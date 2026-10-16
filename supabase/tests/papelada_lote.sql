-- Prova: o lote semanal da papelada (migration 20261016130000_papelada_lote).
--
--   T1  anon/authenticated sem execute nas 3 RPCs (service_role com); papelada_lote com RLS, anon sem nada,
--       authenticated só lê (e só o admin vê linhas)
--   T2  papelada_lote_registrar grava uma vez; o 2º disparo no mesmo dia devolve o MESMO lote
--   T3  registrar recusa entrada ruim (sem telefone, formato estranho, item sem impressão, item repetido) sem gravar
--   T4  SOMBRA NUNCA É APLICADA: conferir com aplicar=true recusa ('sombra', nada muda); o CHECK recusa o update direto
--   T5  conferir sem aplicar (só leitura): o que mudou desde a sexta sai com o motivo — já decidido na tela, impressão
--       diferente (a reavaliação trocou a categoria), linha do banco já lançada, aviso novo na mesma linha; o resto
--       passa; nada é gravado
--   T6  aplicar só pelo admin ('so_admin' para financeiro e para ninguém); item fora do lote = nada conferido nem gravado
--   T7  aplicar trava o lote (pronto → aplicando, escolhidos = os válidos, quem aprovou); o 2º "sim" é recusado
--   T8  resultado lê a fila item por item depois do approve de sempre: entrou (aprovada, com o lançamento), falhou (com
--       o motivo que o servidor devolveu), incompleto (lançamento sem a proposta fechar), saiu (superseded) e os de
--       fora da conferência; fecha o lote (aplicado); rodar de novo devolve o gravado
--   T9  lote vencido: conferir recusa; com aplicar marca 'vencido'; sem aplicar não grava nada
--   T10 o lote novo (outro dia) substitui o pronto anterior do mesmo telefone; o que está aplicando não é tocado
--   T11 só o admin muda papelada_lote (o financeiro recebe 42501); a chave existe com um dos 3 valores
--   T12 o gatilho das chaves continua protegendo as chaves de antes (resumo_formato, voz_unica…)
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado; também roda no ensaio PGlite da bancada,
--   D:/IA-HBR/comprovantes-bancada/pglite-ensaio/rodar-papelada.mjs)
--
--   supabase db query --linked -f supabase/tests/papelada_lote.sql --output json
--
-- Seguro em produção: telefones de mentira 55000…, usuários, linhas do extrato, propostas e despesas de teste
-- criados na transação (sem categoria, valores de centavos, data de hoje), nenhum id fixo, nada chama a edge, e
-- termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _ctx (hoje date) on commit drop;
insert into _ctx values ((now() at time zone 'America/Sao_Paulo')::date);

create function pg_temp._hoje() returns date language sql stable as $$ select hoje from _ctx $$;

create function pg_temp._telefone() returns text language sql volatile as $$
  select '55000' || lpad((floor(random() * 1000000000))::bigint::text, 9, '0')
$$;

create function pg_temp._usuario(p_papel text) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste lote ' || p_papel, 'teste-lote-' || v_id || '@teste.invalido', p_papel, true);
  return v_id;
end $$;

-- uma linha de saída do extrato (centavos, hoje)
create function pg_temp._linha(p_valor numeric) returns uuid language sql as $$
  insert into public.bank_transactions (transaction_date, description, amount, transaction_type, source_type, counterparty_name)
  values (pg_temp._hoje(), 'TESTE LOTE PAPELADA', p_valor, 'debit', 'bank', 'TESTE LOTE PAPELADA') returning id
$$;

-- a proposta pendente da fila para a linha
create function pg_temp._proposta(p_tx uuid, p_valor numeric, p_kind text default 'create_payable',
                                  p_categoria text default 'Pagamento de fatura de cartão') returns uuid language sql as $$
  insert into public.finance_review_queue (kind, status, bank_transaction_id, related_transaction_id, title, confidence,
                                           suggested_amount, suggested_date, suggested_category, reasoning)
  values (p_kind, 'pending', case when p_kind = 'anomaly' then null else p_tx end, case when p_kind = 'anomaly' then p_tx end,
          'Teste lote ' || left(gen_random_uuid()::text, 8), 95, p_valor, pg_temp._hoje(), p_categoria, 'motor de teste')
  returning id
