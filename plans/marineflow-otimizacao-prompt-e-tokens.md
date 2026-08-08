# MarineFlow — Otimização de Prompt, Ferramentas e Consumo de Tokens

**Data:** 08/08/2026
**Origem:** auditoria pedida após o dono observar o tamanho do primeiro prompt no painel do OpenRouter.
**Prioridade definida pelo dono:** *aderência antes de custo* — o agente obedecer o prompt elimina retrabalho, e retrabalho é o que mais gasta token.

---

## 1. A conta, medida (não estimada)

Toda chamada ao modelo carrega **68.941 tokens fixos** antes de qualquer mensagem do usuário.
Esse número é medido: aparece constante no campo `cache_read_tokens` de `ai_operator_messages`.

| Bloco | Tamanho | Peso |
|---|---|---|
| Definições de ferramentas (188 tools) | 126.084 chars ≈ **48.300 tokens** | 70% |
| System prompt (bloco estável, 37 seções) | 54.075 chars ≈ **20.700 tokens** | 30% |
| Bloco volátil (data, cargo, rota, notas) | 1.371 chars ≈ 380 tokens | — |
| Histórico podado + mensagem nova | ~6.000–9.000 tokens | variável |

Calibração: 2,61 chars/token, derivada do `cache_read` real de produção contra os bytes medidos do payload.

### 1.1 A curva — o prompt quintuplicou em 4 semanas

Média de `tokens_in` por chamada:

```
10/07 ── 15.794
15/07 ── 18.031
19/07 ── 19.890
22/07 ── 46.269   ← salto
24/07 ── 62.230
03/08 ── 68.162
06/08 ── 81.897
07/08 ── 74.418
```

Não houve decisão de arquitetura por trás disso. Cada entrega (fiscal, banking, survey, BOM,
conciliação) somou ferramentas ao pacote **global** e o system prompt ganhou uma seção nova.
O crescimento é aditivo e ninguém é dono da remoção.

### 1.2 135 das 188 ferramentas nunca foram usadas

Cruzamento de `ai_operator_audit` (60 dias, 634 chamadas de tool) com `allTools`:

- **53 tools usadas** → ~15.600 tokens
- **135 tools nunca usadas** → **~32.600 tokens de peso morto por chamada** (68% do bloco)
- 25 tools respondem por **94%** de todas as chamadas reais

Peso morto por domínio:

| Domínio | Tools sem uso | Tokens |
|---|---:|---:|
| outros (cadastros, listagens de CRM, `size_dc_cable`) | 27 | ~6.655 |
| comunicação | 13 | ~3.048 |
| memória & aprendizado | 13 | ~3.044 |
| OS/orçamento (campo, check-in/out, despesas, horas) | 11 | ~2.954 |
| financeiro/BI | 15 | ~2.900 |
| agenda & tarefas | 12 | ~2.862 |
| roteiro de execução | 11 | ~2.646 |
| cotação & compras | 9 | ~2.646 |
| levantamento (survey) | 6 | ~1.624 |
| bancário | 8 | ~1.515 |
| BOM / kit | 5 | ~1.374 |
| fiscal | 5 | ~1.372 |

> **"Nunca usada" ≠ "inútil".** Boa parte é funcionalidade recente que ainda não teve ocasião
> (fiscal, banking, survey). A correção certa é **particionar de forma estável**, não deletar.

### 1.3 O cache funciona, mas vaza ~20% das chamadas

Em 07/08: 24 chamadas ao modelo, **6 sem cache algum**. Cada miss paga ~69k tokens a preço
cheio mais a gravação do cache. Os misses coincidem com intervalos > 5 minutos entre turnos
(09:49 → 10:28 → 10:43 → 11:16 → 12:22) — é o TTL padrão de 5 minutos do
`cache_control: { type: "ephemeral" }` expirando entre as mensagens do dono.

**Custo por chamada** (tabela Anthropic p/ Sonnet 5: $3/M entrada, $15/M saída, leitura de
cache 0,1×, gravação 1,25×):

| Situação | Custo |
|---|---|
| Com cache hit | ~US$ 0,040 |
| Com cache miss | ~US$ 0,26 — **6,5× mais caro** |

Estimativa de fatura no ritmo atual: **US$ 60–100/mês**, subindo junto com o número de tools.
(Os números de *token* são medidos; os de *dólar* são estimados — falta confrontar com o
painel do OpenRouter, que pode aplicar markup.)

