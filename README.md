# Cup of Time

A simple TODO app built with Flutter. Tasks are stored locally with
[Drift](https://drift.simonbinder.eu/) (SQLite) and synced to a
[Supabase](https://supabase.com/) `tasks` table whenever a network connection
is available, including live updates via Supabase Realtime.

## Setup

1. Install Flutter dependencies:
   ```sh
   flutter pub get
   ```
2. Create a Supabase project, then run this in its SQL editor:
   ```sql
   create table tasks (
     id uuid primary key default gen_random_uuid(),
     name text not null,
     done boolean not null default false,
     updated_at timestamptz not null default now()
   );

   alter table tasks enable row level security;
   create policy "Allow anon full access" on tasks
     for all using (true) with check (true);

   alter publication supabase_realtime add table tasks;
   ```
3. Copy `.env.example` to `.env` and fill in your project's URL and
   publishable (anon) key, found under Settings > API in the Supabase
   dashboard:
   ```sh
   cp .env.example .env
   ```
4. Run the app:
   ```sh
   flutter run
   ```

## Platforms

Targets Android, iOS, and macOS (the latter for local development/testing).

## Architecture

- `lib/database/` — Drift schema and local persistence (`AppDatabase`).
- `lib/sync/` — `SyncService`: pushes/pulls local changes to Supabase, plus a
  Realtime subscription for server-initiated changes.
- `lib/config/` — reads Supabase connection details from the environment
  (loaded from `.env` via `flutter_dotenv`).
