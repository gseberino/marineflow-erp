-- Assistente do WhatsApp pela assinatura Claude Max do dono (03/10/2026), alternável com o OpenRouter.
--
-- Chave: app_settings.ai_provedor_whatsapp = 'claude_max' | 'openrouter' (nasce 'openrouter': esta
-- migration não muda o comportamento de ninguém). No modo Max o ai-agent enfileira o turno em
-- ai_jobs (tipo 'agente_whatsapp'); o HBR AI Gateway roda o Claude Code com as ferramentas do ERP
-- pela edge erp-mcp; ao terminar, o gatilho daqui chama o ai-agent para responder no WhatsApp
-- ou, se o Max falhou, refazer o turno pelo OpenRouter.
--
-- Só o admin (o dono) vai pelo Max — termos da Anthropic: assinatura é para uso individual.
-- Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. O gateway diz se está disponível (a edge decide antes de enfileirar)
-- ---------------------------------------------------------------------------------------------
alter table public.ai_gateway_workers add column if not exists estado jsonb;
comment on column public.ai_gateway_workers.estado is
  'Último estado informado pelo worker no ping: providers (disponível/pausa até/motivo), jobs ativos e máximo.';

-- Nova assinatura (p_estado). A antiga sai: com as duas, a chamada por nome ficaria ambígua no PostgREST.
drop function if exists public.ai_gateway_ping(text, text, text);
create or replace function public.ai_gateway_ping(
  p_worker_id text,
  p_token text,
  p_version text default null,
  p_estado jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w public.ai_gateway_workers;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  update public.ai_gateway_workers
     set last_seen_at = now(),
         version = coalesce(left(p_version, 64), version),
         estado = case
           when p_estado is not null and jsonb_typeof(p_estado) = 'object' and octet_length(p_estado::text) <= 4000 then p_estado
           else estado end
   where id = w.id;
  return jsonb_build_object(
    'ok', true,
    'worker_id', w.id,
    'allowed_sources', to_jsonb(w.allowed_sources),
    'server_time', now(),
    'pending', (select count(*) from public.ai_jobs j
                 where j.status = 'pending' and j.source = any (w.allowed_sources)),
    'processing', (select count(*) from public.ai_jobs j
                    where j.status = 'processing' and j.worker_id = w.id)
  );
end $$;

-- O Max só é escolhido se algum worker falou nos últimos 45 s E disse que o claude-local está livre
-- (sem pausa por limite da assinatura ou login). Worker antigo, sem estado: indisponível (falha segura).
create or replace function public.ai_claude_max_disponivel()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.ai_gateway_workers w
     where w.enabled
       and w.last_seen_at > now() - interval '45 seconds'
       and coalesce((w.estado->'providers'->'claude-local'->>'available')::boolean, false)
  );
$$;

