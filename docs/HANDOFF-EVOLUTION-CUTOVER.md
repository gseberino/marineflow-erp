# Handoff — Migração Z-API → Evolution API (MarineFlow ERP)

> Documento de continuidade. Última atualização: cutover executado, em fase de
> validação ponta a ponta (debug de mensagem recebida não gravada).
> Branch com todo o código da migração: `claude/keen-brown-j2pgw0`
> (este arquivo foi salvo solto em D:\PC\marineflow-erp para leitura — não está commitado)

---

## 0. Como continuar no VS Code

O código da migração está no branch **`claude/keen-brown-j2pgw0`** (no GitHub).
Seu working copy atual está em `staging/marineflow-functional`. Para ver/trabalhar o código:

```powershell
cd D:\PC\marineflow-erp
git fetch origin
git checkout claude/keen-brown-j2pgw0   # ou crie um branch a partir dele
```

Depois abra o Claude Code no terminal (`claude`) já dentro dessa pasta para ter
acesso direto ao código + Docker + Supabase CLI.

---

## 1. Visão geral / objetivo

Migrar a integração de WhatsApp do MarineFlow ERP de **Z-API** para **Evolution API**
(self-hosted, custo zero, rodando em Docker na máquina local).

Feito com **abstração de provider** (`WhatsAppProvider`), controlada pela feature flag
`WHATSAPP_PROVIDER`. Cutover e rollback = trocar uma variável de ambiente, sem mudar código.

---

## 2. Estado atual (o que já foi feito)

| Fase | Entrega | Status |
|------|---------|--------|
| S1–S4 | Auditoria Z-API (`auditoria-zapi.md`) | ✅ |
| S5 | Docker provisioning (`infra/evolution/`) | ✅ |
| B1–B3 | Docs de risco/equivalência/topologia | ✅ |
| B4 | Abstração `WhatsAppProvider` + `ZapiProvider` | ✅ |
| S6 | Testes `ZapiProvider` + `normalizePhoneNumber` | ✅ |
| B5 | `EvolutionProvider` + `evolution-configure-webhook` | ✅ |
| S7 | Testes `EvolutionProvider` | ✅ |
| **B6** | **Cutover + validação E2E** | 🟡 **EM ANDAMENTO** |
| S8 | Cleanup (remover `ZapiProvider`) | ⬜ pendente |

### Arquivos-chave da abstração

```
supabase/functions/_shared/whatsapp/
├── types.ts                  # WhatsAppProvider, SendResult, IncomingMessageEvent
├── normalize.ts              # normalizePhoneNumber()
├── factory.ts                # createWhatsAppProvider() — escolhe via WHATSAPP_PROVIDER
├── zapi-provider.ts          # ZapiProvider
├── zapi-provider_test.ts
├── evolution-provider.ts     # EvolutionProvider
└── evolution-provider_test.ts
```

Edge functions refatoradas: `whatsapp-send`, `whatsapp-send-text`,
`whatsapp-queue-worker`, `whatsapp-webhook`, `scheduling-automations`.
Nova função: `evolution-configure-webhook`.

### Infraestrutura (na máquina local)

- **Evolution API v2.3.0** em Docker: container `hbr-evolution-api-local`,
  exposto em `http://127.0.0.1:8081` (NÃO é 8080).
- Stack: `hbr-evolution-api-local` + `hbr-evolution-postgres-local` + `hbr-evolution-redis-local`.
- **Instância `hbr-local`** criada e **conectada** (`connectionStatus: open`, "HBR Marine").
- **Cloudflare Quick Tunnel** expondo a 8081. ⚠️ **URL efêmera** — muda a cada reinício.

### Supabase (cutover JÁ EXECUTADO)

- Projeto ativo: **`marineflow-erp-staging`** → `project-ref: okurngvcodmljjicopdp`
- URL: `https://okurngvcodmljjicopdp.supabase.co`
- Secrets: `WHATSAPP_PROVIDER=evolution`, `EVOLUTION_API_URL=<tunnel>`,
  `EVOLUTION_API_KEY=<chave>`, `EVOLUTION_INSTANCE=hbr-local`
