-- Retorno rápido ao cliente, decisões do dono de 20/11/2026 (rr-f3-1b e a medida do rr-f3-2b). Gerada por
-- scripts/gerar_meta.cjs a partir da view vigente (20261208100600_retorno_f3_medidas); só os trechos descritos mudam.
--
-- 1. rr-f3-1b: a meta da proposta automática passa de "até 1 item corrigido" para "até 3 itens corrigidos", em 6 de cada
--    10 propostas. A meta fica numa fonte só, a linha de retorno_config: previa_meta_linhas (3) e previa_meta_pct (60). A
--    view lê de lá e devolve as duas, a contagem e o percentual na meta, e meta_atingida (nulo com menos de 20 mostradas,
--    como o percentual). As colunas viraram_pdf_ate_1_linha(_pct) trocam de nome para viraram_pdf_na_meta(_pct): o nome
--    antigo mentiria com a meta nova. Ninguém lê a view além do teste retorno_f3_medidas.sql (conferido: sem dependente).
-- 2. rr-f3-2b: o orçamento que o áudio do dono criou (retorno_previa.dados.orc_pelo_audio_em, gravada por
--    retorno_orc_do_audio_marcar, 20270214100100) é ato do dono e sai de orc_sem_ato. O PIN agora só manda o PDF.
--
-- Sem dado novo além da coluna com padrão. Nada liga: previa_modo segue como está.
-- Reverter: drop view public.retorno_f3_medidas; reaplicar a view de 20261208100600; alter table public.retorno_config
-- drop column previa_meta_linhas, drop column previa_meta_pct.

alter table public.retorno_config
  add column previa_meta_linhas smallint not null default 3 check (previa_meta_linhas between 0 and 40),
  add column previa_meta_pct smallint not null default 60 check (previa_meta_pct between 1 and 100);

comment on column public.retorno_config.previa_meta_linhas is
  'Retorno F3 (rr-f3-1b, 20/11/2026): a meta da proposta automática. Uma proposta está na meta quando o dono corrige no máximo esta quantidade de itens antes do PDF. Era 1; o dono escolheu 3. Única fonte: retorno_f3_medidas lê daqui.';
comment on column public.retorno_config.previa_meta_pct is
  'Retorno F3 (rr-f3-1b): o percentual das propostas mostradas que precisa ficar na meta (previa_meta_linhas). 60 = 6 de cada 10. Única fonte: retorno_f3_medidas lê daqui.';

drop view public.retorno_f3_medidas;

