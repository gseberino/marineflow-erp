-- ═══════════════════════════════════════════════════════════════════════════
-- Ciclo do Serviço — Roteiro de Execução (Fase 1-3)
-- Plano: plans/marineflow-execucao-os-roteiro.md
--
-- O que entra:
--   1. service_step_templates  — o molde: passos padrão de um serviço do catálogo
--   2. service_order_steps     — a instância: os passos desta OS, com estado e tempo
--   3. work_stop_reasons       — lista fechada de motivos de parada (8-12 no nível 1)
--   4. service_cases           — a base de analogia (cada OS concluída vira um caso)
--   5. ai_suggestion_reviews   — o diff entre o que a IA propôs e o que o humano aprovou
--   + colunas aditivas em services, time_entries e service_order_photos
--
-- TUDO ADITIVO: nenhuma tabela ou coluna existente é removida ou renomeada.
--
-- Nota de projeto: a HBR cobra por serviço/visita (billing_unit 'unit'/'visit' na
-- maioria do catálogo), não por hora. O tempo apontado aqui é CUSTO e base de
-- estimativa — não é unidade de faturamento.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. MOTIVOS DE PARADA
--    Nível 1 curto de propósito: operador escolhe em segundos. Lista longa
--    empurra todo mundo para "outro" e mata a análise.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.work_stop_reasons (
  code text primary key,
  label text not null,
  category text not null check (category in ('espera','logistica','tecnico','pessoal','externo')),
  counts_as_billable boolean not null default false,
  sort integer not null default 0,
  active boolean not null default true
);

insert into public.work_stop_reasons (code, label, category, counts_as_billable, sort) values
  ('falta_peca',        'Falta peça ou material',            'espera',    false, 10),
  ('espera_cliente',    'Aguardando cliente',                'espera',    false, 20),
  ('espera_aprovacao',  'Aguardando aprovação de serviço',   'espera',    false, 30),
  ('acesso_bloqueado',  'Sem acesso ao equipamento',         'logistica', false, 40),
  ('deslocamento',      'Deslocamento',                      'logistica', true,  50),
  ('clima',             'Clima ou maré',                     'externo',   false, 60),
  ('equipamento',       'Ferramenta ou equipamento indisponível', 'tecnico', false, 70),
  ('apoio_tecnico',     'Aguardando apoio técnico',          'tecnico',   false, 80),
  ('retrabalho',        'Retrabalho',                        'tecnico',   true,  90),
  ('pausa',             'Pausa / almoço',                    'pessoal',   false, 100),
  ('outro',             'Outro (descrever)',                 'externo',   false, 999)
on conflict (code) do nothing;

alter table public.work_stop_reasons enable row level security;
create policy work_stop_reasons_read on public.work_stop_reasons
  for select using (auth.uid() is not null);
-- Só a equipe interna edita a lista (mexer nela muda o significado de todo histórico).
create policy work_stop_reasons_write on public.work_stop_reasons
  for all using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ─────────────────────────────────────────────────────────────
-- 2. TEMPLATES DE PASSO (o molde)
--    mode: 'read_do'    = leia e faça (aprendiz, procedimento raro)
--          'do_confirm' = faça e confirme (técnico experiente)
--    É o campo que decide se o roteiro ajuda ou irrita quem executa.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.service_step_templates (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services(id) on delete cascade,
  seq integer not null,
  block text,                                    -- 'Preparação' | 'Execução' | 'Fechamento'
  title text not null,                           -- verbo no imperativo, curto
  detail text,                                   -- o "como", opcional
  kind text not null default 'do'
    check (kind in ('do','check','safety','evidence','handoff')),
  mode text not null default 'do_confirm'
    check (mode in ('read_do','do_confirm')),
  standard_minutes integer check (standard_minutes is null or standard_minutes > 0),
  is_killer boolean not null default false,      -- item crítico: esquecer é caro
  requires_photo boolean not null default false,
  requires_measure text,                         -- 'tensao_v', 'corrente_a', 'torque_nm'
  measure_unit text,
  requires_part boolean not null default false,
  role_hint text,
  -- Curadoria: template rascunhado pela IA não vale até um humano assinar.
  origin text not null default 'manual' check (origin in ('manual','ai')),
  approved_by uuid references public.app_users(id),
  approved_at timestamptz,
  version integer not null default 1,
  active boolean not null default true,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_step_templates_seq_uk unique (service_id, version, seq),
  -- Um template de IA só pode estar ativo se alguém aprovou.
  constraint service_step_templates_ai_needs_approval
    check (origin <> 'ai' or not active or approved_by is not null)
);

