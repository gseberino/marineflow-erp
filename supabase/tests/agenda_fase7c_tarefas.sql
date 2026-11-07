-- Prova das tarefas do dia (as etapas da OS), Agenda de Produção Fase 7c, pacote P8 (migration 20261102100550).
-- bancada: depende de 20261102100550
--
-- Spec: scratchpad agenda-pesquisa/spec-fase7c.md §16 (o P8) com o R5.2, o R5.4 e o R5.10-6, -10, -11 e -13; fixture
-- scripts/bancada-agenda/fixture-fase7c-tarefas.sql (qua 04/11/2026; as OS 97191 a 97196, o Alex e o Mateus).
--   T1  as colunas, os padrões e os CHECKs (o modo nasce desligado na linha e sombra no padrão; fase, regex, linhas, alerta, hora e
--       vale-dia inválidos recusados); as listas ampliadas mantêm os valores de antes; as 2 tabelas, a RLS e os gatilhos (não apaga,
--       só muda o que pode)
--   T2  as portas: anon nada; a técnica logada 42501 nas leituras com porta; as peças de dentro sem grant; a RPC e a rodada; a régua do
--       telefone da 7a com authenticated e sem anon (R5.10-13)
--   T3  as etapas pela base das 6 OS (os_tarefas_fonte): textos, fases, pesos, máscaras, passos e o que fica de fora; 192 = 193
--   T4  o texto e a fase (§16.3.2, §16.3.3) e as 45 linhas reais da carteira
--   T5  a sincronização: idempotente; o escopo que aumenta (191) antes do final, com a ação; a linha que sai; a feita fica; a máscara muda
--       sem refazer a ordem
--   T6  a distribuição: 192 (a manhã do Mateus sem a etapa de risco; pendente → começada → resto), 191 (a soma = o total; a sobra no prazo
--       depois do escopo), 194 (configurar e testar só no fechamento do dono), sem quem faça (só o Mateus)
--   T7  o congelamento: amanhã às 19:30 e não às 19:29; hoje no 1º tique; uma vez só; o meio-dia sem alocação cancela; sombra × ligado
--   T8  a ficha: desligado e sombra = a de antes (as saídas inteiras); ligado = os textos da §16.6.1–16.6.3; os tamanhos (440, 590, 600)
--   T9  a leitura das etapas na resposta (o corpus)
--   T10 a resposta ao "como foi": desligado e sombra = a de antes; ligado — ok, ok faltou a 1 (o parcial e a diária), o motivo, tudo e
--       nunca, a palavra sem OK, falou de falta sem dizer qual, o Mateus responde a dele, o texto que não confere
--   T11 a conferência: dia feito, dia parcial, sem registro (segue o plano, R5.2-3), o desfaz, a equipe e o dono por cima, o roteiro
--   T12 as exceções: a 2ª pendência (uma ação por sequência), não cabe até o prazo (aberta e "coube"), sem quem faça, em teste
--   T13 a conclusão pela palavra do técnico: a pendente dita segura; sem ela conclui; o parâmetro; só sem registro conclui
--   T14 as leituras: a linha "Etapas" da OS e o dia da pessoa (ligado e sombra; desligado = antes); até 400
--   T15 o rascunho etapa: as 3 formas, as guardas, o número que não vale (R5.10-10), o *grava* (o falta grava pendente via dono)
--   T16 as medidas
--   T17 a rodada: desligado não grava; o tique sem nada não grava; o diário uma vez; o passo que falha; o tempo
--   T18 as cópias: as 9 recriadas só acrescentam os blocos do P8
--   T19 a linha (o) do fechamento e a (n) com as perguntas das etapas (R5.2-2): o Alex sem telefone; a véspera do último dia; em teste
--   T20 o fechamento com as etapas desligadas = o de antes (a saída inteira)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261102100550
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase7c_tarefas.sql
--   Sem a fixture (produção) os cenários saem PULADO e só T1, T2, T4 (a tabela da spec) e T9 rodam. Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
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
-- O texto sem os blocos do P8 ("-- FASE 7c: (7c P8 … -- FASE 7c: fim") e sem as marcas de dentro do P8 ("-- (7c P8 … -- (7c: fim)"); as
-- linhas de abrir e de fechar saem junto. Os blocos dos pacotes de antes (P1 a P6) ficam.
create function pg_temp.sem_p8(p text) returns text language plpgsql immutable as $f$
declare
  v_out text[] := '{}';
  l     text;
  v_b   boolean := false;
  v_m   boolean := false;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_b and not v_m and l ~ '^\s*-- FASE 7c: \(7c P8' then v_b := true; continue; end if;
    if not v_b and not v_m and l ~ '^\s*-- \(7c P8' then v_m := true; continue; end if;
    if v_b then if l ~ '^\s*-- FASE 7c: fim' then v_b := false; end if; continue; end if;
    if v_m then if l ~ '^\s*-- \(7c: fim\)' then v_m := false; end if; continue; end if;
    v_out := v_out || l;
  end loop;
  return array_to_string(v_out, E'\n');