$$;

-- o item do lote como a edge grava: a impressão é a proposta de agora
create function pg_temp._item(p_n int, p_id uuid, p_grupo text default 'despesa') returns jsonb language sql stable as $$
  select jsonb_build_object('n', p_n, 'id', q.id, 'grupo', p_grupo, 'titulo', q.title, 'valor', q.suggested_amount,
           'categoria', q.suggested_category, 'codigo', 'categoria', 'motivo', 'teste',
           'impressao', jsonb_build_object('kind', q.kind, 'valor', q.suggested_amount, 'categoria', q.suggested_category,
                                           'data', q.suggested_date, 'regra', q.applied_rule_id,
                                           'vinculo', q.vinculo_sugerido is not null))
    from public.finance_review_queue q where q.id = p_id
$$;

create function pg_temp._registrar(p_phone text, p_formato text, p_itens jsonb, p_dia date default null,
                                   p_valido timestamptz default null) returns jsonb language sql as $$
  select public.papelada_lote_registrar(jsonb_build_object(
    'dia', coalesce(p_dia, pg_temp._hoje()), 'phone', p_phone, 'formato', p_formato, 'itens', p_itens,
    'excecoes', '[{"id": "x", "grupo": "despesa", "codigo": "sem_loja", "motivo": "teste"}]'::jsonb,
    'contagens', '{"itens": 1}'::jsonb, 'total', 1.23, 'linha', 'Escritório da semana: teste. *lote*',
    'valido_ate', coalesce(p_valido, now() + interval '7 days')))
$$;

-- ═══ T1 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_rpc text;
  v_aberta text := '';
  v_t text := 'public.papelada_lote';
begin
  foreach v_rpc in array array['public.papelada_lote_registrar(jsonb)', 'public.papelada_lote_conferir(jsonb)',
                               'public.papelada_lote_resultado(jsonb)'] loop
    if has_function_privilege('anon', v_rpc, 'execute') or has_function_privilege('authenticated', v_rpc, 'execute')
       or not has_function_privilege('service_role', v_rpc, 'execute') then
      v_aberta := v_aberta || v_rpc || ' ';
    end if;
  end loop;
  insert into _resultado values ('T1 RPCs só para service_role; tabela com RLS, anon sem nada, authenticated só lê',
    v_aberta = ''
    and (select relrowsecurity from pg_class where oid = v_t::regclass)
    and not has_table_privilege('anon', v_t, 'select')
    and has_table_privilege('authenticated', v_t, 'select')
    and not has_table_privilege('authenticated', v_t, 'insert')
    and not has_table_privilege('authenticated', v_t, 'update'),
    case when v_aberta = '' then 'portas fechadas' else 'abertas: ' || v_aberta end);
end $$;

-- ═══ T2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_p uuid := pg_temp._proposta(pg_temp._linha(0.11), 0.11);
  v_q uuid := pg_temp._proposta(pg_temp._linha(0.12), 0.12);
  v_r1 jsonb;
  v_r2 jsonb;
begin
  v_r1 := pg_temp._registrar(v_phone, 'sombra', jsonb_build_array(pg_temp._item(1, v_p)));
  -- o 2º disparo (17:40) remonta com a fila de agora: o lote gravado às 17:30 é o que vale
  v_r2 := pg_temp._registrar(v_phone, 'sombra', jsonb_build_array(pg_temp._item(1, v_p), pg_temp._item(2, v_q)));
  insert into _resultado values ('T2 registrar grava uma vez; o 2º disparo devolve o mesmo lote',
    (v_r1->>'ok')::boolean and (v_r1->>'novo')::boolean and (v_r2->>'ok')::boolean and not (v_r2->>'novo')::boolean
    and v_r1->>'id' = v_r2->>'id'
    and (select count(*) from public.papelada_lote where phone_normalized = v_phone) = 1
    and (select jsonb_array_length(itens) from public.papelada_lote where phone_normalized = v_phone) = 1,
    'r1=' || v_r1::text || ' r2=' || v_r2::text);
