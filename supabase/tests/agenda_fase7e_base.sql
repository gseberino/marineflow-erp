-- Prova da base da Agenda de Produção, Fase 7e (pacote P1): os 6 interruptores e os 32 parâmetros, as colunas do que a medição congela, a tabela das compras, a lista do
-- aprendizado, o modo com o freio e as contas pequenas (migration 20261111100000; spec-fase7e §4, §4.5, §8.1, §8.3 e o bloco R7: R7.3, R7.6, R7.11, R7.12).
-- bancada: depende de 20261111100000
--
-- Na §8.3 da spec os blocos são B1 a B5; aqui B1 + B2 = o B1 dela (colunas e CHECKs), B3 = B2 (RLS e privilégios), B4 = B3 (listas), B5 = B4 (a tabela nova), B6 + B7 = B5 (as contas e, pelo R7.13, a matriz do freio); B8 e B9 são da reconciliação.
--
--   B1  colunas, DEFAULTs e CHECKs de agenda_config: os 6 interruptores (a linha desligada, o DEFAULT sombra), os 32 parâmetros com o valor da spec e o que R7.3 e R7.11 mudam
--       (vies_corrige_dono true, folga_semana_min, aprender_tempo_max); cada CHECK recusa pelo nome o valor logo abaixo e logo acima do limite e aceita os 2 limites;
--       as listas de 12 (o tamanho, a dimensão, o índice, o nulo, o valor); o que cruza colunas
--   B2  os_planejamento e agenda_medidas_os: as 12 colunas de cada, o DEFAULT e os CHECKs
--   B3  RLS e privilégios: agenda_medidas_compra (anon nada, técnico vazia, admin lê); as funções novas sem porta para anon e public; o gatilho sem porta; authenticated chama o
--       modo (o leitor invoker)
--   B4  as listas: agenda_aprendizado.item com as 6 novas depois das 10 de antes; rotina, tipo das perguntas e tipo das ações sem nada novo
--   B5  agenda_medidas_compra: não se apaga direto, só muda inteira, os CHECKs e o que nasce vazio; as exclusões de fora da agenda passam (peça, serviço, item de OC, OS, fornecedor)
--   B6  _agenda_z, _agenda_credibilidade (com o nulo) e _agenda_temporada (mês da quinta, barco só em temporada_meses)
--   B7  a matriz: _agenda_margem_modo e _agenda_margem_modo_cru, item × modo × freio (R7.6); promessa = sombra sempre; prazo_sem_fornecedor = medida; outro nome = nulo;
--       cada item lê o interruptor dele
--   B8  nada muda: só as funções da migration, 2 gatilhos, nada de antes lê as colunas novas nem chama as funções novas; as leituras e as rodadas iguais (md5) nos 6 modos
--       desligados, em sombra e ligados com o freio
--   B9  a fixture: a história da 7e, carregar 2× = 1×
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration e ANTES do dado 20261111100900 (que põe os modos em sombra), com o OK nomeado:
--   npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7e_base.sql
--   Seguro em produção: tudo dentro de subtransações desfeitas e termina em ROLLBACK. O que usa as fixtures e a migration como texto só roda na bancada (fora dela sai
--   PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, do índice único ou da FK; 'aceitou' quando entrou (e desfaz); 'erro <estado>: <mensagem>' para o resto.
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

create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;

create function pg_temp.tec() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'technician' order by created_at limit 1
$f$;

-- os 6 interruptores, de uma vez
create function pg_temp.modos(p_modo text) returns void language plpgsql as $f$
begin
  update public.agenda_config
     set modo_vies = p_modo, modo_folga_semana = p_modo, modo_urgencia = p_modo, modo_promessa = p_modo, modo_tempo_compra = p_modo, modo_folga_compra = p_modo
   where id;
end $f$;

-- ── B1. agenda_config: colunas, DEFAULTs e CHECKs ────────────────────────────────────────────────────
with cfg as (select to_jsonb(c) as j from public.agenda_config c where c.id),
esperado(coluna, valor) as (values
  ('credibilidade_k', '5'), ('vies_n_min', '1'), ('vies_min', '0.50'), ('vies_max', '2.50'),
  ('folga_dispersao_padrao', '0.15'), ('folga_percentil', '0.80'), ('folga_semanas', '12'), ('folga_semanas_min', '8'), ('folga_residuos_min', '6'), ('folga_meios_min', '4'),
  ('folga_semana_max', '0.30'), ('folga_semana_troca_max', '0.05'), ('carga_semana_min', '0.60'), ('carga_semana_max', '0.95'),
  ('urgencia_du', '5'), ('puxar_hora', '17:30:00'), ('puxar_quem', 'ja_vem'), ('puxar_max_os', '1'),
  ('promessa_n_min', '1'), ('promessa_min', '1.00'),
  ('tempo_compra_n_min', '3'), ('tempo_compra_percentil', '0.50'), ('tempo_compra_max_du', '15'),
  ('folga_compra_n_min', '3'), ('folga_compra_percentil', '0.80'), ('folga_compra_max_du', '5'), ('prazo_sem_fornecedor_n_min', '3'))
insert into _resultado
select 'B1a os 27 parâmetros de um valor com o padrão da spec (§4.1)',
       bool_and(cfg.j ->> e.coluna = e.valor) and count(*) = 27,
       string_agg(e.coluna || '=' || coalesce(cfg.j ->> e.coluna, 'nulo'), ', ') filter (where cfg.j ->> e.coluna is distinct from e.valor)
  from cfg, esperado e;

-- Os 3 números novos ou mudados do R7, com DEFAULT da coluna e valor da linha: se voltassem ao que o corpo da spec dizia (false; sem piso; sem relógio), o caso cai.
insert into _resultado
select 'B1b vies_corrige_dono nasce TRUE (AG7-33, R7.3-2), na linha e no DEFAULT; o corpo da spec dizia false',
       c.vies_corrige_dono is true and (select pg_get_expr(d.adbin, d.adrelid) from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
                                         where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'vies_corrige_dono') = 'true',
       format('linha=%s', c.vies_corrige_dono)
  from public.agenda_config c where c.id;
insert into _resultado
select 'B1c folga_semana_min nasce 0,05 (R7.4, R7.11): o piso no lugar de 0', c.folga_semana_min = 0.05, c.folga_semana_min::text
  from public.agenda_config c where c.id;
insert into _resultado
select 'B1d aprender_tempo_max nasce 20 s (R7.8-2, R7.11)', c.aprender_tempo_max = interval '20 seconds', c.aprender_tempo_max::text
  from public.agenda_config c where c.id;
-- Default do os_planejamento (R7.3-2) e da saída do dono: nasce false e NOT NULL.
insert into _resultado
select 'B1e vies_dono_fixo: not null, DEFAULT false (R7.3-2)',
       a.attnotnull and (select pg_get_expr(d.adbin, d.adrelid) = 'false' from pg_attrdef d where d.adrelid = a.attrelid and d.adnum = a.attnum),
       format('notnull=%s', a.attnotnull)
  from pg_attribute a where a.attrelid = 'public.os_planejamento'::regclass and a.attname = 'vies_dono_fixo';

with m(coluna) as (values ('modo_vies'), ('modo_folga_semana'), ('modo_urgencia'), ('modo_promessa'), ('modo_tempo_compra'), ('modo_folga_compra'))
insert into _resultado
select 'B1f os 6 interruptores: a linha desligado, o DEFAULT da coluna sombra (quem põe em sombra é o dado 20261111100900)',
       count(*) = 6 and bool_and(to_jsonb(c) ->> m.coluna = 'desligado')
       and bool_and(pg_get_expr(d.adbin, d.adrelid) = '''sombra''::text'),
       string_agg(m.coluna || '=' || (to_jsonb(c) ->> m.coluna) || '/' || pg_get_expr(d.adbin, d.adrelid), ', ')
  from m
  cross join public.agenda_config c
  join pg_attribute a on a.attrelid = 'public.agenda_config'::regclass and a.attname = m.coluna
  join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where c.id;

insert into _resultado
select 'B1g as listas de 12 nascem com os padrões da §4.1 (AG7-20)',
       c.folga_temporada_barco = '{0.10,0.10,0.05,0,0,0,0,0,0,0,0.05,0.10}'::numeric(3,2)[]
       and c.folga_temporada_rv = '{0,0,0,0,0.05,0.10,0,0,0,0,0.05,0.10}'::numeric(3,2)[],
       format('%s / %s', c.folga_temporada_barco, c.folga_temporada_rv)
  from public.agenda_config c where c.id;

-- Todo CHECK de agenda_config desta migration existe pelo nome (37), e todo CHECK novo tem caso nesta tabela (senão o caso seguinte não o veria).
with n(nome) as (select unnest(array[
  'agenda_config_modo_vies_check', 'agenda_config_modo_folga_semana_check', 'agenda_config_modo_urgencia_check', 'agenda_config_modo_promessa_check',
  'agenda_config_modo_tempo_compra_check', 'agenda_config_modo_folga_compra_check', 'agenda_config_credibilidade_k_check', 'agenda_config_vies_n_min_check',
  'agenda_config_vies_min_check', 'agenda_config_vies_max_check', 'agenda_config_folga_dispersao_padrao_check', 'agenda_config_folga_percentil_check',
  'agenda_config_folga_semanas_check', 'agenda_config_folga_semanas_min_check', 'agenda_config_folga_residuos_min_check', 'agenda_config_folga_meios_min_check',
  'agenda_config_folga_semana_max_check', 'agenda_config_folga_semana_min_check', 'agenda_config_folga_semana_troca_max_check', 'agenda_config_carga_semana_min_check',
  'agenda_config_carga_semana_max_check', 'agenda_config_folga_temporada_barco_check', 'agenda_config_folga_temporada_rv_check', 'agenda_config_urgencia_du_check',
  'agenda_config_puxar_hora_check', 'agenda_config_puxar_quem_check', 'agenda_config_puxar_max_os_check', 'agenda_config_promessa_n_min_check', 'agenda_config_promessa_min_check',
  'agenda_config_tempo_compra_n_min_check', 'agenda_config_tempo_compra_percentil_check', 'agenda_config_tempo_compra_max_du_check', 'agenda_config_folga_compra_n_min_check',
  'agenda_config_folga_compra_percentil_check', 'agenda_config_folga_compra_max_du_check', 'agenda_config_prazo_sem_fornecedor_n_min_check', 'agenda_config_aprender_tempo_max_check']))
insert into _resultado
select 'B1h os 37 CHECKs de agenda_config existem pelo nome',
       count(*) = 37 and bool_and(exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_config'::regclass and k.conname = n.nome)),
       string_agg(n.nome, ',') filter (where not exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_config'::regclass and k.conname = n.nome))
  from n;

-- Cada CHECK de um limite recusa o valor logo abaixo e logo acima (pelo nome: o erro só vale se for ESTE check) e aceita os 2 limites.
create temp table _fx (coluna text, abaixo text, acima text, lim_baixo text, lim_alto text, nome text) on commit drop;
insert into _fx values
  ('credibilidade_k',            '0',                  '31',                  '1',                 '30',                  'agenda_config_credibilidade_k_check'),
  ('vies_n_min',                 '0',                  '21',                  '1',                 '20',                  'agenda_config_vies_n_min_check'),
  ('vies_min',                   '0.29',               '1.01',                '0.30',              '1.00',                'agenda_config_vies_min_check'),
  ('vies_max',                   '0.99',               '3.01',                '1.00',              '3.00',                'agenda_config_vies_max_check'),
  ('folga_dispersao_padrao',     '0.04',               '0.31',                '0.05',              '0.30',                'agenda_config_folga_dispersao_padrao_check'),
  ('folga_percentil',            '0.49',               '0.96',                '0.50',              '0.95',                'agenda_config_folga_percentil_check'),
  ('folga_semanas',              '7',                  '27',                  '8',                 '26',                  'agenda_config_folga_semanas_check'),
  ('folga_semanas_min',          '3',                  '13',                  '4',                 '12',                  'agenda_config_folga_semanas_min_check'),
  ('folga_residuos_min',         '2',                  '21',                  '3',                 '20',                  'agenda_config_folga_residuos_min_check'),
  ('folga_meios_min',            '0',                  '21',                  '1',                 '20',                  'agenda_config_folga_meios_min_check'),
  ('folga_semana_max',           '0.04',               '0.41',                '0.05',              '0.40',                'agenda_config_folga_semana_max_check'),
  ('folga_semana_min',           '-0.01',              '0.21',                '0',                 '0.20',                'agenda_config_folga_semana_min_check'),
  ('folga_semana_troca_max',     '0',                  '0.21',                '0.01',              '0.20',                'agenda_config_folga_semana_troca_max_check'),
  ('carga_semana_min',           '0.49',               '0.91',                '0.50',              '0.90',                'agenda_config_carga_semana_min_check'),
  ('carga_semana_max',           '0.79',               '1.01',                '0.80',              '1.00',                'agenda_config_carga_semana_max_check'),
  ('urgencia_du',                '0',                  '21',                  '1',                 '20',                  'agenda_config_urgencia_du_check'),
  ('puxar_hora',                 $$'11:59'$$,          $$'19:01'$$,           $$'12:00'$$,         $$'19:00'$$,           'agenda_config_puxar_hora_check'),
  ('puxar_max_os',               '0',                  '4',                   '1',                 '3',                   'agenda_config_puxar_max_os_check'),
  ('promessa_n_min',             '0',                  '21',                  '1',                 '20',                  'agenda_config_promessa_n_min_check'),
  ('promessa_min',               '0.99',               '1.51',                '1.00',              '1.50',                'agenda_config_promessa_min_check'),
  ('tempo_compra_n_min',         '1',                  '21',                  '2',                 '20',                  'agenda_config_tempo_compra_n_min_check'),
  ('tempo_compra_percentil',     '0.49',               '0.96',                '0.50',              '0.95',                'agenda_config_tempo_compra_percentil_check'),
  ('tempo_compra_max_du',        '4',                  '41',                  '5',                 '40',                  'agenda_config_tempo_compra_max_du_check'),
  ('folga_compra_n_min',         '1',                  '21',                  '2',                 '20',                  'agenda_config_folga_compra_n_min_check'),
  ('folga_compra_percentil',     '0.49',               '0.96',                '0.50',              '0.95',                'agenda_config_folga_compra_percentil_check'),
  ('folga_compra_max_du',        '0',                  '11',                  '1',                 '10',                  'agenda_config_folga_compra_max_du_check'),
  ('prazo_sem_fornecedor_n_min', '1',                  '21',                  '2',                 '20',                  'agenda_config_prazo_sem_fornecedor_n_min_check'),
  ('aprender_tempo_max',         $$'4 seconds'$$,      $$'26 seconds'$$,      $$'5 seconds'$$,     $$'25 seconds'$$,      'agenda_config_aprender_tempo_max_check');

do $b1$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  r     record;
  m     text;
  n     text;
begin
  select string_agg(format('%s/%s: %s, %s', f.coluna, f.nome,
                           pg_temp.recusa(format('update public.agenda_config set %I = %s where id', f.coluna, f.abaixo)),
                           pg_temp.recusa(format('update public.agenda_config set %I = %s where id', f.coluna, f.acima))), ' | ') into v_dif
    from _fx f
   where pg_temp.recusa(format('update public.agenda_config set %I = %s where id', f.coluna, f.abaixo)) is distinct from f.nome
      or pg_temp.recusa(format('update public.agenda_config set %I = %s where id', f.coluna, f.acima)) is distinct from f.nome;
  v_res := pg_temp.ok(v_res, 'B1i os 28 parâmetros de limite recusam, pelo CHECK deles, o valor logo abaixo e logo acima', v_dif is null, v_dif);
  select string_agg(format('%s: %s / %s', f.coluna,
                           pg_temp.recusa(format('update public.agenda_config set %I = %s where id', f.coluna, f.lim_baixo)),
                           pg_temp.recusa(format('update public.agenda_config set %I = %s where id', f.coluna, f.lim_alto))), ' | ') into v_dif
    from _fx f
   where pg_temp.recusa(format('update public.agenda_config set %I = %s where id', f.coluna, f.lim_baixo)) is distinct from 'aceitou'
      or pg_temp.recusa(format('update public.agenda_config set %I = %s where id', f.coluna, f.lim_alto)) is distinct from 'aceitou';
  v_res := pg_temp.ok(v_res, 'B1j os mesmos 28 aceitam os 2 limites', v_dif is null, v_dif);
  v_dif := null;
  foreach m in array array['modo_vies', 'modo_folga_semana', 'modo_urgencia', 'modo_promessa', 'modo_tempo_compra', 'modo_folga_compra'] loop
    if pg_temp.recusa(format('update public.agenda_config set %I = ''meio'' where id', m)) is distinct from format('agenda_config_%s_check', m) then
      v_dif := coalesce(v_dif || ', ', '') || m;
    end if;
    foreach n in array array['desligado', 'sombra', 'ligado'] loop
      if pg_temp.recusa(format('update public.agenda_config set %I = %L where id', m, n)) is distinct from 'aceitou' then
        v_dif := coalesce(v_dif || ', ', '') || m || '=' || n;
      end if;
    end loop;
  end loop;
  v_res := pg_temp.ok(v_res, 'B1k os 6 interruptores: só desligado, sombra e ligado (cada recusa pelo CHECK dele)', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B1l puxar_quem: só ja_vem e disponivel',
    pg_temp.recusa($$update public.agenda_config set puxar_quem = 'todos' where id$$) = 'agenda_config_puxar_quem_check'
    and pg_temp.recusa($$update public.agenda_config set puxar_quem = 'disponivel' where id$$) = 'aceitou',
    pg_temp.recusa($$update public.agenda_config set puxar_quem = 'todos' where id$$));
  -- o que cruza colunas: mesmo dentro do intervalo de cada uma, a ordem é recusada
  v_res := pg_temp.ok(v_res, 'B1m vies_min < vies_max: os dois em 1,00 é recusado pelo CHECK de vies_min',
    pg_temp.recusa($$update public.agenda_config set vies_min = 1.00, vies_max = 1.00 where id$$) = 'agenda_config_vies_min_check',
    pg_temp.recusa($$update public.agenda_config set vies_min = 1.00, vies_max = 1.00 where id$$));
  v_res := pg_temp.ok(v_res, 'B1n folga_semanas_min não passa de folga_semanas (13 com 12 semanas: recusado)',
    pg_temp.recusa($$update public.agenda_config set folga_semanas_min = 13 where id$$) = 'agenda_config_folga_semanas_min_check',
    pg_temp.recusa($$update public.agenda_config set folga_semanas_min = 13 where id$$));
  v_res := pg_temp.ok(v_res, 'B1o folga_semana_min <= folga_semana_max: 0,20 com 0,10 é recusado pelo CHECK de folga_semana_min',
    pg_temp.recusa($$update public.agenda_config set folga_semana_min = 0.20, folga_semana_max = 0.10 where id$$) = 'agenda_config_folga_semana_min_check',
    pg_temp.recusa($$update public.agenda_config set folga_semana_min = 0.20, folga_semana_max = 0.10 where id$$));
  v_res := pg_temp.ok(v_res, 'B1p carga_semana_min < carga_semana_max: 0,90 com 0,90 é recusado pelo CHECK de carga_semana_min',
    pg_temp.recusa($$update public.agenda_config set carga_semana_min = 0.90, carga_semana_max = 0.90 where id$$) = 'agenda_config_carga_semana_min_check',
    pg_temp.recusa($$update public.agenda_config set carga_semana_min = 0.90, carga_semana_max = 0.90 where id$$));
  perform pg_temp.gravar(v_res);
end
$b1$;

-- As listas de 12 (§4.1, R7.12-2): cada defeito é recusado pelo CHECK da coluna, nas 2 colunas. O nulo e o índice são os que passariam num "0 <= all (…)" e num
-- cardinality = 12 sem o resto do CHECK (a mutação que os tira reprova aqui).
do $b1a$
declare
  c_b   constant text := 'agenda_config_folga_temporada_barco_check';
  c_r   constant text := 'agenda_config_folga_temporada_rv_check';
  v_res jsonb := '[]'::jsonb;
  casos text[][] := array[
    array['11 valores',           $$'{0,0,0,0,0,0,0,0,0,0,0}'$$],
    array['13 valores',           $$'{0,0,0,0,0,0,0,0,0,0,0,0,0}'$$],
    array['2 dimensões',          $$'{{0,0,0,0,0,0},{0,0,0,0,0,0}}'$$],
    array['índice a partir de 0', $$'[0:11]={0,0,0,0,0,0,0,0,0,0,0,0}'$$],
    array['nulo no meio',         $$'{0,0,0,0,0,null,0,0,0,0,0,0}'$$],
    array['negativo',             $$'{-0.01,0,0,0,0,0,0,0,0,0,0,0}'$$],
    array['acima de 0,20',        $$'{0.21,0,0,0,0,0,0,0,0,0,0,0}'$$]];
  v_dif text;
  v_x   text;
begin
  for i in 1 .. array_upper(casos, 1) loop
    v_x := casos[i][2];
    if pg_temp.recusa(format('update public.agenda_config set folga_temporada_barco = %s where id', v_x)) is distinct from c_b then
      v_dif := coalesce(v_dif || ' | ', '') || 'barco ' || casos[i][1] || ': ' || pg_temp.recusa(format('update public.agenda_config set folga_temporada_barco = %s where id', v_x));
    end if;
    if pg_temp.recusa(format('update public.agenda_config set folga_temporada_rv = %s where id', v_x)) is distinct from c_r then
      v_dif := coalesce(v_dif || ' | ', '') || 'rv ' || casos[i][1];
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B1q as listas de 12: 11 e 13 valores, 2 dimensões, índice a partir de 0, nulo, negativo e acima de 0,20 são recusados, nas 2 colunas', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B1r e aceitam 12 valores de 0 a 0,20 (o limite)',
    pg_temp.recusa($$update public.agenda_config set folga_temporada_barco = '{0.20,0.20,0,0,0,0,0,0,0,0,0,0}' where id$$) = 'aceitou'
    and pg_temp.recusa($$update public.agenda_config set folga_temporada_rv = '{0,0,0,0,0,0.20,0,0,0,0,0,0}' where id$$) = 'aceitou', null);
  perform pg_temp.gravar(v_res);
end
$b1a$;

insert into _resultado
select 'B1s a linha cabe na página: abaixo de 8 kB, com folga para a 7g (R7.8)', pg_column_size(c.*) < 8000, pg_column_size(c.*) || ' bytes'
  from public.agenda_config c where c.id;

-- ── B2. os_planejamento e agenda_medidas_os ──────────────────────────────────────────────────────────
with c(tabela, coluna) as (values
  ('os_planejamento', 'estimativa_no_inicio_em'), ('os_planejamento', 'dp_bruto_no_inicio'), ('os_planejamento', 'pessoas_no_inicio'), ('os_planejamento', 'pm_plano_no_inicio'),
  ('os_planejamento', 'inicio_plano_no_inicio'), ('os_planejamento', 'prazo_plano_no_inicio'), ('os_planejamento', 'marcado_em'), ('os_planejamento', 'vies_marcado'),
  ('os_planejamento', 'vies_marcado_chave'), ('os_planejamento', 'tempo_compra_marcado'), ('os_planejamento', 'folga_compra_marcada'), ('os_planejamento', 'vies_dono_fixo'),
  ('agenda_medidas_os', 'pm_reais'), ('agenda_medidas_os', 'pm_estimados'), ('agenda_medidas_os', 'estimativa_origem'), ('agenda_medidas_os', 'razao_estimativa'),
  ('agenda_medidas_os', 'pm_plano_dono'), ('agenda_medidas_os', 'razao_dono'), ('agenda_medidas_os', 'prazo_plano_du'), ('agenda_medidas_os', 'prazo_real_du'),
  ('agenda_medidas_os', 'razao_prazo'), ('agenda_medidas_os', 'vies_marcado'), ('agenda_medidas_os', 'compra_pendente'), ('agenda_medidas_os', 'motivo_razao'))
insert into _resultado
select 'B2a as 12 colunas de os_planejamento e as 12 de agenda_medidas_os',
       count(*) = 24 and count(a.attname) = 24, string_agg(c.tabela || '.' || c.coluna, ',') filter (where a.attname is null)
  from c left join pg_attribute a on a.attrelid = ('public.' || c.tabela)::regclass and a.attname = c.coluna and not a.attisdropped;

insert into _resultado
select 'B2b agenda_medidas_os: pm_reais e compra_pendente NOT NULL com DEFAULT (0 e false) desde o P2 (20261111100100: o P1 as deixou nuláveis porque o agenda_medir_os de então passava NULL explícito; o P2 recria a função gravando as duas em todo caminho e enche as linhas antes do NOT NULL)',
       bool_and(a.attnotnull and coalesce(pg_get_expr(d.adbin, d.adrelid), '') = case a.attname when 'pm_reais' then '0' else 'false' end) and count(*) = 2, string_agg(a.attname || ':' || a.attnotnull || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), 'sem default'), ',')
  from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_medidas_os'::regclass and a.attname in ('pm_reais', 'compra_pendente');

do $b2$
declare
  v_res  jsonb := '[]'::jsonb;
  v_os   uuid;
  v_os2  uuid;
  v_base text;
  v_sem  uuid;
  r      record;
  v_dif  text;
  c_um   constant text := 'estimativa_no_inicio_em = date ''2026-11-11''';
begin
  select so.id into v_os from public.service_orders so order by so.created_at limit 1;
  select so.id into v_os2 from public.service_orders so where so.id <> v_os order by so.created_at limit 1;
  insert into public.os_planejamento (service_order_id) values (v_os) on conflict (service_order_id) do nothing;
  v_base := format('update public.os_planejamento set %%s where service_order_id = %L', v_os);

  for r in select * from (values
    ('estimativa sem o dia',      'dp_bruto_no_inicio = 1',                                'estimativa_no_inicio_coerente'),
    ('pessoas sem o dia',         'pessoas_no_inicio = 1',                                 'estimativa_no_inicio_coerente'),
    ('molde sem o dia',           'pm_plano_no_inicio = 1',                                'estimativa_no_inicio_coerente'),
    ('prazo sem o dia',           'prazo_plano_no_inicio = 1, inicio_plano_no_inicio = date ''2026-11-11''', 'estimativa_no_inicio_coerente'),
    ('viés sem a marcação',       'vies_marcado = 1',                                      'marcado_coerente'),
    ('compra sem a marcação',     'tempo_compra_marcado = 0',                              'marcado_coerente'),
    ('folga sem a marcação',      'folga_compra_marcada = 0',                              'marcado_coerente'),
    ('prazo sem o início',        c_um || ', prazo_plano_no_inicio = 1',                   'prazo_plano_coerente'),
    ('início sem o prazo',        c_um || ', inicio_plano_no_inicio = date ''2026-11-11''', 'prazo_plano_coerente'),
    ('dp bruto 0',                c_um || ', dp_bruto_no_inicio = 0',                      'os_planejamento_dp_bruto_no_inicio_check'),
    ('pessoas 0',                 c_um || ', pessoas_no_inicio = 0',                       'os_planejamento_pessoas_no_inicio_check'),
    ('pessoas 7',                 c_um || ', pessoas_no_inicio = 7',                       'os_planejamento_pessoas_no_inicio_check'),
    ('molde 0',                   c_um || ', pm_plano_no_inicio = 0',                      'os_planejamento_pm_plano_no_inicio_check'),
    ('prazo 0',                   c_um || ', prazo_plano_no_inicio = 0, inicio_plano_no_inicio = date ''2026-11-11''', 'os_planejamento_prazo_plano_no_inicio_check'),
    ('viés 0',                    'marcado_em = date ''2026-11-11'', vies_marcado = 0',    'os_planejamento_vies_marcado_check'),
    ('chave do viés 61',          format('vies_marcado_chave = %L', repeat('x', 61)),      'os_planejamento_vies_marcado_chave_check'),
    ('tempo de compra negativo',  'marcado_em = date ''2026-11-11'', tempo_compra_marcado = -1', 'os_planejamento_tempo_compra_marcado_check'),
    ('folga negativa',            'marcado_em = date ''2026-11-11'', folga_compra_marcada = -1', 'os_planejamento_folga_compra_marcada_check')
  ) as t(nome, seta, cheque) loop
    if pg_temp.recusa(format(v_base, r.seta)) is distinct from r.cheque then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(format(v_base, r.seta));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B2c os_planejamento: as 18 linhas erradas recusadas, cada uma pelo CHECK dela', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B2d os_planejamento: a linha coerente entra (o dia e o resto juntos; a marcação; a chave de 60)',
    pg_temp.recusa(format(v_base, c_um || ', dp_bruto_no_inicio = 2.5, pessoas_no_inicio = 2, pm_plano_no_inicio = 10, inicio_plano_no_inicio = date ''2026-11-11'', prazo_plano_no_inicio = 5')) = 'aceitou'
    and pg_temp.recusa(format(v_base, format('marcado_em = date ''2026-11-11'', vies_marcado = 1, vies_marcado_chave = %L, tempo_compra_marcado = 0, folga_compra_marcada = 0', repeat('x', 60)))) = 'aceitou', null);

  -- agenda_medidas_os: uma OS sem medida; a linha base já é uma medida inválida (a forma de um retrato sem razão)
  select so.id into v_sem from public.service_orders so where not exists (select 1 from public.agenda_medidas_os m where m.service_order_id = so.id) order by so.created_at limit 1;
  v_base := format($q$insert into public.agenda_medidas_os select * from jsonb_populate_record(null::public.agenda_medidas_os, jsonb_build_object(
      'service_order_id', %L, 'classe_bem', 'rv', 'classe_sistema', 'geral', 'concluida_em', date '2026-11-11', 'valida', false, 'motivo', 'sem_inicio', 'meios_cumpridos', 0, 'pm_reais', 0, 'compra_pendente', false,
      'meios_fora_do_plano', 0, 'meios_sem_registro', 0, 'diarias_ligadas', 0, 'so_o_dono', false, 'avisos_enviados', 0, 'versao', 1, 'historico', '[]'::jsonb, 'medida_em', now()) || %%L::jsonb)$q$, v_sem);
  v_res := pg_temp.ok(v_res, 'B2e agenda_medidas_os: a linha base com pm_reais e compra_pendente entra; sem cada um deles (NULL explícito, como o insert (m).*) é recusada pelo NOT NULL do P2',
    pg_temp.recusa(format(v_base, '{}')) = 'aceitou'
    and pg_temp.recusa(format(v_base, '{"pm_reais": null}')) <> 'aceitou' and pg_temp.recusa(format(v_base, '{"compra_pendente": null}')) <> 'aceitou', pg_temp.recusa(format(v_base, '{}')));
  v_res := pg_temp.ok(v_res, 'B2f razao_so_valida: razão com motivo_razao = recusada; sem motivo, aceita',
    pg_temp.recusa(format(v_base, '{"razao_estimativa": 1.1, "motivo_razao": "sem_diaria"}')) = 'razao_so_valida'
    and pg_temp.recusa(format(v_base, '{"razao_estimativa": 1.1}')) = 'aceitou', pg_temp.recusa(format(v_base, '{"razao_estimativa": 1.1, "motivo_razao": "sem_diaria"}')));
  v_res := pg_temp.ok(v_res, 'B2g razao_dono_so_valida: razão do dono com motivo_razao = recusada; sem motivo, aceita',
    pg_temp.recusa(format(v_base, '{"razao_dono": 1.1, "motivo_razao": "sem_trabalho"}')) = 'razao_dono_so_valida'
    and pg_temp.recusa(format(v_base, '{"razao_dono": 1.1}')) = 'aceitou', null);
  v_res := pg_temp.ok(v_res, 'B2h estimativa_origem fora de congelada/recalculada = recusada; as 2 entram',
    pg_temp.recusa(format(v_base, '{"estimativa_origem": "chute"}')) = 'agenda_medidas_os_estimativa_origem_check'
    and pg_temp.recusa(format(v_base, '{"estimativa_origem": "congelada"}')) = 'aceitou'
    and pg_temp.recusa(format(v_base, '{"estimativa_origem": "recalculada"}')) = 'aceitou', null);
  v_dif := null;
  for r in select unnest(array['reaberta', 'sem_inicio', 'sem_fim', 'sem_estimativa', 'conferencia_incompleta', 'sem_diaria', 'sem_trabalho']) as m loop
    if pg_temp.recusa(format(v_base, jsonb_build_object('motivo_razao', r.m))) is distinct from 'aceitou' then v_dif := coalesce(v_dif || ',', '') || r.m; end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B2i motivo_razao: os 7 da §4.2 entram; fora da lista, recusado',
    v_dif is null and pg_temp.recusa(format(v_base, '{"motivo_razao": "qualquer"}')) = 'agenda_medidas_os_motivo_razao_check', v_dif);
  v_res := pg_temp.ok(v_res, 'B2j agenda_medidas_os_razao: o índice só das válidas (motivo_razao nulo), por concluida_em desc',
    exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.indexname = 'agenda_medidas_os_razao'
             and i.indexdef like '%agenda_medidas_os%concluida_em DESC%WHERE (motivo_razao IS NULL)%'), null);
  perform pg_temp.gravar(v_res);
