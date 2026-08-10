# Reorganização do módulo financeiro

**Data:** 09/08/2026
**Origem:** o gestor apontou três coisas — (1) conciliação está invertida, (2) submenu
lateral e abas competem entre si, (3) cartão está misturado com Pix/transferência.
**Status:** proposta, aguarda decisão.

---

## 1. O diagnóstico, com números

### 1.1 A inversão conceitual — confirmada

`src/components/BankReconciliation.tsx:122`:

```ts
const pending = allTx.filter(t => !t.reconciled);
```

A aba "Conciliação" lista **toda linha do extrato que ainda não foi tratada**. Isso é fila
de triagem do extrato, não conciliação. Conciliação é comparar o que EU registrei com o que
o banco diz.

O que a coluna `reconciled` significa hoje, medido no banco de produção:

| O que aconteceu de fato | Quantidade | É conciliação? |
|---|---:|---|
| Casou com um pagamento que já existia no sistema | **41** | sim |
| Gerou um lançamento novo a partir da linha do extrato | **1.627** | não — é registro |
| Marcada sem deixar rastro (legado) | 11 | indeterminado |
| Fora da fila (`dismissed_reason`) | 377 | não |

Uma coluna booleana carregando três significados diferentes é a raiz da confusão. A tela não
está errada por acaso: ela reflete fielmente um dado que está errado.

### 1.2 A navegação dupla — confirmada

- `src/components/AppLayout.tsx:233-249` — **11 itens** no submenu "Financeiro"
- `src/v2/pages/FinancialV2.tsx:338-362` — **11 abas** dentro de `/v2/financial`
- **6 itens do menu** apontam para `?tab=...` — mesmo destino, dois caminhos
- **5 abas não têm entrada no menu**: `dre`, `ignoradas`, `fechamento`, `cadastro`, `aging`

Nenhum dos dois sistemas é completo, e os dois se sobrepõem no meio. O comentário no próprio
`AppLayout.tsx:223-232` registra que isso já foi mexido uma vez trocando "escondido demais"
por um meio-termo — o meio-termo é o que confunde agora.

### 1.3 O cartão misturado — confirmado

| Origem | Na fila | Lançadas/conciliadas | Fora da fila | Total |
|---|---:|---:|---:|---:|
| Conta bancária | 89 | 767 | 175 | **1.031** |
| Cartão de crédito | 2 | 912 | 202 | **1.116** |

Os dois convivem na mesma fila com a mesma interface, mas são objetos diferentes:

- Compra no cartão **não tem contraparte** (não é transferência). A identidade vem de
  `merchant_name` + `payee_mcc`, não de CNPJ do recebedor — por isso só 4% têm documento.
- Compra no cartão **não sai do caixa** na data da compra. Sai quando a fatura é paga.
- Hoje **1.650 das 1.676 contas a pagar nasceram do extrato já com status `paid`** —
  a tela "Contas a Pagar" virou o livro de despesas históricas. Só **4** são obrigações reais.

---

## 2. O que o mercado faz (pesquisa)

Duas escolas, e elas explicam exatamente o desconforto.

### Escola A — feed e conciliação separados (QuickBooks, NetSuite, Odoo, Omie)

- **QuickBooks**: aba *Banking → For Review* recebe o feed; você categoriza ou casa, e a linha
  fica **Cleared (C)**. Só a ferramenta separada *Reconcile* — que pede data e saldo final do
  extrato — marca **Reconciled (R)**. Duas telas, dois propósitos, dois estados.
- **NetSuite**: página **Match Bank Data** (casamento linha a linha) e página **Reconcile
  Account Statement** (fecha o período com saldo final e calcula a diferença). A documentação
  da Oracle é explícita: uma faz transação, a outra faz período.
- **Odoo**: a linha do extrato entra numa **conta transitória (suspense account)** e só sai de
  lá quando alguém aponta a contrapartida. O "não tratado" aparece como saldo transitório, não
  como "pendente de conciliação".
- **Omie / Conta Azul**: importam o extrato, auto-conciliam o que casa e **criam lançamento**
  para o que não casou — deixando claro que criar ≠ conciliar.

### Escola B — conciliação-led (Xero)

Não existe staging: toda linha vive na tela *Reconcile* até ser processada, e você concilia ao
mesmo tempo em que registra. Existe a grade *Cash Coding* para tratar em lote e a aba *Bank
Statements* para ver o extrato cru.

