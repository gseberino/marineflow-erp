-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- CRON NOVO — OK NOMEADO
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Secretário, Passo 3 (15/10/2026): o horário automático do turno da tarde do resumo.
-- Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-fechamento.md §2.
--
--   ai-daily-briefing-tarde · '30,40,50 20 * * 1-5' = 17:30, 17:40 e 17:50 de Brasília (UTC−3, sem horário de
--   verão desde 2019), de segunda a sexta. Chama a MESMA função da manhã com ?turno=tarde. A cada disparo a
--   função pergunta "já decidi hoje?" (a linha de hoje em resumo_tarde): a 2ª e a 3ª chamadas só existem para
--   esperar até 20 min quando o dono está no meio de uma conversa. Sábado, domingo e feriado: a função não
--   faz nada (o feriado é conferido nela, com o mesmo calendário da manhã).
--
-- Separada da migration do banco (20261015210000) de propósito: o cron só entra com o OK nomeado, depois de as
-- funções estarem publicadas. Com fechamento_formato = 'desligado' (como a chave nasce), cada chamada responde
-- "desligado" e não lê mais nada.
--
-- Mesmo padrão de chamada dos outros crons (ex.: jobid 6, ai-daily-briefing): net.http_post com o
-- x-cron-secret lido de app_settings.cron_worker_secret. Idempotente (desagenda o de mesmo nome antes).
-- Para tirar: select cron.unschedule('ai-daily-briefing-tarde');

do $$
begin
  if to_regclass('public.resumo_tarde') is null then
    raise exception 'aplique 20261015210000_resumo_tarde.sql antes do cron da tarde';
  end if;
  if exists (select 1 from cron.job where jobname = 'ai-daily-briefing-tarde') then
    perform cron.unschedule('ai-daily-briefing-tarde');
  end if;
  perform cron.schedule('ai-daily-briefing-tarde', '30,40,50 20 * * 1-5', $cron$
    SELECT net.http_post(
      url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-daily-briefing?turno=tarde',
      headers    := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
      ),
      body       := '{}'::jsonb,
      timeout_milliseconds := 55000
    );
  $cron$);
end $$;

-- Prova: um job só, com o horário e a URL certos.
do $$
begin
  if (select count(*) from cron.job where jobname = 'ai-daily-briefing-tarde') <> 1 then
    raise exception 'cron ai-daily-briefing-tarde não ficou com exatamente 1 job';
  end if;
  if not exists (select 1 from cron.job where jobname = 'ai-daily-briefing-tarde'
                    and schedule = '30,40,50 20 * * 1-5'
                    and position('ai-daily-briefing?turno=tarde' in command) > 0
                    and position('x-cron-secret' in command) > 0) then
    raise exception 'cron ai-daily-briefing-tarde com horário ou chamada diferente do previsto';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261015210100', 'resumo_tarde_cron')
on conflict do nothing;
