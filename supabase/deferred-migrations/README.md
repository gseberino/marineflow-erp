# Deferred migrations

Migrations **NÃO** aplicadas automaticamente pelo pipeline padrão do projeto.

Esta pasta fica **fora** de `supabase/migrations/`, portanto o Supabase CLI
e qualquer pipeline que rode `supabase db push` **não a processa**. Cada
migration aqui requer:

1. Decisão explícita de Gustavo / equipe de homologação.
2. Cópia manual para `supabase/migrations/` (ou aplicação direta via
   `supabase db execute` em staging).
3. Validação posterior de comportamento.

## Arquivos atuais

### `20260522190100_ai_operator_whatsapp_bridge.sql`

Cria trigger `AFTER INSERT` em `whatsapp_messages` que enfileira mensagens
inbound em `ai_operator_channel_events`.

**Por que está deferido (Macro Ciclo 1 continuação):**

- O núcleo do MarineFlow AI Operator ainda está sendo homologado em modo
  interno.
- Ativá-la traz para dentro do operador **mensagens reais de clientes**
  (texto + mídia: áudio, imagem, documento, vídeo).
- Decisões pendentes:
  - retenção de mídia sensível;
  - serviço/credencial para transcrição de áudio;
  - serviço/credencial para OCR de documentos;
  - política de resposta automática (atualmente: nunca);
  - integração com o adapter de canal (`ai-operator-channel-intake`).

**Para ativar (futuro ciclo):**

1. Confirmar que o núcleo (`ai-operator-core`) está homologado em staging.
2. Confirmar que existe um worker / Edge Function processando
   `ai_operator_channel_events` (hoje só enfileira).
3. Confirmar que `whatsapp-webhook` continua estabilizado.
4. Mover este arquivo para `supabase/migrations/` no commit que ativa o
   ciclo seguinte (ajustar prefixo de data se necessário).
5. Validar em staging antes de qualquer ativação que envolva clientes
   reais.
