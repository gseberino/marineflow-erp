# Dados financeiros, Open Finance e Pluggy — auditoria e roteiro

> 06/08/2026. Nasceu da observação de que compras no cartão não trazem remetente. A
> apuração mostrou que o problema é maior e de outra natureza: **tratamos cartão com o
> modelo de dados de transferência bancária**, e ignoramos metade do que o provedor manda.

## 1. O que medimos (2.141 transações reais)

| origem / tipo | qtd | nome | documento | merchant | meio | E2E do Pix | parcela |
|---|---:|---:|---:|---:|---:|---:|---:|
| conta / entrada | 148 | 88% | 83% | 58% | 86% | **0%** | — |
| conta / saída | 879 | 79% | 56% | 42% | 84% | **0%** | — |
| cartão / entrada | 135 | **7%** | 0% | 0% | 81% | 0% | — |
| cartão / saída | 979 | 95% | **4%** | **5%** | **0%** | 0% | 19% |

Três leituras:

1. **Cartão não tem contraparte porque compra em loja não é transferência.** Não existe
   `payer`/`receiver` numa compra — existe *estabelecimento*. Quem identifica ali é o
   `merchant` (enriquecimento) e o **MCC**, e nós capturamos merchant em 5% e MCC em 0%.
2. **`pix_end_to_end_id` é 0% em 2.141 linhas.** O motor de conciliação tem uma "camada de
   certeza" inteira construída sobre ele (`scoreCandidate`, tier `certain`, `autoApply`).
   **É código morto em produção** — a conciliação nunca teve seu sinal mais forte.
3. **`payment_method` é 0% no cartão** e 84% na conta. Coerente com o modelo, mas a tela
   trata as duas origens igual e mostra campo vazio como se fosse falha.

## 2. O que o provedor manda e nós jogamos fora

Declaramos no tipo e **nunca lemos**:

| campo | o que é | o que perdemos |
|---|---|---|
| `status` | PENDING vs POSTED | transação pendente muda de valor ou some; conciliamos sobre areia |
| `creditCardMetadata.cardNumber` | 4 últimos dígitos | com 2+ cartões, é o que separa um do outro |
| `merchant.category` | categoria do estabelecimento | classificamos do zero o que já vem classificado |
| `paymentData.receiverReferenceId` | id de referência do recebedor | pista de casamento |
| `paymentData.authenticationCode` | código de autenticação | prova do pagamento |

Nem declaramos, e existe:

| campo | o que é | por que importa |
|---|---|---|
| **`category` / `categoryId`** | categorização própria da Pluggy | é o produto de enriquecimento deles; construímos um classificador inteiro sem usá-lo |
| **`creditCardMetadata.payeeMCC`** | Merchant Category Code (ISO 18245) | **chave universal** de tipo de estabelecimento — resolve "MP *GTEKENERGIASU" sem IA |
| `bills` / `billId` | fatura do cartão | fecha a conta: soma das compras = valor da fatura |
| `accountId` | conta de origem | temos `bank_connection_id`, não a conta |

## 3. Nível de confiança do que existe hoje

| peça | qualidade | observação |
|---|---|---|
| `matching.ts` (pontuação em camadas) | **alta** | desenho correto, testado, com penalidade por documento divergente |
| camada de certeza por Pix | **inerte** | boa, e nunca dispara: o dado não chega |
| `proposals.ts` (regras + memória) | **alta** | corrigida nesta semana (âncora de nome, memória por estabelecimento) |
| `installments.ts` | **alta** | corrigido o centavo que dividia a compra em duas |
| `pluggy.ts` (mapeamento) | **média** | lê ~60% do que o provedor manda; sem MCC, sem categoria, sem status |
| Deduplicação (`bank_ref_id`) | **alta** | índice único por (bank_ref_id, source_type) |
| Tratamento de cartão | **baixa** | modelo de transferência aplicado a compra; sem fatura, sem MCC |
| Trilha de auditoria | **média** | `dismissed_*` e `decided_*` existem; falta log de conciliação |

---

# ROTEIRO

## FASE A — Parar de jogar dado fora (base de tudo)

**A1. Capturar o que já chega.** Migration com `pluggy_category`, `payee_mcc`,
`card_last_digits`, `tx_status`, `merchant_category`, `authentication_code`,
`receiver_reference_id`. Mapear em `pluggy.ts`. Sem isso, toda fase seguinte trabalha
cega.

**A2. Backfill.** Reprocessar as 2.141 pelo endpoint de transações, preenchendo só colunas
nulas (o `backfill` já existe em `banking-sync`; estender aos campos novos).