-- ---------------------------------------------------------------------------------------------
-- 2. Registro atômico do que o erp-mcp executou (duas chamadas em paralelo não se apagam).
--    'agente_ensaio' = o mesmo turno, sem entrega no WhatsApp (o gatilho só olha agente_whatsapp).
-- ---------------------------------------------------------------------------------------------
create or replace function public.ai_job_registrar_ferramenta(
  p_job_id uuid,
  p_nome text,
  p_interrupcao jsonb default null
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  atual jsonb;
  novo jsonb;
begin
  select j.metadata into atual
    from public.ai_jobs j
   where j.id = p_job_id and j.status = 'processing' and j.metadata->>'tipo' in ('agente_whatsapp', 'agente_ensaio')
   for update;
  if not found then
    return false;
  end if;

  novo := atual;
  -- A interrupção (pendência/opções) é o que importa: a primeira vence, e nunca fica de fora.
  if p_interrupcao is not null and jsonb_typeof(p_interrupcao) = 'object' and not (atual ? 'interrupcao') then
    novo := novo || jsonb_build_object('interrupcao', p_interrupcao);
  end if;
  -- A lista de ferramentas é diagnóstico: entra só se couber no limite do metadata.
  if octet_length((novo || jsonb_build_object('ferramentas_usadas',
        coalesce(novo->'ferramentas_usadas', '[]'::jsonb) || to_jsonb(left(coalesce(p_nome, ''), 80))))::text) <= 18000 then
    novo := novo || jsonb_build_object('ferramentas_usadas',
              coalesce(novo->'ferramentas_usadas', '[]'::jsonb) || to_jsonb(left(coalesce(p_nome, ''), 80)));
  end if;

  update public.ai_jobs j set metadata = novo where j.id = p_job_id;
  return novo ? 'interrupcao';
end $$;

-- Entrega uma vez só: devolve true só para a primeira chamada depois que o job terminou.
create or replace function public.ai_job_marcar_entregue(p_job_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.ai_jobs j
     set metadata = j.metadata || jsonb_build_object('entregue_em', now())
   where j.id = p_job_id
     and j.metadata->>'tipo' = 'agente_whatsapp'
     and j.status in ('completed', 'failed', 'cancelled')
     and not (j.metadata ? 'entregue_em');
  return found;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Entrega: o job do turno terminou → ai-agent responde (ou refaz pelo OpenRouter)
-- ---------------------------------------------------------------------------------------------
create or replace function public._ai_jobs_entregar_turno()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.metadata->>'tipo' = 'agente_whatsapp'
     and new.status in ('completed', 'failed', 'cancelled')
     and old.status is distinct from new.status then
    begin
      perform net.http_post(
        url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/ai-agent',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select s.value::text from public.app_settings s where s.key = 'cron_worker_secret')),
        body := jsonb_build_object('type', 'entregar_turno_max', 'job_id', new.id),
        timeout_milliseconds := 120000
      );
    exception when others then
      raise warning 'ai_jobs: falha ao pedir a entrega do turno %: %', new.id, sqlerrm;
    end;
  end if;
  return null;
end $$;

drop trigger if exists ai_jobs_entregar_turno on public.ai_jobs;
create trigger ai_jobs_entregar_turno
  after update of status on public.ai_jobs
  for each row execute function public._ai_jobs_entregar_turno();

-- ---------------------------------------------------------------------------------------------
-- 4. Relógio: sem worker no ar ninguém chama o reaper; o banco chama a cada minuto. Job do
--    WhatsApp que passou do prazo (75 s sem ser pego) vira 'failed' e a entrega refaz pelo
--    OpenRouter; lease vencida volta à fila ou falha, como no reaper do próprio worker.
-- ---------------------------------------------------------------------------------------------
do $$
begin
  perform cron.unschedule(j.jobid) from cron.job j where j.jobname = 'ai-gateway-relogio';
  perform cron.schedule('ai-gateway-relogio', '* * * * *', 'select public._ai_gateway_reap()');
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. As chaves (nascem desligadas: o WhatsApp segue no OpenRouter até alguém virar a chave)
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('ai_provedor_whatsapp', 'openrouter',
   'Quem atende o assistente no WhatsApp: claude_max (assinatura Claude do dono pelo HBR AI Gateway; só o admin) ou openrouter.'),
  ('ai_whatsapp_max_modelo', 'sonnet',
   'Modelo do Claude Max no WhatsApp: haiku, sonnet ou opus.'),
  ('ai_whatsapp_max_reserva', 'on',
   'Se o Claude Max falhar (PC desligado, limite da assinatura, erro), refaz o turno pelo OpenRouter (on) ou só avisa (off).')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------------------------
-- Privilégios
-- ---------------------------------------------------------------------------------------------
revoke all on function public.ai_gateway_ping(text, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.ai_gateway_ping(text, text, text, jsonb) to anon, service_role;
revoke all on function public.ai_claude_max_disponivel() from public, anon, authenticated;
grant execute on function public.ai_claude_max_disponivel() to service_role;
revoke all on function public.ai_job_registrar_ferramenta(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.ai_job_registrar_ferramenta(uuid, text, jsonb) to service_role;
revoke all on function public.ai_job_marcar_entregue(uuid) from public, anon, authenticated;
grant execute on function public.ai_job_marcar_entregue(uuid) to service_role;
revoke all on function public._ai_jobs_entregar_turno() from public, anon, authenticated;

do $$
begin
  if has_function_privilege('anon', 'public.ai_claude_max_disponivel()', 'execute')
     or has_function_privilege('authenticated', 'public.ai_claude_max_disponivel()', 'execute')
     or has_function_privilege('anon', 'public.ai_job_registrar_ferramenta(uuid, text, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.ai_job_registrar_ferramenta(uuid, text, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.ai_job_marcar_entregue(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ai_job_marcar_entregue(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ai_gateway_ping(text, text, text, jsonb)', 'execute') then
    raise exception 'função do WhatsApp pelo Claude Max exposta além do previsto';
  end if;
  if not has_function_privilege('anon', 'public.ai_gateway_ping(text, text, text, jsonb)', 'execute') then
    raise exception 'o worker (anon + token) perdeu o ping';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'ai_jobs_entregar_turno' and tgrelid = 'public.ai_jobs'::regclass) then
    raise exception 'gatilho de entrega não foi criado';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261003233000', 'whatsapp_claude_max')
on conflict do nothing;
