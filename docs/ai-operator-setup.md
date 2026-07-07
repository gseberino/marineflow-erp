# AI Operator — Setup (Fase 1: migração para Claude via OpenRouter)

Este documento cobre os passos manuais que um operador humano precisa executar para o
assistente de IA do MarineFlow ERP (`supabase/functions/ai-agent`) funcionar em produção
depois da migração de Gemini para Claude. O modelo é roteado via **OpenRouter** (não a API
nativa da Anthropic) — decisão inicial do projeto, aproveitando conta/créditos já existentes.

## Secrets a configurar no Supabase

```bash
supabase secrets set OPENROUTER_API_KEY=sk-or-v1-... --project-ref okurngvcodmljjicopdp
```

- `OPENROUTER_API_KEY`: chave da conta OpenRouter (openrouter.ai/keys). Sem ela, a função
  `ai-agent` responde imediatamente com `{"error": "OPENROUTER_API_KEY não configurada no
  Supabase"}` (HTTP 500 via header `X-Actual-Status`).
- `GEMINI_API_KEY` pode continuar configurada — não é mais usada pelo código
  (`ai-agent/index.ts` foi totalmente migrado para Claude nesta fase), mas não há
  necessidade de removê-la agora.
- Não é necessário criar uma `ANTHROPIC_API_KEY` separada nesta fase — o OpenRouter já
  encaminha para a Anthropic por trás usando a própria infraestrutura dele.

## Modelos usados

- Agente principal: `anthropic/claude-sonnet-5` (via OpenRouter).
- Tarefas leves (`optimize_text`, modo `is_sales_copy`): `anthropic/claude-haiku-4.5`.

Se um dia for necessário trocar para a API nativa da Anthropic (sem passar pelo
OpenRouter), a mudança fica isolada em `supabase/functions/_shared/ai/anthropic.ts` — o
resto do núcleo do agente (`agent.ts`, `tools/*.ts`, `prompt.ts`) não precisa mudar, pois
fala um vocabulário interno já no formato nativo da Anthropic independente do transporte.

## Deploy

Depois de configurar o secret acima:

```bash
supabase functions deploy ai-agent --project-ref okurngvcodmljjicopdp
```

Nenhum outro secret novo é necessário nesta fase (`AI_INTERNAL_SECRET` e o secret de cron
no Vault só entram nas Fases 4 e 5).

## O que validar após o deploy

1. Abrir o widget de IA no app e mandar uma pergunta simples (ex: "quantas OS abertas
   temos?") — deve responder normalmente.
2. Pedir para criar um orçamento para um cliente já cadastrado — deve passar pelo fluxo de
   busca → desambiguação (se houver mais de um resultado) → `propose_action` → confirmação.
3. Nos logs da função (`supabase functions logs ai-agent`), confirmar que a partir da 2ª
   chamada dentro do mesmo turno aparece `cached_tokens` maior que zero na linha
   `[openrouter] model=... usage={...}` — isso confirma que o prompt caching está
   funcionando (cobrado a 0.25x pelo OpenRouter nos tokens lidos do cache).
