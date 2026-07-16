-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: endereço estruturado do cliente (número/complemento/bairro)
--   `clients` só tinha address_line_1/address_line_2 concatenados. A emissão de
--   NF-e precisa de número e bairro separados; o ClientFormDialog descartava o
--   bairro ao salvar e dados legados guardaram "número, bairro, compl" na line_2.
--   Aqui adicionamos as colunas e fazemos um backfill best-effort que espelha o
--   parser TS (src/lib/address-legacy.ts). Só preenche onde ainda está NULL —
--   não destrói line_1/line_2.
-- 100% idempotente. Sem segredos.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS address_number     text,
  ADD COLUMN IF NOT EXISTS address_complement text,
  ADD COLUMN IF NOT EXISTS neighborhood       text;

-- Backfill 1: address_line_2 no formato "número, bairro[, complemento...]".
-- number = 1º segmento (começa com dígito); neighborhood = 2º; complement = resto.
WITH parsed AS (
  SELECT
    id,
    btrim(split_part(address_line_2, ',', 1))                         AS p_number,
    btrim(split_part(address_line_2, ',', 2))                         AS p_neigh,
    btrim(regexp_replace(address_line_2, '^[^,]*,[^,]*,?', ''))       AS p_compl
  FROM clients
  WHERE address_line_2 IS NOT NULL
    AND btrim(address_line_2) <> ''
    AND btrim(split_part(address_line_2, ',', 1)) ~ '^\d'
)
UPDATE clients c
SET
  address_number     = COALESCE(NULLIF(c.address_number, ''),     NULLIF(p.p_number, '')),
  neighborhood       = COALESCE(NULLIF(c.neighborhood, ''),       NULLIF(p.p_neigh, '')),
  address_complement = COALESCE(NULLIF(c.address_complement, ''), NULLIF(p.p_compl, ''))
FROM parsed p
WHERE c.id = p.id
  AND (c.address_number IS NULL OR c.neighborhood IS NULL OR c.address_complement IS NULL);

-- Backfill 2: line_2 sem número inicial (ex.: "Centro, Sala 3") → bairro = 1º
-- segmento, complemento = resto; sem número.
WITH parsed AS (
  SELECT
    id,
    btrim(split_part(address_line_2, ',', 1))                   AS p_neigh,
    btrim(regexp_replace(address_line_2, '^[^,]*,?', ''))       AS p_compl
  FROM clients
  WHERE address_line_2 IS NOT NULL
    AND btrim(address_line_2) <> ''
    AND btrim(split_part(address_line_2, ',', 1)) !~ '^\d'
)
UPDATE clients c
SET
  neighborhood       = COALESCE(NULLIF(c.neighborhood, ''),       NULLIF(p.p_neigh, '')),
  address_complement = COALESCE(NULLIF(c.address_complement, ''), NULLIF(p.p_compl, ''))
FROM parsed p
WHERE c.id = p.id
  AND (c.neighborhood IS NULL OR c.address_complement IS NULL);

-- Backfill 3: número ainda ausente, mas address_line_1 termina em ", <número>"
-- (ex.: "Avenida Brasil, 1500"). Extrai só o número; NÃO altera line_1 (para não
-- quebrar PDFs e outros consumidores que já leem line_1 inteira).
UPDATE clients
SET address_number = btrim(substring(address_line_1 from ',\s*(\d[^,]*)$'))
WHERE (address_number IS NULL OR address_number = '')
  AND address_line_1 ~ ',\s*\d[^,]*$';
