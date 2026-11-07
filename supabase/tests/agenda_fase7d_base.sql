-- Prova da base da Agenda de Produção, Fase 7d (pacote P1): os 6 interruptores e os 25 parâmetros, as 2 tabelas novas, as 14 colunas do
-- planejamento, as listas fechadas, as 2 colunas geradas, a regra do conferido, o modo com o freio, o modo cru das 3 perguntas e a fixture
-- da etapa (migration 20261107100000; spec-fase7d §4, §5.1, §8.2, §8.3 e R6.3-1, R6.4, R6.7a, R6.7b, R6.10).
-- bancada: depende de 20261107100000
--
--   B1  colunas, DEFAULTs e CHECKs: agenda_config (os 6 interruptores nascem desligados na linha com o DEFAULT sombra; os 24 parâmetros com
--       o valor da spec; onde_fica_desde nula), os_planejamento e as 2 tabelas; cada CHECK novo recusa o caso dele, pelo nome, e aceita os
--       limites
--   B2  RLS e privilégios: anon nada; o técnico lê 0 e não grava; o administrador lê; as portas das 3 funções novas e da recriada, com o
--       revoke de public e de anon provado em has_function_privilege
--   B3  as listas fechadas: as de antes iguais e na mesma ordem, as novas no fim; critica = a de antes + acesso (local e combinar não);
--       modelo = M11 em onde_fica e os 11 de antes iguais; cliente_tipos_ligados aceita onde_fica, a linha não ganha
--   B4  não apaga; o histórico de agenda_locais (só as colunas de regra, {em, por, antes, depois}, os 20 mais novos, o valor do UPDATE é
--       ignorado); um só patio_hbr ativo
--   B5  _agenda_local_conferido: dono, marina, pesquisa, vencido, no limite, inativo, sem conferência, inexistente, sob a RLS
--   B6  _agenda_local_modo: os 6 nomes, o freio, o nome errado; _agenda_modo_da_pergunta: os 3 tipos, cru (o freio não muda), a cópia só no
--       bloco "-- FASE 7d:", todo tipo tem modo, os tipos de antes iguais
--   B7  nada muda de comportamento: só as 4 funções da migration, nenhum gatilho em tabela de antes, nada de antes chama as novas (até o
--       P2 aplicar), sem dado, ninguém recebe o M11
--   B8  a fixture: os 5 locais (um pátio só: a MP, 3 vagas, nenhum em Itajaí), as OS J e D, a J2, as publicadas, o dia de D, carregar 2× = 1×
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration e ANTES do dado 20261107100900 (que põe os modos em sombra e grava a semente), com o OK
--   nomeado: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_base.sql
--   Seguro em produção: tudo dentro de subtransações desfeitas e termina em ROLLBACK. B6 (a cópia), B7 e B8 usam as fixtures e as migrations
--   como texto e só rodam na bancada (fora dela saem PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, do índice único ou da FK; 'aceitou' quando entrou (e desfaz); 'erro
-- <estado>: <mensagem>' para o resto.
create function pg_temp.recusa(p_sql text) returns text language plpgsql as $f$
declare
  v_nome text; v_estado text; v_msg text;
begin
  begin
    execute p_sql;
    raise exception using errcode = 'P0001', message = '__aceitou__';
  exception when others then
    get stacked diagnostics v_nome = constraint_name, v_estado = returned_sqlstate, v_msg = message_text;
    if v_msg = '__aceitou__' then return 'aceitou'; end if;
    if v_estado in ('23514', '23505', '23503', '23502', '23P01') and coalesce(v_nome, '') <> '' then return v_nome; end if;
    return 'erro ' || v_estado || ': ' || v_msg;
  end;
end $f$;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;

create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;

-- p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou 'erro <estado>: <mensagem>'.
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- Os literais de uma lista fechada (o CHECK pelo nome), na ordem.
create function pg_temp.lista(p_tabela regclass, p_nome text) returns text[] language sql stable as $f$
  select array_agg(m[1] order by o)
    from pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''([^'']*)''', 'g') with ordinality t(m, o)
   where c.conrelid = p_tabela and c.conname = p_nome
$f$;

-- A expressão de uma coluna gerada, avaliada com tipo = p_tipo: o que a coluna daria numa linha desse tipo.
create function pg_temp.gerada(p_tabela regclass, p_coluna text, p_tipo text) returns text language plpgsql stable as $f$
declare
  v_expr text;
  v      text;
begin
  select pg_get_expr(d.adbin, d.adrelid) into strict v_expr
    from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = p_tabela and a.attname = p_coluna and a.attgenerated = 's';
  execute format('select (%s)::text from (select %L::text as tipo) x', v_expr, p_tipo) into v;
  return v;
end $f$;

-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$") e a definição inteira.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7d(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[df]:' and l !~ '^\s*-- FASE 7[df]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[df]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[df]: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;

create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;
-- um local mínimo; a linha fica nesta transação (ou na subtransação de quem chama)
create function pg_temp.local(p_nome text, p_tipo text default 'marina') returns uuid language sql as $f$
  insert into public.agenda_locais (nome, tipo, municipio, uf) values (p_nome, p_tipo, 'Cidade de Teste', 'SC') returning id
$f$;
-- as fixtures como texto (só na bancada)
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7d', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_tabelas_fase7d', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_tarefas_fase7c', true), '') <> ''
$f$;

-- ── B1. Colunas, DEFAULTs e CHECKs ──────────────────────────────────────────────────────────────────
with cfg as (select to_jsonb(c) as j from public.agenda_config c where c.id),
esperado(coluna, valor) as (values
  ('local_conferencia_validade_dias', '365'), ('autorizacao_antecedencia_du', '2'), ('acesso_urgente_du', '1'),
  ('marina_reserva_antecedencia_du', '2'), ('garagem_reserva_min_meios', '1'), ('horario_tolerancia_min', '30'),
  ('patio_entrada_antecedencia_du', '2'), ('patio_retirada_du', '1'), ('patio_tentativas', '3'),
  ('deslocamento_regional_max_min', '45'), ('deslocamento_bate_volta_max_min', '120'), ('deslocamento_fator_estrada', '1.30'),
  ('deslocamento_kmh', '60'), ('bate_volta_meios_dia', '1'), ('pernoite_ida_meios', '1'), ('viagem_km_bate_volta', '120'),
  ('viagem_km_pernoite', '300'), ('onde_fica_janela_dias', '14'), ('onde_fica_antes_dias', '21'), ('local_hora', '16:15:00'))
insert into _resultado
select 'B1a os 20 parâmetros de um valor com o padrão da spec (§4.1)',
       bool_and(cfg.j ->> e.coluna = e.valor) and count(*) = 20,
       string_agg(e.coluna || '=' || coalesce(cfg.j ->> e.coluna, 'nulo'), ', ') filter (where cfg.j ->> e.coluna is distinct from e.valor)
  from cfg, esperado e;

insert into _resultado
select 'B1b temporada_meses {11,12,1,2,3}, viagem_uf_bate_volta {SC}, as palavras do bem e onde_fica_desde nula (R6.7a: ninguém recebe)',
       c.temporada_meses = '{11,12,1,2,3}'::smallint[] and c.viagem_uf_bate_volta = '{SC}'::text[]
       and c.bem_agua_palavras = 'teste de mar|prova de mar|teste no mar|navegando|navegacao|motor ligado|sea trial'
       and c.bem_seco_palavras = 'casco|anodo|transdutor de casco|passa casco|fundo do barco|helice|eixo|pe de galinha'
       and c.onde_fica_desde is null,
       format('%s; %s; desde %s', c.temporada_meses, c.viagem_uf_bate_volta, c.onde_fica_desde)
  from public.agenda_config c where c.id;

with m(coluna) as (values ('modo_local_calendario'), ('modo_local_autorizacao'), ('modo_bem'), ('modo_patio'), ('modo_viagem'), ('modo_mesmo_local'))
insert into _resultado
select 'B1c os 6 interruptores: a linha desligado, o DEFAULT da coluna sombra (a migration de dado põe em sombra)',
       count(*) = 6 and bool_and(to_jsonb(c) ->> m.coluna = 'desligado')
       and bool_and(pg_get_expr(d.adbin, d.adrelid) = '''sombra''::text'),
       string_agg(m.coluna || '=' || (to_jsonb(c) ->> m.coluna) || '/' || pg_get_expr(d.adbin, d.adrelid), ', ')
  from m
  cross join public.agenda_config c
  join pg_attribute a on a.attrelid = 'public.agenda_config'::regclass and a.attname = m.coluna
  join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where c.id;

insert into _resultado
select 'B1d os_planejamento: as 14 colunas novas, todas nulas por padrão',
       count(*) = 14 and bool_and(not a.attnotnull and not a.atthasdef), string_agg(a.attname, ', ' order by a.attnum)
  from pg_attribute a
 where a.attrelid = 'public.os_planejamento'::regclass and not a.attisdropped
   and a.attname in ('local_id', 'local_fonte', 'local_em', 'bem_situacao', 'bem_situacao_fonte', 'bem_situacao_em', 'bem_exige',
                     'descer_quem', 'entrada_em', 'retirada_em', 'entrada_fonte', 'viagem', 'reserva_marina_ok_em', 'descida_ok_em');

-- Cada CHECK de agenda_config recusa o caso dele, pelo nome
do $b1$
declare
  r      record;
  v      text;
  v_dif  text;
  v_n    int := 0;
  v_cob  text[] := '{}';
  v_esta text := coalesce(current_setting('agenda_teste.mig_tabelas_fase7d', true), '');
begin
  for r in select * from (values
    ('modo_local_calendario = ''x''', 'agenda_config_modo_local_calendario_check'),
    ('modo_local_autorizacao = ''x''', 'agenda_config_modo_local_autorizacao_check'),
    ('modo_bem = ''x''', 'agenda_config_modo_bem_check'),
    ('modo_patio = ''x''', 'agenda_config_modo_patio_check'),
    ('modo_viagem = ''x''', 'agenda_config_modo_viagem_check'),
    ('modo_mesmo_local = ''x''', 'agenda_config_modo_mesmo_local_check'),
    ('local_conferencia_validade_dias = 29', 'agenda_config_local_conferencia_validade_dias_check'),
    ('local_conferencia_validade_dias = 731', 'agenda_config_local_conferencia_validade_dias_check'),
    ('autorizacao_antecedencia_du = 11', 'agenda_config_autorizacao_antecedencia_du_check'),
    ('autorizacao_antecedencia_du = -1, acesso_urgente_du = -1', 'agenda_config_acesso_urgente_du_check'),
    ('acesso_urgente_du = 3', 'agenda_config_acesso_urgente_du_check'),
    ('acesso_urgente_du = -1', 'agenda_config_acesso_urgente_du_check'),
    ('autorizacao_antecedencia_du = 0', 'agenda_config_acesso_urgente_du_check'),
    ('marina_reserva_antecedencia_du = 11', 'agenda_config_marina_reserva_antecedencia_du_check'),
    ('garagem_reserva_min_meios = 0', 'agenda_config_garagem_reserva_min_meios_check'),
    ('garagem_reserva_min_meios = 11', 'agenda_config_garagem_reserva_min_meios_check'),
    ('horario_tolerancia_min = 121', 'agenda_config_horario_tolerancia_min_check'),
    ('patio_entrada_antecedencia_du = 11', 'agenda_config_patio_entrada_antecedencia_du_check'),
    ('patio_retirada_du = 6', 'agenda_config_patio_retirada_du_check'),
    ('patio_tentativas = 0', 'agenda_config_patio_tentativas_check'),
    ('patio_tentativas = 7', 'agenda_config_patio_tentativas_check'),
    ('temporada_meses = ''{}''', 'agenda_config_temporada_meses_check'),
    ('temporada_meses = ''{13}''', 'agenda_config_temporada_meses_check'),
    ('temporada_meses = ''{0,1}''', 'agenda_config_temporada_meses_check'),
    ('viagem_uf_bate_volta = ''{sc}''', 'agenda_config_viagem_uf_bate_volta_check'),
    ('viagem_uf_bate_volta = ''{SCX}''', 'agenda_config_viagem_uf_bate_volta_check'),
    ('viagem_uf_bate_volta = ''{SC,NULL}''', 'agenda_config_viagem_uf_bate_volta_check'),
    ('deslocamento_regional_max_min = 9', 'agenda_config_deslocamento_regional_max_min_check'),
    ('deslocamento_regional_max_min = 121, deslocamento_bate_volta_max_min = 300', 'agenda_config_deslocamento_regional_max_min_check'),
    ('deslocamento_bate_volta_max_min = 301', 'agenda_config_deslocamento_bate_volta_max_min_check'),
    ('deslocamento_bate_volta_max_min = 45', 'agenda_config_deslocamento_bate_volta_max_min_check'),
    ('deslocamento_fator_estrada = 0.99', 'agenda_config_deslocamento_fator_estrada_check'),
    ('deslocamento_fator_estrada = 2.01', 'agenda_config_deslocamento_fator_estrada_check'),
    ('deslocamento_kmh = 19', 'agenda_config_deslocamento_kmh_check'),
    ('deslocamento_kmh = 111', 'agenda_config_deslocamento_kmh_check'),
    ('bate_volta_meios_dia = 2', 'agenda_config_bate_volta_meios_dia_check'),
    ('pernoite_ida_meios = 3', 'agenda_config_pernoite_ida_meios_check'),
    ('viagem_km_bate_volta = 19', 'agenda_config_viagem_km_bate_volta_check'),
    ('viagem_km_bate_volta = 1000', 'agenda_config_viagem_km_bate_volta_check'),
    ('viagem_km_pernoite = 2001', 'agenda_config_viagem_km_pernoite_check'),
    ('viagem_km_pernoite = 120', 'agenda_config_viagem_km_pernoite_check'),
    ('onde_fica_janela_dias = 0', 'agenda_config_onde_fica_janela_dias_check'),
    ('onde_fica_janela_dias = 61', 'agenda_config_onde_fica_janela_dias_check'),
    ('onde_fica_antes_dias = 2', 'agenda_config_onde_fica_antes_dias_check'),
    ('onde_fica_antes_dias = 61', 'agenda_config_onde_fica_antes_dias_check'),
    ('local_hora = ''11:59''', 'agenda_config_local_hora_check'),
    ('local_hora = hora_do_plano + interval ''1 minute''', 'agenda_config_local_hora_check'),
    ('bem_agua_palavras = ''ab''', 'agenda_config_bem_agua_palavras_check'),
    ('bem_agua_palavras = repeat(''a'', 401)', 'agenda_config_bem_agua_palavras_check'),
    ('bem_agua_palavras = ''(casco''', 'agenda_config_bem_agua_palavras_check'),
    ('bem_seco_palavras = ''ab''', 'agenda_config_bem_seco_palavras_check'),
    ('bem_seco_palavras = ''[casco''', 'agenda_config_bem_seco_palavras_check'),
    -- FASE 7f: o caso era semana, o tipo que ainda não existia na 7d; a 20261109100000 o põe na lista
    ('cliente_tipos_ligados = ''{cobranca}''', 'agenda_config_cliente_tipos_ligados_check')
    -- FASE 7f: fim
  ) t(sets, nome) loop
    v_n := v_n + 1;
    v_cob := v_cob || r.nome;
    v := pg_temp.recusa(format('update public.agenda_config set %s where id', r.sets));
    if v <> r.nome then
      v_dif := concat_ws('; ', v_dif, format('%s: %s', r.sets, v));
    end if;
  end loop;
  insert into _resultado values (format('B1e cada CHECK de agenda_config recusa o caso dele, pelo nome (%s casos)', v_n), v_dif is null and v_n = 53, v_dif);
  if v_esta <> '' then
    select string_agg(distinct m[1], ', ') into v_dif
      from regexp_matches(v_esta, '''(agenda_config_[a-z_]+_check)''', 'g') m where m[1] <> all (v_cob);
    insert into _resultado values ('B1z todo CHECK de agenda_config da migration (pelo texto dela) tem caso em B1e: um CHECK novo sem caso reprova aqui', v_dif is null, v_dif);
  end if;

  v_dif := null;
  v_n := 0;
  for r in select * from (values
    ('modo_local_calendario = ''ligado'', modo_local_autorizacao = ''sombra'', modo_bem = ''ligado'', modo_patio = ''sombra'', modo_viagem = ''ligado'', modo_mesmo_local = ''sombra'''),
    ('local_conferencia_validade_dias = 30'), ('local_conferencia_validade_dias = 730'),
    ('autorizacao_antecedencia_du = 10'), ('autorizacao_antecedencia_du = 0, acesso_urgente_du = 0'),
    ('acesso_urgente_du = 2'), ('marina_reserva_antecedencia_du = 0'), ('garagem_reserva_min_meios = 10'), ('horario_tolerancia_min = 120'),
    ('patio_entrada_antecedencia_du = 10'), ('patio_retirada_du = 0'), ('patio_tentativas = 6'),
    ('temporada_meses = ''{1,2,3,4,5,6,7,8,9,10,11,12}'''), ('viagem_uf_bate_volta = ''{}'''), ('viagem_uf_bate_volta = ''{SC,PR}'''),
    ('deslocamento_regional_max_min = 10'), ('deslocamento_bate_volta_max_min = 46'), ('deslocamento_fator_estrada = 1.00'), ('deslocamento_kmh = 110'),
    ('bate_volta_meios_dia = 0'), ('pernoite_ida_meios = 2'), ('viagem_km_bate_volta = 299'), ('viagem_km_pernoite = 2000'),
    ('onde_fica_janela_dias = 60'), ('onde_fica_antes_dias = 3'), ('local_hora = ''12:00'''), ('local_hora = hora_do_plano'),
    ('bem_agua_palavras = ''abc'''), ('bem_seco_palavras = repeat(''a'', 400)'),
    ('cliente_tipos_ligados = ''{onde_fica}'''), ('cliente_tipos_ligados = ''{confirmar,vespera,onde_fica}'''),
    ('onde_fica_desde = ''2026-11-07''')
  ) t(sets) loop
    v_n := v_n + 1;
    v := pg_temp.recusa(format('update public.agenda_config set %s where id', r.sets));
    if v <> 'aceitou' then
      v_dif := concat_ws('; ', v_dif, format('%s: %s', r.sets, v));
    end if;
  end loop;
  insert into _resultado values (format('B1f os limites entram (%s casos)', v_n), v_dif is null and v_n = 32, v_dif);
end
$b1$;

-- Os CHECKs das 2 tabelas e do planejamento
do $b1t$
declare
  r       record;
  v       text;
  v_dif   text;
  v_n     int := 0;
  v_os    uuid;
  v_pes   uuid;
  v_loc   uuid;
  c_ins   constant text := 'insert into public.agenda_locais (nome, tipo, municipio, %s) values (''Local Teste'', %s, ''Cidade'', %s)';
begin
  for r in select * from (values
    ('uf', '''marina''', '''sc''', 'agenda_locais_uf_check'),
    ('apelidos', '''marina''', '''{a,b,c,d,e,f,g,h,i}''', 'agenda_locais_apelidos_check'),
    ('latitude', '''marina''', '91', 'agenda_locais_latitude_check'),
    ('longitude', '''marina''', '181', 'agenda_locais_longitude_check'),
    ('sabado', '''marina''', '''x''', 'agenda_locais_sabado_check'),
    ('feriado', '''marina''', '''x''', 'agenda_locais_feriado_check'),
    ('autorizacao_texto', '''marina''', 'repeat(''a'', 201)', 'agenda_locais_autorizacao_texto_check'),
    ('seguro_texto', '''marina''', 'repeat(''a'', 201)', 'agenda_locais_seguro_texto_check'),
    ('taxa_texto', '''marina''', 'repeat(''a'', 121)', 'agenda_locais_taxa_texto_check'),
    ('tomada_max_w', '''marina''', '99', 'agenda_locais_tomada_max_w_check'),
    ('box_max_min', '''marina''', '9', 'agenda_locais_box_max_min_check'),
    ('vagas', '''patio_parceiro''', '0', 'agenda_locais_vagas_check'),
    ('vagas', '''patio_parceiro''', '51', 'agenda_locais_vagas_check'),
    ('vagas', '''marina''', '3', 'local_vagas_so_patio'),
    ('deslocamento_min', '''marina''', '601', 'agenda_locais_deslocamento_min_check'),
    ('viagem', '''marina''', '''x''', 'agenda_locais_viagem_check'),
    ('conferido_por', '''marina''', '''x''', 'agenda_locais_conferido_por_check'),
    ('conferido_por', '''marina''', '''dono''', 'local_conferido_coerente'),
    ('conferido_em', '''marina''', '''2026-11-01''', 'local_conferido_coerente'),
    ('fonte_texto', '''marina''', 'repeat(''a'', 301)', 'agenda_locais_fonte_texto_check'),
    ('nota_dono', '''marina''', 'repeat(''a'', 301)', 'agenda_locais_nota_dono_check'),
    ('abre', '''marina''', '''08:00''', 'local_horario_coerente'),
    ('fecha', '''marina''', '''18:00''', 'local_horario_coerente'),
    ('abre, fecha', '''marina''', '''18:00'', ''08:00''', 'local_horario_coerente'),
    ('latitude', '''marina''', '-26.9', 'local_coordenadas'),
    ('longitude', '''marina''', '-48.6', 'local_coordenadas'),
    ('historico', '''marina''', '''{}''', 'agenda_locais_historico_check')
  ) t(cols, tipo, vals, nome) loop
    v_n := v_n + 1;
    v := pg_temp.recusa(format(c_ins, r.cols, r.tipo, r.vals));
    if v <> r.nome then
      v_dif := concat_ws('; ', v_dif, format('%s=%s: %s', r.cols, r.vals, v));
    end if;
  end loop;
  -- o nome, o tipo e o município, que a fórmula acima não varia
  if pg_temp.recusa($q$insert into public.agenda_locais (nome, tipo, municipio) values ('L', 'marina', 'Cidade')$q$) <> 'agenda_locais_nome_check' then
    v_dif := concat_ws('; ', v_dif, 'nome'); end if;
  if pg_temp.recusa($q$insert into public.agenda_locais (nome, tipo, municipio) values ('Local', 'x', 'Cidade')$q$) <> 'agenda_locais_tipo_check' then
    v_dif := concat_ws('; ', v_dif, 'tipo'); end if;
  if pg_temp.recusa($q$insert into public.agenda_locais (nome, tipo, municipio) values ('Local', 'marina', 'C')$q$) <> 'agenda_locais_municipio_check' then
    v_dif := concat_ws('; ', v_dif, 'municipio'); end if;
  insert into _resultado values (format('B1g cada CHECK de agenda_locais recusa o caso dele, pelo nome (%s casos)', v_n + 3), v_dif is null and v_n = 27, v_dif);

  -- uma linha de planejamento numa OS qualquer (na bancada a fixture de 23/10 tem as OS); tudo desfeito no fim
  v_dif := null;
  select so.id into v_os from public.service_orders so order by so.id limit 1;
  select p.id into v_pes from public.payees p order by p.id limit 1;
  if v_os is null or v_pes is null then
    insert into _resultado values ('B1h os CHECKs do planejamento e de os_autorizados', true, 'PULADO: sem OS ou pessoa');
    return;
  end if;
  begin
    insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
    v_loc := pg_temp.local('Local Plano');
    v_n := 0;
    for r in select * from (values
      (format('local_id = %L', v_loc), 'local_coerente'),
      ('local_fonte = ''dono''', 'local_coerente'),
      (format('local_id = %L, local_fonte = ''x''', v_loc), 'os_planejamento_local_fonte_check'),
      ('bem_situacao = ''agua''', 'situacao_coerente'),
      ('bem_situacao_fonte = ''dono''', 'situacao_coerente'),
      ('bem_situacao = ''x'', bem_situacao_fonte = ''dono''', 'os_planejamento_bem_situacao_check'),
      ('bem_situacao = ''agua'', bem_situacao_fonte = ''x''', 'os_planejamento_bem_situacao_fonte_check'),
      ('bem_exige = ''x''', 'os_planejamento_bem_exige_check'),
      ('descer_quem = ''a''', 'os_planejamento_descer_quem_check'),
      ('descer_quem = repeat(''a'', 81)', 'os_planejamento_descer_quem_check'),
      ('entrada_em = ''2026-11-10''', 'entrada_coerente'),
      ('retirada_em = ''2026-11-10''', 'entrada_coerente'),
      ('entrada_fonte = ''dono''', 'entrada_coerente'),
      ('entrada_em = ''2026-11-10'', retirada_em = ''2026-11-10'', entrada_fonte = ''dono''', 'entrada_antes_saida'),
      ('entrada_em = ''2026-11-11'', retirada_em = ''2026-11-10'', entrada_fonte = ''dono''', 'entrada_antes_saida'),
      ('entrada_em = ''2026-11-10'', entrada_fonte = ''x''', 'os_planejamento_entrada_fonte_check'),
      ('viagem = ''x''', 'os_planejamento_viagem_check')
    ) t(sets, nome) loop
      v_n := v_n + 1;
      v := pg_temp.recusa(format('update public.os_planejamento set %s where service_order_id = %L', r.sets, v_os));
      if v <> r.nome then
        v_dif := concat_ws('; ', v_dif, format('%s: %s', r.sets, v));
      end if;
    end loop;
    -- e o que entra
    for r in select * from (values
      (format('local_id = %L, local_fonte = ''cliente'', local_em = now()', v_loc)),
      ('bem_situacao = ''garagem_seca'', bem_situacao_fonte = ''cliente'', bem_situacao_em = now(), bem_exige = ''agua'', descer_quem = ''a marina'''),
      ('entrada_em = ''2026-11-10'', retirada_em = ''2026-11-12'', entrada_fonte = ''dono'''),
      ('retirada_em = ''2026-11-12'', entrada_fonte = ''cliente'''),
      ('viagem = ''pernoite'', reserva_marina_ok_em = now(), descida_ok_em = now()')
    ) t(sets) loop
      v := pg_temp.recusa(format('update public.os_planejamento set %s where service_order_id = %L', r.sets, v_os));
      if v <> 'aceitou' then
        v_dif := concat_ws('; ', v_dif, format('%s: %s', r.sets, v));
      end if;
    end loop;
    -- os_autorizados
    if pg_temp.recusa(format($q$insert into public.os_autorizados (service_order_id, payee_id, fonte) values (%L, %L, 'x')$q$, v_os, v_pes))
       <> 'os_autorizados_fonte_check' then
      v_dif := concat_ws('; ', v_dif, 'fonte');
    end if;
    if pg_temp.recusa(format($q$insert into public.os_autorizados (service_order_id, payee_id, fonte, trecho) values (%L, %L, 'dono', repeat('a', 301))$q$, v_os, v_pes))
       <> 'os_autorizados_trecho_check' then
      v_dif := concat_ws('; ', v_dif, 'trecho');
    end if;
    if pg_temp.recusa(format($q$insert into public.os_autorizados (service_order_id, payee_id, fonte) values (%L, %L, 'dono')$q$, v_os, gen_random_uuid()))
       <> 'os_autorizados_payee_id_fkey' then
      v_dif := concat_ws('; ', v_dif, 'payee sem cadastro');
    end if;
    insert into public.os_autorizados (service_order_id, payee_id, fonte) values (v_os, v_pes, 'dono');
    if pg_temp.recusa(format($q$insert into public.os_autorizados (service_order_id, payee_id, fonte) values (%L, %L, 'dono')$q$, v_os, v_pes))
       <> 'os_autorizados_pkey' then
      v_dif := concat_ws('; ', v_dif, 'chave repetida');
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado values (format('B1h os CHECKs do planejamento (%s casos, e o que entra) e de os_autorizados, pelo nome', v_n), v_dif is null and v_n = 17, v_dif);
end
$b1t$;

-- ── B2. RLS e privilégios ───────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B2a RLS ligada nas 2 tabelas, com 1 policy: SELECT TO authenticated (nenhuma de escrita)',
       count(*) = 2 and bool_and(c.relrowsecurity
         and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) = 1
         and (select bool_and(p.cmd = 'SELECT' and p.roles = '{authenticated}') from pg_policies p
               where p.schemaname = 'public' and p.tablename = c.relname)),
       string_agg(c.relname || ' rls=' || c.relrowsecurity, ', ')
  from pg_class c where c.oid in ('public.agenda_locais'::regclass, 'public.os_autorizados'::regclass);

