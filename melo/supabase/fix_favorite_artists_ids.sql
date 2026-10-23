-- Update favorite_artists to use Deezer IDs instead of Spotify IDs
-- Run this in Supabase SQL Editor

UPDATE profiles
SET favorite_artists = (
  SELECT jsonb_agg(
    CASE
      WHEN elem->>'name' = 'Drake' THEN jsonb_set(elem, '{id}', '"246791"')
      WHEN elem->>'name' = 'Bruno Mars' THEN jsonb_set(elem, '{id}', '"429675"')
      WHEN elem->>'name' = 'The Weeknd' THEN jsonb_set(elem, '{id}', '"4050205"')
      WHEN elem->>'name' = 'Ariana Grande' THEN jsonb_set(elem, '{id}', '"1562681"')
      WHEN elem->>'name' = 'Billie Eilish' THEN jsonb_set(elem, '{id}', '"9635624"')
      WHEN elem->>'name' = 'Lady Gaga' THEN jsonb_set(elem, '{id}', '"75491"')
      WHEN elem->>'name' = 'Kanye West' THEN jsonb_set(elem, '{id}', '"230"')
      WHEN elem->>'name' = 'SZA' THEN jsonb_set(elem, '{id}', '"5531258"')
      WHEN elem->>'name' = 'Frank Ocean' THEN jsonb_set(elem, '{id}', '"1350335"')
      ELSE elem
    END
  )
  FROM jsonb_array_elements(favorite_artists) AS elem
)
WHERE id = '2535564b-47db-4f4a-82fe-9832a79b086c';
