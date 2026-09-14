-- Recuperada do transcript da sessão (C--Users-PC/374b5203-fb74-4f92-b284-ba488b300c96.jsonl, 2026-08-08T16:35:42.575Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260808163546 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Função nova nasce executável por PUBLIC, e revogar só de `anon` não fecha nada: o
-- privilégio vem por PUBLIC, que inclui anon e authenticated. Já tropecei nisto antes —
-- a lição é revogar de PUBLIC e provar com has_function_privilege, não presumir.
--
-- `bloqueia_lancamento_em_periodo_fechado` é gatilho: ninguém deve poder chamá-la
-- diretamente pela API. `periodo_esta_fechado` só interessa a quem cuida do financeiro.

REVOKE EXECUTE ON FUNCTION public.periodo_esta_fechado(date) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bloqueia_lancamento_em_periodo_fechado() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.periodo_esta_fechado(date) TO service_role;
