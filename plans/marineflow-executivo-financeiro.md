# MarineFlow — Executivo Financeiro (plano piloto)

> 29/07/2026. Status: **PROPOSTA — aguardando 5 decisões do usuário.**
> Documento visual: https://claude.ai/code/artifact/36bfa3be-811e-4de3-9f14-06ae04708be7
> Base: pesquisa em ~80 fontes (10 frentes) + auditoria do estado real do sistema.

---

## 1. O diagnóstico que muda a prioridade

Depois de importar o extrato do C6 (1.810 transações de 1 ano), o banco mostra:

| Métrica | Valor |
|---|---|
| Saídas não conciliadas | **1.583** somando **R$ 926.040** |
| Entradas não conciliadas | 220 somando R$ 862.820 |
| Contas a pagar cadastradas no ERP | **5** |
| Descrições distintas nas pendentes | **437** (≈3,7 transações por descrição) |

**Leitura:** o financeiro do ERP não reflete a operação — quase todo o dinheiro que saiu no último
ano nunca virou despesa. Não é negligência: lançar 1.583 despesas à mão é inviável. E a repetição
alta (437 descrições para 1.583 saídas) é exatamente a condição em que classificação automática
compensa — ensinar uma vez resolve várias.

## 2. Auditoria: o que JÁ existe (não refazer)

- **21 tools financeiras no agente**, incluindo `create_receivable`, `create_payable`,
  `register_payment`, `get_delinquency_plan`, `list_overdue_receivables`, `get_period_summary`,
  + BI (`get_revenue_by_brand`, `get_margin_by_category`, `get_top_clients`).
  **Elas existem e nada as aciona automaticamente.**
- **Portão de aprovação funcionando**: `ai_operator_pending_actions` (24 registros; tools `risk:"high"`
  viram pendência em vez de executar).
- **36 `financial_categories`** + 10 `OPERATIONAL_EXPENSE_CATEGORIES` — quase não usadas
  (2 de 5 payables sem categoria).
- Motor de conciliação em 3 camadas + memória (`reconciliation_memory`), extrato automático 2x/dia,
  briefing 07:30, projeção de caixa 8 semanas, detecção de duplicidade em contas a pagar.

## 3. Síntese da pesquisa (~80 fontes)

1. **Autonomia governada > human-in-the-loop.** Aprovar cada decisão trava a automação na velocidade
   do revisor e piora com o volume. O padrão atual: política escrita, versionada e aplicada pelo
   sistema; humano "on the loop", não "in the loop".
2. **Dois eixos independentes: confiança e materialidade.** Faixas usuais: >85% auto, 70–85% revisão
   rápida, <70% pergunta. Cruzado com valor: acima do limite, sempre humano.
3. **Trilha registra DECISÕES, não só ações** (o que viu, o que decidiu, por quê).
4. **Prompt não é controle** — ~60% de sucesso em burlar guardas só textuais. Limite e permissão
   têm que viver em código/banco (como `is_admin_or_financial`).
5. **Correção humana é o combustível** do aprendizado (já aplicado na conciliação).

**Benchmarks:** touchless 25–33% média vs 80%+ topo; exceções 22% vs 9%; previsão de caixa +30–40%
de precisão com IA; DSO −10 a −30%; fechamento 55% mais rápido.

## 4. Os cinco módulos

| # | Módulo | O que faz |
|---|---|---|
| I | **Construtor de lançamentos** | Propõe a despesa/receita que falta para cada transação órfã (fornecedor, categoria, valor, data). Aprovação em lote. Ataca os R$ 926k. |
| II | **Classificador que aprende** | Sugere categoria com confiança; guarda a correção; aplica em descrições repetidas. |
| III | **Caixa de entrada do gestor** | Fila única de tudo que precisa do humano, com contexto e aprovar/corrigir/recusar. O portão já existe; falta a tela. |
| IV | **Vigilante** | Duplicidade, valor fora do padrão do fornecedor, fornecedor novo, recorrência que parou. Só reporta. |
| V | **Conselheiro** | Leitura do negócio no briefing (tendências, concentração, semana negativa), com recomendação separada da constatação. |

## 5. Governança proposta

| Ação | Quem decide |
|---|---|
| Classificar categoria de despesa existente | Sistema, acima de 85% de confiança |
| Criar lançamento abaixo do limite | Sistema propõe · humano aprova em lote |
| Criar lançamento acima do limite | Humano, item a item |
| Conciliar com certeza (Pix/documento + valor exato) | Sistema (como já é hoje) |
| Registrar pagamento, emitir cobrança, mexer em orçamento | Humano, sempre |
| Enviar mensagem a cliente | Humano, sempre (regra vigente) |

**Três travas inegociáveis:** (1) nada que movimenta dinheiro é automático — criar registro de
despesa é contabilidade, pagar é outra coisa; (2) o limite vive no banco, não no prompt;
(3) tudo reversível e rastreado (de qual transação nasceu, com que confiança, por qual critério).

## 6. Fases

1. **Caixa de entrada + construtor de lançamentos** (maior impacto: transforma os R$ 926k em financeiro).
2. **Classificador com aprendizado** (confiança + memória + lote por descrição).
3. **Vigilante** (anomalias no briefing).
4. **Conselheiro** (leitura do negócio + previsão que aprende o comportamento de pagamento).

## 7. Decisões pendentes

1. **Limite de valor** para proposta em lote (sugestão: R$ 500).
2. **Tratamento do passado**: 90 dias na fila normal + mutirão para o resto (sugestão), ou só do mês corrente.
3. **Categorias**: usar as 36 existentes (sugestão) ou desenhar plano de contas novo.
4. **Sócio/pró-labore/transferências entre contas**: categoria própria não-operacional — *preciso dos
   nomes que costumam aparecer*.
5. **Despesa sensível** (salário, retirada, jurídico): existe caso que não pode aparecer para todos?
