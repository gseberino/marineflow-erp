-- Prova da base da Agenda de Produção, Fase 7b (pacote P1): os interruptores e os parâmetros da etapa (a pergunta da semana, o
-- dono, a dupla, o novato e quem vem sob demanda, a chamada da equipe, quem chamar), a semana presa da disponibilidade e o so_pontas,
-- a coluna chamar do diário do gestor, as listas fechadas ampliadas e o modo de quem faz a pergunta dias_semana (migration
-- 20261101100000), e a fixture da etapa (a equipe de verdade de 30/10 e as pessoas da 7b, por cima do replay e da sintética da 7a).
-- bancada: depende de 20261101100000
--
--   B1 colunas, DEFAULTs e CHECKs (os 26 da migration): agenda_config (os 5 interruptores nascem desligados na linha com o DEFAULT
--      sombra; os 21 parâmetros com o valor da spec e das respostas do dono; equipe_inativo_dias não existe), agenda_disponibilidade,
--      agenda_gestor_dia; cada CHECK novo tem um caso que ele recusa e os limites que entram
--   B2 as listas fechadas (as de antes iguais e na mesma ordem, as novas no fim; critica não muda; dias_semana não é crítica; as
--      listas que a 7b não amplia, iguais)
--   B3 so_pontas só com período e pessoa; semana_dita só segunda e só em exceção; as duas FKs com on delete set null; o índice da
--      semana; dupla_meios_coerente (da 7a) continua
--   B4 RLS e privilégios (anon nada nas tabelas; o técnico lê 0 e não grava; a migration só recria _agenda_modo_da_pergunta, que
--      continua só do service_role, invoker e STABLE)
--   B5 as regex dos dupla_gatilhos e das dupla_notas padrão compilam (cada uma e a lista inteira, pelo validador da 7a)
--   B6 _agenda_modo_da_pergunta: dias_semana = modo_dias; equipe_cadastro = modo_cadastro fora de desligado, senão o do gestor que
--      marca; os outros tipos, o de antes (a definição de 20261031100850 rodada como pg_temp); todo tipo tem modo; a cópia é o corpo
--      de 20261031100850 fora do bloco "-- FASE 7b:"
--   B7 a fixture (fixture-fase7b.sql): o 30/10 (a equipe, a reserva solta, a pergunta do lote), as pessoas da 7b, as OS, as
--      variantes 'campo' (a linha do dono) e 'real' (só o Alex e o dono); carregar 2× = 1×
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7b_base.sql
--   Seguro em produção: as linhas de teste ("TESTE AG7B") só são inseridas; termina em ROLLBACK. B6 (a cópia) e B7 usam as fixtures e
--   as migrations como texto e só rodam na bancada (fora dela saem PULADO).
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
    if v_estado in ('23514', '23505', '23503', '23502', '23P01') then return coalesce(nullif(v_nome, ''), v_estado); end if;
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
-- O texto sem os blocos "-- FASE 7b: … -- FASE 7b: fim" (as linhas de abrir e de fechar saem junto).
create function pg_temp.sem_7b(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7b:' and l !~ '-- FASE 7b: fim' then 1
                                                when l ~ '^\s*-- FASE 7b: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7b: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;

-- As linhas de teste (não dependem das fixtures: B1 a B6 rodam também em produção). Uma pessoa e uma pergunta do dono para as FKs
-- novas da disponibilidade. A mensagem à equipe só existe dentro dos casos (pg_temp.recusa desfaz): ela não se apaga e prenderia a
-- pessoa, e o replay do B7 apaga as pessoas antes de pôr as de produção.
insert into public.payees (id, name, kind, active) values ('d7b00000-0000-4000-8000-0000000000e4', 'TESTE AG7B Pessoa', 'diarista', true);
insert into public.agenda_perguntas (id, tipo, chave, texto, modo)
values ('d7b00000-0000-4000-8000-0000000000e5', 'dias_semana', 'dias_semana:teste-ag7b:2026-11-16', 'Pergunta de teste.', 'sombra');

create temp table _base (nome text primary key, sql text) on commit drop;
insert into _base values
  ('msg', $q$insert into public.agenda_equipe_mensagens (id, payee_id, dia, tipo, modo, texto, enviar_em, dedupe_key) values ('d7b00000-0000-4000-8000-0000000000e6', 'd7b00000-0000-4000-8000-0000000000e4', '2026-11-16', 'dias', 'sombra', 'Mensagem de teste.', '2026-11-05 16:45-03', 'teste-ag7b:dias:2026-11-16')$q$),
  ('disp', $q$insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem%s) values ('d7b00000-0000-4000-8000-0000000000e4', daterange('2026-11-16', '2026-11-16', '[]'), 'disponivel', 'diarista'%s)$q$),
  ('dia', $q$insert into public.agenda_gestor_dia (dia, calculado_em, modos%s) values ('2026-11-05', '2026-11-05 16:53-03', '{}'%s)$q$);
-- O INSERT de teste de p_nome com as colunas e os valores a mais.
create function pg_temp.mais(p_nome text, p_cols text, p_vals text) returns text language sql stable as $f$
  select format((select sql from _base where nome = p_nome), coalesce(', ' || p_cols, ''), coalesce(', ' || p_vals, ''))
$f$;