end $f$;
-- FASE 7c: (correção da revisão, 20261102100580) o texto sem os blocos da correção ("-- FASE 7c: (7c correção … -- FASE 7c: fim") e
-- sem as marcas dela ("-- (7c correção … -- (7c: fim)"), para o T18b comparar a viva com a desta migration.
-- FASE 7d: (7d P1) o texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim": a 20261107100000 recria _agenda_modo_da_pergunta de novo (só
-- acréscimo), e o T18b compara a viva com a desta migration
create function pg_temp.sem_7d(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when l ~ '^\s*-- FASE 7[df]:' and l !~ '^\s*-- FASE 7[df]: fim' then 1
                                                when l ~ '^\s*-- FASE 7[df]: fim' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- FASE 7[df]: fim' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- FASE 7d: fim
create function pg_temp.sem_corr(p text) returns text language plpgsql immutable as $f$
declare
  v_out text[] := '{}';
  l     text;
  v_b   boolean := false;
  v_m   boolean := false;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_b and not v_m and l ~ '^\s*-- FASE 7c: \(7c correção' then v_b := true; continue; end if;
    if not v_b and not v_m and l ~ '^\s*-- \(7c correção' then v_m := true; continue; end if;
    if v_b then if l ~ '^\s*-- FASE 7c: fim' then v_b := false; end if; continue; end if;
    if v_m then if l ~ '^\s*-- \(7c: fim\)' then v_m := false; end if; continue; end if;
    v_out := v_out || l;
  end loop;
  return array_to_string(v_out, E'\n');
end $f$;
-- FASE 7c: fim
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
create function pg_temp.lista(p_tabela text, p_check text) returns text language sql stable as $f$
  select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = p_tabela::regclass and c.conname = p_check
$f$;

-- ── T1. As colunas, os padrões, os CHECKs, as listas, as tabelas e os gatilhos (sem fixture) ───────────────────────────────────
do $t1$
declare
  v_res jsonb := '[]'::jsonb;
  c     public.agenda_config;
  v     text[];
  r     text;
begin
  select * into c from public.agenda_config where id;
  v_res := pg_temp.ok(v_res, 'T1a modo_tarefas: a linha nasce desligado e o padrão é sombra (o dado 20261102100600 põe sombra)',
    c.modo_tarefas = 'desligado'
    and (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'agenda_config'
          and column_name = 'modo_tarefas') like '%sombra%',
    c.modo_tarefas);
  v_res := pg_temp.ok(v_res, 'T1b os 12 parâmetros com o padrão da spec (5 linhas, 60 letras, as 5 fases, 1 h, 0,5, alerta 2, 1 d.u., 16:20, tudo, concluir e cobrar)',
    c.tarefas_linhas_max = 5 and c.tarefas_texto_max = 60 and jsonb_array_length(c.tarefas_fases) = 5
    and c.tarefas_fases -> 0 ->> 0 = 'testar' and c.tarefas_fases -> 4 ->> 0 = 'diagnosticar'
    and c.tarefas_horas_min = 1.00 and c.tarefas_pendente_meios = 0.50 and c.tarefas_pendente_alerta = 2
    and c.tarefas_sem_registro_du = 1 and c.tarefas_hora = time '16:20' and c.tarefas_resposta_vale_dia = 'tudo'
    and c.tarefas_concluir_sem_pendente and c.tarefas_cobrar_vespera,
    format('%s %s %s %s %s %s %s %s %s', c.tarefas_linhas_max, c.tarefas_texto_max, c.tarefas_horas_min, c.tarefas_pendente_meios,
           c.tarefas_pendente_alerta, c.tarefas_sem_registro_du, c.tarefas_hora, c.tarefas_resposta_vale_dia, c.tarefas_fases));
  v := array[
    pg_temp.erro_de('update public.agenda_config set modo_tarefas = ''meio'' where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_linhas_max = 6 where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_texto_max = 20 where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_fases = ''[["executar", 3, "x"]]'' where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_fases = ''[["testar", 5, "(test"]]'' where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_fases = ''[["testar", 4, "test"]]'' where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_fases = ''[]'' where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_horas_min = 0.1 where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_pendente_meios = 3 where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_pendente_alerta = 0 where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_pendente_alerta = 6 where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_sem_registro_du = 6 where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_hora = ''11:00'' where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_hora = ''17:30'' where id'),
    pg_temp.erro_de('update public.agenda_config set tarefas_resposta_vale_dia = ''as_vezes'' where id')];
  v_res := pg_temp.ok(v_res, 'T1c os CHECKs recusam (23514) o modo, as linhas (6), o texto (20), a fase executar, a regex que não compila, o número que não é o da fase, a lista vazia, as horas, o pendente, o alerta 0 e 6, o sem registro 6, a hora antes das 12:00 e depois do "como foi", o vale-dia desconhecido',
    (select bool_and(x like '23514 %') from unnest(v) x) and cardinality(v) = 15, array_to_string(v, ' | '));
  v_res := pg_temp.ok(v_res, 'T1d o alerta aceita 1 (o conflito 7 de fase7-padroes: a resposta do AG7-26 pode virar UPDATE)',
    pg_temp.erro_de('update public.agenda_config set tarefas_pendente_alerta = 1 where id') = 'sem erro', null);
  update public.agenda_config set tarefas_pendente_alerta = 2 where id;
  v_res := pg_temp.ok(v_res, 'T1e as 4 listas ganham o valor novo e mantêm os de antes (Fase 6, 7a, 7b e 7c P1)',
    pg_temp.lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check') ~ '''tarefa'''
    and pg_temp.lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check') ~ '''habilidade'''
    and pg_temp.lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check') ~ '''dias_semana'''
    and pg_temp.lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check') ~ '''situacao'''
    and pg_temp.lista('public.agenda_perguntas', 'agenda_perguntas_tipo_check') ~ '''aprendizado'''
    and pg_temp.lista('public.agenda_acoes', 'agenda_acoes_tipo_check') ~ '''tarefa'''
    and pg_temp.lista('public.agenda_acoes', 'agenda_acoes_tipo_check') ~ '''habilidade'''
    and pg_temp.lista('public.agenda_acoes', 'agenda_acoes_tipo_check') ~ '''gestor'''
    and pg_temp.lista('public.agenda_rascunho', 'agenda_rascunho_tipo_check') ~ '''etapa'''
    and pg_temp.lista('public.agenda_rascunho', 'agenda_rascunho_tipo_check') ~ '''habilidade'''
    and pg_temp.lista('public.agenda_rascunho', 'agenda_rascunho_tipo_check') ~ '''planejar'''
    and pg_temp.lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check') ~ '''tarefas'''
    and pg_temp.lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check') ~ '''habilidade'''
    and pg_temp.lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check') ~ '''equipe_semana''',
    pg_temp.lista('public.agenda_vigia_rodadas', 'agenda_vigia_rodadas_rotina_check'));
  begin
    r := pg_temp.erro_de($q$insert into public.agenda_perguntas (tipo, chave, texto, modo, criada_em)
                           values ('tarefa', 'tarefa:prazo:t1f', 'Teste da lista.', 'sombra', now())$q$);
    r := r || ' ' || (select coalesce(q.critica, false)::text from public.agenda_perguntas q where q.chave = 'tarefa:prazo:t1f');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T1f a pergunta tarefa entra na lista e não é crítica (a expressão de critica não muda)', r = 'sem erro false', r);
  -- a assinatura com outro tamanho é recusada (o CHECK os_planejamento_tarefas_assinatura_check), com uma OS de planejamento qualquer
  r := (select pg_temp.erro_de(format('update public.os_planejamento set tarefas_assinatura = ''curta'' where service_order_id = %L',
                                      p.service_order_id))
          from public.os_planejamento p order by p.service_order_id limit 1);
  v_res := pg_temp.ok(v_res, 'T1g as 2 colunas novas de os_planejamento, nulas; a assinatura só com 32 letras (o CHECK pelo nome recusa outra, 23514)',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'os_planejamento'
      and column_name in ('tarefas_assinatura', 'tarefas_sincronizadas_em') and is_nullable = 'YES') = 2
    and pg_temp.lista('public.os_planejamento', 'os_planejamento_tarefas_assinatura_check') like '%char_length(tarefas_assinatura) = 32%'
    and (r is null or r like '23514 %'),
    coalesce(r, 'sem OS de planejamento: só a definição'));
  v_res := pg_temp.ok(v_res, 'T1h as 2 tabelas com a RLS ligada e a leitura só de admin/financeiro (TO authenticated), sem policy de escrita; authenticated só select, service_role tudo, anon nada',
    (select bool_and(c2.relrowsecurity) from pg_class c2 where c2.oid in ('public.os_tarefas'::regclass, 'public.os_tarefas_dia'::regclass))
    and (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename in ('os_tarefas', 'os_tarefas_dia')) = 2
    and (select bool_and(p.cmd = 'SELECT' and p.roles = '{authenticated}' and p.qual like '%is_admin_or_financial%')
           from pg_policies p where p.schemaname = 'public' and p.tablename in ('os_tarefas', 'os_tarefas_dia'))
    and has_table_privilege('authenticated', 'public.os_tarefas', 'select') and not has_table_privilege('authenticated', 'public.os_tarefas', 'insert')
    and has_table_privilege('service_role', 'public.os_tarefas_dia', 'insert')
    and not has_table_privilege('anon', 'public.os_tarefas', 'select') and not has_table_privilege('anon', 'public.os_tarefas_dia', 'select'),
    (select string_agg(p.tablename || ':' || p.cmd || ':' || p.roles::text, ', ') from pg_policies p
      where p.schemaname = 'public' and p.tablename in ('os_tarefas', 'os_tarefas_dia')));
  perform pg_temp.gravar(v_res);
end
$t1$;


-- ── T2. As portas (sem fixture) ──────────────────────────────────────────────────────────────────────────────────────────────
with f(sig, quem, definer, vol) as (values
  ('public.os_tarefas_fonte(uuid, date)', 'leitura', true, 's'),
  ('public.os_tarefas_da_os(uuid, date)', 'leitura', true, 's'),
  ('public.agenda_tarefas_medidas(date, date, date)', 'leitura', true, 's'),
  ('public._agenda_tarefas_da_pessoa(uuid, date, date)', 'leitura', true, 's'),
  ('public._agenda_tarefa_texto(text, integer)', 'leitura', false, 'i'),
  ('public._agenda_tarefa_fase(text, jsonb)', 'leitura', false, 'i'),
  ('public._agenda_tarefa_datas(date, date)', 'leitura', false, 'i'),
  ('public._agenda_tarefas_lista_texto(jsonb, integer, integer, boolean, boolean)', 'leitura', false, 'i'),
  ('public._agenda_tarefas_fases_ok(jsonb)', 'leitura', false, 'i'),
  ('public.agenda_rascunho_etapa(uuid, text, text, text, text, text, text[], text, date)', 'leitura', true, 'v'),
  ('public.agenda_tarefas_rodar(date, timestamptz)', 'servico', true, 'v'),
  ('public._agenda_etapa_frase(jsonb)', 'servico', false, 'i'),
  ('public._agenda_tarefas_sincronizar(uuid, date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_tarefas_planejar(uuid, date, text)', 'ninguem', false, 's'),
  ('public._agenda_tarefas_texto_confere(text, jsonb)', 'ninguem', false, 'i'),
  ('public._agenda_tarefas_congelar(date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_tarefas_registrar(uuid[], text, text, text, uuid, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_tarefas_conferir(date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_ler_tarefas_da_resposta(text, jsonb)', 'ninguem', false, 'i'),
  ('public._agenda_tarefas_excecoes(date, timestamptz, uuid[])', 'ninguem', true, 'v'),
  ('public._agenda_tarefa_casar(uuid, text)', 'ninguem', false, 's'),
  ('public._agenda_aplicar_etapa(uuid, jsonb, text, date, timestamptz)', 'ninguem', true, 'v'),
  ('public._os_tarefas_so_muda()', 'ninguem', false, 'v'),
  ('public._os_tarefas_dia_so_muda()', 'ninguem', false, 'v'))
insert into _resultado
select 'T2a as 24 funções novas com as portas certas (as leituras com porta definer, do painel e do service_role; as puras de texto do painel e do service_role; a RPC do painel e do service_role; a rodada e a frase só do service_role; as peças de dentro e os gatilhos de ninguém; nunca anon; search_path fixo)',
       count(p.oid) = 24
       and bool_and(p.prosecdef = f.definer and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute')
                                              and has_function_privilege('service_role', p.oid, 'execute')
                          when 'servico' then not has_function_privilege('authenticated', p.oid, 'execute')
                                              and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute')
                               and not has_function_privilege('service_role', p.oid, 'execute') end),
       string_agg(format('%s def=%s vol=%s anon=%s auth=%s srv=%s', f.sig, p.prosecdef, p.provolatile,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
         filter (where p.oid is null or not (p.prosecdef = f.definer and p.provolatile = f.vol
                                             and not has_function_privilege('anon', p.oid, 'execute')))
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'T2b a régua do telefone da 7a (_agenda_equipe_tem_telefone) ganha authenticated e service_role (a linha (o) do fechamento é lida pelo painel; R5.2-1, R5.10-13) e continua sem anon',
       has_function_privilege('authenticated', 'public._agenda_equipe_tem_telefone(uuid)', 'execute')
       and has_function_privilege('service_role', 'public._agenda_equipe_tem_telefone(uuid)', 'execute')
       and not has_function_privilege('anon', 'public._agenda_equipe_tem_telefone(uuid)', 'execute')
       and pg_temp.como(null, 'anon', 'select public._agenda_equipe_tem_telefone(null::uuid)::text') like 'erro 42501%',
       pg_temp.como(null, 'anon', 'select public._agenda_equipe_tem_telefone(null::uuid)::text');
do $t2$
declare
  v_res jsonb := '[]'::jsonb;
  c_tec constant uuid := 'c7c80000-0000-4000-8000-0000000ec008';   -- um login que não é admin nem financeiro
  v     text[];
begin
  v := array[
    pg_temp.como(c_tec, 'authenticated', 'select public.os_tarefas_fonte(null::uuid, date ''2026-11-04'')::text'),
    pg_temp.como(c_tec, 'authenticated', 'select public.os_tarefas_da_os(null::uuid, date ''2026-11-04'')::text'),
    pg_temp.como(c_tec, 'authenticated', 'select public.agenda_tarefas_medidas(date ''2026-11-01'', date ''2026-11-04'', date ''2026-11-04'')::text'),
    pg_temp.como(c_tec, 'authenticated', 'select public._agenda_tarefas_da_pessoa(null::uuid, date ''2026-11-04'', date ''2026-11-04'')::text')];
  v_res := pg_temp.ok(v_res, 'T2c a técnica logada recebe 42501 nas 4 leituras com porta ("As etapas da OS são com o administrador ou o financeiro." / "As medidas das etapas …")',
    v[1] = 'erro 42501: As etapas da OS são com o administrador ou o financeiro.' and v[2] = v[1] and v[4] = v[1]
    and v[3] = 'erro 42501: As medidas das etapas são com o administrador ou o financeiro.', array_to_string(v, ' | '));
  v := array[
    pg_temp.como(null, 'anon', 'select public.os_tarefas_fonte(null::uuid, date ''2026-11-04'')::text'),
    pg_temp.como(null, 'anon', 'select public.os_tarefas_da_os(null::uuid, date ''2026-11-04'')::text'),
    pg_temp.como(null, 'anon', 'select public.agenda_rascunho_etapa(null::uuid, ''painel'', ''OS-97192'')::text'),
    pg_temp.como(null, 'anon', 'select public.agenda_tarefas_rodar(date ''2026-11-04'', now())::text'),
    pg_temp.como(null, 'authenticated', 'select public.agenda_tarefas_rodar(date ''2026-11-04'', now())::text'),
    pg_temp.como(null, 'authenticated', 'select public._agenda_tarefas_planejar(null::uuid, date ''2026-11-04'', ''ligado'')::text')];
  v_res := pg_temp.ok(v_res, 'T2d o anon não chama nada; a rodada e o planejar não são do painel (42501)',
    (select bool_and(x like 'erro 42501%') from unnest(v) x), array_to_string(v, ' | '));
  v := array[
    pg_temp.como(c_tec, 'authenticated', 'select public.agenda_rascunho_etapa(null::uuid, ''painel'', ''OS-97192'', ''cabos'', ''feita'', null, null, ''os cabos estão feitos'')::text')];
  v_res := pg_temp.ok(v_res, 'T2e a técnica logada não anota etapa (a RPC confere o administrador: _autor_da_agenda)', v[1] like 'erro 42501%', v[1]);
  perform pg_temp.gravar(v_res);
end
$t2$;

-- ── T4. O texto e a fase da etapa (a tabela da spec; sem fixture) ───────────────────────────────────────────────────────────────
insert into _resultado
select format('T4a %s → %s', x.nome, x.esperado), public._agenda_tarefa_texto(x.nome, 60) = x.esperado, public._agenda_tarefa_texto(x.nome, 60)
  from (values
    ('SUBSTITUIÇÃO BATERIAS - CHUMBO PARA LITIO', 'Substituição baterias - chumbo para litio'),
    ('SERVIÇO DE PASSAGEM E CRIMPAGEM DE CABOS DE BATERIA', 'Passagem e crimpagem de cabos de bateria'),
    ('Mão de obra - Substituição de conector e emenda no cabo de dados Starlink', 'Substituição de conector e emenda no cabo de dados Starlink'),
    ('Conversão do sistema de refrigeração para 12V — Refrigerador Consul CRC28FB', 'Conversão do sistema de refrigeração para 12V'),
    ('Substituição da tampa da boia (valor a definir — pendente análise de tempo e cotação da peça)', 'Substituição da tampa da boia'),
    ('Religação do Inversor (cabos já prontos - remoção/fixação)', 'Religação do Inversor'),
    ('Sistema de combustível diesel: alimentação, retorno, filtros, válvulas, mangueiras e suportação', 'Sistema de combustível diesel'),
    ('Instalação de escapamento úmido, waterlock/silencioso, mangueiras, respiro/anti-sifão e saída, se necessário',
     'Instalação de escapamento úmido, waterlock/silencioso…')
  ) x(nome, esperado);
insert into _resultado
select format('T4b %s → fase %s', x.nome, x.esperado),
       public._agenda_tarefa_fase(x.nome, (select c.tarefas_fases from public.agenda_config c where c.id)) = x.esperado,
       public._agenda_tarefa_fase(x.nome, (select c.tarefas_fases from public.agenda_config c where c.id))::text
  from (values
    ('Testes e comissionamento do sistema', 5),
    ('Pré-comissionamento, testes de partida, carga, vazamentos, ruído, vibração e checklist final', 5),
    ('COMISSIONAMENTO E VALIDAÇÃO DE GARANTIA E INSTALAÇÃO (AUTORIZADA)', 5),
    ('Organização, documentação, lista de materiais pendentes e entrega técnica', 6),
    ('Configuração e parametrização dos equipamentos', 4),
    ('Desmontagem do sistema elétrico atual', 2),
    ('Desmontagem do Gerador (cortesia)', 2),
    ('Diagnóstico de vazamento do sistema de água pressurizado', 1),
    ('Inspeção inicial, planejamento da instalação e conferência do local', 1),
    ('Religação do Inversor (cabos já prontos - remoção/fixação)', 3),
    ('Sistema elétrico AC: disjuntor, transferência, intertravamento, conexão ao quadro e testes', 3),
    ('Instalação do novo sistema elétrico LiFePO4/Usina', 3)
  ) x(nome, esperado);

-- ── T9. A leitura das etapas na resposta (o corpus; sem fixture) ────────────────────────────────────────────────────────────────
with lista(l) as (values ('[{"n": 1, "texto": "Passagem e crimpagem de cabos de bateria"},
                           {"n": 2, "texto": "Substituição baterias - chumbo para litio"},
                           {"n": 3, "texto": "Testar e conferir antes de entregar (Elétrico DC)"}]'::jsonb)),
     um(l) as (values ('[{"n": 1, "texto": "Passagem e crimpagem de cabos de bateria"}]'::jsonb))
insert into _resultado
select format('T9 "%s" → %s', x.frase, x.esperado),
       public._agenda_ler_tarefas_da_resposta(x.frase, case when x.um then (select l from um) else (select l from lista) end) @> x.esperado::jsonb,
       public._agenda_ler_tarefas_da_resposta(x.frase, case when x.um then (select l from um) else (select l from lista) end)::text
  from (values
    ('ok', false, '{"entendeu": true, "feitas": [1, 2, 3], "pendentes": [], "fonte": "ok"}'),
    ('beleza', false, '{"entendeu": true, "feitas": [1, 2, 3], "pendentes": []}'),
    ('OK', false, '{"entendeu": true, "feitas": [1, 2, 3], "pendentes": []}'),
    ('foi tudo como o previsto', false, '{"entendeu": true, "feitas": [1, 2, 3], "pendentes": []}'),
    ('tudo', false, '{"entendeu": true, "tudo": true, "feitas": [1, 2, 3], "fonte": "tudo"}'),
    ('fiz tudo', false, '{"entendeu": true, "tudo": true, "feitas": [1, 2, 3]}'),
    ('tudo feito', false, '{"entendeu": true, "tudo": true}'),
    ('tudo pronto', false, '{"entendeu": true, "tudo": true}'),
    ('todas', false, '{"entendeu": true, "tudo": true}'),
    ('fiz td', false, '{"entendeu": true, "tudo": true}'),
    ('ok, faltou a 2', false, '{"entendeu": true, "feitas": [1, 3], "pendentes": [2], "fonte": "numeros", "motivo": "estimativa"}'),
    ('ok faltou 2', false, '{"entendeu": true, "pendentes": [2]}'),
    ('Faltou a 2!', false, '{"entendeu": true, "pendentes": [2]}'),
    ('faltou 2 e 3', false, '{"entendeu": true, "feitas": [1], "pendentes": [2, 3]}'),
    ('não deu o 3', false, '{"entendeu": true, "pendentes": [3]}'),
    ('tudo certo menos o 3', false, '{"entendeu": true, "feitas": [1, 2], "pendentes": [3]}'),
    ('exceto o 1', false, '{"entendeu": true, "pendentes": [1]}'),
    ('pendente o 3', false, '{"entendeu": true, "pendentes": [3]}'),
    ('ficou pra amanhã o 3', false, '{"entendeu": true, "pendentes": [3]}'),
    ('fiz 1 e 3', false, '{"entendeu": true, "feitas": [1, 3], "pendentes": [2], "fonte": "numeros"}'),
    ('1 e 3 prontos', false, '{"entendeu": true, "feitas": [1, 3], "pendentes": [2]}'),
    ('Fiz 1, 2 e 3.', false, '{"entendeu": true, "feitas": [1, 2, 3], "pendentes": []}'),
    ('1 e 3', false, '{"entendeu": false, "motivo": "so_numeros"}'),
    ('faltou a 9', false, '{"entendeu": false, "motivo": "numero_fora"}'),
    ('não consegui terminar os cabos', false, '{"entendeu": true, "feitas": [2, 3], "pendentes": [1], "fonte": "palavras"}'),
    ('nao deu pra terminar os cabo', false, '{"entendeu": true, "pendentes": [1], "fonte": "palavras"}'),
    ('faltou a substituição', false, '{"entendeu": true, "pendentes": [2], "fonte": "palavras"}'),
    ('ainda não fiz a substituição', false, '{"entendeu": true, "pendentes": [2], "fonte": "palavras"}'),
    ('faltou o painel', false, '{"entendeu": false, "falou_de_falta": true}'),
    ('faltou', false, '{"entendeu": false, "falou_de_falta": true}'),
    ('ok, faltou', true, '{"entendeu": true, "pendentes": [1], "fonte": "um_so"}'),
    ('ok, faltou peça no 1', false, '{"entendeu": true, "pendentes": [1], "motivo": "material"}'),
    ('faltou o 2, o cliente não liberou', false, '{"entendeu": true, "pendentes": [2], "motivo": "cliente_ou_bem"}'),
    ('ok, só de manhã', false, '{"entendeu": false, "fonte": "nada", "falou_de_falta": false}')
  ) x(frase, um, esperado);


-- ── A fixture e os ajudantes ───────────────────────────────────────────────────────────────────────────────────────────────────
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7c_tarefas', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7a', true), '') <> ''
     and coalesce(current_setting('agenda_teste.replay2910', true), '') <> ''
$f$;
-- A fixture do P8 (por cima da 7c, da 7b, da 7a e do replay), uma vez; cada caso abaixo roda numa subtransação desfeita.
do $carga$
begin
  if not pg_temp.na_bancada() then
    return;
  end if;
  execute current_setting('agenda_teste.fase7c_tarefas');
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97191')
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.modo(p text) returns void language sql as $f$
  update public.agenda_config set modo_tarefas = p, modo_equipe = 'ligado', modo_proposta = 'ligado' where id
$f$;
create function pg_temp.tique(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_dia::text, true);
  return public.agenda_tarefas_rodar(p_dia, pg_temp.em(p_dia, p_hora));
end $f$;
-- As etapas gravadas da OS, na ordem: "texto:estado".
create function pg_temp.etapas(p_numero text) returns text language sql stable as $f$
  select string_agg(t.texto || ':' || t.estado, ' | ' order by t.ordem, t.id) from public.os_tarefas t
   where t.service_order_id = pg_temp.os(p_numero)
$f$;
-- O plano de uma OS (o planejar) em códigos: "04m[Mateus]:Inst ct,Pass c|04t[Alex]:Pass t,Subs c" (dia, m/t, a equipe; as 4 primeiras
-- letras da etapa, c = começa, t = termina).
create function pg_temp.plano(p jsonb) returns text language sql stable as $f$
  select string_agg(to_char((m ->> 'dia')::date, 'DD') || left(m ->> 'turno', 1)
                    || '[' || coalesce((select string_agg(public._agenda_nome_curto(py.name), ',' order by py.name)
                                          from jsonb_array_elements_text(m -> 'equipe') u join public.payees py on py.id = u::uuid), '') || ']:'
                    || coalesce((select string_agg(left(t.texto, 4)
                                                   || case when (i ->> 'comeca')::boolean or (i ->> 'termina')::boolean then ' ' else '' end
                                                   || case when (i ->> 'comeca')::boolean then 'c' else '' end
                                                   || case when (i ->> 'termina')::boolean then 't' else '' end, ',' order by (i ->> 'posicao')::int)
                                   from jsonb_array_elements(m -> 'itens') i join public.os_tarefas t on t.id = (i ->> 'tarefa')::uuid), ''),
                    '|' order by m ->> 'dia', m ->> 'turno' = 'tarde')
    from jsonb_array_elements(p -> 'meios') m
$f$;
-- A linha do tempo da semana (ligado): terça (o Flávio do Alex respondido "tudo"), quarta de manhã, o "como foi" de quarta, a resposta
-- do Alex e a ficha de quinta. p_ate: 'ter' (até ter 19:30), 'qua' (qua 07:10), 'qua_como_foi' (qua 17:00), 'qua_noite' (o "ok, faltou a
-- 1" do Alex às 17:40 e o tique das 19:30), 'qui_como_foi' (qui 07:10 e o "como foi" das 17:00).
create function pg_temp.semana(p_ate text) returns void language plpgsql as $f$
declare
  r jsonb;
begin
  perform pg_temp.modo('ligado');
  r := pg_temp.tique(date '2026-11-03', '07:10');
  r := public._agenda_rotina_como_foi(date '2026-11-03', pg_temp.em(date '2026-11-03', '17:00'));
  r := public.agenda_resposta_da_equipe('5547900000031', 'tudo', 'WA-ALEX-TER', pg_temp.em(date '2026-11-03', '17:40'));
  r := pg_temp.tique(date '2026-11-03', '19:30');
  if p_ate = 'ter' then return; end if;
  r := pg_temp.tique(date '2026-11-04', '07:10');
  if p_ate = 'qua' then return; end if;
  r := public._agenda_rotina_como_foi(date '2026-11-04', pg_temp.em(date '2026-11-04', '17:00'));
  if p_ate = 'qua_como_foi' then return; end if;
  r := public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou a 1', 'WA-ALEX-QUA', pg_temp.em(date '2026-11-04', '17:40'));
  r := pg_temp.tique(date '2026-11-04', '19:30');
  if p_ate = 'qua_noite' then return; end if;
  r := pg_temp.tique(date '2026-11-05', '07:10');
  r := public._agenda_rotina_como_foi(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:00'));
end $f$;
-- A 4ª linha do Flávio (o escopo que aumentou: qua 10:00).
create function pg_temp.compressor() returns void language sql as $f$
  insert into public.service_order_services (id, service_order_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot,
                                             line_total, service_verb, service_system, created_at)
  values (md5('c7c8:linha:191:4')::uuid, pg_temp.os('OS-97191'), 'Instalação do compressor e recarga de gás', 'unit', 1, 1800, 1800,
          'instalacao', 'refrigeracao', pg_temp.em(date '2026-11-04', '10:00'))
$f$;

-- ── T1i. Com a fixture: a assinatura de outro tamanho é recusada pelo CHECK (o T1g, sem fixture, só confere a definição) ───────────
do $t1i$
declare
  r text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T1i a assinatura recusada', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  r := pg_temp.erro_de(format('update public.os_planejamento set tarefas_assinatura = ''curta'' where service_order_id = %L', pg_temp.os('OS-97191')));
  insert into _resultado values ('T1i a assinatura com outro tamanho é recusada (os_planejamento_tarefas_assinatura_check, 23514)', r like '23514 %', r);
end
$t1i$;

-- ── T3. As etapas pela base (os_tarefas_fonte) ─────────────────────────────────────────────────────────────────────────────────
do $t3$
declare
  v_res jsonb := '[]'::jsonb;
  f     jsonb;
  v     jsonb := '{}'::jsonb;
  n     text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T3 as etapas pela base', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  foreach n in array array['OS-97191', 'OS-97192', 'OS-97193', 'OS-97194', 'OS-97195', 'OS-97196'] loop
    f := public.os_tarefas_fonte(pg_temp.os(n), date '2026-11-04');
    v := v || jsonb_build_object(n, jsonb_build_object(
      'roteiro', f -> 'roteiro',
      'textos', (select jsonb_agg(i ->> 'texto' order by o) from jsonb_array_elements(f -> 'itens') with ordinality t(i, o)),
      'fases', (select jsonb_agg((i ->> 'fase')::int order by o) from jsonb_array_elements(f -> 'itens') with ordinality t(i, o)),
      'horas', (select jsonb_agg((i ->> 'horas')::numeric order by o) from jsonb_array_elements(f -> 'itens') with ordinality t(i, o)),
      'exige', (select jsonb_agg((i ->> 'exige')::int order by o) from jsonb_array_elements(f -> 'itens') with ordinality t(i, o)),
      'origem', (select jsonb_agg(i ->> 'origem' order by o) from jsonb_array_elements(f -> 'itens') with ordinality t(i, o)),
      'passos', (select jsonb_agg(jsonb_array_length(i -> 'passos') order by o) from jsonb_array_elements(f -> 'itens') with ordinality t(i, o)),
      'fora', (select coalesce(jsonb_agg((x ->> 'motivo') || ':' || (x ->> 'nome') order by o), '[]'::jsonb)
                 from jsonb_array_elements(f -> 'fora') with ordinality t(x, o)),
      'assinatura', f -> 'assinatura'));
  end loop;
  v_res := pg_temp.ok(v_res, 'T3a Flávio (191, sem roteiro): o diagnóstico 1º (fase 1), a conversão e a tampa (R$ 0 pesa o piso: 1 h), a final pelos blocos de fechamento da Refrigeração e do Hidráulico (90 min: 1,5 h; acima de 60 letras, "Testar e conferir tudo antes de entregar")',
    v -> 'OS-97191' @> '{"roteiro": false, "textos": ["Diagnóstico de vazamento do sistema de água pressurizado", "Conversão do sistema de refrigeração para 12V", "Substituição da tampa da boia", "Testar e conferir tudo antes de entregar"], "fases": [1, 3, 3, 6], "horas": [2.72, 26.18, 1, 1.5], "exige": [0, 0, 0, 0], "origem": ["orcamento", "orcamento", "orcamento", "seguranca"], "fora": []}',
    (v -> 'OS-97191')::text);
  v_res := pg_temp.ok(v_res, 'T3b Lenine (192, com roteiro): cada bloco de linha é uma etapa, na ordem do roteiro, com os passos do bloco; o fechamento do Elétrico DC é a final (75 min); a abertura não é etapa; o lítio pede quem instala sozinho com 220 V (a linha e a final pelo último dia)',
    v -> 'OS-97192' @> '{"roteiro": true, "textos": ["Substituição baterias - chumbo para litio", "Instalação de porta fusíveis - distribuição de energia 12v", "Passagem e crimpagem de cabos de bateria", "Testar e conferir antes de entregar (Elétrico DC)"], "fases": [3, 3, 3, 6], "horas": [22.62, 8.38, 16.75, 1.25], "exige": [1, 0, 0, 1], "origem": ["roteiro", "roteiro", "roteiro", "roteiro"], "passos": [6, 6, 6, 5], "fora": []}',
    (v -> 'OS-97192')::text);
  v_res := pg_temp.ok(v_res, 'T3c Lenine sem roteiro (193) = Lenine com roteiro (192): as mesmas 4 etapas, byte a byte no texto, na fase, no peso e na máscara (só a origem e os passos mudam)',
    v #> '{OS-97193,textos}' = v #> '{OS-97192,textos}' and v #> '{OS-97193,fases}' = v #> '{OS-97192,fases}'
    and v #> '{OS-97193,horas}' = v #> '{OS-97192,horas}' and v #> '{OS-97193,exige}' = v #> '{OS-97192,exige}'
    and v #> '{OS-97193,origem}' = '["orcamento", "orcamento", "orcamento", "seguranca"]' and v #> '{OS-97193,passos}' = '[0, 0, 0, 0]',
    (v -> 'OS-97193')::text);
  v_res := pg_temp.ok(v_res, 'T3d Vanderlei (194): a ordem por fase (desmontagem → adequação → instalação → configuração → testes; o roteiro dizia adequação, desmontagem, testes, configuração, instalação), sem final (o roteiro não tem fechamento); a usina pede 220 V, configurar e testar pedem comissionar',
    v -> 'OS-97194' @> '{"roteiro": true, "textos": ["Desmontagem do sistema elétrico atual", "Adequação de instalação elétrica e quadros", "Instalação do novo sistema elétrico LiFePO4/Usina", "Configuração e parametrização dos equipamentos", "Testes e comissionamento do sistema"], "fases": [2, 3, 3, 4, 5], "exige": [0, 0, 1, 2, 2]}',
    (v -> 'OS-97194')::text);
  v_res := pg_temp.ok(v_res, 'T3e Giancarlo (195): "Voltímetro 12V" fica de fora (material); 9 etapas de linha e a final do Elétrico DC',
    jsonb_array_length(v #> '{OS-97195,textos}') = 10 and v #> '{OS-97195,fora}' = '["material:Voltímetro 12V"]'
    and v #>> '{OS-97195,textos,9}' = 'Testar e conferir antes de entregar (Elétrico DC)',
    (v -> 'OS-97195')::text);
  v_res := pg_temp.ok(v_res, 'T3f Rodrigo (196): o bloco do "Deslocamento técnico" e o do "Conector… Starlink" (material) ficam de fora com as linhas; 1 etapa e a final',
    v -> 'OS-97196' @> '{"textos": ["Substituição de conector e emenda no cabo de dados Starlink", "Testar e conferir antes de entregar (Elétrico DC)"], "fora": ["deslocamento:Deslocamento técnico", "material:Conector de cabo de dados Starlink"]}',
    (v -> 'OS-97196')::text);
  v_res := pg_temp.ok(v_res, 'T3g a OS que não existe: "Não encontrei esse serviço."; a assinatura é a mesma duas vezes (só leitura)',
    public.os_tarefas_fonte('c7c80000-0000-4000-8000-0000000000ff'::uuid, date '2026-11-04')::text = '{"ok": false, "texto": "Não encontrei esse serviço."}'
    and public.os_tarefas_fonte(pg_temp.os('OS-97192'), date '2026-11-04') ->> 'assinatura' = v #>> '{OS-97192,assinatura}',
    null);
  perform pg_temp.gravar(v_res);
end
$t3$;

-- ── T4c. As 45 linhas reais da carteira (o replay de 29/10) pelo texto e pela fase ─────────────────────────────────────────────────
do $t4c$
declare
  v text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T4c as linhas reais', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  select string_agg(so.service_order_number || ' | ' || public._agenda_tarefa_fase(s.name_snapshot, c.tarefas_fases) || ' | '
                    || public._agenda_tarefa_texto(s.name_snapshot, c.tarefas_texto_max), E'\n'
                    order by so.service_order_number, s.created_at, s.id)
    into v
    from public.service_order_services s join public.service_orders so on so.id = s.service_order_id, public.agenda_config c
   where c.id and so.service_order_number in ('ORÇ-00083', 'ORÇ-00095', 'OS-00032', 'OS-00033', 'OS-00069', 'OS-00074', 'OS-00076',
                                              'OS-00096', 'OS-00104', 'OS-00112', 'OS-00130');
  insert into _resultado values ('T4c as 45 linhas reais da carteira: o texto (sem caixa alta, sem o prefixo, sem o parêntese, cortado no travessão, nos dois pontos ou na última palavra com "…") e a fase, byte a byte',
    v = $e$ORÇ-00083 | 3 | Substituição de Claraboia de Teto
ORÇ-00095 | 3 | Kit 1 — Iluminação LED
ORÇ-00095 | 3 | Kit 2 — Elétrica Interna
ORÇ-00095 | 3 | Kit 3 — Sistema de Energia
ORÇ-00095 | 3 | Kit 4 — Água e Sanitário
ORÇ-00095 | 3 | Kit 5 — Conectividade Starlink
ORÇ-00095 | 3 | Kit 6 — Cabine e Revestimento
ORÇ-00095 | 2 | Desmontagem do Gerador
OS-00032 | 1 | Inspeção inicial, planejamento da instalação e conferência…
OS-00032 | 3 | Posicionamento, alinhamento, base, coxins e fixação do…
OS-00032 | 3 | Instalação hidráulica/mecânica de água salgada, mangueiras…
OS-00032 | 3 | Instalação de escapamento úmido, waterlock/silencioso…
OS-00032 | 3 | Sistema de combustível diesel
OS-00032 | 3 | Sistema elétrico DC
OS-00032 | 3 | Sistema elétrico AC
OS-00032 | 5 | Pré-comissionamento, testes de partida, carga, vazamentos…
OS-00032 | 6 | Organização, documentação, lista de materiais pendentes e…
OS-00033 | 3 | Instalação técnica de parelha de motores mercury v8 300hp…
OS-00033 | 5 | Comissionamento e validação de garantia e instalação
OS-00069 | 5 | Testes e comissionamento do sistema
OS-00069 | 4 | Configuração e parametrização dos equipamentos
OS-00069 | 2 | Desmontagem do sistema elétrico atual
OS-00069 | 3 | Adequação de instalação elétrica e quadros
OS-00069 | 3 | Instalação do novo sistema elétrico LiFePO4/Usina
OS-00074 | 3 | Substituição baterias - chumbo para litio
OS-00074 | 3 | Instalação de porta fusíveis - distribuição de energia 12v
OS-00074 | 3 | Passagem e crimpagem de cabos de bateria
OS-00076 | 3 | Deslocamento técnico
OS-00076 | 3 | Substituição de conector e emenda no cabo de dados Starlink
OS-00076 | 3 | Conector de cabo de dados Starlink
OS-00096 | 1 | Diagnóstico técnico no local
OS-00104 | 3 | Conversão do sistema de refrigeração para 12V
OS-00104 | 1 | Diagnóstico de vazamento do sistema de água pressurizado
OS-00104 | 3 | Substituição da tampa da boia
OS-00112 | 3 | Instalação e conversão do sistema de baterias de chumbo…
OS-00130 | 3 | Realocação do banco de baterias
OS-00130 | 3 | Realocação e ligação dos controladores solares
OS-00130 | 3 | Barramento e proteções do sistema de corrente contínua
OS-00130 | 3 | Religação do Inversor
OS-00130 | 3 | Religação do Carregador DC-DC 24-12V 60A
OS-00130 | 3 | Instalação de Voltímetro 12V
OS-00130 | 3 | Adequação do conversor automático 110/220V para uso com…
OS-00130 | 3 | Restauração de mola de toldo e reparo de braços de toldo
OS-00130 | 3 | Fabricação de sobre teto de tulha em compensado naval com…
OS-00130 | 3 | Voltímetro 12V$e$, v);
end
$t4c$;

-- ── T5. A sincronização ────────────────────────────────────────────────────────────────────────────────────────────────────────
do $t5$
declare
  v_res jsonb := '[]'::jsonb;
  s1 jsonb; s2 jsonb; s3 jsonb; s4 jsonb; s5 jsonb;
  t1 text; t2 text; t3 text; t4 text; t5 text; t6 text; t7 text; t8 text; t9 text; t10 text;
  v_ord numeric[];
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T5 a sincronização', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modo('ligado');
    perform set_config('agenda.hoje', '2026-11-04', true);
    s1 := public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '07:10'));
    t1 := pg_temp.etapas('OS-97191') || ' # ' || (select string_agg(t.ordem::text || ':' || t.nova_no_escopo, ',' order by t.ordem)
                                                    from public.os_tarefas t where t.service_order_id = pg_temp.os('OS-97191'));
    s2 := public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '07:25'));
    perform pg_temp.compressor();
    s3 := public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '10:07'));
    t2 := (select t.texto || ':' || t.ordem || ':' || t.nova_no_escopo || ':' || t.origem from public.os_tarefas t
            where t.service_order_id = pg_temp.os('OS-97191') and t.nova_no_escopo);
    t3 := (select string_agg(a.texto || ' [' || a.executada || ']', ' | ') from public.agenda_acoes a
            where a.tipo = 'tarefa' and a.service_order_id = pg_temp.os('OS-97191'));
    -- a máscara muda (o dono disse que o Flávio pede quem sobe no teto em todos os dias) sem refazer a ordem
    v_ord := array(select t.ordem from public.os_tarefas t where t.service_order_id = pg_temp.os('OS-97191') order by t.ordem);
    update public.os_planejamento set exigencias_ditas = '{"altura": "todos"}', exigencias_trecho = 'no Flávio é tudo no teto'
     where service_order_id = pg_temp.os('OS-97191');
    s4 := public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '10:22'));
    t4 := (select string_agg(t.exige::text, ',' order by t.ordem) from public.os_tarefas t where t.service_order_id = pg_temp.os('OS-97191'))
          || ' ' || (array(select t.ordem from public.os_tarefas t where t.service_order_id = pg_temp.os('OS-97191') order by t.ordem) = v_ord);
    -- a linha apagada sai; a feita fica feita
    update public.os_tarefas set estado = 'feita', feita_em = now(), feita_via = 'dono', mudou_em = now()
     where service_order_id = pg_temp.os('OS-97191') and texto like 'Diagnóstico%';
    delete from public.service_order_services where id in (md5('c7c8:linha:191:2')::uuid, md5('c7c8:linha:191:3')::uuid);
    s5 := public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '10:37'));
    t5 := pg_temp.etapas('OS-97191');
    -- os gatilhos: não se apaga; a chave não muda; feita não vai a saiu; o plano do dia não muda a fração
    t6 := pg_temp.erro_de(format('delete from public.os_tarefas where service_order_id = %L', pg_temp.os('OS-97191')));
    t7 := pg_temp.erro_de(format('update public.os_tarefas set chave = ''linha:x'' where service_order_id = %L and estado = ''viva''',
                                 pg_temp.os('OS-97191')));
    t8 := pg_temp.erro_de(format('update public.os_tarefas set estado = ''saiu'' where service_order_id = %L and estado = ''feita''',
                                 pg_temp.os('OS-97191')));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- em teste, a ação do escopo nasce em teste
  begin
    perform pg_temp.modo('sombra');
    perform set_config('agenda.hoje', '2026-11-04', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '07:10'));
    perform pg_temp.compressor();
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '10:07'));
    t9 := (select string_agg(a.texto || ' [' || a.executada || ']', ' | ') from public.agenda_acoes a
            where a.tipo = 'tarefa' and a.service_order_id = pg_temp.os('OS-97191'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- desligado: nada é gravado (nem pela rodada)
  begin
    perform pg_temp.modo('desligado');
    t10 := pg_temp.tique(date '2026-11-04', '07:10')::text
           || ' ' || (select count(*) from public.os_tarefas) || ' ' || (select count(*) from public.os_tarefas_dia);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T5a a 1ª sincronização: as 4 etapas vivas pela ordem do serviço (1 a 4), nenhuma "nova no escopo"; a 2ª, sem nada mudado, não faz nada',
    t1 = 'Diagnóstico de vazamento do sistema de água pressurizado:viva | Conversão do sistema de refrigeração para 12V:viva | Substituição da tampa da boia:viva | Testar e conferir tudo antes de entregar:viva # 1.000:false,2.000:false,3.000:false,4.000:false'
    and (s1 ->> 'mudou')::boolean and (s1 ->> 'primeira')::boolean and not (s2 ->> 'mudou')::boolean,
    t1 || ' · ' || s2::text);
  v_res := pg_temp.ok(v_res, 'T5b o escopo que aumentou (a 4ª linha, qua 10:00): a etapa nova entra no fim, antes do final (ordem 3,5), nova no escopo, e UMA ação ao dono no "o que mudou" (§16.6.5)',
    t2 = 'Instalação do compressor e recarga de gás:3.500:true:orcamento' and (s3 ->> 'novas')::int = 1
    and t3 = 'Flávio: entrou "Instalação do compressor e recarga de gás" (o orçamento aumentou). Ficou no fim, antes de testar e entregar. [true]',
    t2 || ' · ' || t3);
  v_res := pg_temp.ok(v_res, 'T5c a máscara muda (o que a OS pede, dito pelo dono: o teto em todos os dias) sem refazer a ordem',
    t4 = '4,4,4,4,4 true' and (s4 ->> 'atualizadas')::int = 5, t4 || ' · ' || s4::text);
  v_res := pg_temp.ok(v_res, 'T5d a linha apagada: a etapa viva dela sai; a feita fica feita; a final segue a base (sem a linha do Hidráulico, só a Refrigeração)',
    t5 = 'Diagnóstico de vazamento do sistema de água pressurizado:feita | Conversão do sistema de refrigeração para 12V:viva | Substituição da tampa da boia:saiu | Instalação do compressor e recarga de gás:viva | Testar e conferir antes de entregar (Refrigeração):viva'
    and (s5 ->> 'saiu')::int = 1, t5);
  v_res := pg_temp.ok(v_res, 'T5e os gatilhos: a etapa não se apaga, não troca de chave, e a feita só volta a viva (23514)',
    t6 like '% O registro da agenda não se apaga.' and t7 like '23514 %' and t8 like '23514 %', concat_ws(' | ', t6, t7, t8));
  v_res := pg_temp.ok(v_res, 'T5f em teste, a ação do escopo nasce em teste (executada = false, "Em teste: ")',
    t9 = 'Em teste: Flávio: entrou "Instalação do compressor e recarga de gás" (o orçamento aumentou). Ficou no fim, antes de testar e entregar. [false]',
    t9);
  v_res := pg_temp.ok(v_res, 'T5g desligado: a rodada não roda e nada é gravado', t10 = '{"modo": "desligado", "rodou": false} 0 0', t10);
  perform pg_temp.gravar(v_res);
end
$t5$;

-- ── T6. A distribuição (o planejar) ────────────────────────────────────────────────────────────────────────────────────────────
do $t6$
declare
  v_res jsonb := '[]'::jsonb;
  p jsonb; p2 jsonb; p3 jsonb; p4 jsonb; p5 jsonb;
  t1 text; t2 text; t3 text; t4 text; t5 text; t6 text; t7 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T6 a distribuição', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modo('ligado');
    perform set_config('agenda.hoje', '2026-11-03', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os(n), date '2026-11-03', pg_temp.em(date '2026-11-03', '07:10'))
       from unnest(array['OS-97191', 'OS-97192', 'OS-97193', 'OS-97194']) n;
    p := public._agenda_tarefas_planejar(pg_temp.os('OS-97192'), date '2026-11-03', 'ligado');
    t1 := pg_temp.plano(p) || ' # ' || (select string_agg(coalesce(public._agenda_nome_curto(py.name), 'você'), ',' order by m ->> 'dia', m ->> 'turno' = 'tarde')
                                          from jsonb_array_elements(p -> 'meios') m left join public.payees py on py.id = (m ->> 'responde')::uuid);
    t2 := (select sum((i ->> 'fracao')::numeric)::text from jsonb_array_elements(p -> 'meios') m, jsonb_array_elements(m -> 'itens') i)
          || ' ' || (p ->> 'total');
    p2 := public._agenda_tarefas_planejar(pg_temp.os('OS-97194'), date '2026-11-03', 'ligado');
    t3 := pg_temp.plano(p2);
    p3 := public._agenda_tarefas_planejar(pg_temp.os('OS-97191'), date '2026-11-03', 'ligado');
    t4 := pg_temp.plano(p3) || ' # ' || (p3 ->> 'sobra_no_prazo') || ' ' || (p3 ->> 'prazo');
    -- o escopo do Flávio: o que falta não cabe até o prazo (o pendente e o começado contam pelo congelado de terça)
    perform pg_temp.tique(date '2026-11-03', '07:10');
    perform public._agenda_tarefas_registrar(array(select d.id from public.os_tarefas_dia d
                                                     where d.service_order_id = pg_temp.os('OS-97191') and d.dia = '2026-11-03' and d.termina),
                                            'feita', 'equipe', 'tudo', null, pg_temp.em(date '2026-11-03', '17:40'));
    perform pg_temp.compressor();
    perform set_config('agenda.hoje', '2026-11-04', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '10:07'));
    p4 := public._agenda_tarefas_planejar(pg_temp.os('OS-97191'), date '2026-11-04', 'ligado');
    t5 := pg_temp.plano(p4) || ' # ' || (p4 ->> 'sobra_no_prazo') || ' ' || (p4 ->> 'falta') || ' '
          || (select sum((i ->> 'fracao')::numeric) from jsonb_array_elements(p4 -> 'meios') m, jsonb_array_elements(m -> 'itens') i)::text;
    -- com a fonte orçamento, o total é o de agenda_meios_da_os (a soma das etapas acompanha)
    update public.os_planejamento set estimativa_fonte = null, dias = null, estimativa_em = null where service_order_id = pg_temp.os('OS-97191');
    p5 := public._agenda_tarefas_planejar(pg_temp.os('OS-97191'), date '2026-11-04', 'ligado');
    t6 := (p5 ->> 'total') || ' ' || (public.agenda_meios_da_os(pg_temp.os('OS-97191'), date '2026-11-04') ->> 'total');
    -- só o Mateus nos dias da 193: a etapa de risco (o lítio e a final) sem quem faça; o resto vai com ele
    perform set_config('agenda.hoje', '2026-11-04', true);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select md5('t6:193:' || t.turno)::uuid, pg_temp.os('OS-97193'), pg_temp.pessoa('Mateus'), date '2026-11-10', t.turno, 'turno',
           'execucao', 'publicada', 'motor', pg_temp.em(date '2026-11-02', '16:30')
      from (values ('manha'), ('tarde')) t(turno);
    p := public._agenda_tarefas_planejar(pg_temp.os('OS-97193'), date '2026-11-04', 'ligado');
    t7 := pg_temp.plano(p) || ' # ' || (select string_agg(t.texto, ', ' order by t.ordem) from jsonb_array_elements_text(p -> 'sem_quem') u
                                          join public.os_tarefas t on t.id = u::uuid);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- FASE 7c: (correção da revisão, 20261102100580, achado 1) AG7-10c ("Sim, o responsável da OS"): quem responde pelas etapas é só o
  -- responsável da OS na equipe do meio-dia; a manhã do Mateus (ajudante, sem o Alex) fica com a conferência do dono (você), e o
  -- Mateus só recebe a lista. Antes, "quem responde é quem está no meio-dia" (o §16.3.6 itens 2 a 4 da spec) dava a vez ao ajudante.
  v_res := pg_temp.ok(v_res, 'T6a Lenine (192): a manhã do Mateus (ajudante) leva a porta-fusíveis e começa a passagem, nunca o lítio (220 V); a tarde do Alex termina a passagem (a começada vem antes) e começa o lítio; a quinta termina o lítio e a final; quem responde é o responsável da OS (o Alex) e, na manhã só do Mateus, você',
    t1 = '04m[Mateus]:Inst ct,Pass c|04t[Alex]:Pass t,Subs c|05m[Alex]:Subs t,Test ct|05t[Alex]: # você,Alex,Alex,Alex', t1);
  -- FASE 7c: fim
  v_res := pg_temp.ok(v_res, 'T6b as etapas somam a duração do plano (1,5 dia = 3 meios-dias; o arredondamento de cada fração em 3 casas)',
    abs(split_part(t2, ' ', 1)::numeric - split_part(t2, ' ', 2)::numeric) <= 0.01, t2);
  v_res := pg_temp.ok(v_res, 'T6c Vanderlei (194): configurar e testar (comissionar) só no meio-dia do fechamento do dono; a manhã de quarta fica com a instalação',
    t3 = '10m[Alex]:Desm ct,Adeq c|10t[Alex]:Adeq t,Inst c|11m[Alex]:Inst t|11t[Alex]:Conf c', t3);
  v_res := pg_temp.ok(v_res, 'T6d Flávio (191) antes do escopo: o diagnóstico 1º na terça; tudo cabe até sex 06/11 (a final no fechamento do dono)',
    t4 = '03m[Alex]:Diag ct,Conv c|03t[Alex]:Conv|06m[Alex]:Conv|06t[Alex]:Conv t,Subs ct,Test ct # 0.000 2026-11-06', t4);
  v_res := pg_temp.ok(v_res, 'T6e Flávio depois do escopo (qua): a conversão começada vem 1ª na sexta; o compressor não termina e a final não cabe — a sobra no prazo (~0,13) e o que falta (2,13 meios-dias)',
    t5 like '06m[Alex]:Conv t,Subs ct,Inst c|06t[Alex]:Inst # %'
    and split_part(split_part(t5, ' # ', 2), ' ', 1)::numeric between 0.1 and 0.15
    and split_part(split_part(t5, ' # ', 2), ' ', 2)::numeric between 2.1 and 2.15
    and split_part(split_part(t5, ' # ', 2), ' ', 3)::numeric = 2.000, t5);
  v_res := pg_temp.ok(v_res, 'T6f sem os dias do dono (a duração pelo orçamento), o total das etapas é o de agenda_meios_da_os', split_part(t6, ' ', 1) = split_part(t6, ' ', 2), t6);
  v_res := pg_temp.ok(v_res, 'T6g só o Mateus nos dias marcados (193, a duração pelo orçamento): o lítio e a final (220 V) ficam sem quem faça; a porta-fusíveis e a passagem vão com ele',
    t7 = '10m[Mateus]:Inst c|10t[Mateus]:Inst t,Pass c # Substituição baterias - chumbo para litio, Testar e conferir antes de entregar (Elétrico DC)', t7);
  perform pg_temp.gravar(v_res);
