-- Prova da base da Agenda de Produção, Fase 7f (pacote P1): os 6 interruptores e os 15 parâmetros, as colunas do padrão e do prazo, as listas fechadas, o modelo
-- M12, o padrão de cada pergunta (o gatilho e o backfill), o gatilho de antes, a zona, a classe, o modo com o freio e a fixture da etapa (migration
-- 20261109100000; spec-fase7f §4, §5.1, §8.2, §8.3 e R8.5-1 a 6, R8.6, R8.8, R8.12, R8.13).
-- bancada: depende de 20261109100000
--
--   B1  colunas, DEFAULTs e CHECKs: agenda_config (os 6 interruptores nascem desligados na linha com o DEFAULT sombra; os 15 parâmetros com o valor da spec);
--       a trava de veto_tipos, tipo a tipo; perguntas_primeiro na lista; agenda_perguntas (os CHECKs novos, veto_nao_critica fora e pergunta_veto_so_com_padrao
--       nunca criado); agenda_equipe_mensagens e o índice sem mudanca
--   B2  privilégios: o modo para authenticated e service_role; as outras sem grant; o gatilho definer funciona para quem não tem grant
--   B3  o padrão de TODO tipo da lista corrente, com a tabela inteira (tipo novo sem linha reprova aqui); as regras: opção que falta, OS sem linha, prometido em
--       outra OS, fora de veto_tipos, tipo desconhecido
--   B4  o gatilho de INSERT; o INSERT e o UPDATE de veto_ate da 7a, da 7b e da 7c com a forma real; o backfill sobre a equipe_cadastro real; o gatilho de antes
--       (o que muda na aberta, na fechada, o prazo de valor a valor) e a cópia só nos blocos "-- FASE 7f:"
--   B5  _agenda_zona nos 6 casos, igual à regra do 7a (_agenda_dia_avisado)
--   B6  as listas: as de antes iguais e na mesma ordem, os novos no fim; o ampliador; cliente_tipos_ligados "<@", à mão
--   B7  modelo: M12 em semana, M11 em onde_fica, os de antes iguais
--   B8  _agenda_fala_modo: os 6 itens × os 3 modos × o freio
--   B9  _agenda_classe_da_saida: pergunta, ação, linha; o que afeta; a exceção; o que lança
--   B10 nada muda de comportamento: só as funções desta migration, 1 gatilho, nada de antes chama as novas, sem dado; as leituras iguais (md5) nos 6 modos
--       desligados, em sombra e ligados com o freio; _agenda_modo_da_pergunta não muda
--   B11 a fixture: as 8 abertas, quem pode vencer, os tamanhos reais, carregar 2× = 1×
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration e ANTES do dado 20261109100900 (que põe os modos em sombra), com o OK nomeado:
--   npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7f_base.sql
--   Seguro em produção: tudo dentro de subtransações desfeitas e termina em ROLLBACK. O que usa as fixtures e as migrations como texto só roda na bancada (fora dela
--   sai PULADO).
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

-- A expressão de uma coluna gerada, avaliada com tipo = p_tipo.
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

-- O corpo de uma função numa migration (o texto entre "as $function$" e "$function$").
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  if position(format('create or replace function public.%s(', p_nome) in v) = 0 then return ''; end if;
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  v := substr(v, position(E'\nas $function$' in v) + length(E'\nas $function$'));
  return left(v, position('$function$' in v) - 1);
end $f$;

-- O texto sem os blocos "-- FASE 7f: … -- FASE 7f: fim" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7f(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7f:' and l !~ '^\s*-- FASE 7f: fim' then 1
                                                when l ~ '^\s*-- FASE 7f: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7f: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;

create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;
-- uma pergunta mínima, em modo ligado, que passa pelos 2 gatilhos; a linha fica na transação de quem chama
create function pg_temp.perg(p_tipo text, p_chave text, p_extra text default '', p_valores text default '') returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  execute format('insert into public.agenda_perguntas (tipo, chave, texto, modo%s) values (%L, %L, ''Pergunta de teste.'', ''ligado''%s) returning id',
                 case when p_extra <> '' then ', ' || p_extra else '' end, p_tipo, p_chave,
                 case when p_valores <> '' then ', ' || p_valores else '' end) into v;
  return v;
end $f$;
-- as fixtures e as migrations como texto (só na bancada)
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7d', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_base_fase7f', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_base_fase7a', true), '') <> ''
$f$;
-- os 6 interruptores, de uma vez
create function pg_temp.modos(p_modo text) returns void language plpgsql as $f$
begin
  update public.agenda_config
     set modo_bloco_agenda = p_modo, modo_veto = p_modo, modo_lote_dono = p_modo, modo_equipe_previsto = p_modo, modo_equipe_convite = p_modo,
         modo_cliente_camadas = p_modo
   where id;
end $f$;

-- ── B1. Colunas, DEFAULTs e CHECKs ─────────────────────────────────────────────────────
with cfg as (select to_jsonb(c) as j from public.agenda_config c where c.id),
esperado(coluna, valor) as (values
  ('bloco_max_chars', '520'), ('bloco_decisoes_max', '3'), ('bloco_mudancas_max', '3'), ('bloco_compras_max', '3'), ('bloco_compras_du', '2'),
  ('perguntas_abertas_max', '5'), ('dono_semana_aviso', 'propria'), ('dono_semana_hora', '16:50:00'), ('equipe_convite_antecedencia_h', '72'),
  ('cliente_dia_exato_du', '1'), ('cliente_semana_du', '10'), ('cliente_camadas_para', 'estimativa'), ('comunicar_tempo_max', '00:00:15'))
insert into _resultado
select 'B1a os 13 parâmetros de um valor com o padrão da spec (§4.1, R8.5-7)',
       bool_and(cfg.j ->> e.coluna = e.valor) and count(*) = 13,
       string_agg(e.coluna || '=' || coalesce(cfg.j ->> e.coluna, 'nulo'), ', ') filter (where cfg.j ->> e.coluna is distinct from e.valor)
  from cfg, esperado e;

insert into _resultado
select 'B1b veto_tipos: os 14 da §4.1; perguntas_primeiro: padrao_do_dono e dias_semana (AG7-02)',
       c.veto_tipos = '{duracao,material_conferir,padrao_do_dono,chegou,parada,estouro,previsao_fornecedor,fornecedor_cadastro,fornecedores_prazo,equipe_resposta,nao_cabe,atraso_longo,segundo_atraso,fixada_pelo_dono}'::text[]
       and c.perguntas_primeiro = '{padrao_do_dono,dias_semana}'::text[],
       format('%s; %s', c.veto_tipos, c.perguntas_primeiro)
  from public.agenda_config c where c.id;

with m(coluna) as (values ('modo_bloco_agenda'), ('modo_veto'), ('modo_lote_dono'), ('modo_equipe_previsto'), ('modo_equipe_convite'), ('modo_cliente_camadas'))
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

-- A trava de veto_tipos (R8.5-3): a lista do que nunca vence é lida do próprio CHECK; todo nome dela existe, nenhum dos que vencem está nela, cada um é recusado pelo nome
do $b1$
declare
  c_nome  constant text := 'agenda_config_veto_tipos_check';
  v_tipos text[] := pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check');
  v_nunca text[] := pg_temp.lista('public.agenda_config'::regclass, c_nome);
  c       public.agenda_config;
  v_dif   text;
  v_res   jsonb := '[]'::jsonb;
  t       text;
begin
  select * into c from public.agenda_config where id;
  v_res := pg_temp.ok(v_res, 'B1d a lista do que nunca vence tem os 20 da §4.1 com o R8.5-3, e o CHECK é "not (veto_tipos && …)", não uma lista que lê catálogo',
    v_nunca @> array['diaria', 'diaria_ligar', 'nfe_vincular', 'pix_material', 'concluir', 'entrega', 'cliente_aprovar', 'cliente_aviso', 'cliente_resposta', 'aprendizado',
                     'conferencia', 'remarcar_confirmado', 'compre_ate', 'sinal', 'tarefa', 'local', 'combinar', 'acesso', 'dia_prometido', 'dia_avisado']
    and cardinality(v_nunca) = 20
    and (select pg_get_constraintdef(k.oid) like 'CHECK ((NOT (veto_tipos && %' from pg_constraint k
          where k.conrelid = 'public.agenda_config'::regclass and k.conname = c_nome),
    array_to_string(v_nunca, ','));
  v_res := pg_temp.ok(v_res, 'B1e todo nome de veto_tipos, de perguntas_primeiro e da lista do que nunca vence existe em agenda_perguntas.tipo',
    c.veto_tipos <@ v_tipos and c.perguntas_primeiro <@ v_tipos and v_nunca <@ v_tipos,
    array_to_string(array(select x from unnest(c.veto_tipos || c.perguntas_primeiro || v_nunca) x where x <> all (v_tipos)), ','));
  select string_agg(x, ',') into v_dif from unnest(v_nunca) x
   where pg_temp.recusa(format('update public.agenda_config set veto_tipos = veto_tipos || %L::text where id', x)) <> c_nome;
  v_res := pg_temp.ok(v_res, 'B1f veto_tipos recusa cada um dos 20 que nunca vencem, pelo nome (dinheiro, cliente, aprendizado, dia confirmado, relógio próprio)',
    v_dif is null, v_dif);
  select string_agg(x, ',') into v_dif from unnest(v_tipos) x
   where x <> all (v_nunca)
     and pg_temp.recusa(format('update public.agenda_config set veto_tipos = veto_tipos || %L::text where id', x)) <> 'aceitou';
  v_res := pg_temp.ok(v_res, 'B1g veto_tipos aceita os outros tipos (o CHECK não trava o que pode vencer)', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B1h veto_tipos vazia passa: nada vence pelo prazo',
    pg_temp.recusa('update public.agenda_config set veto_tipos = ''{}'' where id') = 'aceitou', null);
  perform pg_temp.gravar(v_res);
end
$b1$;

-- Cada CHECK de agenda_config recusa o caso dele, pelo nome, e aceita os limites
do $b1$
declare
  r      record;
  v      text;
  v_dif  text;
  v_n    int := 0;
  v_cob  text[] := '{}';
begin
  for r in select * from (values
    ('modo_bloco_agenda = ''x''', 'agenda_config_modo_bloco_agenda_check'),
    ('modo_veto = ''x''', 'agenda_config_modo_veto_check'),
    ('modo_lote_dono = ''x''', 'agenda_config_modo_lote_dono_check'),
    ('modo_equipe_previsto = ''x''', 'agenda_config_modo_equipe_previsto_check'),
    ('modo_equipe_convite = ''x''', 'agenda_config_modo_equipe_convite_check'),
    ('modo_cliente_camadas = ''x''', 'agenda_config_modo_cliente_camadas_check'),
    ('bloco_max_chars = 299', 'agenda_config_bloco_max_chars_check'),
    ('bloco_max_chars = 801', 'agenda_config_bloco_max_chars_check'),
    ('bloco_max_chars = 300', 'aceitou'),
    ('bloco_max_chars = 800', 'aceitou'),
    ('bloco_decisoes_max = 0', 'agenda_config_bloco_decisoes_max_check'),
    ('bloco_decisoes_max = 6', 'agenda_config_bloco_decisoes_max_check'),
    ('bloco_decisoes_max = 1', 'aceitou'),
    ('bloco_decisoes_max = 5', 'aceitou'),
    ('bloco_mudancas_max = 0', 'agenda_config_bloco_mudancas_max_check'),
    ('bloco_mudancas_max = 7', 'agenda_config_bloco_mudancas_max_check'),
    ('bloco_mudancas_max = 6', 'aceitou'),
    ('bloco_compras_max = 0', 'agenda_config_bloco_compras_max_check'),
    ('bloco_compras_max = 7', 'agenda_config_bloco_compras_max_check'),
    ('bloco_compras_max = 6', 'aceitou'),
    ('bloco_compras_du = 0', 'agenda_config_bloco_compras_du_check'),
    ('bloco_compras_du = 6', 'agenda_config_bloco_compras_du_check'),
    ('bloco_compras_du = 5', 'aceitou'),
    ('perguntas_abertas_max = 2', 'agenda_config_perguntas_abertas_max_check'),
    ('perguntas_abertas_max = 11', 'agenda_config_perguntas_abertas_max_check'),
    ('perguntas_abertas_max = 3', 'aceitou'),
    ('perguntas_abertas_max = 10', 'aceitou'),
    ('dono_semana_aviso = ''quinta''', 'agenda_config_dono_semana_aviso_check'),
    ('dono_semana_aviso = ''fechamento''', 'aceitou'),
    ('dono_semana_hora = hora_do_plano - interval ''1 minute''', 'agenda_config_dono_semana_hora_check'),
    ('dono_semana_hora = cliente_janela_fim + interval ''1 minute''', 'agenda_config_dono_semana_hora_check'),
    -- FASE 7g: a rodada explicar (explicar_hora, 16:35) fica antes da mensagem da quinta (20261112100000): a quinta só desce até hora_do_plano com a rodada antes dela, na
    -- mesma escrita (sem a 7g, a escrita é a de antes)
    ('dono_semana_hora = hora_do_plano' || case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                                                                  and a.attname = 'explicar_hora' and not a.attisdropped)
                                                 then ', explicar_hora = ''12:00''' else '' end, 'aceitou'),
    -- FASE 7g: fim
    ('dono_semana_hora = cliente_janela_fim', 'aceitou'),
    ('equipe_convite_antecedencia_h = 23', 'agenda_config_equipe_convite_antecedencia_h_check'),
    ('equipe_convite_antecedencia_h = 121', 'agenda_config_equipe_convite_antecedencia_h_check'),
    ('equipe_convite_antecedencia_h = 24', 'aceitou'),
    ('equipe_convite_antecedencia_h = 120', 'aceitou'),
    ('cliente_dia_exato_du = 0', 'agenda_config_cliente_dia_exato_du_check'),
    ('cliente_dia_exato_du = 4', 'agenda_config_cliente_dia_exato_du_check'),
    ('cliente_dia_exato_du = 3', 'aceitou'),
    ('cliente_dia_exato_du = 2, cliente_confirmar_du = 1', 'agenda_config_cliente_dia_exato_du_check'),
    ('cliente_dia_exato_du = 1, cliente_confirmar_du = 1', 'aceitou'),
    ('cliente_semana_du = 4', 'agenda_config_cliente_semana_du_check'),
    ('cliente_semana_du = 21', 'agenda_config_cliente_semana_du_check'),
    ('cliente_semana_du = 5', 'aceitou'),
    ('cliente_semana_du = 20', 'aceitou'),
    ('cliente_camadas_para = ''outra''', 'agenda_config_cliente_camadas_para_check'),
    ('cliente_camadas_para = ''todas''', 'aceitou'),
    ('comunicar_tempo_max = interval ''4 seconds''', 'agenda_config_comunicar_tempo_max_check'),
    ('comunicar_tempo_max = interval ''61 seconds''', 'agenda_config_comunicar_tempo_max_check'),
    ('comunicar_tempo_max = interval ''5 seconds''', 'aceitou'),
    ('comunicar_tempo_max = interval ''60 seconds''', 'aceitou')
  ) as t(sets, espera)
  loop
    v := pg_temp.recusa('update public.agenda_config set ' || r.sets || ' where id');
    v_n := v_n + 1;
    if v is distinct from r.espera then
      v_dif := coalesce(v_dif || ' | ', '') || r.sets || ' → ' || v;
    end if;
    if r.espera <> 'aceitou' then v_cob := v_cob || r.espera; end if;
  end loop;
  perform pg_temp.gravar(pg_temp.ok('[]', format('B1i os CHECKs de agenda_config recusam o caso deles e aceitam os limites (%s casos)', v_n), v_dif is null, v_dif));
  -- nenhum CHECK novo sem caso: a lista dos 20 sai dos nomes novos do catálogo
  select string_agg(k.conname, ',') into v_dif
    from pg_constraint k
   where k.conrelid = 'public.agenda_config'::regclass and k.contype = 'c'
     and k.conname ~ '^agenda_config_(modo_bloco_agenda|modo_veto|modo_lote_dono|modo_equipe_previsto|modo_equipe_convite|modo_cliente_camadas|bloco_|veto_tipos|perguntas_abertas_max|dono_semana_|equipe_convite_|cliente_dia_exato_du|cliente_semana_du|cliente_camadas_para|comunicar_tempo_max)'
     and k.conname <> all (v_cob) and k.conname <> 'agenda_config_veto_tipos_check';
  perform pg_temp.gravar(pg_temp.ok('[]', 'B1j os 20 CHECKs novos de agenda_config têm caso (veto_tipos, no B1f)',
    v_dif is null and (select count(distinct x) from unnest(v_cob) x) = 19, v_dif));