-- ── B1. Colunas, DEFAULTs e CHECKs ──────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B1a agenda_config: os 5 interruptores nascem desligados na linha e o DEFAULT da coluna é sombra; os 21 parâmetros com o valor da spec e das respostas do dono (§4.1, R4.4, R4.2(b), R4.3; AG7-02 meia capacidade 0,50)',
       c.modo_dias = 'desligado' and c.modo_dupla = 'desligado' and c.modo_sabado = 'desligado' and c.modo_cadastro = 'desligado'
       and c.modo_chamar = 'desligado'
       and (select bool_and(pg_get_expr(d.adbin, d.adrelid) like '''sombra''%') and count(*) = 5
              from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
             where a.attrelid = 'public.agenda_config'::regclass
               and a.attname in ('modo_dias', 'modo_dupla', 'modo_sabado', 'modo_cadastro', 'modo_chamar'))
       and c.equipe_hora_dias = time '16:45' and c.equipe_dias_semanas_a_frente = 2 and c.equipe_dias_tentar_dias = 5
       and c.equipe_dias_fechar_antes = interval '30 minutes' and c.dono_dias_semanal and not c.dono_como_tecnico
       and c.dono_carga_max = 0.50 and c.dias_semana_motivos = '{dono_sem_padrao,semente,chamar}'
       and c.dupla_tec_viagem_min = 2 and c.dupla_espera_max_du = 5 and c.novato_dias = 30 and c.novato_diarias = 10
       and not c.novato_sozinho and not c.sob_demanda_sozinho and c.falta_semanas = 8 and c.falta_dias_min = 10
       and c.equipe_chamada_dias = 56 and c.equipe_chamada_prazo_du = 3 and c.equipe_cadastro_abertas_max = 3
       and c.chamar_min_meios = 2 and c.chamar_max_os = 3
       -- (o que a 7b não cria: vem da 7a, com o mesmo valor)
       and c.equipe_padrao = 1 and c.equipe_sugerida = 2 and c.sabado_manha = 'so_prazo',
       (to_jsonb(c) - 'dupla_gatilhos' - 'dupla_notas')::text
  from public.agenda_config c;

insert into _resultado
select 'B1b agenda_config: as 26 colunas novas, todas NOT NULL com DEFAULT, com o tipo da spec; equipe_inativo_dias não existe (R4.1-6)',
       count(*) = 26 and bool_and(a.attnotnull and a.atthasdef)
       and string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
           = 'chamar_max_os:smallint,chamar_min_meios:smallint,dias_semana_motivos:text[],dono_carga_max:numeric(3,2),'
             'dono_como_tecnico:boolean,dono_dias_semanal:boolean,dupla_espera_max_du:smallint,dupla_tec_viagem_min:smallint,'
             'equipe_cadastro_abertas_max:smallint,equipe_chamada_dias:smallint,equipe_chamada_prazo_du:smallint,'
             'equipe_dias_fechar_antes:interval,equipe_dias_semanas_a_frente:smallint,equipe_dias_tentar_dias:smallint,'
             'equipe_hora_dias:time without time zone,falta_dias_min:smallint,falta_semanas:smallint,modo_cadastro:text,'
             'modo_chamar:text,modo_dias:text,modo_dupla:text,modo_sabado:text,novato_diarias:smallint,novato_dias:smallint,'
             'novato_sozinho:boolean,sob_demanda_sozinho:boolean'
       and not exists (select 1 from pg_attribute x where x.attrelid = 'public.agenda_config'::regclass
                                                       and x.attname = 'equipe_inativo_dias' and not x.attisdropped),
       string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
  from pg_attribute a
 where a.attrelid = 'public.agenda_config'::regclass and not a.attisdropped
   and a.attname in ('modo_dias', 'modo_dupla', 'modo_sabado', 'modo_cadastro', 'modo_chamar', 'equipe_hora_dias',
                     'equipe_dias_semanas_a_frente', 'equipe_dias_tentar_dias', 'equipe_dias_fechar_antes', 'dono_dias_semanal',
                     'dono_como_tecnico', 'dono_carga_max', 'dias_semana_motivos', 'dupla_tec_viagem_min', 'dupla_espera_max_du',
                     'novato_dias', 'novato_diarias', 'novato_sozinho', 'sob_demanda_sozinho', 'falta_semanas', 'falta_dias_min',
                     'equipe_chamada_dias', 'equipe_chamada_prazo_du', 'equipe_cadastro_abertas_max', 'chamar_min_meios',
                     'chamar_max_os');

insert into _resultado
select 'B1c as colunas novas das outras tabelas, com o tipo da spec (agenda_gestor_dia.chamar NOT NULL com DEFAULT {}; o resto nulo); cada coluna com comentário',
       string_agg(c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod)
                  || case when a.attnotnull then '!' else '' end
                  || coalesce('=' || pg_get_expr(d.adbin, d.adrelid), ''), ',' order by c.relname, a.attname)
       = 'agenda_disponibilidade.mensagem_id:uuid,agenda_disponibilidade.pergunta_id:uuid,agenda_disponibilidade.semana_dita:date,'
         'agenda_gestor_dia.chamar:jsonb!=''{}''::jsonb'
       and bool_and(col_description(c.oid, a.attnum) is not null),
       string_agg(c.relname || '.' || a.attname || ':' || format_type(a.atttypid, a.atttypmod)
                  || case when a.attnotnull then '!' else '' end
                  || coalesce('=' || pg_get_expr(d.adbin, d.adrelid), ''), ',' order by c.relname, a.attname)
  from pg_attribute a join pg_class c on c.oid = a.attrelid
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
 where not a.attisdropped
   and ((c.oid = 'public.agenda_disponibilidade'::regclass and a.attname in ('semana_dita', 'mensagem_id', 'pergunta_id'))
     or (c.oid = 'public.agenda_gestor_dia'::regclass and a.attname = 'chamar'));

insert into _resultado
select 'B1d agenda_config: os 26 parâmetros novos têm comentário com o código da pergunta ao dono (AG7-xx)',
       count(*) = 26 and bool_and(col_description(a.attrelid, a.attnum) ~ 'AG7-[0-9]{2}'),
       coalesce(string_agg(a.attname, ', ') filter (where coalesce(col_description(a.attrelid, a.attnum), '') !~ 'AG7-[0-9]{2}'), '—')
  from pg_attribute a
 where a.attrelid = 'public.agenda_config'::regclass and not a.attisdropped
   and a.attname in ('modo_dias', 'modo_dupla', 'modo_sabado', 'modo_cadastro', 'modo_chamar', 'equipe_hora_dias',
                     'equipe_dias_semanas_a_frente', 'equipe_dias_tentar_dias', 'equipe_dias_fechar_antes', 'dono_dias_semanal',
                     'dono_como_tecnico', 'dono_carga_max', 'dias_semana_motivos', 'dupla_tec_viagem_min', 'dupla_espera_max_du',
                     'novato_dias', 'novato_diarias', 'novato_sozinho', 'sob_demanda_sozinho', 'falta_semanas', 'falta_dias_min',
                     'equipe_chamada_dias', 'equipe_chamada_prazo_du', 'equipe_cadastro_abertas_max', 'chamar_min_meios',
                     'chamar_max_os');

create temp table _casos (grupo text, nome text, sql text, espera text) on commit drop;
insert into _casos values
  -- agenda_config (os 22 CHECKs)
  ('config', 'modo_dias x', $q$update public.agenda_config set modo_dias = 'x'$q$, 'agenda_config_modo_dias_check'),
  ('config', 'modo_dupla x', $q$update public.agenda_config set modo_dupla = 'x'$q$, 'agenda_config_modo_dupla_check'),
  ('config', 'modo_sabado x', $q$update public.agenda_config set modo_sabado = 'x'$q$, 'agenda_config_modo_sabado_check'),
  ('config', 'modo_cadastro x', $q$update public.agenda_config set modo_cadastro = 'x'$q$, 'agenda_config_modo_cadastro_check'),
  ('config', 'modo_chamar x', $q$update public.agenda_config set modo_chamar = 'x'$q$, 'agenda_config_modo_chamar_check'),
  ('config', 'pergunta da semana antes da janela (07:29)', $q$update public.agenda_config set equipe_hora_dias = '07:29'$q$, 'agenda_config_equipe_hora_dias_check'),
  ('config', 'pergunta da semana a menos de 30 min do fim da janela (19:31)', $q$update public.agenda_config set equipe_hora_dias = '19:31'$q$, 'agenda_config_equipe_hora_dias_check'),
  ('config', 'a semana que vem (1)', $q$update public.agenda_config set equipe_dias_semanas_a_frente = 1$q$, 'agenda_config_equipe_dias_semanas_a_frente_check'),
  ('config', '4 semanas à frente', $q$update public.agenda_config set equipe_dias_semanas_a_frente = 4$q$, 'agenda_config_equipe_dias_semanas_a_frente_check'),
  ('config', 'tentar por 0 dias', $q$update public.agenda_config set equipe_dias_tentar_dias = 0$q$, 'agenda_config_equipe_dias_tentar_dias_check'),
  ('config', 'tentar por 7 dias', $q$update public.agenda_config set equipe_dias_tentar_dias = 7$q$, 'agenda_config_equipe_dias_tentar_dias_check'),
  ('config', 'fechar 14 min antes', $q$update public.agenda_config set equipe_dias_fechar_antes = '14 minutes'$q$, 'agenda_config_equipe_dias_fechar_antes_check'),
  ('config', 'fechar 5 h antes', $q$update public.agenda_config set equipe_dias_fechar_antes = '5 hours'$q$, 'agenda_config_equipe_dias_fechar_antes_check'),
  ('config', 'o dono a 0,19', $q$update public.agenda_config set dono_carga_max = 0.19$q$, 'agenda_config_dono_carga_max_check'),
  ('config', 'o dono a 1,01', $q$update public.agenda_config set dono_carga_max = 1.01$q$, 'agenda_config_dono_carga_max_check'),
  ('config', 'motivo da pergunta do dono que não existe', $q$update public.agenda_config set dias_semana_motivos = '{dono_sem_padrao,toda_hora}'$q$, 'agenda_config_dias_semana_motivos_check'),
  ('config', 'motivo nulo na lista', $q$update public.agenda_config set dias_semana_motivos = '{semente,NULL}'$q$, 'agenda_config_dias_semana_motivos_check'),
  ('config', 'dupla com 1 técnico do orçamento', $q$update public.agenda_config set dupla_tec_viagem_min = 1$q$, 'agenda_config_dupla_tec_viagem_min_check'),
  ('config', 'dupla com 7 técnicos do orçamento', $q$update public.agenda_config set dupla_tec_viagem_min = 7$q$, 'agenda_config_dupla_tec_viagem_min_check'),
  ('config', 'esperar a dupla −1 dia útil', $q$update public.agenda_config set dupla_espera_max_du = -1$q$, 'agenda_config_dupla_espera_max_du_check'),
  ('config', 'esperar a dupla 21 dias úteis', $q$update public.agenda_config set dupla_espera_max_du = 21$q$, 'agenda_config_dupla_espera_max_du_check'),
  ('config', 'novato por 181 dias', $q$update public.agenda_config set novato_dias = 181$q$, 'agenda_config_novato_dias_check'),
  ('config', 'novato por −1 dia', $q$update public.agenda_config set novato_dias = -1$q$, 'agenda_config_novato_dias_check'),
  ('config', 'novato até 61 diárias', $q$update public.agenda_config set novato_diarias = 61$q$, 'agenda_config_novato_diarias_check'),
  ('config', 'falta em 3 semanas', $q$update public.agenda_config set falta_semanas = 3$q$, 'agenda_config_falta_semanas_check'),
  ('config', 'falta em 27 semanas', $q$update public.agenda_config set falta_semanas = 27$q$, 'agenda_config_falta_semanas_check'),
  ('config', 'falta com 3 dias', $q$update public.agenda_config set falta_dias_min = 3$q$, 'agenda_config_falta_dias_min_check'),
  ('config', 'falta com 61 dias', $q$update public.agenda_config set falta_dias_min = 61$q$, 'agenda_config_falta_dias_min_check'),
  ('config', 'chamada a cada 13 dias', $q$update public.agenda_config set equipe_chamada_dias = 13$q$, 'agenda_config_equipe_chamada_dias_check'),
  ('config', 'chamada a cada 181 dias', $q$update public.agenda_config set equipe_chamada_dias = 181$q$, 'agenda_config_equipe_chamada_dias_check'),
  ('config', 'prazo da chamada 0 dia útil', $q$update public.agenda_config set equipe_chamada_prazo_du = 0$q$, 'agenda_config_equipe_chamada_prazo_du_check'),
  ('config', 'prazo da chamada 11 dias úteis', $q$update public.agenda_config set equipe_chamada_prazo_du = 11$q$, 'agenda_config_equipe_chamada_prazo_du_check'),
  ('config', '0 perguntas do cadastro abertas', $q$update public.agenda_config set equipe_cadastro_abertas_max = 0$q$, 'agenda_config_equipe_cadastro_abertas_max_check'),
  ('config', '7 perguntas do cadastro abertas', $q$update public.agenda_config set equipe_cadastro_abertas_max = 7$q$, 'agenda_config_equipe_cadastro_abertas_max_check'),
  ('config', 'chamar com 0 meio-dia', $q$update public.agenda_config set chamar_min_meios = 0$q$, 'agenda_config_chamar_min_meios_check'),
  ('config', 'chamar com 21 meios-dias', $q$update public.agenda_config set chamar_min_meios = 21$q$, 'agenda_config_chamar_min_meios_check'),
  ('config', 'citar 0 OS', $q$update public.agenda_config set chamar_max_os = 0$q$, 'agenda_config_chamar_max_os_check'),
  ('config', 'citar 11 OS', $q$update public.agenda_config set chamar_max_os = 11$q$, 'agenda_config_chamar_max_os_check'),
  ('config', 'os limites que entram (os 5 ligados, a pergunta no início e a 30 min do fim da janela, os extremos de cada parâmetro, sempre, a lista vazia)',
   $q$update public.agenda_config set modo_dias = 'ligado', modo_dupla = 'ligado', modo_sabado = 'ligado', modo_cadastro = 'ligado',
        modo_chamar = 'ligado', equipe_hora_dias = equipe_janela_fim - interval '30 minutes', equipe_dias_semanas_a_frente = 3,
        equipe_dias_tentar_dias = 6, equipe_dias_fechar_antes = '4 hours', dono_dias_semanal = false, dono_como_tecnico = true,
        dono_carga_max = 1.00, dias_semana_motivos = '{sempre}', dupla_tec_viagem_min = 6, dupla_espera_max_du = 20,
        novato_dias = 0, novato_diarias = 60, novato_sozinho = true, sob_demanda_sozinho = true, falta_semanas = 26,
        falta_dias_min = 60, equipe_chamada_dias = 180, equipe_chamada_prazo_du = 10, equipe_cadastro_abertas_max = 6,
        chamar_min_meios = 20, chamar_max_os = 10$q$, 'aceitou'),
  ('config', 'os outros limites que entram (desligados e sombra, a pergunta na abertura da janela, os mínimos, nenhum motivo)',
   $q$update public.agenda_config set modo_dias = 'sombra', modo_dupla = 'desligado', modo_sabado = 'sombra', modo_cadastro = 'desligado',
        modo_chamar = 'sombra', equipe_hora_dias = equipe_janela_inicio, equipe_dias_semanas_a_frente = 2, equipe_dias_tentar_dias = 1,
        equipe_dias_fechar_antes = '15 minutes', dono_carga_max = 0.20, dias_semana_motivos = '{}', dupla_tec_viagem_min = 2,
        dupla_espera_max_du = 0, novato_dias = 180, novato_diarias = 0, falta_semanas = 4, falta_dias_min = 4,
        equipe_chamada_dias = 14, equipe_chamada_prazo_du = 1, equipe_cadastro_abertas_max = 1, chamar_min_meios = 1,
        chamar_max_os = 1$q$, 'aceitou'),
  -- agenda_disponibilidade (a pessoa de teste)
  ('disponibilidade', 'semana presa numa terça', pg_temp.mais('disp', 'semana_dita', $v$'2026-11-17'$v$), 'disp_semana_e_segunda'),
  ('disponibilidade', 'semana presa num padrão',
   $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, semana_dita) values ('d7b00000-0000-4000-8000-0000000000e4', '{1,2}', 'disponivel', 'diarista', '2026-11-16')$q$,
   'disp_semana_so_excecao'),
  ('disponibilidade', 'só abre e fecha num padrão (dias da semana)',
   $q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values ('d7b00000-0000-4000-8000-0000000000e4', '{3}', 'so_pontas', 'dono')$q$,
   'disp_so_pontas_excecao'),
  ('disponibilidade', 'só abre e fecha sem pessoa (um recesso de todos)',
   $q$insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem) values (null, daterange('2026-11-18', '2026-11-18', '[]'), 'so_pontas', 'dono')$q$,
   'disp_so_pontas_excecao'),
  ('disponibilidade', 'situação que não existe',
   $q$insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem) values ('d7b00000-0000-4000-8000-0000000000e4', daterange('2026-11-16', '2026-11-16', '[]'), 'meio', 'diarista')$q$,
   'agenda_disponibilidade_situacao_check'),
  ('disponibilidade', 'a mensagem que não existe', pg_temp.mais('disp', 'mensagem_id', $v$'d7b00000-0000-4000-8000-0000000000ff'$v$), 'agenda_disponibilidade_mensagem_id_fkey'),
  ('disponibilidade', 'a pergunta que não existe', pg_temp.mais('disp', 'pergunta_id', $v$'d7b00000-0000-4000-8000-0000000000ff'$v$), 'agenda_disponibilidade_pergunta_id_fkey'),
  ('disponibilidade', 'a semana presa de seg 16/11 (uma linha por dia), da pergunta respondida e da mensagem',
   (select sql from _base where nome = 'msg') || '; '
   || pg_temp.mais('disp', 'semana_dita, mensagem_id, pergunta_id, nota', $v$'2026-11-16', 'd7b00000-0000-4000-8000-0000000000e6', 'd7b00000-0000-4000-8000-0000000000e5', 'Disse que pode (semana de 16/11)'$v$), 'aceitou'),
  ('disponibilidade', 'o dono só abre e fecha na qua 18/11 (so_pontas numa data, da pessoa)',
   $q$insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, semana_dita, nota) values ('d7b00000-0000-4000-8000-0000000000e4', daterange('2026-11-18', '2026-11-18', '[]'), 'so_pontas', 'dono', '2026-11-16', 'Você disse que só abre e fecha (semana de 16/11)')$q$,
   'aceitou'),
  -- agenda_gestor_dia
  ('diario', 'quem chamar que não é objeto', pg_temp.mais('dia', 'chamar', $v$'[]'$v$), 'agenda_gestor_dia_chamar_check'),
  ('diario', 'o dia com quem chamar', pg_temp.mais('dia', 'chamar', $v$'{"dupla": [], "capacidade": {"sem_lugar": [], "extra": null}, "prazo": []}'$v$), 'aceitou');

insert into _resultado
select format('B1 %s: %s', k.grupo, k.nome), r = k.espera, r
  from _casos k, lateral (select pg_temp.recusa(k.sql) as r) x;

-- O "quem chamar nulo" sai pelo NOT NULL da coluna (23502), antes do CHECK.
insert into _resultado
select 'B1 diario: quem chamar nulo (o NOT NULL da coluna)', r = '23502', r
  from (select pg_temp.recusa(pg_temp.mais('dia', 'chamar', 'null')) as r) x;

-- Todos os CHECKs desta migration: existem e cada um tem caso (um CHECK novo sem prova reprova aqui).
create temp table _checks_f7b (tabela regclass, nome text, primary key (tabela, nome)) on commit drop;
insert into _checks_f7b
select 'public.agenda_config'::regclass, 'agenda_config_' || n || '_check'
  from unnest(array['modo_dias', 'modo_dupla', 'modo_sabado', 'modo_cadastro', 'modo_chamar', 'equipe_hora_dias',
                    'equipe_dias_semanas_a_frente', 'equipe_dias_tentar_dias', 'equipe_dias_fechar_antes', 'dono_carga_max',
                    'dias_semana_motivos', 'dupla_tec_viagem_min', 'dupla_espera_max_du', 'novato_dias', 'novato_diarias',
                    'falta_semanas', 'falta_dias_min', 'equipe_chamada_dias', 'equipe_chamada_prazo_du',
                    'equipe_cadastro_abertas_max', 'chamar_min_meios', 'chamar_max_os']) n
union all
select t::regclass, n from (values
  ('public.agenda_disponibilidade', 'disp_semana_e_segunda'), ('public.agenda_disponibilidade', 'disp_semana_so_excecao'),
  ('public.agenda_disponibilidade', 'disp_so_pontas_excecao'), ('public.agenda_gestor_dia', 'agenda_gestor_dia_chamar_check')) as x(t, n);

insert into _resultado
select 'B1z os 26 CHECKs desta migration existem e todos têm caso (nenhum ficou sem prova)',
       count(*) = 26 and bool_and(exists (select 1 from pg_constraint c where c.conrelid = k.tabela and c.conname = k.nome
                                                                       and c.contype = 'c'))
       and bool_and(exists (select 1 from _casos x where x.espera = k.nome)),
       format('%s; sem constraint: %s; sem caso: %s', count(*),
              coalesce(string_agg(k.nome, ', ') filter (where not exists (select 1 from pg_constraint c
                         where c.conrelid = k.tabela and c.conname = k.nome)), '—'),
              coalesce(string_agg(k.nome, ', ') filter (where not exists (select 1 from _casos x where x.espera = k.nome)), '—'))
  from _checks_f7b k;

-- ── B2. As listas fechadas ──────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('B2a %s: as de antes iguais e na mesma ordem, e as novas no fim', t.nome),
       pg_temp.lista(t.tabela::regclass, t.nome) = t.espera
         -- FASE 7c: a 20261102100000 soma habilidade no fim de 4 destas (agenda_fase7c_base.sql B3a confere a lista inteira)
         || case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                                                          and a.attname = 'modo_habilidade' and not a.attisdropped)
                      and t.nome in ('agenda_perguntas_tipo_check', 'agenda_acoes_tipo_check', 'agenda_vigia_rodadas_rotina_check',
                                     'agenda_alocacoes_cancelada_motivo_check')
                 then '{habilidade}'::text[] else '{}'::text[] end
         -- (7c P8) a 20261102100550 soma tarefa (pergunta e ação), etapa (rascunho) e tarefas (rodada) no fim de 4 listas
         -- (agenda_fase7c_tarefas.sql T1e confere que as de antes ficam)
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
    ('public.agenda_disponibilidade', 'agenda_disponibilidade_situacao_check', '{disponivel,indisponivel,confirmada,so_pontas}'::text[]),
    ('public.agenda_equipe_mensagens', 'agenda_equipe_mensagens_tipo_check', '{ficha,confirmar,como_foi,resposta,dias}'::text[]),
    ('public.agenda_perguntas', 'agenda_perguntas_tipo_check',
     '{nao_cabe,segundo_atraso,atraso_longo,remarcar_confirmado,fixada_pelo_dono,conferencia,chegou,parada,estouro,duracao,material_conferir,padrao_do_dono,diaria,diaria_ligar,equipe_resposta,concluir,entrega,nfe_vincular,pix_material,previsao_fornecedor,fornecedor_cadastro,fornecedores_prazo,cliente_aprovar,cliente_aviso,cliente_resposta,aprendizado,equipe_sem_dias,situacao,estimativa,equipe_cadastro,reavaliar,reestimar,ficha_estimativa,bem_livre,compre_ate,sinal,onda,dia_avisado,dia_prometido,sabado,dias_semana}'::text[]),
    ('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check', '{vigia,rotina,material,cliente,aprender,gestor,equipe_semana}'::text[]),
    -- as que a 7b não amplia (a ação, a recusa e o cancelamento: os da 7a, iguais)
    ('public.agenda_acoes', 'agenda_acoes_tipo_check',
     '{publicar,criar,mover,cancelar,fixar,promover_reserva,soltar_reserva,status,resultado,desfazer,diaria,concluir,entregar,equipe,material,fornecedor,cliente,aprendizado,estimar,reestimar,reparar,gestor,dupla}'::text[]),
    ('public.agenda_equipe_mensagens', 'agenda_equipe_mensagens_recusa_motivo_check',
     '{teto,janela,domingo,sem_telefone,sem_plano,parou,modo,veto}'::text[]),
    ('public.agenda_alocacoes', 'agenda_alocacoes_cancelada_motivo_check',
     '{replanejado,desfeito,os_saiu,pessoa,material,cliente,clima,condicao_vencida,promovida,dono,espera,reestimada}'::text[])
  ) as t(tabela, nome, espera);

insert into _resultado
select 'B2b agenda_perguntas.critica: a expressão da 7a, igual (dias_semana não é crítica: as 8 de antes e as 4 da 7a, nesta ordem)',
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
select 'B2c os valores novos entram: a pergunta dias_semana (não crítica), a mensagem dias e a rodada equipe_semana; a situação so_pontas (B1)',
       (select not q.critica from public.agenda_perguntas q where q.id = 'd7b00000-0000-4000-8000-0000000000e5')
       and pg_temp.recusa((select sql from _base where nome = 'msg')) = 'aceitou'
       and pg_temp.recusa(replace((select sql from _base where nome = 'msg'), '''dias'', ''sombra''', '''semana'', ''sombra''')) = 'agenda_equipe_mensagens_tipo_check'
       and pg_temp.recusa($q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('equipe_semana', '2026-11-05', '2026-11-05 16:45-03', 'sombra', 'sombra')$q$)
           = 'aceitou'
       and pg_temp.recusa($q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('equipe_dias', '2026-11-05', '2026-11-05 16:45-03', 'sombra', 'sombra')$q$)
           = 'agenda_vigia_rodadas_rotina_check',
       pg_temp.recusa($q$insert into public.agenda_vigia_rodadas (rotina, p_hoje, p_agora, modo_proposta, modo_vigia) values ('equipe_semana', '2026-11-05', '2026-11-05 16:45-03', 'sombra', 'sombra')$q$);

-- ── B3. so_pontas, semana_dita, as FKs, o índice e a marca de dupla da 7a ─────────────────────────────────
insert into _resultado
select 'B3a as FKs novas da disponibilidade: a mensagem da equipe e a pergunta do dono, as duas on delete set null',
       count(*) = 2 and bool_and(c.confdeltype = 'n')
       and string_agg(c.conname || '>' || c.confrelid::regclass::text, ',' order by c.conname)
           = 'agenda_disponibilidade_mensagem_id_fkey>agenda_equipe_mensagens,agenda_disponibilidade_pergunta_id_fkey>agenda_perguntas',
       string_agg(c.conname || '>' || c.confrelid::regclass::text || ':' || c.confdeltype::text, ',' order by c.conname)
  from pg_constraint c
 where c.conrelid = 'public.agenda_disponibilidade'::regclass and c.contype = 'f'
   and c.conname in ('agenda_disponibilidade_mensagem_id_fkey', 'agenda_disponibilidade_pergunta_id_fkey');

insert into _resultado
select 'B3b o índice agenda_disp_semana: (payee_id, semana_dita) só das linhas vivas com semana',
       pg_get_indexdef(i.indexrelid) like '%(payee_id, semana_dita)%'
       and pg_get_expr(i.indpred, i.indrelid) like '%substituida_em IS NULL%'
       and pg_get_expr(i.indpred, i.indrelid) like '%semana_dita IS NOT NULL%',
       pg_get_indexdef(i.indexrelid)
  from pg_index i where i.indexrelid = 'public.agenda_disp_semana'::regclass;

insert into _resultado
select 'B3c os CHECKs de antes da disponibilidade continuam (o padrão ou a exceção, os dias, a frequência só no histórico: a linha do dono nunca tem frequência)',
       pg_temp.recusa($q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem, frequencia) values ('d7b00000-0000-4000-8000-0000000000e4', '{1,2,3,4,5}', 'disponivel', 'dono', 0.5)$q$)
         = 'frequencia_so_historico'
       and pg_temp.recusa($q$insert into public.agenda_disponibilidade (payee_id, dias_semana, periodo, situacao, origem) values ('d7b00000-0000-4000-8000-0000000000e4', '{1}', daterange('2026-11-16', '2026-11-16', '[]'), 'so_pontas', 'dono')$q$)
         = 'padrao_ou_excecao'
       and pg_temp.recusa($q$insert into public.agenda_disponibilidade (payee_id, dias_semana, situacao, origem) values ('d7b00000-0000-4000-8000-0000000000e4', '{1,2,3,4,5}', 'disponivel', 'dono')$q$)
         = 'aceitou',
       null;

insert into _resultado
select 'B3d dupla_meios_coerente (da 7a) continua: a dupla só no início com os meios-dias; a OS inteira sem eles',
       exists (select 1 from pg_constraint c where c.conrelid = 'public.os_planejamento'::regclass and c.conname = 'dupla_meios_coerente'
                                             and pg_get_constraintdef(c.oid) like '%dupla_meios IS NOT NULL%'),
       (select pg_get_constraintdef(c.oid) from pg_constraint c
         where c.conrelid = 'public.os_planejamento'::regclass and c.conname = 'dupla_meios_coerente');

-- ── B4. RLS e privilégios ───────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'B4a as tabelas que ganharam coluna continuam como eram: RLS ligada, uma policy de leitura TO authenticated, anon sem nada, authenticated só lê, service_role escreve',
       bool_and(c.relrowsecurity)
       and bool_and((select count(*) from pg_policy p where p.polrelid = c.oid) = 1)
       and bool_and((select bool_and(p.polcmd = 'r' and p.polroles = array[(select oid from pg_roles where rolname = 'authenticated')])
                       from pg_policy p where p.polrelid = c.oid))
       and bool_and(not has_table_privilege('anon', c.oid, 'select') and not has_table_privilege('anon', c.oid, 'insert')
                    and not has_table_privilege('anon', c.oid, 'update'))
       and bool_and(has_table_privilege('authenticated', c.oid, 'select') and not has_table_privilege('authenticated', c.oid, 'insert')
                    and not has_table_privilege('authenticated', c.oid, 'update'))
       and bool_and(has_table_privilege('service_role', c.oid, 'insert') and has_table_privilege('service_role', c.oid, 'update')),
       string_agg(c.relname || ':rls=' || c.relrowsecurity || ':policies=' || (select count(*) from pg_policy p where p.polrelid = c.oid), ', ')
  from pg_class c
 where c.oid in ('public.agenda_config'::regclass, 'public.agenda_disponibilidade'::regclass, 'public.agenda_gestor_dia'::regclass);

insert into _resultado
select 'B4b o técnico: a disponibilidade e o diário voltam vazios; gravar a semana presa dá 42501; anon não lê; o administrador lê as colunas novas',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select count(*)::text from public.agenda_disponibilidade where semana_dita is not null$q$) = '0'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select count(*)::text from public.agenda_gestor_dia$q$) = '0'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, semana_dita) values ('d7b00000-0000-4000-8000-0000000000e4', daterange('2026-11-17', '2026-11-17', '[]'), 'disponivel', 'diarista', '2026-11-16') returning 'x'$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$update public.agenda_config set modo_dias = 'ligado' returning 'x'$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select count(*)::text from public.agenda_disponibilidade$q$) like 'erro 42501%'
       and pg_temp.como(null, 'anon', $q$select modo_dias from public.agenda_config$q$) like 'erro 42501%'
       and pg_temp.como('aa000000-0000-4000-8000-000000000001', 'authenticated',
             $q$select modo_dias || '/' || dono_carga_max || '/' || (select count(*) from public.agenda_disponibilidade where semana_dita is null) from public.agenda_config$q$)
           like 'desligado/0.50/%',
       pg_temp.como('aa000000-0000-4000-8000-0000000000ff', 'authenticated',
             $q$select count(*)::text from public.agenda_disponibilidade where semana_dita is not null$q$);

insert into _resultado
select 'B4c _agenda_modo_da_pergunta recriada: só o service_role executa (anon e authenticated não), invoker, STABLE, search_path fixo — como antes',
       not has_function_privilege('anon', 'public._agenda_modo_da_pergunta(text, text)', 'execute')
       and not has_function_privilege('authenticated', 'public._agenda_modo_da_pergunta(text, text)', 'execute')
       and has_function_privilege('service_role', 'public._agenda_modo_da_pergunta(text, text)', 'execute')
       and not p.prosecdef and p.provolatile = 's' and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%',
       p.provolatile::text || ':' || p.prosecdef::text || ':' || coalesce(array_to_string(p.proconfig, ','), '')
  from pg_proc p where p.oid = 'public._agenda_modo_da_pergunta(text, text)'::regprocedure;

do $b4d$
declare
  v_mig text := coalesce(current_setting('agenda_teste.mig_tabelas_fase7b', true), '');
  v_fns text;
begin
  if v_mig = '' then
    insert into _resultado values ('B4d a migration só recria _agenda_modo_da_pergunta', true,
      'PULADO: sem agenda_teste.mig_tabelas_fase7b (rode pela bancada)');
    return;
  end if;
  select string_agg(m[1], ',' order by o) into v_fns
    from regexp_matches(replace(v_mig, E'\r\n', E'\n'), 'create or replace function public\.([a-z_0-9]+)\(', 'g') with ordinality t(m, o);
  insert into _resultado values ('B4d a migration não cria função nova (as _agenda_* novas e agenda_equipe_semana são do P2/P3): só recria _agenda_modo_da_pergunta; nenhuma policy, nenhum grant a anon',
    v_fns = '_agenda_modo_da_pergunta'
    and position('create policy' in lower(v_mig)) = 0
    and v_mig !~* 'grant[^;]*to[^;]*\manon\M',
    coalesce(v_fns, '—'));
end
$b4d$;

-- ── B5. As regex dos gatilhos e das notas de dupla ──────────────────────────────────────────────────────
insert into _resultado
select 'B5a os 4 gatilhos de dupla padrão (o DEFAULT da coluna, da 7a): cada expressão compila como o casamento a usa (''\m('' || expressão || '')''), e a lista passa no CHECK',
       count(*) = 4 and bool_and(public._agenda_regex_valido('\m(' || (e ->> 1) || ')'))
       and public._agenda_dupla_lista_ok((select c.dupla_gatilhos from public.agenda_config c where c.id), true)
       and array_agg(e ->> 0 order by o) = '{banco_cc,bateria_pesada,ca_energizado,icamento}',
       string_agg((e ->> 0) || ':' || public._agenda_regex_valido('\m(' || (e ->> 1) || ')')::text, ',' order by o)
  from public.agenda_config c, jsonb_array_elements(c.dupla_gatilhos) with ordinality t(e, o)
 where c.id;

insert into _resultado
select 'B5b as notas de dupla padrão (o confinado) compilam e passam no CHECK; um gatilho que não compila não passa',
       bool_and(public._agenda_regex_valido('\m(' || (e ->> 1) || ')'))
       and public._agenda_dupla_lista_ok((select c.dupla_notas from public.agenda_config c where c.id), false)
       and not public._agenda_dupla_lista_ok('[["banco_cc","litio(","inicio",2]]'::jsonb, true)
       and not public._agenda_regex_valido('\m(litio()'),
       string_agg((e ->> 0) || ':' || public._agenda_regex_valido('\m(' || (e ->> 1) || ')')::text, ',')
  from public.agenda_config c, jsonb_array_elements(c.dupla_notas) e
 where c.id;

insert into _resultado
select 'B5c os gatilhos casam o nome do serviço normalizado do Lenine (banco_cc) e não o de 12 V (a régua do M1 do P4)',
       public._agenda_normal('substituição baterias chumbo para lítio') ~ ('\m(' || (c.dupla_gatilhos -> 0 ->> 1) || ')')
       and public._agenda_normal('Revisão do quadro 12V') !~ ('\m(' || (c.dupla_gatilhos -> 0 ->> 1) || ')')
       and public._agenda_normal('Revisão do quadro na casa de máquinas') ~ ('\m(' || (c.dupla_notas -> 0 ->> 1) || ')'),
       public._agenda_normal('substituição baterias chumbo para lítio')
  from public.agenda_config c where c.id;

-- ── B6. O modo de quem faz cada tipo de pergunta ────────────────────────────────────────────────────────
do $b6$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_protecoes_fase7a', true), '');
  v_esta text := coalesce(current_setting('agenda_teste.mig_tabelas_fase7b', true), '');
  cf    public.agenda_config;
  v_a   text;
  v_n   int;
  v_novo text;
  r     record;
begin
  select * into cf from public.agenda_config where id;
  -- dias_semana = modo_dias, nos 3 estados
  for r in select * from (values ('desligado'), ('sombra'), ('ligado')) t(m) loop
    update public.agenda_config set modo_dias = r.m where id;
    v_res := pg_temp.ok(v_res, 'B6a dias_semana = modo_dias (' || r.m || ')',
      public._agenda_modo_da_pergunta('dias_semana', 'dias_semana:x:2026-11-16') = r.m,
      public._agenda_modo_da_pergunta('dias_semana', 'dias_semana:x:2026-11-16'));
  end loop;
  -- equipe_cadastro: desligado = o do gestor que marca (como antes); sombra e ligado = o modo_cadastro
  update public.agenda_config set modo_marcar_sozinho = 'ligado', gestor_so_propor = false, modo_cadastro = 'desligado' where id;
  v_a := public._agenda_modo_da_pergunta('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-09');
  update public.agenda_config set modo_marcar_sozinho = 'desligado' where id;
  v_a := v_a || ',' || public._agenda_modo_da_pergunta('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-09');
  update public.agenda_config set modo_cadastro = 'sombra', modo_marcar_sozinho = 'ligado' where id;
  v_a := v_a || ',' || public._agenda_modo_da_pergunta('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-09');
  update public.agenda_config set modo_cadastro = 'ligado', modo_marcar_sozinho = 'desligado' where id;
  v_a := v_a || ',' || public._agenda_modo_da_pergunta('equipe_cadastro', 'equipe_cadastro:telefone:x');
  v_res := pg_temp.ok(v_res, 'B6b equipe_cadastro: com modo_cadastro desligado, o do gestor que marca (ligado, depois desligado); fora de desligado, o modo_cadastro (sombra com o gestor ligado; ligado com o gestor desligado)',
    v_a = 'ligado,desligado,sombra,ligado', v_a);
  update public.agenda_config
     set modo_dias = cf.modo_dias, modo_cadastro = cf.modo_cadastro, modo_marcar_sozinho = cf.modo_marcar_sozinho,
         gestor_so_propor = cf.gestor_so_propor
   where id;

  v_res := pg_temp.ok(v_res, 'B6c todo tipo da lista fechada tem o modo de quem o faz (o tipo novo sem modo reprova aqui)',
    not exists (select 1 from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t
                 where public._agenda_modo_da_pergunta(t, t || ':x') is null),
    (select string_agg(t, ',') from unnest(pg_temp.lista('public.agenda_perguntas'::regclass, 'agenda_perguntas_tipo_check')) t
      where public._agenda_modo_da_pergunta(t, t || ':x') is null));

  if v_mig = '' or v_esta = '' then
    v_res := pg_temp.ok(v_res, 'B6d e B6e (o de antes e a cópia)', true,
      'PULADO: sem agenda_teste.mig_protecoes_fase7a e agenda_teste.mig_tabelas_fase7b (rode pela bancada)');
    perform pg_temp.gravar(v_res);
    return;
  end if;

  -- o de antes (a definição de 20261031100850 rodada como pg_temp) em cada estado: só dias_semana muda (não existia)
  execute replace(pg_temp.inteira(v_mig, '_agenda_modo_da_pergunta'), 'create or replace function public._agenda_modo_da_pergunta(',
                  'create function pg_temp.modo_antes(');
  for r in select * from (values ('desligado', 'desligado', false), ('ligado', 'sombra', false), ('sombra', 'ligado', true))
                           t(m, m2, sp) loop
    update public.agenda_config
       set modo_marcar_sozinho = r.m, modo_revisao_diaria = r.m2, modo_compre_ate = r.m, gestor_so_propor = r.sp, modo_dias = r.m2,
           modo_cadastro = 'desligado'
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
    v_res := pg_temp.ok(v_res, format('B6d com modo_cadastro desligado, o modo de cada tipo é o de antes (a definição de 20261031100850), menos dias_semana (nova) — o gestor %s, só propor %s', r.m, r.sp),
      -- FASE 7c: a 20261102100000 soma o tipo habilidade (o agenda_fase7c_base.sql B11c confere o modo dele)
      v_a = 'dias_semana' || case when to_regclass('public.agenda_etiquetas') is null then '' else ',habilidade' end
            -- (7c P8) e o tipo tarefa (20261102100550; o agenda_fase7c_tarefas.sql T18 confere a cópia e o modo dele)
            || case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                                       and a.attname = 'modo_tarefas' and not a.attisdropped) then ',tarefa' else '' end
      and v_n = 41 + case when to_regclass('public.agenda_etiquetas') is null then 0 else 1 end
              + case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass
                                       and a.attname = 'modo_tarefas' and not a.attisdropped) then 1 else 0 end,
      -- FASE 7c: fim
      coalesce(v_a, '-') || ' de ' || v_n);
  end loop;
  update public.agenda_config
     set modo_marcar_sozinho = cf.modo_marcar_sozinho, modo_revisao_diaria = cf.modo_revisao_diaria, modo_compre_ate = cf.modo_compre_ate,
         gestor_so_propor = cf.gestor_so_propor, modo_dias = cf.modo_dias, modo_cadastro = cf.modo_cadastro
   where id;

  -- a cópia: o corpo vivo = o desta migration, e sem o bloco "-- FASE 7b:" é o de 20261031100850
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public._agenda_modo_da_pergunta(text, text)'::regprocedure;
  -- FASE 7c: a 20261102100000 recria de novo com o bloco "-- FASE 7c:" (só acréscimo): ele sai antes da régua da cópia da 7b
  v_novo := array_to_string(array(
              select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[cdefg]:' and l !~ '^\s*-- FASE 7[cdefg]: fim' then 1
                                                   when l ~ '^\s*-- FASE 7[cdefg]: fim' then -1 else 0 end)
                                          over (order by o rows between unbounded preceding and current row) as dentro,
                                    l ~ '^\s*-- FASE 7[cdefg]: fim' as fecha
                               from unnest(string_to_array(v_novo, E'\n')) with ordinality u(l, o)) x
               where dentro = 0 and not fecha order by o), E'\n');
  -- FASE 7c: fim
  select count(*) into v_n from regexp_matches(v_novo, '-- FASE 7b: fim', 'g');
  v_res := pg_temp.ok(v_res, 'B6e a cópia de _agenda_modo_da_pergunta: o corpo vivo é o desta migration; sem o bloco "-- FASE 7b:" (1), é o corpo de 20261031100850 (a mais nova antes da 7b)',
    v_n = 1 and v_novo = pg_temp.corpo(v_esta, '_agenda_modo_da_pergunta')
    and pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta') <> ''
    and pg_temp.sem_7b(v_novo) = pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta'),
    format('blocos %s; fonte %s letras; novo sem o bloco %s letras', v_n, length(pg_temp.corpo(v_mig, '_agenda_modo_da_pergunta')),
           length(pg_temp.sem_7b(v_novo))));
  perform pg_temp.gravar(v_res);
end
$b6$;

-- ── B7. A fixture da 7b ─────────────────────────────────────────────────────────────────────────────────
do $b7$
declare
  v_res   jsonb := '[]'::jsonb;
  v_dono  uuid;
  v_a     text;
  v_b     text;
  v_n     int;
  v_sem   jsonb;
  v_md5   text;
  v_md5b  text;
  c_cont  constant text := 'select coalesce(c.recebe_rotina::text || ''/'' || c.incluido_por || ''/'' || (c.parou_em is not null)::text, ''-'') from public.agenda_equipe_contato c where c.payee_id = p.id';
begin
  if coalesce(current_setting('agenda_teste.fase7b', true), '') = '' or coalesce(current_setting('agenda_teste.fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    insert into _resultado values ('B7 (a fixture da 7b)', true,
      'PULADO: sem agenda_teste.fase7b, agenda_teste.fase7a e agenda_teste.replay2910 (rode pela bancada)');
    return;
  end if;

  -- a variante 'real' numa subtransação desfeita (a equipe de produção: só o Alex e o dono)
  begin
    perform set_config('agenda_teste.fase7b_equipe', 'real', true);
    execute current_setting('agenda_teste.fase7b');
    v_sem := public.agenda_capacidade_semanal();
    v_res := pg_temp.ok(v_res, 'B7a a variante ''real'' (a equipe de produção de 31/10): Mateus, Rafael e Bruno fora; a semana típica é só o Alex, 5 diárias e 4 comprometíveis (a de produção, wf7b_r4_01)',
      not exists (select 1 from public.payees where name in ('Mateus', 'Rafael', 'Bruno'))
      and (v_sem ->> 'diarias_semana')::numeric = 5 and (v_sem ->> 'comprometivel')::numeric = 4
      and jsonb_array_length(v_sem -> 'pessoas') = 1 and v_sem -> 'pessoas' -> 0 ->> 'nome' = 'Alex',
      v_sem::text);
    raise exception 'desfaz' using errcode = 'P0097';
  exception when sqlstate 'P0097' then null;
  end;
  perform set_config('agenda_teste.fase7b_equipe', '', true);

  execute current_setting('agenda_teste.fase7b');
  select md5(string_agg(t, '|' order by t)) into v_md5
    from (select 'p:' || p.id || p.name as t from public.payees p
          union all select 'd:' || d.id || coalesce(d.substituida_em::text, '') from public.agenda_disponibilidade d
          union all select 'c:' || c.payee_id || c.recebe_rotina from public.agenda_equipe_contato c
          union all select 'q:' || q.id || q.estado from public.agenda_perguntas q
          union all select 'a:' || a.id || a.estado from public.agenda_alocacoes a
          union all select 'o:' || so.id from public.service_orders so) x;
  execute current_setting('agenda_teste.fase7b');
  select md5(string_agg(t, '|' order by t)) into v_md5b
    from (select 'p:' || p.id || p.name as t from public.payees p
          union all select 'd:' || d.id || coalesce(d.substituida_em::text, '') from public.agenda_disponibilidade d
          union all select 'c:' || c.payee_id || c.recebe_rotina from public.agenda_equipe_contato c
          union all select 'q:' || q.id || q.estado from public.agenda_perguntas q
          union all select 'a:' || a.id || a.estado from public.agenda_alocacoes a
          union all select 'o:' || so.id from public.service_orders so) x;
  v_res := pg_temp.ok(v_res, 'B7b carregar a fixture 2× na mesma transação = 1× (cada parte confere se já está lá)', v_md5 = v_md5b, null);

  v_dono := public._agenda_dono(null);
  -- as pessoas: nome:tipo:dígitos do telefone:linhas vivas:contato:perfil vigente
  execute format($q$
    select string_agg(p.name || ':' || p.kind || ':' || coalesce(length(regexp_replace(p.phone, '\D', '', 'g')), 0)
             || ':' || (select count(*) from public.agenda_disponibilidade d where d.payee_id = p.id and d.substituida_em is null)
             || ':' || coalesce((%s), '-')
             || ':' || exists (select 1 from public.work_profiles w where w.payee_id = p.id and w.vigencia_fim is null),
             ' ; ' order by p.name)
      from public.payees p where p.kind <> 'socio' and p.name not like 'TESTE%%'$q$, c_cont) into v_a;
  v_res := pg_temp.ok(v_res, 'B7c as pessoas (R4.8): Alex (sem telefone, a linha do dono, na rotina pelo dono, sem perfil); Bruno (o novato: telefone, uma data dita, fora da rotina, perfil); João (perfil, sem telefone, sem linha, sem contato); Mateus (prestador, telefone, sem perfil, sem linha, sem contato); Mickael (perfil, telefone, sem linha); Rafael (diarista, telefone, o padrão, na rotina pela regra, perfil); Roberto (perfil, telefone, sem linha, o contato parado); Vinicius não existe',
    v_a = 'Alex:prestador:0:1:true/dono/false:false ; Bruno:diarista:13:1:-:true ; João:prestador:0:0:-:true ; '
          'Mateus:prestador:13:0:-:false ; Mickael:prestador:13:0:-:true ; Rafael:diarista:13:1:true/regra/false:true ; '
          'Roberto:prestador:13:0:false/regra/true:true'
    and not exists (select 1 from public.payees where name ilike 'vin%cius'),
    v_a);

  v_res := pg_temp.ok(v_res, 'B7d o 30/10: a semente do Roberto e do João trocada às 00:11 (9 linhas, nenhuma viva); a linha do Alex de seg a sex, turno nulo, origem dono, "você disse em 29/10", sem frequência',
    (select count(*) from public.agenda_disponibilidade d join public.payees p on p.id = d.payee_id
      where p.name in ('Roberto', 'João') and d.origem = 'historico' and d.substituida_em = timestamptz '2026-10-30 00:11:02.381928-03') = 9
    and exists (select 1 from public.agenda_disponibilidade d join public.payees p on p.id = d.payee_id
                 where p.name = 'Alex' and d.substituida_em is null and d.dias_semana = '{1,2,3,4,5}' and d.turno is null
                   and d.origem = 'dono' and d.situacao = 'disponivel' and d.frequencia is null and d.nota = 'você disse em 29/10'),
    null);

  select string_agg(distinct a.estado || ':' || coalesce(a.cancelada_motivo, '-') || ':' || to_char(a.cancelada_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), ','),
         count(*)
    into v_a, v_n
    from public.agenda_alocacoes a join public.service_orders so on so.id = a.service_order_id
   where so.service_order_number = 'OS-00074' and a.tipo = 'reserva';
  v_res := pg_temp.ok(v_res, 'B7e o 30/10: as 12 reservas do Lenine soltas pela vigia às 00:15 (pessoa) e a pergunta material_conferir dele resolvida; nada do Lenine marcado',
    v_n = 12 and v_a = 'cancelada:pessoa:30/10 00:15'
    and exists (select 1 from public.agenda_perguntas q join public.service_orders so on q.chave = 'material_conferir:' || so.id
                 where so.service_order_number = 'OS-00074' and q.estado = 'resolvida'
                   and q.resolvida_motivo = 'a reserva saiu: o lugar que eu tinha guardado não existe mais')
    and not exists (select 1 from public.agenda_alocacoes a join public.service_orders so on so.id = a.service_order_id
                     where so.service_order_number = 'OS-00074' and a.estado in ('publicada', 'fixada')),
    format('%s: %s', v_n, v_a));

  v_res := pg_temp.ok(v_res, 'B7f o 30/10: a pergunta padrao_do_dono:sem_dias do lote aberta, ligada, não crítica, vista 1 vez (o aviso de 30/10 09:30), com o texto da vigia; o dono sem linha nenhuma; as 2 de fornecedor abertas nunca vistas (como em produção)',
    exists (select 1 from public.agenda_perguntas q
             where q.chave = 'padrao_do_dono:sem_dias' and q.estado = 'aberta' and q.modo = 'ligado' and not q.critica
               and q.mostrada_vezes = 1 and q.mostrada_via = 'aviso'
               and q.texto like 'Não sei em que dias você fica em campo, e % de você. Quais dias da semana você vai? Por exemplo: "fico em campo de segunda a sexta".')
    and not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_dono)
    and (select count(*) from public.agenda_perguntas q
          where q.tipo in ('fornecedor_cadastro', 'fornecedores_prazo') and q.estado = 'aberta' and q.mostrada_vezes = 0) = 2,
    (select q.texto from public.agenda_perguntas q where q.chave = 'padrao_do_dono:sem_dias'));

  v_res := pg_temp.ok(v_res, 'B7g Rafael: o padrão que ele disse (seg a sex, origem diarista, "Disse em 29/10"), na rotina pela regra; Bruno: o novato — perfil desde 20/10, 3 diárias aprovadas, a data dita pelo dono (ter 10/11, o dia todo), sem contato; o "Mateus" fornecedor continua fornecedor',
    exists (select 1 from public.agenda_disponibilidade d join public.payees p on p.id = d.payee_id
             where p.name = 'Rafael' and d.substituida_em is null and d.dias_semana = '{1,2,3,4,5}' and d.origem = 'diarista'
               and d.frequencia is null and d.nota = 'Disse em 29/10')
    and (select count(*) from public.work_shifts s join public.work_profiles w on w.id = s.work_profile_id join public.payees p on p.id = w.payee_id
          where p.name = 'Bruno' and s.status = 'aprovado') = 3
    and exists (select 1 from public.work_profiles w join public.payees p on p.id = w.payee_id
                 where p.name = 'Bruno' and w.vigencia_inicio = date '2026-10-20' and w.vigencia_fim is null)
    and exists (select 1 from public.agenda_disponibilidade d join public.payees p on p.id = d.payee_id
                 where p.name = 'Bruno' and d.substituida_em is null and d.periodo = daterange(date '2026-11-10', date '2026-11-10', '[]')
                   and d.origem = 'dono' and d.situacao = 'disponivel' and d.turno is null)
    and exists (select 1 from public.suppliers s where s.name = 'Mateus'),
    null);

  select string_agg(x.pessoa || '@' || to_char(x.dia, 'DD/MM') || x.turno || '=' || x.situacao, ' ' order by x.pessoa, x.dia, x.turno)
    into v_a
    from public.agenda_capacidade(date '2026-11-10', date '2026-11-10', date '2026-11-05') x where not x.eh_dono;
  v_sem := public.agenda_capacidade_semanal();
  v_res := pg_temp.ok(v_res, 'B7h a grade de ter 10/11: Alex, Bruno (só nessa data) e Rafael, manhã e tarde; ninguém que saiu; a semana típica: Alex e Rafael (5 + 5)',
    v_a = 'Alex@10/11manha=livre Alex@10/11tarde=livre Bruno@10/11manha=livre Bruno@10/11tarde=livre Rafael@10/11manha=livre Rafael@10/11tarde=livre'
    and (v_sem ->> 'diarias_semana')::numeric = 10,
    v_a || ' | ' || v_sem::text);

  v_res := pg_temp.ok(v_res, 'B7i as OS: o Vanderlei (OS-00069) com prazo qua 18/11; a OS-97101 do Otávio com a revisão do quadro na casa de máquinas (R$ 764, a nota de confinado), aberta e aprovada; a Kalmar OS-00033 com 2 técnicos no orçamento',
    exists (select 1 from public.os_planejamento pl join public.service_orders so on so.id = pl.service_order_id
             where so.service_order_number = 'OS-00069' and pl.precisa_ate = date '2026-11-18')
    and exists (select 1 from public.service_orders so join public.service_order_services s on s.service_order_id = so.id
                 join public.clients cl on cl.id = so.client_id
                 where so.service_order_number = 'OS-97101' and so.status = 'open' and so.quote_status = 'approved'
                   and cl.name = 'Otávio' and s.name_snapshot = 'Revisão do quadro na casa de máquinas' and s.line_total = 764)
    and (select so.technician_count_for_travel from public.service_orders so where so.service_order_number = 'OS-00033') = 2,
    null);

  -- a variante 'campo' (a linha do dono)
  perform set_config('agenda_teste.fase7b_dono', 'campo', true);
  execute current_setting('agenda_teste.fase7b');
  perform set_config('agenda_teste.fase7b_dono', '', true);
  v_res := pg_temp.ok(v_res, 'B7j a variante ''campo'': a linha do dono de seg a sex, origem dono, turno nulo, disponível, sem frequência; a pergunta do lote resolvida ("você disse os dias")',
    (select count(*) from public.agenda_disponibilidade d
      where d.payee_id = v_dono and d.substituida_em is null and d.dias_semana = '{1,2,3,4,5}' and d.origem = 'dono'
        and d.turno is null and d.situacao = 'disponivel' and d.frequencia is null) = 1
    and exists (select 1 from public.agenda_perguntas q where q.chave = 'padrao_do_dono:sem_dias' and q.estado = 'resolvida'
                                                         and q.resolvida_motivo = 'você disse os dias'),
    null);
  perform pg_temp.gravar(v_res);
end
$b7$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
