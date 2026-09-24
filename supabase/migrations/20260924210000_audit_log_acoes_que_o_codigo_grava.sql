-- A auditoria recusava, em silêncio, seis ações que o código grava há meses.
--
-- `audit_log_action_check` é uma LISTA FECHADA. Toda vez que uma funcionalidade nova
-- passou a auditar algo, o insert virou erro 23514 e a linha não entrou. E como o
-- `writeAuditLog` do frontend nunca olhava o erro devolvido, o rastro sumia sem deixar
-- nem log: em 24/09/2026 a importação de XML tentou gravar quatro vezes e as quatro
-- foram recusadas — só apareceu porque a edge function checa o erro.
--
-- Contagem em produção antes desta migration (audit_log agrupado por action):
--   update 910 · whatsapp_send_api 205 · reversal 69 · cascade_update 30 · cancel 17
--   lead_created 9 · client_signature 5 · lead_converted 1 · whatsapp_send 1
-- e ZERO para as seis abaixo, que o código escreve:
--
--   import_xml                          entrada de mercadoria por XML (edge process-nfe-xml)
--   confirm_import                      a conferência que dá entrada no estoque
--   revert_import                       desfazer essa entrada
--   whatsapp_preview                    abriu a prévia da mensagem
--   whatsapp_send_open                  abriu o envio de recibo/cobrança
--   whatsapp_unread_reminder_enqueued   lembrete de mensagem não lida agendado
--
-- O que se perdeu não dá para recuperar — o insert falhou, não há de onde ler. O que esta
-- migration garante é que a partir de agora o rastro exista. As entradas antigas de
-- estoque continuam sem auditoria, e isso está registrado aqui de propósito.
--
-- Por que continuar com lista fechada em vez de abrir a coluna: ela é o que impede um
-- `action` digitado errado ('whatsapp_sent' em vez de 'whatsapp_send') de virar uma
-- categoria fantasma que nenhum relatório soma. O preço é este: ampliar a lista junto
-- com a funcionalidade. O teste `src/test/audit-log-acoes.test.ts` passou a cobrar isso.

ALTER TABLE public.audit_log DROP CONSTRAINT IF EXISTS audit_log_action_check;
ALTER TABLE public.audit_log ADD CONSTRAINT audit_log_action_check
  CHECK (action = ANY (ARRAY[
    -- ciclo de vida do registro
    'update','cancel','reopen','reversal','cascade_update','client_signature',
    -- WhatsApp
    'whatsapp_send','whatsapp_send_api','whatsapp_received','whatsapp_preview',
    'whatsapp_send_open','whatsapp_unread_reminder_enqueued',
    -- leads
    'lead_created','lead_matched','lead_converted',
    -- entrada de mercadoria por XML
    'import_xml','confirm_import','revert_import'
  ]));