end
$b2$;

-- ── B4 antes do B3: a tabela nova nasce vazia (a linha do B3 e do B5 nasce depois) ───────────────────
insert into _resultado
select 'B5a agenda_medidas_compra nasce vazia: esta migration não grava dado', count(*) = 0, count(*)::text from public.agenda_medidas_compra;
insert into _resultado
select 'B8a os 6 interruptores desligados em toda a migration: nada escreve o dado', c.modo_vies = 'desligado', c.modo_vies from public.agenda_config c where c.id;

-- ── B3. RLS e privilégios ────────────────────────────────────────────────────────────────────────────
do $b3$
declare
  v_res  jsonb := '[]'::jsonb;
  v_lin  uuid;
  v_os   uuid;
  v_adm  uuid := pg_temp.adm();
  v_tec  uuid := pg_temp.tec();
  v_f    text;
  v_dif  text;
  v      text;
  c_todas constant text[] := array['public._agenda_margem_modo(text)', 'public._agenda_margem_modo_cru(text)', 'public._agenda_credibilidade(numeric, integer, numeric, integer)',
                                   'public._agenda_z(numeric)', 'public._agenda_temporada(date)'];
begin
  v_res := pg_temp.ok(v_res, 'B3a agenda_medidas_compra: RLS ligada, 1 política de leitura TO authenticated por is_admin_or_financial',
    (select c.relrowsecurity from pg_class c where c.oid = 'public.agenda_medidas_compra'::regclass)
    and (select count(*) = 1 and bool_and(p.polcmd = 'r' and 'authenticated'::regrole = any (p.polroles)) from pg_policy p where p.polrelid = 'public.agenda_medidas_compra'::regclass)
    and pg_get_expr((select p.polqual from pg_policy p where p.polrelid = 'public.agenda_medidas_compra'::regclass and p.polname = 'agenda_medidas_compra_leitura'),
                    'public.agenda_medidas_compra'::regclass) like '%is_admin_or_financial%', null);
  v_res := pg_temp.ok(v_res, 'B3b privilégios da tabela: anon nada; authenticated só select; service_role tudo',
    not has_table_privilege('anon', 'public.agenda_medidas_compra', 'select')
    and not has_table_privilege('anon', 'public.agenda_medidas_compra', 'insert')
    and has_table_privilege('authenticated', 'public.agenda_medidas_compra', 'select')
    and not has_table_privilege('authenticated', 'public.agenda_medidas_compra', 'insert')
    and not has_table_privilege('authenticated', 'public.agenda_medidas_compra', 'update')
    and not has_table_privilege('authenticated', 'public.agenda_medidas_compra', 'delete')
    and has_table_privilege('service_role', 'public.agenda_medidas_compra', 'select')
    and has_table_privilege('service_role', 'public.agenda_medidas_compra', 'insert')
    and has_table_privilege('service_role', 'public.agenda_medidas_compra', 'update')
    and has_table_privilege('service_role', 'public.agenda_medidas_compra', 'delete'), null);
  -- uma linha para quem lê (na transação; o rollback desfaz). A bancada não tem material nesta altura; em produção há 20 linhas (e nada é gravado de verdade: rollback no fim).
  if (select count(*) from public.os_material) < 2 then
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria)
    select so.id, 'dono', 'Linha de teste do B3', 1 from public.service_orders so order by so.created_at limit 2;
  end if;
  select m.id, m.service_order_id into v_lin, v_os from public.os_material m order by m.id limit 1;
  if v_lin is null then
    v_res := pg_temp.ok(v_res, 'B3c as leituras por papel', true, 'PULADO: sem linha em os_material');
  else
    insert into public.agenda_medidas_compra (os_material_id, service_order_id, sem_fornecedor, entrega, aprovada_em, precisou_em, valida_tempo, valida_prazo, valida_folga, medida_em)
    values (v_lin, v_os, true, 'linha:' || v_lin, date '2026-11-01', date '2026-11-01', false, false, false, now());
    v := pg_temp.como(null, 'anon', 'select count(*)::text from public.agenda_medidas_compra');
    v_res := pg_temp.ok(v_res, 'B3c anon não lê a tabela (42501)', v like 'erro 42501%', v);
    v := pg_temp.como(v_tec, 'authenticated', 'select count(*)::text from public.agenda_medidas_compra');
    v_res := pg_temp.ok(v_res, 'B3d o técnico lê vazio pela política (sem grant de escrita, sem linha pela RLS)', v = '0', v);
    v := pg_temp.como(v_tec, 'authenticated', format('update public.agenda_medidas_compra set motivo = ''sem_compra'' where os_material_id = %L returning 1', v_lin));
    v_res := pg_temp.ok(v_res, 'B3e o técnico não grava (42501): não há grant de escrita', v like 'erro 42501%', v);
    v := pg_temp.como(v_adm, 'authenticated', 'select count(*)::text from public.agenda_medidas_compra');
    v_res := pg_temp.ok(v_res, 'B3f o administrador lê a linha', v = '1', v);
  end if;
  -- as funções novas: nenhuma porta para anon nem para public (ACL com grantee 0); a do gatilho sem porta para ninguém (R7.12: revoke de public e de anon, e prove)
  select string_agg(p, ', ') into v_dif from unnest(c_todas) p
   where has_function_privilege('anon', p, 'execute')
      or exists (select 1 from pg_proc x, aclexplode(x.proacl) a where x.oid = p::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE');
  v_res := pg_temp.ok(v_res, 'B3g as 5 funções novas sem execute para anon nem para public', v_dif is null, v_dif);
  select string_agg(p, ', ') into v_dif from unnest(c_todas) p
   where not has_function_privilege('authenticated', p, 'execute') or not has_function_privilege('service_role', p, 'execute');
  v_res := pg_temp.ok(v_res, 'B3h as 5 funções têm execute para authenticated e service_role (o molde de _agenda_local_modo; os leitores invoker)', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B3i o gatilho _agenda_medidas_compra_so_muda sem execute para ninguém fora do dono',
    not has_function_privilege('anon', 'public._agenda_medidas_compra_so_muda()', 'execute')
    and not has_function_privilege('authenticated', 'public._agenda_medidas_compra_so_muda()', 'execute')
    and not has_function_privilege('service_role', 'public._agenda_medidas_compra_so_muda()', 'execute'), null);
  -- a chamada de verdade do leitor invoker: o papel authenticated (com o login do administrador) chega ao modo; anon não
  v := pg_temp.como(v_adm, 'authenticated', $$select public._agenda_margem_modo('vies')$$);
  v_res := pg_temp.ok(v_res, 'B3j authenticated chama _agenda_margem_modo (a porta do leitor invoker, R7.6: sem ela o caminho ligado daria 42501 em os_prontidao)', v = 'desligado', v);
  v := pg_temp.como(null, 'anon', $$select public._agenda_margem_modo('vies')$$);
  v_res := pg_temp.ok(v_res, 'B3k anon não chama _agenda_margem_modo (42501)', v like 'erro 42501%', v);
  v := pg_temp.como(null, 'anon', $$select public._agenda_margem_modo_cru('vies')$$);
  v_res := pg_temp.ok(v_res, 'B3l anon não chama _agenda_margem_modo_cru (42501)', v like 'erro 42501%', v);
  v := pg_temp.como(null, 'anon', $$select public._agenda_temporada(date '2026-11-16')::text$$);
  v_res := pg_temp.ok(v_res, 'B3m anon não chama _agenda_temporada (42501)', v like 'erro 42501%', v);
  v := pg_temp.como(null, 'anon', $$select public._agenda_z(0.8)::text$$);
  v_res := pg_temp.ok(v_res, 'B3n anon não chama _agenda_z (42501)', v like 'erro 42501%', v);
  v := pg_temp.como(null, 'anon', $$select public._agenda_credibilidade(1.1, 1, 1, 5)::text$$);
  v_res := pg_temp.ok(v_res, 'B3o anon não chama _agenda_credibilidade (42501)', v like 'erro 42501%', v);
  perform pg_temp.gravar(v_res);
end
$b3$;

-- ── B4. As listas ────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B4a agenda_aprendizado.item: as 10 da Fase 6, na ordem, e as 6 da margem no fim',
       pg_temp.lista('public.agenda_aprendizado'::regclass, 'agenda_aprendizado_item_check')
       = '{fator,mo,presenca,fornecedor_atraso,fornecedor_prazo,capacidade_dono,cliente_pontualidade,aviso_folga,carga,solver,vies,promessa,folga_semana,tempo_compra,folga_compra,prazo_sem_fornecedor}'::text[],
       array_to_string(pg_temp.lista('public.agenda_aprendizado'::regclass, 'agenda_aprendizado_item_check'), ',');
insert into _resultado
select 'B4b a rotina não ganha puxar: o puxar é passo do agenda-gestor (R7.6, R7.13)',
       not ('puxar' = any (pg_temp.lista('public.agenda_vigia_rodadas'::regclass, 'agenda_vigia_rodadas_rotina_check'))), null;
insert into _resultado
select 'B4c agenda_acoes.tipo e agenda_perguntas.tipo não têm nada da 7e: aprendizado e criar já existiam nas ações (R7.6)',
       pg_temp.lista('public.agenda_acoes'::regclass, 'agenda_acoes_tipo_check') @> array['aprendizado', 'criar']
       and not (pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check') && array['vies', 'folga_semana', 'tempo_compra', 'promessa']), null;
do $b4$
declare
  v_res jsonb := '[]'::jsonb;
begin
  v_res := pg_temp.ok(v_res, 'B4d agenda_aprendizado aceita item vies; recusa outro nome (o ampliador manteve o CHECK fechado)',
    pg_temp.recusa($$insert into public.agenda_aprendizado (item, chave, nivel, n_min, calculado_em) values ('vies', 'todas', 'todas', 1, now())$$) = 'aceitou'
    and pg_temp.recusa($$insert into public.agenda_aprendizado (item, chave, nivel, n_min, calculado_em) values ('viez', 'todas', 'todas', 1, now())$$) = 'agenda_aprendizado_item_check', null);
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B5. agenda_medidas_compra: não se apaga, só muda inteira, os CHECKs ──────────────────────────────
do $b5$
declare
  v_res  jsonb := '[]'::jsonb;
  v_lin  uuid;
  v_os   uuid;
  v_os2  uuid;
  v_dif  text;
  v_sql  text;
  r      record;
  c_msg_apaga  constant text := 'erro P0001: O registro da agenda não se apaga.';
  c_msg_inteira constant text := 'erro P0001: A medida da compra só muda inteira: versão + 1 e o que mudou no histórico.';
  c_msg_linha  constant text := 'erro P0001: A medida da compra é da linha: a linha e a OS não mudam.';
begin
  select m.id, m.service_order_id into v_lin, v_os from public.agenda_medidas_compra c join public.os_material m on m.id = c.os_material_id limit 1;
  if v_lin is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B5b a tabela', true, 'PULADO: sem linha em os_material'));
    return;
  end if;
  select so.id into v_os2 from public.service_orders so where so.id <> v_os order by so.created_at limit 1;
  v_sql := format('update public.agenda_medidas_compra set %%s where os_material_id = %L', v_lin);
  v_res := pg_temp.ok(v_res, 'B5b não se apaga', pg_temp.recusa(format('delete from public.agenda_medidas_compra where os_material_id = %L', v_lin)) = c_msg_apaga,
    pg_temp.recusa(format('delete from public.agenda_medidas_compra where os_material_id = %L', v_lin)));
  v_res := pg_temp.ok(v_res, 'B5c mudar sem versão + 1 = recusado (versão igual)', pg_temp.recusa(format(v_sql, 'motivo = ''sem_compra''')) = c_msg_inteira, pg_temp.recusa(format(v_sql, 'motivo = ''sem_compra''')));
  v_res := pg_temp.ok(v_res, 'B5d versão + 2 = recusado', pg_temp.recusa(format(v_sql, 'versao = versao + 2, historico = ''[{"em": "x"}]''')) = c_msg_inteira, null);
  v_res := pg_temp.ok(v_res, 'B5e versão + 1 sem histórico novo = recusado', pg_temp.recusa(format(v_sql, 'versao = versao + 1')) = c_msg_inteira, pg_temp.recusa(format(v_sql, 'versao = versao + 1')));
  v_res := pg_temp.ok(v_res, 'B5f versão + 1 com histórico vazio = recusado', pg_temp.recusa(format(v_sql, 'versao = versao + 1, historico = ''[]''')) = c_msg_inteira, null);
  v_res := pg_temp.ok(v_res, 'B5g versão + 1 com histórico novo = entra', pg_temp.recusa(format(v_sql, 'versao = versao + 1, historico = ''[{"em": "x"}]''')) = 'aceitou', pg_temp.recusa(format(v_sql, 'versao = versao + 1, historico = ''[{"em": "x"}]''')));
  -- agora a linha de verdade anda (versão 2, histórico com 1 entrada): daqui, histórico igual e histórico vazio são recusados, cada um pelo seu guarda
  execute format(v_sql, 'versao = versao + 1, historico = ''[{"em": "y"}]''');
  v_res := pg_temp.ok(v_res, 'B5g2 versão + 1 com o MESMO histórico (não vazio) = recusado', pg_temp.recusa(format(v_sql, 'versao = versao + 1, historico = ''[{"em": "y"}]''')) = c_msg_inteira, pg_temp.recusa(format(v_sql, 'versao = versao + 1, historico = ''[{"em": "y"}]''')));
  v_res := pg_temp.ok(v_res, 'B5g3 versão + 1 com histórico VAZIO, partindo de um não vazio = recusado', pg_temp.recusa(format(v_sql, 'versao = versao + 1, historico = ''[]''')) = c_msg_inteira, pg_temp.recusa(format(v_sql, 'versao = versao + 1, historico = ''[]''')));
  v_res := pg_temp.ok(v_res, 'B5h a linha (o material) não muda', pg_temp.recusa(format(v_sql, format('os_material_id = %L, versao = versao + 1, historico = ''[{"em": "x"}]''', gen_random_uuid()))) = c_msg_linha, null);
  v_res := pg_temp.ok(v_res, 'B5i a OS não muda', pg_temp.recusa(format(v_sql, format('service_order_id = %L, versao = versao + 1, historico = ''[{"em": "x"}]''', v_os2))) = c_msg_linha, null);
  -- os CHECKs: pelo insert, numa OS de teste, sem depender da linha de cima
  v_sql := format($q$insert into public.agenda_medidas_compra (os_material_id, service_order_id, sem_fornecedor, entrega, aprovada_em, precisou_em, valida_tempo, valida_prazo, medida_em, %%s)
                     select id, service_order_id, true, 'linha:x', date '2026-11-01', date '2026-11-01', false, false, now(), %%s from public.os_material where id <> %L limit 1$q$, v_lin);
  for r in select * from (values
    ('marcada_em sem primeiro_dia',  'valida_folga, marcada_em', 'false, date ''2026-11-10''', 'compra_marcada_coerente'),
    ('primeiro_dia sem marcada_em',  'valida_folga, primeiro_dia', 'false, date ''2026-11-10''', 'compra_marcada_coerente'),
    ('folga válida sem marcação',    'valida_folga', 'true', 'compra_folga_so_marcada'),
    ('motivo fora da lista',         'valida_folga, motivo', 'false, ''talvez''', 'agenda_medidas_compra_motivo_check'),
    ('fonte da compra fora da lista','valida_folga, comprado_fonte', 'false, ''cartao''', 'agenda_medidas_compra_comprado_fonte_check'),
    ('histórico que não é lista',    'valida_folga, historico', 'false, ''{}''::jsonb', 'agenda_medidas_compra_historico_check'),
    ('histórico de 21',              'valida_folga, historico', 'false, to_jsonb(array(select g from generate_series(1, 21) g))', 'agenda_medidas_compra_historico_check')
  ) as t(nome, col, val, cheque) loop
    if pg_temp.recusa(format(v_sql, r.col, r.val)) is distinct from r.cheque then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(format(v_sql, r.col, r.val));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B5j os 7 casos errados recusados, cada um pelo CHECK dele', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B5k entrega de 61 letras, prazo_fonte de 21: recusados; 60 e 20 entram',
    pg_temp.recusa($$insert into public.agenda_medidas_compra (os_material_id, service_order_id, sem_fornecedor, entrega, aprovada_em, precisou_em, valida_tempo, valida_prazo, valida_folga, medida_em)
                     select id, service_order_id, true, repeat('x', 61), date '2026-11-01', date '2026-11-01', false, false, false, now() from public.os_material limit 1$$) = 'agenda_medidas_compra_entrega_check'
    and pg_temp.recusa(format($q$insert into public.agenda_medidas_compra (os_material_id, service_order_id, sem_fornecedor, entrega, aprovada_em, precisou_em, valida_tempo, valida_prazo, valida_folga, medida_em, prazo_fonte)
                     select id, service_order_id, true, 'linha:x', date '2026-11-01', date '2026-11-01', false, false, false, now(), repeat('y', 21) from public.os_material where id <> %L limit 1$q$, v_lin)) = 'agenda_medidas_compra_prazo_fonte_check'
    and pg_temp.recusa(format($q$insert into public.agenda_medidas_compra (os_material_id, service_order_id, sem_fornecedor, entrega, aprovada_em, precisou_em, valida_tempo, valida_prazo, valida_folga, medida_em, prazo_fonte)
                     select id, service_order_id, true, repeat('x', 60), date '2026-11-01', date '2026-11-01', false, false, false, now(), repeat('y', 20) from public.os_material where id <> %L limit 1$q$, v_lin)) = 'aceitou', null);
  v_res := pg_temp.ok(v_res, 'B5l a FK de os_material (linha que não existe, recusada)',
    pg_temp.recusa($$insert into public.agenda_medidas_compra (os_material_id, service_order_id, sem_fornecedor, entrega, aprovada_em, precisou_em, valida_tempo, valida_prazo, valida_folga, medida_em)
                     select gen_random_uuid(), id, true, 'linha:x', date '2026-11-01', date '2026-11-01', false, false, false, now() from public.service_orders limit 1$$) = 'agenda_medidas_compra_os_material_id_fkey', null);
  v_res := pg_temp.ok(v_res, 'B5m os 2 gatilhos: não apaga (_agenda_registro_nao_apaga) e só muda inteira (BEFORE UPDATE)',
    (select count(*) = 2
            and bool_and(t.tgtype::int & 2 = 2)
            and count(*) filter (where t.tgfoid = 'public._agenda_registro_nao_apaga()'::regprocedure) = 1
            and count(*) filter (where t.tgfoid = 'public._agenda_medidas_compra_so_muda()'::regprocedure) = 1
       from pg_trigger t where t.tgrelid = 'public.agenda_medidas_compra'::regclass and not t.tgisinternal), null);
  perform pg_temp.gravar(v_res);
end
$b5$;

-- O que vem de fora da agenda (desvio da §4.3): a medida nasce com a OS ainda aberta, então tirar peça, serviço ou item de OC, apagar a OS ou o fornecedor não podem ser recusados por ela. Cada linha com a sua origem
-- real; o resultado da exclusão fica nesta transação (não é o recusa, que desfaz). Dentro de um gatilho (_dispara, depth 1 + o da medida, 2) se prova que só a escrita da FK passa, e não qualquer coisa nessa profundidade.
create temp table _dispara (cmd text) on commit drop;
create function pg_temp.dispara_tg() returns trigger language plpgsql as $f$ begin execute new.cmd; return new; end $f$;
create trigger _dispara_tg before insert on _dispara for each row execute function pg_temp.dispara_tg();
-- executa e diz 'ok' (a mudança fica) ou o erro (a subtransação desfaz)
create function pg_temp.faz(p_sql text) returns text language plpgsql as $f$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return 'erro ' || sqlstate || ': ' || sqlerrm;
end $f$;

do $b5c$
declare
  v_res   jsonb := '[]'::jsonb;
  v_cli   uuid;
  v_bem   uuid;
  v_prod  uuid;
  v_os    uuid;
  v_os2   uuid;
  v_part  uuid;
  v_serv  uuid;
  v_oc    uuid;
  v_item  uuid;
  v_forn  uuid;
  v_forn2 uuid;
  v_m_p   uuid;
  v_m_s   uuid;
  v_m_i   uuid;
  v_m_o   uuid;
  v_m_f   uuid;
  v_m_d   uuid;
  v_m_n   uuid;
  v       text;
  v_antes jsonb;
  v_dep   jsonb;
  c_msg   constant text := 'erro P0001: A medida da compra só muda inteira: versão + 1 e o que mudou no histórico.';
begin
  select so.client_id, so.vessel_id into v_cli, v_bem from public.service_orders so where so.vessel_id is not null order by so.created_at limit 1;
  select p.id into v_prod from public.products p order by p.id limit 1;
  if v_cli is null or v_prod is null then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B5n as exclusões de fora da agenda', true, 'PULADO: sem OS ou produto no estado'));
    return;
  end if;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type) values ('OS-B5C-1', v_cli, v_bem, 'open', 'approved', 'repair') returning id into v_os;
  insert into public.service_orders (service_order_number, client_id, vessel_id, status, quote_status, service_type) values ('OS-B5C-2', v_cli, v_bem, 'open', 'approved', 'repair') returning id into v_os2;
  insert into public.service_order_parts (service_order_id, product_id, quantity, unit_cost_snapshot, unit_sale_snapshot, line_total_cost, line_total_sale)
  values (v_os, v_prod, 1, 10, 20, 10, 20) returning id into v_part;
  insert into public.service_order_services (service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot) values (v_os, null, 'Serviço do B5', 'unit', 1, 10) returning id into v_serv;
  insert into public.purchase_orders (po_number, status, service_order_id) values ('OC-B5C', 'draft', v_os) returning id into v_oc;
  insert into public.purchase_order_items (purchase_order_id, description, quantity) values (v_oc, 'Item do B5', 1) returning id into v_item;
  insert into public.suppliers (name) values ('Fornecedor do B5 a') returning id into v_forn;
  insert into public.suppliers (name) values ('Fornecedor do B5 b') returning id into v_forn2;
  -- as 3 de origem real (se um gatilho de antes já criou a linha, é ela) e as de origem dono: a da OS que sai, a do fornecedor, a do nulo direto
  select m.id into v_m_p from public.os_material m where m.service_order_part_id = v_part;
  if v_m_p is null then
    insert into public.os_material (service_order_id, origem, service_order_part_id, descricao, quantidade_necessaria) values (v_os, 'peca', v_part, 'Peça do B5', 1) returning id into v_m_p;
  end if;
  select m.id into v_m_s from public.os_material m where m.service_order_service_id = v_serv;
  if v_m_s is null then
    insert into public.os_material (service_order_id, origem, service_order_service_id, descricao, quantidade_necessaria) values (v_os, 'texto_livre', v_serv, 'Serviço do B5', 1) returning id into v_m_s;
  end if;
  select m.id into v_m_i from public.os_material m where m.purchase_order_item_id = v_item;
  if v_m_i is null then
    insert into public.os_material (service_order_id, origem, purchase_order_item_id, descricao, quantidade_necessaria) values (v_os, 'oc', v_item, 'Item do B5', 1) returning id into v_m_i;
  end if;
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values (v_os2, 'dono', 'Linha da OS que sai', 1) returning id into v_m_o;
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values (v_os, 'dono', 'Linha do fornecedor', 1) returning id into v_m_f;
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values (v_os, 'dono', 'Linha do nulo direto', 1) returning id into v_m_d;
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria) values (v_os, 'dono', 'Linha sem fornecedor', 1) returning id into v_m_n;
  insert into public.agenda_medidas_compra (os_material_id, service_order_id, fornecedor_id, sem_fornecedor, entrega, aprovada_em, precisou_em, valida_tempo, valida_prazo, valida_folga, medida_em)
  select x.id, x.os, x.f, x.f is null, 'linha:b5', date '2026-11-01', date '2026-11-01', false, false, false, now()
    from (values (v_m_p, v_os, null::uuid), (v_m_s, v_os, null), (v_m_i, v_os, null), (v_m_o, v_os2, null), (v_m_f, v_os, v_forn), (v_m_d, v_os, v_forn2), (v_m_n, v_os, null)) as x(id, os, f);

  v := pg_temp.faz(format('delete from public.service_order_parts where id = %L', v_part));
  v_res := pg_temp.ok(v_res, 'B5n tirar a peça da OS: passa, e a linha de material e a medida saem junto (a cascata)', v = 'ok'
    and not exists (select 1 from public.os_material m where m.id = v_m_p) and not exists (select 1 from public.agenda_medidas_compra c where c.os_material_id = v_m_p), v);
  v := pg_temp.faz(format('delete from public.service_order_services where id = %L', v_serv));
  v_res := pg_temp.ok(v_res, 'B5o tirar o serviço da OS: passa, e a medida sai junto', v = 'ok'
    and not exists (select 1 from public.agenda_medidas_compra c where c.os_material_id = v_m_s), v);
  v := pg_temp.faz(format('delete from public.purchase_order_items where id = %L', v_item));
  v_res := pg_temp.ok(v_res, 'B5p tirar o item da OC: passa, e a medida sai junto', v = 'ok'
    and not exists (select 1 from public.agenda_medidas_compra c where c.os_material_id = v_m_i), v);
  v := pg_temp.faz(format('delete from public.service_orders where id = %L', v_os2));
  v_res := pg_temp.ok(v_res, 'B5q apagar a OS: passa, e a medida sai junto', v = 'ok'
    and not exists (select 1 from public.agenda_medidas_compra c where c.os_material_id = v_m_o), v);

  v_antes := (select to_jsonb(c) from public.agenda_medidas_compra c where c.os_material_id = v_m_f);
  v := pg_temp.faz(format('delete from public.suppliers where id = %L', v_forn));
  v_dep := (select to_jsonb(c) from public.agenda_medidas_compra c where c.os_material_id = v_m_f);
  v_res := pg_temp.ok(v_res, 'B5r apagar o fornecedor: passa; fornecedor_id fica nulo, com a mesma versão e o mesmo histórico, e nada mais muda', v = 'ok'
    and v_dep is not null and v_dep ->> 'fornecedor_id' is null and v_antes ->> 'fornecedor_id' is not null
    and (v_dep - 'fornecedor_id') = (v_antes - 'fornecedor_id'), coalesce(v, '') || ' / ' || coalesce(v_dep::text, 'sem linha'));

  -- continua recusado: o apagar direto (a medida que tem linha de material) e o nulo direto
  v := pg_temp.recusa(format('delete from public.agenda_medidas_compra where os_material_id = %L', v_m_d));
  v_res := pg_temp.ok(v_res, 'B5s apagar a medida direto, com a linha de material de pé: recusado', v = 'erro P0001: O registro da agenda não se apaga.', v);
  v := pg_temp.recusa(format('update public.agenda_medidas_compra set fornecedor_id = null where os_material_id = %L', v_m_d));
  v_res := pg_temp.ok(v_res, 'B5t fornecedor_id = null direto: recusado (só a FK passa)', v = c_msg, v);
  -- de dentro de um gatilho (depth 2, a mesma da FK), só o caminho exato passa: cada condição do guarda tem o seu caso
  v := pg_temp.recusa(format('insert into _dispara values (%L)', format('update public.agenda_medidas_compra set fornecedor_id = %L where os_material_id = %L', v_forn2, v_m_n)));
  v_res := pg_temp.ok(v_res, 'B5u dentro de um gatilho, pôr um fornecedor (de nulo a valor): recusado', v = c_msg, v);
  v := pg_temp.recusa(format('insert into _dispara values (%L)', format('update public.agenda_medidas_compra set fornecedor_id = null, motivo = ''sem_compra'' where os_material_id = %L', v_m_d)));
  v_res := pg_temp.ok(v_res, 'B5v dentro de um gatilho, o nulo junto com outra coluna: recusado', v = c_msg, v);
  v := pg_temp.recusa(format('insert into _dispara values (%L)', format('update public.agenda_medidas_compra set fornecedor_id = null where os_material_id = %L', v_m_n)));
  v_res := pg_temp.ok(v_res, 'B5w dentro de um gatilho, fornecedor que já era nulo (sem mudança nenhuma): recusado', v = c_msg, v);
  v := pg_temp.recusa(format('insert into _dispara values (%L)', format('update public.agenda_medidas_compra set fornecedor_id = %L where os_material_id = %L', v_forn, v_m_d)));
  v_res := pg_temp.ok(v_res, 'B5x dentro de um gatilho, trocar por outro fornecedor: recusado', v = c_msg, v);
  perform pg_temp.gravar(v_res);
