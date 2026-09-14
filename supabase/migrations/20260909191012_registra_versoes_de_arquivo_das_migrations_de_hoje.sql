-- Recuperada do transcript da sessão (C--Users-PC/a12c77fb-6295-4d2c-86c2-da5fd7d7a34a.jsonl, 2026-09-09T19:10:25.353Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260909191012 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Convergência de registro: as 4 migrations aplicadas em 09/09/2026 via MCP receberam
-- timestamp próprio do MCP; aqui registramos TAMBÉM as versões dos arquivos do repo,
-- para que um futuro `db push` não tente reexecutá-las (mesmo padrão da Saída A de 11/08).
insert into supabase_migrations.schema_migrations (version, name) values
  ('20260828110000', 'agenda_suggestions_quote_request_entity'),
  ('20260829040000', 'crons_briefing_e_followups_no_repo'),
  ('20260831090000', 'fio_solto_ganha_direcao'),
  ('20260729210000', 'dedupe_extrato_manual_x_pluggy')
on conflict (version) do nothing;
