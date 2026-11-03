-- Retorno rápido ao cliente, F1 (sobe em sombra na seg 16/11/2026, a ÚLTIMA migration da leva): o cron
-- 'retorno-minuto', que põe o retorno para andar. Sobe por último de propósito: quando ele existir, todas as
-- funções que ele chama já existem.
--
-- K2 = a cada minuto, e o SQL decide antes de chamar a edge (incidente de 17/08: crons de WhatsApp a cada 30–60 s
-- chamando funções encheram net._http_response e cron.job_run_details até esgotar o crédito de CPU). Molde do job
-- 41 'comprovantes-vigia':
--   1. select public.retorno_vigia(now()) — só SQL, sem chamada de edge (disjuntor, áudio transcrito, respostas
--      humanas, fecho dos casos, relógio, acorde simulado, cadastro provisório, incertas, presos, rebaixamento e, às
--      04:00, arquivar, retenção e alongamento); cada passo isolado, nunca levanta;
--   2. net.http_post para a edge retorno-recibos SÓ quando public.retorno_tem_vencido(now()): há saída de texto
--      agendada e vencida, fora de reserva, com o retorno ligado ou em sombra. Sem trabalho, nenhuma chamada e
--      nenhuma linha em net._http_response. O cabeçalho x-cron-secret vem de app_settings.cron_worker_secret
--      (verificarCronSecret na edge, que falha fechado); timeout de 60 s (a rodada da edge para em 45 s).
-- Com o retorno desligado (retorno_config.modo = 'desligado'), o vigia sai na hora e retorno_tem_vencido é falso:
-- o minuto custa duas leituras de uma linha.
--
-- Medir a carga ANTES e DEPOIS (B.0, R1-24), pela sessão coordenadora, com a CLI (só leitura):
--   - a latência de uma consulta em memória (o sinal que provou o incidente de 17/08), 3 vezes, antes de subir e de
--     novo com o cron rodando há 1 h:
--       explain (analyze, buffers) select count(*) from public.app_settings;
--   - as linhas novas por hora (as limpezas jobid 20, 'purge-cron-history', e 21, 'purge-pgnet-responses', já
--     existem):
--       select count(*) from cron.job_run_details where start_time > now() - interval '1 hour';
--       select count(*) from net._http_response where created > now() - interval '1 hour';
--     Esperado com o cron: +60 linhas/h em cron.job_run_details; em net._http_response, só os minutos com saída
--     vencida (na sombra, ~1 por recibo).
--
-- A bancada rápida (P15) aplica esta migration dentro do begin … rollback (nada fica agendado); o replay nunca a
-- aplica.
--
-- Sem dado de negócio: só a linha do job em cron.job.
-- Reverter: select cron.unschedule(jobid) from cron.job where jobname = 'retorno-minuto';
-- (o retorno para de andar; as saídas agendadas ficam como estão). Sem deploy, parar sem tirar o cron:
-- update public.retorno_config set modo = 'desligado'.

-- O cron só sobe depois das funções que chama (falha fecha: sem elas, a migration para aqui).
do $$
begin
  if to_regprocedure('public.retorno_vigia(timestamptz)') is null
     or to_regprocedure('public.retorno_tem_vencido(timestamptz)') is null then
    raise exception 'retorno-minuto: retorno_vigia(timestamptz) ou retorno_tem_vencido(timestamptz) não existe; o cron sobe depois delas (20261116100700 e 20261116100800)';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'cron')
     or not exists (select 1 from pg_namespace where nspname = 'net') then
    raise exception 'retorno-minuto: pg_cron ou pg_net ausente';
  end if;
end $$;

select cron.unschedule(jobid) from cron.job where jobname = 'retorno-minuto';
select cron.schedule('retorno-minuto', '* * * * *', $c$
  select public.retorno_vigia(now());
  select net.http_post(
    url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/retorno-recibos',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-cron-secret', (select value::text from public.app_settings where key = 'cron_worker_secret' limit 1)),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000)
  where public.retorno_tem_vencido(now());
$c$);

-- Confere o que ficou agendado: um job só, ativo, com o vigia e a guarda antes da chamada.
do $$
begin
  if (select count(*) from cron.job
       where jobname = 'retorno-minuto'
         and schedule = '* * * * *'
         and active
         and command like '%public.retorno_vigia(now())%'
         and command like '%where public.retorno_tem_vencido(now())%'
         and command like '%/functions/v1/retorno-recibos%') <> 1 then
    raise exception 'retorno-minuto: o cron não ficou como esperado (um job, a cada minuto, com o vigia e a guarda)';
  end if;
end $$;