exception when others then
  insert into _resultado values ('T2 registrar grava uma vez; o 2º disparo devolve o mesmo lote', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T3 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_p uuid := pg_temp._proposta(pg_temp._linha(0.12), 0.12);
  v_a jsonb;
  v_b jsonb;
  v_c jsonb;
  v_d jsonb;
begin
  v_a := public.papelada_lote_registrar(jsonb_build_object('dia', pg_temp._hoje(), 'formato', 'sombra', 'itens', '[]'::jsonb));
  v_b := pg_temp._registrar(v_phone, 'enviado', jsonb_build_array(pg_temp._item(1, v_p)));
  v_c := pg_temp._registrar(v_phone, 'sombra', jsonb_build_array(pg_temp._item(1, v_p) - 'impressao'));
  v_d := pg_temp._registrar(v_phone, 'sombra', jsonb_build_array(pg_temp._item(1, v_p), pg_temp._item(2, v_p) || jsonb_build_object('n', 2)));
  insert into _resultado values ('T3 registrar recusa entrada ruim sem gravar',
    not (v_a->>'ok')::boolean and not (v_b->>'ok')::boolean and not (v_c->>'ok')::boolean and not (v_d->>'ok')::boolean
    and (select count(*) from public.papelada_lote where phone_normalized = v_phone) = 0,
    concat_ws(' | ', v_a->>'erro', v_b->>'erro', v_c->>'erro', v_d->>'erro'));
exception when others then
  insert into _resultado values ('T3 registrar recusa entrada ruim sem gravar', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T4 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_admin uuid := pg_temp._usuario('admin');
  v_p uuid := pg_temp._proposta(pg_temp._linha(0.13), 0.13);
  v_lote uuid;
  v_r jsonb;
  v_check boolean := false;
begin
  v_lote := (pg_temp._registrar(v_phone, 'sombra', jsonb_build_array(pg_temp._item(1, v_p)))->>'id')::uuid;
  v_r := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote, 'aplicar', true, 'app_user_id', v_admin));
  begin
    update public.papelada_lote set status = 'aplicando', escolhidos = '[]'::jsonb, aplicado_por = v_admin,
                                    aplicacao_inicio = now() where id = v_lote;
  exception when check_violation then
    v_check := true;
  end;
  insert into _resultado values ('T4 a sombra nunca é aplicada (RPC recusa; CHECK recusa o update direto)',
    not (v_r->>'ok')::boolean and v_r->>'erro' = 'sombra' and v_check
    and (select status from public.papelada_lote where id = v_lote) = 'pronto'
    and (select escolhidos is null from public.papelada_lote where id = v_lote)
    and (select status from public.finance_review_queue where id = v_p) = 'pending',
    'rpc=' || v_r::text || ' check=' || v_check);