create view public.retorno_f3_medidas with (security_invoker = on) as
with meta as (
  select c.previa_meta_linhas, c.previa_meta_pct from public.retorno_config c where c.id
), casos as (
  select a.id, a.chave, a.estado, a.aberta_em, a.visita_a_combinar_em,
         date_trunc('week', a.aberta_em at time zone 'America/Sao_Paulo')::date as semana,
         public._retorno_f3_pedido_do_caso(a.id, now()) as pedido
    from public.retorno_aberturas a
   where a.nivel in ('recibo', 'passagem') or a.visita_a_combinar_em is not null   -- passagem é o mesmo caso, e costuma ser o mais demorado
), por_caso as (
  select c.id, c.semana, c.pedido, c.estado, c.aberta_em, c.visita_a_combinar_em,
         min(p.criada_em) filter (where p.origem = 'historico') as primeira_proposta_em,
         min(p.pdf_em) as pdf_em,
         coalesce(bool_or(p.origem = 'historico' and p.modo = 'ligado'), false) as mostrada,
         coalesce(bool_or((public.retorno_previa_comparar(p.id, now()) ->> 'linhas_alteradas')::integer <= (select m.previa_meta_linhas from meta m))
                    filter (where p.origem = 'historico' and p.modo = 'ligado' and p.pdf_em is not null), false) as na_meta
    from casos c
    left join public.retorno_previa p on p.abertura_id = c.id
   group by c.id, c.semana, c.pedido, c.estado, c.aberta_em, c.visita_a_combinar_em
), por_semana as (
  select pc.semana,
         count(*) filter (where pc.pedido) as pedidos,
         count(*) filter (where pc.pedido and pc.primeira_proposta_em is not null) as com_proposta,
         round(public._retorno_mediana_com_infinito(
                 array_agg(case when pc.primeira_proposta_em is not null then public._retorno_horas_uteis(pc.aberta_em, pc.primeira_proposta_em) end)
                   filter (where pc.pedido)), 2) as pedido_proposta_mediana_h,
         round(public._retorno_mediana_com_infinito(
                 array_agg(case when pc.pdf_em is not null then public.agenda_du_entre((pc.aberta_em at time zone 'America/Sao_Paulo')::date,
                                                                                       (pc.pdf_em at time zone 'America/Sao_Paulo')::date)::numeric end)
                   filter (where pc.pedido)), 2) as pedido_pdf_mediana_du,
         count(*) filter (where pc.mostrada) as propostas_mostradas,
         count(*) filter (where pc.mostrada and pc.na_meta) as viraram_pdf_na_meta,
         count(*) filter (where pc.visita_a_combinar_em is not null and pc.estado in ('aberta', 'vencida')
                            and public.agenda_du_entre((pc.visita_a_combinar_em at time zone 'America/Sao_Paulo')::date,
                                                       (now() at time zone 'America/Sao_Paulo')::date) > 5) as visita_sem_data
    from por_caso pc
   group by pc.semana
), orcs as (
  select so.id, so.client_id, so.vessel_id, so.created_at,
         date_trunc('week', so.created_at at time zone 'America/Sao_Paulo')::date as semana
    from public.service_orders so
   where so.origem is not null
), eventos as (
  select e.payload, date_trunc('week', e.created_at at time zone 'America/Sao_Paulo')::date as semana
    from public.ai_operator_audit e
   where e.event_type in ('tool:create_quote_from_items', 'tool:create_service_order')
     and e.payload -> 'sessao_amarrada' = 'true'::jsonb
     and not e.payload ? 'erro'   -- a tentativa barrada é pre_validacao_recusada: e não chega aqui; com erro, nada foi criado
     and (e.event_type = 'tool:create_quote_from_items' or coalesce(e.payload -> 'args' ->> 'status', 'draft') = 'draft')   -- create_service_order só conta quando abre orçamento
), semanas as (
  select pc.semana from por_caso pc
   where pc.pedido or pc.visita_a_combinar_em is not null or pc.primeira_proposta_em is not null or pc.pdf_em is not null
  union
  select o.semana from orcs o
  union
  select e.semana from eventos e
  union
  select date_trunc('week', v.created_at at time zone 'America/Sao_Paulo')::date from public.vessels v
   where v.created_at >= timestamptz '2026-12-08 00:00:00-03'
  union
  select date_trunc('week', p.criada_em at time zone 'America/Sao_Paulo')::date from public.retorno_previa p
  union
  select date_trunc('week', p.pdf_em at time zone 'America/Sao_Paulo')::date from public.retorno_previa p where p.pdf_em is not null
)
select s.semana,
       coalesce(m.pedidos, 0) as pedidos,
       coalesce(m.com_proposta, 0) as com_proposta,
       m.pedido_proposta_mediana_h,
       m.pedido_pdf_mediana_du,
       coalesce(m.propostas_mostradas, 0) as propostas_mostradas,
       (select mt.previa_meta_linhas from meta mt) as meta_linhas,
       (select mt.previa_meta_pct from meta mt) as meta_pct,
       coalesce(m.viraram_pdf_na_meta, 0) as viraram_pdf_na_meta,
       case when coalesce(m.propostas_mostradas, 0) >= 20 then round(100.0 * m.viraram_pdf_na_meta / m.propostas_mostradas, 1) end as viraram_pdf_na_meta_pct,
       case when coalesce(m.propostas_mostradas, 0) >= 20
            then 100.0 * m.viraram_pdf_na_meta / m.propostas_mostradas >= (select mt.previa_meta_pct from meta mt) end as meta_atingida,
       -- ORÇ com origem e sem ato do dono (o item decidido com PIN, ou a aprovação do ditado deste caso), mais o construtor amarrado que rodou sem aprovação.
       (select count(*)
          from orcs o
         where o.semana = s.semana
           and not exists (select 1
                             from public.retorno_previa p
                             join public.retorno_cartao_itens i on i.previa_id = p.id
                             join public.retorno_cartoes c on c.id = i.cartao_id
                            where p.service_order_id = o.id and c.decidido_por = 'sim_pin'
                              and i.decidido_em is not null and i.estado in ('feito', 'fora'))
           and not exists (select 1 from public.retorno_previa p
                            where p.service_order_id = o.id and p.dados ? 'orc_pelo_audio_em')   -- rr-f3-2b: o áudio do dono criou
           and not exists (select 1
                             from public.retorno_previa p
                             join public.ai_operator_audit e on e.event_type = 'approve_execute:retorno_orcar_caso'
                                  and e.payload -> 'args' -> '_retrato' ->> 'abertura_id' = p.abertura_id::text
                            where p.service_order_id = o.id))
       + (select count(*) from eventos e where e.semana = s.semana) as orc_sem_ato,
       (select count(*)
          from orcs o
         where o.semana = s.semana
           and exists (select 1 from orcs a
                        where a.client_id = o.client_id and a.vessel_id is not distinct from o.vessel_id and a.id <> o.id
                          and (a.created_at, a.id) < (o.created_at, o.id)
                          and a.created_at >= o.created_at - interval '12 hours')) as orc_duplicado,
       (select count(*)
          from public.vessels v
         where v.created_at >= timestamptz '2026-12-08 00:00:00-03'
           and date_trunc('week', v.created_at at time zone 'America/Sao_Paulo')::date = s.semana
           and exists (select 1 from public.vessels x
                        where x.id <> v.id and x.client_id = v.client_id and x.active
                          and public._retorno_busca(x.name) = public._retorno_busca(v.name))) as cadastro_duplicado,
       (select count(*) from eventos e
         where e.semana = s.semana
           and (coalesce(e.payload -> 'args' ->> 'client_name', '') <> '' or coalesce(e.payload -> 'args' ->> 'vessel_name', '') <> '')) as escolha_por_nome,
       (select count(*) from orcs o join public.clients cl on cl.id = o.client_id
         where o.semana = s.semana and cl.generico) as orc_numero_novo_cliente_final,
       (select count(*) from public.retorno_previa p join public.clients cl on cl.id = p.client_id
         where date_trunc('week', p.criada_em at time zone 'America/Sao_Paulo')::date = s.semana and cl.generico) as proposta_cliente_final,
       (select count(*) from public.retorno_previa p join public.retorno_aberturas a on a.id = p.abertura_id
         where p.pdf_em is not null and p.pdf_chave is distinct from a.chave
           and date_trunc('week', p.pdf_em at time zone 'America/Sao_Paulo')::date = s.semana) as pdf_fora_do_contato,
       coalesce(m.visita_sem_data, 0) as visita_sem_data
  from semanas s
  left join por_semana m on m.semana = s.semana;;

comment on view public.retorno_f3_medidas is
  'Retorno F3 (P11; meta do rr-f3-1b): a medida por semana da proposta, do ORÇ com origem e do cadastro. O portão de sombra e o de saída leem daqui. A meta (itens corrigidos e percentual) vem de retorno_config.previa_meta_linhas e previa_meta_pct. Com menos de 20 mostradas, as contagens sem percentual e meta_atingida nulo.';

revoke all on public.retorno_f3_medidas from public, anon, authenticated;
grant select on public.retorno_f3_medidas to service_role;
