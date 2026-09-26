-- Perfil de tools do agente: a LISTA saiu do banco e foi para o código (26/09/2026).
--
-- A lista de ai_tool_profile_operacao agora mora em supabase/functions/_shared/ai/perfil-operacao.ts
-- (PERFIL_OPERACAO), e um teste cruza prompt × perfil antes do deploy. Motivo: a lista era
-- editada à mão, nada a comparava com o prompt, e 32 ferramentas que o prompt ensinava ficaram
-- escondidas — o modelo obedecia e recebia "Tool desconhecida" (25/09, "me manda o PDF").
-- O retrato da lista como estava em produção ficou congelado em perfil-operacao_test.ts.
--
-- O banco passa a guardar só o liga/desliga (ai_tool_profile = 'operacao' | qualquer outro).
-- Apagar a chave velha é para não sobrar uma "segunda fonte" que alguém edite achando que muda
-- o agente — ela não muda mais nada.
--
-- ORDEM SEGURA: aplicar DEPOIS do deploy da edge ai-agent com perfil-operacao.ts. Se for aplicada
-- antes, o código antigo lê a lista vazia e devolve TODAS as tools: não quebra nada, só volta a
-- custar ~35 mil tokens por chamada até o deploy.

update public.app_settings
   set description = 'Perfil de tools do agente: operacao (lista enxuta em _shared/ai/perfil-operacao.ts, mais as de risco alto) ou qualquer outro valor = todas as tools.'
 where key = 'ai_tool_profile';

delete from public.app_settings where key = 'ai_tool_profile_operacao';

do $$
begin
  if exists (select 1 from public.app_settings where key = 'ai_tool_profile_operacao') then
    raise exception 'ai_tool_profile_operacao continua no banco';
  end if;
  if not exists (select 1 from public.app_settings where key = 'ai_tool_profile') then
    raise exception 'ai_tool_profile sumiu — o perfil ficaria desligado (todas as tools)';
  end if;
end $$;
