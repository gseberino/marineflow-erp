-- Recuperada do transcript da sessão (C--Users-PC/2d4124b3-a014-48da-8feb-73901aafa6ff.jsonl, 2026-07-27T20:31:06.154Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260727203110 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- CORREÇÃO DE SEGURANÇA (27/07/2026)
--
-- Uma view no Postgres roda, por padrão, com os privilégios do DONO (postgres), não de quem
-- chama. Com isso a RLS das tabelas base é ignorada: qualquer portador da chave anônima
-- lia 23 fios do ERP (incluindo valores de títulos vencidos) e 95 contatos não
-- identificados (telefone + trecho da última mensagem). Verificado com SET ROLE anon.
--
-- security_invoker = on faz a view respeitar a RLS de quem consulta. O REVOKE é a segunda
-- camada: o papel anônimo não tem motivo para enxergar nenhuma das duas.

ALTER VIEW public.erp_open_loop_facts  SET (security_invoker = on);
ALTER VIEW public.unidentified_contacts SET (security_invoker = on);

REVOKE ALL ON public.erp_open_loop_facts  FROM anon;
REVOKE ALL ON public.unidentified_contacts FROM anon;

-- Funções que ESCREVEM não devem sequer ser chamáveis pelo papel anônimo. A RLS já barrava
-- a gravação, mas deixar a porta fechada é mais barato que depender de uma segunda trava.
REVOKE EXECUTE ON FUNCTION public.refresh_entity_open_loops()             FROM anon;
REVOKE EXECUTE ON FUNCTION public.touch_open_loop(uuid, text, timestamptz, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.record_conversation_loop(
  text, uuid, text, text, text, text, uuid, timestamptz, text, text, timestamptz, uuid
) FROM anon;
REVOKE EXECUTE ON FUNCTION public.backfill_message_identity(integer)      FROM anon;
