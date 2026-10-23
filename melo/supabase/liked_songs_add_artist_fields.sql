-- Migration: Add artist_id and artist_image columns to liked_songs table
-- Run this in Supabase SQL Editor

ALTER TABLE liked_songs
ADD COLUMN IF NOT EXISTS artist_id text DEFAULT '',
ADD COLUMN IF NOT EXISTS artist_image text DEFAULT '';