insert into _resultado
select 'B2b os privilégios: anon nada; authenticated só SELECT; service_role tudo',
       bool_and(not has_table_privilege('anon', t, 'select,insert,update,delete')
                and has_table_privilege('authenticated', t, 'select')
                and not has_table_privilege('authenticated', t, 'insert,update,delete,truncate')
                and has_table_privilege('service_role', t, 'select,insert,update,delete')),
       null
  from unnest(array['public.agenda_locais', 'public.os_autorizados']) t;

do $b2$
declare
  v_res jsonb := '[]'::jsonb;
  v_loc uuid;
  a text; b text; c text; d text; e text; f text; g text; h text;
begin
  begin
    v_loc := pg_temp.local('Local Leitura');
    update public.agenda_locais set conferido_em = date '2026-11-01', conferido_por = 'dono' where id = v_loc;
    a := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated', $q$select count(*)::text from public.agenda_locais$q$);
    b := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
           $q$insert into public.agenda_locais (nome, tipo, municipio) values ('Local', 'marina', 'Cidade') returning id::text$q$);
    c := pg_temp.como(null, 'anon', $q$select count(*)::text from public.agenda_locais$q$);
    d := pg_temp.como(null, 'anon', $q$select count(*)::text from public.os_autorizados$q$);
    e := pg_temp.como(pg_temp.adm(), 'authenticated', format($q$select count(*)::text from public.agenda_locais where id = '%s'$q$, v_loc));
    f := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
           format($q$select public._agenda_local_conferido('%s', date '2026-11-04')::text$q$, v_loc));
    g := pg_temp.como(pg_temp.adm(), 'authenticated', format($q$select public._agenda_local_conferido('%s', date '2026-11-04')::text$q$, v_loc));
    h := pg_temp.como(null, 'anon', format($q$select public._agenda_local_conferido('%s', date '2026-11-04')::text$q$, v_loc));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B2c as linhas: o técnico lê 0 e gravar dá 42501; anon não lê; o administrador lê; o conferido sob a RLS: técnico false, administrador true, anon 42501',
    a = '0' and b like 'erro 42501%' and c like 'erro 42501%' and d like 'erro 42501%' and e = '1' and f = 'false' and g = 'true' and h like 'erro 42501%',
    format('%s | %s | %s | %s | %s | %s | %s | %s', a, b, c, d, e, f, g, h));
  a := pg_temp.como(null, 'anon', $q$select public._agenda_local_modo('bem')$q$);
  b := pg_temp.como(pg_temp.adm(), 'authenticated', $q$select public._agenda_local_modo('bem')$q$);
  c := pg_temp.como(null, 'service_role', $q$select public._agenda_local_modo('bem')$q$);
  d := pg_temp.como(null, 'anon', $q$select public._agenda_modo_da_pergunta('acesso', 'x')$q$);
  e := pg_temp.como(pg_temp.adm(), 'authenticated', $q$select public._agenda_modo_da_pergunta('acesso', 'x')$q$);
  f := pg_temp.como(null, 'service_role', $q$select public._agenda_modo_da_pergunta('acesso', 'x')$q$);
  v_res := pg_temp.ok(v_res, 'B2d o modo: anon 42501; o administrador e o serviço leem; o modo da pergunta só o serviço (como antes)',
    a like 'erro 42501%' and b = 'desligado' and c = 'desligado' and d like 'erro 42501%' and e like 'erro 42501%' and f = 'desligado',
    format('%s | %s | %s | %s | %s | %s', a, b, c, d, e, f));
  perform pg_temp.gravar(v_res);
