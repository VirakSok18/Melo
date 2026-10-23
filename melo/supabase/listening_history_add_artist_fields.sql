-- Migration: Add artist_id and artist_image columns to listening_history table
-- Run this in Supabase SQL Editor

ALTER TABLE listening_history
ADD COLUMN IF NOT EXISTS artist_id text DEFAULT '',
ADD COLUMN IF NOT EXISTS artist_image text DEFAULT '';
