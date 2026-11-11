-- Prova da base da Agenda de Produção, Fase 7g (pacote P1): os 4 interruptores e os 18 parâmetros, o lugar do porquê na alocação e na ação, as 3 tabelas, as 2
-- listas, e as peças do porquê (quem marcou, o degrau, a zona mais severa, o CHECK das suposições e os textos) (migration 20261112100000; spec-fase7g §4, §5.1,
-- §6.1, §8.1, §8.3 agenda_fase7g_base.sql e o bloco R9: R9.3-1, R9.4-1, R9.4-2, R9.5-5, R9.5-8, R9.12-12, R9.13).
-- bancada: depende de 20261112100000
--
-- Na §8.3 da spec os blocos são B1 a B6; aqui B1 + B2 = o B1 dela (colunas, DEFAULTs e CHECKs), B3 = B2 (RLS e privilégios), B4 = B3 (as listas), B5 = B4 (as tabelas
-- não apagam e só mudam o permitido), B6 = B5 + B6 (o degrau, quem marcou) e os textos; B7 e B8 são da reconciliação (a forma real e "nada muda").
--
--   B1  agenda_config: os 4 interruptores (a linha desligado, o DEFAULT sombra), os 15 parâmetros com o valor da spec e os 3 do R9 (marcacoes_desde nula,
--       placar_min_linhas 3, explicar_tempo_max 15 s); cada CHECK recusa pelo nome o valor logo abaixo e logo acima do limite e aceita os 2 limites; origens_do_dono
--       (vazia, com nulo, fora da lista de agenda_acoes.origem); o que cruza colunas (a amostra e o mínimo; a hora e a mensagem da quinta); o peso da linha
--   B2  agenda_alocacoes.suposicoes (nula, sem DEFAULT: R9.4-1) e degrau; agenda_acoes.zona e degrau; os 4 CHECKs; tudo nulo nas linhas que existem; a zona da ação
--       não muda depois do INSERT
--   B3  RLS e privilégios das 3 tabelas (anon nada, técnico vazio, admin lê, ninguém grava fora do service_role); as 8 funções sem porta para anon, public nem
--       authenticated, com porta para service_role (§5.1, §3.1-13; o CHECK roda como quem escreve, e authenticated não grava as 2 tabelas); nenhuma função sem definer
--       com porta para authenticated as chama (com controle); os 3 gatilhos sem porta; as 11: search_path fixo, nenhuma definer, a volatilidade
--   B4  as listas: motivo com ferramenta no fim (AG7-27), rotina com explicar no fim; nada do P5b (nivel, ok_marcacao, ok_do_dono, espera_ok_desde); capacidade_motivos
--       sem ferramenta
--   B5  as 3 tabelas: os CHECKs, não se apagam direto, só mudam o permitido; a marcação sai em cascata com a OS (R9.12-12); o SET NULL da ação no tipo de OS passa; a
--       forma coluna a coluna (tipo, NOT NULL, DEFAULT), as chaves (PK e o ON DELETE de cada FK) e os 2 índices
--   B6  _agenda_degrau (os 8 casos da §8.3 e as combinações), _agenda_quem_marcou, _agenda_zona_mais_severa, _agenda_suposicoes_validas e os 4 textos (§6.1)
--   B7  a fixture: a forma real da ação e das alocações (R9.12-8), as peças sobre ela, carregar 2× = 1×
--   B8  nada muda: só as funções da migration, nada de antes lê as colunas novas nem chama as funções novas, as leituras iguais (md5) nos 4 modos com e sem o freio
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration e ANTES do dado 20261112100990 (que põe os modos em sombra), com o OK nomeado:
--   npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7g_base.sql
--   Seguro em produção: tudo dentro de subtransações desfeitas e termina em ROLLBACK. O que usa a fixture, a migration como texto ou desliga um gatilho (o SET NULL
--   da ação) só roda na bancada (fora dela sai PULADO).
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

-- os 4 interruptores, de uma vez
create function pg_temp.modos(p_modo text) returns void language plpgsql as $f$
begin
  update public.agenda_config set modo_porque = p_modo, modo_explicar = p_modo, modo_placar = p_modo, modo_rebaixar = p_modo where id;
end $f$;

-- uma alocação de teste (cancelada, num dia longe: não choca com ninguém e não vigora), com as colunas a mais: o que recusa é o CHECK da coluna
create function pg_temp.aloc(p_cols text, p_vals text) returns text language sql as $f$
  select format($q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, cancelada_em%s)
                   select so.id, p.id, date '2031-01-07', 'manha', 'turno', 'execucao', 'cancelada', 'motor', now()%s
                     from public.service_orders so, public.payees p
                    where p.active and p.kind <> 'socio' order by so.created_at, p.created_at limit 1$q$,
                coalesce(', ' || p_cols, ''), coalesce(', ' || p_vals, ''))
$f$;

-- uma ação de teste (em sombra: não executada, nada a desfazer), com as colunas a mais
create function pg_temp.acao(p_cols text, p_vals text) returns text language sql as $f$
  select format($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto%s) values (date '2031-01-07', false, 'vigia', 'mover', 'Ação de teste do B2'%s)$q$,
                coalesce(', ' || p_cols, ''), coalesce(', ' || p_vals, ''))
$f$;

-- ── B8a antes de tudo: o que a migration deixa (as tabelas vazias, os modos desligados; o B3 e o B5 escrevem depois, na transação) ──
insert into _resultado
select 'B8a as 3 tabelas nascem vazias e os 4 interruptores desligados, marcacoes_desde nula: a migration não grava dado',
       (select count(*) from public.agenda_marcacoes) = 0 and (select count(*) from public.agenda_tipos_os) = 0 and (select count(*) from public.agenda_placar_semanas) = 0
       and (select c.modo_porque = 'desligado' and c.modo_explicar = 'desligado' and c.modo_placar = 'desligado' and c.modo_rebaixar = 'desligado' and c.marcacoes_desde is null
              from public.agenda_config c where c.id), null;

-- ── B1. agenda_config: colunas, DEFAULTs e CHECKs ────────────────────────────────────────────────────
with cfg as (select to_jsonb(c) as j from public.agenda_config c where c.id),
esperado(coluna, valor) as (values
  ('porque_motivos_max', '1'), ('livre_semanas', '4'), ('como_pensei_perguntas', '3'), ('como_pensei_itens_max', '5'), ('correcao_janela_du', '10'),
  ('rebaixar_janela_semanas', '8'), ('rebaixar_n_min', '3'), ('rebaixar_taxa', '0.50'), ('rebaixar_amostra', '6'), ('voltar_n', '3'), ('rebaixar_trava_dias', '28'),
  ('explicar_hora', '16:35:00'), ('placar_janela', 'semana_passada'), ('placar_semanas_hist', '8'), ('placar_min_linhas', '3'))
insert into _resultado
select 'B1a os 15 parâmetros de um valor com o padrão da spec (§4.1; placar_min_linhas 3 do R9.4-3; AG7-25, AG7-26, AG7-28)',
       bool_and(cfg.j ->> e.coluna = e.valor) and count(*) = 15,
       string_agg(e.coluna || '=' || coalesce(cfg.j ->> e.coluna, 'nulo'), ', ') filter (where cfg.j ->> e.coluna is distinct from e.valor)
  from cfg, esperado e;

insert into _resultado
select 'B1b origens_do_dono nasce {dono,assistente,tela} (§4.1)', c.origens_do_dono = '{dono,assistente,tela}'::text[], c.origens_do_dono::text
  from public.agenda_config c where c.id;
-- R9.4-2: nula e sem DEFAULT. Com um DEFAULT (now()), a linha nasceria com a hora da migration e a medida começaria antes do dado; a medida sem o "desde" olharia para trás.
insert into _resultado
select 'B1c marcacoes_desde: nula na linha, nulável e sem DEFAULT (quem grava é o dado 20261112100990; R9.4-2)',
       c.marcacoes_desde is null and not a.attnotnull and not a.atthasdef and format_type(a.atttypid, a.atttypmod) = 'timestamp with time zone',
       format('linha=%s notnull=%s default=%s tipo=%s', c.marcacoes_desde, a.attnotnull, a.atthasdef, format_type(a.atttypid, a.atttypmod))
  from public.agenda_config c, pg_attribute a
 where c.id and a.attrelid = 'public.agenda_config'::regclass and a.attname = 'marcacoes_desde';
insert into _resultado
select 'B1d explicar_tempo_max nasce 15 s (R9.5-8)', c.explicar_tempo_max = interval '15 seconds', c.explicar_tempo_max::text
  from public.agenda_config c where c.id;

with m(coluna) as (values ('modo_porque'), ('modo_explicar'), ('modo_placar'), ('modo_rebaixar'))
insert into _resultado
select 'B1f os 4 interruptores: a linha desligado, o DEFAULT da coluna sombra (quem põe em sombra é o dado 20261112100990)',
       count(*) = 4 and bool_and(to_jsonb(c) ->> m.coluna = 'desligado')
       and bool_and(pg_get_expr(d.adbin, d.adrelid) = '''sombra''::text'),
       string_agg(m.coluna || '=' || (to_jsonb(c) ->> m.coluna) || '/' || pg_get_expr(d.adbin, d.adrelid), ', ')
  from m
  cross join public.agenda_config c
  join pg_attribute a on a.attrelid = 'public.agenda_config'::regclass and a.attname = m.coluna
  join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where c.id;

-- Todo CHECK de agenda_config desta migration existe pelo nome (21).
with n(nome) as (select 'agenda_config_' || x || '_check' from unnest(array[
  'modo_porque', 'modo_explicar', 'modo_placar', 'modo_rebaixar', 'porque_motivos_max', 'origens_do_dono', 'livre_semanas', 'como_pensei_perguntas',
  'como_pensei_itens_max', 'correcao_janela_du', 'rebaixar_janela_semanas', 'rebaixar_n_min', 'rebaixar_taxa', 'rebaixar_amostra', 'voltar_n', 'rebaixar_trava_dias',
  'explicar_hora', 'placar_janela', 'placar_semanas_hist', 'placar_min_linhas', 'explicar_tempo_max']) x)
insert into _resultado
select 'B1h os 21 CHECKs de agenda_config existem pelo nome',
       count(*) = 21 and bool_and(exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_config'::regclass and k.conname = n.nome)),
       string_agg(n.nome, ',') filter (where not exists (select 1 from pg_constraint k where k.conrelid = 'public.agenda_config'::regclass and k.conname = n.nome))
  from n;

-- O cabeçalho da migration é afirmação (lição 9 da 7e): o número de CHECKs de agenda_config que ele diz (no DDL e no DESFAZER) é o que o do $$ cria e o catálogo tem,
-- e a coluna que ele diz estar sem CHECK é a única das 22 sem CHECK. A conferência do P1 achou 20 no texto para 21 no do $$. Lê a migration como texto: só na bancada.
do $b1h2$
declare
  v_mig   text := coalesce(current_setting('agenda_teste.mig_base_fase7g', true), '');
  v_cab   int[];
  v_desf  int[];
  v_menos text[];
  v_nomes text[];
  v_cat   int;
  v_sem   text;
begin
  if v_mig = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B1h2 o cabeçalho da migration', true, 'PULADO: sem agenda_teste.mig_base_fase7g (rode pela bancada)'));
    return;
  end if;
  select array_agg(m[1]::int) into v_cab from regexp_matches(v_mig, '(\d+) CHECKs novos por nome em agenda_config', 'g') m;
  select array_agg(m[1]::int) into v_desf from regexp_matches(v_mig, 'drop dos (\d+) CHECKs', 'g') m;
  select array_agg(m[1]) into v_menos from regexp_matches(v_mig, 'CHECK por nome em cada um, menos ([a-z_]+)', 'g') m;
  select array_agg(m[1]) into v_nomes from regexp_matches(v_mig, '\(''(agenda_config_[a-z_]+_check)''', 'g') m;
  select count(*)::int into v_cat from pg_constraint k where k.conrelid = 'public.agenda_config'::regclass and k.contype = 'c' and k.conname = any (v_nomes);
  -- das 22 colunas da migration (as 21 dos nomes dos CHECKs mais marcacoes_desde), as que não têm CHECK nenhum no catálogo
  select string_agg(a.attname, ',' order by a.attname) into v_sem
    from pg_attribute a
   where a.attrelid = 'public.agenda_config'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attname = any (array_append(array(select regexp_replace(x, '^agenda_config_(.*)_check$', '\1') from unnest(v_nomes) x), 'marcacoes_desde'))
     and not exists (select 1 from pg_constraint k where k.conrelid = a.attrelid and k.contype = 'c' and a.attnum = any (k.conkey));
  perform pg_temp.gravar(pg_temp.ok('[]', 'B1h2 o cabeçalho e o DESFAZER da migration dizem o número de CHECKs de agenda_config que o do $$ cria e o catálogo tem (21), e a coluna sem CHECK que ele diz é a única',
    v_cab = array[21] and v_desf = array[21] and cardinality(v_nomes) = 21 and v_cat = 21 and v_menos = array[v_sem] and v_sem = 'marcacoes_desde',
    format('cabeçalho %s, DESFAZER %s, do $$ %s, catálogo %s; sem CHECK: diz %s, é %s', v_cab, v_desf, cardinality(v_nomes), v_cat, v_menos, v_sem)));
end
$b1h2$;

