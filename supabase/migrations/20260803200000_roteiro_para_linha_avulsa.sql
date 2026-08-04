-- ═══════════════════════════════════════════════════════════════════════════
-- Linha de texto livre também merece roteiro
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter
--
-- Três OS abertas grandes ficam invisíveis para o roteiro porque suas linhas
-- foram digitadas à mão e não apontam para serviço nenhum: OS-00061 (10 de 11),
-- OS-00032 (8 de 9), OS-00060 (7 de 8). São 36 linhas ao todo.
--
-- A saída óbvia seria vinculá-las ao catálogo. Medi antes de fazer, e a medida
-- disse não: das 36, só 3 se parecem com algum serviço existente acima de 0,6
-- de semelhança, e — mais decisivo — **36 linhas têm 36 textos distintos, sem
-- uma repetição sequer**. São descrições de projeto específico, não serviço de
-- catálogo. Criar 36 serviços para usar uma vez cada incharia o catálogo e
-- daria 36 classificações novas para o dono revisar.
--
-- O que a medida sugeriu foi outra coisa: lendo o texto da PRÓPRIA LINHA, a
-- regra de palavra-chave classifica bem — "Reparo de vazamento no box do
-- chuveiro" sai reparo + hidráulico; "Instalação de escapamento úmido,
-- waterlock" sai instalação + hidráulico. Dezessete das 36 saem completas.
--
-- Então a linha passa a poder carregar a própria classificação. O sistema já
-- morava nela desde 02/08 (para os serviços genéricos); agora ganha o verbo, e
-- o gerador passa a enxergar linha sem serviço de catálogo. Mesma composição,
-- mesma segurança, sem catálogo inchado.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.service_order_services
  add column if not exists service_verb text
    references public.service_verbs(slug) on update cascade;

comment on column public.service_order_services.service_verb is
  'Verbo desta linha. Sobrepõe o do catálogo e, em linha de texto livre (sem
   service_id), é a única fonte — é ele que traz o corpo do roteiro.';

create index if not exists so_services_verbo on public.service_order_services (service_verb);

-- ─── O gerador passa a enxergar a linha avulsa ──────────────────────────────
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

  select count(distinct coalesce(block_key, block)) into v_bloco
  from public.service_order_steps where service_order_id = p_service_order_id;

  -- ── Fase A: aberturas ────────────────────────────────────────────────────
  -- `left join services` porque a linha avulsa não tem serviço: a classificação
  -- vem dela mesma.
  for r_sys in
    select distinct coalesce(sos.service_system, s.service_system) as sistema
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    join public.service_systems ss on ss.slug = coalesce(sos.service_system, s.service_system)
    left join public.service_verbs sv on sv.slug = coalesce(sos.service_verb, s.service_verb)
    where sos.service_order_id = p_service_order_id
      and ss.is_physical
      and coalesce(sv.intervem_no_sistema, true)
      and not exists (select 1 from public.service_order_steps st
                      where st.service_order_service_id = sos.id)
      and not exists (select 1 from public.service_step_templates t
                      where t.service_id = sos.service_id and t.active)
    order by 1
  loop
    v_key := 'abertura:' || r_sys.sistema;
    continue when exists (select 1 from public.service_order_steps st
                          where st.service_order_id = p_service_order_id and st.block_key = v_key);

    select count(*), string_agg(public.frase_legivel(sos.name_snapshot), ', ' order by sos.created_at)
      into v_qtd, v_escopo
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    left join public.service_verbs sv on sv.slug = coalesce(sos.service_verb, s.service_verb)
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_system, s.service_system) = r_sys.sistema
      and coalesce(sv.intervem_no_sistema, true);

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

  -- ── Fase B: o corpo de cada linha ────────────────────────────────────────
  -- A condição `service_id is not null` saiu: agora basta a linha ter verbo,
  -- próprio ou herdado do catálogo.
  for r_line in
    select sos.id as line_id, sos.service_id, sos.name_snapshot,
           coalesce(sos.service_verb, s.service_verb) as verbo_efetivo
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_verb, s.service_verb) is not null
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
      where b.active and b.block_role = 'corpo' and b.applies_to_verb = r_line.verbo_efetivo;
    end if;

    get diagnostics v_batch = row_count;
    v_created := v_created + v_batch;
    if v_batch = 0 then v_bloco := v_bloco - 1; end if;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  -- ── Fase C: fechamentos ──────────────────────────────────────────────────
  for r_sys in
    select distinct replace(st.block_key, 'abertura:', '') as sistema
    from public.service_order_steps st
    where st.service_order_id = p_service_order_id and st.block_key like 'abertura:%'
    order by 1
  loop
    v_key := 'fechamento:' || r_sys.sistema;
    continue when exists (select 1 from public.service_order_steps st
                          where st.service_order_id = p_service_order_id and st.block_key = v_key);

    select count(*) into v_qtd
    from public.service_order_services sos
    left join public.services s on s.id = sos.service_id
    left join public.service_verbs sv on sv.slug = coalesce(sos.service_verb, s.service_verb)
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_system, s.service_system) = r_sys.sistema
      and coalesce(sv.intervem_no_sistema, true);

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

