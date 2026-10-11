-- HBR AI Gateway: o BANCO decide qual provider cada worker pode pegar (11/10/2026).
--
-- Antes, o filtro de provider do claim era declarado pelo próprio worker (p_providers): qualquer token
-- válido conseguia pegar job de qualquer provider, inclusive os do assistente (claude-local, perfil
-- erp_agent), que levam o mcp_token das ferramentas do ERP. Agora cada worker tem a lista do que pode
-- pegar; nula = todos (o comportamento de antes, até a migration de dado que restringe o hbr-pc-1).
--
-- Idêntica no marineflow-erp e no hbr-ai-gateway (o teste PGlite do gateway roda este arquivo).
-- Não escreve dados. Idempotente.

alter table public.ai_gateway_workers add column if not exists allowed_providers text[];

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'ai_gateway_workers_providers_chk'
       and conrelid = 'public.ai_gateway_workers'::regclass
  ) then
    alter table public.ai_gateway_workers
      add constraint ai_gateway_workers_providers_chk
      check (allowed_providers is null or cardinality(allowed_providers) between 1 and 8);
  end if;
end $$;

comment on column public.ai_gateway_workers.allowed_providers is
  'Providers que este worker pode pegar no claim (ex.: {claude-local} ou {local-doc}). Nulo = todos.';

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
     and (w.allowed_providers is null or j.provider = any (w.allowed_providers))
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

revoke all on function public.ai_gateway_claim_job(text, text, text[], integer) from public, anon, authenticated;
grant execute on function public.ai_gateway_claim_job(text, text, text[], integer) to anon, service_role;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'ai_gateway_workers' and column_name = 'allowed_providers'
  ) then
    raise exception 'coluna allowed_providers não foi criada';
  end if;
  if not has_function_privilege('anon', 'public.ai_gateway_claim_job(text, text, text[], integer)', 'execute') then
    raise exception 'o worker (anon + token) perdeu o claim';
  end if;
  if has_function_privilege('authenticated', 'public.ai_gateway_claim_job(text, text, text[], integer)', 'execute') then
    raise exception 'usuário do app alcança o claim do worker';
  end if;
  if has_table_privilege('anon', 'public.ai_gateway_workers', 'select')
     or has_table_privilege('authenticated', 'public.ai_gateway_workers', 'select') then
    raise exception 'ai_gateway_workers legível pela API';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011104000', 'ai_gateway_providers_por_worker')
on conflict do nothing;
