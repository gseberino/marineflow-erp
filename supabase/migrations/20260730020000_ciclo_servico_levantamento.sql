-- ═══════════════════════════════════════════════════════════════════════════
-- Ciclo do Serviço — Fase 4: LEVANTAMENTO ANTES DE ORÇAR
-- Plano: plans/marineflow-execucao-os-roteiro.md (seções 3-bis e 4-bis)
--
-- Quando o serviço exige análise técnica antes de orçar, a IA monta um
-- questionário curto, o técnico (ou o cliente, por foto) responde, e desse
-- levantamento sai a estimativa e o rascunho do orçamento.
--
-- Princípios que viraram estrutura:
--   P15 — nem todo serviço precisa: `trigger_reason` registra qual gatilho disparou
--   P16 — a pergunta certa vale mais que muitas: `price_impact` ordena, e o
--         módulo de parada grava confiança + justificativa por escrito
--   P17 — levantar de longe antes de perto: `ask_remotely` marca o que um leigo
--         responde com uma foto
--   P18 — contingência proporcional à confiança, e não gordura escondida
--
-- Todas as policies nascem com TO authenticated: sem isso ficam no role `public`,
-- que inclui anon, e is_external_seller(null) devolve false (lição de 29/07).
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────
-- 1. PERGUNTAS PADRÃO DE UM SERVIÇO (o molde do questionário)
-- ─────────────────────────────────────────────────────────────
create table if not exists public.service_survey_templates (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services(id) on delete cascade,
  seq integer not null,
  question text not null,
  help_text text,                                -- o porquê, para quem responde entender o que está em jogo
  answer_type text not null default 'escolha'
    check (answer_type in ('sim_nao','escolha','numero','texto','foto','medida')),
  options jsonb,                                 -- ["fixo","removível","não identificado"]
  -- P16: ordena o questionário. Primeiro a pergunta cuja resposta mais muda o preço.
  price_impact text not null default 'medio'
    check (price_impact in ('alto','medio','baixo')),
  affects text[],                                -- {'tempo','material','acesso','risco'}
  branch_on jsonb,                               -- {"template_id":"...","equals":"sim"} → só aparece se
  -- P17: pergunta que um leigo responde com uma foto pode ir ao cliente por link.
  ask_remotely boolean not null default false,
  origin text not null default 'manual' check (origin in ('manual','ai')),
  approved_by uuid references public.app_users(id),
  approved_at timestamptz,
  version integer not null default 1,
  active boolean not null default true,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_survey_templates_seq_uk unique (service_id, version, seq),
  -- Mesma trava do roteiro: pergunta rascunhada por IA não vale sem assinatura humana.
  constraint service_survey_templates_ai_needs_approval
    check (origin <> 'ai' or not active or approved_by is not null)
);

create index if not exists service_survey_templates_service
  on public.service_survey_templates (service_id, active, seq);

alter table public.service_survey_templates enable row level security;
create policy service_survey_templates_all on public.service_survey_templates
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

create trigger set_updated_at_service_survey_templates
  before update on public.service_survey_templates
  for each row execute function public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────
