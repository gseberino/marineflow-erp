-- Lucro por OS desconta o custo interno da OS (Comprovantes F2, 11/10/2026). OK NOMEADO SEPARADO (P2).
--
-- Decisão do dono: a compra de OS que NÃO é cobrada do cliente (o "custo interno": a despesa que nasceu
-- de comprovante, sempre não faturável, e a despesa marcada "Interno" na tela) sai do lucro da OS — o
-- comprovante "só conta para o lucro líquido e as análises" (ajustes do dono, 11/10/2026). Antes,
-- vw_os_profitability (20260929173000) descontava só o operational_cost_total, que é a soma das
-- despesas FATURÁVEIS (as que o cliente paga e que já estão na receita): a despesa não faturável não
-- entrava em lugar nenhum e a OS parecia mais lucrativa do que é.
--
-- Contar uma vez só: a view já desconta o deslocamento COBRADO (travel_cost_total) como custo; o cupom
-- de combustível/pedágio interno é o custo real dessa mesma viagem. Somar os dois contaria o
-- deslocamento duas vezes (10 de 85 OS cobram deslocamento em 11/10/2026): o interno de viagem só
-- entra no que passa do deslocamento cobrado (o maior dos dois, nunca a soma; nunca mais otimista que
-- hoje). Os outros custos internos entram inteiros.
--
-- A mesma compra também COBRADA do cliente: o cupom vira custo interno e depois o dono lança na OS a
-- despesa faturável igual, para cobrar (ou na ordem inversa, com o "peça ou despesa" já respondido). A
-- faturável já está na receita e no operational_cost_total (repasse): o interno do comprovante que tem
-- uma gêmea cobrada (mesma OS, mesmo valor, data a ±3 dias, uma para uma) não conta de novo — o lucro
-- não depende da ordem em que os dois foram lançados.
--
-- Agora: net_profit e net_margin_percent descontam também hbr_cost = outros internos + greatest(0,
-- viagem interna − deslocamento cobrado), sem os internos de comprovante com gêmea cobrada. Coluna nova
-- hbr_cost no FIM (as telas leem por nome); as outras colunas ficam iguais e na mesma ordem.
--
-- Em produção, em 11/10/2026, há 0 despesas não faturáveis: nenhuma OS muda de lucro no dia.
-- Depende de service_order_expenses.origem_codigo (20261011203000): aplicar depois das migrations da F2.
-- Não escreve dados (a prova grava despesas de teste numa subtransação desfeita). Idempotente.

