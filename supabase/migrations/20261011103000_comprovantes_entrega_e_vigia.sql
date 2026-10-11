-- Comprovantes F1 (11/10/2026): entrega pelo gatilho de ai_jobs e vigia de 2 em 2 minutos.
--
--   * Gatilho ai_jobs_comprovante_lido: o job de leitura (metadata.tipo = 'comprovante_leitura')
--     terminou → POST comprovantes-whatsapp {acao:'entrega', job_id} (porta x-cron-secret).
--     Função própria: não toca no gatilho do Max (ai_jobs_entregar_turno).
--   * pg_cron 'comprovantes-vigia' (*/2): rebaixa mídia, reenfileira uma vez, entrega o que o
--     gatilho perdeu, Dropbox com backoff, apaga originais vencidos, avisa o que esperou demais,
--     expurga leitura_texto de 90 dias. Com tudo parado, NENHUMA chamada HTTP (a guarda
--     _comprovantes_vigia_tem_trabalho decide antes).
--
--   * Manutenção só de banco (_comprovantes_manutencao) roda no PRÓPRIO comando do pg_cron, antes
--     da guarda: o expurgo de 90 dias do texto do OCR e a limpeza do job (texto do OCR e URL
--     assinada) não dependem de a edge estar no ar.
--
-- EMERGÊNCIA: 'off' em app_settings.comprovante_fluxo só muda o que CHEGA depois; o que já está em
-- andamento termina pelo modo gravado na linha (avisos, encaminhamentos, Dropbox). Para calar tudo
-- na hora, sem deploy (com o OK do dono):
--   select cron.unschedule('comprovantes-vigia');
--   alter table public.ai_jobs disable trigger ai_jobs_comprovante_lido;
-- e para voltar: rodar esta migration de novo (ela reagenda o cron) e
--   alter table public.ai_jobs enable trigger ai_jobs_comprovante_lido;
--
-- GRAVA DADO — OK NOMEADO: um job em cron.job ('comprovantes-vigia'). Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. Gatilho de entrega
-- ---------------------------------------------------------------------------------------------
create or replace function public._ai_jobs_comprovante_lido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.metadata->>'tipo' = 'comprovante_leitura'
     and new.status in ('completed', 'failed', 'cancelled')
     and old.status is distinct from new.status then
    begin
      perform net.http_post(
        url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/comprovantes-whatsapp',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select s.value::text from public.app_settings s where s.key = 'cron_worker_secret')),
        body := jsonb_build_object('acao', 'entrega', 'job_id', new.id),
        timeout_milliseconds := 60000
      );
    exception when others then
      -- o vigia entrega o que o gatilho perder (job final há 2 min sem entregue_em)
      raise warning 'comprovantes: falha ao pedir a entrega da leitura %: %', new.id, sqlerrm;
    end;
  end if;
  return null;
end $$;

drop trigger if exists ai_jobs_comprovante_lido on public.ai_jobs;
create trigger ai_jobs_comprovante_lido
  after update of status on public.ai_jobs
  for each row execute function public._ai_jobs_comprovante_lido();

-- ---------------------------------------------------------------------------------------------
-- 2. Guarda do vigia: as mesmas condições das listas de comprovantes_vigia_lote
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovantes_vigia_tem_trabalho()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    -- expurgo do texto do OCR
    exists (select 1 from public.comprovantes x
             where x.leitura_texto is not null and x.lido_em < now() - interval '90 days')
    -- baixar, e a rede de segurança (recebido há 1 h sem desfecho)
    or exists (select 1 from public.comprovantes x
                where x.situacao = 'recebido'
                  and (x.created_at < now() - interval '1 hour'
                       or (x.arquivo_path is null
                           and (x.download_proxima_em <= now()
                                or (x.download_proxima_em is null and x.created_at < now() - interval '5 minutes')))))
    -- entregar (o gatilho perdeu) e reenfileirar
    or exists (select 1 from public.comprovantes x
                 join public.ai_jobs j on j.id = x.job_id
                where x.situacao = 'na_fila'
                  and j.status in ('completed', 'failed', 'cancelled')
                  and ((coalesce(j.completed_at, j.updated_at) < now() - interval '2 minutes' and not (j.metadata ? 'entregue_em'))
                       or (j.status = 'failed' and j.error_code in ('deadline_exceeded', 'input_unavailable')
                           and j.metadata ? 'entregue_em' and not x.reenfileirado and x.arquivo_apagado_em is null)))
    -- Dropbox
    or exists (select 1 from public.comprovantes x
                where x.numero is not null and x.dropbox_id is null and x.situacao in ('lido', 'falhou')
                  and x.dropbox_tentativas < 5 and x.dropbox_proxima_em <= now())
    -- apagar original vencido (nunca de CMP vivo)
    or exists (select 1 from public.comprovantes x
                where x.arquivo_apagar_apos <= now() and x.arquivo_apagado_em is null and x.arquivo_path is not null
                  and not (x.numero is not null and x.situacao <> 'cancelado'))
    -- aviso que esperou 10 min ou mais
    or exists (select 1 from public.comprovantes x
                where x.modo = 'dono' and x.avisado_em is null and x.recebido_em <= now() - interval '10 minutes'
                  and (x.aviso_proximo_em is null or x.aviso_proximo_em <= now())
                  and ((x.situacao in ('lido', 'falhou') and x.numero is not null)
                       or (x.situacao = 'cancelado' and x.motivo_cancelamento in ('arquivo_repetido', 'chave_repetida'))
                       or (x.situacao = 'falhou' and x.forcado and x.numero is null)));