end
$t6$;

-- ── T7. O congelamento ─────────────────────────────────────────────────────────────────────────────────────────────────────────
do $t7$
declare
  v_res jsonb := '[]'::jsonb;
  c0 int; c1 int; c2 int; c3 jsonb; c4 jsonb; c5 jsonb; c6 jsonb;
  t1 text; t2 text; t3 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T7 o congelamento', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modo('ligado');
    perform pg_temp.tique(date '2026-11-03', '07:10');
    c0 := (select count(*) from public.os_tarefas_dia d where d.service_order_id = pg_temp.os('OS-97191') and d.dia = '2026-11-03');
    perform pg_temp.tique(date '2026-11-03', '19:29');
    c1 := (select count(*) from public.os_tarefas_dia d where d.service_order_id = pg_temp.os('OS-97192') and d.dia = '2026-11-04');
    c3 := pg_temp.tique(date '2026-11-03', '19:30');
    c2 := (select count(*) from public.os_tarefas_dia d where d.service_order_id = pg_temp.os('OS-97192') and d.dia = '2026-11-04');
    c4 := pg_temp.tique(date '2026-11-03', '19:45');
    -- o meio-dia de quarta à tarde perde a alocação (o replano): as linhas dele cancelam; a nova alocação congela no tique seguinte
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_em = pg_temp.em(date '2026-11-03', '19:50'), cancelada_motivo = 'replanejado'
     where id = md5('c7c8:aloc:192:alex:2026-11-04:tarde')::uuid;
    c5 := pg_temp.tique(date '2026-11-03', '20:07');
    t1 := (select string_agg(d.turno || ':' || d.estado, ',' order by d.turno, d.posicao) from public.os_tarefas_dia d
            where d.service_order_id = pg_temp.os('OS-97192') and d.dia = '2026-11-04');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (md5('t7:192:tarde')::uuid, pg_temp.os('OS-97192'), pg_temp.pessoa('Alex'), date '2026-11-04', 'tarde', 'turno', 'execucao',
            'publicada', 'motor', pg_temp.em(date '2026-11-03', '20:10'));
    c6 := pg_temp.tique(date '2026-11-03', '20:22');
    t2 := (select string_agg(d.turno || ':' || d.estado, ',' order by d.turno, d.estado, d.posicao) from public.os_tarefas_dia d
            where d.service_order_id = pg_temp.os('OS-97192') and d.dia = '2026-11-04');
    -- em teste, as linhas são de sombra e nunca se misturam com as ligadas
    perform pg_temp.modo('sombra');
    perform pg_temp.tique(date '2026-11-03', '20:37');
    t3 := (select string_agg(d.modo || ':' || count, ',' order by d.modo) from (select d.modo, count(*) from public.os_tarefas_dia d
            where d.service_order_id = pg_temp.os('OS-97192') and d.dia = '2026-11-04' and d.estado = 'planejada' group by d.modo) d);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T7a o de hoje congela no 1º tique do dia (o Flávio de terça: 3 linhas); o de amanhã não congela às 19:29 e congela às 19:30, antes da ficha (4 linhas do Lenine de quarta); uma vez só (o tique das 19:45 não congela nada)',
    c0 = 3 and c1 = 0 and c2 = 4 and (c4 #>> '{contagens,congelar,congelados}')::int = 0, format('%s %s %s %s', c0, c1, c2, c4 -> 'contagens' -> 'congelar'));
  v_res := pg_temp.ok(v_res, 'T7b o meio-dia que perdeu a alocação: as linhas dele viram canceladas no tique seguinte; a alocação nova congela no tique seguinte',
    t1 = 'manha:planejada,manha:planejada,tarde:cancelada,tarde:cancelada' and (c5 #>> '{contagens,congelar,cancelados}')::int = 2
    and t2 = 'manha:planejada,manha:planejada,tarde:cancelada,tarde:cancelada,tarde:planejada,tarde:planejada',
    t1 || ' · ' || t2);
  v_res := pg_temp.ok(v_res, 'T7c sombra e ligado nunca se misturam: em teste, o de quarta congela de novo, de sombra, ao lado do ligado',
    t3 = 'ligado:4,sombra:4', t3);
  perform pg_temp.gravar(v_res);
end
$t7$;


-- As de antes, rodadas como pg_temp (o corpo da origem): a ficha (20261026100300) e a resposta da equipe (20261101100800).
do $antes$
begin
  if coalesce(current_setting('agenda_teste.mig_equipe_fase3', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_correcao_fase7b', true), '') = '' then
    return;
  end if;
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_equipe_fase3'), 'agenda_equipe_ficha'),
                  'create or replace function public.agenda_equipe_ficha(', 'create function pg_temp.ficha_antes(');
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_correcao_fase7b'), 'agenda_resposta_da_equipe'),
                  'create or replace function public.agenda_resposta_da_equipe(', 'create function pg_temp.resposta_antes(');
end
$antes$;
-- As 6 saídas da ficha de cada pessoa (Alex, Mateus) em cada dia útil de ter 03 a qua 11/11 (p_hoje = o dia útil de antes), pela de agora
-- e pela de antes.
create function pg_temp.fichas(p_antes boolean) returns jsonb language plpgsql as $f$
declare
  v jsonb := '[]'::jsonb;
  p text;
  d date;
begin
  foreach p in array array['Alex', 'Mateus'] loop
    foreach d in array array[date '2026-11-04', date '2026-11-05', date '2026-11-06', date '2026-11-09', date '2026-11-10',
                             date '2026-11-11'] loop
      v := v || jsonb_build_array(case when p_antes then pg_temp.ficha_antes(pg_temp.pessoa(p), d, public.agenda_somar_du(d, -1))
                                       else public.agenda_equipe_ficha(pg_temp.pessoa(p), d, public.agenda_somar_du(d, -1)) end);
    end loop;
  end loop;
  return v;
end $f$;

-- ── T8. A ficha ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
do $t8$
declare
  v_res jsonb := '[]'::jsonb;
  f1 jsonb; f2 jsonb; f3 jsonb; f4 jsonb; f5 jsonb; f6 jsonb;
  a1 jsonb; a2 jsonb; a3 jsonb; a4 jsonb;
  t_lim text;
  t_fl text;
begin
  if not pg_temp.carregada() or to_regprocedure('pg_temp.ficha_antes(uuid, date, date)') is null then
    insert into _resultado values ('T8 a ficha', true, 'PULADO: sem a fixture do P8 e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- desligado e sombra = a de antes (com o plano congelado de sombra existindo)
  begin
    perform pg_temp.modo('desligado');
    f1 := pg_temp.fichas(false);
    f2 := pg_temp.fichas(true);
    perform pg_temp.modo('sombra');
    perform pg_temp.tique(date '2026-11-03', '07:10');
    perform pg_temp.tique(date '2026-11-03', '19:30');
    f3 := pg_temp.fichas(false);
    f4 := pg_temp.fichas(true);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T8a desligado: as 6 saídas da ficha (12 pessoa × dia) = as da de antes, byte a byte', f1 = f2 and jsonb_array_length(f1) = 12,
    md5(f1::text) || ' ' || md5(f2::text));
  v_res := pg_temp.ok(v_res, 'T8b em teste (com o plano congelado de sombra): = as da de antes, byte a byte (a equipe recebe os textos de antes)',
    f3 = f4 and f3 = f1, md5(f3::text) || ' ' || md5(f4::text));
  -- ligado: os textos da §16.6.1–16.6.3
  begin
    perform pg_temp.semana('ter');
    a1 := public.agenda_equipe_ficha(pg_temp.pessoa('Alex'), date '2026-11-04', date '2026-11-03');
    a2 := public.agenda_equipe_ficha(pg_temp.pessoa('Mateus'), date '2026-11-04', date '2026-11-03');
    perform set_config('agenda.hoje', '2026-11-04', true);
    a3 := public.agenda_equipe_ficha(pg_temp.pessoa('Alex'), date '2026-11-04', date '2026-11-04');
    perform pg_temp.tique(date '2026-11-04', '07:10');
    perform public._agenda_rotina_como_foi(date '2026-11-04', pg_temp.em(date '2026-11-04', '17:00'));
    perform public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou a 1', 'WA-T8', pg_temp.em(date '2026-11-04', '17:40'));
    perform pg_temp.tique(date '2026-11-04', '19:30');
    a4 := public.agenda_equipe_ficha(pg_temp.pessoa('Alex'), date '2026-11-05', date '2026-11-04');
    f5 := public.agenda_equipe_ficha(pg_temp.pessoa('Alex'), date '2026-11-05', date '2026-11-05');
    -- os tamanhos em todas (ligado): a ficha até 440; com o acesso do 7d e o previsto do 7f (160 letras), até 600; o "como foi" de hoje e
    -- a ficha de amanhã juntos até 590
    select string_agg(format('%s %s: %s/%s/%s', p, d, char_length(public.agenda_equipe_ficha(pg_temp.pessoa(p), d, public.agenda_somar_du(d, -1)) ->> 'texto_ficha'),
                             char_length(public.agenda_equipe_ficha(pg_temp.pessoa(p), d, public.agenda_somar_du(d, -1)) ->> 'texto_curto'),
                             char_length(public.agenda_equipe_ficha(pg_temp.pessoa(p), public.agenda_somar_du(d, -1), public.agenda_somar_du(d, -1)) ->> 'texto_como_foi')), ', ')
           filter (where char_length(public.agenda_equipe_ficha(pg_temp.pessoa(p), d, public.agenda_somar_du(d, -1)) ->> 'texto_ficha') > 440
                      or char_length(public.agenda_equipe_ficha(pg_temp.pessoa(p), d, public.agenda_somar_du(d, -1)) ->> 'texto_ficha') + 160 > 600
                      or coalesce(char_length(public.agenda_equipe_ficha(pg_temp.pessoa(p), public.agenda_somar_du(d, -1), public.agenda_somar_du(d, -1)) ->> 'texto_como_foi'), 0)
                         + 1 + coalesce(char_length(public.agenda_equipe_ficha(pg_temp.pessoa(p), d, public.agenda_somar_du(d, -1)) ->> 'texto_curto'), 0) > 590)
      into t_lim
      from unnest(array['Alex', 'Mateus']) p,
           unnest(array[date '2026-11-05', date '2026-11-06', date '2026-11-09', date '2026-11-10', date '2026-11-11']) d;
    f6 := public.agenda_equipe_ficha(pg_temp.pessoa('Alex'), date '2026-11-09', date '2026-11-06');
    -- o Flávio de sexta depois do escopo: o último dia e o que sobra
    perform pg_temp.compressor();
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '19:40'));
    t_fl := public.agenda_equipe_ficha(pg_temp.pessoa('Alex'), date '2026-11-06', date '2026-11-04') ->> 'texto_ficha';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T8c a ficha das 19:30 do Alex para quarta (§16.6.1): "O que fazer" no lugar do "Serviço"',
    a1 ->> 'texto_ficha' = 'Alex, amanhã (qua 04/11): 13h no barco do Lenine, na Marina Itajaí. O que fazer: 1) Terminar: Passagem e crimpagem de cabos de bateria; 2) Começar: Substituição baterias - chumbo para litio. Responde OK se tá certo.',
    a1 ->> 'texto_ficha');
  v_res := pg_temp.ok(v_res, 'T8d a ficha do Mateus (ajudante) para quarta de manhã (§16.6.1): sem a etapa de risco',
    a2 ->> 'texto_ficha' = 'Mateus, amanhã (qua 04/11): 8h no barco do Lenine, na Marina Itajaí. O que fazer: 1) Instalação de porta fusíveis - distribuição de energia 12v; 2) Começar: Passagem e crimpagem de cabos de bateria. Responde OK se tá certo.',
    a2 ->> 'texto_ficha');
  v_res := pg_temp.ok(v_res, 'T8e o "como foi" de quarta do Alex, com 1 item (§16.6.2)',
    a3 ->> 'texto_como_foi' = 'Como foi hoje? Ficou a tarde? Do de hoje: 1) Passagem e crimpagem de cabos de bateria. Se ficou pronto, responde OK. Se faltou, responde: ok, faltou.',
    a3 ->> 'texto_como_foi');
  v_res := pg_temp.ok(v_res, 'T8f a ficha de quinta (o último dia, com o dono fechando; a pendente de quarta volta 1ª): "É o último dia no barco do Lenine: tem que ficar tudo pronto." (§16.6.1)',
    a4 ->> 'texto_ficha' = 'Alex, amanhã (qui 05/11): 8h no barco do Lenine, na Marina Itajaí, com o Gustavo. O que fazer: 1) Passagem e crimpagem de cabos de bateria; 2) Terminar: Substituição baterias - chumbo para litio; 3) Testar e conferir antes de entregar (Elétrico DC) — com o Gustavo. É o último dia no barco do Lenine: tem que ficar tudo pronto. Responde OK se tá certo.',
    a4 ->> 'texto_ficha');
  v_res := pg_temp.ok(v_res, 'T8g o "o que tem pra amanhã" de quinta (§16.6.3)',
    a4 ->> 'texto_resposta' = 'Alex, amanhã (qui 05/11): 8h no barco do Lenine, na Marina Itajaí, com o Gustavo, o dia todo. O que fazer: 1) Passagem e crimpagem de cabos de bateria; 2) Terminar: Substituição baterias - chumbo para litio; 3) Testar e conferir antes de entregar (Elétrico DC) — com o Gustavo. Dúvida, fala com o Gustavo.',
    a4 ->> 'texto_resposta');
  v_res := pg_temp.ok(v_res, 'T8h a ficha que vai junto do "como foi" de quarta (texto_curto, 3 linhas, cabe em 590 com ele)',
    a4 ->> 'texto_curto' = 'Amanhã (qui 05/11): 8h no barco do Lenine, na Marina Itajaí, com o Gustavo. O que fazer: 1) Passagem e crimpagem de cabos de bateria; 2) Terminar: Substituição baterias - chumbo para litio; 3) Testar e conferir antes de entregar (Elétrico DC) — com o Gustavo.',
    a4 ->> 'texto_curto');
  v_res := pg_temp.ok(v_res, 'T8i o "como foi" de quinta, com 3 itens (§16.6.2: "ok e o número", o último n no exemplo); o texto_confirmar não muda',
    f5 ->> 'texto_como_foi' = 'Como foi hoje? Ficou manhã e tarde? Do de hoje: 1) Passagem e crimpagem de cabos de bateria; 2) Substituição baterias - chumbo para litio; 3) Testar e conferir antes de entregar (Elétrico DC). Se fez tudo, responde OK. Se faltou alguma, responde OK e o número (ex.: ok, faltou a 3).'
    and f5 ->> 'texto_confirmar' = 'Bom dia, Alex. Hoje é Lenine às 8h. Tá confirmado?',
    f5 ->> 'texto_como_foi');
  v_res := pg_temp.ok(v_res, 'T8j muitas etapas (Giancarlo, 10 num dia, que é o último): as 5 primeiras e "e mais 5", com a cobrança do último dia, dentro de 440 letras',
    f6 ->> 'texto_ficha' like '%O que fazer: 1) Realocação do banco de baterias; 2) Realocação e ligação dos controladores solares; 3) %; 5) %; e mais 5. É o último dia no barco do Giancarlo: tem que ficar tudo pronto. Responde OK se tá certo.'
    and char_length(f6 ->> 'texto_ficha') <= 440, f6 ->> 'texto_ficha');
  v_res := pg_temp.ok(v_res, 'T8k os tamanhos (ligado; Alex e Mateus de qui 05 a qua 11/11): toda ficha até 440 e, com 160 letras do 7d e do 7f, até 600; o "como foi" de hoje e a ficha de amanhã juntos até 590',
    t_lim is null, coalesce(t_lim, 'todas'));
  v_res := pg_temp.ok(v_res, 'T8l o último dia com o que sobra (o Flávio de sexta depois do escopo): "Ainda falta: …"',
    t_fl like '% É o último dia no barco do Flávio: tem que ficar tudo pronto. Ainda falta: % Responde OK se tá certo.', t_fl);
  perform pg_temp.gravar(v_res);