---

## 2. O problema de aderência (a prioridade escolhida)

Rastreamento do pedido real do dono ("orçamento para o Rodrigo", 07/08) em `ai_operator_messages`.

### 2.1 O agente ignorou a macro que o próprio prompt manda usar

O system prompt tem **três blocos** insistindo em `create_quote_from_items`
("UMA chamada por orçamento", "ATALHO PODEROSO", "DEPOIS DA MACRO, PARE").
No pedido do Rodrigo o agente fez o caminho manual:
`create_service_order` + `add_service_to_order` ×2 + `add_material_to_order` + `get_client_history`
— **5 chamadas de LLM só no primeiro turno**, ~370k tokens.

Em 60 dias: `create_quote_from_items` foi usada **4 vezes**; `add_service_to_order`, **29**.

**Causa provável:** a mesma seção que manda usar a macro lista, logo abaixo, 10 passos manuais
que mandam o contrário (`search_products_batch` → `create_service_order` → `add_item`).
Duas instruções opostas; o modelo segue a mais detalhada.

### 2.2 Violação direta de uma regra fiscal do próprio prompt

O conector da Starlink (item **físico**) entrou por `add_material_to_order`.
`prompt.ts:176` diz textualmente: *"NÃO use add_material_to_order para item físico — beco
fiscal, some do estoque e do BI"*.

Não é caso isolado: `add_material_to_order` (44 usos) e `remove_service_order_item` (44 usos)
empatados em 60 dias — o par sugere retrabalho sistemático de mover item da lista errada.

### 2.3 Retrabalho por lacuna de ferramenta

`edit_service_order_item` **não altera nome**. O agente teve que remover e recriar o item, e
ainda assim dois retornos vieram `"Item não encontrado neste orçamento/OS"`.
Cada round-trip desses custa ~75k tokens de entrada.

### 2.4 Redundâncias e contradições no prompt

Seções mais pesadas (bloco estável, 37 seções, ~20.700 tokens):

| Seção | Tokens |
|---|---:|
| FLUXO DE CRIAÇÃO DE ORÇAMENTO | 1.523 |
| PEDIDO GRANDE (lista de itens) | 1.480 |
| TÉCNICO EM CAMPO E AGENDA | 1.466 |
| PLANO ANTES DE EXECUTAR | 1.318 |
| COTAÇÃO A FORNECEDORES | 1.315 |
| cabeçalho (persona + diretrizes) | 1.134 |
| EXEMPLOS DE MENSAGEM | 938 |
| APRENDIZADO — CONSTITUIÇÃO VIVA | 913 |

Duplicações identificadas:

1. **Macro de orçamento explicada 3×** — PEDIDO GRANDE + PLANO ANTES DE EXECUTAR (3 parágrafos
   inteiros repetidos) + FLUXO DE CRIAÇÃO. ~4.300 tokens, com **caminhos contraditórios**.
2. **DESAMBIGUAÇÃO — FLUXO** (321 tok) duplica o passo 1 de FLUXO DE CRIAÇÃO **e** já está
   implementado deterministicamente no código (`AUTO_DISAMBIG`, `agent.ts:81`).
3. **ROTEIRO: EXECUTAR PASSO A PASSO** (461 tok) duplica a subseção "ROTEIRO DE EXECUÇÃO"
   dentro de TÉCNICO EM CAMPO E AGENDA.
4. **O QUE FALTA COMPRAR** (294 tok) duplica quase textualmente o passo 0 de COTAÇÃO A FORNECEDORES.
5. **AGENDA & TAREFAS** (741 tok) contém estoque, compras, caixa de entrada e histórico — não é
   agenda; é catálogo de tools que as próprias `description` já fornecem.
6. **O QUE MAIS VOCÊ SABE FAZER** (266 tok) é lista de nomes de tools que já têm descrição própria.
7. **"NÃO FINJA"** aparece no cabeçalho e de novo no bloco WhatsApp.

### 2.5 Armadilha a não acionar

Existe um roteador de intenção pronto (`ai-agent/index.ts:14`) atrás da flag `ai_intent_router`.
A chave **não existe** em `app_settings` — está desligada.

