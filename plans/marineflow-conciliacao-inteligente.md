# MarineFlow — Conciliação Inteligente (diagnóstico + motor em 3 camadas)

> 27/07/2026. Status: **PROPOSTA — aguardando 6 decisões do usuário.**
> Documento visual: https://claude.ai/code/artifact/41d149af-132d-4983-b410-6ba1d4128b72
> Origem: usuário importou extrato real, havia uma entrada compatível com o sinal de um
> orçamento e a conciliação não sugeriu nada.

---

## 1. Causa raiz (confirmada no código e no banco)

`src/components/BankReconciliation.tsx` → `getFilteredSOs()`:
```ts
const list = isCredit ? sos.filter(so => ['completed','invoiced'].includes(so.status)) : sos;
```
Para **crédito** (dinheiro entrando) só entram OS `completed`/`invoiced`. Orçamento aguardando
sinal é `draft`; OS ativa é `open`/`scheduled`/`in_progress`/`awaiting_parts`. Nenhum é candidato.

Contagem real em produção (27/07): `draft` 31, `cancelled` 15, `invoiced` 6, `approved` 4,
`completed` 4, `open` 3, `scheduled` 3, `in_progress` 3, `awaiting_parts` 1 → **a tela vê 10 de 70**.

**Orçamento e OS são a MESMA tabela** (`service_orders`), separados por `status` + prefixo
`ORÇ-`/`OS-` (a RPC `register_deposit_and_convert` faz a troca ao registrar o sinal).

## 2. O dado que existe e não é usado

- Setting `quote_deposit_percentage` (hoje 30).
- `src/lib/quote-deposit.ts` — fonte única do cálculo do sinal (`computeDeposit`,
  `depositAmountFromPcts`), já aplicando `discountRatio`. Criada para corrigir divergência
  PDF × botão "Receber sinal".
- Condições de pagamento com parcela de sinal (`tipo='aprovacao'` ou `days_after_approval=0`).

→ Dá para calcular o **sinal esperado de cada um dos 31 orçamentos** e comparar com o extrato.
Hoje a conciliação só compara com `receivables`/`payables` **já lançados** — e o sinal só vira
receivable *depois* do registro manual. Ciclo que se morde.

## 3. Inventário de lacunas (módulo relido: 2.620 linhas)

| Lacuna | Hoje | Severidade |
|---|---|---|
| Orçamentos aguardando sinal | fora dos candidatos | Crítico |
| Saldo de OS em andamento | fora dos candidatos | Crítico |
| Conciliação automática | não existe (100% manual, 1 a 1) | Crítico |
| `pix_end_to_end_id` | coluna criada 27/07, não usada p/ casar | Alto |
| `counterparty_document` | extraído, não comparado com `clients` | Alto |
| Agente IA | 139 tools, **nenhuma** de conciliação | Alto |
| Aprendizado | zero memória de conciliações anteriores | Médio |

Sugestões atuais (`getSuggestions`): só receivables/payables abertos, tolerância fixa
**±5% valor e ±7 dias**, sem score e sem ordenação. Não usa nome do cliente nem documento.
Backend: **nenhuma** conciliação (só `fiscal-reconcile`, que é outra coisa).

## 4. Síntese da pesquisa de mercado (pesquisa até saturação)

**Arquitetura consensual: motor em camadas** — determinístico → heurístico pontuado → IA no resíduo.

Benchmarks de auto-match: manual 60-75% · só regras 50-70% · regras+heurística 80-90% ·
com IA 90-98%. (Nibo publica 85% de acerto na categorização automática.)

Princípios a incorporar:
- **Score com pesos**, não filtro binário. Referências de mercado: Amount 40 / Payee 30 /
  Date 20 / Description 10; outra: embedding 50 / amount 35 / currency 10 / date 5.
- **Tolerância dupla** (% e valor absoluto), vencendo a mais conservadora — padrão Oracle.
  5% de R$ 50k = R$ 2,5k de folga, inaceitável.
- **1-para-muitos** = subset sum; viável com 5-15 contas abertas por cliente, limitando por
  janela de valor.
- **Normalização de nome** antes de comparar (Jaro-Winkler favorece prefixo, bom p/ razão social).
- **Aprender com correção do usuário**: cada conciliação manual é exemplo rotulado
  (texto do extrato → cliente).
- **Explicabilidade + trilha de auditoria** obrigatórias para confiar no automático.
- Exceções nomeadas do mercado: valor divergente, título não encontrado, duplicidade,
  pagamento parcial, baixa já realizada, juros/multa (extrato > título), tarifa/desconto
  (extrato < título), pagamento agrupado.

