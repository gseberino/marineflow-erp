-- ═══════════════════════════════════════════════════════════════════════════
-- Ciclo do Serviço — o roteiro composto finalmente chega na OS
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter (P27)
--
-- O dono aprovou os 116 passos dos 23 blocos em 31/07 e nada mudou nas OS:
-- generate_service_order_steps() só sabia ler service_step_templates, que
-- existem para 5 dos 261 serviços. compose_route_for_service() estava pronta
-- e não era chamada por ninguém — nem pelo app, nem pelas tools da IA.
--
-- Precedência decidida pelo dono (31/07): **o template ganha**.
--   linha com template escrito  → usa o template, como sempre foi
--   linha sem template          → compõe: abertura do sistema + corpo do verbo
--                                 + fechamento do sistema
-- Sem soma dos dois: o template do pacote elétrico já traz "Desligar tudo e
-- confirmar ausência de tensão", que é o mesmo passo da abertura do DC.
--
-- Duas decisões de desenho que valem explicação:
--
-- 1. A abertura do sistema entra UMA VEZ POR OS, não uma vez por linha.
--    "Todo trabalho em 12V DC começa desligando a alimentação" — desliga-se
--    uma vez, mesmo que a OS tenha três serviços de 12V. A repetição do mesmo
--    passo de segurança é o caminho mais curto para o técnico parar de ler.
--
-- 2. Esses passos compartilhados ficam com service_order_service_id nulo.
--    Preparação e fechamento são tempo da OS, não de uma linha; pendurá-los na
--    primeira linha inflaria o custo dela e mentiria na margem. O rollup já
--    ignora passo sem linha (guard `v_line is null`), então isso é seguro.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. origin precisa saber dizer "composto" ───────────────────────────────
-- Lista fechada: sem isto o INSERT da composição falha em tempo de execução.
alter table public.service_order_steps
  drop constraint if exists service_order_steps_origin_check;
alter table public.service_order_steps
  add constraint service_order_steps_origin_check
  check (origin in ('template','ai','manual','client_request','composed'));

-- ─── 2. Rótulo legível do sistema ───────────────────────────────────────────
-- Serve ao agrupamento na tela e, de quebra, ao dedupe: o bloco do passo
-- compartilhado é 'Preparação · Elétrico DC', e é por ele que a função
-- reconhece que aquela abertura já está na OS.
create or replace function public.service_system_label(p_system text)
returns text language sql immutable set search_path = public as $fn$
  select case p_system
    when 'eletrico_dc'  then 'Elétrico DC'
    when 'eletrico_ac'  then 'Elétrico AC'
    when 'gas'          then 'Gás GLP'
    when 'hidraulico'   then 'Hidráulico'
    when 'eletronico'   then 'Eletrônico'
    when 'refrigeracao' then 'Refrigeração'
    when 'mecanico'     then 'Mecânico'
    when 'estrutural'   then 'Estrutural'
    else p_system end;
$fn$;

revoke all on function public.service_system_label(text) from public, anon;
grant execute on function public.service_system_label(text) to authenticated;