end
$b1$;

-- agenda_perguntas: as colunas, os CHECKs novos, o que saiu e o que nunca entrou
do $b1$
declare
  v_res jsonb := '[]'::jsonb;
  v_q   uuid;
  v_f   uuid;
  v     text;
begin
  v_res := pg_temp.ok(v_res, 'B1k agenda_perguntas: as 7 colunas; só destrava tem padrão (0), as outras nulas',
    (select count(*) = 7 and bool_and((a.attname = 'destrava') = a.atthasdef) and bool_and((a.attname = 'destrava') = a.attnotnull)
       from pg_attribute a where a.attrelid = 'public.agenda_perguntas'::regclass and not a.attisdropped
        and a.attname in ('padrao_chave', 'padrao_efeito', 'veto_espera', 'veto_teria_em', 'destrava', 'assumida_por', 'assumida_em')), null);
  v_res := pg_temp.ok(v_res, 'B1l veto_nao_critica saiu; pergunta_veto_so_com_padrao nunca entrou (R8.5-1); veto_padrao_tem_prazo ficou; os 3 novos de pé',
    (select array_agg(c.conname::text order by c.conname) from pg_constraint c
      where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname ~ '^(veto_|pergunta_)')
    = array['pergunta_assumida_coerente', 'pergunta_assumida_fechada', 'pergunta_padrao_coerente', 'veto_padrao_tem_prazo'],
    (select string_agg(c.conname::text, ',' order by c.conname) from pg_constraint c
      where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname ~ '^(veto_|pergunta_)'));

  v_q := pg_temp.perg('parada', 'parada:teste-b1');
  perform set_config('agenda.backfill_padrao', 'on', true);
  v_res := pg_temp.ok(v_res, 'B1m as listas de padrao_chave, padrao_efeito e veto_espera recusam o que não é delas',
    pg_temp.recusa(format('update public.agenda_perguntas set padrao_chave = ''x'' where id = %L', v_q)) = 'agenda_perguntas_padrao_chave_check'
    and pg_temp.recusa(format('update public.agenda_perguntas set padrao_efeito = ''x'' where id = %L', v_q)) = 'agenda_perguntas_padrao_efeito_check'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_espera = ''x'' where id = %L', v_q)) = 'agenda_perguntas_veto_espera_check', null);
  v_res := pg_temp.ok(v_res, 'B1n pergunta_padrao_coerente: a chave sem o efeito, e o efeito sem a chave',
    pg_temp.recusa(format('update public.agenda_perguntas set padrao_efeito = null where id = %L', v_q)) = 'pergunta_padrao_coerente'
    and pg_temp.recusa(format('update public.agenda_perguntas set padrao_chave = null where id = %L', v_q)) = 'pergunta_padrao_coerente', null);
  perform set_config('agenda.backfill_padrao', '', true);
  v_res := pg_temp.ok(v_res, 'B1o destrava 0..9999; assumida_por só prazo ou teto',
    pg_temp.recusa(format('update public.agenda_perguntas set destrava = -1 where id = %L', v_q)) = 'agenda_perguntas_destrava_check'
    and pg_temp.recusa(format('update public.agenda_perguntas set destrava = 10000 where id = %L', v_q)) = 'agenda_perguntas_destrava_check'
    and pg_temp.recusa(format('update public.agenda_perguntas set destrava = 9999 where id = %L', v_q)) = 'aceitou'
    and pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''x'', assumida_em = now(), estado = ''resolvida'', resolvida_motivo = ''t'' where id = %L', v_q))
        = 'agenda_perguntas_assumida_por_check', null);
  v_res := pg_temp.ok(v_res, 'B1p pergunta_assumida_coerente: quem sem quando, quando sem quem',
    pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''prazo'', estado = ''resolvida'', resolvida_motivo = ''t'' where id = %L', v_q)) = 'pergunta_assumida_coerente'
    and pg_temp.recusa(format('update public.agenda_perguntas set assumida_em = now(), estado = ''resolvida'', resolvida_motivo = ''t'' where id = %L', v_q)) = 'pergunta_assumida_coerente', null);
  v_res := pg_temp.ok(v_res, 'B1q pergunta_assumida_fechada: na aberta recusa; em vencida e descartada recusa; em resolvida passa',
    pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''prazo'', assumida_em = now() where id = %L', v_q)) = 'pergunta_assumida_fechada'
    and pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''prazo'', assumida_em = now(), estado = ''vencida'', resolvida_motivo = ''t'' where id = %L', v_q)) = 'pergunta_assumida_fechada'
    and pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''prazo'', assumida_em = now(), estado = ''descartada'', resolvida_motivo = ''t'' where id = %L', v_q)) = 'pergunta_assumida_fechada'
    and pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''teto'', assumida_em = now(), estado = ''resolvida'', resolvida_motivo = ''t'' where id = %L', v_q)) = 'aceitou', null);

  -- a crítica pode ter prazo (AG7-15): era o que veto_nao_critica recusava
  v := pg_temp.recusa($q$insert into public.agenda_perguntas (tipo, chave, texto, modo, opcoes, recomendacao, veto_ate)
                         values ('nao_cabe', 'nao_cabe:teste-b1', 'Pergunta de teste.', 'ligado', '[{"n":1},{"n":2}]', 1, now() + interval '1 day')$q$);
  v_res := pg_temp.ok(v_res, 'B1r crítica com prazo: passa (AG7-15); quem filtra é a rodada', v = 'aceitou', v);

  -- agenda_equipe_mensagens
  v_res := pg_temp.ok(v_res, 'B1s agenda_equipe_mensagens: dias (date[]) e alocacao_ids (uuid[]), nulas',
    (select count(*) = 2 and bool_and(not a.attnotnull and not a.atthasdef)
            and bool_and(format_type(a.atttypid, null) = case a.attname when 'dias' then 'date[]' else 'uuid[]' end)
       from pg_attribute a where a.attrelid = 'public.agenda_equipe_mensagens'::regclass and not a.attisdropped
        and a.attname in ('dias', 'alocacao_ids')), null);
  v_res := pg_temp.ok(v_res, 'B1t agenda_equipe_uma_por_dia: fora resposta e mudanca',
    (select i.indexdef from pg_indexes i where i.schemaname = 'public' and i.indexname = 'agenda_equipe_uma_por_dia')
    like '%(payee_id, dia, tipo, modo) WHERE (tipo <> ALL (ARRAY[''resposta''::text, ''mudanca''::text]))',
    (select i.indexdef from pg_indexes i where i.schemaname = 'public' and i.indexname = 'agenda_equipe_uma_por_dia'));
  select id into v_f from public.payees where active order by id limit 1;
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key)
  values (v_f, date '2031-01-02', 'mudanca', 'sombra', 'Mudou um.', now(), 'teste-b1:mudanca:1'),
         (v_f, date '2031-01-02', 'previsto', 'sombra', 'Previsto um.', now(), 'teste-b1:previsto:1');
  v_res := pg_temp.ok(v_res, 'B1u 2 mudanças da mesma pessoa no mesmo dia passam; 2 previstos, não; a mudança repetida cai na dedupe_key',
    pg_temp.recusa(format($q$insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key)
                             values (%L, '2031-01-02', 'mudanca', 'sombra', 'Mudou dois.', now(), 'teste-b1:mudanca:2')$q$, v_f)) = 'aceitou'
    and pg_temp.recusa(format($q$insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key)
                                 values (%L, '2031-01-02', 'previsto', 'sombra', 'Previsto dois.', now(), 'teste-b1:previsto:2')$q$, v_f)) = 'agenda_equipe_uma_por_dia', null);
  raise exception using errcode = 'P0001', message = '__desfaz__';
exception when others then
  if sqlerrm <> '__desfaz__' then raise; end if;
  -- o bloco desfaz o que escreveu; o resultado vai depois
  perform pg_temp.gravar(v_res);
end
$b1$;

-- ── B2. Privilégios ────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B2a _agenda_fala_modo: authenticated e service_role sim; anon e public não',
       has_function_privilege('authenticated', 'public._agenda_fala_modo(text)', 'execute')
       and has_function_privilege('service_role', 'public._agenda_fala_modo(text)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_fala_modo(text)', 'execute')
       and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                        where p.oid = 'public._agenda_fala_modo(text)'::regprocedure and a.grantee = 0),
       null;

with f(nome) as (values ('public._agenda_padrao_da_pergunta(text, boolean, uuid, jsonb, smallint, uuid[])'), ('public._agenda_perguntas_padrao()'),
                        ('public._agenda_zona(uuid, uuid, date, date)'), ('public._agenda_classe_da_saida(text, uuid, date, timestamptz)'))
insert into _resultado
select 'B2b as 4 novas sem grant: nem anon, nem authenticated, nem service_role, nem public; _agenda_perguntas_antes segue fora de anon e authenticated',
       count(*) = 4 and not has_function_privilege('anon', 'public._agenda_perguntas_antes()', 'execute')
       and not has_function_privilege('authenticated', 'public._agenda_perguntas_antes()', 'execute') and bool_and(not has_function_privilege('anon', f.nome, 'execute') and not has_function_privilege('authenticated', f.nome, 'execute')
                                 and not has_function_privilege('service_role', f.nome, 'execute')
                                 and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.nome::regprocedure and a.grantee = 0)),
       string_agg(f.nome, ', ') filter (where has_function_privilege('service_role', f.nome, 'execute') or has_function_privilege('authenticated', f.nome, 'execute'))
  from f;

