-- Fix: Flutter upserts daily_playlists with
--   onConflict = user_id,genre,playlist_date
-- but the table only has the 4-column UNIQUE
--   (user_id, genre, playlist_date, playlist_number)
-- so Postgres rejects it with 42P10 "no unique or exclusion constraint".
--
-- Run once in Supabase SQL Editor. Adding this constraint makes the app's
-- upsert target valid regardless of which shape the table currently has.

ALTER TABLE public.daily_playlists
  ADD CONSTRAINT daily_playlists_user_genre_date_key
  UNIQUE (user_id, genre, playlist_date);

-- If that fails with "could not create unique constraint" you have duplicate
-- (user_id, genre, playlist_date) rows from before; clean them first:
--   DELETE FROM public.daily_playlists a
--   USING public.daily_playlists b
--   WHERE a.id > b.id
--     AND a.user_id = b.user_id
--     AND a.genre = b.genre
--     AND a.playlist_date = b.playlist_date;
-- then re-run the ALTER TABLE above.
