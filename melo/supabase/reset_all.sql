-- ============================================================
-- FULL DATABASE RESET — Wipes ALL Melo data, tables & accounts
-- Run this once in the Supabase SQL Editor:
-- Dashboard -> SQL Editor -> New query -> Paste & Run
-- ============================================================

-- 1. Truncate all application data tables (CASCADE handles foreign keys)
TRUNCATE TABLE
  public.playlist_songs,
  public.playlist_collaborators,
  public.user_playlists,
  public.liked_songs,
  public.downloaded_songs,
  public.listening_history,
  public.daily_playlists,
  public.daily_new_releases,
  public.user_taste_profiles,
  public.artist_follows,
  public.profile_follows,
  public.user_subscriptions,
  public.profiles
CASCADE;

-- 2. Delete all Auth users, sessions, identities & OAuth tokens
DELETE FROM auth.users;

-- ============================================================
-- SUCCESS: Your database is now 100% clean and fresh!
-- Note for Avatars: If you want to clear stored avatar image files:
-- Go to Supabase Dashboard -> Storage -> avatars -> select all & delete.
-- ============================================================