insert into _resultado
select 'B2c o gatilho é o único definer; search_path fixo nas 6; a zona, a classe, o padrão e o modo são STABLE',
       count(*) = 6
       and bool_and(p.prosecdef = (p.proname = '_agenda_perguntas_padrao'))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%')
       and bool_and(case when p.proname in ('_agenda_zona', '_agenda_classe_da_saida', '_agenda_padrao_da_pergunta', '_agenda_fala_modo') then p.provolatile = 's' else true end),
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('_agenda_padrao_da_pergunta', '_agenda_perguntas_padrao', '_agenda_zona', '_agenda_classe_da_saida', '_agenda_fala_modo', '_agenda_perguntas_antes');

do $b2$
declare
  v_tec constant uuid := 'aa000000-0000-4000-8000-0000000000ff';
  v_res jsonb := '[]'::jsonb;
  v     text;
  w     text;
begin
  v := pg_temp.como(v_tec, 'authenticated', $q$select public._agenda_zona(null, null, date '2026-11-10', date '2026-11-10')$q$);
  w := pg_temp.como(null, 'anon', $q$select public._agenda_fala_modo('veto')$q$);
  v_res := pg_temp.ok(v_res, 'B2d o técnico e o anon: a zona e o modo dão 42501', v like 'erro 42501%' and w like 'erro 42501%', v || ' | ' || w);
  v := pg_temp.como(v_tec, 'authenticated', $q$select public._agenda_padrao_da_pergunta('parada', false, null, '[]', null)::text$q$);
  w := pg_temp.como(v_tec, 'authenticated', $q$select public._agenda_classe_da_saida('linha', null, date '2026-11-10', now())::text$q$);
  v_res := pg_temp.ok(v_res, 'B2e o técnico: o padrão e a classe dão 42501', v like 'erro 42501%' and w like 'erro 42501%', v || ' | ' || w);
  v := pg_temp.como(null, 'service_role', $q$select public._agenda_fala_modo('veto')$q$);
  v_res := pg_temp.ok(v_res, 'B2f o service_role lê o modo', v = 'desligado', v);
  -- o gatilho definer: quem insere sem grant na função do padrão (a rodada da vigia corre como service_role) e a pergunta nasce com o padrão
  v := pg_temp.como(null, 'service_role', $q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('parada', 'parada:teste-b2', 'Pergunta de teste.', 'ligado') returning padrao_chave || '/' || padrao_efeito$q$);
  v_res := pg_temp.ok(v_res, 'B2g o service_role insere e o gatilho preenche: definer, sem grant na função do padrão', v = 'como_esta/nada', v);
  raise exception using errcode = 'P0001', message = '__desfaz__';
exception when others then
  if sqlerrm <> '__desfaz__' then raise; end if;
  -- o bloco desfaz o que escreveu; o resultado vai depois
  perform pg_temp.gravar(v_res);
end
$b2$;

-- ── B3. O padrão de TODO tipo ──────────────────────────────────────────────────────────
do $b3$
declare
  v_tipos text[] := pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check');
  v_res   jsonb := '[]'::jsonb;
  v_dif   text;
  v_os    uuid;
  v_os2   uuid;
  c_op    constant jsonb := '[{"n": 1}, {"n": 2}]';
  j       jsonb;
begin
  create temp table _esperado (tipo text primary key, chave text, efeito text, espera text, recom smallint) on commit drop;
  -- a tabela da §5.1 com o R8.5-2; recom = a opção que vem, quando a tabela depende dela
  insert into _esperado values
    ('duracao',             'estimativa',   'nada',  null,         null),
    ('material_conferir',   'sem_peca',     'nada',  null,         null),
    ('padrao_do_dono',      'abre_e_fecha', 'nada',  null,         null),
    ('dias_semana',         'abre_e_fecha', 'nada',  'tipo',       null),
    ('previsao_fornecedor', 'prazo_padrao', 'nada',  null,         null),
    ('fornecedor_cadastro', 'prazo_padrao', 'nada',  null,         null),
    ('fornecedores_prazo',  'prazo_padrao', 'nada',  null,         null),
    ('parada',              'como_esta',    'nada',  null,         null),
    ('estouro',             'como_esta',    'nada',  null,         null),
    ('equipe_resposta',     'como_esta',    'nada',  null,         null),
    ('chegou',              'nao_chegou',   'nada',  null,         null),
    ('nao_cabe',            'recomendacao', 'opcao', null,         1),
    ('atraso_longo',        'recomendacao', 'opcao', null,         1),
    ('segundo_atraso',      'recomendacao', 'opcao', null,         1),
    ('fixada_pelo_dono',    'recomendacao', 'opcao', null,         1),
    ('remarcar_confirmado', 'recomendacao', 'opcao', 'cliente',    1),
    ('diaria',              null,           null,    'dinheiro',   null),
    ('diaria_ligar',        null,           null,    'dinheiro',   null),
    ('nfe_vincular',        null,           null,    'dinheiro',   null),
    ('pix_material',        null,           null,    'dinheiro',   null),
    ('concluir',            null,           null,    'dinheiro',   null),
    ('entrega',             null,           null,    'dinheiro',   null),
    ('compre_ate',          null,           null,    'dinheiro',   null),
    ('sinal',               null,           null,    'dinheiro',   null),
    ('cliente_aprovar',     null,           null,    'tipo',       null),
    ('cliente_aviso',       null,           null,    'tipo',       null),
    ('cliente_resposta',    null,           null,    'tipo',       null),
    ('aprendizado',         null,           null,    'tipo',       null),
    ('conferencia',         null,           null,    'tipo',       null),
    ('tarefa',              null,           null,    'tipo',       null),
    ('situacao',            'estimativa',   'opcao', 'tipo',       1),
    ('estimativa',          'estimativa',   'opcao', 'tipo',       1),
    ('reestimar',           'estimativa',   'opcao', 'tipo',       1),
    ('ficha_estimativa',    'estimativa',   'opcao', 'tipo',       1),
    ('reavaliar',           null,           null,    'sem_padrao', null),
    ('equipe_sem_dias',     null,           null,    'sem_padrao', null),
    ('combinar',            null,           null,    'sem_padrao', null),
    ('bem_livre',           'como_esta',    'nada',  'tipo',       null),
    ('equipe_cadastro',     'como_esta',    'nada',  'tipo',       null),
    ('onda',                'recomendacao', 'opcao', 'tipo',       1),
    ('dia_avisado',         'recomendacao', 'opcao', 'tipo',       1),
    ('sabado',              'recomendacao', 'opcao', 'tipo',       1),
    ('dia_prometido',       'recomendacao', 'opcao', 'cliente',    1),
    ('habilidade',          'recomendacao', 'nada',  'tipo',       null),
    ('local',               null,           null,    'cliente',    null),
    ('acesso',              'recomendacao', 'opcao', 'cliente',    1);
  -- FASE 7g: (7g P5b) ok_marcacao (20261112100700): a recomendação, como nao_cabe; fora de veto_tipos (quem o põe é o dado 100990), espera tipo
  if 'ok_marcacao' = any (v_tipos) then
    insert into _esperado values ('ok_marcacao', 'recomendacao', 'opcao',
                                  case when 'ok_marcacao' = any ((public._agenda_cfg()).veto_tipos) then null else 'tipo' end, 1);
  end if;
  -- FASE 7g: fim

  select string_agg(t, ',') into v_dif from unnest(v_tipos) t where t not in (select e.tipo from _esperado e);
  v_res := pg_temp.ok(v_res, format('B3a todo tipo da lista corrente está na tabela da prova (%s tipos): tipo novo sem linha reprova aqui', cardinality(v_tipos)),
    v_dif is null and cardinality(v_tipos) = (select count(*) from _esperado), v_dif);
  select string_agg(e.tipo, ',') into v_dif from _esperado e where e.tipo <> all (v_tipos);
  v_res := pg_temp.ok(v_res, 'B3b nenhum tipo da prova está fora da lista', v_dif is null, v_dif);

  select string_agg(format('%s: %s', e.tipo, public._agenda_padrao_da_pergunta(e.tipo, false, null, c_op, e.recom)), ' | ') into v_dif
    from _esperado e
   where public._agenda_padrao_da_pergunta(e.tipo, false, null, c_op, e.recom)
         is distinct from jsonb_build_object('chave', e.chave, 'efeito', e.efeito, 'espera', e.espera);
  v_res := pg_temp.ok(v_res, 'B3c cada tipo dá a linha dele: chave, efeito e espera (§5.1, R8.5-2)', v_dif is null, v_dif);

  -- o CASE não pode deixar tipo cair no else por engano: fora os 3 que a tabela manda para sem_padrao, todos os tipos estão escritos na função
  select string_agg(t, ',') into v_dif from unnest(v_tipos) t
   where t not in ('reavaliar', 'equipe_sem_dias', 'combinar')
     and position('''' || t || '''' in (select p.prosrc from pg_proc p where p.oid = 'public._agenda_padrao_da_pergunta(text, boolean, uuid, jsonb, smallint, uuid[])'::regprocedure)) = 0;
  v_res := pg_temp.ok(v_res, 'B3d os tipos com padrão estão escritos no CASE (B3 trava o CASE completo)', v_dif is null, v_dif);

  -- as regras
  select id into v_os from public.service_orders where not exists (select 1 from public.os_planejamento pl where pl.service_order_id = service_orders.id) order by id limit 1;
  select id into v_os2 from public.service_orders where id <> v_os and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = service_orders.id) order by id limit 1;
  v_res := pg_temp.ok(v_res, 'B3e OS sem linha em os_planejamento (o caso comum) = sem espera: a crítica pode vencer',
    public._agenda_padrao_da_pergunta('nao_cabe', true, v_os, c_op, 1::smallint) = jsonb_build_object('chave', 'recomendacao', 'efeito', 'opcao', 'espera', null), v_os::text);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em) values (v_os, 1, 'dono', now());
  v_res := pg_temp.ok(v_res, 'B3f OS com linha e sem prometido = sem espera',
    public._agenda_padrao_da_pergunta('nao_cabe', true, v_os, c_op, 1::smallint) ->> 'espera' is null, null);
  update public.os_planejamento set prometido_tipo = 'faixa', prometido_de = date '2031-01-02', prometido_ate = date '2031-01-03' where service_order_id = v_os;
  select string_agg(t, ',') into v_dif from unnest(array['nao_cabe', 'atraso_longo', 'segundo_atraso', 'fixada_pelo_dono']) t
   where public._agenda_padrao_da_pergunta(t, true, v_os, c_op, 1::smallint) ->> 'espera' is distinct from 'cliente';
  v_res := pg_temp.ok(v_res, 'B3g com prometido (faixa, não só firme) = espera cliente, nos 4 tipos', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B3h o prometido em OUTRA OS da pergunta também segura',
    public._agenda_padrao_da_pergunta('nao_cabe', true, v_os2, c_op, 1::smallint, array[v_os2, v_os]) ->> 'espera' = 'cliente'
    and public._agenda_padrao_da_pergunta('nao_cabe', true, v_os2, c_op, 1::smallint, array[v_os2]) ->> 'espera' is null
    and public._agenda_padrao_da_pergunta('nao_cabe', true, null, c_op, 1::smallint, array[v_os]) ->> 'espera' = 'cliente', null);

  j := jsonb_build_object('chave', null, 'efeito', null, 'espera', 'sem_padrao');
  select string_agg(e.tipo, ',') into v_dif from _esperado e
   where e.efeito = 'opcao' and (public._agenda_padrao_da_pergunta(e.tipo, false, null, c_op, null) is distinct from j
                                 or public._agenda_padrao_da_pergunta(e.tipo, false, null, '[]', 1::smallint) is distinct from j
                                 or public._agenda_padrao_da_pergunta(e.tipo, false, null, c_op, 3::smallint) is distinct from j
                                 or public._agenda_padrao_da_pergunta(e.tipo, false, null, null, 1::smallint) is distinct from j
                                 -- opções que não são lista: quem recusa é o CHECK da coluna, com o nome dele; o gatilho não pode lançar antes
                                 or public._agenda_padrao_da_pergunta(e.tipo, false, null, '{}', 1::smallint) is distinct from j);
  v_res := pg_temp.ok(v_res, 'B3i efeito opcao sem opção de verdade (nula, sem opções, fora das opções, opções nulas) = sem_padrao: nunca agenda_decidir(null) (R8.12-2)', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B3j tipo que a função não conhece e tipo nulo = sem_padrao',
    public._agenda_padrao_da_pergunta('tipo_que_nao_existe', false, null, '[]', null) = j and public._agenda_padrao_da_pergunta(null, false, null, '[]', null) = j, null);
  update public.agenda_config set veto_tipos = array_remove(veto_tipos, 'parada') where id;
  v_res := pg_temp.ok(v_res, 'B3k tirar o tipo de veto_tipos: espera tipo, mantendo a chave (o texto mostra o que o gestor faria)',
    public._agenda_padrao_da_pergunta('parada', false, null, '[]', null) = jsonb_build_object('chave', 'como_esta', 'efeito', 'nada', 'espera', 'tipo'), null);
  update public.agenda_config set veto_tipos = veto_tipos || '{situacao}'::text[] where id;
  v_res := pg_temp.ok(v_res, 'B3l pôr situacao em veto_tipos a deixa vencer, com a opção',
    public._agenda_padrao_da_pergunta('situacao', false, null, c_op, 2::smallint) = jsonb_build_object('chave', 'estimativa', 'efeito', 'opcao', 'espera', null), null);
  update public.agenda_config set veto_tipos = veto_tipos || '{bem_livre,equipe_cadastro,onda,sabado,habilidade,dias_semana}'::text[] where id;
  select string_agg(t, ',') into v_dif from unnest(array['bem_livre', 'equipe_cadastro', 'onda', 'sabado', 'habilidade', 'dias_semana']) t
   where public._agenda_padrao_da_pergunta(t, false, null, c_op, 1::smallint) ->> 'espera' is distinct from 'tipo';
  v_res := pg_temp.ok(v_res, 'B3l2 quem tem relógio próprio não vence por aqui nem com o tipo em veto_tipos: 2 relógios na mesma pergunta, não', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B3m p_critica não decide nada: a tabela vai pelo tipo (em BEFORE INSERT a coluna gerada ainda é nula)',
    public._agenda_padrao_da_pergunta('nao_cabe', null, null, c_op, 1::smallint) = public._agenda_padrao_da_pergunta('nao_cabe', true, null, c_op, 1::smallint)
    and public._agenda_padrao_da_pergunta('nao_cabe', false, null, c_op, 1::smallint) = public._agenda_padrao_da_pergunta('nao_cabe', true, null, c_op, 1::smallint), null);
  raise exception using errcode = 'P0001', message = '__desfaz__';
