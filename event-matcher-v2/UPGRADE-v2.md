# Event Matcher v2: upgrade guide (about 40 minutes)

## What's new

- **AI matching.** Google Gemini reads what everyone wrote and picks your best 5, with a "% fit", a one-line reason and a suggested first line to start the conversation. If the AI is off or busy, the app quietly falls back to the old rules.
- **Live alerts.** Banner, sound, vibration, and a phone notification when the page is in the background. They fire when a good match joins, when someone is interested in you, when it's mutual, and when a connection waves.
- **Find them in the room.** Connections can see "Black hoodie, near the stage" and send a wave: "I am coming to you", "Where are you?", and so on.
- **Organiser dashboard** (`admin.html`). Each event gets its own organiser password, and organisers see only their event. The dashboard shows live numbers, a joins timeline, skills wanted vs offered (with a "short supply" insight), who came and what they want, a CSV attendee list (no phone numbers), and a printable PDF report.
- **Live wall** (`wall.html?event=CODE`). A projector screen with a big QR code, live counters, "just joined" and the most wanted skills.

## Files to upload (do NOT upload config.js or README.md)

`index.html`, `admin.html`, `wall.html`, `match.js`, `schema.sql`, `schema_v2.sql`, the `api` folder (with `ai-match.js` inside), and `UPGRADE-v2.md`.

Your `config.js` on GitHub already has your real keys. The one in this zip doesn't exist on purpose, so you can't overwrite it by mistake.

## Step 1. Upgrade the database (5 min)

1. In Supabase, go to **SQL Editor → New query**.
2. Paste all of `schema_v2.sql` and click **Run**. You should see "Success". Your existing events, people and connections are kept.

## Step 2. Get a free Gemini API key (10 min)

1. Go to **aistudio.google.com** and sign in with Google.
2. Click **Get API key → Create API key**. Copy it and keep it private, like a password.
3. On AI Studio's **rate limit** page, check which models your free tier allows. The app uses `gemini-flash-latest` by default. If that model isn't listed, note the name of a Flash model that is.

Note: on the free tier, Google may use the requests to improve its products. That's why the app only sends people's answers to the AI, never names or phone numbers, and the consent text on the join form says so.

## Step 3. Add the keys to Vercel (5 min)

Vercel → your project → **Settings → Environment Variables**. Add each of these (keep all environments ticked) and click **Save**:

| Name | Value |
|---|---|
| `GEMINI_API_KEY` | the key from Step 2 |
| `SUPABASE_URL` | the same URL as in your config.js |
| `SUPABASE_ANON_KEY` | the same `sb_publishable_...` key as in your config.js |
| `GEMINI_MODEL` | optional. Only add it if Step 2 showed `gemini-flash-latest` isn't available, and use the model name you noted. |

## Step 4. Upload the new files to GitHub (10 min)

1. Open your `event-matcher` repository → **Add file → Upload files**.
2. Drag in the files from the list above, **including the `api` folder** (drag the folder itself, not just the file inside).
3. Click **Commit changes**. Vercel redeploys automatically in about a minute.

## Step 5. Create a real event with an organiser password (3 min)

1. Open `YOUR-LINK/admin.html` and open **Master admin** at the bottom.
2. Enter your master admin key. Fill in the event code, name, tagline and an organiser password (8 or more characters), then click **Create or update event**.
3. Give the organiser the event code and the organiser password. They sign in at the top of the same page.
4. Click **Open live wall** from the dashboard, and put it on a projector or TV.

## Step 6. Test (10 min)

1. Join on two phones with matching answers.
2. On each phone you should see "AI picked..." with a % fit and "Start with:". If you see "Why you two:" instead, the AI isn't working yet (see below).
3. Turn on live alerts on phone 1, then join from phone 2. Phone 1 should show "New match just joined" within about 15 seconds.
4. Tap interested on both phones, set "where are you" on one, and wave from the other.

## If something breaks

| What you see | What to do |
|---|---|
| "Why you two" instead of AI picks | Check the Vercel environment variables, then redeploy: **Deployments → ⋯ → Redeploy**. Then open **Logs** in Vercel and look for "ai-match failed". |
| Logs say the model is not found | Add `GEMINI_MODEL` with a model name from AI Studio, then redeploy. |
| Logs say quota or 429 | You hit the free limit. The app keeps working with rules, and the limits reset daily. |
| "Wrong key for this event" | Use the organiser password for that event, or your master key. |
| No phone notifications | iPhones only allow them for apps added to the home screen. Banners, sound and vibration inside the page still work. |

## Honest limits

- Alerts work while the page is open, including in the background on Android Chrome. They are not true push notifications when the browser is closed.
- The AI is limited per person (at most once every 40 seconds) and per event (1,500 calls a day), so the free quota lasts.
- No photos yet. "Find them" uses text.
