-- Adiciona suporte a envio de PDF pré-gerado em agendamentos.
-- O document_url é gerado no client (browser) no momento do agendamento
-- e armazenado aqui para que whatsapp-process-scheduled possa usar
-- sem precisar regenerar o PDF no servidor.
ALTER TABLE public.whatsapp_scheduled_sends
  ADD COLUMN IF NOT EXISTS document_url text;
