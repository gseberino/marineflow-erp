-- ─────────────────────────────────────────────────────────────────────────────
-- Entrada de mercadoria passa a saber PARA QUEM a peça foi comprada.
--
-- O PROBLEMA (medido 04/08/2026): das 4 notas de entrada em produção, NENHUMA está
-- vinculada a ordem de compra, e há 2 OS aguardando peça. As 43 entradas de compra
-- viraram estoque genérico — a peça chega e a OS que a motivou continua parada,
-- porque nada liga uma coisa à outra. Se duas OS esperam o mesmo produto e chega
-- uma unidade, ela é de quem consumir primeiro.
--
-- O vínculo existia, mas em CADEIA 1:1: nota → uma OC → uma OS
-- (`fiscal_notes.purchase_order_id`, `purchase_orders.service_order_id`). Isso não
-- descreve a operação real: compra-se de um fornecedor uma vez só, para economizar
-- frete, e naquela nota vêm peças de duas ou três OS. A cadeia obriga a escolher uma
-- (falso) ou a não vincular nada — que foi o que aconteceu nas 4 notas.
--
-- POR QUE NA LINHA E NÃO NA NOTA: é como Odoo, SAP e ERPNext resolvem. Se a nota
-- inteira apontasse para três OS, ficaria ambíguo qual peça é de qual — e é
-- exatamente isso que se precisa saber. Uma coluna na linha dá N:N de graça: a nota
-- tem itens de várias OS, e uma OS recebe itens de várias notas (entrega parcelada).
--
-- A OC continua OPCIONAL e não vira pré-requisito. Criar uma ordem de compra a
-- partir da nota que chegou produziria um confronto vazio — bateria sempre, por
-- construção — e a OC existe justamente para confrontar pedido × recebido.
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.fiscal_note_items
  add column if not exists service_order_id uuid references public.service_orders(id) on delete set null;

comment on column public.fiscal_note_items.service_order_id is
  'OS para a qual ESTE item foi comprado. NULL = compra para estoque, sem dono. O vinculo e por linha (nao pela nota) porque uma nota costuma trazer peca de varias OS.';

create index if not exists idx_fni_service_order on public.fiscal_note_items(service_order_id)
  where service_order_id is not null;

-- ─────────────────────────────────────────────────────────────────────────────
-- suggest_nfe_service_orders — o encurtamento de fluxo que interessa.
--
-- O sistema já sabe quem está esperando o quê: quais OS estão comprometidas e quais
-- produtos elas reservaram. Em vez de pedir mais um campo ao usuário, ele propõe o
-- vínculo e a pessoa confirma. Devolve UMA sugestão por item, a mais antiga primeiro
-- (quem espera há mais tempo tem prioridade) — critério explícito, não sorte.
--
-- Só sugere; não grava nada. Quem decide é a tela.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.suggest_nfe_service_orders(p_note_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
with itens as (
  select i.id as item_id,
         coalesce(i.matched_product_id, i.product_id) as product_id,
         coalesce(i.q_com, i.quantity, 0) as qtd
  from fiscal_note_items i
  where i.fiscal_note_id = p_note_id
),
candidatas as (
  select it.item_id,
         so.id   as service_order_id,
         so.service_order_number as os,
         so.created_at,
         sum(sop.quantity) as qtd_na_os,
         row_number() over (partition by it.item_id order by so.created_at asc) as posicao
  from itens it
  join service_order_parts sop on sop.product_id = it.product_id
  join service_orders so       on so.id = sop.service_order_id
  where it.product_id is not null
    and so.status in ('approved', 'scheduled', 'in_progress', 'awaiting_parts')
  group by it.item_id, so.id, so.service_order_number, so.created_at
)
select coalesce(jsonb_object_agg(
         c.item_id,
         jsonb_build_object(
           'service_order_id', c.service_order_id,
           'os', c.os,
           'quantidade_na_os', c.qtd_na_os,
           'motivo', 'esta peça está reservada para esta OS, que aguarda material'
         )
       ), '{}'::jsonb)
from candidatas c
where c.posicao = 1;
$$;

comment on function public.suggest_nfe_service_orders(uuid) is
  'Sugere, por item da nota, a OS que esta esperando aquela peca (mais antiga primeiro). So sugere — nao grava.';

revoke all on function public.suggest_nfe_service_orders(uuid) from public;
revoke all on function public.suggest_nfe_service_orders(uuid) from anon;
grant execute on function public.suggest_nfe_service_orders(uuid) to authenticated, service_role;
