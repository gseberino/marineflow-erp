-- Prova: o registro da manhã nova do resumo (migration 20261015200000_resumo_secretario).
--
--   R1 anon/authenticated sem execute nas 3 RPCs (service_role com); tabelas com RLS, anon sem nada,
--      authenticated só lê
--   R2 resumo_registrar grava o dia e os itens; o segundo disparo no mesmo dia devolve o MESMO texto e
--      não duplica itens (as letras não mudam)
--   R3 o item de manhã de ontem sem ação vira "ignorado" no registrar de hoje; o que teve ação, o de
--      cartão aberto ("abriu") e o da lista não viram ignorado
--   R4 resumo_item_acao: adiado sem data / com data passada = invalido; com amanhã grava em TODOS os itens
--      da letra (o principal e o do mesmo assunto), com o histórico
--   R5 letra que não existe hoje = nao_achei; ação desconhecida = invalido
--   R6 resumo_item_voltar pela letra limpa a ação e marca voltou_em; pelo nome acha o assunto de outro dia
--   R7 CHECKs: letra N/S/E/I/O recusada, adiado sem data recusado, sombra enviada recusada
--   R8 só o admin lê (financeiro e técnico veem 0 linhas)
--   R9 só o admin muda resumo_formato (o financeiro recebe 42501); a chave existe
--   R10 a letra sozinha (o cartão pronto) grava "abriu" só no histórico; a ação não muda
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado; também roda no ensaio PGlite da bancada,
--   D:/IA-HBR/comprovantes-bancada/pglite-ensaio/rodar-secretario.mjs)
--
--   supabase db query --linked -f supabase/tests/resumo_secretario.sql --output json
--
-- Seguro em produção: telefones de mentira 55000…, usuários de teste criados na transação, nenhum
-- id fixo nem data fixa (o "hoje" é o dia de Brasília), e termina em ROLLBACK.
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

-- um usuário de verdade (ativo, com cargo) para as leituras com RLS
create function pg_temp._usuario(p_papel text) returns uuid language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into public.app_users (id, full_name, email, role, active)
  values (v_id, 'Teste resumo ' || p_papel, 'teste-resumo-' || v_id || '@teste.invalido', p_papel, true);
  return v_id;
end $$;

