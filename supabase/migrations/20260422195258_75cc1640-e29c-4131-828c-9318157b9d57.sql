CREATE OR REPLACE FUNCTION public.wa_normalize_phone(raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s text;
  d text;
  ddd text;
  rest text;
BEGIN
  IF raw IS NULL OR raw = '' THEN RETURN ''; END IF;
  s := split_part(raw, '@', 1);
  d := regexp_replace(s, '\D', '', 'g');
  IF d = '' THEN RETURN ''; END IF;
  IF length(d) > 14 THEN RETURN ''; END IF;
  IF left(d, 2) = '00' THEN d := substring(d from 3); END IF;
  IF length(d) = 12 AND left(d, 2) = '55' THEN
    ddd := substring(d from 3 for 2);
    rest := substring(d from 5);
    IF rest ~ '^[6-8]' THEN
      d := '55' || ddd || '9' || rest;
    END IF;
  END IF;
  IF length(d) BETWEEN 12 AND 14 THEN RETURN d; END IF;
  IF length(d) IN (10, 11) THEN RETURN '55' || d; END IF;
  RETURN d;
END;
$$;

WITH bad_messages AS (
  SELECT id,
    '55' || substring(phone_normalized from 3 for 2) || substring(phone_normalized from 6) AS fixed
  FROM public.whatsapp_messages
  WHERE length(phone_normalized) = 13
    AND left(phone_normalized, 2) = '55'
    AND substring(phone_normalized from 5 for 1) = '9'
    AND substring(phone_normalized from 6 for 1) = '9'
)
UPDATE public.whatsapp_messages m
SET phone_normalized = b.fixed
FROM bad_messages b
WHERE m.id = b.id;

WITH bad_leads AS (
  SELECT id,
    '55' || substring(phone_normalized from 3 for 2) || substring(phone_normalized from 6) AS fixed
  FROM public.whatsapp_leads
  WHERE length(phone_normalized) = 13
    AND left(phone_normalized, 2) = '55'
    AND substring(phone_normalized from 5 for 1) = '9'
    AND substring(phone_normalized from 6 for 1) = '9'
)
UPDATE public.whatsapp_leads l
SET phone_normalized = b.fixed
FROM bad_leads b
WHERE l.id = b.id;