end
$b5c$;

-- ── B6. As contas pequenas ───────────────────────────────────────────────────────────────────────────
do $b6$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  v     text;
  j     jsonb;
  r     record;
begin
  -- _agenda_z: a tabela da §4.5, ponto a ponto
  for r in select * from (values (0.50, 0), (0.55, 0.1257), (0.60, 0.2533), (0.65, 0.3853), (0.70, 0.5244), (0.75, 0.6745), (0.80, 0.8416), (0.85, 1.0364), (0.90, 1.2816), (0.95, 1.6449)) as t(q, z) loop
    if public._agenda_z(r.q) is distinct from r.z::numeric then
      v_dif := coalesce(v_dif || ', ', '') || r.q || ': ' || coalesce(public._agenda_z(r.q)::text, 'nulo');
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B6a _agenda_z: os 10 pontos da tabela', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B6b _agenda_z interpola em linha reta dentro do degrau: 0,825 → 0,9390; 0,8625 → 1,0977',
    public._agenda_z(0.825) = 0.9390 and round(public._agenda_z(0.8625), 4) = 1.0977,
    format('%s, %s', public._agenda_z(0.825), public._agenda_z(0.8625)));
  v_res := pg_temp.ok(v_res, 'B6c _agenda_z: q abaixo de 0,50 = 22023',
    pg_temp.recusa('select public._agenda_z(0.49)') = 'erro 22023: _agenda_z: o quantil precisa estar entre 0,50 e 0,95 (recebido 0.49).', pg_temp.recusa('select public._agenda_z(0.49)'));
  v_res := pg_temp.ok(v_res, 'B6d _agenda_z: q acima de 0,95 = 22023',
    pg_temp.recusa('select public._agenda_z(0.951)') = 'erro 22023: _agenda_z: o quantil precisa estar entre 0,50 e 0,95 (recebido 0.951).', pg_temp.recusa('select public._agenda_z(0.951)'));
  v_res := pg_temp.ok(v_res, 'B6e _agenda_z: q nulo = 22023', pg_temp.recusa('select public._agenda_z(null)') like 'erro 22023:%', pg_temp.recusa('select public._agenda_z(null)'));
  -- _agenda_credibilidade: a forma de sempre; sem amostra vale a base, sem que o nulo vire nulo (R7.12-2)
  v_res := pg_temp.ok(v_res, 'B6f _agenda_credibilidade: com n = 4, k = 5: (4/9) × 1,25 + (5/9) × 1 = 1,1111… (sem arredondar)',
    round(public._agenda_credibilidade(1.25, 4, 1, 5), 4) = 1.1111, public._agenda_credibilidade(1.25, 4, 1, 5)::text);
  v_res := pg_temp.ok(v_res, 'B6g _agenda_credibilidade: Z sobe com n: n = 1 pesa 1/6 da estatística, n = 5 pesa metade',
    round(public._agenda_credibilidade(2, 1, 1, 5), 4) = 1.1667 and round(public._agenda_credibilidade(2, 5, 1, 5), 4) = 1.5000,
    format('%s, %s', public._agenda_credibilidade(2, 1, 1, 5), public._agenda_credibilidade(2, 5, 1, 5)));
  v_res := pg_temp.ok(v_res, 'B6h _agenda_credibilidade: estatística nula = base (a medida que não existe não puxa)',
    public._agenda_credibilidade(null, 5, 1.5, 5) = 1.5, null);
  v_res := pg_temp.ok(v_res, 'B6i _agenda_credibilidade: n nulo = base (R7.12-2: sem o teste do nulo, viraria nulo)',
    public._agenda_credibilidade(1.25, null, 1.5, 5) = 1.5, coalesce(public._agenda_credibilidade(1.25, null, 1.5, 5)::text, 'nulo'));
  v_res := pg_temp.ok(v_res, 'B6j _agenda_credibilidade: n = 0 e n negativo = base',
    public._agenda_credibilidade(1.25, 0, 1.5, 5) = 1.5 and public._agenda_credibilidade(1.25, -1, 1.5, 5) = 1.5, null);
  -- _agenda_temporada: o mês da quinta-feira da semana ISO; barco só em temporada_meses; o que sai
  j := public._agenda_temporada(date '2027-01-11');
  v_res := pg_temp.ok(v_res, 'B6k janeiro: barco 0,10, rv 0, extra 0,10, por barco, texto "temporada de barco"',
    (j ->> 'mes')::int = 1 and (j ->> 'barco')::numeric = 0.10 and (j ->> 'rv')::numeric = 0 and (j ->> 'extra')::numeric = 0.10 and j ->> 'por' = 'barco' and j ->> 'texto' = 'temporada de barco', j::text);
  j := public._agenda_temporada(date '2027-06-14');
  v_res := pg_temp.ok(v_res, 'B6l junho: rv 0,10, barco 0, por motorhome, texto "temporada de motorhome"',
    (j ->> 'mes')::int = 6 and (j ->> 'barco')::numeric = 0 and (j ->> 'rv')::numeric = 0.10 and (j ->> 'extra')::numeric = 0.10 and j ->> 'por' = 'motorhome' and j ->> 'texto' = 'temporada de motorhome', j::text);
  j := public._agenda_temporada(date '2027-04-12');
  v_res := pg_temp.ok(v_res, 'B6m abril: tudo 0, por e texto nulos', (j ->> 'extra')::numeric = 0 and j ->> 'por' is null and j ->> 'texto' is null and j ? 'por', j::text);
  v_res := pg_temp.ok(v_res, 'B6n a semana de 28/12 é dezembro (a quinta é 31/12): barco e rv 0,10', (public._agenda_temporada(date '2026-12-28') ->> 'mes')::int = 12, public._agenda_temporada(date '2026-12-28')::text);
  v_res := pg_temp.ok(v_res, 'B6o a semana de seg 30/11 é dezembro: o mês é o da quinta 03/12, não o da segunda',
    (public._agenda_temporada(date '2026-11-30') ->> 'mes')::int = 12, public._agenda_temporada(date '2026-11-30')::text);
  v_res := pg_temp.ok(v_res, 'B6p a data dentro da semana dá o mesmo que a segunda (sex 04/12 = semana de seg 30/11)',
    (public._agenda_temporada(date '2026-12-04') ->> 'mes')::int = 12, null);
  v_res := pg_temp.ok(v_res, 'B6p2 domingo 29/11 é da semana de seg 23/11 (a quinta é 26/11, novembro), não de dezembro', (public._agenda_temporada(date '2026-11-29') ->> 'mes')::int = 11, public._agenda_temporada(date '2026-11-29')::text);
  v_res := pg_temp.ok(v_res, 'B6q a semana da virada de ano, seg 28/12/2026: a quinta 31/12 ainda é 2026, dezembro; seg 04/01/2027: janeiro',
    (public._agenda_temporada(date '2027-01-04') ->> 'mes')::int = 1, null);
  j := public._agenda_temporada(date '2027-11-08');
  v_res := pg_temp.ok(v_res, 'B6r novembro, empate 0,05 e 0,05: barco (a regra do empate)',
    j ->> 'por' = 'barco' and j ->> 'texto' = 'temporada de barco' and (j ->> 'barco')::numeric = 0.05 and (j ->> 'rv')::numeric = 0.05, j::text);
  v_res := pg_temp.ok(v_res, 'B6s p_seg nulo = nulo', public._agenda_temporada(null) is null, null);
  -- temporada_meses é a fonte única (R2, AG7-20): mês fora dela com valor na lista de barco = 0; e dentro dela, mudando a lista, muda o resultado (lê a coluna, não um literal)
  update public.agenda_config set temporada_meses = '{1,2,3}', folga_temporada_barco = '{0.15,0,0,0,0,0,0,0,0,0,0.05,0.10}' where id;
  j := public._agenda_temporada(date '2027-11-08');
  v_res := pg_temp.ok(v_res, 'B6t fora de temporada_meses, o barco de novembro vale 0 (fonte única): o valor da lista de 12 não entra; fica o motorhome',
    (j ->> 'barco')::numeric = 0 and (j ->> 'rv')::numeric = 0.05 and j ->> 'por' = 'motorhome', j::text);
  j := public._agenda_temporada(date '2027-01-11');
  v_res := pg_temp.ok(v_res, 'B6u dentro de temporada_meses, lê folga_temporada_barco de verdade (0,15 mudado)', (j ->> 'barco')::numeric = 0.15, j::text);
  update public.agenda_config set temporada_meses = '{11,12,1,2,3}', folga_temporada_barco = '{0.10,0.10,0.05,0,0,0,0,0,0,0,0.05,0.10}' where id;
  perform pg_temp.gravar(v_res);
