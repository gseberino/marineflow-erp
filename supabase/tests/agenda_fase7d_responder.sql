-- Prova do conserto do NOVO-agenda-91 na Agenda de Produção, Fase 7d (pacote P6b; migration 20261107100550): a pergunta com opções ganha resposta pela conversa.
-- Tudo passa pelo CAMINHO REAL: agenda_ver foco decisoes (*agenda pendências*) → agenda_rascunho_aplicar → *grava* (agenda_rascunho_gravar), nunca agenda_decidir direto. Os
-- testes da 7a e da 7b chamavam agenda_decidir, e por isso nunca viram o defeito.
-- bancada: depende de 20261107100550
--
--   R0  as portas e as cópias: a função nova; as 3 recriadas, que só mudam onde devem; a migration não escreve dado; nada de tique lê a lista
--   R1  um caso por tipo, com número e efeito: a chamada, o contato, a estimativa, a situacao, a dias_semana ligada, a reavaliar, a reestimar, a ficha_estimativa, a diaria_ligar
--   R2  a nfe_vincular e a previsao_fornecedor: fora da lista, sem número, "1" não cai em outra pergunta; o caminho real é material_informar com o aviso
--   R3  a ordem: as críticas primeiro, com o número de antes; a crítica não muda a releitura
--   R4  o "1" ambíguo: com várias esperando, pergunta qual e não grava rascunho; a numeração que anda; o nome; por extenso
--   R5  a pergunta que venceu; a sombra fica de fora; a opção já dita não ganha número; opcoes que não é lista (escalar, nulo, objeto)
--   R6  o freio: ninguém marca dia; quem tem número e não tem resposta ouve isso na hora
--   R7  a tela (agenda_tela_semana) e as cobranças do fechamento: as linhas não mudam
--   R8  as 3 perguntas reais de produção (05/11), com os textos e as opções delas: o que o dono vê e o que cada opção faz
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7d_responder.sql
--   Seguro em produção: termina em ROLLBACK. As portas rodam em qualquer banco; o resto usa as fixtures e só roda na bancada (fora dela sai PULADO).
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
-- O texto sem os blocos "-- FASE 7d: … -- FASE 7d: fim".
create function pg_temp.sem_7d(p text) returns text language plpgsql immutable as $f$
declare
  v_fora   text[] := '{}';
  v_dentro boolean := false;
  l        text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- FASE 7d:' and l !~ '^\s*-- FASE 7d: fim' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro and l ~ '^\s*-- FASE 7d: fim' then
      v_dentro := false;
      continue;
    end if;
    if not v_dentro then
      v_fora := v_fora || l;
    end if;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;
create function pg_temp.como(p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_papel)::text, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- ── R0. As portas (sem fixture) ──────────────────────────────────────────────────────
insert into _resultado
select 'R0a a função nova é interna: invoker, imutável, search_path fixo, nem public, nem anon, nem authenticated, nem service_role',
       p.oid is not null and not p.prosecdef and p.provolatile = 'i' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
       and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
       and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute'),
       null
  from pg_proc p
 where p.oid = 'public._agenda_disse_os_numeros(text, integer, integer)'::regprocedure;

insert into _resultado
select 'R0b anon não chega (42501): a nova, a lista e o rascunho, rodando de verdade',
       pg_temp.como('anon', $q$select public._agenda_disse_os_numeros('1', 1, 1)::text$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public.agenda_decisoes_abertas(now())::text$q$) like 'erro 42501%'
       and pg_temp.como('anon', $q$select public.agenda_rascunho_aplicar(gen_random_uuid(), 'whatsapp', null, null, '1', '1', '1')::text$q$) like 'erro 42501%',
       pg_temp.como('anon', $q$select public.agenda_decisoes_abertas(now())::text$q$);

insert into _resultado
select 'R0c as recriadas mantêm o que eram: a lista e o foco invoker e stable; o rascunho definer e volatile; search_path fixo',
       (select not p.prosecdef and p.provolatile = 's' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
          from pg_proc p where p.oid = 'public.agenda_decisoes_abertas(timestamptz)'::regprocedure)
       and (select not p.prosecdef and p.provolatile = 's' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
              from pg_proc p where p.oid = 'public._agenda_ver_decisoes(date, timestamptz)'::regprocedure)
       and (select p.prosecdef and p.provolatile = 'v' and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=public'
              from pg_proc p where p.oid = 'public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamptz)'::regprocedure),
       null;

insert into _resultado
select 'R0d a lista não entrou em caminho de tique: só agenda_rascunho_aplicar, _agenda_ver_decisoes e agenda_tela_semana a chamam',
       array_agg(p.proname::text order by p.proname::text) = array['_agenda_ver_decisoes', 'agenda_rascunho_aplicar', 'agenda_tela_semana'],
       array_to_string(array_agg(p.proname::text order by p.proname::text), ', ')
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and p.prosrc like '%agenda_decisoes_abertas(%' and p.proname <> 'agenda_decisoes_abertas';

insert into _resultado
select 'R0e a palavra do dono: os 2 números em algarismo, por extenso e separados; "1" sozinho não vale pelos dois; iguais, 2 vezes; sem a decisão, só a opção',
       bool_and(public._agenda_disse_os_numeros(c.t, c.d, c.o) = c.espera) and count(*) = 23,
       string_agg(c.t, '; ') filter (where public._agenda_disse_os_numeros(c.t, c.d, c.o) is distinct from c.espera)
  from (values
    ('1', 1, 1, false), ('2', 1, 2, false), ('2', 2, 1, false), ('1 1', 1, 1, true), ('na decisão 1, a opção 2', 1, 2, true), ('opção 2 da decisão 1', 1, 2, true),
    ('na decisão um, a opção dois', 1, 2, true), ('a primeira, opção 2', 1, 2, true), ('a 1/2', 1, 2, true), ('1.2', 1, 2, true), ('', 1, 2, false),
    ('pode ser', 1, 1, false), ('já está combinado', 1, 1, false), ('qui 12/11', 1, 2, false), ('decisão 12, opção 3', 1, 3, false), ('decisão 2', 2, 2, false),
    ('do Giancarlo, a 1', null, 1, true), ('do Giancarlo', null, 1, false), ('opção um', null, 1, true),
    ('a segunda, opção 3', 2, 3, true), ('a terceira, opção 4', 3, 4, true), ('quatro e cinco', 4, 5, true), ('na quarta, opção 1', 4, 1, false))
    as c(t, d, o, espera);

-- ── As fixtures e as definições de antes ─────────────────────────────────────────────
-- A base é a equipe REAL de produção (Alex e o dono) sobre o replay de 29/10; quem precisa de Mateus e Bruno os carrega dentro do caso.
do $carga$
declare
  v_m text;
begin
  if coalesce(current_setting('agenda_teste.fase7b', true), '') = '' or coalesce(current_setting('agenda_teste.fase7a', true), '') = ''
     or coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
    return;
  end if;
  perform set_config('agenda_teste.fase7b_equipe', 'real', true);
  execute current_setting('agenda_teste.fase7b');
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  -- a lista de antes do pacote, para a ordem das críticas
  v_m := coalesce(current_setting('agenda_teste.mig_cliente_fase7d', true), '');
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, 'agenda_decisoes_abertas'), 'create or replace function public.agenda_decisoes_abertas(',
                    'create function pg_temp.lista_antes(');
  end if;
  update public.agenda_config
     set modo_proposta = 'ligado', modo_vigia = 'ligado', modo_marcar_sozinho = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         modo_material = 'ligado', modo_equipe = 'ligado', modo_diaria = 'ligado', modo_leitura = 'ligado', modo_cadastro = 'ligado', modo_dias = 'ligado',
         modo_revisao_diaria = 'ligado'
   where id;
  -- a presença do dono como em produção (abre e fecha; o replay dá "sempre")
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
end
$carga$;

create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-00130')
     and exists (select 1 from public.agenda_equipe_contato c join public.payees py on py.id = c.payee_id where py.name = 'Alex' and c.incluido_por = 'dono')
     and to_regprocedure('pg_temp.lista_antes(timestamptz)') is not null
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$
  select id from public.app_users where role = 'admin' and active order by id limit 1
$f$;
create function pg_temp.os(p_numero text) returns uuid language sql stable as $f$
  select so.id from public.service_orders so where so.service_order_number = p_numero
$f$;
create function pg_temp.pessoa(p_nome text) returns uuid language sql stable as $f$
  select id from public.payees where name = p_nome and active order by id limit 1
$f$;
-- Sem pergunta aberta de antes: cada caso começa com a lista vazia.
create function pg_temp.limpa() returns void language sql as $f$
  update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where estado = 'aberta'
$f$;
-- Uma pergunta à mão, com o que importa.
create function pg_temp.perg(p_tipo text, p_chave text, p_texto text, p_opcoes jsonb, p_os uuid default null, p_perda date default null, p_modo text default 'ligado',
                             p_rec smallint default null, p_payee uuid default null, p_dia date default null) returns uuid language sql as $f$
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, opcoes, perda_em, modo, recomendacao, payee_id, dia, criada_em)
  values (p_tipo, p_chave, p_os, case when p_os is null then '{}'::uuid[] else array[p_os] end, p_texto, p_opcoes, p_perda, p_modo, p_rec, p_payee, p_dia, timestamptz '2026-10-29 08:00-03')
  returning id
$f$;
create function pg_temp.lista(p_dia date, p_hora text default '17:40') returns jsonb language sql stable as $f$
  select public.agenda_decisoes_abertas(pg_temp.em(p_dia, p_hora))
