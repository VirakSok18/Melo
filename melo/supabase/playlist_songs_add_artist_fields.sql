-- Migration: Add artist_id and artist_image columns to playlist_songs table
-- Run this in Supabase SQL Editor

ALTER TABLE playlist_songs
ADD COLUMN IF NOT EXISTS artist_id text DEFAULT '',
ADD COLUMN IF NOT EXISTS artist_image text DEFAULT '';
