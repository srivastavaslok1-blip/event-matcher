# Event Matcher: setup guide (about 90 minutes, no coding)

What you get: a real website where people at an event scan a QR code, say what they are looking for, see the few people worth meeting (with the reasons), and swap WhatsApp numbers only when both say yes.

Files in this folder:

| File | What it is |
|---|---|
| `index.html` | The app people use |
| `admin.html` | Your private page: create events, see live numbers, delete data |
| `match.js` | The matching rules |
| `config.js` | The only file you edit (two values) |
| `schema.sql` | The database, pasted into Supabase once |

## Step 1. Create the database (20 min)

1. Go to supabase.com and sign up with GitHub or email.
2. Click **New project**. Name it `event-matcher`. Choose a region near India (Mumbai if shown). Save the database password somewhere.
3. Wait about 2 minutes until the project is ready.
4. Open **SQL Editor** in the left menu, then **New query**.
5. Open `schema.sql`, find the last lines, and change `CHANGE-THIS-TO-A-LONG-PASSWORD` to a long password only you know. Write it down: this is your admin key.
6. Copy the whole file, paste it into the query box and click **Run**. You should see "Success. No rows returned".

## Step 2. Connect the app to the database (5 min)

1. In Supabase open **Project Settings**, then **API** (the page may be called **API Keys** or **Data API**).
2. Copy the **Project URL** (looks like `https://abcd1234.supabase.co`).
3. Copy the **public key**: the one called `anon` or `publishable`. Never copy the `service_role` or `secret` key.
4. Open `config.js` in any text editor (Notes works) and paste both values between the quotes. Save.

## Step 3. Put it on the internet (25 min)

1. Create a GitHub account if you do not have one. Click **New repository**, name it `event-matcher`, keep it Public, and create it.
2. Click **uploading an existing file**, drag in all five files from this folder, and click **Commit changes**.
3. Go to vercel.com and sign up with GitHub. Click **Add New**, then **Project**, pick `event-matcher`, and click **Deploy**. Leave all settings alone.
4. In about a minute you get a link like `https://event-matcher-xyz.vercel.app`. This is your live website.

If Vercel gives trouble, use GitHub Pages instead: in your repository open **Settings**, then **Pages**, set Source to `main` branch and root folder, and save. Your link appears after a few minutes.

## Step 4. Create your first event (5 min)

1. Open `YOUR-LINK/admin.html`.
2. Type your admin key, an event code (for example `DEMO`) and an event name (for example `NIT Trichy Builders Meetup`).
3. Click **Create or rename event**. It shows the link people should open: `YOUR-LINK/?event=DEMO`.
4. Make a QR code for that link at qrcode-monkey.com. Put it on a slide or poster.

## Step 5. Test it before anyone sees it (30 min)

1. Open the event link on your phone. Fill the form as yourself.
2. Ask two friends to open the link on their own phones and join with different answers.
3. You should see each other as matches with the reasons. Tap **I am interested** on both phones. The Connections tab then shows a WhatsApp button.
4. Open `admin.html` and click **Show live numbers**. You should see 3 people.
5. Before the real event, use **Delete this event's people** so the demo data is gone.

## Two-day plan

**Day 1**
1. Steps 1 to 4 above (about 90 minutes).
2. Step 5 with 3 friends (30 minutes). Write down anything confusing.
3. Ask 15 to 25 friends or hostel mates to join a test event with your demo code. More people means better demo matches.
4. Fix wording or small issues with me. Bring me any error message or screenshot.
5. Record a 60-second screen video: scan QR, fill form, see matches, tap interested, mutual WhatsApp.

**Day 2**
1. Run a real mini event or session with 10 to 20 people. Even a hostel wing or a club meeting counts.
2. Collect a quick rating from each person (1 to 5: "was your list useful?") and one line you may quote.
3. Open the admin page and note: people joined, interests sent, mutual matches.
4. Write a one-page summary for the chairman: the problem, the live link, your real numbers, what you learned and the next step.

## What to tell the chairman

Say it plainly:

- "It is a working web app. Here is the live link and a video of it in use."
- "Version 1 matches with clear rules and shows the reason for every match. AI-written reasons and ranking are the next step."
- "This is how many people used it, and what they said." (Use real numbers only.)
- "The next steps are one real event with an organiser, then the AI layer."

## Honest limits of this version

- No logins. Your phone remembers you through your browser. If someone clears their browser data, they join again.
- Anyone with an event code can join that event. Pick codes that are not easy to guess for real events.
- Matching is rule-based. It is explainable and fast, but it is not AI yet.
- Supabase free projects pause after 7 days without activity. Open your Supabase project before a demo.
- Vercel's free plan is meant for personal, non-commercial use. It is fine for a pilot.
- Keep your admin key private. The `anon` key in `config.js` is public by design: the database only answers through the functions in `schema.sql`.
- Tell people what you store (consent text is on the form) and delete event data after the event with the admin button.

## If something breaks

| What you see | What to do |
|---|---|
| "Almost there" screen | `config.js` still has the placeholder values. Paste your real URL and public key. |
| "Unknown event code" | Create the event on the admin page first. |
| "Wrong admin key" | The key must match what you put at the end of `schema.sql`. Run `update admin_secret set key = 'new-key';` in the SQL Editor to change it. |
| Blank page | Open the link in Chrome, press F12, open Console, and send me the red text. |
| Works on laptop, not on phone | Check that the phone has internet and that you opened the exact link, including `?event=CODE`. |