**Não ligar.** Ele filtra as tools conforme a mensagem, e as tools renderizam *antes* do system
no prefixo cacheado. Conjunto variável de tools = cache miss em 100% das chamadas.
Hoje uma chamada com cache custa ~US$ 0,040; com o roteador e prefixo de 30k sem cache, ~US$ 0,090.
**Ligar o roteador dobraria o custo.**

---

## 3. Plano em fases

Ordem recomendada de execução: **0 → 3 → 1 → 2 → 5 → 4**
(A Fase 3 vem cedo por ser uma linha, reversível, e dar ganho imediato enquanto as outras são trabalhadas.)

### Fase 0 — Instrumentação (pré-requisito)

Hoje `ai_operator_messages` guarda `tokens_in`/`tokens_out`/`cache_read_tokens`, mas ninguém
traduz isso em dinheiro. Sem isso, nenhuma fase seguinte é mensurável.

- Criar view `v_ai_custo_diario`: custo por dia, canal e sessão, com taxa de cache hit.
- Aplicar `security_invoker = on` + `REVOKE` de `anon` na mesma migration.

| | |
|---|---|
| **Ganho de token** | 0 (habilita medir tudo) |
| **Risco** | Nenhum — leitura apenas |

### Fase 1 — Resolver a contradição do orçamento (ADERÊNCIA)

O item que o dono priorizou. Três frentes:

**1a. Fundir as três seções de orçamento em uma.**
Uma seção "MONTAR ORÇAMENTO" com `create_quote_from_items` como caminho **único**, e o passo a
passo manual explicitamente rotulado como fallback para dois casos nomeados (editar OS que já
existe; item que a macro devolveu ambíguo). Hoje são 4.300 tokens ensinando dois caminhos opostos.

**1b. Mover a regra do item físico para o código.**
A regra existe no prompt mas está enterrada no meio de "EDITAR/REMOVER item". O correto é
`add_material_to_order` recusar (ou avisar sobre) item que aparenta ser físico — o que pode ser
verificado em código não deveria depender de o modelo lembrar de uma linha no meio de 20.700 tokens.

**1c. Fechar a lacuna de `edit_service_order_item`.**
Adicionar parâmetro `description` para alterar o nome do item. Elimina o ciclo remover+recriar
que hoje aparece 44 vezes em 60 dias.

| | |
|---|---|
| **Ganho de token** | ~2.500–3.500/chamada, **e** 3–5 chamadas de LLM a menos por orçamento |
| **Risco** | MÉDIO — muda comportamento; exige teste antes/depois em caso real |

### Fase 2 — Deduplicação do resto do prompt

Aplicar os cortes 2–7 da seção 2.4. Reduzir EXEMPLOS DE MENSAGEM de 5 pares para 2
(cobrança e cotação — os únicos com uso real).

> **Regra de contenção:** cruft ≠ comprimento. **Não** cortar contexto que só a casa sabe —
> valores da empresa, ISS, portão de comunicação, regras fiscais, permissões por cargo.
> O alvo é instrução duplicada e contraditória, não volume.

| | |
|---|---|
| **Ganho de token** | ~2.000–2.500/chamada |
| **Risco** | BAIXO-MÉDIO — cada corte testado individualmente |

**Alvo combinado F1+F2:** system 20.700 → ~14.000–15.000 tokens (−30%).

### Fase 3 — TTL de 1 hora no cache

Confirmado suportado pelo OpenRouter. Mudança de uma linha em `prompt.ts`:

```ts
cache_control: { type: "ephemeral", ttl: "1h" }
```

Conta com os dados de 07/08:

| | Hoje (5 min) | Com 1h |
|---|---|---|
| Misses/dia | 6 | ~2 |
| Custo de gravação | 1,25× base | 2,0× base |
| Custo diário dos misses | ~US$ 1,55 | ~US$ 0,91 |

**Ressalva:** a gravação de 1h custa 2× em vez de 1,25×, então só compensa com ≥3 leituras por
gravação. Nos dados atuais são 4 (24 chamadas / 6 misses) — compensa. Em dia de uso esparso
(2–3 chamadas isoladas) pioraria. **Aplicar e medir com a view da Fase 0.**

| | |
|---|---|
| **Ganho** | ~25% da conta diária |
| **Risco** | BAIXO — reversível em uma linha |

### Fase 4 — Particionamento estável das ferramentas

