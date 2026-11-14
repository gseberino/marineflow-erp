-- Via do técnico pelo WhatsApp (13/11/2026) — o responsável de cada serviço e o registro dos envios.
--
-- Pedido do dono: o assistente manda a via do técnico em PDF a cada responsável pelos serviços da OS
-- (parciais ou totais), e a ele quando pedir; a agenda a anexa à ficha das 19:30 no 1º dia da pessoa
-- naquela OS, e de novo só se a OS mudar. Decisão dele: cada pessoa recebe SÓ os serviços dela.
--
-- Por que uma coluna nova e não technician_user_id: aquela aponta para app_users (login), e a equipe
-- de campo são favorecidos (payees) — o Alex não tem login, e nenhum técnico ativo tem. Medido em
-- 13/11/2026: technician_user_id preenchido em 8 de 367 linhas.
--
-- Só estrutura: nenhum dado é gravado ou mudado. Sem gatilho novo; service_order_services só tem os de
-- updated_at e garantia (a agenda não reage a esta coluna).
--
-- DESFAZER:
--   drop table if exists public.via_tecnico_envios;
--   drop index if exists public.service_order_services_responsavel_idx;
--   alter table public.service_order_services drop column if exists responsavel_payee_id;

-- ── 1. O responsável de cada linha de serviço ──────────────────────────────────────────────────────
alter table public.service_order_services
  add column if not exists responsavel_payee_id uuid references public.payees(id) on delete set null;

comment on column public.service_order_services.responsavel_payee_id is
  'Quem faz este serviço (payees.id; sócio, funcionário, diarista ou prestador). Nulo = sem responsável marcado: a linha vai na via de todo mundo da OS. A via do técnico de uma pessoa leva as linhas dela e as sem responsável (decisão do dono, 13/11/2026).';

create index if not exists service_order_services_responsavel_idx
  on public.service_order_services (responsavel_payee_id)
  where responsavel_payee_id is not null;

-- ── 2. O registro de cada via mandada (ou pulada) ──────────────────────────────────────────────────
-- A agenda lê daqui "essa pessoa já recebeu esta versão da via desta OS?"; o dono e o assistente
-- leem "para quem a via foi". Escrita só pela chave de serviço (edges); leitura só do administrador.
create table if not exists public.via_tecnico_envios (
  id               uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  -- Para quem foi: a pessoa da equipe (payees) ou, no pedido para si, o usuário (app_users).
  payee_id         uuid references public.payees(id) on delete set null,
  app_user_id      uuid references public.app_users(id) on delete set null,
  -- agenda = junto da ficha das 19:30; assistente = o dono mandou a alguém (com o SIM); para_si = quem pediu recebeu.
  origem           text not null check (origem in ('agenda', 'assistente', 'para_si')),
  -- enviado = o WhatsApp aceitou; falhou = não saiu (motivo); pulado = não era para sair (motivo).
  estado           text not null check (estado in ('enviado', 'falhou', 'pulado')),
  motivo           text check (motivo is null or char_length(motivo) <= 300),
  -- Só dígitos, como payees.phone e app_users.phone_normalized.
  destino          text check (destino is null or destino ~ '^[0-9]{8,15}$'),
  -- impressaoDaVia: muda quando o conteúdo da via da pessoa muda (não muda com data, hora ou link de foto).
  impressao        text,
  -- Quantos serviços foram no papel (os da pessoa e os sem responsável).
  servicos         integer check (servicos is null or servicos >= 0),
  -- A ficha da agenda que esta via acompanha, e o dia de trabalho dela.
  ficha_id         uuid references public.agenda_equipe_mensagens(id) on delete set null,
  dia              date,
  -- Quem pediu (app_users.id) quando veio do assistente.
  pedido_por       uuid references public.app_users(id) on delete set null,
  criado_em        timestamptz not null default now(),
  constraint via_tecnico_envios_alguem check (payee_id is not null or app_user_id is not null),
  constraint via_tecnico_envios_motivo_coerente check ((estado = 'enviado') or (motivo is not null))
);

comment on table public.via_tecnico_envios is
  'Via do técnico em PDF pelo WhatsApp (13/11/2026): cada envio (ou pulo) para a equipe ou para quem pediu. A agenda manda no 1º dia da pessoa na OS e de novo só quando a impressao muda.';

-- "Esta pessoa já recebeu esta versão desta OS?" e "o que saiu com esta ficha?".
create index if not exists via_tecnico_envios_pessoa_os_idx
  on public.via_tecnico_envios (payee_id, service_order_id, criado_em desc);
create index if not exists via_tecnico_envios_ficha_idx
  on public.via_tecnico_envios (ficha_id) where ficha_id is not null;
-- Uma ficha leva no máximo UMA via enviada (ou pulada) por OS: dois tiques do cron juntos não mandam duas.
create unique index if not exists via_tecnico_envios_ficha_os_uidx
  on public.via_tecnico_envios (ficha_id, service_order_id)
  where ficha_id is not null and estado in ('enviado', 'pulado');

alter table public.via_tecnico_envios enable row level security;

-- Leitura: só administrador logado. Nada de escrita por usuário: grava a chave de serviço (edges).
drop policy if exists via_tecnico_envios_admin_le on public.via_tecnico_envios;
create policy via_tecnico_envios_admin_le on public.via_tecnico_envios
  for select to authenticated
  using (public.is_admin(auth.uid()));

-- Tabela nova vem com os grants padrão: fechar para anon e deixar ao logado só o SELECT (a política filtra).
revoke all on public.via_tecnico_envios from anon;
revoke all on public.via_tecnico_envios from authenticated;
grant select on public.via_tecnico_envios to authenticated;
grant all on public.via_tecnico_envios to service_role;
