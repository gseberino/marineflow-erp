# Conciliação bancária — redesenho definitivo

> Escrito em 05/08/2026, depois de o gestor apontar que a Caixa de entrada ficou melhor
> que a Conciliação e de descobrirmos ~380 transações em estado "ignorada" sem tela que
> as mostre nem como desfazer.

## 1. O que apuramos sobre as "ignoradas"

Não foi a IA agindo por conta própria. São 380 transações (R$ 370 mil) em quatro origens,
**todas autorizadas** — mas nenhuma delas visível depois do fato:

| origem | qtd | valor | quando foi autorizado |
|---|---:|---:|---|
| Duplicata OFX × sincronização | 136 | R$ 163.020,03 | "autorizo a aplicação" |
| Pagamento de fatura de cartão | 114 | R$ 99.890,81 | "eu autorizo" |
| Transferência entre contas próprias | 34 | R$ 94.485,92 | aprovações na fila + migration |
| Mecânica do cartão (Pix no Crédito, ajuste, estorno) | 22 | R$ 7.092,55 | "eu autorizo" |
| **Parcelas de compra parcelada** | **~70** | **~R$ 15 mil** | **efeito do meu código, sem aviso** |

**O defeito real não é o que foi ignorado — é que ignorar não deixa rastro navegável.**
As últimas ~70 são consequência direta da funcionalidade de parcelamento: aprovar uma
compra em 10x marca as outras 9 pernas como resolvidas. Isso é contabilmente certo e
aconteceu **em silêncio**. O gestor não tinha como saber, conferir nem desfazer.

Um sistema que tira 380 linhas de vista sem um livro do porquê não é confiável, por mais
correto que esteja cada caso.

## 2. O que a pesquisa diz (e o que isso muda aqui)

| princípio | fonte | o que falta em nós |
|---|---|---|
| Nada some: a linha fica numa **conta transitória** até ser resolvida | Odoo | "ignorada" é sumiço, não estado |
| Editar algo conciliado **limpa a conciliação** e força revisão | NetSuite | não temos desfazer nenhum |
| Trilha imutável: regra aplicada, quem, quando, aprovação | NetSuite / zone&co | temos `dismissed_reason` solto, sem autor nem data |
| **Um-para-muitos E muitos-para-um** | Odoo / Xero | fizemos N contas ↔ 1 transação; falta 1 conta ↔ N transações |
| **Tolerância + baixa da diferença** em conta designada | Xero / NetSuite | não existe; por isso taxa bancária trava a conciliação |
| Humano só vê **exceção**; o resto o sistema resolve | zone&co | a Conciliação mostra tudo igual, sem hierarquia |
| Regras de casamento **do negócio**, não genéricas | NetSuite | temos, e são boas — mas só na Caixa de entrada |

## 3. Decisão de arquitetura

O gestor já decidiu, em 30/07, **manter Conciliação e Caixa de entrada como abas
separadas** — e a decisão continua certa: são dois raciocínios diferentes (dinheiro que
sai e já é despesa vs. dinheiro que entra e precisa achar seu dono).

O que muda: **a Conciliação herda a mecânica da Caixa de entrada**, e as duas passam a
compartilhar o mesmo motor de estado. Não é fundir telas — é parar de manter duas
qualidades diferentes de ferramenta para o mesmo trabalho.

### Estado único da linha bancária

Toda transação passa a ter um estado explícito, com autor e data:

```
pendente ──► conciliada   (virou lançamento ou foi ligada a um existente)
    │
    └──────► ignorada     (duplicata, mecânica de cartão, transferência, parcela)
                 │
                 └──► REVERSÍVEL: volta a pendente, desfazendo o que criou
```

Regra que sustenta tudo: **toda saída de "pendente" é reversível e diz quem, quando e por
quê.** É o que separa "o sistema resolveu" de "o sistema escondeu".

## 4. Fases

### F1 — Livro das ignoradas + desfazer (URGENTE, resolve a desconfiança)
- Coluna `dismissed_at`, `dismissed_by`, `dismissed_kind` (enum: duplicata,
  fatura_cartao, transferencia, parcela, manual).
- Aba/filtro **"Ignoradas (380)"** na Conciliação, agrupada por motivo, com valor e período.
- Botão **Desfazer** por linha e por grupo: volta a pendente e reverte o efeito
  (apaga lançamento criado, reabre a proposta).
- Ao aprovar compra parcelada, a tela **diz** quantas pernas saíram junto.

### F2 — Conciliação com a mecânica da Caixa de entrada
- Agrupamento por favorecido/cliente, ordenação escolhível, seleção múltipla,
  aprovação otimista, categoria editável na linha — tudo já existe em
  `finance-inbox-grouping.ts` e `FinanceReviewInbox.tsx`, e passa a ser componente
  compartilhado em vez de código gêmeo.
- Hierarquia por exceção: **Certas** (aplicar sozinho) · **Prováveis** (1 clique) ·
  **Sem candidato** (decidir). Hoje tudo aparece com o mesmo peso.

### F3 — Conciliação parcial e tolerância
- Editar valor/data antes de confirmar.
- Tolerância configurável (padrão: R$ 5,00 ou 0,5%) com **baixa automática da diferença**
  em categoria designada (Tarifas bancárias) — resolve taxa de Pix/TED, que hoje trava.
- Um recebimento que quita **parte** de uma conta deixa o saldo aberto, em vez de exigir
  o valor exato.

### F4 — Muitos-para-um (o inverso do que já fizemos)
- Uma OS paga em várias transações (sinal + parcelas): marcar a conta e ir somando
  transações até fechar.

### F5 — Trilha e fechamento
- `reconciliation_log`: linha, ação, autor, regra aplicada, valores antes/depois.
- Fechar o mês trava conciliação e ignorar no período; reabrir exige justificativa.

## 5. O que NÃO fazer

- **Não fundir as duas abas.** Decisão do gestor, e boa.
- **Não deixar a IA ignorar transação.** Classificar é barato, ignorar é sumiço:
  ignorar segue sendo ato humano ou migration autorizada, nunca inferência.
- **Não inventar tolerância alta.** Acima do teto, a diferença vira decisão explícita.

## Fontes

- [Odoo 19 — Bank reconciliation](https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/reconciliation.html)
- [NetSuite auto-match rules & workflows](https://www.houseblend.io/articles/netsuite-bank-reconciliation-auto-match-rules)
- [Zone & Co — ERP bank reconciliation automation](https://www.zoneandco.com/articles/finance-teams-guide-to-erp-bank-reconciliation-automation-challenges-best-practices-and-proven-benefits)
- [Numeric — Transaction reconciliation guide](https://www.numeric.io/blog/transaction-reconciliation-guide)
- [Xero — Reconcile bank transactions](https://www.xero.com/us/accounting-software/reconcile-bank-transactions/)
- [BankRecon — 8 best practices](https://bankrecon.io/blog/bank-reconciliation-best-practices)