- Webhook da instância → `.../functions/v1/whatsapp-webhook` (`enabled: true`)
- `whatsapp-webhook` tem `verify_jwt=false`.

---

## 3. ⚠️ BLOQUEIO ATUAL — onde paramos

**Sintoma:** Mensagem de teste → webhook **foi chamado** (`POST | 200 | whatsapp-webhook`
nos logs), MAS **não foi gravada** em `whatsapp_messages`.

**Interpretação:** Conectividade 100% OK (WhatsApp → Evolution → Tunnel → Supabase).
O `parseIncomingWebhook()` retornou `null` (mensagem "ignorada").

**Causas a investigar (ordem de probabilidade):**

1. **Direção da mensagem.** Se enviada *DO* número HBR (fromMe), pode ter sido ignorada.
   → Teste correto: enviar de **OUTRO número → PARA** o número da HBR (inbound).
2. **Campo `event`.** Parser exige `event === "messages.upsert"` (minúsculo, com ponto).
   Ver `supabase/functions/_shared/whatsapp/evolution-provider.ts` (~linha 130).
3. **Estrutura do payload** v2.3.0 (`data.key`, `data.message`, `data.pushName`, `data.messageTimestamp`).

---

## 4. Próximo passo: capturar o payload bruto (debug não-invasivo)

Criar função de debug temporária que só grava o payload; apontar o webhook para ela;
reenviar; inspecionar o JSON real; corrigir o parser; reapontar para produção.

### 4.1 — Tabela de debug (SQL Editor do Supabase)

```sql
create table if not exists public.webhook_debug (
  id uuid primary key default gen_random_uuid(),
  received_at timestamptz default now(),
  payload jsonb
);
```

### 4.2 — Função `evolution-debug`

```typescript
// supabase/functions/evolution-debug/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

Deno.serve(async (req) => {
  const payload = await req.json().catch(() => ({}));
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  await admin.from("webhook_debug").insert({ payload });
  return new Response(JSON.stringify({ ok: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
```

Deploy:
```powershell
supabase functions deploy evolution-debug --no-verify-jwt --project-ref okurngvcodmljjicopdp
```

### 4.3 — Apontar o webhook para o debug (temporário)

```powershell
$key = ((Select-String -Path "D:\Agentes IA - Gustavo\hbr-agent-core\local-stack.env.example" -Pattern "^HBR_EVOLUTION_API_KEY=(.+)$").Matches.Groups[1].Value).Trim()
$body = @{ webhook = @{
  enabled=$true
  url="https://okurngvcodmljjicopdp.supabase.co/functions/v1/evolution-debug"
  webhookByEvents=$false; webhookBase64=$false
  events=@("MESSAGES_UPSERT")
}} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri "http://127.0.0.1:8081/webhook/set/hbr-local" -Method POST -Headers @{ "apikey"=$key; "Content-Type"="application/json" } -Body $body
```

### 4.4 — Reenviar (de outro número → HBR) e ler

```sql
select payload from public.webhook_debug order by received_at desc limit 1;
```

Comparar com o que `EvolutionProvider.parseIncomingWebhook` espera e ajustar.

### 4.5 — Reapontar para produção

```powershell
$key = ((Select-String -Path "D:\Agentes IA - Gustavo\hbr-agent-core\local-stack.env.example" -Pattern "^HBR_EVOLUTION_API_KEY=(.+)$").Matches.Groups[1].Value).Trim()
$body = @{ webhook = @{
  enabled=$true
  url="https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-webhook"
  webhookByEvents=$false; webhookBase64=$false
  events=@("MESSAGES_UPSERT","MESSAGES_UPDATE","MESSAGES_DELETE","SEND_MESSAGE","CONNECTION_UPDATE")
}} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Uri "http://127.0.0.1:8081/webhook/set/hbr-local" -Method POST -Headers @{ "apikey"=$key; "Content-Type"="application/json" } -Body $body
```

Depois de validar: **dropar `webhook_debug` e deletar `evolution-debug`**.