end
$b6$;

-- ── B7. A matriz freio × modo ────────────────────────────────────────────────────────────────────────
do $b7$
declare
  v_res  jsonb := '[]'::jsonb;
  v_dif  text;
  v_f    boolean;
  v_m    text;
  v_i    text;
  v_col  text;
  v_n    int := 0;
  v_ef   text;
  v_cr   text;
  v_esp  text;
  c_itens constant text[] := array['vies', 'folga_semana', 'urgencia', 'tempo_compra', 'folga_compra'];
begin
  -- os 5 itens que obedecem ao freio: item × 3 modos × freio, efetivo e cru
  foreach v_i in array c_itens loop
    v_col := case v_i when 'vies' then 'modo_vies' when 'folga_semana' then 'modo_folga_semana' when 'urgencia' then 'modo_urgencia' when 'tempo_compra' then 'modo_tempo_compra' when 'folga_compra' then 'modo_folga_compra' end;
    foreach v_f in array array[false, true] loop
      foreach v_m in array array['desligado', 'sombra', 'ligado'] loop
        execute format('update public.agenda_config set %I = %L, gestor_so_propor = %L where id', v_col, v_m, v_f);
        v_ef := public._agenda_margem_modo(v_i);
        v_cr := public._agenda_margem_modo_cru(v_i);
        v_esp := case when v_m = 'ligado' and v_f then 'sombra' else v_m end;
        v_n := v_n + 1;
        if v_ef is distinct from v_esp or v_cr is distinct from v_m then
          v_dif := coalesce(v_dif || ' | ', '') || format('%s %s freio=%s: efetivo %s (esperava %s), cru %s', v_i, v_m, v_f, v_ef, v_esp, v_cr);
        end if;
      end loop;
    end loop;
    execute format('update public.agenda_config set %I = ''desligado'', gestor_so_propor = false where id', v_col);
  end loop;
  v_res := pg_temp.ok(v_res, format('B7a os 30 casos: ligado + freio = sombra no modo efetivo (só nele); o cru nunca vê o freio; desligado continua desligado (%s casos)', v_n), v_dif is null and v_n = 30, v_dif);

  -- promessa = sombra sempre no efetivo (AG7-32, R7.6); no cru, o que está na linha
  v_dif := null;
  foreach v_f in array array[false, true] loop
    foreach v_m in array array['desligado', 'sombra', 'ligado'] loop
      update public.agenda_config set modo_promessa = v_m, gestor_so_propor = v_f where id;
      if public._agenda_margem_modo('promessa') is distinct from 'sombra' or public._agenda_margem_modo_cru('promessa') is distinct from v_m then
        v_dif := coalesce(v_dif || ' | ', '') || format('%s freio=%s: efetivo %s, cru %s', v_m, v_f, public._agenda_margem_modo('promessa'), public._agenda_margem_modo_cru('promessa'));
      end if;
    end loop;
  end loop;
  update public.agenda_config set modo_promessa = 'desligado', gestor_so_propor = false where id;
  v_res := pg_temp.ok(v_res, 'B7b promessa: efetivo = sombra nas 6 combinações, mesmo ligado e sem freio (AG7-32, R7.6); cru = a linha', v_dif is null, v_dif);

  -- prazo_sem_fornecedor: só medida; os 2 devolvem 'medida', com e sem freio
  v_dif := null;
  foreach v_f in array array[false, true] loop
    update public.agenda_config set gestor_so_propor = v_f where id;
    if public._agenda_margem_modo('prazo_sem_fornecedor') is distinct from 'medida' or public._agenda_margem_modo_cru('prazo_sem_fornecedor') is distinct from 'medida' then
      v_dif := coalesce(v_dif || ', ', '') || v_f::text;
    end if;
  end loop;
  update public.agenda_config set gestor_so_propor = false where id;
  v_res := pg_temp.ok(v_res, 'B7c prazo_sem_fornecedor = medida nos 2, com e sem freio', v_dif is null, v_dif);

  -- outro nome e nulo = nulo (§4.5: "os outros → null")
  v_res := pg_temp.ok(v_res, 'B7d item que não é da margem = nulo; nome nulo = nulo',
    public._agenda_margem_modo('fator') is null and public._agenda_margem_modo_cru('fator') is null
    and public._agenda_margem_modo('modo_vies') is null and public._agenda_margem_modo_cru(null) is null and public._agenda_margem_modo(null) is null, null);

  -- cada item lê o interruptor dele: com todos desligados, só o de vies ligado aparece como ligado
  perform pg_temp.modos('desligado');
  update public.agenda_config set modo_vies = 'ligado', gestor_so_propor = false where id;
  v_res := pg_temp.ok(v_res, 'B7e cada item lê o interruptor dele: só vies ligado; os outros desligados',
    public._agenda_margem_modo('vies') = 'ligado'
    and public._agenda_margem_modo('folga_semana') = 'desligado' and public._agenda_margem_modo('urgencia') = 'desligado'
    and public._agenda_margem_modo('tempo_compra') = 'desligado' and public._agenda_margem_modo('folga_compra') = 'desligado', null);
  update public.agenda_config set modo_vies = 'desligado', modo_folga_semana = 'ligado' where id;
  v_res := pg_temp.ok(v_res, 'B7f folga_semana lê o dele (e vies não)',
    public._agenda_margem_modo('folga_semana') = 'ligado' and public._agenda_margem_modo('vies') = 'desligado', null);
  update public.agenda_config set modo_folga_semana = 'desligado', modo_urgencia = 'ligado' where id;
  v_res := pg_temp.ok(v_res, 'B7g urgencia lê o dele', public._agenda_margem_modo('urgencia') = 'ligado' and public._agenda_margem_modo('folga_semana') = 'desligado', null);
  update public.agenda_config set modo_urgencia = 'desligado', modo_tempo_compra = 'ligado' where id;
  v_res := pg_temp.ok(v_res, 'B7h tempo_compra lê o dele', public._agenda_margem_modo('tempo_compra') = 'ligado' and public._agenda_margem_modo('urgencia') = 'desligado', null);
  update public.agenda_config set modo_tempo_compra = 'desligado', modo_folga_compra = 'ligado' where id;
  v_res := pg_temp.ok(v_res, 'B7i folga_compra lê o dele', public._agenda_margem_modo('folga_compra') = 'ligado' and public._agenda_margem_modo('tempo_compra') = 'desligado', null);
  perform pg_temp.modos('desligado');
  perform pg_temp.gravar(v_res);
