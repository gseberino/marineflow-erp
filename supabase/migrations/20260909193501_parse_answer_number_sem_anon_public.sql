-- Recuperada do transcript da sessão (C--Users-PC/a12c77fb-6295-4d2c-86c2-da5fd7d7a34a.jsonl, 2026-09-09T19:35:13.420Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260909193501 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

revoke execute on function public.parse_answer_number(text) from public;
revoke execute on function public.parse_answer_number(text) from anon;
grant execute on function public.parse_answer_number(text) to authenticated, service_role;