create index if not exists service_step_templates_service
  on public.service_step_templates (service_id, active, seq);

alter table public.service_step_templates enable row level security;
create policy service_step_templates_all on public.service_step_templates
  for all using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

create trigger set_updated_at_service_step_templates
  before update on public.service_step_templates
  for each row execute function public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────
-- 3. PASSOS DA OS (a instância)
--    Liga-se opcionalmente à linha de serviço (service_order_services), que já
--    possui started_at/finished_at/elapsed_minutes — o roteiro alimenta esses
--    campos por rollup em vez de criar um segundo lugar para a mesma verdade.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.service_order_steps (
  id uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  service_order_service_id uuid references public.service_order_services(id) on delete set null,
  template_id uuid references public.service_step_templates(id) on delete set null,
  seq integer not null,
  block text,
  title text not null,
  detail text,
  kind text not null default 'do'
    check (kind in ('do','check','safety','evidence','handoff')),
  mode text not null default 'do_confirm'
    check (mode in ('read_do','do_confirm')),
  standard_minutes integer,
  is_killer boolean not null default false,
  requires_photo boolean not null default false,
  requires_measure text,
  measure_unit text,
  measure_value numeric,

  status text not null default 'pending'
    check (status in ('pending','in_progress','done','not_applicable','blocked')),
  na_reason text,
  blocked_reason_code text references public.work_stop_reasons(code),
  blocked_note text,

  assigned_user_id uuid references public.app_users(id),
  started_at timestamptz,
  completed_at timestamptz,
  actual_minutes integer,

  origin text not null default 'template'
    check (origin in ('template','ai','manual','client_request')),
  ai_confidence numeric(3,2) check (ai_confidence is null or (ai_confidence >= 0 and ai_confidence <= 1)),
  ai_source text,
  approved_by uuid references public.app_users(id),
  approved_at timestamptz,

  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- "Não se aplica" sem motivo é buraco no dado, não resposta.
  constraint service_order_steps_na_needs_reason
    check (status <> 'not_applicable' or coalesce(na_reason, '') <> ''),
  -- Travar sem dizer por quê tira o sentido do Pareto de paradas.
  constraint service_order_steps_blocked_needs_reason
    check (status <> 'blocked' or blocked_reason_code is not null)
);

create index if not exists service_order_steps_os_seq
  on public.service_order_steps (service_order_id, seq);
create index if not exists service_order_steps_assigned
  on public.service_order_steps (assigned_user_id, status)
  where status in ('pending','in_progress');

alter table public.service_order_steps enable row level security;
create policy service_order_steps_all on public.service_order_steps
  for all using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

create trigger set_updated_at_service_order_steps
  before update on public.service_order_steps
  for each row execute function public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────
