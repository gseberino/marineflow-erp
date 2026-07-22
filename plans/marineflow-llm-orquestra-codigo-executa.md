# LLM orquestra, código executa — plano de eficiência do agente

> Objetivo do dono: "a IA só deve comandar, ou fazer pequenas chamadas com palavras-chave —
> o trabalho pesado deve estar em ferramentas do código e/ou no banco".
> Motivação medida: um pedido real (2 orçamentos, ~20 itens) gerou ~15 chamadas de LLM,
> estourou o teto de 150s da Edge Function (HTTP 546) e foi descartado — o dono pagou e não
> recebeu nada.

## O diagnóstico de custo (medido)

- Bloco de ferramentas: **112 tools = ~18.600 tokens** enviados em TODA chamada. Hoje **sem cache**.
- Cada iteração do loop reenvia: system (cacheado) + tools (não) + histórico (cresce a cada passo).
- Logo o custo é **multiplicativo pelo número de round-trips**. 30 idas ao LLM = 30× o contexto.
- O gargalo NÃO é o modelo pensar demais — é ele **conversar demais com o próprio sistema**:
  buscar produto, criar OS, adicionar item, buscar o próximo, adicionar... 30 vezes.

## Princípio

**O LLM decide O QUE fazer; o código decide COMO.**
Em vez de o modelo reger 30 micro-passos, ele faz UMA chamada com uma intenção compacta
(palavras-chave), e uma ferramenta do servidor executa o fluxo inteiro de uma vez e devolve
um resumo curto. Menos round-trips = menos custo, menos latência, sem timeout, mais previsível.

## As três alavancas

### 1. Macro-tools (composite) — a principal
Uma ferramenta cujo `execute()` faz um FLUXO inteiro no servidor, numa única ida ao LLM.
- **`create_quote_from_items`** (FLAGSHIP — resolve o caso que falhou): recebe cliente +
  título + lista de itens como PALAVRAS-CHAVE + mão de obra + imposto/comissão. O servidor
  resolve cada palavra-chave contra o catálogo, cria a OS, adiciona tudo, aplica encargos,
  recalcula e devolve: número, total, margem, o que casou (com origem/data) e o que ficou
  provisório. **~30 round-trips viram 1.**
- Próximos alvos do mesmo padrão: `approve_quote_full` (aprovação → sinal → lembrete → OC →
  agenda numa chamada), `send_quote_and_track` (cotação: criar + disparar).

### 2. Resolvedor por palavra-chave (determinístico)
O "faz sentido" do dono: o LLM manda termos, o CÓDIGO casa. Para cada item:
- busca em `products` (name/sku/brand), escolhe o melhor candidato por heurística simples;
- puxa o último preço praticado (`service_order_parts`) com data e origem;
- 1 match = alta confiança; vários = assume o melhor e MARCA "confirmar"; zero = "provisório".
Nunca interrompe por item — resolve tudo e REPORTA as suposições para o dono corrigir depois.
Vive em `_shared/ai/keyword-resolver.ts`, reutilizável por qualquer macro.

### 3. Cache — MEDIDO, já está saudável (corrigido)
Eu suspeitei que as tools iam sem cache. **Medi nos logs de token e estava errado:** o cache
funciona — ~43.6k tokens são lidos do cache em cada chamada (system + tools + prompt estável).
O breakpoint de cache no bloco estável cobre as ferramentas.
**O que NÃO é cacheado é o HISTÓRICO que cresce a cada iteração** (~26-28k tokens por chamada
no fundo de um turno longo). Ou seja, o custo real de um turno pesado = round-trips × histórico
crescente. Isso reforça a alavanca #1: cada macro-chamada que elimina uma ida ao LLM elimina
um reenvio de histórico de dezenas de milhares de tokens. Não há o que "consertar" no cache.

## Ordem de execução
1. **Resolvedor por palavra-chave** (base das macros).
2. **`create_quote_from_items`** (flagship — fecha o caso real e prova o padrão).
3. **Cache/enxugar tools** (alavanca fixa de custo, sem risco de comportamento).
4. Generalizar o padrão para aprovação e cotação, medindo o ganho a cada passo.

## Como medimos o sucesso
- O pedido dos 2 orçamentos passa a ser ~3 idas ao LLM em vez de ~30.
- Sem HTTP 546. Custo do pedido cai de ordem de grandeza.
- O agente vira "maestro": entende, monta o spec, chama uma macro, narra o resultado.