end
$b2$;

with f(sig, quem, vol) as (values
  ('public._agenda_local_conferido(uuid, date)', 'leitura', 's'),
  ('public._agenda_local_modo(text)', 'leitura', 's'),
  ('public._agenda_modo_da_pergunta(text, text)', 'servico', 's'),
  ('public._agenda_locais_historico()', 'gatilho', 'v'))
insert into _resultado
select 'B2e as portas: revoke de public E de anon nas 4; o conferido e o modo: authenticated e service_role; o modo da pergunta: só o service_role; o gatilho: ninguém; nenhuma definer, search_path fixo',
       count(p.oid) = 4
       and bool_and(not p.prosecdef and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
                    and p.proacl is not null
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          when 'servico' then not has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute') end),
       string_agg(format('%s %s definer=%s anon=%s auth=%s srv=%s', f.sig, p.provolatile, p.prosecdef,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── B3. As listas fechadas e as colunas geradas ─────────────────────────────────────────────────────
-- Os valores de antes são os de produção em 05/11 (rec7d_listas). As etapas seguintes somam depois: confere-se o começo da lista.
do $b3$
declare
  v_res  jsonb := '[]'::jsonb;
  v_ant  text[];
  v      text[];
  v_t    text;
  v_dif  text;
  r      record;
begin
  v_ant := array['nao_cabe', 'segundo_atraso', 'atraso_longo', 'remarcar_confirmado', 'fixada_pelo_dono', 'conferencia', 'chegou', 'parada',
                 'estouro', 'duracao', 'material_conferir', 'padrao_do_dono', 'diaria', 'diaria_ligar', 'equipe_resposta', 'concluir', 'entrega',
                 'nfe_vincular', 'pix_material', 'previsao_fornecedor', 'fornecedor_cadastro', 'fornecedores_prazo', 'cliente_aprovar',
                 'cliente_aviso', 'cliente_resposta', 'aprendizado', 'equipe_sem_dias', 'situacao', 'estimativa', 'equipe_cadastro', 'reavaliar',
                 'reestimar', 'ficha_estimativa', 'bem_livre', 'compre_ate', 'sinal', 'onda', 'dia_avisado', 'dia_prometido', 'sabado',
                 'dias_semana', 'habilidade', 'tarefa'];
  v := pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check');
  v_res := pg_temp.ok(v_res, 'B3a agenda_perguntas.tipo: os 43 de antes na mesma ordem + local, combinar, acesso',
    v[1:46] = v_ant || array['local', 'combinar', 'acesso'], array_to_string(v, ','));

  v_ant := array['publicar', 'criar', 'mover', 'cancelar', 'fixar', 'promover_reserva', 'soltar_reserva', 'status', 'resultado', 'desfazer',
                 'diaria', 'concluir', 'entregar', 'equipe', 'material', 'fornecedor', 'cliente', 'aprendizado', 'estimar', 'reestimar',
                 'reparar', 'gestor', 'dupla', 'habilidade', 'tarefa'];
  v := pg_temp.lista('public.agenda_acoes'::regclass, 'agenda_acoes_tipo_check');
  v_res := pg_temp.ok(v_res, 'B3b agenda_acoes.tipo: os 25 de antes + local', v[1:26] = v_ant || array['local'], array_to_string(v, ','));

  v := pg_temp.lista('public.agenda_vigia_rodadas'::regclass, 'agenda_vigia_rodadas_rotina_check');
  v_res := pg_temp.ok(v_res, 'B3c agenda_vigia_rodadas.rotina: as 9 de antes + local',
    v[1:10] = array['vigia', 'rotina', 'material', 'cliente', 'aprender', 'gestor', 'equipe_semana', 'habilidade', 'tarefas', 'local'], array_to_string(v, ','));

  v := pg_temp.lista('public.agenda_alocacoes'::regclass, 'agenda_alocacoes_cancelada_motivo_check');
  v_res := pg_temp.ok(v_res, 'B3d agenda_alocacoes.cancelada_motivo: os 13 de antes + local (sem autorizacao: o acesso não é filtro de pessoa)',
    v[1:14] = array['replanejado', 'desfeito', 'os_saiu', 'pessoa', 'material', 'cliente', 'clima', 'condicao_vencida', 'promovida', 'dono', 'espera',
                    'reestimada', 'habilidade', 'local'] and not ('autorizacao' = any (v)), array_to_string(v, ','));

  v := pg_temp.lista('public.agenda_cliente_mensagens'::regclass, 'agenda_cliente_mensagens_tipo_check');
  v_res := pg_temp.ok(v_res, 'B3e agenda_cliente_mensagens.tipo: os 11 de antes + onde_fica',
    v[1:12] = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data', 'pronto', 'pronto_lembrete',
                    'pos_servico', 'mudanca_no_dia', 'onde_fica'], array_to_string(v, ','));

  -- critica: avaliada tipo a tipo (a expressão viva da coluna)
  select string_agg(t, ',' order by t) into v_t
    from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t
   where pg_temp.gerada('public.agenda_perguntas'::regclass, 'critica', t) = 'true';
  v_res := pg_temp.ok(v_res, 'B3f critica: os 12 de antes + acesso; local e combinar não são críticas (a expressão viva, tipo a tipo)',
    v_t = 'acesso,aprendizado,atraso_longo,cliente_aviso,dia_avisado,dia_prometido,diaria,fixada_pelo_dono,nao_cabe,onda,remarcar_confirmado,sabado,segundo_atraso',
    v_t);

  -- modelo: os 11 de antes iguais à expressão de antes; onde_fica = M11; o que não está na lista cai no else, como antes
  for r in select * from (values ('confirmar', 'M1'), ('vespera', 'M2'), ('material_chegou', 'M3'), ('acesso', 'M4'), ('andamento', 'M5'),
                                 ('pode_atrasar', 'M6'), ('nova_data', 'M7'), ('pronto', 'M8'), ('pronto_lembrete', 'M8'), ('pos_servico', 'M9'),
                                 ('mudanca_no_dia', 'M10'), ('onde_fica', 'M11'), ('outro', 'M10')) t(tipo, m) loop
    v_t := pg_temp.gerada('public.agenda_cliente_mensagens'::regclass, 'modelo', r.tipo);
    if v_t is distinct from r.m then
      v_dif := concat_ws('; ', v_dif, format('%s = %s', r.tipo, v_t));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B3g modelo: onde_fica = M11 pelo SET EXPRESSION; os 11 de antes iguais; o resto no else', v_dif is null, v_dif);

  -- as constraints que dependem de critica continuam lá, com o mesmo nome, e valem para o tipo novo
  -- FASE 7f: a 20261109100000 tira veto_nao_critica de propósito (AG7-15)
  v_res := pg_temp.ok(v_res, 'B3h critica_tem_opcoes, critica_decidida e, até a 7f, veto_nao_critica de pé depois do SET EXPRESSION',
    (select count(*) from pg_constraint where conrelid = 'public.agenda_perguntas'::regclass
      and conname in ('critica_tem_opcoes', 'critica_decidida', 'veto_nao_critica'))
    = case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                     and a.attname = 'modo_bloco_agenda' and not a.attisdropped) then 2 else 3 end, null);
  -- FASE 7f: fim

  v_res := pg_temp.ok(v_res, 'B3i cliente_tipos_ligados: a lista do CHECK aceita onde_fica, e a forma continua "<@" (o ampliador não serve, R6.4)',
    (select pg_get_constraintdef(c.oid) like '%<@%''onde_fica''%' from pg_constraint c
      where c.conrelid = 'public.agenda_config'::regclass and c.conname = 'agenda_config_cliente_tipos_ligados_check'),
    (select pg_get_constraintdef(c.oid) from pg_constraint c
      where c.conrelid = 'public.agenda_config'::regclass and c.conname = 'agenda_config_cliente_tipos_ligados_check'));
  v_res := pg_temp.ok(v_res, 'B3j a linha NÃO ganha onde_fica: o tipo fica fora da lista, em teste',
    (select not ('onde_fica' = any (c.cliente_tipos_ligados)) from public.agenda_config c where c.id), null);
  perform pg_temp.gravar(v_res);
end
$b3$;

-- ── B4. Não apaga; o histórico ──────────────────────────────────────────────────────────────────────
do $b4$
declare
  v_res jsonb := '[]'::jsonb;
  v_loc uuid;
  v_os  uuid;
  v_pes uuid;
  v_h   jsonb;
  v_em  timestamptz;
  v_por uuid := 'aa000000-0000-4000-8000-0000000000aa';
  i     int;
  a text; b text; c text;
begin
  begin
    v_loc := pg_temp.local('Local Histórico');
    a := pg_temp.recusa(format('delete from public.agenda_locais where id = %L', v_loc));
    v_res := pg_temp.ok(v_res, 'B4a agenda_locais não se apaga', a = 'erro P0001: O registro da agenda não se apaga.', a);

    select so.id into v_os from public.service_orders so order by so.id limit 1;
    select p.id into v_pes from public.payees p order by p.id limit 1;
    if v_os is not null and v_pes is not null then
      insert into public.os_autorizados (service_order_id, payee_id, fonte) values (v_os, v_pes, 'dono');
      a := pg_temp.recusa(format('delete from public.os_autorizados where service_order_id = %L', v_os));
      b := pg_temp.recusa(format('update public.os_autorizados set revogado_em = now() where service_order_id = %L', v_os));
      v_res := pg_temp.ok(v_res, 'B4b os_autorizados não se apaga; sai por revogado_em', a = 'erro P0001: O registro da agenda não se apaga.' and b = 'aceitou', a || ' | ' || b);
    end if;

    -- coluna que não é de regra: atualizado_em muda, o histórico não
    update public.agenda_locais set atualizado_em = timestamptz '2020-01-01 00:00-03' where id = v_loc;
    update public.agenda_locais set nome = 'Local Novo', apelidos = '{novo}', fonte_texto = 'x' where id = v_loc returning historico, atualizado_em into v_h, v_em;
    v_res := pg_temp.ok(v_res, 'B4c nome, apelidos e fonte não entram no histórico; atualizado_em é posto pelo gatilho',
      v_h = '[]'::jsonb and v_em > timestamptz '2020-01-01 00:00-03', v_h::text);

    -- coluna de regra: {em, por, antes, depois}, só o que mudou
    update public.agenda_locais set sabado = 'manha', vagas = null, atualizado_por = v_por where id = v_loc returning historico into v_h;
    v_res := pg_temp.ok(v_res, 'B4d a mudança de regra entra como {em, por, antes, depois}, só com as colunas que mudaram',
      jsonb_array_length(v_h) = 1 and v_h -> 0 -> 'antes' = '{"sabado": null}'::jsonb and v_h -> 0 -> 'depois' = '{"sabado": "manha"}'::jsonb
      and (v_h -> 0 ->> 'por')::uuid = v_por and (v_h -> 0 ->> 'em') is not null, v_h::text);

    -- o valor que vier no UPDATE é ignorado
    update public.agenda_locais set historico = '[{"x": 1}]' where id = v_loc returning historico into v_h;
    v_res := pg_temp.ok(v_res, 'B4e o historico do UPDATE é ignorado: só o gatilho escreve',
      jsonb_array_length(v_h) = 1 and v_h -> 0 ->> 'x' is null, v_h::text);

    -- os 20 mais novos
    for i in 1 .. 21 loop
      update public.agenda_locais set tomada_max_w = 1000 + i where id = v_loc returning historico into v_h;
    end loop;
    v_res := pg_temp.ok(v_res, 'B4f o histórico guarda os 20 mais novos',
      jsonb_array_length(v_h) = 20 and v_h -> 19 -> 'depois' ->> 'tomada_max_w' = '1021' and v_h -> 0 -> 'depois' ->> 'tomada_max_w' = '1002',
      format('%s entradas; 1ª %s; última %s', jsonb_array_length(v_h), v_h -> 0 -> 'depois', v_h -> 19 -> 'depois'));

    -- um só patio_hbr ativo
    update public.agenda_locais set tipo = 'patio_hbr' where id = v_loc;
    a := pg_temp.recusa($q$insert into public.agenda_locais (nome, tipo, municipio) values ('Outro', 'patio_hbr', 'Cidade')$q$);
    update public.agenda_locais set ativo = false where id = v_loc;
    b := pg_temp.recusa($q$insert into public.agenda_locais (nome, tipo, municipio) values ('Outro', 'patio_hbr', 'Cidade')$q$);
    c := pg_temp.recusa($q$insert into public.agenda_locais (nome, tipo, municipio) values ('Parceiro', 'patio_parceiro', 'Cidade')$q$);
    v_res := pg_temp.ok(v_res, 'B4g um só patio_hbr ativo: o 2º é recusado; com o 1º inativo, entra; patio_parceiro não conta',
      a = 'agenda_locais_um_patio_hbr' and b = 'aceitou' and c = 'aceitou', format('%s | %s | %s', a, b, c));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B5. _agenda_local_conferido ─────────────────────────────────────────────────────────────────────
do $b5$
declare
  v_res jsonb := '[]'::jsonb;
  c_hoje constant date := date '2026-11-04';
  v_dono uuid; v_marina uuid; v_pesq uuid; v_nada uuid; v_inativo uuid;
begin
  begin
    v_dono := pg_temp.local('Local Dono');
    v_marina := pg_temp.local('Local Marina');
    v_pesq := pg_temp.local('Local Pesquisa');
    v_nada := pg_temp.local('Local Nada');
    v_inativo := pg_temp.local('Local Inativo');
    update public.agenda_locais set conferido_em = c_hoje - 10, conferido_por = 'dono' where id = v_dono;
    update public.agenda_locais set conferido_em = c_hoje - 10, conferido_por = 'marina' where id = v_marina;
    update public.agenda_locais set conferido_em = c_hoje - 10, conferido_por = 'pesquisa' where id = v_pesq;
    update public.agenda_locais set conferido_em = c_hoje - 10, conferido_por = 'dono', ativo = false where id = v_inativo;

    v_res := pg_temp.ok(v_res, 'B5a dono e marina conferem; a pesquisa é nota; sem conferência, inativo e inexistente = false',
      public._agenda_local_conferido(v_dono, c_hoje) and public._agenda_local_conferido(v_marina, c_hoje)
      and not public._agenda_local_conferido(v_pesq, c_hoje) and not public._agenda_local_conferido(v_nada, c_hoje)
      and not public._agenda_local_conferido(v_inativo, c_hoje) and not public._agenda_local_conferido(gen_random_uuid(), c_hoje)
      and not public._agenda_local_conferido(null, c_hoje) and not public._agenda_local_conferido(v_dono, null), null);

    update public.agenda_locais set conferido_em = c_hoje - 365 where id = v_dono;
    update public.agenda_locais set conferido_em = c_hoje - 366 where id = v_marina;
    v_res := pg_temp.ok(v_res, 'B5b a validade: 365 dias ainda vale; 366, venceu',
      public._agenda_local_conferido(v_dono, c_hoje) and not public._agenda_local_conferido(v_marina, c_hoje), null);

    update public.agenda_config set local_conferencia_validade_dias = 400 where id;
    v_res := pg_temp.ok(v_res, 'B5c a validade é o parâmetro: com 400, o de 366 dias volta a valer',
      public._agenda_local_conferido(v_marina, c_hoje), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$b5$;

-- ── B6. O modo com o freio e o modo cru das perguntas ───────────────────────────────────────────────
do $b6$
declare
  v_res   jsonb := '[]'::jsonb;
  r       record;
  v_dif   text;
  v_a     text;
  v_n     int;
  v_novo  text;
  v_esta  text := coalesce(current_setting('agenda_teste.mig_tabelas_fase7d', true), '');
  v_mig   text := coalesce(current_setting('agenda_teste.mig_tarefas_fase7c', true), '');
begin
 begin
  -- os 6 nomes: cada um lê o interruptor dele, e só ele (os outros 5 em outro valor)
  update public.agenda_config set gestor_so_propor = false where id;
  for r in select * from (values ('calendario', 'modo_local_calendario'), ('acesso', 'modo_local_autorizacao'), ('bem', 'modo_bem'),
                                 ('patio', 'modo_patio'), ('viagem', 'modo_viagem'), ('mesmo_local', 'modo_mesmo_local')) t(q, col) loop
    update public.agenda_config
       set modo_local_calendario = 'desligado', modo_local_autorizacao = 'desligado', modo_bem = 'desligado', modo_patio = 'desligado',
           modo_viagem = 'desligado', modo_mesmo_local = 'desligado' where id;
    execute format('update public.agenda_config set %I = ''ligado'' where id', r.col);
    if public._agenda_local_modo(r.q) <> 'ligado'
       or (select count(*) from unnest(array['calendario', 'acesso', 'bem', 'patio', 'viagem', 'mesmo_local']) q
            where public._agenda_local_modo(q) = 'ligado') <> 1 then
      v_dif := concat_ws('; ', v_dif, r.q);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B6a _agenda_local_modo: os 6 nomes, cada um lê o interruptor dele e só ele', v_dif is null, v_dif);

  -- o freio: ligado vale sombra; sombra e desligado não mudam (R6.7b)
  v_dif := null;
  for r in select * from (values ('desligado', false, 'desligado'), ('sombra', false, 'sombra'), ('ligado', false, 'ligado'),
                                 ('desligado', true, 'desligado'), ('sombra', true, 'sombra'), ('ligado', true, 'sombra')) t(m, freio, espera) loop
    update public.agenda_config
       set modo_local_calendario = r.m, modo_local_autorizacao = r.m, modo_bem = r.m, modo_patio = r.m, modo_viagem = r.m, modo_mesmo_local = r.m,
           gestor_so_propor = r.freio where id;
    select string_agg(q || '=' || public._agenda_local_modo(q), ',') filter (where public._agenda_local_modo(q) is distinct from r.espera)
      into v_a from unnest(array['calendario', 'acesso', 'bem', 'patio', 'viagem', 'mesmo_local']) q;
    if v_a is not null then
      v_dif := concat_ws('; ', v_dif, format('%s freio %s: %s', r.m, r.freio, v_a));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B6b o freio: *gestor, só propor* faz o ligado valer sombra nos 6; sombra e desligado não mudam', v_dif is null, v_dif);

  -- o freio de produção de hoje: a linha com gestor_so_propor = true e tudo ligado nada liga
  update public.agenda_config
     set modo_local_calendario = 'ligado', modo_local_autorizacao = 'ligado', modo_bem = 'ligado', modo_patio = 'ligado', modo_viagem = 'ligado',
         modo_mesmo_local = 'ligado', gestor_so_propor = true where id;
  v_res := pg_temp.ok(v_res, 'B6c com o freio, nenhum modo efetivo é ligado',
    not exists (select 1 from unnest(array['calendario', 'acesso', 'bem', 'patio', 'viagem', 'mesmo_local']) q
                 where public._agenda_local_modo(q) = 'ligado'), null);

  -- o modo da pergunta é CRU: com o freio e o modo ligado, a pergunta continua no modo ligado (R6.7b: continua respondível)
  v_res := pg_temp.ok(v_res, 'B6d _agenda_modo_da_pergunta é cru: com o freio, acesso e combinar seguem ligado, onde _agenda_local_modo diz sombra',
    public._agenda_modo_da_pergunta('acesso', 'acesso:x:2026-11-10') = 'ligado'
    and public._agenda_modo_da_pergunta('combinar', 'combinar:acesso:x:2026-11-10') = 'ligado'
    and public._agenda_modo_da_pergunta('combinar', 'combinar:reserva_marina:x:2026-11-10') = 'ligado'
    and public._agenda_modo_da_pergunta('combinar', 'combinar:entrada:x:2026-11-10') = 'ligado'
    and public._agenda_local_modo('acesso') = 'sombra', null);

  -- os 3 tipos, cada um no interruptor dele: valores todos diferentes para não coincidir
  update public.agenda_config
     set modo_cliente = 'ligado', modo_local_autorizacao = 'sombra', modo_bem = 'desligado', modo_patio = 'ligado', gestor_so_propor = false where id;
  v_res := pg_temp.ok(v_res, 'B6e local = modo_cliente; acesso e combinar:acesso = modo_local_autorizacao',
    public._agenda_modo_da_pergunta('local', 'local:x') = 'ligado' and public._agenda_modo_da_pergunta('acesso', 'acesso:x:2026-11-10') = 'sombra'
    and public._agenda_modo_da_pergunta('combinar', 'combinar:acesso:x:2026-11-10') = 'sombra', null);
  v_res := pg_temp.ok(v_res, 'B6f combinar pela chave: reserva_marina e descida = modo_bem; entrada = modo_patio',
    public._agenda_modo_da_pergunta('combinar', 'combinar:reserva_marina:x:2026-11-10') = 'desligado'
    and public._agenda_modo_da_pergunta('combinar', 'combinar:descida:x:2026-11-10') = 'desligado'
    and public._agenda_modo_da_pergunta('combinar', 'combinar:entrada:x:2026-11-10') = 'ligado', null);
  v_res := pg_temp.ok(v_res, 'B6g combinar com chave de outro tipo ou nula cai no do acesso (nunca nulo: a limpeza da vigia precisa do modo)',
    public._agenda_modo_da_pergunta('combinar', 'combinar:x') = 'sombra' and public._agenda_modo_da_pergunta('combinar', null) = 'sombra', null);
  v_res := pg_temp.ok(v_res, 'B6h todo tipo da lista fechada tem o modo de quem o faz (o tipo novo sem modo reprova aqui)',
    not exists (select 1 from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t
                 where public._agenda_modo_da_pergunta(t, t || ':x') is null),
    (select string_agg(t, ',') from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t
      where public._agenda_modo_da_pergunta(t, t || ':x') is null));

  if v_mig = '' or v_esta = '' then
    v_res := pg_temp.ok(v_res, 'B6i e B6j (o de antes e a cópia)', true, 'PULADO: sem agenda_teste.mig_tarefas_fase7c e agenda_teste.mig_tabelas_fase7d (rode pela bancada)');
  else
    -- o de antes (a definição de 20261102100550 rodada como pg_temp): os 43 tipos de antes iguais, em três combinações de modos
    execute replace(pg_temp.inteira(v_mig, '_agenda_modo_da_pergunta'), 'create or replace function public._agenda_modo_da_pergunta(',
                    'create function pg_temp.modo_antes(');
    for r in select * from (values ('desligado', 'desligado'), ('ligado', 'sombra'), ('sombra', 'ligado')) t(m, m2) loop
      update public.agenda_config
         set modo_marcar_sozinho = r.m, modo_revisao_diaria = r.m2, modo_compre_ate = r.m, modo_dias = r.m2, modo_cadastro = r.m,
             modo_habilidade = r.m2, modo_habilidade_propor = r.m, modo_tarefas = r.m2, modo_cliente = r.m, modo_proposta = r.m2, modo_vigia = r.m,
             modo_local_calendario = r.m2, modo_local_autorizacao = r.m, modo_bem = r.m2, modo_patio = r.m, modo_viagem = r.m2, modo_mesmo_local = r.m
       where id;
      select string_agg(t, ',' order by t) filter (where public._agenda_modo_da_pergunta(t, t || ':x') is distinct from pg_temp.modo_antes(t, t || ':x')),
             count(*)
        into v_a, v_n
        from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t;
      v_res := pg_temp.ok(v_res, format('B6i o modo de cada tipo é o de antes, menos acesso, combinar e local (novos) — %s/%s', r.m, r.m2),
        v_a = 'acesso,combinar,local' and v_n >= 46, coalesce(v_a, '-') || ' de ' || v_n);
    end loop;
    -- a cópia: o corpo vivo = o desta migration; sem o bloco "-- FASE 7d:" é o de 20261102100550
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public._agenda_modo_da_pergunta(text, text)'::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7d: fim', 'g');
    v_res := pg_temp.ok(v_res, 'B6j a cópia de _agenda_modo_da_pergunta: o corpo vivo é o desta migration; sem o bloco "-- FASE 7d:" (1), é o corpo de 20261102100550 (a mais nova antes da 7d), byte a byte',
      v_n = 1 and v_novo = pg_temp.corpo(v_esta, '_agenda_modo_da_pergunta') and pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta') <> ''
      and pg_temp.sem_7d(v_novo) = pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta'),
      format('blocos %s; fonte %s letras; novo sem o bloco %s letras', v_n, length(pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta')), length(pg_temp.sem_7d(v_novo))));
  end if;
  raise exception 'desfaz' using errcode = 'P0099';
 exception when sqlstate 'P0099' then null;
 end;
  -- o nome errado: lança, fora do bloco acima
  v_a := pg_temp.recusa($q$select public._agenda_local_modo('outro')$q$);
  v_dif := pg_temp.recusa($q$select public._agenda_local_modo(null)$q$);
  v_res := pg_temp.ok(v_res, 'B6k _agenda_local_modo com outro nome ou nulo = 22023',
    v_a like 'erro 22023:%' and v_dif like 'erro 22023:%', v_a || ' | ' || v_dif);
  perform pg_temp.gravar(v_res);
end
$b6$;

-- ── B7. Nada muda de comportamento ──────────────────────────────────────────────────────────────────
do $b7$
declare
  v_res  jsonb := '[]'::jsonb;
  v_esta text := coalesce(current_setting('agenda_teste.mig_tabelas_fase7d', true), '');
  v_t    text;
begin
  if v_esta = '' then
    insert into _resultado values ('B7 nada muda de comportamento', true, 'PULADO: sem agenda_teste.mig_tabelas_fase7d (rode pela bancada)');
    return;
  end if;
  select string_agg(n, ',' order by n) into v_t
    from (select distinct m[1] as n from regexp_matches(replace(v_esta, E'\r\n', E'\n'), 'create or replace function public\.([a-z_0-9]+)\(', 'g') m) x;
  v_res := pg_temp.ok(v_res, 'B7a a migration só cria as 3 novas e recria _agenda_modo_da_pergunta: nada do motor, da vigia nem dos textos',
    v_t = '_agenda_locais_historico,_agenda_local_conferido,_agenda_local_modo,_agenda_modo_da_pergunta', v_t);

  v_res := pg_temp.ok(v_res, 'B7b nenhum gatilho novo em tabela de antes: as funções novas só disparam em agenda_locais',
    not exists (select 1 from pg_trigger t
                 where not t.tgisinternal and t.tgfoid = 'public._agenda_locais_historico()'::regprocedure
                   and t.tgrelid <> 'public.agenda_locais'::regclass), null);

  -- Nada de antes chama o que é novo. Vale até a migration de quem passa a chamar (o P2 cria a primeira função que entra aqui): daí em
  -- diante esta linha sai sozinha, pela régua de cada pacote.
  if to_regprocedure('public.agenda_feriado_municipal(date, text)') is null then
    select string_agg(p.proname, ',' order by p.proname) into v_t
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.prosrc ~ '(_agenda_local_modo|_agenda_local_conferido|agenda_locais|os_autorizados|modo_local_calendario|modo_bem|modo_patio|modo_viagem|modo_mesmo_local|onde_fica|bem_situacao|local_fonte|temporada_meses)'
       and p.proname not in ('_agenda_local_conferido', '_agenda_local_modo', '_agenda_locais_historico', '_agenda_modo_da_pergunta');
    v_res := pg_temp.ok(v_res, 'B7c nenhuma função de antes lê as colunas, as tabelas ou as funções novas: com os 6 desligados, o motor, a vigia e os textos são os de antes',
      v_t is null, v_t);
  end if;

  v_res := pg_temp.ok(v_res, 'B7d sem dado: as 2 tabelas vazias (a semente é do dado 20261107100900, o P8)',
    (select count(*) from public.agenda_locais) = 0 and (select count(*) from public.os_autorizados) = 0, null);
  v_res := pg_temp.ok(v_res, 'B7e nenhuma linha de planejamento ganhou valor nas 14 colunas',
    not exists (select 1 from public.os_planejamento pl
                 where num_nonnulls(pl.local_id, pl.local_fonte, pl.local_em, pl.bem_situacao, pl.bem_situacao_fonte, pl.bem_situacao_em, pl.bem_exige,
                                    pl.descer_quem, pl.entrada_em, pl.retirada_em, pl.entrada_fonte, pl.viagem, pl.reserva_marina_ok_em, pl.descida_ok_em) > 0), null);
  v_res := pg_temp.ok(v_res, 'B7f ninguém recebe o M11: onde_fica_desde nula e o tipo fora da lista; nenhuma mensagem onde_fica',
    (select c.onde_fica_desde is null and not ('onde_fica' = any (c.cliente_tipos_ligados)) from public.agenda_config c where c.id)
    and not exists (select 1 from public.agenda_cliente_mensagens m where m.tipo = 'onde_fica'), null);
  v_res := pg_temp.ok(v_res, 'B7g nenhuma pergunta, ação ou rodada do tipo novo',
    not exists (select 1 from public.agenda_perguntas q where q.tipo in ('local', 'combinar', 'acesso'))
    and not exists (select 1 from public.agenda_acoes a where a.tipo = 'local')
    and not exists (select 1 from public.agenda_vigia_rodadas r where r.rotina = 'local'), null);
  perform pg_temp.gravar(v_res);
end
$b7$;

-- ═══ Daqui em diante, a fixture (só na bancada) ═════════════════════════════════════════════════════
do $b8$
declare
  v_res jsonb := '[]'::jsonb;
  v_dia date;
  v_n1  int;
  v_n2  int;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('B8 a fixture', true, 'PULADO: sem as fixtures como texto (rode pela bancada)');
    return;
  end if;
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  perform set_config('agenda_teste.fase7c_variante', '', true);
  perform set_config('agenda_teste.fase7c_etiquetas', '', true);

  -- o dia de D em julho (agenda_teste.fase7d_d_dia), desfeito
  begin
    perform set_config('agenda_teste.fase7d_d_dia', '2027-07-13', true);
    execute current_setting('agenda_teste.fase7d');
    select min(a.dia) into v_dia from public.agenda_alocacoes a
      join public.service_orders so on so.id = a.service_order_id where so.service_order_number = 'OS-D1';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda_teste.fase7d_d_dia', '', true);
  v_res := pg_temp.ok(v_res, 'B8a agenda_teste.fase7d_d_dia troca o dia da OS-D1 (o mesmo cenário em julho)', v_dia = date '2027-07-13', v_dia::text);

  execute current_setting('agenda_teste.fase7d');

  v_res := pg_temp.ok(v_res, 'B8b os 5 locais da §8.2, com o R6.10: Marina Itajaí, Tedesco, MP, Caiobá e Veleiros da Ilha',
    (select array_agg(l.nome order by l.nome) from public.agenda_locais l)
    = array['Iate Clube Caiobá', 'MP Motorhomes', 'Marina Itajaí', 'Tedesco Marina Garden Plaza', 'Veleiros da Ilha'],
    (select string_agg(l.nome, ', ' order by l.nome) from public.agenda_locais l));
  v_res := pg_temp.ok(v_res, 'B8c um pátio só: a MP é o patio_hbr, em BC, com 3 vagas e deslocamento 0; nenhum "Pátio da HBR" nem pátio em Itajaí (AG7-18)',
    (select count(*) = 1 and bool_and(l.nome = 'MP Motorhomes' and l.municipio = 'Balneário Camboriú' and l.vagas = 3 and l.deslocamento_min = 0)
       from public.agenda_locais l where l.tipo in ('patio_hbr', 'patio_parceiro'))
    and not exists (select 1 from public.agenda_locais l where l.nome ilike 'p_tio%' or (l.tipo like 'patio%' and l.municipio = 'Itajaí')), null);
  v_res := pg_temp.ok(v_res, 'B8d a conferência: Marina Itajaí conferida pelo dono em 16/07/2027; Tedesco só pesquisa; as outras sem conferência',
    (select string_agg(l.nome, ',' order by l.nome) from public.agenda_locais l where public._agenda_local_conferido(l.id, date '2027-07-16')) = 'Marina Itajaí'
    and (select l.exige_autorizacao and l.sabado = 'manha' and l.abre = time '08:00' and l.fecha = time '18:00' and l.tem_garagem_seca
           from public.agenda_locais l where l.nome = 'Marina Itajaí')
    and (select l.conferido_por = 'pesquisa' and l.tem_garagem_seca from public.agenda_locais l where l.nome like 'Tedesco%'), null);
  v_res := pg_temp.ok(v_res, 'B8e as 14 OS de J e as 3 de D, todas na carteira',
    (select count(*) from public.os_carteira(date '2027-07-16') k where k.numero ~ '^OS-J[0-9]+$') = 14
    and (select count(*) from public.os_carteira(date '2026-11-30') k where k.numero ~ '^OS-D[0-9]+$') = 3, null);
  v_res := pg_temp.ok(v_res, 'B8f as aprovações do M11: J11 ontem, J12 há 20 dias, as outras fora da janela de 14 dias',
    (select string_agg(k.numero || '=' || k.aprovada_em, ',' order by k.numero collate "C") from public.os_carteira(date '2027-07-16') k
      where k.numero ~ '^OS-J1[12]$') = 'OS-J11=2027-07-15,OS-J12=2027-06-26'
    and (select bool_and(k.aprovada_em = date '2027-07-01') from public.os_carteira(date '2027-07-16') k
          where k.numero ~ '^OS-J[0-9]+$' and k.numero !~ '^OS-J1[12]$'), null);
  v_res := pg_temp.ok(v_res, 'B8g OS-J2: 2 dias, dupla, Roberto e João ditos, só o Roberto autorizado, garagem seca dita, a linha do "Teste de mar"',
    (select pl.dias = 2 and pl.dupla_dita = 'todos' and pl.bem_situacao = 'garagem_seca' and pl.bem_situacao_fonte = 'dono' and pl.descer_quem = 'a marina'
       from public.os_planejamento pl join public.service_orders so on so.id = pl.service_order_id where so.service_order_number = 'OS-J2')
    and (select array_agg(p.name order by p.name) from public.os_planejamento_equipe e join public.payees p on p.id = e.payee_id
          join public.service_orders so on so.id = e.service_order_id where so.service_order_number = 'OS-J2') = array['João', 'Roberto']
    and (select array_agg(p.name) from public.os_autorizados a join public.payees p on p.id = a.payee_id
          join public.service_orders so on so.id = a.service_order_id where so.service_order_number = 'OS-J2') = array['Roberto']
    and exists (select 1 from public.service_order_services s join public.service_orders so on so.id = s.service_order_id
                 where so.service_order_number = 'OS-J2' and s.name_snapshot = 'Teste de mar'), null);
  v_res := pg_temp.ok(v_res, 'B8h as publicadas de antes da 7d: J1 e J2 em ter 20/07, J12 em seg 26/07, J13 em seg 19/07, D1 em ter 01/12 de manhã',
    (select string_agg(x.n || ' ' || x.d || ' ' || x.c, ', ' order by x.n collate "C", x.d)
       from (select so.service_order_number as n, a.dia as d, count(*) as c from public.agenda_alocacoes a
               join public.service_orders so on so.id = a.service_order_id
              where so.service_order_number ~ '^OS-[JD][0-9]+$' and a.estado = 'publicada' group by 1, 2) x)
    = 'OS-D1 2026-12-01 1, OS-J1 2027-07-20 2, OS-J12 2027-07-26 2, OS-J13 2027-07-19 2, OS-J2 2027-07-20 4',
    (select string_agg(x.n || ' ' || x.d || ' ' || x.c, ', ' order by x.n collate "C", x.d)
       from (select so.service_order_number as n, a.dia as d, count(*) as c from public.agenda_alocacoes a
               join public.service_orders so on so.id = a.service_order_id
              where so.service_order_number ~ '^OS-[JD][0-9]+$' and a.estado = 'publicada' group by 1, 2) x));
  v_res := pg_temp.ok(v_res, 'B8i os lugares da cadeia: J1 na MP pela OS; J3 a J5 e J11 sem marina; J8 e D2 em Penha; D3 em BC; J14 com o local dito pelo dono; J12 sem situação',
    (select so.marina_id = (select m.id from public.marinas m where m.name = 'MP Motorhomes') from public.service_orders so where so.service_order_number = 'OS-J1')
    and (select count(*) from public.service_orders so join public.vessels v on v.id = so.vessel_id
          where so.service_order_number in ('OS-J3', 'OS-J4', 'OS-J5', 'OS-J11') and so.marina_id is null and v.marina_id is null and v.asset_type = 'Motorhome') = 4
    and (select count(*) from public.service_orders so join public.clients c on c.id = so.client_id
          where so.service_order_number in ('OS-J8', 'OS-D2') and c.city = 'Penha' and so.marina_id is null) = 2
    and (select c.city = 'Balneário Camboriú' and so.marina_id is null from public.service_orders so join public.clients c on c.id = so.client_id
          where so.service_order_number = 'OS-D3')
    and (select l.nome like 'Tedesco%' and pl.local_fonte = 'dono' from public.os_planejamento pl join public.agenda_locais l on l.id = pl.local_id
          join public.service_orders so on so.id = pl.service_order_id where so.service_order_number = 'OS-J14')
    and (select pl.bem_situacao is null from public.os_planejamento pl join public.service_orders so on so.id = pl.service_order_id
          where so.service_order_number = 'OS-J12'), null);
  v_res := pg_temp.ok(v_res, 'B8j as datas do cenário: sex 16/07/2027, ter 20/07/2027 e seg 30/11/2026; 20/07 é dia útil da HBR (o feriado é de BC, P2); seg 19/07 é o próximo dia útil',
    extract(isodow from date '2027-07-16') = 5 and extract(isodow from date '2027-07-20') = 2 and extract(isodow from date '2026-11-30') = 1
    and public.agenda_dia_util(date '2027-07-20') and public.agenda_somar_du(date '2027-07-16', 1) = date '2027-07-19', null);
  v_res := pg_temp.ok(v_res, 'B8k a fixture não mexe nos parâmetros: os 6 desligados, a antecedência no padrão (2; o R6.10 tirou o 4), onde_fica_desde nula',
    (select c.modo_local_calendario = 'desligado' and c.modo_local_autorizacao = 'desligado' and c.modo_bem = 'desligado' and c.modo_patio = 'desligado'
            and c.modo_viagem = 'desligado' and c.modo_mesmo_local = 'desligado' and c.autorizacao_antecedencia_du = 2 and c.onde_fica_desde is null
       from public.agenda_config c where c.id), null);

  select count(*) into v_n1 from public.service_orders;
  execute current_setting('agenda_teste.fase7d');
  select count(*) into v_n2 from public.service_orders;
  v_res := pg_temp.ok(v_res, 'B8l carregar 2× = 1×', v_n1 = v_n2, format('%s × %s OS', v_n1, v_n2));

  -- a equipe real não serve: a fixture recusa em vez de quebrar pelo meio
  perform set_config('agenda_teste.fase7b_equipe', 'real', true);
  begin
    execute current_setting('agenda_teste.fase7d');
    v_res := pg_temp.ok(v_res, 'B8m com a equipe real, a fixture recusa com o motivo', false, 'carregou');
  exception when others then
    v_res := pg_temp.ok(v_res, 'B8m com a equipe real, a fixture recusa com o motivo', sqlerrm like 'fixture-fase7d:%', sqlerrm);
  end;
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  perform pg_temp.gravar(v_res);
end
$b8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
