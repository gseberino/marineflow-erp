-- Prova da escrita pela conversa da Agenda de Produção, Fase 1 (pacote P5): migration 20261024160600.
-- bancada: depende de 20261024160600
--
-- Sempre (com ou sem a fixture):
--   A  portas: as 6 RPCs do rascunho são security definer, search_path fixo, abertas para authenticated e service_role e
--      nunca para anon; as internas (o cargo, as guardas, o salvar, os três aplicar) só service_role
--   B  só o admin mexe: técnico pelo painel (mesmo passando o id do admin), id de técnico ou id vazio pelo service role →
--      42501 "Só o administrador mexe na agenda."; o admin pelo painel passa (o p_autor não conta)
-- Com a fixture de 23/10 (scripts/bancada-agenda/fixture-2310.sql):
--   C  o áudio R01 inteiro: as 11 chamadas resolvem; NADA toca os_planejamento/os_planejamento_equipe/os_material/
--      agenda_disponibilidade antes do *grava*; a releitura byte a byte; ler 2× = o mesmo texto; o *grava* byte a byte; o
--      resultado = scripts/bancada-agenda/fixture-2310-pos-rodada.sql (as 4 tabelas, linha a linha); o histórico com as
--      palavras do dono; o painel do Nelson no nível C; *grava* de novo não tem nada
--   D  guarda contra número e data que o dono não disse (e o extenso ↔ dígito que tem de passar)
--   E  a correção substitui (e o que não foi dito de novo fica)
--   F  ambíguo / não achado / fora da carteira vira pergunta e nada entra no rascunho (Rodrigo, OS-00999, "a peça" do
--      Nelson, "cabos" do Vanderlei, peça que não existe, Kamell, pessoa que não existe, OS concluída, datas)
--   G  expirado não grava (e o resto do lote grava)
--   H  gravar é tudo ou nada: um item que não passa desfaz o lote inteiro e diz qual
--   I  o padrão "vem" novo substitui UMA vez só os dias que ele cobre; "só de manhã"/"não vem" sozinhos não apagam o
--      resto (capacidade antes e depois); a restrição dita de novo troca a anterior; sábado só por data; exceção por data
--   J  descartar
--   K  material: parcial (e o texto "3 de 8 na mão"), novo (fora do orçamento), fornecedor não cadastrado, dispensar,
--      "pode começar sem", "tá a caminho" sem data que vence, compra combinada que não volta a perguntar
--   L  planejar: "não tem peça a comprar", "não antes de", espera, escopo, campo que não existe, estimativa aceita;
--      desfazer (sai da espera, sem prazo, sem "não antes de", escopo resolvido); a prioridade muda a ordem do bloco 2
--   M  agenda desligada (modo_leitura): as três escritas recusam e nada entra; o *grava* do rascunho de antes grava
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261024160600
--   Em produção, só DEPOIS de aplicar 160000..160600, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase1_rascunho.sql
--   Sem a fixture (produção), C–L saem PULADO e só A e B rodam. Os cenários mexem em linhas só dentro de subtransações
--   desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;

-- As chamadas como a ferramenta faz (o admin da fixture, pelo WhatsApp, em 23/10).
create function pg_temp.plan(p_os text, p_dados jsonb, p_trecho text) returns jsonb language sql as $f$
  select public.agenda_rascunho_planejar('aa000000-0000-4000-8000-000000000001', 'whatsapp', p_os, p_dados, p_trecho,
                                         date '2026-10-23')
$f$;
create function pg_temp.mat(p_os text, p_itens text[], p_sit text, p_quando text, p_trecho text,
                            p_forn text default null, p_qtd numeric default null, p_novo boolean default false)
returns jsonb language sql as $f$
  select public.agenda_rascunho_material('aa000000-0000-4000-8000-000000000001', 'whatsapp', p_os, p_itens, p_sit, p_quando,
                                         p_forn, p_qtd, p_novo, p_trecho, date '2026-10-23')
$f$;
create function pg_temp.disp(p_pessoa text, p_sit text, p_dias text, p_padrao boolean, p_trecho text) returns jsonb
language sql as $f$
  select public.agenda_rascunho_disponibilidade('aa000000-0000-4000-8000-000000000001', 'whatsapp', p_pessoa, p_sit, p_dias,
                                                p_padrao, p_trecho, date '2026-10-23')
$f$;
create function pg_temp.grava() returns jsonb language sql as $f$
  select public.agenda_rascunho_gravar('aa000000-0000-4000-8000-000000000001', date '2026-10-23')
$f$;
create function pg_temp.ler() returns jsonb language sql stable as $f$
  select public.agenda_rascunho_ler('aa000000-0000-4000-8000-000000000001', date '2026-10-23')
$f$;
create function pg_temp.abertos() returns int language sql stable as $f$
  select count(*)::int from public.agenda_rascunho
   where autor = 'aa000000-0000-4000-8000-000000000001' and estado = 'aberto'
$f$;

-- O áudio R01 (spec §8.5), uma chamada por item, como o modelo faz: trecho = as palavras do dono daquele item.
create function pg_temp.r01() returns jsonb language plpgsql as $f$
declare
  v jsonb := '[]'::jsonb;
begin
  v := v || pg_temp.plan('Lenine', '{"dias": 2, "com_quem": [{"pessoa": "Roberto", "turnos": "dia"}, {"pessoa": "João", "turnos": "tarde"}], "dono": "abre_e_fecha"}',
                         'Lenine dois dias com o Roberto, eu abro e fecho, o João ajuda à tarde.');
  v := v || pg_temp.mat('Flávio', array['compressor'], 'na_mao', 'dia 14', 'O compressor do Flávio chegou dia 14, tá aqui');
  v := v || pg_temp.plan('Flávio', '{"dias": 1, "com_quem": [{"pessoa": "eu"}, {"pessoa": "Roberto"}]}', 'é um dia, eu e o Roberto');
  v := v || pg_temp.mat('Nelson', array['Cerbo', 'Orion', 'cabos'], 'na_mao', null, 'Do Nelson, Cerbo, Orion e os cabos tão aqui');
  v := v || pg_temp.mat('Nelson', array['painel'], 'a_caminho', 'dia 3', 'o painel chega dia 3');
  v := v || pg_temp.plan('Nelson', '{"dias": 2}', 'são dois dias');
  v := v || pg_temp.mat('Vanderlei', array['tudo'], 'vou_comprar', 'terça', 'Vanderlei eu compro na Premel terça', 'Premel');
  v := v || pg_temp.plan('Vanderlei', '{"dias": 3, "com_quem": [{"pessoa": "Roberto"}]}', 'são três dias com o Roberto');
  v := v || pg_temp.plan('Giancarlo', '{"dias": 3, "escopo_decidido": "só a primeira parte, baterias e barramento", "bem_livre_em": "dia 3"}',
                         'Giancarlo é só a primeira parte, baterias e barramento, três dias, mas o motorhome só fica livre dia 3.');
  v := v || pg_temp.disp('eu', 'vem', 'segunda a sexta', true, 'Eu fico em campo de segunda a sexta; sexta à tarde, escritório.');
  v := v || pg_temp.disp('eu', 'so_manha', 'sexta', true, 'Eu fico em campo de segunda a sexta; sexta à tarde, escritório.');
  return v;
end
$f$;

-- A fotografia das 4 tabelas de fato, linha a linha, sem o que é do relógio (ids gerados, carimbos, histórico, trecho).
create function pg_temp.foto() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'planejamento', coalesce((
      select jsonb_agg(jsonb_build_object(
               'os', so.service_order_number, 'dias', p.dias, 'fonte', p.estimativa_fonte, 'presenca', p.dono_presenca,
               'precisa_ate', p.precisa_ate, 'bem', p.bem_indisponivel::text, 'nao_antes', p.nao_antes_de,
               'motivo', p.nao_antes_motivo, 'aberto', p.escopo_em_aberto, 'decidido', p.escopo_decidido,
               'congelada', p.congelada_ate, 'rever', p.revisar_em, 'prioridade', p.prioridade_manual,
               'conferido', p.material_conferido_em is not null) order by so.service_order_number)
        from public.os_planejamento p join public.service_orders so on so.id = p.service_order_id), '[]'::jsonb),
    'equipe', coalesce((
      select jsonb_agg(jsonb_build_object('os', so.service_order_number, 'pessoa', e.payee_id, 'turnos', e.turnos)
                       order by so.service_order_number, e.payee_id)
        from public.os_planejamento_equipe e join public.service_orders so on so.id = e.service_order_id), '[]'::jsonb),
    'material', coalesce((
      select jsonb_agg(jsonb_build_object(
               'os', so.service_order_number, 'origem', m.origem,
               'vinculo', coalesce(m.service_order_part_id, m.service_order_service_id, m.purchase_order_item_id),
               'descricao', m.descricao, 'precisa', m.quantidade_necessaria, 'na_mao', m.quantidade_na_mao,
               'critico', m.critico, 'situacao', m.situacao, 'fonte', m.fonte, 'fornecedor', m.fornecedor_id,
               'fornecedor_nome', m.fornecedor_nome, 'compra', m.compra_prevista_em, 'comprado', m.comprado_em,
               'prev_de', m.previsao_de, 'prev_ate', m.previsao_ate, 'prev_orig', m.previsao_original,
               'prev_fonte', m.previsao_fonte, 'chegou', m.chegou_em)
             order by so.service_order_number, m.origem,
                      coalesce(m.service_order_part_id, m.service_order_service_id, m.purchase_order_item_id), m.descricao)
        from public.os_material m join public.service_orders so on so.id = m.service_order_id), '[]'::jsonb),
    'disponibilidade', coalesce((
      select jsonb_agg(jsonb_build_object(
               'pessoa', d.payee_id, 'dias', d.dias_semana::text, 'periodo', d.periodo::text, 'turno', d.turno,
               'situacao', d.situacao, 'origem', d.origem, 'frequencia', d.frequencia, 'nota', d.nota,
               'vigente', d.substituida_em is null)
             order by d.payee_id, d.origem, d.dias_semana::text, d.periodo::text, d.turno, d.situacao, d.frequencia)
        from public.agenda_disponibilidade d), '[]'::jsonb));
