-- A via do técnico sai com a segurança de cada sistema mesmo sem roteiro (avaliação de 04/10/2026,
-- conclusão dada ao dono em 05/10).
--
-- Desde 01/10 a via impressa leva só os blocos "Antes de mexer" e "Antes de entregar" de cada
-- sistema — mas tirados do ROTEIRO gravado na OS (service_order_steps). Nenhuma OS ganhou roteiro
-- desde 14/08, então as vias saíam sem a parte de segurança e sem aviso.
--
-- Esta função SÓ LÊ: devolve os mesmos blocos que generate_service_order_steps gravaria (fases A e
-- C), para a tela imprimir sem criar roteiro nenhum. O sistema de cada linha vem do cadastro (da
-- linha ou do serviço do catálogo) e, na falta dele, do texto da própria linha
-- (classify_service_text) — a mesma regra que lines_missing_system já sugere ao dono.

create or replace function public.seguranca_da_via(p_service_order_id uuid)
returns table (
  papel             text,     -- 'abertura' | 'fechamento'
  sistema           text,
  bloco             text,     -- rótulo do bloco, como o gerador escreveria
  escopo            text,     -- a quais serviços da OS o bloco vale
  identificado_por  text,     -- 'cadastro' | 'texto da linha'
  seq               integer,
  title             text,
  detail            text,
  kind              text,
  is_killer         boolean,
  requires_photo    boolean,
  requires_measure  text,
  measure_unit      text,
  mode              text,
  standard_minutes  numeric)
language sql
stable
security invoker
set search_path = public
as $fn$
  with linhas as (
    select sos.id, sos.name_snapshot, sos.created_at,
           coalesce(sos.service_system, s.service_system) as gravado,
           coalesce(sos.service_verb, s.service_verb) as verbo
      from public.service_order_services sos
      left join public.services s on s.id = sos.service_id
     where sos.service_order_id = p_service_order_id
  ),
  classificadas as (
    select l.*,
           coalesce(l.gravado,
                    (select ss.slug from public.service_systems ss
                      where ss.slug = (public.classify_service_text(l.name_snapshot)->>'sistema')
                        and ss.is_physical and ss.active)) as sistema,
           case when l.gravado is not null then 'cadastro' else 'texto da linha' end as por
      from linhas l
  ),
  sistemas as (
    select c.sistema,
           min(c.por) as por,  -- 'cadastro' < 'texto da linha': basta uma linha cadastrada
           string_agg(public.frase_legivel(c.name_snapshot), ', ' order by c.created_at) as escopo,
           count(*) as qtd
      from classificadas c
      join public.service_systems ss on ss.slug = c.sistema and ss.is_physical
      left join public.service_verbs sv on sv.slug = c.verbo
     where coalesce(sv.intervem_no_sistema, true)
     group by c.sistema
  )
  select b.block_role::text,
         x.sistema,
         case b.block_role when 'abertura' then 'Antes de mexer — ' else 'Antes de entregar — ' end
           || public.service_system_label(x.sistema),
         case when x.qtd > 1 then 'Vale para os ' || x.qtd || ' serviços desta OS: ' || x.escopo || '.'
              else 'Vale para: ' || x.escopo || '.' end,
         x.por,
         b.seq::integer, b.title::text, b.detail::text, b.kind::text, b.is_killer, b.requires_photo,
         b.requires_measure::text, b.measure_unit::text, b.mode::text, b.standard_minutes::numeric
    from sistemas x
    join public.service_step_blocks b
      on b.active and b.applies_to_system = x.sistema and b.block_role in ('abertura', 'fechamento')
   order by (b.block_role = 'fechamento'), x.sistema, b.seq;
$fn$;

revoke all on function public.seguranca_da_via(uuid) from public;
revoke all on function public.seguranca_da_via(uuid) from anon;
grant execute on function public.seguranca_da_via(uuid) to authenticated;

comment on function public.seguranca_da_via(uuid) is
  'Só leitura: os blocos de segurança (abertura e fechamento) de cada sistema da OS, como generate_service_order_steps gravaria, para a via do técnico imprimir sem roteiro. Sistema do cadastro ou, na falta, do texto da linha. 05/10/2026.';
