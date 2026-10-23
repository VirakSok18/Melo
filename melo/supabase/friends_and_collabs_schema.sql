-- 1. Ensure profile_follows table exists with appropriate constraints and RLS
CREATE TABLE IF NOT EXISTS profile_follows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(follower_id, following_id),
  CHECK (follower_id <> following_id)
);

ALTER TABLE profile_follows ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'profile_follows' AND policyname = 'Anyone can read profile follows') THEN
    CREATE POLICY "Anyone can read profile follows" ON profile_follows FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'profile_follows' AND policyname = 'Users can insert own follows') THEN
    CREATE POLICY "Users can insert own follows" ON profile_follows FOR INSERT WITH CHECK (auth.uid() = follower_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'profile_follows' AND policyname = 'Users can delete own follows') THEN
    CREATE POLICY "Users can delete own follows" ON profile_follows FOR DELETE USING (auth.uid() = follower_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profile_follows_follower_id ON profile_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_profile_follows_following_id ON profile_follows(following_id);
CREATE INDEX IF NOT EXISTS idx_profile_follows_pair ON profile_follows(follower_id, following_id);

-- 2. Enhance user_playlists for collaboration
ALTER TABLE user_playlists ADD COLUMN IF NOT EXISTS is_collaborative BOOLEAN DEFAULT false;
ALTER TABLE user_playlists ADD COLUMN IF NOT EXISTS is_public BOOLEAN DEFAULT true;

-- 3. Collaborative playlist members table
CREATE TABLE IF NOT EXISTS playlist_collaborators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  playlist_id UUID NOT NULL REFERENCES user_playlists(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'editor', -- 'owner', 'editor', 'viewer'
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(playlist_id, user_id)
);

ALTER TABLE playlist_collaborators ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'playlist_collaborators' AND policyname = 'Anyone can read collaborators') THEN
    CREATE POLICY "Anyone can read collaborators" ON playlist_collaborators FOR SELECT USING (true);
  END IF;
  
  DROP POLICY IF EXISTS "Owners and editors can join" ON playlist_collaborators;
  CREATE POLICY "Owners and editors can join" ON playlist_collaborators FOR INSERT WITH CHECK (
    auth.uid() = user_id OR 
    EXISTS (SELECT 1 FROM user_playlists WHERE id = playlist_collaborators.playlist_id AND user_id = auth.uid())
  );
  
  DROP POLICY IF EXISTS "Users can leave or owner remove" ON playlist_collaborators;
  CREATE POLICY "Users can leave or owner remove" ON playlist_collaborators FOR DELETE USING (
    auth.uid() = user_id OR 
    EXISTS (SELECT 1 FROM user_playlists WHERE id = playlist_collaborators.playlist_id AND user_id = auth.uid())
  );

  DROP POLICY IF EXISTS "Users can update own collaborator status" ON playlist_collaborators;
  CREATE POLICY "Users can update own collaborator status" ON playlist_collaborators FOR UPDATE USING (
    auth.uid() = user_id OR 
    EXISTS (SELECT 1 FROM user_playlists WHERE id = playlist_collaborators.playlist_id AND user_id = auth.uid())
  );
END $$;

CREATE INDEX IF NOT EXISTS idx_playlist_collaborators_playlist ON playlist_collaborators(playlist_id);
CREATE INDEX IF NOT EXISTS idx_playlist_collaborators_user ON playlist_collaborators(user_id);

-- 4. Track attribution in playlist_songs
ALTER TABLE playlist_songs ADD COLUMN IF NOT EXISTS added_by_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE playlist_songs ADD COLUMN IF NOT EXISTS added_by_name TEXT DEFAULT '';
ALTER TABLE playlist_songs ADD COLUMN IF NOT EXISTS added_by_avatar TEXT DEFAULT '';

-- 5. user_playlists RLS policies for collaboration
DO $$ BEGIN
  DROP POLICY IF EXISTS "Users can read own and collaborative playlists" ON user_playlists;
  CREATE POLICY "Users can read own and collaborative playlists" ON user_playlists FOR SELECT USING (
    auth.uid() = user_id OR
    is_collaborative = true OR
    EXISTS (SELECT 1 FROM playlist_collaborators WHERE playlist_id = user_playlists.id AND user_id = auth.uid())
  );

  DROP POLICY IF EXISTS "Users can update own and collaborative playlists" ON user_playlists;
  DROP POLICY IF EXISTS "Users can update own playlists" ON user_playlists;
  CREATE POLICY "Users can update own and collaborative playlists" ON user_playlists FOR UPDATE USING (
    auth.uid() = user_id OR
    is_collaborative = true OR
    EXISTS (SELECT 1 FROM playlist_collaborators WHERE playlist_id = user_playlists.id AND user_id = auth.uid())
  );

  DROP POLICY IF EXISTS "Collaborators can read playlist songs" ON playlist_songs;
  CREATE POLICY "Collaborators can read playlist songs" ON playlist_songs FOR SELECT USING (true);

  DROP POLICY IF EXISTS "Collaborators can insert playlist songs" ON playlist_songs;
  CREATE POLICY "Collaborators can insert playlist songs" ON playlist_songs FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_playlists WHERE id = playlist_songs.playlist_id AND (
        user_id = auth.uid() OR
        is_collaborative = true OR
        EXISTS (SELECT 1 FROM playlist_collaborators WHERE playlist_id = playlist_songs.playlist_id AND user_id = auth.uid())
      )
    )
  );

  DROP POLICY IF EXISTS "Collaborators can delete playlist songs" ON playlist_songs;
  CREATE POLICY "Collaborators can delete playlist songs" ON playlist_songs FOR DELETE USING (
    auth.uid() = user_id OR
    EXISTS (
      SELECT 1 FROM user_playlists WHERE id = playlist_songs.playlist_id AND (
        user_id = auth.uid() OR
        is_collaborative = true OR
        EXISTS (SELECT 1 FROM playlist_collaborators WHERE playlist_id = playlist_songs.playlist_id AND user_id = auth.uid())
      )
    )
  );

  DROP POLICY IF EXISTS "Collaborators can update playlist songs" ON playlist_songs;
  CREATE POLICY "Collaborators can update playlist songs" ON playlist_songs FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM user_playlists WHERE id = playlist_songs.playlist_id AND (
        user_id = auth.uid() OR
        is_collaborative = true OR
        EXISTS (SELECT 1 FROM playlist_collaborators WHERE playlist_id = playlist_songs.playlist_id AND user_id = auth.uid())
      )
    )
  );
END $$;

-- 6. Realtime broadcasts & full replica identity for live playlist updates
ALTER TABLE playlist_songs REPLICA IDENTITY FULL;
ALTER TABLE playlist_collaborators REPLICA IDENTITY FULL;
ALTER TABLE user_playlists REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE playlist_songs;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE playlist_collaborators;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE user_playlists;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 7. Ensure storage bucket 'avatars' exists and is publicly accessible
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', true, 10485760, ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/gif'])
ON CONFLICT (id) DO UPDATE SET public = true;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Public Access to Avatars') THEN
    CREATE POLICY "Public Access to Avatars" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Authenticated Upload to Avatars') THEN
    CREATE POLICY "Authenticated Upload to Avatars" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage' AND policyname = 'Authenticated Update to Avatars') THEN
    CREATE POLICY "Authenticated Update to Avatars" ON storage.objects FOR UPDATE USING (bucket_id = 'avatars' AND auth.role() = 'authenticated');
  END IF;
END $$;