exception when others then
  if sqlerrm <> '__desfaz__' then raise; end if;
  -- o bloco desfaz o que escreveu; o resultado vai depois
  perform pg_temp.gravar(v_res);
end
$b3$;

-- ── B4. O gatilho, a forma real da 7a, da 7b e da 7c, o backfill e o gatilho de antes ──
do $b4$
declare
  c_prazo constant timestamptz := timestamptz '2031-03-11 18:00-03';
  c_op    constant jsonb := '[{"n": 1, "texto": "Sim"}, {"n": 2, "texto": "Não"}]';
  v_res   jsonb := '[]'::jsonb;
  v_q     uuid;
  v_q2    uuid;
  v_os    uuid;
  q       public.agenda_perguntas;
  v       text;
  v_dif   text;
  v_mig   text := coalesce(current_setting('agenda_teste.mig_base_fase7f', true), '');
  v_mig7a text := coalesce(current_setting('agenda_teste.mig_base_fase7a', true), '');
  t       text;
begin
  -- ── o gatilho de INSERT ──────────────────────────────────────────────────────────
  v_q := pg_temp.perg('duracao', 'duracao:teste-b4');
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4a o gatilho preenche: duracao = estimativa, nada, sem espera, destrava 0; texto e tipo como vieram',
    q.padrao_chave = 'estimativa' and q.padrao_efeito = 'nada' and q.veto_espera is null and q.destrava = 0 and q.texto = 'Pergunta de teste.' and q.tipo = 'duracao',
    to_jsonb(q) ->> 'padrao_chave');
  v_q := pg_temp.perg('duracao', 'duracao:teste-b4b', 'padrao_chave, padrao_efeito, veto_espera, destrava', '''recomendacao'', ''opcao'', ''dono'', 77');
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4b o que vier no INSERT nessas colunas é ignorado: quem preenche é o gatilho (R8.5-6: destrava nasce 0)',
    q.padrao_chave = 'estimativa' and q.padrao_efeito = 'nada' and q.veto_espera is null and q.destrava = 0, null);
  v_q := pg_temp.perg('nao_cabe', 'nao_cabe:teste-b4c', 'opcoes, recomendacao', format('%L::jsonb, 2', c_op));
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4c a crítica: o gatilho lê a recomendação; critica (gerada) continua certa',
    q.padrao_chave = 'recomendacao' and q.padrao_efeito = 'opcao' and q.veto_espera is null and q.critica, null);
  v_q := pg_temp.perg('estimativa', 'estimativa:teste-b4d', 'opcoes, opcao_padrao, veto_ate', format('%L::jsonb, 1, %L::timestamptz', c_op, c_prazo));
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4d sem recomendação e com opcao_padrao: a opção aplicada é coalesce(opcao_padrao, recomendacao)', q.padrao_efeito = 'opcao' and q.padrao_chave = 'estimativa', null);
  v_q := pg_temp.perg('estimativa', 'estimativa:teste-b4e', 'opcoes', format('%L::jsonb', c_op));
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4e nem recomendação nem opcao_padrao: sem_padrao, sem chave', q.padrao_chave is null and q.padrao_efeito is null and q.veto_espera = 'sem_padrao', null);
  select id into v_os from public.service_orders where not exists (select 1 from public.os_planejamento pl where pl.service_order_id = service_orders.id) order by id limit 1;
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, prometido_tipo, prometido_de, prometido_ate)
  values (v_os, 1, 'dono', now(), 'firme', date '2031-03-20', date '2031-03-21');
  v_q := pg_temp.perg('nao_cabe', 'nao_cabe:teste-b4f', 'opcoes, recomendacao, os_ids', format('%L::jsonb, 1, array[%L::uuid]', c_op, v_os));
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4f o gatilho olha as OS de os_ids: prometido numa delas, sem service_order_id, espera o cliente', q.veto_espera = 'cliente', q.veto_espera);
  v_q := pg_temp.perg('nao_cabe', 'nao_cabe:teste-b4f2', 'opcoes, recomendacao, service_order_id', format('%L::jsonb, 1, %L::uuid', c_op, v_os));
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4f2 e olha service_order_id', q.veto_espera = 'cliente', q.veto_espera);

  -- ── a forma real: INSERT da 7a pela função de verdade, nos tipos que têm prazo (a resolução vem de _agenda_gestor_perguntar, que grava veto_ate) ─────
  foreach t in array array['situacao', 'estimativa', 'reestimar', 'ficha_estimativa'] loop
    v_q := public._agenda_gestor_perguntar(t, t || ':teste-b4g', null, 'Pergunta do gestor.', c_op, 1::smallint, c_prazo, 1::smallint, 'ligado', now());
    select * into q from public.agenda_perguntas where id = v_q;
    if q.veto_ate is distinct from c_prazo or q.padrao_chave is distinct from 'estimativa' or q.veto_espera is distinct from 'tipo' then
      v_dif := coalesce(v_dif || ', ', '') || t;
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B4g 7a: _agenda_gestor_perguntar com prazo, nos 4 tipos: nasce com veto_ate e espera tipo (o CHECK pergunta_veto_so_com_padrao da §4.2 lançaria dentro do gestor)', v_dif is null, v_dif);

  -- a 7b: a chamada aberta, com a forma de produção (06/11): 2 opções, recomendação 1, opcao_padrao nula, veto_ate gravado, mostrada 1 vez
  v_q := pg_temp.perg('equipe_cadastro', 'equipe_cadastro:chamada:2031-03-03', 'opcoes, recomendacao, veto_ate, mostrada_vezes, mostrada_em, mostrada_via',
                      format('%L::jsonb, 1, %L::timestamptz, 1, %L::timestamptz, ''fechamento''', c_op, c_prazo, c_prazo - interval '5 days'));
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4h 7b: a equipe_cadastro com veto_ate nasce: como_esta, nada, espera tipo',
    q.veto_ate = c_prazo and q.padrao_chave = 'como_esta' and q.padrao_efeito = 'nada' and q.veto_espera = 'tipo', null);
  -- e a escrita de verdade da 7b é UPDATE de nulo a valor
  v_q := pg_temp.perg('equipe_cadastro', 'equipe_cadastro:chamada:2031-03-10', 'mostrada_vezes, mostrada_em, mostrada_via', format('1, %L::timestamptz, ''fechamento''', c_prazo - interval '5 days'));
  v := pg_temp.recusa(format('update public.agenda_perguntas q set veto_ate = public._agenda_veto_ate(q.mostrada_em, 2::smallint), expira_em = greatest(coalesce(q.expira_em, q.criada_em), public._agenda_veto_ate(q.mostrada_em, 2::smallint)) where q.id = %L', v_q));
  v_res := pg_temp.ok(v_res, 'B4i 7b: o UPDATE do prazo da chamada (de nulo a valor) passa', v = 'aceitou', v);
  v_q := pg_temp.perg('dias_semana', 'dias_semana:teste-b4', 'veto_ate', format('%L::timestamptz', c_prazo));
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4j 7b: dias_semana com veto_ate: espera tipo (fecha pelo passo dela)', q.veto_espera = 'tipo' and q.padrao_chave = 'abre_e_fecha', null);

  -- a 7c: a proposta do histórico; o prazo é da função de verdade
  v_q := pg_temp.perg('habilidade', 'habilidade:equipe:2031-03-03', 'mostrada_vezes, mostrada_em, mostrada_via', format('1, %L::timestamptz, ''fechamento''', c_prazo - interval '5 days'));
  perform public._agenda_habilidade_vetos(date '2031-03-07', c_prazo - interval '4 days');
  select * into q from public.agenda_perguntas where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4k 7c: _agenda_habilidade_vetos grava o prazo na pergunta com espera tipo, e não lança',
    q.veto_ate is not null and q.veto_espera = 'tipo' and q.padrao_chave = 'recomendacao' and q.padrao_efeito = 'nada', q.veto_ate::text);
  v := pg_temp.recusa(format($q$insert into public.agenda_perguntas (tipo, chave, texto, modo, veto_ate) values ('habilidade', 'habilidade:os:teste-b4', 'Pergunta de teste.', 'ligado', %L::timestamptz)$q$, c_prazo));
  v_res := pg_temp.ok(v_res, 'B4l 7c: INSERT de habilidade com veto_ate passa', v = 'aceitou', v);

  -- ── o backfill: a pergunta real nasce antes do gatilho; rodar a migration de verdade, que é o que aplicar faz ─────
  if v_mig = '' then
    v_res := pg_temp.ok(v_res, 'B4m o backfill', true, 'PULADO: sem agenda_teste.mig_base_fase7f (rode pela bancada)');
  else
    -- volta as perguntas ao estado de antes da migration: sem padrão
    perform set_config('agenda.backfill_padrao', 'on', true);
    update public.agenda_perguntas set padrao_chave = null, padrao_efeito = null, veto_espera = null where estado = 'aberta';
    perform set_config('agenda.backfill_padrao', '', true);
    v_q := pg_temp.perg('compre_ate', 'compre_ate:teste-b4m');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_q;
    perform set_config('agenda.backfill_padrao', 'on', true);
    update public.agenda_perguntas set estado = estado, veto_espera = veto_espera where id = v_q;
    perform set_config('agenda.backfill_padrao', '', true);
    select count(*) into strict v_dif from public.agenda_perguntas where estado = 'aberta' and veto_ate is not null and padrao_chave is null and veto_espera is null;
    execute v_mig;
    select * into q from public.agenda_perguntas where chave = 'equipe_cadastro:chamada:2031-03-03';
    v_res := pg_temp.ok(v_res, format('B4m a migration roda de novo com a equipe_cadastro aberta com veto_ate (forma real) e mais %s perguntas com prazo: não quebra e preenche', v_dif),
      q.veto_ate = c_prazo and q.padrao_chave = 'como_esta' and q.padrao_efeito = 'nada' and q.veto_espera = 'tipo', to_jsonb(q) ->> 'veto_espera');
    select * into q from public.agenda_perguntas where chave = 'estimativa:teste-b4d';
    v_res := pg_temp.ok(v_res, 'B4m2 o backfill lê coalesce(opcao_padrao, recomendacao), como o gatilho', q.padrao_chave = 'estimativa' and q.padrao_efeito = 'opcao', q.padrao_chave);
    v_res := pg_temp.ok(v_res, 'B4n o backfill alcança toda aberta: nenhuma ficou sem padrão e sem motivo',
      not exists (select 1 from public.agenda_perguntas x where x.estado = 'aberta' and x.padrao_chave is null and x.veto_espera is null), null);
    v_res := pg_temp.ok(v_res, 'B4o o backfill não toca fechada nem liga prazo: a resolvida continua como estava; a variável volta vazia',
      coalesce(current_setting('agenda.backfill_padrao', true), '') = '', null);
    v := pg_temp.recusa(format('update public.agenda_perguntas set padrao_chave = ''sem_peca'', padrao_efeito = ''nada'' where id = %L',
                               (select id from public.agenda_perguntas where chave = 'equipe_cadastro:chamada:2031-03-03')));
    v_res := pg_temp.ok(v_res, 'B4p depois da migration, padrao_* não muda mais', v = 'erro P0001: A pergunta não muda o que pergunta: só se mostra, se responde ou se resolve.', v);
  end if;

  -- ── o gatilho de antes ───────────────────────────────────────────────────────────
  v_q := pg_temp.perg('parada', 'parada:teste-b4q');
  v := pg_temp.recusa(format('update public.agenda_perguntas set padrao_chave = ''sem_peca'', padrao_efeito = ''nada'' where id = %L', v_q));
  v_res := pg_temp.ok(v_res, 'B4q padrao_* não muda na aberta', v like 'erro P0001: A pergunta não muda%', v);
  v_res := pg_temp.ok(v_res, 'B4r veto_espera vai de nulo a dono e a sem_padrao; a outro valor, não; de valor a valor, não; de valor a nulo, não',
    pg_temp.recusa(format('update public.agenda_perguntas set veto_espera = ''dono'' where id = %L', v_q)) = 'aceitou'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_espera = ''sem_padrao'' where id = %L', v_q)) = 'aceitou'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_espera = ''cliente'' where id = %L', v_q)) like 'erro P0001: A pergunta não muda%'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_espera = ''tipo'' where id = %L', v_q)) like 'erro P0001: A pergunta não muda%', null);
  update public.agenda_perguntas set veto_espera = 'dono' where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4s a pergunta que espera o dono não volta: de dono para nulo ou para outro, recusa',
    pg_temp.recusa(format('update public.agenda_perguntas set veto_espera = null where id = %L', v_q)) like 'erro P0001: A pergunta não muda%'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_espera = ''sem_padrao'' where id = %L', v_q)) like 'erro P0001: A pergunta não muda%', null);
  v_q := pg_temp.perg('parada', 'parada:teste-b4t');
  v_res := pg_temp.ok(v_res, 'B4t na aberta, destrava e veto_teria_em mudam, e mudam de novo',
    pg_temp.recusa(format('update public.agenda_perguntas set destrava = 12 where id = %L', v_q)) = 'aceitou'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_teria_em = now() where id = %L', v_q)) = 'aceitou', null);
  update public.agenda_perguntas set destrava = 12, veto_teria_em = now() where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4u a pergunta aberta continua sem mudar o que pergunta: texto, tipo, opções',
    pg_temp.recusa(format('update public.agenda_perguntas set texto = ''Outra.'' where id = %L', v_q)) like 'erro P0001: A pergunta não muda%'
    and pg_temp.recusa(format('update public.agenda_perguntas set recomendacao = 1, opcoes = %L where id = %L', c_op, v_q)) like 'erro P0001: A pergunta não muda%', null);

  -- na fechada: o carimbo, de nulo a valor, uma vez (o prazo do P2 decide por agenda_decidir e carimba depois)
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4v na fechada resolvida, assumida_* de nulo a valor passa; o resto, não',
    pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''prazo'', assumida_em = now() where id = %L', v_q)) = 'aceitou'
    and pg_temp.recusa(format('update public.agenda_perguntas set destrava = 13 where id = %L', v_q)) = 'erro P0001: A pergunta fechada não muda: a decisão registrada fica como foi.'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_teria_em = null where id = %L', v_q)) = 'erro P0001: A pergunta fechada não muda: a decisão registrada fica como foi.', null);
  update public.agenda_perguntas set assumida_por = 'prazo', assumida_em = now() where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4w uma vez só: assumida não muda de valor nem volta a nulo',
    pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''teto'' where id = %L', v_q)) = 'erro P0001: A pergunta fechada não muda: a decisão registrada fica como foi.'
    and pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = null, assumida_em = null where id = %L', v_q)) = 'erro P0001: A pergunta fechada não muda: a decisão registrada fica como foi.', null);
  v_q2 := pg_temp.perg('parada', 'parada:teste-b4x');
  update public.agenda_perguntas set estado = 'vencida', resolvida_motivo = 'teste' where id = v_q2;
  v := pg_temp.recusa(format('update public.agenda_perguntas set assumida_por = ''prazo'', assumida_em = now() where id = %L', v_q2));
  v_res := pg_temp.ok(v_res, 'B4x na vencida, nem o carimbo', v = 'erro P0001: A pergunta fechada não muda: a decisão registrada fica como foi.', v);

  -- o prazo, de valor a valor: só a pergunta que o dono nunca viu antes do prazo, na mesma escrita que a mostra depois dele
  v_q := pg_temp.perg('situacao', 'situacao:teste-b4y', 'opcoes, recomendacao, opcao_padrao, veto_ate', format('%L::jsonb, 1, 1, %L::timestamptz', c_op, c_prazo));
  v_res := pg_temp.ok(v_res, 'B4y nunca mostrada: o prazo vai a um novo na escrita que a mostra depois do prazo; sem mostrar, ou mostrando antes do prazo, não',
    pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = %L::timestamptz + interval ''2 days'', mostrada_vezes = 1, mostrada_em = %L::timestamptz + interval ''1 day'', mostrada_via = ''fechamento'' where id = %L', c_prazo, c_prazo, v_q)) = 'aceitou'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = %L::timestamptz + interval ''2 days'' where id = %L', c_prazo, v_q)) like 'erro P0001: A pergunta não muda%'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = %L::timestamptz + interval ''2 days'', mostrada_vezes = 1, mostrada_em = %L::timestamptz - interval ''1 day'', mostrada_via = ''fechamento'' where id = %L', c_prazo, c_prazo, v_q)) like 'erro P0001: A pergunta não muda%', null);
  v_res := pg_temp.ok(v_res, 'B4z o prazo não anda para trás nem some',
    pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = %L::timestamptz - interval ''2 days'', mostrada_vezes = 1, mostrada_em = %L::timestamptz + interval ''1 day'', mostrada_via = ''fechamento'' where id = %L', c_prazo, c_prazo, v_q)) like 'erro P0001: A pergunta não muda%'
    and pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = null, mostrada_vezes = 1, mostrada_em = %L::timestamptz + interval ''1 day'', mostrada_via = ''fechamento'' where id = %L', c_prazo, v_q)) like 'erro P0001: A pergunta não muda%', null);
  update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = c_prazo - interval '1 day', mostrada_via = 'fechamento' where id = v_q;
  v_res := pg_temp.ok(v_res, 'B4z1 a pergunta mostrada antes do prazo: o que o dono viu nunca muda, mesmo depois de vencer, mesmo mostrando de novo',
    pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = %L::timestamptz + interval ''2 days'', mostrada_vezes = 2, mostrada_em = %L::timestamptz + interval ''1 day'' where id = %L', c_prazo, c_prazo, v_q)) like 'erro P0001: A pergunta não muda%', null);
  v_q2 := pg_temp.perg('situacao', 'situacao:teste-b4z2', 'opcoes, recomendacao, opcao_padrao, veto_ate, mostrada_vezes, mostrada_em, mostrada_via',
                       format('%L::jsonb, 1, 1, %L::timestamptz, 1, %L::timestamptz + interval ''1 hour'', ''aviso''', c_op, c_prazo, c_prazo));
  v_res := pg_temp.ok(v_res, 'B4z2 mostrada só depois do prazo vencido (R2: "nunca mostrada antes do prazo"): ganha o prazo novo quando é mostrada de novo',
    pg_temp.recusa(format('update public.agenda_perguntas set veto_ate = %L::timestamptz + interval ''2 days'', mostrada_vezes = 2, mostrada_em = %L::timestamptz + interval ''1 day'' where id = %L', c_prazo, c_prazo, v_q2)) = 'aceitou', null);

  -- a cópia
  if v_mig = '' or v_mig7a = '' then
    v_res := pg_temp.ok(v_res, 'B4z3 _agenda_perguntas_antes: a cópia', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
  else
    select replace(p.prosrc, E'\r\n', E'\n') into v from pg_proc p where p.oid = 'public._agenda_perguntas_antes()'::regprocedure;
    v_res := pg_temp.ok(v_res, 'B4z3 _agenda_perguntas_antes: o corpo vivo é o desta migration; sem os 2 blocos "-- FASE 7f:", é o de 20261031100000 (a mais nova antes da 7f), byte a byte',
      v = pg_temp.corpo(v_mig, '_agenda_perguntas_antes') and pg_temp.sem_7f(v) = pg_temp.corpo(v_mig7a, '_agenda_perguntas_antes')
      and (select count(*) from regexp_matches(v, '-- FASE 7f: fim', 'g')) = 2,
      format('vivo %s letras; sem blocos %s; origem %s', length(v), length(pg_temp.sem_7f(v)), length(pg_temp.corpo(v_mig7a, '_agenda_perguntas_antes'))));
  end if;
  raise exception using errcode = 'P0001', message = '__desfaz__';
exception when others then
  if sqlerrm <> '__desfaz__' then raise; end if;
  -- o bloco desfaz o que escreveu; o resultado vai depois
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B5. _agenda_zona ───────────────────────────────────────────────────────────────────
do $b5$
declare
  c_hoje  constant date := date '2031-03-11';   -- ter
  v_res   jsonb := '[]'::jsonb;
  v_os    uuid;
  v_cli   uuid;
  v_payee uuid;
  v_cinco date := public.agenda_somar_du(c_hoje, 5);
  v_dez   date := public.agenda_somar_du(c_hoje, 10);
  v_onze  date := public.agenda_somar_du(c_hoje, 11);
  v_prox  date := public.agenda_somar_du(c_hoje, 1);
  v_dois  date := public.agenda_somar_du(c_hoje, 2);
begin
  select id, client_id into v_os, v_cli from public.service_orders where not exists (select 1 from public.os_planejamento pl where pl.service_order_id = service_orders.id) order by id limit 1;
  select id into v_payee from public.payees where active order by id limit 1;
  v_res := pg_temp.ok(v_res, 'B5a hoje e antes de hoje: travada',
    public._agenda_zona(v_os, v_payee, c_hoje, c_hoje) = 'travada' and public._agenda_zona(v_os, v_payee, c_hoje - 3, c_hoje) = 'travada', null);
  v_res := pg_temp.ok(v_res, 'B5b o próximo dia útil (o congelamento): travada; o seguinte, não',
    public._agenda_zona(v_os, v_payee, v_prox, c_hoje) = 'travada' and public._agenda_zona(v_os, v_payee, v_dois, c_hoje) = 'firme', null);
  v_res := pg_temp.ok(v_res, 'B5c até cliente_semana_du dias úteis (10): firme; o 11º: livre',
    public._agenda_zona(v_os, v_payee, v_dez, c_hoje) = 'firme' and public._agenda_zona(v_os, v_payee, v_onze, c_hoje) = 'livre', null);
  update public.agenda_config set congelamento_du = 2 where id;
  v_res := pg_temp.ok(v_res, 'B5d o congelamento vem do parâmetro', public._agenda_zona(v_os, v_payee, v_dois, c_hoje) = 'travada', null);
  update public.agenda_config set congelamento_du = 1, cliente_semana_du = 5 where id;
  v_res := pg_temp.ok(v_res, 'B5e o limite da firme vem do parâmetro', public._agenda_zona(v_os, v_payee, v_cinco, c_hoje) = 'firme'
    and public.agenda_somar_du(c_hoje, 6) = public.agenda_somar_du(v_cinco, 1)
    and public._agenda_zona(v_os, v_payee, public.agenda_somar_du(c_hoje, 6), c_hoje) = 'livre', null);
  update public.agenda_config set cliente_semana_du = 10 where id;

  -- a ficha ligada ou a confirmação da pessoa naquele dia: travada, lá longe; a de sombra não; a recusada não; a de outra pessoa não
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key, estado)
  values (v_payee, v_cinco, 'ficha', 'ligado', 'Ficha de teste.', now(), 'teste-b5:ficha', 'enfileirada');
  v_res := pg_temp.ok(v_res, 'B5f dia com ficha enviada à pessoa: travada, e é o que _agenda_dia_avisado diz (a regra do 7a, chamada)',
    public._agenda_zona(v_os, v_payee, v_cinco, c_hoje) = 'travada' and public._agenda_dia_avisado(v_payee, v_os, v_cinco) = 'equipe'
    and public._agenda_zona(v_os, null, v_cinco, c_hoje) = 'firme' and public._agenda_dia_avisado(null, v_os, v_cinco) is null, null);
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key, estado)
  values (v_payee, v_cinco + 1, 'ficha', 'sombra', 'Ficha de teste.', now(), 'teste-b5:sombra', 'registrada');
  v_res := pg_temp.ok(v_res, 'B5g a ficha em sombra não trava', public._agenda_zona(v_os, v_payee, v_cinco + 1, c_hoje) = 'firme', null);
  -- o cliente: prometido firme cobre o dia; faixa, não
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, prometido_tipo, prometido_de, prometido_ate)
  values (v_os, 1, 'dono', now(), 'firme', v_dez, v_dez);
  v_res := pg_temp.ok(v_res, 'B5h dia firme dito ao cliente: travada; é o cliente em _agenda_dia_avisado',
    public._agenda_zona(v_os, null, v_dez, c_hoje) = 'travada' and public._agenda_dia_avisado(null, v_os, v_dez) = 'cliente', null);
  update public.os_planejamento set prometido_tipo = 'faixa' where service_order_id = v_os;
  v_res := pg_temp.ok(v_res, 'B5i dia em faixa não trava (só firme: _agenda_dia_avisado)', public._agenda_zona(v_os, null, v_dez, c_hoje) = 'firme', null);
  v_res := pg_temp.ok(v_res, 'B5j sem o dia ou sem hoje: null, nada a afirmar',
    public._agenda_zona(v_os, v_payee, null, c_hoje) is null and public._agenda_zona(v_os, v_payee, c_hoje, null) is null, null);
  raise exception using errcode = 'P0001', message = '__desfaz__';
