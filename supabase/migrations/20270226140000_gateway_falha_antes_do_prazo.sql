-- Gateway: o job que não teria nova tentativa antes do prazo falha na hora (24/11/2026).
--
-- Caso real (24/11 09:32 e 09:44): o login do Claude Code no PC falhou (auth_failed) em 5 s; o gateway devolveu o turno
-- do WhatsApp para a fila com nova tentativa em 600 s, mas o prazo do turno é 75 s. O job ficou parado até o reaper
-- marcar deadline_exceeded; só então a entrega refez pelo OpenRouter (sem crédito) e mandou o aviso ao dono — ~80 s
-- depois da mensagem dele, em vez de ~10 s.
--
-- Muda só a decisão pending × failed de ai_gateway_fail_job (corpo de produção de 24/11, sem CR): a nova tentativa
-- tem de cair antes de deadline_at. Job sem prazo e retry dentro do prazo: igual a antes. O código de erro gravado é o
-- real (auth_failed, rate_limited...), não deadline_exceeded. Grants e assinatura não mudam (create or replace).
-- Prova: supabase/tests/gateway_falha_antes_do_prazo.sql.

create or replace function public.ai_gateway_fail_job(p_worker_id text, p_token text, p_job_id uuid, p_lease_id uuid, p_error_code text, p_error text, p_retryable boolean DEFAULT false, p_retry_after_seconds integer DEFAULT 0, p_count_attempt boolean DEFAULT true, p_provider_used text DEFAULT NULL::text, p_model_used text DEFAULT NULL::text, p_duration_ms integer DEFAULT NULL::integer, p_usage jsonb DEFAULT NULL::jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
         and (not coalesce(p_count_attempt, true) or j.attempts < j.max_attempts)
         -- 24/11/2026: a nova tentativa só vale se cair ANTES do prazo. Se cair depois, o job já está perdido (o reaper
         -- o marcaria deadline_exceeded no prazo): falha agora, com o código real, e a entrega avisa em segundos.
         and (j.deadline_at is null
              or now() + make_interval(secs => least(greatest(coalesce(p_retry_after_seconds, 0), 0), 86400)) < j.deadline_at)
      then 'pending'
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
end $function$;

notify pgrst, 'reload schema';

insert into supabase_migrations.schema_migrations (version, name) values ('20270226140000', 'gateway_falha_antes_do_prazo');
