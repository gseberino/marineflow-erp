-- ═══════════════════════════════════════════════════════════════════════════
-- Ciclo do Serviço — o roteiro dito na língua de quem executa
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter
--
-- Observação do dono na OS-00051: "Preparação · Eletrônico não diz de qual
-- serviço representa... poderia estar mais explícito do que se trata, o que o
-- técnico terá que fazer."
--
-- Ele está certo, e a causa é a decisão de compartilhar a abertura entre as
-- linhas do mesmo sistema: o bloco passou a valer para três serviços e o
-- escopo ficou implícito. O técnico via um bloco órfão, sem dono e sem
-- explicação — e "Eletrônico" é o nome interno do eixo, não a palavra de quem
-- trabalha.
--
-- Três mudanças:
--   1. block_key  — chave estável ('abertura:gas'), para dedupe e agrupamento
--   2. block      — vira RÓTULO de exibição: "1 · Antes de mexer — Gás GLP"
--   3. block_note — a linha de escopo: "Vale para os 3 serviços desta OS: ..."
--
-- E, atendendo ao pedido de materiais por etapa: service_order_parts ganha o
-- vínculo com a linha de serviço, que não existia. Material com dono aparece
-- na etapa; material sem dono entra na separação geral da folha.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. Colunas novas ───────────────────────────────────────────────────────
alter table public.service_order_steps
  add column if not exists block_key text,
  add column if not exists block_note text;

comment on column public.service_order_steps.block_key is
  'Chave estável do bloco (abertura:gas, linha:<uuid>, fechamento:gas). O rótulo
   em `block` muda com a numeração; esta não muda, e é por ela que se deduplica.';
comment on column public.service_order_steps.block_note is
  'Linha de escopo do bloco compartilhado: a quais serviços da OS ele se aplica.';

create index if not exists so_steps_block_key on public.service_order_steps (service_order_id, block_key);

-- Material por etapa: o vínculo que faltava. Nulo = material da OS inteira,
-- que é o caso de todos os 200 lançamentos manuais de hoje.
alter table public.service_order_parts
  add column if not exists service_order_service_id uuid
    references public.service_order_services(id) on delete set null;

create index if not exists so_parts_por_linha on public.service_order_parts (service_order_service_id);

