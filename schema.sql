-- Event Matcher database. Run ONCE in Supabase: SQL Editor > New query > paste all > Run.
-- Safe to run again: it only creates things that are missing and replaces the functions.

create extension if not exists pgcrypto;

create table if not exists events (
  code text primary key,
  name text not null,
  created_at timestamptz default now()
);

create table if not exists profiles (
  id uuid primary key default gen_random_uuid(),
  event_code text not null references events(code) on delete cascade,
  name text not null,
  college text,
  role text not null,
  intent text[] not null default '{}',
  need_skills text[] not null default '{}',
  offer_skills text[] not null default '{}',
  looking_text text,
  offer_text text,
  project text,
  link text,
  whatsapp text not null,
  created_at timestamptz default now()
);

create table if not exists interests (
  from_id uuid not null references profiles(id) on delete cascade,
  to_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (from_id, to_id)
);

create table if not exists admin_secret (key text primary key);

-- Lock every table. With no policies, the public key cannot read or write them directly.
-- The app talks to the database only through the functions below.
alter table events enable row level security;
alter table profiles enable row level security;
alter table interests enable row level security;
alter table admin_secret enable row level security;

-- Look up an event by its code.
create or replace function get_event(p_code text)
returns table(code text, name text)
language sql security definer set search_path = public as $$
  select e.code, e.name from events e where lower(e.code) = lower(trim(p_code));
$$;

-- Join an event. Returns the new secret profile id.
create or replace function join_event(
  p_code text, p_name text, p_college text, p_role text,
  p_intent text[], p_need text[], p_offer text[],
  p_looking_text text, p_offer_text text, p_project text, p_link text, p_whatsapp text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_code text; v_id uuid;
begin
  select e.code into v_code from events e where lower(e.code) = lower(trim(p_code));
  if v_code is null then raise exception 'Unknown event code'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'Name is required'; end if;
  if length(regexp_replace(coalesce(p_whatsapp,''), '\D', '', 'g')) < 10 then raise exception 'Valid WhatsApp number is required'; end if;
  insert into profiles(event_code, name, college, role, intent, need_skills, offer_skills,
                       looking_text, offer_text, project, link, whatsapp)
  values (v_code, left(trim(p_name),80), left(p_college,120), p_role, coalesce(p_intent,'{}'),
          coalesce(p_need,'{}'), coalesce(p_offer,'{}'), left(p_looking_text,300), left(p_offer_text,300),
          left(p_project,300), left(p_link,300), regexp_replace(p_whatsapp, '\D', '', 'g'))
  returning id into v_id;
  return v_id;
end $$;

-- Return my own profile.
create or replace function get_me(p_me uuid)
returns table(id uuid, event_code text, event_name text, name text, college text, role text,
              intent text[], need_skills text[], offer_skills text[],
              looking_text text, offer_text text, project text, link text)
language sql security definer set search_path = public as $$
  select p.id, p.event_code, e.name, p.name, p.college, p.role, p.intent, p.need_skills, p.offer_skills,
         p.looking_text, p.offer_text, p.project, p.link
  from profiles p join events e on e.code = p.event_code where p.id = p_me;
$$;

-- Return the other people at my event. Phone numbers are never included.
create or replace function list_candidates(p_me uuid)
returns table(id uuid, name text, college text, role text, intent text[], need_skills text[],
              offer_skills text[], looking_text text, offer_text text, project text, link text)
language sql security definer set search_path = public as $$
  select o.id, o.name, o.college, o.role, o.intent, o.need_skills, o.offer_skills,
         o.looking_text, o.offer_text, o.project, o.link
  from profiles me join profiles o on o.event_code = me.event_code and o.id <> me.id
  where me.id = p_me
  order by o.created_at desc
  limit 300;
$$;

-- Say "I'm interested" in someone at the same event.
create or replace function express_interest(p_me uuid, p_to uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from profiles a join profiles b on a.event_code = b.event_code
                 where a.id = p_me and b.id = p_to and a.id <> b.id) then
    raise exception 'Not allowed';
  end if;
  insert into interests(from_id, to_id) values (p_me, p_to) on conflict do nothing;
end $$;

-- Who have I already said yes to.
create or replace function my_interests(p_me uuid)
returns table(to_id uuid)
language sql security definer set search_path = public as $$
  select i.to_id from interests i where i.from_id = p_me;
$$;

-- People who said yes to me AND I said yes to. Only these people's WhatsApp numbers are shown.
create or replace function get_mutuals(p_me uuid)
returns table(id uuid, name text, college text, role text, whatsapp text, link text)
language sql security definer set search_path = public as $$
  select o.id, o.name, o.college, o.role, o.whatsapp, o.link
  from interests a
  join interests b on b.from_id = a.to_id and b.to_id = a.from_id
  join profiles o on o.id = a.to_id
  where a.from_id = p_me;
$$;

-- Admin functions. They need the admin key you set at the bottom of this file.
create or replace function admin_check(p_key text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from admin_secret s where s.key = p_key);
$$;

create or replace function admin_create_event(p_key text, p_code text, p_name text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_key) then raise exception 'Wrong admin key'; end if;
  insert into events(code, name) values (trim(p_code), trim(p_name))
  on conflict (code) do update set name = excluded.name;
end $$;

create or replace function admin_overview(p_key text, p_event text)
returns json
language plpgsql security definer set search_path = public as $$
declare v_profiles int; v_interests int; v_mutual int; v_recent json;
begin
  if not admin_check(p_key) then raise exception 'Wrong admin key'; end if;
  select count(*) into v_profiles from profiles where lower(event_code) = lower(trim(p_event));
  select count(*) into v_interests from interests i join profiles p on p.id = i.from_id
    where lower(p.event_code) = lower(trim(p_event));
  select count(*) into v_mutual from interests a
    join interests b on a.from_id = b.to_id and a.to_id = b.from_id
    join profiles pa on pa.id = a.from_id
    where a.from_id < a.to_id and lower(pa.event_code) = lower(trim(p_event));
  select coalesce(json_agg(r), '[]'::json) into v_recent from (
    select name, college, role, created_at from profiles
    where lower(event_code) = lower(trim(p_event)) order by created_at desc limit 15) r;
  return json_build_object('profiles', v_profiles, 'interests', v_interests,
                           'mutual', v_mutual, 'recent', v_recent);
end $$;

create or replace function admin_delete_event_data(p_key text, p_event text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_key) then raise exception 'Wrong admin key'; end if;
  delete from profiles where lower(event_code) = lower(trim(p_event));
end $$;

-- Only the public (anon) key may call these functions.
revoke all on function get_event(text), join_event(text,text,text,text,text[],text[],text[],text,text,text,text,text),
  get_me(uuid), list_candidates(uuid), express_interest(uuid,uuid), my_interests(uuid), get_mutuals(uuid),
  admin_create_event(text,text,text), admin_overview(text,text), admin_delete_event_data(text,text)
  from public;
revoke all on function admin_check(text) from public, anon, authenticated;

grant execute on function get_event(text), join_event(text,text,text,text,text[],text[],text[],text,text,text,text,text),
  get_me(uuid), list_candidates(uuid), express_interest(uuid,uuid), my_interests(uuid), get_mutuals(uuid),
  admin_create_event(text,text,text), admin_overview(text,text), admin_delete_event_data(text,text)
  to anon, authenticated;

-- ======================================================================
-- LAST STEP: set your admin key. Change the text between the quotes to a long
-- password only you know, then run just this line. Never share it.
-- ======================================================================
insert into admin_secret(key) values ('CHANGE-THIS-TO-A-LONG-PASSWORD')
on conflict do nothing;