-- 4. BASE DE CASOS (analogia)
--    Separada da OS de propósito: precisa sobreviver a edição/cancelamento e
--    precisa poder ser DESLIGADA quando o caso foi atípico (`usable = false`),
--    senão um caso ruim contamina toda estimativa futura.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.service_cases (
  id uuid primary key default gen_random_uuid(),
  service_order_id uuid not null references public.service_orders(id) on delete cascade,
  service_id uuid references public.services(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  marina_id uuid references public.marinas(id) on delete set null,
  asset_type text,                               -- Lancha | Catamarã | Motorhome | Camper
  features jsonb not null default '{}'::jsonb,   -- respostas de levantamento + condições
  planned_minutes integer,
  actual_minutes integer,
  materials_cost numeric(12,2),
  parts_used jsonb,
  variance_pct numeric(6,2),
  outcome text check (outcome in ('dentro','estourou','sobrou')),
  usable boolean not null default true,
  unusable_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_cases_os_uk unique (service_order_id, service_id)
);

create index if not exists service_cases_lookup
  on public.service_cases (service_id, usable, created_at desc);

alter table public.service_cases enable row level security;
create policy service_cases_all on public.service_cases
  for all using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

create trigger set_updated_at_service_cases
  before update on public.service_cases
  for each row execute function public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────
-- 5. O DIFF (instrumentação do aprendizado)
--    Ligado desde já, mesmo antes de existir quem o consuma: sem histórico
--    acumulado, o aprendizado começaria do zero lá na frente.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.ai_suggestion_reviews (
  id uuid primary key default gen_random_uuid(),
  suggestion_type text not null
    check (suggestion_type in ('survey_question','step','duration','material','quote_line','step_template')),
  target_table text not null,
  target_id uuid,
  service_id uuid references public.services(id) on delete set null,
  suggested jsonb not null,
  approved jsonb,                                -- null = rejeitado
  verdict text not null check (verdict in ('accepted','edited','rejected')),
  change_summary text,                           -- "tempo de 40 para 90 min", uma linha
  reviewer_id uuid references public.app_users(id),
  ai_model text,
  prompt_version text,
  reviewed_at timestamptz not null default now()
);

create index if not exists ai_suggestion_reviews_type
  on public.ai_suggestion_reviews (suggestion_type, verdict, reviewed_at desc);

alter table public.ai_suggestion_reviews enable row level security;
create policy ai_suggestion_reviews_all on public.ai_suggestion_reviews
  for all using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ─────────────────────────────────────────────────────────────
-- 6. COLUNAS ADITIVAS
-- ─────────────────────────────────────────────────────────────
alter table public.services
  add column if not exists standard_minutes integer,
  add column if not exists standard_source text,
  add column if not exists field_factor numeric(4,2) not null default 1.00,
  add column if not exists requires_survey boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'services_standard_source_check') then
    alter table public.services
      add constraint services_standard_source_check
      check (standard_source is null or standard_source in ('oem','manual','historico'));
  end if;
end $$;

alter table public.time_entries
  add column if not exists step_id uuid references public.service_order_steps(id) on delete set null,
  add column if not exists stop_reason_code text references public.work_stop_reasons(code);

create index if not exists time_entries_step on public.time_entries (step_id);

alter table public.service_order_photos
  add column if not exists step_id uuid references public.service_order_steps(id) on delete set null,
  add column if not exists captured_live boolean not null default false;