**O sistema hoje é um híbrido dos dois**, e é o pior dos mundos: tem o staging da escola A
("Caixa de entrada", só débitos) *e* a tela única da escola B ("Conciliação", tudo), com o
mesmo dado aparecendo nos dois lugares por critérios diferentes.

A intuição do gestor é a **escola A** — que é a majoritária e a que auditoria espera, porque
separa "registrei" de "bateu com o banco".

### Sobre cartão

Consenso em todas as fontes: cartão de crédito é **conta própria**, com reconciliação
própria contra a fatura, não contra o caixa. A compra debita despesa e credita a conta
"cartão"; **a fatura** é a obrigação que vira conta a pagar e é ela que aparece no extrato
bancário quando paga. Lançar cada compra como conta a pagar individual — o que o sistema faz
hoje em 908 casos — duplica a obrigação.

---

## 3. O desenho proposto

Três destinos, um para cada pergunta que alguém faz ao abrir o sistema.

### 3.1 **Extrato** — "o que o banco trouxe e eu ainda não registrei?"

Absorve a atual "Caixa de entrada" **e** a fila da atual "Conciliação". Deixa de existir a
duplicação: a fila é uma só, e é o extrato.

- **Fonte:** linhas de `bank_transactions` sem lançamento e sem descarte
- **Entra tudo:** débito e crédito. Hoje os 87 créditos (R$ 628 mil) nunca entram na caixa de
  entrada por decisão de projeto — é justamente por isso que faltam no DRE.
