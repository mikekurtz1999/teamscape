-- ============================================================
-- TeamScape × Supabase — Full Schema
-- Run this in the Supabase SQL Editor (Project → SQL Editor → New query)
-- ============================================================

-- 1. Extensions
create extension if not exists "uuid-ossp";

-- 2. Custom role enum
do $$ begin
  create type app_role as enum ('at', 'coach', 'sc', 'athlete', 'parent');
exception when duplicate_object then null; end $$;

-- ============================================================
-- 3. Profiles table (linked 1:1 to auth.users)
-- ============================================================
create table if not exists public.profiles (
  id           uuid primary key references auth.users on delete cascade,
  role         text not null default 'athlete',
  athlete_key  text,      -- populated for role = 'athlete'
  athlete_name text,
  athlete_team text,
  created_at   timestamptz default now()
);
-- Add missing columns if table already existed from a prior run
alter table public.profiles add column if not exists athlete_key  text;
alter table public.profiles add column if not exists athlete_name text;
alter table public.profiles add column if not exists athlete_team text;

-- 4. Auth trigger: auto-insert a profile row on every new sign-up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, role, athlete_key, athlete_name, athlete_team)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'athlete'),
    new.raw_user_meta_data->>'athlete_key',
    new.raw_user_meta_data->>'athlete_name',
    new.raw_user_meta_data->>'athlete_team'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 5. Helper functions used by RLS policies
drop function if exists public.my_role() cascade;
drop function if exists public.my_athlete_key() cascade;

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role::text from public.profiles where id = auth.uid()
$$;

create or replace function public.my_athlete_key()
returns text language sql stable security definer set search_path = public as $$
  select athlete_key from public.profiles where id = auth.uid()
$$;

-- ============================================================
-- 6. Data tables
--    All tables use:
--      id text primary key     (for array tables)
--      OR athlete_key primary  (for per-athlete tables)
--      OR id='singleton'       (for singleton tables)
--    Plus a jsonb `data` column that stores the full JS object.
--    This pattern lets the JS layer pass objects through unchanged.
-- ============================================================

-- ---- Array tables (each JS array item = one row) ----

create table if not exists public.encounters (
  id          text primary key,
  athlete_key text,
  data        jsonb not null
);

create table if not exists public.events (
  id   text primary key,
  data jsonb not null
);

create table if not exists public.requests (
  id          text primary key,
  athlete_key text,
  data        jsonb not null
);

create table if not exists public.teams_posts (
  id   text primary key,
  data jsonb not null
);

create table if not exists public.sc_programs (
  id   text primary key,
  data jsonb not null
);

create table if not exists public.sc_logs (
  id   text primary key,
  data jsonb not null
);

create table if not exists public.film_notes (
  id          text primary key,
  athlete_key text,
  data        jsonb not null
);

create table if not exists public.practice_scripts (
  id   text primary key,
  data jsonb not null
);

-- ---- Per-athlete tables (one row per athlete, keyed by athlete_key) ----

create table if not exists public.athletes (
  athlete_key text primary key,
  data        jsonb not null
);

create table if not exists public.restrictions (
  athlete_key text primary key,
  data        jsonb not null
);

create table if not exists public.rehab_plans (
  athlete_key text primary key,
  data        jsonb not null
);

create table if not exists public.daily_checkins (
  athlete_key text primary key,
  data        jsonb not null  -- keyed object: { dateKey: [{dateKey, ratings, note, ts}] }
);

create table if not exists public.wellness_ratings (
  athlete_key text primary key,
  data        jsonb not null  -- keyed object: { dateKey: ratings }
);

create table if not exists public.medical_records (
  athlete_key text primary key,
  data        jsonb not null
);

create table if not exists public.athlete_flags (
  athlete_key text primary key,
  data        jsonb not null
);

create table if not exists public.comm_logs (
  athlete_key text primary key,
  data        jsonb not null  -- array of log entries for this athlete
);

create table if not exists public.rtp_protocols (
  athlete_key text primary key,
  data        jsonb not null
);

create table if not exists public.rehab_settings (
  athlete_key text primary key,
  data        jsonb not null
);

