-- Retorno rápido ao cliente, F3 (P11): a medida da proposta e o cron da rodada.
--
-- retorno_previa_comparar: a foto da proposta como nasceu (linhas_iniciais) contra o ORÇ que saiu, linha a linha. É o número que o
-- portão de saída lê: o que o dono mudou por ditado aparece como alterado, porque a foto nunca é tocada por retorno_previa_aplicar.
-- retorno_f3_medidas: uma linha por semana, cada coluna pela própria data; a CTE semanas é a união de todas, como em retorno_f2_medidas,
-- para o evento sem caso não sumir de um portão de meta 0.
--
-- Cron próprio, e não um passo em retorno_vigia: a vigia já foi redefinida por gerador duas vezes (F1 e 20261201100000), e um passo a mais
-- acoplaria a F3 à cadeia. Sem efeito enquanto previa_modo = 'desligado': a chamada lê 1 linha e sai.
--
-- Reverter: select cron.unschedule(jobid) from cron.job where jobname = 'retorno-previa'; drop view public.retorno_f3_medidas.

create or replace function public._retorno_mediana_com_infinito(p_valores numeric[])
returns numeric
language sql
immutable
set search_path = public
as $$
  with v as (
    select x, row_number() over (order by x nulls last) as rn, count(*) over () as n
      from unnest(p_valores) as x
  )
  select case when (select count(*) filter (where v.x is null) * 2 > count(*) from v) then null
              else (select avg(v.x) from v where v.rn in ((v.n + 1) / 2, (v.n + 2) / 2)) end;
$$;

comment on function public._retorno_mediana_com_infinito(numeric[]) is
  'Retorno F3 (P11): mediana em que o nulo conta como infinito. Mais da metade sem valor dá nulo; com exatamente metade, o maior valor conhecido.';

revoke all on function public._retorno_mediana_com_infinito(numeric[]) from public, anon, authenticated;

create or replace function public.retorno_previa_comparar(p_previa uuid, p_agora timestamptz default now())
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := coalesce(p_agora, now());
  v_p public.retorno_previa;
  v_aberta timestamptz;
  v_orc uuid;
  v_numero text;
  v_iguais integer;
  v_pares_dif integer;
  v_so_foto integer;
  v_so_orc integer;
  v_pares integer;
  v_preco_dif integer;
begin
  select * into v_p from public.retorno_previa p where p.id = p_previa;
  if not found or jsonb_array_length(v_p.linhas_iniciais) = 0 then
    return null;   -- proposta ditada do zero ou linha de rascunho: fora da medida
  end if;

  if v_p.estado = 'virou_orc' and v_p.modo = 'ligado' then
    select so.id, so.service_order_number into v_orc, v_numero
      from public.service_orders so
     where so.id = v_p.service_order_id and so.created_at <= v_agora;
  elsif v_p.modo = 'sombra' and v_p.estado in ('sombra', 'descartada') and v_p.client_id is not null then
    select a.aberta_em into v_aberta from public.retorno_aberturas a where a.id = v_p.abertura_id;
    -- O ORÇ que respondeu a este pedido: da mesma unidade, quando a proposta tem uma, e dentre eles o mais antigo.
    select so.id, so.service_order_number into v_orc, v_numero
      from public.service_orders so
     where so.client_id = v_p.client_id
       and so.created_at >= v_aberta
       and so.created_at <= v_aberta + interval '5 days'
       and so.created_at <= v_agora
       and (so.origem is null or so.origem = 'retorno_ditado')
       and so.status <> 'cancelled'
       and so.merged_into_id is null
     order by coalesce(v_p.vessel_id is not null and so.vessel_id = v_p.vessel_id, false) desc, so.created_at, so.id
     limit 1;
  end if;

  if v_orc is null then
    return null;
  end if;

  -- Chave: peça, product_id; serviço, o nome normalizado (214 de 331 linhas de serviço em 180 dias não têm service_id).
  with foto as (
    select f.tipo, f.chave, f.quantidade, f.preco,
           row_number() over (partition by f.tipo, f.chave order by f.preco nulls last, f.quantidade) as ordem
      from (select l.tipo,
                   case when l.tipo = 'peca' then coalesce(l.product_id::text, public._retorno_busca(l.nome)) else public._retorno_busca(l.nome) end as chave,
                   l.quantidade, l.preco
              from jsonb_to_recordset(v_p.linhas_iniciais) as l(tipo text, product_id uuid, nome text, quantidade numeric, preco numeric)) f
  ), orc as (
    select o.tipo, o.chave, o.quantidade, o.preco,
           row_number() over (partition by o.tipo, o.chave order by o.preco nulls last, o.quantidade) as ordem
      from (select 'peca'::text as tipo, sp.product_id::text as chave, sp.quantity as quantidade, sp.unit_sale_snapshot as preco
              from public.service_order_parts sp
             where sp.service_order_id = v_orc and sp.created_at <= v_agora
            union all
            select 'servico', public._retorno_busca(ss.name_snapshot), ss.quantity, ss.unit_price_snapshot
              from public.service_order_services ss
             where ss.service_order_id = v_orc and coalesce(ss.created_at, v_agora) <= v_agora) o
  ), pares as (
    select f.tipo is not null as tem_foto, o.tipo is not null as tem_orc,
           f.quantidade is not distinct from o.quantidade as mesma_qtd,
           coalesce(abs(f.preco - o.preco) <= 0.01, false) as mesmo_preco
      from foto f
      full join orc o on o.tipo = f.tipo and o.chave = f.chave and o.ordem = f.ordem
  )
  select count(*) filter (where p.tem_foto and p.tem_orc and p.mesma_qtd and p.mesmo_preco),
         count(*) filter (where p.tem_foto and p.tem_orc and not (p.mesma_qtd and p.mesmo_preco)),
         count(*) filter (where p.tem_foto and not p.tem_orc),
         count(*) filter (where p.tem_orc and not p.tem_foto),
         count(*) filter (where p.tem_foto and p.tem_orc),
         count(*) filter (where p.tem_foto and p.tem_orc and not p.mesmo_preco)
    into v_iguais, v_pares_dif, v_so_foto, v_so_orc, v_pares, v_preco_dif
    from pares p;

  return jsonb_build_object('orc_id', v_orc, 'numero', v_numero, 'linhas_iguais', v_iguais,
                            'linhas_alteradas', v_pares_dif + greatest(v_so_foto, v_so_orc),
                            'preco_igual', case when v_pares = 0 then null else v_preco_dif = 0 end);