-- Cada CHECK de um limite recusa o valor logo abaixo e logo acima (pelo nome: o erro só vale se for ESTE check) e aceita os 2 limites. "extra" leva a coluna que cruza para
-- fora do caminho (rebaixar_n_min sobe com a amostra no máximo, senão quem recusa é o CHECK da amostra).
create temp table _fx (coluna text, abaixo text, acima text, lim_baixo text, lim_alto text, nome text, extra text) on commit drop;
insert into _fx values
  ('porque_motivos_max',      '-1',            '4',              '0',             '3',              'agenda_config_porque_motivos_max_check', null),
  ('livre_semanas',           '1',             '9',              '2',             '8',              'agenda_config_livre_semanas_check', null),
  ('como_pensei_perguntas',   '0',             '6',              '1',             '5',              'agenda_config_como_pensei_perguntas_check', null),
  ('como_pensei_itens_max',   '2',             '11',             '3',             '10',             'agenda_config_como_pensei_itens_max_check', null),
  ('correcao_janela_du',      '2',             '21',             '3',             '20',             'agenda_config_correcao_janela_du_check', null),
  ('rebaixar_janela_semanas', '3',             '27',             '4',             '26',             'agenda_config_rebaixar_janela_semanas_check', null),
  ('rebaixar_n_min',          '1',             '11',             '2',             '10',             'agenda_config_rebaixar_n_min_check', ', rebaixar_amostra = 20'),
  ('rebaixar_taxa',           '0.19',          '0.91',           '0.20',          '0.90',           'agenda_config_rebaixar_taxa_check', null),
  ('rebaixar_amostra',        '2',             '21',             '3',             '20',             'agenda_config_rebaixar_amostra_check', null),
  ('voltar_n',                '1',             '11',             '2',             '10',             'agenda_config_voltar_n_check', null),
  ('rebaixar_trava_dias',     '6',             '91',             '7',             '90',             'agenda_config_rebaixar_trava_dias_check', null),
  ('placar_semanas_hist',     '3',             '27',             '4',             '26',             'agenda_config_placar_semanas_hist_check', null),
  ('placar_min_linhas',       '0',             '11',             '1',             '10',             'agenda_config_placar_min_linhas_check', null),
  ('explicar_tempo_max',      $$'4 seconds'$$, $$'26 seconds'$$, $$'5 seconds'$$, $$'25 seconds'$$, 'agenda_config_explicar_tempo_max_check', null);

do $b1$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  m     text;
  n     text;
  v     text;
  v_ds  time;
begin
  select string_agg(format('%s/%s: %s, %s', f.coluna, f.nome,
                           pg_temp.recusa(format('update public.agenda_config set %I = %s%s where id', f.coluna, f.abaixo, coalesce(f.extra, ''))),
                           pg_temp.recusa(format('update public.agenda_config set %I = %s%s where id', f.coluna, f.acima, coalesce(f.extra, '')))), ' | ') into v_dif
    from _fx f
   where pg_temp.recusa(format('update public.agenda_config set %I = %s%s where id', f.coluna, f.abaixo, coalesce(f.extra, ''))) is distinct from f.nome
      or pg_temp.recusa(format('update public.agenda_config set %I = %s%s where id', f.coluna, f.acima, coalesce(f.extra, ''))) is distinct from f.nome;
  v_res := pg_temp.ok(v_res, 'B1i os 14 parâmetros de limite recusam, pelo CHECK deles, o valor logo abaixo e logo acima', v_dif is null, v_dif);
  select string_agg(format('%s: %s / %s', f.coluna,
                           pg_temp.recusa(format('update public.agenda_config set %I = %s%s where id', f.coluna, f.lim_baixo, coalesce(f.extra, ''))),
                           pg_temp.recusa(format('update public.agenda_config set %I = %s%s where id', f.coluna, f.lim_alto, coalesce(f.extra, '')))), ' | ') into v_dif
    from _fx f
   where pg_temp.recusa(format('update public.agenda_config set %I = %s%s where id', f.coluna, f.lim_baixo, coalesce(f.extra, ''))) is distinct from 'aceitou'
      or pg_temp.recusa(format('update public.agenda_config set %I = %s%s where id', f.coluna, f.lim_alto, coalesce(f.extra, ''))) is distinct from 'aceitou';
  v_res := pg_temp.ok(v_res, 'B1j os mesmos 14 aceitam os 2 limites', v_dif is null, v_dif);
  v_dif := null;
  foreach m in array array['modo_porque', 'modo_explicar', 'modo_placar', 'modo_rebaixar'] loop
    if pg_temp.recusa(format('update public.agenda_config set %I = ''meio'' where id', m)) is distinct from format('agenda_config_%s_check', m) then
      v_dif := coalesce(v_dif || ', ', '') || m;
    end if;
    foreach n in array array['desligado', 'sombra', 'ligado'] loop
      if pg_temp.recusa(format('update public.agenda_config set %I = %L where id', m, n)) is distinct from 'aceitou' then
        v_dif := coalesce(v_dif || ', ', '') || m || '=' || n;
      end if;
    end loop;
  end loop;
  v_res := pg_temp.ok(v_res, 'B1k os 4 interruptores: só desligado, sombra e ligado (cada recusa pelo CHECK dele)', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B1l placar_janela: só semana_passada e ultimos_7_dias (AG7-26)',
    pg_temp.recusa($$update public.agenda_config set placar_janela = 'mes' where id$$) = 'agenda_config_placar_janela_check'
    and pg_temp.recusa($$update public.agenda_config set placar_janela = 'ultimos_7_dias' where id$$) = 'aceitou',
    pg_temp.recusa($$update public.agenda_config set placar_janela = 'mes' where id$$));
  -- origens_do_dono: vazia, com nulo e com origem que não existe são recusadas; a lista inteira de agenda_acoes.origem entra, e cada origem dela sozinha também
  v_dif := null;
  if pg_temp.recusa($$update public.agenda_config set origens_do_dono = '{}' where id$$) is distinct from 'agenda_config_origens_do_dono_check' then v_dif := 'vazia: ' || pg_temp.recusa($$update public.agenda_config set origens_do_dono = '{}' where id$$); end if;
  if pg_temp.recusa($$update public.agenda_config set origens_do_dono = '{dono,null}' where id$$) is distinct from 'agenda_config_origens_do_dono_check' then v_dif := coalesce(v_dif || ' | ', '') || 'nulo'; end if;
  if pg_temp.recusa($$update public.agenda_config set origens_do_dono = '{dono,gestor}' where id$$) is distinct from 'agenda_config_origens_do_dono_check' then v_dif := coalesce(v_dif || ' | ', '') || 'gestor'; end if;
  if pg_temp.recusa(format('update public.agenda_config set origens_do_dono = %L where id', pg_temp.lista('public.agenda_acoes', 'agenda_acoes_origem_check'))) is distinct from 'aceitou' then v_dif := coalesce(v_dif || ' | ', '') || 'a lista inteira'; end if;
  select string_agg(o, ',') into v from unnest(pg_temp.lista('public.agenda_acoes', 'agenda_acoes_origem_check')) o
   where pg_temp.recusa(format('update public.agenda_config set origens_do_dono = %L where id', array[o])) is distinct from 'aceitou';
  if v is not null then v_dif := coalesce(v_dif || ' | ', '') || 'sozinhas: ' || v; end if;
  v_res := pg_temp.ok(v_res, 'B1m origens_do_dono: vazia, com nulo e com origem fora de agenda_acoes.origem recusadas; as 12 origens, juntas e sozinhas, entram', v_dif is null, v_dif);
  -- o que cruza colunas
  v_res := pg_temp.ok(v_res, 'B1n rebaixar_amostra não fica abaixo de rebaixar_n_min (5 com mínimo 6: recusado pelo CHECK da amostra; 6 com 6 entra)',
    pg_temp.recusa($$update public.agenda_config set rebaixar_n_min = 6, rebaixar_amostra = 5 where id$$) = 'agenda_config_rebaixar_amostra_check'
    and pg_temp.recusa($$update public.agenda_config set rebaixar_n_min = 6, rebaixar_amostra = 6 where id$$) = 'aceitou',
    pg_temp.recusa($$update public.agenda_config set rebaixar_n_min = 6, rebaixar_amostra = 5 where id$$));
  select c.dono_semana_hora into v_ds from public.agenda_config c where c.id;
  v_res := pg_temp.ok(v_res, 'B1o explicar_hora: de 12:00 até antes de dono_semana_hora (11:59 e a própria hora da quinta recusadas; 12:00 e 1 minuto antes entram)',
    pg_temp.recusa($$update public.agenda_config set explicar_hora = '11:59' where id$$) = 'agenda_config_explicar_hora_check'
    and pg_temp.recusa(format('update public.agenda_config set explicar_hora = %L where id', v_ds)) = 'agenda_config_explicar_hora_check'
    and pg_temp.recusa($$update public.agenda_config set explicar_hora = '12:00' where id$$) = 'aceitou'
    and pg_temp.recusa(format('update public.agenda_config set explicar_hora = %L where id', v_ds - interval '1 minute')) = 'aceitou',
    format('dono_semana_hora=%s', v_ds));
  v_res := pg_temp.ok(v_res, 'B1p a quinta não passa a antes da rodada: dono_semana_hora 16:35 com explicar_hora 16:35 é recusado (pelo CHECK de explicar_hora)',
    pg_temp.recusa($$update public.agenda_config set dono_semana_hora = '16:35' where id$$) = 'agenda_config_explicar_hora_check',
    pg_temp.recusa($$update public.agenda_config set dono_semana_hora = '16:35' where id$$));
  perform pg_temp.gravar(v_res);
end
$b1$;

insert into _resultado
select 'B1s a linha de agenda_config cabe na página: abaixo de 8 kB (R9.8)', pg_column_size(c.*) < 8000, pg_column_size(c.*) || ' bytes'
  from public.agenda_config c where c.id;

-- ── B2. O lugar do porquê: agenda_alocacoes e agenda_acoes ───────────────────────────────────────────
with col(tabela, coluna, tipo) as (values
  ('agenda_alocacoes', 'suposicoes', 'jsonb'), ('agenda_alocacoes', 'degrau', 'text'), ('agenda_acoes', 'zona', 'text'), ('agenda_acoes', 'degrau', 'text'))
insert into _resultado
select 'B2a as 4 colunas novas: nuláveis e SEM DEFAULT (suposicoes nula = de antes da 7g, R9.4-1; a §4.2 dizia not null default ''[]'')',
       count(*) = 4 and bool_and(not a.attnotnull and not a.atthasdef and format_type(a.atttypid, a.atttypmod) = col.tipo),
       string_agg(format('%s.%s notnull=%s default=%s tipo=%s', col.tabela, col.coluna, a.attnotnull, a.atthasdef, format_type(a.atttypid, a.atttypmod)), '; ')
         filter (where a.attnotnull or a.atthasdef or format_type(a.atttypid, a.atttypmod) <> col.tipo)
  from col join pg_attribute a on a.attrelid = ('public.' || col.tabela)::regclass and a.attname = col.coluna and not a.attisdropped;
insert into _resultado
select 'B2b nada é escrito: todas as alocações e ações que existem seguem com as 4 colunas nulas',
       (select count(*) from public.agenda_alocacoes where suposicoes is not null or degrau is not null) = 0
       and (select count(*) from public.agenda_acoes where zona is not null or degrau is not null) = 0,
       format('%s alocações, %s ações', (select count(*) from public.agenda_alocacoes), (select count(*) from public.agenda_acoes));
insert into _resultado
select 'B2c os 4 CHECKs pelo nome; o das suposições chama _agenda_suposicoes_validas',
       (select count(*) from pg_constraint where conrelid = 'public.agenda_alocacoes'::regclass and conname in ('alocacao_suposicoes_validas', 'alocacao_degrau_check')) = 2
       and (select count(*) from pg_constraint where conrelid = 'public.agenda_acoes'::regclass and conname in ('agenda_acoes_zona_check', 'agenda_acoes_degrau_check')) = 2
       and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'alocacao_suposicoes_validas') like '%_agenda_suposicoes_validas(suposicoes)%', null;

do $b2$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  v_id  uuid;
  r     record;
begin
  -- os CHECKs, pelo INSERT (a coluna só nasce no INSERT): cada valor errado recusado pelo CHECK dele, cada certo entra
  for r in select * from (values
    ('suposições objeto',               pg_temp.aloc('suposicoes', $$'{}'::jsonb$$),                                                      'alocacao_suposicoes_validas'),
    ('suposição sem detalhe',           pg_temp.aloc('suposicoes', $$'[{"codigo": "sem_peca"}]'::jsonb$$),                                 'alocacao_suposicoes_validas'),
    ('suposição de código inventado',   pg_temp.aloc('suposicoes', $$'[{"codigo": "chute", "detalhe": {}}]'::jsonb$$),                     'alocacao_suposicoes_validas'),
    ('suposições nulas',                pg_temp.aloc('suposicoes', 'null'),                                                                 'aceitou'),
    ('suposições vazias',               pg_temp.aloc('suposicoes', $$'[]'::jsonb$$),                                                        'aceitou'),
    ('uma suposição certa',             pg_temp.aloc('suposicoes', $$'[{"codigo": "sem_peca", "detalhe": {}}]'::jsonb$$),                  'aceitou'),
    ('degrau inventado na alocação',    pg_temp.aloc('degrau', $$'pior'$$),                                                                 'alocacao_degrau_check'),
    ('degrau tirou na alocação',        pg_temp.aloc('degrau', $$'tirou'$$),                                                                'aceitou'),
    ('zona inventada na ação',          pg_temp.acao('zona', $$'morna'$$),                                                                  'agenda_acoes_zona_check'),
    ('zona firme na ação',              pg_temp.acao('zona', $$'firme'$$),                                                                  'aceitou'),
    ('degrau inventado na ação',        pg_temp.acao('degrau', $$'pior'$$),                                                                 'agenda_acoes_degrau_check'),
    ('degrau data na ação',             pg_temp.acao('degrau', $$'data'$$),                                                                 'aceitou')
  ) as t(nome, sql, espera) loop
    if pg_temp.recusa(r.sql) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(r.sql);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B2d os 4 CHECKs: suposições (objeto, sem detalhe, código inventado), degrau e zona recusados pelo nome; nula, [], a certa e os valores da lista entram', v_dif is null, v_dif);
  -- a zona e o degrau da ação só no INSERT: o gatilho de "só desfaz" da Fase 2 já recusa mudar (§4.2: "não precisa mudar")
  execute pg_temp.acao('zona, degrau', $$'livre', 'dia'$$) || ' returning id' into v_id;
  v_res := pg_temp.ok(v_res, 'B2e a zona e o degrau da ação não mudam depois do INSERT (o gatilho de só desfaz da Fase 2)',
    pg_temp.recusa(format('update public.agenda_acoes set zona = ''travada'' where id = %L', v_id)) like 'erro P0001:%'
    and pg_temp.recusa(format('update public.agenda_acoes set degrau = null where id = %L', v_id)) like 'erro P0001:%',
    pg_temp.recusa(format('update public.agenda_acoes set zona = ''travada'' where id = %L', v_id)));
  perform pg_temp.gravar(v_res);
end
$b2$;

