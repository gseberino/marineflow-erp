-- Repescagem diária de áudio: a segunda tentativa que não existia.
--
-- POR QUE, com os números que motivaram (medidos em 24-25/09/2026):
--
-- A mídia do WhatsApp expira no Evolution em cerca de DUAS SEMANAS. Testado áudio a áudio,
-- semana a semana: de 14/09 em diante o Evolution devolve; de 07/09 para trás responde
-- "Message not found". A transcrição no webhook é fire-and-forget (não pode atrasar o
-- recebimento da mensagem), então ela falha em silêncio — Evolution caído, Groq fora,
-- túnel oscilando. Sem uma segunda passada, cada falha vira um buraco PERMANENTE no
-- histórico assim que essa janela fecha.
--
-- Não é hipótese: o Evolution ficou 4h30 fora do ar em 24/09/2026, e o acervo tinha 700
-- áudios velhos demais para recuperar. Os 88 que ainda estavam dentro da janela foram
-- transcritos na mão em 25/09; este cron existe para não haver uma próxima leva.
--
-- 04:10 da manhã: fora do horário de uso, junto das outras rotinas de manutenção, e com
-- folga para o dia inteiro de mensagens ter passado.

select cron.schedule(
  'whatsapp-repescar-audios',
  '10 4 * * *',
  $$
  SELECT net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/whatsapp-repescar-audios',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (SELECT value::text FROM app_settings WHERE key = 'cron_worker_secret' LIMIT 1)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 180000
  );
  $$
);
