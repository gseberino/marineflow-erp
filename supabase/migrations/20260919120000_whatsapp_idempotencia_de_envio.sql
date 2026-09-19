-- Idempotência de envio de WhatsApp (Diário de Bordo, item "WhatsApp · chave de deduplicação").
--
-- Dois caminhos de envio, duas proteções:
--
-- 1) FILA (whatsapp_send_queue) — usada pelos remetentes automáticos (briefing, monitor,
--    lembretes de saldo/orçamento/tarefa, follow-ups, não lidas). Ganha a coluna dedupe_key
--    com índice único. Um gatilho preenche a chave sozinho para toda origem automática
--    (origem:telefone:dia:md5(mensagem)) e descarta em silêncio a linha repetida. Assim um
--    cron que dispare duas vezes, ou uma edge reexecutada, não manda a mesma mensagem duas
--    vezes no mesmo dia. Origens de conversa ('manual' e 'ai_agent') ficam de fora: repetir
--    uma resposta é legítimo ali.
--
-- 2) ENVIO DIRETO (edge whatsapp-send) — usada pelo painel, pelas tools do agente e pelas
--    mensagens agendadas. Tabela whatsapp_send_idempotencia: quem chama manda dedupe_key, a
--    edge reserva a chave ANTES de enviar e, se já existir, responde "já enviada" sem
--    chamar o provedor. Reserva de envio que falhou é liberada para a tentativa seguinte.
--
-- Medição antes de escrever isto (90 dias): 2 duplicatas reais de texto, nenhuma dos
-- remetentes automáticos. É proteção para o dia em que acontecer, não conserto de incêndio.

-- ── 1. Fila ────────────────────────────────────────────────────────────────────────────
alter table public.whatsapp_send_queue add column if not exists dedupe_key text;

-- Único e NÃO parcial de propósito: NULL não colide com NULL, e um índice parcial
-- exigiria a cláusula WHERE em todo upsert (PostgREST não a manda).
create unique index if not exists whatsapp_send_queue_dedupe_key_uq
  on public.whatsapp_send_queue (dedupe_key);

create or replace function public.whatsapp_send_queue_idempotencia()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Origem automática sem chave explícita: chave por origem + telefone + dia local + corpo.
  if new.dedupe_key is null
     and new.source is not null
     and new.source not in ('manual', 'ai_agent') then
    new.dedupe_key := new.source || ':' || coalesce(new.phone_normalized, '') || ':'
      || to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD') || ':'
      || md5(coalesce(new.message, ''));
  end if;

  if new.dedupe_key is not null
     and exists (select 1 from public.whatsapp_send_queue q where q.dedupe_key = new.dedupe_key) then
    -- Repetida: descarta em silêncio (o insert devolve zero linhas para esta entrada).
    -- Duas inserções simultâneas da mesma chave escapam deste exists; o índice único
    -- barra a segunda com 23505, que é o comportamento certo para uma corrida.
    return null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_whatsapp_send_queue_idempotencia on public.whatsapp_send_queue;
create trigger trg_whatsapp_send_queue_idempotencia
  before insert on public.whatsapp_send_queue
  for each row execute function public.whatsapp_send_queue_idempotencia();

-- ── 2. Envio direto ────────────────────────────────────────────────────────────────────
create table if not exists public.whatsapp_send_idempotencia (
  chave text primary key,
  phone_normalized text,
  contexto text,
  provider_message_id text,
  criado_em timestamptz not null default now()
);
create index if not exists whatsapp_send_idempotencia_criado_em_idx
  on public.whatsapp_send_idempotencia (criado_em);

-- Só a service role escreve/lê (a edge). RLS ligada sem policy = fechada para anon e
-- authenticated, mesmo com os grants nominais de default privileges.
alter table public.whatsapp_send_idempotencia enable row level security;

comment on table public.whatsapp_send_idempotencia is
  'Chaves de envio já usadas pela edge whatsapp-send (dedupe_key). Linhas com mais de 30 dias são apagadas pela própria edge.';
comment on column public.whatsapp_send_queue.dedupe_key is
  'Chave de idempotência. Preenchida pelo gatilho para origens automáticas; linha repetida é descartada.';

-- Aplicada por `db query -f` (sem `db push`): registra a si mesma para o histórico não divergir.
insert into supabase_migrations.schema_migrations (version, name)
values ('20260919120000', 'whatsapp_idempotencia_de_envio')
on conflict do nothing;