-- um item com o mínimo; o resto vem de p_extra
create function pg_temp._item(p_letra text, p_extra jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_build_object(
    'letra', p_letra, 'principal', true, 'posicao', 'manha', 'ordem', 0, 'familia', 'cobranca',
    'tipo', 'cobranca_grande', 'secao', 'dinheiro', 'referencia', 'recv:' || gen_random_uuid(),
    'assunto', 'cliente:' || gen_random_uuid(), 'nome', 'Marcelo Teste', 'nome_busca', 'marcelo teste',
    'fato', '16890.00|2026-10-13|grande', 'valor', 16890, 'titulo', '*Marcelo Teste*: R$ 16.890,00 venceu',
    'recomendacao', 'Recomendo um lembrete hoje.', 'motivo', 'Subiu porque é cobrança grande.',
    'pedido', 'Prepare um lembrete.', 'detalhe', jsonb_build_object('saldo', 16890)
  ) || p_extra
$$;

create function pg_temp._registrar(p_dia date, p_itens jsonb, p_texto text default 'Bom dia! Teste.',
                                   p_modo text default 'novo') returns jsonb language sql as $$
  select public.resumo_registrar(jsonb_build_object(
    'dia', p_dia, 'phone', pg_temp._phone(), 'modo', p_modo, 'tipo_do_dia', 'util', 'texto_novo', p_texto,
    'texto_antigo', '☀️ Bom dia! Resumo antigo de teste', 'escritorio', 'Escritório: teste',
    'enviado', p_modo = 'novo', 'itens_manha', 1, 'itens_lista', 0, 'itens', p_itens))
$$;

-- ═══ R1 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_f text;
  v_t text;
  v_falhas text[] := '{}';
begin
  foreach v_f in array array['public.resumo_registrar(jsonb)', 'public.resumo_item_acao(jsonb)', 'public.resumo_item_voltar(jsonb)'] loop
    if has_function_privilege('anon', v_f, 'execute') then v_falhas := v_falhas || ('anon executa ' || v_f); end if;
    if has_function_privilege('authenticated', v_f, 'execute') then v_falhas := v_falhas || ('authenticated executa ' || v_f); end if;
    if not has_function_privilege('service_role', v_f, 'execute') then v_falhas := v_falhas || ('service_role sem ' || v_f); end if;
  end loop;
  foreach v_t in array array['public.resumo_manha', 'public.resumo_itens'] loop
    if not (select relrowsecurity from pg_class where oid = v_t::regclass) then v_falhas := v_falhas || ('RLS desligada ' || v_t); end if;
    if has_table_privilege('anon', v_t, 'select') or has_table_privilege('anon', v_t, 'insert') then v_falhas := v_falhas || ('anon em ' || v_t); end if;
    if has_table_privilege('authenticated', v_t, 'insert') or has_table_privilege('authenticated', v_t, 'update')
       or has_table_privilege('authenticated', v_t, 'delete') then v_falhas := v_falhas || ('authenticated escreve ' || v_t); end if;
  end loop;
  insert into _resultado values ('R1 RPCs só para service_role; tabelas fechadas', cardinality(v_falhas) = 0,
    coalesce(nullif(array_to_string(v_falhas, ', '), ''), '3 funções e 2 tabelas conferidas'));
exception when others then
  insert into _resultado values ('R1 RPCs só para service_role; tabelas fechadas', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R2 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_ref text := 'recv:' || gen_random_uuid();
  v_a jsonb;
  v_b jsonb;
  v_n integer;
begin
  v_a := pg_temp._registrar(pg_temp._hoje(), jsonb_build_array(
    pg_temp._item('A', jsonb_build_object('referencia', v_ref)),
    pg_temp._item('A', jsonb_build_object('principal', false, 'familia', 'cliente', 'tipo', 'cliente_sem_resposta',
                                          'secao', 'clientes', 'referencia', 'fone:5500011112222', 'fato', '2026-10-14T20:00:00Z')),
    pg_temp._item('D', jsonb_build_object('posicao', 'lista', 'ordem', 3, 'tipo', 'cobranca_fora_do_marco'))),
    'Bom dia! Primeiro texto.');
  v_b := pg_temp._registrar(pg_temp._hoje(), jsonb_build_array(pg_temp._item('B')), 'Bom dia! Segundo texto.');
  select count(*) into v_n from public.resumo_itens where phone_normalized = pg_temp._phone() and dia = pg_temp._hoje();
  insert into _resultado values ('R2 registrar grava uma vez; o 2º disparo devolve o mesmo texto e não duplica',
    (v_a->>'novo')::boolean and not (v_b->>'novo')::boolean and v_b->>'texto_novo' = 'Bom dia! Primeiro texto.'
      and v_a->>'id' = v_b->>'id' and v_n = 3,
    'novo1=' || coalesce(v_a->>'novo', '-') || ' novo2=' || coalesce(v_b->>'novo', '-') || ' itens=' || v_n);
exception when others then
  insert into _resultado values ('R2 registrar grava uma vez; o 2º disparo devolve o mesmo texto e não duplica', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R3 ═══════════════════════════════════════════════════════════════════════════════════════
-- Ontem (outro telefone, para não mexer no dia de R2): A sem ação, B com "feito", C com o cartão aberto
-- (a letra sozinha: "abriu" no histórico), D da lista sem ação.
do $$
declare
  v_phone text := pg_temp._telefone();
  v_ontem date := pg_temp._hoje() - 1;
  v_r jsonb;
  v_a text;
  v_b text;
  v_c text;
  v_d text;
begin
  perform public.resumo_registrar(jsonb_build_object('dia', v_ontem, 'phone', v_phone, 'modo', 'novo', 'texto_novo', 'ontem',
    'itens', jsonb_build_array(pg_temp._item('A'), pg_temp._item('B', '{"ordem": 1}'::jsonb), pg_temp._item('C', '{"ordem": 2}'::jsonb),
                               pg_temp._item('D', '{"posicao": "lista", "ordem": 3}'::jsonb))));
  update public.resumo_itens set acao = 'feito', acao_em = now() where phone_normalized = v_phone and dia = v_ontem and letra = 'B';
  update public.resumo_itens set historico = jsonb_build_array(jsonb_build_object('acao', 'abriu', 'em', now()))
   where phone_normalized = v_phone and dia = v_ontem and letra = 'C';
  v_r := public.resumo_registrar(jsonb_build_object('dia', pg_temp._hoje(), 'phone', v_phone, 'modo', 'novo', 'texto_novo', 'hoje',
    'itens', '[]'::jsonb));
  select acao into v_a from public.resumo_itens where phone_normalized = v_phone and dia = v_ontem and letra = 'A';
  select acao into v_b from public.resumo_itens where phone_normalized = v_phone and dia = v_ontem and letra = 'B';
  select acao into v_c from public.resumo_itens where phone_normalized = v_phone and dia = v_ontem and letra = 'C';
  select acao into v_d from public.resumo_itens where phone_normalized = v_phone and dia = v_ontem and letra = 'D';
  insert into _resultado values ('R3 manhã de ontem sem ação vira ignorado; feito, cartão aberto e lista não mudam',
    v_a = 'ignorado' and v_b = 'feito' and v_c is null and v_d is null and (v_r->>'ignorados')::int = 1,
    'A=' || coalesce(v_a, 'null') || ' B=' || coalesce(v_b, 'null') || ' C=' || coalesce(v_c, 'null') || ' D=' || coalesce(v_d, 'null')
      || ' ignorados=' || coalesce(v_r->>'ignorados', '-'));
exception when others then
  insert into _resultado values ('R3 manhã de ontem sem ação vira ignorado; feito, cartão aberto e lista não mudam', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R4 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_sem jsonb;
  v_passado jsonb;
  v_ok jsonb;
  v_n integer;
  v_hist integer;
begin
  v_sem := public.resumo_item_acao(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'A', 'acao', 'adiado'));
  v_passado := public.resumo_item_acao(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'A', 'acao', 'adiado',
    'ate', pg_temp._hoje() - 1));
  v_ok := public.resumo_item_acao(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'a', 'acao', 'adiado',
    'ate', pg_temp._hoje() + 1));
  select count(*), min(jsonb_array_length(historico)) into v_n, v_hist from public.resumo_itens
   where phone_normalized = pg_temp._phone() and dia = pg_temp._hoje() and letra = 'A'
     and acao = 'adiado' and adiado_ate = pg_temp._hoje() + 1;
  insert into _resultado values ('R4 adiado: sem data e data passada recusados; amanhã vale para os 2 itens da letra',
    v_sem->>'resultado' = 'invalido' and v_passado->>'resultado' = 'invalido' and v_ok->>'resultado' = 'feito'
      and (v_ok->>'itens')::int = 2 and v_n = 2 and v_hist = 1 and v_ok->'item'->>'nome' = 'Marcelo Teste',
    'sem=' || coalesce(v_sem->>'resultado', '-') || ' passado=' || coalesce(v_passado->>'resultado', '-')
      || ' ok=' || coalesce(v_ok->>'resultado', '-') || ' itens=' || v_n);
exception when others then
  insert into _resultado values ('R4 adiado: sem data e data passada recusados; amanhã vale para os 2 itens da letra', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R5 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_x jsonb;
  v_y jsonb;
begin
  v_x := public.resumo_item_acao(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'Z', 'acao', 'feito'));
  v_y := public.resumo_item_acao(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'D', 'acao', 'apagar'));
  insert into _resultado values ('R5 letra que não existe hoje = nao_achei; ação desconhecida = invalido',
    v_x->>'resultado' = 'nao_achei' and v_y->>'resultado' = 'invalido',
    'Z=' || coalesce(v_x->>'resultado', '-') || ' apagar=' || coalesce(v_y->>'resultado', '-'));