-- ── B3. RLS e privilégios ────────────────────────────────────────────────────────────────────────────
-- Quem chamaria as 8 pela porta de authenticated: função de public sem definer (roda como quem chama), com execute para authenticated, que cita uma das 8 (o B3e3 e o
-- controle dele). O pacote que criar uma assim dá a porta a authenticated à função chamada, na mesma migration, e muda o B3e e o B3e3.
create function pg_temp.chamador_sem_definer_7g() returns text language sql stable as $f$
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and not p.prosecdef
     and has_function_privilege('authenticated', p.oid, 'execute')
     and p.proname not in ('_agenda_suposicoes_validas', '_agenda_quem_marcou', '_agenda_degrau', '_agenda_zona_mais_severa', '_agenda_duracao_fonte_texto',
                           '_agenda_suposicao_texto', '_agenda_criterio_texto', '_agenda_degrau_texto')
     and p.prosrc ~ '_agenda_(suposicoes_validas|quem_marcou|degrau|zona_mais_severa|duracao_fonte_texto|suposicao_texto|criterio_texto|degrau_texto)\('
$f$;

do $b3$
declare
  v_res  jsonb := '[]'::jsonb;
  v_adm  uuid := pg_temp.adm();
  v_tec  uuid := pg_temp.tec();
  v_dif  text;
  v      text;
  t      text;
  c_tabelas constant text[] := array['agenda_marcacoes', 'agenda_tipos_os', 'agenda_placar_semanas'];
  c_funcoes constant text[] := array['public._agenda_suposicoes_validas(jsonb)', 'public._agenda_quem_marcou(text, text)', 'public._agenda_degrau(jsonb, jsonb, date, date, date)',
                                     'public._agenda_zona_mais_severa(text[])', 'public._agenda_duracao_fonte_texto(text, numeric, numeric, text)',
                                     'public._agenda_suposicao_texto(text, jsonb)', 'public._agenda_criterio_texto(text)', 'public._agenda_degrau_texto(text)'];
  c_gatilhos constant text[] := array['public._agenda_marcacoes_so_muda()', 'public._agenda_tipos_os_so_muda()', 'public._agenda_placar_so_muda()'];
begin
  select string_agg(x, ', ') into v_dif from unnest(c_tabelas) x
   where not (select c.relrowsecurity from pg_class c where c.oid = ('public.' || x)::regclass)
      or (select count(*) from pg_policy p where p.polrelid = ('public.' || x)::regclass) <> 1
      or not exists (select 1 from pg_policy p where p.polrelid = ('public.' || x)::regclass and p.polcmd = 'r' and p.polroles = array['authenticated'::regrole::oid]
                       and pg_get_expr(p.polqual, p.polrelid) like '%is_admin_or_financial%');
  v_res := pg_temp.ok(v_res, 'B3a as 3 tabelas: RLS ligada, 1 política só de leitura TO authenticated por is_admin_or_financial', v_dif is null, v_dif);
  select string_agg(x, ', ') into v_dif from unnest(c_tabelas) x
   where has_table_privilege('anon', 'public.' || x, 'select') or has_table_privilege('anon', 'public.' || x, 'insert')
      or not has_table_privilege('authenticated', 'public.' || x, 'select')
      or has_table_privilege('authenticated', 'public.' || x, 'insert') or has_table_privilege('authenticated', 'public.' || x, 'update')
      or has_table_privilege('authenticated', 'public.' || x, 'delete')
      or not has_table_privilege('service_role', 'public.' || x, 'select') or not has_table_privilege('service_role', 'public.' || x, 'insert')
      or not has_table_privilege('service_role', 'public.' || x, 'update');
  v_res := pg_temp.ok(v_res, 'B3b privilégios das 3: anon nada; authenticated só select; service_role escreve', v_dif is null, v_dif);
  -- uma linha em cada (na transação; o rollback desfaz)
  insert into public.agenda_tipos_os (classe, calculado_em) values ('rv:teste', now());
  insert into public.agenda_placar_semanas (semana, de, ate, modo, numeros, texto, linha, calculado_em)
  values (date '2031-01-06', date '2031-01-06', date '2031-01-11', 'sombra', '{}', 'Placar de teste', 'Placar de teste', now());
  insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, de, ate, meios, pessoas, marcada_em, primeiro_inicio)
  select a.id, so.id, 'dono', 'dono', 'criar', 'rv:teste', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now()
    from public.agenda_acoes a, public.service_orders so order by a.criada_em, so.created_at limit 1;
  v_dif := null;
  foreach t in array c_tabelas loop
    v := pg_temp.como(null, 'anon', format('select count(*)::text from public.%I', t));
    if v not like 'erro 42501%' then v_dif := coalesce(v_dif || ' | ', '') || t || ' anon=' || v; end if;
    v := pg_temp.como(v_tec, 'authenticated', format('select count(*)::text from public.%I', t));
    if v <> '0' then v_dif := coalesce(v_dif || ' | ', '') || t || ' técnico=' || v; end if;
    v := pg_temp.como(v_tec, 'authenticated', format('delete from public.%I returning 1', t));
    if v not like 'erro 42501%' then v_dif := coalesce(v_dif || ' | ', '') || t || ' técnico apaga=' || coalesce(v, 'nulo'); end if;
    v := pg_temp.como(v_adm, 'authenticated', format('select count(*)::text from public.%I', t));
    if v <> '1' then v_dif := coalesce(v_dif || ' | ', '') || t || ' admin=' || v; end if;
    v := pg_temp.como(v_adm, 'authenticated', format('update public.%I set versao = versao returning 1', t));
    if t <> 'agenda_tipos_os' and v not like 'erro 42501%' then v_dif := coalesce(v_dif || ' | ', '') || t || ' admin grava=' || coalesce(v, 'nulo'); end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B3c as leituras por papel: anon 42501, técnico lê vazio e não apaga, administrador lê a linha e não grava', v_dif is null, v_dif);
  select string_agg(p, ', ') into v_dif from unnest(c_funcoes) p
   where has_function_privilege('anon', p, 'execute')
      or exists (select 1 from pg_proc x, aclexplode(x.proacl) a where x.oid = p::regprocedure and a.grantee = 0 and a.privilege_type = 'EXECUTE');
  v_res := pg_temp.ok(v_res, 'B3d as 8 funções novas sem execute para anon nem para public', v_dif is null, v_dif);
  select string_agg(p, ', ') into v_dif from unnest(c_funcoes) p
   where has_function_privilege('authenticated', p, 'execute') or not has_function_privilege('service_role', p, 'execute');
  v_res := pg_temp.ok(v_res, 'B3e as 8 têm execute só para service_role, nenhum para authenticated (§5.1 e §3.1-13: internas; o revoke é explícito, o privilégio padrão do esquema daria)', v_dif is null, v_dif);
  select string_agg(x, ', ') into v_dif from unnest(array['public.agenda_alocacoes', 'public.agenda_acoes']) x
   where has_table_privilege('authenticated', x, 'insert') or has_table_privilege('authenticated', x, 'update') or has_table_privilege('authenticated', x, 'delete')
      or not has_table_privilege('service_role', x, 'insert') or not has_table_privilege('service_role', x, 'update');
  v_res := pg_temp.ok(v_res, 'B3e2 authenticated não grava agenda_alocacoes nem agenda_acoes (só select, Fase 2) e o service_role grava: o CHECK das suposições, que roda como quem escreve, não precisa da porta de authenticated', v_dif is null, v_dif);
  -- ninguém chama as 8 pela porta de authenticated; dos leitores do painel, a tela da semana e o plano da OS são definer. Controle: uma função sem definer, plantada com a
  -- porta de authenticated, que chama quem marcou, aparece (e sai com a subtransação).
  v_dif := pg_temp.chamador_sem_definer_7g();
  begin
    create function public._b3e3_sonda_7g() returns text language sql stable as $s$ select public._agenda_quem_marcou('tela') $s$;
    grant execute on function public._b3e3_sonda_7g() to authenticated;
    v := coalesce(pg_temp.chamador_sem_definer_7g(), 'nada');
    raise exception using errcode = 'P0001', message = '__desfaz__';
  exception when others then
    if sqlerrm <> '__desfaz__' then v := 'erro ' || sqlstate || ': ' || sqlerrm; end if;
  end;
  select count(*) filter (where p.prosecdef)::text || '/' || count(*)::text into t
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('agenda_tela_semana', 'os_plano_da_os');
  v_res := pg_temp.ok(v_res, 'B3e3 nenhuma função sem definer com porta para authenticated chama as 8, e agenda_tela_semana e os_plano_da_os são definer; controle: a plantada aparece',
    v_dif is null and v in ('_b3e3_sonda_7g()', 'public._b3e3_sonda_7g()') and t = '2/2', format('chamadores %s | controle %s | definer entre tela e plano %s', coalesce(v_dif, 'nenhum'), v, t));
  select string_agg(p, ', ') into v_dif from unnest(c_gatilhos) p
   where has_function_privilege('anon', p, 'execute') or has_function_privilege('authenticated', p, 'execute') or has_function_privilege('service_role', p, 'execute');
  v_res := pg_temp.ok(v_res, 'B3f os 3 gatilhos sem execute para ninguém fora do dono', v_dif is null, v_dif);
  -- a chamada de verdade: authenticated, mesmo com o login do administrador, não chama quem marcou nem os textos (42501); o service_role chama (lê agenda_config); anon não
  v := pg_temp.como(v_adm, 'authenticated', $$select public._agenda_quem_marcou('tela')$$);
  v_res := pg_temp.ok(v_res, 'B3g authenticated, com o login do administrador, não chama _agenda_quem_marcou (42501: sem porta, §5.1)', v like 'erro 42501%', v);
  v := pg_temp.como(v_adm, 'authenticated', $$select public._agenda_degrau_texto('dia')$$);
  v_res := pg_temp.ok(v_res, 'B3g2 authenticated, com o login do administrador, não chama os textos (42501)', v like 'erro 42501%', v);
  v := pg_temp.como(null, 'service_role', $$select public._agenda_quem_marcou('tela')$$);
  v_res := pg_temp.ok(v_res, 'B3g3 o service_role chama _agenda_quem_marcou (a porta que fica; lê agenda_config)', v = 'dono', v);
  v := pg_temp.como(null, 'anon', $$select public._agenda_quem_marcou('tela')$$);
  v_res := pg_temp.ok(v_res, 'B3h anon não chama _agenda_quem_marcou (42501)', v like 'erro 42501%', v);
  v := pg_temp.como(null, 'anon', $$select public._agenda_duracao_fonte_texto('dono', 2, null)$$);
  v_res := pg_temp.ok(v_res, 'B3i anon não chama os textos (42501)', v like 'erro 42501%', v);
  perform pg_temp.gravar(v_res);
end
$b3$;

-- As 11 funções: search_path fixo, nenhuma definer; as 7 de conta IMMUTABLE (o CHECK das suposições roda em cada INSERT; as outras são conta só sobre o argumento), quem marcou
-- STABLE (lê agenda_config) e os 3 gatilhos VOLATILE (o padrão).
with f(nome, vol) as (values
  ('_agenda_suposicoes_validas', 'i'), ('_agenda_degrau', 'i'), ('_agenda_zona_mais_severa', 'i'), ('_agenda_duracao_fonte_texto', 'i'), ('_agenda_suposicao_texto', 'i'),
  ('_agenda_criterio_texto', 'i'), ('_agenda_degrau_texto', 'i'), ('_agenda_quem_marcou', 's'),
  ('_agenda_marcacoes_so_muda', 'v'), ('_agenda_tipos_os_so_muda', 'v'), ('_agenda_placar_so_muda', 'v'))
