-- Perfil de tools do agente: a LISTA saiu do banco e foi para o código (26/09/2026).
--
-- A lista de ai_tool_profile_operacao agora mora em supabase/functions/_shared/ai/perfil-operacao.ts
-- (PERFIL_OPERACAO), e um teste cruza prompt × perfil antes do deploy. Motivo: a lista era
-- editada à mão, nada a comparava com o prompt, e 32 ferramentas que o prompt ensinava ficaram
-- escondidas — o modelo obedecia e recebia "Tool desconhecida" (25/09, "me manda o PDF").
-- O retrato da lista como estava em produção ficou congelado em perfil-operacao_test.ts.
--
-- O banco passa a guardar só o liga/desliga (ai_tool_profile = 'operacao' | qualquer outro).
--
-- A CHAVE VELHA FICA (revisão final, 26/09/2026): a primeira versão desta migration apagava
-- ai_tool_profile_operacao. Apagar tira a rede de quem precisar voltar a edge ai-agent para uma
-- versão anterior a perfil-operacao.ts: o código antigo lê a lista do banco e, vazia, devolve
-- TODAS as tools (~35 mil tokens por chamada) sem ninguém perceber. Ela fica, marcada na
-- descrição como sem efeito, para ninguém editá-la achando que muda o agente. Apagar é para
-- depois de o código novo ter rodado sem volta.
--
-- ORDEM: aplicar DEPOIS do deploy da edge ai-agent com perfil-operacao.ts (só muda descrições;
-- antes do deploy a descrição diria algo que ainda não é verdade).
--
-- VERSÃO: nasceu 20260926213000, dentro da faixa que a sessão do financeiro usava na mesma noite
-- (20260926210000 já estava aplicada por ela) — duas sessões na mesma vizinhança dão versão
-- repetida ou fora de ordem no db push. Foi para 20260927090100, fora dessa faixa.
-- perfil-operacao_test.ts confere o nome e que a versão é única.

update public.app_settings
   set description = 'Perfil de tools do agente: operacao (lista enxuta em _shared/ai/perfil-operacao.ts, mais as de risco alto) ou qualquer outro valor = todas as tools.'
 where key = 'ai_tool_profile';

update public.app_settings
   set description = 'SEM EFEITO desde 27/09/2026: a lista do perfil operacao mora em _shared/ai/perfil-operacao.ts. Mantida só para voltar a edge ai-agent a uma versão antiga. Editar aqui não muda o agente.'
 where key = 'ai_tool_profile_operacao';

do $$
begin
  if not exists (select 1 from public.app_settings where key = 'ai_tool_profile') then
    raise exception 'ai_tool_profile sumiu — o perfil ficaria desligado (todas as tools)';
  end if;
end $$;