-- ---- Singleton tables (one row per org, id = 'singleton') ----

create table if not exists public.org_settings (
  id   text primary key default 'singleton',
  data jsonb not null default '{}'::jsonb
);

create table if not exists public.at_location (
  id   text primary key default 'singleton',
  data jsonb not null default '{"text":"","updatedAt":null}'::jsonb
);

create table if not exists public.gameday (
  id     text primary key default 'singleton',
  items  jsonb not null default '[]'::jsonb,
  config jsonb not null default '{}'::jsonb
);

create table if not exists public.messages_store (
  id   text primary key default 'singleton',
  data jsonb not null default '{"convs":[]}'::jsonb
);

create table if not exists public.triage_queue (
  id   text primary key default 'singleton',
  data jsonb not null default '[]'::jsonb  -- array of athlete keys
);

create table if not exists public.triage_lists (
  id   text primary key default 'singleton',
  data jsonb not null default '{}'::jsonb
);

create table if not exists public.hidden_coach_events (
  id   text primary key default 'singleton',
  data jsonb not null default '[]'::jsonb  -- array of event IDs hidden by AT
);

-- ============================================================
-- 7. Enable Row Level Security on every table
-- ============================================================
alter table public.profiles           enable row level security;
alter table public.encounters         enable row level security;
alter table public.events             enable row level security;
alter table public.requests           enable row level security;
alter table public.teams_posts        enable row level security;
alter table public.sc_programs        enable row level security;
alter table public.sc_logs            enable row level security;
alter table public.film_notes         enable row level security;
alter table public.practice_scripts   enable row level security;
alter table public.athletes           enable row level security;
alter table public.restrictions       enable row level security;
alter table public.rehab_plans        enable row level security;
alter table public.daily_checkins     enable row level security;
alter table public.wellness_ratings   enable row level security;
alter table public.medical_records    enable row level security;
alter table public.athlete_flags      enable row level security;
alter table public.comm_logs          enable row level security;
alter table public.rtp_protocols      enable row level security;
alter table public.rehab_settings     enable row level security;
alter table public.org_settings       enable row level security;
alter table public.at_location        enable row level security;
alter table public.gameday            enable row level security;
alter table public.messages_store     enable row level security;
alter table public.triage_queue       enable row level security;
alter table public.triage_lists       enable row level security;
alter table public.hidden_coach_events enable row level security;

-- ============================================================
-- 8. RLS Policies
-- ============================================================

-- profiles: users only see their own row
drop policy if exists "Users see own profile"   on public.profiles;
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users see own profile"   on public.profiles for select using (id = auth.uid());
create policy "Users update own profile" on public.profiles for update using (id = auth.uid());

-- encounters: AT full access; athletes see own
drop policy if exists "AT full access to encounters"    on public.encounters;
drop policy if exists "Athletes see own encounters"     on public.encounters;
create policy "AT full access to encounters" on public.encounters
  for all using (public.my_role() = 'at');
create policy "Athletes see own encounters" on public.encounters
  for select using (public.my_role() = 'athlete' and athlete_key = public.my_athlete_key());

-- events: all logged-in users can read; AT/coach/sc can write
drop policy if exists "All users see events"     on public.events;
drop policy if exists "AT/coach/sc manage events" on public.events;
create policy "All users see events" on public.events
  for select using (auth.uid() is not null);
create policy "AT/coach/sc manage events" on public.events
  for all using (public.my_role() in ('at', 'coach', 'sc'));

-- requests: AT full access; athletes manage own; coaches can read
drop policy if exists "AT full access to requests"     on public.requests;
drop policy if exists "Athletes manage own requests"   on public.requests;
drop policy if exists "Coaches see requests"           on public.requests;
create policy "AT full access to requests" on public.requests
  for all using (public.my_role() = 'at');
create policy "Athletes manage own requests" on public.requests
  for all using (public.my_role() = 'athlete' and athlete_key = public.my_athlete_key());
create policy "Coaches see requests" on public.requests
  for select using (public.my_role() = 'coach');

-- teams_posts: all logged-in users can read and post
drop policy if exists "All users manage teams_posts" on public.teams_posts;
create policy "All users manage teams_posts" on public.teams_posts
  for all using (auth.uid() is not null);

