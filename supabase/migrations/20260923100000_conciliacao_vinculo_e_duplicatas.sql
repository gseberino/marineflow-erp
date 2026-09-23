-- APLICADA EM PRODUCAO em 23/09/2026: 14 duplicatas canceladas (R$ 2.114,78) e 29
-- vinculos reconstruidos. Registrada aqui para que banco e repositorio nao divirjam.
--
-- Conciliacao: devolve o vinculo perdido e desfaz a despesa contada duas vezes.
--
-- CAUSA (medida em 23/09/2026):
--   O banco tem a trava certa -- os indices unicos `payables_uma_por_transacao` e
--   `receivables_uma_por_transacao` impedem duas contas para a mesma transacao. Mas sao
--   PARCIAIS (`where bank_transaction_id is not null`): quem grava nulo passa por baixo.
--
--   A tela de Conciliacao gravava nulo. Ela marcava `bank_transactions.reconciled = true`
--   e ligava o pagamento, mas nunca apontava a conta para a transacao. Com isso:
--     1. a trava do banco nao protegia esses lancamentos;
--     2. a varredura da caixa de entrada, que decide "ja virou lancamento?" olhando
--        exatamente `payables.bank_transaction_id`, nao enxergava o que a tela criou --
--        e propunha a mesma despesa de novo, aprovada de boa-fe no dia seguinte.
--
--   A cronologia confirma: em 04/08 a tela criou as contas sem vinculo, em 05/08 a caixa
--   de entrada criou as gemeas com vinculo. Doze pares assim, mais dois de 07/04 vindos
--   do caminho de despesa de OS.
--
-- O codigo ja foi corrigido (os quatro inserts da tela e o `useReconcile` agora gravam o
-- vinculo, e a violacao de unicidade virou mensagem legivel). Esta migration cuida do que
-- ficou para tras.

-- ---------------------------------------------------------------------------
-- 1. Backfill: 29 lancamentos sem vinculo, reconstruidos SEM adivinhar.
--
-- A transacao guarda `reconciled_payment_id` e o pagamento sabe de qual conta ele e:
-- transacao -> pagamento -> conta. E um caminho deterministico, nao um palpite por
-- data e valor. O `not exists` evita brigar com a trava quando a transacao ja foi
-- reivindicada por outra conta (conta paga em parcelas recebe varias transacoes).
-- ---------------------------------------------------------------------------
update payables p
   set bank_transaction_id = t.id
  from bank_transactions t
  join payments pm on pm.id = t.reconciled_payment_id
 where pm.payable_id = p.id
   and p.bank_transaction_id is null
   and t.reconciled = true
   and not exists (select 1 from payables x where x.bank_transaction_id = t.id);

update receivables r
   set bank_transaction_id = t.id
  from bank_transactions t
  join payments pm on pm.id = t.reconciled_payment_id
 where pm.receivable_id = r.id
   and r.bank_transaction_id is null
   and t.reconciled = true
   and not exists (select 1 from receivables x where x.bank_transaction_id = t.id);

-- ---------------------------------------------------------------------------
-- 2. A informacao que so o duplicado tem, antes de ele sair de cena.
--
-- Cancelar o duplicado nao pode apagar o que ele sabia. Um deles carrega o vinculo com a
-- ordem de servico e o gemeo que fica nao carrega -- sem esta transferencia, o custo
-- sumiria da OS. A comissao da OS-00073 (faturada) e o caso real.
-- ---------------------------------------------------------------------------
update payables fica
   set linked_service_order_id = sai.linked_service_order_id
  from payables sai
 where sai.id = 'e005b0be-f3ac-413e-9812-a2a88e2b2f9c'
   and fica.bank_transaction_id is not null
   and fica.issue_date = sai.issue_date
   and fica.amount = sai.amount
   and fica.linked_service_order_id is null;

