-- =========================================================
-- MELO MASTER SUPABASE SETUP SCRIPT (1-CLICK EXECUTION)
-- Run this in your new Supabase Project -> SQL Editor
-- =========================================================

-- 1. PROFILES TABLE & AUTH TRIGGER
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE,
  display_name TEXT,
  profile_setup_completed BOOLEAN DEFAULT FALSE,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Profiles are viewable by everyone" ON public.profiles;
CREATE POLICY "Profiles are viewable by everyone" ON public.profiles FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- 2. USER SUBSCRIPTIONS (Unlocked for all)
CREATE TABLE IF NOT EXISTS public.user_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id TEXT NOT NULL DEFAULT 'lifetime_free',
  plan_name TEXT NOT NULL DEFAULT 'Melo Free Lifetime',
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_subscriptions_user_id_key UNIQUE (user_id)
);

ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own subscription" ON public.user_subscriptions;
CREATE POLICY "Users can view own subscription" ON public.user_subscriptions FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert/update own subscription" ON public.user_subscriptions;
CREATE POLICY "Users can insert/update own subscription" ON public.user_subscriptions FOR ALL USING (auth.uid() = user_id);

-- 3. LIKED SONGS
CREATE TABLE IF NOT EXISTS public.liked_songs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  artist_id TEXT,
  artist_image TEXT,
  image TEXT DEFAULT '',
  genre TEXT DEFAULT '',
  duration_ms INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, track_id)
);

ALTER TABLE public.liked_songs REPLICA IDENTITY FULL;
ALTER TABLE public.liked_songs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own liked songs" ON public.liked_songs;
CREATE POLICY "Users can read own liked songs" ON public.liked_songs FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own liked songs" ON public.liked_songs;
CREATE POLICY "Users can insert own liked songs" ON public.liked_songs FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own liked songs" ON public.liked_songs;
CREATE POLICY "Users can update own liked songs" ON public.liked_songs FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own liked songs" ON public.liked_songs;
CREATE POLICY "Users can delete own liked songs" ON public.liked_songs FOR DELETE USING (auth.uid() = user_id);

-- 4. DOWNLOADED SONGS
CREATE TABLE IF NOT EXISTS public.downloaded_songs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  song_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  artist_id TEXT,
  artist_image TEXT,
  artwork_url TEXT DEFAULT '',
  audio_url TEXT DEFAULT '',
  downloaded_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, song_id)
);

ALTER TABLE public.downloaded_songs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own downloaded songs" ON public.downloaded_songs;
CREATE POLICY "Users can read own downloaded songs" ON public.downloaded_songs FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own downloaded songs" ON public.downloaded_songs;
CREATE POLICY "Users can insert own downloaded songs" ON public.downloaded_songs FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own downloaded songs" ON public.downloaded_songs;
CREATE POLICY "Users can delete own downloaded songs" ON public.downloaded_songs FOR DELETE USING (auth.uid() = user_id);

-- 5. ARTIST FOLLOWS
CREATE TABLE IF NOT EXISTS public.artist_follows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  artist_id TEXT NOT NULL,
  artist_name TEXT NOT NULL,
  artist_image TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, artist_id)
);

ALTER TABLE public.artist_follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own artist follows" ON public.artist_follows;
CREATE POLICY "Users can read own artist follows" ON public.artist_follows FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage own artist follows" ON public.artist_follows;
CREATE POLICY "Users can manage own artist follows" ON public.artist_follows FOR ALL USING (auth.uid() = user_id);

-- 6. PROFILE FOLLOWS
CREATE TABLE IF NOT EXISTS public.profile_follows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  following_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(follower_id, following_id)
);

ALTER TABLE public.profile_follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view profile follows" ON public.profile_follows;
CREATE POLICY "Public can view profile follows" ON public.profile_follows FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage own profile follows" ON public.profile_follows;
CREATE POLICY "Users can manage own profile follows" ON public.profile_follows FOR ALL USING (auth.uid() = follower_id);