$f$;
create function pg_temp.pendencias(p_dia date, p_hora text default '17:40') returns text language sql stable as $f$
  select public._agenda_ver_decisoes(p_dia, pg_temp.em(p_dia, p_hora)) ->> 'texto'
$f$;
-- A ferramenta agenda_aplicar: a decisão e a opção como o modelo passou, e as palavras do dono.
create function pg_temp.responde(p_decisao text, p_opcao text, p_trecho text, p_dia date, p_hora text default '17:41') returns jsonb language sql as $f$
  select public.agenda_rascunho_aplicar(pg_temp.adm(), 'whatsapp', null, null, p_decisao, p_opcao, p_trecho, p_dia, pg_temp.em(p_dia, p_hora))
$f$;
-- O *grava*.
create function pg_temp.grava(p_dia date, p_hora text default '17:42') returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', pg_temp.em(p_dia, p_hora)::text, true);
  return public.agenda_rascunho_gravar(pg_temp.adm(), p_dia);
end $f$;
create function pg_temp.rascunhos() returns int language sql stable as $f$
  select count(*)::int from public.agenda_rascunho r where r.autor = pg_temp.adm() and r.estado = 'aberto'
$f$;
create function pg_temp.est(p_id uuid) returns text language sql stable as $f$
  select q.estado || ':' || coalesce(q.opcao_escolhida::text, '-') || ':' || coalesce(q.respondida_via, '-') from public.agenda_perguntas q where q.id = p_id
$f$;
-- O plano inteiro: a prova de que ninguém marcou dia.
create function pg_temp.plano() returns text language sql stable as $f$
  select md5(coalesce(string_agg(a.id::text || a.estado, ',' order by a.id), '')) from public.agenda_alocacoes a
$f$;
create function pg_temp.os_pl(p_os uuid) returns text language sql stable as $f$
  select coalesce(pl.dias::text, 'sem dias') || '/' || coalesce(pl.estimativa_fonte, 'sem fonte') from (select 1) z
    left join public.os_planejamento pl on pl.service_order_id = p_os