end
$b7$;

-- ── B8. Nada muda de comportamento ───────────────────────────────────────────────────────────────────
do $b8$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  c_novas constant text[] := array['_agenda_gestor_puxar', '_agenda_aprender_tempo_compra', '_agenda_aprender_folga_compra', '_agenda_aprender_prazo_sem_fornecedor', '_agenda_margem_modo', '_agenda_margem_modo_cru', '_agenda_credibilidade', '_agenda_z', '_agenda_temporada', '_agenda_medidas_compra_so_muda', '_agenda_dias_com_vies', '_agenda_vies_dono_da_os', '_agenda_aprender_vies',
    -- as novas do P2 (20261111100100), sem marca porque são inteiras da 7e
    '_agenda_margem_tipo_os', '_agenda_margem_dp_bruto', '_agenda_margem_dono_e_pessoa', '_agenda_material_critico', '_agenda_margem_em_uso', '_agenda_vies_da_os', '_agenda_tempo_interno_compra',
    '_agenda_aprender_congelar_marcacao', 'agenda_medir_compra', '_agenda_aprender_medir_compras',
    -- as novas do P4 (20261111100300), sem marca porque são inteiras da 7e
    '_agenda_aprender_folga_semana', '_agenda_carga_da_semana', '_agenda_os_urgente',
    -- as novas do P5 (20261111100400)
    '_agenda_aprender_promessa', 'agenda_promessa_da_os',
    -- a nova do P7 (20261111100600): a saúde da margem, inteira da 7e
    '_agenda_saude_margem',
    -- a 7g (P2, 20261112100100): as suposições da OS leem tempo_compra_marcado (o compra_interna_padrao, R9.5-3), sem a marca porque são inteiras da 7g
    '_agenda_suposicoes_da_os'];