-- ─────────────────────────────────────────────────────────────
-- 7. GERAR O ROTEIRO A PARTIR DO CATÁLOGO
--    Idempotente por linha de serviço: rodar de novo não duplica passos.
--    Retorna quantos passos criou.
-- ─────────────────────────────────────────────────────────────
create or replace function public.generate_service_order_steps(p_service_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_created integer := 0;
  v_batch integer := 0;
  v_seq integer;
  r_line record;
begin
  -- SECURITY DEFINER ignora RLS por definição: sem esta porta, um vendedor
  -- externo autenticado gravaria passos que a policy da tabela lhe nega.
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão para gerar roteiro' using errcode = '42501';
  end if;

  if not exists (select 1 from public.service_orders where id = p_service_order_id) then
    raise exception 'Ordem de serviço % não encontrada', p_service_order_id;
  end if;

  select coalesce(max(seq), 0) into v_seq
  from public.service_order_steps where service_order_id = p_service_order_id;

  for r_line in
    select sos.id as line_id, sos.service_id, sos.name_snapshot
    from public.service_order_services sos
    where sos.service_order_id = p_service_order_id
      and sos.service_id is not null
      -- pula linha que já tem roteiro (idempotência)
      and not exists (
        select 1 from public.service_order_steps s
        where s.service_order_service_id = sos.id
      )
    order by sos.created_at
  loop
    insert into public.service_order_steps (
      service_order_id, service_order_service_id, template_id, seq, block, title, detail,
      kind, mode, standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
      origin
    )
    select
      p_service_order_id, r_line.line_id, t.id,
      v_seq + row_number() over (order by t.seq),
      coalesce(t.block, r_line.name_snapshot),
      t.title, t.detail, t.kind, t.mode, t.standard_minutes, t.is_killer,
      t.requires_photo, t.requires_measure, t.measure_unit,
      'template'
    from public.service_step_templates t
    where t.service_id = r_line.service_id
      and t.active
      and t.version = (
        select max(version) from public.service_step_templates
        where service_id = r_line.service_id and active
      );

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  -- Quantos passos ESTA chamada criou (0 = já estava tudo gerado, ou o serviço
  -- ainda não tem template — a UI distingue os dois casos).
  return v_created;
end;
$$;

revoke all on function public.generate_service_order_steps(uuid) from public, anon;
grant execute on function public.generate_service_order_steps(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 8. ROLLUP DO TEMPO PARA A LINHA DE SERVIÇO
--    service_order_services.elapsed_minutes já existia e estava órfão; o roteiro
--    passa a alimentá-lo, em vez de criar um segundo lugar para a mesma verdade.
-- ─────────────────────────────────────────────────────────────
create or replace function public.rollup_step_time_to_service_line()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line uuid := coalesce(new.service_order_service_id, old.service_order_service_id);
begin
  if v_line is null then
    return coalesce(new, old);
  end if;

  update public.service_order_services sos
  set elapsed_minutes = agg.total,
      started_at = coalesce(sos.started_at, agg.first_start),
      finished_at = case when agg.pendentes = 0 then agg.last_end else null end
  from (
    select
      sum(coalesce(actual_minutes, 0))::integer as total,
      min(started_at) as first_start,
      max(completed_at) as last_end,
      count(*) filter (where status not in ('done','not_applicable')) as pendentes
    from public.service_order_steps
    where service_order_service_id = v_line
  ) agg
  where sos.id = v_line;

  return coalesce(new, old);
end;
$$;

create trigger trg_rollup_step_time
  after insert or update of status, actual_minutes, started_at, completed_at
     or delete
  on public.service_order_steps
  for each row execute function public.rollup_step_time_to_service_line();

-- ─────────────────────────────────────────────────────────────
-- 9. VIEW DE VARIAÇÃO (o número que justifica o projeto)
--    security_invoker + revoke de anon na MESMA migration: view criada sem isso
--    ignora a RLS das tabelas base.
-- ─────────────────────────────────────────────────────────────
create or replace view public.v_service_order_labor_variance
with (security_invoker = on) as
select
  so.id,
  so.service_order_number,
  so.client_id,
  so.status,
  (so.estimated_hours * 60)::integer                                as orcado_min,
  coalesce(sum(st.standard_minutes), 0)::integer                    as padrao_roteiro_min,
  coalesce(sum(st.actual_minutes), 0)::integer                      as real_min,
  count(st.id)                                                      as passos,
  count(st.id) filter (where st.status = 'done')                    as passos_feitos,
  count(st.id) filter (where st.status = 'blocked')                 as passos_travados,
  count(st.id) filter (where st.status = 'not_applicable')          as passos_na,
  case
    when coalesce(sum(st.standard_minutes), 0) > 0
    then round(((coalesce(sum(st.actual_minutes), 0) - sum(st.standard_minutes))::numeric
                / sum(st.standard_minutes)) * 100, 1)
  end                                                               as variacao_pct
from public.service_orders so
left join public.service_order_steps st on st.service_order_id = so.id
group by so.id, so.service_order_number, so.client_id, so.status, so.estimated_hours;

revoke all on public.v_service_order_labor_variance from anon;
grant select on public.v_service_order_labor_variance to authenticated;

comment on view public.v_service_order_labor_variance is
  'Orçado x padrão do roteiro x real por OS. O tempo aqui é custo, não unidade de faturamento.';

-- ─────────────────────────────────────────────────────────────
-- 10. FECHAR A FUNÇÃO DE TRIGGER (apontado pelo advisor)
--     rollup_step_time_to_service_line() precisa ser SECURITY DEFINER para
--     escrever em service_order_services independentemente de quem move o passo,
--     mas o PostgREST a expõe em /rest/v1/rpc/ — inclusive para anon. Chamada
--     fora do contexto de trigger ela falharia, mas superfície que não precisa
--     existir não deve existir.
-- ─────────────────────────────────────────────────────────────
revoke all on function public.rollup_step_time_to_service_line() from public, anon, authenticated;