$f$;
-- A semana da equipe, como a rodada.
create function pg_temp.semana(p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.hoje', p_dia::text, true);
  return public.agenda_equipe_semana(p_dia, pg_temp.em(p_dia, p_hora));
end $f$;
-- Mateus, Rafael e Bruno (a fixture sem a variante real; o que já está fica)
create function pg_temp.equipe_toda() returns void language plpgsql as $f$
begin
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  execute current_setting('agenda_teste.fase7b');
end $f$;

-- ── R0f a R0j: as cópias ─────────────────────────────────────────────────────────────
do $cp$
declare
  v_res jsonb := '[]'::jsonb;
  v_mig text := coalesce(current_setting('agenda_teste.mig_responder_fase7d', true), '');
  v_p6  text := coalesce(current_setting('agenda_teste.mig_cliente_fase7d', true), '');
  v_f2  text := coalesce(current_setting('agenda_teste.mig_rascunho_fase2', true), '');
  v_org text;
  v_txt text;
  v_viva text;
begin
  if v_mig = '' or v_p6 = '' or v_f2 = '' then
    insert into _resultado values ('R0f as cópias', true, 'PULADO: sem as migrations como texto (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_org := pg_temp.corpo(v_f2, 'agenda_rascunho_aplicar');
  v_txt := pg_temp.corpo(v_mig, 'agenda_rascunho_aplicar');
  select replace(p.prosrc, E'\r\n', E'\n') into v_viva from pg_proc p where p.oid = 'public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamptz)'::regprocedure;
  v_res := pg_temp.ok(v_res, 'R0f agenda_rascunho_aplicar só muda nos blocos "-- FASE 7d:", na migration e viva (a de 20261025100400, byte a byte)',
    v_org <> '' and pg_temp.sem_7d(v_txt) = v_org and pg_temp.sem_7d(v_viva) = v_org and v_txt <> v_org, null);
  v_org := pg_temp.corpo(v_p6, '_agenda_ver_decisoes');
  v_txt := pg_temp.corpo(v_mig, '_agenda_ver_decisoes');
  v_res := pg_temp.ok(v_res, 'R0g _agenda_ver_decisoes só muda no bloco do P5', v_org <> '' and pg_temp.sem_7d(v_txt) = pg_temp.sem_7d(v_org) and v_txt <> v_org, null);
  v_org := pg_temp.corpo(v_p6, 'agenda_decisoes_abertas');
  v_txt := pg_temp.corpo(v_mig, 'agenda_decisoes_abertas');
  v_res := pg_temp.ok(v_res, 'R0h agenda_decisoes_abertas: só o texto, a ordem e o where',
    replace(replace(replace(v_txt,
      $$'os_ids', to_jsonb(x.os_ids),
           'texto', case when x.critica or x.texto ~ '(^|\s)\d\)\s' or jsonb_array_length(x.opcoes) < 2 then x.texto
                         else x.texto || ' ' || (select string_agg((o ->> 'n') || ') ' || (o ->> 'texto'), '; ' order by (o ->> 'n')::int)
                                                   from jsonb_array_elements(x.opcoes) o) || '.' end,
$$, $$'os_ids', to_jsonb(x.os_ids), 'texto', x.texto,
$$),
      'order by (not q.critica), q.perda_em', 'order by q.perda_em'),
      $$where (q.critica
                  or (q.tipo in ('combinar', 'local', 'situacao', 'estimativa', 'reavaliar', 'reestimar', 'ficha_estimativa', 'dias_semana',
                                 'equipe_cadastro', 'diaria_ligar')
                      and q.opcao_escolhida is null
                      and case when jsonb_typeof(q.opcoes) = 'array' then jsonb_array_length(q.opcoes) > 0 else false end))
             and q.estado$$, $$where (q.critica or q.tipo in ('combinar', 'local')) and q.estado$$) = v_org, v_txt);
  v_res := pg_temp.ok(v_res, 'R0i a migration só cria as 4 e não escreve dado; nada de cliente, fila, prompt, dinheiro nem as funções da sessão do retorno',
    (select count(*) from regexp_matches(v_mig, 'create or replace function public\.', 'g')) = 4
    and v_mig !~* '(^|\n)\s*(update|insert into|delete from)\s+public\.'
    and pg_temp.corpo(v_mig, 'agenda_decidir') = '' and pg_temp.corpo(v_mig, '_agenda_cliente_registrar') = ''
    and pg_temp.corpo(v_mig, '_agenda_chave_telefone') = '' and pg_temp.corpo(v_mig, 'agenda_dia_util') = '' and pg_temp.corpo(v_mig, 'agenda_somar_du') = ''
    and pg_temp.corpo(v_mig, 'agenda_feriado') = '' and pg_temp.corpo(v_mig, '_agenda_cliente_dia') = '' and pg_temp.corpo(v_mig, '_agenda_nome_curto') = '', null);
  perform pg_temp.gravar(v_res);
end
$cp$;

-- ── R1. Um caso por tipo ─────────────────────────────────────────────────────────────
do $r1$
declare
  v_res  jsonb := '[]'::jsonb;
  c_d    constant date := date '2026-11-05';
  c_g    constant date := date '2026-10-29';
  c_ag   constant timestamptz := timestamptz '2026-10-29 16:52-03';
  r      jsonb;
  r2     jsonb;
  v_t    text;
  v_q    uuid;
  v_id   uuid;
  v_ac   uuid;
  v_pl   text;
  q      public.agenda_perguntas%rowtype;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R1 um caso por tipo', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;

  -- A chamada, opção 1
  begin
    perform pg_temp.limpa();
    update public.agenda_config set modo_dias = 'sombra' where id;
    perform pg_temp.semana(c_d, '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:%' and x.estado = 'aberta';
    v_t := pg_temp.pendencias(c_d);
    v_res := pg_temp.ok(v_res, 'R1a a chamada ganha número em *agenda pendências* e não aparece duas vezes',
      v_t like 'Uma decisão espera você na agenda:%Decisão 1: Na agenda conto com Alex%' and v_t like '%na decisão 1, a opção 2%' and v_t not like '%Também quero saber: Na agenda conto%'
      and q.id is not null and not q.critica and q.modo = 'ligado', v_t);
    r := pg_temp.responde(null, '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R1b sozinha na lista, "1" é a opção 1 dela; a releitura diz de qual pergunta é (antes: "Não tenho decisão da agenda esperando você agora")',
      (r ->> 'ok')::boolean and r ->> 'releitura' like E'Entendi assim, confere?\n• Decisão: na pergunta "Na agenda conto com Alex%": Está certo.\nResponda *grava*%' and pg_temp.rascunhos() = 1, r::text);
    v_res := pg_temp.ok(v_res, 'R1c nada muda antes do *grava*', pg_temp.est(q.id) = 'aberta:-:-', pg_temp.est(q.id));
    r2 := pg_temp.grava(c_d);
    v_res := pg_temp.ok(v_res, 'R1d o *grava* chega a agenda_decidir: "Anotei: sigo com a equipe que tenho.", respondida pela opção 1, pelo WhatsApp, e sai da lista',
      r2 ->> 'texto' like '%Anotei: sigo com a equipe que tenho.%' and pg_temp.est(q.id) = 'respondida:1:whatsapp' and jsonb_array_length(pg_temp.lista(c_d)) = 0, r2::text || pg_temp.est(q.id));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A chamada, opção 2
  begin
    perform pg_temp.limpa();
    update public.agenda_config set modo_dias = 'sombra' where id;
    perform pg_temp.semana(c_d, '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave like 'equipe_cadastro:chamada:%' and x.estado = 'aberta';
    r := pg_temp.responde('1', '2', 'decisão 1, opção 2', c_d);
    r2 := pg_temp.grava(c_d);
    v_res := pg_temp.ok(v_res, 'R1e a chamada, opção 2: pede quem saiu e quem entrou',
      r2 ->> 'texto' like '%Me diga quem saiu ou quem entrou e em que dias vem%' and pg_temp.est(q.id) = 'respondida:2:whatsapp', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O contato, opção 1 (Bruno) e opção 2 (Mateus)
  begin
    perform pg_temp.limpa();
    perform pg_temp.equipe_toda();
    perform pg_temp.limpa();
    v_id := pg_temp.pessoa('Bruno');
    update public.agenda_config set modo_dias = 'desligado' where id;
    perform pg_temp.semana(c_d, '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave = 'equipe_cadastro:contato:' || v_id and x.estado = 'aberta';
    v_t := pg_temp.pendencias(c_d);
    v_res := pg_temp.ok(v_res, 'R1f o contato ganha número', q.id is not null and v_t like '%Decisão %: Bruno tem telefone, mas não está na rotina%' and v_t not like '%Também quero saber: Bruno tem telefone%', v_t);
    r := (select e from jsonb_array_elements(pg_temp.lista(c_d)) e where e ->> 'id' = q.id::text);
    r2 := pg_temp.responde(r ->> 'n', '1', format('decisão %s, opção 1', r ->> 'n'), c_d);
    v_res := pg_temp.ok(v_res, 'R1g o contato: a releitura diz de quem é', r2 ->> 'releitura' like '%na pergunta "Bruno tem telefone%": Ponho.%', r2::text);
    r2 := pg_temp.grava(c_d);
    v_res := pg_temp.ok(v_res, 'R1h o contato, opção 1: entra na rotina pelo dono, com *desfaz*',
      r2 ->> 'texto' like '%Pus Bruno na rotina da equipe, como você pediu. *desfaz* tira.%'
      and (select c.recebe_rotina and c.incluido_por = 'dono' from public.agenda_equipe_contato c where c.payee_id = v_id)
      and (select a.desfazivel_ate is not null from public.agenda_acoes a where a.tipo = 'equipe' and a.payee_id = v_id and a.depois ->> 'motivo' = 'contato') , r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    perform pg_temp.equipe_toda();
    perform pg_temp.limpa();
    v_id := pg_temp.pessoa('Bruno');
    update public.agenda_config set modo_dias = 'desligado' where id;
    perform pg_temp.semana(c_d, '16:45');
    select x.* into q from public.agenda_perguntas x where x.chave = 'equipe_cadastro:contato:' || v_id and x.estado = 'aberta';
    r := (select e from jsonb_array_elements(pg_temp.lista(c_d)) e where e ->> 'id' = q.id::text);
    r2 := pg_temp.responde(r ->> 'n', '2', format('decisão %s, opção 2', r ->> 'n'), c_d);
    r2 := pg_temp.grava(c_d);
    v_res := pg_temp.ok(v_res, 'R1i o contato, opção 2: a linha parada, e a pergunta não volta',
      r2 ->> 'texto' like '%Anotei: Bruno fica fora da rotina da equipe.%'
      and (select not c.recebe_rotina and c.parou_em is not null from public.agenda_equipe_contato c where c.payee_id = v_id), r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A estimativa do Giancarlo, opção 1 (os dias), opção 2 (eu digo) e opção 3 (terminou)
  begin
    perform pg_temp.limpa();
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    v_t := pg_temp.pendencias(c_g, '17:00');
    v_res := pg_temp.ok(v_res, 'R1j a estimativa ganha número, com as 3 opções no texto', v_q is not null and v_t like '%Decisão 1: Giancarlo (OS-00130): pelo valor do orçamento%1) Marque 10 dias; 2) Eu digo os dias (recomendo); 3) Já terminou%', v_t);
    v_pl := pg_temp.plano();
    r := pg_temp.responde(null, '1', '1', c_g, '17:01');
    v_res := pg_temp.ok(v_res, 'R1k a releitura da estimativa diz Giancarlo', r ->> 'releitura' like '%na pergunta "Giancarlo (OS-00130): pelo valor do orçamento%": Marque 10 dias.%', r::text);
    r2 := pg_temp.grava(c_g, '17:02');
    v_res := pg_temp.ok(v_res, 'R1l a estimativa, opção 1: os 10 dias gravados pela minha conta, com *desfaz*; a agenda não marca dia nenhum nessa resposta',
      r2 ->> 'texto' like '%Combinado, Giancarlo: contei 10 dias (estimativa minha). *desfaz Giancarlo* volta.%'
      and pg_temp.os_pl(pg_temp.os('OS-00130')) = '10.0/orcamento' and pg_temp.est(v_q) = 'respondida:1:whatsapp' and pg_temp.plano() = v_pl,
      r2::text || pg_temp.os_pl(pg_temp.os('OS-00130')) || pg_temp.est(v_q));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    r := pg_temp.responde('1', '2', 'decisão 1, opção 2', c_g, '17:01');
    r2 := pg_temp.grava(c_g, '17:02');
    v_t := pg_temp.pendencias(c_g, '17:03');
    v_res := pg_temp.ok(v_res, 'R1m a estimativa, opção 2: "Me diga os dias", ela fica aberta com a opção escolhida, perde o número e fica em "Também quero saber"',
      r2 ->> 'texto' like '%Me diga os dias (ex.: ''Giancarlo 3 dias'').%' and pg_temp.est(v_q) = 'aberta:2:-'
      and jsonb_array_length(pg_temp.lista(c_g, '17:03')) = 0 and v_t like '%Também quero saber: Giancarlo (OS-00130)%' and v_t not like '%Decisão 1%', r2::text || v_t);
    r := pg_temp.responde(null, '1', '1', c_g, '17:04');
    v_res := pg_temp.ok(v_res, 'R1n depois dela, "1" não reabre: a pergunta é por palavras', r ->> 'motivo' = 'sem_numero' and r ->> 'texto' like 'Essa pergunta não tem número de decisão: me responda com as suas palavras. Giancarlo%', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    r := pg_temp.responde('1', '3', 'decisão 1, opção 3', c_g, '17:01');
    r2 := pg_temp.grava(c_g, '17:02');
    v_res := pg_temp.ok(v_res, 'R1o a estimativa, opção 3: "Use *concluiu Giancarlo*.", respondida; a OS não conclui sozinha',
      r2 ->> 'texto' like '%Use *concluiu Giancarlo*.%' and pg_temp.est(v_q) = 'respondida:3:whatsapp'
      and (select so.status from public.service_orders so where so.id = pg_temp.os('OS-00130')) <> 'completed', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A situacao do Nelson
  begin
    perform pg_temp.limpa();
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    select x.* into q from public.agenda_perguntas x where x.id = v_q;
    v_t := pg_temp.pendencias(c_g, '17:00');
    v_res := pg_temp.ok(v_res, 'R1p a situacao ganha número', q.tipo = 'situacao' and v_t like '%Decisão 1: Nelson (OS-00112)%', v_t);
    r := pg_temp.responde('1', '1', 'na decisão 1, a opção 1', c_g, '17:01');
    r2 := pg_temp.grava(c_g, '17:02');
    v_res := pg_temp.ok(v_res, 'R1q a situacao, opção 1: os dias da proposta gravados pela minha conta',
      r2 ->> 'texto' like '%Combinado, Nelson:%*desfaz Nelson* volta.%' and pg_temp.est(v_q) = 'respondida:1:whatsapp'
      and pg_temp.os_pl(pg_temp.os('OS-00112')) like '%/orcamento', r2::text || pg_temp.est(v_q));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A dias_semana ligada: a opção 2 cria o padrão do dono
  begin
    perform pg_temp.limpa();
    update public.agenda_config set modo_cadastro = 'desligado' where id;
    perform pg_temp.semana(c_d, '16:45');
    select x.* into q from public.agenda_perguntas x where x.tipo = 'dias_semana' and x.estado = 'aberta';
    v_t := pg_temp.pendencias(c_d);
    v_res := pg_temp.ok(v_res, 'R1r a dias_semana ligada ganha número', q.id is not null and q.modo = 'ligado' and v_t like '%Decisão 1: Semana de 16/11:%' and v_t not like '%Também quero saber: Semana de 16/11%', v_t);
    r := pg_temp.responde(null, '2', 'a 2', c_d);
    v_res := pg_temp.ok(v_res, 'R1s a releitura da dias_semana', r ->> 'releitura' like '%na pergunta "Semana de 16/11:%": Fico em campo de seg a sex.%', r::text);
    r2 := pg_temp.grava(c_d);
    v_res := pg_temp.ok(v_res, 'R1t a dias_semana, opção 2: o padrão do dono, seg a sex, toda semana',
      r2 ->> 'texto' like '%Anotei: você fica em campo de seg a sex, toda semana a partir de agora.%'
      and (select count(*) from public.agenda_disponibilidade d where d.payee_id = public._agenda_dono(null) and d.substituida_em is null and d.dias_semana = '{1,2,3,4,5}' and d.origem = 'dono') = 1,
      r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A reavaliar, a reestimar, a ficha_estimativa e a diaria_ligar: o número e a chegada a agenda_decidir
  begin
    perform pg_temp.limpa();
    v_q := pg_temp.perg('reavaliar', 'reavaliar:teste', 'O diagnóstico de Rodrigo (OS-00096) foi feito ter 27/10. 1) Terminou: use *concluiu Rodrigo*; 2) Achou mais serviço: me diga o que é e quantos dias.',
      '[{"n":1,"texto":"Terminou: use *concluiu Rodrigo*","efeito":{"terminou":true}},{"n":2,"texto":"Achou mais serviço: me diga o que é e quantos dias","efeito":{"dizer":true}}]', pg_temp.os('OS-00096'));
    r := pg_temp.responde(null, '2', '2', c_g);
    r2 := pg_temp.grava(c_g);
    v_res := pg_temp.ok(v_res, 'R1u a reavaliar: número, *grava*, "Me diga o que mais tem para fazer"', r2 ->> 'texto' like '%Me diga o que mais tem para fazer e quantos dias%' and pg_temp.est(v_q) = 'respondida:2:whatsapp', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_q := pg_temp.perg('reestimar', 'reestimar:teste', 'Nelson (OS-00112): o orçamento mudou depois que você disse 2 dias. 1) Fique com 2 dias (recomendo); 2) Use 3 dias.',
      '[{"n":1,"texto":"Fique com 2 dias","efeito":{"manter":true}},{"n":2,"texto":"Use 3 dias","efeito":{"dias":3}}]', pg_temp.os('OS-00112'));
    v_res := pg_temp.ok(v_res, 'R1v a reestimar entra na lista', (pg_temp.lista(c_g) -> 0 ->> 'tipo') = 'reestimar', pg_temp.lista(c_g)::text);
    r := pg_temp.responde(null, '1', '1', c_g);
    r2 := pg_temp.grava(c_g);
    -- a condição não vale (a chave à mão não é a de agora): o despacho chegou, e o lote não grava
    v_res := pg_temp.ok(v_res, 'R1w a reestimar: o *grava* chega a _agenda_gestor_decidir', (r ->> 'ok')::boolean and r2 ->> 'texto' like 'Não gravei nada. A agenda mudou desde a releitura: Não mudei nada: não precisa mais%', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_id := pg_temp.pessoa('Alex');
    v_q := pg_temp.perg('ficha_estimativa', format('ficha_estimativa:%s:2026-10-30', v_id), 'Hoje às 19:30 a ficha de sex 30/10 vai para Alex: Lenine, pela minha estimativa. 1) Mande (recomendo); 2) Segure a ficha: eu não mando e você fala com ele.',
      '[{"n":1,"texto":"Mande","efeito":{"mandar":true}},{"n":2,"texto":"Segure a ficha","efeito":{"segurar":true}}]', pg_temp.os('OS-00074'));
    r := pg_temp.responde(null, '2', '2', c_g);
    r2 := pg_temp.grava(c_g);
    v_res := pg_temp.ok(v_res, 'R1x a ficha_estimativa: número, *grava*, "não mando a ficha", e conta como vista',
      r2 ->> 'texto' like '%Combinado: não mando a ficha de sex 30/10 para Alex%' and pg_temp.est(v_q) = 'respondida:2:whatsapp'
      and (select x.mostrada_vezes >= 1 from public.agenda_perguntas x where x.id = v_q), r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_id := pg_temp.pessoa('Alex');
    v_q := pg_temp.perg('diaria_ligar', format('diaria_ligar:%s:2026-10-28', v_id), 'A diária de qua 28/10 do Alex já estava lançada, sem OS. Ligo ao Lenine (OS-00074)? Me responda aqui.',
      '[{"n":1,"texto":"ligar a diária às OS do plano","efeito":{"diaria":"ligar"}},{"n":2,"texto":"deixar sem OS","efeito":{"diaria":"manter"}}]', pg_temp.os('OS-00074'), null, 'ligado', 1::smallint, v_id, date '2026-10-28');
    v_t := pg_temp.pendencias(c_g);
    v_res := pg_temp.ok(v_res, 'R1y a diaria_ligar: o texto não traz as opções, e a lista acrescenta: o número tem o que responder',
      v_t like '%Decisão 1: A diária de qua 28/10 do Alex já estava lançada, sem OS. Ligo ao Lenine (OS-00074)? Me responda aqui. 1) ligar a diária às OS do plano; 2) deixar sem OS.%', v_t);
    r := pg_temp.responde(null, '2', '2', c_g);
    r2 := pg_temp.grava(c_g);
    v_res := pg_temp.ok(v_res, 'R1z a diaria_ligar, opção 2: fica como estava', r2 ->> 'texto' like '%Deixei a diária de qua 28/10 do Alex como estava.%' and pg_temp.est(v_q) = 'respondida:2:whatsapp', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A combinar e a local continuam na lista; a local sem leitura, de uma opção só, não ganha opção no texto
  begin
    perform pg_temp.limpa();
    v_q := pg_temp.perg('combinar', 'combinar:acesso:r1', 'Nelson já autorizou João? 1) Já está (anoto); 2) Ainda não.', '[{"n":1,"texto":"Já está"},{"n":2,"texto":"Ainda não"}]', pg_temp.os('OS-00112'), date '2026-11-01');
    perform pg_temp.perg('local', 'local:r1', 'Beto respondeu onde fica a lancha: "na marina". Não achei esse lugar no cadastro. Me diga onde é.', '[{"n":2,"texto":"Não gravo, eu te digo como é"}]', pg_temp.os('OS-00074'), date '2026-11-02');
    v_t := pg_temp.pendencias(c_g);
    v_res := pg_temp.ok(v_res, 'R1z1 a combinar e a local seguem numeradas; a de uma opção só não ganha opção no texto',
      v_t like '%Decisão 1: Nelson já autorizou João? 1) Já está (anoto); 2) Ainda não.%' and v_t like E'%Decisão 2: Beto respondeu onde fica a lancha: "na marina". Não achei esse lugar no cadastro. Me diga onde é.\n%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Sozinha na lista, a decisão e a opção que o modelo passou valem, mesmo sem número nas palavras: a régua das palavras é para quando há mais de uma esperando
  begin
    perform pg_temp.limpa();
    perform pg_temp.perg('equipe_cadastro', 'equipe_cadastro:chamada:U', 'Pergunta U? 1) Está certo; 2) Mudou.', '[{"n":1,"texto":"Está certo","efeito":{"chamada":"ok"}},{"n":2,"texto":"Mudou","efeito":{"chamada":"mudou"}}]');
    r := pg_temp.responde('1', '1', 'está certo', c_d);
    v_res := pg_temp.ok(v_res, 'R1z2 sozinha, "está certo" com decisão 1 e opção 1 vira rascunho', (r ->> 'ok')::boolean and pg_temp.rascunhos() = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r1$;

-- ── R2. A nota e o aviso do fornecedor: fora da lista ───────────────────────────────
create function pg_temp.nfe(p_os uuid) returns uuid language plpgsql as $f$
declare
  v_rem uuid;
begin
  insert into public.material_remessas (nfe_chave, emitente, emitente_uf, numero, emitida_em, saida_em, previsao_ate, mod_frete, itens)
  values (repeat('4', 44), 'Tamoyo', 'SC', '495411', date '2026-10-27', date '2026-10-27', date '2026-11-03', '0',
          '[{"descricao":"Porta Fusivel MIDI"}]'::jsonb)
  returning id into v_rem;
  return pg_temp.perg('nfe_vincular', 'nfe:' || v_rem,
    'Chegou por e-mail a nota 495411 da Tamoyo (SC, sem cadastro), despachada sáb 31/10: deve chegar por volta de ter 03/11. É material de qual serviço? 1) Vanderlei: Porta Fusível MIDI…; 2) nenhum (estoque ou escritório). Me diga o número ou o nome.',
    jsonb_build_array(jsonb_build_object('n', 1, 'os', p_os, 'inicio', null, 'texto', 'Vanderlei: Porta Fusível MIDI…'),
                      jsonb_build_object('n', 2, 'os', null, 'texto', 'nenhum (estoque ou escritório)')));
end $f$;
create function pg_temp.rasc_q() returns uuid language sql stable as $f$
  select (r.dados ->> 'pergunta_id')::uuid from public.agenda_rascunho r where r.autor = pg_temp.adm() and r.estado = 'aberto' order by r.criado_em desc limit 1
$f$;
-- Uma pergunta da equipe à mão, que o *grava* consegue responder.
create function pg_temp.equipe(p_nome text, p_perda date default null) returns uuid language sql as $f$
  select pg_temp.perg('equipe_cadastro', 'equipe_cadastro:chamada:' || p_nome, format('Pergunta %s? 1) Está certo (recomendo); 2) Mudou.', p_nome),
    '[{"n":1,"texto":"Está certo","efeito":{"chamada":"ok"}},{"n":2,"texto":"Mudou","efeito":{"chamada":"mudou"}}]', null, p_perda)
$f$;

do $r2$
declare
  v_res jsonb := '[]'::jsonb;
  c_g   constant date := date '2026-10-29';
  c_ag  constant timestamptz := timestamptz '2026-10-29 16:52-03';
  v_van uuid;
  v_n   uuid;
  v_q   uuid;
  v_t   text;
  r     jsonb;
  r2    jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R2 a nota', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  v_van := pg_temp.os('OS-00069');

  begin
    perform pg_temp.limpa();
    v_n := pg_temp.nfe(v_van);
    v_t := pg_temp.pendencias(c_g);
    v_res := pg_temp.ok(v_res, 'R2a a nfe_vincular não entra na lista: sem número, em "Também quero saber", uma vez só',
      jsonb_array_length(pg_temp.lista(c_g)) = 0 and v_t like 'Também quero saber: Chegou por e-mail a nota 495411%' and v_t not like '%Decisão%'
      and (select count(*) from regexp_matches(v_t, 'nota 495411', 'g')) = 1, v_t);
    r := pg_temp.responde(null, '1', '1', c_g);
    v_res := pg_temp.ok(v_res, 'R2b "1" à nota: nada no rascunho, e a recusa diz que é por palavras (antes: "Não tenho decisão da agenda esperando você agora")',
      r ->> 'motivo' = 'sem_numero' and r ->> 'texto' like 'Essa pergunta não tem número de decisão: me responda com as suas palavras. Chegou por e-mail a nota 495411%' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('1', '1', 'decisão 1, opção 1', c_g);
    v_res := pg_temp.ok(v_res, 'R2c "decisão 1, opção 1", também', r ->> 'motivo' = 'sem_numero' and pg_temp.rascunhos() = 0, r::text);
    r := public.agenda_decidir(v_n, 1::smallint, pg_temp.adm(), 'whatsapp', '1', c_g, pg_temp.em(c_g, '17:41'));
    v_res := pg_temp.ok(v_res, 'R2d por isso ela fica fora: agenda_decidir não tem o que fazer com ela (o achado)', not (r ->> 'ok')::boolean and r ->> 'texto' = 'Essa pergunta não é de decisão.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- O caminho real da nota: material_informar com o aviso. A opção 2 ("nenhum") e a opção 1 (o serviço)
  begin
    perform pg_temp.limpa();
    v_n := pg_temp.nfe(v_van);
    r := public.agenda_rascunho_material(pg_temp.adm(), 'whatsapp', null, null, 'nao_e_de_servico', null, null, null, false, 'a nota 495411 não é de serviço', c_g, 'a nota 495411');
    r2 := pg_temp.grava(c_g);
    v_res := pg_temp.ok(v_res, 'R2e a nota, "nenhum": pelo caminho dela (material_informar, situação nao_e_de_servico), o *grava* a responde',
      (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean and (select x.estado from public.agenda_perguntas x where x.id = v_n) = 'respondida'
      and (select m.vinculo from public.material_remessas m where m.nfe_chave = repeat('4', 44)) = 'sem_servico', r::text || r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_n := pg_temp.nfe(v_van);
    r := public.agenda_rascunho_material(pg_temp.adm(), 'whatsapp', 'OS-00069', array['tudo'], 'a_caminho', null, null, null, false, 'a nota 495411 é do Vanderlei', c_g, 'a nota 495411');
    r2 := pg_temp.grava(c_g);
    v_res := pg_temp.ok(v_res, 'R2f a nota, "Vanderlei": material_informar com a OS e o aviso liga a nota à OS e responde a pergunta',
      (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean and (select x.estado from public.agenda_perguntas x where x.id = v_n) = 'respondida'
      and (select m.vinculo from public.material_remessas m where m.nfe_chave = repeat('4', 44)) = 'ligada', r::text || r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Com uma decisão só na lista, "1" dito à nota não pode cair nela (o buraco que o conserto abriria)
  begin
    perform pg_temp.limpa();
    v_n := pg_temp.nfe(v_van);
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    v_res := pg_temp.ok(v_res, 'R2g a lista tem só a estimativa', jsonb_array_length(pg_temp.lista(c_g)) = 1, pg_temp.lista(c_g)::text);
    r := pg_temp.responde(null, '1', '1', c_g);
    v_res := pg_temp.ok(v_res, 'R2h "1" com a nota esperando: pergunta qual, cita as duas e não grava rascunho',
      r ->> 'motivo' = 'decisao_ambigua' and r ->> 'texto' like 'Qual decisão? 1) Giancarlo%Sem número, responda com as suas palavras: Chegou por e-mail a nota 495411%' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('1', '1', '1', c_g);
    v_res := pg_temp.ok(v_res, 'R2i o modelo preenchendo decisão 1, opção 1 com o "1": também pergunta', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('1', '1', 'decisão 1, opção 1', c_g);
    v_res := pg_temp.ok(v_res, 'R2j com o dono dizendo a decisão e a opção, vale', (r ->> 'ok')::boolean and pg_temp.rasc_q() = v_q, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A previsao_fornecedor, a mesma coisa
  begin
    perform pg_temp.limpa();
    v_q := pg_temp.perg('previsao_fornecedor', 'sinal:teste', 'O Mateus escreveu: "sai amanhã". É de qual serviço? 1) Vanderlei; 2) nenhuma delas. Me diga o número ou o nome.',
      '[{"n":1,"os":null,"texto":"Vanderlei"},{"n":2,"os":null,"texto":"nenhuma delas"}]');
    r := pg_temp.responde(null, '1', '1', c_g);
    r2 := public.agenda_decidir(v_q, 1::smallint, pg_temp.adm(), 'whatsapp', '1', c_g, pg_temp.em(c_g, '17:41'));
    v_res := pg_temp.ok(v_res, 'R2k a previsao_fornecedor: fora da lista, sem número, e agenda_decidir não a decide',
      jsonb_array_length(pg_temp.lista(c_g)) = 0 and r ->> 'motivo' = 'sem_numero' and r2 ->> 'texto' = 'Essa pergunta não é de decisão.', r::text || r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r2$;

-- ── R3. A ordem ──────────────────────────────────────────────────────────────────────
do $r3$
declare
  v_res jsonb := '[]'::jsonb;
  c_d   constant date := date '2026-11-05';
  c_op  constant jsonb := '[{"n":1,"texto":"Atrasa o Nelson"},{"n":2,"texto":"Atrasa o Vanderlei"}]';
  c_1   uuid;
  c_2   uuid;
  n_1   uuid;
  n_2   uuid;
  n_3   uuid;
  v     jsonb;
  va    jsonb;
  v_t   text;
  r     jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R3 a ordem', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.limpa();
    -- as não críticas perdem ANTES das críticas: pela régua de antes, uma delas seria a "Decisão 1"
    n_1 := pg_temp.equipe('A', date '2026-11-06');
    n_2 := pg_temp.equipe('B');
    n_3 := pg_temp.equipe('C', date '2026-11-07');
    c_1 := pg_temp.perg('nao_cabe', 'nao_cabe:r3', 'Não cabe o Nelson. 1) Atrasa o Nelson; 2) Atrasa o Vanderlei.', c_op, null, date '2026-11-10', 'ligado', 1::smallint);
    -- a crítica cujo texto não traz as opções fica como está: só a não crítica ganha as opções no fim
    c_2 := pg_temp.perg('dia_avisado', 'dia_avisado:r3', 'Dia avisado do Flávio (OS-00104).', c_op, null, date '2026-11-12', 'ligado', 1::smallint);
    v := pg_temp.lista(c_d);
    va := pg_temp.lista_antes(pg_temp.em(c_d, '17:40'));
    v_res := pg_temp.ok(v_res, 'R3a as críticas PRIMEIRO, pela perda; depois as outras, pela perda, sem prazo por último',
      (select array_agg(e ->> 'id' order by (e ->> 'n')::int) from jsonb_array_elements(v) e) = array[c_1::text, c_2::text, n_1::text, n_3::text, n_2::text], v::text);
    v_res := pg_temp.ok(v_res, 'R3b para quem já tem crítica aberta, "Decisão 1" e "Decisão 2" são as mesmas de antes do pacote',
      (select count(*) from jsonb_array_elements(va) a join jsonb_array_elements(v) e on e ->> 'id' = a ->> 'id' and e ->> 'n' = a ->> 'n') = 2 and jsonb_array_length(va) = 2, va::text);
    v_t := pg_temp.pendencias(c_d);
    v_res := pg_temp.ok(v_res, 'R3c em *agenda pendências*, a mesma ordem: 5 decisões, a crítica é a 1, e a crítica sem as opções no texto fica byte a byte',
      v_t like '5 decisões esperam você na agenda:%Decisão 1: Não cabe o Nelson.%Decisão 3: Pergunta A?%' and v_t like E'%Decisão 2: Dia avisado do Flávio (OS-00104).\n%', v_t);
    r := pg_temp.responde('1', '2', 'decisão 1, opção 2', c_d);
    v_res := pg_temp.ok(v_res, 'R3d a releitura da crítica diz qual é (correção O18)', r ->> 'releitura' like E'Entendi assim, confere?\n• Decisão: na pergunta "%": Atrasa o Vanderlei.\n%' and pg_temp.rasc_q() = c_1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r3$;

-- ── R4. O "1" ambíguo ────────────────────────────────────────────────────────────────
do $r4$
declare
  v_res jsonb := '[]'::jsonb;
  c_g   constant date := date '2026-10-29';
  c_ag  constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_d   constant date := date '2026-11-05';
  v_a   uuid;
  v_b   uuid;
  v_q   uuid;
  v_c   uuid;
  r     jsonb;
  r2    jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R4 o ambíguo', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A', date '2026-11-06');
    v_b := pg_temp.equipe('B', date '2026-11-07');
    r := pg_temp.responde(null, '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R4a 2 abertas, "1" sem dizer qual: pergunta, com o jeito de responder, e nada no rascunho',
      r ->> 'motivo' = 'decisao_ambigua' and r ->> 'texto' like 'Qual decisão? 1) Pergunta A?%; 2) Pergunta B?%Diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('1', '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R4b "1", e o modelo preenche decisão 1, opção 1: pergunta', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('1', '2', '2', c_d);
    v_res := pg_temp.ok(v_res, 'R4c "2", e o modelo escolhe a decisão 1: pergunta', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('2', '1', '2', c_d);
    v_res := pg_temp.ok(v_res, 'R4d "2", e o modelo inventa a opção 1: pergunta', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('1', '1', 'pode ser', c_d);
    v_res := pg_temp.ok(v_res, 'R4e "pode ser", sem número: pergunta', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('1', null, 'a 1', c_d);
    v_res := pg_temp.ok(v_res, 'R4f a decisão sem a opção: a pergunta volta como está, com as opções, e nada no rascunho',
      r ->> 'motivo' = 'sem_opcao' and r ->> 'texto' like 'Pergunta A?%' and jsonb_array_length(r -> 'opcoes') = 2 and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('1', '9', 'decisão 1, opção 9', c_d);
    v_res := pg_temp.ok(v_res, 'R4g a opção que não existe', r ->> 'motivo' = 'opcao_nao_existe' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('7', '1', 'decisão 7, opção 1', c_d);
    v_res := pg_temp.ok(v_res, 'R4h a decisão que não existe', r ->> 'motivo' = 'decisao_nao_existe' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('2', '1', 'na decisão 2, a opção 1', c_d);
    v_res := pg_temp.ok(v_res, 'R4i com os 2 números ditos, é a pergunta 2, e a releitura diz qual', (r ->> 'ok')::boolean and pg_temp.rasc_q() = v_b and r ->> 'releitura' like '%na pergunta "Pergunta B?%": Está certo.%', r::text);
    r := pg_temp.responde('2', '2', 'na decisão dois, a opção dois', c_d);
    v_res := pg_temp.ok(v_res, 'R4j por extenso, e a resposta nova substitui a de antes: uma linha só no rascunho', (r ->> 'ok')::boolean and pg_temp.rascunhos() = 1 and r ->> 'releitura' like '%: Mudou.%', r::text);
    r := pg_temp.responde('1', '1', '1 1', c_d);
    v_res := pg_temp.ok(v_res, 'R4k "1 1": a decisão 1, a opção 1', (r ->> 'ok')::boolean and pg_temp.rascunhos() = 2, r::text);
    r2 := pg_temp.grava(c_d);
    v_res := pg_temp.ok(v_res, 'R4l o *grava* responde cada uma com a sua opção', pg_temp.est(v_a) = 'respondida:1:whatsapp' and pg_temp.est(v_b) = 'respondida:2:whatsapp', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Pelo nome: só vale com o nome dito
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A');
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    r := pg_temp.responde('Giancarlo', '1', '1', c_g);
    v_res := pg_temp.ok(v_res, 'R4m "1", e o modelo escolhe a decisão pelo nome: pergunta', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('Giancarlo', '1', 'do Giancarlo', c_g);
    v_res := pg_temp.ok(v_res, 'R4n o nome sem a opção nas palavras: pergunta', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('Giancarlo', '1', 'do Giancarlo, a 1', c_g);
    v_res := pg_temp.ok(v_res, 'R4o com o nome dito, é a dele', (r ->> 'ok')::boolean and pg_temp.rasc_q() = v_q, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A opção pelo nome da OS diz por si qual é: não passa pela régua das palavras (a crítica, como sempre foi)
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A');
    v_c := pg_temp.perg('nao_cabe', 'nao_cabe:r4n', 'Não cabe o Giancarlo. 1) Atrasa o Giancarlo; 2) Atrasa o Nelson.',
      jsonb_build_array(jsonb_build_object('n', 1, 'texto', 'Atrasa o Giancarlo', 'os', pg_temp.os('OS-00130')), jsonb_build_object('n', 2, 'texto', 'Atrasa o Nelson', 'os', pg_temp.os('OS-00112'))),
      null, date '2026-11-10', 'ligado', 1::smallint);
    r := pg_temp.responde('1', 'Giancarlo', 'pode atrasar', c_g);
    v_res := pg_temp.ok(v_res, 'R4t "pode atrasar o Giancarlo": a opção pelo nome vale, mesmo com 2 abertas e sem número nas palavras', (r ->> 'ok')::boolean and pg_temp.rasc_q() = v_c and r ->> 'releitura' like E'%• Decisão: na pergunta "%": Atrasa o Giancarlo.\n%', r::text);
    perform public.agenda_rascunho_descartar(pg_temp.adm());
    r := pg_temp.responde(null, 'Giancarlo', 'pode atrasar', c_g);
    v_res := pg_temp.ok(v_res, 'R4u a opção pelo nome, sem dizer a decisão e com 2 abertas: pergunta qual, nada no rascunho, como sempre foi', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A numeração que anda entre ver e responder
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A', date '2026-11-06');
    v_b := pg_temp.equipe('B', date '2026-11-07');
    r := pg_temp.responde('1', '1', 'decisão 1, opção 1', c_d);
    v_res := pg_temp.ok(v_res, 'R4p o rascunho é da pergunta A', pg_temp.rasc_q() = v_a, r::text);
    -- nasce uma crítica: a A vira a decisão 2
    v_c := pg_temp.perg('nao_cabe', 'nao_cabe:r4', 'Não cabe o Nelson. 1) Atrasa o Nelson; 2) Atrasa o Vanderlei.', '[{"n":1,"texto":"Atrasa o Nelson"},{"n":2,"texto":"Atrasa o Vanderlei"}]', null, date '2026-11-10', 'ligado', 1::smallint);
    v_res := pg_temp.ok(v_res, 'R4q a crítica desloca os números', (pg_temp.lista(c_d) -> 0 ->> 'id') = v_c::text and (pg_temp.lista(c_d) -> 1 ->> 'id') = v_a::text, null);
    r2 := pg_temp.grava(c_d);
    v_res := pg_temp.ok(v_res, 'R4r o *grava* vale pela pergunta, não pelo número: a A foi respondida, a crítica não', pg_temp.est(v_a) = 'respondida:1:whatsapp' and pg_temp.est(v_c) = 'aberta:-:-', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A', date '2026-11-06');
    v_b := pg_temp.equipe('B', date '2026-11-07');
    -- o dono viu "Decisão 2 = B"; nasce uma crítica; ele responde "decisão 2": agora é a A, e a releitura diz
    v_c := pg_temp.perg('nao_cabe', 'nao_cabe:r4', 'Não cabe o Nelson. 1) Atrasa o Nelson; 2) Atrasa o Vanderlei.', '[{"n":1,"texto":"Atrasa o Nelson"},{"n":2,"texto":"Atrasa o Vanderlei"}]', null, date '2026-11-10', 'ligado', 1::smallint);
    r := pg_temp.responde('2', '1', 'decisão 2, opção 1', c_d);
    v_res := pg_temp.ok(v_res, 'R4s o número que andou: a releitura mostra de qual pergunta é, e é o dono quem manda *grava*', r ->> 'releitura' like '%na pergunta "Pergunta A?%": Está certo.%' and pg_temp.est(v_a) = 'aberta:-:-', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r4$;

-- ── R5. Quem não ganha número ────────────────────────────────────────────────────────
do $r5$
declare
  v_res jsonb := '[]'::jsonb;
  c_d   constant date := date '2026-11-05';
  v_a   uuid;
  v_b   uuid;
  v_t   text;
  r     jsonb;
  r2    jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R5 quem não ganha número', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- A que venceu, pelo relógio e pelo estado
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A');
    update public.agenda_perguntas set expira_em = pg_temp.em(c_d, '12:00') where id = v_a;
    r := pg_temp.responde('1', '1', 'decisão 1, opção 1', c_d);
    v_res := pg_temp.ok(v_res, 'R5a a que venceu sai da lista, e a resposta diz que não há decisão', jsonb_array_length(pg_temp.lista(c_d)) = 0 and r ->> 'motivo' = 'sem_decisao' and pg_temp.rascunhos() = 0, r::text);
    v_res := pg_temp.ok(v_res, 'R5b antes de vencer, ela estava lá', jsonb_array_length(pg_temp.lista(c_d, '11:59')) = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A');
    r := pg_temp.responde(null, '1', '1', c_d);
    update public.agenda_perguntas set estado = 'vencida' where id = v_a;
    r2 := pg_temp.grava(c_d);
    v_res := pg_temp.ok(v_res, 'R5c venceu entre a releitura e o *grava*: não grava, e a pergunta continua vencida',
      (r ->> 'ok')::boolean and not (r2 ->> 'ok')::boolean and r2 ->> 'texto' like 'Não gravei nada. A agenda mudou desde a releitura: Essa pergunta já foi respondida ou resolvida%' and pg_temp.est(v_a) = 'vencida:-:-', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- A sombra fica de fora, e não conta como esperando
  begin
    perform pg_temp.limpa();
    update public.agenda_config set modo_vigia = 'sombra' where id;
    v_a := pg_temp.perg('equipe_cadastro', 'equipe_cadastro:chamada:S', 'Pergunta S? 1) Está certo; 2) Mudou.', '[{"n":1,"texto":"Está certo","efeito":{"chamada":"ok"}},{"n":2,"texto":"Mudou","efeito":{"chamada":"mudou"}}]', null, null, 'sombra');
    v_t := pg_temp.pendencias(c_d);
    r := pg_temp.responde(null, '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R5d a pergunta em sombra fica de fora: sem número, sem resposta, e o "Em teste" de sempre',
      jsonb_array_length(pg_temp.lista(c_d)) = 0 and r ->> 'motivo' = 'sem_decisao' and v_t like 'Em teste (nada foi perguntado de verdade): eu perguntaria isto.%Pergunta S?%' and v_t not like '%Decisão%', v_t || r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A');
    v_b := pg_temp.perg('equipe_cadastro', 'equipe_cadastro:chamada:S', 'Pergunta S? 1) Está certo; 2) Mudou.', '[{"n":1,"texto":"Está certo","efeito":{"chamada":"ok"}},{"n":2,"texto":"Mudou","efeito":{"chamada":"mudou"}}]', null, null, 'sombra');
    r := pg_temp.responde(null, '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R5e a sombra não atrapalha: "1" vai à única ligada', (r ->> 'ok')::boolean and pg_temp.rasc_q() = v_a, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Sem opções, e com opções de um tipo sem efeito em agenda_decidir
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.perg('equipe_cadastro', 'equipe_cadastro:telefone:x', 'Falta o telefone do Alex: sem ele não mando a ficha.', '[]');
    v_t := pg_temp.pendencias(c_d);
    r := pg_temp.responde(null, '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R5f sem opções segue como está: em "Também quero saber", e "1" não acha decisão',
      jsonb_array_length(pg_temp.lista(c_d)) = 0 and v_t = 'Também quero saber: Falta o telefone do Alex: sem ele não mando a ficha.' and r ->> 'motivo' = 'sem_decisao', v_t || r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.perg('duracao', 'duracao:r5', 'Quantos dias? 1) Dois; 2) Três.', '[{"n":1,"texto":"Dois"},{"n":2,"texto":"Três"}]');
    v_res := pg_temp.ok(v_res, 'R5g tipo com opções e sem efeito em agenda_decidir não entra: a lista é fechada', jsonb_array_length(pg_temp.lista(c_d)) = 0, pg_temp.lista(c_d)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- Quem não conta como "esperando": a de opções que venceu, a sem opções, a fechada
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A');
    v_b := pg_temp.perg('duracao', 'duracao:r5v', 'Quantos dias? 1) Dois; 2) Três.', '[{"n":1,"texto":"Dois"},{"n":2,"texto":"Três"}]');
    update public.agenda_perguntas set expira_em = pg_temp.em(c_d, '12:00') where id = v_b;
    perform pg_temp.perg('padrao_do_dono', 'padrao_do_dono:r5', 'Quais dias da semana você vai?', '[]');
    v_b := pg_temp.perg('duracao', 'duracao:r5f', 'Quantos dias? 1) Dois; 2) Três.', '[{"n":1,"texto":"Dois"},{"n":2,"texto":"Três"}]');
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_b;
    r := pg_temp.responde(null, '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R5m a de opções vencida, a sem opções e a fechada não contam: "1" vai à única que espera', (r ->> 'ok')::boolean and pg_temp.rasc_q() = v_a, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- opcoes que não é lista: o CHECK da coluna impede, e a guarda segura mesmo assim. Tirando o CHECK (e o not null) dentro da subtransação.
  begin
    perform pg_temp.limpa();
    alter table public.agenda_perguntas drop constraint agenda_perguntas_opcoes_check;
    alter table public.agenda_perguntas alter column opcoes drop not null;
    insert into public.agenda_perguntas (tipo, chave, texto, opcoes, modo, criada_em) values
      ('estimativa', 'estimativa:r5:escalar', 'Texto escalar', '"x"'::jsonb, 'ligado', pg_temp.em(c_d, '08:00')),
      ('estimativa', 'estimativa:r5:numero', 'Texto numero', '5'::jsonb, 'ligado', pg_temp.em(c_d, '08:00')),
      ('estimativa', 'estimativa:r5:nulojson', 'Texto nulo json', 'null'::jsonb, 'ligado', pg_temp.em(c_d, '08:00')),
      ('estimativa', 'estimativa:r5:objeto', 'Texto objeto', '{"n":1}'::jsonb, 'ligado', pg_temp.em(c_d, '08:00')),
      ('estimativa', 'estimativa:r5:nulo', 'Texto nulo', null, 'ligado', pg_temp.em(c_d, '08:00'));
    v_res := pg_temp.ok(v_res, 'R5h opcoes escalar, número, nulo em JSON, objeto e nulo: a lista não lança e não os leva', jsonb_array_length(pg_temp.lista(c_d)) = 0, pg_temp.lista(c_d)::text);
    v_t := pg_temp.pendencias(c_d);
    v_res := pg_temp.ok(v_res, 'R5i ficam em "Também quero saber", como antes', (select count(*) from regexp_matches(v_t, 'Também quero saber: Texto', 'g')) = 5, v_t);
    r := pg_temp.responde(null, '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R5j "1" não lança: não conta como pergunta com opções', r ->> 'motivo' = 'sem_decisao', r::text);
    v_a := pg_temp.equipe('A');
    r := pg_temp.responde(null, '1', '1', c_d);
    v_res := pg_temp.ok(v_res, 'R5k ao lado delas, a boa tem número 1 e responde sozinha', (pg_temp.lista(c_d) -> 0 ->> 'id') = v_a::text and jsonb_array_length(pg_temp.lista(c_d)) = 1 and (r ->> 'ok')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R5l o CHECK e o not null da coluna voltaram (o que o caso acima desfez)',
    exists (select 1 from pg_constraint c where c.conrelid = 'public.agenda_perguntas'::regclass and c.conname = 'agenda_perguntas_opcoes_check')
    and (select a.attnotnull from pg_attribute a where a.attrelid = 'public.agenda_perguntas'::regclass and a.attname = 'opcoes'), null);
  perform pg_temp.gravar(v_res);
end
$r5$;

-- ── R6. O freio ──────────────────────────────────────────────────────────────────────
do $r6$
declare
  v_res jsonb := '[]'::jsonb;
  c_g   constant date := date '2026-10-29';
  c_ag  constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_ops constant jsonb := '[{"n":1,"texto":"Fique com 2 dias","efeito":{"manter":true}},{"n":2,"texto":"Use 3 dias","efeito":{"dias":3}}]';
  v_q   uuid;
  v_a   uuid;
  v_pl  text;
  v_dia text;
  r     jsonb;
  r2    jsonb;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R6 o freio', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- A estimativa com o freio: tem número, e a resposta é recusada na hora
  begin
    perform pg_temp.limpa();
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    update public.agenda_config set gestor_so_propor = true where id;
    v_pl := pg_temp.plano();
    v_dia := pg_temp.os_pl(pg_temp.os('OS-00130'));
    v_res := pg_temp.ok(v_res, 'R6a com o freio, q.modo = ligado continua: a estimativa tem número', pg_temp.pendencias(c_g, '17:00') like '%Decisão 1: Giancarlo%', null);
    r := pg_temp.responde(null, '1', '1', c_g, '17:01');
    v_res := pg_temp.ok(v_res, 'R6b a opção com os dias é recusada na hora, com o porquê, sem rascunho e sem "a agenda mudou"',
      r ->> 'motivo' = 'em_teste' and r ->> 'texto' = 'Com *gestor, só propor* essa resposta não muda nada agora. Se quiser, me diga com as suas palavras (por exemplo, os dias do serviço).' and pg_temp.rascunhos() = 0, r::text);
    v_res := pg_temp.ok(v_res, 'R6c nada mudou: nem os dias, nem o plano, nem a pergunta', pg_temp.os_pl(pg_temp.os('OS-00130')) = v_dia and pg_temp.plano() = v_pl and pg_temp.est(v_q) = 'aberta:-:-', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- O rascunho de antes do freio: o *grava* depois dele é recusado por agenda_decidir, como sempre
  begin
    perform pg_temp.limpa();
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    r := pg_temp.responde(null, '1', '1', c_g, '17:01');
    update public.agenda_config set gestor_so_propor = true where id;
    v_pl := pg_temp.plano();
    v_dia := pg_temp.os_pl(pg_temp.os('OS-00130'));
    r2 := pg_temp.grava(c_g, '17:02');
    v_res := pg_temp.ok(v_res, 'R6d o rascunho feito antes do freio: o *grava* não passa, e nada mudou',
      (r ->> 'ok')::boolean and not (r2 ->> 'ok')::boolean and r2 ->> 'texto' like '%O gestor da agenda está em teste%' and pg_temp.os_pl(pg_temp.os('OS-00130')) = v_dia and pg_temp.plano() = v_pl and pg_temp.est(v_q) = 'aberta:-:-', r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- A reestimar é a única resposta não crítica que marca dia (a opção 2 acompanha o plano): com o freio, não passa; a situacao e a reavaliar, idem
  begin
    perform pg_temp.limpa();
    update public.agenda_config set gestor_so_propor = true where id;
    v_pl := pg_temp.plano();
    v_q := pg_temp.perg('reestimar', 'reestimar:freio', 'Nelson (OS-00112): o orçamento mudou. 1) Fique com 2 dias (recomendo); 2) Use 3 dias.', c_ops, pg_temp.os('OS-00112'));
    r := pg_temp.responde(null, '2', '2', c_g);
    v_res := pg_temp.ok(v_res, 'R6e a reestimar com o freio: recusada, sem rascunho, o plano igual', r ->> 'texto' like 'Com *gestor, só propor*%' and pg_temp.rascunhos() = 0 and pg_temp.plano() = v_pl and pg_temp.est(v_q) = 'aberta:-:-', r::text);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_q;
    v_q := pg_temp.perg('reavaliar', 'reavaliar:freio', 'O diagnóstico foi feito. 1) Terminou; 2) Achou mais serviço.', '[{"n":1,"texto":"Terminou","efeito":{"terminou":true}},{"n":2,"texto":"Achou mais","efeito":{"dizer":true}}]', pg_temp.os('OS-00096'));
    r := pg_temp.responde(null, '2', '2', c_g);
    v_res := pg_temp.ok(v_res, 'R6f a reavaliar com o freio: recusada', r ->> 'texto' like 'Com *gestor, só propor*%' and pg_temp.rascunhos() = 0, r::text);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_q;
    update public.agenda_config set gestor_so_propor = false where id;
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00112'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    update public.agenda_config set gestor_so_propor = true where id;
    r := pg_temp.responde(null, '1', '1', c_g, '17:01');
    v_res := pg_temp.ok(v_res, 'R6g a situacao com o freio: recusada', r ->> 'texto' like 'Com *gestor, só propor*%' and pg_temp.rascunhos() = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- Quem não é do gestor segue respondendo com o freio, e não mexe no plano
  begin
    perform pg_temp.limpa();
    update public.agenda_config set gestor_so_propor = true where id;
    v_pl := pg_temp.plano();
    v_a := pg_temp.equipe('A');
    r := pg_temp.responde(null, '1', '1', c_g);
    r2 := pg_temp.grava(c_g);
    v_res := pg_temp.ok(v_res, 'R6h a chamada com o freio responde, como hoje, e o plano fica igual', r2 ->> 'texto' like '%Anotei: sigo com a equipe que tenho.%' and pg_temp.est(v_a) = 'respondida:1:whatsapp' and pg_temp.plano() = v_pl, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- A crítica do gestor (a onda) não passa pela recusa nova: com o freio, como antes (rascunho, e o *grava* recusa)
  begin
    perform pg_temp.limpa();
    update public.agenda_config set gestor_so_propor = true where id;
    v_pl := pg_temp.plano();
    v_q := pg_temp.perg('onda', 'onda:r6', 'Muita mudança. 1) Tudo; 2) Só hoje; 3) Nada.', '[{"n":1,"texto":"Tudo","efeito":{"aplicar":"tudo"}},{"n":2,"texto":"Só hoje","efeito":{"aplicar":"so_evento_real"}},{"n":3,"texto":"Nada","efeito":{"aplicar":"nada"}}]', null, null, 'ligado', 3::smallint);
    r := pg_temp.responde(null, '1', '1', c_g);
    r2 := pg_temp.grava(c_g);
    v_res := pg_temp.ok(v_res, 'R6i a crítica com o freio é a de antes: o rascunho nasce, o *grava* não passa, o plano fica igual',
      (r ->> 'ok')::boolean and r ->> 'releitura' like E'%• Decisão: na pergunta "Muita mudança%": Tudo.\n%' and not (r2 ->> 'ok')::boolean and pg_temp.plano() = v_pl, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- Fora do freio, o modo em teste: a frase é outra
  begin
    perform pg_temp.limpa();
    v_q := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    update public.agenda_config set modo_marcar_sozinho = 'sombra' where id;
    r := pg_temp.responde(null, '1', '1', c_g, '17:01');
    v_res := pg_temp.ok(v_res, 'R6j a pergunta ligada com o modo que voltou a teste: "ainda está em teste", sem rascunho',
      r ->> 'motivo' = 'em_teste' and r ->> 'texto' = 'Essa pergunta ainda está em teste: mostro como ficaria, mas não mudo nada.' and pg_temp.rascunhos() = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r6$;

-- ── R7. A tela e as cobranças ────────────────────────────────────────────────────────
do $r7$
declare
  v_res jsonb := '[]'::jsonb;
  c_d   constant date := date '2026-11-05';
  v_a   uuid;
  v_c   uuid;
  v_id  uuid;
  r     jsonb;
  v_t   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R7 a tela', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.limpa();
    v_a := pg_temp.equipe('A');
    v_c := pg_temp.perg('nao_cabe', 'nao_cabe:r7', 'Não cabe o Nelson. 1) Atrasa o Nelson; 2) Atrasa o Vanderlei.', '[{"n":1,"texto":"Atrasa o Nelson"},{"n":2,"texto":"Atrasa o Vanderlei"}]', null, date '2026-11-10', 'ligado', 1::smallint);
    r := public.agenda_tela_semana(date '2026-11-02', c_d, pg_temp.em(c_d, '17:40'));
    v_res := pg_temp.ok(v_res, 'R7a a tela leva a crítica e a outra, pelo mesmo número, com o jeito de responder de sempre, sem nada que diga "crítica"',
      jsonb_array_length(r -> 'decisoes') = 2 and r #>> '{decisoes,0,texto}' = 'Decisão 1: Não cabe o Nelson. 1) Atrasa o Nelson; 2) Atrasa o Vanderlei.'
      and r #>> '{decisoes,1,texto}' = 'Decisão 2: Pergunta A? 1) Está certo (recomendo); 2) Mudou.' and r #>> '{decisoes,1,pergunta_id}' = v_a::text
      and r ->> 'como_responder' = 'Responda no WhatsApp: diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2").' and (r -> 'decisoes')::text not like '%ríti%', (r -> 'decisoes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- A cobrança que manda responder em *agenda pendências* (a linha do contato no fechamento) agora é verdade, sem texto novo
  begin
    perform pg_temp.limpa();
    perform pg_temp.equipe_toda();
    perform pg_temp.limpa();
    v_id := pg_temp.pessoa('Bruno');
    update public.agenda_config set modo_dias = 'desligado' where id;
    perform pg_temp.semana(c_d, '16:45');
    select string_agg(l ->> 'texto', ' / ') into v_t from jsonb_array_elements(public._agenda_linhas_do_fechamento(c_d)) l;
    v_res := pg_temp.ok(v_res, 'R7b a linha da equipe manda responder em *agenda pendências*, e o que ela chama tem número lá',
      v_t like '%Bruno tem telefone%' and v_t like '%*agenda pendências*%' and pg_temp.pendencias(c_d) like '%Decisão %: Bruno tem telefone%', v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r7$;

-- ── R8. As 3 perguntas reais de produção (05/11; sql/wf7dd_a91_textos), com os textos e as opções delas ─────
do $r8$
declare
  v_res jsonb := '[]'::jsonb;
  c_g    constant date := date '2026-10-29';
  c_ag   constant timestamptz := timestamptz '2026-10-29 16:52-03';
  c_est  constant text := 'Giancarlo (OS-00130): pelo valor do orçamento são 10 diárias (10 dias com 1 pessoa). É mais de 8 diárias: não marco sozinho. Me diga os dias. 1) Marque 10 dias; 2) Eu digo os dias (recomendo); 3) Já terminou (ou já entreguei).';
  c_cha  constant text := 'Na agenda conto com Alex: você disse todo dia útil. Alex não tem telefone no cadastro: sem ele não mando a ficha; para pôr, diga: o telefone do Alex é … Quem você chama quando precisa eu só conto nos dias que você disser (ex.: Mateus vem qua e qui). Roberto e João saíram da agenda em 30/10: não conto com eles. Está certo? 1) Está certo (recomendo); 2) Mudou. Se não responder em 3 dias úteis depois de ver, sigo assim.';
  c_nfe  constant text := 'Chegou por e-mail a nota 495411 da Tamoyo (SC, sem cadastro), despachada sáb 31/10: deve chegar por volta de ter 03/11. É material de qual serviço? 1) Vanderlei: Porta Fusível MIDI…; 2) nenhum (estoque ou escritório). Me diga o número ou o nome.';
  v_e    uuid;
  v_c    uuid;
  v_n    uuid;
  r      jsonb;
  r2     jsonb;
  v_t    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R8 as reais', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.limpa();
    v_e := (public._agenda_gestor_perguntas_da_os(pg_temp.os('OS-00130'), c_g, c_ag, false) ->> 'pergunta_id')::uuid;
    v_c := pg_temp.perg('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-02', c_cha, '[{"efeito":{"chamada":"ok"},"n":1,"texto":"Está certo"},{"efeito":{"chamada":"mudou"},"n":2,"texto":"Mudou"}]', null, null, 'ligado', 1::smallint);
    v_n := pg_temp.nfe(pg_temp.os('OS-00069'));
    v_t := pg_temp.pendencias(c_g, '17:40');
    v_res := pg_temp.ok(v_res, 'R8a a estimativa real é a do gerador, byte a byte', (select q.texto from public.agenda_perguntas q where q.id = v_e) = c_est, null);
    v_res := pg_temp.ok(v_res, 'R8b *agenda pendências* com as 3: a estimativa é a 1, a chamada é a 2, a nota segue sem número, byte a byte',
      v_t = '2 decisões esperam você na agenda:' || E'\n' || 'Decisão 1: ' || c_est || E'\n' || 'Decisão 2: ' || c_cha || E'\n'
            || 'Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.' || E'\n' || '(e mais 1 linha)', v_t);
    v_res := pg_temp.ok(v_res, 'R8c a nota foi cortada pelo teto de 1.000 letras, como antes do pacote: ela continua nos dados e na resposta ao "1"',
      (public._agenda_ver_decisoes(c_g, pg_temp.em(c_g, '17:40')) #>> '{dados,outras}')::int = 1, null);
    r := pg_temp.responde(null, '1', '1', c_g, '17:41');
    v_res := pg_temp.ok(v_res, 'R8d "1" sozinho com as 3: pergunta qual, e a nota vem junto', r ->> 'motivo' = 'decisao_ambigua' and r ->> 'texto' like '%' || c_nfe and pg_temp.rascunhos() = 0, r::text);
    r := pg_temp.responde('2', '1', 'decisão 2, opção 1', c_g, '17:41');
    r2 := pg_temp.grava(c_g);
    v_res := pg_temp.ok(v_res, 'R8e a chamada, opção 1: sigo com a equipe', r2 ->> 'texto' like '%Anotei: sigo com a equipe que tenho.%' and pg_temp.est(v_c) = 'respondida:1:whatsapp' and pg_temp.est(v_e) = 'aberta:-:-', r2::text);
    r := pg_temp.responde(null, '2', 'a 2', c_g, '17:43');
    v_res := pg_temp.ok(v_res, 'R8f depois da chamada, sobram a estimativa e a nota: "a 2" ainda pergunta qual', r ->> 'motivo' = 'decisao_ambigua' and pg_temp.rascunhos() = 0, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$r8$;

select teste, ok, detalhe from _resultado order by teste;
rollback;