end;
$$;

comment on function public.retorno_previa_comparar(uuid, timestamptz) is
  'Retorno F3 (P11): a foto da proposta como nasceu (linhas_iniciais) contra o ORÇ que saiu. Linha sem par conta pelo maior dos dois lados: trocar uma por outra conta 1. Sem foto, nulo.';

revoke all on function public.retorno_previa_comparar(uuid, timestamptz) from public, anon, authenticated;
grant execute on function public.retorno_previa_comparar(uuid, timestamptz) to service_role;

create or replace view public.retorno_f3_medidas with (security_invoker = on) as
with casos as (
  select a.id, a.chave, a.estado, a.aberta_em, a.visita_a_combinar_em,
         date_trunc('week', a.aberta_em at time zone 'America/Sao_Paulo')::date as semana,
         coalesce(public._retorno_intencao_do_caso(a.id, now()) in ('orcamento', 'adicional'), false) as pedido
    from public.retorno_aberturas a
   where a.nivel = 'recibo' or a.visita_a_combinar_em is not null
), por_caso as (
  select c.id, c.semana, c.pedido, c.estado, c.aberta_em, c.visita_a_combinar_em,
         min(p.criada_em) filter (where p.origem = 'historico') as primeira_proposta_em,
         min(p.pdf_em) as pdf_em,
         coalesce(bool_or(p.origem = 'historico' and p.modo = 'ligado'), false) as mostrada,
         coalesce(bool_or((public.retorno_previa_comparar(p.id, now()) ->> 'linhas_alteradas')::integer <= 1)
                    filter (where p.origem = 'historico' and p.modo = 'ligado' and p.pdf_em is not null), false) as ate_1_linha
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
         count(*) filter (where pc.mostrada and pc.ate_1_linha) as viraram_pdf_ate_1_linha,
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
   where e.event_type = 'tool:create_quote_from_items'
     and e.payload -> 'sessao_amarrada' = 'true'::jsonb
     and not e.payload ? 'erro'   -- a tentativa barrada é pre_validacao_recusada: e não chega aqui; com erro, nada foi criado
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
       coalesce(m.viraram_pdf_ate_1_linha, 0) as viraram_pdf_ate_1_linha,
       case when coalesce(m.propostas_mostradas, 0) >= 20 then round(100.0 * m.viraram_pdf_ate_1_linha / m.propostas_mostradas, 1) end as viraram_pdf_ate_1_linha_pct,
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
  left join por_semana m on m.semana = s.semana;

comment on view public.retorno_f3_medidas is
  'Retorno F3 (P11): a medida por semana da proposta, do ORÇ com origem e do cadastro. O portão de sombra e o de saída leem daqui. Com menos de 20 mostradas, as contagens sem percentual.';

revoke all on public.retorno_f3_medidas from public, anon, authenticated;
grant select on public.retorno_f3_medidas to service_role;

-- Sem efeito enquanto previa_modo = 'desligado': a chamada lê 1 linha e sai.
select cron.schedule('retorno-previa', '*/5 10-23 * * 1-6', $c$ select public.retorno_previa_rodada() $c$);
