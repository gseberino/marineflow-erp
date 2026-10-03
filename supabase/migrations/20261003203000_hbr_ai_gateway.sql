-- HBR AI Gateway: fila ai_jobs para o worker local que roda o Claude pela assinatura do dono (03/10/2026).
--
-- Fluxo
--   MarineFlow (só o admin) -> ai_job_submit() -> ai_jobs 'pending'
--   worker local (chave anon + token próprio) -> ai_gateway_claim_job() -> 'processing'
--     -> ai_gateway_complete_job() 'completed' | ai_gateway_fail_job() 'pending' (retry) / 'failed' / 'cancelled'
--   MarineFlow lê o resultado na própria linha (RLS: só quem pediu) e pode ouvir pelo Realtime.
--
-- Segurança
--   * Ninguém escreve direto em ai_jobs: anon não tem nada; authenticated só lê os próprios jobs.
--   * O worker NÃO usa service_role: entra como anon e só alcança as funções ai_gateway_*, que exigem
--     o token dele (aqui fica só o sha256). Sem o token, nada; com o token, só a fila.
--   * Claim atômico (FOR UPDATE SKIP LOCKED) + lease renovada por heartbeat. Cada claim gera um
--     lease_id novo e toda transição confere worker_id + lease_id: um worker atrasado (lease vencida,
--     job já repassado) não consegue gravar resultado por cima do outro.
--   * A campainha do Realtime (tópico público 'ai-gateway:wake') só avisa "tem job" — não leva conteúdo.
--     Se o Realtime falhar, o worker continua pelo polling.
--
-- Idempotente: pode ser reaplicada.

-- ---------------------------------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------------------------------

