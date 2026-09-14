# Desativar o `hbrmarine.online` — inventário medido e ordem segura

**27/07/2026** · levantamento read-only, nada foi alterado · complementa `marineflow-email-agente.md` §3.1

---

## 1. Correção do que eu disse antes

Eu avisei que desligar o `.online` quebraria "os links de orçamento e OS já enviados a clientes".
**Fui buscar o número e não é verdade.** Varri **todas as colunas de texto de todas as tabelas** do
schema `public` e o domínio aparece em **2 linhas no banco inteiro**:

| Onde | Ocorrências |
|---|---|
| `app_settings.value` (a chave `app_public_url`) | 1 |
| `ai_comms_log.message_preview` | 1 |

E nas mensagens de WhatsApp: **zero**. De 73 mensagens que contêm URL, 1 aponta para `vercel.app`
e 72 para outros destinos — **nenhuma para `hbrmarine.online`**. Ou seja: **não há link antigo em
poder de cliente que vá quebrar.** O risco que eu levantei era prospectivo (links futuros), não
retrospectivo. Corrigido.

## 2. O que realmente depende do domínio

Em ordem de gravidade:

### 2.1 🔴 `evolution.hbrmarine.online` — o WhatsApp para
É o hostname do Cloudflare Tunnel que expõe a Evolution API rodando no Docker local. O secret
`EVOLUTION_API_URL` do Supabase aponta para lá. **Se o DNS sair do ar, o envio de WhatsApp morre** —
`whatsapp-send` passa a responder 502, exatamente o modo de falha já documentado.
Este é o único item verdadeiramente bloqueante.

### 2.2 🟡 `app_settings.app_public_url` — links futuros nascem quebrados
Uma linha, mas ela é lida em três caminhos de código:

| Arquivo | Uso |
|---|---|
| `supabase/functions/whatsapp-process-scheduled/index.ts:61` | monta a URL base do link enviado |
| `supabase/functions/_shared/ai/tools/whatsapp.ts:236` | `origin` usado pela tool de envio |
| `supabase/functions/ai-agent/index.ts:384` | `toolCtx.appOrigin` no canal WhatsApp |

Enquanto o valor não for trocado, todo link novo que o agente enviar nasce apontando para um
domínio morto.

### 2.3 🟡 Fallbacks fixos no código
Se `app_public_url` ficar vazio, estes assumem o domínio antigo:

- `src/pages/SettingsPage.tsx:331, 371, 718` (default + placeholder do campo)
- `src/components/WhatsAppSettings.tsx:98`
- `src/hooks/use-whatsapp-templates.ts:172` (só texto de exemplo)
- `supabase/functions/whatsapp-process-scheduled/index.ts:61`
- `supabase/functions/whatsapp-webhook/index.ts:70` — a frase *"Responda no painel hbrmarine.online"*,
  enviada a **você** a cada novo lead. Não vai para cliente, mas fica errada.

### 2.4 🟢 Cosmético
`_shared/ai/anthropic.ts:163` e `whatsapp-read-media/index.ts:93` mandam
`HTTP-Referer: https://hbrmarine.online` para o OpenRouter. É só atribuição de ranking — domínio
morto ali não quebra nada, mas convém arrumar junto.

### 2.5 🟢 O endereço do ERP em si
Hoje o app é servido em `hbrmarine.online` (confirmado: HTTP 200, `<title>HBR Marine - ERP
Sistema</title>`). O projeto Vercel só tem os domínios `*.vercel.app`, então quem responde ali é a
Cloudflare apontando para a Vercel. Perder isso é perder o atalho bonito — quem usa o sistema passa
a entrar por `marineflow-erp.vercel.app`. Incômodo, não incidente.

---

## 3. Ordem segura (o que não pode ser invertido)

> **A regra:** mover o túnel **antes** de mexer no DNS. Todo o resto é reversível; o túnel não.

1. **Decidir o novo endereço do ERP.** Duas opções realistas:
   - `erp.hbrmarine.com.br` (DNS na GoDaddy → CNAME para a Vercel + adicionar o domínio no projeto).
     Melhor: alinha o sistema à marca que vocês realmente usam.
   - Ficar em `marineflow-erp.vercel.app`. Zero trabalho, endereço feio.
2. **Criar o novo hostname do túnel** (ex.: `evolution.hbrmarine.com.br`) apontando para o mesmo
   tunnel ID `0aab3763-a50b-45fc-b16b-63977ea03cf7`, **sem remover o antigo**. Os dois podem
   coexistir.
3. **Trocar o secret** `EVOLUTION_API_URL` no Supabase para o novo hostname.
4. **Testar o envio de WhatsApp de verdade** (uma mensagem para o seu próprio número). Só depois
   de ver a mensagem chegar é que o hostname antigo pode cair.
5. **Atualizar `app_settings.app_public_url`** para o novo endereço do ERP.
6. **Trocar os fallbacks no código** (item 2.3) e fazer deploy.
7. **Só então** deixar o `.online` expirar ou remover as rotas.

**Se a ordem for invertida** — domínio fora antes do passo 4 — o WhatsApp para e a recuperação exige
recriar hostname e secret com o sistema já em produção parado.

---

## 4. O que eu posso fazer sozinho e o que precisa de você

| Tarefa | Quem |
|---|---|
| Trocar os fallbacks fixos do código por leitura de config, sem domínio decorado | **Eu** — é edição de arquivo, só peça |
| Preparar o SQL de troca do `app_public_url` | **Eu** (aplicar exige sua autorização) |
| Decidir o novo endereço do ERP | **Você** |
| DNS na GoDaddy / domínio na Vercel / hostname no Cloudflare Tunnel | **Você** (é console autenticado) |
| Trocar o secret `EVOLUTION_API_URL` | **Você** (ou eu, com autorização explícita — é produção) |

**Não fiz nada disso ainda.** Os passos 2.3 e 2.4 mexem em arquivos que outras sessões podem estar
editando neste momento, então preferi não tocar sem você mandar.
