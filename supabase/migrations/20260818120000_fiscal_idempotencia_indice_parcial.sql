-- [VERIFICAÇÃO 18/08] Retry pós-falha era IMPOSSÍVEL: índice único de idempotência global
--
-- Achado da revisão adversarial: uq_ifd_idempotency_key era único sobre TODAS as linhas
-- com chave não-nula. Como a UI e as tools usam chave ESTÁVEL por origem (nfse-os-<id>,
-- nfe-os-<id>) e markFailed não limpa a chave, a 1ª emissão rejeitada deixava a chave
-- presa numa linha 'failed' — o "Tentar de novo" então: reservava numeração (RPS/NF
-- queimado), estourava 23505 no INSERT e devolvia 500 cru. A OS nunca mais faturava por
-- aquele caminho, e cada tentativa queimava mais um número.
--
-- Correção: o índice vira PARCIAL sobre documentos VIVOS — o mesmo conjunto de status do
-- uq_ifd_active_per_origin. Linha failed/rejected/cancelled mantém a chave gravada
-- (histórico), mas deixa de bloquear a próxima emissão com a mesma chave. A proteção
-- contra duplicidade REAL continua: enquanto houver documento vivo com a chave, o INSERT
-- de outro falha (e o handler recupera via findActiveDocument → reused).
drop index if exists uq_ifd_idempotency_key;
create unique index uq_ifd_idempotency_key
  on public.issued_fiscal_documents (idempotency_key)
  where idempotency_key is not null
    and status in ('draft', 'queued', 'processing', 'authorized');
