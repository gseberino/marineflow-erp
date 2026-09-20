# Estoque — Fase E: o saldo vira cache do histórico

**20/09/2026** · plano de execução (fases A–D já feitas: estorno com referência 27/07, view de
variância 28/07, fase C zerando 30 negativos em 18/09) · decisão do dono já tomada ("grande, mas
sem decisão nova") · execução prevista: um bloco de trabalho de um dia, com portão por etapa.

## 1. O problema em uma frase

`products.stock_quantity` é escrito por **14 funções do banco e 4 caminhos do frontend**, cada um
somando ou subtraindo por conta própria; `inventory_movements` é escrito por alguns deles e não por
outros. Resultado medido hoje: **496 produtos ativos, 176 com movimentos, 86 com saldo diferente da
soma dos movimentos**. O fantasma de R$ 380 mil sumiu na fase C, mas a porta continua aberta: basta
um caminho gravar o saldo sem gravar o movimento para a contradição voltar.

## 2. O princípio

Só existe **uma** forma de mexer no estoque: inserir um movimento. O saldo é uma soma. Quem
precisar do saldo lê `products.stock_quantity` como hoje, mas essa coluna passa a ser mantida por
gatilho a partir de `inventory_movements`, e nenhum código escreve nela diretamente.

## 3. Quem escreve o saldo hoje (inventário de 20/09)

| Caminho | Onde | Grava movimento? |
|---|---|---|
| Baixa na conclusão da OS | `trg_so_status_stock` (gatilho em service_orders), `deduct_stock_on_os_complete` | sim (`service_order_usage`) |
| Cancelamento em cascata | `cancel_service_order_cascade` | sim (`return`) |
| Recebimento de OC | `receive_po` | sim (`purchase`) |
| Entrada por XML | `confirm_nfe_import`, `revert_nfe_import` | sim (`purchase` / estorno) |
| Baixa por NF-e avulsa | `settle_nfe_stock_and_receivable`, `reverse_nfe_settlement_on_cancel` | sim |
| Produção de kit | `produce_composed_product` | sim |
| Reconciliação v2 | `reconcile_stock_to_v2` | ajuste manual |
| **Ajuste manual na tela** | `src/hooks/use-inventory.ts` (`update({ stock_quantity })`, linhas ~125 e ~178) | **só às vezes** |
| **Peça adicionada/removida na OS** | `src/hooks/use-service-order-parts.ts` (~78, decrementa direto) | **não** |
| **Cadastro/edição de produto** | `ProductFormDialog`, `QuickProductDialog`, `ServiceOrderForm` (campo `stock_quantity`) | **não** |
| **Importação CSV** | `src/hooks/use-import.ts` (~165) | **não** |
| Tool do agente | `adjust_inventory` (`_shared/ai/tools`) | conferir |

Os quatro em negrito são a porta aberta.

## 4. Etapas, cada uma com portão

### E1 · Uma função para mexer no estoque (banco)
```sql
create function public.registrar_movimento_estoque(
  p_product uuid, p_tipo text, p_delta numeric, p_ref_tipo text, p_ref_id uuid,
  p_custo numeric default null, p_notas text default null) returns uuid
-- insere em inventory_movements e devolve o id. security definer, revoke de anon.
```
Todas as 14 funções do banco passam a chamar esta em vez de fazer `update products set
stock_quantity = …`. O gatilho da etapa E3 cuida do saldo. **Portão:** `grep -c stock_quantity` nas
funções do banco cai a zero fora do gatilho; os testes SQL existentes (receive_po, cancelamento,
NF-e) continuam verdes.

### E2 · Frontend deixa de escrever o saldo
- `use-inventory.ts`: ajuste manual chama RPC `adjust_inventory_v2(product, nova_qtd, motivo)`,
  que calcula o delta e registra `manual_adjustment` com `adjusted_by`.
- `use-service-order-parts.ts`: peça em OS aberta **não** baixa estoque (reserva sim, via
  `reserved_quantity`); a baixa é da conclusão (já é assim no `trg_so_status_stock`). O
  decremento direto na linha ~78 sai.
- Formulários de produto: o campo "Estoque atual" vira somente leitura na edição; na criação,
  valor inicial gera um movimento `opening_balance` pela RPC.
- Importação CSV: idem, `opening_balance` por linha importada.
**Portão:** `grep "update({ stock_quantity" src` retorna zero; smoke tests das telas de estoque,
produto e peças verdes.

### E3 · Saldo passa a ser soma (banco)
```sql
-- 3a) saldo de abertura: fecha a diferença de cada produto NUMA vez, com data de corte
insert into inventory_movements (product_id, movement_type, quantity_delta, reference_type, notes, adjusted_by)
select p.id, 'opening_balance', p.stock_quantity - coalesce(sum(m.quantity_delta), 0), 'cutover',
       'Saldo de abertura da fase E (saldo em tela − soma dos movimentos até o corte)', 'fase-e'
  from products p left join inventory_movements m on m.product_id = p.id
 group by p.id, p.stock_quantity
having p.stock_quantity - coalesce(sum(m.quantity_delta), 0) <> 0;
-- 3b) gatilho: após insert/update/delete em inventory_movements, recalcula o produto tocado
-- 3c) prova: select count(*) from products p where stock_quantity <> (select coalesce(sum(quantity_delta),0) from inventory_movements where product_id = p.id)  →  0
```
**Portão:** contagem 3c em zero; `v_estoque_variancia` ganha a coluna `soma_ledger` comparada ao
saldo (contradição "saldo ≠ soma" passa a existir e nasce em zero).

### E4 · Fecha a porta
Gatilho `before update of stock_quantity on products` que **recusa** a escrita direta, exceto quando
`current_setting('estoque.via_movimento', true) = '1'` (setado pelo gatilho da E3). Assim, qualquer
caminho esquecido quebra alto em vez de corromper baixo.

### E5 · Vigia
Job diário (pode ser um bloco no `ai-business-monitor`) que roda a prova 3c e abre alerta se
qualquer produto divergir. Custo: uma consulta.

## 5. O que NÃO muda
Reserva (`reserved_quantity`) continua com a regra atual (reserva na aprovação, libera na conclusão
ou cancelamento). Preço, custo médio e histórico de preço não entram aqui.

## 6. Riscos e como provar
- **Dupla contagem** na migração das funções (uma função registra o movimento E o gatilho recalcula
  E a função ainda soma): a E1 é feita função a função, com o teste SQL em transação revertida
  (`do $$ … raise exception 'TESTE_OK …' $$`) mostrando saldo antes/depois.
- **Saldo de abertura errado** se houver movimento pendente de estorno: rodar a E3 com a operação
  parada (fim de semana) e conferir `v_estoque_variancia` antes e depois.
- **Rollback:** a E3 é reversível apagando os movimentos `opening_balance` e o gatilho; a E4 é um
  `drop trigger`.

## 7. Ordem e tamanho
E1 (2–3 h) → E2 (2 h) → E3 (1 h, fora do horário de uso) → E4 (30 min) → E5 (30 min). Um dia.
