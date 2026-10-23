-- ============================================================
-- MELO: Password Reset Stored Procedure
-- Run this in Supabase Dashboard -> SQL Editor -> New Query -> Run
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION reset_user_password(user_email text, new_password text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Find user by email
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE lower(trim(email)) = lower(trim(user_email));

  IF v_user_id IS NULL THEN
    RETURN false;
  END IF;

  -- Update encrypted password using bcrypt
  UPDATE auth.users
  SET encrypted_password = crypt(new_password, gen_salt('bf')),
      updated_at = now()
  WHERE id = v_user_id;

  RETURN true;
END;
$$;
