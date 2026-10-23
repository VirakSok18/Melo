CREATE TABLE IF NOT EXISTS downloaded_songs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) NOT NULL,
  track_id TEXT NOT NULL,
  title TEXT NOT NULL,
  artist TEXT NOT NULL,
  image TEXT DEFAULT '',
  file_size BIGINT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, track_id)
);

ALTER TABLE downloaded_songs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Everyone can read" ON downloaded_songs
  FOR SELECT USING (true);

CREATE POLICY "Users can insert own" ON downloaded_songs
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own" ON downloaded_songs
  FOR DELETE USING (auth.uid() = user_id);
