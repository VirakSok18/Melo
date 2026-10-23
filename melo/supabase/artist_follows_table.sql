CREATE TABLE IF NOT EXISTS artist_follows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  artist_id TEXT NOT NULL,
  artist_name TEXT NOT NULL,
  artist_image TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, artist_id)
);

ALTER TABLE artist_follows ENABLE ROW LEVEL SECURITY;

-- Everyone can read follows
CREATE POLICY "Anyone can read artist follows"
  ON artist_follows FOR SELECT
  USING (true);

-- Users can only insert their own follows
CREATE POLICY "Users can insert own follows"
  ON artist_follows FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can only delete their own follows
CREATE POLICY "Users can delete own follows"
  ON artist_follows FOR DELETE
  USING (auth.uid() = user_id);

-- Index for fast lookups
CREATE INDEX idx_artist_follows_user_id ON artist_follows(user_id);
CREATE INDEX idx_artist_follows_artist_id ON artist_follows(artist_id);
CREATE INDEX idx_artist_follows_user_artist ON artist_follows(user_id, artist_id);
