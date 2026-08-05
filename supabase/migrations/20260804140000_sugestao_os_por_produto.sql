-- ─────────────────────────────────────────────────────────────────────────────
-- Sugestão de OS a partir dos PRODUTOS — a versão que serve na hora da decisão.
--
-- `suggest_nfe_service_orders(note_id)`, criada horas antes, lê de
-- `fiscal_note_items` — e essas linhas só passam a existir DEPOIS que a nota é
-- confirmada. Só que a escolha do destino acontece ANTES, na tela de conferência.
-- Ou seja: a função certa, no momento errado. Ela continua útil para consultar uma
-- nota já importada, mas não serve para sugerir enquanto se confere.
--
-- Esta recebe os produtos que o preview já casou (o preview traz product_id por
-- item antes de qualquer gravação) e devolve, para cada um, a OS que está
-- esperando aquela peça. É o que permite a tela dizer "3 destes itens são da
-- OS-00051, vincular?" em vez de pedir que o usuário descubra sozinho.
--
-- Critério de desempate explícito: a OS mais ANTIGA primeiro — quem espera há mais
-- tempo tem prioridade. Sem isso seria a ordem que o banco devolvesse, ou seja,
-- sorte. Devolve uma sugestão por produto; se duas OS disputam a mesma peça, a
-- segunda aparece em `outras`, para a tela poder avisar que há disputa.
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.suggest_service_orders_for_products(p_product_ids uuid[])
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
with candidatas as (
  select sop.product_id,
         so.id                   as service_order_id,
         so.service_order_number as os,
         so.status,
         so.created_at,
         sum(sop.quantity)       as qtd_na_os,
         row_number() over (partition by sop.product_id order by so.created_at asc) as posicao,
         count(*)    over (partition by sop.product_id) as concorrentes
  from unnest(coalesce(p_product_ids, '{}'::uuid[])) as pid(product_id)
  join service_order_parts sop on sop.product_id = pid.product_id
  join service_orders so       on so.id = sop.service_order_id
  where so.status in ('approved', 'scheduled', 'in_progress', 'awaiting_parts')
  group by sop.product_id, so.id, so.service_order_number, so.status, so.created_at
)
select coalesce(jsonb_object_agg(
         c.product_id,
         jsonb_build_object(
           'service_order_id', c.service_order_id,
           'os',               c.os,
           'status',           c.status,
           'quantidade_na_os', c.qtd_na_os,
           'outras',           greatest(c.concorrentes - 1, 0)
         )
       ), '{}'::jsonb)
from candidatas c
where c.posicao = 1;
$$;

comment on function public.suggest_service_orders_for_products(uuid[]) is
  'Para cada produto, a OS que aguarda aquela peca (mais antiga primeiro). Serve a tela de conferencia da NF-e, ANTES da confirmacao — diferente de suggest_nfe_service_orders, que depende de fiscal_note_items ja gravada. So sugere.';

revoke all on function public.suggest_service_orders_for_products(uuid[]) from public;
revoke all on function public.suggest_service_orders_for_products(uuid[]) from anon;
grant execute on function public.suggest_service_orders_for_products(uuid[]) to authenticated, service_role;
