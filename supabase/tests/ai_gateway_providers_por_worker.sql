-- Prova: o BANCO decide qual provider cada worker do HBR AI Gateway pega
-- (migrations 20261011104000_ai_gateway_providers_por_worker e 20261011106000_ai_gateway_hbr_pc_1_so_claude).
--
--   P1 worker {local-doc} não pega job claude-local (nem pedindo por p_providers)
--   P2 worker com allowed_providers nulo pega tudo (o comportamento de antes)
--   P3 worker {claude-local} (o que o hbr-pc-1 vira) pega claude-local e não pega local-doc
--   P4 o hbr-pc-1, se existir, está em {claude-local} (depois da 20261011106000)
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado P10 da spec; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/ai_gateway_providers_por_worker.sql --output json
--
-- Seguro em produção: cria três workers de teste com token próprio e uma ORIGEM própria
-- (allowed_sources = {teste-…}), então o claim só enxerga os jobs de teste — nunca um turno real do
-- assistente. Não toca no hbr-pc-1 (só lê). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

do $$
declare
  v_fonte text := 'teste-' || substr(md5(random()::text), 1, 8);
  v_doc text := 'teste-doc-' || substr(md5(random()::text), 1, 8);
  v_claude text := 'teste-claude-' || substr(md5(random()::text), 1, 8);
  v_todos text := 'teste-todos-' || substr(md5(random()::text), 1, 8);
  v_token text := 'token-de-teste-' || md5(random()::text) || md5(random()::text);
  v_hash text;
  v_job_claude uuid;
  v_job_doc uuid;
  v_pegou uuid;
  v_pegou2 uuid;
  v_pegou3 uuid;
  v_pc1 text[];
  v_pc1_existe boolean;
begin
  v_hash := encode(extensions.digest(convert_to(v_token, 'UTF8'), 'sha256'), 'hex');
  insert into public.ai_gateway_workers (id, token_hash, allowed_sources, allowed_providers) values
    (v_doc, v_hash, array[v_fonte], array['local-doc']),
    (v_claude, v_hash, array[v_fonte], array['claude-local']),
    (v_todos, v_hash, array[v_fonte], null);

  -- o job do Claude tem prioridade maior: se o filtro falhasse, ele sairia primeiro
  insert into public.ai_jobs (source, provider, model, prompt, priority)
  values (v_fonte, 'claude-local', 'sonnet', 'teste', 90) returning id into v_job_claude;
  insert into public.ai_jobs (source, provider, model, task_profile, response_format, prompt, priority)
  values (v_fonte, 'local-doc', 'leitor-v1', 'comprovante', 'json', 'ler_comprovante', 10) returning id into v_job_doc;

  -- P1
  begin
    select id into v_pegou from public.ai_gateway_claim_job(v_doc, v_token, null, 60);
    select id into v_pegou2 from public.ai_gateway_claim_job(v_doc, v_token, array['claude-local'], 60);
    select id into v_pegou3 from public.ai_gateway_claim_job(v_doc, v_token, null, 60);
    insert into _resultado values ('P1 worker {local-doc} não pega claude-local',
      v_pegou = v_job_doc and v_pegou2 is null and v_pegou3 is null
      and (select status from public.ai_jobs where id = v_job_claude) = 'pending',
      'pegou o local-doc: ' || (v_pegou = v_job_doc) || '; pedindo claude-local: ' || coalesce(v_pegou2::text, 'nada')
      || '; de novo: ' || coalesce(v_pegou3::text, 'nada'));
  exception when others then
    insert into _resultado values ('P1 worker {local-doc} não pega claude-local', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;

  -- P2
  begin
    update public.ai_jobs set status = 'pending', worker_id = null, lease_id = null, lease_expires_at = null, attempts = 0
     where id in (v_job_claude, v_job_doc);
    v_pegou := null; v_pegou2 := null; v_pegou3 := null;
    select id into v_pegou from public.ai_gateway_claim_job(v_todos, v_token, null, 60);
    select id into v_pegou2 from public.ai_gateway_claim_job(v_todos, v_token, null, 60);
    select id into v_pegou3 from public.ai_gateway_claim_job(v_todos, v_token, null, 60);
    insert into _resultado values ('P2 allowed_providers nulo pega tudo',
      v_pegou = v_job_claude and v_pegou2 = v_job_doc and v_pegou3 is null,
      'ordem: ' || coalesce(v_pegou::text, '-') || ', ' || coalesce(v_pegou2::text, '-'));
  exception when others then
    insert into _resultado values ('P2 allowed_providers nulo pega tudo', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;

  -- P3
  begin
    update public.ai_jobs set status = 'pending', worker_id = null, lease_id = null, lease_expires_at = null, attempts = 0
     where id in (v_job_claude, v_job_doc);
    update public.ai_jobs set priority = 0 where id = v_job_claude;
    update public.ai_jobs set priority = 90 where id = v_job_doc;        -- agora o local-doc sairia primeiro
    v_pegou := null; v_pegou2 := null;
    select id into v_pegou from public.ai_gateway_claim_job(v_claude, v_token, null, 60);
    select id into v_pegou2 from public.ai_gateway_claim_job(v_claude, v_token, array['local-doc'], 60);
    insert into _resultado values ('P3 worker {claude-local} (o hbr-pc-1) não pega local-doc',
      v_pegou = v_job_claude and v_pegou2 is null
      and (select status from public.ai_jobs where id = v_job_doc) = 'pending',
      'pegou o claude-local: ' || (v_pegou = v_job_claude) || '; pedindo local-doc: ' || coalesce(v_pegou2::text, 'nada'));
  exception when others then
    insert into _resultado values ('P3 worker {claude-local} (o hbr-pc-1) não pega local-doc', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;

  -- P4 (só leitura)
  select true, w.allowed_providers into v_pc1_existe, v_pc1 from public.ai_gateway_workers w where w.id = 'hbr-pc-1';
  insert into _resultado values ('P4 hbr-pc-1 restrito a claude-local',
    not coalesce(v_pc1_existe, false) or (v_pc1 = array['claude-local']),
    case when not coalesce(v_pc1_existe, false) then 'sem hbr-pc-1 neste banco'
         else 'allowed_providers = ' || coalesce(array_to_string(v_pc1, ','), 'nulo (todos)') end);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