$$;

-- ---------------------------------------------------------------------------------------------
-- 3. Manutenção só de banco, chamada pelo próprio pg_cron (não depende da edge)
--    * leitura_texto (OCR bruto, pode ter CPF) some aos 90 dias (decisão 11);
--    * job de leitura terminado há mais de 1 h perde o texto do OCR (response.data.texto) e a URL
--      assinada (input.arquivo.url), mesmo que a entrega nunca aconteça. Não toca status (nenhum
--      gatilho de status redispara). Falha aqui vira aviso, nunca derruba o comando do cron.
-- ---------------------------------------------------------------------------------------------
create or replace function public._comprovantes_manutencao()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_a integer := 0;
  v_b integer := 0;
begin
  begin
    update public.comprovantes x set leitura_texto = null
     where x.leitura_texto is not null and x.lido_em < now() - interval '90 days';
    get diagnostics v_a = row_count;

    update public.ai_jobs j
       set response = case when jsonb_typeof(j.response->'data') = 'object' and (j.response->'data') ? 'texto'
                           then jsonb_set(j.response, '{data}', (j.response->'data') #- '{texto}')
                           else j.response end,
           input = case when jsonb_typeof(j.input->'arquivo') = 'object' and (j.input->'arquivo') ? 'url'
                        then j.input #- '{arquivo,url}'
                        else j.input end
     where j.metadata->>'tipo' = 'comprovante_leitura'
       and j.status in ('completed', 'failed', 'cancelled')
       and coalesce(j.completed_at, j.updated_at) < now() - interval '1 hour'
       and ((jsonb_typeof(j.response->'data') = 'object' and (j.response->'data') ? 'texto')
            or (jsonb_typeof(j.input->'arquivo') = 'object' and (j.input->'arquivo') ? 'url'));
    get diagnostics v_b = row_count;
  exception when others then
    raise warning 'comprovantes: manutenção do vigia falhou: %', sqlstate;
  end;
  return v_a + v_b;
end $$;

revoke all on function public._ai_jobs_comprovante_lido() from public, anon, authenticated;
revoke all on function public._comprovantes_vigia_tem_trabalho() from public, anon, authenticated;
revoke all on function public._comprovantes_manutencao() from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 4. pg_cron 'comprovantes-vigia' (*/2): a manutenção de banco sempre; a edge só se houver trabalho
-- ---------------------------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    if exists (select 1 from cron.job where jobname = 'comprovantes-vigia') then
      perform cron.unschedule('comprovantes-vigia');
    end if;
    perform cron.schedule('comprovantes-vigia', '*/2 * * * *', $cron$
      select public._comprovantes_manutencao();
      select net.http_post(
        url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/comprovantes-whatsapp',
        headers := jsonb_build_object('Content-Type', 'application/json',
          'x-cron-secret', (select value::text from public.app_settings where key = 'cron_worker_secret' limit 1)),
        body := '{"acao":"vigiar"}'::jsonb,
        timeout_milliseconds := 60000)
      where public._comprovantes_vigia_tem_trabalho();
    $cron$);
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Prova
-- ---------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'ai_jobs_comprovante_lido' and tgrelid = 'public.ai_jobs'::regclass) then
    raise exception 'gatilho de entrega dos comprovantes não foi criado';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'ai_jobs_entregar_turno' and tgrelid = 'public.ai_jobs'::regclass) then
    raise exception 'o gatilho de entrega do Max sumiu';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'cron')
     and not exists (select 1 from cron.job where jobname = 'comprovantes-vigia' and schedule = '*/2 * * * *') then
    raise exception 'cron comprovantes-vigia não foi agendado';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'cron')
     and not exists (select 1 from cron.job where jobname = 'comprovantes-vigia'
                        and command like '%_comprovantes_manutencao()%') then
    raise exception 'cron comprovantes-vigia sem a manutenção de banco';
  end if;
  if has_function_privilege('anon', 'public._ai_jobs_comprovante_lido()', 'execute')
     or has_function_privilege('authenticated', 'public._ai_jobs_comprovante_lido()', 'execute')
     or has_function_privilege('anon', 'public._comprovantes_vigia_tem_trabalho()', 'execute')
     or has_function_privilege('authenticated', 'public._comprovantes_vigia_tem_trabalho()', 'execute')
     or has_function_privilege('anon', 'public._comprovantes_manutencao()', 'execute')
     or has_function_privilege('authenticated', 'public._comprovantes_manutencao()', 'execute') then
    raise exception 'função do gatilho/vigia dos comprovantes exposta';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011103000', 'comprovantes_entrega_e_vigia')
on conflict do nothing;
