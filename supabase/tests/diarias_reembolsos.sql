-- Prova: reembolso do técnico nas Diárias (F2b, migration 20261011301000).
--
--   D1 conta corrente com reembolso: linhas (dia e reembolso), totais (trabalhado só dos dias,
--      reembolsos à parte), saldo corrido e final, "em aberto"
--   D2 resumo dos freelancers com os reembolsos (por pessoa e no total)
--   D3 acerto com reembolso: a simulação lista os itens; o fechado guarda a foto e mostra na mensagem
--   D4 trava: reembolso dentro de acerto fechado não muda, não entra e não sai; reaberto = muda
--   D5 RLS: anon nada; authenticated só lê, e só quem vê a folha (admin/financeiro)
--   D6 o dia do crédito: nunca antes do início da conta corrente nem dentro de acerto fechado
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado PF3-2 da spec da F3; também roda no ensaio PGlite da bancada)
--
--   supabase db query --linked -f supabase/tests/diarias_reembolsos.sql --output json
--
-- Seguro em produção: termina em ROLLBACK. Cria um freelancer de teste, um dia e reembolsos de
-- mentira (insert direto, como as funções dos comprovantes fazem). Sem id nem data fixos.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (dono uuid, tecnico_user uuid, fav uuid, reemb uuid, acerto uuid) on commit drop;

create function pg_temp._hoje() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;
create function pg_temp._letras(n integer) returns text language sql volatile as $$
  select upper(translate(substr(md5(random()::text || clock_timestamp()::text), 1, n), '0123456789', 'ghijklmnop'))
$$;

do $$
declare
  v_dono uuid := gen_random_uuid();
  v_tec uuid := gen_random_uuid();
  v_fav uuid;
  v_perfil uuid;
  v_reemb uuid;
begin
  insert into public.app_users (id, full_name, email, role, active, created_at)
  values (v_dono, 'Admin de teste F2b', 'teste-f2b-' || v_dono || '@teste.invalido', 'admin', true, now() - interval '30 years'),
         (v_tec, 'Técnico de teste F2b', 'teste-f2b-' || v_tec || '@teste.invalido', 'technician', true, now());
  insert into public.payees (name, kind, active, conta_corrente_desde)
  values ('Freelancer Reembolso ' || pg_temp._letras(6), 'diarista', true, pg_temp._hoje() - 30)
  returning id into v_fav;
  insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, vigencia_inicio)
  values (v_fav, 'freelancer', 'diaria', 300, pg_temp._hoje() - 30) returning id into v_perfil;
  insert into public.work_shifts (work_profile_id, data, tipo, fracao, valor_diaria)
  values (v_perfil, pg_temp._hoje() - 5, 'diaria', 1, 300);
  insert into public.diarias_reembolsos (favorecido_id, data, valor, descricao, origem, origem_codigo, categoria, criado_por)
  values (v_fav, pg_temp._hoje() - 4, 62, 'Reembolso CMP-99901 · Posto Teste', 'comprovante', 'CMP-99901',
          'Combustível e deslocamento', v_dono)
  returning id into v_reemb;
  insert into _ctx values (v_dono, v_tec, v_fav, v_reemb, null);
end $$;

create function pg_temp._dono() returns uuid language sql stable as $$ select dono from _ctx $$;
create function pg_temp._fav() returns uuid language sql stable as $$ select fav from _ctx $$;

-- ═══ D1 / D2 ═════════════════════════════════════════════════════════════════════════════════
do $$
declare
  c jsonb;
  a jsonb;
  r jsonb;
  v_l jsonb;
  v_p jsonb;