$f$;

-- A primeira diferença entre dois jsonb de fotografia (para o detalhe do teste).
create function pg_temp.dif(a jsonb, b jsonb) returns text language sql immutable as $f$
  select coalesce((
    select format('%s: %s ≠ %s', k, left(coalesce(a -> k, 'null'::jsonb)::text, 400), left(coalesce(b -> k, 'null'::jsonb)::text, 400))
      from (select jsonb_object_keys(a) k union select jsonb_object_keys(b)) x
     where a -> k is distinct from b -> k order by k limit 1), 'iguais')
$f$;

-- ── A. Portas ───────────────────────────────────────────────────────────────────────────────────────────
create temp table _rpcs_p5 (f text) on commit drop;
insert into _rpcs_p5 values
  ('public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)'),
  -- Fase 4 (P3): a assinatura ganhou p_aviso no fim (drop + create em 20261027100300); antes dela, a de 11 argumentos.
  ((coalesce(to_regprocedure('public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date, text)')::text,
             'public.agenda_rascunho_material(uuid, text, text, text[], text, text, text, numeric, boolean, text, date)'))),
  ('public.agenda_rascunho_disponibilidade(uuid, text, text, text, text, boolean, text, date)'),
  ('public.agenda_rascunho_ler(uuid, date)'), ('public.agenda_rascunho_gravar(uuid, date)'),
  ('public.agenda_rascunho_descartar(uuid)');
create temp table _internas_p5 (f text) on commit drop;
insert into _internas_p5 values
  ('public._autor_da_agenda(uuid)'), ('public._agenda_trecho_tem(text, text)'), ('public._agenda_trecho_tem_numero(text, numeric)'),
  ('public._agenda_recusa(text, text, jsonb)'), ('public._agenda_data_conferida(text, text, date, text)'),
  ('public._agenda_dias_citados(text)'), ('public._agenda_dias_semana_texto(smallint[])'), ('public._agenda_quando_texto(date, date)'),
  ('public._agenda_recusa_da_os(jsonb)'), ('public._agenda_os_do_rascunho(jsonb)'), ('public._agenda_resolver_fornecedor(text)'),
  ('public._agenda_rotulo_do_item(text, text[])'), ('public._agenda_rascunho_frase(text, jsonb)'),
  ('public._agenda_rascunho_salvar(uuid, text, text, text, uuid, jsonb, text, date)'),
  ('public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)'),
  ('public._agenda_aplicar_material(uuid, uuid, jsonb, text, date)'),
  ('public._agenda_aplicar_disponibilidade(uuid, jsonb, text, date)');

insert into _resultado
select 'A1 as 6 RPCs do rascunho: security definer, search_path fixo; ler é STABLE, as outras VOLATILE',
       count(*) = 6 and bool_and(p.prosecdef)
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(p.provolatile = case when p.proname = 'agenda_rascunho_ler' then 's' else 'v' end),
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ')
  from pg_proc p where p.oid in (select f::regprocedure::oid from _rpcs_p5);

insert into _resultado
select 'A2 as RPCs: authenticated e service_role executam; anon nunca',
       bool_and(has_function_privilege('authenticated', f::regprocedure, 'execute')
                and has_function_privilege('service_role', f::regprocedure, 'execute')
                and not has_function_privilege('anon', f::regprocedure, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f::regprocedure, 'execute')
                                      or not has_function_privilege('authenticated', f::regprocedure, 'execute'))
  from _rpcs_p5;