A parte mais pesada (48.300 tokens) e a mais delicada.

> **Regra inviolável:** a partição precisa ser **estável** para um dado canal/cargo, nunca variar
> por mensagem. Partição variável = o erro do roteador de intenção = cache miss sempre.

O mecanismo já existe: 83 das 188 tools têm campo `roles`, e o filtro roda em
`ai-agent/index.ts:437`. Faltam duas coisas:

- 105 tools **sem** restrição de cargo (admin recebe as 188);
- nenhuma dimensão de **canal**.

Proposta: somar `channels: ["whatsapp"] | ["panel"] | ambos`. O WhatsApp (conversa rápida,
`effort: low`, orçamento de 45s) não precisa de fiscal (1.372 tok), BOM/kit (1.374), roteiro de
execução (2.646), survey (1.624) nem bancário (1.515) — ~8.500 tokens só nesses cinco domínios.

**Trade-off a declarar:** hoje o bloco estável é byte-idêntico entre canais *de propósito*
(comentário em `prompt.ts:510`) para compartilhar um único cache. Particionar tools por canal cria
**dois** caches em vez de um. Cada um se paga com 3 leituras — aceitável no volume atual, mas é
uma escolha consciente, não um efeito colateral.

| | |
|---|---|
| **Ganho** | 8.000–12.000 tokens no canal WhatsApp |
| **Risco** | ALTO — cortar tool necessária faz o agente dizer "não consigo". Mitigar: só cortar o que tem 0 uso em 60 dias **e** não pertence a fluxo recém-lançado; manter modo completo acionável |

### Fase 5 — Enxugar cada schema de ferramenta

Independente de quantas tools existem: a descrição média tem 244 chars, e várias passam de 500
(`send_supplier_quote_request` 649, `log_service_order_hours` 582, `create_quote_from_items` 531).
Parte carrega instrução de comportamento que já está no system prompt — duplicação cruzada
system ↔ tools.

> **Cuidado na direção oposta:** sub-descrição é o erro mais comum em definição de ferramenta.
> O alvo é remover *steering* e exemplos das descrições, **não** o contrato (parâmetros, limites,
> o que a tool não retorna). Descrição prescritiva de *quando chamar* deve ficar.

| | |
|---|---|
| **Ganho** | 15–20% do bloco de tools sem remover funcionalidade |
| **Risco** | BAIXO-MÉDIO |

---

## 4. Projeção consolidada

| | Hoje | Depois (painel) | Depois (WhatsApp) |
|---|---:|---:|---:|
| Tools | 48.300 | ~34.000 | ~24.000 |
| System | 20.700 | ~14.500 | ~14.500 |
| **Prefixo total** | **68.941** | **~48.500** | **~38.500** |

Redução de custo projetada: **45% a 55%**, com aderência melhor (menos chamadas de LLM por tarefa
concluída — o ganho que não aparece na conta de tokens por chamada, mas aparece na fatura).

---

## 5. O que falta para começar

1. **Custo real no painel do OpenRouter** (7 e 30 dias, `anthropic/claude-sonnet-5`) — calibra a
   estimativa em dólar e revela markup.
2. Autorização para cada fase, uma por vez.

## 6. Verificações feitas

- Leitura de `prompt.ts` (545 linhas), `agent.ts`, `anthropic.ts`, `models.ts`,
  `context-pruning.ts`, `ai-agent/index.ts`, `tools/index.ts`
- Medição do payload via Deno importando `allTools` e `buildSystemBlocks`
- Calibração chars/token contra `cache_read_tokens` de produção
- 5 consultas SQL em `ai_operator_messages` e `ai_operator_audit` (projeto `okurngvcodmljjicopdp`)
- Pricing confirmado na referência da API Claude
- Suporte a `ttl: "1h"` confirmado na documentação do OpenRouter

## 7. Limitações desta auditoria

- Custo em dólar é estimativa (tabela Anthropic; passa por OpenRouter). Tokens são medidos.
- A divisão 70/30 tools↔system tem margem de ~5% (o total de 68.941 é exato).
- Não foi apurado **por que** cada uma das 135 tools não é usada — se por ser nova, por não estar
  ensinada ao agente, ou por o modelo não a achar no meio de 188 opções. São causas distintas com
  correções distintas; a Fase 4 depende dessa distinção.
