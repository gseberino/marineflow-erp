-- ═══════════════════════════════════════════════════════════════════════════
-- O levantamento passa a compor o orçamento
--
-- Até aqui o levantamento perguntava bem e parava. Media-se 14 metros entre o
-- banco e o quadro, anotava-se, e depois alguém digitava o cabo na mão — o
-- trabalho que o levantamento existia para poupar. As 53 perguntas marcadas
-- como "impacto alto no preço" não tinham nada que convertesse esse impacto
-- em preço.
--
-- Uma regra diz: PARA ESTA PERGUNTA, quando a resposta for assim, entra este
-- produto nesta quantidade. É dado, não código: quem escreve a regra é quem
-- conhece o serviço, e ela entra inativa até ser aprovada na tela — o mesmo
-- rito dos blocos de roteiro e das perguntas.
--
-- NADA ENTRA NO ORÇAMENTO SOZINHO. A função de cálculo só devolve uma lista
-- para conferir; lançar é um segundo ato, deliberado.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. As regras
-- ───────────────────────────────────────────────────────────────────────────
create table if not exists public.survey_material_rules (
  id uuid primary key default gen_random_uuid(),

  -- A pergunta que dispara. Sem ela não há o que converter.
  template_id uuid not null references public.service_survey_templates(id) on delete cascade,

  -- Quando vale. 'sempre' serve para pergunta cuja simples resposta já implica
  -- o material (mediu a distância → vai cabo, qualquer que seja o número).
  condition_type text not null default 'sempre'
    check (condition_type in ('sempre', 'igual', 'contem', 'faixa', 'sim', 'nao')),
  match_value text,
  min_value numeric,
  max_value numeric,

  -- O que entra.
  product_id uuid not null references public.products(id) on delete restrict,

  -- Quanto entra.
  --   'fixa'         → qty_fixed, independente da resposta ("sempre 2 terminais")
  --   'proporcional' → resposta × qty_factor ("2 m de cabo por metro medido:
  --                    o positivo vai e o negativo volta")
  --   'por_unidade'  → resposta × qty_factor, para contagem ("1 conector por
  --                    aparelho na linha")
  qty_mode text not null default 'fixa'
    check (qty_mode in ('fixa', 'proporcional', 'por_unidade')),
  qty_fixed numeric not null default 1 check (qty_fixed >= 0),
  qty_factor numeric not null default 1 check (qty_factor >= 0),

  -- Folga. Cabo se corta com sobra: quem mede 14 m e compra 14 m emenda no
  -- meio. A folga é da regra, não do motor, porque cada material tem a sua.
  qty_slack_pct numeric not null default 0 check (qty_slack_pct between 0 and 100),
  qty_round text not null default 'cima' check (qty_round in ('nenhum', 'cima', 'meio')),

  -- Por que esta regra existe. Aparece na tela de aprovação: regra sem
  -- justificativa é número mágico que ninguém ousa mudar depois.
  rationale text,

  origin text not null default 'ai' check (origin in ('ai', 'human')),
  active boolean not null default false,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Uma regra de faixa sem faixa nunca dispararia; uma de igualdade sem valor
  -- casaria com tudo. Melhor o banco recusar do que a regra existir e mentir.
  constraint faixa_precisa_de_limite check (
    condition_type <> 'faixa' or (min_value is not null or max_value is not null)),
  constraint igual_precisa_de_valor check (
    condition_type not in ('igual', 'contem') or match_value is not null),
  -- Regra proporcional com fator zero lançaria quantidade zero em silêncio.
  constraint proporcional_precisa_de_fator check (
    qty_mode = 'fixa' or qty_factor > 0)
);

create index if not exists idx_survey_material_rules_template
  on public.survey_material_rules(template_id) where active;

alter table public.survey_material_rules enable row level security;

-- Leitura para quem trabalha na oficina; escrita fora do vendedor externo, que
-- não tem por que mexer no que compõe custo.
drop policy if exists smr_select on public.survey_material_rules;
create policy smr_select on public.survey_material_rules
  for select to authenticated using (true);

drop policy if exists smr_write on public.survey_material_rules;
create policy smr_write on public.survey_material_rules
  for all to authenticated
  using (not public.is_external_seller(auth.uid()))
  with check (not public.is_external_seller(auth.uid()));

revoke all on table public.survey_material_rules from anon;

comment on table public.survey_material_rules is
  'Converte resposta de levantamento em material do orçamento. Entra inativa e
   só vale depois de aprovada na tela — regra de material mexe em preço.';

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Ler número de uma resposta escrita por gente
--
-- Ninguém digita "14". Digita "14m", "14,5 metros", "aprox 14". O levantamento
-- é preenchido em campo, no celular, muitas vezes de luva. Recusar a resposta
-- por causa da vírgula seria transformar um dado bom em nada.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.parse_answer_number(p_answer text)
returns numeric
language plpgsql immutable set search_path = public
as $fn$
declare v_limpo text; v_num numeric;
begin
  if p_answer is null then return null; end if;
  -- Primeiro número da resposta, aceitando vírgula decimal.
  v_limpo := substring(replace(p_answer, ',', '.') from '(\d+\.?\d*)');
  if v_limpo is null then return null; end if;
  begin
    v_num := v_limpo::numeric;
  exception when others then
    return null;
  end;
  return v_num;
end;
$fn$;

comment on function public.parse_answer_number(text) is
  'Extrai o número de uma resposta digitada em campo ("14,5 m" → 14.5).
   Devolve null quando não há número — o motor trata isso como "não dá para
   calcular", nunca como zero.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. O material que este levantamento sugere
--
-- Só calcula e devolve. Não grava nada. Assim a lista sempre reflete as
-- respostas de agora: corrigiu a medida, a quantidade acompanha.
--
-- Devolve também o que está ERRADO com cada sugestão (campo `alerta`), porque
-- o catálogo tem armadilha real: há produto vendido "por metro" cujo preço é
-- o do trecho inteiro. Multiplicar isso por 14 estoura o orçamento com cara
-- de conta feita. Quem confere precisa ver o aviso junto do número.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.survey_suggested_materials(p_survey_id uuid)
returns table (
  rule_id uuid,
  product_id uuid,
  product_name text,
  unit text,
  question text,
  answer text,
  quantity numeric,
  unit_sale numeric,
  unit_cost numeric,
  line_total numeric,
  rationale text,
  alerta text)
language sql stable security invoker set search_path = public
as $fn$
  with respondidas as (
    select a.template_id, a.answer_value,
           public.parse_answer_number(a.answer_value) as numero
    from public.service_survey_answers a
    where a.survey_id = p_survey_id
      and a.answer_value is not null
      and a.skipped_reason is null
  ),
  casadas as (
    select r.*, q.answer_value, q.numero, t.question as pergunta
    from respondidas q
    join public.survey_material_rules r on r.template_id = q.template_id and r.active
    join public.service_survey_templates t on t.id = r.template_id
    where case r.condition_type
      when 'sempre' then true
      when 'igual'  then lower(trim(q.answer_value)) = lower(trim(r.match_value))
      when 'contem' then q.answer_value ilike '%' || r.match_value || '%'
      when 'sim'    then lower(trim(q.answer_value)) in ('sim', 's', 'true')
      when 'nao'    then lower(trim(q.answer_value)) in ('não', 'nao', 'n', 'false')
      -- Faixa é [min, max): inclusiva embaixo, EXCLUSIVA em cima. Faixas
      -- contíguas ("até 60" e "de 60 a 100") são o uso normal, e com o topo
      -- inclusivo uma corrente de exatamente 60 A casaria com as duas — duas
      -- proteções para o mesmo circuito, na mesma proposta. Na dúvida sobe
      -- para a faixa maior, que é o lado seguro: fusível de 60 A com 60 A
      -- passando abre em serviço.
      when 'faixa'  then q.numero is not null
                        and (r.min_value is null or q.numero >= r.min_value)
                        and (r.max_value is null or q.numero < r.max_value)
      else false
    end
  ),
  quantificadas as (
    select c.*,
      case c.qty_mode
        when 'fixa' then c.qty_fixed
        -- Proporcional e por_unidade só valem com número na resposta. Sem
        -- número, a quantidade fica nula e a linha aparece marcada — melhor
        -- pedir para conferir do que chutar 1.
        else case when c.numero is null then null
                  else c.numero * c.qty_factor end
      end * (1 + c.qty_slack_pct / 100.0) as bruta
    from casadas c
  )
  select
    q.id as rule_id,
    p.id as product_id,
    p.name as product_name,
    p.unit,
    q.pergunta,
    q.answer_value,
    case q.qty_round
      when 'cima' then ceil(q.bruta)
      when 'meio' then ceil(q.bruta * 2) / 2
      else round(q.bruta, 2)
    end as quantity,
    coalesce(p.sale_price, 0) as unit_sale,
    coalesce(p.cost_price, 0) as unit_cost,
    round(coalesce(p.sale_price, 0) * coalesce(
      case q.qty_round
        when 'cima' then ceil(q.bruta)
        when 'meio' then ceil(q.bruta * 2) / 2
        else round(q.bruta, 2)
      end, 0), 2) as line_total,
    q.rationale,
    nullif(concat_ws(' · ',
      case when q.bruta is null
        then 'a resposta não tem número — confira a quantidade' end,
      -- Resposta de campo raramente é um número limpo. "2,5 m até o inversor e
      -- 2 m até o quadro" tem dois trechos, e o motor só leu o primeiro. Somar
      -- por conta própria seria pior: os trechos podem ser alternativas, não
      -- parcelas. Quem conferir decide — mas precisa ser avisado.
      case when q.qty_mode <> 'fixa'
             and (select count(*) from regexp_matches(q.answer_value, '\d+[.,]?\d*', 'g')) > 1
        then 'a resposta tem mais de um número: usei o primeiro ('
             || trim(to_char(q.numero, 'FM999999.99')) || ') — confira se falta somar os outros' end,
      -- Regra que multiplica metros exige produto vendido por metro. O catálogo
      -- tem 16 grafias de unidade; comparar sem normalizar deixaria passar.
      case when q.qty_mode = 'proporcional'
             and lower(coalesce(p.unit, '')) not in ('m', 'mt', 'metro', 'metros')
        then 'a regra calcula metros mas o produto é vendido em "' || coalesce(p.unit, '—') || '"' end,
      case when coalesce(p.cost_price, 0) = 0
        then 'produto sem custo cadastrado: a margem desta linha não é calculável' end,
      case when coalesce(p.sale_price, 0) = 0
        then 'produto sem preço de venda' end
    ), '') as alerta
  from quantificadas q
  join public.products p on p.id = q.product_id
  order by p.name;
$fn$;

revoke all on function public.survey_suggested_materials(uuid) from public, anon;
grant execute on function public.survey_suggested_materials(uuid) to authenticated;

comment on function public.survey_suggested_materials(uuid) is
  'O material que as respostas deste levantamento implicam. Só calcula — não
   grava. Traz `alerta` por linha: unidade incompatível com regra por metro,
   produto sem custo, resposta sem número.';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Lançar o que foi conferido
--
-- Recebe as regras que a pessoa aceitou, não "tudo o que der". Aceitar uma a
-- uma é o ponto: a lista é sugestão, e sugestão que se aplica sozinha vira
-- número que ninguém revisou dentro de uma proposta assinada.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function public.apply_survey_materials(
  p_survey_id uuid,
  p_rule_ids uuid[])
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare
  v_os uuid; v_linha uuid; v_service uuid; v_criadas integer := 0;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select s.service_order_id, s.service_id into v_os, v_service
  from public.service_surveys s where s.id = p_survey_id;

  if v_os is null then
    return jsonb_build_object('ok', false,
      'mensagem', 'Este levantamento não está ligado a um orçamento ou OS.');
  end if;

  -- A linha do serviço, quando existir: é por ela que a folha impressa agrupa
  -- o material por etapa.
  select id into v_linha from public.service_order_services
  where service_order_id = v_os and service_id = v_service
  order by created_at limit 1;

  insert into public.service_order_parts
    (service_order_id, service_order_service_id, product_id, quantity,
     unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale,
     source, notes)
  select v_os, v_linha, m.product_id, m.quantity,
         m.unit_cost, m.unit_sale,
         m.unit_cost * m.quantity, m.unit_sale * m.quantity,
         'survey',
         'Do levantamento: ' || left(m.question, 60) || ' → ' || left(m.answer, 40)
  from public.survey_suggested_materials(p_survey_id) m
  where m.rule_id = any(p_rule_ids)
    and m.quantity is not null
    and m.quantity > 0
    -- Não lança duas vezes o mesmo produto vindo do mesmo levantamento.
    and not exists (
      select 1 from public.service_order_parts x
      where x.service_order_id = v_os
        and x.product_id = m.product_id
        and x.source = 'survey');

  get diagnostics v_criadas = row_count;

  return jsonb_build_object('ok', true, 'linhas_criadas', v_criadas,
    'mensagem', case
      when v_criadas = 0 then 'Nada novo a lançar — esses materiais já estavam no orçamento.'
      else v_criadas || ' item(ns) lançado(s) a partir do levantamento.' end);
end;
$fn$;

revoke all on function public.apply_survey_materials(uuid, uuid[]) from public, anon;
grant execute on function public.apply_survey_materials(uuid, uuid[]) to authenticated;

comment on function public.apply_survey_materials(uuid, uuid[]) is
  'Lança no orçamento apenas as sugestões escolhidas (source=survey). DEFINER
   porque grava — e por isso checa is_external_seller na primeira linha.';
