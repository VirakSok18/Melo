-- Enable Realtime on profile_follows so user receives follow notifications instantly
ALTER TABLE profile_follows REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE profile_follows;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
