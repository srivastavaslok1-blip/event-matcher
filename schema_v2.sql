-- Event Matcher v2 upgrade.
-- Run this AFTER schema.sql (which you already ran). Supabase: SQL Editor > New query > paste all > Run.
-- Safe to run again. It keeps all existing events, people and connections.

-- ---------- new columns and tables ----------
alter table events   add column if not exists tagline text;
alter table events   add column if not exists org_key text;          -- password for this event's organiser
alter table profiles add column if not exists spot_text text;        -- "Blue hoodie, near the stage"
alter table profiles add column if not exists spot_at timestamptz;
alter table profiles add column if not exists last_seen timestamptz;

create table if not exists waves (
  id bigserial primary key,
  from_id uuid not null references profiles(id) on delete cascade,
  to_id uuid not null references profiles(id) on delete cascade,
  note text,
  created_at timestamptz default now()
);

create table if not exists ai_state (
  profile_id uuid primary key references profiles(id) on delete cascade,
  sig text,
  result jsonb,
  updated_at timestamptz,
  last_call timestamptz
);

create table if not exists ai_usage (
  day date not null,
  event_code text not null,
  calls int not null default 0,
  primary key (day, event_code)
);

create index if not exists profiles_event_idx on profiles(event_code);
create index if not exists interests_to_idx on interests(to_id);
create index if not exists waves_to_idx on waves(to_id, created_at desc);

alter table waves    enable row level security;
alter table ai_state enable row level security;
alter table ai_usage enable row level security;

-- Remove the example admin key if it was ever saved by accident.
delete from admin_secret where key like 'CHANGE-THIS%';

-- ---------- internal helpers (not callable from the browser) ----------
create or replace function org_check(p_key text, p_event text) returns boolean
language sql security definer set search_path = public as $$
  select coalesce(p_key, '') <> '' and (
    exists (select 1 from admin_secret s where s.key = p_key)
    or exists (select 1 from events e where lower(e.code) = lower(trim(p_event)) and e.org_key = p_key));
$$;

create or replace function is_mutual(a uuid, b uuid) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from interests where from_id = a and to_id = b)
     and exists (select 1 from interests where from_id = b and to_id = a);
$$;

-- ---------- participant functions ----------
drop function if exists get_event(text);
create function get_event(p_code text)
returns table(code text, name text, tagline text)
language sql security definer set search_path = public as $$
  select e.code, e.name, e.tagline from events e where lower(e.code) = lower(trim(p_code));
$$;

drop function if exists get_me(uuid);
create function get_me(p_me uuid)
returns table(id uuid, event_code text, event_name text, name text, college text, role text,
              intent text[], need_skills text[], offer_skills text[],
              looking_text text, offer_text text, project text, link text, spot_text text)
language sql security definer set search_path = public as $$
  select p.id, p.event_code, e.name, p.name, p.college, p.role, p.intent, p.need_skills, p.offer_skills,
         p.looking_text, p.offer_text, p.project, p.link, p.spot_text
  from profiles p join events e on e.code = p.event_code where p.id = p_me;
$$;

-- Everything the app needs in one call: people here, my interests, connections, waves, alerts.
create or replace function sync(p_me uuid) returns json
language plpgsql security definer set search_path = public as $$
declare v_event text;
begin
  update profiles set last_seen = now() where id = p_me returning event_code into v_event;
  if v_event is null then raise exception 'Profile not found'; end if;
  return json_build_object(
    'cands', (select coalesce(json_agg(c), '[]'::json) from (
        select o.id, o.name, o.college, o.role, o.intent, o.need_skills, o.offer_skills,
               o.looking_text, o.offer_text, o.project, o.link, o.created_at
        from profiles o where o.event_code = v_event and o.id <> p_me
        order by o.created_at desc limit 300) c),
    'sent', (select coalesce(json_agg(i.to_id), '[]'::json) from interests i where i.from_id = p_me),
    'mutuals', (select coalesce(json_agg(m), '[]'::json) from (
        select o.id, o.name, o.college, o.role, o.whatsapp, o.link, o.spot_text, o.spot_at
        from interests a
        join interests b on b.from_id = a.to_id and b.to_id = a.from_id
        join profiles o on o.id = a.to_id
        where a.from_id = p_me order by b.created_at desc) m),
    'waves', (select coalesce(json_agg(w), '[]'::json) from (
        select w.id, w.from_id, p.name as from_name, w.note, w.created_at
        from waves w join profiles p on p.id = w.from_id
        where w.to_id = p_me order by w.created_at desc limit 20) w),
    'incoming', (select count(*) from interests i where i.to_id = p_me
                   and not exists (select 1 from interests j where j.from_id = p_me and j.to_id = i.from_id))
  );
end $$;

