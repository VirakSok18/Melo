-- ============================================================
-- Enable Realtime & Policies on liked_songs
-- Run this in Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================

-- 1. Enable REPLICA IDENTITY FULL so DELETE events include all columns
ALTER TABLE public.liked_songs REPLICA IDENTITY FULL;

-- 2. Ensure RLS is enabled
ALTER TABLE public.liked_songs ENABLE ROW LEVEL SECURITY;

-- 3. Ensure full CRUD policies exist (Select, Insert, Update, Delete)
DO $$ 
BEGIN
  -- UPDATE policy (required for upsert / conflict resolution)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'liked_songs' 
      AND policyname = 'Users can update own liked songs'
  ) THEN
    CREATE POLICY "Users can update own liked songs"
      ON public.liked_songs FOR UPDATE USING (auth.uid() = user_id);
  END IF;

  -- INSERT policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'liked_songs' 
      AND policyname = 'Users can insert own liked songs'
  ) THEN
    CREATE POLICY "Users can insert own liked songs"
      ON public.liked_songs FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;

  -- SELECT policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'liked_songs' 
      AND policyname = 'Users can read own liked songs'
  ) THEN
    CREATE POLICY "Users can read own liked songs"
      ON public.liked_songs FOR SELECT USING (auth.uid() = user_id);
  END IF;

  -- DELETE policy
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'liked_songs' 
      AND policyname = 'Users can delete own liked songs'
  ) THEN
    CREATE POLICY "Users can delete own liked songs"
      ON public.liked_songs FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- 4. Add liked_songs to the Supabase Realtime publication
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
      AND schemaname = 'public' 
      AND tablename = 'liked_songs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.liked_songs;
  END IF;
EXCEPTION WHEN OTHERS THEN 
  NULL;
END $$;