exception when others then
  if sqlerrm <> '__desfaz__' then raise; end if;
  -- o bloco desfaz o que escreveu; o resultado vai depois
  perform pg_temp.gravar(v_res);
end
$b5$;

-- ── B6. As listas fechadas ─────────────────────────────────────────────────────────────
do $b6$
declare
  v_res jsonb := '[]'::jsonb;
  v     text;
  v_dif text;
  v_a   text[];
  v_mig text := coalesce(current_setting('agenda_teste.mig_base_fase7f', true), '');
  r     record;
begin
  for r in select * from (values
    ('public.agenda_acoes', 'agenda_acoes_tipo_check', '{assumir}'::text[]),
    ('public.agenda_perguntas', 'agenda_perguntas_respondida_via_check', '{prazo}'::text[]),
    ('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', '{comunicar}'::text[]),
    ('public.agenda_equipe_mensagens', 'agenda_equipe_mensagens_tipo_check', '{previsto,mudanca,convite}'::text[]),
    ('public.agenda_cliente_mensagens', 'agenda_cliente_mensagens_tipo_check', '{semana}'::text[])
  ) as t(tabela, nome, novos)
  loop
    v_a := pg_temp.lista(r.tabela::regclass, r.nome);
    -- FASE 7g: a 20261112100000 soma explicar depois de comunicar (agenda_fase7g_base.sql B4b confere a lista inteira)
    if r.nome = 'agenda_vigia_rodadas_rotina_check' and v_a[cardinality(v_a)] = 'explicar'
       and exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_porque' and not a.attisdropped) then
      v_a := v_a[1:cardinality(v_a) - 1];
    end if;
    -- FASE 7g: fim
    -- FASE 7g: (7g P5b) a 20261112100700 soma nivel no fim das ações (agenda_fase7g_ok_do_dono.sql K0c confere)
    if r.nome = 'agenda_acoes_tipo_check' and v_a[cardinality(v_a)] = 'nivel' and to_regprocedure('public._agenda_espera_ok(uuid)') is not null then
      v_a := v_a[1:cardinality(v_a) - 1];
    end if;
    -- FASE 7g: fim
    if v_a[cardinality(v_a) - cardinality(r.novos) + 1 : cardinality(v_a)] is distinct from r.novos then
      v_dif := coalesce(v_dif || ' | ', '') || r.nome || ': ' || array_to_string(v_a, ',');
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'B6a as 5 listas: os novos no fim, na ordem', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B6b os de antes iguais e na mesma ordem: as 5 listas, com a contagem da 7d',
    cardinality(pg_temp.lista('public.agenda_equipe_mensagens'::regclass, 'agenda_equipe_mensagens_tipo_check')) = 8
    and (pg_temp.lista('public.agenda_equipe_mensagens'::regclass, 'agenda_equipe_mensagens_tipo_check'))[1:5] = '{ficha,confirmar,como_foi,resposta,dias}'::text[]
    and (pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_respondida_via_check')) = '{whatsapp,painel,tela,prazo}'::text[]
    and (pg_temp.lista('public.agenda_cliente_mensagens'::regclass, 'agenda_cliente_mensagens_tipo_check'))[1:12]
        = '{confirmar,vespera,acesso,material_chegou,andamento,pode_atrasar,nova_data,pronto,pronto_lembrete,pos_servico,mudanca_no_dia,onde_fica}'::text[]
    and 'tarefa' = any (pg_temp.lista('public.agenda_acoes'::regclass, 'agenda_acoes_tipo_check'))
    and 'tarefas' = any (pg_temp.lista('public.agenda_vigia_rodadas'::regclass, 'agenda_vigia_rodadas_rotina_check')), null);
  -- o ampliador
  if v_mig <> '' then
    v_a := pg_temp.lista('public.agenda_acoes'::regclass, 'agenda_acoes_tipo_check');
    execute v_mig;
    v_res := pg_temp.ok(v_res, 'B6c rodar a migration de novo não muda as listas', pg_temp.lista('public.agenda_acoes'::regclass, 'agenda_acoes_tipo_check') = v_a, null);
  end if;
  begin
    perform public._agenda_ampliar_lista('public.agenda_acoes', 'nome_que_nao_existe', 'tipo', array['x']);
    v := 'passou';
  exception when others then v := sqlstate;
  end;
  v_res := pg_temp.ok(v_res, 'B6d o ampliador com o nome errado: 42704, não passa calado', v = '42704', v);
  v := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated', $q$select public._agenda_ampliar_lista('public.agenda_acoes', 'agenda_acoes_tipo_check', 'tipo', array['x'])::text$q$);
  v_res := pg_temp.ok(v_res, 'B6e o ampliador sem grant', v like 'erro 42501%', v);
  -- cliente_tipos_ligados: à mão, e continua "<@"
  v_res := pg_temp.ok(v_res, 'B6f cliente_tipos_ligados: a lista do CHECK aceita semana, e a forma continua "<@" (o ampliador não serve, R8.5-4)',
    (select pg_get_constraintdef(c.oid) like '%<@%''semana''%' from pg_constraint c
      where c.conrelid = 'public.agenda_config'::regclass and c.conname = 'agenda_config_cliente_tipos_ligados_check'), null);
  begin
    perform public._agenda_ampliar_lista('public.agenda_config', 'agenda_config_cliente_tipos_ligados_check', 'cliente_tipos_ligados', array['x']);
    v := 'passou';
  exception when others then v := sqlstate;
  end;
  v_res := pg_temp.ok(v_res, 'B6g o ampliador recusa esse CHECK (22023): por isso à mão', v = '22023', v);
  v_res := pg_temp.ok(v_res, 'B6h o valor da linha não ganhou semana (nasce em teste); pôr semana passa; tipo de fora recusa, com o nome de antes',
    (select not ('semana' = any (c.cliente_tipos_ligados)) from public.agenda_config c where c.id)
    and pg_temp.recusa('update public.agenda_config set cliente_tipos_ligados = cliente_tipos_ligados || ''{semana}''::text[] where id') = 'aceitou'
    and pg_temp.recusa('update public.agenda_config set cliente_tipos_ligados = cliente_tipos_ligados || ''{cobranca}''::text[] where id') = 'agenda_config_cliente_tipos_ligados_check', null);
  v_res := pg_temp.ok(v_res, 'B6i os valores novos entram: a ação assumir, a via prazo, a rodada comunicar',
    pg_temp.recusa($q$insert into public.agenda_acoes (dia, executada, origem, tipo, texto) values (date '2031-01-02', true, 'vigia', 'assumir', 'Teste.')$q$) = 'aceitou'
    and pg_temp.recusa($q$insert into public.agenda_perguntas (tipo, chave, texto, modo, estado, respondida_em, respondida_via) values ('parada', 'parada:teste-b6', 'Teste.', 'ligado', 'respondida', now(), 'prazo')$q$) = 'aceitou'
    and pg_temp.recusa($q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('comunicar', date '2031-01-02', now(), 'sombra', 'sombra')$q$) = 'aceitou', null);
  raise exception using errcode = 'P0001', message = '__desfaz__';