exception when others then
  insert into _resultado values ('R5 letra que não existe hoje = nao_achei; ação desconhecida = invalido', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R6 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_letra jsonb;
  v_sem jsonb;
  v_nome jsonb;
  v_phone text := pg_temp._telefone();
  v_dia date := pg_temp._hoje() - 3;
  v_acao_a text;
  v_voltou boolean;
  v_acao_velho text;
begin
  -- pela letra de hoje (A ficou adiado no R4)
  v_letra := public.resumo_item_voltar(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'A'));
  select bool_and(acao is null and adiado_ate is null and voltou_em is not null) into v_voltou
    from public.resumo_itens where phone_normalized = pg_temp._phone() and dia = pg_temp._hoje() and letra = 'A';
  v_sem := public.resumo_item_voltar(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'D'));
  -- pelo nome, num dia passado (outro telefone)
  perform public.resumo_registrar(jsonb_build_object('dia', v_dia, 'phone', v_phone, 'modo', 'novo', 'texto_novo', 'antes',
    'itens', jsonb_build_array(pg_temp._item('C', '{"nome": "Flávio da Igreja", "nome_busca": "flavio da igreja", "familia": "os", "tipo": "os_esperando_compra", "secao": "obras"}'::jsonb))));
  update public.resumo_itens set acao = 'tirado', acao_em = now() - interval '2 days'
   where phone_normalized = v_phone and dia = v_dia;
  v_nome := public.resumo_item_voltar(jsonb_build_object('phone', v_phone, 'nome', 'flavio'));
  select acao into v_acao_velho from public.resumo_itens where phone_normalized = v_phone and dia = v_dia;
  insert into _resultado values ('R6 volta pela letra limpa a ação; sem ação avisa; pelo nome acha o de outro dia',
    v_letra->>'resultado' = 'voltou' and v_letra->>'desfeita' = 'adiado' and v_voltou
      and v_sem->>'resultado' = 'sem_acao' and v_nome->>'resultado' = 'voltou' and v_nome->>'desfeita' = 'tirado'
      and v_acao_velho is null,
    'letra=' || coalesce(v_letra->>'resultado', '-') || ' sem=' || coalesce(v_sem->>'resultado', '-')
      || ' nome=' || coalesce(v_nome->>'resultado', '-') || '/' || coalesce(v_nome->>'desfeita', '-'));
