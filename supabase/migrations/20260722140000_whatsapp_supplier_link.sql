-- Resolução de contato: vínculo de FORNECEDOR na conversa de WhatsApp (Fase 3 · Etapa 2).
-- 100% ADITIVO — nenhuma coluna, trigger, RPC ou policy existente é alterada.
--
-- Problema medido em 22/07/2026: das 1839 mensagens recebidas, 1779 (96,7%) não têm nenhuma
-- entidade vinculada. `whatsapp_messages` já tinha client_id, mas NÃO tinha supplier_id — por
-- isso a leitura de cotação precisava casar fornecedor por "últimos 8 dígitos do telefone",
-- uma heurística em tempo de leitura, sem memória.
--
-- Com esta coluna, ensinar o vínculo UMA vez passa a valer para as mensagens seguintes e para
-- as anteriores daquele número.

alter table public.whatsapp_messages
  add column if not exists supplier_id uuid references public.suppliers(id) on delete set null;

create index if not exists idx_wamsg_supplier on public.whatsapp_messages (supplier_id)
  where supplier_id is not null;

comment on column public.whatsapp_messages.supplier_id is
  'Fornecedor dono deste número, quando identificado. Preenchido por link_contact_to_entity (agente) — espelha o papel de client_id para o outro lado da operação.';
