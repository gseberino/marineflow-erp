-- ═══════════════════════════════════════════════════════════════════════════
-- Tipos de serviço viram cadastro (simetria com as categorias) + verbo "projeto"
--
-- Pedido do dono (03/08): "criar uma nova categoria e um novo tipo de serviço,
-- pois tem alguns que são projetos e não tem nenhum na lista ali."
--
-- Ele apontou uma assimetria que eu deixei: em 02/08 os SISTEMAS viraram
-- cadastro e os VERBOS continuaram como lista fixa em CHECK. Pior, a falta de
-- um verbo adequado forçou classificação errada — sete serviços de projeto e
-- assessoria ficaram como `logistica`, que é frete e deslocamento. Eles
-- recebiam o roteiro de quem viaja: "confirmar endereço e acesso", "conferir
-- ferramenta antes de sair", "fotografar o estado do bem na retirada". Para
-- "elaboração de projeto elétrico" isso é ruído puro.
--
-- E um efeito que só se enxerga com o verbo certo na mesa: "Projeto Elétrico"
-- tem sistema `eletrico_dc`, então o compositor lhe daria "desligar a
-- alimentação e desconectar o negativo do banco" — num trabalho de escritório.
-- Daí o campo `is_fieldwork`: verbo que não vai a campo NÃO puxa abertura nem
-- fechamento de sistema, por mais que o sistema esteja preenchido. O sistema
-- continua ali dizendo de que projeto se trata (elétrico? hidráulico?), que é
-- informação boa — só não vira procedimento de segurança.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.service_verbs (
  slug text primary key,
  name text not null,
  is_fieldwork boolean not null default true,
  sort integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.service_verbs is
  'Tipos de serviço (o que se faz). O verbo traz o corpo do roteiro; o sistema
   traz a abertura e o fechamento de segurança.';
comment on column public.service_verbs.is_fieldwork is
  'false = trabalho que não vai a campo (projeto, consultoria). Não recebe
   abertura nem fechamento de sistema, mesmo com sistema preenchido — não há
   alimentação para desligar em uma prancheta.';

insert into public.service_verbs (slug, name, is_fieldwork, sort) values
  ('instalacao',   'Instalação',              true,  10),
  ('substituicao', 'Substituição',            true,  20),
  ('reparo',       'Reparo',                  true,  30),
  ('diagnostico',  'Diagnóstico',             true,  40),
  ('manutencao',   'Manutenção',              true,  50),
  ('remocao',      'Remoção / desmontagem',   true,  60),
  ('configuracao', 'Configuração',            true,  70),
  ('adequacao',    'Adequação',               true,  80),
  ('logistica',    'Logística / deslocamento',true,  90),
  ('projeto',      'Projeto / consultoria',   false, 95)
on conflict (slug) do nothing;

alter table public.service_verbs enable row level security;

create policy service_verbs_read on public.service_verbs
  for select to authenticated
  using (not (select public.is_external_seller(auth.uid())));

create policy service_verbs_write on public.service_verbs
  for all to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create trigger set_updated_at_service_verbs
  before update on public.service_verbs
  for each row execute function public.update_updated_at_column();

-- ─── CHECKs viram FK, como nos sistemas ─────────────────────────────────────
alter table public.services drop constraint if exists services_verb_check;
alter table public.services
  add constraint services_verb_fk
  foreign key (service_verb) references public.service_verbs(slug) on update cascade;

alter table public.service_survey_templates drop constraint if exists survey_tpl_verb_check;
alter table public.service_survey_templates
  add constraint survey_tpl_verb_fk
  foreign key (applies_to_verb) references public.service_verbs(slug) on update cascade;

alter table public.service_step_blocks
  add constraint step_blocks_verb_fk
  foreign key (applies_to_verb) references public.service_verbs(slug) on update cascade;

-- ─── Os sete serviços que estavam no verbo errado ───────────────────────────
update public.services set
  service_verb = 'projeto',
  classified_by = 'ai',
  classified_at = now(),
  classification_confidence = 0.8
where active and service_verb = 'logistica'
  and (name ilike '%projeto%' or name ilike '%assessoria%' or name ilike '%consultoria%');

-- ─── O gerador respeita is_fieldwork ────────────────────────────────────────
-- Única mudança: a Fase A passa a exigir que o VERBO vá a campo, além de o
-- sistema ser físico. Projeto elétrico deixa de receber "desligue a alimentação".
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
  for r_sys in
    select distinct coalesce(sos.service_system, s.service_system) as sistema
    from public.service_order_services sos
    join public.services s on s.id = sos.service_id
    join public.service_systems ss on ss.slug = coalesce(sos.service_system, s.service_system)
    left join public.service_verbs sv on sv.slug = s.service_verb
    where sos.service_order_id = p_service_order_id
      and ss.is_physical
      and coalesce(sv.is_fieldwork, true)   -- projeto não desliga alimentação
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
      and coalesce(sv.is_fieldwork, true);

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
    left join public.service_verbs sv on sv.slug = s.service_verb
    where sos.service_order_id = p_service_order_id
      and coalesce(sos.service_system, s.service_system) = r_sys.sistema
      and coalesce(sv.is_fieldwork, true);

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

-- ─── Status dos verbos, para a tela avisar quando falta o corpo ─────────────
create or replace view public.v_service_verbs_status
with (security_invoker = on) as
select sv.slug, sv.name, sv.is_fieldwork, sv.sort, sv.active,
  (select count(*) from public.service_step_blocks b
    where b.applies_to_verb = sv.slug and b.block_role = 'corpo' and b.active) as passos_corpo,
  (select count(*) from public.service_survey_templates t
    where t.applies_to_verb = sv.slug and t.active) as perguntas,
  (select count(*) from public.services s
    where s.service_verb = sv.slug and s.active) as servicos
from public.service_verbs sv;

revoke all on public.v_service_verbs_status from anon;
grant select on public.v_service_verbs_status to authenticated;
