-- Agenda de Produção, Fase 1 ("O que eu tenho que fazer"), pacote P2: material e compras no mesmo deploy.
-- Spec: scratchpad agenda-pesquisa/spec-fase1.md (§3 item 14, §5.3, §7.4). Plano: plano-final.md §3 (os_material).
-- Depende de 20261024150000, 150100 e 150200 (Fase 0 de compras) e de 20261024160000 (a tabela os_material).
--
-- ═══ DDL — OK NOMEADO ═══ (6 funções novas, duas delas auxiliares do histórico, e CREATE OR REPLACE de
-- get_os_purchase_needs, mesma assinatura e mesma ACL; não grava dado — quem grava é a sincronização, chamada
-- pelo task-automations depois do deploy)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- O QUE MUDA:
--   1. os_necessidade_bruta(p_so_id): a conta de compra de HOJE, sem o que o dono informou. É o corpo de
--      get_os_purchase_needs da migration 20261024150100 copiado sem mudar uma linha (o teste
--      src/test/status-que-reservam.test.ts cobra a cópia byte a byte). STABLE, security invoker.
--   2. aplicar_os_material(p_needs, p_linhas): pura (IMMUTABLE). Aplica à conta bruta o que o dono (ou o
--      fornecedor, a nota, o Pix) disse de cada linha em os_material. Casa pelo vínculo (peça → linha da
--      peça; texto livre → linha de serviço; item a caminho → item da OC) e, nesta ordem:
--        · dispensado: o item SAI da lista (e da falta);
--        · quantidade na mão: soma ao disponível (parcial: 1 de 2 deixa 1 faltando); na mão completo = ok;
--        · comprado / a caminho: conta como já pedido (o que faltava vira "já pedido");
--        · a falta, o status (a mesma régua de compute_purchase_needs: ok / on_order / partial / missing; texto
--          livre com falta continua uncatalogued) e o campo novo `informado` (comprado, a_caminho, na_mao ou
--          parcial) no item que o fato mudou;
--        · shortages em ordem determinística (rank, falta desc, posição original), shortageCount,
--          estimatedCost e needsPurchase recalculados.
--      Só conta o fato INFORMADO (fonte dono, fornecedor, nfe ou pix). A linha que a sincronização copiou
--      (fonte nula, estoque ou oc) é espelho da conta bruta: não acrescenta nada e, se ficasse velha (o
--      estoque mudou e a sincronização ainda não passou, ou está desligada), esconderia uma falta.
--      Sem fato que mude algum item, devolve p_needs IDÊNTICO (prova de que nada muda para quem não tem
--      os_material). O espelho TS é aplicarSituacaoDoMaterial (src/lib/purchase-needs.ts), com o MESMO
--      cenário numérico em supabase/tests/agenda_fase1_material.sql e nos dois testes vitest.
--   3. get_os_purchase_needs(p_so_id): create or replace, MESMA assinatura e ACL =
--      aplicar_os_material(os_necessidade_bruta(OS), linhas de os_material da OS). count_purchase_shortages
--      (150000), a R16 (find e isResolved), o item da manhã do Secretário (que lê a tarefa R16) e a tool
--      get_purchase_needs herdam sem mudar. A leitura é security invoker: o técnico não lê os_material (RLS)
--      e recebe a conta bruta, sem erro.
--   4. os_material_sincronizar(p_so_id, p_hoje): definer, só service_role. Materializa uma linha por item da
--      conta bruta (peça, texto livre, item de OC de texto livre da OS) para guardar fatos, e mantém o que o
--      sistema sabe:
--        · cria a linha que falta: estoque cobrindo → na_mao (fonte estoque, chegou hoje); coberto por OC →
--          a_caminho (fonte oc, previsão = expected_date da OC, se houver); senão → falta;
--        · a linha que o sistema escreveu (fonte nula, estoque ou oc) é refeita a cada passada pela conta
--          bruta (o estoque que deixou de cobrir volta a faltar; a OC que saiu deixa de contar);
--        · o fato informado (dono, fornecedor, nfe, pix) fica, com três exceções: a quantidade que SOBE derruba
--          na_mao/comprado/a_caminho para falta (o que foi dito valia para a quantidade antiga); o estoque
--          cobrindo vira na_mao (fonte estoque); e a falta que ganhou OC vira a_caminho (fonte oc);
--        · linha de item de OC que não está mais pendente: recebido → na_mao (fonte oc, chegou na data do
--          recebimento ou hoje); OC cancelada → a linha do sistema volta a falta;
--        · fornecedor: peça → o da OC que a cobre, senão products.supplier_id; item de OC → o da OC;
--        · toda mudança acrescenta ao historico {em, de, para, por:'sistema', nota} (os 20 mais novos) e só a
--          mudança real toca atualizado_em — é ele que a R16 lê como fato novo (mudouDesde).
--      Devolve {criadas, atualizadas, linhas}.
--   5. os_material_sincronizar_carteira(p_hoje): definer, só service_role. Percorre a carteira (o mesmo
--      recorte da os_carteira do P3: OS ativas + orçamento aprovado ou esperando sinal, sem agrupados) e
--      captura o erro por OS ({os, msg}) sem derrubar as outras. Devolve {oss, criadas, atualizadas, erros}.
--      O task-automations chama a cada 15 min, antes das regras (passo agenda:material).
--
-- CORREÇÃO SOBRE A SPEC (provada na bancada): a FK os_material.purchase_order_item_id nasceu (160000) com
-- ON DELETE SET NULL, mas a linha de origem 'oc' exige o item (CHECK origem_coerente): apagar um item de OC
-- com linha de material — o "remover item" da tela de OC e o compras-ciclo do assistente fazem isso — seria
-- RECUSADO pelo CHECK. Até o P2 nenhuma linha 'oc' existia; a sincronização cria a do compressor da OS-00104.
-- O conserto foi feito na própria 160000 (ainda não aplicada): ON DELETE CASCADE, como as FKs de peça e de
-- serviço. Os casos D16 e F6 de agenda_fase1_material.sql provam que apagar o item apaga a linha.
--
-- O QUE NÃO MUDA: compute_purchase_needs (a fórmula pura), count_purchase_shortages, v_oc_itens_a_caminho, a
-- tabela os_material e as policies dela. Material citado pelo dono (origem 'dono') NÃO entra na compra nesta
-- fase (Fase 4).
--
-- ORDEM DE LIGAR: depois de 20261024160000 (a tabela). Aplicar ANTES de o front ir para a main (o hook lê
-- os_material: sem a tabela o PostgREST responde 404 e a faixa de compras da OS mostra erro) e ANTES do deploy
-- do task-automations (o passo novo chama os_material_sincronizar_carteira e a R16 lê os_material). Aplicada
-- sozinha, a conta não muda para ninguém: sem fato informado, get_os_purchase_needs = os_necessidade_bruta.
--
-- PROVA (depois de aplicar): supabase/tests/agenda_fase1_material.sql (begin/rollback),
-- supabase/tests/purchase_needs_reserva_e_a_caminho.sql e supabase/tests/purchase_needs_parity.sql. Na bancada:
--   node scripts/bancada-agenda/rodar.mjs --ate 20261024160300
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK; depois de 160000..160200):
--   npx supabase db query --linked -f supabase/migrations/20261024160300_agenda_fase1_material.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024160300', 'agenda_fase1_material');"
--
-- IDEMPOTENTE: só create or replace function, revoke/grant e comment.