-- ─── A lista de pendências passa a cobrir a linha avulsa ────────────────────
-- E a sugestão passa a ler o texto da própria linha, que é a fonte mais direta
-- que existe: o nome que alguém digitou descrevendo o trabalho.
drop function if exists public.lines_missing_system(uuid);

create or replace function public.lines_missing_system(p_service_order_id uuid)
returns table (
  line_id uuid,
  service_name text,
  service_verb text,
  sistema_sugerido text,
  verbo_sugerido text,
  motivo_sugestao text)
language sql stable security invoker set search_path = public, extensions
as $fn$
  select
    sos.id,
    sos.name_snapshot,
    coalesce(sos.service_verb, s.service_verb),
    -- 1º o texto da própria linha; 2º o que já se sabe da OS
    coalesce(
      (select ss.slug from public.service_systems ss
        where ss.slug = (public.classify_service_text(sos.name_snapshot)->>'sistema')
          and ss.is_physical and ss.active),
      (select sug.sistema from public.suggest_system_for_line(sos.id) sug)),
    (select sv.slug from public.service_verbs sv
      where sv.slug = (public.classify_service_text(sos.name_snapshot)->>'verbo') and sv.active),
    case when (public.classify_service_text(sos.name_snapshot)->>'sistema') is not null
              or (public.classify_service_text(sos.name_snapshot)->>'verbo') is not null
         then 'pelo texto desta linha'
         else 'pelo problema relatado nesta OS' end
  from public.service_order_services sos
  left join public.services s on s.id = sos.service_id
  where sos.service_order_id = p_service_order_id
    -- falta o sistema, ou falta o verbo (que a linha avulsa nunca herda)
    and (
      (sos.service_system is null and s.service_system is null)
      or (sos.service_verb is null and s.service_verb is null)
    )
    and not exists (select 1 from public.service_step_templates t
                    where t.service_id = sos.service_id and t.active);
$fn$;

revoke all on function public.lines_missing_system(uuid) from public, anon;
grant execute on function public.lines_missing_system(uuid) to authenticated;

-- Definir os dois eixos de uma linha, de uma vez.
create or replace function public.set_line_classification(
  p_line_id uuid, p_system text, p_verb text)
returns void
language sql security invoker set search_path = public
as $fn$
  update public.service_order_services
  set service_system = nullif(p_system, ''),
      service_verb  = nullif(p_verb, ''),
      updated_at = now()
  where id = p_line_id;
$fn$;

revoke all on function public.set_line_classification(uuid, text, text) from public, anon;
grant execute on function public.set_line_classification(uuid, text, text) to authenticated;
