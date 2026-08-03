-- ═══════════════════════════════════════════════════════════════════════════
-- Correção conceitual: o que importa não é ir a campo, é mexer no sistema
--
-- Pergunta do dono (03/08): "projeto/consultoria está como 'não vai a campo'.
-- Por quê? E se eu tiver uma avaliação em campo? Isso não conta?"
--
-- Ele está certo e o erro é meu. Chamei o campo de `is_fieldwork` e com isso
-- respondi à pergunta errada. A prova está no corpo que eu mesmo escrevi para o
-- verbo: o passo 1 é "Levantar o que existe hoje, com foto e medida" — que é
-- trabalho de campo, num verbo que eu tinha marcado como não sendo.
--
-- O critério correto, que a prática de controle de energia perigosa usa, é a
-- EXPOSIÇÃO, não o lugar: bloqueio é exigido quando alguém fica exposto a
-- energia durante intervenção. Observar, medir por fora e fotografar não expõe;
-- abrir o quadro e mexer no cabo expõe. Um levantamento de projeto acontece no
-- barco e continua sendo observação.
--
-- Então o campo passa a se chamar pelo que ele decide: `intervem_no_sistema`.
-- Os valores não mudam — projeto continua sendo o único `false` —, mas agora o
-- nome diz a verdade e o dono consegue julgar caso a caso na tela.
--
-- E como observação PODE virar intervenção no meio do caminho (o levantamento
-- que precisa abrir o painel para ver o que tem atrás), o corpo do projeto ganha
-- um passo de segurança condicional: quem for abrir, desliga antes.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.service_verbs rename column is_fieldwork to intervem_no_sistema;

comment on column public.service_verbs.intervem_no_sistema is
  'true = o trabalho mexe no sistema e expõe a energia (elétrica, gás, pressão),
   então recebe a abertura e o fechamento de segurança da categoria.
   false = observa, mede e documenta sem intervir — vai a campo do mesmo jeito,
   mas não há o que desligar. O critério é a exposição, não o lugar.';

-- A view e o gerador acompanham o nome novo. `create or replace view` não
-- consegue renomear coluna existente — precisa cair e subir de novo.
drop view if exists public.v_service_verbs_status;

create view public.v_service_verbs_status
with (security_invoker = on) as
select sv.slug, sv.name, sv.intervem_no_sistema, sv.sort, sv.active,
  (select count(*) from public.service_step_blocks b
    where b.applies_to_verb = sv.slug and b.block_role = 'corpo' and b.active) as passos_corpo,
  (select count(*) from public.service_survey_templates t
    where t.applies_to_verb = sv.slug and t.active) as perguntas,
  (select count(*) from public.services s
    where s.service_verb = sv.slug and s.active) as servicos
from public.service_verbs sv;

revoke all on public.v_service_verbs_status from anon;
grant select on public.v_service_verbs_status to authenticated;

-- Só duas linhas do gerador mudam de nome; a lógica é a mesma.
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

  for r_sys in
    select distinct coalesce(sos.service_system, s.service_system) as sistema
    from public.service_order_services sos
    join public.services s on s.id = sos.service_id
    join public.service_systems ss on ss.slug = coalesce(sos.service_system, s.service_system)
    left join public.service_verbs sv on sv.slug = s.service_verb
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
    join public.services s on s.id = sos.service_id
    left join public.service_verbs sv on sv.slug = s.service_verb
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
    left join public.service_verbs sv on sv.slug = s.service_verb
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

-- ─── O levantamento que vira intervenção ────────────────────────────────────
-- Observação e intervenção não são caixas estanques: quem foi medir às vezes
-- precisa abrir o quadro para ver o que há atrás. Este passo entra no corpo do
-- projeto para cobrir exatamente esse momento — sem carregar o bloco inteiro de
-- abertura, que seria excessivo para quem só vai olhar.
do $$
begin
  if exists (select 1 from public.service_step_blocks
             where applies_to_verb = 'projeto' and seq = 8) then
    raise notice 'Passo já existe.';
    return;
  end if;

  insert into public.service_step_blocks
    (block_role, applies_to_system, applies_to_verb, seq, title, detail, kind, mode,
     standard_minutes, is_killer, requires_photo, requires_measure, measure_unit,
     origin, active)
  values
  ('corpo',null,'projeto',8,
   'Se o levantamento exigir abrir painel, quadro ou compartimento: desligue antes',
   'Medir por fora e fotografar não expõe ninguém. Abrir o quadro para ver o que há atrás, sim — e aí vale o mesmo procedimento de quem foi executar: desligar, confirmar ausência de tensão, e só então olhar. Levantamento não é desculpa para trabalhar em circuito vivo.',
   'safety','read_do',10,true,false,null,null,'ai',false);

  raise notice 'Passo de segurança do levantamento inserido.';
end $$;
