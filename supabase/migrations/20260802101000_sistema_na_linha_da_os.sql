-- ═══════════════════════════════════════════════════════════════════════════
-- O sistema passa a ser resolvido na LINHA da OS, não só no catálogo
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter (P27)
--
-- Observação do dono (02/08): "alguns [serviços] são genéricos e se enquadram
-- em várias categorias, como o diagnóstico técnico em bancada ou no local, este
-- serviço pode ser elétrico, mecânico, DC ou AC."
--
-- Ele está certo, e o erro é meu: os dois eixos são ortogonais e estão certos,
-- mas eu fixei a CARDINALIDADE. Gravei um valor por serviço quando, em dez
-- deles, o sistema só se conhece na hora do trabalho.
--
-- A consequência era de SEGURANÇA, não de organização: classificados como
-- `nenhum`, esses serviços recebiam o corpo do verbo e NENHUM bloco de
-- abertura. Um diagnóstico num sistema de gás saía sem fechar o registro, sem
-- ventilar e sem eliminar fontes de ignição — o roteiro calado exatamente onde
-- mais importa.
--
-- Desenho escolhido pelo dono: o catálogo continua sendo o molde, e a linha da
-- OS é onde o caso real se resolve — que é como Salesforce e Dynamics separam
-- tipo de trabalho de item da ordem. Efeito colateral bem-vindo: o técnico que
-- descobre no local que o problema era de gás marca o sistema e o roteiro ganha
-- o bloco de segurança DURANTE a execução. Hoje isso é impossível.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.service_order_services
  add column if not exists service_system text
    references public.service_systems(slug) on update cascade;

comment on column public.service_order_services.service_system is
  'Sistema que ESTA linha toca. Sobrepõe o do catálogo — é assim que um serviço
   genérico ("diagnóstico no local") vira elétrico numa OS e gás na seguinte.
   Nulo = usa o do serviço.';

create index if not exists so_services_sistema on public.service_order_services (service_system);

-- ─── O gerador passa a perguntar à linha antes do catálogo ──────────────────
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

  -- ── Fase A: antes de mexer, um bloco por sistema ─────────────────────────
  -- `coalesce(sos.service_system, s.service_system)` é a mudança inteira: a
  -- linha manda, o catálogo é o padrão.
  for r_sys in
    select distinct coalesce(sos.service_system, s.service_system) as sistema
    from public.service_order_services sos
    join public.services s on s.id = sos.service_id
    join public.service_systems ss on ss.slug = coalesce(sos.service_system, s.service_system)
    where sos.service_order_id = p_service_order_id
      and ss.is_physical           -- 'nenhum' não abre nada: não há o que desligar
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
    join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_system, s.service_system) = r_sys.sistema;

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
    if v_batch = 0 then v_bloco := v_bloco - 1; end if;

    select coalesce(max(seq), 0) into v_seq
    from public.service_order_steps where service_order_id = p_service_order_id;
  end loop;

  -- ── Fase C: fechamentos, simétricos à abertura ───────────────────────────
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
    join public.services s on s.id = sos.service_id
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_system, s.service_system) = r_sys.sistema;

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

-- ─── NULL passa a significar "indeterminado", não "não classificado" ────────
-- Antes desta migration, NULL queria dizer "ninguém classificou ainda" — e por
-- isso marquei os genéricos como `nenhum`. Só que `nenhum` é uma AFIRMAÇÃO
-- ("não toca sistema físico") e genérico é uma PERGUNTA ("qual deles?"). Com o
-- catálogo 100% classificado, NULL fica livre para o segundo significado, e as
-- duas situações param de se confundir:
--
--   NULL      → o sistema depende da OS. Escolher na linha.  → alerta na tela
--   'nenhum'  → não toca sistema físico (frete, mão de obra) → sem alerta
--
-- Os nove abaixo são os que o dono apontou: "este serviço pode ser elétrico,
-- mecânico, DC ou AC".
update public.services set
  service_system = null,
  classified_by = 'ai',
  classified_at = now(),
  classification_confidence = 0.5
where id in (
  'd70a0160-eb16-4063-8d5b-1bd18f1ac110',  -- DIAGNÓSTICO TÉCNICO NO LOCAL
  '7a1c524f-2a63-4a32-9995-87258e487e76',  -- DIAGNÓSTICO TÉCNICO EM BANCADA
  '6eb2b8a9-5803-41fd-b292-173287ae16c7',  -- Diagnóstico Equipamentos com Defeito
  '821125a7-2978-471b-b8a0-ff7d172b5017',  -- TESTE TÉCNICO DE FUNCIONAMENTO
  '9d6e2403-e4c1-4c62-873e-c6a9b77d37d1',  -- COMISSIONAMENTO E VALIDAÇÃO DE GARANTIA
  'fa29568f-a6a3-41c8-866c-9d6be3b783a0',  -- Substituição e Instalação Equipamentos
  '3db1f0b5-e344-403e-b3b4-91a4e771758d',  -- CT - Instalação e Fixação
  '61d69409-f3ad-449f-9c98-0202eccbbc51',  -- IT - Instalação e Configuração
  'f4340279-f29c-424a-8a5b-429ce89c1c99'   -- Assistência Técnica Autorizada Marine Center
);

-- ─── Quem está sem preparação de segurança ──────────────────────────────────
-- A tela usa isto para avisar ANTES de gerar o roteiro, em vez de deixar a
-- ausência passar em silêncio como acontecia até aqui.
create or replace function public.lines_missing_system(p_service_order_id uuid)
returns table (line_id uuid, service_name text, service_verb text)
language sql stable security definer set search_path = public as $fn$
  select sos.id, sos.name_snapshot, s.service_verb
  from public.service_order_services sos
  join public.services s on s.id = sos.service_id
  where sos.service_order_id = p_service_order_id
    -- indeterminado nos dois níveis: nem a linha escolheu, nem o catálogo sabe
    and sos.service_system is null
    and s.service_system is null
    -- quem tem template traz a própria preparação dentro dele
    and not exists (select 1 from public.service_step_templates t
                    where t.service_id = sos.service_id and t.active);
$fn$;

revoke all on function public.lines_missing_system(uuid) from public, anon;
grant execute on function public.lines_missing_system(uuid) to authenticated;