- **Ações:** virar lançamento · casar com algo que já existe · tirar da fila
- **Recortes internos (abas legítimas — mesmo material):** Conta bancária | Cartão | Fora da fila
- **Interface:** herda a da Caixa de entrada, que já tem agrupamento por favorecido,
  multi-seleção, ordenação, MCC e aprovação em lote. (O próprio gestor: *"a caixa de entrada
  tem funcionalidade melhor que a conciliação"*.)

### 3.2 **Conciliação** — "o que eu registrei bate com o banco?"

Tela nova, pequena, com o sentido correto. Parte dos **lançamentos**, não do extrato.

- Lançamento **com** linha do extrato casada → conciliado (41 hoje)
- Lançamento **sem** linha no extrato → registrei e não caiu no banco *(investigar)*
- Linha do extrato **sem** lançamento → caiu e não registrei *(link para o Extrato)*
- Casamento **sugerido pelo sistema**, aguardando confirmação
- **Fechamento do período** contra saldo final — a tela `FechamentoPanel` já existe e passa a
  morar aqui, que é o lugar dela (é o equivalente ao *Reconcile Account Statement*)

### 3.3 **Cartões** — módulo separado

- Visão por cartão (final) e por **fatura** (`bill_id` já preenchido em 899 linhas)
- Compra = **despesa** na data da compra, com ramo/MCC e categoria
- **A fatura** é a única conta a pagar
- Conciliação do cartão = fatura fechada × pagamento da fatura no extrato bancário
- Compras de cartão saem da fila do banco

---

## 4. Mudança de dados

**Princípio: nada destrutivo.** A informação para separar os três significados de `reconciled`
já existe nas colunas atuais — falta apenas lê-la corretamente.

View `bank_transactions_situacao` (ou coluna derivada):

```sql
case
  when dismissed_reason is not null                      then 'fora'
  when reconciled_payment_id is not null                 then 'conciliada'  -- casou de verdade
  when exists (select 1 from payables    p where p.bank_transaction_id = bt.id)
    or exists (select 1 from receivables r where r.bank_transaction_id = bt.id)
                                                          then 'lancada'    -- virou registro
  when reconciled                                         then 'lancada'    -- legado sem link
  else                                                          'nova'
end
```

Regras da casa que valem aqui: `security_invoker=on` e `REVOKE` de `anon` na mesma migration.

Pendências de dado a resolver na mesma fase:

- **11 transações sem rastro** — marcadas conciliadas, sem pagamento e sem lançamento. Precisam
  ser identificadas e devolvidas à fila ou vinculadas.
- **`payables.bank_transaction_id`** já existe e cobre 1.650 registros — é a trilha de auditoria
  do que nasceu do extrato. Serve de base para a nova Conciliação sem criar tabela nenhuma.

---

## 5. Navegação — um mapa só

**Regra:** o menu lateral é o único mapa do módulo. Aba só existe quando é *recorte do mesmo
material* dentro de uma tela — nunca como caminho alternativo para um destino.

| Hoje (11 itens + 11 abas) | Proposto (7 itens) |
|---|---|
| Visão Geral · DRE · Aging | **Visão Geral** — DRE e Aging como abas (leituras do mesmo dado) |
| Caixa de Entrada · Conciliação (fila) · Fora da fila | **Extrato** — abas Banco / Cartão / Fora da fila |
| *(não existe)* · Fechamento | **Conciliação** — abas Sugeridas / Casadas / Sem par / Fechamento |
| *(disperso na fila do banco)* | **Cartões** — por cartão e por fatura |
| Contas a Receber | **Contas a Receber** |
| Contas a Pagar | **Contas a Pagar** — abas Em aberto / Histórico pago |
| Regras da IA · Contas Bancárias · Saúde do cadastro | **Configuração** — as três como abas |

Comissões, Favorecidos, Emissão Fiscal e Relatórios continuam como estão (são telas inteiras,
já com rota própria).

Cada item do menu vira **rota de verdade** (`/v2/financial/extrato`, `/v2/financial/conciliacao`,
…). Somem os `?tab=` do menu — que é a origem exata do "não sei se clico na lateral ou em cima".

---

## 6. Execução em fases

Cada fase é entregável sozinha e nenhuma move móvel duas vezes.

### F1 · Verdade nos dados *(invisível, base de tudo)*
View de situação · backfill dos vínculos faltantes · identificar as 11 sem rastro.
**Risco:** nenhum na UI. **Reversível:** sim (é view).

### F2 · Extrato ≠ Conciliação *(o coração do pedido)*
A fila vira "Extrato" com a interface da Caixa de entrada, absorvendo créditos e o que hoje
está na aba Conciliação. Nasce a Conciliação de verdade sobre os lançamentos, com o Fechamento
dentro. Esses dois itens já viram rota real no menu.
**Risco:** médio — mexe nas duas telas mais usadas. **Mitigação:** smoke test de render por
aba (padrão `AgendaPage.smoke.test.tsx`) antes de deploy.

### F3 · Cartões fora da fila do banco
Módulo próprio · fatura como entidade e como única conta a pagar · compras de cartão saem da
fila do banco. Absorve o item B3 que já estava pendente e agora está desbloqueado.
**Risco:** médio — reclassifica 908 contas a pagar. **Mitigação:** tabela de reparo com
`bank_transaction_id`, como no reparo Coremma.

### F4 · Menu único
O resto do menu vira rota; abas só como recorte; some a duplicação.
**Risco:** baixo. **Atenção:** manter redirect dos `?tab=` antigos para não quebrar link salvo.

### F5 · Contas a Pagar volta a ser obrigação
Em aberto é a lista principal; histórico pago é recorte.
**Risco:** baixo.

---

## 7. Decisões que dependem do gestor

1. **Nome do destino da fila** — recomendo **"Extrato"**, porque é literalmente o que é, e
   porque "Caixa de entrada" deixa de existir como destino separado (ela *é* a fila).
   Alternativas: manter "Caixa de entrada" · "Análise de extrato".
2. **Aposentar a interface atual da Conciliação** (`BankReconciliation.tsx`, 1.727 linhas) em
   favor da interface da Caixa de entrada — recomendo sim, com base no que o próprio gestor
   observou sobre qual das duas funciona melhor.
3. **Ordem das fases** — recomendo F1 → F2 → F3 → F4 → F5. F2 antes de F4 evita mexer no menu
   duas vezes.

---

## Fontes

**Feed vs. conciliação**
- [Xero and QuickBooks — Bank Coding Differences](https://report.woodard.com/articles/xero-and-quickbooks-bank-coding-differences-ocawr)
- [Bank Reconciliation in QuickBooks Online (2026)](https://bankreconciler.app/blogQuickBooksReconciliation)
- [Bank Reconciliations in QuickBooks & Xero](https://polaristaxandaccounting.com/bank-reconciliations-quickbooks-xero/)
- [Xero vs QuickBooks Online: Reconciliation API Gap](https://satvasolutions.com/blog/xero-vs-qbo-api-reconciliation-gap)

**NetSuite — as duas páginas**
- [Bank Data Matching and Reconciliation (Oracle)](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/chapter_4842302228.html)
- [Matching Bank Data (Oracle)](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_4843222719.html)
- [Reconciling Bank Statements (Oracle)](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N1552329.html)
- [Editing Accounts to Use Match Bank Data and Reconcile Account Statement](https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_162636875948.html)
- [NetSuite Bank Reconciliation Made Simple (Numeric)](https://www.numeric.io/blog/netsuite-bank-reconciliation)
- [Solving NetSuite Bank Reconciliation Differences (Prolecto)](https://blog.prolecto.com/2024/04/07/solving-netsuite-bank-reconciliation-differences/)

**Odoo — conta transitória e modelos**
- [Bank reconciliation — Odoo 17](https://www.odoo.com/documentation/17.0/applications/finance/accounting/bank/reconciliation.html)
- [Reconciliation models — Odoo 17](https://www.odoo.com/documentation/17.0/applications/finance/accounting/bank/reconciliation_models.html)
- [Odoo Bank Reconciliation: A CPA's Setup & Automation Guide](https://theledgerlabs.com/odoo-bank-reconciliation-guide/)

**Xero — cash coding, regras, abas**
- [Reconcile statement lines in bulk — Xero Central](https://central.xero.com/0/article/Reconcile-using-cash-coding-US)
- [Xero Bank Reconciliation Guide (2026)](https://bankreconciler.app/blogXeroReconciliation)
- [Categorise Transactions in Xero: bank feed workflow](https://bankreconciler.app/blogCategorizeTransactionsXero)
- [Xero Reconciliation Simplified (Numeric)](https://www.numeric.io/blog/how-to-reconcile-in-xero)

**pt-BR — Omie e Conta Azul**
- [Importando extratos e realizando a conciliação bancária — Omie](https://ajuda.omie.com.br/pt-BR/articles/6506873-importando-extratos-e-realizando-a-conciliacao-bancaria)
- [Perguntas frequentes: conciliação bancária — Omie](https://ajuda.omie.com.br/pt-BR/articles/6812438-perguntas-frequentes-conciliacao-bancaria)
- [Associando vários lançamentos do extrato com apenas um — Omie](https://ajuda.omie.com.br/pt-BR/articles/10069800-conciliacao-bancaria-associando-varios-lancamentos-do-extrato-com-apenas-um-no-omie)
- [Conciliação bancária: perguntas frequentes — Conta Azul](https://ajuda.contaazul.com/hc/pt-br/articles/29276816907533-Concilia%C3%A7%C3%A3o-banc%C3%A1ria-perguntas-frequentes-sobre-como-bater-saldo)

**Cartão de crédito como conta própria**
- [Set up, use, and pay credit card accounts — QuickBooks](https://quickbooks.intuit.com/learn-support/en-us/help-article/chart-accounts/set-use-pay-credit-card-accounts/L6cksFiDF_US_en_US)
- [Record your payments to credit cards — QuickBooks](https://quickbooks.intuit.com/learn-support/en-us/help-article/pay-bills/record-payments-credit-cards/L7IjpiWLZ_US_en_US)
- [Credit Card Reconciliation: Steps, Tips & Best Practices (HighRadius)](https://www.highradius.com/resources/Blog/credit-card-reconciliation/)
- [Complete Guide to Credit Card Reconciliation (Tipalti)](https://tipalti.com/resources/learn/credit-card-reconciliation/)
- [What is Credit Card Reconciliation (FloQast)](https://www.floqast.com/blog/what-is-how-to-credit-card-reconciliation)
- [Conta Cartão de Crédito: como lançar compras — Conta Azul](https://ajuda.contaazul.com/hc/pt-br/articles/8328868327821-Conta-Cart%C3%A3o-de-Cr%C3%A9dito-como-lan%C3%A7ar-compras)
- [Como lançar compras com cartão de crédito — Maxiprod](https://maxiprod.com.br/ajuda/compras/compras-perguntas-frequentes/como-lancar-compras-com-cartao-de-credito/)

**Arquitetura de informação e navegação**
- [The Difference Between Information Architecture and Navigation — NN/g](https://www.nngroup.com/articles/ia-vs-navigation/)
- [3 Common IA Mistakes (Low Information Scent) — NN/g](https://www.nngroup.com/articles/3-ia-mistakes/)
- [Stop Using Secondary Navigation Bars… Maybe! — Boagworld](https://boagworld.com/design/secondary-navigation/)
- [Secondary Navigation — Appian SAIL Design System](https://docs.appian.com/suite/help/26.6/sail/secondary-navigation.html)
- [UX navigation design: patterns and best practices — Eleken](https://www.eleken.co/blog-posts/ux-navigation-design)
