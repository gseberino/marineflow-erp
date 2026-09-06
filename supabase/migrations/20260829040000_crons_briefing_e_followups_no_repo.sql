-- ─────────────────────────────────────────────────────────────────────────────
-- Traz para o repositório dois crons que só existiam no banco.
--
-- `ai-daily-briefing` (jobid 6) e `ai-whatsapp-followups` (jobid 7) foram agendados
-- direto em produção e nunca tiveram migration. O repo, portanto, não descreve o
-- sistema: quem restaurar o banco de um dump limpo, criar um branch do Supabase ou
-- montar um ambiente novo fica SEM o resumo matinal das 07:30 e sem as réguas de
-- follow-up — e não há nada no código que denuncie a ausência.
--
-- POR QUE É CONDICIONAL, e não o `unschedule` + `schedule` do padrão mais recente:
-- o objetivo aqui é o repo passar a DESCREVER o que já existe, não reagendar nada.
-- `cron.unschedule` seguido de `cron.schedule` recria o job com um jobid novo, e os
-- comentários no código das duas functions citam os jobids 6 e 7 nominalmente. Como
-- em produção os dois já rodam com exatamente o comando abaixo (copiado da coluna
-- `command` de `cron.job` em 29/08/2026), aqui a migration é no-op; num banco onde
-- não existam, ela cria. É idempotente nos dois sentidos.
--
-- ⚠️ Consequência assumida: se alguém alterar o schedule DESTE arquivo, a mudança não
-- se propaga para um banco onde o job já exista. Para mudar de verdade um cron vivo,
-- use uma migration nova com `unschedule` + `schedule` (padrão de
-- 20260808150000_cron_reconciliacao_de_custo.sql).
-- ─────────────────────────────────────────────────────────────────────────────

-- Resumo matinal (07:30 BRT = 10:30 UTC). Manda WhatsApp para a equipe: agenda do dia,
-- quem está esperando resposta, orçamentos parados, recebíveis e saúde do negócio.
select cron.schedule(
  'ai-daily-briefing',
  '30 10 * * *',
  $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-daily-briefing',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
  $cron$
)
where not exists (select 1 from cron.job where jobname = 'ai-daily-briefing');

-- Follow-ups com CLIENTE (pós-atendimento D+2..D+7 e reativação >6 meses).
-- ⚠️ Esta função MANDA MENSAGEM REAL para cliente quando wa_test_mode está desligado.
-- O volume é contido pelo dedupe em ai_operator_alerts_log, não por estar parada.
select cron.schedule(
  'ai-whatsapp-followups',
  '*/30 * * * *',
  $cron$
  SELECT net.http_post(
    url        := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-whatsapp-followups',
    headers    := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body       := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $cron$
)
where not exists (select 1 from cron.job where jobname = 'ai-whatsapp-followups');