exception when others then
  insert into _resultado values ('T4 a sombra nunca é aplicada (RPC recusa; CHECK recusa o update direto)', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T5 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_ok uuid := pg_temp._proposta(pg_temp._linha(0.21), 0.21);
  v_tela uuid := pg_temp._proposta(pg_temp._linha(0.22), 0.22);
  v_mudou uuid := pg_temp._proposta(pg_temp._linha(0.23), 0.23);
  v_tx_lanc uuid := pg_temp._linha(0.24);
  v_lanc uuid := pg_temp._proposta(v_tx_lanc, 0.24);
  v_tx_aviso uuid := pg_temp._linha(0.25);
  v_aviso uuid := pg_temp._proposta(v_tx_aviso, 0.25);
  v_lote uuid;
  v_r jsonb;
  v_fora text;
begin
  v_lote := (pg_temp._registrar(v_phone, 'ligado', jsonb_build_array(
    pg_temp._item(1, v_ok), pg_temp._item(2, v_tela), pg_temp._item(3, v_mudou), pg_temp._item(4, v_lanc), pg_temp._item(5, v_aviso)))->>'id')::uuid;
  -- depois da sexta: o dono aprovou uma na tela; a reavaliação trocou a categoria de outra; a linha de uma ganhou
  -- despesa por outro caminho; outra ganhou um aviso do vigia
  update public.finance_review_queue set status = 'approved', decided_at = now() where id = v_tela;
  update public.finance_review_queue set suggested_category = 'Juros e encargos' where id = v_mudou;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id, origin)
  values ('Teste lote: lançada por outro caminho', pg_temp._hoje(), pg_temp._hoje(), 0.24, 0.24, 0, 'paid', v_tx_lanc, 'bank_reconciliation');
  perform pg_temp._proposta(v_tx_aviso, 0.25, 'anomaly', null);

  v_r := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote));
  select string_agg((f->>'n') || ':' || (f->>'codigo'), ',' order by (f->>'n')::int) into v_fora from jsonb_array_elements(v_r->'fora') f;
  insert into _resultado values ('T5 conferir (só leitura): o que mudou desde a sexta sai com o motivo; nada é gravado',
    (v_r->>'ok')::boolean and v_r->'validos' = jsonb_build_array(v_ok::text)
    and v_fora = '2:ja_decidido_approved,3:mudou,4:ja_lancado,5:aviso_novo'
    and (select status from public.papelada_lote where id = v_lote) = 'pronto'
    and (select escolhidos is null and resultado is null from public.papelada_lote where id = v_lote),
    'fora=' || coalesce(v_fora, '-') || ' validos=' || (v_r->'validos')::text);
exception when others then
  insert into _resultado values ('T5 conferir (só leitura): o que mudou desde a sexta sai com o motivo; nada é gravado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T6 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_fin uuid := pg_temp._usuario('financial');
  v_admin uuid := pg_temp._usuario('admin');
  v_p uuid := pg_temp._proposta(pg_temp._linha(0.31), 0.31);
  v_outra uuid := pg_temp._proposta(pg_temp._linha(0.32), 0.32);
  v_lote uuid;
  v_a jsonb;
  v_b jsonb;
  v_c jsonb;
  v_d jsonb;
begin
  v_lote := (pg_temp._registrar(v_phone, 'ligado', jsonb_build_array(pg_temp._item(1, v_p)))->>'id')::uuid;
  v_a := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote, 'aplicar', true, 'app_user_id', v_fin));
  v_b := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote, 'aplicar', true));
  v_c := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote, 'aplicar', true, 'app_user_id', v_admin,
                                                         'ids', jsonb_build_array(v_p, v_outra)));
  -- lista vazia não é "o lote todo"
  v_d := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote, 'aplicar', true, 'app_user_id', v_admin,
                                                         'ids', '[]'::jsonb));
  insert into _resultado values ('T6 aplicar só pelo admin; item fora do lote ou lista vazia = nada gravado',
    v_a->>'erro' = 'so_admin' and v_b->>'erro' = 'so_admin' and v_c->>'erro' = 'item_fora_do_lote'
    and v_d->>'erro' = 'nada_escolhido'
    and (select status from public.papelada_lote where id = v_lote) = 'pronto',
    concat_ws(' | ', v_a->>'erro', v_b->>'erro', v_c->>'erro', v_d->>'erro'));
