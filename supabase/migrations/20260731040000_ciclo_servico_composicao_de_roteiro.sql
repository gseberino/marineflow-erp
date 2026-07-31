-- ═══════════════════════════════════════════════════════════════════════════
-- Ciclo do Serviço — roteiro por COMPOSIÇÃO (P27-P29)
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter
--
-- Roteiro = abertura do SISTEMA + corpo do VERBO + fechamento do SISTEMA.
-- ~23 blocos escritos uma vez cobrem os 261 serviços do catálogo, em vez de
-- ~2.700 passos impossíveis de manter: mudou a regra de segurança de gás,
-- corrige-se UM bloco e todos os serviços de gás acompanham.
--
-- APLICADA EM PRODUÇÃO 31/07/2026 (nome: ciclo_servico_composicao_de_roteiro),
-- seguida da correção fix_classify_service_text_unaccent_schema — a extensão
-- unaccent vive no schema `extensions` neste projeto, não em public, e a função
-- quebrava na primeira chamada. Esta versão do arquivo já traz a correção.
--
-- Resultado da classificação por palavra-chave nos 261 serviços ativos:
--   154 completos (verbo + sistema) = 59%
--    91 parciais (só um dos eixos)  = 35%
--    16 sem classificação           =  6%
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. Os dois eixos, no próprio serviço ───────────────────────────────────
alter table public.services
  add column if not exists service_verb text,
  add column if not exists service_system text,
  add column if not exists classified_by text,      -- 'keyword' | 'ai' | 'human'
  add column if not exists classified_at timestamptz,
  add column if not exists classification_confidence numeric(3,2);

do $$
begin
  if not exists (select 1 from pg_constraint where conname='services_verb_check') then
    alter table public.services add constraint services_verb_check
      check (service_verb is null or service_verb in
        ('instalacao','substituicao','reparo','diagnostico','manutencao',
         'remocao','configuracao','adequacao','logistica'));
  end if;
  if not exists (select 1 from pg_constraint where conname='services_system_check') then
    alter table public.services add constraint services_system_check
      check (service_system is null or service_system in
        ('eletrico_dc','eletrico_ac','gas','hidraulico','eletronico',
         'refrigeracao','mecanico','estrutural','nenhum'));
  end if;
end $$;

create index if not exists services_classificacao on public.services (service_verb, service_system) where active;

-- ─── 2. Os blocos reusáveis ─────────────────────────────────────────────────
-- Abertura e fechamento pertencem ao SISTEMA (todo trabalho em 12V DC começa
-- desligando, seja geladeira, bomba ou guincho). O corpo pertence ao VERBO.
create table if not exists public.service_step_blocks (
  id uuid primary key default gen_random_uuid(),
  block_role text not null check (block_role in ('abertura','corpo','fechamento')),
  applies_to_system text,
  applies_to_verb text,
  seq integer not null,
  title text not null,
  detail text,
  kind text not null default 'do' check (kind in ('do','check','safety','evidence','handoff')),
  mode text not null default 'do_confirm' check (mode in ('read_do','do_confirm')),
  standard_minutes integer,
  is_killer boolean not null default false,
  requires_photo boolean not null default false,
  requires_measure text,
  measure_unit text,
  origin text not null default 'manual' check (origin in ('manual','ai')),
  approved_by uuid references public.app_users(id),
  approved_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint block_tem_eixo check (
    (block_role in ('abertura','fechamento') and applies_to_system is not null)
    or (block_role = 'corpo' and applies_to_verb is not null)),
  constraint block_ai_precisa_aprovacao
    check (origin <> 'ai' or not active or approved_by is not null)
);

create index if not exists step_blocks_sistema on public.service_step_blocks (applies_to_system, block_role, seq) where active;
create index if not exists step_blocks_verbo on public.service_step_blocks (applies_to_verb, seq) where active;

alter table public.service_step_blocks enable row level security;
create policy service_step_blocks_all on public.service_step_blocks
  for all to authenticated
  using (not (select public.is_external_seller(auth.uid())))
  with check (not (select public.is_external_seller(auth.uid())));

create trigger set_updated_at_service_step_blocks
  before update on public.service_step_blocks
  for each row execute function public.update_updated_at_column();