begin
  -- nenhuma função de antes lê as colunas nem chama as funções novas. Quem vier depois nesta etapa: a função recriada leva a marca -- FASE 7e (sai daqui sozinha); a função NOVA, sem marca, entra em c_novas, pelo nome.
  select string_agg(p.proname, ',' order by p.proname) into v_dif
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname <> all (c_novas)
     and p.prosrc ~ '_agenda_(margem_modo|margem_modo_cru|credibilidade|z|temporada|medidas_compra_so_muda)\(|modo_vies|modo_folga_semana|modo_urgencia|modo_promessa|modo_tempo_compra|modo_folga_compra|credibilidade_k|vies_n_min|vies_min|vies_max|vies_corrige_dono|folga_dispersao_padrao|folga_percentil|folga_semanas|folga_residuos_min|folga_meios_min|folga_semana_|carga_semana_|folga_temporada_|urgencia_du|puxar_hora|puxar_quem|puxar_max_os|promessa_n_min|promessa_min|tempo_compra_|folga_compra_|prazo_sem_fornecedor_n_min|aprender_tempo_max|vies_marcado|vies_dono_fixo|estimativa_no_inicio_em|dp_bruto_no_inicio|pessoas_no_inicio|pm_plano_no_inicio|inicio_plano_no_inicio|prazo_plano_no_inicio|marcado_em|tempo_compra_marcado|folga_compra_marcada|pm_reais|pm_estimados|estimativa_origem|razao_estimativa|pm_plano_dono|razao_dono|razao_prazo|motivo_razao|agenda_medidas_compra'
     and not (p.prosrc ~ '-- FASE 7e:|-- \(7e');
  v_res := pg_temp.ok(v_res, 'B8b nenhuma função de antes lê as colunas nem chama as funções novas (fora as marcadas -- FASE 7e, que são dos pacotes seguintes)', v_dif is null, v_dif);
  -- a migration só cria as 6 novas: nenhuma "create or replace function" de um nome de antes (R7.1: o P1 não recria nada; quem recria é do P2 em diante)
  if coalesce(current_setting('agenda_teste.mig_base_fase7e', true), '') = '' then
    v_res := pg_temp.ok(v_res, 'B8c as funções da migration', true, 'PULADO: sem agenda_teste.mig_base_fase7e (rode pela bancada)');
  else
    select string_agg(distinct m[1], ',' order by m[1]) into v_dif
      from regexp_matches(current_setting('agenda_teste.mig_base_fase7e'), 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
    v_res := pg_temp.ok(v_res, 'B8c a migration só cria as 6 funções novas: nada do motor, da medição nem da saúde é recriado (R7.1)',
      v_dif = '_agenda_credibilidade,_agenda_margem_modo,_agenda_margem_modo_cru,_agenda_medidas_compra_so_muda,_agenda_temporada,_agenda_z', v_dif);
  end if;
  perform pg_temp.gravar(v_res);
end
$b8$;

do $b8b$
declare
  v_res  jsonb := '[]'::jsonb;
  v_dif  text;
  v_ref  jsonb;
  v      text;
  v_n    int := 0;
  f      boolean;
  r      record;
  c_hoje constant date := date '2026-10-29';
  c_agor constant timestamptz := timestamptz '2026-10-29 16:52-03';
begin
  -- Sobre o replay de 29/10 que o rodar.mjs já carregou (a equipe e a carteira reais da fixture): as leituras do que sai ao dono. Com os 6 modos desligados (a régua), em sombra, e
  -- ligados com o freio (o caso de produção) o que sai é igual: nada lê os modos. Só na bancada.
  if coalesce(current_setting('agenda_teste.fase7e', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B8d as leituras', true, 'PULADO: sem fixture (rode pela bancada)'));
    return;
  end if;
  create temp table _leitura (nome text, sql text) on commit drop;
  insert into _leitura values
    ('agenda_textos_do_fechamento', format('select public.agenda_textos_do_fechamento(%L::date)::text', c_hoje)),
    ('_agenda_linhas_do_fechamento', format('select public._agenda_linhas_do_fechamento(%L::date)::text', c_hoje)),
    ('agenda_decisoes_abertas', format('select public.agenda_decisoes_abertas(%L::timestamptz)::text', c_agor)),
    ('_agenda_ver_decisoes', format('select public._agenda_ver_decisoes(%L::date, %L::timestamptz)::text', c_hoje, c_agor)),
    ('agenda_aprontar', format('select public.agenda_aprontar(%L::date)::text', c_hoje)),
    ('agenda_aviso_pecas', format('select public.agenda_aviso_pecas(%L::date, %L::timestamptz)::text', c_hoje, c_agor)),
    ('agenda_saude', format('select public.agenda_saude(%L::date, %L::timestamptz)::text', c_hoje, c_agor));
  foreach f in array array[false, true] loop
    update public.agenda_config set gestor_so_propor = f where id;
    perform pg_temp.modos('desligado');
    v_ref := '{}';
    for r in select * from _leitura loop
      execute r.sql into v;
      v_ref := v_ref || jsonb_build_object(r.nome, md5(v));
    end loop;
    perform pg_temp.modos('sombra');
    for r in select * from _leitura loop
      execute r.sql into v;
      v_n := v_n + 1;
      if md5(v) is distinct from v_ref ->> r.nome then
        v_dif := coalesce(v_dif || ', ', '') || format('%s (sombra, freio %s)', r.nome, f);
      end if;
    end loop;
    if f then
      update public.agenda_config
         set modo_vies = 'ligado', modo_folga_semana = 'ligado', modo_urgencia = 'ligado', modo_tempo_compra = 'ligado', modo_folga_compra = 'ligado'
       where id;
      for r in select * from _leitura loop
        execute r.sql into v;
        v_n := v_n + 1;
        if md5(v) is distinct from v_ref ->> r.nome then
          v_dif := coalesce(v_dif || ', ', '') || format('%s (ligado com o freio)', r.nome);
        end if;
      end loop;
    end if;
  end loop;
  perform pg_temp.modos('desligado');
  update public.agenda_config set gestor_so_propor = false where id;
  perform pg_temp.gravar(pg_temp.ok('[]', format('B8d as leituras do que sai ao dono dão o mesmo md5 de desligado, em sombra e ligadas com o freio (%s leituras): nada lê os 6 modos', v_n), v_dif is null, v_dif));
end
$b8b$;

-- ── B9. A fixture da 7e ──────────────────────────────────────────────────────────────────────────────
do $b9$
declare
  v_res jsonb := '[]'::jsonb;
  v_n   int;
begin
  if coalesce(current_setting('agenda_teste.fase7e', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B9a a fixture', true, 'PULADO: sem agenda_teste.fase7e (rode pela bancada)'));
    return;
  end if;
  execute current_setting('agenda_teste.fase7e');
  v_n := (select count(*) from public.service_orders);
  v_res := pg_temp.ok(v_res, 'B9a a OS-E0 e as suas 6 linhas de material (as 3 do P1 + as 3 do P2: a nota, o histórico, o balcão)', (select count(*) = 6 from public.os_material m where m.service_order_id = 'e7e00000-0000-4000-8000-000000000e00'), null);
  v_res := pg_temp.ok(v_res, 'B9b a forma real (R7.12-8): fonte nula e critico true nas 3 (R7.5-4, R7.5-5)',
    (select bool_and(m.fonte is null and m.critico) from public.os_material m where m.id = any (array[md5('e7e:material:m1')::uuid, md5('e7e:material:m2')::uuid, md5('e7e:material:m3')::uuid])), null);
  v_res := pg_temp.ok(v_res, 'B9c a forma real do histórico (R7.5-3): a chave é para, não depois, e tem as 7 chaves de produção',
    (select (m.historico -> 0) ?& array['em', 'de', 'para', 'por', 'autor', 'trecho', 'nota'] and not (m.historico -> 0) ? 'depois' and m.historico -> 0 ->> 'para' = 'comprado'
       from public.os_material m where m.id = md5('e7e:material:m1')::uuid), null);
  v_res := pg_temp.ok(v_res, 'B9d a forma real do compre_ate_base (R7.5-6): as 6 chaves do P10',
    (select m.compre_ate_base ?& array['primeiro', 'folga', 'prazo', 'corridos', 'prazo_fonte', 'interno'] from public.os_material m where m.id = md5('e7e:material:m3')::uuid), null);
  v_res := pg_temp.ok(v_res, 'B9e o "miúdo" não existe na coluna: parafusos é critico true (só a função do P2 calcula)',
    (select m.critico from public.os_material m where m.id = md5('e7e:material:m2')::uuid), null);
  execute current_setting('agenda_teste.fase7e');
  v_res := pg_temp.ok(v_res, 'B9f carregar a fixture 2× = 1×', (select count(*) from public.service_orders) = v_n and (select count(*) from public.os_material m where m.service_order_id = 'e7e00000-0000-4000-8000-000000000e00') = 6, null);
  perform pg_temp.gravar(v_res);
end
$b9$;

-- agenda_medir_os grava todas as colunas (R7.5-1, P2): a 1ª chamada entra pelo insert (m).* com as 2 preenchidas (o NOT NULL do P2) e, numa 2ª rodada, nada muda.
do $b8e$
declare
  v_res jsonb := '[]'::jsonb;
  v_os  uuid;
  v1    jsonb;
  v2    jsonb;
begin
  -- uma OS concluída qualquer (na transação; o rollback desfaz): na bancada as fixtures não deixam nenhuma concluída, então ela nasce aqui
  perform set_config('agenda.porta', 'on', true);
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at,
                                     check_in_at, check_out_at, delivered_at, grand_total)
  select gen_random_uuid(), 'OS-E99', so.client_id, so.vessel_id, 'completed', 'approved', 'repair', t, t, t, t, t, t, 0
    from public.service_orders so, (select timestamptz '2026-11-05 17:00-03' as t) x
   where so.status <> 'draft' order by so.created_at limit 1
  returning id into v_os;
  perform set_config('agenda.porta', 'off', true);
  v1 := public.agenda_medir_os(v_os, date '2026-11-09');
  v2 := public.agenda_medir_os(v_os, date '2026-11-09');
  v_res := pg_temp.ok(v_res, 'B8e agenda_medir_os (a recriada pelo P2) grava a linha sem erro e na 2ª rodada não muda nada: pm_reais e compra_pendente entram no insert (m).* e o to_jsonb(m) = to_jsonb(m0)',
    v1 ->> 'ok' = 'true' and v2 ->> 'mudou' = 'false' and v2 ->> 'versao' = v1 ->> 'versao', format('%s / %s', v1, v2));
  perform pg_temp.gravar(v_res);
end
$b8e$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