-- sc_programs / sc_logs: AT and S&C coach
drop policy if exists "AT/SC access sc_programs" on public.sc_programs;
drop policy if exists "AT/SC access sc_logs"     on public.sc_logs;
create policy "AT/SC access sc_programs" on public.sc_programs
  for all using (public.my_role() in ('at', 'sc'));
create policy "AT/SC access sc_logs" on public.sc_logs
  for all using (public.my_role() in ('at', 'sc'));

-- film_notes / practice_scripts: AT only
drop policy if exists "AT access film_notes"       on public.film_notes;
drop policy if exists "AT access practice_scripts" on public.practice_scripts;
create policy "AT access film_notes" on public.film_notes
  for all using (public.my_role() = 'at');
create policy "AT access practice_scripts" on public.practice_scripts
  for all using (public.my_role() = 'at');

-- athletes roster: AT full; coaches/SC read-only; athletes see own row
drop policy if exists "AT full access to athletes"  on public.athletes;
drop policy if exists "Coach/SC see athletes"       on public.athletes;
drop policy if exists "Athletes see own record"     on public.athletes;
create policy "AT full access to athletes" on public.athletes
  for all using (public.my_role() = 'at');
create policy "Coach/SC see athletes" on public.athletes
  for select using (public.my_role() in ('coach', 'sc'));
create policy "Athletes see own record" on public.athletes
  for select using (public.my_role() = 'athlete' and athlete_key = public.my_athlete_key());

-- restrictions: AT full; coaches/SC read; athletes read own
drop policy if exists "AT full access to restrictions" on public.restrictions;
drop policy if exists "Coach/SC see restrictions"      on public.restrictions;
drop policy if exists "Athletes see own restrictions"  on public.restrictions;
create policy "AT full access to restrictions" on public.restrictions
  for all using (public.my_role() = 'at');
create policy "Coach/SC see restrictions" on public.restrictions
  for select using (public.my_role() in ('coach', 'sc'));
create policy "Athletes see own restrictions" on public.restrictions
  for select using (public.my_role() = 'athlete' and athlete_key = public.my_athlete_key());

-- rehab_plans: AT full; athletes read own
drop policy if exists "AT full access to rehab_plans"  on public.rehab_plans;
drop policy if exists "Athletes see own rehab_plans"   on public.rehab_plans;
create policy "AT full access to rehab_plans" on public.rehab_plans
  for all using (public.my_role() = 'at');
create policy "Athletes see own rehab_plans" on public.rehab_plans
  for select using (public.my_role() = 'athlete' and athlete_key = public.my_athlete_key());

-- daily_checkins: AT full; athletes manage own
drop policy if exists "AT full access to daily_checkins"     on public.daily_checkins;
drop policy if exists "Athletes manage own daily_checkins"   on public.daily_checkins;
create policy "AT full access to daily_checkins" on public.daily_checkins
  for all using (public.my_role() = 'at');
create policy "Athletes manage own daily_checkins" on public.daily_checkins
  for all using (public.my_role() = 'athlete' and athlete_key = public.my_athlete_key());

-- wellness_ratings: AT full; athletes manage own
drop policy if exists "AT full access to wellness_ratings"   on public.wellness_ratings;
drop policy if exists "Athletes manage own wellness_ratings" on public.wellness_ratings;
create policy "AT full access to wellness_ratings" on public.wellness_ratings
  for all using (public.my_role() = 'at');
create policy "Athletes manage own wellness_ratings" on public.wellness_ratings
  for all using (public.my_role() = 'athlete' and athlete_key = public.my_athlete_key());

-- medical_records: AT only (clinical data — no athlete self-access)
drop policy if exists "AT full access to medical_records" on public.medical_records;
create policy "AT full access to medical_records" on public.medical_records
  for all using (public.my_role() = 'at');

-- athlete_flags: AT full; coaches/SC read
drop policy if exists "AT full access to athlete_flags" on public.athlete_flags;
drop policy if exists "Coach/SC see athlete_flags"      on public.athlete_flags;
create policy "AT full access to athlete_flags" on public.athlete_flags
  for all using (public.my_role() = 'at');
