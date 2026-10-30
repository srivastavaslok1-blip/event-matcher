# Event Matcher

Meeting the right people at an event should not depend on luck.

Event Matcher is a web app for college events, hackathons and startup meetups. Participants scan a QR code, say what they are looking for and what they can offer, and the app shows the few people actually worth meeting, with the reason for each match. Phone numbers stay hidden until both people say they are interested.

Built by Slok, 2nd-year student at NIT Trichy.

## How it works

1. The organiser creates an event and shares a QR code.
2. Each participant fills a 1-minute profile: role, what they need, what they can offer.
3. The app shows up to 5 best-fit people, with the reasons ("Can help with Web development, which you are looking for").
4. If both people tap "I am interested", they see each other's WhatsApp. Otherwise, nothing is shared.

## Privacy

- No public list of people and no phone numbers visible by default.
- Contact details unlock only on mutual interest.
- Organisers can delete all of an event's data after the event.

## Tech

- Web app: plain HTML, CSS and JavaScript
- Database: Supabase (Postgres) with row-level security. The browser can only call a small set of locked-down functions.
- Hosting: Vercel

## Status

Version 1 is live. Matching uses transparent, rule-based scoring. AI-based ranking is the next step.

## Roadmap

- AI ranking and explanations for matches
- Organiser dashboard
- Piloting at college events

Contact: srivastavaslok1@gmail.com