exception when others then
  if sqlerrm <> '__desfaz__' then raise; end if;
  -- o bloco desfaz o que escreveu; o resultado vai depois
  perform pg_temp.gravar(v_res);
end
$b6$;

-- ── B7. modelo ─────────────────────────────────────────────────────────────────────────
do $b7$
declare
  v_dif text;
  r     record;
begin
  for r in select * from (values ('confirmar', 'M1'), ('vespera', 'M2'), ('material_chegou', 'M3'), ('acesso', 'M4'), ('andamento', 'M5'), ('pode_atrasar', 'M6'),
                                 ('nova_data', 'M7'), ('pronto', 'M8'), ('pronto_lembrete', 'M8'), ('pos_servico', 'M9'), ('mudanca_no_dia', 'M10'), ('onde_fica', 'M11'),
                                 ('semana', 'M12')) as t(tipo, modelo)
  loop
    if pg_temp.gerada('public.agenda_cliente_mensagens'::regclass, 'modelo', r.tipo) is distinct from r.modelo then
      v_dif := coalesce(v_dif || ', ', '') || r.tipo || '=' || coalesce(pg_temp.gerada('public.agenda_cliente_mensagens'::regclass, 'modelo', r.tipo), 'nulo');
    end if;
  end loop;
  perform pg_temp.gravar(pg_temp.ok('[]', 'B7a modelo: semana = M12, onde_fica = M11, os 11 de antes iguais', v_dif is null, v_dif));
end
$b7$;

-- ── B8. _agenda_fala_modo ──────────────────────────────────────────────────────────────
do $b8$
declare
  v_res  jsonb := '[]'::jsonb;
  v_dif  text;
  v_n    int := 0;
  v      text;
  r      record;
  m      text;
  f      boolean;
begin
  foreach m in array array['desligado', 'sombra', 'ligado'] loop
    foreach f in array array[false, true] loop
      perform pg_temp.modos(m);
      update public.agenda_config set gestor_so_propor = f where id;
      for r in select * from (values ('bloco', false), ('lote', false), ('veto', true), ('previsto', true), ('convite', true), ('camadas', true)) as t(item, freia) loop
        v_n := v_n + 1;
        v := public._agenda_fala_modo(r.item);
        if v is distinct from (case when f and r.freia and m = 'ligado' then 'sombra' else m end) then
          v_dif := coalesce(v_dif || ' | ', '') || format('%s %s freio=%s → %s', r.item, m, f, v);
        end if;
      end loop;
    end loop;
  end loop;
  perform pg_temp.modos('desligado');
  update public.agenda_config set gestor_so_propor = false where id;
  v_res := pg_temp.ok(v_res, format('B8a os %s casos: ligado + freio = sombra em veto, previsto, convite e camadas; bloco e lote ficam (R8.6); desligado continua desligado', v_n), v_dif is null, v_dif);
  update public.agenda_config set modo_bloco_agenda = 'ligado', modo_lote_dono = 'sombra', modo_veto = 'ligado', modo_equipe_previsto = 'sombra', modo_equipe_convite = 'desligado', modo_cliente_camadas = 'ligado' where id;
  v_res := pg_temp.ok(v_res, 'B8b cada item lê o interruptor dele',
    public._agenda_fala_modo('bloco') = 'ligado' and public._agenda_fala_modo('lote') = 'sombra' and public._agenda_fala_modo('veto') = 'ligado'
    and public._agenda_fala_modo('previsto') = 'sombra' and public._agenda_fala_modo('convite') = 'desligado' and public._agenda_fala_modo('camadas') = 'ligado', null);
  perform pg_temp.modos('desligado');
  begin
    perform public._agenda_fala_modo('outro');
    v := 'passou';
  exception when others then v := sqlstate;
  end;
  v_res := pg_temp.ok(v_res, 'B8c item que não existe = 22023', v = '22023', v);
  begin
    perform public._agenda_fala_modo(null);
    v := 'passou';
  exception when others then v := sqlstate;
  end;
  v_res := pg_temp.ok(v_res, 'B8d item nulo = 22023', v = '22023', v);
  raise exception using errcode = 'P0001', message = '__desfaz__';
exception when others then
  if sqlerrm <> '__desfaz__' then raise; end if;
  -- o bloco desfaz o que escreveu; o resultado vai depois
  perform pg_temp.gravar(v_res);
end
$b8$;

-- ── B9. _agenda_classe_da_saida ────────────────────────────────────────────────────────
do $b9$
declare
  c_hoje  constant date := date '2031-03-11';   -- ter
  c_agora constant timestamptz := timestamptz '2031-03-11 17:30-03';
  c_op    constant jsonb := '[{"n": 1}, {"n": 2}]';
  v_res   jsonb := '[]'::jsonb;
  v_os    uuid;
  v_os2   uuid;
  v_os3   uuid;
  v_cli   uuid;
  v_payee uuid;
  v_prox  date := public.agenda_somar_du(c_hoje, 1);
  v_lon   date := public.agenda_somar_du(c_hoje, 6);
  v_al    uuid;
  v_q     uuid;
  v_a     uuid;
  v_a2    uuid;
  j       jsonb;
  v       text;