end
$t8$;

-- ── T10. A resposta ao "como foi" ──────────────────────────────────────────────────────────────────────────────────────────────
-- O que a resposta deixou: a volta, a leitura gravada, o resultado das alocações do dia e o das linhas do dia.
create function pg_temp.efeito(p_ret jsonb, p_dia date) returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'ret', p_ret,
    'leitura', (select m.leitura - 'tarefas' - 'lista' from public.agenda_equipe_mensagens m
                 where m.payee_id = pg_temp.pessoa('Alex') and m.tipo = 'como_foi' and m.dia = p_dia),
    'alocs', (select jsonb_agg(jsonb_build_object('t', a.turno, 'res', a.resultado, 'mot', a.motivo) order by a.turno)
                from public.agenda_alocacoes a
               where a.payee_id = pg_temp.pessoa('Alex') and a.dia = p_dia and a.estado in ('publicada', 'fixada')),
    'diaria', public._agenda_confirmacao_do_dia(pg_temp.pessoa('Alex'), p_dia) ->> 'estado')
$f$;
create function pg_temp.linhas(p_dia date) returns text language sql stable as $f$
  select string_agg(left(t.texto, 4) || ':' || coalesce(d.resultado, '-') || coalesce('/' || d.resultado_via, ''), ',' order by d.turno = 'tarde', d.posicao)
    from public.os_tarefas_dia d join public.os_tarefas t on t.id = d.tarefa_id
   where d.service_order_id = pg_temp.os('OS-97192') and d.dia = p_dia and d.estado = 'planejada' and d.termina