create table if not exists public.ai_jobs (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  available_at        timestamptz not null default now(),   -- não roda antes disso (backoff / limite de uso)
  deadline_at         timestamptz,                          -- se não começou até aqui, falha (pedido interativo)
  started_at          timestamptz,
  completed_at        timestamptz,
  status              text not null default 'pending',
  source              text not null default 'marineflow',
  requested_by        uuid references auth.users(id) on delete set null,
  provider            text not null default 'claude-local', -- provider pedido
  model               text not null default 'sonnet',       -- nível pedido: haiku | sonnet | opus
  task_profile        text not null default 'text',         -- perfil LOCAL do gateway (ferramentas); o job só escolhe o nome
  response_format     text not null default 'text',
  json_schema         jsonb,
  system_prompt       text,
  prompt              text not null,
  input               jsonb,
  response            jsonb,
  error               text,
  error_code          text,
  metadata            jsonb not null default '{}'::jsonb,
  priority            smallint not null default 0,          -- maior roda primeiro
  attempts            smallint not null default 0,
  max_attempts        smallint not null default 3,
  timeout_seconds     integer not null default 300,
  allow_fallback      boolean not null default false,       -- autoriza outro provider legítimo se o pedido estiver indisponível
  worker_id           text,
  lease_id            uuid,
  lease_expires_at    timestamptz,
  cancel_requested_at timestamptz,
  provider_used       text,
  model_used          text,                                 -- id real do modelo que respondeu
  duration_ms         integer,
  usage               jsonb,
  constraint ai_jobs_status_chk check (status in ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  constraint ai_jobs_response_format_chk check (response_format in ('text', 'json', 'json_schema')),
  constraint ai_jobs_json_schema_chk check (
    (response_format <> 'json_schema' or json_schema is not null)
    and (json_schema is null or jsonb_typeof(json_schema) = 'object')
  ),
  constraint ai_jobs_source_chk check (source ~ '^[a-z0-9][a-z0-9_-]{0,31}$'),
  constraint ai_jobs_provider_chk check (provider ~ '^[a-z0-9][a-z0-9-]{0,31}$'),
  constraint ai_jobs_model_chk check (model ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  constraint ai_jobs_task_profile_chk check (task_profile ~ '^[a-z0-9][a-z0-9_-]{0,31}$'),
  constraint ai_jobs_prompt_chk check (char_length(prompt) between 1 and 200000),
  constraint ai_jobs_system_prompt_chk check (system_prompt is null or char_length(system_prompt) <= 50000),
  constraint ai_jobs_input_chk check (input is null or octet_length(input::text) <= 1000000),
  constraint ai_jobs_metadata_chk check (jsonb_typeof(metadata) = 'object' and octet_length(metadata::text) <= 20000),
  constraint ai_jobs_priority_chk check (priority between -100 and 100),
  constraint ai_jobs_attempts_chk check (attempts >= 0 and max_attempts between 1 and 10),
  constraint ai_jobs_timeout_chk check (timeout_seconds between 10 and 3600)
);

comment on table public.ai_jobs is
  'Fila de jobs de IA do MarineFlow executados pelo HBR AI Gateway local. Escrita só pelas funções ai_job_* e ai_gateway_*.';

create index if not exists ai_jobs_fila_idx
  on public.ai_jobs (priority desc, available_at, created_at) where status = 'pending';
create index if not exists ai_jobs_em_execucao_idx
  on public.ai_jobs (lease_expires_at) where status = 'processing';
create index if not exists ai_jobs_quem_pediu_idx
  on public.ai_jobs (requested_by, created_at desc);

create table if not exists public.ai_gateway_workers (
  id              text primary key,
  token_hash      text not null,                               -- sha256 (hex) do token; o token só existe no .env do PC
  enabled         boolean not null default true,
  allowed_sources text[] not null default array['marineflow'],
  created_at      timestamptz not null default now(),
  last_seen_at    timestamptz,
  version         text,
  constraint ai_gateway_workers_id_chk check (id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$'),
  constraint ai_gateway_workers_hash_chk check (token_hash ~ '^[0-9a-f]{64}$')
);

comment on table public.ai_gateway_workers is
  'Workers autorizados do HBR AI Gateway. Guarda só o sha256 do token. Sem policy: ninguém lê pela API.';

-- ---------------------------------------------------------------------------------------------
-- Gatilhos: updated_at e campainha do Realtime
-- ---------------------------------------------------------------------------------------------

create or replace function public._ai_jobs_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists ai_jobs_touch on public.ai_jobs;
create trigger ai_jobs_touch
  before update on public.ai_jobs
  for each row execute function public._ai_jobs_touch();

create or replace function public._ai_jobs_campainha()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if tg_op = 'INSERT' and new.status = 'pending' then
      perform realtime.send('{}'::jsonb, 'wake', 'ai-gateway:wake', false);
    elsif tg_op = 'UPDATE' and new.status = 'processing'
          and new.cancel_requested_at is not null and old.cancel_requested_at is null then
      perform realtime.send(jsonb_build_object('job_id', new.id), 'cancel', 'ai-gateway:wake', false);
    end if;
  exception when others then
    null; -- a campainha é só atalho: o worker também faz polling e heartbeat
  end;
  return null;
end $$;

drop trigger if exists ai_jobs_campainha on public.ai_jobs;
create trigger ai_jobs_campainha
  after insert or update of cancel_requested_at on public.ai_jobs
  for each row execute function public._ai_jobs_campainha();

-- ---------------------------------------------------------------------------------------------
-- API do worker (anon + token). Nada aqui confia em dado do job para decidir permissão.
-- ---------------------------------------------------------------------------------------------

create or replace function public._ai_gateway_auth(p_worker_id text, p_token text)
returns public.ai_gateway_workers
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  w public.ai_gateway_workers;
begin
  select * into w
    from public.ai_gateway_workers g
   where g.id = p_worker_id
     and g.enabled
     and g.token_hash = encode(extensions.digest(convert_to(coalesce(p_token, ''), 'UTF8'), 'sha256'), 'hex');
  if not found then
    raise exception 'ai_gateway: worker não autorizado' using errcode = '28000';
  end if;
  return w;
end $$;

-- Devolve à fila (ou encerra) jobs cujo worker sumiu, e vence os pendentes com prazo estourado.
create or replace function public._ai_gateway_reap()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  n integer;
begin
  with vencidos as (
    select j.id
      from public.ai_jobs j
     where j.status = 'processing'
       and j.lease_expires_at < now()
     for update skip locked
  )
  update public.ai_jobs j set
    status = case
      when j.cancel_requested_at is not null then 'cancelled'
      when j.attempts >= j.max_attempts then 'failed'
      else 'pending' end,
    completed_at = case
      when j.cancel_requested_at is not null or j.attempts >= j.max_attempts then now() end,
    available_at = now() + interval '15 seconds',
    lease_id = null,
    lease_expires_at = null,
    error_code = case when j.cancel_requested_at is not null then 'cancelled' else 'lease_expired' end,
    error = case when j.cancel_requested_at is not null then 'Cancelado.'
                 else 'O worker parou de responder durante a execução (lease vencida).' end
  from vencidos v
  where j.id = v.id;
  get diagnostics n = row_count;

  update public.ai_jobs j set
    status = 'failed',
    completed_at = now(),
    error_code = 'deadline_exceeded',
    error = 'O prazo do job venceu antes de ele começar.'
  where j.status = 'pending'
    and j.deadline_at is not null
    and j.deadline_at < now();

  return n;
end $$;

create or replace function public.ai_gateway_ping(p_worker_id text, p_token text, p_version text default null)
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
     set last_seen_at = now(), version = coalesce(left(p_version, 64), version)
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

create or replace function public.ai_gateway_claim_job(
  p_worker_id text,
  p_token text,
  p_providers text[] default null,
  p_lease_seconds integer default 120
)
returns setof public.ai_jobs
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w public.ai_gateway_workers;
  v_id uuid;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  update public.ai_gateway_workers set last_seen_at = now() where id = w.id;
  perform public._ai_gateway_reap();

  select j.id into v_id
    from public.ai_jobs j
   where j.status = 'pending'
     and j.available_at <= now()
     and j.source = any (w.allowed_sources)
     and (p_providers is null or j.provider = any (p_providers))
   order by j.priority desc, j.available_at, j.created_at
   for update skip locked
   limit 1;

  if v_id is null then
    return;
  end if;

  return query
  update public.ai_jobs j set
    status = 'processing',
    worker_id = w.id,
    lease_id = gen_random_uuid(),
    lease_expires_at = now() + make_interval(secs => greatest(30, least(coalesce(p_lease_seconds, 120), 900))),
    attempts = j.attempts + 1,
    started_at = now(),
    completed_at = null,
    error = null,
    error_code = null
  where j.id = v_id
  returning j.*;
end $$;

-- 'ok' | 'cancel' (dono pediu cancelamento) | 'lost' (o job não é mais deste worker/lease)
create or replace function public.ai_gateway_heartbeat(
  p_worker_id text,
  p_token text,
  p_job_id uuid,
  p_lease_id uuid,
  p_lease_seconds integer default 120
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w public.ai_gateway_workers;
  v_cancel timestamptz;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  update public.ai_jobs j set
    lease_expires_at = now() + make_interval(secs => greatest(30, least(coalesce(p_lease_seconds, 120), 900)))
  where j.id = p_job_id
    and j.status = 'processing'
    and j.worker_id = w.id
    and j.lease_id = p_lease_id
  returning j.cancel_requested_at into v_cancel;
  if not found then
    return 'lost';
  end if;
  return case when v_cancel is not null then 'cancel' else 'ok' end;
end $$;

create or replace function public.ai_gateway_complete_job(
  p_worker_id text,
  p_token text,
  p_job_id uuid,
  p_lease_id uuid,
  p_response jsonb,
  p_provider_used text default null,
  p_model_used text default null,
  p_duration_ms integer default null,
  p_usage jsonb default null
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w public.ai_gateway_workers;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  if p_response is null or octet_length(p_response::text) > 2000000 then
    raise exception 'ai_gateway: resposta ausente ou maior que 2 MB' using errcode = '22023';
  end if;
  update public.ai_jobs j set
    status = 'completed',
    response = p_response,
    completed_at = now(),
    lease_id = null,
    lease_expires_at = null,
    error = null,
    error_code = null,
    provider_used = left(p_provider_used, 64),
    model_used = left(p_model_used, 128),
    duration_ms = p_duration_ms,
    usage = p_usage
  where j.id = p_job_id
    and j.status = 'processing'
    and j.worker_id = w.id
    and j.lease_id = p_lease_id;
  return found;
end $$;

-- Devolve o novo status: 'pending' (vai tentar de novo), 'failed', 'cancelled' ou 'lost'.
-- p_count_attempt = false quando a culpa não é do job (limite de uso da assinatura, worker desligando).
create or replace function public.ai_gateway_fail_job(
  p_worker_id text,
  p_token text,
  p_job_id uuid,
  p_lease_id uuid,
  p_error_code text,
  p_error text,
  p_retryable boolean default false,
  p_retry_after_seconds integer default 0,
  p_count_attempt boolean default true,
  p_provider_used text default null,
  p_model_used text default null,
  p_duration_ms integer default null,
  p_usage jsonb default null
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  w public.ai_gateway_workers;
  j public.ai_jobs;
  v_status text;
begin
  w := public._ai_gateway_auth(p_worker_id, p_token);
  select * into j
    from public.ai_jobs x
   where x.id = p_job_id
     and x.status = 'processing'
     and x.worker_id = w.id
     and x.lease_id = p_lease_id
   for update;
  if not found then
    return 'lost';
  end if;

  v_status := case
    when j.cancel_requested_at is not null or p_error_code = 'cancelled' then 'cancelled'
    when coalesce(p_retryable, false)
         and (not coalesce(p_count_attempt, true) or j.attempts < j.max_attempts) then 'pending'
    else 'failed' end;

  update public.ai_jobs x set
    status = v_status,
    attempts = case when v_status = 'pending' and not coalesce(p_count_attempt, true)
                    then greatest(x.attempts - 1, 0) else x.attempts end,
    available_at = case when v_status = 'pending'
                        then now() + make_interval(secs => least(greatest(coalesce(p_retry_after_seconds, 0), 0), 86400))
                        else x.available_at end,
    completed_at = case when v_status = 'pending' then null else now() end,
    lease_id = null,
    lease_expires_at = null,
    error_code = left(coalesce(p_error_code, 'internal'), 64),
    error = left(p_error, 4000),
    provider_used = coalesce(left(p_provider_used, 64), x.provider_used),
    model_used = coalesce(left(p_model_used, 128), x.model_used),
    duration_ms = coalesce(p_duration_ms, x.duration_ms),
    usage = coalesce(p_usage, x.usage)
  where x.id = j.id;

  return v_status;
end $$;

-- ---------------------------------------------------------------------------------------------
-- API do MarineFlow (authenticated). Só o admin cria; quem pediu (ou o admin) cancela.
-- ---------------------------------------------------------------------------------------------

create or replace function public.ai_job_submit(
  p_prompt text,
  p_model text default 'sonnet',
  p_provider text default 'claude-local',
  p_system_prompt text default null,
  p_input jsonb default null,
  p_response_format text default 'text',
  p_json_schema jsonb default null,
  p_task_profile text default 'text',
  p_priority integer default 0,
  p_timeout_seconds integer default 300,
  p_max_attempts integer default 3,
  p_allow_fallback boolean default false,
  p_deadline_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'ai_jobs: só o administrador do MarineFlow pode criar jobs de IA' using errcode = '42501';
  end if;
  -- trava contra laço no app: um bug não pode encher a fila
  if (select count(*) from public.ai_jobs j
       where j.requested_by = v_uid and j.status in ('pending', 'processing')) >= 50 then
    raise exception 'ai_jobs: já existem 50 jobs abertos deste usuário' using errcode = '54000';
  end if;

  insert into public.ai_jobs (
    source, requested_by, provider, model, system_prompt, prompt, input,
    response_format, json_schema, task_profile, priority, timeout_seconds,
    max_attempts, allow_fallback, deadline_at, metadata
  ) values (
    'marineflow', v_uid,
    coalesce(p_provider, 'claude-local'), coalesce(p_model, 'sonnet'),
    p_system_prompt, p_prompt, p_input,
    coalesce(p_response_format, 'text'), p_json_schema, coalesce(p_task_profile, 'text'),
    coalesce(p_priority, 0), coalesce(p_timeout_seconds, 300),
    coalesce(p_max_attempts, 3), coalesce(p_allow_fallback, false),
    p_deadline_at, coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_id;
  return v_id;
end $$;

-- Devolve: 'cancelled' (estava na fila), 'cancelling' (o worker vai interromper) ou o status final.
create or replace function public.ai_job_cancel(p_job_id uuid)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  j public.ai_jobs;
begin
  select * into j from public.ai_jobs x where x.id = p_job_id for update;
  if not found or v_uid is null
     or (j.requested_by is distinct from v_uid and not public.is_admin(v_uid)) then
    raise exception 'ai_jobs: job não encontrado' using errcode = 'P0002';
  end if;

  if j.status = 'pending' then
    update public.ai_jobs x set
      status = 'cancelled', cancel_requested_at = now(), completed_at = now(),
      error_code = 'cancelled', error = 'Cancelado antes de começar.'
    where x.id = j.id;
    return 'cancelled';
  elsif j.status = 'processing' then
    update public.ai_jobs x set cancel_requested_at = coalesce(x.cancel_requested_at, now())
    where x.id = j.id;
    return 'cancelling';
  end if;
  return j.status;
end $$;

-- ---------------------------------------------------------------------------------------------
-- RLS e privilégios (revogar de anon/authenticated POR NOME: o grant padrão do Supabase não vem de PUBLIC)
-- ---------------------------------------------------------------------------------------------

alter table public.ai_jobs enable row level security;
alter table public.ai_gateway_workers enable row level security;

drop policy if exists ai_jobs_le_os_proprios on public.ai_jobs;
create policy ai_jobs_le_os_proprios on public.ai_jobs
  for select to authenticated
  using (requested_by = (select auth.uid()) or public.is_admin((select auth.uid())));

revoke all on table public.ai_jobs from public, anon, authenticated;
grant select on table public.ai_jobs to authenticated;
grant all on table public.ai_jobs to service_role;

revoke all on table public.ai_gateway_workers from public, anon, authenticated;
grant all on table public.ai_gateway_workers to service_role;

revoke all on function public._ai_jobs_touch() from public, anon, authenticated;
revoke all on function public._ai_jobs_campainha() from public, anon, authenticated;
revoke all on function public._ai_gateway_auth(text, text) from public, anon, authenticated;
revoke all on function public._ai_gateway_reap() from public, anon, authenticated;
revoke all on function public.ai_gateway_ping(text, text, text) from public, anon, authenticated;
revoke all on function public.ai_gateway_claim_job(text, text, text[], integer) from public, anon, authenticated;
revoke all on function public.ai_gateway_heartbeat(text, text, uuid, uuid, integer) from public, anon, authenticated;
revoke all on function public.ai_gateway_complete_job(text, text, uuid, uuid, jsonb, text, text, integer, jsonb) from public, anon, authenticated;
revoke all on function public.ai_gateway_fail_job(text, text, uuid, uuid, text, text, boolean, integer, boolean, text, text, integer, jsonb) from public, anon, authenticated;
revoke all on function public.ai_job_submit(text, text, text, text, jsonb, text, jsonb, text, integer, integer, integer, boolean, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function public.ai_job_cancel(uuid) from public, anon, authenticated;

-- worker: anon (+ token)
grant execute on function public.ai_gateway_ping(text, text, text) to anon, service_role;
grant execute on function public.ai_gateway_claim_job(text, text, text[], integer) to anon, service_role;
grant execute on function public.ai_gateway_heartbeat(text, text, uuid, uuid, integer) to anon, service_role;
grant execute on function public.ai_gateway_complete_job(text, text, uuid, uuid, jsonb, text, text, integer, jsonb) to anon, service_role;
grant execute on function public.ai_gateway_fail_job(text, text, uuid, uuid, text, text, boolean, integer, boolean, text, text, integer, jsonb) to anon, service_role;
-- MarineFlow: authenticated (a função ainda exige admin)
grant execute on function public.ai_job_submit(text, text, text, text, jsonb, text, jsonb, text, integer, integer, integer, boolean, timestamptz, jsonb) to authenticated, service_role;
grant execute on function public.ai_job_cancel(uuid) to authenticated, service_role;

-- Realtime para o MarineFlow acompanhar o próprio job (postgres_changes respeita a RLS acima).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables
                      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'ai_jobs') then
    alter publication supabase_realtime add table public.ai_jobs;
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Prova: a migration falha se alguma porta ficou aberta.
-- ---------------------------------------------------------------------------------------------

do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.ai_jobs'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.ai_gateway_workers'::regclass) then
    raise exception 'RLS desligada em ai_jobs/ai_gateway_workers';
  end if;
  if has_table_privilege('anon', 'public.ai_jobs', 'select')
     or has_table_privilege('anon', 'public.ai_jobs', 'insert')
     or has_table_privilege('anon', 'public.ai_jobs', 'update') then
    raise exception 'anon ainda alcança ai_jobs';
  end if;
  if has_table_privilege('authenticated', 'public.ai_jobs', 'insert')
     or has_table_privilege('authenticated', 'public.ai_jobs', 'update')
     or has_table_privilege('authenticated', 'public.ai_jobs', 'delete') then
    raise exception 'authenticated ainda escreve direto em ai_jobs';
  end if;
  if has_table_privilege('anon', 'public.ai_gateway_workers', 'select')
     or has_table_privilege('authenticated', 'public.ai_gateway_workers', 'select') then
    raise exception 'ai_gateway_workers legível pela API';
  end if;
  if has_function_privilege('anon', 'public._ai_gateway_auth(text, text)', 'execute')
     or has_function_privilege('authenticated', 'public._ai_gateway_auth(text, text)', 'execute')
     or has_function_privilege('anon', 'public._ai_gateway_reap()', 'execute') then
    raise exception 'helper interno do gateway exposto';
  end if;
  if has_function_privilege('anon', 'public.ai_job_submit(text, text, text, text, jsonb, text, jsonb, text, integer, integer, integer, boolean, timestamptz, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.ai_job_cancel(uuid)', 'execute') then
    raise exception 'anon consegue criar/cancelar job';
  end if;
  if has_function_privilege('authenticated', 'public.ai_gateway_claim_job(text, text, text[], integer)', 'execute')
     or has_function_privilege('authenticated', 'public.ai_gateway_complete_job(text, text, uuid, uuid, jsonb, text, text, integer, jsonb)', 'execute') then
    raise exception 'usuário do app alcança a API do worker';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261003203000', 'hbr_ai_gateway')
on conflict do nothing;