-- ─── 2. Nome de serviço legível ─────────────────────────────────────────────
-- O catálogo tem nomes gritados em caixa alta ("INSTAÇÃO DE MULTIMEDIA CONSOLE
-- VEÍCULO" — com o erro de digitação e tudo). Em papel, caixa alta cansa e
-- atrapalha a leitura. Só normaliza o que está TODO em maiúsculas: nome já
-- escrito em caixa mista é preservado, senão "LiFePO4/Victron" viraria
-- "lifepo4/victron".
create or replace function public.frase_legivel(p_texto text)
returns text language sql immutable set search_path = public as $fn$
  select case
    when p_texto is null or p_texto = '' then p_texto
    when p_texto <> upper(p_texto) then p_texto          -- já tem caixa mista
    else upper(left(lower(p_texto), 1)) || substr(lower(p_texto), 2)
  end;
$fn$;

revoke all on function public.frase_legivel(text) from public, anon;
grant execute on function public.frase_legivel(text) to authenticated;

-- ─── 3. O gerador, agora falando com o técnico ──────────────────────────────
create or replace function public.generate_service_order_steps(p_service_order_id uuid)
returns integer
language plpgsql security definer set search_path = public
as $fn$
declare
  v_created integer := 0;
  v_batch integer := 0;
  v_seq integer;
  v_bloco integer;
  r_line record;
  r_sys record;
  v_tem_template boolean;
  v_key text;
  v_rotulo text;
  v_escopo text;
  v_qtd integer;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão para gerar roteiro' using errcode = '42501';
  end if;

  if not exists (select 1 from public.service_orders where id = p_service_order_id) then
    raise exception 'Ordem de serviço % não encontrada', p_service_order_id;
  end if;

  select coalesce(max(seq), 0) into v_seq
  from public.service_order_steps where service_order_id = p_service_order_id;

  -- A numeração dos blocos continua de onde parou, para o caso de a OS ganhar
  -- uma linha nova depois do roteiro já gerado.
  select count(distinct coalesce(block_key, block)) into v_bloco
  from public.service_order_steps where service_order_id = p_service_order_id;

  -- ── Fase A: antes de mexer, um bloco por sistema ─────────────────────────
  for r_sys in
    select distinct s.service_system as sistema
    from public.service_order_services sos
    join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
      and s.service_system is not null
      and not exists (select 1 from public.service_order_steps st
                      where st.service_order_service_id = sos.id)
      and not exists (select 1 from public.service_step_templates t
                      where t.service_id = sos.service_id and t.active)
    order by 1
  loop
    v_key := 'abertura:' || r_sys.sistema;
    continue when exists (select 1 from public.service_order_steps st
                          where st.service_order_id = p_service_order_id and st.block_key = v_key);

    -- O escopo, escrito por extenso: é isto que faltava na folha.
    select count(*), string_agg(public.frase_legivel(sos.name_snapshot), ', ' order by sos.created_at)
      into v_qtd, v_escopo
    from public.service_order_services sos
    join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id and s.service_system = r_sys.sistema;

    v_bloco := v_bloco + 1;
    v_rotulo := v_bloco || ' · Antes de mexer — ' || public.service_system_label(r_sys.sistema);

    insert into public.service_order_steps (
      service_order_id, service_order_service_id, template_id, seq, block, block_key, block_note,
      title, detail, kind, mode, standard_minutes, is_killer, requires_photo,
      requires_measure, measure_unit, origin)
    select
      p_service_order_id, null, null, v_seq + row_number() over (order by b.seq),
      v_rotulo, v_key,
      case when v_qtd > 1
           then 'Vale para os ' || v_qtd || ' serviços desta OS: ' || v_escopo || '.'
           else 'Vale para: ' || v_escopo || '.' end,
      b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
      b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
    from public.service_step_blocks b
    where b.active and b.block_role = 'abertura' and b.applies_to_system = r_sys.sistema;

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  -- ── Fase B: o serviço em si, um bloco por linha ──────────────────────────
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
    select exists (select 1 from public.service_step_templates t
                   where t.service_id = r_line.service_id and t.active) into v_tem_template;

    v_bloco := v_bloco + 1;
    v_key := 'linha:' || r_line.line_id;
    v_rotulo := v_bloco || ' · ' || public.frase_legivel(r_line.name_snapshot);

    if v_tem_template then
      insert into public.service_order_steps (
        service_order_id, service_order_service_id, template_id, seq, block, block_key,
        title, detail, kind, mode, standard_minutes, is_killer, requires_photo,
        requires_measure, measure_unit, origin)
      select
        p_service_order_id, r_line.line_id, t.id, v_seq + row_number() over (order by t.seq),
        v_rotulo, v_key,
        t.title, t.detail, t.kind, t.mode, t.standard_minutes, t.is_killer,
        t.requires_photo, t.requires_measure, t.measure_unit, 'template'
      from public.service_step_templates t
      where t.service_id = r_line.service_id
        and t.active
        and t.version = (select max(version) from public.service_step_templates
                         where service_id = r_line.service_id and active);
    else
      insert into public.service_order_steps (
        service_order_id, service_order_service_id, template_id, seq, block, block_key,
        title, detail, kind, mode, standard_minutes, is_killer, requires_photo,
        requires_measure, measure_unit, origin)
      select
        p_service_order_id, r_line.line_id, null, v_seq + row_number() over (order by b.seq),
        v_rotulo, v_key,
        b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
        b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
      from public.service_step_blocks b
      where b.active and b.block_role = 'corpo' and b.applies_to_verb = r_line.service_verb;
    end if;

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;

    -- Bloco sem nenhum passo (serviço sem verbo classificado) não consome número.
    if v_batch = 0 then v_bloco := v_bloco - 1; end if;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  -- ── Fase C: antes de entregar, fechando o que foi aberto ─────────────────
  for r_sys in
    select distinct replace(st.block_key, 'abertura:', '') as sistema
    from public.service_order_steps st
    where st.service_order_id = p_service_order_id
      and st.block_key like 'abertura:%'
    order by 1
  loop
    v_key := 'fechamento:' || r_sys.sistema;
    continue when exists (select 1 from public.service_order_steps st
                          where st.service_order_id = p_service_order_id and st.block_key = v_key);

    select count(*) into v_qtd
    from public.service_order_services sos
    join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id and s.service_system = r_sys.sistema;

    v_bloco := v_bloco + 1;
    v_rotulo := v_bloco || ' · Antes de entregar — ' || public.service_system_label(r_sys.sistema);

    insert into public.service_order_steps (
      service_order_id, service_order_service_id, template_id, seq, block, block_key, block_note,
      title, detail, kind, mode, standard_minutes, is_killer, requires_photo,
      requires_measure, measure_unit, origin)
    select
      p_service_order_id, null, null, v_seq + row_number() over (order by b.seq),
      v_rotulo, v_key,
      case when v_qtd > 1
           then 'Fecha os ' || v_qtd || ' serviços de ' ||
                lower(public.service_system_label(r_sys.sistema)) || ' desta OS.'
           else 'Fecha o serviço de ' ||
                lower(public.service_system_label(r_sys.sistema)) || ' desta OS.' end,
      b.title, b.detail, b.kind, b.mode, b.standard_minutes, b.is_killer,
      b.requires_photo, b.requires_measure, b.measure_unit, 'composed'
    from public.service_step_blocks b
    where b.active and b.block_role = 'fechamento' and b.applies_to_system = r_sys.sistema;

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  return v_created;
end;
$fn$;

revoke all on function public.generate_service_order_steps(uuid) from public, anon;
grant execute on function public.generate_service_order_steps(uuid) to authenticated;

-- ─── 4. O kit passa a dizer de que serviço o material é ─────────────────────
-- Sem isto, o material entra na OS sem dono e a folha nunca consegue dizer o
-- que se usa em cada etapa.
create or replace function public.apply_service_material_kit(p_service_order_id uuid, p_service_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $fn$
declare v_kit uuid; v_linha uuid; v_criadas integer := 0; v_ja integer := 0;
begin
  if (select public.is_external_seller(auth.uid())) then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;

  select material_kit_product_id into v_kit from public.services where id = p_service_id;
  if v_kit is null then
    return jsonb_build_object('ok', false,
      'mensagem', 'Este serviço não tem kit de materiais cadastrado. Cadastre o kit no catálogo (produto do tipo kit) e ligue-o ao serviço.');
  end if;

  -- A linha da OS que corresponde a este serviço: é ela que passa a ser dona
  -- do material, e é por ela que a folha agrupa o material por etapa.
  select id into v_linha
  from public.service_order_services
  where service_order_id = p_service_order_id and service_id = p_service_id
  order by created_at limit 1;

  select count(*) into v_ja
  from public.service_order_parts sop
  join public.product_components pc on pc.component_product_id = sop.product_id
  where sop.service_order_id = p_service_order_id
    and pc.parent_product_id = v_kit and sop.source = 'kit';

  insert into public.service_order_parts
    (service_order_id, service_order_service_id, product_id, quantity,
     unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale, source, notes)
  select p_service_order_id, v_linha, pc.component_product_id, pc.quantity,
         coalesce(p.cost_price, 0), coalesce(p.sale_price, 0),
         coalesce(p.cost_price, 0) * pc.quantity, coalesce(p.sale_price, 0) * pc.quantity,
         'kit', 'Do kit de materiais do serviço'
  from public.product_components pc
  join public.products p on p.id = pc.component_product_id
  where pc.parent_product_id = v_kit
    and not exists (
      select 1 from public.service_order_parts x
      where x.service_order_id = p_service_order_id
        and x.product_id = pc.component_product_id and x.source = 'kit');

  get diagnostics v_criadas = row_count;

  return jsonb_build_object('ok', true, 'linhas_criadas', v_criadas, 'ja_estavam', v_ja,
    'mensagem', case
      when v_criadas = 0 and v_ja > 0 then 'O kit já estava aplicado nesta OS.'
      when v_criadas = 0 then 'O kit não tem componentes cadastrados.'
      else v_criadas || ' item(ns) de material lançado(s).' end);
end;
$fn$;

revoke all on function public.apply_service_material_kit(uuid, uuid) from public, anon;
grant execute on function public.apply_service_material_kit(uuid, uuid) to authenticated;