exception when others then
  insert into _resultado values ('R6 volta pela letra limpa a ação; sem ação avisa; pelo nome acha o de outro dia', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R7 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_recusas text[] := '{}';
  v_letra text;
  v_id uuid;
begin
  select id into v_id from public.resumo_manha where phone_normalized = pg_temp._phone() and dia = pg_temp._hoje();
  foreach v_letra in array array['N', 'S', 'E', 'I', 'O', 'AA', 'a'] loop
    begin
      insert into public.resumo_itens (resumo_id, dia, phone_normalized, modo, letra, posicao, ordem, familia, tipo, secao,
        referencia, assunto, nome, nome_busca, fato, titulo, motivo)
      values (v_id, pg_temp._hoje(), pg_temp._phone(), 'novo', v_letra, 'lista', 9, 'cobranca', 'cobranca_antiga', 'dinheiro',
        'recv:x', 'cliente:x', 'X', 'x', 'f', 't', 'm');
    exception when check_violation then
      v_recusas := v_recusas || v_letra;
    end;
  end loop;
  begin
    update public.resumo_itens set acao = 'adiado', acao_em = now(), adiado_ate = null
     where phone_normalized = pg_temp._phone() and dia = pg_temp._hoje() and letra = 'D';
  exception when check_violation then
    v_recusas := v_recusas || 'adiado_sem_data'::text;
  end;
  begin
    insert into public.resumo_manha (dia, phone_normalized, modo, texto_novo, enviado)
    values (pg_temp._hoje() - 10, pg_temp._phone(), 'sombra', 'x', true);
  exception when check_violation then
    v_recusas := v_recusas || 'sombra_enviada'::text;
  end;
  insert into _resultado values ('R7 CHECKs: N/S/E/I/O, duas letras e minúscula recusadas; adiado sem data; sombra enviada',
    cardinality(v_recusas) = 9, 'recusados: ' || array_to_string(v_recusas, ', '));
exception when others then
  insert into _resultado values ('R7 CHECKs: N/S/E/I/O, duas letras e minúscula recusadas; adiado sem data; sombra enviada', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R8 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id uuid;
  v_quem uuid;
  v_papel text;
  v_viu integer;
  v_viram text := '';
  v_vazou boolean := false;
  v_admin uuid := pg_temp._usuario('admin');
  v_viu_admin integer;
begin
  begin
    select id into v_id from public.resumo_manha where phone_normalized = pg_temp._phone() and dia = pg_temp._hoje();
    foreach v_papel in array array['financial', 'technician'] loop
      v_quem := pg_temp._usuario(v_papel);
      perform set_config('request.jwt.claim.sub', v_quem::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', v_quem, 'role', 'authenticated')::text, true);
      set local role authenticated;
      select (select count(*) from public.resumo_manha where id = v_id) + (select count(*) from public.resumo_itens where resumo_id = v_id)
        into v_viu;
      reset role;
      v_viram := v_viram || v_papel || ' vê ' || v_viu || '; ';
      v_vazou := v_vazou or v_viu <> 0;
    end loop;
    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    set local role authenticated;
    select (select count(*) from public.resumo_manha where id = v_id) + (select count(*) from public.resumo_itens where resumo_id = v_id)
      into v_viu_admin;
    reset role;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    insert into _resultado values ('R8 só o admin lê o resumo e os itens', not v_vazou and v_viu_admin = 4,
      v_viram || 'admin vê ' || v_viu_admin || ' (1 dia + 3 itens)');
  exception when others then
    reset role;
    insert into _resultado values ('R8 só o admin lê o resumo e os itens', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
  end;
end $$;

-- ═══ R9 ═══════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_fin uuid := pg_temp._usuario('financial');
  v_admin uuid := pg_temp._usuario('admin');
  v_recusou boolean := false;
  v_admin_mudou boolean := false;
  v_antes text;
  v_existe boolean;
begin
  select value into v_antes from public.app_settings where key = 'resumo_formato';
  v_existe := v_antes is not null;
  perform set_config('request.jwt.claim.sub', v_fin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_fin, 'role', 'authenticated')::text, true);
  begin
    update public.app_settings set value = 'novo' where key = 'resumo_formato';
  exception when insufficient_privilege then
    v_recusou := true;
  end;
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  update public.app_settings set value = 'sombra' where key = 'resumo_formato';
  v_admin_mudou := (select value from public.app_settings where key = 'resumo_formato') = 'sombra';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('R9 a chave existe; o financeiro não muda resumo_formato (42501); o admin muda',
    v_existe and v_recusou and v_admin_mudou,
    'existe=' || v_existe || ' recusou=' || v_recusou || ' admin=' || v_admin_mudou || ' (desfeito no rollback)');
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('R9 a chave existe; o financeiro não muda resumo_formato (42501); o admin muda', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- ═══ R10 ══════════════════════════════════════════════════════════════════════════════════════
-- A letra sozinha (o cartão pronto): "abriu" entra só no histórico do principal; a ação não muda.
do $$
declare
  v_r jsonb;
  v_x jsonb;
  v_acao text;
  v_abriu integer;
  v_outros integer;
begin
  v_r := public.resumo_item_acao(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'D', 'acao', 'abriu'));
  v_x := public.resumo_item_acao(jsonb_build_object('phone', pg_temp._phone(), 'letra', 'Z', 'acao', 'abriu'));
  select acao, (select count(*) from jsonb_array_elements(historico) e where e->>'acao' = 'abriu') into v_acao, v_abriu
    from public.resumo_itens where phone_normalized = pg_temp._phone() and dia = pg_temp._hoje() and letra = 'D' and principal;
  select count(*) into v_outros from public.resumo_itens
   where phone_normalized = pg_temp._phone() and dia = pg_temp._hoje() and letra = 'A' and historico @> '[{"acao": "abriu"}]'::jsonb;
  insert into _resultado values ('R10 a letra sozinha grava "abriu" no histórico sem mudar a ação; letra que não existe = nao_achei',
    v_r->>'resultado' = 'feito' and v_acao is null and v_abriu = 1 and v_outros = 0 and v_x->>'resultado' = 'nao_achei',
    'r=' || coalesce(v_r->>'resultado', '-') || ' acao=' || coalesce(v_acao, 'null') || ' abriu=' || v_abriu || ' Z=' || coalesce(v_x->>'resultado', '-'));
exception when others then
  insert into _resultado values ('R10 a letra sozinha grava "abriu" no histórico sem mudar a ação; letra que não existe = nao_achei', false,
    'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