insert into _resultado
select 'B3j as 11 funções novas: search_path fixo, nenhuma definer; as 7 de conta IMMUTABLE, quem marcou STABLE e os 3 gatilhos VOLATILE',
       count(*) = 11 and bool_and(p.provolatile::text = f.vol and not p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'),
       string_agg(format('%s vol=%s definer=%s cfg=%s', f.nome, p.provolatile, p.prosecdef, p.proconfig), '; ')
         filter (where p.provolatile::text <> f.vol or p.prosecdef or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=public')
  from f join pg_proc p on p.proname = f.nome and p.pronamespace = 'public'::regnamespace;

-- ── B4. As listas ────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B4a agenda_alocacoes.motivo: os 11 de antes, na ordem, e ferramenta no fim (AG7-27)',
       pg_temp.lista('public.agenda_alocacoes'::regclass, 'agenda_alocacoes_motivo_check')
       = '{material,cliente_ou_bem,equipe_faltou,trabalho_anterior,informacao,clima,estimativa,imprevisto_tecnico,urgencia_outra_os,esqueci,concluida_antes,ferramenta}'::text[],
       array_to_string(pg_temp.lista('public.agenda_alocacoes'::regclass, 'agenda_alocacoes_motivo_check'), ',');
insert into _resultado
select 'B4b agenda_vigia_rodadas.rotina: as 11 de antes (as de produção, wf7g_p1_estado), na ordem, e explicar no fim',
       pg_temp.lista('public.agenda_vigia_rodadas'::regclass, 'agenda_vigia_rodadas_rotina_check')
       = '{vigia,rotina,material,cliente,aprender,gestor,equipe_semana,habilidade,tarefas,local,comunicar,explicar}'::text[],
       array_to_string(pg_temp.lista('public.agenda_vigia_rodadas'::regclass, 'agenda_vigia_rodadas_rotina_check'), ',');
insert into _resultado
select 'B4c nada do P5b (R9.4-4): nivel fora das ações, ok_marcacao fora das perguntas, ok_do_dono fora da condição, e os_planejamento sem espera_ok_desde/ok_do_dono_*',
       not ('nivel' = any (pg_temp.lista('public.agenda_acoes'::regclass, 'agenda_acoes_tipo_check')))
       and not ('ok_marcacao' = any (pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')))
       and not ('ok_do_dono' = any (pg_temp.lista('public.agenda_alocacoes'::regclass, 'agenda_alocacoes_condicao_tipo_check')))
       and not exists (select 1 from pg_attribute a where a.attrelid = 'public.os_planejamento'::regclass and not a.attisdropped
                         and a.attname in ('espera_ok_desde', 'ok_do_dono_em', 'ok_do_dono_via')), null;
do $b4$
declare
  v_res jsonb := '[]'::jsonb;
begin
  v_res := pg_temp.ok(v_res, 'B4d capacidade_motivos continua sem ferramenta (não é falta do dono; §3.1 item 12)',
    pg_temp.recusa($$update public.agenda_config set capacidade_motivos = capacidade_motivos || '{ferramenta}' where id$$) = 'agenda_config_capacidade_motivos_check',
    pg_temp.recusa($$update public.agenda_config set capacidade_motivos = capacidade_motivos || '{ferramenta}' where id$$));
  v_res := pg_temp.ok(v_res, 'B4e a rodada explicar entra em agenda_vigia_rodadas; um nome de fora, não (o ampliador manteve o CHECK fechado)',
    pg_temp.recusa($$insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia, rotina) values (date '2031-01-07', now(), 'sombra', 'sombra', 'explicar')$$) = 'aceitou'
    and pg_temp.recusa($$insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia, rotina) values (date '2031-01-07', now(), 'sombra', 'sombra', 'explica')$$) = 'agenda_vigia_rodadas_rotina_check',
    pg_temp.recusa($$insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia, rotina) values (date '2031-01-07', now(), 'sombra', 'sombra', 'explicar')$$));
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B5. As 3 tabelas: os CHECKs, não se apagam, só mudam o permitido ─────────────────────────────────
do $b5$
declare
  v_res   jsonb := '[]'::jsonb;
  v_dif   text;
  v_acao  uuid;
  v_acao2 uuid;
  v_os    uuid;
  v_os2   uuid;
  v_sql   text;
  v_ins   text;
  r       record;
  c_apaga constant text := 'erro P0001: O registro da agenda não se apaga.';
  c_so_desfecho constant text := 'erro P0001: A marcação é o que aconteceu: só o desfecho muda.';
  c_uma_vez constant text := 'erro P0001: O desfecho da marcação sai de aberta uma vez, e decidido não volta.';
  c_inteira constant text := 'erro P0001: A marcação só muda inteira: versão + 1 e o que mudou no histórico.';
begin
  -- 2 ações de teste (em sombra) e a 1ª OS: na transação, o rollback desfaz
  execute pg_temp.acao(null, null) || ' returning id' into v_acao;
  execute pg_temp.acao(null, null) || ' returning id' into v_acao2;
  select so.id into v_os from public.service_orders so order by so.created_at limit 1;
  select so.id into v_os2 from public.service_orders so where so.id <> v_os order by so.created_at limit 1;
  -- ── agenda_marcacoes: os CHECKs pelo insert (cada um na sua subtransação; o padrão é uma marcação do gestor aberta, que entra)
  v_ins := format($q$insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, duracao_fonte, de, ate, meios, pessoas, marcada_em,
                     primeiro_inicio, desfecho, desfecho_em, ajustes, historico)
                     values (%L, %L, %%s)$q$, v_acao, v_os);
  for r in select * from (values
    ('a padrão (gestor, aberta)', $$'gestor', 'vigia', 'criar', 'rv:energia', 'orcamento', date '2031-01-07', date '2031-01-08', 4, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'aceitou'),
    ('a do dono, sem desfecho',   $$'dono', 'dono', 'fixar', 'rv:energia', 'dono', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), null, null, '{}', '[]'$$, 'aceitou'),
    ('reparar (R9.4-2)',          $$'gestor', 'vigia', 'reparar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'aceitou'),
    ('reestimar (R9.4-2)',        $$'gestor', 'vigia', 'reestimar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'aceitou'),
    ('decidida com data',         $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aceita', now(), '{}', '[]'$$, 'aceitou'),
    ('ajustada com o ajuste',     $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'ajustada', now(), '{dia}', '[]'$$, 'aceitou'),
    ('ajustada com os 5 ajustes', $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'ajustada', now(), '{duracao,pessoa,dia,tirou,material}', '[]'$$, 'aceitou'),
    ('desfeita com data',         $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'desfeita', now(), '{}', '[]'$$, 'aceitou'),
    ('remarcada com data',        $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'remarcada', now(), '{}', '[]'$$, 'aceitou'),
    ('saiu com data',             $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'saiu', now(), '{}', '[]'$$, 'aceitou'),
    ('fonte aceita',              $$'gestor', 'vigia', 'criar', 'rv:energia', 'aceita', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'aceitou'),
    ('fonte sugerida',            $$'gestor', 'vigia', 'criar', 'rv:energia', 'sugerida', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'aceitou'),
    ('tipo publicar',             $$'gestor', 'vigia', 'publicar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'aceitou'),
    ('tipo mover',                $$'gestor', 'vigia', 'mover', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'aceitou'),
    ('tipo promover_reserva',     $$'gestor', 'vigia', 'promover_reserva', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'aceitou'),
    ('quem cliente',              $$'cliente', 'cliente', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'agenda_marcacoes_quem_check'),
    ('tipo cancelar',             $$'gestor', 'vigia', 'cancelar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'agenda_marcacoes_tipo_acao_check'),
    ('classe de 2 letras',        $$'gestor', 'vigia', 'criar', 'rv', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'agenda_marcacoes_classe_check'),
    ('classe de 41 letras',       $$'gestor', 'vigia', 'criar', repeat('x', 41), null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'agenda_marcacoes_classe_check'),
    ('fonte fora da lista',       $$'gestor', 'vigia', 'criar', 'rv:energia', 'chute', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'agenda_marcacoes_duracao_fonte_check'),
    ('0 meios',                   $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 0, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'agenda_marcacoes_meios_check'),
    ('desfecho fora da lista',    $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'talvez', now(), '{}', '[]'$$, 'agenda_marcacoes_desfecho_check'),
    ('gestor sem desfecho',       $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), null, null, '{}', '[]'$$, 'marcacao_desfecho_so_gestor'),
    ('dono com desfecho',         $$'dono', 'dono', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'marcacao_desfecho_so_gestor'),
    ('decidida sem data',         $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aceita', null, '{}', '[]'$$, 'marcacao_decidida_tem_data'),
    ('aberta com data',           $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', now(), '{}', '[]'$$, 'marcacao_decidida_tem_data'),
    ('ajustada sem ajuste',       $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'ajustada', now(), '{}', '[]'$$, 'marcacao_ajustes_coerentes'),
    ('aceita com ajuste',         $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aceita', now(), '{dia}', '[]'$$, 'marcacao_ajustes_coerentes'),
    ('ajuste fora da lista',      $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'ajustada', now(), '{cor}', '[]'$$, 'agenda_marcacoes_ajustes_check'),
    ('período ao contrário',      $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-08', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$, 'marcacao_periodo'),
    ('histórico que não é lista', $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '{}'$$, 'agenda_marcacoes_historico_check'),
    ('histórico de 21',           $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', to_jsonb(array(select g from generate_series(1, 21) g))$$, 'agenda_marcacoes_historico_check'),
    ('histórico de 20',           $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', to_jsonb(array(select g from generate_series(1, 20) g))$$, 'aceitou')
  ) as t(nome, vals, espera) loop
    if pg_temp.recusa(format(v_ins, r.vals)) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(format(v_ins, r.vals));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B5a agenda_marcacoes: os 16 casos certos entram (as 4 fontes, os 7 tipos com reparar e reestimar, os 6 desfechos, os 5 ajustes, o dono sem desfecho) e os 17 errados são recusados, cada um pelo CHECK dele', v_dif is null, v_dif);
  -- a zona e o degrau da marcação (as listas da ação)
  v_dif := null;
  for r in select * from (values
    ('zona travada', $$'travada', null$$, 'aceitou'), ('zona firme', $$'firme', null$$, 'aceitou'), ('zona livre', $$'livre', null$$, 'aceitou'),
    ('zona inventada', $$'morna', null$$, 'agenda_marcacoes_zona_check'),
    ('degrau pessoa', $$null, 'pessoa'$$, 'aceitou'), ('degrau turno', $$null, 'turno'$$, 'aceitou'), ('degrau dia', $$null, 'dia'$$, 'aceitou'),
    ('degrau data', $$null, 'data'$$, 'aceitou'), ('degrau tirou', $$null, 'tirou'$$, 'aceitou'), ('degrau inventado', $$null, 'pior'$$, 'agenda_marcacoes_degrau_check')
  ) as t(nome, vals, espera) loop
    v_sql := format($q$insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, de, ate, meios, pessoas, marcada_em, primeiro_inicio,
                       desfecho, zona, degrau) values (%L, %L, 'gestor', 'vigia', 'mover', 'rv:energia', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', %s)$q$,
                    v_acao, v_os, r.vals);
    if pg_temp.recusa(v_sql) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(v_sql);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B5a2 a zona e o degrau da marcação: os 3 e os 5 da lista entram; um de fora, não (pelo CHECK de cada um)', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B5b a FK da ação recusa ação que não existe; a da OS, OS que não existe',
    pg_temp.recusa(format(replace(v_ins, v_acao::text, gen_random_uuid()::text), $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$)) = 'agenda_marcacoes_acao_id_fkey'
    and pg_temp.recusa(format(replace(v_ins, v_os::text, gen_random_uuid()::text), $$'gestor', 'vigia', 'criar', 'rv:energia', null, date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', null, '{}', '[]'$$)) = 'agenda_marcacoes_service_order_id_fkey', null);

  -- a linha que anda: uma marcação do gestor aberta, e uma do dono
  execute format(v_ins, $$'gestor', 'vigia', 'criar', 'rv:energia', 'orcamento', date '2031-01-07', date '2031-01-08', 4, '{}', now(), now(), 'aberta', null, '{}', '[]'$$);
  insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, de, ate, meios, pessoas, marcada_em, primeiro_inicio)
  values (v_acao2, v_os, 'dono', 'tela', 'fixar', 'rv:energia', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now());
  v_res := pg_temp.ok(v_res, 'B5c conferida nasce false (R9.4-2: o silêncio não é aceite), not null; suposições e ajustes nascem vazios; versão 1',
    (select bool_and(not m.conferida and m.suposicoes = '{}' and m.ajustes = '{}' and m.versao = 1 and m.historico = '[]') from public.agenda_marcacoes m where m.service_order_id = v_os)
    and pg_temp.recusa(format('update public.agenda_marcacoes set conferida = null, desfecho = ''aceita'', desfecho_em = now(), versao = 2, historico = ''[{"em": "x"}]'' where acao_id = %L', v_acao)) like 'erro 23502%',
    pg_temp.recusa(format('update public.agenda_marcacoes set conferida = null, desfecho = ''aceita'', desfecho_em = now(), versao = 2, historico = ''[{"em": "x"}]'' where acao_id = %L', v_acao)));
  v_sql := format('update public.agenda_marcacoes set %%s where acao_id = %L and service_order_id = %L', v_acao, v_os);
  v_res := pg_temp.ok(v_res, 'B5d não se apaga direto', pg_temp.recusa(format('delete from public.agenda_marcacoes where acao_id = %L', v_acao)) = c_apaga,
    pg_temp.recusa(format('delete from public.agenda_marcacoes where acao_id = %L', v_acao)));
  v_dif := null;
  for r in select * from (values
    ('a classe',            $$classe = 'rv:geral', desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[{"em": "x"}]'$$,           c_so_desfecho),
    ('quem',                $$quem = 'dono', desfecho = null, versao = 2, historico = '[{"em": "x"}]'$$,                                     c_so_desfecho),
    ('as suposições',       $$suposicoes = '{uma_pessoa}', desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[{"em": "x"}]'$$, c_so_desfecho),
    ('o primeiro início',   $$primeiro_inicio = now() + interval '1 day', desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[{"em": "x"}]'$$, c_so_desfecho),
    ('aberta para aberta',  $$versao = 2, historico = '[{"em": "x"}]'$$,                                                                     c_uma_vez),
    ('sem versão',          $$desfecho = 'aceita', desfecho_em = now(), historico = '[{"em": "x"}]'$$,                                       c_inteira),
    ('versão + 2',          $$desfecho = 'aceita', desfecho_em = now(), versao = 3, historico = '[{"em": "x"}]'$$,                           c_inteira),
    ('sem histórico novo',  $$desfecho = 'aceita', desfecho_em = now(), versao = 2$$,                                                        c_inteira),
    ('histórico vazio',     $$desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[]'$$,                                      c_inteira),
    ('aceita, inteira',     $$desfecho = 'aceita', desfecho_em = now(), conferida = true, versao = 2, historico = '[{"em": "x"}]'$$,          'aceitou'),
    ('ajustada, inteira',   $$desfecho = 'ajustada', ajustes = '{dia,pessoa}', desfecho_em = now(), desfecho_acao_id = '$$ || v_acao2 || $$', versao = 2, historico = '[{"em": "x"}]'$$, 'aceitou')
  ) as t(nome, sets, espera) loop
    if pg_temp.recusa(format(v_sql, r.sets)) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(format(v_sql, r.sets));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B5e a aberta: muda só o desfecho (com ajustes, data, ação e conferida), uma vez, com versão + 1 e histórico novo; o resto recusado pela regra certa', v_dif is null, v_dif);
  -- com o histórico de partida vazio, "vazio" e "igual" são o mesmo caso: uma aberta que já nasce com histórico separa as duas regras
  insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, de, ate, meios, pessoas, marcada_em, primeiro_inicio, desfecho, historico)
  values (v_acao, v_os2, 'gestor', 'vigia', 'criar', 'rv:energia', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta', '[{"em": "a"}]');
  v_sql := format('update public.agenda_marcacoes set %%s where acao_id = %L and service_order_id = %L', v_acao, v_os2);
  v_res := pg_temp.ok(v_res, 'B5e2 com histórico de partida: decidir com o histórico vazio ou igual é recusado; com uma entrada nova, entra',
    pg_temp.recusa(format(v_sql, $$desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[]'$$)) = c_inteira
    and pg_temp.recusa(format(v_sql, $$desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[{"em": "a"}]'$$)) = c_inteira
    and pg_temp.recusa(format(v_sql, $$desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[{"em": "a"}, {"em": "b"}]'$$)) = 'aceitou',
    pg_temp.recusa(format(v_sql, $$desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[]'$$)) || ' / '
    || pg_temp.recusa(format(v_sql, $$desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[{"em": "a"}]'$$)));
  v_sql := format('update public.agenda_marcacoes set %%s where acao_id = %L and service_order_id = %L', v_acao, v_os);
  -- decide de verdade, e daí não volta
  execute format(v_sql, $$desfecho = 'aceita', desfecho_em = now(), versao = 2, historico = '[{"em": "x"}]'$$);
  v_res := pg_temp.ok(v_res, 'B5f decidida não volta nem muda de desfecho (aceita → ajustada e aceita → aberta recusadas)',
    pg_temp.recusa(format(v_sql, $$desfecho = 'ajustada', ajustes = '{dia}', versao = 3, historico = '[{"em": "x"}, {"em": "y"}]'$$)) = c_uma_vez
    and pg_temp.recusa(format(v_sql, $$desfecho = 'aberta', desfecho_em = null, versao = 3, historico = '[{"em": "x"}, {"em": "y"}]'$$)) = c_uma_vez,
    pg_temp.recusa(format(v_sql, $$desfecho = 'ajustada', ajustes = '{dia}', versao = 3, historico = '[{"em": "x"}, {"em": "y"}]'$$)));
  v_res := pg_temp.ok(v_res, 'B5g a do dono não muda (não tem desfecho a decidir)',
    pg_temp.recusa(format('update public.agenda_marcacoes set desfecho = ''aceita'', desfecho_em = now(), versao = 2, historico = ''[{"em": "x"}]'' where acao_id = %L', v_acao2)) = c_uma_vez,
    pg_temp.recusa(format('update public.agenda_marcacoes set desfecho = ''aceita'', desfecho_em = now(), versao = 2, historico = ''[{"em": "x"}]'' where acao_id = %L', v_acao2)));

  -- ── agenda_tipos_os
  v_dif := null;
  v_ins := $q$insert into public.agenda_tipos_os (classe, calculado_em, %s) values (%s, now(), %s)$q$;
  for r in select * from (values
    ('o padrão',                     'nivel',                        $$'sozinho'$$,                                                   'aceitou'),
    ('classe de 3',                  'nivel',                        $$'sozinho'$$,                                                   'aceitou'),
    ('classe de 40',                 'nivel',                        $$'sozinho'$$,                                                   'aceitou'),
    ('classe de 2',                  'nivel',                        $$'sozinho'$$,                                                   'agenda_tipos_os_classe_check'),
    ('classe de 41',                 'nivel',                        $$'sozinho'$$,                                                   'agenda_tipos_os_classe_check'),
    ('espera com desde',             'nivel, desde',                 $$'espera_ok', now()$$,                                           'aceitou'),
    ('nível fora',                   'nivel',                        $$'talvez'$$,                                                    'agenda_tipos_os_nivel_check'),
    ('teria fora',                   'teria',                        $$'talvez'$$,                                                    'agenda_tipos_os_teria_check'),
    ('espera sem desde',             'nivel',                        $$'espera_ok'$$,                                                 'tipo_espera_tem_desde'),
    ('sozinho com desde',            'desde',                        'now()',                                                         'tipo_espera_tem_desde'),
    ('amostra objeto',               'amostra',                      $$'{}'$$,                                                        'agenda_tipos_os_amostra_check'),
    ('amostra de 21',                'amostra',                      'to_jsonb(array(select g from generate_series(1, 21) g))',       'agenda_tipos_os_amostra_check'),
    ('texto de 301',                 'texto',                        $$repeat('x', 301)$$,                                            'agenda_tipos_os_texto_check'),
    ('texto de 300',                 'texto',                        $$repeat('x', 300)$$,                                            'aceitou'),
    ('histórico de 21',              'historico',                    'to_jsonb(array(select g from generate_series(1, 21) g))',       'agenda_tipos_os_historico_check')
  ) as t(nome, cols, vals, espera) loop
    v_sql := format(v_ins, r.cols, quote_literal(case r.nome when 'classe de 3' then 'rvx' when 'classe de 40' then repeat('x', 40) when 'classe de 2' then 'rv'
                                                             when 'classe de 41' then repeat('x', 41) else 'rv:energia' end), r.vals);
    if pg_temp.recusa(v_sql) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(v_sql);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B5h agenda_tipos_os: os 5 certos entram (a classe de 3 e de 40 letras) e os 10 errados são recusados, cada um pelo CHECK dele', v_dif is null, v_dif);
  insert into public.agenda_tipos_os (classe, calculado_em, acao_id) values ('rv:energia', now(), v_acao);
  v_res := pg_temp.ok(v_res, 'B5i o tipo de OS muda tudo menos a classe; não se apaga',
    pg_temp.recusa($$update public.agenda_tipos_os set teria = 'espera_ok', n = 4, corrigidas = 3, texto = 'x', calculado_em = now(), acao_id = null where classe = 'rv:energia'$$) = 'aceitou'
    and pg_temp.recusa($$update public.agenda_tipos_os set classe = 'rv:geral' where classe = 'rv:energia'$$) = 'erro P0001: O tipo de OS é a classe: a classe não muda.'
    and pg_temp.recusa($$delete from public.agenda_tipos_os where classe = 'rv:energia'$$) = c_apaga,
    pg_temp.recusa($$update public.agenda_tipos_os set classe = 'rv:geral' where classe = 'rv:energia'$$));

  -- ── agenda_placar_semanas
  v_dif := null;
  v_ins := $q$insert into public.agenda_placar_semanas (semana, de, ate, modo, numeros, texto, linha, calculado_em, historico) values (%s, now(), %s)$q$;
  for r in select * from (values
    ('a padrão',             $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{}', 'Placar', 'Placar'$$,          $$'[]'$$, 'aceitou'),
    ('ligado',               $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'ligado', '{}', 'Placar', 'Placar'$$,          $$'[]'$$, 'aceitou'),
    ('semana numa terça',    $$date '2031-01-14', date '2031-01-14', date '2031-01-18', 'sombra', '{}', 'Placar', 'Placar'$$,          $$'[]'$$, 'agenda_placar_semanas_semana_check'),
    ('modo desligado',       $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'desligado', '{}', 'Placar', 'Placar'$$,       $$'[]'$$, 'agenda_placar_semanas_modo_check'),
    ('números em lista',     $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '[]', 'Placar', 'Placar'$$,          $$'[]'$$, 'agenda_placar_semanas_numeros_check'),
    ('texto de 2',           $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{}', 'Pl', 'Placar'$$,              $$'[]'$$, 'agenda_placar_semanas_texto_check'),
    ('texto de 1001',        $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{}', repeat('x', 1001), 'Placar'$$, $$'[]'$$, 'agenda_placar_semanas_texto_check'),
    ('texto de 1000',        $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{}', repeat('x', 1000), 'Placar'$$, $$'[]'$$, 'aceitou'),
    ('linha de 2',           $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{}', 'Placar', 'Pl'$$,              $$'[]'$$, 'agenda_placar_semanas_linha_check'),
    ('linha de 301',         $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{}', 'Placar', repeat('x', 301)$$,  $$'[]'$$, 'agenda_placar_semanas_linha_check'),
    ('período ao contrário', $$date '2031-01-13', date '2031-01-18', date '2031-01-13', 'sombra', '{}', 'Placar', 'Placar'$$,          $$'[]'$$, 'placar_periodo'),
    ('histórico de 11',      $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{}', 'Placar', 'Placar'$$,          'to_jsonb(array(select g from generate_series(1, 11) g))', 'agenda_placar_semanas_historico_check'),
    ('histórico de 10',      $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{}', 'Placar', 'Placar'$$,          'to_jsonb(array(select g from generate_series(1, 10) g))', 'aceitou')
  ) as t(nome, vals, hist, espera) loop
    if pg_temp.recusa(format(v_ins, r.vals, r.hist)) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(format(v_ins, r.vals, r.hist));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B5j agenda_placar_semanas: os certos entram e os 9 errados são recusados, cada um pelo CHECK dele', v_dif is null, v_dif);
  execute format(v_ins, $$date '2031-01-13', date '2031-01-13', date '2031-01-18', 'sombra', '{"ppc": 1}', 'Placar', 'Placar'$$, $$'[]'$$);
  v_sql := $q$update public.agenda_placar_semanas set %s where semana = date '2031-01-13'$q$;
  v_dif := null;
  for r in select * from (values
    ('a semana',                    $$semana = date '2031-01-20', versao = 2, historico = '[{"em": "x"}]'$$,                         'erro P0001: O placar é da semana: a semana e o período não mudam.'),
    ('o período',                   $$de = date '2031-01-14', versao = 2, historico = '[{"em": "x"}]'$$,                             'erro P0001: O placar é da semana: a semana e o período não mudam.'),
    ('números sem versão',          $$numeros = '{"ppc": 2}'$$,                                                                      'erro P0001: O placar só muda inteiro: versão + 1 e o que mudou no histórico.'),
    ('números, versão + 2',         $$numeros = '{"ppc": 2}', versao = 3, historico = '[{"em": "x"}]'$$,                             'erro P0001: O placar só muda inteiro: versão + 1 e o que mudou no histórico.'),
    ('números sem histórico novo',  $$numeros = '{"ppc": 2}', versao = 2$$,                                                          'erro P0001: O placar só muda inteiro: versão + 1 e o que mudou no histórico.'),
    ('números, histórico vazio',    $$numeros = '{"ppc": 2}', versao = 2, historico = '[]'$$,                                        'erro P0001: O placar só muda inteiro: versão + 1 e o que mudou no histórico.'),
    ('só a versão',                 $$versao = 2, historico = '[{"em": "x"}]'$$,                                                     'erro P0001: O placar só muda inteiro: versão + 1 e o que mudou no histórico.'),
    ('o modo, inteiro',             $$modo = 'ligado', versao = 2, historico = '[{"em": "x"}]'$$,                                     'aceitou'),
    ('o texto, inteiro',            $$texto = 'Placar 2', linha = 'Placar 2', calculado_em = now() + interval '1 hour', versao = 2, historico = '[{"em": "x"}]'$$, 'aceitou'),
    ('enviado, sem versão',         $$enviado_em = now()$$,                                                                          'aceitou'),
    ('enviado com versão',          $$enviado_em = now(), versao = 2, historico = '[{"em": "x"}]'$$,                                 'erro P0001: O placar só muda inteiro: versão + 1 e o que mudou no histórico.')
  ) as t(nome, sets, espera) loop
    if pg_temp.recusa(format(v_sql, r.sets)) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || pg_temp.recusa(format(v_sql, r.sets));
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B5k o placar: a semana e o período não mudam; o conteúdo muda inteiro (versão + 1, histórico novo); enviado_em de nulo a um valor, sem versão', v_dif is null, v_dif);
  -- histórico igual, partindo de um não vazio
  execute format(v_sql, $$numeros = '{"ppc": 2}', versao = 2, historico = '[{"em": "y"}]'$$);
  execute format(v_sql, $$enviado_em = now()$$);
  v_res := pg_temp.ok(v_res, 'B5l o placar enviado: enviado_em não muda nem volta a nulo; o MESMO histórico (não vazio) ou um vazio, com conteúdo novo, é recusado; não se apaga',
    pg_temp.recusa(format(v_sql, $$enviado_em = now() + interval '1 day'$$)) = 'erro P0001: O placar enviado não volta: enviado_em vai de nulo a um valor, uma vez.'
    and pg_temp.recusa(format(v_sql, $$enviado_em = null$$)) = 'erro P0001: O placar enviado não volta: enviado_em vai de nulo a um valor, uma vez.'
    and pg_temp.recusa(format(v_sql, $$numeros = '{"ppc": 3}', versao = 3, historico = '[{"em": "y"}]'$$)) = 'erro P0001: O placar só muda inteiro: versão + 1 e o que mudou no histórico.'
    and pg_temp.recusa(format(v_sql, $$numeros = '{"ppc": 3}', versao = 3, historico = '[]'$$)) = 'erro P0001: O placar só muda inteiro: versão + 1 e o que mudou no histórico.'
    and pg_temp.recusa(format(v_sql, $$numeros = '{"ppc": 3}', versao = 3, historico = '[{"em": "y"}, {"em": "z"}]'$$)) = 'aceitou'
    and pg_temp.recusa($$delete from public.agenda_placar_semanas where semana = date '2031-01-13'$$) = c_apaga,
    pg_temp.recusa(format(v_sql, $$enviado_em = now() + interval '1 day'$$)));
  perform pg_temp.gravar(v_res);
end
$b5$;

-- A cascata (R9.12-12): a marcação nasce com a OS aberta; apagar a OS pela tela tem de levar a marcação junto (a FK da OS é cascade, e o gatilho de apagar só vale
-- de fora de gatilho). Uma OS nova, sem alocação (a com alocação vigorada não se apaga, com ou sem marcação: a regra da Fase 2).
do $b5m$
declare
  v_res  jsonb := '[]'::jsonb;
  v_os   uuid := gen_random_uuid();
  v_acao uuid;
  v      text;
begin
  execute pg_temp.acao(null, null) || ' returning id' into v_acao;
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at)
  select v_os, 'OS-G99', so.client_id, so.vessel_id, 'open', 'approved', 'repair', now(), now()
    from public.service_orders so where so.client_id is not null order by so.created_at limit 1;
  insert into public.agenda_marcacoes (acao_id, service_order_id, quem, origem_acao, tipo_acao, classe, de, ate, meios, pessoas, marcada_em, primeiro_inicio, desfecho)
  values (v_acao, v_os, 'gestor', 'vigia', 'criar', 'rv:energia', date '2031-01-07', date '2031-01-07', 2, '{}', now(), now(), 'aberta');
  v := pg_temp.recusa(format('delete from public.service_orders where id = %L', v_os));
  v_res := pg_temp.ok(v_res, 'B5m apagar a OS com marcação (sem alocação) passa: a marcação sai em cascata (WHEN pg_trigger_depth() = 0, R9.12-12)', v = 'aceitou', v);
  delete from public.service_orders where id = v_os;
  v_res := pg_temp.ok(v_res, 'B5n e a marcação foi junto', not exists (select 1 from public.agenda_marcacoes where service_order_id = v_os), null);
  perform pg_temp.gravar(v_res);
end
$b5m$;

-- O SET NULL da ação no tipo de OS (R9.12-12): a ação não se apaga (o gatilho da Fase 2), então o caminho só existe se alguém tirar esse gatilho. Na bancada, desligado
-- por um instante dentro da transação, a FK escreve acao_id nulo e o gatilho do tipo de OS deixa passar. Fora da bancada, PULADO (não se mexe em gatilho em produção).
do $b5o$
declare
  v_res  jsonb := '[]'::jsonb;
  v_acao uuid;
  v      text;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B5o o SET NULL da ação no tipo de OS', true, 'PULADO: só na bancada'));
    return;
  end if;
  insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values (date '2031-01-07', false, 'vigia', 'mover', 'Ação de teste do B5o') returning id into v_acao;
  insert into public.agenda_tipos_os (classe, calculado_em, acao_id) values ('barco:teste', now(), v_acao);
  alter table public.agenda_acoes disable trigger agenda_acoes_nao_apaga;
  v := pg_temp.recusa(format('delete from public.agenda_acoes where id = %L', v_acao));
  delete from public.agenda_acoes where id = v_acao;
  alter table public.agenda_acoes enable trigger agenda_acoes_nao_apaga;
  v_res := pg_temp.ok(v_res, 'B5o o ON DELETE SET NULL de agenda_tipos_os.acao_id passa pelo gatilho do tipo de OS (só a classe é fixa)',
    v = 'aceitou' and (select t.acao_id is null from public.agenda_tipos_os t where t.classe = 'barco:teste'), v);
  perform pg_temp.gravar(v_res);
end
$b5o$;

-- A forma das 3 tabelas (§4.3 e R9.4-2), coluna a coluna: o tipo, o NOT NULL e o DEFAULT. Um DEFAULT a mais ou um NOT NULL a menos não aparece em nenhum INSERT do B5.
with esperado(tabela, coluna, tipo, nn, padrao) as (values
  ('agenda_marcacoes', 'acao_id', 'uuid', true, null), ('agenda_marcacoes', 'service_order_id', 'uuid', true, null), ('agenda_marcacoes', 'quem', 'text', true, null),
  ('agenda_marcacoes', 'origem_acao', 'text', true, null), ('agenda_marcacoes', 'tipo_acao', 'text', true, null), ('agenda_marcacoes', 'classe', 'text', true, null),
  ('agenda_marcacoes', 'duracao_fonte', 'text', false, null), ('agenda_marcacoes', 'suposicoes', 'text[]', true, '''{}''::text[]'),
  ('agenda_marcacoes', 'de', 'date', true, null), ('agenda_marcacoes', 'ate', 'date', true, null), ('agenda_marcacoes', 'meios', 'smallint', true, null),
  ('agenda_marcacoes', 'pessoas', 'uuid[]', true, null), ('agenda_marcacoes', 'marcada_em', 'timestamp with time zone', true, null),
  ('agenda_marcacoes', 'primeiro_inicio', 'timestamp with time zone', true, null), ('agenda_marcacoes', 'aprovada_em', 'timestamp with time zone', false, null),
  ('agenda_marcacoes', 'zona', 'text', false, null), ('agenda_marcacoes', 'degrau', 'text', false, null), ('agenda_marcacoes', 'desfecho', 'text', false, null),
  ('agenda_marcacoes', 'ajustes', 'text[]', true, '''{}''::text[]'), ('agenda_marcacoes', 'desfecho_em', 'timestamp with time zone', false, null),
  ('agenda_marcacoes', 'desfecho_acao_id', 'uuid', false, null), ('agenda_marcacoes', 'conferida', 'boolean', true, 'false'),
  ('agenda_marcacoes', 'versao', 'smallint', true, '1'), ('agenda_marcacoes', 'historico', 'jsonb', true, '''[]''::jsonb'),
  ('agenda_tipos_os', 'classe', 'text', true, null), ('agenda_tipos_os', 'nivel', 'text', true, '''sozinho''::text'), ('agenda_tipos_os', 'teria', 'text', false, null),
  ('agenda_tipos_os', 'n', 'smallint', true, '0'), ('agenda_tipos_os', 'corrigidas', 'smallint', true, '0'), ('agenda_tipos_os', 'aceitas_seguidas', 'smallint', true, '0'),
  ('agenda_tipos_os', 'amostra', 'jsonb', true, '''[]''::jsonb'), ('agenda_tipos_os', 'desde', 'timestamp with time zone', false, null),
  ('agenda_tipos_os', 'acao_id', 'uuid', false, null), ('agenda_tipos_os', 'travado_ate', 'date', false, null),
  ('agenda_tipos_os', 'calculado_em', 'timestamp with time zone', true, null), ('agenda_tipos_os', 'texto', 'text', false, null),
  ('agenda_tipos_os', 'historico', 'jsonb', true, '''[]''::jsonb'),
  ('agenda_placar_semanas', 'semana', 'date', true, null), ('agenda_placar_semanas', 'de', 'date', true, null), ('agenda_placar_semanas', 'ate', 'date', true, null),
  ('agenda_placar_semanas', 'modo', 'text', true, null), ('agenda_placar_semanas', 'numeros', 'jsonb', true, null), ('agenda_placar_semanas', 'texto', 'text', true, null),
  ('agenda_placar_semanas', 'linha', 'text', true, null), ('agenda_placar_semanas', 'calculado_em', 'timestamp with time zone', true, null),
  ('agenda_placar_semanas', 'enviado_em', 'timestamp with time zone', false, null), ('agenda_placar_semanas', 'versao', 'smallint', true, '1'),
  ('agenda_placar_semanas', 'historico', 'jsonb', true, '''[]''::jsonb')),
real(tabela, coluna, tipo, nn, padrao) as (
  select c.relname::text, a.attname::text, format_type(a.atttypid, a.atttypmod), a.attnotnull, pg_get_expr(d.adbin, d.adrelid)
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where c.relnamespace = 'public'::regnamespace and c.relname in ('agenda_marcacoes', 'agenda_tipos_os', 'agenda_placar_semanas')
     and a.attnum > 0 and not a.attisdropped)
insert into _resultado
select 'B5p as 3 tabelas coluna a coluna (48): o tipo, o NOT NULL e o DEFAULT da §4.3 (conferida not null default false, R9.4-2)',
       count(*) filter (where e.coluna is null or r.coluna is null or e.tipo <> r.tipo or e.nn <> r.nn or e.padrao is distinct from r.padrao) = 0 and count(*) = 48,
       string_agg(format('%s.%s: %s/%s/%s', coalesce(e.tabela, r.tabela), coalesce(e.coluna, r.coluna), r.tipo, r.nn, coalesce(r.padrao, '—')), '; ')
         filter (where e.coluna is null or r.coluna is null or e.tipo <> r.tipo or e.nn <> r.nn or e.padrao is distinct from r.padrao)
  from esperado e full join real r on r.tabela = e.tabela and r.coluna = e.coluna;

-- As chaves das 3 (§4.3, R9.12-12): a marcação é uma por (ação, OS); a ação e a ação do desfecho não saem debaixo dela (restrict), a OS leva junto (cascade); a ação do nível
-- no tipo de OS vira nula (set null). O B5m e o B5o provam a cascata e o SET NULL andando; aqui, o que o catálogo guarda.
with esperado(tabela, tipo, colunas, ref, apaga) as (values
  ('agenda_marcacoes', 'p', 'acao_id,service_order_id', null, null),
  ('agenda_marcacoes', 'f', 'acao_id', 'agenda_acoes', 'r'),
  ('agenda_marcacoes', 'f', 'service_order_id', 'service_orders', 'c'),
  ('agenda_marcacoes', 'f', 'desfecho_acao_id', 'agenda_acoes', 'r'),
  ('agenda_tipos_os', 'p', 'classe', null, null),
  ('agenda_tipos_os', 'f', 'acao_id', 'agenda_acoes', 'n'),
  ('agenda_placar_semanas', 'p', 'semana', null, null)),
real(tabela, tipo, colunas, ref, apaga) as (
  select t.relname::text, k.contype::text,
         (select string_agg(a.attname::text, ',' order by u.o) from unnest(k.conkey) with ordinality u(n, o) join pg_attribute a on a.attrelid = k.conrelid and a.attnum = u.n),
         nullif(k.confrelid, 0)::regclass::text, nullif(k.confdeltype::text, ' ')
    from pg_constraint k join pg_class t on t.oid = k.conrelid
   where t.relnamespace = 'public'::regnamespace and t.relname in ('agenda_marcacoes', 'agenda_tipos_os', 'agenda_placar_semanas') and k.contype in ('p', 'f'))
insert into _resultado
select 'B5r as chaves: a marcação é uma por (ação, OS); ação e ação do desfecho restrict, OS cascade; a ação do tipo de OS set null; a semana e a classe são a chave',
       count(*) filter (where e.tabela is null or r.tabela is null or e.ref is distinct from r.ref or e.apaga is distinct from r.apaga) = 0 and count(*) = 7,
       string_agg(format('%s %s (%s) → %s %s', coalesce(e.tabela, r.tabela), coalesce(e.tipo, r.tipo), coalesce(e.colunas, r.colunas), r.ref, r.apaga), '; ')
         filter (where e.tabela is null or r.tabela is null or e.ref is distinct from r.ref or e.apaga is distinct from r.apaga)
  from esperado e full join real r on r.tabela = e.tabela and r.tipo = e.tipo and r.colunas = e.colunas;

-- Os 2 índices de agenda_marcacoes (§4.3): a amostra por classe do gestor (as mais novas primeiro) e as abertas por OS.
insert into _resultado
select 'B5q os 2 índices de agenda_marcacoes: (classe, desfecho_em desc) só do gestor e (service_order_id) só das abertas',
       count(*) = 2
       and bool_and(case i.indexname
                      when 'agenda_marcacoes_classe' then i.indexdef = 'CREATE INDEX agenda_marcacoes_classe ON public.agenda_marcacoes USING btree (classe, desfecho_em DESC) WHERE (quem = ''gestor''::text)'
                      when 'agenda_marcacoes_abertas' then i.indexdef = 'CREATE INDEX agenda_marcacoes_abertas ON public.agenda_marcacoes USING btree (service_order_id) WHERE (desfecho = ''aberta''::text)'
                      else false end),
       string_agg(i.indexdef, ' | ')
  from pg_indexes i
 where i.schemaname = 'public' and i.tablename = 'agenda_marcacoes' and i.indexname <> 'agenda_marcacoes_pkey';

-- ── B6. As peças do porquê ───────────────────────────────────────────────────────────────────────────
do $b6$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  r     record;
  c_a   constant text := 'aaaaaaaa-0000-4000-8000-000000000001';
  c_b   constant text := 'bbbbbbbb-0000-4000-8000-000000000002';
  m     text := '{"payee_id": "%s", "dia": "%s", "turno": "%s", "presenca": "%s"}';
begin
  -- _agenda_degrau: os 8 casos da §8.3 e as combinações (antes, depois, fim de antes, fim de depois, prometido)
  for r in select * from (values
    ('novo: sem antes',                         '[]', format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), null::date, null::date, null::date, null),
    ('novo: antes nulo',                        null, format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), null, null, null, null),
    ('tirou',                                   format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), '[]', null, null, null, 'tirou'),
    ('tirou: depois nulo',                      format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), null, null, null, null, 'tirou'),
    ('pessoa',                                  format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_b, '2026-11-24', 'manha', 'turno')), null, null, null, 'pessoa'),
    ('pessoa: dupla vira 1 no mesmo meio-dia',  format('[%s, %s]', format(m, c_a, '2026-11-24', 'manha', 'turno'), format(m, c_b, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), null, null, null, 'pessoa'),
    ('turno',                                   format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-24', 'tarde', 'turno')), null, null, null, 'turno'),
    ('turno e pessoa: vale o turno (o mais caro)', format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_b, '2026-11-24', 'tarde', 'turno')), null, null, null, 'turno'),
    ('dia, na semana do fim de antes',          format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-27', 'manha', 'turno')), null, null, null, 'dia'),
    ('dia: até o domingo da semana (29/11)',    format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-28', 'manha', 'turno')), null, date '2026-11-29', null, 'dia'),
    ('data: na semana seguinte, sem prometido', format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-30', 'manha', 'turno')), null, null, null, 'data'),
    ('antecipar fica no dia',                   format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-17', 'manha', 'turno')), null, null, null, 'dia'),
    ('dia: o fim dentro do prometido, noutra semana', format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-12-01', 'manha', 'turno')), null, null, date '2026-12-04', 'dia'),
    ('data: o fim depois do prometido, na mesma semana', format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-26', 'manha', 'turno')), null, null, date '2026-11-25', 'data'),
    ('o fim dado vale sobre o último dia',      format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-25', 'manha', 'turno')), date '2026-11-24', date '2026-12-01', null, 'data'),
    ('o fim de antes dado muda a semana',       format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-11-30', 'manha', 'turno')), date '2026-11-30', null, null, 'dia'),
    ('abrir e fechar do dono não contam',       format('[%s, %s, %s]', format(m, c_a, '2026-11-24', 'manha', 'turno'), format(m, c_b, '2026-11-24', 'manha', 'abertura'), format(m, c_b, '2026-11-24', 'tarde', 'fechamento')),
                                                format('[%s, %s, %s]', format(m, c_a, '2026-11-24', 'manha', 'turno'), format(m, c_b, '2026-11-25', 'manha', 'abertura'), format(m, c_b, '2026-11-25', 'tarde', 'fechamento')), null, null, null, null),
    ('só abrir e fechar antes = novo',          format('[%s]', format(m, c_b, '2026-11-24', 'manha', 'abertura')), format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), null, null, null, null),
    ('sem a chave presenca = turno',            format('[{"payee_id": "%s", "dia": "2026-11-24", "turno": "manha"}]', c_a), format('[{"payee_id": "%s", "dia": "2026-11-24", "turno": "manha"}]', c_b), null, null, null, 'pessoa'),
    ('iguais, em outra ordem: nada mudou',      format('[%s, %s]', format(m, c_a, '2026-11-24', 'manha', 'turno'), format(m, c_a, '2026-11-24', 'tarde', 'turno')), format('[%s, %s]', format(m, c_a, '2026-11-24', 'tarde', 'turno'), format(m, c_a, '2026-11-24', 'manha', 'turno')), null, null, null, null),
    ('mais um meio-dia no mesmo dia = turno',   format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s, %s]', format(m, c_a, '2026-11-24', 'manha', 'turno'), format(m, c_a, '2026-11-24', 'tarde', 'turno')), null, null, null, 'turno'),
    ('antes que não é lista = sem antes',       '{}', format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), null, null, null, null),
    ('depois que não é lista = tirou',          format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), '{"alocacoes": []}', null, null, null, 'tirou'),
    ('sem fim, o do depois é o ÚLTIMO dia dele',  format('[%s]', format(m, c_a, '2026-11-24', 'manha', 'turno')), format('[%s, %s]', format(m, c_a, '2026-11-27', 'manha', 'turno'), format(m, c_a, '2026-11-30', 'manha', 'turno')), null, null, null, 'data'),
    ('sem fim, o do antes é o ÚLTIMO dia dele',   format('[%s, %s]', format(m, c_a, '2026-11-24', 'manha', 'turno'), format(m, c_a, '2026-11-30', 'manha', 'turno')), format('[%s]', format(m, c_a, '2026-12-01', 'manha', 'turno')), null, null, null, 'dia')
  ) as t(nome, antes, depois, fim_a, fim_d, prometido, espera) loop
    if public._agenda_degrau(r.antes::jsonb, r.depois::jsonb, r.fim_a, r.fim_d, r.prometido) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || coalesce(public._agenda_degrau(r.antes::jsonb, r.depois::jsonb, r.fim_a, r.fim_d, r.prometido), 'nulo');
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B6a _agenda_degrau: novo, tirou, pessoa, turno, dia, data, sem prometido, com prometido, abrir e fechar não contam, combinações, objeto no lugar da lista, o fim de cada lado sem o dado (25 casos)', v_dif is null, v_dif);

  -- _agenda_quem_marcou
  v_dif := null;
  for r in select * from (values
    ('alocação do dono',       'vigia',      'dono',    'dono'),
    ('ação do assistente',     'assistente', 'motor',   'dono'),
    ('ação da tela',           'tela',       null,      'dono'),
    ('ação do dono',           'dono',       'motor',   'dono'),
    ('vigia',                  'vigia',      'motor',   'gestor'),
    ('motor',                  'motor',      null,      'gestor'),
    ('aprovação',              'aprovacao',  'motor',   'gestor'),
    ('a do cliente é gestor',  'cliente',    'cliente', 'gestor'),
    ('os dois nulos',          null,         null,      'gestor')
  ) as t(nome, oa, oal, espera) loop
    if public._agenda_quem_marcou(r.oa, r.oal) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || coalesce(public._agenda_quem_marcou(r.oa, r.oal), 'nulo');
    end if;
  end loop;
  -- quem marcou lê o parâmetro: tirar a tela das origens do dono faz a tela virar gestor
  update public.agenda_config set origens_do_dono = '{dono,assistente}' where id;
  if public._agenda_quem_marcou('tela') <> 'gestor' or public._agenda_quem_marcou('assistente') <> 'dono' then v_dif := coalesce(v_dif || ' | ', '') || 'não lê origens_do_dono'; end if;
  update public.agenda_config set origens_do_dono = '{dono,assistente,tela}' where id;
  v_res := pg_temp.ok(v_res, 'B6b _agenda_quem_marcou: dono pela alocação ou pela origem da ação (origens_do_dono), gestor no resto e com os dois nulos; lê o parâmetro', v_dif is null, v_dif);

  -- _agenda_zona_mais_severa
  v_res := pg_temp.ok(v_res, 'B6c _agenda_zona_mais_severa: travada > firme > livre; nula, vazia, só nulos e só valor de fora = nula (R9.12-2)',
    public._agenda_zona_mais_severa(array['livre', 'travada', 'firme']) = 'travada'
    and public._agenda_zona_mais_severa(array['livre', null, 'firme']) = 'firme'
    and public._agenda_zona_mais_severa(array['livre', 'livre']) = 'livre'
    and public._agenda_zona_mais_severa(null) is null
    and public._agenda_zona_mais_severa('{}') is null
    and public._agenda_zona_mais_severa(array[null, null]::text[]) is null
    and public._agenda_zona_mais_severa(array['morna']) is null, null);

  -- _agenda_suposicoes_validas
  v_dif := null;
  for r in select * from (values
    ('nula',                     null,                                                                                     true),
    ('vazia',                    '[]',                                                                                     true),
    ('as 12, cada uma uma vez',  (select jsonb_agg(jsonb_build_object('codigo', c, 'detalhe', '{}'::jsonb)) from unnest(array['prazo_padrao_peca', 'quanto_falta_padrao', 'local_suposto', 'bem_disponivel', 'disponibilidade_suposta', 'compra_interna_padrao', 'sinal_a_cobrar', 'duracao_orcamento', 'uma_pessoa', 'peca_nao_segura', 'sem_peca', 'dono_abre_fecha']) c)::text, true),
    ('13 itens',                 (select jsonb_agg(jsonb_build_object('codigo', 'sem_peca', 'detalhe', '{}'::jsonb)) from generate_series(1, 13))::text, false),
    ('objeto',                   '{}',                                                                                     false),
    ('texto',                    '"sem_peca"',                                                                             false),
    ('item que não é objeto',    '["sem_peca"]',                                                                           false),
    ('item sem código',          '[{"detalhe": {}}]',                                                                      false),
    ('código número',            '[{"codigo": 1, "detalhe": {}}]',                                                         false),
    ('código de fora',           '[{"codigo": "dito", "detalhe": {}}]',                                                    false),
    ('sem detalhe',              '[{"codigo": "sem_peca"}]',                                                               false),
    ('detalhe lista',            '[{"codigo": "sem_peca", "detalhe": []}]',                                                false),
    ('detalhe nulo',             '[{"codigo": "sem_peca", "detalhe": null}]',                                              false),
    ('com chave a mais',         '[{"codigo": "sem_peca", "detalhe": {}, "texto": "x"}]',                                  true)
  ) as t(nome, p, espera) loop
    if public._agenda_suposicoes_validas(r.p::jsonb) is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || coalesce(public._agenda_suposicoes_validas(r.p::jsonb)::text, 'nulo');
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B6d _agenda_suposicoes_validas: nula e [] passam; até 12 objetos com codigo da lista e detalhe objeto; o resto não (14 casos)', v_dif is null, v_dif);

  -- _agenda_duracao_fonte_texto (§6.1, byte a byte; R9.3-1)
  v_dif := null;
  for r in select * from (values
    ('dono',                        public._agenda_duracao_fonte_texto('dono', 2, null),            'você disse 2 dias'),
    ('aceita',                      public._agenda_duracao_fonte_texto('aceita', 2, 1528),          '2 dias (a minha estimativa, que você aceitou)'),
    ('orçamento',                   public._agenda_duracao_fonte_texto('orcamento', 3, null),       '3 dias pelo orçamento (estimativa minha)'),
    ('orçamento com mão de obra',   public._agenda_duracao_fonte_texto('orcamento', 3, 2300),       '3 dias pelo orçamento (R$ 2.300 de mão de obra; estimativa minha)'),
    ('orçamento, mão de obra 0',    public._agenda_duracao_fonte_texto('orcamento', 3, 0),          '3 dias pelo orçamento (estimativa minha)'),
    ('mão de obra arredondada',     public._agenda_duracao_fonte_texto('orcamento', 2, 1999.6),     '2 dias pelo orçamento (R$ 2.000 de mão de obra; estimativa minha)'),
    ('sugerida',                    public._agenda_duracao_fonte_texto('sugerida', 3, null),        'uns 3 dias (estimativa minha, só para reservar)'),
    ('sugerida de 2',               public._agenda_duracao_fonte_texto('sugerida', 2, null),        'uns 2 dias (estimativa minha, só para reservar)'),
    ('sugerida de 1 (sem "uns")',   public._agenda_duracao_fonte_texto('sugerida', 1, null),        '1 dia (estimativa minha, só para reservar)'),
    ('sugerida de 1,5',             public._agenda_duracao_fonte_texto('sugerida', 1.5, null),      '1,5 dia (estimativa minha, só para reservar)'),
    ('dono, meio dia',              public._agenda_duracao_fonte_texto('dono', 0.5, null),          'você disse meio dia'),
    ('a frase do viés vale (AG7-33)', public._agenda_duracao_fonte_texto('dono', 3, null, 'Você disse 3 dias; contei 3,5 (nos serviços assim, os seus dias levaram 1,2×; 5 OS).'),
                                    'Você disse 3 dias; contei 3,5 (nos serviços assim, os seus dias levaram 1,2×; 5 OS).'),
    ('frase do viés vazia não vale', public._agenda_duracao_fonte_texto('dono', 3, null, '  '),     'você disse 3 dias'),
    ('frase do viés nula não vale', public._agenda_duracao_fonte_texto('aceita', 3, null, null),    '3 dias (a minha estimativa, que você aceitou)')
  ) as t(nome, v, espera) loop
    if r.v is distinct from r.espera then v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || coalesce(r.v, 'nulo'); end if;
  end loop;
  if public._agenda_duracao_fonte_texto('dono', null, null) is not null then v_dif := coalesce(v_dif || ' | ', '') || 'sem dias'; end if;
  if public._agenda_duracao_fonte_texto('dono', 0, null) is not null then v_dif := coalesce(v_dif || ' | ', '') || '0 dias'; end if;
  if public._agenda_duracao_fonte_texto('chute', 2, null) is not null then v_dif := coalesce(v_dif || ' | ', '') || 'fonte de fora'; end if;
  if public._agenda_duracao_fonte_texto(null, 2, null) is not null then v_dif := coalesce(v_dif || ' | ', '') || 'fonte nula'; end if;
  v_res := pg_temp.ok(v_res, 'B6e _agenda_duracao_fonte_texto: as 4 fontes da §6.1 byte a byte, a mão de obra, a frase do viés (R9.3-1); sem dias, 0 ou fonte de fora = nula', v_dif is null, v_dif);

  -- _agenda_suposicao_texto (§6.1, byte a byte; R9.3-7: o local pelo nome, com a preposição)
  v_dif := null;
  for r in select * from (values
    ('peça, 1',                 public._agenda_suposicao_texto('prazo_padrao_peca', '{"itens": ["Cerbo"], "du": 7}'),                    'Cerbo: contei 7 dias úteis de entrega (não sei de quem comprar)'),
    ('peça, 2',                 public._agenda_suposicao_texto('prazo_padrao_peca', '{"itens": ["Cerbo", "Cabo"], "du": 7}'),            'Cerbo e mais 1 peça: contei 7 dias úteis de entrega (sem fornecedor)'),
    ('peça, 3',                 public._agenda_suposicao_texto('prazo_padrao_peca', '{"itens": ["Cerbo", "Cabo", "Fusível"], "du": 1}'), 'Cerbo e mais 2 peças: contei 1 dia útil de entrega (sem fornecedor)'),
    ('peça, sem item',          public._agenda_suposicao_texto('prazo_padrao_peca', '{"itens": [], "du": 7}'),                           'contei 7 dias úteis de entrega (não sei de quem comprar)'),
    ('quanto falta',            public._agenda_suposicao_texto('quanto_falta_padrao', '{"dias": 1}'),                                    'contei que falta 1 dia (você não disse quanto falta)'),
    ('quanto falta, meio dia',  public._agenda_suposicao_texto('quanto_falta_padrao', '{"dias": 0.5}'),                                  'contei que falta meio dia (você não disse quanto falta)'),
    ('local, o pátio',          public._agenda_suposicao_texto('local_suposto', '{"local": "na MP Motorhomes", "fonte": "patio"}'),     'na MP Motorhomes (supus pelo tipo do bem)'),
    ('local, a cidade',         public._agenda_suposicao_texto('local_suposto', '{"local": "em Balneário Camboriú", "fonte": "cidade"}'), 'em Balneário Camboriú (supus pela cidade do cliente)'),
    ('local, o cadastro',       public._agenda_suposicao_texto('local_suposto', '{"local": "na Marina Itajaí", "fonte": "bem", "bem": "barco"}'), 'na Marina Itajaí (supus pelo cadastro do barco)'),
    ('local, sem o bem',        public._agenda_suposicao_texto('local_suposto', '{"local": "na Marina Itajaí", "fonte": "bem"}'),       'na Marina Itajaí (supus pelo cadastro do bem)'),
    ('bem disponível',          public._agenda_suposicao_texto('bem_disponivel', '{"bem": "barco"}'),                                    'o barco livre nesses dias (ninguém disse que está em uso)'),
    ('bem disponível, sem bem', public._agenda_suposicao_texto('bem_disponivel', '{}'),                                                  'o barco livre nesses dias (ninguém disse que está em uso)'),
    ('disponibilidade, 1',      public._agenda_suposicao_texto('disponibilidade_suposta', '{"pessoas": ["Mateus"]}'),                    'Mateus: contei os dias da última resposta'),
    ('disponibilidade, 2',      public._agenda_suposicao_texto('disponibilidade_suposta', '{"pessoas": ["Mateus", "Vinicius"]}'),        'Mateus e Vinicius: contei os dias da última resposta'),
    ('disponibilidade, 3',      public._agenda_suposicao_texto('disponibilidade_suposta', '{"pessoas": ["Mateus", "Vinicius", "Alex"]}'), 'Mateus, Vinicius e Alex: contei os dias da última resposta'),
    ('disponibilidade, nome em branco fica de fora', public._agenda_suposicao_texto('disponibilidade_suposta', '{"pessoas": ["Mateus", " "]}'), 'Mateus: contei os dias da última resposta'),
    ('compra interna, 1',       public._agenda_suposicao_texto('compra_interna_padrao', '{"du": 1}'),                                    'você compra em até 1 dia útil depois de aprovado'),
    ('compra interna, 2',       public._agenda_suposicao_texto('compra_interna_padrao', '{"du": 2}'),                                    'você compra em até 2 dias úteis depois de aprovado'),
    ('sinal',                   public._agenda_suposicao_texto('sinal_a_cobrar', '{}'),                                                  'o sinal ainda não foi pago: marquei e lembro você de cobrar'),
    ('uma pessoa',              public._agenda_suposicao_texto('uma_pessoa', '{}'),                                                      '1 pessoa (dupla só quando o serviço pede)'),
    ('peça pequena, 3',         public._agenda_suposicao_texto('peca_nao_segura', '{"n": 3, "limiar": 300}'),                            '3 itens pequenos ficam para separar na véspera (abaixo de R$ 300)'),
    ('peça pequena, 1',         public._agenda_suposicao_texto('peca_nao_segura', '{"n": 1, "limiar": 1500}'),                           '1 item pequeno fica para separar na véspera (abaixo de R$ 1.500)'),
    ('sem peça',                public._agenda_suposicao_texto('sem_peca', '{}'),                                                        'sem peça a comprar (o orçamento não tem material)'),
    ('abre e fecha',            public._agenda_suposicao_texto('dono_abre_fecha', null),                                                 'você abre e fecha')
  ) as t(nome, v, espera) loop
    if r.v is distinct from r.espera then v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || coalesce(r.v, 'nulo'); end if;
  end loop;
  -- sem o número que a frase precisa, nula (não se afirma o que não foi contado); duracao_orcamento vai pela fonte; código de fora = nula
  for r in select * from (values
    ('peça sem du',             public._agenda_suposicao_texto('prazo_padrao_peca', '{"itens": ["Cerbo"]}')),
    ('quanto falta sem dias',   public._agenda_suposicao_texto('quanto_falta_padrao', '{}')),
    ('local sem local',         public._agenda_suposicao_texto('local_suposto', '{"fonte": "patio"}')),
    ('local vazio',             public._agenda_suposicao_texto('local_suposto', '{"local": " ", "fonte": "patio"}')),
    ('disponibilidade sem nome', public._agenda_suposicao_texto('disponibilidade_suposta', '{"pessoas": []}')),
    ('compra sem du',           public._agenda_suposicao_texto('compra_interna_padrao', '{}')),
    ('peça pequena sem n',      public._agenda_suposicao_texto('peca_nao_segura', '{"limiar": 300}')),
    ('peça pequena com 0',      public._agenda_suposicao_texto('peca_nao_segura', '{"n": 0, "limiar": 300}')),
    ('peça pequena sem limiar', public._agenda_suposicao_texto('peca_nao_segura', '{"n": 2}')),
    ('duração do orçamento',    public._agenda_suposicao_texto('duracao_orcamento', '{"dias": 3, "mo": 2300}')),
    ('código de fora',          public._agenda_suposicao_texto('dito', '{}')),
    ('código nulo',             public._agenda_suposicao_texto(null, '{}'))
  ) as t(nome, v) loop
    if r.v is not null then v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || r.v; end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B6f _agenda_suposicao_texto: os 11 códigos com texto da §6.1 byte a byte (24 casos); sem o número, duracao_orcamento e código de fora = nula (12 casos)', v_dif is null, v_dif);

  -- _agenda_criterio_texto (§6.1 e R9.5-5: os 10 do CHECK do 7c) e _agenda_degrau_texto
  v_dif := null;
  for r in select * from (values
    ('dono_disse', 'quem você disse'), ('lider', 'o responsável do serviço'), ('habilidade', 'quem sabe fazer'), ('continuidade', 'quem já estava no serviço'),
    ('local', 'quem já estava no lugar'), ('carga', 'quem tinha a semana mais livre'), ('custo', 'o mais em conta para o serviço'), ('unico', 'só ele estava livre'),
    ('empate', null), ('presenca_do_dono', null), ('dito', null), (null, null)
  ) as t(c, espera) loop
    if public._agenda_criterio_texto(r.c) is distinct from r.espera then v_dif := coalesce(v_dif || ' | ', '') || coalesce(r.c, 'nulo') || ': ' || coalesce(public._agenda_criterio_texto(r.c), 'nulo'); end if;
  end loop;
  -- os 10 do CHECK vivo têm caso aqui: um critério novo no 7c sem texto decidido reprova
  if (select array_agg(x order by x) from unnest(pg_temp.lista('public.agenda_alocacoes', 'agenda_alocacoes_criterio_check')) x)
     <> array['carga', 'continuidade', 'custo', 'dono_disse', 'empate', 'habilidade', 'lider', 'local', 'presenca_do_dono', 'unico'] then
    v_dif := coalesce(v_dif || ' | ', '') || 'a lista do 7c mudou: ' || array_to_string(pg_temp.lista('public.agenda_alocacoes', 'agenda_alocacoes_criterio_check'), ',');
  end if;
  v_res := pg_temp.ok(v_res, 'B6g _agenda_criterio_texto: os 8 com texto (dono_disse = "quem você disse"; lider e unico do R9.5-5); empate, presenca_do_dono, de fora e nulo = nula; a lista do 7c é a de 10', v_dif is null, v_dif);
  v_dif := null;
  for r in select * from (values
    ('pessoa', 'troquei só a pessoa'), ('turno', 'troquei só o turno'), ('dia', 'mudei o dia, dentro da semana combinada'), ('data', 'a data de fim andou'),
    ('tirou', 'tirei da agenda'), ('pior', null), (null, null)
  ) as t(c, espera) loop
    if public._agenda_degrau_texto(r.c) is distinct from r.espera then v_dif := coalesce(v_dif || ' | ', '') || coalesce(r.c, 'nulo') || ': ' || coalesce(public._agenda_degrau_texto(r.c), 'nulo'); end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B6h _agenda_degrau_texto: os 5 da §6.1; de fora e nulo = nula', v_dif is null, v_dif);
  perform pg_temp.gravar(v_res);
end
$b6$;

-- ── B7. A fixture: a forma real (R9.12-8) e as peças sobre ela ───────────────────────────────────────
do $b7$
declare
  v_res jsonb := '[]'::jsonb;
  v_n   int;
  a     public.agenda_acoes;
  c_os  constant uuid := md5('7g:os:g0')::uuid;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B7a a fixture', true, 'PULADO: sem agenda_teste.fase7g (rode pela bancada)'));
    return;
  end if;
  execute current_setting('agenda_teste.fase7g');
  v_n := (select count(*) from public.service_orders);
  select * into a from public.agenda_acoes where id = md5('7g:acao:g0')::uuid;
  v_res := pg_temp.ok(v_res, 'B7a a ação na forma de produção: criar da vigia, antes {alocacoes: [], fim: nulo}, depois com as 6 chaves de cada alocação (wf7g_p1_acoes)',
    a.tipo = 'criar' and a.origem = 'vigia' and a.executada and a.antes -> 'alocacoes' = '[]' and a.antes ? 'fim'
    and (select bool_and(e ?& array['alocacao_id', 'payee_id', 'nome', 'dia', 'turno', 'presenca']) from jsonb_array_elements(a.depois -> 'alocacoes') e)
    and not exists (select 1 from public.os_planejamento where service_order_id = c_os), a.depois::text);
  v_res := pg_temp.ok(v_res, 'B7b as 2 alocações na forma de produção: publicadas, fonte orcamento, critério unico (R9.5-6), suposições NULAS (de antes da 7g), motivos em texto',
    (select count(*) = 2 and bool_and(l.estado = 'publicada' and l.duracao_fonte = 'orcamento' and l.criterio = 'unico' and l.suposicoes is null and l.degrau is null
                                      and jsonb_typeof(l.motivos -> 0) = 'string')
       from public.agenda_alocacoes l where l.service_order_id = c_os), null);
  v_res := pg_temp.ok(v_res, 'B7c as peças sobre a forma real: a criação é nova (degrau nulo); cancelar tudo seria tirou; quem marcou é o gestor; o critério e a fonte em palavras',
    public._agenda_degrau(a.antes -> 'alocacoes', a.depois -> 'alocacoes', (a.antes ->> 'fim')::date, (a.depois ->> 'fim')::date, null) is null
    and public._agenda_degrau(a.depois -> 'alocacoes', '[]', (a.depois ->> 'fim')::date, null, null) = 'tirou'
    and (select bool_and(public._agenda_quem_marcou(a.origem, l.origem) = 'gestor'
                         and public._agenda_criterio_texto(l.criterio) = 'só ele estava livre'
                         and public._agenda_duracao_fonte_texto(l.duracao_fonte, 1, null) = '1 dia pelo orçamento (estimativa minha)')
           from public.agenda_alocacoes l where l.service_order_id = c_os), null);
  execute current_setting('agenda_teste.fase7g');
  v_res := pg_temp.ok(v_res, 'B7d carregar a fixture 2× = 1×', (select count(*) from public.service_orders) = v_n
    and (select count(*) from public.agenda_alocacoes where service_order_id = c_os) = 2, null);
  perform pg_temp.gravar(v_res);
end
$b7$;

-- ── B8. Nada muda de comportamento ───────────────────────────────────────────────────────────────────
do $b8$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  c_novas constant text[] := array['_agenda_suposicoes_validas', '_agenda_quem_marcou', '_agenda_degrau', '_agenda_degrau_texto', '_agenda_zona_mais_severa',
    '_agenda_duracao_fonte_texto', '_agenda_suposicao_texto', '_agenda_criterio_texto', '_agenda_marcacoes_so_muda', '_agenda_tipos_os_so_muda', '_agenda_placar_so_muda',
    -- FASE 7g: (7g P2, 20261112100100) os 2 gatilhos do porquê leem modo_porque e chamam o CHECK das suposições, o degrau e a zona mais severa
    '_agenda_alocacoes_porque', '_agenda_acoes_porque',
    -- FASE 7g: fim
    -- FASE 7g: (7g P3, 20261112100200) as leituras de como pensei e do porquê leem modo_explicar e os parâmetros dele e chamam as peças do P1
    '_agenda_porque_fonte', '_agenda_porque_linha', '_agenda_porque_da_os', 'agenda_como_pensei'
    -- FASE 7g: fim
    ];
begin
  -- nenhuma função de antes lê as colunas nem chama as funções novas. Quem vier depois nesta etapa: a função recriada leva a marca -- FASE 7g (sai daqui sozinha); a função NOVA,
  -- sem marca, entra em c_novas, pelo nome.
  select string_agg(p.proname, ',' order by p.proname) into v_dif
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname <> all (c_novas)
     and p.prosrc ~ '_agenda_(suposicoes_validas|quem_marcou|degrau|degrau_texto|zona_mais_severa|duracao_fonte_texto|suposicao_texto|criterio_texto|marcacoes_so_muda|tipos_os_so_muda|placar_so_muda)\(|modo_porque|modo_explicar|modo_placar|modo_rebaixar|porque_motivos_max|origens_do_dono|livre_semanas|como_pensei_|correcao_janela_du|rebaixar_|voltar_n|explicar_hora|placar_janela|placar_semanas_hist|marcacoes_desde|placar_min_linhas|explicar_tempo_max|agenda_marcacoes|agenda_tipos_os|agenda_placar_semanas'
     and not (p.prosrc ~ '-- FASE 7g:|-- \(7g');
  v_res := pg_temp.ok(v_res, 'B8b nenhuma função de antes lê as colunas nem chama as funções novas (fora as marcadas -- FASE 7g, que são dos pacotes seguintes)', v_dif is null, v_dif);
  -- a migration só cria as 11 novas: nenhuma "create or replace function" de um nome de antes (R9.1: o P1 não recria nada; quem recria é do P2 em diante)
  if coalesce(current_setting('agenda_teste.mig_base_fase7g', true), '') = '' then
    v_res := pg_temp.ok(v_res, 'B8c as funções da migration', true, 'PULADO: sem agenda_teste.mig_base_fase7g (rode pela bancada)');
  else
    select string_agg(distinct m[1], ',' order by m[1]) into v_dif
      from regexp_matches(current_setting('agenda_teste.mig_base_fase7g'), 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
    v_res := pg_temp.ok(v_res, 'B8c a migration só cria as 11 funções novas: nada do motor, da medição nem da saúde é recriado (R9.1)',
      v_dif = '_agenda_criterio_texto,_agenda_degrau,_agenda_degrau_texto,_agenda_duracao_fonte_texto,_agenda_marcacoes_so_muda,_agenda_placar_so_muda,_agenda_quem_marcou,_agenda_suposicao_texto,_agenda_suposicoes_validas,_agenda_tipos_os_so_muda,_agenda_zona_mais_severa', v_dif);
    -- comentário é afirmação: nenhuma linha da migration chama a tela da semana, o plano da OS ou o cartão de invoker (são definer: B3e3). A conferência do P1 achou 2.
    select string_agg(m[1], ' | ') into v_dif
      from regexp_matches(current_setting('agenda_teste.mig_base_fase7g'),
             '(?n)([^\n]*(tela da semana|tela_semana|plano da os|plano_da_os|cart[aã]o)[^\n]*invoker[^\n]*|[^\n]*invoker[^\n]*(tela da semana|tela_semana|plano da os|plano_da_os|cart[aã]o)[^\n]*)', 'gi') m;
    v_res := pg_temp.ok(v_res, 'B8e nenhuma linha da migration chama a tela da semana, o plano da OS ou o cartão de invoker (são definer)', v_dif is null, left(v_dif, 400));
  end if;
  perform pg_temp.gravar(v_res);
end
$b8$;

do $b8d$
declare
  v_ref  jsonb;
  v      text;
  v_dif  text;
  v_n    int := 0;
  f      boolean;
  m      text;
  r      record;
  c_hoje constant date := date '2026-10-29';
  c_agor constant timestamptz := timestamptz '2026-10-29 16:52-03';
begin
  -- Sobre o replay de 29/10 que o rodar.mjs já carregou: as leituras do que sai ao dono. Com os 4 modos desligados (a régua), em sombra e ligados, com e sem o freio, o que sai é
  -- igual: nada lê os 4 modos. Só na bancada (a sombra byte a byte na carteira real de hoje é a do f7g/p1/real.mjs).
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
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
  foreach f in array array[true, false] loop
    update public.agenda_config set gestor_so_propor = f where id;
    perform pg_temp.modos('desligado');
    v_ref := '{}';
    for r in select * from _leitura loop
      execute r.sql into v;
      v_ref := v_ref || jsonb_build_object(r.nome, md5(v));
    end loop;
    foreach m in array array['sombra', 'ligado'] loop
      perform pg_temp.modos(m);
      for r in select * from _leitura loop
        execute r.sql into v;
        v_n := v_n + 1;
        if md5(v) is distinct from v_ref ->> r.nome then
          v_dif := coalesce(v_dif || ', ', '') || format('%s (%s, freio %s)', r.nome, m, f);
        end if;
      end loop;
    end loop;
  end loop;
  perform pg_temp.modos('desligado');
  update public.agenda_config set gestor_so_propor = false where id;
  perform pg_temp.gravar(pg_temp.ok('[]', format('B8d as leituras do que sai ao dono dão o mesmo md5 de desligado, em sombra e ligadas, com e sem o freio (%s leituras): nada lê os 4 modos', v_n), v_dif is null, v_dif));
end
$b8d$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