insert into _resultado
select 'A3 as internas (cargo, guardas, salvar, aplicar): só service_role — nem authenticated, nem anon',
       count(*) = 17 and bool_and(has_function_privilege('service_role', f::regprocedure, 'execute')
                                  and not has_function_privilege('authenticated', f::regprocedure, 'execute')
                                  and not has_function_privilege('anon', f::regprocedure, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('authenticated', f::regprocedure, 'execute')
                                      or has_function_privilege('anon', f::regprocedure, 'execute'))
  from _internas_p5;

insert into _resultado
select 'A4 security definer entre as internas: só o cargo, o salvar e os três aplicar',
       bool_and(p.prosecdef = (p.proname in ('_autor_da_agenda', '_agenda_rascunho_salvar', '_agenda_aplicar_planejar',
                                             '_agenda_aplicar_material', '_agenda_aplicar_disponibilidade')))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(p.proname || ':' || p.prosecdef::text, ', ')
  from pg_proc p where p.oid in (select f::regprocedure::oid from _internas_p5);

-- ── B. Só o administrador mexe na agenda ────────────────────────────────────────────────────────────────
do $b$
declare
  c_admin constant uuid := 'aa000000-0000-4000-8000-0000000000a1';
  c_tec   constant uuid := 'aa000000-0000-4000-8000-0000000000a2';
  v_res   jsonb := '[]'::jsonb;
  v_msg   text;
  v_cod   text;
  v_r     jsonb;
begin
  begin
    insert into public.app_users (id, full_name, email, role, active) values
      (c_admin, 'Admin B', 'admin-b@bancada.invalid', 'admin', true),
      (c_tec, 'Técnico B', 'tecnico-b@bancada.invalid', 'technician', true);

    -- B1/B2: pelo service role (WhatsApp), o p_autor tem de ser admin ativo.
    begin
      perform public.agenda_rascunho_ler(c_tec, date '2026-10-23');
      v_msg := 'não deu erro';
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    v_res := pg_temp.ok(v_res, 'B1 service role com o id de um técnico → 42501 "Só o administrador mexe na agenda."',
      v_cod = '42501' and v_msg = 'Só o administrador mexe na agenda.', v_cod || ' ' || v_msg);
    v_cod := null;
    begin
      perform public.agenda_rascunho_planejar(null, 'whatsapp', 'OS-00001', '{"dias": 2}', 'dois dias', date '2026-10-23');
      v_msg := 'não deu erro';
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    v_res := pg_temp.ok(v_res, 'B2 service role sem autor → 42501', v_cod = '42501', v_cod || ' ' || v_msg);

    -- B3: pelo painel, vale o login: o técnico não vira admin passando o id do admin.
    v_cod := null;
    begin
      perform set_config('request.jwt.claim.sub', c_tec::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', c_tec, 'role', 'authenticated')::text, true);
      set local role authenticated;
      perform public.agenda_rascunho_gravar(c_admin, date '2026-10-23');
      v_msg := 'não deu erro';
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    reset role;
    v_res := pg_temp.ok(v_res, 'B3 técnico pelo painel (passando o id do admin) → 42501 no *grava*', v_cod = '42501', v_cod || ' ' || v_msg);
    -- (o set_config de dentro de um bloco que deu erro é desfeito com ele: cada bloco põe o seu login)
    v_cod := null;
    begin
      perform set_config('request.jwt.claim.sub', c_tec::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', c_tec, 'role', 'authenticated')::text, true);
      set local role authenticated;
      perform public.agenda_rascunho_disponibilidade(c_admin, 'painel', 'eu', 'vem', 'segunda a sexta', true,
                                                     'segunda a sexta', date '2026-10-23');
      v_msg := 'não deu erro';
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    reset role;
    v_res := pg_temp.ok(v_res, 'B4 técnico pelo painel → 42501 também na escrita de rascunho', v_cod = '42501', v_cod || ' ' || v_msg);
    -- B4b: um JWT de usuário sem "sub" não pode dizer quem é pelo p_autor.
    v_cod := null;
    begin
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
      set local role authenticated;
      perform public.agenda_rascunho_ler(c_admin, date '2026-10-23');
      v_msg := 'não deu erro';
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    reset role;
    v_res := pg_temp.ok(v_res, 'B4b JWT de usuário sem login (sem sub) passando o id do admin → 42501', v_cod = '42501', v_cod || ' ' || v_msg);

    -- B5: o admin pelo painel passa, mesmo sem p_autor (vale o login).
    v_cod := null;
    begin
      perform set_config('request.jwt.claim.sub', c_admin::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', c_admin, 'role', 'authenticated')::text, true);
      set local role authenticated;
      v_r := public.agenda_rascunho_ler(null, date '2026-10-23');
      v_msg := null;
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    reset role;
    v_res := pg_temp.ok(v_res, 'B5 o admin pelo painel (sem p_autor) lê o rascunho: "Não tenho nada esperando para gravar."',
      v_msg is null and v_r ->> 'texto' = 'Não tenho nada esperando para gravar.', coalesce(v_msg, v_r::text));
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.gravar(v_res);
end
$b$;

-- ── C–L: com a fixture de 23/10 ─────────────────────────────────────────────────────────────────────────
do $cenarios$
declare
  v_fixture boolean := exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002')
                   and exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000104')
                   and exists (select 1 from public.app_users where id = 'aa000000-0000-4000-8000-000000000001');
  c_autor  constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_dono   constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_rob    constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao   constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_premel constant uuid := 'dd000000-0000-4000-8000-000000000001';
  c_poi    constant uuid := '71000000-0000-4000-8000-000000000001';
  v_res    jsonb := '[]'::jsonb;
  v_antes  jsonb;
  v_depois jsonb;
  v_a      jsonb;
  v_b      jsonb;
  r        jsonb;
  r2       jsonb;
  v_txt    text;
  v_txt2   text;
  v_n      int;
  v_ok     boolean;
  v_msg    text;
  v_cod    text;
  v_pos    text := current_setting('agenda_teste.pos_rodada', true);
begin
  if not v_fixture then
    insert into _resultado values ('C–L cenários com a fixture de 23/10', true, 'PULADO: sem a fixture (produção); rodam A e B');
    return;
  end if;

  -- ── C. O áudio R01 inteiro ──
  begin
    v_antes := pg_temp.foto();
    r := pg_temp.r01();
    v_res := pg_temp.ok(v_res, 'C1 as 11 chamadas do áudio R01 resolvem (nenhuma pergunta)',
      jsonb_array_length(r) = 11 and not exists (select 1 from jsonb_array_elements(r) e where not (e ->> 'ok')::boolean),
      (select string_agg(e::text, ' | ') from jsonb_array_elements(r) e where not (e ->> 'ok')::boolean));
    v_res := pg_temp.ok(v_res, 'C2 antes do *grava* NADA muda em os_planejamento, os_planejamento_equipe, os_material e agenda_disponibilidade',
      pg_temp.foto() = v_antes, pg_temp.dif(pg_temp.foto(), v_antes));
    v_res := pg_temp.ok(v_res, 'C3 o rascunho: 16 linhas abertas (uma por item; as 4 peças do Vanderlei e as 3 do Nelson uma a uma)',
      pg_temp.abertos() = 16, pg_temp.abertos()::text);
    v_txt := pg_temp.ler() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'C4 a releitura, byte a byte',
      v_txt = E'Entendi assim, confere?\n'
              '• Lenine (OS-00074): 2 dias com Roberto e João (à tarde); você abre e fecha.\n'
              '• Flávio (OS-00104): Compressor 12V de… na mão desde qua 14/10; 1 dia com você e Roberto.\n'
              '• Nelson (OS-00112): Cerbo gx victron…, Orion-Tr Smart 12/12-30A… e KIT Cabos Comunicação… na mão (desde hoje); '
              'Painel Touch de… chega ter 03/11 (você disse); 2 dias.\n'
              '• Vanderlei (OS-00069): os 4 itens você compra ter 27/10, fornecedor Premel; 3 dias com Roberto.\n'
              '• Giancarlo (OS-00100): só a primeira parte, baterias e barramento; 3 dias; o motorhome fica livre ter 03/11.\n'
              '• Você: em campo de seg a sex; toda sexta à tarde, não.\n'
              'Responda *grava* ou corrija o que estiver errado.',
      v_txt);
    v_res := pg_temp.ok(v_res, 'C5 a releitura é a mesma na última chamada e lida 2× (md5)',
      md5(v_txt) = md5(pg_temp.ler() ->> 'texto') and r -> 10 ->> 'releitura' = v_txt, null);
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C6 o *grava*, byte a byte: uma linha por OS (o estado da prontidão) e a sua',
      (r2 ->> 'ok')::boolean and (r2 ->> 'gravados')::int = 16
      and r2 ->> 'texto' = E'Gravado. Agora:\n'
                           '• Lenine: falta você dizer se tem peça a comprar.\n'
                           '• Flávio: falta você dizer se tem peça embutida em "Conversão do sistema…" e "Substituição da tampa…".\n'
                           '• Nelson: pronto a partir de qua 04/11, se "Painel Touch de…" chegar ter 03/11.\n'
                           '• Vanderlei: pronto a partir de qui 29/10, se a compra sair ter 27/10.\n'
                           '• Giancarlo: falta você dizer se tem peça embutida em "Barramento e proteções…" e "Realocação do banco…" (e mais 1).\n'
                           '• Você: em campo de seg a sex; toda sexta à tarde, não.',
      r2 ->> 'texto');
    v_res := pg_temp.ok(v_res, 'C7 as 16 linhas do rascunho ficam gravado (nenhuma aberta)',
      pg_temp.abertos() = 0
      and (select count(*) from public.agenda_rascunho where autor = c_autor and estado = 'gravado' and gravado_em is not null) = 16,
      null);
    v_a := pg_temp.foto();
    -- C9: o histórico com as palavras do dono e o "antes/depois".
    v_res := pg_temp.ok(v_res, 'C9 histórico: a OS-00074 guarda {em, autor, trecho, antes, depois} com só o que mudou; o compressor, por dono',
      (select jsonb_array_length(p.historico) = 1
              and p.historico -> 0 ->> 'trecho' = 'Lenine dois dias com o Roberto, eu abro e fecho, o João ajuda à tarde.'
              and p.historico -> 0 ->> 'autor' = c_autor::text and p.historico -> 0 ->> 'em' = '2026-10-23'
              and (p.historico -> 0 -> 'depois') ? 'dias' and (p.historico -> 0 -> 'depois') ? 'equipe'
              and not (p.historico -> 0 -> 'depois') ? 'precisa_ate'
              and p.trecho = 'Lenine dois dias com o Roberto, eu abro e fecho, o João ajuda à tarde.'
         from public.os_planejamento p where p.service_order_id = pg_temp.os('74'))
      and (select m.historico -> -1 ->> 'por' = 'dono' and m.historico -> -1 ->> 'para' = 'na_mao'
                  and m.trecho = 'O compressor do Flávio chegou dia 14, tá aqui'
             from public.os_material m where m.purchase_order_item_id = c_poi),
      (select p.historico::text from public.os_planejamento p where p.service_order_id = pg_temp.os('74')));
    v_res := pg_temp.ok(v_res, 'C10 na prontidão: o painel do Nelson é nível C (o dono disse) e o compressor é A',
      (select e ->> 'nivel' from jsonb_array_elements(public.os_prontidao(pg_temp.os('112'), date '2026-10-23') #> '{material,itens}') e
        where e ->> 'linha' = md5('peca:112:4')::uuid::text) = 'C'
      and (select e ->> 'nivel' from jsonb_array_elements(public.os_prontidao(pg_temp.os('104'), date '2026-10-23') #> '{material,itens}') e
            where e ->> 'linha' = c_poi::text) = 'A',
      null);
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'C11 *grava* de novo: "Não tenho nada esperando para gravar." e nada muda',
      r2 ->> 'texto' = 'Não tenho nada esperando para gravar.' and (r2 ->> 'gravados')::int = 0 and pg_temp.foto() = v_a,
      r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- C8: o mesmo estado do arquivo pós-rodada, escrito à mão.
  if v_pos is null or v_pos = '' then
    v_res := pg_temp.ok(v_res, 'C8 R01 = fixture-2310-pos-rodada.sql', true, 'PULADO: sem agenda_teste.pos_rodada (rode pela bancada)');
  else
    begin
      execute v_pos;
      v_b := pg_temp.foto();
      -- C12 (o eval L05a): depois da rodada só o painel do Nelson falta; "a peça do Nelson chegou" é ele, e nada muda
      -- antes do *grava*.
      r := pg_temp.mat('Nelson', array['a peça'], 'na_mao', null, 'a peça do Nelson chegou');
      v_ok := (r ->> 'ok')::boolean and r ->> 'item' = 'Nelson (OS-00112): Painel Touch de… na mão (desde hoje)'
              and r ->> 'releitura' = E'Entendi assim, confere?\n• Nelson (OS-00112): Painel Touch de… na mão (desde hoje).\n'
                                      'Responda *grava* ou corrija o que estiver errado.'
              and pg_temp.foto() = v_b;
      v_txt := r::text;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    v_res := pg_temp.ok(v_res, 'C8 o *grava* do R01 deixa EXATAMENTE o estado de fixture-2310-pos-rodada.sql (as 4 tabelas)',
      v_a = v_b, pg_temp.dif(v_a, v_b));
    v_res := pg_temp.ok(v_res, 'C12 (L05a) depois da rodada, "a peça do Nelson chegou" é o painel (o único que falta); nada muda antes do *grava*',
      v_ok, v_txt);
  end if;

  -- ── D. Guarda contra número e data que o dono não disse ──
  begin
    v_antes := pg_temp.foto();
    r := pg_temp.plan('Nelson', '{"dias": 3}', 'são dois dias');
    v_res := pg_temp.ok(v_res, 'D1 dias 3 com o dono dizendo "dois dias" → recusa e nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'fora_do_trecho'
      and r ->> 'pergunta' = 'Não achei "3 dias" no que você disse; me diga de novo quantos dias.' and pg_temp.abertos() = 0,
      r::text);
    r := pg_temp.mat('Nelson', array['painel'], 'a_caminho', '03/11', 'o painel chega dia 3');
    v_res := pg_temp.ok(v_res, 'D2 data calculada pelo modelo ("03/11") quando o dono disse "dia 3" → recusa',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' = 'Não achei "03/11" no que você disse; me diga de novo.'
      and pg_temp.abertos() = 0, r::text);
    r := pg_temp.plan('Nelson', '{"dias": 3}', 'o painel chega dia 3');
    v_res := pg_temp.ok(v_res, 'D3 o "3" de "dia 3" é data, não conta como "3 dias"',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'fora_do_trecho', r::text);
    v_ok := (pg_temp.plan('Nelson', '{"dias": 2}', 'uns 2 dias') ->> 'ok')::boolean
        and (pg_temp.plan('Lenine', '{"dias": 1.5}', 'o do Lenine é um dia e meio') ->> 'ok')::boolean
        and (pg_temp.plan('Flávio', '{"dias": 0.5}', 'Flávio é meio dia') ->> 'ok')::boolean
        and (pg_temp.plan('Vanderlei', '{"dias": 2.5}', 'Vanderlei dois e meio') ->> 'ok')::boolean
        and (pg_temp.plan('Giancarlo', '{"dias": 1.5}', 'Giancarlo 1,5 dia') ->> 'ok')::boolean;
    v_res := pg_temp.ok(v_res, 'D4 extenso e dígito passam: "2 dias", "um dia e meio", "meio dia", "dois e meio", "1,5 dia"',
      v_ok and pg_temp.abertos() = 5, pg_temp.abertos()::text);
    perform public.agenda_rascunho_descartar(c_autor);
    r := pg_temp.mat('Vanderlei', array['porta fusível'], 'na_mao', null, 'chegaram as porta fusível', null, 3);
    v_res := pg_temp.ok(v_res, 'D5 quantidade 3 que o dono não disse → recusa',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' = 'Não achei "3" no que você disse; me diga de novo quantas.', r::text);
    r := pg_temp.plan('Giancarlo', '{"bem_livre_em": "dia 5"}', 'o motorhome só fica livre dia 3');
    v_res := pg_temp.ok(v_res, 'D6 "dia 5" para o bem quando o dono disse "dia 3" → recusa', not (r ->> 'ok')::boolean, r::text);
    r := pg_temp.disp('Roberto', 'vem', 'sábado', true, 'o Roberto vem de segunda a sexta');
    v_res := pg_temp.ok(v_res, 'D7 padrão "sábado" que o dono não disse → recusa',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' = 'Não achei "sábado" no que você disse; me diga de novo quais dias.', r::text);
    r := pg_temp.plan('Lenine', '{"aceitar_sugestao": true}', 'pode ser o que você acha');
    v_res := pg_temp.ok(v_res, 'D8 "aceito a sua estimativa": sem número dito, grava a sugestão com fonte aceita',
      (r ->> 'ok')::boolean and r ->> 'item' = 'Lenine (OS-00074): 2,5 dias (a minha estimativa, que você aceitou)', r::text);
    r := pg_temp.plan('Lenine', '{}', 'nada');
    v_res := pg_temp.ok(v_res, 'D9 sem trecho ou sem nada a mudar → pergunta',
      not (pg_temp.plan('Lenine', '{"dias": 2}', '  ') ->> 'ok')::boolean and r ->> 'motivo' = 'nada', r::text);
    v_res := pg_temp.ok(v_res, 'D10 nada disso tocou as tabelas de fato', pg_temp.foto() = v_antes, pg_temp.dif(pg_temp.foto(), v_antes));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── E. A correção substitui ──
  begin
    perform pg_temp.plan('Lenine', '{"dias": 2, "com_quem": [{"pessoa": "Roberto"}]}', 'Lenine dois dias com o Roberto');
    r := pg_temp.plan('Lenine', '{"dias": 3}', 'não, são três dias');
    v_res := pg_temp.ok(v_res, 'E1 "não, são três dias": uma linha aberta do Lenine, com 3 dias e o Roberto que já tinha sido dito',
      (r ->> 'ok')::boolean and r ->> 'item' = 'Lenine (OS-00074): 3 dias com Roberto'
      and (select count(*) from public.agenda_rascunho where chave = 'planejar:' || pg_temp.os('74') and estado = 'aberto') = 1
      and (select count(*) from public.agenda_rascunho where chave = 'planejar:' || pg_temp.os('74') and estado = 'substituido') = 1
      and (select trecho from public.agenda_rascunho where chave = 'planejar:' || pg_temp.os('74') and estado = 'aberto')
          = 'Lenine dois dias com o Roberto / não, são três dias',
      r::text);
    perform pg_temp.mat('Nelson', array['painel'], 'a_caminho', 'dia 3', 'o painel chega dia 3');
    r := pg_temp.mat('Nelson', array['painel'], 'na_mao', null, 'o painel chegou, tá aqui');
    v_res := pg_temp.ok(v_res, 'E2 "o painel chegou" depois de "chega dia 3": a linha vira "na mão" e a previsão sai da releitura',
      r ->> 'item' = 'Nelson (OS-00112): Painel Touch de… na mão (desde hoje)'
      and (select count(*) from public.agenda_rascunho where chave = 'material:peca:' || md5('peca:112:4')::uuid::text and estado = 'aberto') = 1,
      r::text);
    perform pg_temp.mat('Nelson', array['painel'], 'a_caminho', 'dia 3', 'o painel chega dia 3');
    r := pg_temp.mat('Nelson', array['painel'], 'pode_comecar_sem', null, 'dá pra começar sem o painel');
    v_res := pg_temp.ok(v_res, 'E3 "dá para começar sem" junta com a previsão (não apaga)',
      r ->> 'item' = 'Nelson (OS-00112): Painel Touch de… chega ter 03/11 (você disse) (dá para começar sem)', r::text);
    -- A ordem da releitura não pula: a linha corrigida fica onde estava.
    v_txt := pg_temp.ler() ->> 'texto';
    v_res := pg_temp.ok(v_res, 'E4 a linha corrigida fica no lugar (Lenine antes do Nelson)',
      strpos(v_txt, 'Lenine') < strpos(v_txt, 'Nelson') and pg_temp.abertos() = 2, v_txt);
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'E5 gravado: 3 dias + Roberto no Lenine; painel a caminho 03/11 e não crítico',
      (select p.dias = 3 from public.os_planejamento p where p.service_order_id = pg_temp.os('74'))
      and (select string_agg(e.payee_id::text || ':' || e.turnos, ',') from public.os_planejamento_equipe e
            where e.service_order_id = pg_temp.os('74')) = c_rob::text || ':dia'
      and (select m.situacao = 'a_caminho' and m.previsao_ate = '2026-11-03' and m.previsao_fonte = 'dono' and not m.critico
             from public.os_material m where m.service_order_part_id = md5('peca:112:4')::uuid),
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── F. Pergunta, e nada no rascunho ──
  begin
    r := pg_temp.plan('Rodrigo', '{"dias": 0.5, "com_quem": [{"pessoa": "eu"}]}', 'o do Rodrigo é meio dia, só eu');
    v_res := pg_temp.ok(v_res, 'F1 (R05) "o do Rodrigo é meio dia": pergunta qual Rodrigo, com os dois números; nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'os_ambiguo'
      and r ->> 'pergunta' like 'Qual Rodrigo: OS-00076 (%) ou OS-00096 (%)?' and jsonb_array_length(r -> 'opcoes') = 2
      and pg_temp.abertos() = 0, r::text);
    r := pg_temp.plan('OS-00999', '{"dias": 2}', 'dois dias');
    v_res := pg_temp.ok(v_res, 'F2 OS-00999 → "Não encontrei a OS-00999."', r ->> 'pergunta' = 'Não encontrei a OS-00999.', r::text);
    r := pg_temp.plan('OS-00050', '{"dias": 2}', 'dois dias');
    v_res := pg_temp.ok(v_res, 'F3 OS concluída → diz o status e não anota',
      r ->> 'pergunta' = 'A OS-00050 já foi concluída. Só anoto o que é de serviço da carteira (OS aberta ou orçamento aprovado).',
      r::text);
    r := pg_temp.mat('Nelson', array['a peça'], 'na_mao', null, 'chegou a peça do Nelson');
    v_res := pg_temp.ok(v_res, 'F4 (L05b) "chegou a peça do Nelson" com 4 faltando → pergunta qual, com as 4',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'item_ambiguo' and jsonb_array_length(r -> 'opcoes') = 4
      and r ->> 'pergunta' = 'Qual peça do Nelson: KIT Cabos Comunicação…, Central de controle…, Orion-Tr Smart 12/12-30A… ou Painel Touch de…?',
      r::text);
    r := pg_temp.mat('Vanderlei', array['cabos'], 'comprei', null, 'comprei os cabos do Vanderlei');
    v_res := pg_temp.ok(v_res, 'F5 "os cabos" do Vanderlei casa com 3 itens → pergunta qual',
      r ->> 'motivo' = 'item_ambiguo' and jsonb_array_length(r -> 'opcoes') = 3, r::text);
    r := pg_temp.mat('Nelson', array['bomba'], 'na_mao', null, 'a bomba do Nelson chegou');
    v_res := pg_temp.ok(v_res, 'F6 peça que não está no orçamento → diz o que tem e oferece "peça nova"',
      r ->> 'motivo' = 'item_nao_achei'
      and r ->> 'pergunta' = 'Não achei "bomba" no material de Nelson (OS-00112). Tem: KIT Cabos Comunicação…, Central de controle…, '
                             'Orion-Tr Smart 12/12-30A… e Painel Touch de… Se é peça que não está no orçamento, me diga que é nova.',
      r::text);
    r := pg_temp.mat('Nelson', array['Cerbo'], 'vou_comprar', null, 'compro o Cerbo na Kamell', 'Kamell');
    v_res := pg_temp.ok(v_res, 'F7 fornecedor "Kamell" com dois cadastros → pergunta com a cidade de cada um',
      r ->> 'pergunta' = 'Qual Kamell: Kamell (Vila Velha/ES) ou Kamell (Itajaí/SC)?', r::text);
    r := pg_temp.plan('Lenine', '{"dias": 2, "com_quem": [{"pessoa": "Pedro"}]}', 'dois dias com o Pedro');
    v_res := pg_temp.ok(v_res, 'F8 pessoa que não existe → "Não conheço ninguém chamado Pedro na equipe."',
      r ->> 'pergunta' = 'Não conheço ninguém chamado Pedro na equipe.', r::text);
    r := pg_temp.mat('Flávio', array['compressor'], 'na_mao', 'amanhã', 'o compressor chega amanhã');
    r2 := pg_temp.mat('Flávio', array['compressor'], 'a_caminho', 'dia 20/10', 'chegava dia 20/10');
    v_res := pg_temp.ok(v_res, 'F9 "chegou" no futuro e "chega" no passado → pergunta',
      r ->> 'motivo' = 'data_futura' and r2 ->> 'motivo' = 'data_passada', r::text || ' ' || r2::text);
    r := pg_temp.disp('Roberto', 'vem', 'xyz', false, 'o Roberto vem xyz');
    v_res := pg_temp.ok(v_res, 'F10 data que não dá para entender → a frase do agenda_data_dita',
      r ->> 'pergunta' = 'Não entendi a data "xyz". Diga como "dia 3", "03/11", "terça" ou "amanhã".', r::text);
    v_res := pg_temp.ok(v_res, 'F11 nenhuma dessas entrou no rascunho', pg_temp.abertos() = 0, pg_temp.abertos()::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── G. Expirado não grava ──
  begin
    v_antes := pg_temp.foto();
    perform pg_temp.plan('Lenine', '{"dias": 2}', 'Lenine dois dias');
    update public.agenda_rascunho set criado_em = '2026-10-21 10:00-03', expira_em = '2026-10-22 10:00-03'
     where autor = c_autor and estado = 'aberto';
    v_txt := pg_temp.ler() ->> 'texto';
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'G1 a releitura vencida não aparece nem grava: "A releitura de qua 21/10 expirou; me diga de novo o que mudou."',
      v_txt = 'Não tenho nada esperando para gravar.'
      and r ->> 'texto' = 'A releitura de qua 21/10 expirou; me diga de novo o que mudou.' and (r ->> 'gravados')::int = 0
      and pg_temp.foto() = v_antes
      and (select count(*) from public.agenda_rascunho where autor = c_autor and estado = 'expirado') = 1,
      r::text);
    perform pg_temp.plan('Lenine', '{"dias": 2}', 'Lenine dois dias');
    update public.agenda_rascunho set criado_em = '2026-10-21 10:00-03', expira_em = '2026-10-22 10:00-03'
     where autor = c_autor and estado = 'aberto';
    perform pg_temp.plan('Nelson', '{"dias": 2}', 'Nelson dois dias');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'G2 com uma vencida e uma em dia: grava a em dia e avisa da vencida',
      (r ->> 'gravados')::int = 1
      and r ->> 'texto' = E'Gravado. Agora:\n• Nelson: falta você dizer o que já está na mão e o que falta (4 itens sem compra registrada).\n'
                          '(A releitura de qua 21/10 tinha expirado e não foi gravada.)'
      and not exists (select 1 from public.os_planejamento where service_order_id = pg_temp.os('74'))
      and exists (select 1 from public.os_planejamento where service_order_id = pg_temp.os('112') and dias = 2),
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── H. Tudo ou nada ──
  begin
    v_antes := pg_temp.foto();
    perform pg_temp.plan('Lenine', '{"dias": 2}', 'Lenine dois dias');
    perform pg_temp.plan('Nelson', '{"dias": 2}', 'Nelson dois dias');
    perform pg_temp.mat('Flávio', array['compressor'], 'na_mao', null, 'o compressor tá aqui');
    -- Um item corrompido no meio do lote (0,3 dia não passa no CHECK de os_planejamento.dias).
    update public.agenda_rascunho set dados = jsonb_set(dados, '{dias}', '0.3')
     where autor = c_autor and estado = 'aberto' and chave = 'planejar:' || pg_temp.os('112');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'H1 um item que não passa desfaz o lote inteiro: nada gravado, as 3 linhas continuam abertas',
      not (r ->> 'ok')::boolean and (r ->> 'gravados')::int = 0
      and r ->> 'texto' = 'Não gravei nada: o banco recusou um item (Nelson (OS-00112): 2 dias). Corrija o que estiver errado, ou mande *descarta*, e depois *grava* de novo.'
      and pg_temp.foto() = v_antes and pg_temp.abertos() = 3,
      r::text || ' ' || pg_temp.dif(pg_temp.foto(), v_antes));
    perform public.agenda_rascunho_descartar(c_autor);
    -- A peça saiu da OS depois da releitura: o *grava* diz qual.
    perform pg_temp.plan('Lenine', '{"dias": 2}', 'Lenine dois dias');
    perform pg_temp.mat('Nelson', array['painel'], 'a_caminho', 'dia 3', 'o painel chega dia 3');
    delete from public.service_order_parts where id = md5('peca:112:4')::uuid;
    v_antes := pg_temp.foto();
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'H2 a peça saiu da OS depois da releitura: "Não gravei nada: "Painel Touch de…" saiu do serviço"',
      not (r ->> 'ok')::boolean
      and r ->> 'texto' like 'Não gravei nada: "Painel Touch de…" saiu do serviço (Nelson (OS-00112): Painel Touch de… chega ter 03/11 (você disse)).%'
      and pg_temp.foto() = v_antes and pg_temp.abertos() = 2,
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── I. O padrão novo substitui o velho UMA vez; exceção por data ──
  begin
    perform pg_temp.disp('Roberto', 'vem', 'segunda a quinta', true, 'o Roberto vem de segunda a quinta, quarta só de manhã');
    perform pg_temp.disp('Roberto', 'so_manha', 'quarta', true, 'o Roberto vem de segunda a quinta, quarta só de manhã');
    v_txt := pg_temp.ler() ->> 'texto';
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'I1 o "vem de seg a qui" troca UMA vez só os 4 dias da semente que ele cobre: a sexta da semente fica',
      (r ->> 'ok')::boolean
      and (select count(*) from public.agenda_disponibilidade where payee_id = c_rob and substituida_em is null) = 3
      and (select count(*) from public.agenda_disponibilidade where payee_id = c_rob and substituida_em is null and origem = 'dono') = 2
      and (select count(*) from public.agenda_disponibilidade where payee_id = c_rob and substituida_em is not null and origem = 'historico') = 4
      and (select dias_semana::text from public.agenda_disponibilidade
            where payee_id = c_rob and substituida_em is null and origem = 'historico') = '{5}'
      and (select count(*) from public.agenda_disponibilidade where payee_id = c_joao and substituida_em is null) = 4
      and v_txt = E'Entendi assim, confere?\n• Roberto: vem de seg a qui; toda quarta à tarde, não.\nResponda *grava* ou corrija o que estiver errado.'
      and r ->> 'texto' = E'Gravado. Agora:\n• Roberto: vem de seg a qui; toda quarta à tarde, não.',
      v_txt || ' | ' || (r ->> 'texto'));
    v_res := pg_temp.ok(v_res, 'I2 a capacidade passa a ler o padrão dito: quarta de manhã livre (1), à tarde indisponível; sexta pela semente',
      (select string_agg(format('%s %s %s %s', to_char(g.dia, 'DD/MM'), g.turno, g.situacao, trim_scale(g.meios_esperados)), ' | ' order by g.dia, g.turno)
         from public.agenda_capacidade('2026-10-28', '2026-10-30', date '2026-10-23') g where g.payee_id = c_rob)
      = '28/10 manha livre 1 | 28/10 tarde indisponivel 0 | 29/10 manha livre 1 | 29/10 tarde livre 1 | 30/10 manha livre 1 | 30/10 tarde livre 1',
      (select string_agg(format('%s %s %s %s', to_char(g.dia, 'DD/MM'), g.turno, g.situacao, trim_scale(g.meios_esperados)), ' | ' order by g.dia, g.turno)
         from public.agenda_capacidade('2026-10-28', '2026-10-30', date '2026-10-23') g where g.payee_id = c_rob));
    perform pg_temp.disp('Roberto', 'vem', 'segunda a sexta', true, 'o Roberto agora vem de segunda a sexta');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'I3 um 2º padrão (seg a sex) troca os 2 do dono e a sexta da semente: fica 1 vigente',
      (select count(*) from public.agenda_disponibilidade where payee_id = c_rob and substituida_em is null) = 1
      and (select dias_semana::text from public.agenda_disponibilidade where payee_id = c_rob and substituida_em is null) = '{1,2,3,4,5}',
      r::text);
    perform pg_temp.disp('Roberto', 'nao_vem', 'terça', false, 'o Roberto não vem terça');
    v_txt := pg_temp.ler() ->> 'texto';
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'I4 exceção "não vem terça": o padrão fica; a terça 27/10 do Roberto fica indisponível',
      v_txt = E'Entendi assim, confere?\n• Roberto: não vem ter 27/10.\nResponda *grava* ou corrija o que estiver errado.'
      and (select count(*) from public.agenda_disponibilidade where payee_id = c_rob and substituida_em is null) = 2
      and (select bool_and(g.situacao = 'indisponivel') from public.agenda_capacidade('2026-10-27', '2026-10-27', date '2026-10-23') g
            where g.payee_id = c_rob),
      v_txt);
    perform pg_temp.disp('Roberto', 'vem', 'terça', false, 'não, o Roberto vem terça sim');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'I5 a exceção da mesma data e turno troca a anterior (fica o rastro)',
      (select count(*) from public.agenda_disponibilidade where payee_id = c_rob and substituida_em is null and periodo is not null) = 1
      and (select situacao from public.agenda_disponibilidade where payee_id = c_rob and substituida_em is null and periodo is not null) = 'disponivel',
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── I (cont.). O padrão restritivo não apaga o resto; sábado só por data ──
  begin
    v_a := public.agenda_capacidade_semanal(date '2026-10-23');
    perform pg_temp.disp('João', 'so_manha', 'terça', true, 'o João só vem de manhã às terças');
    v_txt := pg_temp.ler() ->> 'texto';
    r := pg_temp.grava();
    v_b := public.agenda_capacidade_semanal(date '2026-10-23');
    v_res := pg_temp.ok(v_res, 'I6 "só de manhã às terças" sozinho: os 4 dias da semente do João ficam; só a terça à tarde sai (6,77 → 6,52)',
      v_txt = E'Entendi assim, confere?\n• João: toda terça à tarde, não.\nResponda *grava* ou corrija o que estiver errado.'
      and r ->> 'texto' = E'Gravado. Agora:\n• João: toda terça à tarde, não.'
      and v_a ->> 'diarias_semana' = '6.77' and v_b ->> 'diarias_semana' = '6.52'
      and (select count(*) from public.agenda_disponibilidade where payee_id = c_joao and substituida_em is null and origem = 'historico') = 4
      and exists (select 1 from jsonb_array_elements(v_b -> 'pessoas') e where e ->> 'nome' = 'João' and e ->> 'diarias_semana' = '2.08')
      and (select string_agg(format('%s %s %s', to_char(g.dia, 'DD/MM'), g.turno, g.situacao), ' | ' order by g.dia, g.turno)
             from public.agenda_capacidade('2026-10-27', '2026-10-28', date '2026-10-23') g where g.payee_id = c_joao)
          = '27/10 manha livre | 27/10 tarde indisponivel | 28/10 manha livre | 28/10 tarde livre',
      v_txt || ' | ' || (r ->> 'texto') || ' | ' || (v_b ->> 'diarias_semana'));
    perform pg_temp.disp('João', 'so_tarde', 'terça', true, 'não, o João só vem à tarde às terças');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'I7 a restrição dita de novo para o mesmo dia troca a anterior (não somam: terça de manhã fora, à tarde livre)',
      (select count(*) from public.agenda_disponibilidade where payee_id = c_joao and substituida_em is null and origem = 'dono') = 1
      and (select string_agg(format('%s %s %s', to_char(g.dia, 'DD/MM'), g.turno, g.situacao), ' | ' order by g.dia, g.turno)
             from public.agenda_capacidade('2026-10-27', '2026-10-27', date '2026-10-23') g where g.payee_id = c_joao)
          = '27/10 manha indisponivel | 27/10 tarde livre',
      r::text);
    perform pg_temp.disp('João', 'nao_vem', 'segundas', true, 'o João não vem mais às segundas');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'I8 "não vem mais às segundas" (ele nem tinha segunda): nada da semente sai; a capacidade não muda',
      (r ->> 'ok')::boolean
      and (select count(*) from public.agenda_disponibilidade where payee_id = c_joao and substituida_em is null and origem = 'historico') = 4
      and public.agenda_capacidade_semanal(date '2026-10-23') ->> 'diarias_semana' = '6.52',
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    r := pg_temp.disp('Roberto', 'vem', 'sábado', true, 'o Roberto vem todo sábado');
    r2 := pg_temp.disp('Roberto', 'nao_vem', 'sábado', true, 'o Roberto não vem sábado');
    v_res := pg_temp.ok(v_res, 'I9 padrão só de sábado: pergunta qual sábado (é por data) e nada entra no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'sabado_padrao'
      and r ->> 'pergunta' = 'Sábado eu só conto por data: qual sábado? (por exemplo, "sábado dia 31")'
      and not (r2 ->> 'ok')::boolean and r2 ->> 'motivo' = 'sabado_padrao'
      and r2 ->> 'pergunta' = 'Sábado já fica fora da conta: só conto sábado quando você diz a data.'
      and pg_temp.abertos() = 0,
      r::text || ' | ' || r2::text);
    perform pg_temp.disp('Roberto', 'vem', 'segunda a sábado', true, 'o Roberto vem de segunda a sábado');
    v_txt := pg_temp.ler() ->> 'texto';
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'I10 "segunda a sábado": grava seg a sex e a releitura diz que o sábado é por data',
      v_txt = E'Entendi assim, confere?\n• Roberto: vem de seg a sex (sábado eu só conto por data).\nResponda *grava* ou corrija o que estiver errado.'
      and r ->> 'texto' = E'Gravado. Agora:\n• Roberto: vem de seg a sex (sábado eu só conto por data).'
      and (select string_agg(dias_semana::text, ' ') from public.agenda_disponibilidade
            where payee_id = c_rob and substituida_em is null) = '{1,2,3,4,5}',
      v_txt || ' | ' || (r ->> 'texto'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── J. Descartar ──
  begin
    v_antes := pg_temp.foto();
    perform pg_temp.plan('Lenine', '{"dias": 2}', 'Lenine dois dias');
    r := public.agenda_rascunho_descartar(c_autor);
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'J1 *descarta*: "Descartei. Nada foi gravado." e o *grava* depois não tem nada',
      r ->> 'texto' = 'Descartei. Nada foi gravado.' and (r ->> 'descartados')::int = 1
      and r2 ->> 'texto' = 'Não tenho nada esperando para gravar.' and pg_temp.foto() = v_antes, r::text);
    r := public.agenda_rascunho_descartar(c_autor);
    v_res := pg_temp.ok(v_res, 'J2 *descarta* sem nada: "Não tinha nada esperando para gravar."',
      r ->> 'texto' = 'Não tinha nada esperando para gravar.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── K. Material ──
  begin
    r := pg_temp.mat('Vanderlei', array['porta fusível'], 'na_mao', null, 'chegaram 3 porta fusível', null, 3);
    v_res := pg_temp.ok(v_res, 'K1 parcial: "chegaram 3" das 8 → "3 de 8 na mão"',
      r ->> 'item' = 'Vanderlei (OS-00069): Porta Fusível MIDI… 3 de 8 na mão', r::text);
    r := pg_temp.mat('Giancarlo', array['baterias'], 'vou_comprar', null, 'tem as baterias do Giancarlo, vou comprar na Mercado Livre',
                     'Mercado Livre', null, true);
    v_res := pg_temp.ok(v_res, 'K2 peça nova (fora do orçamento) com fornecedor que não está no cadastro',
      r ->> 'item' = 'Giancarlo (OS-00100): Baterias (fora do orçamento) você vai comprar, fornecedor Mercado Livre', r::text);
    r := pg_temp.mat('Nelson', array['Orion'], 'dispensar', null, 'o Orion não precisa mais');
    v_res := pg_temp.ok(v_res, 'K3 dispensar', r ->> 'item' = 'Nelson (OS-00112): Orion-Tr Smart 12/12-30A… não precisa mais (sai da lista)', r::text);
    r := pg_temp.mat('Nelson', array['Cerbo'], 'comprei', 'ontem', 'comprei o Cerbo ontem');
    v_res := pg_temp.ok(v_res, 'K4 "comprei ontem": comprado em qui 22/10 (a data dita, para trás)',
      r ->> 'item' = 'Nelson (OS-00112): Cerbo gx victron… comprado em qui 22/10', r::text);
    r := pg_temp.mat('Nelson', array['painel'], 'comprei', null, 'comprei o painel');
    v_res := pg_temp.ok(v_res, 'K5 "comprei" sem data: comprado hoje', r ->> 'item' = 'Nelson (OS-00112): Painel Touch de… comprado hoje', r::text);
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'K6 gravado: parcial 3/8 continua faltando; a bateria nova é linha do dono ligada à linha de serviço dela; Orion dispensado; Cerbo comprado',
      (r ->> 'ok')::boolean
      and (select m.quantidade_na_mao = 3 and m.situacao = 'falta' and m.fonte = 'dono' from public.os_material m
            where m.service_order_part_id = md5('peca:69:2')::uuid)
      and (select m.origem = 'dono' and m.service_order_service_id = md5('servico:100:1')::uuid and m.fornecedor_nome = 'Mercado Livre'
                  and m.fornecedor_id is null and m.situacao = 'falta' and m.quantidade_necessaria = 1
             from public.os_material m where m.service_order_id = pg_temp.os('100') and m.origem = 'dono')
      and (select m.situacao from public.os_material m where m.service_order_part_id = md5('peca:112:3')::uuid) = 'dispensado'
      and (select m.situacao = 'comprado' and m.comprado_em = '2026-10-22' from public.os_material m
            where m.service_order_part_id = md5('peca:112:2')::uuid),
      r ->> 'texto');
    v_res := pg_temp.ok(v_res, 'K7 na prontidão: a pergunta da peça embutida da "Realocação do banco de baterias" sumiu (a bateria responde por ela)',
      not exists (select 1 from jsonb_array_elements(public.os_prontidao(pg_temp.os('100'), date '2026-10-23') #> '{material,embutidas}') e
                   where e ->> 'linha' = md5('servico:100:1')::uuid::text)
      and exists (select 1 from jsonb_array_elements(public.os_prontidao(pg_temp.os('100'), date '2026-10-23') #> '{material,embutidas}') e),
      null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── K (cont.). "Tá a caminho" sem data vence; a compra combinada não volta a perguntar; o parcial aparece ──
  begin
    perform pg_temp.mat('Nelson', array['Cerbo'], 'a_caminho', null, 'o Cerbo do Nelson tá a caminho');
    r := pg_temp.grava();
    v_a := (select e from jsonb_array_elements(public.os_prontidao(pg_temp.os('112'), date '2026-10-23') #> '{material,itens}') e
             where e ->> 'linha' = md5('peca:112:2')::uuid::text);
    v_b := (select e from jsonb_array_elements(public.os_prontidao(pg_temp.os('112'), date '2026-11-06') #> '{material,itens}') e
             where e ->> 'linha' = md5('peca:112:2')::uuid::text);
    v_res := pg_temp.ok(v_res, 'K8 "tá a caminho" sem data: o pedido conta de hoje (23/10); lido 10 dias úteis depois, a previsão venceu e pergunta "chegou?"',
      (r ->> 'ok')::boolean
      and (select m.comprado_em = '2026-10-23' from public.os_material m where m.service_order_part_id = md5('peca:112:2')::uuid)
      and v_a ->> 'data' = '2026-10-29' and not (v_a ->> 'atrasado')::boolean
      and v_b ->> 'data' = '2026-10-29' and (v_b ->> 'atrasado')::boolean
      and exists (select 1 from jsonb_array_elements(public.os_prontidao(pg_temp.os('112'), date '2026-11-06') -> 'restricoes') e
                   where e ->> 'tipo' = 'atrasado'
                     and e ->> 'texto' = 'a previsão de "Central de controle…" venceu em 29/10: chegou?'),
      v_a::text || ' | ' || v_b::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.mat('Vanderlei', array['tudo'], 'vou_comprar', 'terça', 'Vanderlei eu compro tudo na Casa do Eletricista terça',
                        'Casa do Eletricista');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'K9 "compro terça na Casa do Eletricista" (fora do cadastro): o *grava* não pergunta de novo "de quem e quando"; só quando chega',
      r ->> 'texto' = E'Gravado. Agora:\n• Vanderlei: falta você dizer quando chega a compra de ter 27/10.'
      and not exists (select 1 from jsonb_array_elements(public.os_prontidao(pg_temp.os('69'), date '2026-10-23') -> 'restricoes') e
                       where e ->> 'tipo' = 'sem_previsao')
      and exists (select 1 from jsonb_array_elements(public.os_prontidao(pg_temp.os('69'), date '2026-10-23') -> 'restricoes') e
                   where e ->> 'tipo' = 'compra_sem_prazo' and (e ->> 'bloqueia')::boolean
                     and e ->> 'pergunta' = 'quando chega a compra de ter 27/10?'
                     and e ->> 'texto' = '4 itens: você compra ter 27/10, fornecedor Casa do Eletricista; sem prazo de entrega conhecido: quando chega?'),
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.mat('Vanderlei', array['tudo'], 'vou_comprar', 'terça', 'Vanderlei eu compro tudo terça');
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'K10 "compro tudo terça" sem fornecedor: pergunta só de quem (o quando já foi dito)',
      r ->> 'texto' = E'Gravado. Agora:\n• Vanderlei: falta você dizer de quem é a compra de ter 27/10.'
      and exists (select 1 from jsonb_array_elements(public.os_prontidao(pg_temp.os('69'), date '2026-10-23') -> 'restricoes') e
                   where e ->> 'tipo' = 'compra_sem_prazo'
                     and e ->> 'texto' = '4 itens: você compra ter 27/10; de quem? (sem o fornecedor não sei quando chega)'),
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.mat('Vanderlei', array['porta fusível'], 'na_mao', null, 'chegaram 3 porta fusível', null, 3);
    r := pg_temp.grava();
    v_txt := public.agenda_ver('aa000000-0000-4000-8000-000000000001', null, null, 'material', 'Vanderlei', null, false,
                               date '2026-10-23') ->> 'texto';
    v_res := pg_temp.ok(v_res, 'K11 "chegaram 3 dos 8": a lista do material diz quantas estão na mão e quantas faltam',
      split_part(v_txt, E'\n', 3) like '• Porta Fusível MIDI c/ Capa Proteção — 3 de 8 na mão, faltam 5: a comprar, sem fornecedor — você disse em %: "chegaram 3 porta fusível"',
      v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── L. Planejar ──
  begin
    r := pg_temp.plan('Lenine', '{"sem_material": true, "precisa_ate": "dia 20", "nao_antes_de": "dia 5", "nao_antes_motivo": "o barco está no estaleiro"}',
                      'o do Lenine não tem peça, ele precisa até dia 20 e não dá antes do dia 5, o barco está no estaleiro');
    v_res := pg_temp.ok(v_res, 'L1 "não tem peça", prazo do cliente e "não antes de" com o motivo',
      r ->> 'item' = 'Lenine (OS-00074): o cliente precisa até sex 20/11; não antes de qui 05/11 (o barco está no estaleiro); não tem peça a comprar',
      r::text);
    r := pg_temp.plan('OS-00076', '{"congelar_ate": "dia 10"}', 'o Starlink do Rodrigo fica parado até dia 10');
    v_res := pg_temp.ok(v_res, 'L2 espera sem data para rever: revê no dia em que a espera acaba',
      r ->> 'item' = 'Rodrigo (OS-00076): em espera até ter 10/11', r::text);
    r := pg_temp.plan('Giancarlo', '{"escopo_em_aberto": "fazer tudo de uma vez ou por partes?"}', 'Giancarlo: tudo de uma vez ou por partes?');
    r := pg_temp.plan('Giancarlo', '{"escopo_decidido": "por partes"}', 'Giancarlo vai por partes');
    v_res := pg_temp.ok(v_res, 'L3 o escopo decidido fecha a pergunta em aberto',
      r ->> 'item' = 'Giancarlo (OS-00100): por partes', r::text);
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'L4 gravado: conferido, prazo, não antes de, espera (rever = fim da espera), escopo em aberto nulo',
      (select p.material_conferido_em is not null and p.precisa_ate = '2026-11-20' and p.nao_antes_de = '2026-11-05'
              and p.nao_antes_motivo = 'o barco está no estaleiro' and p.dias is null
         from public.os_planejamento p where p.service_order_id = pg_temp.os('74'))
      and (select p.congelada_ate = '2026-11-10' and p.revisar_em = '2026-11-10'
             from public.os_planejamento p where p.service_order_id = pg_temp.os('76'))
      and (select p.escopo_em_aberto is null and p.escopo_decidido = 'por partes'
             from public.os_planejamento p where p.service_order_id = pg_temp.os('100'))
      and not exists (select 1 from jsonb_array_elements(public.os_prontidao(pg_temp.os('74'), date '2026-10-23') -> 'restricoes') e
                       where e ->> 'tipo' = 'material_nao_conferido'),
      r ->> 'texto');
    v_cod := null;
    begin
      perform pg_temp.plan('Lenine', '{"horas": 4}', 'quatro horas');
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    v_res := pg_temp.ok(v_res, 'L5 campo que não existe é erro de quem chamou (22023), não pergunta ao dono',
      v_cod = '22023' and v_msg = 'agenda_rascunho_planejar: o campo "horas" não existe', v_cod || ' ' || v_msg);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── L (cont.). Desfazer (sai da espera, sem prazo, sem "não antes de", escopo resolvido) e a prioridade ──
  begin
    perform pg_temp.plan('Lenine', '{"congelar_ate": "dia 30"}', 'o Lenine fica parado até dia 30');
    r := pg_temp.grava();
    v_txt := public.os_prontidao(pg_temp.os('74'), date '2026-10-23') ->> 'estado';
    r := pg_temp.plan('Lenine', '{"limpar": ["espera"]}', 'o Lenine pode voltar hoje');
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'L6 "pode voltar" (limpar espera): a releitura diz "sai da espera" e a OS deixa de estar congelada',
      v_txt = 'congelada'
      and r ->> 'item' = 'Lenine (OS-00074): sai da espera'
      and (r2 ->> 'ok')::boolean
      and (select p.congelada_ate is null and p.revisar_em is null from public.os_planejamento p where p.service_order_id = pg_temp.os('74'))
      and public.os_prontidao(pg_temp.os('74'), date '2026-10-23') ->> 'estado' <> 'congelada',
      r::text || ' | ' || (r2 ->> 'texto'));
    perform pg_temp.plan('Lenine', '{"precisa_ate": "dia 20", "nao_antes_de": "dia 5", "escopo_em_aberto": "troca o painel ou só o disjuntor?"}',
                         'o Lenine precisa até dia 20, não antes do dia 5; troca o painel ou só o disjuntor?');
    r := pg_temp.grava();
    r := pg_temp.plan('Lenine', '{"limpar": ["prazo", "nao_antes", "escopo"]}',
                      'o Lenine não tem mais prazo, pode começar quando quiser e o escopo está resolvido');
    r2 := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'L7 limpar prazo, "não antes de" e escopo: as frases e os campos vazios',
      r ->> 'item' = 'Lenine (OS-00074): o cliente não tem mais prazo; pode começar sem esperar data; nada mais a decidir no escopo'
      and (select p.precisa_ate is null and p.nao_antes_de is null and p.nao_antes_motivo is null and p.escopo_em_aberto is null
             from public.os_planejamento p where p.service_order_id = pg_temp.os('74')),
      r::text || ' | ' || (r2 ->> 'texto'));
    v_cod := null;
    begin
      perform pg_temp.plan('Lenine', '{"limpar": ["tudo"]}', 'tira tudo');
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    v_txt2 := v_cod || ' ' || v_msg;
    v_cod := null;
    begin
      perform pg_temp.plan('Lenine', '{"limpar": ["espera"], "congelar_ate": "dia 30"}', 'tira da espera e espera até dia 30');
    exception when others then
      get stacked diagnostics v_cod = returned_sqlstate, v_msg = message_text;
    end;
    v_res := pg_temp.ok(v_res, 'L8 limpar com valor que não existe, ou com o mesmo campo, é erro de quem chamou (22023)',
      v_txt2 = '22023 agenda_rascunho_planejar: limpar "tudo" não existe (espera, nao_antes, prazo ou escopo)'
      and v_cod = '22023' and v_msg = 'agenda_rascunho_planejar: limpar e o mesmo campo na mesma chamada',
      v_txt2 || ' | ' || v_cod || ' ' || v_msg);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_txt := (select string_agg(e ->> 'numero', ' ' order by o)
                from jsonb_array_elements(public.agenda_o_que_fazer(null, date '2026-10-23') #> '{dados,travados}') with ordinality t(e, o));
    r := pg_temp.plan('Giancarlo', '{"prioridade": 1}', 'o do Giancarlo passa na frente');
    perform pg_temp.grava();
    v_txt2 := (select string_agg(e ->> 'numero', ' ' order by o)
                 from jsonb_array_elements(public.agenda_o_que_fazer(null, date '2026-10-23') #> '{dados,travados}') with ordinality t(e, o));
    v_res := pg_temp.ok(v_res, 'L9 "passa na frente" (prioridade 1) no Giancarlo: a OS-00100 vai para o 1º lugar do bloco 2',
      r ->> 'item' = 'Giancarlo (OS-00100): passa na frente (prioridade 1)'
      and v_txt = 'OS-00069 OS-00074 OS-00104 OS-00112 OS-00100 ORÇ-00083 OS-00096'
      and v_txt2 = 'OS-00100 OS-00069 OS-00074 OS-00104 OS-00112 ORÇ-00083 OS-00096',
      v_txt || ' → ' || v_txt2);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── M. A agenda desligada não anota; o rascunho que ficou aberto ainda grava ──
  begin
    perform pg_temp.plan('Lenine', '{"dias": 2}', 'Lenine dois dias');
    update public.agenda_config set modo_leitura = 'desligado';
    v_antes := pg_temp.foto();
    r := pg_temp.plan('Nelson', '{"dias": 2}', 'Nelson dois dias');
    v_a := pg_temp.mat('Flávio', array['compressor'], 'na_mao', null, 'o compressor tá aqui');
    v_b := pg_temp.disp('Roberto', 'nao_vem', 'terça', false, 'o Roberto não vem terça');
    v_res := pg_temp.ok(v_res, 'M1 desligada: as três escritas recusam ("não anotei nada", sem *grava*) e nada entra no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'desligada'
      and r ->> 'pergunta' = 'A agenda de produção está desligada agora: não anotei nada.'
      and not (v_a ->> 'ok')::boolean and v_a ->> 'motivo' = 'desligada'
      and not (v_b ->> 'ok')::boolean and v_b ->> 'motivo' = 'desligada'
      and pg_temp.abertos() = 1,
      r::text || ' | ' || v_a::text || ' | ' || v_b::text);
    r := pg_temp.grava();
    v_res := pg_temp.ok(v_res, 'M2 desligada: o *grava* do rascunho aberto de antes ainda grava (tem saída)',
      (r ->> 'ok')::boolean and (r ->> 'gravados')::int = 1
      and exists (select 1 from public.os_planejamento where service_order_id = pg_temp.os('74') and dias = 2),
      r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$cenarios$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
