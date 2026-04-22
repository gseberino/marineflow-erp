-- Helper functions
CREATE OR REPLACE FUNCTION public.wa_normalize_phone(raw text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
DECLARE s text; d text; ddd text; rest text;
BEGIN
  IF raw IS NULL OR raw = '' THEN RETURN ''; END IF;
  s := split_part(raw, '@', 1);
  d := regexp_replace(s, '\D', '', 'g');
  IF d = '' THEN RETURN ''; END IF;
  IF length(d) > 14 THEN RETURN ''; END IF;
  IF left(d, 2) = '00' THEN d := substr(d, 3); END IF;
  IF length(d) = 12 AND left(d, 2) = '55' THEN
    ddd := substr(d, 3, 2);
    rest := substr(d, 5);
    IF length(rest) = 8 AND left(rest, 1) ~ '[6-9]' THEN
      d := '55' || ddd || '9' || rest;
    END IF;
  END IF;
  IF length(d) BETWEEN 12 AND 14 THEN RETURN d; END IF;
  IF length(d) IN (10, 11) THEN RETURN '55' || d; END IF;
  RETURN d;
END;
$$;

-- Returns body as text, message_type as text via composite (scalar function for easy UPDATE)
CREATE OR REPLACE FUNCTION public.wa_extract_body_text(p jsonb)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p IS NULL THEN RETURN '[mensagem não reconhecida]'; END IF;
  IF jsonb_typeof(p->'text') = 'string' THEN RETURN p->>'text'; END IF;
  IF p->'text'->>'message' IS NOT NULL THEN RETURN p->'text'->>'message'; END IF;
  IF jsonb_typeof(p->'message') = 'string' THEN RETURN p->>'message'; END IF;
  IF p->'message'->>'conversation' IS NOT NULL THEN RETURN p->'message'->>'conversation'; END IF;
  IF p->'message'->'extendedTextMessage'->>'text' IS NOT NULL THEN RETURN p->'message'->'extendedTextMessage'->>'text'; END IF;
  IF p->>'body' IS NOT NULL THEN RETURN p->>'body'; END IF;
  IF p->>'caption' IS NOT NULL THEN RETURN p->>'caption'; END IF;
  IF p ? 'image' THEN RETURN COALESCE(p->'image'->>'caption', '[imagem]'); END IF;
  IF p ? 'audio' THEN RETURN '[áudio]'; END IF;
  IF p ? 'video' THEN RETURN COALESCE(p->'video'->>'caption', '[vídeo]'); END IF;
  IF p ? 'document' THEN RETURN COALESCE(p->'document'->>'caption', '[documento] ' || COALESCE(p->'document'->>'fileName', '')); END IF;
  IF p ? 'sticker' THEN RETURN '[sticker]'; END IF;
  IF p ? 'reaction' THEN RETURN '[reação] ' || COALESCE(p->'reaction'->>'value', ''); END IF;
  IF p ? 'poll' OR p ? 'pollCreation' THEN RETURN '[enquete]'; END IF;
  IF p ? 'listResponseMessage' OR p->'message' ? 'listResponseMessage' THEN RETURN COALESCE(p->'listResponseMessage'->'singleSelectReply'->>'selectedRowId', '[resposta de lista]'); END IF;
  IF p ? 'buttonsResponseMessage' OR p->'message' ? 'buttonsResponseMessage' THEN RETURN COALESCE(p->'buttonsResponseMessage'->>'selectedDisplayText', '[resposta de botão]'); END IF;
  IF p ? 'location' THEN RETURN '[localização] ' || COALESCE(p->'location'->>'latitude', '') || ',' || COALESCE(p->'location'->>'longitude', ''); END IF;
  IF p ? 'contact' OR p ? 'contacts' OR p ? 'contactsArrayMessage' THEN RETURN '[contato] ' || COALESCE(p->'contact'->>'displayName', ''); END IF;
  RETURN '[mensagem não reconhecida]';
END;
$$;

CREATE OR REPLACE FUNCTION public.wa_extract_message_type(p jsonb)
RETURNS text
LANGUAGE plpgsql IMMUTABLE
SET search_path = public
AS $$
BEGIN
  IF p IS NULL THEN RETURN 'other'; END IF;
  IF jsonb_typeof(p->'text') = 'string' OR p->'text'->>'message' IS NOT NULL
     OR jsonb_typeof(p->'message') = 'string' OR p->'message'->>'conversation' IS NOT NULL
     OR p->'message'->'extendedTextMessage'->>'text' IS NOT NULL
     OR p->>'body' IS NOT NULL OR p->>'caption' IS NOT NULL THEN RETURN 'text'; END IF;
  IF p ? 'image' THEN RETURN 'image'; END IF;
  IF p ? 'audio' THEN RETURN 'audio'; END IF;
  IF p ? 'video' THEN RETURN 'video'; END IF;
  IF p ? 'document' THEN RETURN 'document'; END IF;
  IF p ? 'sticker' THEN RETURN 'sticker'; END IF;
  IF p ? 'reaction' THEN RETURN 'reaction'; END IF;
  IF p ? 'poll' OR p ? 'pollCreation' THEN RETURN 'poll'; END IF;
  IF p ? 'listResponseMessage' OR p->'message' ? 'listResponseMessage' THEN RETURN 'list_response'; END IF;
  IF p ? 'buttonsResponseMessage' OR p->'message' ? 'buttonsResponseMessage' THEN RETURN 'button_response'; END IF;
  IF p ? 'location' THEN RETURN 'location'; END IF;
  IF p ? 'contact' OR p ? 'contacts' OR p ? 'contactsArrayMessage' THEN RETURN 'contact'; END IF;
  RETURN 'other';
END;
$$;

-- Build remap and merge duplicate leads
CREATE TEMP TABLE _lead_remap ON COMMIT DROP AS
SELECT id AS lead_id, phone_normalized AS old_phone,
       public.wa_normalize_phone(phone_normalized) AS new_phone,
       message_count, created_at
FROM public.whatsapp_leads;

DELETE FROM public.whatsapp_messages WHERE lead_id IN (
  SELECT lead_id FROM _lead_remap WHERE new_phone = '' OR new_phone IS NULL
);
DELETE FROM public.whatsapp_leads WHERE id IN (
  SELECT lead_id FROM _lead_remap WHERE new_phone = '' OR new_phone IS NULL
);
DELETE FROM _lead_remap WHERE new_phone = '' OR new_phone IS NULL;

CREATE TEMP TABLE _keepers ON COMMIT DROP AS
SELECT DISTINCT ON (new_phone) new_phone, lead_id AS keeper_id
FROM _lead_remap
ORDER BY new_phone, message_count DESC NULLS LAST, created_at ASC;

UPDATE public.whatsapp_messages m
SET lead_id = k.keeper_id
FROM _lead_remap r
JOIN _keepers k ON k.new_phone = r.new_phone
WHERE m.lead_id = r.lead_id AND r.lead_id <> k.keeper_id;

DELETE FROM public.whatsapp_leads
WHERE id IN (
  SELECT r.lead_id FROM _lead_remap r
  JOIN _keepers k ON k.new_phone = r.new_phone
  WHERE r.lead_id <> k.keeper_id
);

UPDATE public.whatsapp_leads l
SET phone_normalized = k.new_phone
FROM _keepers k
WHERE l.id = k.keeper_id AND l.phone_normalized <> k.new_phone;

-- Messages: drop invalid, renormalize the rest
DELETE FROM public.whatsapp_messages
WHERE public.wa_normalize_phone(phone_normalized) = '';

UPDATE public.whatsapp_messages
SET phone_normalized = public.wa_normalize_phone(phone_normalized)
WHERE phone_normalized <> public.wa_normalize_phone(phone_normalized);

-- Recompute counts
UPDATE public.whatsapp_leads l
SET message_count = COALESCE(sub.cnt, 0)
FROM (
  SELECT lead_id, COUNT(*) AS cnt FROM public.whatsapp_messages
  WHERE lead_id IS NOT NULL GROUP BY lead_id
) sub
WHERE l.id = sub.lead_id;

-- Re-extract bodies for "other"/placeholder messages (scalar functions, no LATERAL needed)
UPDATE public.whatsapp_messages
SET body = public.wa_extract_body_text(raw_payload),
    message_type = public.wa_extract_message_type(raw_payload)
WHERE (message_type = 'other' OR body = '[mensagem não reconhecida]')
  AND raw_payload IS NOT NULL
  AND public.wa_extract_message_type(raw_payload) <> 'other';

-- Fix direction
UPDATE public.whatsapp_messages
SET direction = 'outbound'
WHERE direction = 'inbound'
  AND raw_payload->>'fromMe' = 'true';