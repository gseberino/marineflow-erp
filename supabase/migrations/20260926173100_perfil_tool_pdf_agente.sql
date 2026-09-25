-- Libera send_document_pdf_to_self no perfil enxuto de tools do agente (ai_tool_profile_operacao).
--
-- Com o perfil "operacao" ativo, só entram no turno as tools desta lista, as de risco alto e as
-- que o usuário digitou pelo nome (_shared/ai/agent.ts). Tool nova fora da lista fica
-- INVISÍVEL: foi o que aconteceu com get_whatsapp_conversation — publicada em 24/09/2026 e com
-- zero usos, porque nunca entrou aqui.
--
-- Aplicar DEPOIS do teste real com a tool chamada pelo nome (Fase 5). O agente guarda o perfil
-- em cache por 5 minutos: a liberação vale a partir do cache seguinte.
--
-- Idempotente: só acrescenta se ainda não estiver na lista.

update app_settings
   set value = (value::jsonb || '["send_document_pdf_to_self"]'::jsonb)::text
 where key = 'ai_tool_profile_operacao'
   and not (value::jsonb ? 'send_document_pdf_to_self');

do $$
begin
  if not exists (
    select 1 from app_settings
     where key = 'ai_tool_profile_operacao' and value::jsonb ? 'send_document_pdf_to_self'
  ) then
    raise exception 'send_document_pdf_to_self não entrou em ai_tool_profile_operacao';
  end if;
end $$;
