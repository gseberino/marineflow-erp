# AI Operator — Setup (Fase 1: migração para Claude)

Este documento cobre os passos manuais que um operador humano precisa executar para o
assistente de IA do MarineFlow ERP (`supabase/functions/ai-agent`) funcionar em produção
depois da migração de Gemini para Claude (Anthropic).

## Secrets a configurar no Supabase

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-... --project-ref okurngvcodmljjicopdp
```

- `ANTHROPIC_API_KEY`: chave da API da Anthropic (console.anthropic.com). Sem ela, a
  função `ai-agent` responde imediatamente com `{"error": "ANTHROPIC_API_KEY não
  configurada no Supabase"}` (HTTP 500 via header `X-Actual-Status`).
- `GEMINI_API_KEY` pode continuar configurada — não é mais usada pelo código
  (`ai-agent/index.ts` foi totalmente migrado para Claude nesta fase), mas não há
  necessidade de removê-la agora.

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
   chamada à Anthropic dentro do mesmo turno aparece `cache_read_input_tokens` maior que
   zero na linha `[anthropic] model=... usage={...}` — isso confirma que o prompt caching
   está funcionando.