begin
  c := public.conta_corrente_freelancer(pg_temp._fav(), null, null, pg_temp._dono(), null);
  select x into v_l from jsonb_array_elements(c->'linhas') x where x->>'tipo' = 'reembolso';
  a := public.conta_corrente_freelancer(pg_temp._fav(), null, null, pg_temp._dono(), 'em_aberto');
  insert into _resultado values ('D1 conta corrente: trabalhado 300 (só os dias), reembolsos 62, saldo final 362, linha do reembolso',
    (c->>'trabalhado')::numeric = 300 and (c->>'reembolsos')::numeric = 62 and (c->>'pago')::numeric = 0
    and (c->>'saldo_final')::numeric = 362 and c->>'estado' = 'deve' and jsonb_array_length(c->'linhas') = 2
    and (v_l->>'trabalhado')::numeric = 62 and (v_l->>'pago')::numeric = 0 and v_l->>'conta' = 'CMP-99901'
    and v_l->>'categoria' = 'Combustível e deslocamento' and (v_l->>'saldo')::numeric = 362 and not (v_l->>'aguardando')::boolean
    and (a->>'saldo_final')::numeric = 362 and jsonb_array_length(a->'linhas') = 2,
    'trabalhado=' || coalesce(c->>'trabalhado', '-') || ' reembolsos=' || coalesce(c->>'reembolsos', '-')
    || ' saldo=' || coalesce(c->>'saldo_final', '-') || ' em_aberto=' || coalesce(a->>'saldo_final', '-'));

  r := public.resumo_freelancers(null, null, pg_temp._dono(), null);
  select x into v_p from jsonb_array_elements(r->'pessoas') x where x->>'id' = pg_temp._fav()::text;
  insert into _resultado values ('D2 resumo: reembolsos por pessoa e no total; o "deve" soma o reembolso',
    (v_p->>'reembolsos')::numeric = 62 and (v_p->>'trabalhado')::numeric = 300 and (v_p->>'saldo_final')::numeric = 362
    and (r->>'reembolsos')::numeric >= 62 and (r->>'deve')::numeric >= 362,
    'pessoa=' || coalesce(v_p::text, '-'));
exception when others then
  insert into _resultado values ('D1/D2 conta corrente e resumo', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ D3 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  s jsonb;
  f jsonb;
  v_ac record;
begin
  -- Desde 27/10 o recibo sai do Pix que zera a conta (20261027180000): CPF e o Pix de quitação.
  update public.payees set document = '999' || lpad((floor(random() * 100000000))::int::text, 8, '0') where id = pg_temp._fav();
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, expense_category,
                               payee_id, origin)
  values ('Pix quitação teste', pg_temp._hoje() - 1, pg_temp._hoje() - 1, 362, 362, 0, 'paid', 'Diárias de freelancers',
          pg_temp._fav(), 'bank_reconciliation');
  s := public.fechar_acerto_diarias(pg_temp._fav(), pg_temp._hoje() - 1, true, null);
  f := public.fechar_acerto_diarias(pg_temp._fav(), pg_temp._hoje() - 1, false, pg_temp._dono());
  select * into v_ac from public.acertos_diarias where id = (f->>'id')::uuid;
  update _ctx set acerto = v_ac.id;
  insert into _resultado values ('D3 acerto: a simulação lista os reembolsos; o fechado guarda a foto e mostra na mensagem',
    (s->>'reembolsos')::numeric = 62 and jsonb_array_length(s->'reembolsos_itens') = 1
    and s->'reembolsos_itens'->0->>'codigo' = 'CMP-99901' and (s->'reembolsos_itens'->0->>'valor')::numeric = 62
    and (s->>'valor_do_acerto')::numeric = 362 and s->>'resumo' like '%· reembolso de despesas pagas pelo técnico R$ 62,00 · já recebido%'
    and (f->>'ok')::boolean and v_ac.reembolsos = 62 and v_ac.trabalhado = 300 and v_ac.valor_do_acerto = 362
    and f->>'message' like '%· reembolso de despesas pagas pelo técnico R$ 62,00%',
    coalesce(s->>'resumo', '-'));