-- ── 1. A conta bruta: o corpo de get_os_purchase_needs de 20261024150100, sem mudar uma linha ────────────

create or replace function public.os_necessidade_bruta(p_so_id uuid)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  with
  -- A OS reserva estoque? A MESMA lista de recompute_product_reservations
  -- (20260724220000_stock_v2_status_sets_fix.sql). Fora dela, a reserva da OS é zero
  -- e não há o que devolver ao disponível.
  os as (
    select so.id,
           so.status in ('approved','scheduled','in_progress','awaiting_parts','awaiting_client','reopened') as reserva
      from service_orders so
     where so.id = p_so_id
  ),
  -- O que ESTA OS reservou, por produto: a soma das peças dela (é o que o recálculo soma).
  propria as (
    select sop.product_id, sum(sop.quantity) as q
      from service_order_parts sop
      join os on os.id = sop.service_order_id and os.reserva
     group by sop.product_id
  ),
  necessidade as (
    select public.compute_purchase_needs(
      p_so_id,
      coalesce((select jsonb_agg(jsonb_build_object(
          'id', sop.id, 'product_id', sop.product_id, 'quantity', sop.quantity,
          'unit_cost_snapshot', sop.unit_cost_snapshot,
          'product_name', p.name, 'product_unit', p.unit)
          order by sop.created_at, sop.id)
        from service_order_parts sop
        left join products p on p.id = sop.product_id
        where sop.service_order_id = p_so_id), '[]'::jsonb),
      coalesce((select jsonb_agg(jsonb_build_object(
          'id', s.id, 'service_id', s.service_id, 'name_snapshot', s.name_snapshot,
          'billing_unit_snapshot', s.billing_unit_snapshot, 'quantity', s.quantity,
          'unit_price_snapshot', s.unit_price_snapshot)
          order by s.created_at, s.id)
        from service_order_services s
        where s.service_order_id = p_so_id), '[]'::jsonb),
      -- O reservado que entra na conta é o de OUTRAS OS: a reserva desta sai. O piso em
      -- zero cobre o reservado defasado (menor que a reserva própria): o disponível nunca
      -- passa do físico.
      coalesce((select jsonb_agg(jsonb_build_object(
          'id', pa.id, 'stock_quantity', pa.stock_quantity,
          'reserved_quantity', greatest(coalesce(pa.reserved_quantity, 0) - coalesce(pr.q, 0), 0)))
        from product_availability pa
        left join propria pr on pr.product_id = pa.id
        where pa.id in (select sop.product_id from service_order_parts sop
                        where sop.service_order_id = p_so_id)), '[]'::jsonb),
      -- "Já pedido" só de OC viva (conta_como_ja_pedido: < 60 dias e OS não encerrada).
      coalesce((select jsonb_agg(jsonb_build_object(
          'product_id', v.product_id, 'quantity', v.quantity, 'received_qty', v.received_qty))
        from v_oc_itens_a_caminho v
        where v.conta_como_ja_pedido
          and v.product_id in (select sop.product_id from service_order_parts sop
                               where sop.service_order_id = p_so_id)), '[]'::jsonb)
    ) as r
  ),
  -- Linhas de texto livre de OC DESTA OS que ainda não chegaram. Entram em items como
  -- "a caminho" (shortage 0): não pedem compra, mas não deixam a OS parecer pronta.
  -- Sem corte de idade (conta_como_ja_pedido não entra aqui): o rascunho de 61 dias
  -- continua sendo o compressor que ainda não chegou.
  a_caminho as (
    select coalesce(jsonb_agg(jsonb_build_object(
        'sourceId', v.purchase_order_item_id, 'origin', 'purchase_order', 'productId', null,
        'description', v.description, 'unit', null, 'required', v.quantity,
        'available', 0, 'onOrder', v.pendente, 'shortage', 0, 'status', 'on_order',
        'unitCost', v.unit_cost, 'purchaseOrderNumber', v.po_number)
        order by v.po_criada_em, v.purchase_order_item_id), '[]'::jsonb) as itens
      from v_oc_itens_a_caminho v
     where v.service_order_id = p_so_id
       and v.product_id is null
       and v.pendente > 0
  )
  select jsonb_set(n.r, '{items}', coalesce(n.r -> 'items', '[]'::jsonb) || a.itens)
    from necessidade n, a_caminho a;