-- ---------------------------------------------------------------------------
-- 3. As 14 duplicatas, canceladas -- nao apagadas.
--
-- Cancelar mantem o rastro e e reversivel; apagar destruiria a prova de que isto
-- aconteceu, que e justamente o que impede o erro de voltar sem ninguem notar. O que
-- fica em cada par e sempre o lado COM vinculo bancario: ele tem categoria, fornecedor
-- e o apontamento para o extrato.
--
-- Os dois de 07/04 ("Despesa OS SO-2026-00002") sao o mesmo abastecimento lancado pelo
-- caminho da OS; conferido: a OS-00002 esta cancelada e e de teste, nao ha custo a
-- preservar nela.
-- ---------------------------------------------------------------------------
with duplicadas(id) as (values
  ('86f1641e-ec85-4979-8a19-b7c229b81c9a'::uuid),  -- 01/08 MERCADOLIVRE       267,80
  ('c44b775e-428b-4124-9829-aa3f0d5d61d1'::uuid),  -- 01/08 ZEFLEX             199,00
  ('820edafe-6316-4c5e-bac0-96197e9d6e4b'::uuid),  -- 01/08 Coremma            120,50
  ('1dafa05e-c6d9-47a8-b227-8e3b57132653'::uuid),  -- 01/08 POSTO CAT2          71,97
  ('62d05b78-6abb-4970-9195-e2fab73e621c'::uuid),  -- 01/08 MABOREMB            64,94
  ('0eb0dd6b-2c03-4390-8373-64fb2ad3f3dd'::uuid),  -- 01/08 MABOREMB            57,79
  ('495dc423-987b-4f0f-b302-229fe1bbced0'::uuid),  -- 01/08 MERCADOLIVRE        53,99
  ('c558d413-a721-4415-bf1f-ad785400c1d9'::uuid),  -- 02/08 MERCADOLIVRE        78,84
  ('e005b0be-f3ac-413e-9812-a2a88e2b2f9c'::uuid),  -- 03/08 Thaline (comissao) 100,00
  ('863754d0-138a-49e9-9689-4b9606d1b460'::uuid),  -- 03/08 Roberto             66,00
  ('d488cd74-5c52-4ff8-b296-014711659c2d'::uuid),  -- 04/08 CORREA MATERIAIS   767,95
  ('377af9e9-f5ff-4b16-82b2-6f8da3096922'::uuid),  -- 04/08 Roberto             66,00
  ('c2f10f33-0724-4cd9-917a-012a314680a1'::uuid),  -- 07/04 Despesa OS-00002   100,00
  ('eda87de2-94a7-42f6-9ad2-88577014462d'::uuid)   -- 07/04 Despesa OS-00002   100,00
)
update payables p
   set status = 'cancelled',
       paid_amount = 0,
       balance_amount = 0,
       notes = concat_ws(
         E'\n', p.notes,
         'Cancelada em 23/09/2026: despesa lancada duas vezes. O mesmo pagamento ja esta '
         || 'registrado na conta vinculada a transacao bancaria. Causa corrigida no codigo '
         || '(o vinculo conta-transacao passou a ser gravado pela tela de Conciliacao).'),
       updated_at = now()
  from duplicadas d
 where p.id = d.id
   and p.status <> 'cancelled';

-- O pagamento do duplicado vai junto: os relatorios de caixa somam `payments` com
-- status 'confirmed', entao deixa-lo confirmado manteria o dinheiro saindo duas vezes
-- no fluxo mesmo com a conta cancelada.
update payments pm
   set status = 'cancelled'
 where pm.payable_id in (
         '86f1641e-ec85-4979-8a19-b7c229b81c9a','c44b775e-428b-4124-9829-aa3f0d5d61d1',
         '820edafe-6316-4c5e-bac0-96197e9d6e4b','1dafa05e-c6d9-47a8-b227-8e3b57132653',
         '62d05b78-6abb-4970-9195-e2fab73e621c','0eb0dd6b-2c03-4390-8373-64fb2ad3f3dd',
         '495dc423-987b-4f0f-b302-229fe1bbced0','c558d413-a721-4415-bf1f-ad785400c1d9',
         'e005b0be-f3ac-413e-9812-a2a88e2b2f9c','863754d0-138a-49e9-9689-4b9606d1b460',
         'd488cd74-5c52-4ff8-b296-014711659c2d','377af9e9-f5ff-4b16-82b2-6f8da3096922',
         'c2f10f33-0724-4cd9-917a-012a314680a1','eda87de2-94a7-42f6-9ad2-88577014462d')
   and pm.status = 'confirmed';
