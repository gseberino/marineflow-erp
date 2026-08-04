-- ─────────────────────────────────────────────────────────────────────────────
-- Registro do ENVIO de cotação a fornecedor — separa "escolhi" de "mandei".
--
-- O PROBLEMA (medido em 03/08/2026): as três cotações em produção (COT-00001 a
-- 00003, criadas em 23/07) aparecem como enviadas a dois fornecedores cada, e
-- NUNCA foram enviadas a ninguém. Não existe uma única mensagem de WhatsApp
-- citando "COT-", e a fila de envio jamais teve uma linha de cotação — só
-- briefing, agente, monitor e cobrança.
--
-- A causa: `quote_requests.sent_supplier_ids` é gravado na CRIAÇÃO da cotação
-- (use-quote-requests.ts, useCreateQuoteRequest) com os fornecedores que o
-- usuário apenas SELECIONOU no formulário. O nome do campo diz "enviados", mas
-- o conteúdo é "escolhidos". E não havia botão de enviar em tela nenhuma: o
-- envio só existia pela ferramenta do agente, que por sua vez não escreve nesse
-- campo. Resultado: o sistema afirmava ter enviado, o dono confiava, e a regra
-- R17 cobrava "fornecedor não respondeu" sobre um pedido que nunca saiu.
--
-- A CORREÇÃO estrutural é esta tabela: envio é FATO, com hora e destino, não uma
-- lista de intenção. `sent_supplier_ids` passa a significar apenas "consultados"
-- (quem foi escolhido para cotar) e deixa de ser usado como prova de envio.
--
-- O status NÃO é copiado para cá de propósito: ele vive em whatsapp_send_queue,
-- que o worker atualiza a cada minuto. Guardar uma segunda cópia criaria dois
-- lugares para a mesma verdade — exatamente o defeito que estamos corrigindo.
-- Aqui fica só o vínculo; o estado sai por junção.
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists public.quote_request_sends (
  id                uuid primary key default gen_random_uuid(),
  quote_request_id  uuid not null references public.quote_requests(id) on delete cascade,
  supplier_id       uuid not null references public.suppliers(id),
  phone_normalized  text not null,
  queue_id          uuid references public.whatsapp_send_queue(id) on delete set null,
  channel           text not null default 'whatsapp',
  created_by        uuid,
  created_at        timestamptz not null default now()
);

comment on table public.quote_request_sends is
  'Cada tentativa REAL de envio de uma cotacao a um fornecedor. O status vive em whatsapp_send_queue (via queue_id) — aqui fica so o vinculo, para nao existir duas versoes da mesma verdade.';
comment on column public.quote_request_sends.queue_id is
  'Linha da fila que carrega esta mensagem. O worker atualiza status/failed_reason la; a tela le por juncao.';

create index if not exists idx_qrs_quote   on public.quote_request_sends(quote_request_id);
create index if not exists idx_qrs_queue   on public.quote_request_sends(queue_id);

alter table public.quote_request_sends enable row level security;

-- Mesma regra das demais tabelas de compras: admin ou financeiro, uma politica
-- por comando, TO authenticated explicito. Sem o TO, a politica valeria tambem
-- para anon — e is_admin_or_financial(NULL) devolve false sem FECHAR o acesso.
create policy quote_request_sends_select on public.quote_request_sends
  for select to authenticated using (public.is_admin_or_financial(auth.uid()));
create policy quote_request_sends_insert on public.quote_request_sends
  for insert to authenticated with check (public.is_admin_or_financial(auth.uid()));
create policy quote_request_sends_update on public.quote_request_sends
  for update to authenticated using (public.is_admin_or_financial(auth.uid()))
                                 with check (public.is_admin_or_financial(auth.uid()));
create policy quote_request_sends_delete on public.quote_request_sends
  for delete to authenticated using (public.is_admin_or_financial(auth.uid()));

revoke all on public.quote_request_sends from anon;
grant select, insert, update, delete on public.quote_request_sends to authenticated;
grant all on public.quote_request_sends to service_role;
