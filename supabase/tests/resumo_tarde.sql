-- Prova: o turno da tarde do resumo (migration 20261015210000_resumo_tarde).
--
--   T1 anon/authenticated sem execute nas 3 RPCs (service_role com); resumo_tarde com RLS, anon sem nada,
--      authenticated só lê
--   T2 resumo_tarde_registrar grava uma vez; o 2º disparo no mesmo dia devolve o MESMO texto ("já decidi hoje")
--   T3 SOMBRA NUNCA ENVIA: enviado=false não toca a fila; pedir enviado com formato sombra é recusado pelo CHECK
--      (nada gravado, nada na fila); insert direto de sombra enviada também é recusado
--   T4 ligado com a manhã NOVA: grava e enfileira UMA vez na mesma transação (source ai_briefing_tarde,
--      dedupe_key do dia); sem a manhã nova = manha_nao_e_nova (nada gravado, nada na fila)
--   T5 o dia calado: sem texto e sem fila; CHECK recusa calado com texto e não calado sem texto
--   T6 resumo_itens_acoes: tudo ou nada (letra que não existe, repetida, data fora → nada muda); com tudo certo,
--      grava em TODOS os itens de cada letra, com via 'lote' e a resposta no histórico
--   T7 resumo_semana_responder: sem pergunta enviada = sem_pergunta; com ela = gravado; de novo = trocado; a
--      pergunta da sombra (não enviada) não recebe resposta
--   T8 só o admin lê resumo_tarde (financeiro e técnico veem 0 linhas)
--   T9 só o admin muda fechamento_formato (o financeiro recebe 42501); a chave existe com um dos 3 valores
--   T10 as RPCs da manhã (20261015200000) não mudaram: md5 dos corpos = os de produção em 15/10/2026
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado; também roda no ensaio PGlite da bancada,
--   D:/IA-HBR/comprovantes-bancada/pglite-ensaio/rodar-secretario-fechamento.mjs)
--
--   supabase db query --linked -f supabase/tests/resumo_tarde.sql --output json
--
-- Seguro em produção: telefones de mentira 55000…, usuários de teste criados na transação, nenhum id fixo nem
-- data fixa (o "hoje" é o dia de Brasília), a linha da fila nunca é confirmada (o worker não a vê) e termina em
-- ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (phone text, hoje date) on commit drop;

create function pg_temp._telefone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;

insert into _ctx values (pg_temp._telefone(), (now() at time zone 'America/Sao_Paulo')::date);

create function pg_temp._phone() returns text language sql stable as $$ select phone from _ctx $$;
create function pg_temp._hoje() returns date language sql stable as $$ select hoje from _ctx $$;

create function pg_temp._usuario(p_papel text) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste tarde ' || p_papel, 'teste-tarde-' || v_id || '@teste.invalido', p_papel, true);
  return v_id;
end $$;

