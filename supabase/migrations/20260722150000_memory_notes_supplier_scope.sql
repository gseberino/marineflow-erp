-- Memória por entidade: escopo de FORNECEDOR (Fase 3 · Etapa 3).
-- ADITIVO — só acrescenta coluna e ALARGA um CHECK existente (nenhuma linha atual pode violar
-- um conjunto maior de valores permitidos). Nada é removido ou alterado em dados.
--
-- A tabela ai_operator_memory_notes JÁ tinha client_id, vessel_id, topic, confidence, source e
-- o fluxo de verificação (candidate → verified/rejected). A infraestrutura de memória por
-- entidade existia e estava ociosa: faltava o lado do fornecedor e o agente usá-la.

alter table public.ai_operator_memory_notes
  add column if not exists supplier_id uuid references public.suppliers(id) on delete cascade;

create index if not exists idx_memnotes_supplier on public.ai_operator_memory_notes (supplier_id)
  where supplier_id is not null;

-- Índice para o carregamento contextual (só notas verificadas de uma entidade).
create index if not exists idx_memnotes_client_verified
  on public.ai_operator_memory_notes (client_id, verification_status)
  where client_id is not null;

-- Alarga o escopo para incluir 'supplier', preservando os valores já aceitos.
alter table public.ai_operator_memory_notes drop constraint if exists ai_operator_memory_notes_scope_check;
alter table public.ai_operator_memory_notes add constraint ai_operator_memory_notes_scope_check
  check (scope = any (array['vessel'::text, 'client'::text, 'global'::text, 'supplier'::text]));

comment on column public.ai_operator_memory_notes.supplier_id is
  'Fornecedor a que esta nota se refere (scope = supplier). Espelha client_id/vessel_id.';
