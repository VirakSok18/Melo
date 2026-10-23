-- User Playlists: user-created playlists synced across devices
CREATE TABLE IF NOT EXISTS user_playlists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  cover_image TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Playlist Songs: songs inside each playlist
CREATE TABLE IF NOT EXISTS playlist_songs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  playlist_id UUID REFERENCES user_playlists(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  track_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  image TEXT DEFAULT '',
  duration TEXT DEFAULT '',
  position INT NOT NULL DEFAULT 0,
  added_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(playlist_id, track_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_playlists_user ON user_playlists(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_playlist_songs_playlist ON playlist_songs(playlist_id, position);

-- RLS
ALTER TABLE user_playlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE playlist_songs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own playlists"
  ON user_playlists FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own playlists"
  ON user_playlists FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own playlists"
  ON user_playlists FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own playlists"
  ON user_playlists FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can read own playlist songs"
  ON playlist_songs FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own playlist songs"
  ON playlist_songs FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own playlist songs"
  ON playlist_songs FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own playlist songs"
  ON playlist_songs FOR DELETE USING (auth.uid() = user_id);
