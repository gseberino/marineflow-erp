-- ─────────────────────────────────────────────────────────────────────────────
-- Desliga o detector 'promise' da Caixa de Entrada da Agenda.
--
-- NÃO é migration: é uma decisão operacional, reversível por dado, que vive em
-- app_settings. Rodar SÓ depois do deploy do commit que criou o mecanismo
-- (agenda_detector_<tipo>_enabled) — antes disso a chave existe e não faz nada.
--
-- POR QUE: 2 aceitas em 17 decididas (12%). A confiança auto-declarada pelo modelo
-- não discrimina neste detector — descartadas com média 0.88 contra aceitas 0.93, e
-- 4 descartadas em 0.95 —, então subir o limiar cortaria as aceitas junto.
--
-- PARA RELIGAR: troque 'false' por 'true' (ou apague a linha; ausente = ligado).
-- ─────────────────────────────────────────────────────────────────────────────

insert into public.app_settings (key, value)
values ('agenda_detector_promise_enabled', 'false')
on conflict (key) do update set value = excluded.value;

-- Conferência: deve devolver exatamente uma linha, com 'false'.
select key, value from public.app_settings
where key like 'agenda_detector_%_enabled';

-- Depois do próximo tick (de hora em hora, aos :20), a resposta da function passa a
-- trazer barradas_por_detector_desligado > 0 e 'promise' fora de detectores_ligados.
-- Se vier 0 por vários ticks, o detector simplesmente não estava propondo nada — não
-- é sinal de que a flag falhou.