create or replace view public.vw_os_profitability
with (security_invoker = on) as
with os_costs as (
  select service_order_parts.service_order_id,
         sum(service_order_parts.quantity * service_order_parts.unit_cost_snapshot) as total_parts_cost
    from public.service_order_parts
   group by service_order_parts.service_order_id
), os_commissions as (
  select commissions.service_order_id,
         sum(commissions.amount) as total_commission
    from public.commissions
   where commissions.status <> 'cancelled'::text
   group by commissions.service_order_id
), mao_de_obra as (
  select service_order_id, custo_real_mao_de_obra, dias_trabalhados
    from public.v_custo_real_mao_de_obra_por_os
), horas_vendidas as (
  -- O "homem-hora orçado" que existe de fato: estimated_hours está vazio em quase toda OS; o que
  -- se vende por hora é a linha de serviço cobrada por hora.
  select service_order_id, sum(quantity) filter (where billing_unit_snapshot = 'hour') as horas
    from public.service_order_services
   group by service_order_id
), internas_de_comprovante as (
  -- o custo interno que nasceu de comprovante, numerado por OS e valor (casa um a um com a cobrada igual)
  select e.id, e.service_order_id, round(e.amount, 2) as valor, e.expense_date,
         row_number() over (partition by e.service_order_id, round(e.amount, 2) order by e.expense_date, e.id) as n
    from public.service_order_expenses e
   where e.origem_codigo is not null and e.billable_to_client = false
), cobradas as (
  -- a despesa cobrada do cliente, lançada à mão ou pelo assistente
  select e.service_order_id, round(e.amount, 2) as valor, e.expense_date,
         row_number() over (partition by e.service_order_id, round(e.amount, 2) order by e.expense_date, e.id) as n
    from public.service_order_expenses e
   where e.origem_codigo is null and e.billable_to_client = true
), gemeas as (
  -- a mesma compra também cobrada do cliente: o custo dela já está no repasse (operational_cost_total)
  select i.id
    from internas_de_comprovante i
    join cobradas f on f.service_order_id = i.service_order_id and f.valor = i.valor and f.n = i.n
   where abs(f.expense_date - i.expense_date) <= 3
), custo_hbr as (
  -- Custo interno da OS (11/10/2026): despesa que o cliente não paga, separando a de viagem
  -- (combustível, pedágio) — que só conta no que passa do deslocamento cobrado — e sem o interno de
  -- comprovante que tem gêmea cobrada.
  select e.service_order_id,
         sum(e.amount) filter (where e.category in ('Combustível e deslocamento', 'Pedágio e estacionamento')) as viagem,
         sum(e.amount) filter (where e.category not in ('Combustível e deslocamento', 'Pedágio e estacionamento')) as outros
    from public.service_order_expenses e
   where e.billable_to_client = false
     and not exists (select 1 from gemeas g where g.id = e.id)
   group by e.service_order_id
)
select so.id as os_id,
       so.service_order_number,
       so.status,
       so.grand_total as revenue,
       coalesce(oc.total_parts_cost, 0::numeric) as parts_cost,
       coalesce(so.travel_cost_total, 0::numeric) as travel_cost,
       coalesce(so.operational_cost_total, 0::numeric) as operational_cost,
       coalesce(com.total_commission, 0::numeric) as commission_cost,
       so.grand_total - coalesce(oc.total_parts_cost, 0::numeric) as gross_profit,
       so.grand_total - coalesce(oc.total_parts_cost, 0::numeric) - coalesce(so.travel_cost_total, 0::numeric)
         - coalesce(so.operational_cost_total, 0::numeric) - coalesce(com.total_commission, 0::numeric)
         - coalesce(mo.custo_real_mao_de_obra, 0::numeric)
         - (coalesce(ch.outros, 0::numeric)
            + greatest(0::numeric, coalesce(ch.viagem, 0::numeric) - coalesce(so.travel_cost_total, 0::numeric))) as net_profit,
       case
         when so.grand_total > 0::numeric then
           (so.grand_total - coalesce(oc.total_parts_cost, 0::numeric) - coalesce(so.travel_cost_total, 0::numeric)
             - coalesce(so.operational_cost_total, 0::numeric) - coalesce(com.total_commission, 0::numeric)
             - coalesce(mo.custo_real_mao_de_obra, 0::numeric)
             - (coalesce(ch.outros, 0::numeric)
                + greatest(0::numeric, coalesce(ch.viagem, 0::numeric) - coalesce(so.travel_cost_total, 0::numeric))))
             / so.grand_total * 100::numeric
         else 0::numeric
       end as net_margin_percent,
       so.created_at,
       so.check_out_at as finished_at,
       c.name as client_name,
       -- 29/09/2026:
       coalesce(mo.custo_real_mao_de_obra, 0::numeric) as labor_cost_real,
       coalesce(mo.dias_trabalhados, 0::numeric) as labor_days,
       coalesce(so.labor_cost_total, 0::numeric) as labor_sold,
       coalesce(hv.horas, 0::numeric) as hours_sold,
       -- 11/10/2026:
       coalesce(ch.outros, 0::numeric)
         + greatest(0::numeric, coalesce(ch.viagem, 0::numeric) - coalesce(so.travel_cost_total, 0::numeric)) as hbr_cost
  from public.service_orders so
  left join os_costs oc on oc.service_order_id = so.id
  left join os_commissions com on com.service_order_id = so.id
  left join mao_de_obra mo on mo.service_order_id = so.id
  left join horas_vendidas hv on hv.service_order_id = so.id
  left join custo_hbr ch on ch.service_order_id = so.id
  left join public.clients c on c.id = so.client_id;

comment on column public.vw_os_profitability.net_profit is
  'Receita − peças (custo) − deslocamento − despesas faturáveis − comissões − mão de obra real das diárias (29/09/2026) − custo interno da OS (hbr_cost, 11/10/2026).';
