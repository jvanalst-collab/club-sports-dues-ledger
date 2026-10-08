# Dues Ledger (no-sign-in version)

A static site (no build step) that stores its data in Supabase. Anyone with the
link and the shared passcode can view and edit. Nobody needs a Claude, Supabase,
or Vercel account to use it.

## Files

- `index.html` — the app
- `config.js` — where your Supabase URL and anon key go
- `supabase-setup.sql` — creates the tables, the passcode check, and the three starting trips
- `vendor/` — the Supabase client library (v2.45.4), bundled so the site loads nothing from a CDN except fonts

## Setup

1. **Supabase.** Create a new project (or reuse one). Open the SQL editor, paste in
   `supabase-setup.sql`, change `CHANGE-THIS-PASSCODE` to the passcode you want, and run it.
   Use a long passcode (four or more random words). The passcode is the only thing
   protecting the data.
2. **config.js.** From the project's API settings, copy the Project URL and the
   anon (publishable) key into `config.js`.
3. **Vercel.** Deploy this folder as a static site (framework preset "Other", no
   build command, output directory = this folder). For example, run `vercel` from
   inside the folder, or push it to a Git repo and import the repo.
4. Open the deployed URL, enter the passcode, and send the URL and passcode to the captains.

## How access works

- The two tables have row level security on with no policies, so the anon key in
  `config.js` cannot read or write them directly.
- All reads and writes go through three database functions (`ledger_get`,
  `ledger_put`, `ledger_del`). Each checks the passcode against a bcrypt hash
  stored in the database before doing anything.
- Each browser remembers the passcode after the first entry. "Lock" forgets it on that device.
- To change the passcode, edit and re-run the last `insert into public.ledger_meta` statement
  in the SQL file. Everyone is asked for the new one on their next refresh.

## How "live" works

Each open page asks the database every 4 seconds whether anything changed and
reloads the data if so. A change made on one device shows on the others within a
few seconds. If two people edit the same trip or cost category at the same moment,
the last save wins.

## Limits to know about

- Anyone who has both the link and the passcode can change or delete anything. There is no per-person login and no edit history.
- Take a backup now and then: in Supabase, export the `ledger_docs` table.
