-- Prova: o job do gateway que não teria nova tentativa antes do prazo falha na hora
-- (migration 20270226140000_gateway_falha_antes_do_prazo).
--
--   F1 retry depois do prazo (600 s × prazo 75 s, o caso de 24/11) → failed agora, com o código real e completed_at
--   F2 retry dentro do prazo (5 s × 75 s) → pending, como antes
--   F3 job sem prazo e retry de 600 s → pending, como antes
--   F4 erro não-retentável → failed, como antes
--   F5 tentativas esgotadas (count_attempt) → failed, como antes
--
-- ═══ COMO RODAR ═══
--   supabase db query --linked -f supabase/tests/gateway_falha_antes_do_prazo.sql --output json
--
-- Seguro em produção: worker de teste com token próprio e ORIGEM própria (allowed_sources = {teste-…}), então o claim
-- só enxerga os jobs de teste. Os jobs não têm metadata.tipo de turno: o gatilho de entrega não dispara. ROLLBACK.
-- A tabela final tem de mostrar ok = true em todas as linhas.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_fonte text := 'teste-' || substr(md5(random()::text), 1, 8);
  v_worker text := 'teste-prazo-' || substr(md5(random()::text), 1, 8);
  v_token text := 'token-de-teste-' || md5(random()::text) || md5(random()::text);
  v_job uuid;
  v_lease uuid;
  v_st text;
  r public.ai_jobs;
  -- um caso: cria o job, o worker pega, o worker falha; devolve o status gravado
  v_casos jsonb := jsonb_build_array(
    jsonb_build_object('t', 'F1 retry depois do prazo falha agora', 'prazo_s', 75, 'retry', true, 'apos_s', 600, 'conta', false, 'max', 3, 'tent', 0, 'espera', 'failed'),
    jsonb_build_object('t', 'F2 retry dentro do prazo continua pending', 'prazo_s', 75, 'retry', true, 'apos_s', 5, 'conta', false, 'max', 3, 'tent', 0, 'espera', 'pending'),
    jsonb_build_object('t', 'F3 sem prazo continua pending', 'prazo_s', null, 'retry', true, 'apos_s', 600, 'conta', false, 'max', 3, 'tent', 0, 'espera', 'pending'),
    jsonb_build_object('t', 'F4 não-retentável falha', 'prazo_s', 75, 'retry', false, 'apos_s', 0, 'conta', true, 'max', 3, 'tent', 0, 'espera', 'failed'),
    jsonb_build_object('t', 'F5 tentativas esgotadas falha', 'prazo_s', null, 'retry', true, 'apos_s', 5, 'conta', true, 'max', 1, 'tent', 0, 'espera', 'failed')
  );
  c jsonb;
begin
  insert into public.ai_gateway_workers (id, token_hash, allowed_sources, allowed_providers)
  values (v_worker, encode(extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex'), array[v_fonte], array['claude-local']);

  for c in select * from jsonb_array_elements(v_casos) loop
    begin
      insert into public.ai_jobs (source, provider, model, prompt, max_attempts, deadline_at)
      values (v_fonte, 'claude-local', 'sonnet', 'teste', (c->>'max')::int,
              case when c->>'prazo_s' is null then null else now() + make_interval(secs => (c->>'prazo_s')::int) end)
      returning id into v_job;
      select x.id, x.lease_id into v_job, v_lease from public.ai_gateway_claim_job(v_worker, v_token, null, 60) x;
      if v_job is null then raise exception 'o worker de teste não pegou o job'; end if;
      v_st := public.ai_gateway_fail_job(v_worker, v_token, v_job, v_lease, 'auth_failed', 'teste',
                (c->>'retry')::boolean, (c->>'apos_s')::int, (c->>'conta')::boolean);
      select * into r from public.ai_jobs where id = v_job;
      insert into _resultado values (c->>'t',
        v_st = c->>'espera' and r.status = c->>'espera' and r.error_code = 'auth_failed'
          and (case when c->>'espera' = 'failed' then r.completed_at is not null else r.completed_at is null end),
        'devolveu ' || coalesce(v_st, '-') || ', gravado ' || r.status || ', código ' || coalesce(r.error_code, '-')
          || ', completed_at ' || coalesce(r.completed_at::text, 'nulo'));
      -- o próximo caso começa com a fila do worker vazia
      update public.ai_jobs set status = 'cancelled', completed_at = now() where id = v_job and status = 'pending';
    exception when others then
      insert into _resultado values (c->>'t', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
    end;
  end loop;
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