begin
  select id, client_id into v_os, v_cli from public.service_orders where not exists (select 1 from public.os_planejamento pl where pl.service_order_id = service_orders.id) order by id limit 1;
  select id into v_os2 from public.service_orders where id <> v_os and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = service_orders.id) order by id limit 1;
  select id into v_payee from public.payees where active order by id limit 1;

  -- linha, e o que lança
  j := public._agenda_classe_da_saida('linha', null, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9a linha = informação, sem efeito', j ->> 'classe' = 'informacao' and not (j ->> 'excecao')::boolean and j -> 'afeta' = '{"equipe": false, "cliente": false, "dono": false}', j::text);
  begin perform public._agenda_classe_da_saida('outro', null, c_hoje, c_agora); v := 'passou'; exception when others then v := sqlstate; end;
  v_res := pg_temp.ok(v_res, 'B9b tipo que não existe = 22023', v = '22023', v);
  begin perform public._agenda_classe_da_saida('acao', gen_random_uuid(), null, c_agora); v := 'passou'; exception when others then v := sqlstate; end;
  v_res := pg_temp.ok(v_res, 'B9c sem o dia = 22004', v = '22004', v);
  begin perform public._agenda_classe_da_saida('acao', gen_random_uuid(), c_hoje, c_agora); v := 'passou'; exception when others then v := sqlstate; end;
  v_res := pg_temp.ok(v_res, 'B9d ação que não existe lança: quem chama diz que não leu, nunca "é só informação"', v = 'P0002', v);
  begin perform public._agenda_classe_da_saida('pergunta', gen_random_uuid(), c_hoje, c_agora); v := 'passou'; exception when others then v := sqlstate; end;
  v_res := pg_temp.ok(v_res, 'B9e pergunta que não existe lança', v = 'P0002', v);

  -- pergunta
  v_q := pg_temp.perg('nao_cabe', 'nao_cabe:teste-b9a', 'opcoes, recomendacao, perda_em', format('%L::jsonb, 1, %L::date', c_op, v_prox));
  j := public._agenda_classe_da_saida('pergunta', v_q, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9f pergunta aberta em ligado = decisão; crítica que perde até o próximo dia útil = exceção',
    j ->> 'classe' = 'decisao' and (j ->> 'excecao')::boolean and (j ->> 'dia')::date = v_prox and j ->> 'zona' = 'travada', j::text);
  v_q := pg_temp.perg('nao_cabe', 'nao_cabe:teste-b9b', 'opcoes, recomendacao, perda_em', format('%L::jsonb, 1, %L::date', c_op, v_lon));
  j := public._agenda_classe_da_saida('pergunta', v_q, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9g crítica que perde depois: decisão, sem exceção', j ->> 'classe' = 'decisao' and not (j ->> 'excecao')::boolean, j::text);
  v_q := pg_temp.perg('parada', 'parada:teste-b9c', 'perda_em', format('%L::date', v_prox));
  j := public._agenda_classe_da_saida('pergunta', v_q, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9h não crítica que perde amanhã: sem exceção', j ->> 'classe' = 'decisao' and not (j ->> 'excecao')::boolean, j::text);
  v_q := pg_temp.perg('nao_cabe', 'nao_cabe:teste-b9d', 'opcoes, recomendacao', format('%L::jsonb, 1', c_op));
  j := public._agenda_classe_da_saida('pergunta', v_q, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9i crítica sem perda_em: sem exceção, e não nulo (R8.12-2)', (j -> 'excecao') = 'false'::jsonb, j::text);
  insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('parada', 'parada:teste-b9e', 'Pergunta de teste.', 'sombra') returning id into v_q;
  j := public._agenda_classe_da_saida('pergunta', v_q, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9j pergunta em sombra = informação', j ->> 'classe' = 'informacao', j::text);
  v_q := pg_temp.perg('parada', 'parada:teste-b9f');
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_q;
  j := public._agenda_classe_da_saida('pergunta', v_q, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9j2 pergunta fechada = informação', j ->> 'classe' = 'informacao', j::text);

  -- ação: a alocação de um dia longe, com e sem o que a pessoa já sabe
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem)
  values (v_os, v_payee, v_prox, 'manha', 'turno', 'execucao', 'publicada', 'motor') returning id into v_al;
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, texto)
  values (c_hoje, false, 'vigia', 'criar', v_os, array[v_os], array[v_al], 'Em teste: marcaria.') returning id into v_a;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9k ação em sombra = informação', j ->> 'classe' = 'informacao' and not (j ->> 'excecao')::boolean, j::text);
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, texto, desfazivel_ate)
  values (c_hoje, true, 'vigia', 'criar', v_os, array[v_os], array[v_al], 'Marquei.', c_agora + interval '1 day') returning id into v_a;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9l ação executada = mudança; ninguém soube: sem exceção, mesmo no próximo dia útil; o dia é o da alocação, a zona travada',
    j ->> 'classe' = 'mudanca' and (j ->> 'dia')::date = v_prox and j ->> 'zona' = 'travada' and not (j ->> 'excecao')::boolean
    and j -> 'afeta' = '{"equipe": false, "cliente": false, "dono": false}', j::text);

  -- a equipe: mensagem em sombra não conta; ligada e enfileirada conta; recusada não conta; por dias[] conta
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key, estado) values (v_payee, v_prox, 'ficha', 'sombra', 'Teste.', now(), 'teste-b9:1', 'enfileirada');
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9m a ficha em sombra não afeta a equipe', not (j #>> '{afeta,equipe}')::boolean, j::text);
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key, estado, recusa_motivo) values (v_payee, v_prox, 'ficha', 'ligado', 'Teste.', now(), 'teste-b9:2', 'recusada', 'janela');
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9n a ficha recusada não afeta a equipe (as 3 fichas da história foram recusadas)', not (j #>> '{afeta,equipe}')::boolean, j::text);
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key, estado, dias) values (v_payee, c_hoje, 'previsto', 'ligado', 'Teste.', now(), 'teste-b9:3', 'enfileirada', array[v_prox]);
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9o o previsto que DIZ o dia, em dias[], afeta a equipe; com o dia até o próximo dia útil, exceção',
    (j #>> '{afeta,equipe}')::boolean and (j ->> 'excecao')::boolean and not (j #>> '{afeta,cliente}')::boolean, j::text);
  update public.agenda_acoes set desfeita_em = c_agora, desfeita_pela = v_a where id = v_a;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9p ação desfeita = informação', j ->> 'classe' = 'informacao', j::text);

  -- a equipe, longe: mexe no que sabem, mas não é exceção
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem)
  values (v_os2, v_payee, v_lon, 'manha', 'turno', 'execucao', 'publicada', 'motor') returning id into v_al;
  insert into public.agenda_equipe_mensagens (payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key, estado) values (v_payee, v_lon, 'ficha', 'ligado', 'Teste.', now(), 'teste-b9:4', 'enfileirada');
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas, texto, desfazivel_ate)
  values (c_hoje, true, 'vigia', 'cancelar', v_os2, array[v_os2], array[v_al], 'Tirei.', c_agora + interval '1 day') returning id into v_a;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9q a cancelada conta como a criada; o dia longe mexe no que a pessoa sabe, mas não é exceção; a zona vem da ficha',
    (j #>> '{afeta,equipe}')::boolean and not (j ->> 'excecao')::boolean and j ->> 'zona' = 'travada' and (j ->> 'dia')::date = v_lon, j::text);

  -- o cliente: fora do intervalo dito
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, prometido_tipo, prometido_de, prometido_ate)
  values (v_os2, 1, 'dono', now(), 'faixa', v_prox, v_prox);
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9r o dia fora do prometido afeta o cliente', (j #>> '{afeta,cliente}')::boolean, j::text);
  update public.os_planejamento set prometido_de = v_lon, prometido_ate = v_lon + 10 where service_order_id = v_os2;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9s o dia dentro do prometido, sem plano vigente: não afeta o cliente', not (j #>> '{afeta,cliente}')::boolean, j::text);

  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem)
  values (v_os2, v_payee, public.agenda_somar_du(v_lon, 12), 'manha', 'turno', 'execucao', 'publicada', 'motor');
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9s2 o dia dentro, e o fim do plano fora do prometido: afeta o cliente', (j #>> '{afeta,cliente}')::boolean, j::text);

  update public.os_planejamento set prometido_de = v_lon + 1, prometido_ate = public.agenda_somar_du(v_lon, 12) where service_order_id = v_os2;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9s3 o fim dentro, e o dia fora do prometido: afeta o cliente', (j #>> '{afeta,cliente}')::boolean, j::text);
  select id into v_os3 from public.service_orders where id <> all (array[v_os, v_os2]) and not exists (select 1 from public.os_planejamento pl where pl.service_order_id = service_orders.id)
     and not exists (select 1 from public.agenda_alocacoes al where al.service_order_id = service_orders.id) order by id limit 1;
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, prometido_tipo, prometido_de, prometido_ate)
  values (v_os3, 1, 'dono', now(), 'faixa', c_hoje, c_hoje + 3);
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, texto)
  values (c_hoje, true, 'vigia', 'status', v_os3, array[v_os3], 'Mudei o status.') returning id into v_a2;
  j := public._agenda_classe_da_saida('acao', v_a2, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9s4 prometido e nenhum dia no plano (o fim é nulo): não afeta, e não vira nulo (R8.12-2)', (j -> 'afeta' -> 'cliente') = 'false'::jsonb, j::text);

  -- o dono: outra ação da mesma OS já contada
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, texto, contada_em, contada_via)
  values (c_hoje, false, 'vigia', 'mover', v_os2, array[v_os2], 'Em teste: moveria.', c_agora, 'fechamento');
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9t ação em sombra contada não conta para o dono', not (j #>> '{afeta,dono}')::boolean, j::text);
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, texto, contada_em, contada_via, desfazivel_ate)
  values (c_hoje, true, 'vigia', 'publicar', null, array[v_os2], 'Publiquei.', c_agora, 'fechamento', c_agora + interval '1 day');
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9u a publicação contada, com a OS em os_ids, afeta o dono', (j #>> '{afeta,dono}')::boolean, j::text);

  -- a falta: tipo equipe, sem alocação, o dia em depois
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
  values (c_hoje, true, 'equipe', 'equipe', v_os, array[v_os], v_payee, jsonb_build_object('motivo', 'nao_vou', 'dia', v_prox), 'O Teste avisou que não vem.') returning id into v_a;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9v a falta para o próximo dia útil = exceção; o dia é o que a ação diz, não o dela', (j ->> 'excecao')::boolean and (j ->> 'dia')::date = v_prox and j ->> 'zona' = 'travada', j::text);
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
  values (c_hoje, true, 'equipe', 'equipe', v_os, array[v_os], v_payee, jsonb_build_object('motivo', 'sem_sim', 'dia', v_lon), 'O Teste não confirmou.') returning id into v_a;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9w a falta de um dia longe: sem exceção', not (j ->> 'excecao')::boolean and (j ->> 'dia')::date = v_lon, j::text);
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, payee_id, depois, texto)
  values (c_hoje, true, 'equipe', 'equipe', v_os, array[v_os], v_payee, jsonb_build_object('motivo', 'outra', 'dia', v_prox), 'Outra coisa da equipe.') returning id into v_a;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9x tipo equipe com outro motivo: não é exceção', not (j ->> 'excecao')::boolean, j::text);
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, depois, texto)
  values (c_hoje, true, 'vigia', 'status', v_os, array[v_os], '{"dia": "amanhã"}', 'Mudei o status.') returning id into v_a;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9y depois.dia que não é data não quebra a leitura: fica o dia da ação', (j ->> 'dia')::date = c_hoje, j::text);
  -- o cliente que ouviu o dia, com alocação na ação
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem)
  values (v_os, v_payee, v_prox, 'tarde', 'turno', 'execucao', 'publicada', 'motor') returning id into v_al;
  insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, texto)
  values (c_hoje, true, 'vigia', 'criar', v_os, array[v_os], array[v_al], 'Marquei.') returning id into v_a2;
  j := public._agenda_classe_da_saida('acao', v_a2, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9y2 ninguém disse o dia ao cliente: não afeta', not (j #>> '{afeta,cliente}')::boolean, j::text);
  update public.service_orders set client_confirmed_for = (v_prox + time '08:00') at time zone 'America/Sao_Paulo' where id = v_os;
  j := public._agenda_classe_da_saida('acao', v_a2, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9y3 o cliente confirmou o dia da alocação: afeta o cliente, e é exceção', (j #>> '{afeta,cliente}')::boolean and (j ->> 'excecao')::boolean, j::text);
  -- o cliente que ouviu o dia, sem alocação na ação
  update public.service_orders set client_confirmed_for = (c_hoje + time '08:00') at time zone 'America/Sao_Paulo' where id = v_os;
  j := public._agenda_classe_da_saida('acao', v_a, c_hoje, c_agora);
  v_res := pg_temp.ok(v_res, 'B9z o cliente ouviu o dia: afeta o cliente, e o dia é hoje: exceção', (j #>> '{afeta,cliente}')::boolean and (j ->> 'excecao')::boolean, j::text);
  raise exception using errcode = 'P0001', message = '__desfaz__';
exception when others then
  if sqlerrm <> '__desfaz__' then raise; end if;
  -- o bloco desfaz o que escreveu; o resultado vai depois
  perform pg_temp.gravar(v_res);
end
$b9$;

-- ── B10. Nada muda de comportamento ────────────────────────────────────────────────────
insert into _resultado
select 'B10a o gatilho novo é o único: 1 BEFORE INSERT em agenda_perguntas, e vem depois de agenda_perguntas_antes',
       count(*) filter (where t.tgname = 'agenda_perguntas_padrao') = 1
       and count(*) filter (where t.tgfoid = 'public._agenda_perguntas_padrao()'::regprocedure) = 1
       and 'agenda_perguntas_antes' < 'agenda_perguntas_padrao',
       string_agg(t.tgname, ', ' order by t.tgname)
  from pg_trigger t
 where t.tgrelid = 'public.agenda_perguntas'::regclass and not t.tgisinternal;

do $b10$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_base_fase7f', true), '');
  v_dif  text;
  v_a    text;
  c_hoje constant date := date '2026-10-29';
  c_agor constant timestamptz := timestamptz '2026-10-29 16:52-03';
  r      record;
begin
  if v_mig = '' then
    v_res := pg_temp.ok(v_res, 'B10b as funções da migration', true, 'PULADO: sem agenda_teste.mig_base_fase7f (rode pela bancada)');
  else
    select string_agg(distinct m[1], ',' order by m[1]) into v_a
      from regexp_matches(v_mig, 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
    v_res := pg_temp.ok(v_res, 'B10b a migration só cria as 5 novas e recria _agenda_perguntas_antes: nada do motor, da vigia nem dos textos',
      v_a = '_agenda_classe_da_saida,_agenda_fala_modo,_agenda_padrao_da_pergunta,_agenda_perguntas_antes,_agenda_perguntas_padrao,_agenda_zona', v_a);
  end if;
  select string_agg(p.proname, ',' order by p.proname) into v_dif
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname not in ('_agenda_classe_da_saida', '_agenda_fala_modo', '_agenda_padrao_da_pergunta', '_agenda_perguntas_antes', '_agenda_perguntas_padrao', '_agenda_zona')
     and p.prosrc ~ '_agenda_(classe_da_saida|fala_modo|zona)\(|padrao_chave|padrao_efeito|veto_espera|veto_teria_em|assumida_por|assumida_em|modo_bloco_agenda|modo_lote_dono|modo_veto|modo_equipe_previsto|modo_equipe_convite|modo_cliente_camadas|veto_tipos|comunicar_tempo_max'
     -- (quem vier depois nesta etapa entra aqui)
     and p.proname not in ('_agenda_comunicar_teto', '_agenda_pergunta_assumir', '_agenda_pergunta_espera', '_agenda_pergunta_frases', '_agenda_pergunta_linha', 'agenda_comunicar_rodar', 'agenda_perguntas_em_ordem')  -- P2
     and p.proname not in ('agenda_bloco_do_fechamento')  -- P3
     and p.proname not in ('_agenda_comunicar_lote_guardaria', '_agenda_comunicar_quinta', '_agenda_e_excecao', '_agenda_lote_ligado')  -- P4
     and p.proname not in ('_agenda_saude_comunicacao', 'agenda_veto_dito', 'agenda_saude')  -- P7 (agenda_saude: a marca "-- (7f" dentro do bloco do gestor, não o bloco)
     and p.proname not in ('_agenda_comunicar_convites', '_agenda_comunicar_convites_vencidos', '_agenda_comunicar_mudancas_equipe', '_agenda_comunicar_previsto',
                           '_agenda_equipe_mudanca_na_hora')  -- P5
     and p.proname not in ('_agenda_cliente_camada', '_agenda_cliente_semana')  -- P6
     and p.proname not in ('_agenda_cliente_semana_mudou')  -- P9
     and p.proname not in ('_agenda_gestor_puxar')  -- 7e P4b (R7.7-8: o convite sem o SIM, pela mesma regra da ficha, lê _agenda_fala_modo)
     and p.proname not in ('_agenda_acoes_porque')  -- 7g P2 (a zona da ação, §3.1 item 5: chama _agenda_zona, que não lê o freio)
     -- 7g P6 (o placar conta as perguntas assumidas, assumida_em; a saúde do rebaixar lê o veto por _agenda_fala_modo, R9.6)
     and p.proname not in ('_agenda_placar_numeros', '_agenda_saude_explicar')
     -- 7g P5b (o "espera o seu ok", 20261112100700: _agenda_espera_ok lê modo_veto CRU, de propósito — R9.6, a reserva fica com o freio —; o nível de
     -- _agenda_explicar_tipos lê o veto por _agenda_fala_modo, R9.6)
     and p.proname not in ('_agenda_espera_ok', '_agenda_explicar_tipos')
     and not exists (select 1 from regexp_matches(coalesce(p.prosrc, ''), '-- FASE 7f:') x);
  v_res := pg_temp.ok(v_res, 'B10c nenhuma função de antes lê as colunas nem chama as funções novas: o gatilho é a única porta', v_dif is null, v_dif);
  v_res := pg_temp.ok(v_res, 'B10d sem dado: nenhuma ação assumir, rodada comunicar, mensagem previsto, mudanca, convite nem semana; ninguém assumida',
    not exists (select 1 from public.agenda_acoes where tipo = 'assumir')
    and not exists (select 1 from public.agenda_vigia_rodadas where rotina = 'comunicar')
    and not exists (select 1 from public.agenda_equipe_mensagens where tipo in ('previsto', 'mudanca', 'convite'))
    and not exists (select 1 from public.agenda_cliente_mensagens where tipo = 'semana')
    and not exists (select 1 from public.agenda_perguntas where assumida_por is not null or veto_teria_em is not null or destrava <> 0), null);
  perform pg_temp.gravar(v_res);
end
$b10$;

-- As leituras: md5 nos 6 modos desligados, em sombra e ligados com o freio (o que a migration de dado e o ligar fazem), no replay de 29/10 e na fixture
do $b10$
declare
  c_hoje constant date := date '2026-11-10';
  c_agor constant timestamptz := timestamptz '2026-11-10 17:30-03';
  v_res  jsonb := '[]'::jsonb;
  v_ref  jsonb;
  v      text;
  v_dif  text;
  v_n    int := 0;
  f      boolean;
  r      record;
begin
  if coalesce(current_setting('agenda_teste.fase7f', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B10e as leituras', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  execute current_setting('agenda_teste.fase7f');
  create temp table _leitura (nome text, sql text) on commit drop;
  insert into _leitura values
    -- (P3) a chave bloco existe fora de desligado e vai só ao detalhe (R8.6): o resto da saída é que é byte a byte (agenda_fase7f_bloco.sql, L6)
    ('agenda_textos_do_fechamento', format('select (public.agenda_textos_do_fechamento(%L::date) - ''bloco'')::text', c_hoje)),
    ('_agenda_linhas_do_fechamento', format('select public._agenda_linhas_do_fechamento(%L::date)::text', c_hoje)),
    ('agenda_decisoes_abertas', format('select public.agenda_decisoes_abertas(%L::timestamptz)::text', c_agor)),
    ('_agenda_ver_decisoes', format('select public._agenda_ver_decisoes(%L::date, %L::timestamptz)::text', c_hoje, c_agor)),
    ('agenda_aprontar', format('select public.agenda_aprontar(%L::date)::text', c_hoje)),
    ('agenda_aviso_pecas', format('select public.agenda_aviso_pecas(%L::date, %L::timestamptz)::text', c_hoje, c_agor)),
    -- (P7) a chave comunicacao traz os 6 modos crus (R8.6: a saúde lê o modo cru): o resto da saída é que é byte a byte (agenda_fase7f_leituras.sql, V3a)
    ('agenda_saude', format('select (public.agenda_saude(%L::date, %L::timestamptz) - ''comunicacao'')::text', c_hoje, c_agor));
  -- Sombra é byte a byte (R8.6): com e sem o freio, o desligado é a régua. Com o freio (o caso real), veto, previsto, convite e camadas ligados valem sombra: as leituras
  -- também não mudam. Bloco e lote ligados ficam de fora: eles mudam de propósito no P3 e no P4.
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
         set modo_veto = 'ligado', modo_equipe_previsto = 'ligado', modo_equipe_convite = 'ligado', modo_cliente_camadas = 'ligado'
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
  perform pg_temp.gravar(pg_temp.ok('[]', format('B10e as 7 leituras dão o mesmo md5 de desligado: em sombra, com e sem o freio; com o freio, veto, previsto, convite e camadas ligados (%s leituras)', v_n), v_dif is null, v_dif));

  -- o modo de cada tipo de pergunta é o de antes em qualquer um dos 6 e com o freio: _agenda_modo_da_pergunta não é recriada e segue crua
  perform pg_temp.modos('desligado');
  update public.agenda_config set gestor_so_propor = false where id;
  create temp table _modo_antes on commit drop as
    select t, public._agenda_modo_da_pergunta(t, t || ':x') as modo
      from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t;
  perform pg_temp.modos('ligado');
  select string_agg(a.t, ',') into v_dif from _modo_antes a where public._agenda_modo_da_pergunta(a.t, a.t || ':x') is distinct from a.modo;
  perform pg_temp.gravar(pg_temp.ok('[]', 'B10f _agenda_modo_da_pergunta: os 6 modos não mudam o modo de nenhum tipo', v_dif is null, v_dif));
  perform pg_temp.modos('desligado');
end
$b10$;

-- ── B11. A fixture ─────────────────────────────────────────────────────────────────────
do $b11$
declare
  v_res jsonb := '[]'::jsonb;
  v     text;
  v_n   int;
begin
  if coalesce(current_setting('agenda_teste.fase7f', true), '') = '' then
    perform pg_temp.gravar(pg_temp.ok('[]', 'B11a a fixture', true, 'PULADO: sem agenda_teste.fase7f (rode pela bancada)'));
    return;
  end if;
  -- já carregada por B10
  v_res := pg_temp.ok(v_res, 'B11a as 8 abertas da §8.2, todas ligadas: só elas estão abertas',
    (select count(*) = 8 and bool_and(q.modo = 'ligado') from public.agenda_perguntas q where q.estado = 'aberta'),
    (select string_agg(q.tipo, ',' order by q.criada_em) from public.agenda_perguntas q where q.estado = 'aberta'));
  v_res := pg_temp.ok(v_res, 'B11b só padrao_do_dono, duracao, material_conferir, fornecedores_prazo, parada e a do Giancarlo nascem sem espera; Flávio espera o cliente, a diária o dinheiro',
    (select string_agg(q.tipo || ':' || coalesce(q.veto_espera, '-'), ',' order by q.criada_em) from public.agenda_perguntas q where q.estado = 'aberta')
    = 'padrao_do_dono:-,duracao:-,material_conferir:-,fornecedores_prazo:-,parada:-,nao_cabe:cliente,nao_cabe:-,diaria:dinheiro',
    (select string_agg(q.tipo || ':' || coalesce(q.veto_espera, '-'), ',' order by q.criada_em) from public.agenda_perguntas q where q.estado = 'aberta'));
  v_res := pg_temp.ok(v_res, 'B11c duas mostradas com prazo (vencem ter 10/11 18:00), uma de carona, sem prazo',
    (select count(*) = 2 and bool_and(q.mostrada_vezes = 1 and q.mostrada_via = 'fechamento') from public.agenda_perguntas q where q.estado = 'aberta' and q.veto_ate = timestamptz '2026-11-10 18:00-03')
    and (select q.veto_ate is null and q.carona_em is not null from public.agenda_perguntas q where q.estado = 'aberta' and q.tipo = 'parada'), null);
  v_res := pg_temp.ok(v_res, 'B11d os textos das perguntas têm o tamanho real, 253 a 449 letras (R8.4, R8.12-8)',
    (select min(char_length(q.texto)) >= 253 and max(char_length(q.texto)) <= 449 from public.agenda_perguntas q where q.estado = 'aberta'),
    (select min(char_length(q.texto)) || '..' || max(char_length(q.texto)) from public.agenda_perguntas q where q.estado = 'aberta'));
  v_res := pg_temp.ok(v_res, 'B11e só 2 das 6 OS têm linha em os_planejamento (OS sem linha é o caso comum, R8.12-3)',
    (select count(*) = 2 from public.os_planejamento pl join public.service_orders so on so.id = pl.service_order_id where so.service_order_number ~ '^OS-F[1-6]$'), null);
  v_res := pg_temp.ok(v_res, 'B11f o plano: Nelson 3 dias pela estimativa; Vanderlei hoje 4 meios-dias, 1 não cumprido por material; a ficha, o previsto e o convite do Roberto; a semana do Nelson',
    (select count(*) = 6 and bool_and(a.duracao_fonte = 'orcamento') from public.agenda_alocacoes a join public.service_orders so on so.id = a.service_order_id where so.service_order_number = 'OS-F1' and a.estado = 'publicada')
    and (select count(*) = 4 and count(*) filter (where a.resultado = 'nao_cumprido' and a.motivo = 'material') = 1 from public.agenda_alocacoes a join public.service_orders so on so.id = a.service_order_id where so.service_order_number = 'OS-F3' and a.dia = date '2026-11-10')
    and (select count(*) = 3 from public.agenda_equipe_mensagens m where m.modo = 'ligado' and m.tipo in ('previsto', 'convite', 'ficha') and m.dedupe_key like 'agenda-equipe:%:roberto:%')
    and (select count(*) = 1 from public.agenda_cliente_mensagens m where m.tipo = 'semana' and m.modelo = 'M12'), null);
  v_res := pg_temp.ok(v_res, 'B11g as 4 ações de hoje: 3 executadas não contadas, 1 em sombra',
    (select count(*) = 4 and count(*) filter (where a.executada) = 3 and bool_and(a.contada_em is null) from public.agenda_acoes a where a.id::text like 'f7f00000%'), null);
  v_res := pg_temp.ok(v_res, 'B11h a classe na fixture: a do Lenine sem exceção; a do Flávio, a tarde de hoje com ficha, exceção; a sombra é informação',
    not (public._agenda_classe_da_saida('acao', 'f7f00000-0000-4000-8000-000000000601', date '2026-11-10', timestamptz '2026-11-10 17:30-03') ->> 'excecao')::boolean
    and (public._agenda_classe_da_saida('acao', 'f7f00000-0000-4000-8000-000000000603', date '2026-11-10', timestamptz '2026-11-10 17:30-03') ->> 'excecao')::boolean
    and public._agenda_classe_da_saida('acao', 'f7f00000-0000-4000-8000-000000000604', date '2026-11-10', timestamptz '2026-11-10 17:30-03') ->> 'classe' = 'informacao', null);
  v_n := (select count(*) from public.service_orders);
  execute current_setting('agenda_teste.fase7f');
  v_res := pg_temp.ok(v_res, 'B11i carregar 2× = 1×', (select count(*) from public.service_orders) = v_n, null);
  perform pg_temp.gravar(v_res);
end
$b11$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
