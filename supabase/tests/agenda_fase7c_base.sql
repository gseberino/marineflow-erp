-- Prova da base da Agenda de Produção, Fase 7c (pacote P1): a tabela das etiquetas, os 3 interruptores e os 17 parâmetros, as colunas
-- novas do planejamento e da alocação, as listas fechadas ampliadas, a regra única "a equipe atende" e as leituras puras (o que cada
-- pessoa faz, o que a OS pede, o responsável, os meios-dias sem quem o serviço pede e sem o responsável), as 3 recriadas
-- (_agenda_tecnico_declarado e _agenda_e_novato com a etiqueta e o [c3-conf]; _agenda_modo_da_pergunta com habilidade) e a fixture da
-- etapa (migration 20261102100000; spec-fase7c §4, §5.1, §6.1, §6.2, §8.3, R5.1-5, R5.1-6, R5.4, R5.5).
-- bancada: depende de 20261102100000
--
--   B1  colunas, DEFAULTs e CHECKs: agenda_config (os 3 interruptores nascem desligados na linha com o DEFAULT sombra; os 17
--       parâmetros com o valor da spec), os_planejamento e agenda_alocacoes; cada CHECK novo tem um caso que ele recusa (a regra e a
--       expressão regular inválidas também) e os limites que entram; os verbos de habilidade_verbos conferidos contra o catálogo
--   B2  RLS e privilégios: agenda_etiquetas (anon nada; o técnico lê 0 e não grava); os_exigencias com o técnico = 42501; as portas
--       das 10 novas, dos 2 gatilhos e das 3 recriadas
--   B3  as listas fechadas: as de antes iguais e na mesma ordem, habilidade no fim; critica não muda; habilidade não é crítica
--   B4  agenda_etiquetas: não se apaga; só as trocas de estado da §4.3; instala × ajudante se excluem; uma viva por etiqueta; a
--       proposta do gestor nunca troca o que o dono disse; os CHECKs da tabela
--   B5  agenda_habilidades: o padrão, o dono, a proposta não vale, o vale do gestor e do dono, o nível 0, o ajudante corta instala em 1,
--       o novo é papel 2, quem vem sob demanda, os textos da §6.2 byte a byte, a ordem e a população
--   B6  os_exigencias na carteira real (as 11 OS do §2, com o sistema e o verbo de produção): as máscaras e os textos byte a byte; o dito
--       tira e amplia; a linha de logística e a de sistema nenhum ficam fora; a regra de sistema só com o verbo da lista; a paridade
--       com os gatilhos de dupla (banco_cc, ca_energizado ⇒ energizado)
--   B7  a tabela-verdade de _agenda_atende (cada código; o dono no turno; a altura do dono; o par do novo; a ordem)
--   B8  _agenda_lider_da_os (dono, fez, planejado, o ajudante não é líder, p_ignorar, a diária ligada, o desempate, nenhum)
--   B9  _agenda_meios_sem_quem_pede (a 179 com o João ajudante sozinho no último meio-dia; o fechamento do dono cobre; a equipe dita;
--       o novo sozinho) e _agenda_lideres_ausentes (a 175)
--   B10 _agenda_du_h
--   B11 o R5.1-5: _agenda_tecnico_declarado e _agenda_e_novato nas variantes do R5.1-6 (contra as definições da 100860 rodadas como
--       pg_temp), o papel novo (o [c3-rev]: o dia fixo sem perfil), o [c3-conf] (o declarado no meio da semana, medido na segunda), a
--       etiqueta que tira e a que põe; as 3 cópias só mudam nos blocos "-- FASE 7c:"; o modo de cada tipo de pergunta
--   B12 a fixture: a variante real (só o Alex e o dono), a sintética (Roberto e João de volta, o Bruno com o padrão dele, as OS 171 a
--       179), as linhas reais completadas; carregar 2× = 1×
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7c_base.sql
--   Seguro em produção: tudo dentro de subtransações desfeitas e termina em ROLLBACK. B1v, B6, B8, B9, B11 e B12 usam as fixtures e as
--   migrations como texto e só rodam na bancada (fora dela saem PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

-- Executa um comando e diz que porta o recusou: o nome do CHECK, do índice único ou da FK; 'aceitou' quando entrou (e
-- desfaz); 'erro <estado>: <mensagem>' para o resto.
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
-- O texto sem os blocos "-- FASE 7c: … -- FASE 7c: fim" (as linhas de abrir e de fechar saem junto; a "-- antes: <linha>" de dentro
-- de um bloco volta como a linha de antes, com o recuo dela).
create function pg_temp.sem_7c(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- FASE 7[cdefg]:' and l !~ '^\s*-- FASE 7[cdefg]: fim' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro and l ~ '^\s*-- FASE 7[cdefg]: fim' then
      v_dentro := false;
      continue;
    end if;
    if v_dentro then
      if l ~ '^\s*-- antes: ' then
        v_fora := v_fora || regexp_replace(l, '^(\s*)-- antes: ', '\1');
      end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;

-- FASE 7d: o texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim" (para o B11d comparar a viva com as da 7c, na mesma régua de antes)
create function pg_temp.sem_7d(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[defg]:' and l !~ '^\s*-- FASE 7[defg]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[defg]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[defg]: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- FASE 7d: fim

create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by created_at limit 1
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
-- as fixtures como texto (só na bancada)
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7a', true), '') <> ''
     and coalesce(current_setting('agenda_teste.replay2910', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_base_fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_correcao3_fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.mig_tabelas_fase7b', true), '') <> ''
$f$;
-- a fixture da 7c (o que ainda não está, entra): equipe 'real' = só o Alex e o dono; a variante do novato; as etiquetas 'mv'
create function pg_temp.carregar(p_equipe text, p_variante text default '', p_etiquetas text default '') returns void
language plpgsql as $f$
begin
  perform set_config('agenda_teste.fase7b_equipe', coalesce(p_equipe, ''), true);
  perform set_config('agenda_teste.fase7c_variante', coalesce(p_variante, ''), true);
  perform set_config('agenda_teste.fase7c_etiquetas', coalesce(p_etiquetas, ''), true);
  execute current_setting('agenda_teste.fase7c');
  perform set_config('agenda_teste.fase7c_variante', '', true);
  perform set_config('agenda_teste.fase7c_etiquetas', '', true);
end $f$;
-- uma pessoa de teste (diarista, ativa) e uma etiqueta
create function pg_temp.gente(p_nome text, p_criado timestamptz default timestamptz '2026-08-01 10:00-03') returns uuid
language sql as $f$
  insert into public.payees (name, kind, active, phone, created_at, updated_at)
  values (p_nome, 'diarista', true, null, p_criado, p_criado) returning id
$f$;
create function pg_temp.etiqueta(p_payee uuid, p_etiqueta text, p_nivel int, p_origem text, p_estado text default 'vale',
                                 p_motivo text default 'você disse', p_em timestamptz default timestamptz '2026-11-03 16:10-03')
returns uuid language sql as $f$
  insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em)
  values (p_payee, p_etiqueta, p_nivel, p_origem, p_estado, p_motivo, case when p_estado = 'vale' then p_em end, p_em)
  returning id
$f$;
-- o texto de agenda_habilidades de uma pessoa: "i c a p fonte.papel | texto"
create function pg_temp.hab(p_payee uuid, p_hoje date default date '2026-11-04') returns text language sql stable as $f$
  select format('%s%s%s%s %s | %s', h.instala, h.comissiona, h.altura, h.papel, h.fonte ->> 'papel', h.texto)
    from public.agenda_habilidades(p_hoje, array[p_payee]) h
$f$;

-- ── B1. Colunas, DEFAULTs e CHECKs ──────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B1a agenda_config: os 3 interruptores nascem desligados na linha e o DEFAULT da coluna é sombra; os 17 parâmetros com o valor da spec (§4.1; AG7-10 "pode tudo, menos comissionar")',
       c.modo_habilidade = 'desligado' and c.modo_lider = 'desligado' and c.modo_habilidade_propor = 'desligado'
       and (select bool_and(pg_get_expr(d.adbin, d.adrelid) like '''sombra''%') and count(*) = 3
              from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.agenda_config'::regclass
               and a.attname in ('modo_habilidade', 'modo_lider', 'modo_habilidade_propor'))
       and c.habilidade_padrao = '{"instala": 2, "comissiona": 0, "altura": 2}'::jsonb
       and c.habilidade_dono = '{"instala": 3, "comissiona": 3, "altura": 2}'::jsonb
       and c.habilidade_nivel_energizado = 2 and c.habilidade_nivel_comissionar = 3 and c.habilidade_nivel_diagnostico = 2
       and c.habilidade_nivel_altura = 2 and c.habilidade_nivel_par = 2 and c.habilidade_fechamento_cobre
       and c.habilidade_verbos = '{instalacao,substituicao,adequacao,reparo,configuracao,manutencao}'
       and jsonb_array_length(c.habilidade_regras) = 9
       and c.habilidade_regras -> 0 = '["comissionamento", "todos", "tipo", "commissioning"]'::jsonb
       and c.habilidade_regras -> 8 ->> 0 = 'altura' and c.habilidade_regras -> 8 ->> 3 like '(teto|%|arco)'
       and (select array_agg(k order by k) from jsonb_object_keys(c.habilidade_palavras) k)
           = '{ajudante,altura,comissiona,diagnostico,energizado,instala}'
       and c.habilidade_janela_dias = 90 and c.habilidade_instala_dias = 60 and c.habilidade_instala_diarias = 20
       and c.habilidade_hora = time '16:10' and c.habilidade_conferir_semanas = 2 and c.lider_espera_max_du = 2
       -- (o que a 7c não cria: o prazo do veto da 7a e o novato da 7b, com o mesmo valor)
       and c.veto_du = 1 and c.veto_hora = time '18:00' and c.novato_dias = 30 and c.novato_diarias = 10,
       null
  from public.agenda_config c where c.id;

insert into _resultado
select 'B1b agenda_config: as 20 colunas novas (os 3 interruptores e os 17 parâmetros), todas NOT NULL com DEFAULT e comentário, com o tipo da spec; habilidade_veto_du e habilidade_novato_* não existem',
       count(*) = 20 and bool_and(a.attnotnull and a.atthasdef) and bool_and(col_description(a.attrelid, a.attnum) is not null)
       and string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
           = 'habilidade_conferir_semanas:smallint,habilidade_dono:jsonb,habilidade_fechamento_cobre:boolean,'
             'habilidade_hora:time without time zone,habilidade_instala_diarias:smallint,habilidade_instala_dias:smallint,'
             'habilidade_janela_dias:smallint,habilidade_nivel_altura:smallint,habilidade_nivel_comissionar:smallint,'
             'habilidade_nivel_diagnostico:smallint,habilidade_nivel_energizado:smallint,habilidade_nivel_par:smallint,'
             'habilidade_padrao:jsonb,habilidade_palavras:jsonb,habilidade_regras:jsonb,habilidade_verbos:text[],'
             'lider_espera_max_du:smallint,modo_habilidade:text,modo_habilidade_propor:text,modo_lider:text'
       and not exists (select 1 from pg_attribute x where x.attrelid = 'public.agenda_config'::regclass and not x.attisdropped
                                                     and x.attname ~ '^habilidade_(veto|novato)'),
       string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
  from pg_attribute a
 where a.attrelid = 'public.agenda_config'::regclass and not a.attisdropped
   and (a.attname like 'habilidade\_%' or a.attname in ('modo_habilidade', 'modo_lider', 'modo_habilidade_propor', 'lider_espera_max_du'));

insert into _resultado
select 'B1c as colunas novas das outras tabelas, com o tipo da spec (exigencias_ditas e criterio_detalhe NOT NULL com DEFAULT {}; o resto nulo); cada coluna com comentário; a FK do responsável on delete set null',
       string_agg(c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod)
                  || case when a.attnotnull then '!' else '' end
                  || coalesce('=' || pg_get_expr(d.adbin, d.adrelid), ''), ',' order by c.relname, a.attname)
       = 'agenda_alocacoes.criterio:text,agenda_alocacoes.criterio_detalhe:jsonb!=''{}''::jsonb,'
         'os_planejamento.exigencias_ditas:jsonb!=''{}''::jsonb,os_planejamento.exigencias_trecho:text,'
         'os_planejamento.lider_em:timestamp with time zone,os_planejamento.lider_payee_id:uuid,os_planejamento.lider_trecho:text'
       and bool_and(col_description(c.oid, a.attnum) is not null)
       and (select k.confdeltype = 'n' and k.confrelid = 'public.payees'::regclass from pg_constraint k
             where k.conrelid = 'public.os_planejamento'::regclass and k.contype = 'f'
               and k.conkey = array[(select attnum from pg_attribute where attrelid = 'public.os_planejamento'::regclass
                                                                       and attname = 'lider_payee_id')]),
       string_agg(c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod)
                  || case when a.attnotnull then '!' else '' end
                  || coalesce('=' || pg_get_expr(d.adbin, d.adrelid), ''), ',' order by c.relname, a.attname)
  from pg_attribute a join pg_class c on c.oid = a.attrelid
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where not a.attisdropped
   and ((c.oid = 'public.os_planejamento'::regclass
         and a.attname in ('exigencias_ditas', 'exigencias_trecho', 'lider_payee_id', 'lider_em', 'lider_trecho'))
     or (c.oid = 'public.agenda_alocacoes'::regclass and a.attname in ('criterio', 'criterio_detalhe')));

-- os casos de cada CHECK (um que ele recusa e os limites que entram)
create temp table _casos (grupo text, nome text, sql text, espera text) on commit drop;
insert into _casos values
  ('config', 'modo_habilidade x', $q$update public.agenda_config set modo_habilidade = 'x'$q$, 'agenda_config_modo_habilidade_check'),
  ('config', 'modo_lider x', $q$update public.agenda_config set modo_lider = 'x'$q$, 'agenda_config_modo_lider_check'),
  ('config', 'modo_habilidade_propor x', $q$update public.agenda_config set modo_habilidade_propor = 'x'$q$, 'agenda_config_modo_habilidade_propor_check'),
  ('config', 'o padrão com chave a mais', $q$update public.agenda_config set habilidade_padrao = '{"instala": 2, "comissiona": 0, "altura": 2, "solda": 1}'$q$, 'agenda_config_habilidade_padrao_check'),
  ('config', 'o padrão sem altura', $q$update public.agenda_config set habilidade_padrao = '{"instala": 2, "comissiona": 0}'$q$, 'agenda_config_habilidade_padrao_check'),
  ('config', 'o padrão com instala 0', $q$update public.agenda_config set habilidade_padrao = '{"instala": 0, "comissiona": 0, "altura": 2}'$q$, 'agenda_config_habilidade_padrao_check'),
  ('config', 'o padrão com comissiona 4', $q$update public.agenda_config set habilidade_padrao = '{"instala": 2, "comissiona": 4, "altura": 2}'$q$, 'agenda_config_habilidade_padrao_check'),
  ('config', 'o padrão com altura 2,5', $q$update public.agenda_config set habilidade_padrao = '{"instala": 2, "comissiona": 0, "altura": 2.5}'$q$, 'agenda_config_habilidade_padrao_check'),
  ('config', 'o padrão com texto', $q$update public.agenda_config set habilidade_padrao = '{"instala": "2", "comissiona": 0, "altura": 2}'$q$, 'agenda_config_habilidade_padrao_check'),
  ('config', 'o do dono com altura 4', $q$update public.agenda_config set habilidade_dono = '{"instala": 3, "comissiona": 3, "altura": 4}'$q$, 'agenda_config_habilidade_dono_check'),
  ('config', 'nível energizado 0', $q$update public.agenda_config set habilidade_nivel_energizado = 0$q$, 'agenda_config_habilidade_nivel_energizado_check'),
  ('config', 'nível energizado 4', $q$update public.agenda_config set habilidade_nivel_energizado = 4$q$, 'agenda_config_habilidade_nivel_energizado_check'),
  ('config', 'nível de comissionar 4', $q$update public.agenda_config set habilidade_nivel_comissionar = 4$q$, 'agenda_config_habilidade_nivel_comissionar_check'),
  ('config', 'nível de diagnóstico 0', $q$update public.agenda_config set habilidade_nivel_diagnostico = 0$q$, 'agenda_config_habilidade_nivel_diagnostico_check'),
  ('config', 'nível de altura 4', $q$update public.agenda_config set habilidade_nivel_altura = 4$q$, 'agenda_config_habilidade_nivel_altura_check'),
  ('config', 'nível do par 0', $q$update public.agenda_config set habilidade_nivel_par = 0$q$, 'agenda_config_habilidade_nivel_par_check'),
  ('config', 'as regras vazias', $q$update public.agenda_config set habilidade_regras = '[]'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'uma regra com 3 coisas', $q$update public.agenda_config set habilidade_regras = '[["altura", "todos", "palavra"]]'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'a exigência que não existe', $q$update public.agenda_config set habilidade_regras = '[["solda", "todos", "palavra", "solda"]]'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'o alcance que não existe', $q$update public.agenda_config set habilidade_regras = '[["altura", "meio", "palavra", "teto"]]'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'a fonte que não existe', $q$update public.agenda_config set habilidade_regras = '[["altura", "todos", "foto", "teto"]]'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'a regra sem valor', $q$update public.agenda_config set habilidade_regras = '[["altura", "todos", "palavra", " "]]'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'a regra com número', $q$update public.agenda_config set habilidade_regras = '[["altura", "todos", "palavra", 3]]'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'a regra que não é lista', $q$update public.agenda_config set habilidade_regras = '{"altura": "teto"}'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'a palavra com expressão inválida', $q$update public.agenda_config set habilidade_regras = '[["altura", "todos", "palavra", "(teto"]]'$q$, 'agenda_config_habilidade_regras_check'),
  ('config', 'as palavras sem diagnostico', $q$update public.agenda_config set habilidade_palavras = habilidade_palavras - 'diagnostico'$q$, 'agenda_config_habilidade_palavras_check'),
  ('config', 'as palavras com uma chave a mais', $q$update public.agenda_config set habilidade_palavras = habilidade_palavras || '{"solda": "sold"}'$q$, 'agenda_config_habilidade_palavras_check'),
  ('config', 'a palavra com expressão inválida (a guarda do trecho)', $q$update public.agenda_config set habilidade_palavras = habilidade_palavras || '{"altura": "(teto"}'$q$, 'agenda_config_habilidade_palavras_check'),
  ('config', 'a palavra vazia', $q$update public.agenda_config set habilidade_palavras = habilidade_palavras || '{"instala": ""}'$q$, 'agenda_config_habilidade_palavras_check'),
  ('config', 'a janela de 29 dias', $q$update public.agenda_config set habilidade_janela_dias = 29$q$, 'agenda_config_habilidade_janela_dias_check'),
  ('config', 'a janela de 366 dias', $q$update public.agenda_config set habilidade_janela_dias = 366$q$, 'agenda_config_habilidade_janela_dias_check'),
  ('config', '"instala sozinho" com 13 dias de casa', $q$update public.agenda_config set habilidade_instala_dias = 13$q$, 'agenda_config_habilidade_instala_dias_check'),
  ('config', '"instala sozinho" com 366 dias de casa', $q$update public.agenda_config set habilidade_instala_dias = 366$q$, 'agenda_config_habilidade_instala_dias_check'),
  ('config', '"instala sozinho" com 4 diárias', $q$update public.agenda_config set habilidade_instala_diarias = 4$q$, 'agenda_config_habilidade_instala_diarias_check'),
  ('config', '"instala sozinho" com 121 diárias', $q$update public.agenda_config set habilidade_instala_diarias = 121$q$, 'agenda_config_habilidade_instala_diarias_check'),
  ('config', 'a rodada antes do meio-dia (11:59)', $q$update public.agenda_config set habilidade_hora = '11:59'$q$, 'agenda_config_habilidade_hora_check'),
  ('config', 'a rodada depois da publicação', $q$update public.agenda_config set habilidade_hora = hora_do_plano + interval '1 minute'$q$, 'agenda_config_habilidade_hora_check'),
  ('config', 'conferir 0 semanas', $q$update public.agenda_config set habilidade_conferir_semanas = 0$q$, 'agenda_config_habilidade_conferir_semanas_check'),
  ('config', 'conferir 7 semanas', $q$update public.agenda_config set habilidade_conferir_semanas = 7$q$, 'agenda_config_habilidade_conferir_semanas_check'),
  ('config', 'esperar o responsável −1 dia útil', $q$update public.agenda_config set lider_espera_max_du = -1$q$, 'agenda_config_lider_espera_max_du_check'),
  ('config', 'esperar o responsável 11 dias úteis', $q$update public.agenda_config set lider_espera_max_du = 11$q$, 'agenda_config_lider_espera_max_du_check'),
  ('config', 'os limites que entram (os 3 ligados, os máximos, a rodada na hora da publicação, uma regra só, o fechamento que não cobre)',
   $q$update public.agenda_config set modo_habilidade = 'ligado', modo_lider = 'ligado', modo_habilidade_propor = 'ligado',
        habilidade_padrao = '{"altura": 3, "instala": 3, "comissiona": 3}', habilidade_dono = '{"instala": 1, "comissiona": 0, "altura": 0}',
        habilidade_nivel_energizado = 3, habilidade_nivel_comissionar = 3, habilidade_nivel_diagnostico = 3, habilidade_nivel_altura = 3,
        habilidade_nivel_par = 3, habilidade_fechamento_cobre = false, habilidade_regras = '[["diagnostico", "ultimo", "verbo", "diagnostico"]]',
        habilidade_janela_dias = 365, habilidade_instala_dias = 365, habilidade_instala_diarias = 120, habilidade_hora = hora_do_plano,
        habilidade_conferir_semanas = 6, lider_espera_max_du = 10$q$, 'aceitou'),
  ('config', 'os outros limites que entram (desligados e sombra, os mínimos, a rodada ao meio-dia, uma palavra só por chave)',
   $q$update public.agenda_config set modo_habilidade = 'sombra', modo_lider = 'desligado', modo_habilidade_propor = 'sombra',
        habilidade_nivel_energizado = 1, habilidade_nivel_comissionar = 1, habilidade_nivel_diagnostico = 1, habilidade_nivel_altura = 1,
        habilidade_nivel_par = 1, habilidade_janela_dias = 30, habilidade_instala_dias = 14, habilidade_instala_diarias = 5,
        habilidade_hora = '12:00', habilidade_conferir_semanas = 1, lider_espera_max_du = 0,
        habilidade_palavras = '{"instala": "a", "ajudante": "b", "comissiona": "c", "altura": "d", "energizado": "e", "diagnostico": "f"}'$q$,
   'aceitou'),
  -- os_planejamento (a 1ª OS que existir; o upsert desfeito)
  ('planejamento', 'o dono disse uma exigência que não existe',
   $q$insert into public.os_planejamento (service_order_id, exigencias_ditas) select so.id, '{"solda": "todos"}' from public.service_orders so order by so.id limit 1 on conflict (service_order_id) do update set exigencias_ditas = excluded.exigencias_ditas$q$,
   'os_planejamento_exigencias_ditas_check'),
  ('planejamento', 'o dono disse "talvez"',
   $q$insert into public.os_planejamento (service_order_id, exigencias_ditas) select so.id, '{"altura": "talvez"}' from public.service_orders so order by so.id limit 1 on conflict (service_order_id) do update set exigencias_ditas = excluded.exigencias_ditas$q$,
   'os_planejamento_exigencias_ditas_check'),
  ('planejamento', 'o dono disse um número',
   $q$insert into public.os_planejamento (service_order_id, exigencias_ditas) select so.id, '{"altura": 1}' from public.service_orders so order by so.id limit 1 on conflict (service_order_id) do update set exigencias_ditas = excluded.exigencias_ditas$q$,
   'os_planejamento_exigencias_ditas_check'),
  ('planejamento', 'o responsável sem a data',
   $q$insert into public.os_planejamento (service_order_id, lider_payee_id) select so.id, (select py.id from public.payees py order by py.id limit 1) from public.service_orders so order by so.id limit 1 on conflict (service_order_id) do update set lider_payee_id = excluded.lider_payee_id, lider_em = null$q$,
   'os_planejamento_lider_coerente'),
  ('planejamento', 'o trecho do que a OS pede com 501 letras',
   $q$insert into public.os_planejamento (service_order_id, exigencias_trecho) select so.id, repeat('a', 501) from public.service_orders so order by so.id limit 1 on conflict (service_order_id) do update set exigencias_trecho = excluded.exigencias_trecho$q$,
   'os_planejamento_exigencias_trecho_check'),
  ('planejamento', 'o trecho do responsável com 301 letras',
   $q$insert into public.os_planejamento (service_order_id, lider_trecho) select so.id, repeat('a', 301) from public.service_orders so order by so.id limit 1 on conflict (service_order_id) do update set lider_trecho = excluded.lider_trecho$q$,
   'os_planejamento_lider_trecho_check'),
  ('planejamento', 'as quatro ditas e o responsável com a data (o que entra)',
   $q$insert into public.os_planejamento (service_order_id, exigencias_ditas, exigencias_trecho, lider_payee_id, lider_em, lider_trecho) select so.id, '{"energizado": "todos", "comissionamento": "ultimo", "altura": "nao", "diagnostico": "todos"}', 'trecho', (select py.id from public.payees py order by py.id limit 1), now(), 'o responsável é ele' from public.service_orders so order by so.id limit 1 on conflict (service_order_id) do update set exigencias_ditas = excluded.exigencias_ditas, lider_payee_id = excluded.lider_payee_id, lider_em = excluded.lider_em$q$,
   'aceitou'),
  -- agenda_alocacoes (uma alocação nova de teste, num dia longe; desfeita)
  ('alocacao', 'o critério que não existe',
   $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, criterio) select (select so.id from public.service_orders so order by so.id limit 1), (select py.id from public.payees py order by py.id limit 1), date '2027-03-01', 'manha', 'turno', 'execucao', 'publicada', 'motor', now(), 'sorte'$q$,
   'agenda_alocacoes_criterio_check'),
  ('alocacao', 'o detalhe do critério que não é objeto',
   $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, criterio_detalhe) select (select so.id from public.service_orders so order by so.id limit 1), (select py.id from public.payees py order by py.id limit 1), date '2027-03-01', 'manha', 'turno', 'execucao', 'publicada', 'motor', now(), '[]'$q$,
   'agenda_alocacoes_criterio_detalhe_check'),
  ('alocacao', 'o critério presenca_do_dono com o detalhe (o que entra)',
   $q$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em, criterio, criterio_detalhe) select (select so.id from public.service_orders so order by so.id limit 1), (select py.id from public.payees py order by py.id limit 1), date '2027-03-01', 'manha', 'turno', 'execucao', 'publicada', 'motor', now(), 'presenca_do_dono', '{"regra": "7c"}'$q$,
   'aceitou'),
  -- agenda_etiquetas (os CHECKs nomeados da tabela; a pessoa de teste nasce e some no mesmo comando)
  ('etiqueta', 'instala 0 (o 0 só em comissiona e altura)',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em) select id, 'instala', 0, 'dono', 'vale', 'você disse', now(), now() from p$q$,
   'etiqueta_nivel_zero'),
  ('etiqueta', 'vale sem a data',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, criado_em) select id, 'instala', 2, 'dono', 'vale', 'você disse', now() from p$q$,
   'etiqueta_vale_tem_data'),
  ('etiqueta', 'proposta com a data de valer',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em) select id, 'instala', 2, 'gestor', 'proposta', '32 diárias', now(), now() from p$q$,
   'etiqueta_proposta_sem_data'),
  ('etiqueta', 'o dono propondo',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, criado_em) select id, 'instala', 2, 'dono', 'proposta', 'você disse', now() from p$q$,
   'etiqueta_dono_vale'),
  ('etiqueta', 'substituída sem a data',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, criado_em) select id, 'instala', 2, 'gestor', 'substituida', '32 diárias', now() from p$q$,
   'etiqueta_substituida'),
  ('etiqueta', 'a etiqueta que não existe',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em) select id, 'solda', 2, 'dono', 'vale', 'você disse', now(), now() from p$q$,
   'agenda_etiquetas_etiqueta_check'),
  ('etiqueta', 'o nível 4',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em) select id, 'altura', 4, 'dono', 'vale', 'você disse', now(), now() from p$q$,
   'agenda_etiquetas_nivel_check'),
  ('etiqueta', 'a origem que não existe',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em) select id, 'altura', 2, 'ia', 'vale', 'você disse', now(), now() from p$q$,
   'agenda_etiquetas_origem_check'),
  ('etiqueta', 'o estado que não existe',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, criado_em) select id, 'altura', 2, 'gestor', 'talvez', 'sobe', now() from p$q$,
   'agenda_etiquetas_estado_check'),
  ('etiqueta', 'o motivo de 2 letras',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em) select id, 'altura', 2, 'dono', 'vale', 'ok', now(), now() from p$q$,
   'agenda_etiquetas_motivo_check'),
  ('etiqueta', 'a evidência que não é objeto',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, evidencia, criado_em) select id, 'altura', 2, 'gestor', 'proposta', 'sobe', '[]', now() from p$q$,
   'agenda_etiquetas_evidencia_check'),
  ('etiqueta', 'o trecho com 501 letras',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em) select id, 'altura', 2, 'dono', 'vale', 'você disse', repeat('a', 501), now(), now() from p$q$,
   'agenda_etiquetas_trecho_check'),
  ('etiqueta', 'o que entra (a proposta do gestor; a vale do dono com nível 0 de altura)',
   $q$with p as (insert into public.payees (name, kind, active) values ('TESTE AG7C', 'diarista', true) returning id), a as (insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, criado_em) select id, 'instala', 2, 'gestor', 'proposta', '32 diárias desde 23/08', now() from p returning payee_id) insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em) select payee_id, 'altura', 0, 'dono', 'vale', 'você disse', now(), now() from a$q$,
   'aceitou');

insert into _resultado
select format('B1 %s: %s', k.grupo, k.nome), r = k.espera, r
  from _casos k, lateral (select pg_temp.recusa(k.sql) as r) x;

-- Todos os CHECKs nomeados desta migration: existem e cada um tem caso (um CHECK novo sem prova reprova aqui).
create temp table _checks_f7c (tabela regclass, nome text, primary key (tabela, nome)) on commit drop;
insert into _checks_f7c
select 'public.agenda_config'::regclass, 'agenda_config_' || n || '_check'
  from unnest(array['modo_habilidade', 'modo_lider', 'modo_habilidade_propor', 'habilidade_padrao', 'habilidade_dono',
                    'habilidade_nivel_energizado', 'habilidade_nivel_comissionar', 'habilidade_nivel_diagnostico',
                    'habilidade_nivel_altura', 'habilidade_nivel_par', 'habilidade_regras', 'habilidade_palavras',
                    'habilidade_janela_dias', 'habilidade_instala_dias', 'habilidade_instala_diarias', 'habilidade_hora',
                    'habilidade_conferir_semanas', 'lider_espera_max_du']) n
union all
select t::regclass, n from (values
  ('public.os_planejamento', 'os_planejamento_exigencias_ditas_check'), ('public.os_planejamento', 'os_planejamento_lider_coerente'),
  ('public.agenda_alocacoes', 'agenda_alocacoes_criterio_check'),
  ('public.agenda_etiquetas', 'etiqueta_nivel_zero'), ('public.agenda_etiquetas', 'etiqueta_vale_tem_data'),
  ('public.agenda_etiquetas', 'etiqueta_proposta_sem_data'), ('public.agenda_etiquetas', 'etiqueta_dono_vale'),
  ('public.agenda_etiquetas', 'etiqueta_substituida'),
  -- os CHECKs na linha das colunas (o nome é o que o Postgres dá: <tabela>_<coluna>_check)
  ('public.os_planejamento', 'os_planejamento_exigencias_trecho_check'), ('public.os_planejamento', 'os_planejamento_lider_trecho_check'),
  ('public.agenda_alocacoes', 'agenda_alocacoes_criterio_detalhe_check'),
  ('public.agenda_etiquetas', 'agenda_etiquetas_etiqueta_check'), ('public.agenda_etiquetas', 'agenda_etiquetas_nivel_check'),
  ('public.agenda_etiquetas', 'agenda_etiquetas_origem_check'), ('public.agenda_etiquetas', 'agenda_etiquetas_estado_check'),
  ('public.agenda_etiquetas', 'agenda_etiquetas_motivo_check'), ('public.agenda_etiquetas', 'agenda_etiquetas_evidencia_check'),
  ('public.agenda_etiquetas', 'agenda_etiquetas_trecho_check')) as x(t, n);

insert into _resultado
select 'B1z os 36 CHECKs desta migration (os 26 nomeados e os 10 na linha das colunas) existem e todos têm caso (nenhum ficou sem prova); nenhum outro CHECK em agenda_etiquetas',
       count(*) = 36
       and (select count(*) from pg_constraint c where c.conrelid = 'public.agenda_etiquetas'::regclass and c.contype = 'c')
           = (select count(*) from _checks_f7c x where x.tabela = 'public.agenda_etiquetas'::regclass)
       and bool_and(exists (select 1 from pg_constraint c where c.conrelid = k.tabela and c.conname = k.nome
                                                                       and c.contype = 'c'))
       and bool_and(exists (select 1 from _casos x where x.espera = k.nome)),
       format('%s; sem constraint: %s; sem caso: %s', count(*),
              coalesce(string_agg(k.nome, ', ') filter (where not exists (select 1 from pg_constraint c
                         where c.conrelid = k.tabela and c.conname = k.nome)), '—'),
              coalesce(string_agg(k.nome, ', ') filter (where not exists (select 1 from _casos x where x.espera = k.nome)), '—'))
  from _checks_f7c k;

-- B1v os verbos de habilidade_verbos contra o catálogo: o bloco da migration rodado de novo (o texto entre as marcas "verbos")
do $b1v$
declare
  v_mig   text := replace(coalesce(current_setting('agenda_teste.mig_base_fase7c', true), ''), E'\r\n', E'\n');
  v_bloco text;
  a       text;
  b       text;
  c       text;
begin
  if v_mig = '' then
    insert into _resultado values ('B1v os verbos conferidos contra o catálogo', true, 'PULADO: sem agenda_teste.mig_base_fase7c (rode pela bancada)');
    return;
  end if;
  v_bloco := substr(v_mig, position('-- ── verbos: início' in v_mig));
  v_bloco := left(v_bloco, position('-- ── verbos: fim' in v_bloco) - 1);
  begin
    if to_regclass('public.service_verbs') is null then
      create table public.service_verbs (slug text primary key, name text, active boolean default true);
    end if;
    -- (a) o catálogo vazio: nada a conferir
    a := pg_temp.recusa(format('do $x$ begin delete from public.service_verbs where false; end $x$; %s', v_bloco));
    if not exists (select 1 from public.service_verbs) then
      insert into public.service_verbs (slug, name)
      select s, s from unnest(array['instalacao', 'substituicao', 'reparo', 'diagnostico', 'manutencao', 'remocao', 'configuracao',
                                    'adequacao', 'logistica', 'projeto']) s;
    end if;
    -- (b) o catálogo de produção: todos estão
    b := pg_temp.recusa(v_bloco);
    -- (c) um verbo que não existe
    c := pg_temp.recusa('update public.agenda_config set habilidade_verbos = habilidade_verbos || ''{solda}''; ' || v_bloco);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado values ('B1v os verbos de habilidade_verbos conferidos contra o catálogo de verbos (service_verbs) pela migration: o catálogo vazio e o de produção passam; um verbo que não está nele = 23514',
    position('-- ── verbos: início' in v_mig) > 0 and a = 'aceitou' and b = 'aceitou'
    and c = 'erro 23514: agenda_config.habilidade_verbos: {solda} não estão no catálogo de verbos (service_verbs).',
    format('%s | %s | %s', a, b, c));
end
$b1v$;

-- ── B2. RLS e privilégios ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B2a agenda_etiquetas: RLS ligada e uma policy só, de leitura, TO authenticated (admin/financeiro); anon sem nada; authenticated só lê; service_role escreve; os 3 gatilhos (não apaga, só muda o estado, exclusiva)',
       c.relrowsecurity
       and (select count(*) from pg_policy p where p.polrelid = c.oid) = 1
       and (select bool_and(p.polcmd = 'r' and p.polroles = array[(select oid from pg_roles where rolname = 'authenticated')]
                            and pg_get_expr(p.polqual, p.polrelid) like '%is_admin_or_financial%')
              from pg_policy p where p.polrelid = c.oid)
       and not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('anon', c.oid, 'insert')
       and has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'insert')
       and not has_table_privilege('authenticated', c.oid, 'update') and not has_table_privilege('authenticated', c.oid, 'delete')
       and has_table_privilege('service_role', c.oid, 'insert') and has_table_privilege('service_role', c.oid, 'update')
       and (select string_agg(t.tgname || ':' || t.tgfoid::regproc::text, ',' order by t.tgname)
              from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal)
           = 'agenda_etiquetas_exclusiva:_agenda_etiquetas_exclusiva,agenda_etiquetas_nao_apaga:_agenda_registro_nao_apaga,'
             'agenda_etiquetas_so_muda:_agenda_etiquetas_so_muda'
       and (select pg_get_indexdef(i.indexrelid) like '%UNIQUE%(payee_id, etiqueta)%'
                   and pg_get_expr(i.indpred, i.indrelid) like '%proposta%vale%'
              from pg_index i where i.indexrelid = 'public.agenda_etiquetas_viva'::regclass),
       (select string_agg(t.tgname, ',') from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal)
  from pg_class c where c.oid = 'public.agenda_etiquetas'::regclass;

do $b2$
declare
  v_res jsonb := '[]'::jsonb;
  v_p   uuid;
  v_os  uuid := (select so.id from public.service_orders so order by so.id limit 1);
  a     text;
  b     text;
  c     text;
  d     text;
  e     text;
  f     text;
begin
  begin
    v_p := pg_temp.gente('TESTE AG7C Leitura');
    perform pg_temp.etiqueta(v_p, 'instala', 2, 'dono');
    a := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated', $q$select count(*)::text from public.agenda_etiquetas$q$);
    b := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
           format($q$insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, vale_desde, criado_em) values ('%s', 'altura', 0, 'dono', 'vale', 'você disse', now(), now()) returning 'x'$q$, v_p));
    c := pg_temp.como(null, 'anon', $q$select count(*)::text from public.agenda_etiquetas$q$);
    d := pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated', format($q$select public.os_exigencias('%s', date '2026-11-04')::text$q$, v_os));
    e := pg_temp.como(null, 'anon', format($q$select public.os_exigencias('%s', date '2026-11-04')::text$q$, v_os));
    f := pg_temp.como(pg_temp.adm(), 'authenticated',
           format($q$select (public.os_exigencias('%s', date '2026-11-04') ->> 'ok') || '/' || (select count(*) from public.agenda_etiquetas e where e.payee_id = '%s')
                       || '/' || (select h.texto from public.agenda_habilidades(date '2026-11-04', array['%s'::uuid]) h)$q$, v_os, v_p, v_p));
    -- o serviço (a vigia, a rodada) sem login: as duas leituras
    f := f || ' | ' || pg_temp.como(null, 'service_role',
           format($q$select (public.os_exigencias('%s', date '2026-11-04') ->> 'ok') || '/' || (select h.texto from public.agenda_habilidades(date '2026-11-04', array['%s'::uuid]) h)$q$, v_os, v_p));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B2b o técnico: as etiquetas voltam vazias e gravar dá 42501; anon não lê nem chama; os_exigencias com o técnico = 42501 "O que a OS pede é com o administrador ou o financeiro."; o administrador e o serviço leem as duas leituras (os textos de dentro também)',
    a = '0' and b like 'erro 42501%' and c like 'erro 42501%'
    and d = 'erro 42501: O que a OS pede é com o administrador ou o financeiro.' and e like 'erro 42501%'
    and f = 'true/1/Teste: instala sozinho (você disse). | true/Teste: instala sozinho (você disse).',
    format('%s | %s | %s | %s | %s | %s', a, b, c, d, e, f));
  perform pg_temp.gravar(v_res);
end
$b2$;

with f(sig, quem, vol) as (values
  ('public.agenda_habilidades(date, uuid[])', 'leitura', 's'),
  ('public.os_exigencias(uuid, date)', 'leitura', 's'),
  ('public._agenda_habilidade_config_ok(text, jsonb)', 'leitura', 'i'),
  ('public._agenda_tecnico_declarado(uuid, date)', 'leitura', 's'),
  ('public._agenda_e_novato(uuid, date)', 'leitura', 's'),
  ('public._agenda_modo_da_pergunta(text, text)', 'servico', 's'),
  ('public._agenda_etiqueta_texto(text, smallint)', 'leitura', 'i'),
  ('public._agenda_exigencia_texto(integer, text, boolean)', 'leitura', 'i'),
  ('public._agenda_du_h(boolean[], integer, integer)', 'ninguem', 'i'),
  ('public._agenda_atende(integer, integer[], integer[], integer[], integer[], boolean, integer, jsonb)', 'ninguem', 'i'),
  ('public._agenda_lider_da_os(uuid, date, uuid[])', 'ninguem', 's'),
  ('public._agenda_meios_sem_quem_pede(date, date, date, uuid[], boolean)', 'ninguem', 's'),
  ('public._agenda_lideres_ausentes(date, date, date)', 'ninguem', 's'),
  ('public._agenda_etiquetas_so_muda()', 'gatilho', 'v'),
  ('public._agenda_etiquetas_exclusiva()', 'gatilho', 'v'))
insert into _resultado
select 'B2c as portas: as 2 leituras do painel, os 2 textos que elas chamam, o validador, o declarado e o novato: authenticated e service_role; o modo da pergunta: só o service_role; as 5 peças de dentro: ninguém; os 2 gatilhos: nem anon nem authenticated; todas invoker, com search_path fixo e a volatilidade da spec; nunca anon',
       count(p.oid) = 15
       and bool_and(not p.prosecdef and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          when 'servico' then not has_function_privilege('authenticated', p.oid, 'execute') and has_function_privilege('service_role', p.oid, 'execute')
                          when 'gatilho' then not has_function_privilege('authenticated', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('service_role', p.oid, 'execute') end),
       string_agg(format('%s %s definer=%s anon=%s auth=%s srv=%s', f.sig, p.provolatile, p.prosecdef,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
         filter (where p.oid is null or p.prosecdef or p.provolatile <> f.vol or has_function_privilege('anon', p.oid, 'execute'))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);

-- ── B3. As listas fechadas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('B3a %s: as de antes iguais e na mesma ordem, e habilidade no fim', t.nome),
       pg_temp.lista(t.tabela::regclass, t.nome) = t.espera || '{habilidade}'::text[]
         -- FASE 7c: (7c P8) a 20261102100550 soma tarefa (pergunta e ação), etapa (rascunho) e tarefas (rodada) no fim de 4 listas,
         -- depois de habilidade (agenda_fase7c_tarefas.sql T1e confere que as de antes ficam)
         || case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                                                         and a.attname = 'modo_tarefas' and not a.attisdropped)
                then case t.nome when 'agenda_perguntas_tipo_check' then '{tarefa}'::text[] when 'agenda_acoes_tipo_check' then '{tarefa}'::text[]
                                 when 'agenda_rascunho_tipo_check' then '{etapa}'::text[]
                                 when 'agenda_vigia_rodadas_rotina_check' then '{tarefas}'::text[] else '{}'::text[] end
                else '{}'::text[] end
         -- FASE 7c: fim
         -- FASE 7d: a 20261107100000 soma local (e combinar e acesso, na pergunta) no fim de 4 destas (agenda_fase7d_base.sql B3 confere)
         || case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                                      and a.attname = 'modo_bem' and not a.attisdropped)
                 then case t.nome when 'agenda_perguntas_tipo_check' then '{local,combinar,acesso}'::text[]
                                  when 'agenda_acoes_tipo_check' then '{local}'::text[]
                                  when 'agenda_vigia_rodadas_rotina_check' then '{local}'::text[]
                                  when 'agenda_alocacoes_cancelada_motivo_check' then '{local}'::text[] else '{}'::text[] end
                 else '{}'::text[] end
         -- FASE 7d: fim
         -- FASE 7f: a 20261109100000 soma assumir (ação), comunicar (rodada) e previsto, mudanca e convite (equipe) no fim (agenda_fase7f_base.sql B6 confere)
                    || case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                                         and a.attname = 'modo_bloco_agenda' and not a.attisdropped)
                            then case t.nome when 'agenda_acoes_tipo_check' then '{assumir}'::text[]
                                             when 'agenda_vigia_rodadas_rotina_check' then '{comunicar}'::text[]
                                             when 'agenda_equipe_mensagens_tipo_check' then '{previsto,mudanca,convite}'::text[] else '{}'::text[] end
                            else '{}'::text[] end
         -- FASE 7f: fim
         -- FASE 7g: a 20261112100000 soma explicar no fim da rodada (agenda_fase7g_base.sql B4b confere a lista inteira)
                    || case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                                         and a.attname = 'modo_porque' and not a.attisdropped)
                            then case t.nome when 'agenda_vigia_rodadas_rotina_check' then '{explicar}'::text[] else '{}'::text[] end
                            else '{}'::text[] end
         -- FASE 7g: fim
         -- FASE 7g: (7g P5b) a 20261112100700 soma ok_marcacao (pergunta), nivel (ação) e ok_do_dono (condição) no fim (agenda_fase7g_ok_do_dono.sql K0c confere)
                    || case when to_regprocedure('public._agenda_espera_ok(uuid)') is not null
                            then case t.nome when 'agenda_perguntas_tipo_check' then '{ok_marcacao}'::text[]
                                             when 'agenda_acoes_tipo_check' then '{nivel}'::text[]
                                             when 'agenda_alocacoes_condicao_tipo_check' then '{ok_do_dono}'::text[] else '{}'::text[] end
                            else '{}'::text[] end,
         -- FASE 7g: fim
       array_to_string(pg_temp.lista(t.tabela::regclass, t.nome), ',')
  from (values
    ('public.agenda_perguntas', 'agenda_perguntas_tipo_check',
     '{nao_cabe,segundo_atraso,atraso_longo,remarcar_confirmado,fixada_pelo_dono,conferencia,chegou,parada,estouro,duracao,material_conferir,padrao_do_dono,diaria,diaria_ligar,equipe_resposta,concluir,entrega,nfe_vincular,pix_material,previsao_fornecedor,fornecedor_cadastro,fornecedores_prazo,cliente_aprovar,cliente_aviso,cliente_resposta,aprendizado,equipe_sem_dias,situacao,estimativa,equipe_cadastro,reavaliar,reestimar,ficha_estimativa,bem_livre,compre_ate,sinal,onda,dia_avisado,dia_prometido,sabado,dias_semana}'::text[]),
    ('public.agenda_acoes', 'agenda_acoes_tipo_check',
     '{publicar,criar,mover,cancelar,fixar,promover_reserva,soltar_reserva,status,resultado,desfazer,diaria,concluir,entregar,equipe,material,fornecedor,cliente,aprendizado,estimar,reestimar,reparar,gestor,dupla}'::text[]),
    ('public.agenda_rascunho', 'agenda_rascunho_tipo_check',
     '{planejar,material,disponibilidade,marcar,aplicar,desfazer,andamento,fornecedor,aviso}'::text[]),
    ('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', '{vigia,rotina,material,cliente,aprender,gestor,equipe_semana}'::text[]),
    ('public.agenda_alocacoes', 'agenda_alocacoes_cancelada_motivo_check',
     '{replanejado,desfeito,os_saiu,pessoa,material,cliente,clima,condicao_vencida,promovida,dono,espera,reestimada}'::text[])
  ) as t(tabela, nome, espera);

insert into _resultado
select 'B3b agenda_perguntas.critica: a expressão da 7a, igual (habilidade não é crítica)',
       a.attgenerated = 's'
       and (select array_agg(m[1] order by o) from regexp_matches(pg_get_expr(d.adbin, d.adrelid), '''([^'']*)''', 'g') with ordinality t(m, o))
           = '{nao_cabe,segundo_atraso,atraso_longo,remarcar_confirmado,fixada_pelo_dono,diaria,cliente_aviso,aprendizado,onda,dia_avisado,dia_prometido,sabado}'::text[]
             -- FASE 7d: a 20261107100000 soma acesso no fim (agenda_fase7d_base.sql B3f confere a lista inteira)
             || case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                             and a.attname = 'modo_bem' and not a.attisdropped) then '{acesso}'::text[] else '{}'::text[] end
             -- FASE 7d: fim
             -- FASE 7g: (7g P5b) a 20261112100700 soma ok_marcacao no fim (agenda_fase7g_ok_do_dono.sql K0d confere)
             || case when to_regprocedure('public._agenda_espera_ok(uuid)') is not null then '{ok_marcacao}'::text[] else '{}'::text[] end,
             -- FASE 7g: fim
       pg_get_expr(d.adbin, d.adrelid)
  from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'critica';

insert into _resultado
select 'B3c os valores novos entram: a pergunta habilidade (não crítica) e a rodada habilidade; um tipo que não existe continua recusado',
       pg_temp.recusa($q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('habilidade', 'habilidade:equipe:2026-11-04', 'Pergunta de teste.', 'sombra')$q$) = 'aceitou'
       and pg_temp.recusa($q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('habilidade', '2026-11-04', '2026-11-04 16:15-03', 'sombra', 'sombra')$q$) = 'aceitou'
       and pg_temp.recusa($q$insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('habilidades', 'x:1', 'Pergunta de teste.', 'sombra')$q$) = 'agenda_perguntas_tipo_check',
       null;

do $b3d$
declare
  v_c boolean;
begin
  begin
    insert into public.agenda_perguntas (tipo, chave, texto, modo) values ('habilidade', 'habilidade:equipe:2026-11-04', 'Pergunta de teste.', 'sombra')
    returning critica into v_c;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  insert into _resultado values ('B3d a pergunta habilidade nasce não crítica (a coluna gerada)', v_c = false, v_c::text);
end
$b3d$;

-- ── B4. agenda_etiquetas: o rastro, as trocas e a exclusividade ──────────────────────────────────────────────
do $b4$
declare
  v_res jsonb := '[]'::jsonb;
  v_p   uuid;
  v_q   uuid;
  v_e   uuid;
  v_f   uuid;
  v_g   uuid;
  r     text;
  a     text := '';
  b     text;
  c     text;
  d     text;
begin
  begin
    v_p := pg_temp.gente('TESTE AG7C Rastro');
    -- (a) as trocas: proposta → vale; vale → substituida; proposta → recusada; o resto, não
    v_e := pg_temp.etiqueta(v_p, 'comissiona', 2, 'gestor', 'proposta', '15 diárias');
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set estado = 'vale', vale_desde = now() where id = '%s'$q$, v_e)) || ';';
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set nivel = 3 where id = '%s'$q$, v_e)) || ';';
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set motivo = 'outro motivo' where id = '%s'$q$, v_e)) || ';';
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set pergunta_id = null where id = '%s'$q$, v_e)) || ';';
    update public.agenda_etiquetas set estado = 'vale', vale_desde = now() where id = v_e;
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set estado = 'proposta', vale_desde = null where id = '%s'$q$, v_e)) || ';';
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set estado = 'recusada', vale_desde = null where id = '%s'$q$, v_e)) || ';';
    update public.agenda_etiquetas set estado = 'substituida', substituida_em = now() where id = v_e;
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set estado = 'vale', substituida_em = null where id = '%s'$q$, v_e)) || ';';
    v_f := pg_temp.etiqueta(v_p, 'comissiona', 3, 'gestor', 'proposta', '15 diárias');
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set estado = 'recusada' where id = '%s'$q$, v_f)) || ';';
    update public.agenda_etiquetas set estado = 'recusada' where id = v_f;
    a := a || pg_temp.recusa(format($q$update public.agenda_etiquetas set estado = 'vale', vale_desde = now() where id = '%s'$q$, v_f));
    -- (b) não se apaga
    b := pg_temp.recusa(format($q$delete from public.agenda_etiquetas where id = '%s'$q$, v_e));

    -- (c) instala × ajudante e uma viva por etiqueta
    v_q := pg_temp.gente('TESTE AG7C Exclusiva');
    v_e := pg_temp.etiqueta(v_q, 'ajudante', 2, 'gestor', 'vale', 'entrou em 29/09, 15 diárias', timestamptz '2026-11-03 16:10-03');
    v_f := pg_temp.etiqueta(v_q, 'instala', 2, 'dono', 'vale', 'você disse', timestamptz '2026-11-04 09:00-03');
    c := (select string_agg(format('%s %s %s %s', e.etiqueta, e.nivel, e.estado, coalesce(to_char(e.substituida_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), '-')), '; ' order by e.criado_em)
            from public.agenda_etiquetas e where e.payee_id = v_q);
    -- o dono de novo (por cima do dele): a viva da mesma etiqueta vira substituída
    v_g := pg_temp.etiqueta(v_q, 'instala', 3, 'dono', 'vale', 'você disse', timestamptz '2026-11-04 10:00-03');
    -- a proposta do gestor por cima do que o dono disse: recusada (instala e ajudante)
    r := pg_temp.recusa(format($q$insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, criado_em) values ('%s', 'instala', 2, 'gestor', 'proposta', '32 diárias desde 23/08', now())$q$, v_q))
         || ' / ' || pg_temp.recusa(format($q$insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, criado_em) values ('%s', 'ajudante', 1, 'gestor', 'proposta', 'começou em 20/10, 3 diárias', now())$q$, v_q));
    -- a proposta do gestor numa etiqueta que o dono não disse entra; o dono por cima dela a substitui
    perform pg_temp.etiqueta(v_q, 'altura', 2, 'gestor', 'proposta', 'sobe', timestamptz '2026-11-04 11:00-03');
    perform pg_temp.etiqueta(v_q, 'altura', 0, 'dono', 'vale', 'você disse', timestamptz '2026-11-04 12:00-03');
    d := (select string_agg(format('%s %s %s %s', e.etiqueta, e.nivel, e.origem, e.estado), '; ' order by e.criado_em)
            from public.agenda_etiquetas e where e.payee_id = v_q)
         || ' | vivas por etiqueta ' || (select max(n) from (select count(*) as n from public.agenda_etiquetas e
                                                               where e.payee_id = v_q and e.estado in ('proposta', 'vale')
                                                               group by e.etiqueta) x)::text
         || ' | ' || r;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B4a as trocas de estado: proposta → vale, recusada ou substituída; vale → substituída; nada volta (vale → proposta, vale → recusada, substituída → vale, recusada → vale), o nível e o motivo não mudam; a pergunta muda',
    a = 'aceitou;erro 23514: agenda_etiquetas: a etiqueta não muda; só o estado (o rastro fica).;erro 23514: agenda_etiquetas: a etiqueta não muda; só o estado (o rastro fica).;aceitou;erro 23514: agenda_etiquetas: a etiqueta não volta de vale para proposta.;erro 23514: agenda_etiquetas: a etiqueta não volta de vale para recusada.;erro 23514: agenda_etiquetas: a etiqueta não volta de substituida para vale.;aceitou;erro 23514: agenda_etiquetas: a etiqueta não volta de recusada para vale.',
    a);
  v_res := pg_temp.ok(v_res, 'B4b a etiqueta não se apaga (o gatilho de Fase 2)', b = 'erro P0001: O registro da agenda não se apaga.', b);
  v_res := pg_temp.ok(v_res, 'B4c instala × ajudante: o "instala sozinho" do dono substitui o "ajudante" do gestor, com a data da nova',
    c = 'ajudante 2 substituida 04/11 09:00; instala 2 vale -', c);
  v_res := pg_temp.ok(v_res, 'B4d uma viva por etiqueta (o dono por cima do dono substitui a vale; o dono por cima da proposta do gestor a substitui) e a proposta do gestor nunca troca o que o dono disse (instala nem ajudante)',
    d = 'ajudante 2 gestor substituida; instala 2 dono substituida; instala 3 dono vale; altura 2 gestor substituida; altura 0 dono vale | vivas por etiqueta 1 | erro 23514: agenda_etiquetas: a proposta do gestor não troca o que o dono disse. / erro 23514: agenda_etiquetas: a proposta do gestor não troca o que o dono disse.',
    d);
  perform pg_temp.gravar(v_res);
end
$b4$;

-- ── B5. agenda_habilidades ───────────────────────────────────────────────────────────────────────────────
do $b5$
declare
  v_res  jsonb := '[]'::jsonb;
  v_dono uuid := public._agenda_dono(null);
  v_z uuid; v_y uuid; v_x uuid; v_w uuid; v_v uuid; v_u uuid; v_t uuid; v_s uuid;
  a text; b text; c text; d text; e text; f text; g text;
begin
  begin
    v_z := pg_temp.gente('Zeca');
    v_y := pg_temp.gente('Yuri');
    v_x := pg_temp.gente('Xico');
    v_w := pg_temp.gente('Wil');
    v_v := pg_temp.gente('Vado');
    v_u := pg_temp.gente('Ugo');
    v_t := pg_temp.gente('Tito');
    perform pg_temp.etiqueta(v_y, 'instala', 2, 'gestor', 'vale', '32 diárias desde 23/08');
    perform pg_temp.etiqueta(v_y, 'altura', 0, 'dono');
    perform pg_temp.etiqueta(v_x, 'ajudante', 2, 'gestor', 'vale', 'entrou em 29/09, 15 diárias');
    perform pg_temp.etiqueta(v_w, 'ajudante', 1, 'gestor', 'vale', 'começou em 26/10, 2 diárias');
    perform pg_temp.etiqueta(v_v, 'instala', 1, 'dono');
    perform pg_temp.etiqueta(v_u, 'instala', 3, 'gestor', 'proposta', '40 diárias desde 01/06');
    perform pg_temp.etiqueta(v_t, 'comissiona', 3, 'dono');
    perform pg_temp.etiqueta(v_t, 'altura', 3, 'dono');
    a := concat_ws(E'\n', pg_temp.hab(v_z), pg_temp.hab(v_y), pg_temp.hab(v_x), pg_temp.hab(v_w), pg_temp.hab(v_v), pg_temp.hab(v_u),
                   pg_temp.hab(v_t), pg_temp.hab(v_dono));
    -- a ordem de p_payees, sem repetir, e quem não é pessoa fica fora
    b := (select string_agg(h.nome, ',') from public.agenda_habilidades(date '2026-11-04',
            array[v_y, v_z, v_y, 'a6e0da00-7b00-4000-8000-0000000000e1'::uuid, null, v_dono]) h);
    -- o fonte de quem tem duas coisas marcadas
    c := (select h.fonte::text from public.agenda_habilidades(date '2026-11-04', array[v_y]) h);
    -- o dono que disse que não sobe no teto; o padrão mudado
    perform pg_temp.etiqueta(v_dono, 'altura', 0, 'dono');
    update public.agenda_config set habilidade_padrao = '{"instala": 3, "comissiona": 1, "altura": 1}' where id;
    d := pg_temp.hab(v_dono) || E'\n' || pg_temp.hab(v_z) || E'\n' || pg_temp.hab(v_x);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- quem vem sob demanda (o dono disse uma data; sem padrão) e a população sem p_payees
  begin
    v_s := pg_temp.gente('Sávio', timestamptz '2026-09-01 10:00-03');
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
    values (v_s, daterange(date '2026-11-10', date '2026-11-10', '[]'), null, 'disponivel', 'dono', 'Você disse que vem', timestamptz '2026-11-03 10:00-03');
    e := pg_temp.hab(v_s);
    perform pg_temp.etiqueta(v_s, 'ajudante', 2, 'dono');
    e := e || E'\n' || pg_temp.hab(v_s);
    update public.agenda_config set sob_demanda_sozinho = true where id;
    e := e || E'\n' || pg_temp.hab(v_s);
    update public.agenda_config set sob_demanda_sozinho = false where id;
    perform pg_temp.etiqueta(v_s, 'instala', 2, 'dono', 'vale', 'você disse', timestamptz '2026-11-04 10:00-03');
    e := e || E'\n' || pg_temp.hab(v_s);
    -- a população: a grade das próximas 2 semanas (o Sávio está nela) e quem tem etiqueta viva (o Yuri, que não está na grade)
    v_y := pg_temp.gente('Yuri');
    perform pg_temp.etiqueta(v_y, 'altura', 0, 'dono');
    f := (select string_agg(h.nome, ',' order by h.nome) filter (where h.nome in ('Sávio', 'Yuri')) || '|dono primeiro ' || (array_agg(h.eh_dono))[1]::text
            from public.agenda_habilidades(date '2026-11-04') h);
    g := pg_temp.recusa($q$select public.agenda_habilidades(null)$q$);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B5a os níveis, o papel, de onde veio e o texto (§6.2): o padrão; o "eu marquei" e o "você disse"; o ajudante corta instala em 1 (papel 1); o novo é papel 2 (instala 0); instala 1 = papel 1; a proposta não vale; o mesmo "você disse" divide o parêntese; o dono',
    a = E'2020 padrao | Zeca: pode tudo, menos comissionar (padrão).\n'
        || E'2000 gestor | Yuri: instala sozinho (eu marquei: 32 diárias desde 23/08); não sobe no teto (você disse).\n'
        || E'1021 gestor | Xico: é ajudante: não vai sozinho em serviço de risco (eu marquei: entrou em 29/09, 15 diárias).\n'
        || E'0022 gestor | Wil: é novo: nunca vai sozinho (eu marquei: começou em 26/10, 2 diárias).\n'
        || E'1021 dono | Vado: instala só com alguém junto (você disse).\n'
        || E'2020 padrao | Ugo: pode tudo, menos comissionar (padrão).\n'
        || E'2330 padrao | Tito: comissiona Victron sozinho; sobe no teto e orienta (você disse).\n'
        || '3320 padrao | Você: comissiona Victron sozinho; instala sozinho e ensina; sobe no teto (padrão).',
    a);
  v_res := pg_temp.ok(v_res, 'B5b p_payees na ordem pedida, sem repetir; o que não é pessoa (a pessoa a mais da 7b, nulo) fica fora',
    b = 'Yuri,Zeca,Gustavo', b);
  v_res := pg_temp.ok(v_res, 'B5c fonte: {instala: gestor, comissiona: padrao, altura: dono, papel: gestor}',
    c::jsonb = '{"instala": "gestor", "comissiona": "padrao", "altura": "dono", "papel": "gestor"}', c);
  v_res := pg_temp.ok(v_res, 'B5d o dono que disse que não sobe no teto (os do padrão juntos, o dito à parte) e o padrão da casa mudado (o ajudante continua cortado em 1)',
    d = E'3300 padrao | Você: comissiona Victron sozinho; instala sozinho e ensina (padrão); não sobe no teto (você disse).\n'
        || E'3110 padrao | Zeca: instala sozinho e ensina; acompanha o comissionamento; sobe no teto só acompanhado (padrão).\n'
        || '1111 gestor | Xico: é ajudante: não vai sozinho em serviço de risco (eu marquei: entrou em 29/09, 15 diárias).',
    d);
  v_res := pg_temp.ok(v_res, 'B5e quem vem sob demanda (R5.1-5): papel novo, também com ajudante 2 do dono (vale a mais protetora); com sob_demanda_sozinho, o ajudante; com instala 2 do dono, responsável',
    e = E'0022 sob_demanda | Sávio: nunca vai sozinho (vem só nos dias que você diz).\n'
        || E'0022 sob_demanda | Sávio: nunca vai sozinho (vem só nos dias que você diz).\n'
        || E'1021 dono | Sávio: é ajudante: não vai sozinho em serviço de risco (você disse).\n'
        || '2020 dono | Sávio: instala sozinho (você disse).',
    e);
  v_res := pg_temp.ok(v_res, 'B5f sem p_payees: a grade das próximas 2 semanas (agenda_capacidade) e quem tem etiqueta viva, o dono primeiro; sem p_hoje = 22004',
    f = 'Sávio,Yuri|dono primeiro true' and g like 'erro 22004%', f || ' | ' || g);
  perform pg_temp.gravar(v_res);
end
$b5$;

-- ── B7. A regra única _agenda_atende (pura: sempre) ─────────────────────────────────────────────────────────
-- (o B6, o B8, o B9, o B11 e o B12 usam as fixtures: depois)
with n(v) as (select '{"ene": 2, "com": 3, "dia": 2, "alt": 2, "par": 2}'::jsonb),
c(o, nome, ex, inst, com, alt, pap, dono, dalt, espera) as (values
  (1, 'nada pedido, equipe vazia', 0, '{}'::int[], '{}'::int[], '{}'::int[], '{}'::int[], false, 2, null::text),
  (2, 'energizado sem ninguém', 1, '{}', '{}', '{}', '{}', false, 2, 'energizado'),
  (3, 'energizado com quem instala sozinho', 1, '{2}', '{0}', '{2}', '{0}', false, 2, null),
  (4, 'energizado só com o ajudante (instala 1)', 1, '{1}', '{0}', '{2}', '{1}', false, 2, 'energizado'),
  (5, 'energizado com o dono no turno', 1, '{1}', '{0}', '{2}', '{1}', true, 2, null),
  (6, 'comissionamento com quem instala sozinho', 2, '{2}', '{0}', '{2}', '{0}', false, 2, 'comissionamento'),
  (7, 'comissionamento com quem comissiona Victron', 2, '{2}', '{3}', '{2}', '{0}', false, 2, null),
  (8, 'comissionamento com o dono no turno', 2, '{2}', '{0}', '{2}', '{0}', true, 2, null),
  (9, 'diagnóstico só com o ajudante', 8, '{1}', '{0}', '{2}', '{1}', false, 2, 'diagnostico'),
  (10, 'diagnóstico com quem faz diagnóstico (comissiona 2)', 8, '{1}', '{2}', '{2}', '{1}', false, 2, null),
  (11, 'diagnóstico com quem instala sozinho', 8, '{2}', '{0}', '{2}', '{0}', false, 2, null),
  (12, 'altura com quem não sobe', 4, '{2}', '{0}', '{0}', '{0}', false, 2, 'altura'),
  (13, 'altura com quem sobe só acompanhado', 4, '{2}', '{0}', '{1}', '{0}', false, 2, 'altura'),
  (14, 'altura com o dono no turno que sobe', 4, '{2}', '{0}', '{0}', '{0}', true, 2, null),
  (15, 'altura com o dono no turno que não sobe', 4, '{2}', '{0}', '{0}', '{0}', true, 0, 'altura'),
  (16, 'altura com quem sobe', 4, '{1}', '{0}', '{2}', '{1}', false, 2, null),
  (17, 'o novo sozinho, nada pedido', 0, '{0}', '{0}', '{2}', '{2}', false, 2, 'novato_sozinho'),
  (18, 'o novo com o ajudante', 0, '{0,1}', '{0,0}', '{2,2}', '{2,1}', false, 2, 'novato_sozinho'),
  (19, 'o novo com quem instala sozinho', 0, '{0,2}', '{0,0}', '{2,2}', '{2,0}', false, 2, null),
  (20, 'o novo com o dono no turno', 0, '{0}', '{0}', '{2}', '{2}', true, 2, null),
  (21, 'o novo com um responsável que instala só com alguém (instala 1 não é par)', 0, '{0,1}', '{0,0}', '{2,2}', '{2,0}', false, 2, 'novato_sozinho'),
  (22, 'a ordem: energizado e altura sem ninguém → energizado', 5, '{}', '{}', '{}', '{}', false, 2, 'energizado'),
  (23, 'a ordem: comissionamento antes de diagnóstico e altura', 14, '{2}', '{0}', '{0}', '{0}', false, 2, 'comissionamento'),
  (24, 'o novo que sobe no teto não cobre o par (altura atendida, falta o par)', 4, '{0}', '{0}', '{2}', '{2}', false, 2, 'novato_sozinho'),
  (25, 'tudo atendido por uma dupla responsável + quem comissiona', 15, '{2,1}', '{0,3}', '{2,0}', '{0,1}', false, 2, null),
  (26, 'arrays nulos = equipe vazia', 4, null, null, null, null, false, 2, 'altura'))
insert into _resultado
select 'B7 _agenda_atende (§3.5): a tabela-verdade — cada código, o dono no turno (cobre energizado, comissionamento e diagnóstico; a altura só se ele sobe), o par do novo, a ordem e a equipe vazia',
       bool_and(public._agenda_atende(c.ex, c.inst, c.com, c.alt, c.pap, c.dono, c.dalt, n.v) is not distinct from c.espera),
       coalesce(string_agg(format('%s %s: %s (esperava %s)', c.o, c.nome, coalesce(public._agenda_atende(c.ex, c.inst, c.com, c.alt, c.pap, c.dono, c.dalt, n.v), 'nulo'), coalesce(c.espera, 'nulo')), '; ' order by c.o)
                  filter (where public._agenda_atende(c.ex, c.inst, c.com, c.alt, c.pap, c.dono, c.dalt, n.v) is distinct from c.espera), 'todas as 26')
  from c, n;

-- ── B10. _agenda_du_h (pura: sempre) ────────────────────────────────────────────────────────────────────
-- O vetor útil de 6 dias: 1 e 2 úteis, 3 e 4 não, 5 e 6 úteis. (1,2) o mesmo dia; (1,3) o dia 2; (2,7) os dias 2 a 4; (3,10) os dias
-- 3 a 5; (10,1) ao contrário, os dias 2 a 5; (10,12) o dia 6; (11,14) o dia 7, fora do vetor; (1,12) os dias 2 a 6.
insert into _resultado
select 'B10 _agenda_du_h: os dias úteis d com dia(h1) < d ≤ dia(h2), dia(h) = (h + 1) / 2, pelo vetor útil; negativo ao contrário; fora do vetor não conta; nulo com nulo',
       public._agenda_du_h(u.v, 1, 2) = 0 and public._agenda_du_h(u.v, 1, 3) = 1 and public._agenda_du_h(u.v, 2, 7) = 1
       and public._agenda_du_h(u.v, 3, 10) = 1 and public._agenda_du_h(u.v, 10, 1) = -2 and public._agenda_du_h(u.v, 10, 12) = 1
       and public._agenda_du_h(u.v, 11, 14) = 0 and public._agenda_du_h(u.v, 5, 5) = 0 and public._agenda_du_h(u.v, 1, 12) = 3
       and public._agenda_du_h(u.v, null, 3) is null,
       format('%s %s %s %s %s %s %s %s %s', public._agenda_du_h(u.v, 1, 2), public._agenda_du_h(u.v, 1, 3), public._agenda_du_h(u.v, 2, 7),
              public._agenda_du_h(u.v, 3, 10), public._agenda_du_h(u.v, 10, 1), public._agenda_du_h(u.v, 10, 12),
              public._agenda_du_h(u.v, 11, 14), public._agenda_du_h(u.v, 5, 5), public._agenda_du_h(u.v, 1, 12))
  from (select array[true, true, false, false, true, true]::boolean[] as v) u;

-- os textos (puros: sempre)
insert into _resultado
select 'B7b os textos (§3.2 e §6.1): cada nível de etiqueta; o que a OS pede, longo e curto, com o alcance; máscara 0 = nulo',
       public._agenda_etiqueta_texto('instala', 1::smallint) = 'instala só com alguém junto'
       and public._agenda_etiqueta_texto('instala', 3::smallint) = 'instala sozinho e ensina'
       and public._agenda_etiqueta_texto('ajudante', 3::smallint) = 'é ajudante e já quase instala sozinho'
       and public._agenda_etiqueta_texto('comissiona', 0::smallint) = 'não comissiona'
       and public._agenda_etiqueta_texto('comissiona', 1::smallint) = 'acompanha o comissionamento'
       and public._agenda_etiqueta_texto('comissiona', 2::smallint) = 'faz diagnóstico sozinho'
       and public._agenda_etiqueta_texto('altura', 1::smallint) = 'sobe no teto só acompanhado'
       and public._agenda_etiqueta_texto('altura', 3::smallint) = 'sobe no teto e orienta'
       and public._agenda_etiqueta_texto('instala', 0::smallint) is null and public._agenda_etiqueta_texto('solda', 1::smallint) is null
       and public._agenda_exigencia_texto(1, 'ultimo') = 'quem instala sozinho com 220 V ou banco de bateria no último dia'
       and public._agenda_exigencia_texto(6, 'todos') = 'quem comissiona Victron e quem sobe no teto em todos os dias'
       and public._agenda_exigencia_texto(12, null, true) = 'sobe no teto e faz diagnóstico'
       and public._agenda_exigencia_texto(8, null) = 'quem faz diagnóstico'
       and public._agenda_exigencia_texto(0, 'todos') is null and public._agenda_exigencia_texto(null, null) is null,
       public._agenda_exigencia_texto(15, 'ultimo', true);

-- ── B11 (parte sem fixture): o modo de quem faz a pergunta habilidade ─────────────────────────────────────────
do $b11m$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_tabelas_fase7b', true), '');
  v_esta text := coalesce(current_setting('agenda_teste.mig_base_fase7c', true), '');
  v_novo text;
  v_a    text;
  v_n    int;
  r      record;
begin
 begin
  update public.agenda_config set modo_habilidade = 'ligado', modo_habilidade_propor = 'sombra' where id;
  v_res := pg_temp.ok(v_res, 'B11a _agenda_modo_da_pergunta: a habilidade da equipe (habilidade:equipe:…) é do modo_habilidade_propor; a de uma OS (habilidade:os:<os>), do modo_habilidade; toda chave da habilidade tem modo',
    public._agenda_modo_da_pergunta('habilidade', 'habilidade:equipe:2026-11-04') = 'sombra'
    and public._agenda_modo_da_pergunta('habilidade', 'habilidade:os:c7c00000-0000-4000-8000-000000097173') = 'ligado'
    and public._agenda_modo_da_pergunta('habilidade', 'habilidade:x') = 'sombra'
    and public._agenda_modo_da_pergunta('habilidade', null) = 'sombra', null);
  update public.agenda_config set modo_habilidade = 'desligado', modo_habilidade_propor = 'desligado' where id;
  v_res := pg_temp.ok(v_res, 'B11b todo tipo da lista fechada tem o modo de quem o faz (o tipo novo sem modo reprova aqui)',
    not exists (select 1 from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t
                 where public._agenda_modo_da_pergunta(t, t || ':x') is null),
    (select string_agg(t, ',') from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t
      where public._agenda_modo_da_pergunta(t, t || ':x') is null));
  if v_mig = '' or v_esta = '' then
    v_res := pg_temp.ok(v_res, 'B11c e B11d (o de antes e a cópia)', true,
      'PULADO: sem agenda_teste.mig_tabelas_fase7b e agenda_teste.mig_base_fase7c (rode pela bancada)');
  else
  -- o de antes (a definição de 20261101100000 rodada como pg_temp): só habilidade muda (não existia)
  execute replace(pg_temp.inteira(v_mig, '_agenda_modo_da_pergunta'), 'create or replace function public._agenda_modo_da_pergunta(',
                  'create function pg_temp.modo_antes(');
  for r in select * from (values ('desligado', 'desligado'), ('ligado', 'sombra'), ('sombra', 'ligado')) t(m, m2) loop
    update public.agenda_config
       set modo_marcar_sozinho = r.m, modo_revisao_diaria = r.m2, modo_compre_ate = r.m, modo_dias = r.m2, modo_cadastro = r.m,
           modo_habilidade = r.m2, modo_habilidade_propor = r.m
     where id;
    -- FASE 7d: local, combinar e acesso (20261107100000) não têm o de antes: ficam fora da comparação (o agenda_fase7d_base.sql B6i confere)
    -- (7g P5b: e ok_marcacao, 20261112100700; o K4n de agenda_fase7g_ok_do_dono.sql confere o modo dele)
    select string_agg(t, ',' order by t) filter (where public._agenda_modo_da_pergunta(t, t || ':x') is distinct from pg_temp.modo_antes(t, t || ':x')
                                                   and t not in ('local', 'combinar', 'acesso', 'ok_marcacao')),
           count(*) filter (where t not in ('local', 'combinar', 'acesso', 'ok_marcacao'))
    -- (7g: fim)
    -- FASE 7d: fim
      into v_a, v_n
      from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t;
    v_res := pg_temp.ok(v_res, format('B11c o modo de cada tipo é o de antes (a definição de 20261101100000), menos habilidade (nova) — o gestor %s, a 7c %s/%s', r.m, r.m2, r.m),
      -- FASE 7c: (7c P8, 20261102100550) e menos tarefa (nova, do modo_tarefas): 43 tipos
      v_a = case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_tarefas'
                     and not a.attisdropped) then 'habilidade,tarefa' else 'habilidade' end
      and v_n = 42 + case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_tarefas'
                     and not a.attisdropped) then 1 else 0 end,
      -- FASE 7c: fim
      coalesce(v_a, '-') || ' de ' || v_n);
  end loop;
  -- a cópia: o corpo vivo = o desta migration; sem o bloco "-- FASE 7c:" é o de 20261101100000
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public._agenda_modo_da_pergunta(text, text)'::regprocedure;
  -- FASE 7d: (7d P1) a 20261107100000 recria de novo, com o bloco "-- FASE 7d:" (só acréscimo): ele sai antes da régua da cópia da 7c
  v_novo := pg_temp.sem_7d(v_novo);
  -- FASE 7d: fim
  select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7c: fim', 'g');
  v_res := pg_temp.ok(v_res, 'B11d a cópia de _agenda_modo_da_pergunta: o corpo vivo é o desta migration; sem o bloco "-- FASE 7c:" (1), é o corpo de 20261101100000 (a mais nova antes da 7c)',
    -- FASE 7c: (7c P8, 20261102100550) o P8 recria a função (+ o bloco do tipo tarefa): a viva é a do P8, com 2 blocos "-- FASE 7c:";
    -- tirados os dois, a de 20261101100000 (agenda_fase7c_tarefas.sql T18 confere a do P8 contra esta)
    v_n = 1 + case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_tarefas'
                     and not a.attisdropped) then 1 else 0 end
    and (v_novo = pg_temp.corpo(v_esta, '_agenda_modo_da_pergunta')
         or (exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_tarefas'
                     and not a.attisdropped)
             and v_novo = pg_temp.corpo(coalesce(current_setting('agenda_teste.mig_tarefas_fase7c', true), ''), '_agenda_modo_da_pergunta')))
    -- FASE 7c: fim
    and pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta') <> ''
    and pg_temp.sem_7c(v_novo) = pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta'),
    format('blocos %s; fonte %s letras; novo sem o bloco %s letras', v_n, length(pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta')),
           length(pg_temp.sem_7c(v_novo))));
  end if;
  raise exception 'desfaz' using errcode = 'P0099';
 exception when sqlstate 'P0099' then null;
 end;
  perform pg_temp.gravar(v_res);
end
$b11m$;

-- ── B11e. As cópias do declarado e do novato (de 20261101100860) ──────────────────────────────────────────────
do $b11c$
declare
  v_esta text := coalesce(current_setting('agenda_teste.mig_base_fase7c', true), '');
  v_c3   text := coalesce(current_setting('agenda_teste.mig_correcao3_fase7b', true), '');
  f      record;
  v_novo text;
  v_n    int;
  v_an   int;
begin
  if v_esta = '' or v_c3 = '' then
    insert into _resultado values ('B11e as cópias', true, 'PULADO: sem agenda_teste.mig_base_fase7c e agenda_teste.mig_correcao3_fase7b (rode pela bancada)');
    return;
  end if;
  for f in select * from (values
      ('_agenda_tecnico_declarado', 'public._agenda_tecnico_declarado(uuid, date)', 2, 1),
      ('_agenda_e_novato', 'public._agenda_e_novato(uuid, date)', 1, 0)) as x(nome, sig, blocos, antes) loop
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7c: fim', 'g');
    select count(*) into v_an from regexp_matches(v_novo, '-- antes: ', 'g');
    insert into _resultado values (
      format('B11e a cópia de %s: o corpo vivo é o desta migration; sem os %s blocos "-- FASE 7c:" (e com a linha "-- antes:" de volta: %s), é o corpo de 20261101100860 (a correção 3 da 7b)', f.nome, f.blocos, f.antes),
      v_n = f.blocos and v_an = f.antes and v_novo = pg_temp.corpo(v_esta, f.nome) and pg_temp.corpo(v_c3, f.nome) <> ''
      and pg_temp.sem_7c(v_novo) = pg_temp.corpo(v_c3, f.nome)
      and v_novo like '%-- FASE 7b: (correção 3)%' = (f.nome = '_agenda_e_novato'),
      format('blocos %s; antes %s; fonte %s letras; novo sem os blocos %s letras', v_n, v_an, length(pg_temp.corpo(v_c3, f.nome)),
             length(pg_temp.sem_7c(v_novo))));
  end loop;
end
$b11c$;

-- ═══ Daqui em diante, as fixtures (só na bancada) ═══════════════════════════════════════════════════════════════
-- As definições de antes (as da 100860) rodadas como pg_temp: o novato de antes chama o declarado de antes.
do $antes$
declare
  v_c3 text := coalesce(current_setting('agenda_teste.mig_correcao3_fase7b', true), '');
begin
  if v_c3 = '' then return; end if;
  execute replace(pg_temp.inteira(v_c3, '_agenda_tecnico_declarado'), 'create or replace function public._agenda_tecnico_declarado(',
                  'create function pg_temp.declarado_antes(');
  execute replace(replace(pg_temp.inteira(v_c3, '_agenda_e_novato'), 'create or replace function public._agenda_e_novato(',
                          'create function pg_temp.novato_antes('),
                  'public._agenda_tecnico_declarado(', 'pg_temp.declarado_antes(');
end
$antes$;

-- o novato, o declarado e o papel de uma pessoa num dia: "novato t/f (antes t/f), declarado t/f (antes t/f), papel n fonte"
create function pg_temp.r5(p_payee uuid, p_dia date) returns text language plpgsql as $f$
declare
  h record;
begin
  select * into h from public.agenda_habilidades(p_dia, array[p_payee]);
  return format('novato %s (antes %s), declarado %s (antes %s), papel %s %s',
                left(public._agenda_e_novato(p_payee, p_dia)::text, 1), left(pg_temp.novato_antes(p_payee, p_dia)::text, 1),
                left(public._agenda_tecnico_declarado(p_payee, p_dia)::text, 1), left(pg_temp.declarado_antes(p_payee, p_dia)::text, 1),
                h.papel, h.fonte ->> 'papel');
end $f$;

-- ── B12 (a variante real) e B11 (o Alex de produção), numa subtransação: só o Alex e o dono ────────────────────
do $real$
declare
  v_res  jsonb := '[]'::jsonb;
  v_alex uuid;
  a      text;
  b      text;
  c      text;
  d      text;
  r      record;
begin
  if not pg_temp.na_bancada() or to_regprocedure('pg_temp.novato_antes(uuid, date)') is null then
    insert into _resultado values ('B12a/B11f (a variante real)', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.carregar('real');
    v_alex := pg_temp.pessoa('Alex');
    a := (select string_agg(h.nome || ':' || h.papel, ',') from public.agenda_habilidades(date '2026-11-04') h);
    b := pg_temp.r5(v_alex, date '2026-11-04');
    c := (select h.texto from public.agenda_habilidades(date '2026-11-04', array[v_alex]) h);
    -- carregar 2× = 1× (as linhas reais completadas não andam)
    d := (select md5(string_agg(sos.id::text || coalesce(sos.service_system, '-') || coalesce(sos.service_verb, '-'), ',' order by sos.id))
            from public.service_order_services sos);
    perform pg_temp.carregar('real');
    d := (d = (select md5(string_agg(sos.id::text || coalesce(sos.service_system, '-') || coalesce(sos.service_verb, '-'), ',' order by sos.id))
                 from public.service_order_services sos))::text
         || ' / OS sintéticas ' || (select count(*) from public.service_orders where service_order_number between 'OS-97171' and 'OS-97179')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B12a a variante real: na grade só o dono e o Alex (os dois responsáveis); carregar 2× = 1×; nenhuma OS sintética da 7c',
    a = 'Gustavo:0,Alex:0' and d = 'true / OS sintéticas 0', a || ' | ' || d);
  v_res := pg_temp.ok(v_res, 'B11f o Alex de produção (sem perfil, o padrão do dono seg a sex desde 30/10, cadastro 05/08): não é novato, é o técnico declarado, papel responsável pelo padrão; o texto "pode tudo, menos comissionar (padrão)" (R5.1-6)',
    b = 'novato f (antes f), declarado t (antes t), papel 0 padrao' and c = 'Alex: pode tudo, menos comissionar (padrão).', b || ' | ' || c);
  perform pg_temp.gravar(v_res);
end
$real$;

-- ── A sintética, carregada uma vez (o resto roda em cima dela, cada caso numa subtransação desfeita) ─────────────
do $carga$
begin
  if pg_temp.na_bancada() then
    perform pg_temp.carregar('');
  end if;
end
$carga$;

-- ── B12. A fixture sintética ───────────────────────────────────────────────────────────────────────────────
do $b12$
declare
  v_res jsonb := '[]'::jsonb;
  a     text;
  b     text;
  c     text;
  d     text;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('B12 (a fixture sintética)', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  a := (select string_agg(h.nome || ':' || h.papel || ':' || (h.fonte ->> 'papel'), ',') from public.agenda_habilidades(date '2026-11-04') h);
  b := (select string_agg(so.service_order_number || ' ' || s.name_snapshot || ' ' || pl.dias || coalesce(' ' || pl.dono_presenca, ''), '; ' order by so.service_order_number)
          from public.service_orders so join public.service_order_services s on s.service_order_id = so.id
          join public.os_planejamento pl on pl.service_order_id = so.id
         where so.service_order_number between 'OS-97171' and 'OS-97179');
  c := (select count(*) from public.service_order_services sos join public.service_orders so on so.id = sos.service_order_id
         where so.service_order_number in ('OS-00032', 'OS-00033', 'OS-00069', 'OS-00074', 'OS-00096')
           and sos.service_verb is not null)::text;
  begin
    d := (select md5(string_agg(to_jsonb(x)::text, ',' order by x.id)) from public.agenda_disponibilidade x)
         || (select md5(string_agg(to_jsonb(x)::text, ',' order by x.id)) from public.agenda_alocacoes x);
    perform pg_temp.carregar('');
    d := (d = (select md5(string_agg(to_jsonb(x)::text, ',' order by x.id)) from public.agenda_disponibilidade x)
              || (select md5(string_agg(to_jsonb(x)::text, ',' order by x.id)) from public.agenda_alocacoes x))::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B12b a sintética (R5.1-6): na grade o dono, Alex, Bruno (o novo pela regra da 7b), João, Rafael e Roberto (os dois de volta pelo padrão deles); Mateus (sem linha) e Mickael fora',
    a = 'Gustavo:0:padrao,Alex:0:padrao,Bruno:2:novato,João:0:padrao,Rafael:0:padrao,Roberto:0:padrao', a);
  v_res := pg_temp.ok(v_res, 'B12c as OS 171 a 179 da §8.2: uma linha de serviço e os dias ditos; o Caio com a presença nunca',
    b = 'OS-97171 Substituição baterias chumbo para lítio 3.0; OS-97172 Instalação de painel solar no teto 1.0; OS-97173 Comissionamento do sistema de energia 1.0 nunca; '
        || 'OS-97174 Instalação de porta-fusíveis 12V 0.5; OS-97175 Instalação de inversor 220 V 3.0; OS-97176 Revisão do quadro elétrico 2.0; '
        || 'OS-97177 Troca do banco de baterias 1.0; OS-97178 Instalação de luminárias 12V 0.5; OS-97179 Instalação de carregador e inversor 1.0', b);
  v_res := pg_temp.ok(v_res, 'B12d as linhas reais completadas com o sistema e o verbo do catálogo (wf7c_05): das 20 linhas das 5 OS que o replay trouxe sem eles, 14 têm verbo (as 6 do Kalmar OS-00032 sem verbo nem em produção); carregar 2× = 1×',
    c = '14' and d = 'true', c || ' | ' || d);
  perform pg_temp.gravar(v_res);
end
$b12$;

-- ── B6. os_exigencias na carteira real ───────────────────────────────────────────────────────────────────
do $b6$
declare
  v_res jsonb := '[]'::jsonb;
  v_len uuid;
  v_rob uuid;
  a     text;
  b     text;
  c     text;
  d     text;
  e     text;
  f     text;
  g     text;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('B6 (o que a OS pede)', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_len := pg_temp.os('OS-00074');
  v_rob := pg_temp.os('ORÇ-00083');
  a := (select string_agg(format('%s %s/%s', t.n, x.ex ->> 'todos', x.ex ->> 'ultimo'), ', ' order by t.o)
          from unnest(array['OS-00032', 'OS-00033', 'OS-00069', 'OS-00074', 'OS-00076', 'OS-00096', 'OS-00104', 'OS-00112', 'OS-00130',
                            'ORÇ-00083', 'ORÇ-00095']) with ordinality t(n, o),
               lateral (select public.os_exigencias(pg_temp.os(t.n), date '2026-11-04') as ex) x);
  b := concat_ws(E'\n', public.os_exigencias(v_len, date '2026-11-04') ->> 'texto', public.os_exigencias(v_len, date '2026-11-04') ->> 'texto_curto',
                 public.os_exigencias(v_rob, date '2026-11-04') ->> 'texto', public.os_exigencias(pg_temp.os('OS-00104'), date '2026-11-04') ->> 'texto');
  c := (select jsonb_agg(i - 'linha_id')::text from jsonb_array_elements(public.os_exigencias(pg_temp.os('OS-00130'), date '2026-11-04') -> 'itens') i);
  d := public.os_exigencias('00000000-0000-4000-8000-000000000000', date '2026-11-04')::text;
  begin
    -- o dito tira (o Robson não precisa de quem sobe no teto) e amplia (o Lenine pede energizado em todos os dias)
    insert into public.os_planejamento (service_order_id, exigencias_ditas) values (v_rob, '{"altura": "nao"}')
    on conflict (service_order_id) do update set exigencias_ditas = excluded.exigencias_ditas;
    insert into public.os_planejamento (service_order_id, exigencias_ditas) values (v_len, '{"energizado": "todos", "diagnostico": "ultimo"}')
    on conflict (service_order_id) do update set exigencias_ditas = excluded.exigencias_ditas;
    e := concat_ws(E'\n', public.os_exigencias(v_rob, date '2026-11-04') ->> 'texto',
                   format('%s/%s ft %s %s', public.os_exigencias(v_len, date '2026-11-04') ->> 'todos', public.os_exigencias(v_len, date '2026-11-04') ->> 'ultimo',
                          public.os_exigencias(v_len, date '2026-11-04') ->> 'fonte_texto', public.os_exigencias(v_len, date '2026-11-04') ->> 'texto'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a logística e o sistema nenhum ficam fora; o sistema CA só com o verbo da lista; o verbo principal pelo maior valor
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total,
                                               service_system, service_verb, created_at)
    values (pg_temp.os('OS-97174'), 'Levar o inversor até a marina', 'unit', 1, 100, 100, 'eletrico_dc', 'logistica', timestamptz '2026-10-26 11:00-03'),
           (pg_temp.os('OS-97174'), 'Tomada de terra no píer', 'unit', 1, 100, 100, 'nenhum', 'instalacao', timestamptz '2026-10-26 11:01-03'),
           (pg_temp.os('OS-97174'), 'Painel do píer', 'unit', 1, 100, 100, 'eletrico_ac', 'remocao', timestamptz '2026-10-26 11:02-03');
    f := (public.os_exigencias(pg_temp.os('OS-97174'), date '2026-11-04') ->> 'todos') || '/' || (public.os_exigencias(pg_temp.os('OS-97174'), date '2026-11-04') ->> 'ultimo');
    update public.service_order_services set service_verb = 'instalacao' where name_snapshot = 'Painel do píer';
    f := f || ' ' || (public.os_exigencias(pg_temp.os('OS-97174'), date '2026-11-04') ->> 'ultimo')
         || ' ' || (public.os_exigencias(pg_temp.os('OS-97174'), date '2026-11-04') -> 'itens' -> 0 ->> 'fonte');
    insert into public.service_order_services (service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total,
                                               service_system, service_verb, created_at)
    values (pg_temp.os('OS-97178'), 'Achar a falha do quadro', 'unit', 1, 2000, 2000, 'eletrico_dc', 'diagnostico', timestamptz '2026-10-26 11:00-03');
    f := f || ' ' || (public.os_exigencias(pg_temp.os('OS-97178'), date '2026-11-04') ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- a paridade com os gatilhos de dupla (R2): toda OS da fixture que casa banco_cc ou ca_energizado também pede energizado
  g := (select coalesce(string_agg(so.service_order_number, ', ' order by so.service_order_number), 'nenhuma')
          from public.service_orders so
         where exists (select 1 from jsonb_array_elements(coalesce(public._agenda_dupla_da_os(so.id) -> 'motivos', '[]'::jsonb)) m
                        where m ->> 'motivo' in ('banco_cc', 'ca_energizado'))
           and ((public.os_exigencias(so.id, date '2026-11-04') ->> 'todos')::int | (public.os_exigencias(so.id, date '2026-11-04') ->> 'ultimo')::int) & 1 = 0)
       || ' | casam ' || (select count(*) from public.service_orders so
                          where exists (select 1 from jsonb_array_elements(coalesce(public._agenda_dupla_da_os(so.id) -> 'motivos', '[]'::jsonb)) m
                                         where m ->> 'motivo' in ('banco_cc', 'ca_energizado')))::text;
  v_res := pg_temp.ok(v_res, 'B6a as máscaras das 11 OS da carteira real (a tabela do §2 da spec: todos/último; 1 energizado, 2 comissionamento, 4 altura, 8 diagnóstico)',
    a = 'OS-00032 0/3, OS-00033 0/2, OS-00069 0/3, OS-00074 0/1, OS-00076 4/0, OS-00096 8/0, OS-00104 0/0, OS-00112 0/1, OS-00130 4/1, ORÇ-00083 4/0, ORÇ-00095 4/1', a);
  v_res := pg_temp.ok(v_res, 'B6b os textos da §6.1, byte a byte (o Lenine, o curto dele, o Robson e o Flávio — "refrigerador" não é gerador: a palavra casa no início)',
    b = E'Lenine pede quem instala sozinho com 220 V ou banco de bateria no último dia (pela linha "Substituição baterias - chumbo para litio").\n'
        || E'quem instala sozinho com 220 V ou banco de bateria, no último dia\n'
        || E'Robson pede quem sobe no teto (pela linha "Serviço de Substituição de Claraboia de Teto").\n'
        || 'Flávio não pede ninguém em especial.', b);
  v_res := pg_temp.ok(v_res, 'B6c os itens do Giancarlo, um por exigência, alcance e linha (a da 1ª regra que casou): o energizado pelo sistema CA (o conversor, que a palavra 220 V também pegaria) e pela palavra (o inversor; o barramento e o banco de baterias); a altura pela palavra (o toldo e o sobre teto); na ordem da exigência, da regra e do valor da linha; a linha cortada em 60 letras',
    c::jsonb = '[{"exigencia": "energizado", "meios": "ultimo", "fonte": "sistema", "linha": "Adequação do conversor automático 110/220V para uso com inv…"},
                 {"exigencia": "energizado", "meios": "ultimo", "fonte": "palavra", "linha": "Religação do Inversor (cabos já prontos - remoção/fixação)"},
                 {"exigencia": "energizado", "meios": "ultimo", "fonte": "palavra", "linha": "Barramento e proteções do sistema de corrente contínua"},
                 {"exigencia": "energizado", "meios": "ultimo", "fonte": "palavra", "linha": "Realocação do banco de baterias"},
                 {"exigencia": "altura", "meios": "todos", "fonte": "palavra", "linha": "Restauração de mola de toldo e reparo de braços de toldo"},
                 {"exigencia": "altura", "meios": "todos", "fonte": "palavra", "linha": "Fabricação de sobre teto de tulha em compensado naval com f…"}]'::jsonb,
    c);
  v_res := pg_temp.ok(v_res, 'B6d a OS que não existe: {ok: false, "Não encontrei esse serviço."}',
    d::jsonb = '{"ok": false, "texto": "Não encontrei esse serviço."}', d);
  v_res := pg_temp.ok(v_res, 'B6e o que o dono disse vale sobre as regras: "nao" tira (o Robson não pede ninguém); "todos" amplia o último (o Lenine: energizado em todos, você disse) e põe o que a regra não via (diagnóstico no último dia)',
    e = E'Robson não pede ninguém em especial.\n'
        || '1/8 ft 0 Lenine pede quem instala sozinho com 220 V ou banco de bateria (você disse) e quem faz diagnóstico no último dia (você disse).', e);
  v_res := pg_temp.ok(v_res, 'B6f a logística e o sistema nenhum ficam fora; o sistema CA só pede com o verbo da lista (remoção não, instalação sim); o verbo principal é o da linha de maior valor (o diagnóstico de R$ 2.000 pede quem faz diagnóstico)',
    f = '0/0 1 sistema Hugo pede quem faz diagnóstico (pela linha "Achar a falha do quadro").', f);
  v_res := pg_temp.ok(v_res, 'B6g a paridade com os gatilhos de dupla (R2): toda OS que casa banco_cc ou ca_energizado (_agenda_dupla_da_os) também pede energizado',
    g like 'nenhuma | casam %' and g not like '%| casam 0', g);
  perform pg_temp.gravar(v_res);
end
$b6$;

-- ── B8. O responsável da OS ──────────────────────────────────────────────────────────────────────────────
do $b8$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-04';
  v_edu  uuid;
  v_ivo  uuid;
  v_lia  uuid;
  v_rob  uuid;
  v_joao uuid;
  v_ws   uuid;
  v_ids  uuid[];
  a text; b text; c text; d text; e text; f text; g text; h text;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('B8 (o responsável)', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_edu := pg_temp.os('OS-97175');
  v_ivo := pg_temp.os('OS-97179');
  v_lia := pg_temp.os('OS-97171');
  v_rob := pg_temp.pessoa('Roberto');
  v_joao := pg_temp.pessoa('João');
  a := (public._agenda_lider_da_os(v_edu, c_d))::text;
  b := (public._agenda_lider_da_os(v_ivo, c_d))::text;
  v_ids := array(select x.id from public.agenda_alocacoes x where x.service_order_id = v_ivo and x.payee_id = v_joao);
  c := coalesce(public._agenda_lider_da_os(v_ivo, c_d, v_ids)::text, 'nulo');
  d := coalesce(public._agenda_lider_da_os(pg_temp.os('OS-97174'), c_d)::text, 'nulo');
  begin
    -- o dono disse o responsável
    update public.os_planejamento set lider_payee_id = v_joao, lider_em = timestamptz '2026-11-04 09:00-03', lider_trecho = 'no Edu o responsável é o João'
     where service_order_id = v_edu;
    e := public._agenda_lider_da_os(v_edu, c_d) ->> 'texto' || ' ' || (public._agenda_lider_da_os(v_edu, c_d) ->> 'fonte');
    -- a pessoa que o dono disse saiu (inativa): vale quem fez
    update public.payees set active = false where id = v_joao;
    e := e || ' / ' || (public._agenda_lider_da_os(v_edu, c_d) ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o João fez um meio-dia ANTES (seg 02/11, passado sem resultado): sem etiqueta ele é responsável e passa a ser o líder; com o
    -- "ajudante" (o ajudante nunca é líder), volta o Roberto
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_edu, v_joao, date '2026-11-02', 'tarde', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-10-30 16:30-03');
    f := public._agenda_lider_da_os(v_edu, c_d) ->> 'texto';
    perform pg_temp.etiqueta(v_joao, 'ajudante', 2, 'gestor', 'vale', 'entrou em 29/09, 15 diárias');
    f := f || ' / ' || (public._agenda_lider_da_os(v_edu, c_d) ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a diária ligada à OS conta como a manhã daquele dia (a Lia não tem meio-dia marcado)
    select ws.id into v_ws from public.work_shifts ws join public.work_profiles w on w.id = ws.work_profile_id
     where w.payee_id = v_rob and ws.data = date '2026-10-23' and ws.tipo = 'diaria' limit 1;
    insert into public.work_shift_os (shift_id, service_order_id) values (v_ws, v_lia);
    g := public._agenda_lider_da_os(v_lia, c_d)::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o desempate: dois responsáveis no mesmo 1º meio-dia; ganha quem tem mais meios-dias na OS (o João, com mais um)
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_ivo, v_rob, date '2026-11-10', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03');
    h := public._agenda_lider_da_os(v_ivo, c_d) ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B8a fez: o Edu (Roberto cumpriu ter 03/11 de manhã e de tarde) — "Roberto (fez o 1º dia, ter 03/11)", desde 03/11',
    a::jsonb - 'payee_id' = '{"nome": "Roberto", "fonte": "fez", "desde": "2026-11-03", "texto": "Roberto (fez o 1º dia, ter 03/11)"}'
    and (a::jsonb ->> 'payee_id')::uuid = v_rob, a);
  v_res := pg_temp.ok(v_res, 'B8b planejado: o Ivo (só o João marcado na ter 10/11; o dono abrindo e fechando não conta) — "João (está no 1º dia marcado)"; com os meios-dias dele em p_ignorar, nenhum; a OS sem nada marcado, nenhum',
    b::jsonb - 'payee_id' = '{"nome": "João", "fonte": "planejado", "desde": "2026-11-10", "texto": "João (está no 1º dia marcado)"}'
    and c = 'nulo' and d = 'nulo', b || ' | ' || c || ' | ' || d);
  v_res := pg_temp.ok(v_res, 'B8c dono: "João (você disse)" vale sobre quem fez; com a pessoa inativa, volta quem fez',
    e = 'João (você disse) dono / Roberto (fez o 1º dia, ter 03/11)', e);
  v_res := pg_temp.ok(v_res, 'B8d o ajudante nunca é líder: o João no meio-dia de antes é o líder só enquanto não é ajudante',
    f = 'João (fez o 1º dia, seg 02/11) / Roberto (fez o 1º dia, ter 03/11)', f);
  v_res := pg_temp.ok(v_res, 'B8e a diária ligada à OS (work_shift_os) conta como a manhã daquele dia: "Roberto (fez o 1º dia, sex 23/10)"',
    g::jsonb - 'payee_id' = '{"nome": "Roberto", "fonte": "fez", "desde": "2026-10-23", "texto": "Roberto (fez o 1º dia, sex 23/10)"}', g);
  v_res := pg_temp.ok(v_res, 'B8f o desempate do 1º meio-dia: mais meios-dias na OS (o João, nos dois turnos), depois o nome',
    h = 'João (está no 1º dia marcado)', h);
  perform pg_temp.gravar(v_res);
end
$b8$;

-- ── B9. Os meios-dias sem quem o serviço pede e sem o responsável ─────────────────────────────────────────────
create function pg_temp.sem_quem(p_os uuid[] default null, p_com_dita boolean default false) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s %s %s %s [%s] dono %s último %s', so.service_order_number, to_char(m.dia, 'DD/MM'), m.turno, m.falta,
                                    (select string_agg(public._agenda_nome_curto(py.name), '+' order by py.name) from public.payees py where py.id = any (m.equipe)),
                                    left(m.dono_turno::text, 1), left(m.ultimo::text, 1)), '; ' order by so.service_order_number, m.dia, m.turno), 'nada')
    from public._agenda_meios_sem_quem_pede(date '2026-11-05', date '2026-11-18', date '2026-11-04', p_os, p_com_dita) m
    join public.service_orders so on so.id = m.os
$f$;

do $b9$
declare
  v_res  jsonb := '[]'::jsonb;
  v_ivo  uuid;
  v_edu  uuid;
  v_duda uuid;
  v_joao uuid;
  v_rob  uuid;
  v_bru  uuid;
  v_dono uuid := public._agenda_dono(null);
  a text; b text; c text; d text; e text; f text; g text;
begin
  if not pg_temp.na_bancada() then
    insert into _resultado values ('B9 (a avaliação do publicado)', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_ivo := pg_temp.os('OS-97179');
  v_edu := pg_temp.os('OS-97175');
  v_duda := pg_temp.os('OS-97174');
  v_joao := pg_temp.pessoa('João');
  v_rob := pg_temp.pessoa('Roberto');
  v_bru := pg_temp.pessoa('Bruno');
  -- sem etiqueta: o João pode tudo (o padrão); com as etiquetas dos testes M e V, o João é ajudante
  a := pg_temp.sem_quem();
  begin
    perform pg_temp.carregar('', '', 'mv');
    b := pg_temp.sem_quem();
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    c := pg_temp.sem_quem();
    c := c || ' || só o Ivo: ' || pg_temp.sem_quem(array[v_ivo]) || ' || só o Edu: ' || pg_temp.sem_quem(array[v_edu]);
    -- a equipe dita pelo dono: fora, salvo com p_com_dita
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_ivo, v_joao, 'dia');
    d := pg_temp.sem_quem() || ' || com a dita: ' || pg_temp.sem_quem(null, true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o novo sozinho (o Bruno, pela regra da 7b) num meio-dia sem nada pedido; com o Roberto junto, atende
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_duda, v_bru, date '2026-11-12', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03');
    e := pg_temp.sem_quem(array[v_duda]);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_duda, v_rob, date '2026-11-12', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03');
    e := e || ' / ' || pg_temp.sem_quem(array[v_duda]);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o Edu (Roberto fez): a qui 05/11 de manhã só com o João — sem o responsável; com o dono no turno, ou com o Roberto, não
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_edu, v_joao, date '2026-11-05', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03'),
           (v_edu, v_joao, date '2026-11-05', 'tarde', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03'),
           (v_edu, v_dono, date '2026-11-05', 'tarde', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03');
    f := (select coalesce(string_agg(format('%s %s %s %s [%s]', so.service_order_number, to_char(l.dia, 'DD/MM'), l.turno, l.lider_nome,
                                            (select string_agg(public._agenda_nome_curto(py.name), '+') from public.payees py where py.id = any (l.equipe))), '; '), 'nada')
            from public._agenda_lideres_ausentes(date '2026-11-05', date '2026-11-18', date '2026-11-04') l
            join public.service_orders so on so.id = l.os);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (v_edu, v_rob, date '2026-11-05', 'manha', 'turno', 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03');
    g := (select coalesce(string_agg(l.turno, ','), 'nada') from public._agenda_lideres_ausentes(date '2026-11-05', date '2026-11-18', date '2026-11-04') l)
         || ' / fora da janela: ' || (select coalesce(string_agg(l.turno, ','), 'nada') from public._agenda_lideres_ausentes(date '2026-11-06', date '2026-11-18', date '2026-11-04') l);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'B9a sem etiqueta (o padrão: pode tudo), o publicado da janela atende: nada', a = 'nada', a);
  v_res := pg_temp.ok(v_res, 'B9b com o João ajudante (os testes M e V) e o dono fechando a ter 10/11 do Ivo, o fechamento cobre o último dia: nada',
    b = 'nada', b);
  v_res := pg_temp.ok(v_res, 'B9c sem o fechamento cobrir (habilidade_fechamento_cobre false): o Ivo na ter 10/11 à tarde (o último meio-dia), o João sozinho, falta energizado; a manhã não pede nada; o filtro por OS',
    c = 'OS-97179 10/11 tarde energizado [João] dono f último t || só o Ivo: OS-97179 10/11 tarde energizado [João] dono f último t || só o Edu: nada', c);
  v_res := pg_temp.ok(v_res, 'B9d a OS com a equipe dita pelo dono fica fora (a palavra dele vale), salvo com p_com_dita',
    d = 'nada || com a dita: OS-97179 10/11 tarde energizado [João] dono f último t', d);
  v_res := pg_temp.ok(v_res, 'B9e o novo sozinho (o Bruno) num meio-dia que não pede nada: falta novato_sozinho; com o Roberto junto, atende',
    e = 'OS-97174 12/11 manha novato_sozinho [Bruno] dono f último t / nada', e);
  v_res := pg_temp.ok(v_res, 'B9f _agenda_lideres_ausentes: o Edu (Roberto fez) na qui 05/11 de manhã só com o João — sem o responsável; à tarde o dono está no turno (não conta)',
    f = 'OS-97175 05/11 manha Roberto [João]', f);
  v_res := pg_temp.ok(v_res, 'B9g com o Roberto no meio-dia, ninguém falta; fora da janela, nada',
    g = 'nada / fora da janela: nada', g);
  perform pg_temp.gravar(v_res);
end
$b9$;

-- ── B11. O R5.1-5 nas variantes do R5.1-6 ─────────────────────────────────────────────────────────────────────
do $b11$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-04';
  c_seg  constant date := date '2026-11-02';
  v_alex uuid;
  v_bru  uuid;
  v_mat  uuid;
  v      text;
  x      jsonb := '{}'::jsonb;
  r      record;
begin
  if not pg_temp.na_bancada() or to_regprocedure('pg_temp.novato_antes(uuid, date)') is null then
    insert into _resultado values ('B11 (as variantes)', true, 'PULADO: sem as fixtures e as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_alex := pg_temp.pessoa('Alex');
  v_bru := pg_temp.pessoa('Bruno');
  v_mat := pg_temp.pessoa('Mateus');
  x := x || jsonb_build_object('alex', pg_temp.r5(v_alex, c_d), 'bruno', pg_temp.r5(v_bru, c_d),
                               'bruno_texto', (select h.texto from public.agenda_habilidades(c_d, array[v_bru]) h));
  for r in select * from (values ('alex_perfil'), ('alex_respondeu'), ('alex_semana'), ('mateus_terca'), ('mateus_terca_sem_perfil'),
                                 ('bruno_ajudante'), ('bruno_instala')) t(var) loop
    begin
      perform pg_temp.carregar('', r.var);
      v := case when r.var like 'alex%' then pg_temp.r5(v_alex, c_d)
                when r.var like 'mateus%' then pg_temp.r5(v_mat, c_d) || ' | sob demanda ' || left(public._agenda_e_sob_demanda(v_mat, c_d)::text, 1)
                else pg_temp.r5(v_bru, c_d) end;
      if r.var = 'alex_semana' then
        v := v || ' | na segunda: ' || pg_temp.r5(v_alex, c_seg);
      end if;
      if r.var = 'alex_respondeu' then
        v := v || ' | padrões vivos ' || (select string_agg(d.dias_semana::text || ':' || d.origem, ' ') from public.agenda_disponibilidade d
                                           where d.payee_id = v_alex and d.substituida_em is null and d.dias_semana is not null);
      end if;
      if r.var = 'mateus_terca_sem_perfil' then
        v := v || ' | ' || (select h.texto from public.agenda_habilidades(c_d, array[v_mat]) h);
        update public.agenda_config set sob_demanda_sozinho = true where id;
        v := v || ' | com sob_demanda_sozinho: papel ' || (select h.papel from public.agenda_habilidades(c_d, array[v_mat]) h)::text;
      end if;
      if r.var like 'bruno%' then
        v := v || ' | ' || (select h.texto from public.agenda_habilidades(c_d, array[v_bru]) h);
      end if;
      x := x || jsonb_build_object(r.var, v);
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- a etiqueta no técnico declarado (com o perfil novo de alex_perfil): ajudante (qualquer nível) e instala 1 tiram o declarado e o
  -- novato da 7b volta; instala 2 do gestor não tira
  for r in select * from (values ('ajudante', 2, 'dono'), ('ajudante', 3, 'gestor'), ('instala', 1, 'dono'), ('instala', 2, 'gestor'))
                           t(etq, niv, ori) loop
    begin
      perform pg_temp.carregar('', 'alex_perfil');
      perform pg_temp.etiqueta(v_alex, r.etq, r.niv, r.ori);
      x := x || jsonb_build_object(format('alex_%s%s_%s', r.etq, r.niv, r.ori), pg_temp.r5(v_alex, c_d));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  -- quem vem sob demanda (o Mateus da 7b com uma data dita) com ajudante 2 do dono: o papel novo continua
  begin
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
    values (v_mat, daterange(date '2026-11-11', date '2026-11-11', '[]'), null, 'disponivel', 'dono', 'Você disse que vem', timestamptz '2026-11-04 10:00-03');
    perform pg_temp.etiqueta(v_mat, 'ajudante', 2, 'dono');
    x := x || jsonb_build_object('mateus_datas', pg_temp.r5(v_mat, c_d));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  v_res := pg_temp.ok(v_res, 'B11g o Bruno da fixture (perfil e cadastro em 20/10, 3 diárias, o padrão dito por ele): novato, igual antes; papel novo pela regra da 7b; o texto "é novo: nunca vai sozinho (começou em 20/10, 3 diárias)"',
    x ->> 'bruno' = 'novato t (antes t), declarado f (antes f), papel 2 novato'
    and x ->> 'bruno_texto' = 'Bruno: é novo: nunca vai sozinho (começou em 20/10, 3 diárias).', x ->> 'bruno' || ' | ' || (x ->> 'bruno_texto'));
  v_res := pg_temp.ok(v_res, 'B11h alex_perfil: com um perfil de diária desde ontem e 0 diárias, o Alex não é novato (igual à 100860: o técnico declarado)',
    x ->> 'alex_perfil' = 'novato f (antes f), declarado t (antes t), papel 0 padrao', x ->> 'alex_perfil');
  v_res := pg_temp.ok(v_res, 'B11i alex_respondeu: depois de ele responder os próprios dias (o padrão do dono seg a sex substituído por um seg a qui de origem diarista), continua não novato e declarado',
    x ->> 'alex_respondeu' = 'novato f (antes f), declarado t (antes t), papel 0 padrao | padrões vivos {1,2,3,4}:diarista', x ->> 'alex_respondeu');
  v_res := pg_temp.ok(v_res, 'B11j [c3-conf] alex_semana: declarado pelo dono só na qua 04/11 e com um perfil desde seg 02/11 — medido na segunda (o dia do motor), não é novato (com a 100860 era: a linha "criada até p_dia")',
    x ->> 'alex_semana' = 'novato f (antes f), declarado t (antes t), papel 0 padrao | na segunda: novato f (antes t), declarado t (antes f), papel 0 padrao',
    x ->> 'alex_semana');
  v_res := pg_temp.ok(v_res, 'B11k mateus_terca: cadastrado hoje, "toda terça" dita pelo dono e um perfil de hoje — novato, não declarado, papel novo (igual antes)',
    x ->> 'mateus_terca' = 'novato t (antes t), declarado f (antes f), papel 2 novato | sob demanda f', x ->> 'mateus_terca');
  v_res := pg_temp.ok(v_res, 'B11l [c3-rev] mateus_terca_sem_perfil: na 7b não é novato nem vem sob demanda (o limite do C2f); na 7c o papel é novo pelo dia fixo dito a menos de 30 dias do cadastro e sem perfil — "é novo: nunca vai sozinho (começou em 04/11, ainda sem diária)"; com sob_demanda_sozinho, o padrão',
    x ->> 'mateus_terca_sem_perfil' = 'novato f (antes f), declarado f (antes f), papel 2 dia_fixo | sob demanda f | Mateus: é novo: nunca vai sozinho (começou em 04/11, ainda sem diária). | com sob_demanda_sozinho: papel 0',
    x ->> 'mateus_terca_sem_perfil');
  v_res := pg_temp.ok(v_res, 'B11m bruno_ajudante: com ajudante 2 do dono, continua novato e papel novo (vale a mais protetora)',
    x ->> 'bruno_ajudante' = 'novato t (antes t), declarado f (antes f), papel 2 novato | Bruno: é novo: nunca vai sozinho (começou em 20/10, 3 diárias).',
    x ->> 'bruno_ajudante');
  v_res := pg_temp.ok(v_res, 'B11n bruno_instala: com instala 2 do dono ("o Bruno instala sozinho"), não é novato (o (b) do R5.1-5) e é responsável — "Bruno: instala sozinho (você disse)."',
    x ->> 'bruno_instala' = 'novato f (antes t), declarado f (antes f), papel 0 dono | Bruno: instala sozinho (você disse).', x ->> 'bruno_instala');
  v_res := pg_temp.ok(v_res, 'B11o a etiqueta no técnico declarado (o Alex com o perfil novo): ajudante de qualquer nível e instala 1 tiram o declarado — o novato da 7b volta; instala 2 do gestor não tira',
    x ->> 'alex_ajudante2_dono' = 'novato t (antes f), declarado f (antes t), papel 2 novato'
    and x ->> 'alex_ajudante3_gestor' = 'novato t (antes f), declarado f (antes t), papel 2 novato'
    and x ->> 'alex_instala1_dono' = 'novato t (antes f), declarado f (antes t), papel 2 novato'
    and x ->> 'alex_instala2_gestor' = 'novato f (antes f), declarado t (antes t), papel 0 gestor',
    concat_ws(' | ', x ->> 'alex_ajudante2_dono', x ->> 'alex_ajudante3_gestor', x ->> 'alex_instala1_dono', x ->> 'alex_instala2_gestor'));
  v_res := pg_temp.ok(v_res, 'B11p quem vem sob demanda (o Mateus com uma data dita) com ajudante 2 do dono: papel novo (sob demanda), não novato da 7b',
    x ->> 'mateus_datas' = 'novato f (antes f), declarado f (antes f), papel 2 sob_demanda', x ->> 'mateus_datas');
  perform pg_temp.gravar(v_res);
end
$b11$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
