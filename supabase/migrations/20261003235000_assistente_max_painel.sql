-- Chat do app (painel) pela assinatura Claude Max do dono + status do gateway para Configurações
-- (03/10/2026). Continuação de 20261003233000_whatsapp_claude_max.
--
-- Chave: app_settings.ai_provedor_painel = 'claude_max' | 'openrouter' (nasce 'openrouter': esta
-- migration não muda o comportamento de ninguém). No modo Max o ai-agent enfileira o turno do
-- painel (tipo 'agente_painel') e ESPERA a resposta na própria requisição. Se a tela desistir de
-- esperar (passou do tempo da edge), o job é marcado 'painel_tarde' e só então o gatilho de entrega
-- grava a resposta na conversa — sem essa marca, a própria edge entrega e a corrida não existe.
--
-- Só o admin (o dono) vai pelo Max — termos da Anthropic: assinatura é para uso individual.
-- Idempotente.

-- ---------------------------------------------------------------------------------------------
-- 1. O erp-mcp registra as ferramentas também dos turnos do painel
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
   where j.id = p_job_id and j.status = 'processing'
     and j.metadata->>'tipo' in ('agente_whatsapp', 'agente_painel', 'agente_ensaio')
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

-- Entrega uma vez só (WhatsApp e painel): true só para a primeira chamada depois que o job terminou.
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
     and j.metadata->>'tipo' in ('agente_whatsapp', 'agente_painel')
     and j.status in ('completed', 'failed', 'cancelled')
     and not (j.metadata ? 'entregue_em');
  return found;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. A tela desistiu de esperar: daqui em diante quem entrega é o gatilho. Só marca job que AINDA
--    não terminou — se terminou, devolve false e a edge entrega ela mesma (sem perder nem duplicar).
-- ---------------------------------------------------------------------------------------------
create or replace function public.ai_job_painel_desistir(p_job_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.ai_jobs j
     set metadata = j.metadata || jsonb_build_object('painel_tarde', true)
   where j.id = p_job_id
     and j.metadata->>'tipo' = 'agente_painel'
     and j.status in ('pending', 'processing');
  return found;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 3. Gatilho de entrega: WhatsApp sempre; painel só quando a tela desistiu de esperar
-- ---------------------------------------------------------------------------------------------
create or replace function public._ai_jobs_entregar_turno()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.metadata->>'tipo' = 'agente_whatsapp'
      or (new.metadata->>'tipo' = 'agente_painel' and coalesce((new.metadata->>'painel_tarde')::boolean, false)))
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

-- ---------------------------------------------------------------------------------------------
-- 4. Status do gateway para a tela de Configurações (só o admin). Sem token, sem prompt, sem
--    resposta: o PC está no ar? o claude-local está livre? como foram os últimos turnos?
-- ---------------------------------------------------------------------------------------------
create or replace function public.ai_gateway_status()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or not public.is_admin(v_uid) then
    raise exception 'Só o administrador vê o status do gateway' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'disponivel', public.ai_claude_max_disponivel(),
    'agora', now(),
    'workers', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', w.id,
               'enabled', w.enabled,
               'last_seen_at', w.last_seen_at,
               'version', w.version,
               'providers', w.estado->'providers',
               'ativos', w.estado->'ativos',
               'maximo', w.estado->'max'
             ) order by w.last_seen_at desc nulls last)
        from public.ai_gateway_workers w), '[]'::jsonb),
    'ultimos', coalesce((
      select jsonb_agg(x order by x->>'created_at' desc)
        from (
          select jsonb_build_object(
                   'tipo', j.metadata->>'tipo',
                   'status', j.status,
                   'model_used', j.model_used,
                   'duration_ms', j.duration_ms,
                   'error_code', j.error_code,
                   'created_at', j.created_at
                 ) as x
            from public.ai_jobs j
           where j.metadata->>'tipo' in ('agente_whatsapp', 'agente_painel')
           order by j.created_at desc
           limit 8
        ) u), '[]'::jsonb)
  );
end $$;

-- ---------------------------------------------------------------------------------------------
-- 5. As chaves do painel (nascem desligadas: o chat do app segue no OpenRouter)
-- ---------------------------------------------------------------------------------------------
insert into public.app_settings (key, value, description) values
  ('ai_provedor_painel', 'openrouter',
   'Quem atende o assistente no app (painel): claude_max (assinatura Claude do dono pelo HBR AI Gateway; só o admin) ou openrouter.'),
  ('ai_painel_max_modelo', 'sonnet',
   'Modelo do Claude Max no app (painel): haiku, sonnet ou opus.')
on conflict (key) do nothing;

update public.app_settings
   set description = 'Se o Claude Max falhar (PC desligado, limite da assinatura, erro), refaz o turno pelo OpenRouter (on) ou só avisa (off). Vale para o WhatsApp e para o app.'
 where key = 'ai_whatsapp_max_reserva';

-- ---------------------------------------------------------------------------------------------
-- Privilégios
-- ---------------------------------------------------------------------------------------------
revoke all on function public.ai_job_registrar_ferramenta(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.ai_job_registrar_ferramenta(uuid, text, jsonb) to service_role;
revoke all on function public.ai_job_marcar_entregue(uuid) from public, anon, authenticated;
grant execute on function public.ai_job_marcar_entregue(uuid) to service_role;
revoke all on function public.ai_job_painel_desistir(uuid) from public, anon, authenticated;
grant execute on function public.ai_job_painel_desistir(uuid) to service_role;
revoke all on function public._ai_jobs_entregar_turno() from public, anon, authenticated;
revoke all on function public.ai_gateway_status() from public, anon, authenticated;
grant execute on function public.ai_gateway_status() to authenticated, service_role;

do $$
begin
  if has_function_privilege('anon', 'public.ai_job_registrar_ferramenta(uuid, text, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.ai_job_registrar_ferramenta(uuid, text, jsonb)', 'execute')
     or has_function_privilege('anon', 'public.ai_job_marcar_entregue(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ai_job_marcar_entregue(uuid)', 'execute')
     or has_function_privilege('anon', 'public.ai_job_painel_desistir(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ai_job_painel_desistir(uuid)', 'execute')
     or has_function_privilege('anon', 'public.ai_gateway_status()', 'execute') then
    raise exception 'função do assistente pelo Claude Max exposta além do previsto';
  end if;
  if not has_function_privilege('authenticated', 'public.ai_gateway_status()', 'execute') then
    raise exception 'a tela de Configurações perdeu o status do gateway';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'ai_jobs_entregar_turno' and tgrelid = 'public.ai_jobs'::regclass) then
    raise exception 'gatilho de entrega sumiu';
  end if;
  if (select count(*) from public.app_settings where key in ('ai_provedor_painel', 'ai_painel_max_modelo')) <> 2 then
    raise exception 'chaves do painel não foram criadas';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261003235000', 'assistente_max_painel')
on conflict do nothing;