## 5. Arquitetura proposta

**Camada 1 — Certeza (concilia sozinha):** `pix_end_to_end_id` ↔ cobrança emitida;
`counterparty_document` + valor exato ↔ conta em aberto.

**Camada 2 — Probabilidade (sugere ranqueado):** score ponderado sobre valor (tolerância dupla),
data, nome normalizado e histórico. **Candidatos corrigidos**: sinal esperado de orçamentos +
saldo de OS ativas + receivables + payables. Mostra % de confiança e razão em 1 frase.

**Camada 3 — Contexto (IA):** o resíduo vai ao agente, que tem o que nenhum motor de mercado tem:
conversas WhatsApp, histórico do cliente, orçamentos em negociação, memória. Sempre com aprovação.

**Entrada pela UI:** botão "Analisar com IA" por transação + "Conciliar tudo" em lote
(retorna "N conciliadas, M sugestões, K sem candidato").

**Onde mora:** edge function `banking-reconcile` + `_shared/banking/matching.ts` (puro, testável),
espelhando o padrão `_shared/fiscal`. Tools novas no agente: `listar_transacoes_pendentes`,
`sugerir_conciliacao`, `conciliar_transacao` (atrás do gate de aprovação).

## 6. Fases

1. **Candidatos corrigidos** (rápido) — remove o filtro, calcula sinal esperado via
   `quote-deposit.ts`, rotula ("Sinal do ORÇ-00042 — esperado R$ 4.500"). Resolve o caso relatado.
2. **Motor de score no backend** — `banking-reconcile` + matching puro com testes; camada 1
   automática, camada 2 sugerindo; usa Pix E2E e documento.
3. **IA como 3ª camada** — tools + botões + bloco no briefing 07:30.
4. **Memória e casos difíceis** — mapeamento texto→cliente aprendido, 1-para-muitos,
   parcial, juros/tarifa.

## 7. Segunda revisão (27/07, a pedido do usuário) — 3 correções

1. **CORREÇÃO DE NÚMERO (meu erro):** existe `quote_status` separado de `status`. Dos 31 `draft`,
   **25 são `rejected`** (R$ 511k em propostas perdidas — NÃO são candidatos), 3 `sent`, 2 `draft`
   e **1 `awaiting_deposit`** (R$ 20.000). O bug fica MAIS forte: há um status que significa
   literalmente "aguardando o sinal" e a conciliação não olha para ele.
2. **Trigger `on_quote_deposit_paid` já existe** (função `handle_quote_deposit_payment`): quando um
   receivable com `service_order_id` passa a `paid`/`partially_paid`, muda a SO de
   `quote_status='awaiting_deposit'` → `approved` + `converted_to_os_at=NOW()`.
   → **A conciliação NÃO precisa saber converter**; basta registrar o pagamento. Reduz escopo.
3. **Candidato que faltou: `collections`** (2 abertas, R$ 950). Tem régua automática
   (`auto_rule_enabled`, `rule_days_before/after`) e `standalone_amount` para cobranças avulsas
   sem receivable. Trigger `trg_sync_collection_from_receivable` já fecha a cobrança quando o
   receivable é pago.

Verificado e OK (sem problema): `payments.status` default `'confirmed'` (entra no fluxo de caixa e
no resumo do mês); `register_payment_and_update_balance` é atômica e checa role;
`cancelPaymentCascade` desfaz a conciliação ao cancelar pagamento.

## 8. Decisões — RESPONDIDAS pelo usuário em 27/07/2026

| # | Decisão | Resposta |
|---|---|---|
| 1 | Conciliação automática | **Só camada 1** (Pix E2E ou documento+valor exato). Resto sugere. |
| 2 | Tolerância | **2% limitado a R$ 50** (vence a mais conservadora); data **D+5 / D−2**. |
| 3 | Valor ≠ sinal esperado | **Sugerir mostrando a diferença**; usuário decide parcial vs negociado. Nunca aceitar em silêncio. |
| 4 | Juros / multa / tarifa | **Só apontar e sugerir categoria**; não lançar diferença automaticamente na v1. |
| 5 | Quando a IA age | **Botão + varredura diária** no briefing 07:30. Varredura só sugere. |
| 6 | Conversão do orçamento | **Sim, mas avisando antes**: a sugestão exibe "isto vai aprovar o ORÇ-XXXXX e convertê-lo em OS". |

→ Implementação liberada. Ordem: Fase 1 (candidatos) → Fase 2 (motor) → Fase 3 (IA) → Fase 4 (memória).
