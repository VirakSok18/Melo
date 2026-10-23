-- Listening History: tracks every song interaction across the app
CREATE TABLE IF NOT EXISTS listening_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  image TEXT DEFAULT '',
  genre TEXT DEFAULT '',
  skipped BOOLEAN DEFAULT FALSE,
  completed BOOLEAN DEFAULT FALSE,
  replayed BOOLEAN DEFAULT FALSE,
  listen_duration INT DEFAULT 0,
  source TEXT DEFAULT 'vibe',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast queries per user + genre
CREATE INDEX IF NOT EXISTS idx_listening_history_user_genre
  ON listening_history(user_id, genre, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_listening_history_user_created
  ON listening_history(user_id, created_at DESC);

-- Daily Playlists: generated per user per genre per day
CREATE TABLE IF NOT EXISTS daily_playlists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  genre TEXT NOT NULL,
  playlist_number INT NOT NULL DEFAULT 1,
  playlist_date DATE DEFAULT CURRENT_DATE,
  songs JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, genre, playlist_date, playlist_number)
);

-- User Taste Profile: summarizes learned preferences
CREATE TABLE IF NOT EXISTS user_taste_profiles (
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

-- RLS policies
ALTER TABLE listening_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_taste_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own listening history"
  ON listening_history FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own listening history"
  ON listening_history FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own listening history"
  ON listening_history FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own listening history"
  ON listening_history FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can read own daily playlists"
  ON daily_playlists FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own daily playlists"
  ON daily_playlists FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own daily playlists"
  ON daily_playlists FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can read own taste profiles"
  ON user_taste_profiles FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own taste profiles"
  ON user_taste_profiles FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own taste profiles"
  ON user_taste_profiles FOR UPDATE USING (auth.uid() = user_id);

-- Daily New Releases: personalized new songs, refreshed daily
CREATE TABLE IF NOT EXISTS daily_new_releases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  release_date DATE DEFAULT CURRENT_DATE,
  songs JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, release_date)
);

ALTER TABLE daily_new_releases ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own new releases"
  ON daily_new_releases FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own new releases"
  ON daily_new_releases FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own new releases"
  ON daily_new_releases FOR UPDATE USING (auth.uid() = user_id);

-- Liked Songs: songs the user has hearted/liked
CREATE TABLE IF NOT EXISTS liked_songs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  image TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, track_id)
);

ALTER TABLE liked_songs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own liked songs"
  ON liked_songs FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own liked songs"
  ON liked_songs FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own liked songs"
  ON liked_songs FOR DELETE USING (auth.uid() = user_id);
