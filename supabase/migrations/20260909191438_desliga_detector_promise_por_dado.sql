-- Recuperada do transcript da sessão (C--Users-PC/a12c77fb-6295-4d2c-86c2-da5fd7d7a34a.jsonl, 2026-09-09T19:14:50.903Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260909191438 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- Decisão operacional (audit/desligar-detector-promise.sql): detector 'promise' com 12%
-- de aceite (2/17); confiança do modelo não discrimina neste detector. Reversível:
-- trocar para 'true' religa. Mecanismo (agenda_detector_<tipo>_enabled) está no ar desde 28/08 (v13).
insert into public.app_settings (key, value)
values ('agenda_detector_promise_enabled', 'false')
on conflict (key) do update set value = excluded.value;
