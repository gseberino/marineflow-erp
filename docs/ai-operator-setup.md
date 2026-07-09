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

O secret de cron no Vault só entra na Fase 5. `AI_INTERNAL_SECRET` já é necessário a
partir da Fase 4 — ver seção própria abaixo.

## O que validar após o deploy

1. Abrir o widget de IA no app e mandar uma pergunta simples (ex: "quantas OS abertas
   temos?") — deve responder normalmente.
2. Pedir para criar um orçamento para um cliente já cadastrado — deve passar pelo fluxo de
   busca → desambiguação (se houver mais de um resultado) → card de aprovação → confirmar.
3. Nos logs da função (`supabase functions logs ai-agent`), confirmar que a partir da 2ª
   chamada dentro do mesmo turno aparece `cached_tokens` maior que zero na linha
   `[openrouter] model=... usage={...}` — isso confirma que o prompt caching está
   funcionando (cobrado a 0.25x pelo OpenRouter nos tokens lidos do cache).

## Fase 4 — canal WhatsApp interno (equipe)

**Ainda não deployado nem habilitado para ninguém** — os passos abaixo são pra quando o
usuário decidir ativar.

### Secret novo

```bash
supabase secrets set AI_INTERNAL_SECRET=$(openssl rand -hex 32) --project-ref okurngvcodmljjicopdp
```

Usado pelo `whatsapp-webhook` pra autenticar a chamada interna que ele faz pro `ai-agent`
(não é um JWT de usuário — é um segredo compartilhado entre as duas functions).

### Habilitar um funcionário

Ainda não existe UI pra isso (fica pra Fase 6 — `AppUserEditDialog`/settings). Por
enquanto, via SQL direto (Supabase Studio ou `execute_sql`):

```sql
update app_users
set ai_whatsapp_enabled = true
where id = '<uuid do funcionário>';
```

`phone_normalized` já deve estar preenchido pelo backfill da migration
(`20260706120000_app_users_ai_whatsapp.sql`) — confirme com
`select phone, phone_normalized from app_users where id = '<uuid>';` antes de habilitar.

### Definir o PIN (ações de risco alto)

Não existe UI ainda. Gerar o hash localmente com Deno e gravar via SQL:

```bash
deno eval 'import { hashPin } from "./supabase/functions/_shared/ai/whatsapp-pin.ts"; console.log(await hashPin("4321"))'
```

```sql
update app_users set ai_whatsapp_pin_hash = '<hash gerado acima>' where id = '<uuid>';
```

### Riscos antes de deployar esta fase

- `whatsapp-webhook` é uma function em produção que hoje recebe mensagens reais de
  clientes/leads — a mudança foi cuidadosamente colocada ANTES da resolução de lead e só
  ativa pra números com `ai_whatsapp_enabled=true` (nenhum ainda), mas vale testar com
  `wa_test_mode` ativo e um número de teste antes de habilitar alguém de verdade.
- Uma vez habilitado, mensagens daquele número passam a ser respondidas pela IA de
  verdade — teste primeiro com o próprio número de quem for revisar.
