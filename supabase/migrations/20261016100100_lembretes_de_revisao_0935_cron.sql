-- CRON — OK NOMEADO. Secretário, Passo 4 ("uma voz só"), P4.4 (15/10/2026): os lembretes de revisão
-- (planos de manutenção e campanha de temporada, ter–qui) passam das 09:05 para as 09:35 de Brasília,
-- para não cair na janela da manhã (07:30–09:30: só a manhã do secretário pergunta).
-- Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md (§5)
--
-- Medido: 13/10 e 14/10 às 09:05, 35 minutos depois da manhã; os 4 cartões foram recusados.
--
-- Separada da migration do banco de propósito: mexe num cron de produção (jobid 36,
-- 'lembretes-de-revisao', '5 12 * * 2-4' conferido em produção em 15/10/2026). O cron não nasceu numa
-- migration (lembretes-de-revisao/index.ts:3-11); aqui só o horário muda, o comando fica igual.
-- ORDEM: aplicar ANTES de publicar a função lembretes-de-revisao nova (ela recusa rodar antes das 09:30
-- de Brasília; com o cron ainda às 09:05 os lembretes de ter–qui não sairiam).
-- Idempotente: já às 09:35 = nada; horário diferente dos dois = para e avisa. Banco sem o job (ambiente
-- local, sem o cron de produção) = nada.

do $$
declare
  v_job   bigint;
  v_hora  text;
begin
  if not exists (select 1 from pg_namespace where nspname = 'cron') then
    raise notice 'sem pg_cron neste banco: nada a mudar';
    return;
  end if;
  select j.jobid, j.schedule into v_job, v_hora from cron.job j where j.jobname = 'lembretes-de-revisao';
  if v_job is null then
    raise notice 'o cron lembretes-de-revisao não existe neste banco: nada a mudar';
    return;
  end if;
  if v_hora = '35 12 * * 2-4' then
    return;
  end if;
  if v_hora <> '5 12 * * 2-4' then
    raise exception 'o cron lembretes-de-revisao está em "%", não em "5 12 * * 2-4": confira antes de mudar', v_hora;
  end if;
  perform cron.alter_job(job_id := v_job, schedule := '35 12 * * 2-4');
end $$;

-- Prova: se o job existe, está às 09:35 (12:35 UTC) de terça a quinta, ativo como antes.
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron')
     and exists (select 1 from cron.job j where j.jobname = 'lembretes-de-revisao')
     and not exists (select 1 from cron.job j where j.jobname = 'lembretes-de-revisao' and j.schedule = '35 12 * * 2-4') then
    raise exception 'o cron lembretes-de-revisao não ficou às 09:35';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261016100100', 'lembretes_de_revisao_0935_cron')
on conflict do nothing;