-- 7. USER PLAYLISTS & PLAYLIST SONGS
CREATE TABLE IF NOT EXISTS public.user_playlists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT DEFAULT '',
  cover_url TEXT DEFAULT '',
  is_public BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.user_playlists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Playlists are viewable by everyone" ON public.user_playlists;
CREATE POLICY "Playlists are viewable by everyone" ON public.user_playlists FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage own playlists" ON public.user_playlists;
CREATE POLICY "Users can manage own playlists" ON public.user_playlists FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.playlist_songs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  playlist_id UUID REFERENCES public.user_playlists(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  artist_id TEXT,
  artist_image TEXT,
  image TEXT DEFAULT '',
  duration_ms INT DEFAULT 0,
  added_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(playlist_id, track_id)
);

ALTER TABLE public.playlist_songs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Playlist songs viewable by everyone" ON public.playlist_songs;
CREATE POLICY "Playlist songs viewable by everyone" ON public.playlist_songs FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can manage songs in playlists" ON public.playlist_songs;
CREATE POLICY "Users can manage songs in playlists" ON public.playlist_songs FOR ALL USING (true);

-- 8. PLAYLIST COLLABORATORS
CREATE TABLE IF NOT EXISTS public.playlist_collaborators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  playlist_id UUID REFERENCES public.user_playlists(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'editor',
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(playlist_id, user_id)
);

ALTER TABLE public.playlist_collaborators ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view collaborators" ON public.playlist_collaborators;
CREATE POLICY "Public can view collaborators" ON public.playlist_collaborators FOR SELECT USING (true);

DROP POLICY IF EXISTS "Manage collaborators" ON public.playlist_collaborators;
CREATE POLICY "Manage collaborators" ON public.playlist_collaborators FOR ALL USING (true);

-- 9. LISTENING HISTORY & VIBE TABLES
CREATE TABLE IF NOT EXISTS public.listening_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  artist_id TEXT,
  artist_image TEXT,
  image TEXT DEFAULT '',
  genre TEXT DEFAULT '',
  skipped BOOLEAN DEFAULT FALSE,
  completed BOOLEAN DEFAULT FALSE,
  replayed BOOLEAN DEFAULT FALSE,
  listen_duration INT DEFAULT 0,
  source TEXT DEFAULT 'vibe',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.listening_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own listening history" ON public.listening_history;
CREATE POLICY "Users can read own listening history" ON public.listening_history FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own listening history" ON public.listening_history;
CREATE POLICY "Users can insert own listening history" ON public.listening_history FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.daily_playlists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  genre TEXT NOT NULL,
  playlist_number INT NOT NULL DEFAULT 1,
  playlist_date DATE DEFAULT CURRENT_DATE,
  songs JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, genre, playlist_date, playlist_number)
);

ALTER TABLE public.daily_playlists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own daily playlists" ON public.daily_playlists;
CREATE POLICY "Users can manage own daily playlists" ON public.daily_playlists FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.user_taste_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  genre TEXT NOT NULL,
  liked_artists JSONB DEFAULT '[]'::jsonb,
  liked_songs JSONB DEFAULT '[]'::jsonb,
  disliked_artists JSONB DEFAULT '[]'::jsonb,
  disliked_songs JSONB DEFAULT '[]'::jsonb,
  recommend_more JSONB DEFAULT '[]'::jsonb,
  recommend_less JSONB DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, genre)
);

ALTER TABLE public.user_taste_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own taste profile" ON public.user_taste_profiles;
CREATE POLICY "Users can manage own taste profile" ON public.user_taste_profiles FOR ALL USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.daily_new_releases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  genre TEXT NOT NULL,
  release_date DATE DEFAULT CURRENT_DATE,
  songs JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(genre, release_date)
);

ALTER TABLE public.daily_new_releases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view daily new releases" ON public.daily_new_releases;
CREATE POLICY "Public can view daily new releases" ON public.daily_new_releases FOR SELECT USING (true);

-- 10. ENABLE REALTIME
ALTER PUBLICATION supabase_realtime ADD TABLE public.liked_songs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.profile_follows;
ALTER PUBLICATION supabase_realtime ADD TABLE public.playlist_songs;