create policy "Coach/SC see athlete_flags" on public.athlete_flags
  for select using (public.my_role() in ('coach', 'sc'));

-- comm_logs: AT only (clinical communication notes)
drop policy if exists "AT full access to comm_logs" on public.comm_logs;
create policy "AT full access to comm_logs" on public.comm_logs
  for all using (public.my_role() = 'at');

-- rtp_protocols: AT full; athletes read own
drop policy if exists "AT full access to rtp_protocols" on public.rtp_protocols;
drop policy if exists "Athletes see own rtp_protocols"  on public.rtp_protocols;
create policy "AT full access to rtp_protocols" on public.rtp_protocols
  for all using (public.my_role() = 'at');
create policy "Athletes see own rtp_protocols" on public.rtp_protocols
  for select using (public.my_role() = 'athlete' and athlete_key = public.my_athlete_key());

-- rehab_settings: AT only
drop policy if exists "AT full access to rehab_settings" on public.rehab_settings;
create policy "AT full access to rehab_settings" on public.rehab_settings
  for all using (public.my_role() = 'at');

-- org_settings: AT can write; everyone can read (needed for clinic hours, org name, etc.)
drop policy if exists "AT manages org_settings"    on public.org_settings;
drop policy if exists "All users read org_settings" on public.org_settings;
create policy "AT manages org_settings" on public.org_settings
  for all using (public.my_role() = 'at');
create policy "All users read org_settings" on public.org_settings
  for select using (auth.uid() is not null);

-- at_location: AT writes; everyone reads
drop policy if exists "AT manages at_location"    on public.at_location;
drop policy if exists "All users read at_location" on public.at_location;
create policy "AT manages at_location" on public.at_location
  for all using (public.my_role() = 'at');
create policy "All users read at_location" on public.at_location
  for select using (auth.uid() is not null);

-- gameday: AT writes; everyone reads
drop policy if exists "AT manages gameday"    on public.gameday;
drop policy if exists "All users read gameday" on public.gameday;
create policy "AT manages gameday" on public.gameday
  for all using (public.my_role() = 'at');
create policy "All users read gameday" on public.gameday
  for select using (auth.uid() is not null);

-- messages: all logged-in users
drop policy if exists "All users manage messages" on public.messages_store;
create policy "All users manage messages" on public.messages_store
  for all using (auth.uid() is not null);

-- triage: AT only
drop policy if exists "AT manages triage_queue" on public.triage_queue;
drop policy if exists "AT manages triage_lists" on public.triage_lists;
create policy "AT manages triage_queue" on public.triage_queue
  for all using (public.my_role() = 'at');
create policy "AT manages triage_lists" on public.triage_lists
  for all using (public.my_role() = 'at');

-- hidden_coach_events: AT only
drop policy if exists "AT manages hidden_coach_events" on public.hidden_coach_events;
create policy "AT manages hidden_coach_events" on public.hidden_coach_events
  for all using (public.my_role() = 'at');

-- ============================================================
-- 9. Seed data — demo athletes & singleton defaults
--    NOTE: User accounts (for login) must be created separately
--    in the Supabase Auth dashboard or via the CLI.
--    See .env.example for demo account details.
-- ============================================================