$f$;
do $t10$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  e1 jsonb; e2 jsonb; e3 jsonb; e4 jsonb;
  t_ok text; t_falta text; t_mot text; t_tudo text; t_nunca text; t_pal text; t_umas text; t_mat text; t_conf text; t_soma text;
begin
  if not pg_temp.carregada() or to_regprocedure('pg_temp.resposta_antes(text, text, text, timestamptz)') is null then
    insert into _resultado values ('T10 a resposta', true, 'PULADO: sem a fixture do P8 e as migrations como texto (rode pela bancada)');
    return;
  end if;
  -- desligado e em teste = a de antes (a mesma volta, a mesma leitura, o mesmo resultado e a mesma diária)
  begin
    perform pg_temp.semana('qua_como_foi');
    perform pg_temp.modo('sombra');
    e1 := pg_temp.efeito(public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou a 1', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40')),
                         date '2026-11-04') || jsonb_build_object('linhas', pg_temp.linhas(date '2026-11-04'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qua_como_foi');
    perform pg_temp.modo('sombra');
    e2 := pg_temp.efeito(pg_temp.resposta_antes('5547900000031', 'ok, faltou a 1', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40')),
                         date '2026-11-04') || jsonb_build_object('linhas', pg_temp.linhas(date '2026-11-04'));
    perform pg_temp.modo('desligado');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qua_como_foi');
    perform pg_temp.modo('desligado');
    e3 := pg_temp.efeito(public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou a 1', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40')),
                         date '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qua_como_foi');
    perform pg_temp.modo('desligado');
    e4 := pg_temp.efeito(pg_temp.resposta_antes('5547900000031', 'ok, faltou a 1', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40')),
                         date '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T10a em teste: a resposta ao "como foi" = a de antes (a volta, a leitura, o resultado das alocações, a diária) e nenhuma etapa registrada',
    e1 - 'linhas' = e2 - 'linhas' and e1 ->> 'linhas' = e2 ->> 'linhas' and e1 ->> 'linhas' !~ '/equipe', e1::text || ' · ' || e2::text);
  v_res := pg_temp.ok(v_res, 'T10b desligado: = a de antes', e3 = e4, e3::text || ' · ' || e4::text);
  -- ligado
  begin
    perform pg_temp.semana('qua_como_foi');
    r := public.agenda_resposta_da_equipe('5547900000031', 'ok', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40'));
    t_ok := pg_temp.linhas(date '2026-11-04') || ' ' || (pg_temp.efeito(r, date '2026-11-04') -> 'alocs')::text || ' '
            || (pg_temp.efeito(r, date '2026-11-04') ->> 'diaria');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qua_como_foi');
    r := public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou a 1', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40'));
    t_falta := pg_temp.linhas(date '2026-11-04') || ' ' || (pg_temp.efeito(r, date '2026-11-04') -> 'alocs')::text || ' '
               || (pg_temp.efeito(r, date '2026-11-04') ->> 'diaria') || ' '
               || (select (m.leitura -> 'tarefas' ->> 'pendentes') || (m.leitura -> 'lista' -> 0 ->> 'texto')
                     from public.agenda_equipe_mensagens m where m.payee_id = pg_temp.pessoa('Alex') and m.tipo = 'como_foi' and m.dia = '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qua_como_foi');
    r := public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou peça no 1', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40'));
    t_mot := (pg_temp.efeito(r, date '2026-11-04') -> 'alocs')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qua_como_foi');
    r := public.agenda_resposta_da_equipe('5547900000031', 'fiz tudo', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40'));
    t_tudo := pg_temp.linhas(date '2026-11-04') || ' ' || (pg_temp.efeito(r, date '2026-11-04') -> 'alocs')::text || ' '
              || (pg_temp.efeito(r, date '2026-11-04') ->> 'diaria') || ' ' || (r ->> 'entendeu');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qua_como_foi');
    update public.agenda_config set tarefas_resposta_vale_dia = 'nunca' where id;
    r := public.agenda_resposta_da_equipe('5547900000031', 'fiz tudo', 'WA-T10', pg_temp.em(date '2026-11-04', '17:40'));
    t_nunca := pg_temp.linhas(date '2026-11-04') || ' ' || coalesce((pg_temp.efeito(r, date '2026-11-04') -> 'alocs')::text, '') || ' '
               || (pg_temp.efeito(r, date '2026-11-04') ->> 'diaria') || ' ' || (r ->> 'entendeu');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qui_como_foi');
    r := public.agenda_resposta_da_equipe('5547900000031', 'não consegui terminar os cabos', 'WA-T10', pg_temp.em(date '2026-11-05', '17:40'));
    t_pal := pg_temp.linhas(date '2026-11-05') || ' ' || (pg_temp.efeito(r, date '2026-11-05') -> 'alocs')::text || ' '
             || (pg_temp.efeito(r, date '2026-11-05') ->> 'diaria') || ' ' || (r ->> 'entendeu');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qui_como_foi');
    r := public.agenda_resposta_da_equipe('5547900000031', 'faltou umas coisas', 'WA-T10', pg_temp.em(date '2026-11-05', '17:40'));
    t_umas := pg_temp.linhas(date '2026-11-05') || ' # '
              || (select string_agg(q.chave || ' | ' || q.texto, ' ; ') from public.agenda_perguntas q
                   where q.tipo = 'equipe_resposta' and q.chave like 'equipe_resposta:%:tarefas');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('qua_como_foi');
    r := public.agenda_resposta_da_equipe('5547900000011', 'ok', 'WA-T10M', pg_temp.em(date '2026-11-04', '17:45'));
    t_mat := pg_temp.linhas(date '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a lista mudou depois do "como foi" (o texto que ele recebeu não tem mais o "2) …" de agora): os números não valem
    perform pg_temp.semana('qui_como_foi');
    update public.os_tarefas set texto = 'Troca das baterias de chumbo por lítio', mudou_em = now()
     where service_order_id = pg_temp.os('OS-97192') and texto like 'Substituição%';
    r := public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou a 2', 'WA-T10', pg_temp.em(date '2026-11-05', '17:40'));
    t_conf := pg_temp.linhas(date '2026-11-05') || ' # '
              || coalesce((select string_agg(q.chave, ' ; ') from public.agenda_perguntas q
                            where q.tipo = 'equipe_resposta' and q.chave like 'equipe_resposta:%:tarefas'), 'sem pergunta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T10c "ok": a etapa que terminava hoje feita (via equipe); a tarde cumprida; a diária confirmada',
    t_ok = 'Inst:-,Pass:feita/equipe [{"t": "tarde", "mot": null, "res": "cumprido"}] confirmada', t_ok);
  v_res := pg_temp.ok(v_res, 'T10d "ok, faltou a 1": a passagem pendente (via equipe); a tarde parcial (estimativa) no lugar do cumprido; a diária confirmada (os turnos do plano); a leitura e a lista ficam na mensagem',
    t_falta = 'Inst:-,Pass:pendente/equipe [{"t": "tarde", "mot": "estimativa", "res": "parcial"}] confirmada [1]Passagem e crimpagem de cabos de bateria', t_falta);
  v_res := pg_temp.ok(v_res, 'T10e "ok, faltou peça no 1": o parcial com o motivo material', t_mot = '[{"t": "tarde", "mot": "material", "res": "parcial"}]', t_mot);
  v_res := pg_temp.ok(v_res, 'T10f "fiz tudo" (sem turno nem OK) com tarefas_resposta_vale_dia = tudo: vale como o OK — a etapa feita, a tarde cumprida, a diária confirmada',
    t_tudo = 'Inst:-,Pass:feita/equipe [{"t": "tarde", "mot": null, "res": "cumprido"}] confirmada true', t_tudo);
  v_res := pg_temp.ok(v_res, 'T10g com nunca: a etapa feita, mas a diária pela gramática de antes (não entendi: o turno sem resultado, a diária divergente)',
    t_nunca = 'Inst:-,Pass:feita/equipe [{"t": "tarde", "mot": null, "res": null}] divergente false', t_nunca);
  v_res := pg_temp.ok(v_res, 'T10h "não consegui terminar os cabos" sem OK: a passagem pendente pela palavra, as outras feitas; a diária pela regra de antes (sem resultado no turno)',
    t_pal = 'Pass:pendente/equipe,Subs:feita/equipe,Test:feita/equipe [{"t": "manha", "mot": null, "res": null}, {"t": "tarde", "mot": null, "res": null}] divergente false', t_pal);
  v_res := pg_temp.ok(v_res, 'T10i "faltou umas coisas" (falou de falta sem dizer qual): a pergunta equipe_resposta ao dono (§16.6.4) e nada muda nas etapas',
    t_umas like 'Pass:-,Subs:-,Test:- # equipe_resposta:%:2026-11-05:tarefas | O Alex respondeu "faltou umas coisas" ao "como foi" do Lenine (qui 05/11), e não entendi o que faltou. Me diga qual (ex.: "no Lenine falta passagem e crimpagem de cabos de bateria").',
    t_umas);
  -- FASE 7c: (correção da revisão, 20261102100580, achado 1) AG7-10c: o ajudante só recebe a lista — o "ok" do Mateus não anota etapa
  -- (nem a dele, nem a do Alex); a manhã dele fica com a conferência do dono. Antes, o ok dele anotava a porta-fusíveis como feita.
  v_res := pg_temp.ok(v_res, 'T10j o "ok" do Mateus (ajudante) não anota etapa nenhuma: quem confere a manhã dele é você (AG7-10c)', t_mat = 'Inst:-,Pass:-', t_mat);
  -- FASE 7c: fim
  v_res := pg_temp.ok(v_res, 'T10k o "como foi" que não tem mais a lista de agora: o número não vale (só as palavras); "ok, faltou a 2" vira a pergunta ao dono, nada pendente',
    t_conf like 'Pass:-,Troc:-,Test:- # equipe_resposta:%:2026-11-05:tarefas', t_conf);
  perform pg_temp.gravar(v_res);
end
$t10$;

-- ── T11. A conferência ─────────────────────────────────────────────────────────────────────────────────────────────────────────
do $t11$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  t1 text; t2 text; t3 text; t4 text; t5 text; t6 text; t7 text; t8 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T11 a conferência', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.semana('qua');
    r := public.agenda_registrar_dia(pg_temp.adm(), date '2026-11-04', 'cumprido', null, pg_temp.os('OS-97192'), null, 'dia_feito',
                                     'dia feito', date '2026-11-04', pg_temp.em(date '2026-11-04', '18:00'));
    perform pg_temp.tique(date '2026-11-04', '18:07');
    t1 := pg_temp.linhas(date '2026-11-04') || ' ' || pg_temp.etapas('OS-97192');
    -- a conferência mudou (o dia virou parcial): as linhas via conferência são refeitas
    r := public.agenda_registrar_dia(pg_temp.adm(), date '2026-11-04', 'parcial', 'estimativa', pg_temp.os('OS-97192'), null, 'dia_feito',
                                     'dia parcial', date '2026-11-04', pg_temp.em(date '2026-11-04', '18:10'));
    r := pg_temp.tique(date '2026-11-04', '18:22');
    t2 := pg_temp.linhas(date '2026-11-04') || ' ' || pg_temp.etapas('OS-97192') || ' ' || (r #>> '{contagens,conferir,refeitas}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- sem a palavra de ninguém: depois de 1 dia útil, sem registro — conta como feita para o plano (R5.2-3)
    perform pg_temp.semana('qua');
    r := pg_temp.tique(date '2026-11-05', '07:10');
    t3 := pg_temp.linhas(date '2026-11-04') || ' ' || pg_temp.etapas('OS-97192') || ' # '
          || pg_temp.plano(public._agenda_tarefas_planejar(pg_temp.os('OS-97192'), date '2026-11-05', 'ligado')) || ' # '
          || (public._agenda_tarefas_planejar(pg_temp.os('OS-97192'), date '2026-11-05', 'ligado') ->> 'sobra_no_prazo') || ' # '
          || coalesce((select string_agg(q.chave, ',') from public.agenda_perguntas q where q.chave = 'tarefa:prazo:' || pg_temp.os('OS-97192')), 'sem tarefa:prazo');
    t4 := public.os_tarefas_da_os(pg_temp.os('OS-97192'), date '2026-11-05') ->> 'texto';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a palavra da equipe vale sobre a conferência; a do dono sobre as duas
    perform pg_temp.semana('qua_noite');
    r := public.agenda_registrar_dia(pg_temp.adm(), date '2026-11-04', 'cumprido', null, pg_temp.os('OS-97192'), null, 'dia_feito',
                                     'dia feito', date '2026-11-04', pg_temp.em(date '2026-11-04', '20:00'));
    perform pg_temp.tique(date '2026-11-04', '20:07');
    t5 := pg_temp.linhas(date '2026-11-04');
    perform public._agenda_tarefas_registrar(array(select d.id from public.os_tarefas_dia d join public.os_tarefas t on t.id = d.tarefa_id
                                                     where d.dia = '2026-11-04' and d.termina and t.texto like 'Passagem%'),
                                            'feita', 'dono', 'no Lenine os cabos já estão passados', null, pg_temp.em(date '2026-11-04', '20:10'));
    t6 := pg_temp.linhas(date '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- com roteiro: todos os passos do bloco feitos fazem a etapa (via roteiro) e as linhas dela sem resultado
    perform pg_temp.semana('qua');
    update public.service_order_steps set status = 'done', completed_at = now()
     where service_order_id = pg_temp.os('OS-97192') and block_key = 'linha:' || md5('c7c8:linha:192:2')::uuid::text;
    r := pg_temp.tique(date '2026-11-04', '12:07');
    t7 := pg_temp.linhas(date '2026-11-04') || ' ' || pg_temp.etapas('OS-97192') || ' ' || (r #>> '{contagens,conferir,pelo_roteiro}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T11a *dia feito* (o dono, quarta): as etapas que terminavam no dia feitas via conferência',
    t1 like 'Inst:feita/conferencia,Pass:feita/conferencia %' and t1 like '%Instalação de porta fusíveis - distribuição de energia 12v:feita%'
    and t1 like '%Passagem e crimpagem de cabos de bateria:feita%', t1);
  v_res := pg_temp.ok(v_res, 'T11b o dia mudou para parcial: as linhas via conferência são refeitas (pendentes) e as etapas voltam a viva',
    t2 like 'Inst:pendente/conferencia,Pass:pendente/conferencia %' and t2 like '%Passagem e crimpagem de cabos de bateria:viva%' and t2 like '% 2', t2);
  v_res := pg_temp.ok(v_res, 'T11c sem a palavra de ninguém, depois de 1 dia útil: sem registro (sem pendente: a etapa não volta à fila, a quinta segue o plano, nada de "não cabe" por ela)',
    t3 like 'Inst:sem_registro/conferencia,Pass:sem_registro/conferencia %'
    and t3 like '%# 05m[Alex]:Subs t,Test ct|05t[Alex]: # 0.000 # sem tarefa:prazo', t3);
  v_res := pg_temp.ok(v_res, 'T11d a sem registro aparece como "sem confirmação" na linha da OS', t4 like '%(sem confirmação)%', t4);
  v_res := pg_temp.ok(v_res, 'T11e a palavra da equipe ("ok, faltou a 1") fica por cima do *dia feito*; a do dono por cima das duas',
    t5 = 'Inst:feita/conferencia,Pass:pendente/equipe' and t6 = 'Inst:feita/conferencia,Pass:feita/dono', t5 || ' · ' || t6);
  v_res := pg_temp.ok(v_res, 'T11f com roteiro: os passos todos feitos fazem a etapa (via roteiro) e a linha dela',
    t7 like 'Inst:feita/roteiro,Pass:- %' and t7 like '%Instalação de porta fusíveis - distribuição de energia 12v:feita%' and t7 like '% 1', t7);
  perform pg_temp.gravar(v_res);
end
$t11$;


-- ── T12. As exceções ao dono ───────────────────────────────────────────────────────────────────────────────────────────────────
create function pg_temp.mateus_193() returns void language plpgsql as $f$
begin
  perform set_config('agenda.hoje', '2026-11-04', true);
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  select md5('t12:193:' || t.turno)::uuid, pg_temp.os('OS-97193'), pg_temp.pessoa('Mateus'), date '2026-11-10', t.turno, 'turno',
         'execucao', 'publicada', 'motor', pg_temp.em(date '2026-11-02', '16:30')
    from (values ('manha'), ('tarde')) t(turno);
end $f$;
do $t12$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  t1 text; t2 text; t3 text; t4 text; t5 text; t6 text; t7 text; t8 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T12 as exceções', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    -- (a) a passagem pendente qua e qui: UMA ação; o próximo dia dela (o Mateus na sexta de manhã)
    perform pg_temp.semana('qui_como_foi');
    perform set_config('agenda.hoje', '2026-11-05', true);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (md5('t12:192:sex')::uuid, pg_temp.os('OS-97192'), pg_temp.pessoa('Mateus'), date '2026-11-06', 'manha', 'turno', 'execucao',
            'publicada', 'motor', pg_temp.em(date '2026-11-05', '12:00'));
    r := public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou a 1', 'WA-T12', pg_temp.em(date '2026-11-05', '17:40'));
    r := pg_temp.tique(date '2026-11-05', '17:52');
    t1 := (select string_agg(a.texto || ' [' || a.executada || ' ' || (a.antes ->> 'vezes') || ']', ' | ') from public.agenda_acoes a
            where a.tipo = 'tarefa' and a.antes ? 'vezes');
    r := public._agenda_tarefas_excecoes(date '2026-11-05', pg_temp.em(date '2026-11-05', '18:00'), null);
    t2 := (select count(*) from public.agenda_acoes a where a.tipo = 'tarefa' and a.antes ? 'vezes')::text;
    -- uma sequência nova (feita e pendente de novo em 2 dias) = uma ação nova
    update public.os_tarefas set pendente_vezes = 2, pendente_desde = '2026-11-09', pendente_ultimo = '2026-11-10', mudou_em = now()
     where service_order_id = pg_temp.os('OS-97192') and texto like 'Passagem%';
    r := public._agenda_tarefas_excecoes(date '2026-11-10', pg_temp.em(date '2026-11-10', '18:00'), array[pg_temp.os('OS-97192')]);
    t3 := (select count(*) from public.agenda_acoes a where a.tipo = 'tarefa' and a.antes ? 'vezes')::text;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- (b) o Flávio depois do escopo: o que falta não cabe até sex 06/11; com mais um meio-dia (o Mateus na quinta à tarde), coube
    perform pg_temp.semana('qua');
    perform pg_temp.compressor();
    perform pg_temp.tique(date '2026-11-04', '10:07');
    t4 := (select q.modo || ' | ' || q.perda_em || ' | ' || q.texto from public.agenda_perguntas q
            where q.chave = 'tarefa:prazo:' || pg_temp.os('OS-97191') and q.estado = 'aberta');
    perform set_config('agenda.hoje', '2026-11-04', true);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (md5('t12:191:qui')::uuid, pg_temp.os('OS-97191'), pg_temp.pessoa('Mateus'), date '2026-11-05', 'tarde', 'turno', 'execucao',
            'publicada', 'motor', pg_temp.em(date '2026-11-04', '11:00'));
    r := public._agenda_tarefas_excecoes(date '2026-11-04', pg_temp.em(date '2026-11-04', '11:07'), array[pg_temp.os('OS-97191')]);
    t5 := (select q.estado || ' | ' || q.resolvida_motivo from public.agenda_perguntas q where q.chave = 'tarefa:prazo:' || pg_temp.os('OS-97191'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- (b') só o Mateus nos dias da 193: a etapa de risco sem quem faça; com o Alex num dia, agora tem quem faça
    perform pg_temp.modo('ligado');
    perform set_config('agenda.hoje', '2026-11-04', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97193'), date '2026-11-04', pg_temp.em(date '2026-11-04', '07:10'));
    perform pg_temp.mateus_193();
    r := public._agenda_tarefas_excecoes(date '2026-11-04', pg_temp.em(date '2026-11-04', '07:20'), array[pg_temp.os('OS-97193')]);
    t6 := (select q.modo || ' | ' || q.texto from public.agenda_perguntas q where q.chave = 'tarefa:quem:' || pg_temp.os('OS-97193'));
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    select md5('t12:193:alex:' || t.turno)::uuid, pg_temp.os('OS-97193'), pg_temp.pessoa('Alex'), date '2026-11-13', t.turno, 'turno',
           'execucao', 'publicada', 'motor', pg_temp.em(date '2026-11-04', '08:00')
      from (values ('manha'), ('tarde')) t(turno);
    r := public._agenda_tarefas_excecoes(date '2026-11-04', pg_temp.em(date '2026-11-04', '08:07'), array[pg_temp.os('OS-97193')]);
    t7 := (select q.estado || ' | ' || q.resolvida_motivo from public.agenda_perguntas q where q.chave = 'tarefa:quem:' || pg_temp.os('OS-97193'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- em teste: a pergunta nasce em teste, com "Em teste: "
    perform pg_temp.modo('sombra');
    perform set_config('agenda.hoje', '2026-11-04', true);
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97193'), date '2026-11-04', pg_temp.em(date '2026-11-04', '07:10'));
    perform pg_temp.mateus_193();
    r := public._agenda_tarefas_excecoes(date '2026-11-04', pg_temp.em(date '2026-11-04', '07:20'), array[pg_temp.os('OS-97193')]);
    t8 := (select q.modo || ' | ' || left(q.texto, 22) from public.agenda_perguntas q where q.chave = 'tarefa:quem:' || pg_temp.os('OS-97193'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T12a a etapa pendente 2 dias (qua e qui): UMA ação ao dono no "o que mudou", com o próximo dia dela no começo do dia (§16.6.5 (a))',
    t1 = 'Lenine: "Passagem e crimpagem de cabos de bateria" ficou faltando qua 04 e qui 05/11 (Alex). Passei para sex 06/11, no começo do dia. Se já está feita, me diga (ex.: "no Lenine, passagem e crimpagem de cabos de bateria já está feita"). [true 2]',
    t1);
  v_res := pg_temp.ok(v_res, 'T12b a mesma sequência não repete a ação; uma sequência nova (feita e pendente de novo) ganha uma nova', t2 = '1' and t3 = '2', t2 || ' ' || t3);
  v_res := pg_temp.ok(v_res, 'T12c o que falta não cabe até o prazo (o Flávio depois do escopo): a pergunta tarefa:prazo, ligada, perda_em = o prazo, sem opções (§16.6.5 (b))',
    t4 = 'ligado | 2026-11-06 | Flávio: o que falta não cabe até o prazo, sex 06/11 — Conversão do sistema de refrigeração para 12V, Substituição da tampa da boia, Instalação do compressor e recarga de gás e Testar e conferir tudo antes de entregar (cerca de 1,5 dia), e o plano tem 1 dia até lá. Me diga como fica: chamar alguém junto, usar o sábado ou passar do prazo.',
    t4);
  v_res := pg_temp.ok(v_res, 'T12d com mais um meio-dia até o prazo, ela se resolve sozinha ("coube")', t5 = 'resolvida | coube', t5);
  v_res := pg_temp.ok(v_res, 'T12e a etapa de risco sem quem faça (só o Mateus nos dias marcados): a pergunta tarefa:quem (§16.6.5 (b'')); com o Alex num dia, "agora tem quem faça"',
    t6 = 'ligado | Lenine: "Substituição baterias - chumbo para litio" pede quem instala sozinho com 220 V ou banco de bateria, e nos dias marcados só vai o Mateus. Quem vai junto?'
    and t7 = 'resolvida | agora tem quem faça', t6 || ' · ' || t7);
  v_res := pg_temp.ok(v_res, 'T12f em teste, a pergunta nasce em teste, com "Em teste: "', t8 = 'sombra | Em teste: Lenine: "Sub', t8);
  perform pg_temp.gravar(v_res);
end
$t12$;

-- ── T13. A conclusão pela palavra do técnico ───────────────────────────────────────────────────────────────────────────────────
do $t13$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  t1 text; t2 text; t3 text; t4 text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T13 a conclusão', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    -- a passagem ficou pendente na quarta (dita pelo Alex) e o Alex diz "terminei" na quinta, o último dia: não conclui, pergunta
    perform pg_temp.semana('qui_como_foi');
    r := public.agenda_resposta_da_equipe('5547900000031', 'terminei', 'WA-T13', pg_temp.em(date '2026-11-05', '17:40'));
    r := public._agenda_rotina_conclusao(date '2026-11-05', pg_temp.em(date '2026-11-05', '18:00'));
    t1 := (select so.status || ' ' || (so.check_out_at is null) from public.service_orders so where so.id = pg_temp.os('OS-97192'))
          || ' | ' || coalesce((select q.texto from public.agenda_perguntas q where q.tipo = 'concluir' and q.service_order_id = pg_temp.os('OS-97192')), 'sem pergunta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o dono disse que a passagem já está feita: sem pendente dita, conclui como antes
    perform pg_temp.semana('qui_como_foi');
    perform public._agenda_tarefas_registrar(array(select d.id from public.os_tarefas_dia d join public.os_tarefas t on t.id = d.tarefa_id
                                                     where d.service_order_id = pg_temp.os('OS-97192') and d.termina and t.texto like 'Passagem%'),
                                            'feita', 'dono', 'no Lenine os cabos já estão passados', null, pg_temp.em(date '2026-11-05', '12:00'));
    r := public.agenda_resposta_da_equipe('5547900000031', 'terminei', 'WA-T13', pg_temp.em(date '2026-11-05', '17:40'));
    r := public._agenda_rotina_conclusao(date '2026-11-05', pg_temp.em(date '2026-11-05', '18:00'));
    t2 := (select so.status || ' ' || (so.check_out_at is not null) from public.service_orders so where so.id = pg_temp.os('OS-97192'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- tarefas_concluir_sem_pendente = false: conclui como antes, mesmo com a pendente dita
    perform pg_temp.semana('qui_como_foi');
    update public.agenda_config set tarefas_concluir_sem_pendente = false where id;
    r := public.agenda_resposta_da_equipe('5547900000031', 'terminei', 'WA-T13', pg_temp.em(date '2026-11-05', '17:40'));
    r := public._agenda_rotina_conclusao(date '2026-11-05', pg_temp.em(date '2026-11-05', '18:00'));
    t3 := (select so.status || ' ' || (so.check_out_at is not null) from public.service_orders so where so.id = pg_temp.os('OS-97192'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- só sem registro (ninguém disse que falta): conclui, e a medida conta a conclusão sem confirmação (R5.2-3)
    perform pg_temp.semana('qua');
    perform pg_temp.tique(date '2026-11-05', '07:10');
    perform public._agenda_rotina_como_foi(date '2026-11-05', pg_temp.em(date '2026-11-05', '17:00'));
    r := public.agenda_resposta_da_equipe('5547900000031', 'terminei', 'WA-T13', pg_temp.em(date '2026-11-05', '17:40'));
    r := public._agenda_rotina_conclusao(date '2026-11-05', pg_temp.em(date '2026-11-05', '18:00'));
    r := public.agenda_tarefas_medidas(date '2026-11-01', date '2026-11-06', date '2026-11-05');
    t4 := (select so.status || ' ' || (so.check_out_at is not null) from public.service_orders so where so.id = pg_temp.os('OS-97192'))
          || ' ' || (r ->> 'concluidas_sem_confirmacao') || ' ' || (r ->> 'concluidas_com_pendencia');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T13a "terminei" no último dia com a etapa pendente dita: a OS não conclui; a pergunta concluir lista só a pendente dita (§16.6.6)',
    t1 = 'in_progress true | O Alex disse que terminou o Lenine, mas não concluí: ainda falta "Passagem e crimpagem de cabos de bateria". *concluiu Lenine* fecha a OS mesmo assim.', t1);
  v_res := pg_temp.ok(v_res, 'T13b sem a pendente dita (o dono disse que está feita), conclui como antes', t2 = 'completed true', t2);
  v_res := pg_temp.ok(v_res, 'T13c com tarefas_concluir_sem_pendente = false, conclui como antes', t3 = 'completed true', t3);
  v_res := pg_temp.ok(v_res, 'T13d só sem registro (ninguém disse que falta): conclui, e a medida conta concluidas_sem_confirmacao',
    t4 = 'completed true 1 0', t4);
  perform pg_temp.gravar(v_res);
end
$t13$;

-- ── T14. As leituras (a linha "Etapas" da OS e o dia da pessoa) ──────────────────────────────────────────────────────────────────
do $antes_leituras$
begin
  if coalesce(current_setting('agenda_teste.mig_leituras_fase1', true), '') = ''
     or coalesce(current_setting('agenda_teste.mig_leituras_fase2', true), '') = '' then
    return;
  end if;
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_leituras_fase1'), '_agenda_ver_os'),
                  'create or replace function public._agenda_ver_os(', 'create function pg_temp.ver_os_antes(');
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_leituras_fase2'), 'agenda_dia_da_pessoa'),
                  'create or replace function public.agenda_dia_da_pessoa(', 'create function pg_temp.dia_antes(');
end
$antes_leituras$;
do $t14$
declare
  v_res jsonb := '[]'::jsonb;
  t1 text; t2 text; t3 text; t4 text; t5 text; t6 text; t7 text; t8 text;
  v_dif text;
  n text;
begin
  if not pg_temp.carregada() or to_regprocedure('pg_temp.ver_os_antes(uuid, date)') is null then
    insert into _resultado values ('T14 as leituras', true, 'PULADO: sem a fixture do P8 e as migrations como texto (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.semana('qua_noite');
    perform pg_temp.compressor();
    perform public._agenda_tarefas_sincronizar(pg_temp.os('OS-97191'), date '2026-11-04', pg_temp.em(date '2026-11-04', '19:40'));
    t1 := public._agenda_ver_os(pg_temp.os('OS-97191'), date '2026-11-04') ->> 'texto';
    t2 := public.os_tarefas_da_os(pg_temp.os('OS-97192'), date '2026-11-04') ->> 'texto';
    t3 := public.agenda_dia_da_pessoa(pg_temp.pessoa('Alex'), date '2026-11-05', date '2026-11-04') ->> 'texto';
    t4 := (public.agenda_dia_da_pessoa(pg_temp.pessoa('Alex'), date '2026-11-05', date '2026-11-04') #> '{dados,plano,0,etapas}') ->> 0;
    select string_agg(nn || ':' || char_length(public.os_tarefas_da_os(pg_temp.os(nn), date '2026-11-04') ->> 'texto'), ',')
           filter (where char_length(public.os_tarefas_da_os(pg_temp.os(nn), date '2026-11-04') ->> 'texto') > 400)
      into t5 from unnest(array['OS-97191', 'OS-97192', 'OS-97193', 'OS-97194', 'OS-97195', 'OS-97196']) nn;
    update public.os_tarefas set estado = 'feita', feita_em = now(), feita_via = 'dono', mudou_em = now()
     where service_order_id = pg_temp.os('OS-97192') and estado = 'viva';
    t6 := public.os_tarefas_da_os(pg_temp.os('OS-97192'), date '2026-11-04') ->> 'texto';
    perform pg_temp.modo('sombra');
    t7 := public._agenda_ver_os(pg_temp.os('OS-97191'), date '2026-11-04') ->> 'texto';
    -- desligado: = a de antes, byte a byte (as etapas existem e não aparecem)
    perform pg_temp.modo('desligado');
    foreach n in array array['OS-97191', 'OS-97192', 'OS-97194', 'OS-97195'] loop
      if public._agenda_ver_os(pg_temp.os(n), date '2026-11-04') is distinct from pg_temp.ver_os_antes(pg_temp.os(n), date '2026-11-04') then
        v_dif := concat_ws(', ', v_dif, n);
      end if;
    end loop;
    if public.agenda_dia_da_pessoa(pg_temp.pessoa('Alex'), date '2026-11-05', date '2026-11-04')
       is distinct from pg_temp.dia_antes(pg_temp.pessoa('Alex'), date '2026-11-05', date '2026-11-04')
       or public.agenda_dia_da_pessoa(pg_temp.pessoa('Mateus'), date '2026-11-04', date '2026-11-04')
          is distinct from pg_temp.dia_antes(pg_temp.pessoa('Mateus'), date '2026-11-04', date '2026-11-04') then
      v_dif := concat_ws(', ', v_dif, 'o dia da pessoa');
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T14a a linha "Etapas" da OS (agenda_ver com a OS), depois da do prazo: o feito × pendente, o escopo novo e o "não cabe" (§16.6.8)',
    t1 like '%Prazo: sex 06/11 (o cliente disse).' || E'\n' || 'Etapas: 1 de 5 feitas (Diagnóstico de vazamento do sistema de água pressurizado). Falta: Conversão do sistema de refrigeração para 12V (sex 06/11); Substituição da tampa da boia (sex 06/11); Instalação do compressor e recarga de gás (entrou qua 04/11: o orçamento aumentou); e mais 1. Até sex 06/11 não cabe: falta cerca de 1,5 dia e o plano tem 1.',
    t1);
  v_res := pg_temp.ok(v_res, 'T14b a pendente: "(ficou faltando qua 04/11; vai qui 05/11)"', t2 like '%Passagem e crimpagem de cabos de bateria (ficou faltando qua 04/11; vai qui 05/11)%', t2);
  v_res := pg_temp.ok(v_res, 'T14c o que o Alex faz amanhã (agenda_dia_da_pessoa): " — o que fazer: …" no item da OS (3 linhas, o item em até 200 letras); o plano ganha as etapas',
    t3 = 'Amanhã (qui 05/11), Alex tem Lenine (OS-97192) o dia todo (com você fechando) — o que fazer: 1) Passagem e crimpagem de cabos de bateria; 2) Terminar: Substituição baterias - chumbo para litio; e mais 1. Costuma vir de seg a sex (você disse).'
    and t4 like '%"texto": "Passagem e crimpagem de cabos de bateria"%', t3);
  v_res := pg_temp.ok(v_res, 'T14d a linha "Etapas" até 400 letras nas 6 OS; tudo feito: "Etapas: as 4 feitas."',
    t5 is null and t6 = 'Etapas: as 4 feitas.', coalesce(t5, 'todas até 400') || ' · ' || t6);
  v_res := pg_temp.ok(v_res, 'T14e em teste: "Etapas (em teste: a equipe ainda não recebe): …"',
    t7 like '%' || E'\n' || 'Etapas (em teste: a equipe ainda não recebe): 1 de 5 feitas (%', t7);
  v_res := pg_temp.ok(v_res, 'T14f desligado: a visão da OS e o dia da pessoa = os de antes, byte a byte', v_dif is null, coalesce(v_dif, 'iguais'));
  perform pg_temp.gravar(v_res);
end
$t14$;

-- ── T15. O rascunho etapa e o *grava* ──────────────────────────────────────────────────────────────────────────────────────────
create function pg_temp.etapa(p_os text, p_etapa text, p_estado text, p_texto text, p_partes text[], p_trecho text) returns jsonb
language sql as $f$
  select public.agenda_rascunho_etapa(pg_temp.adm(), 'painel', p_os, p_etapa, p_estado, p_texto, p_partes, p_trecho, date '2026-11-04')
$f$;
do $t15$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  g jsonb;
  t_a text; t_b text; t_c text; t_num text; t_amb text; t_gua text; t_nova text; t_parte text; t_forma text; t_desl text; t_desl2 text;
  t_g1 text; t_g2 text; t_g3 text; t_g4 text; t_falta text; t_pal text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T15 o rascunho etapa', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.semana('qua_noite');
    perform set_config('agenda.agora', pg_temp.em(date '2026-11-04', '20:00')::text, true);
    r := pg_temp.etapa('OS-97192', 'porta fusíveis', 'feita', null, null, 'no Lenine os porta-fusíveis já estão instalados');
    t_a := (r ->> 'ok') || ' | ' || (r ->> 'releitura');
    r := pg_temp.etapa('OS-97191', null, null, 'Trocar a bomba d''água', null, 'acrescenta no Flávio: trocar a bomba d''água');
    t_b := (r ->> 'ok') || ' | ' || (r ->> 'releitura');
    r := pg_temp.etapa('OS-97194', 'instalação do novo sistema', null, null, array['Fixar o banco de baterias', 'Passar os cabos', 'Montar o quadro'],
                       'divide a instalação do Vanderlei em 3: fixar o banco de baterias, passar os cabos e montar o quadro');
    t_c := (r ->> 'ok') || ' | ' || (r ->> 'releitura');
    -- as guardas
    t_num := pg_temp.etapa('OS-97192', '2', 'falta', null, null, 'no Lenine falta a 2') ->> 'pergunta';
    t_amb := pg_temp.etapa('OS-97192', 'bateria', 'falta', null, null, 'no Lenine falta a bateria') ->> 'pergunta';
    t_gua := pg_temp.etapa('OS-97192', 'porta fusíveis', 'feita', null, null, 'no Lenine a porta fusíveis') ->> 'pergunta';
    t_nova := pg_temp.etapa('OS-97191', null, null, 'Trocar a bomba d''água', null, 'acrescenta uma coisa no Flávio') ->> 'pergunta';
    t_parte := pg_temp.etapa('OS-97194', 'instalação do novo sistema', null, null, array['Fixar o banco de baterias', 'Pintar o casco'],
                             'divide a instalação em 2: fixar o banco de baterias e a outra parte') ->> 'pergunta';
    t_forma := pg_temp.erro_de($q$select pg_temp.etapa('OS-97192', 'porta fusíveis', 'feita', 'Outra coisa', null, 'tudo junto')$q$);
    -- o *grava*: a porta-fusíveis feita (e a linha congelada dela), a etapa nova do dono no lugar certo, a divisão
    g := public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-04');
    t_g1 := g ->> 'texto';
    t_g2 := pg_temp.etapas('OS-97192') || ' # ' || pg_temp.linhas(date '2026-11-04');
    t_g3 := (select string_agg(t.texto || ':' || t.origem || ':' || t.horas || ':' || t.ordem, ', ' order by t.ordem)
               from public.os_tarefas t where t.service_order_id = pg_temp.os('OS-97191') and t.estado = 'viva');
    t_g4 := (select string_agg(t.texto || ':' || t.origem || ':' || t.horas || ':' || t.exige || ':' || (t.pai_id is not null), ', ' order by t.ordem)
               from public.os_tarefas t where t.service_order_id = pg_temp.os('OS-97194') and t.texto not like 'Desm%' and t.texto not like 'Adeq%'
                and t.texto not like 'Conf%' and t.texto not like 'Test%')
            || ' # ' || (select t.estado from public.os_tarefas t where t.service_order_id = pg_temp.os('OS-97194') and t.texto like 'Instalação do novo%');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- "no Lenine ainda falta a porta-fusíveis" (a pendente dita pelo dono: grava pendente via dono na linha congelada dela)
    perform pg_temp.semana('qua_noite');
    perform set_config('agenda.agora', pg_temp.em(date '2026-11-04', '20:00')::text, true);
    r := pg_temp.etapa('OS-97192', 'porta fusíveis', 'falta', null, null, 'no Lenine ainda falta a porta fusíveis');
    g := public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-04');
    t_falta := (g ->> 'texto') || ' # ' || pg_temp.linhas(date '2026-11-04');
    -- "no Lenine falta a substituição das baterias": pelas palavras, a substituição
    r := pg_temp.etapa('OS-97192', 'substituição das baterias', 'falta', null, null, 'no Lenine falta a substituição das baterias');
    t_pal := (r ->> 'ok') || ' | ' || (r ->> 'releitura');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.semana('ter');
    update public.agenda_config set modo_leitura = 'desligado' where id;
    t_desl := pg_temp.etapa('OS-97192', 'porta fusíveis', 'feita', null, null, 'no Lenine os porta-fusíveis já estão instalados') ->> 'pergunta';
    update public.agenda_config set modo_leitura = 'ligado', modo_tarefas = 'desligado' where id;
    t_desl2 := pg_temp.etapa('OS-97192', 'porta fusíveis', 'feita', null, null, 'no Lenine os porta-fusíveis já estão instalados') ->> 'pergunta';
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T15a (a) feita: a releitura do banco (a linha começa pelo rótulo da OS, a frase não repete o nome)',
    t_a like 'true | %• Lenine (OS-97192): "Instalação de porta fusíveis - distribuição de energia 12v" já está feita%', t_a);
  v_res := pg_temp.ok(v_res, 'T15b (b) a etapa nova com as palavras do dono', t_b like 'true | %• Flávio (OS-97191): acrescentar "Trocar a bomba d''água" (no fim, antes de testar e entregar)%', t_b);
  v_res := pg_temp.ok(v_res, 'T15c (c) dividir, com as partes da base (a linha e o que o dono disse)',
    t_c like 'true | %• Vanderlei (OS-97194): dividir "Instalação do novo sistema elétrico LiFePO4/Usina" em 3: Fixar o banco de baterias; Passar os cabos; Montar o quadro%', t_c);
  v_res := pg_temp.ok(v_res, 'T15d só o número ("no Lenine falta a 2") não vale: a pergunta pelo nome, com a lista (R5.10-10); nenhum rascunho',
    t_num = 'Me diga pelo nome: no Lenine faltam Substituição baterias - chumbo para litio, Instalação de porta fusíveis - distribuição de energia 12v, Passagem e crimpagem de cabos de bateria e Testar e conferir antes de entregar (Elétrico DC).',
    t_num);
  v_res := pg_temp.ok(v_res, 'T15e as guardas: a etapa ambígua ("bateria": a substituição e a passagem) não casa; sem a palavra do estado no trecho; a etapa nova sem as palavras do dono; a parte sem base; uma coisa por vez (22023)',
    t_amb like 'Não acho essa etapa no Lenine. As que faltam: %' and t_gua = 'Não achei no que você disse qual etapa do Lenine; me diga de novo.'
    and t_nova = 'Para acrescentar, preciso das suas palavras: o que entra no Flávio?'
    and t_parte = 'Para dividir, cada parte tem de vir do serviço, do roteiro, do material da OS ou do que você disse: "Pintar o casco" não tem de onde vir.'
    and t_forma = '22023 Diga uma coisa por vez: uma etapa feita ou que falta, uma etapa nova ou dividir uma etapa.',
    concat_ws(' | ', t_amb, t_gua, t_nova, t_parte, t_forma));
  v_res := pg_temp.ok(v_res, 'T15f o *grava*: "Gravado. Agora:" com as 3 frases (§16.6.9)',
    t_g1 like 'Gravado. Agora:%• Lenine: "Instalação de porta fusíveis - distribuição de energia 12v" feita.%'
    and t_g1 like '%• Flávio: entrou "Trocar a bomba d''água", antes de testar e entregar.%'
    and t_g1 like '%• Vanderlei: "Instalação do novo sistema elétrico LiFePO4/Usina" virou 3 etapas.%', t_g1);
  v_res := pg_temp.ok(v_res, 'T15g a feita pelo dono: a etapa e a linha congelada dela (via dono)',
    t_g2 like '%Instalação de porta fusíveis - distribuição de energia 12v:feita%' and t_g2 like '% # Inst:feita/dono,Pass:pendente/equipe', t_g2);
  v_res := pg_temp.ok(v_res, 'T15h a etapa nova do dono: viva, origem dono, 1 h (tarefas_horas_min), antes do final',
    t_g3 like '%Trocar a bomba d''água:dono:1.00:3.500, Testar e conferir tudo antes de entregar:seguranca:1.50:4.000', t_g3);
  v_res := pg_temp.ok(v_res, 'T15i a divisão: a etapa (do roteiro) substituída e as 3 partes logo depois dela (origem ia, o peso ÷ 3, a máscara dela)',
    t_g4 = 'Instalação do novo sistema elétrico LiFePO4/Usina:roteiro:18.85:1:false, Fixar o banco de baterias:ia:6.28:1:true, Passar os cabos:ia:6.28:1:true, Montar o quadro:ia:6.28:1:true # substituida', t_g4);
  v_res := pg_temp.ok(v_res, 'T15j "ainda falta" pelo dono: a linha congelada dela (que já passou) fica pendente via dono, por cima (R5.2-3, R5.10-11); pelas palavras, "a substituição das baterias" casa a substituição',
    t_falta like '%• Lenine: "Instalação de porta fusíveis - distribuição de energia 12v" volta a faltar.% # Inst:pendente/dono,Pass:pendente/equipe'
    and t_pal like 'true | %"Substituição baterias - chumbo para litio" ainda falta%', t_falta || ' · ' || t_pal);
  v_res := pg_temp.ok(v_res, 'T15k com a agenda desligada ou as etapas desligadas, não anota',
    t_desl = 'A agenda de produção está desligada agora: não anotei nada.' and t_desl2 = 'As etapas dos serviços ainda estão desligadas: não anotei nada.',
    t_desl || ' | ' || t_desl2);
  perform pg_temp.gravar(v_res);
end
$t15$;

-- ── T16. As medidas ────────────────────────────────────────────────────────────────────────────────────────────────────────────
do $t16$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  m jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T16 as medidas', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.semana('qui_como_foi');
    perform pg_temp.compressor();
    r := public.agenda_resposta_da_equipe('5547900000031', 'ok, faltou a 1', 'WA-T16', pg_temp.em(date '2026-11-05', '17:40'));
    r := pg_temp.tique(date '2026-11-05', '17:52');
    m := public.agenda_tarefas_medidas(date '2026-11-01', date '2026-11-06', date '2026-11-05');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T16 as medidas da semana: 1 alerta de 2 dias, 1 etapa nova do escopo, nenhuma etapa de risco em meio-dia que não atende; o PPC das etapas entre 0 e 1 (sem o sem registro); as respostas com lista todas entendidas',
    (m ->> 'alertas_2_dias')::int = 1 and (m ->> 'escopo_novo')::int = 1 and (m ->> 'risco_sem_quem_atende')::int = 0
    and (m ->> 'ppc_etapas')::numeric between 0 and 1 and (m #>> '{respostas,com_lista}')::int >= 3
    and (m #>> '{respostas,entendidas}')::int = (m #>> '{respostas,com_lista}')::int,
    m::text);
  perform pg_temp.gravar(v_res);
end
$t16$;

-- ── T17. A rodada ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
do $t17$
declare
  v_res jsonb := '[]'::jsonb;
  r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb;
  n0 int; n1 int; n2 int;
  t_desl text;
  t_teste text;
  t_hora text;
  t_falha text;
  v_t0 timestamptz;
  v_ms int;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('T17 a rodada', true, 'PULADO: sem a fixture do P8 (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.semana('ter');
    n0 := (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'tarefas');
    v_t0 := clock_timestamp();
    r1 := pg_temp.tique(date '2026-11-03', '19:45');
    v_ms := (extract(epoch from clock_timestamp() - v_t0) * 1000)::int;
    n1 := (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'tarefas');
    -- o diário: uma vez por dia, a partir de tarefas_hora (16:20)
    r2 := pg_temp.tique(date '2026-11-04', '16:22');
    r3 := pg_temp.tique(date '2026-11-04', '16:37');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- em teste, o diário (a partir de tarefas_hora): a ação de teste com o que a ficha de amanhã diria a quem responde (§16.5.4); a hora
    -- do "como foi" é a de agenda_config (com 17:30, o texto diz 17:30)
    perform pg_temp.modo('sombra');
    perform pg_temp.tique(date '2026-11-03', '07:10');
    perform pg_temp.tique(date '2026-11-04', '07:10');
    perform pg_temp.tique(date '2026-11-04', '16:22');
    t_teste := (select string_agg(a.texto || ' [' || a.executada || ' ' || a.origem || ']', ' | ') from public.agenda_acoes a where a.tipo = 'tarefa');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modo('sombra');
    update public.agenda_config set equipe_hora_como_foi = '17:30' where id;
    perform pg_temp.tique(date '2026-11-03', '07:10');
    perform pg_temp.tique(date '2026-11-04', '07:10');
    perform pg_temp.tique(date '2026-11-04', '16:22');
    t_hora := (select string_agg(right(a.texto, 45), ' | ') from public.agenda_acoes a where a.tipo = 'tarefa');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- desligado: a rodada não faz nada, não grava etapa nem a linha da rotina
    update public.agenda_config set modo_tarefas = 'desligado' where id;
    n2 := (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'tarefas');
    r5 := pg_temp.tique(date '2026-11-04', '07:10');
    r5 := pg_temp.tique(date '2026-11-04', '16:22');
    t_desl := (select count(*) from public.os_tarefas) || ' ' || (select count(*) from public.os_tarefas_dia) || ' '
              || ((select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'tarefas') - n2) || ' ' || coalesce(r5 ->> 'gravou', '-');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o passo que falha (congelar): a rodada não lança, os outros rodam, a falha vai a app_error_logs (agenda / tarefas:congelar)
    perform pg_temp.modo('ligado');
    create function pg_temp.quebra() returns trigger language plpgsql as $q$ begin raise exception 'teste: o congelar quebrou'; end $q$;
    create trigger t17_quebra before insert on public.os_tarefas_dia for each row execute function pg_temp.quebra();
    r4 := pg_temp.tique(date '2026-11-03', '07:10');
    t_falha := (r4 ->> 'erros') || ' ' || (r4 -> 'falhas' -> 0 ->> 'passo') || ' ' || (r4 -> 'contagens' ? 'sincronizar') || ' '
               || (r4 -> 'contagens' ? 'conferir') || ' '
               || (select count(*) from public.app_error_logs e where e.context = 'agenda' and e.action = 'tarefas:congelar') || ' '
               || (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'tarefas' and x.erros = 1);
    drop trigger t17_quebra on public.os_tarefas_dia;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T17f em teste, o diário deixa UMA ação de teste por quem responde amanhã, com o que a ficha diria (não executada, da vigia); a hora do "como foi" vem de agenda_config',
    t_teste = 'Em teste (o que cada um faz): amanhã (qui 05/11) o Alex levaria na ficha: 1) Terminar: Substituição baterias - chumbo para litio; 2) Testar e conferir antes de entregar (Elétrico DC). Às 17:00 eu perguntaria o que ficou faltando. [false vigia]'
    and t_hora = 'Às 17:30 eu perguntaria o que ficou faltando.', concat_ws(' · ', t_teste, t_hora));
  v_res := pg_temp.ok(v_res, 'T17e desligado: a rodada não grava etapa, linha do dia nem a linha da rotina', t_desl like '0 0 0 %', t_desl || ' ' || r5::text);
  v_res := pg_temp.ok(v_res, 'T17a o tique sem nada a fazer não grava a linha da rotina; os que fazem gravam (rotina tarefas)',
    n0 >= 2 and n1 = n0 and not (r1 ->> 'gravou')::boolean, format('%s %s %s', n0, n1, r1 ->> 'gravou'));
  v_res := pg_temp.ok(v_res, 'T17b o passo diário uma vez por dia, a partir de tarefas_hora', r2 -> 'contagens' ? 'diario' and not (r3 -> 'contagens' ? 'diario'),
    (r2 -> 'contagens' ? 'diario')::text || ' ' || (r3 -> 'contagens' ? 'diario')::text);
  v_res := pg_temp.ok(v_res, 'T17c o passo que falha: 1 erro (congelar), os outros passos rodaram, a falha em app_error_logs (agenda / tarefas:congelar) e na linha da rotina',
    t_falha = '1 congelar true true 1 1', t_falha);
  v_res := pg_temp.ok(v_res, format('T17d o tempo de um tique sem nada a fazer na fixture (%s ms; a meta de produção é 300 ms; a bancada é PGlite)', v_ms),
    v_ms < 3000, v_ms::text);
  perform pg_temp.gravar(v_res);
end
$t17$;

-- ── T18. As cópias: as 9 recriadas só acrescentam os blocos do P8 (sem fixture) ───────────────────────────────────────────────────
-- Cada recriada é a definição MAIS NOVA de antes (a origem abaixo), byte a byte, mais os blocos "-- FASE 7c: (7c P8 …" e as marcas
-- "-- (7c P8 …" de dentro da linha (n); e a que está no banco é a desta migration.
do $t18$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_tarefas_fase7c', true), '');
  v_dif text;
  v_viva text;
  v_sem text;
  v_n int := 0;
  f record;
begin
  if v_mig = '' then
    insert into _resultado values ('T18 as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  for f in select * from (values
      ('_agenda_modo_da_pergunta', 'agenda_teste.mig_base_fase7c'),
      ('_agenda_rascunho_frase', 'agenda_teste.mig_conversa_fase7c'),
      ('agenda_rascunho_gravar', 'agenda_teste.mig_conversa_fase7c'),
      ('_agenda_ver_os', 'agenda_teste.mig_leituras_fase1'),
      ('agenda_dia_da_pessoa', 'agenda_teste.mig_leituras_fase2'),
      ('agenda_equipe_ficha', 'agenda_teste.mig_equipe_fase3'),
      ('_agenda_rotina_conclusao', 'agenda_teste.mig_equipe_fase3'),
      ('agenda_resposta_da_equipe', 'agenda_teste.mig_correcao_fase7b'),
      ('_agenda_linhas_do_fechamento', 'agenda_teste.mig_rodada_fase7c')) x(nome, origem) loop
    if coalesce(current_setting(f.origem, true), '') = '' then
      v_sem := concat_ws(', ', v_sem, f.nome);
      continue;
    end if;
    v_n := v_n + 1;
    if pg_temp.sem_p8(pg_temp.corpo(v_mig, f.nome)) is distinct from replace(pg_temp.corpo(current_setting(f.origem), f.nome), E'\r\n', E'\n')
       or pg_temp.corpo(v_mig, f.nome) = pg_temp.sem_p8(pg_temp.corpo(v_mig, f.nome)) then
      v_dif := concat_ws(', ', v_dif, f.nome);
    end if;
    if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = f.nome) <> 1
       -- FASE 7c: (correção da revisão, 20261102100580) a viva sem os blocos e as marcas da correção (ela recria 2 das 9 só com
       -- acréscimos: agenda_dia_da_pessoa e _agenda_linhas_do_fechamento; o K0 de agenda_fase77c_correcao.sql confere)
       or pg_temp.sem_corr(pg_temp.sem_7d((select replace(p.prosrc, E'\r\n', E'\n') from pg_proc p
                                           where p.pronamespace = 'public'::regnamespace and p.proname = f.nome)))
          is distinct from pg_temp.corpo(v_mig, f.nome) then
       -- FASE 7c: fim
      v_viva := concat_ws(', ', v_viva, f.nome);
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'T18a as 9 recriadas, sem os blocos do P8, são a definição mais nova de antes, byte a byte (e cada uma tem bloco do P8)',
    v_n = 9 and v_dif is null and v_sem is null, format('%s conferidas; diferentes: %s; sem a origem: %s', v_n, coalesce(v_dif, 'nenhuma'), coalesce(v_sem, 'nenhuma')));
  v_res := pg_temp.ok(v_res, 'T18b no banco está a desta migration (uma definição de cada)', v_viva is null, coalesce(v_viva, 'iguais'));
  v_res := pg_temp.ok(v_res, 'T18c a migration cria ou recria 33 funções: as 22 novas, as 2 de gatilho e as 9 recriadas',
    (select count(*) from regexp_matches(v_mig, '\ncreate or replace function public\.([a-z_0-9]+)\(', 'g')) = 33,
    (select count(*) from regexp_matches(v_mig, '\ncreate or replace function public\.([a-z_0-9]+)\(', 'g'))::text);
  perform pg_temp.gravar(v_res);
end
$t18$;

-- ── T19. A linha (o) do fechamento e a (n) com as perguntas das etapas (R5.2-2) ─────────────────────────────────────────────────
-- O fechamento de antes (a origem: 20261102100400, o P5), rodado como pg_temp.
do $antes_fech$
begin
  if coalesce(current_setting('agenda_teste.mig_rodada_fase7c', true), '') = '' then
    return;
  end if;
  execute replace(pg_temp.inteira(current_setting('agenda_teste.mig_rodada_fase7c'), '_agenda_linhas_do_fechamento'),
                  'create or replace function public._agenda_linhas_do_fechamento(', 'create function pg_temp.fechamento_antes(');
end
$antes_fech$;
-- A linha (o) do fechamento do dia (a de texto "Etapas" ou "Em teste: Etapas"), ou nula.
create function pg_temp.linha_o(p_dia date) returns jsonb language sql stable as $f$
  select x from jsonb_array_elements(public._agenda_linhas_do_fechamento(p_dia)) x
   where x ->> 'tipo' = 'dia' and (x ->> 'texto' like 'Etapas (%' or x ->> 'texto' like 'Em teste: Etapas (%')
$f$;
-- O João (da fixture da 7a, sem telefone) com telefone e na rotina: a (o) fica só com o Alex.
create function pg_temp.joao_na_rotina() returns void language plpgsql as $f$
declare
  v_joao uuid := pg_temp.pessoa('João');
begin
  update public.payees set phone = '5547900000041' where id = v_joao;
  if not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = v_joao) then
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    values (v_joao, true, 'dono', timestamptz '2026-10-30 00:11-03');
  end if;
  update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null, parou_motivo = null where payee_id = v_joao;
end $f$;
do $t19$
declare
  v_res jsonb := '[]'::jsonb;
  r jsonb;
  o_qua jsonb; o_ter jsonb; o_som jsonb; o_fone jsonb; o_joao jsonb; o_falta jsonb;
  t_painel text; t_tec text;
  v_lig_igual boolean; v_lig_det text;
  v_n jsonb; v_e int;
  c_tec constant uuid := 'c7c80000-0000-4000-8000-0000000ec008';
begin
  if not pg_temp.carregada() or to_regprocedure('pg_temp.fechamento_antes(date)') is null then
    insert into _resultado values ('T19 a linha (o)', true, 'PULADO: sem a fixture do P8 e as migrations como texto (rode pela bancada)');
    return;
  end if;
  begin
    -- ligado, o Alex sem telefone (o de produção): o "como foi" dele é recusado, e a (o) leva as etapas de hoje e de amanhã ao dono
    perform pg_temp.joao_na_rotina();
    update public.payees set phone = null where id = pg_temp.pessoa('Alex');
    perform pg_temp.semana('ter');
    o_ter := pg_temp.linha_o(date '2026-11-03');
    r := pg_temp.tique(date '2026-11-04', '07:10');
    r := public._agenda_rotina_como_foi(date '2026-11-04', pg_temp.em(date '2026-11-04', '17:00'));
    o_qua := pg_temp.linha_o(date '2026-11-04');
    -- o painel (o administrador logado) lê a mesma linha; a técnica logada não a recebe
    t_painel := pg_temp.como(pg_temp.adm(), 'authenticated',
      $q$select x ->> 'texto' from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-04')) x where x ->> 'texto' like 'Etapas (%'$q$);
    t_tec := pg_temp.como(c_tec, 'authenticated',
      $q$select count(*)::text from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-04')) x where x ->> 'texto' like 'Etapas (%'$q$);
    -- a (n) leva as perguntas das etapas (tarefa), e a (e) não as repete
    v_n := (select jsonb_agg(q.chave order by q.chave) from public.agenda_perguntas q
             where q.tipo = 'tarefa' and q.estado = 'aberta' and q.modo = 'ligado'
               and exists (select 1 from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-04')) x
                            where x ->> 'tipo' = 'pergunta' and (x -> 'pergunta_ids' ? q.id::text or x ->> 'pergunta_id' = q.id::text)
                              and (x ->> 'perda')::int >= 75));
    v_e := (select count(*) from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-04')) x
             where (x ->> 'perda')::int = 30
               and exists (select 1 from public.agenda_perguntas q where q.tipo = 'tarefa'
                            and (x -> 'pergunta_ids' ? q.id::text or x ->> 'pergunta_id' = q.id::text)));
    -- o dono diz pela conversa que no Lenine ainda falta a passagem (o *grava*): ela volta primeiro amanhã, o teste vai à tarde com ele
    perform set_config('agenda.agora', pg_temp.em(date '2026-11-04', '18:10')::text, true);
    r := pg_temp.etapa('OS-97192', 'passagem dos cabos', 'falta', null, null, 'no Lenine ainda falta a passagem dos cabos');
    r := public.agenda_rascunho_gravar(pg_temp.adm(), date '2026-11-04');
    o_falta := pg_temp.linha_o(date '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- com o telefone do Alex (e o João na rotina), ninguém fica de fora do WhatsApp: sem a (o)
    perform pg_temp.joao_na_rotina();
    perform pg_temp.semana('qua');
    o_fone := pg_temp.linha_o(date '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o João da 7a (sem telefone, fora da rotina) entra junto: "Alex e João não têm telefone"
    update public.payees set phone = null where id = pg_temp.pessoa('Alex');
    perform pg_temp.semana('qua');
    o_joao := pg_temp.linha_o(date '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- em teste: a (o) de modo sombra com "Em teste: "; as linhas ligado (as que o dono lê) = as do fechamento de antes, byte a byte
    perform pg_temp.joao_na_rotina();
    update public.payees set phone = null where id = pg_temp.pessoa('Alex');
    perform pg_temp.modo('sombra');
    r := pg_temp.tique(date '2026-11-03', '07:10');
    r := public._agenda_rotina_como_foi(date '2026-11-03', pg_temp.em(date '2026-11-03', '17:00'));
    r := pg_temp.tique(date '2026-11-03', '19:30');
    r := pg_temp.tique(date '2026-11-04', '07:10');
    r := pg_temp.tique(date '2026-11-04', '10:07');
    r := public._agenda_rotina_como_foi(date '2026-11-04', pg_temp.em(date '2026-11-04', '17:00'));
    o_som := pg_temp.linha_o(date '2026-11-04');
    select (select jsonb_agg(x) from jsonb_array_elements(public._agenda_linhas_do_fechamento(d)) x where x ->> 'modo' = 'ligado')
           is not distinct from
           (select jsonb_agg(x) from jsonb_array_elements(pg_temp.fechamento_antes(d)) x where x ->> 'modo' = 'ligado'),
           d::text
      into v_lig_igual, v_lig_det
      from (values (date '2026-11-04')) z(d);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'T19a qua 04/11, ligado, o Alex sem telefone: a linha (o) sem números — o que hoje devia ficar pronto, o exemplo pelas palavras, o que fazer amanhã e a cobrança do último dia (R5.2-2(b))',
    o_qua ->> 'texto' = 'Etapas (Alex não tem telefone: quem passa e confere é você). Hoje no Lenine devia ficar pronto: Passagem e crimpagem de cabos de bateria. Se faltou alguma, me diga qual (ex.: no Lenine falta "passagem e crimpagem de cabos de bateria"). Amanhã (qui 05/11), Alex no Lenine: Terminar: Substituição baterias - chumbo para litio; Testar e conferir antes de entregar (Elétrico DC). É o último dia: tem que ficar tudo pronto.'
    and o_qua ->> 'texto' !~ '(^|[ :;])\d\) ',
    o_qua ->> 'texto');
  v_res := pg_temp.ok(v_res, 'T19b a véspera do último dia: perda 75, tipo dia, ligado, sem pergunta nem ação; a forma curta para o Secretário cheio',
    (o_qua ->> 'perda')::int = 75 and o_qua ->> 'modo' = 'ligado' and o_qua -> 'pergunta_id' = 'null'::jsonb and o_qua -> 'acao_ids' = '[]'::jsonb
    and o_qua ->> 'texto_curto' = 'Etapas: amanhã é o último dia do Lenine (Alex, 2 etapas); hoje, 1 para conferir. Pergunte o que o Alex faz amanhã.'
    and char_length(o_qua ->> 'texto') <= 480,
    format('%s %s %s', o_qua ->> 'perda', o_qua ->> 'modo', o_qua ->> 'texto_curto'));
  -- FASE 7c: (correção 2 da revisão, 20261102100590, achado 13; a cobrança saiu na 7d P5, R6.12) qua 04/11 é dia de revisão da tarde, e com 62d1fd95 as linhas saem
  -- nesse dia: a linha de ter 03/11 não cobra mais o último dia do Lenine (qui 05/11); ela sai na própria qua 04/11. Amanhã (qua) continua sem "É o último dia" e sem
  -- pendente dita (a etapa de risco sozinha não sobe a perda): 70.
  v_res := pg_temp.ok(v_res, 'T19c ter 03/11 (amanhã não é o último dia de nenhuma OS e não volta pendente dita): perda 70, sem a cobrança antecipada do último dia do Lenine (7d P5, R6.12: ela sai na própria véspera)',
    (o_ter ->> 'perda')::int = 70 and o_ter ->> 'texto' like 'Etapas (Alex não tem telefone: quem passa e confere é você). Hoje no Flávio devia ficar pronto: %'
    and o_ter ->> 'texto' !~ 'Qui 05/11 é o último dia do Lenine' and o_ter ->> 'texto' !~ 'é dia de revisão'
    and char_length(o_ter ->> 'texto') <= 480
    and o_ter ->> 'texto' not like '%Amanhã (qua 04/11), Alex no Lenine: %É o último dia%',
    format('%s · %s', o_ter ->> 'perda', o_ter ->> 'texto'));
  -- FASE 7c: fim
  v_res := pg_temp.ok(v_res, 'T19d o painel (o administrador logado) lê a mesma linha (a régua do telefone com authenticated); a técnica logada não a recebe',
    t_painel = o_qua ->> 'texto' and (t_tec = '0' or t_tec like 'erro P0002: A agenda está sem os parâmetros%'), concat_ws(' | ', t_painel, t_tec));
  v_res := pg_temp.ok(v_res, 'T19e a (n) leva as perguntas das etapas (tarefa) abertas, com a perda dela, e a (e) não as repete (R5.4 item 4)',
    jsonb_array_length(coalesce(v_n, '[]'::jsonb)) >= 1 and v_e = 0, format('%s; (e): %s', v_n, v_e));
  v_res := pg_temp.ok(v_res, 'T19i o dono disse que ainda falta a passagem: hoje não há o que conferir; amanhã ela volta primeiro e o teste é à tarde "— com você"; perda 75',
    o_falta ->> 'texto' = 'Etapas (Alex não tem telefone: quem passa e confere é você). Amanhã (qui 05/11), Alex no Lenine: Passagem e crimpagem de cabos de bateria; Terminar: Substituição baterias - chumbo para litio; Testar e conferir antes de entregar (Elétrico DC) — com você. É o último dia: tem que ficar tudo pronto.'
    and (o_falta ->> 'perda')::int = 75,
    format('%s · %s', o_falta ->> 'perda', o_falta ->> 'texto'));
  v_res := pg_temp.ok(v_res, 'T19f todos com telefone e na rotina: nenhuma linha (o)', o_fone is null, coalesce(o_fone ->> 'texto', 'nenhuma'));
  v_res := pg_temp.ok(v_res, 'T19g duas pessoas sem telefone (o Alex e o João da 7a): "Alex e João não têm telefone", cortado por etapa inteira até 480 letras',
    o_joao ->> 'texto' like 'Etapas (Alex e João não têm telefone: quem passa e confere é você). %' and char_length(o_joao ->> 'texto') <= 480
    and o_joao ->> 'texto' like '%; e mais %',
    o_joao ->> 'texto');
  v_res := pg_temp.ok(v_res, 'T19h em teste: a (o) de modo sombra começa por "Em teste: "; as linhas ligado (o texto do dono) = as do fechamento de antes, byte a byte',
    o_som ->> 'modo' = 'sombra' and o_som ->> 'texto' like 'Em teste: Etapas (Alex não tem telefone: %' and v_lig_igual,
    format('%s · ligado igual: %s', o_som ->> 'texto', v_lig_igual));
  perform pg_temp.gravar(v_res);
end
$t19$;

-- ── T20. O fechamento com as etapas desligadas = o de antes (a saída inteira) ────────────────────────────────────────────────────
do $t20$
declare
  v_res jsonb := '[]'::jsonb;
  v_dif text;
  d date;
  v_var text;
begin
  if not pg_temp.carregada() or to_regprocedure('pg_temp.fechamento_antes(date)') is null then
    insert into _resultado values ('T20 o fechamento desligado', true, 'PULADO: sem a fixture do P8 e as migrations como texto (rode pela bancada)');
    return;
  end if;
  foreach v_var in array array['7b ligada', '7b em sombra', '7b desligada', 'Alex sem telefone'] loop
    begin
      update public.agenda_config set modo_tarefas = 'desligado',
             modo_equipe = case v_var when '7b em sombra' then 'sombra' when '7b desligada' then 'desligado' else 'ligado' end where id;
      if v_var = 'Alex sem telefone' then
        update public.payees set phone = null where id = pg_temp.pessoa('Alex');
      end if;
      perform set_config('agenda.hoje', '2026-11-03', true);
      perform public._agenda_rotina_como_foi(date '2026-11-03', pg_temp.em(date '2026-11-03', '17:00'));
      perform public.agenda_tarefas_rodar(date '2026-11-03', pg_temp.em(date '2026-11-03', '19:30'));
      foreach d in array array[date '2026-11-03', date '2026-11-04', date '2026-11-05', date '2026-11-06', date '2026-11-10'] loop
        perform set_config('agenda.hoje', d::text, true);
        if public._agenda_linhas_do_fechamento(d) is distinct from pg_temp.fechamento_antes(d) then
          v_dif := concat_ws(', ', v_dif, v_var || ' ' || d);
        end if;
      end loop;
      if exists (select 1 from public.os_tarefas) or exists (select 1 from public.os_tarefas_dia) then
        v_dif := concat_ws(', ', v_dif, v_var || ': gravou etapa');
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'T20 com modo_tarefas desligado, a saída inteira de _agenda_linhas_do_fechamento = a do P5, byte a byte (ter a qua seguinte; a 7b ligada, em sombra e desligada; o Alex sem telefone), e nenhuma etapa gravada',
    v_dif is null, coalesce(v_dif, 'iguais'));
  perform pg_temp.gravar(v_res);
end
$t20$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