-- a manhã do dia (resumo_registrar da migration 20261015200000) com itens nas letras A, B (2 itens) e D
create function pg_temp._manha(p_phone text, p_modo text) returns jsonb language sql as $$
  select public.resumo_registrar(jsonb_build_object(
    'dia', pg_temp._hoje(), 'phone', p_phone, 'modo', p_modo, 'tipo_do_dia', 'util', 'texto_novo', 'Bom dia! Teste.',
    'enviado', p_modo = 'novo', 'itens_manha', 2, 'itens_lista', 1,
    'itens', jsonb_build_array(
      jsonb_build_object('letra', 'A', 'principal', true, 'posicao', 'manha', 'ordem', 0, 'familia', 'cobranca', 'tipo', 'cobranca_grande',
        'secao', 'dinheiro', 'referencia', 'recv:' || gen_random_uuid(), 'assunto', 'cliente:1', 'nome', 'Marcelo Teste',
        'nome_busca', 'marcelo teste', 'fato', '16890.00|2026-10-13|grande', 'valor', 16890, 'titulo', 't', 'motivo', 'm'),
      jsonb_build_object('letra', 'B', 'principal', true, 'posicao', 'manha', 'ordem', 1, 'familia', 'orcamento', 'tipo', 'orcamento_parado',
        'secao', 'clientes', 'referencia', 'os:' || gen_random_uuid(), 'assunto', 'cliente:2', 'nome', 'ORÇ-1 Teste',
        'nome_busca', 'orc 1 teste', 'fato', 'sent|14461.00|2026-10-06|parado', 'valor', 14461, 'titulo', 't', 'motivo', 'm'),
      jsonb_build_object('letra', 'B', 'principal', false, 'posicao', 'manha', 'ordem', 1, 'familia', 'cobranca', 'tipo', 'cobranca_antiga',
        'secao', 'dinheiro', 'referencia', 'recv:' || gen_random_uuid(), 'assunto', 'cliente:2', 'nome', 'MP Teste',
        'nome_busca', 'mp teste', 'fato', '1650.00|2026-07-22|lista', 'valor', 1650, 'titulo', 't', 'motivo', 'm'),
      jsonb_build_object('letra', 'D', 'principal', true, 'posicao', 'lista', 'ordem', 2, 'familia', 'os', 'tipo', 'os_parada',
        'secao', 'obras', 'referencia', 'os:' || gen_random_uuid(), 'assunto', 'os:3', 'nome', 'OS-69 Teste',
        'nome_busca', 'os 69 teste', 'fato', 'open|2026-10-03', 'valor', 9008.99, 'titulo', 't', 'motivo', 'm'))))
$$;

create function pg_temp._tarde(p_phone text, p_formato text, p_modo text, p_enviado boolean, p_texto text default 'Fechamento de teste.',
                               p_pergunta boolean default false) returns jsonb language sql as $$
  select public.resumo_tarde_registrar(jsonb_build_object(
    'dia', pg_temp._hoje(), 'phone', p_phone, 'turno', 'fechamento', 'modo', p_modo, 'formato', p_formato,
    'texto', p_texto, 'calado', p_texto is null, 'enviado', p_enviado, 'letras', '[{"letra": "A", "referencia": "recv:x", "tipo": "cobranca_grande", "parte": "ficou"}]'::jsonb,
    'detalhe', '{"ficaram": 1}'::jsonb, 'escritorio', 'Escritório (contado às 17:30): teste', 'itens', 1,
    'pergunta_semana', p_pergunta, 'conversa_ativa', false, 'tentativa', 1, 'max_attempts', 7))
$$;

create function pg_temp._fila(p_phone text) returns integer language sql stable as $$
  select count(*)::int from public.whatsapp_send_queue where phone_normalized = p_phone
$$;

-- ═══ T1 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text;
  v_t text := 'public.resumo_tarde';
  v_falhas text[] := '{}';
begin
  foreach v_f in array array['public.resumo_tarde_registrar(jsonb)', 'public.resumo_itens_acoes(jsonb)', 'public.resumo_semana_responder(jsonb)'] loop
    if has_function_privilege('anon', v_f, 'execute') then v_falhas := v_falhas || ('anon executa ' || v_f); end if;
    if has_function_privilege('authenticated', v_f, 'execute') then v_falhas := v_falhas || ('authenticated executa ' || v_f); end if;
    if not has_function_privilege('service_role', v_f, 'execute') then v_falhas := v_falhas || ('service_role sem ' || v_f); end if;
  end loop;
  if not (select relrowsecurity from pg_class where oid = v_t::regclass) then v_falhas := v_falhas || 'RLS desligada'::text; end if;
  if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert') then v_falhas := v_falhas || 'anon na tabela'::text; end if;
  if has_table_privilege('authenticated', v_t, 'insert') or has_table_privilege('authenticated', v_t, 'update')
     or has_table_privilege('authenticated', v_t, 'delete') then v_falhas := v_falhas || 'authenticated escreve'::text; end if;
  insert into _resultado values ('T1 RPCs só para service_role; resumo_tarde fechada', cardinality(v_falhas) = 0,
    coalesce(nullif(array_to_string(v_falhas, ', '), ''), '3 funções e 1 tabela conferidas'));