-- Tell your connections how to find you in the room.
create or replace function update_spot(p_me uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update profiles set spot_text = nullif(left(trim(coalesce(p_text, '')), 120), ''), spot_at = now() where id = p_me;
  if not found then raise exception 'Profile not found'; end if;
end $$;

-- Wave at a connection (only allowed when the interest is mutual).
create or replace function send_wave(p_me uuid, p_to uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_mutual(p_me, p_to) then raise exception 'You can only wave at your connections'; end if;
  if exists (select 1 from waves where from_id = p_me and to_id = p_to and created_at > now() - interval '15 seconds') then
    raise exception 'Wait a few seconds before waving again';
  end if;
  insert into waves(from_id, to_id, note) values (p_me, p_to, left(trim(coalesce(p_note, '')), 120));
end $$;

-- AI matching bookkeeping, used by the /api/ai-match server function.
-- Gives back a cached answer when nothing changed, and limits how often each person can trigger the AI.
create or replace function ai_begin(p_me uuid, p_sig text) returns json
language plpgsql security definer set search_path = public as $$
declare s ai_state%rowtype; v_event text; v_calls int;
begin
  select event_code into v_event from profiles where id = p_me;
  if v_event is null then raise exception 'Profile not found'; end if;
  select * into s from ai_state where profile_id = p_me;
  if found and s.sig = p_sig and s.result is not null and s.updated_at > now() - interval '30 minutes' then
    return json_build_object('status', 'cached', 'result', s.result);
  end if;
  if found and s.last_call > now() - interval '40 seconds' then
    return json_build_object('status', 'throttled', 'result', s.result);
  end if;
  insert into ai_usage(day, event_code, calls) values (current_date, v_event, 1)
  on conflict (day, event_code) do update set calls = ai_usage.calls + 1
  returning calls into v_calls;
  if v_calls > 1500 then return json_build_object('status', 'capped', 'result', s.result); end if;
  insert into ai_state(profile_id, last_call) values (p_me, now())
  on conflict (profile_id) do update set last_call = now();
  return json_build_object('status', 'go');
end $$;

create or replace function ai_save(p_me uuid, p_sig text, p_result jsonb) returns void
language sql security definer set search_path = public as $$
  update ai_state set sig = p_sig, result = p_result, updated_at = now() where profile_id = p_me;
$$;

-- Public numbers for the big-screen wall. No names, no phone numbers.
create or replace function event_wall(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare v_code text; v_name text; v_tag text;
begin
  select code, name, tagline into v_code, v_name, v_tag from events where lower(code) = lower(trim(p_code));
  if v_code is null then raise exception 'Unknown event code'; end if;
  return json_build_object(
    'code', v_code, 'name', v_name, 'tagline', v_tag,
    'people', (select count(*) from profiles where event_code = v_code),
    'connections', (select count(*) from interests a join interests b on a.from_id = b.to_id and a.to_id = b.from_id
                    join profiles p on p.id = a.from_id where a.from_id < a.to_id and p.event_code = v_code),
    'waves', (select count(*) from waves w join profiles p on p.id = w.from_id where p.event_code = v_code),
    'wanted', (select coalesce(json_agg(x), '[]'::json) from (
        select s as skill, count(*) as n from profiles, unnest(need_skills) s
        where event_code = v_code group by s order by n desc limit 5) x),
    'recent', (select coalesce(json_agg(r), '[]'::json) from (
        select role, college, created_at from profiles where event_code = v_code
        order by created_at desc limit 6) r));
end $$;

-- ---------- organiser and admin functions ----------
-- Master admin key: creates events and gives each organiser their own event password.
drop function if exists admin_create_event(text, text, text);
create or replace function admin_create_event(p_key text, p_code text, p_name text, p_tagline text, p_org_key text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_key) then raise exception 'Wrong admin key'; end if;
  if trim(coalesce(p_code, '')) !~ '^[A-Za-z0-9-]{2,30}$' then
    raise exception 'Event code: 2-30 letters, numbers or dashes, no spaces';
  end if;
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'Event name is required'; end if;
  if length(trim(coalesce(p_org_key, ''))) between 1 and 7 then
    raise exception 'Organiser password must be at least 8 characters';
  end if;
  insert into events(code, name, tagline, org_key)
  values (trim(p_code), trim(p_name), nullif(trim(coalesce(p_tagline, '')), ''), nullif(trim(coalesce(p_org_key, '')), ''))
  on conflict (code) do update set
    name = excluded.name,
    tagline = excluded.tagline,
    org_key = coalesce(excluded.org_key, events.org_key);
end $$;

create or replace function admin_list_events(p_key text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_key) then raise exception 'Wrong admin key'; end if;
  return (select coalesce(json_agg(e), '[]'::json) from (
    select ev.code, ev.name, ev.created_at, (ev.org_key is not null) as has_org_key,
           (select count(*) from profiles p where p.event_code = ev.code) as people
    from events ev order by ev.created_at desc) e);
end $$;

-- Works with the master key OR that event's organiser password.
create or replace function admin_overview(p_key text, p_event text) returns json
language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if not org_check(p_key, p_event) then raise exception 'Wrong key for this event'; end if;
  select code into v_code from events where lower(code) = lower(trim(p_event));
  if v_code is null then raise exception 'Unknown event code'; end if;
  return json_build_object(
    'event', (select json_build_object('code', code, 'name', name, 'tagline', tagline) from events where code = v_code),
    'profiles', (select count(*) from profiles where event_code = v_code),
    'active_now', (select count(*) from profiles where event_code = v_code and last_seen > now() - interval '5 minutes'),
    'interests', (select count(*) from interests i join profiles p on p.id = i.from_id where p.event_code = v_code),
    'mutual', (select count(*) from interests a join interests b on a.from_id = b.to_id and a.to_id = b.from_id
               join profiles p on p.id = a.from_id where a.from_id < a.to_id and p.event_code = v_code),
    'connected_people', (select count(distinct a.from_id) from interests a
               join interests b on a.from_id = b.to_id and a.to_id = b.from_id
               join profiles p on p.id = a.from_id where p.event_code = v_code),
    'waves', (select count(*) from waves w join profiles p on p.id = w.from_id where p.event_code = v_code),
    'ai_served', (select count(*) from ai_state s join profiles p on p.id = s.profile_id
                  where p.event_code = v_code and s.result is not null),
    'timeline', (select coalesce(json_agg(t order by t.bucket), '[]'::json) from (
        select date_bin('15 minutes', created_at, timestamptz '2000-01-01') as bucket, count(*) as n
        from profiles where event_code = v_code group by 1 order by 1 desc limit 48) t),
    'roles', (select coalesce(json_agg(r), '[]'::json) from (
        select role as label, count(*) as n from profiles where event_code = v_code group by role order by n desc) r),
    'intents', (select coalesce(json_agg(x), '[]'::json) from (
        select s as label, count(*) as n from profiles, unnest(intent) s where event_code = v_code
        group by s order by n desc) x),
    'needs', (select coalesce(json_agg(x), '[]'::json) from (
        select s as label, count(*) as n from profiles, unnest(need_skills) s where event_code = v_code
        group by s order by n desc) x),
    'offers', (select coalesce(json_agg(x), '[]'::json) from (
        select s as label, count(*) as n from profiles, unnest(offer_skills) s where event_code = v_code
        group by s order by n desc) x),
    'recent', (select coalesce(json_agg(r), '[]'::json) from (
        select name, college, role, created_at from profiles where event_code = v_code
        order by created_at desc limit 15) r));
end $$;

-- Attendee list for the organiser (no phone numbers).
create or replace function admin_export(p_key text, p_event text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if not org_check(p_key, p_event) then raise exception 'Wrong key for this event'; end if;
  return (select coalesce(json_agg(x), '[]'::json) from (
    select p.name, p.college, p.role, array_to_string(p.intent, '; ') as wants,
           array_to_string(p.need_skills, '; ') as needs, array_to_string(p.offer_skills, '; ') as offers,
           p.link, p.created_at as joined_at,
           (select count(*) from interests a join interests b on b.from_id = a.to_id and b.to_id = a.from_id
            where a.from_id = p.id) as connections
    from profiles p where lower(p.event_code) = lower(trim(p_event)) order by p.created_at) x);
end $$;

drop function if exists admin_delete_event_data(text, text);
create function admin_delete_event_data(p_key text, p_event text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not org_check(p_key, p_event) then raise exception 'Wrong key for this event'; end if;
  delete from profiles where lower(event_code) = lower(trim(p_event));
end $$;

-- ---------- permissions ----------
revoke all on function org_check(text, text), is_mutual(uuid, uuid) from public, anon, authenticated;

revoke all on function get_event(text), get_me(uuid), sync(uuid), update_spot(uuid, text),
  send_wave(uuid, uuid, text), ai_begin(uuid, text), ai_save(uuid, text, jsonb), event_wall(text),
  admin_create_event(text, text, text, text, text), admin_list_events(text), admin_overview(text, text),
  admin_export(text, text), admin_delete_event_data(text, text)
  from public;

grant execute on function get_event(text), get_me(uuid), sync(uuid), update_spot(uuid, text),
  send_wave(uuid, uuid, text), ai_begin(uuid, text), ai_save(uuid, text, jsonb), event_wall(text),
  admin_create_event(text, text, text, text, text), admin_list_events(text), admin_overview(text, text),
  admin_export(text, text), admin_delete_event_data(text, text)
  to anon, authenticated;
