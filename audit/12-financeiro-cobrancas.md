# 12 — Financeiro, Cobranças e Bancário (Etapa 2, módulo 3)

Superfície: `src/pages/FinancialPage.tsx` (895 l) e `src/v2/pages/FinancialV2.tsx`, `ReceivablesV2`,
`CollectionsPage`/`CollectionsV2`, `CommissionsPage`/`CommissionsV2`, `src/components/collections/*` (8),
`BankReconciliation.tsx` (1.699 l), `FinanceReviewInbox.tsx` (1.122 l), `FinanceRulesPanel`, `IgnoradasPanel`,
`FechamentoPanel`, `DREPanel`, `AgingReportPanel`, `CashForecastPanel`, `ReimbursementsPanel`,
`BankSourcesPanel`, `BankConnectionsPanel`, `SaudeDoCadastroPanel`, hooks `use-financial`, `use-collections`,
`use-reconciliation`, `use-finance-review`, `use-fechamento`, `use-bank-connections`, libs `dre.ts`,
`client-statement.ts`, `bank-parser.ts`, `finance-inbox-grouping.ts`, `_shared/banking/*`, Edge Functions
`banking-sync`, `banking-reconcile`, `finance-review`, `pluggy-*`, `balance-reminders`, `receivable-reminders`.

---

## 12.1 Achados

### [MF-AUD-050] Quatro funcionalidades ficaram para trás na migração para a V2 — invisíveis no app
- **Módulo:** Financeiro / Cadastros / Dashboard
- **Arquivo:linha:** `src/components/CashForecastPanel.tsx` (130 l) e `BulkBillingReminderDialog.tsx` (546 l),
  importados só por `src/pages/FinancialPage.tsx:18-19`; `src/components/ClientStatementDialog.tsx` (109 l),
  importado só por `src/pages/ClientDetail.tsx`; `src/components/agenda/DashboardTasksWidget.tsx` (51 l),
  importado só por `src/pages/Dashboard.tsx`
- **Categoria:** B/C — **Severidade:** P1
- **Descrição:** Varredura de todos os 146 componentes de `src/components/**` (fora `ui/`) buscando quais são
  importados **exclusivamente** por páginas legadas. Quatro apareceram. Como as rotas redirecionam para a V2
  desde 30/07 (`LegadoOuV2`, MF-AUD-037), essas quatro funcionalidades **não existem mais no app** — só abrindo
  a URL com `?legacy=1`:

  1. **`CashForecastPanel` — programação de pagamentos por semana.** Não é o mesmo que o gráfico da V2. O
     `FinancialV2` reimplementou "fluxo de caixa 3/6/12 meses" inline com Recharts (`:394-405`), enquanto o
     painel legado responde outra pergunta — "o que vence nas próximas 8 semanas" — e traz duas coisas que a V2
     não tem: **alerta de semanas negativas** (`semanasNegativas`) e **detecção de contas a pagar duplicadas**
     (`useDuplicatePayables`). Tem teste próprio (`CashForecastPanel.smoke.test.tsx`).
  2. **`BulkBillingReminderDialog` — cobrança em lote por WhatsApp (546 linhas).** A maior das quatro. Não há
     equivalente no `FinancialV2` (busca por `bulk`/`lote`/`BillingReminder` no arquivo: nada).
  3. **`ClientStatementDialog` — extrato do cliente.** Apoiado por lib pura com teste
     (`src/lib/client-statement.ts` + `client-statement.test.ts`). `ClientDetailV2` não tem nenhuma referência a
     extrato.
  4. **`DashboardTasksWidget` — widget de tarefas no Dashboard.** É exatamente o item `[V-32]` do plano
     `marineflow-agenda-tarefas.md`, declarado concluído na Fase 1 ("widget no Dashboard"). O `DashboardV2` não o
     importa; tem apenas links para `/v2/agenda`.

  Este é o custo concreto da transição inacabada descrita em MF-AUD-037, e é diferente de "código morto": é
  **funcionalidade viva que o usuário perdeu sem aviso**.
- **Evidência:** varredura programática sobre 146 componentes (importadores de cada um, cruzados com a lista das
  19 páginas legadas). Resultado:
  ```
  SÓ EM TELA LEGADA  DashboardTasksWidget       Dashboard.tsx
  SÓ EM TELA LEGADA  BulkBillingReminderDialog  FinancialPage.tsx
  SÓ EM TELA LEGADA  CashForecastPanel          FinancialPage.tsx
  SÓ EM TELA LEGADA  ClientStatementDialog      ClientDetail.tsx
  ```
  ```
  $ grep -n -i "forecast|previs|fluxo" src/v2/pages/FinancialV2.tsx
  39:   visão geral (KPIs + fluxo de caixa 3/6/12m + próximos 30d), DRE,   ← escopo declarado, sem o painel semanal
  $ grep -n -i "bulk|lote|BillingReminder" src/v2/pages/FinancialV2.tsx   → nenhum
  $ grep -n "Statement|extrato" src/v2/pages/ClientDetailV2.tsx           → nenhum
  ```