exception when others then
  insert into _resultado values ('T1 RPCs só para service_role; resumo_tarde fechada', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_a jsonb;
  v_b jsonb;
  v_n integer;
begin
  perform pg_temp._manha(v_phone, 'sombra');
  v_a := pg_temp._tarde(v_phone, 'sombra', 'sombra', false, 'Primeiro texto.');
  v_b := pg_temp._tarde(v_phone, 'sombra', 'sombra', false, 'Segundo texto.');
  select count(*) into v_n from public.resumo_tarde where phone_normalized = v_phone;
  insert into _resultado values ('T2 registrar grava uma vez; o 2º disparo devolve o mesmo texto (já decidi hoje)',
    (v_a->>'novo')::boolean and not (v_b->>'novo')::boolean and v_b->>'texto' = 'Primeiro texto.' and v_a->>'id' = v_b->>'id' and v_n = 1,
    'novo1=' || coalesce(v_a->>'novo', '-') || ' novo2=' || coalesce(v_b->>'novo', '-') || ' linhas=' || v_n);
exception when others then
  insert into _resultado values ('T2 registrar grava uma vez; o 2º disparo devolve o mesmo texto (já decidi hoje)', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T3 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_phone2 text := pg_temp._telefone();
  v_r jsonb;
  v_recusou boolean := false;
  v_direto boolean := false;
  v_linhas integer;
begin
  perform pg_temp._manha(v_phone, 'novo');
  v_r := pg_temp._tarde(v_phone, 'sombra', 'novo', false);
  -- sombra com enviado = true: o CHECK recusa (nada fica gravado, nada vai para a fila)
  perform pg_temp._manha(v_phone2, 'novo');
  begin
    perform pg_temp._tarde(v_phone2, 'sombra', 'novo', true);
  exception when check_violation then
    v_recusou := true;
  end;
  begin
    insert into public.resumo_tarde (dia, phone_normalized, turno, modo, formato, texto, enviado)
    values (pg_temp._hoje() - 20, v_phone, 'fechamento', 'novo', 'sombra', 'x', true);
  exception when check_violation then
    v_direto := true;
  end;
  select count(*) into v_linhas from public.resumo_tarde where phone_normalized = v_phone2;
  insert into _resultado values ('T3 sombra nunca envia: fila intocada; sombra enviada recusada pelo CHECK (RPC e insert direto)',
    (v_r->>'enviado')::boolean = false and pg_temp._fila(v_phone) = 0 and v_recusou and v_direto and v_linhas = 0 and pg_temp._fila(v_phone2) = 0,
    'fila=' || pg_temp._fila(v_phone) || ' rpc_recusou=' || v_recusou || ' direto_recusou=' || v_direto || ' gravou=' || v_linhas);
exception when others then
  insert into _resultado values ('T3 sombra nunca envia: fila intocada; sombra enviada recusada pelo CHECK (RPC e insert direto)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T4 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_sem text := pg_temp._telefone();
  v_a jsonb;
  v_b jsonb;
  v_c jsonb;
  v_fila record;
  v_sem_linhas integer;
begin
  perform pg_temp._manha(v_phone, 'novo');
  v_a := pg_temp._tarde(v_phone, 'ligado', 'novo', true, 'Fechamento enviado.');
  v_b := pg_temp._tarde(v_phone, 'ligado', 'novo', true, 'Outro texto.');
  select q.source, q.message, q.dedupe_key, q.max_attempts, q.priority into v_fila
    from public.whatsapp_send_queue q where q.phone_normalized = v_phone;
  -- a manhã do outro telefone foi a sombra: enviar é recusado pela RPC
  perform pg_temp._manha(v_sem, 'sombra');
  v_c := public.resumo_tarde_registrar(jsonb_build_object('dia', pg_temp._hoje(), 'phone', v_sem, 'turno', 'fechamento', 'modo', 'novo',
    'formato', 'ligado', 'texto', 'x', 'enviado', true));
  select count(*) into v_sem_linhas from public.resumo_tarde where phone_normalized = v_sem;
  insert into _resultado values ('T4 ligado com a manhã nova enfileira uma vez (mesma transação); sem a manhã nova, nada',
    (v_a->>'enviado')::boolean and (v_a->>'na_fila')::int = 1 and not (v_b->>'novo')::boolean and pg_temp._fila(v_phone) = 1
      and v_fila.source = 'ai_briefing_tarde' and v_fila.message = 'Fechamento enviado.' and v_fila.max_attempts = 7 and v_fila.priority = 4
      and v_fila.dedupe_key = 'secretario_tarde:' || pg_temp._hoje() || ':' || v_phone
      and v_c->>'erro' = 'manha_nao_e_nova' and v_sem_linhas = 0 and pg_temp._fila(v_sem) = 0,
    'fila=' || pg_temp._fila(v_phone) || ' source=' || coalesce(v_fila.source, '-') || ' sem_manha_nova=' || coalesce(v_c->>'erro', '-'));
exception when others then
  insert into _resultado values ('T4 ligado com a manhã nova enfileira uma vez (mesma transação); sem a manhã nova, nada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T5 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_r jsonb;
  v_recusas text[] := '{}';
  v_calado boolean;
begin
  perform pg_temp._manha(v_phone, 'novo');
  -- calado não tem o que enviar: pedir enviado num dia calado é recusado pelo CHECK
  begin
    perform pg_temp._tarde(v_phone, 'ligado', 'novo', true, null);
  exception when check_violation then
    v_recusas := v_recusas || 'calado_enviado'::text;
  end;
  v_r := pg_temp._tarde(v_phone, 'ligado', 'novo', false, null);
  select calado into v_calado from public.resumo_tarde where phone_normalized = v_phone;
  begin
    insert into public.resumo_tarde (dia, phone_normalized, turno, modo, formato, texto, calado)
    values (pg_temp._hoje() - 30, v_phone, 'fechamento', 'sombra', 'sombra', 'tem texto', true);
  exception when check_violation then
    v_recusas := v_recusas || 'calado_com_texto'::text;
  end;
  begin
    insert into public.resumo_tarde (dia, phone_normalized, turno, modo, formato, texto, calado)
    values (pg_temp._hoje() - 31, v_phone, 'fechamento', 'sombra', 'sombra', null, false);
  exception when check_violation then
    v_recusas := v_recusas || 'sem_texto'::text;
  end;
  insert into _resultado values ('T5 o dia calado: sem texto e sem fila; CHECKs do calado',
    (v_r->>'novo')::boolean and v_calado and v_r->>'texto' is null and pg_temp._fila(v_phone) = 0 and cardinality(v_recusas) = 3,
    'recusados: ' || array_to_string(v_recusas, ', ') || ' fila=' || pg_temp._fila(v_phone));
exception when others then
  insert into _resultado values ('T5 o dia calado: sem texto e sem fila; CHECKs do calado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T6 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_falta jsonb;
  v_rep jsonb;
  v_data jsonb;
  v_ok jsonb;
  v_mudou integer;
  v_b integer;
  v_hist jsonb;
begin
  perform pg_temp._manha(v_phone, 'novo');
  v_falta := public.resumo_itens_acoes(jsonb_build_object('phone', v_phone, 'modo', 'novo', 'acoes', jsonb_build_array(
    jsonb_build_object('letra', 'A', 'acao', 'adiado', 'ate', pg_temp._hoje() + 7, 'resposta', 'semana'),
    jsonb_build_object('letra', 'Z', 'acao', 'tirado'))));
  v_rep := public.resumo_itens_acoes(jsonb_build_object('phone', v_phone, 'modo', 'novo', 'acoes', jsonb_build_array(
    jsonb_build_object('letra', 'A', 'acao', 'tirado'), jsonb_build_object('letra', 'a', 'acao', 'feito'))));
  v_data := public.resumo_itens_acoes(jsonb_build_object('phone', v_phone, 'modo', 'novo', 'acoes', jsonb_build_array(
    jsonb_build_object('letra', 'A', 'acao', 'tirado'), jsonb_build_object('letra', 'D', 'acao', 'adiado', 'ate', pg_temp._hoje() + 91))));
  select count(*) into v_mudou from public.resumo_itens where phone_normalized = v_phone and acao is not null;
  v_ok := public.resumo_itens_acoes(jsonb_build_object('phone', v_phone, 'modo', 'novo', 'acoes', jsonb_build_array(
    jsonb_build_object('letra', 'A', 'acao', 'adiado', 'ate', pg_temp._hoje() + 7, 'resposta', 'semana'),
    jsonb_build_object('letra', 'b', 'acao', 'adiado', 'ate', pg_temp._hoje() + 15, 'resposta', '15dias'),
    jsonb_build_object('letra', 'D', 'acao', 'tirado'))));
  select count(*) into v_b from public.resumo_itens
   where phone_normalized = v_phone and letra = 'B' and acao = 'adiado' and adiado_ate = pg_temp._hoje() + 15;
  select historico -> -1 into v_hist from public.resumo_itens where phone_normalized = v_phone and letra = 'A';
  insert into _resultado values ('T6 resumo_itens_acoes: tudo ou nada; grava em todos os itens da letra com via lote',
    v_falta->>'resultado' = 'nao_achei' and v_falta->'letras' = '["Z"]'::jsonb and v_rep->>'erro' = 'letra_repetida'
      and v_data->>'erro' = 'ate' and v_mudou = 0 and v_ok->>'resultado' = 'feito' and jsonb_array_length(v_ok->'itens') = 3
      and v_b = 2 and v_hist->>'via' = 'lote' and v_hist->>'resposta' = 'semana' and v_hist->>'acao' = 'adiado',
    'falta=' || coalesce(v_falta->>'resultado', '-') || ' rep=' || coalesce(v_rep->>'erro', '-') || ' data=' || coalesce(v_data->>'erro', '-')
      || ' mudou_antes=' || v_mudou || ' B=' || v_b || ' hist=' || coalesce(v_hist::text, '-'));
exception when others then
  insert into _resultado values ('T6 resumo_itens_acoes: tudo ou nada; grava em todos os itens da letra com via lote', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T7 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_sombra text := pg_temp._telefone();
  v_sem jsonb;
  v_a jsonb;
  v_b jsonb;
  v_s jsonb;
  v_inv jsonb;
  v_resp text;
begin
  v_sem := public.resumo_semana_responder(jsonb_build_object('phone', v_phone, 'resposta', 'ajudou'));
  perform pg_temp._manha(v_phone, 'novo');
  perform pg_temp._tarde(v_phone, 'ligado', 'novo', true, 'Fechamento de sexta. A semana ajudou?', true);
  v_a := public.resumo_semana_responder(jsonb_build_object('phone', v_phone, 'resposta', 'ajudou'));
  v_b := public.resumo_semana_responder(jsonb_build_object('phone', v_phone, 'resposta', 'atrapalhou'));
  v_inv := public.resumo_semana_responder(jsonb_build_object('phone', v_phone, 'resposta', 'mais ou menos'));
  select resposta_semana into v_resp from public.resumo_tarde where phone_normalized = v_phone;
  perform pg_temp._manha(v_sombra, 'sombra');
  perform pg_temp._tarde(v_sombra, 'sombra', 'sombra', false, 'Fechamento de sexta (sombra).', true);
  v_s := public.resumo_semana_responder(jsonb_build_object('phone', v_sombra, 'resposta', 'pouco'));
  insert into _resultado values ('T7 a pergunta da sexta: sem pergunta enviada = sem_pergunta; gravado; trocado; sombra não responde',
    v_sem->>'resultado' = 'sem_pergunta' and v_a->>'resultado' = 'gravado' and v_b->>'resultado' = 'trocado' and v_b->>'antes' = 'ajudou'
      and v_resp = 'atrapalhou' and v_s->>'resultado' = 'sem_pergunta' and v_inv->>'resultado' = 'invalido',
    'sem=' || coalesce(v_sem->>'resultado', '-') || ' a=' || coalesce(v_a->>'resultado', '-') || ' b=' || coalesce(v_b->>'resultado', '-')
      || ' resposta=' || coalesce(v_resp, '-') || ' sombra=' || coalesce(v_s->>'resultado', '-'));
exception when others then
  insert into _resultado values ('T7 a pergunta da sexta: sem pergunta enviada = sem_pergunta; gravado; trocado; sombra não responde', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T8 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_quem uuid;
  v_papel text;
  v_viu integer;
  v_viram text := '';
  v_vazou boolean := false;
  v_admin uuid := pg_temp._usuario('admin');
  v_viu_admin integer;
begin
  perform pg_temp._manha(v_phone, 'sombra');
  perform pg_temp._tarde(v_phone, 'sombra', 'sombra', false);
  begin
    foreach v_papel in array array['financial', 'technician'] loop
      v_quem := pg_temp._usuario(v_papel);
      perform set_config('request.jwt.claim.sub', v_quem::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
      set local role authenticated;
      select count(*) into v_viu from public.resumo_tarde where phone_normalized = v_phone;
      reset role;
      v_viram := v_viram || v_papel || ' vê ' || v_viu || '; ';
      v_vazou := v_vazou or v_viu <> 0;
    end loop;
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_viu_admin from public.resumo_tarde where phone_normalized = v_phone;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('T8 só o admin lê resumo_tarde', not v_vazou and v_viu_admin = 1, v_viram || 'admin vê ' || v_viu_admin);
  exception when others then
    reset role;
    insert into _resultado values ('T8 só o admin lê resumo_tarde', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T9 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_fin uuid := pg_temp._usuario('financial');
  v_admin uuid := pg_temp._usuario('admin');
  v_recusou boolean := false;
  v_admin_mudou boolean := false;
  v_antes text;
begin
  select value into v_antes from public.app_settings where key = 'fechamento_formato';
  perform set_config('request.jwt.claim.sub', v_fin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_fin, 'role', 'authenticated')::text, true);
  begin
    update public.app_settings set value = 'ligado' where key = 'fechamento_formato';
  exception when insufficient_privilege then
    v_recusou := true;
  end;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  update public.app_settings set value = 'sombra' where key = 'fechamento_formato';
  v_admin_mudou := (select value from public.app_settings where key = 'fechamento_formato') = 'sombra';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T9 a chave existe; o financeiro não muda fechamento_formato (42501); o admin muda',
    v_antes in ('desligado', 'sombra', 'ligado') and v_recusou and v_admin_mudou,
    'antes=' || coalesce(v_antes, 'null') || ' recusou=' || v_recusou || ' admin=' || v_admin_mudou || ' (desfeito no rollback)');
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T9 a chave existe; o financeiro não muda fechamento_formato (42501); o admin muda', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T10 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_md5 jsonb;
begin
  select jsonb_object_agg(p.proname, md5(regexp_replace(lower(p.prosrc), '\s', '', 'g'))) into v_md5
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('resumo_registrar', 'resumo_item_acao', 'resumo_item_voltar');
  insert into _resultado values ('T10 as RPCs da manhã não mudaram (md5 = produção em 15/10/2026)',
    v_md5->>'resumo_registrar' = '1ac21f289fd0a14c459d8acdd8dbbd70' and v_md5->>'resumo_item_acao' = 'ca6b76181fdaf147d4b0bc97a77afa5a'
      and v_md5->>'resumo_item_voltar' = '6732f31d93a98d47c389c00e4085b3aa',
    coalesce(v_md5::text, 'null'));
exception when others then
  insert into _resultado values ('T10 as RPCs da manhã não mudaram (md5 = produção em 15/10/2026)', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