$function$;

comment on function public.os_necessidade_bruta(uuid) is
  'Agenda de Produção (Fase 1, P2): a necessidade de compra BRUTA de uma OS, sem o que o dono informou em os_material. Corpo de get_os_purchase_needs de 20261024150100 sem mudança (reserva própria, já pedido de OC viva, itens a caminho por OC de texto livre da OS). get_os_purchase_needs = aplicar_os_material(os_necessidade_bruta, os_material).';

revoke all on function public.os_necessidade_bruta(uuid) from public, anon;
grant execute on function public.os_necessidade_bruta(uuid) to authenticated, service_role;

-- ── 2. O que o dono informou, aplicado à conta (pura) ──────────────────────────────────────────────────

create or replace function public.aplicar_os_material(p_needs jsonb, p_linhas jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  with
  -- Só o fato INFORMADO entra. A linha que a sincronização copiou (fonte nula, estoque ou oc) é espelho da
  -- conta bruta: aplicá-la não muda nada quando está em dia e esconde uma falta quando fica velha.
  linhas as (
    select x.l, x.ord
      from jsonb_array_elements(case when jsonb_typeof(p_linhas) = 'array' then p_linhas else '[]'::jsonb end)
           with ordinality as x(l, ord)
     where x.l ->> 'fonte' in ('dono', 'fornecedor', 'nfe', 'pix')
  ),
  itens as (
    select x.i, x.ord as idx
      from jsonb_array_elements(case when jsonb_typeof(p_needs -> 'items') = 'array' then p_needs -> 'items'
                                     else '[]'::jsonb end) with ordinality as x(i, ord)
  ),
  -- O vínculo decide: peça → linha da peça; texto livre → linha de serviço (só a de origem texto_livre: a do
  -- dono pode citar a mesma linha de serviço várias vezes e não entra na compra); item a caminho → item da OC.
  casados as (
    select it.i, it.idx, ln.l
      from itens it
      left join lateral (
        select y.l
          from linhas y
         where (it.i ->> 'origin' = 'part'           and y.l ->> 'origem' = 'peca'
                and y.l ->> 'service_order_part_id' = it.i ->> 'sourceId')
            or (it.i ->> 'origin' = 'free_text'      and y.l ->> 'origem' = 'texto_livre'
                and y.l ->> 'service_order_service_id' = it.i ->> 'sourceId')
            or (it.i ->> 'origin' = 'purchase_order' and y.l ->> 'origem' = 'oc'
                and y.l ->> 'purchase_order_item_id' = it.i ->> 'sourceId')
         order by y.ord
         limit 1
      ) ln on true
  ),
  base as (
    select c.i, c.idx, c.l,
           c.i ->> 'origin' as origem_item,
           c.l ->> 'situacao' as sit,
           coalesce((c.i ->> 'required')::numeric, 0)  as r,
           coalesce((c.i ->> 'available')::numeric, 0) as a0,
           coalesce((c.i ->> 'onOrder')::numeric, 0)   as o0,
           coalesce((c.i ->> 'shortage')::numeric, 0)  as s0,
           coalesce((c.i ->> 'unitCost')::numeric, 0)  as custo,
           greatest(coalesce((c.l ->> 'quantidade_necessaria')::numeric, 0), 0) as qn,
           greatest(coalesce((c.l ->> 'quantidade_na_mao')::numeric, 0), 0)     as qna
      from casados c
  ),
  -- A quantidade na mão soma ao disponível (na_mao tem a quantidade completa pelo CHECK; se a OS pedir mais
  -- do que o dito, sobra a diferença como falta).
  passo_disponivel as (
    select b.*, case when b.l is null then b.a0 else greatest(b.a0, least(b.r, b.qna)) end as a1
      from base b
  ),
  -- Comprado/a caminho conta como já pedido: o que o dono comprou (quantidade − na mão), até o que falta.
  passo_pedido as (
    select p.*, case
        when p.l is null then p.o0
        when p.sit in ('comprado', 'a_caminho')
          then greatest(least(p.o0, p.r - p.a1), least(p.r - p.a1, greatest(p.qn - p.qna, 0)))
        else least(p.o0, p.r - p.a1) end as o1
      from passo_disponivel p
  ),
  -- O item a caminho por OC de texto livre nunca pede compra (falta 0, como na conta bruta).
  passo_falta as (
    select p.*, case
        when p.l is null then p.s0
        when p.origem_item = 'purchase_order' then 0
        else greatest(p.r - p.a1 - p.o1, 0) end as s1
      from passo_pedido p
  ),
  -- A régua de compute_purchase_needs.
  passo_status as (
    select p.*, case
        when p.l is null then p.i ->> 'status'
        when p.origem_item = 'purchase_order' then case when p.r - p.a1 = 0 then 'ok' else 'on_order' end
        when p.s1 = 0 and p.r - p.a1 = 0 then 'ok'
        when p.s1 = 0 then 'on_order'
        when p.origem_item = 'free_text' then 'uncatalogued'
        when p.a1 > 0 then 'partial'
        else 'missing' end as st
      from passo_falta p
  ),
  marcados as (
    select p.*,
           (p.l is not null and p.sit = 'dispensado') as sai,
           (p.l is not null and p.sit is distinct from 'dispensado'
            and (p.a1 <> p.a0 or p.o1 <> p.o0 or p.s1 <> p.s0 or p.st is distinct from p.i ->> 'status')) as mudou
      from passo_status p
  ),
  final as (
    select m.idx, m.s1, m.custo,
           case when m.mudou
                then m.i || jsonb_build_object('available', m.a1, 'onOrder', m.o1, 'shortage', m.s1, 'status', m.st,
                                               'informado', case when m.sit = 'falta' then 'parcial' else m.sit end)
                else m.i end as js,
           case m.st when 'missing' then 0 when 'partial' then 1 when 'uncatalogued' then 2
                     when 'on_order' then 3 else 4 end as rank
      from marcados m
     where not m.sai
  )
  select case
    when p_needs is null then null
    when not exists (select 1 from marcados where sai or mudou) then p_needs
    else p_needs || jsonb_build_object(
      'items',         coalesce((select jsonb_agg(f.js order by f.idx) from final f), '[]'::jsonb),
      'shortages',     coalesce((select jsonb_agg(f.js order by f.rank, f.s1 desc, f.idx) from final f where f.s1 > 0),
                                '[]'::jsonb),
      'shortageCount', (select count(*) from final f where f.s1 > 0),
      'estimatedCost', coalesce((select sum(f.s1 * f.custo) from final f where f.s1 > 0), 0),
      'needsPurchase', exists (select 1 from final f where f.s1 > 0))
  end;
$function$;

comment on function public.aplicar_os_material(jsonb, jsonb) is
  'Agenda de Produção (Fase 1, P2): aplica a necessidade de compra (formato de get_os_purchase_needs) o que foi informado em os_material (fonte dono/fornecedor/nfe/pix; a linha copiada pela sincronização nao conta). Por vinculo: dispensado sai; quantidade na mao soma ao disponivel; na_mao completo = ok; comprado/a_caminho = ja pedido. Recalcula falta, status (regua de compute_purchase_needs), informado, shortages (rank, falta desc, posicao original), shortageCount, estimatedCost e needsPurchase. Sem fato que mude algum item, devolve p_needs identico. Pura. Espelho TS: aplicarSituacaoDoMaterial (src/lib/purchase-needs.ts).';

revoke all on function public.aplicar_os_material(jsonb, jsonb) from public, anon;
grant execute on function public.aplicar_os_material(jsonb, jsonb) to authenticated, service_role;

-- ── 3. get_os_purchase_needs: a conta bruta com o que o dono informou ──────────────────────────────────

create or replace function public.get_os_purchase_needs(p_so_id uuid)
 returns jsonb
 language sql
 stable
 set search_path to 'public'
as $function$
  -- security invoker: quem não lê os_material (o técnico, pela RLS) recebe a conta bruta, sem erro.
  select public.aplicar_os_material(
    public.os_necessidade_bruta(p_so_id),
    coalesce((select jsonb_agg(jsonb_build_object(
        'service_order_part_id', m.service_order_part_id,
        'service_order_service_id', m.service_order_service_id,
        'purchase_order_item_id', m.purchase_order_item_id,
        'origem', m.origem, 'situacao', m.situacao, 'fonte', m.fonte,
        'quantidade_necessaria', m.quantidade_necessaria, 'quantidade_na_mao', m.quantidade_na_mao)
        order by m.id)
      from public.os_material m
     where m.service_order_id = p_so_id), '[]'::jsonb));
$function$;

comment on function public.get_os_purchase_needs(uuid) is
  'Necessidade LIQUIDA de compra de uma OS (falta = necessario - disponivel - ja pedido). Espelha src/lib/purchase-needs.ts + src/hooks/use-purchase-needs.ts; e a via do agente de IA e da R16 (count_purchase_shortages). Desde 24/10/2026 (Agenda, Fase 1, P2) = aplicar_os_material(os_necessidade_bruta(OS), os_material da OS): o que o dono informou (comprado/a caminho = ja pedido; na mao = disponivel; dispensado sai) entra na conta e o item ganha "informado". Sem os_material (ou para quem nao le os_material, como o tecnico), igual a os_necessidade_bruta.';

revoke all on function public.get_os_purchase_needs(uuid) from public, anon;
grant execute on function public.get_os_purchase_needs(uuid) to authenticated, service_role;

-- ── 4. Sincronização de uma OS ─────────────────────────────────────────────────────────────────────────

-- Quantidade em texto curto ("2", e não "2.000"), para o histórico.
create or replace function public._os_material_qtd(p numeric)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select replace(trim_scale(p)::text, '.', ',');
$function$;

comment on function public._os_material_qtd(numeric) is
  'Agenda de Produção (Fase 1, P2): quantidade em texto curto para o histórico de os_material ("2", e nao "2.000").';
revoke all on function public._os_material_qtd(numeric) from public, anon, authenticated;
grant execute on function public._os_material_qtd(numeric) to service_role;

-- O histórico com a entrada nova no fim, só os 20 mais novos (o CHECK da tabela).
create or replace function public._os_material_historico(p_historico jsonb, p_entrada jsonb)
 returns jsonb
 language sql
 immutable
 set search_path to 'public'
as $function$
  select coalesce(jsonb_agg(h.e order by h.n), '[]'::jsonb)
    from (select x.e, x.n, count(*) over () as total
            from jsonb_array_elements(
                   case when jsonb_typeof(p_historico) = 'array' then p_historico else '[]'::jsonb end
                   || jsonb_build_array(p_entrada)) with ordinality as x(e, n)) h
   where h.n > h.total - 20;
$function$;

comment on function public._os_material_historico(jsonb, jsonb) is
  'Agenda de Produção (Fase 1, P2): acrescenta uma entrada ao historico de os_material e corta nos 20 mais novos.';
revoke all on function public._os_material_historico(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public._os_material_historico(jsonb, jsonb) to service_role;

create or replace function public.os_material_sincronizar(p_so_id uuid, p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_bruto       jsonb;
  v_item        jsonb;
  v_origin      text;
  v_origem      text;
  v_src         uuid;
  v_req         numeric;
  v_status      text;
  v_desc        text;
  v_velha       public.os_material%rowtype;
  v_nova        public.os_material%rowtype;
  v_sistema     boolean;
  v_oc_prev     date;
  v_oc_forn     uuid;
  v_oc_numero   text;
  v_prod_forn   uuid;
  v_forn        uuid;
  v_ini_sit     text;
  v_nota        text;
  v_pendentes   uuid[] := '{}';
  v_criadas     int := 0;
  v_atualizadas int := 0;
  v_poi         record;
begin
  if p_so_id is null then
    raise exception 'os_material_sincronizar: a OS veio vazia';
  end if;
  if not exists (select 1 from public.service_orders where id = p_so_id) then
    raise exception 'os_material_sincronizar: a OS % não existe', p_so_id using errcode = 'P0002';
  end if;
  -- Uma sincronização por OS de cada vez (o motor de 15 min e, no P5, as RPCs do rascunho).
  perform pg_advisory_xact_lock(hashtext('os_material:' || p_so_id::text));

  v_bruto := public.os_necessidade_bruta(p_so_id);

  for v_item in select e from jsonb_array_elements(coalesce(v_bruto -> 'items', '[]'::jsonb)) as t(e) loop
    v_origin := v_item ->> 'origin';
    v_origem := case v_origin when 'part' then 'peca' when 'free_text' then 'texto_livre'
                              when 'purchase_order' then 'oc' end;
    continue when v_origem is null;
    v_src := (v_item ->> 'sourceId')::uuid;
    if v_origin = 'purchase_order' then
      v_pendentes := v_pendentes || v_src;
    end if;
    v_req := (v_item ->> 'required')::numeric;
    continue when v_req is null or v_req <= 0;   -- linha com quantidade 0 não tem o que guardar
    v_status := v_item ->> 'status';
    v_desc := left(coalesce(nullif(btrim(v_item ->> 'description'), ''), 'Material'), 200);

    -- O que o sistema diz da linha hoje: a OC que a cobre (a da própria OS primeiro), o fornecedor e a
    -- situação inicial.
    v_oc_prev := null; v_oc_forn := null; v_oc_numero := null; v_prod_forn := null;
    if v_status = 'on_order' then
      select v.expected_date, po.supplier_id, v.po_number
        into v_oc_prev, v_oc_forn, v_oc_numero
        from public.v_oc_itens_a_caminho v
        join public.purchase_orders po on po.id = v.purchase_order_id
       where v.pendente > 0
         and case when v_origin = 'purchase_order' then v.purchase_order_item_id = v_src
                  else v.product_id = (v_item ->> 'productId')::uuid and v.conta_como_ja_pedido end
       order by (v.service_order_id is distinct from p_so_id), v.po_criada_em, v.purchase_order_item_id
       limit 1;
    end if;
    if v_origin = 'part' then
      select p.supplier_id into v_prod_forn from public.products p where p.id = (v_item ->> 'productId')::uuid;
    elsif v_origin = 'purchase_order' and v_oc_forn is null then
      select po.supplier_id into v_oc_forn
        from public.purchase_order_items poi join public.purchase_orders po on po.id = poi.purchase_order_id
       where poi.id = v_src;
    end if;
    v_forn := coalesce(v_oc_forn, v_prod_forn);
    v_ini_sit := case v_status when 'ok' then 'na_mao' when 'on_order' then 'a_caminho' else 'falta' end;

    select m.* into v_velha
      from public.os_material m
     where m.origem = v_origem
       and case v_origem when 'peca' then m.service_order_part_id = v_src
                         when 'texto_livre' then m.service_order_service_id = v_src
                         else m.purchase_order_item_id = v_src end
     for update;

    if not found then
      insert into public.os_material (
        service_order_id, service_order_part_id, service_order_service_id, purchase_order_item_id, origem,
        descricao, quantidade_necessaria, quantidade_na_mao, situacao, fonte, fornecedor_id,
        previsao_ate, previsao_original, previsao_fonte, chegou_em, historico)
      values (
        p_so_id,
        case when v_origem = 'peca' then v_src end,
        case when v_origem = 'texto_livre' then v_src end,
        case when v_origem = 'oc' then v_src end,
        v_origem, v_desc, v_req,
        case when v_ini_sit = 'na_mao' then v_req else 0 end,
        v_ini_sit,
        case v_ini_sit when 'na_mao' then 'estoque' when 'a_caminho' then 'oc' end,
        v_forn,
        case when v_ini_sit = 'a_caminho' then v_oc_prev end,
        case when v_ini_sit = 'a_caminho' then v_oc_prev end,
        case when v_ini_sit = 'a_caminho' and v_oc_prev is not null then 'oc' end,
        case when v_ini_sit = 'na_mao' then p_hoje end,
        jsonb_build_array(jsonb_build_object('em', p_hoje, 'de', null, 'para', v_ini_sit, 'por', 'sistema',
          'nota', case v_ini_sit when 'na_mao' then 'o estoque cobre'
                                 when 'a_caminho' then 'pedido na ' || coalesce(v_oc_numero, 'OC')
                                 else 'a comprar' end)));
      v_criadas := v_criadas + 1;
      continue;
    end if;

    v_nova := v_velha;
    v_nota := null;
    v_nova.service_order_id := p_so_id;
    v_nova.descricao := v_desc;
    -- A linha que o próprio sistema escreveu é refeita pela conta bruta; o fato informado fica.
    v_sistema := v_velha.fonte is null or v_velha.fonte in ('estoque', 'oc');

    if v_req <> v_velha.quantidade_necessaria then
      v_nota := format('a quantidade %s de %s para %s',
                       case when v_req > v_velha.quantidade_necessaria then 'subiu' else 'caiu' end,
                       public._os_material_qtd(v_velha.quantidade_necessaria), public._os_material_qtd(v_req));
      v_nova.quantidade_necessaria := v_req;
      v_nova.quantidade_na_mao := least(v_nova.quantidade_na_mao, v_req);
    end if;

    if v_sistema then
      v_nova.situacao := v_ini_sit;
      v_nova.fonte := case v_ini_sit when 'na_mao' then 'estoque' when 'a_caminho' then 'oc' end;
      v_nova.fornecedor_id := v_forn;
      v_nova.compra_prevista_em := null;
      v_nova.quantidade_na_mao := case when v_ini_sit = 'na_mao' then v_req else 0 end;
      v_nova.chegou_em := case when v_ini_sit <> 'na_mao' then null
                               when v_velha.situacao = 'na_mao' then coalesce(v_velha.chegou_em, p_hoje)
                               else p_hoje end;
      v_nova.previsao_de := null;
      v_nova.previsao_ate := case when v_ini_sit = 'a_caminho' then v_oc_prev end;
      v_nova.previsao_fonte := case when v_ini_sit = 'a_caminho' and v_oc_prev is not null then 'oc' end;
      v_nova.previsao_original := coalesce(v_velha.previsao_original, v_nova.previsao_ate);
      if v_nova.situacao <> v_velha.situacao then
        v_nota := coalesce(v_nota || '; ', '') || case v_nova.situacao
          when 'na_mao' then 'o estoque cobre'
          when 'a_caminho' then 'pedido na ' || coalesce(v_oc_numero, 'OC')
          else case v_velha.situacao when 'na_mao' then 'o estoque deixou de cobrir'
                                     else 'a OC deixou de cobrir' end end;
      end if;
    else
      -- O que foi dito valia para a quantidade antiga: a que sobe derruba o fato.
      if v_req > v_velha.quantidade_necessaria and v_velha.situacao in ('na_mao', 'comprado', 'a_caminho') then
        v_nova.situacao := 'falta';
        v_nova.chegou_em := null;
        v_nova.previsao_de := null;
        v_nova.previsao_ate := null;
        v_nova.previsao_fonte := null;
      end if;
      -- A que cai pode completar o que está na mão.
      if v_nova.quantidade_na_mao >= v_nova.quantidade_necessaria
         and v_nova.situacao not in ('na_mao', 'dispensado') then
        v_nova.situacao := 'na_mao';
        v_nova.chegou_em := coalesce(v_nova.chegou_em, p_hoje);
        v_nova.compra_prevista_em := null;
      end if;
      if v_status = 'ok' and v_nova.situacao not in ('na_mao', 'dispensado') then
        -- Chegou e entrou no estoque.
        v_nova.situacao := 'na_mao';
        v_nova.fonte := 'estoque';
        v_nova.quantidade_na_mao := v_req;
        v_nova.chegou_em := p_hoje;
        v_nova.compra_prevista_em := null;
        v_nota := coalesce(v_nota || '; ', '') || 'o estoque cobre';
      elsif v_status = 'on_order' and v_nova.situacao = 'falta' then
        -- "Vou comprar" que virou OC: a OC é o fato mais novo.
        v_nova.situacao := 'a_caminho';
        v_nova.fonte := 'oc';
        v_nova.quantidade_na_mao := 0;
        v_nova.compra_prevista_em := null;
        v_nova.fornecedor_id := coalesce(v_oc_forn, v_nova.fornecedor_id);
        v_nova.previsao_de := null;
        v_nova.previsao_ate := v_oc_prev;
        v_nova.previsao_fonte := case when v_oc_prev is not null then 'oc' end;
        v_nova.previsao_original := coalesce(v_velha.previsao_original, v_oc_prev);
        v_nota := coalesce(v_nota || '; ', '') || 'pedido na ' || coalesce(v_oc_numero, 'OC');
      end if;
    end if;

    if (v_nova.service_order_id, v_nova.descricao, v_nova.quantidade_necessaria, v_nova.quantidade_na_mao,
        v_nova.situacao, v_nova.fonte, v_nova.fornecedor_id, v_nova.compra_prevista_em, v_nova.previsao_de,
        v_nova.previsao_ate, v_nova.previsao_original, v_nova.previsao_fonte, v_nova.chegou_em)
       is distinct from
       (v_velha.service_order_id, v_velha.descricao, v_velha.quantidade_necessaria, v_velha.quantidade_na_mao,
        v_velha.situacao, v_velha.fonte, v_velha.fornecedor_id, v_velha.compra_prevista_em, v_velha.previsao_de,
        v_velha.previsao_ate, v_velha.previsao_original, v_velha.previsao_fonte, v_velha.chegou_em) then
      update public.os_material
         set service_order_id = v_nova.service_order_id, descricao = v_nova.descricao,
             quantidade_necessaria = v_nova.quantidade_necessaria, quantidade_na_mao = v_nova.quantidade_na_mao,
             situacao = v_nova.situacao, fonte = v_nova.fonte, fornecedor_id = v_nova.fornecedor_id,
             compra_prevista_em = v_nova.compra_prevista_em, previsao_de = v_nova.previsao_de,
             previsao_ate = v_nova.previsao_ate, previsao_original = v_nova.previsao_original,
             previsao_fonte = v_nova.previsao_fonte, chegou_em = v_nova.chegou_em,
             historico = public._os_material_historico(v_velha.historico, jsonb_build_object(
               'em', p_hoje, 'de', v_velha.situacao, 'para', v_nova.situacao, 'por', 'sistema',
               'nota', coalesce(v_nota, 'conferido com a OS'))),
             atualizado_em = now(), atualizado_por = null
       where id = v_velha.id;
      v_atualizadas := v_atualizadas + 1;
    end if;
  end loop;

  -- Item de OC da OS que não está mais pendente: recebido vira na mão; OC cancelada volta a faltar.
  for v_velha in
    select m.* from public.os_material m
     where m.service_order_id = p_so_id and m.origem = 'oc' and m.purchase_order_item_id is not null
       and not (m.purchase_order_item_id = any (v_pendentes))
     order by m.id
     for update
  loop
    select poi.quantity, poi.received_qty, po.status as po_status, po.received_date, po.po_number
      into v_poi
      from public.purchase_order_items poi join public.purchase_orders po on po.id = poi.purchase_order_id
     where poi.id = v_velha.purchase_order_item_id;
    continue when not found;
    v_nova := v_velha;
    v_nota := null;
    if v_poi.po_status = 'received' or coalesce(v_poi.received_qty, 0) >= v_poi.quantity then
      if v_velha.situacao not in ('na_mao', 'dispensado') then
        v_nova.situacao := 'na_mao';
        v_nova.fonte := 'oc';
        v_nova.quantidade_na_mao := v_nova.quantidade_necessaria;
        v_nova.chegou_em := least(coalesce(v_poi.received_date, p_hoje), p_hoje);
        v_nova.compra_prevista_em := null;
        v_nota := 'recebido na ' || v_poi.po_number;
      end if;
    elsif v_poi.po_status = 'cancelled'
          and (v_velha.fonte is null or v_velha.fonte = 'oc') and v_velha.situacao <> 'falta' then
      v_nova.situacao := 'falta';
      v_nova.fonte := null;
      v_nova.quantidade_na_mao := 0;
      v_nova.chegou_em := null;
      v_nova.previsao_de := null;
      v_nova.previsao_ate := null;
      v_nova.previsao_fonte := null;
      v_nota := 'a ' || v_poi.po_number || ' foi cancelada';
    end if;
    if v_nota is not null then
      update public.os_material
         set situacao = v_nova.situacao, fonte = v_nova.fonte, quantidade_na_mao = v_nova.quantidade_na_mao,
             chegou_em = v_nova.chegou_em, compra_prevista_em = v_nova.compra_prevista_em,
             previsao_de = v_nova.previsao_de, previsao_ate = v_nova.previsao_ate,
             previsao_fonte = v_nova.previsao_fonte,
             historico = public._os_material_historico(v_velha.historico, jsonb_build_object(
               'em', p_hoje, 'de', v_velha.situacao, 'para', v_nova.situacao, 'por', 'sistema', 'nota', v_nota)),
             atualizado_em = now(), atualizado_por = null
       where id = v_velha.id;
      v_atualizadas := v_atualizadas + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'criadas', v_criadas,
    'atualizadas', v_atualizadas,
    'linhas', (select count(*) from public.os_material where service_order_id = p_so_id));
end;
$function$;

comment on function public.os_material_sincronizar(uuid, date) is
  'Agenda de Produção (Fase 1, P2): materializa em os_material uma linha por item da conta bruta da OS (peça, texto livre, item de OC de texto livre) e mantém o que o sistema sabe: estoque cobrindo = na_mao (fonte estoque); OC cobrindo = a_caminho (fonte oc, previsão da OC); senão falta. A linha do sistema (fonte nula/estoque/oc) é refeita a cada passada; o fato informado fica, salvo quantidade que sobe (derruba para falta), estoque cobrindo (na_mao) e falta que ganhou OC (a_caminho). Item de OC recebido = na_mao; OC cancelada = falta. Histórico com os 20 mais novos; atualizado_em só muda com mudança real. Só service_role. Devolve {criadas, atualizadas, linhas}.';

revoke all on function public.os_material_sincronizar(uuid, date) from public, anon, authenticated;
grant execute on function public.os_material_sincronizar(uuid, date) to service_role;

-- ── 5. Sincronização da carteira ───────────────────────────────────────────────────────────────────────

create or replace function public.os_material_sincronizar_carteira(p_hoje date default public._hoje_brt())
 returns jsonb
 language plpgsql
 volatile
 security definer
 set search_path to 'public'
as $function$
declare
  v_os          record;
  v_r           jsonb;
  v_oss         int := 0;
  v_criadas     int := 0;
  v_atualizadas int := 0;
  v_erros       jsonb := '[]'::jsonb;
begin
  -- A carteira: o mesmo recorte da os_carteira (P3) — OS ativas (STATUS_OS_ATIVAS) e orçamento aprovado ou
  -- esperando sinal, sem os agrupados em outro.
  for v_os in
    select so.id, so.service_order_number
      from public.service_orders so
     where so.merged_into_id is null
       and (so.status in ('open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'awaiting_client')
            or (so.status = 'draft' and so.quote_status in ('approved', 'awaiting_deposit')))
     order by so.service_order_number, so.id
  loop
    v_oss := v_oss + 1;
    begin
      v_r := public.os_material_sincronizar(v_os.id, p_hoje);
      v_criadas := v_criadas + coalesce((v_r ->> 'criadas')::int, 0);
      v_atualizadas := v_atualizadas + coalesce((v_r ->> 'atualizadas')::int, 0);
    exception when others then
      -- Uma OS com problema não derruba as outras: o erro sai no retorno e o motor grava em app_error_logs.
      v_erros := v_erros || jsonb_build_object('os', v_os.service_order_number, 'msg', left(sqlerrm, 300));
    end;
  end loop;
  return jsonb_build_object('oss', v_oss, 'criadas', v_criadas, 'atualizadas', v_atualizadas, 'erros', v_erros);
end;
$function$;

comment on function public.os_material_sincronizar_carteira(date) is
  'Agenda de Produção (Fase 1, P2): roda os_material_sincronizar em cada OS da carteira (OS ativas + orçamento aprovado ou esperando sinal, sem agrupados), na ordem do número; o erro de uma OS vai para erros [{os, msg}] sem derrubar as outras. Chamada pelo task-automations a cada 15 min (passo agenda:material), só com agenda_config.modo_leitura <> desligado. Só service_role. Devolve {oss, criadas, atualizadas, erros}.';

revoke all on function public.os_material_sincronizar_carteira(date) from public, anon, authenticated;
grant execute on function public.os_material_sincronizar_carteira(date) to service_role;