- **Ação recomendada:** confirmar com o Gustavo quais das quatro ele usa (é possível que alguma tenha sido
  abandonada de propósito) e portar as escolhidas para a V2 — os componentes existem e funcionam, é trabalho de
  montar na tela nova, não de reescrever. Depois disso, MF-AUD-037 (apagar as legadas) fica seguro.
- **Esforço:** M — **Decisão do Gustavo:** Sim — **quais das quatro devem voltar?** Esta é a decisão de maior
  impacto imediato para o uso diário.

### [MF-AUD-051] Combobox de fornecedor em contas a pagar — ver [MF-AUD-045]
`src/components/PayableFormDialog.tsx:123` busca por `s.contact_email`, campo que não existe em `suppliers`.
Registrado no módulo 23 junto com os demais erros que o `tsc` acusa.

### [MF-AUD-052] Tabelas do financeiro forçam rolagem lateral no celular
- **Módulo:** Financeiro / UI
- **Arquivo:linha:** `src/components/AgingReportPanel.tsx:150` (`min-w-[700px]`),
  `BankReconciliation.tsx:786` (`min-w-[600px]`), `:1622` e `:1665` (`min-w-[800px]`),
  `ReimbursementsPanel.tsx:31` (`min-w-[800px]`), `BankSourcesPanel.tsx:107` (`min-w-[520px]`),
  `BulkEditor.tsx:213` (`min-w-[1000px]`), `ImportWizard.tsx:213,264`
- **Categoria:** G/H — **Severidade:** P2
- **Descrição:** Enquanto as listas principais foram resolvidas com orçamento de colunas
  (`DataTable`, "Princípio 0 — zero scroll horizontal, por construção"), os painéis financeiros mantêm tabelas
  com largura mínima fixa dentro de `overflow-x-auto`. Em telefone, isso é exatamente a barra de rolagem lateral
  que o Princípio 0 existe para eliminar — e vários desses painéis (aging, conciliação, reembolsos) são de uso
  do dono, que trabalha do celular. Nove ocorrências, em sete arquivos.
- **Evidência:**
  ```tsx
  src/components/BulkEditor.tsx:213        <table className="text-xs w-full min-w-[1000px]">
  src/components/BankReconciliation.tsx:1622 <table className="w-full text-sm min-w-[800px]">
  src/components/ReimbursementsPanel.tsx:31  <table className="w-full text-sm min-w-[800px]">
  src/components/AgingReportPanel.tsx:150    <table className="w-full text-sm min-w-[700px]">
  ```
- **Ação recomendada:** migrar esses painéis para o `DataTable` da V2 (que já resolve o problema) ou, onde a
  tabela for essencialmente uma matriz, adotar o padrão de cartão empilhado no mobile, como o `WeekView` da
  Agenda faz.
- **Esforço:** M — **Decisão do Gustavo:** Não (a preferência por zero rolagem lateral já está estabelecida).

---

## 12.2 Verificações feitas que **não** produziram achado

- **Conciliação bancária — o plano `marineflow-conciliacao-inteligente.md` (Fases 1-3, "ENTREGUE") confere:**
  `supabase/functions/_shared/banking/{types,matching,quote-deposit}.ts` existem; as tools
  `listar_transacoes_pendentes`/`sugerir_conciliacao`/`conciliar_transacao` estão em
  `_shared/ai/tools/banking.ts`; a Edge `banking-reconcile` existe; e há **8 arquivos de teste** de banking em
  `src/test/` (matching, proposals, installments, internal-transfers, pluggy-map, quote-deposit-paridade).
  `[V-41]`, `[V-42]`, `[V-44]`, `[V-45]` confirmados.
- **Livro das "ignoradas" (`[V-47]`, F1 do plano `conciliacao-definitiva`, marcada como URGENTE):**
  **entregue** — `IgnoradasPanel.tsx` existe, tem smoke test e está montado no `FinancialV2.tsx:613`.
- **Fechamento de período:** `FechamentoPanel` montado (`FinancialV2.tsx:614`), com RLS correta na tabela
  `periodos_fechados` (admin fecha/reabre, financeiro lê) — ver módulo 20.
- **Sinal do orçamento com desconto:** a lib única `src/lib/quote-deposit.ts` existe, com teste próprio **e**
  teste de paridade com o espelho do backend (`src/test/banking-quote-deposit-paridade.test.ts`, 12 casos).
  A classe de bug registrada na memória do projeto está fechada.
- **DRE:** `src/lib/dre.ts` + `dre.test.ts` (8 casos) + `DREPanel` montado nas duas gerações.
- **Cobranças:** `src/components/collections/*` (8 componentes) alcançáveis por `CollectionsV2`; régua
  automática em `collection_templates`/`AutoRuleDialog`; crons `receivable-reminders-daily` (11:00 UTC) e
  `balance-reminders-daily` (11:30 UTC) ativos.
- **Reconciliação com o banco de produção:** os 17 jobs de cron estão ativos e correspondem a Edge Functions
  existentes no repositório — não encontrei cron órfão apontando para função removida.

---

*Módulo 3 auditado. 3 achados (`MF-AUD-050`, `MF-AUD-052` próprios; `MF-AUD-051` cruzado).*