exception when others then
  insert into _resultado values ('T6 aplicar só pelo admin; item fora do lote = nada gravado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T7 e T8 ══════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_admin uuid := pg_temp._usuario('admin');
  v_entra uuid := pg_temp._proposta(pg_temp._linha(0.41), 0.41);
  v_falha uuid := pg_temp._proposta(pg_temp._linha(0.42), 0.42);
  v_tx_meia uuid := pg_temp._linha(0.43);
  v_meia uuid := pg_temp._proposta(v_tx_meia, 0.43);
  v_saiu uuid := pg_temp._proposta(pg_temp._linha(0.44), 0.44);
  v_mudou uuid := pg_temp._proposta(pg_temp._linha(0.45), 0.45);
  v_aviso uuid := pg_temp._proposta(pg_temp._linha(0.46), 0.46, 'anomaly', null);
  v_lote uuid;
  v_c jsonb;
  v_c2 jsonb;
  v_r jsonb;
  v_r2 jsonb;
  v_pay uuid;
  v_sits text;
  v_titulo text;
begin
  v_lote := (pg_temp._registrar(v_phone, 'ligado', jsonb_build_array(
    pg_temp._item(1, v_entra), pg_temp._item(2, v_falha), pg_temp._item(3, v_meia), pg_temp._item(4, v_saiu),
    pg_temp._item(5, v_mudou), pg_temp._item(6, v_aviso, 'aviso')))->>'id')::uuid;
  update public.finance_review_queue set suggested_amount = 0.99 where id = v_mudou;

  -- T7: o "sim" trava o lote, só com os válidos; o 2º "sim" é recusado
  v_c := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote, 'aplicar', true, 'app_user_id', v_admin,
                                                         'pendencia_id', gen_random_uuid()));
  v_c2 := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote, 'aplicar', true, 'app_user_id', v_admin));
  insert into _resultado values ('T7 aplicar trava o lote (aplicando, só os válidos, quem aprovou); o 2º "sim" é recusado',
    (v_c->>'ok')::boolean and jsonb_array_length(v_c->'validos') = 5 and jsonb_array_length(v_c->'fora') = 1
    and v_c2->>'erro' = 'lote_aplicando'
    and (select status = 'aplicando' and aplicado_por = v_admin and jsonb_array_length(escolhidos) = 5 and pendencia_id is not null
           from public.papelada_lote where id = v_lote),
    'c=' || v_c::text || ' c2=' || (v_c2->>'erro'));

  -- o approve de sempre (finance-review) fez o seu trabalho: uma entrou, uma falhou, uma ficou pela metade, uma já
  -- estava lançada (superseded), o aviso entrou (ciente)
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id, origin)
  values ('Teste lote: entrou', pg_temp._hoje(), pg_temp._hoje(), 0.41, 0.41, 0, 'paid',
          (select bank_transaction_id from public.finance_review_queue where id = v_entra), 'bank_reconciliation')
  returning id into v_pay;
  update public.finance_review_queue set status = 'approved', decided_by = v_admin, decided_at = now(), created_payable_id = v_pay where id = v_entra;
  insert into public.payables (description, issue_date, due_date, amount, paid_amount, balance_amount, status, bank_transaction_id, origin)
  values ('Teste lote: pela metade', pg_temp._hoje(), pg_temp._hoje(), 0.43, 0.43, 0, 'paid', v_tx_meia, 'bank_reconciliation');
  update public.finance_review_queue set status = 'superseded' where id = v_saiu;
  update public.finance_review_queue set status = 'approved', decided_by = v_admin, decided_at = now() where id = v_aviso;
  select title into v_titulo from public.finance_review_queue where id = v_falha;

  v_r := public.papelada_lote_resultado(jsonb_build_object('lote_id', v_lote,
    'resposta', jsonb_build_object('aprovadas', 2, 'falhas', jsonb_build_array(v_titulo || ': Pode ser algo já lançado — abra a linha'))));
  v_r2 := public.papelada_lote_resultado(jsonb_build_object('lote_id', v_lote));
  select string_agg((i->>'n') || ':' || (i->>'situacao'), ',' order by (i->>'n')::int) into v_sits from jsonb_array_elements(v_r->'itens') i;
  insert into _resultado values ('T8 resultado pelo banco: entrou, falhou (com o motivo do servidor), incompleto, saiu, fora; fecha o lote; 2ª vez = o gravado',
    (v_r->>'ok')::boolean and v_sits = '1:entrou,2:falhou,3:incompleto,4:saiu,5:fora,6:entrou'
    and (v_r->>'entrou')::int = 2 and (v_r->>'falhou')::int = 3 and (v_r->>'fora')::int = 1
    and (v_r->>'valor_entrou')::numeric = 0.41
    and exists (select 1 from jsonb_array_elements(v_r->'itens') i where i->>'n' = '2' and i->>'motivo' = 'Pode ser algo já lançado — abra a linha')
    and exists (select 1 from jsonb_array_elements(v_r->'itens') i where i->>'n' = '1' and i->>'payable_id' = v_pay::text)
    and (select status = 'aplicado' and aplicado_em is not null from public.papelada_lote where id = v_lote)
    and (v_r2->>'ja')::boolean and v_r2->'itens' = v_r->'itens',
    'situacoes=' || coalesce(v_sits, '-') || ' entrou=' || (v_r->>'entrou') || ' 2a=' || coalesce(v_r2->>'ja', '-'));
