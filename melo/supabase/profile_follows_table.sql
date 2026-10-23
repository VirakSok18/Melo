-- User-to-user follows. follower_id follows following_id.
-- Followers of a user = rows where following_id = that user.
CREATE TABLE IF NOT EXISTS profile_follows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  following_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(follower_id, following_id),
  CHECK (follower_id <> following_id)
);

ALTER TABLE profile_follows ENABLE ROW LEVEL SECURITY;

-- Everyone can read follows (needed to show follower counts publicly)
CREATE POLICY "Anyone can read profile follows"
  ON profile_follows FOR SELECT
  USING (true);

-- Users can only insert their own follows
CREATE POLICY "Users can insert own follows"
  ON profile_follows FOR INSERT
  WITH CHECK (auth.uid() = follower_id);

-- Users can only delete their own follows
CREATE POLICY "Users can delete own follows"
  ON profile_follows FOR DELETE
  USING (auth.uid() = follower_id);

-- Indexes for fast follower/following counts
CREATE INDEX idx_profile_follows_follower_id ON profile_follows(follower_id);
CREATE INDEX idx_profile_follows_following_id ON profile_follows(following_id);
CREATE INDEX idx_profile_follows_pair ON profile_follows(follower_id, following_id);