comment on column public.vw_os_profitability.hbr_cost is
  'Custo interno da OS (despesa não faturável e a que nasceu de comprovante) que entra no lucro; o de deslocamento (combustível, pedágio) só no que passa do deslocamento cobrado; o de comprovante com a mesma compra também cobrada do cliente (mesmo valor, ±3 dias) não entra. Já descontado do net_profit.';

-- view recriada: fechar anon de novo na mesma migration
revoke all on public.vw_os_profitability from anon;
grant select on public.vw_os_profitability to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Prova: anon sem select; hbr_cost é a última coluna; numa subtransação desfeita, na OS mais recente:
-- um custo interno de 10 tira 10 do lucro; combustível interno do tamanho do deslocamento cobrado não
-- tira nada (sem deslocamento cobrado, não há o que testar) e o pedágio de 30 que passa dele tira 30; o
-- cupom interno com a gêmea cobrada não tira nada.
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_os uuid;
  v_desloc numeric;
  v_antes numeric;
  v_custo numeric;
  v_igual numeric;
  v_passa numeric;
  v_gemea numeric;
begin
  if has_table_privilege('anon', 'public.vw_os_profitability', 'select') then
    raise exception 'vw_os_profitability aberta para o anon';
  end if;
  if not has_table_privilege('authenticated', 'public.vw_os_profitability', 'select') then
    raise exception 'vw_os_profitability sem select para authenticated';
  end if;
  if (select a.attname from pg_attribute a
       where a.attrelid = 'public.vw_os_profitability'::regclass and a.attnum > 0 and not a.attisdropped
       order by a.attnum desc limit 1) is distinct from 'hbr_cost' then
    raise exception 'hbr_cost não é a última coluna de vw_os_profitability';
  end if;

  select so.id, coalesce(so.travel_cost_total, 0) into v_os, v_desloc from public.service_orders so
   where so.grand_total is not null and so.status <> 'cancelled'
   order by so.created_at desc limit 1;
  if v_os is not null then
    begin
      select p.net_profit into v_antes from public.vw_os_profitability p where p.os_id = v_os;
      insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
      values (v_os, 'Outras despesas', 'prova da migration (desfeita)', 10, 'company', false);
      select p.net_profit into v_custo from public.vw_os_profitability p where p.os_id = v_os;
      if v_desloc > 0 then
        insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
        values (v_os, 'Combustível e deslocamento', 'prova da migration (desfeita)', v_desloc, 'company', false);
      end if;
      select p.net_profit into v_igual from public.vw_os_profitability p where p.os_id = v_os;
      insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client)
      values (v_os, 'Pedágio e estacionamento', 'prova da migration (desfeita)', 30, 'company', false);
      select p.net_profit into v_passa from public.vw_os_profitability p where p.os_id = v_os;
      -- o cupom interno de 17,30 e a mesma compra lançada também como despesa cobrada (sem recálculo da
      -- OS: só a exclusão do interno é medida) — o interno não conta
      insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client,
                                                 expense_date, origem_codigo)
      values (v_os, 'Outras despesas', 'prova da migration (desfeita)', 17.30, 'company', false, current_date, 'CMP-99999');
      insert into public.service_order_expenses (service_order_id, category, description, amount, paid_by, billable_to_client,
                                                 expense_date)
      values (v_os, 'Outras despesas', 'prova da migration (desfeita)', 17.30, 'company', true, current_date - 2);
      select p.net_profit into v_gemea from public.vw_os_profitability p where p.os_id = v_os;
      raise exception 'desfaz a prova' using errcode = 'MFR00';
    exception when sqlstate 'MFR00' then
      null;
    end;
    if v_antes - v_custo is distinct from 10 or v_igual is distinct from v_custo or v_igual - v_passa is distinct from 30
       or v_gemea is distinct from v_passa then
      raise exception 'Lucro por OS: o custo interno não desconta certo (antes %, com 10 %, com a viagem igual ao deslocamento %, com 30 a mais %, com a gêmea cobrada %)',
        v_antes, v_custo, v_igual, v_passa, v_gemea;
    end if;
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011205000', 'lucro_por_os_custo_hbr')
on conflict do nothing;