insert into public.athletes (athlete_key, data) values
  ('jsmith',    '{"key":"jsmith","name":"J. Smith","age":17,"height":"6''0\"","weight":"185 lb","phone":"(555) 201-8841","email":"jsmith@school.edu","team":"Varsity Football","sport":"Football","gradYear":2026,"active":true,"triageFlag":true,"availability":"Limited Participant","currentInjury":"R ankle sprain (Grade I)"}'),
  ('amiller',   '{"key":"amiller","name":"A. Miller","age":16,"height":"5''7\"","weight":"142 lb","phone":"(555) 201-3374","email":"amiller@school.edu","team":"Varsity Soccer","sport":"Soccer","gradYear":2027,"active":true,"triageFlag":false,"availability":"Full Participant","currentInjury":""}'),
  ('bnguyen',   '{"key":"bnguyen","name":"B. Nguyen","age":18,"height":"5''10\"","weight":"155 lb","phone":"(555) 201-5529","email":"bnguyen@school.edu","team":"Track & Field","sport":"Track","gradYear":2025,"active":true,"triageFlag":false,"availability":"Return-to-Play","currentInjury":"Hamstring strain (Phase 3 RTP)"}'),
  ('ckeller',   '{"key":"ckeller","name":"C. Keller","age":17,"height":"5''11\"","weight":"168 lb","phone":"(555) 201-4432","email":"ckeller@school.edu","team":"Baseball","sport":"Baseball","gradYear":2026,"active":true,"triageFlag":false,"availability":"Testing","currentInjury":"Shoulder soreness (throwing program)"}'),
  ('dthompson', '{"key":"dthompson","name":"D. Thompson","age":19,"height":"6''4\"","weight":"240 lb","phone":"(555) 201-9902","email":"dthompson@college.edu","team":"Football","sport":"Football","gradYear":2024,"active":true,"triageFlag":true,"availability":"Out","currentInjury":"Concussion (RTL progression)"}'),
  ('emartin',   '{"key":"emartin","name":"E. Martin","age":15,"height":"5''3\"","weight":"118 lb","phone":"(555) 201-6621","email":"emartin@school.edu","team":"Softball","sport":"Softball","gradYear":2028,"active":true,"triageFlag":false,"availability":"Limited Participant","currentInjury":"Wrist sprain (brace)"}')
on conflict (athlete_key) do nothing;

-- Singleton defaults
insert into public.org_settings (id, data) values
  ('singleton', '{"start":"07:00","end":"18:00","slotMin":15,"maxDur":120,"dur":{"eval":45,"follow":20,"rehab":30,"treatment":15},"reasons":[{"type":"eval","label":"Initial Evaluation","minutes":45},{"type":"follow","label":"Follow-up","minutes":20},{"type":"rehab","label":"Rehab Session","minutes":30},{"type":"treatment","label":"Treatment","minutes":15}],"treatments":[{"name":"Ice","minutes":15},{"name":"Heat","minutes":15},{"name":"E-stim","minutes":20},{"name":"Ultrasound","minutes":15}],"templates":{},"allowCheckin":true,"allowAsyncCheckin":true,"shareAtLocation":true,"preWindow":{"start":"14:00","end":"15:00"},"postWindow":{"start":"17:00","end":"18:00"},"defaultQueueSort":"workflow","org":{"name":"TeamScape Demo","venue":"Main Athletic Complex"},"orgTheme":{"mode":"system","accent":"#0b5fff"},"emr":{"enabled":false}}')
on conflict (id) do nothing;

insert into public.at_location   (id, data)         values ('singleton', '{"text":"","updatedAt":null}') on conflict (id) do nothing;
insert into public.gameday       (id, items, config) values ('singleton', '[]', '{}')                     on conflict (id) do nothing;
insert into public.messages_store(id, data)          values ('singleton', '{"convs":[]}')                 on conflict (id) do nothing;
insert into public.triage_queue  (id, data)          values ('singleton', '[]')                           on conflict (id) do nothing;
insert into public.triage_lists  (id, data)          values ('singleton', '{}')                           on conflict (id) do nothing;
insert into public.hidden_coach_events(id, data)     values ('singleton', '[]')                           on conflict (id) do nothing;

-- ============================================================
-- Done! Next steps:
-- 1. Create demo user accounts in Supabase Auth (Authentication → Users → Invite)
--    at@demo.com      password: demo123  metadata: {"role":"at"}
--    coach@demo.com   password: demo123  metadata: {"role":"coach"}
--    sc@demo.com      password: demo123  metadata: {"role":"sc"}
--    athlete@demo.com password: demo123  metadata: {"role":"athlete","athlete_key":"jsmith","athlete_name":"J. Smith","athlete_team":"Varsity Football"}
-- 2. Copy your Supabase Project URL and anon key into TeamScape_V1.7.htm
--    (search for SUPABASE_URL and SUPABASE_ANON_KEY)
-- 3. Deploy the scan-ppe Edge Function (see supabase/functions/scan-ppe/index.ts)
--    supabase functions deploy scan-ppe
--    supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
-- ============================================================