exception when others then
  insert into _resultado values ('D3 acerto: a simulação lista os reembolsos; o fechado guarda a foto e mostra na mensagem', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ D4 / D6 ═════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_reemb uuid := (select reemb from _ctx);
  v_erro_muda text;
  v_erro_entra text;
  v_erro_sai text;
  v_reab jsonb;
  v_ok boolean := false;
  v_data_dentro date;
  v_data_antes date;
begin
  begin
    update public.diarias_reembolsos set status = 'cancelado', cancelado_em = now(), motivo_cancelamento = 'teste'
     where id = v_reemb;
  exception when others then
    v_erro_muda := sqlerrm;
  end;
  begin
    insert into public.diarias_reembolsos (favorecido_id, data, valor, descricao, origem, origem_codigo)
    values (pg_temp._fav(), pg_temp._hoje() - 3, 10, 'Reembolso CMP-99902', 'comprovante', 'CMP-99902');
  exception when others then
    v_erro_entra := sqlerrm;
  end;
  begin
    delete from public.diarias_reembolsos where id = v_reemb;
  exception when others then
    v_erro_sai := sqlerrm;
  end;
  -- D6: o crédito novo cai no período aberto (depois do acerto) e nunca antes da conta corrente
  v_data_dentro := public._comprovante_reembolso_data(pg_temp._fav(), pg_temp._hoje() - 3);
  v_reab := public.reabrir_acerto_diarias((select acerto from _ctx), 'teste do reembolso', pg_temp._dono());
  v_data_antes := public._comprovante_reembolso_data(pg_temp._fav(), pg_temp._hoje() - 400);
  update public.diarias_reembolsos set status = 'cancelado', cancelado_em = now(), motivo_cancelamento = 'teste'
   where id = v_reemb;
  v_ok := found;
  insert into _resultado values ('D4 trava: reembolso no acerto fechado não muda, não entra, não sai; reaberto muda',
    v_erro_muda like 'O reembolso de % está no acerto nº %, já fechado.%' and v_erro_entra like '%está no acerto nº%'
    and v_erro_sai like '%está no acerto nº%' and (v_reab->>'ok')::boolean and v_ok,
    coalesce(v_erro_muda, 'mudou') || ' | ' || coalesce(v_erro_entra, 'entrou') || ' | ' || coalesce(v_erro_sai, 'saiu'));
  insert into _resultado values ('D6 o dia do crédito: depois do último acerto fechado e nunca antes da conta corrente',
    v_data_dentro = pg_temp._hoje() and v_data_antes = pg_temp._hoje() - 30,
    'dentro=' || v_data_dentro || ' antes=' || v_data_antes);
exception when others then
  insert into _resultado values ('D4/D6 trava e o dia do crédito', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ D5 ═════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_anon text := 'leu';
  v_anon_escreve text := 'escreveu';
  v_auth_escreve text := 'escreveu';
  v_tec integer;
  v_adm integer;
  v_fav uuid := pg_temp._fav();
begin
  begin
    execute 'set local role anon';
    perform 1 from public.diarias_reembolsos limit 1;
  exception when others then
    v_anon := sqlstate;
  end;
  execute 'reset role';
  begin
    execute 'set local role anon';
    insert into public.diarias_reembolsos (favorecido_id, data, valor, descricao) values (v_fav, pg_temp._hoje(), 1, 'x');
  exception when others then
    v_anon_escreve := sqlstate;
  end;
  execute 'reset role';
  -- o técnico (logado) não vê; o admin vê
  perform set_config('request.jwt.claim.sub', (select tecnico_user from _ctx)::text, true);
  execute 'set local role authenticated';
  select count(*) into v_tec from public.diarias_reembolsos where favorecido_id = v_fav;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', pg_temp._dono()::text, true);
  execute 'set local role authenticated';
  select count(*) into v_adm from public.diarias_reembolsos where favorecido_id = v_fav;
  begin
    insert into public.diarias_reembolsos (favorecido_id, data, valor, descricao) values (v_fav, pg_temp._hoje(), 1, 'x');
  exception when others then
    v_auth_escreve := sqlstate;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  insert into _resultado values ('D5 RLS: anon nada; authenticated só lê, e só quem vê a folha',
    v_anon = '42501' and v_anon_escreve = '42501' and v_tec = 0 and v_adm >= 1 and v_auth_escreve = '42501',
    'anon=' || v_anon || '/' || v_anon_escreve || ' tecnico=' || v_tec || ' admin=' || v_adm || ' admin_escreve=' || v_auth_escreve);
exception when others then
  execute 'reset role';
  insert into _resultado values ('D5 RLS: anon nada; authenticated só lê, e só quem vê a folha', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