-- ─── 3. Classificação por palavra-chave ─────────────────────────────────────
-- Camada barata, determinística e auditável. A IA não deve ser chamada para
-- reconhecer "instalação de bateria" — isso é um LIKE.
create or replace function public.classify_service_text(p_texto text)
returns jsonb
language plpgsql
immutable
set search_path = public, extensions
as $fn$
declare k text; v text; s text;
begin
  k := regexp_replace(lower(unaccent(coalesce(p_texto,''))), '\s+', ' ', 'g');
  k := regexp_replace(k, '^(servico de |servico |ct - )', '');

  v := case
    when k ~ '(instala|instaca)'                              then 'instalacao'
    when k ~ '(substitui|subtitui|troca)'                     then 'substituicao'
    when k ~ '(reparo|repara|conserto|restaur|recondicion|correcao)' then 'reparo'
    when k ~ '(diagnost|analise|avalia|inspec|vistoria|teste|verifica)' then 'diagnostico'
    when k ~ '(manuten|revisao|limpeza|higieni|desincrust)'    then 'manutencao'
    when k ~ '(remocao|remover|desmontagem|retirada)'          then 'remocao'
    when k ~ '(configura|parametriz|programa|atualiza)'        then 'configuracao'
    when k ~ '(adequa|adapta|modifica|melhoria|upgrade|otimiza|desenvolvimento|confeccao|montagem|ajuste|realocacao|reajuste)' then 'adequacao'
    when k ~ '(frete|deslocamento|visita|hora tecnica|mao de obra|consultoria|assessoria|projeto)' then 'logistica'
    else null end;

  -- Ordem importa: o mais específico primeiro. "aquecedor a gás" é gás, não
  -- elétrico, mesmo tendo resistência.
  s := case
    when k ~ '(gas|glp|fogao|aquecedor|boiler|cooktop)'        then 'gas'
    when k ~ '(geladeira|geleira|ar condicionado|ar-condicionado|climatiz|freezer|condicionador|evaporador)' then 'refrigeracao'
    when k ~ '(agua|hidraulic|bomba d|mangueira|registro|chuveiro|torneira|pia|esgoto|caixa d|pvc|vazamento|escapamento|waterlock|misturador|calafetacao|box)' then 'hidraulico'
    when k ~ '(220v|110v|tomada de cais|quadro ac|ats|transferencia automatica|estabilizador|shore power|gerador)' then 'eletrico_ac'
    when k ~ '(bateria|litio|lifepo|inversor|dc-dc|dc/dc|fusivel|barramento|alternador|usina|victron|mppt|solar|fotovoltaic|12v|24v|shunt|isolador galvanico|carregador|conversor|painel eletric|chave de bateria|cabo eletric|terminal|instalacao eletrica)' then 'eletrico_dc'
    when k ~ '(gps|multimidia|radio|antena|starlink|camera|transducer|display|sensor|alarme|som|alto falante|subwoofer|roteador|monitor|painel de instrumento|vhf|sonda|piloto automatico)' then 'eletronico'
    when k ~ '(guincho|fechadura|amortecedor|corredica|dobradica|suporte|rodado|pneu|roda|slide|esteira|parafus|manipulo|pedaleira|plataforma)' then 'mecanico'
    when k ~ '(teto|parede|piso|isolacao termica|acabamento|movel|armario|gaveta)' then 'estrutural'
    when k ~ '(luz|led|spot|farol|iluminacao)'                 then 'eletrico_dc'
    else null end;

  return jsonb_build_object('verbo', v, 'sistema', s,
    'confianca', case when v is not null and s is not null then 0.9
                      when v is not null or s is not null then 0.5 else 0 end);
end;
$fn$;

revoke all on function public.classify_service_text(text) from public, anon;
grant execute on function public.classify_service_text(text) to authenticated;

-- ─── 4. O COMPOSITOR ────────────────────────────────────────────────────────
-- Devolve os passos SEM gravar: a mesma função serve para a prévia na tela e
-- para a geração. Ver antes de aplicar é o que impede roteiro errado de entrar.
create or replace function public.compose_route_for_service(p_service_id uuid)
returns table (
  seq integer, block text, title text, detail text, kind text, mode text,
  standard_minutes integer, is_killer boolean, requires_photo boolean,
  requires_measure text, measure_unit text, origem_bloco text)
language plpgsql stable security definer set search_path = public
as $fn$
declare v_verb text; v_sys text;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select service_verb, service_system into v_verb, v_sys
  from public.services where id = p_service_id;

  return query
  with partes as (
    select b.*, case b.block_role when 'abertura' then 1 when 'corpo' then 2 else 3 end as ordem_bloco
    from public.service_step_blocks b
    where b.active
      and ((b.block_role in ('abertura','fechamento') and b.applies_to_system = v_sys)
        or (b.block_role = 'corpo' and b.applies_to_verb = v_verb))
  )
  select (row_number() over (order by p.ordem_bloco, p.seq))::integer,
    case p.block_role when 'abertura' then 'Preparação'
                      when 'corpo' then 'Execução' else 'Fechamento' end,
    p.title, p.detail, p.kind, p.mode, p.standard_minutes, p.is_killer,
    p.requires_photo, p.requires_measure, p.measure_unit,
    p.block_role || ' · ' || coalesce(p.applies_to_system, p.applies_to_verb)
  from partes p order by p.ordem_bloco, p.seq;
end;
$fn$;

revoke all on function public.compose_route_for_service(uuid) from public, anon;
grant execute on function public.compose_route_for_service(uuid) to authenticated;

-- ─── 5. Classificação inicial dos 261 serviços ativos ───────────────────────
update public.services s
set service_verb = (public.classify_service_text(s.name)->>'verbo'),
    service_system = (public.classify_service_text(s.name)->>'sistema'),
    classification_confidence = (public.classify_service_text(s.name)->>'confianca')::numeric,
    classified_by = 'keyword',
    classified_at = now()
where s.active and s.classified_at is null;
