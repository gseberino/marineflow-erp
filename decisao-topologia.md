# Decisão de Topologia de Rede (Fase B3)
**Projeto:** MarineFlow ERP — Migração WhatsApp Z-API → Evolution API
**Data:** 2026-06-10

> **Bloqueador identificado:** a Evolution roda em `localhost:8080` (S5). É preciso definir como o backend do MarineFlow alcança a Evolution **antes** de qualquer integração (B4/B5).

---

## Cenário identificado: **A — chamadas partem do backend/nuvem**

Evidência no código real (auditoria S1–S4, confirmada na B1):

- **Todas** as chamadas à Z-API partem de **Supabase Edge Functions** (Deno, executando na **nuvem** da Supabase): `whatsapp-send`, `whatsapp-send-text`, `whatsapp-queue-worker`, `whatsapp-status-worker`, `whatsapp-unread-reminder`, `scheduling-automations`, `zapi-configure-webhook`, e o `whatsapp-webhook` (notificação de lead).
- O **front-end nunca** chama a Z-API diretamente — sempre via `supabase.functions.invoke(...)`. (Cenário B descartado; o front já está protegido por proxy.)
- Não há backend local/n8n no mesmo host (Cenário C descartado).

**Consequência:** as edge functions na nuvem da Supabase **não conseguem** alcançar `http://localhost:8080` da máquina do desenvolvedor. A Evolution precisa de um **endereço público** alcançável pela nuvem.

### Direção das duas conexões

| Direção | Quem inicia | Destino | Já funciona hoje? |
|---|---|---|---|
| **Saída (envio)** | Edge function (nuvem) | Evolution API | ❌ **bloqueado** — Evolution em localhost. **É o que precisa ser resolvido.** |
| **Entrada (webhook)** | Evolution | `…/functions/v1/whatsapp-webhook` (Supabase, **já público**) | ✅ funciona — a URL do webhook do MarineFlow já é pública. |

O problema é **unidirecional**: só a saída (edge → Evolution) precisa de exposição pública. A entrada já está resolvida porque o endpoint de webhook do MarineFlow é uma URL pública da Supabase.

---

## Decisão — Desenvolvimento

**Túnel Cloudflare (nomeado) para expor `localhost:8080`.**

- `cloudflared tunnel` com **nome fixo** (não o `trycloudflare` efêmero) → URL estável tipo `https://evo-dev.seudominio.com`, sem trocar a cada restart.
- Configurar `EVOLUTION_API_URL` = URL do túnel nos **secrets da edge function** (Supabase), **não** no `.env` do front.
- Alternativas equivalentes: `ngrok` (mais simples, mas URL muda no plano free) ou `tailscale funnel`. **Recomendo Cloudflare Tunnel** pela URL estável e gratuidade.

```
[Edge Function nuvem] --HTTPS--> [Cloudflare Tunnel] --> [localhost:8080 Evolution]
[Evolution] --HTTPS--> [Supabase .../whatsapp-webhook] (já público)
```

## Decisão — Produção

**VPS com Docker + reverse proxy TLS.**

- Subir o stack da S5 (`infra/evolution/docker-compose.yml`) em uma **VPS** (Hetzner/DigitalOcean/equivalente) com domínio e IP fixo.
- **Reverse proxy** (Caddy ou Traefik) terminando **TLS** em `https://evo.seudominio.com` → `evolution-api:8080` (na rede interna do compose).
- `EVOLUTION_API_URL=https://evo.seudominio.com` nos secrets da Supabase de produção.
- A porta `8080` **não** deve ser exposta diretamente à internet — apenas via proxy TLS. O `apikey` protege a API, mas TLS é obrigatório (o `apikey` trafega em header).
- Volume `evolution_instances` em disco persistente (a sessão WhatsApp não pode se perder — já previsto na S5).

```
[Edge Function nuvem] --HTTPS--> [Caddy/Traefik :443] --> [evolution-api:8080 (rede interna)]
                                       └ TLS, apikey no header
```

---

## Proteção da chave (já adequada, reforçar)

- `EVOLUTION_API_KEY` vai **somente** em **Supabase secrets** (lido por `Deno.env.get`), nunca em `VITE_*`/bundle. Mesma postura do `ZAPI_TOKEN` hoje.
- As edge functions continuam sendo o **proxy** entre front e provider — nenhuma mudança de superfície de exposição em relação ao modelo atual.
- ⚠️ **Pendência herdada do B1 (#5):** se forem espelhadas chaves `evolution_*` em `app_settings` (como hoje com `zapi_*`), **restringir RLS a admin** antes. Preferência: **não** espelhar credenciais Evolution no DB — mantê-las só em secrets.

---

## Passos necessários (pré-B5)

1. **Dev:** instalar `cloudflared`, criar túnel nomeado para `localhost:8080`, anotar a URL pública.
2. Criar a instância `marineflow` na Evolution e **escanear o QR** (S5/README); confirmar `connectionState = open`.
3. Definir secrets na Supabase (dev e, depois, prod): `EVOLUTION_API_URL`, `EVOLUTION_API_KEY`, `EVOLUTION_INSTANCE`, `WHATSAPP_PROVIDER=zapi` (só vira `evolution` no cutover B6).
4. **Prod (quando aprovado):** provisionar VPS, subir o compose, configurar Caddy/Traefik + domínio + TLS, apontar `EVOLUTION_API_URL` de produção.
5. Registrar o webhook na instância via `POST /webhook/set/{instance}` apontando para `…/functions/v1/whatsapp-webhook` (B5.3).

---

## Decisões que dependem do desenvolvedor (bloqueiam B5)

1. **Domínio/host de produção** da Evolution (qual VPS/domínio?) — necessário para `EVOLUTION_API_URL` de prod.
2. **URL do túnel de dev** (após criar o Cloudflare Tunnel) — necessário para testar `EvolutionProvider` em dev.
3. **Espelhar credenciais Evolution no `app_settings`?** Recomendo **não** (só secrets). Confirmar.
4. **Modo "link" sem equivalente na Evolution** (ver `tabela-equivalencia.md`, risco #2) — como tratar o card de OS/orçamento? Pergunta levada ao desenvolvedor.

> **Fim da Fase B3. Topologia: Cenário A (backend→nuvem). Dev = Cloudflare Tunnel; Prod = VPS+TLS. Aguardando confirmação dos 4 itens acima antes da Fase B4/B5.**