---

## 5. Caminhos na máquina local

| Item | Caminho |
|------|---------|
| Repositório | `D:\PC\marineflow-erp` (SSH: `git@github.com:gseberino/marineflow-erp.git`) |
| Docker Compose Evolution | `D:\Agentes IA - Gustavo\hbr-agent-core\docker-compose.local.yml` |
| Env Evolution (API key) | `D:\Agentes IA - Gustavo\hbr-agent-core\local-stack.env.example` → `HBR_EVOLUTION_API_KEY` |
| cloudflared.exe | `C:\cloudflared\cloudflared.exe` |

---

## 6. Comandos de verificação

**Saúde Evolution:**
```powershell
Invoke-WebRequest http://127.0.0.1:8081/   # 200 "it is working"
docker ps --filter "name=evolution"
```

**Listar instâncias (v2.3.0 — campo `name`):**
```powershell
$key = ((Select-String -Path "D:\Agentes IA - Gustavo\hbr-agent-core\local-stack.env.example" -Pattern "^HBR_EVOLUTION_API_KEY=(.+)$").Matches.Groups[1].Value).Trim()
Invoke-RestMethod -Uri "http://127.0.0.1:8081/instance/fetchInstances" -Headers @{ "apikey"=$key } | ConvertTo-Json -Depth 6
```

**Conferir webhook:**
```powershell
Invoke-RestMethod -Uri "http://127.0.0.1:8081/webhook/find/hbr-local" -Headers @{ "apikey"=$key } | ConvertTo-Json -Depth 5
```

**Iniciar Cloudflare Tunnel (gera nova URL → atualizar secret depois):**
```powershell
Start-Process -FilePath "C:\cloudflared\cloudflared.exe" `
  -ArgumentList "tunnel --url http://localhost:8081" `
  -RedirectStandardError "$env:TEMP\cloudflared-err.log" -NoNewWindow
Start-Sleep 10
Get-Content "$env:TEMP\cloudflared-err.log" | Select-String "trycloudflare.com"
```

**Atualizar secret da URL (após nova URL de tunnel):**
```powershell
supabase secrets set EVOLUTION_API_URL="https://<NOVA_URL>.trycloudflare.com" --project-ref okurngvcodmljjicopdp
```

**Rodar testes (precisa Deno):**
```powershell
deno test supabase/functions/_shared/whatsapp/
```

---

## 7. ⚠️ Pendências / riscos

1. **Tunnel efêmero (CRÍTICO).** Quick Tunnel muda de URL a cada reinício. Se cair,
   `EVOLUTION_API_URL` aponta para URL morta e o sistema para.
   → Criar **Named Tunnel** Cloudflare (URL fixa, grátis) ou VPS + domínio + TLS.
   Ver `decisao-topologia.md` e `infra/evolution/README.md`.
2. **Envio automático ativo.** Após cutover, enviam sozinhas: `whatsapp-process-scheduled`,
   `whatsapp-queue-worker`, `scheduling-automations`, `ai-whatsapp-followups`, `ai-agent`.
3. **Idempotência (B1).** Possível duplicação em cobranças — dedup key recomendada.
4. **RLS.** Verificar policies de `app_settings` para chaves `zapi_*` / `evolution_*`.
5. **S8 cleanup.** Remover `ZapiProvider` só após ~2 semanas estável + autorização.

---

## 8. Rollback

```powershell
supabase secrets set WHATSAPP_PROVIDER=zapi --project-ref okurngvcodmljjicopdp
```
(Número precisa estar pareado na Z-API novamente para envio funcionar.)

---

## 9. Definição de "pronto" (B6 completo)

- [ ] Mensagem **recebida** de outro número → aparece em `whatsapp_messages` (inbound)
- [ ] Mensagem **enviada** pelo painel → chega ao destinatário (outbound)
- [ ] `MESSAGES_UPDATE` atualiza `delivery_status`
- [ ] Tunnel estável (named tunnel ou VPS)
- [ ] `webhook_debug` e `evolution-debug` removidos
- [ ] 48h de monitoramento sem erros
