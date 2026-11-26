-- CRON — OK NOMEADO. Cobrança, fatia 5a (dono, 26/11/2026: "2. A" — o lembrete 3 dias antes do vencimento passa a pedir o
-- "sim" dele). A rotina receivable-reminders deixa de mandar ao cliente: prepara os lembretes e pergunta ao dono no
-- WhatsApp (receivable-reminders/index.ts e propor.ts). Por isso ela sai das 08:00 de Brasília (dentro da janela da manhã,
-- 07:30–09:30, em que só a manhã do secretário pergunta) e passa a rodar às 10:40 e às 15:40 (13:40 e 18:40 UTC): a
-- segunda rodada pega o que a primeira não pôde perguntar (dono ocupado com outra confirmação).
--
-- Só o horário muda; o comando fica igual. O cron não nasceu numa migration com este nome (jobname
-- 'receivable-reminders-daily', '0 11 * * *', jobid 10, conferido em produção em 26/11/2026).
-- ORDEM: publicar a função receivable-reminders nova ANTES ou junto (a nova recusa rodar antes das 09:30; a antiga, às
-- 10:40, mandaria sozinha ao cliente como antes — por isso a função vai primeiro).
-- Idempotente: já em '40 13,18 * * *' = nada; horário diferente dos dois = para e avisa. Banco sem pg_cron ou sem o job
-- (ambiente local) = nada.

do $$
declare
  v_job   bigint;
  v_hora  text;
begin
  if not exists (select 1 from pg_namespace where nspname = 'cron') then
    raise notice 'sem pg_cron neste banco: nada a mudar';
    return;
  end if;
  select j.jobid, j.schedule into v_job, v_hora from cron.job j where j.jobname = 'receivable-reminders-daily';
  if v_job is null then
    raise notice 'o cron receivable-reminders-daily não existe neste banco: nada a mudar';
    return;
  end if;
  if v_hora = '40 13,18 * * *' then
    return;
  end if;
  if v_hora <> '0 11 * * *' then
    raise exception 'o cron receivable-reminders-daily está em "%", não em "0 11 * * *": confira antes de mudar', v_hora;
  end if;
  perform cron.alter_job(job_id := v_job, schedule := '40 13,18 * * *');
end $$;

-- Prova: se o job existe, está às 10:40 e 15:40 de Brasília, ativo como antes.
do $$
declare
  v_hora  text;
  v_ativo boolean;
begin
  if not exists (select 1 from pg_namespace where nspname = 'cron') then
    return;
  end if;
  select j.schedule, j.active into v_hora, v_ativo from cron.job j where j.jobname = 'receivable-reminders-daily';
  if v_hora is null then
    return;
  end if;
  if v_hora <> '40 13,18 * * *' or v_ativo is not true then
    raise exception 'prova: receivable-reminders-daily ficou em "%" (ativo=%)', v_hora, v_ativo;
  end if;
end $$;