-- 2. O LEVANTAMENTO DE UM ORÇAMENTO
--    O orçamento no MarineFlow é a própria service_orders em status draft —
--    o levantamento se pendura nela, sem entidade paralela.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.service_surveys (
  id uuid primary key default gen_random_uuid(),
  service_order_id uuid references public.service_orders(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  vessel_id uuid references public.vessels(id) on delete set null,
  service_id uuid references public.services(id) on delete set null,

  -- P15: qual dos cinco gatilhos disparou, em texto legível.
  trigger_reason text not null,
  mode text not null default 'local' check (mode in ('remoto','local')),
  status text not null default 'draft'
    check (status in ('draft','sent','answered','closed','skipped')),

  -- P16: módulo de parada. A justificativa é obrigatória quando há confiança
  -- declarada — decidir sem dizer por quê é o que produz pergunta ruim.
  confidence text check (confidence in ('alta','media','baixa')),
  confidence_rationale text,
  questions_planned integer,
  questions_asked integer,

  -- P18: a estimativa que sai do levantamento.
  estimated_minutes_p50 integer,
  estimated_minutes_p80 integer,
  contingency_pct numeric(5,2) check (contingency_pct is null or contingency_pct >= 0),
  materials_draft jsonb,
  cases_used jsonb,                              -- quais casos sustentaram a estimativa

  -- P17: link para o cliente responder o que é respondível por foto.
  share_token text unique,
  answered_by uuid references public.app_users(id),
  answered_at timestamptz,
  created_by uuid references public.app_users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint service_surveys_confidence_needs_reason
    check (confidence is null or coalesce(confidence_rationale, '') <> '')
);

create index if not exists service_surveys_os on public.service_surveys (service_order_id);
create index if not exists service_surveys_status on public.service_surveys (status, created_at desc);

alter table public.service_surveys enable row level security;
create policy service_surveys_all on public.service_surveys
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

create trigger set_updated_at_service_surveys
  before update on public.service_surveys
  for each row execute function public.update_updated_at_column();

-- ─────────────────────────────────────────────────────────────
-- 3. RESPOSTAS
--    `skipped_reason` existe porque "não consegui ver" é resposta legítima e
--    precisa virar dado, não buraco.
-- ─────────────────────────────────────────────────────────────
create table if not exists public.service_survey_answers (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.service_surveys(id) on delete cascade,
  template_id uuid references public.service_survey_templates(id) on delete set null,
  seq integer not null,
  question_snapshot text not null,
  answer_value text,
  answer_json jsonb,
  photo_path text,
  skipped_reason text,
  answered_at timestamptz not null default now(),
  constraint service_survey_answers_uk unique (survey_id, seq)
);

create index if not exists service_survey_answers_survey
  on public.service_survey_answers (survey_id, seq);

alter table public.service_survey_answers enable row level security;
create policy service_survey_answers_all on public.service_survey_answers
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

-- ─────────────────────────────────────────────────────────────
-- 4. COLUNAS ADITIVAS NO ORÇAMENTO
-- ─────────────────────────────────────────────────────────────
alter table public.service_orders
  add column if not exists survey_id uuid references public.service_surveys(id) on delete set null,
  add column if not exists estimate_confidence text,
  add column if not exists contingency_pct numeric(5,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'service_orders_estimate_confidence_check') then
    alter table public.service_orders
      add constraint service_orders_estimate_confidence_check
      check (estimate_confidence is null or estimate_confidence in ('alta','media','baixa'));
  end if;
end $$;

-- ─────────────────────────────────────────────────────────────
-- 5. O GATILHO (P15) — quatro contas, nenhuma IA
--    Decide se o serviço merece levantamento e DIZ POR QUÊ. Só o quinto gatilho
--    (ler incerteza no pedido do cliente) é LLM, e fica fora daqui.
-- ─────────────────────────────────────────────────────────────
create or replace function public.should_survey_service(
  p_service_id uuid,
  p_client_id uuid default null,
  p_vessel_id uuid default null,
  p_valor numeric default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_forcado boolean;
  v_casos integer;
  v_min integer;
  v_max integer;
  v_disp numeric;
  v_cliente_novo boolean := false;
  v_limiar numeric := coalesce(
    (select value::numeric from public.app_settings where key = 'survey_valor_limiar'), 3000);
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select coalesce(requires_survey, false) into v_forcado
  from public.services where id = p_service_id;

  -- Gatilho 1: dispersão histórica. Sem casos, não há dispersão a medir.
  select count(*), min(actual_minutes), max(actual_minutes)
    into v_casos, v_min, v_max
  from public.service_cases
  where service_id = p_service_id and usable and actual_minutes > 0;

  if v_casos >= 2 and v_min > 0 then
    v_disp := round(((v_max - v_min)::numeric / v_min) * 100, 0);
  end if;

  -- Gatilho 4: cliente sem histórico.
  if p_client_id is not null then
    select not exists (
      select 1 from public.service_orders
      where client_id = p_client_id and status in ('completed','invoiced')
    ) into v_cliente_novo;
  end if;

  return jsonb_build_object(
    'precisa', (
      coalesce(v_forcado, false)
      or coalesce(v_disp, 0) > 30
      or v_casos = 0
      or coalesce(p_valor, 0) >= v_limiar
      or v_cliente_novo
    ),
    'motivos', (
      select coalesce(jsonb_agg(m), '[]'::jsonb) from (
        select 'Serviço marcado como sempre exigindo levantamento' as m where coalesce(v_forcado,false)
        union all
        select 'Execuções anteriores variaram ' || v_disp || '% entre si' where coalesce(v_disp,0) > 30
        union all
        select 'Nenhuma execução registrada deste serviço' where v_casos = 0
        union all
        select 'Valor de ' || to_char(p_valor,'FM999G999D00') || ' acima do limiar de ' || to_char(v_limiar,'FM999G999D00')
          where coalesce(p_valor,0) >= v_limiar
        union all
        select 'Cliente ainda sem serviço concluído' where v_cliente_novo
      ) t
    ),
    'casos_conhecidos', v_casos,
    'dispersao_pct', v_disp
  );
end;
$fn$;

revoke all on function public.should_survey_service(uuid, uuid, uuid, numeric) from public, anon;
grant execute on function public.should_survey_service(uuid, uuid, uuid, numeric) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 6. ESTIMATIVA POR ANALOGIA (P8/P18)
--    Devolve P50, P80 e os casos que sustentam — número sem os casos que o
--    sustentam não é entregue. Abaixo do piso mínimo, diz que não tem base.
-- ─────────────────────────────────────────────────────────────
create or replace function public.estimate_from_cases(p_service_id uuid, p_min_casos integer default 3)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_n integer;
  v_p50 numeric;
  v_p80 numeric;
  v_casos jsonb;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select count(*),
         percentile_cont(0.5) within group (order by actual_minutes),
         percentile_cont(0.8) within group (order by actual_minutes)
    into v_n, v_p50, v_p80
  from public.service_cases
  where service_id = p_service_id and usable and actual_minutes > 0;

  if v_n < p_min_casos then
    return jsonb_build_object(
      'tem_base', false,
      'casos', v_n,
      'mensagem', 'Sem base suficiente: ' || v_n || ' execução(ões) registrada(s), mínimo ' || p_min_casos ||
                  '. Use o tempo padrão do roteiro e trate a estimativa como provisória.'
    );
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'os', so.service_order_number, 'minutos', c.actual_minutes, 'quando', c.created_at::date)
         order by c.created_at desc), '[]'::jsonb)
    into v_casos
  from public.service_cases c
  left join public.service_orders so on so.id = c.service_order_id
  where c.service_id = p_service_id and c.usable and c.actual_minutes > 0
  limit 5;

  return jsonb_build_object(
    'tem_base', true,
    'casos', v_n,
    'p50_min', round(v_p50),
    'p80_min', round(v_p80),
    -- P18: quanto mais espalhado o histórico, maior a contingência.
    'contingencia_pct', least(30, greatest(5, round(((v_p80 - v_p50) / nullif(v_p50,0)) * 100))),
    'baseado_em', v_casos
  );
end;
$fn$;

revoke all on function public.estimate_from_cases(uuid, integer) from public, anon;
grant execute on function public.estimate_from_cases(uuid, integer) to authenticated;