**A3. Diagnóstico do E2E do Pix.** Gravar o `paymentData` cru de 20 transações Pix numa
tabela de amostra e descobrir ONDE o provedor põe o EndToEndId. Hipóteses: outro campo,
não vem nesta instituição, ou `paymentMethod` não é literalmente "PIX". **Enquanto não se
sabe, a camada de certeza continua morta** — e ela é o maior ganho de automação disponível.

**A4. Status PENDING.** Não propor lançamento de transação pendente; reprocessar quando
virar POSTED. Hoje uma compra pendente que muda de valor deixa o lançamento errado.

## FASE B — Cartão como cartão

**B1. MCC → categoria.** Tabela `mcc_categorias` (ISO 18245 → plano de contas). 5812
restaurante → Alimentação; 5541 posto → Combustível; 5251 ferragens → Ferramentas. É
determinístico, auditável e mais barato que IA.

**B2. Precedência revista.** regra do gestor > MCC > memória por estabelecimento >
categoria da Pluggy > regra de texto > IA. Hoje a IA entra onde o MCC resolveria.

**B3. Fatura como entidade.** Importar `bills`: fechamento, vencimento, valor. Conferir
soma das compras = valor da fatura. Fecha o ciclo que hoje é conferido no olho.

**B4. Cartão por número.** `card_last_digits` separa cartões e permite custo por cartão.

**B5. UI honesta por origem.** Compra em loja não tem remetente — a tela deve mostrar
estabelecimento + MCC, e não um campo "De:" vazio que parece defeito. **Resolve a
observação que originou esta auditoria.**

## FASE C — Conciliação com o sinal forte de volta

**C1. Religar a camada de certeza** com o resultado de A3.
**C2. Casar por `authenticationCode`/`receiverReferenceId`** quando não houver E2E.
**C3. Memória por assinatura** já existe (`reconciliation_memory`); medir acerto e expor.

## FASE D — Robustez da integração

**D1. Webhook em vez de polling.** `pluggy-webhook` existe e está subutilizada: reagir a
`transactions/created` e `item/updated` em vez de varrer.
**D2. Reconexão (MFA/consentimento).** Consentimento de Open Finance expira em 12 meses;
hoje a falha é silenciosa. Alerta antes de vencer.
**D3. Idempotência sob retry.** O índice único protege; falta tratar o erro sem abortar o
lote inteiro.
**D4. Reconciliação de saldo.** `balance_after` × soma das transações: divergência denuncia
transação faltando — o controle que os ERPs chamam de *proof of completeness*.

## FASE E — Fechamento e auditoria (a F5 que ficou pendente)

**E1. `reconciliation_log`**: linha, ação, autor, regra, valores antes/depois.
**E2. Fechar o mês**: trava conciliação e ignorar no período; reabrir exige justificativa.
**E3. Relatório de conformidade**: % conciliado, dias da mais antiga, exceções abertas.

## FASE F — Correções pendentes já identificadas

**F1.** 41 fornecedores com nome fantasia de uma palavra (cidade/apelido) — o matcher já
não cai mais nisso, mas o cadastro segue sujo.
**F2.** Categoria de farmácia (regra FARMA aguarda sua decisão).
**F3.** `useUnignoreBankTransaction` não desfaz o efeito — deve chamar `undismiss`.

---

## Ordem recomendada

**A → B → C → D → E → F.** A é pré-requisito de tudo. B tem o maior retorno imediato
(cartão é 52% do volume). C depende do diagnóstico A3. D é robustez. E é governança.

## Fontes

- [Pluggy — Transaction](https://docs.pluggy.ai/docs/transactions)
- [Pluggy — Payment data coverage](https://docs.pluggy.ai/docs/paymentdata-coverage)
- [Pluggy — Transaction Enrichment](https://docs.pluggy.ai/docs/enrich-api)
- [Pluggy — Credit Card Installments](https://docs.pluggy.ai/docs/credit-card-installments)
- [Open Finance Brasil — API Cartão de Crédito v2.4.0 (PRD)](https://openfinancebrasil.atlassian.net/wiki/spaces/OF/pages/1739325456/Documento+de+Requisito+do+Produto+PRD+-+API+de+Cart+o+de+Cr+dito+v2.4.0)
- [Open Finance Brasil — Informações Gerais Cartão de Crédito](https://openfinancebrasil.atlassian.net/wiki/spaces/OF/pages/310607893)
- [Odoo — Bank reconciliation](https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/reconciliation.html)