exception when others then
  insert into _resultado values ('T7/T8 aplicar e resultado', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T9 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_admin uuid := pg_temp._usuario('admin');
  v_p uuid := pg_temp._proposta(pg_temp._linha(0.51), 0.51);
  v_lote uuid;
  v_a jsonb;
  v_b jsonb;
  v_status_meio text;
begin
  v_lote := (pg_temp._registrar(v_phone, 'ligado', jsonb_build_array(pg_temp._item(1, v_p)), null, now() - interval '1 minute')->>'id')::uuid;
  v_a := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote));
  select status into v_status_meio from public.papelada_lote where id = v_lote;
  v_b := public.papelada_lote_conferir(jsonb_build_object('lote_id', v_lote, 'aplicar', true, 'app_user_id', v_admin));
  insert into _resultado values ('T9 lote vencido: recusado; só o "sim" marca vencido',
    v_a->>'erro' = 'lote_vencido' and v_status_meio = 'pronto' and v_b->>'erro' = 'lote_vencido'
    and (select status from public.papelada_lote where id = v_lote) = 'vencido',
    concat_ws(' | ', v_a->>'erro', v_status_meio, v_b->>'erro'));
exception when others then
  insert into _resultado values ('T9 lote vencido: recusado; só o "sim" marca vencido', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T10 ══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_outro text := pg_temp._telefone();
  v_admin uuid := pg_temp._usuario('admin');
  v_p uuid := pg_temp._proposta(pg_temp._linha(0.61), 0.61);
  v_q uuid := pg_temp._proposta(pg_temp._linha(0.62), 0.62);
  v_velho uuid;
  v_aplicando uuid;
  v_do_outro uuid;
  v_novo jsonb;
begin
  v_velho := (pg_temp._registrar(v_phone, 'ligado', jsonb_build_array(pg_temp._item(1, v_p)), pg_temp._hoje() - 14)->>'id')::uuid;
  v_aplicando := (pg_temp._registrar(v_phone, 'ligado', jsonb_build_array(pg_temp._item(1, v_q)), pg_temp._hoje() - 7)->>'id')::uuid;
  v_do_outro := (pg_temp._registrar(v_outro, 'ligado', jsonb_build_array(pg_temp._item(1, v_p)), pg_temp._hoje() - 7)->>'id')::uuid;
  -- o de 7 dias atrás está no meio de um "sim"
  update public.papelada_lote set status = 'aplicando', escolhidos = '[]'::jsonb, aplicado_por = v_admin, aplicacao_inicio = now()
   where id = v_aplicando;
  v_novo := pg_temp._registrar(v_phone, 'ligado', jsonb_build_array(pg_temp._item(1, v_p)));
  insert into _resultado values ('T10 o lote novo substitui o pronto anterior do mesmo telefone (não o aplicando, não o de outro telefone)',
    (v_novo->>'novo')::boolean
    and (select status from public.papelada_lote where id = v_velho) = 'substituido'
    and (select status from public.papelada_lote where id = v_aplicando) = 'aplicando'
    and (select status from public.papelada_lote where id = v_do_outro) = 'pronto',
    'velho=' || (select status from public.papelada_lote where id = v_velho));
exception when others then
  insert into _resultado values ('T10 o lote novo substitui o pronto anterior do mesmo telefone (não o aplicando, não o de outro telefone)', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ T1b (RLS por papel) ═══════════════════════════════════════════════════════════════════════
do $$
declare
  v_phone text := pg_temp._telefone();
  v_p uuid := pg_temp._proposta(pg_temp._linha(0.71), 0.71);
  v_quem uuid;
  v_papel text;
  v_viu integer;
  v_viram text := '';
  v_vazou boolean := false;
  v_admin uuid := pg_temp._usuario('admin');
  v_viu_admin integer;
begin
  perform pg_temp._registrar(v_phone, 'sombra', jsonb_build_array(pg_temp._item(1, v_p)));
  begin
    foreach v_papel in array array['financial', 'technician'] loop
      v_quem := pg_temp._usuario(v_papel);
      perform set_config('request.jwt.claim.sub', v_quem::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
      set local role authenticated;
      select count(*) into v_viu from public.papelada_lote where phone_normalized = v_phone;
      reset role;
      v_viram := v_viram || v_papel || ' vê ' || v_viu || '; ';
      v_vazou := v_vazou or v_viu <> 0;
    end loop;
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select count(*) into v_viu_admin from public.papelada_lote where phone_normalized = v_phone;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('T1b só o admin lê papelada_lote', not v_vazou and v_viu_admin = 1, v_viram || 'admin vê ' || v_viu_admin);
  exception when others then
    reset role;
    insert into _resultado values ('T1b só o admin lê papelada_lote', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ T11 e T12 ════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_fin uuid := pg_temp._usuario('financial');
  v_admin uuid := pg_temp._usuario('admin');
  v_recusou boolean := false;
  v_recusou_resumo boolean := false;
  v_recusou_voz boolean := false;
  v_admin_mudou boolean := false;
  v_antes text;
begin
  select value into v_antes from public.app_settings where key = 'papelada_lote';
  perform set_config('request.jwt.claim.sub', v_fin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_fin, 'role', 'authenticated')::text, true);
  begin
    update public.app_settings set value = 'ligado' where key = 'papelada_lote';
  exception when insufficient_privilege then
    v_recusou := true;
  end;
  begin
    update public.app_settings set value = 'novo' where key = 'resumo_formato';
  exception when insufficient_privilege then
    v_recusou_resumo := true;
  end;
  begin
    update public.app_settings set value = 'ligado' where key = 'voz_unica';
  exception when insufficient_privilege then
    v_recusou_voz := true;
  end;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  update public.app_settings set value = 'sombra' where key = 'papelada_lote';
  v_admin_mudou := (select value from public.app_settings where key = 'papelada_lote') = 'sombra';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T11 a chave existe; o financeiro não muda papelada_lote (42501); o admin muda',
    v_antes in ('desligado', 'sombra', 'ligado') and v_recusou and v_admin_mudou,
    'antes=' || coalesce(v_antes, 'null') || ' recusou=' || v_recusou || ' admin=' || v_admin_mudou || ' (desfeito no rollback)');
  insert into _resultado values ('T12 o gatilho continua protegendo resumo_formato e voz_unica', v_recusou_resumo and v_recusou_voz,
    'resumo=' || v_recusou_resumo || ' voz=' || v_recusou_voz);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('T11 a chave existe; o financeiro não muda papelada_lote (42501); o admin muda', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