-- ─── 3. O gerador, agora com as duas fontes ─────────────────────────────────
create or replace function public.generate_service_order_steps(p_service_order_id uuid)
returns integer
language plpgsql security definer set search_path = public
as $fn$
declare
  v_created integer := 0;
  v_batch integer := 0;
  v_seq integer;
  r_line record;
  v_tem_template boolean;
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

  -- ── Fase A: aberturas dos sistemas que a OS vai tocar ────────────────────
  -- Um conjunto por sistema, antes de qualquer execução. Só para as linhas que
  -- serão compostas: quem tem template traz a própria preparação dentro dele.
  insert into public.service_order_steps (
    service_order_id, service_order_service_id, template_id, seq, block, title, detail,
    kind, mode, standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
    origin)
  select
    p_service_order_id, null, null,
    v_seq + row_number() over (order by public.service_system_label(b.applies_to_system), b.seq),
    'Preparação · ' || public.service_system_label(b.applies_to_system),
    b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
    b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
  from public.service_step_blocks b
  where b.active
    and b.block_role = 'abertura'
    and b.applies_to_system in (
      select distinct s.service_system
      from public.service_order_services sos
      join public.services s on s.id = sos.service_id
      where sos.service_order_id = p_service_order_id
        and s.service_system is not null
        and not exists (select 1 from public.service_order_steps st
                        where st.service_order_service_id = sos.id)
        and not exists (select 1 from public.service_step_templates t
                        where t.service_id = sos.service_id and t.active))
    -- Idempotência: a abertura daquele sistema já está na OS?
    and not exists (
      select 1 from public.service_order_steps st
      where st.service_order_id = p_service_order_id
        and st.block = 'Preparação · ' || public.service_system_label(b.applies_to_system));

  get diagnostics v_batch = row_count;
  v_created := v_created + v_batch;

  select coalesce(max(seq), 0) into v_seq
  from public.service_order_steps where service_order_id = p_service_order_id;

  -- ── Fase B: o corpo de cada linha ────────────────────────────────────────
  for r_line in
    select sos.id as line_id, sos.service_id, sos.name_snapshot, s.service_verb
    from public.service_order_services sos
    join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
      and sos.service_id is not null
      and not exists (select 1 from public.service_order_steps st
                      where st.service_order_service_id = sos.id)
    order by sos.created_at
  loop
    select exists (
      select 1 from public.service_step_templates t
      where t.service_id = r_line.service_id and t.active
    ) into v_tem_template;

    if v_tem_template then
      -- Template escrito para este serviço: ele manda, inteiro.
      insert into public.service_order_steps (
        service_order_id, service_order_service_id, template_id, seq, block, title, detail,
        kind, mode, standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
        origin)
      select
        p_service_order_id, r_line.line_id, t.id,
        v_seq + row_number() over (order by t.seq),
        coalesce(t.block, r_line.name_snapshot),
        t.title, t.detail, t.kind, t.mode, t.standard_minutes, t.is_killer,
        t.requires_photo, t.requires_measure, t.measure_unit, 'template'
      from public.service_step_templates t
      where t.service_id = r_line.service_id
        and t.active
        and t.version = (select max(version) from public.service_step_templates
                         where service_id = r_line.service_id and active);
    else
      -- Sem template: o corpo do verbo, nomeado pelo serviço da linha para que
      -- o técnico saiba de qual dos serviços da OS aquele trecho fala.
      insert into public.service_order_steps (
        service_order_id, service_order_service_id, template_id, seq, block, title, detail,
        kind, mode, standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
        origin)
      select
        p_service_order_id, r_line.line_id, null,
        v_seq + row_number() over (order by b.seq),
        r_line.name_snapshot,
        b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
        b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
      from public.service_step_blocks b
      where b.active
        and b.block_role = 'corpo'
        and b.applies_to_verb = r_line.service_verb;
    end if;

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  -- ── Fase C: fechamentos, depois de tudo executado ────────────────────────
  -- A regra é a simetria, e ela é deliberada: **todo sistema que teve abertura
  -- ganha fechamento**. Amarrar o fechamento à existência de corpo deixaria a
  -- OS com "desligue a alimentação" sem o "confira antes de energizar" sempre
  -- que o serviço tivesse sistema mas não verbo — e desenergizar sem o passo
  -- de reenergizar com teste é exatamente o que não pode faltar.
  insert into public.service_order_steps (
    service_order_id, service_order_service_id, template_id, seq, block, title, detail,
    kind, mode, standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
    origin)
  select
    p_service_order_id, null, null,
    v_seq + row_number() over (order by public.service_system_label(b.applies_to_system), b.seq),
    'Fechamento · ' || public.service_system_label(b.applies_to_system),
    b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
    b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
  from public.service_step_blocks b
  where b.active
    and b.block_role = 'fechamento'
    -- Fecha o que foi aberto: existe 'Preparação · <sistema>' nesta OS?
    and exists (
      select 1 from public.service_order_steps st
      where st.service_order_id = p_service_order_id
        and st.block = 'Preparação · ' || public.service_system_label(b.applies_to_system))
    and not exists (
      select 1 from public.service_order_steps st
      where st.service_order_id = p_service_order_id
        and st.block = 'Fechamento · ' || public.service_system_label(b.applies_to_system));

  get diagnostics v_batch = row_count;
  v_created := v_created + v_batch;

  return v_created;
end;
$fn$;

revoke all on function public.generate_service_order_steps(uuid) from public, anon;
grant execute on function public.generate_service_order_steps(uuid) to authenticated;
