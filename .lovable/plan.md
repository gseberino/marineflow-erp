

## Diagnóstico

Olhei os logs da Z-API e os registros no banco. Identifiquei **três problemas reais** que se misturam e geram a confusão atual:

### 1. "Mensagem não reconhecida" — o webhook não enxerga o campo de texto da Z-API
A Z-API entrega o payload `ReceivedCallback` com chaves no nível raiz: `text`, `image`, `audio`, `video`, `document`, **mas o campo `text` em algumas variantes vem como string direta** (ex.: `"text": "olá"`) ou como **`message`** dentro de um objeto. Hoje o código só trata `p.text.message`. Quando vem em outro formato (ex.: lista de transmissão, mensagem editada `isEdit`, mensagem com `referenceMessageId` de resposta), o parser cai no `else` e grava `[mensagem não reconhecida]`.

Também não tratamos: `p.body`, `p.caption`, `p.text` quando é string, mensagens de status (`p.status`), `messageContextInfo`, e o tipo `notification` (mudança de nome/foto), que devem ser ignorados em vez de virar mensagem.

### 2. Números incompatíveis (ex.: `+156860829159528`, `554792036481`)
Dois bugs de normalização:

- **Número truncado** (`554792036481` = 12 dígitos): a função `normalizePhone` adiciona o prefixo `55` apenas quando o input tem 10 ou 11 dígitos. Se a Z-API já manda 12 (`554792036481`), o código devolve como está — mas `4792036481` é só 10, faltando o **9** do celular brasileiro. O número real é `5547992036481` (13 dígitos com nono dígito). Precisamos **inserir o 9** quando detectarmos celular brasileiro de 8 dígitos no terceiro grupo.
- **Número gigante** (`156860829159528`): vem do `chatId` em formato `<phone>@c.us` ou `<phone>@s.whatsapp.net` em listas de transmissão, onde a Z-API às vezes concatena `participantPhone` + ID interno. Precisamos **extrair só o telefone antes de `@`** e descartar IDs com mais de 14 dígitos.

### 3. Os lembretes outbound estão "poluindo" o inbox
Os registros que você está vendo com texto `🆕 Novo lead WhatsApp ... [mensagem não reconhecida]` são **mensagens outbound** (lembretes que o sistema enviou aos admins), não mensagens recebidas de clientes. Elas aparecem no inbox porque o filtro atual mostra todas as direções. O texto "mensagem não reconhecida" dentro delas é só o **eco** da primeira mensagem original mal-parseada (problema 1).

---

## Plano de correção

### A) Corrigir o parser de mensagens (`whatsapp-webhook`)
Reescrever o bloco de extração de texto para cobrir todas as variantes da Z-API:
```ts
// pseudocódigo
if (typeof p.text === 'string') body = p.text;
else if (p.text?.message) body = p.text.message;
else if (typeof p.message === 'string') body = p.message;
else if (p.message?.conversation) body = p.message.conversation;
else if (p.message?.extendedTextMessage?.text) body = p.message.extendedTextMessage.text;
else if (p.body) body = p.body;
else if (p.caption) body = p.caption;
// ...image/audio/video/document/sticker/reaction/poll/list/buttonsResponse
```
Adicionar suporte a: `sticker`, `reaction`, `poll`, `listResponseMessage`, `buttonsResponseMessage`, `templateMessage`, `contactsArrayMessage`. Para tipos sem texto útil (reação, sticker), gravar com `message_type` específico (ex.: `reaction`, `sticker`) em vez de `other`.

Ignorar callbacks de sistema que não são mensagem: `notification`, `MessageStatusCallback` (já tratado), `PresenceChatCallback`, e payloads onde `p.notification` está presente.

### B) Corrigir normalização de telefone
Reescrever `normalizePhone`:
```ts
function normalizePhone(raw, defaultDDI = "55") {
  if (!raw) return "";
  // Extrai só a parte antes de @ (chatId @c.us / @broadcast)
  let s = String(raw).split('@')[0];
  let d = s.replace(/\D/g, "");
  if (!d) return "";
  if (d.length > 14) return ""; // ID interno inválido
  if (d.startsWith("00")) d = d.slice(2);
  // Brasil: se vier 12 dígitos começando com 55 e o terceiro bloco tiver 8, inserir o 9
  if (d.length === 12 && d.startsWith("55")) {
    const ddd = d.slice(2,4);
    const rest = d.slice(4);
    if (rest.length === 8 && /^[6-9]/.test(rest)) {
      d = `55${ddd}9${rest}`;
    }
  }
  if (d.length >= 12 && d.length <= 14) return d;
  if (d.length === 10 || d.length === 11) return `${defaultDDI}${d}`;
  return d;
}
```

### C) Migração para corrigir registros já gravados
Criar uma migration que:
1. **Re-normaliza** `phone_normalized` em `whatsapp_messages` e `whatsapp_leads` aplicando a regra do nono dígito (Brasil).
2. **Funde leads duplicados** (mesmo telefone após renormalização): mantém o lead com mais mensagens, atualiza `whatsapp_messages.lead_id` para apontar pro lead vencedor, deleta o duplicado.
3. **Re-extrai o body** dos registros com `message_type='other'` ou body=`[mensagem não reconhecida]` reaplicando o novo parser sobre `raw_payload`. (Função plpgsql que lê o JSON e atualiza `body`/`message_type`.)
4. **Marca como `outbound`** os registros que têm `raw_payload->>'fromMe' = 'true'` mas estão como `inbound` (caso existam).

### D) Filtro no Inbox — separar inbound vs outbound
No `WhatsAppLeadsPage` (e no `WhatsAppLogsPage`), garantir que o **inbox de leads mostre só `direction='inbound'`** dos clientes. Os lembretes `outbound` ficam visíveis apenas na página de Logs com filtro de direção.

### E) Botão "Reprocessar payloads"
Na página **Logs WhatsApp**, adicionar botão **"Reprocessar mensagens não reconhecidas"** que chama uma edge function nova (`whatsapp-reprocess-messages`) que itera sobre registros com `message_type='other'` e reaplica o parser corrigido sobre o `raw_payload`. Útil para corrigir histórico sem rodar migration novamente.

---

## Arquivos afetados

| Arquivo | Mudança |
|---|---|
| `supabase/functions/whatsapp-webhook/index.ts` | Reescrever `normalizePhone` + parser de body |
| `supabase/functions/whatsapp-reprocess-messages/index.ts` | **Novo** — reprocessa registros `other` |
| `supabase/migrations/<ts>_fix_whatsapp_phones_and_bodies.sql` | Renormaliza telefones + funde leads + re-extrai body |
| `src/pages/WhatsAppLeadsPage.tsx` | Filtrar `direction='inbound'` no inbox |
| `src/pages/WhatsAppLogsPage.tsx` | Adicionar botão "Reprocessar não reconhecidas" |

---

## Pergunta antes de implementar

A migration de **fusão de leads duplicados** é destrutiva (deleta o lead duplicado e move histórico). Prefere:
- **(a)** Aplicar fusão automática (recomendado — limpa o inbox)
- **(b)** Apenas renormalizar telefones e me deixar uma view com os duplicados pra eu mesclar manualmente

Confirme a escolha (a/b) e digo "implementar" para eu sair do modo plano e aplicar tudo.

