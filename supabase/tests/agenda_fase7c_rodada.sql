-- Prova da rodada diária de quem faz o quê da Agenda de Produção, Fase 7c (pacote P5): a proposta pelo histórico e pelo técnico que o
-- dono declarou, a pergunta da equipe (o texto, o modo, uma aberta, refeita quando muda), o prazo de veto contado de quando ela foi vista,
-- a conferência em teste do publicado, a pergunta por OS, as medidas, a rodada uma vez por dia e a linha (n) do fechamento com a pergunta
-- de quem faz o quê — o portão separado por etapa, o "Também" fora do registro e o prazo na forma curta (migration 20261102100400;
-- spec-fase7c §5.5, §6.4–§6.6, §8.3 agenda_fase7c_rodada.sql, R5.1-6, R5.4 item 4, R5.7-1/-7, R5.10-6/-7/-8).
-- bancada: depende de 20261102100400
--
--   R0  as portas: a rodada só do service_role; as medidas do painel (admin/financeiro, conferido dentro) e do service_role, definer; os
--       passos e o texto da pergunta sem grant a ninguém; a recriada com as de antes; o anon e a técnica logada não chegam
--   R1real a equipe real (só o Alex e o dono): a proposta é "Alex instala sozinho" (o técnico declarado), mais ninguém; o texto da pergunta
--       é o do R5.1-6, byte a byte, ligado; a proposta não vale antes do prazo (o Alex continua "pode tudo, menos comissionar (padrão)")
--   R1  a sintética: Alex instala 2 (declarado), Roberto instala 2 (33 diárias desde 23/08), João ajudante 2, Bruno ajudante 1 (o novato),
--       Rafael ajudante 2 (sem diária); o Mateus com datas (sob demanda) e o Mickael (fora da grade) nada; as evidências
--   R1b o Mateus cadastrado agora com "toda terça" dita pelo dono: com um perfil de hoje é o novato (ajudante 1, nunca instala); sem perfil,
--       nada (o papel novo já o protege)
--   R2  a pergunta: o texto da sintética byte a byte; em teste nasce em teste (a linha do fechamento só no detalhe); uma aberta; a rodada
--       de novo sem mudança não refaz; refeita quando o dono diz outra coisa antes de ver e quando o modo muda; sem proposta viva, sai
--   R2c com o Secretário cheio: a forma curta da linha (n) diz o que foi marcado e o prazo, conta como vista, e o veto_ate gravado depois é
--       a data do texto; como "Também" (com uma pergunta da 7b na frente), não conta
--   R2d o portão da (n): com a 7b desligada e a 7c em teste, a chamada da 7a fica na pergunta de fato (e), perda 30
--   R2e desligado = antes: com os modos da 7c desligados, a saída inteira de _agenda_linhas_do_fechamento é a da 20261101100860 (rodada como
--       pg_temp), com a 7b desligada e em teste, com e sem as perguntas de fornecedor abertas e nunca vistas; em teste, as linhas ligadas
--       são as de antes (só nasce linha de sombra)
--   R3  o prazo: a pergunta mostrada ter 03/11 às 17:30 ganha o prazo de qua 04/11 18:00 na rodada de qua (e não vale ainda); na de qui
--       05/11, as propostas valem, a pergunta fecha e sai a ação da §6.5; a nunca mostrada nunca vale; mostrar de novo não adia
--   R4  o que o dono disse não é proposto por cima (a etiqueta do dono em instala ou ajudante)
--   R5  a conferência em teste: as ações de teste com os textos da §6.6 (o meio-dia sem quem o serviço pede, com quem eu poria e sem
--       ninguém; o novo sozinho; o responsável fixo); sem repetir no dia; no máximo 6 por dia
--   R6  a pergunta por OS (só ligado): a OS de fora por falta de quem comissiona ganha a pergunta da §6.4; fecha quando volta a caber
--   R7  as medidas: dono_em_tarefa_de_outro = 3 (os 3 meios-dias do dono numa OS de 12 V com o Roberto livre); sozinho_em_risco com a 179
--   R8  a rodada: antes da hora (cedo), uma vez por dia (ja_rodou), a linha da rotina habilidade, o passo que falha registra e segue, com
--       tudo desligado só o prazo e a medida rodam, e nenhuma mensagem nova a ninguém
--   R9  a cópia: tirados os blocos "-- FASE 7c:" e as marcas "-- (7c …)", _agenda_linhas_do_fechamento viva e a da migration são a da
--       20261101100860, com 4 blocos e 3 marcas
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7c_rodada.sql
--   Seguro em produção: termina em ROLLBACK. R0 roda em qualquer banco; R9 sai PULADO sem as migrations como texto; o resto usa as
--   fixtures e só roda na bancada (fora dela sai PULADO).
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
-- O texto sem os blocos "-- FASE 7c: … -- FASE 7c: fim" e sem as marcas de dentro "-- (7c … -- (7c: fim)" (as linhas de abrir e de
-- fechar saem junto).
create function pg_temp.sem_7c(p text) returns text language sql immutable as $f$
  select array_to_string(array(
           select l from (select l, o, sum(case when (l ~ '^\s*-- FASE 7c:' and l !~ '^\s*-- FASE 7c: fim')
                                                     or (l ~ '^\s*-- \(7c ' and l !~ '^\s*-- \(7c: fim\)') then 1
                                                when l ~ '^\s*-- (FASE 7c: fim|\(7c: fim\))' then -1 else 0 end)
                                       over (order by o rows between unbounded preceding and current row) as dentro,
                                 l ~ '^\s*-- (FASE 7c: fim|\(7c: fim\))' as fecha
                            from unnest(string_to_array(replace(p, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
            where dentro = 0 and not fecha order by o), E'\n')
$f$;
-- FASE 7c: (correção da revisão, 20261102100580) o texto sem os blocos ("-- FASE 7c: (7c correção … -- FASE 7c: fim") e as marcas
-- ("-- (7c correção … -- (7c: fim)") da correção, para o R9 conferir a viva contra a do P8
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

-- ── R0. As portas (sem fixture) ────────────────────────────────────────────────────────────────────────────────
with f(sig, quem, definer, vol) as (values
  ('public.agenda_habilidade(date, timestamptz)', 'servico', true, 'v'),
  ('public.agenda_habilidade_medidas(date, date, date)', 'leitura', true, 's'),
  ('public._agenda_habilidade_propor(date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_habilidade_vetos(date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_habilidade_conferir(date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_habilidade_perguntas_os(date, timestamptz)', 'ninguem', true, 'v'),
  ('public._agenda_habilidade_pergunta_texto(date, uuid[])', 'ninguem', false, 's'),
  ('public._agenda_linhas_do_fechamento(date)', 'leitura', false, 's'))
insert into _resultado
select 'R0a as 7 novas e a recriada com as portas certas (a rodada só do service_role; as medidas e a linha do fechamento do painel e do service_role; os passos e o texto de ninguém, nem service_role; nunca anon; search_path fixo; os passos e a rodada definer, como as medidas)',
       count(p.oid) = 8
       and bool_and(p.prosecdef = f.definer and p.provolatile = f.vol and array_to_string(p.proconfig, ',') like '%search_path=public%'
                    and not has_function_privilege('anon', p.oid, 'execute')
                    and case f.quem
                          when 'servico' then not has_function_privilege('authenticated', p.oid, 'execute')
                                              and has_function_privilege('service_role', p.oid, 'execute')
                          when 'leitura' then has_function_privilege('authenticated', p.oid, 'execute')
                                              and has_function_privilege('service_role', p.oid, 'execute')
                          else not has_function_privilege('authenticated', p.oid, 'execute')
                               and not has_function_privilege('service_role', p.oid, 'execute') end),
       string_agg(format('%s def=%s vol=%s anon=%s auth=%s srv=%s', f.sig, p.prosecdef, p.provolatile,
                         has_function_privilege('anon', p.oid, 'execute'), has_function_privilege('authenticated', p.oid, 'execute'),
                         has_function_privilege('service_role', p.oid, 'execute')), '; ')
  from f left join pg_proc p on p.oid = to_regprocedure(f.sig);
insert into _resultado
select 'R0b o anon não chama a rodada nem as medidas; a técnica logada (login que não é admin nem financeiro) não lê as medidas (42501)',
       pg_temp.como(null, 'anon', 'select public.agenda_habilidade(date ''2026-11-04'', timestamptz ''2026-11-04 16:15-03'')::text') like 'erro 42501%'
       and pg_temp.como(null, 'anon', 'select public.agenda_habilidade_medidas(date ''2026-10-05'', date ''2026-11-04'', date ''2026-11-04'')::text') like 'erro 42501%'
       and pg_temp.como('c7c00000-0000-4000-8000-0000000ec005', 'authenticated',
                        'select public.agenda_habilidade_medidas(date ''2026-10-05'', date ''2026-11-04'', date ''2026-11-04'')::text')
           = 'erro 42501: As medidas de quem faz o quê são com o administrador ou o financeiro.'
       and pg_temp.como('c7c00000-0000-4000-8000-0000000ec005', 'authenticated',
                        'select public.agenda_habilidade(date ''2026-11-04'', timestamptz ''2026-11-04 16:15-03'')::text') like 'erro 42501%',
       pg_temp.como('c7c00000-0000-4000-8000-0000000ec005', 'authenticated',
                    'select public.agenda_habilidade_medidas(date ''2026-10-05'', date ''2026-11-04'', date ''2026-11-04'')::text');

-- ── R9. A cópia (só com as migrations como texto) ───────────────────────────────────────────────────────────────
do $r9$
declare
  v_res  jsonb := '[]'::jsonb;
  v_mig  text := coalesce(current_setting('agenda_teste.mig_correcao3_fase7b', true), '');
  v_esta text := coalesce(current_setting('agenda_teste.mig_rodada_fase7c', true), '');
  v_novo text;
  v_fonte text;
  v_da_mig text;
begin
  if v_mig = '' or v_esta = '' then
    insert into _resultado values ('R9 a cópia de _agenda_linhas_do_fechamento', true,
      'PULADO: sem agenda_teste.mig_correcao3_fase7b e agenda_teste.mig_rodada_fase7c (rode pela bancada)');
    return;
  end if;
  v_fonte := pg_temp.corpo(v_mig, '_agenda_linhas_do_fechamento');
  v_da_mig := pg_temp.corpo(v_esta, '_agenda_linhas_do_fechamento');
  select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = 'public._agenda_linhas_do_fechamento(date)'::regprocedure;
  -- FASE 7c: (correção da revisão, 20261102100580) a correção recria o fechamento só com acréscimos (1 bloco no declare, 1 antes do
  -- return e 2 marcas na linha (n): o K0 de agenda_fase77c_correcao.sql confere): a viva sem eles é a do P8
  v_novo := pg_temp.sem_corr(v_novo);
  -- FASE 7c: fim
  v_res := pg_temp.ok(v_res, 'R9 _agenda_linhas_do_fechamento viva e a da migration: tirados os 4 blocos "-- FASE 7c:" e as 3 marcas de dentro "-- (7c …" (só inserções), são o corpo da 20261101100860, byte a byte',
    v_fonte <> '' and pg_temp.sem_7c(v_novo) = v_fonte and pg_temp.sem_7c(v_da_mig) = v_fonte
    -- FASE 7c: (7c P8, 20261102100550) o P8 recria o fechamento (+ 4 blocos e 2 marcas: as perguntas das etapas na (n), a (e) e a linha
    -- (o)): a viva é a do P8, com 8 blocos e 5 marcas; tirados todos os da 7c, a 20261101100860 (agenda_fase7c_tarefas.sql T18 confere)
    and (v_novo = v_da_mig
         or (exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_tarefas'
                     and not a.attisdropped)
             and v_novo = pg_temp.corpo(coalesce(current_setting('agenda_teste.mig_tarefas_fase7c', true), ''), '_agenda_linhas_do_fechamento')))
    and (select count(*) from regexp_matches(v_novo, '-- FASE 7c: fim', 'g')) = 4 + case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_tarefas'
                     and not a.attisdropped) then 4 else 0 end
    and (select count(*) from regexp_matches(v_novo, '-- \(7c: fim\)', 'g')) = 3 + case when exists (select 1 from pg_attribute a where a.attrelid = 'public.agenda_config'::regclass and a.attname = 'modo_tarefas'
                     and not a.attisdropped) then 2 else 0 end,
    -- FASE 7c: fim
    format('fonte %s letras; viva sem a 7c %s; blocos %s; marcas %s', length(v_fonte), length(pg_temp.sem_7c(v_novo)),
           (select count(*) from regexp_matches(v_novo, '-- FASE 7c: fim', 'g')),
           (select count(*) from regexp_matches(v_novo, '-- \(7c: fim\)', 'g'))));
  perform pg_temp.gravar(v_res);
end
$r9$;

-- ── As fixtures e os ajudantes ─────────────────────────────────────────────────────────────────────────────────
create function pg_temp.na_bancada() returns boolean language sql stable as $f$
  select coalesce(current_setting('agenda_teste.fase7c', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7b', true), '') <> ''
     and coalesce(current_setting('agenda_teste.fase7a', true), '') <> ''
     and coalesce(current_setting('agenda_teste.replay2910', true), '') <> ''
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
create function pg_temp.modos7b(p_modo text) returns void language sql as $f$
  update public.agenda_config set modo_dias = p_modo, modo_dupla = p_modo, modo_sabado = p_modo, modo_cadastro = p_modo,
                                  modo_chamar = p_modo where id
$f$;
create function pg_temp.modos7c(p_hab text, p_lid text, p_prop text) returns void language sql as $f$
  update public.agenda_config set modo_habilidade = p_hab, modo_lider = p_lid, modo_habilidade_propor = p_prop where id
$f$;
create function pg_temp.nao_vem(p_nome text, p_de date, p_ate date) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(p_de, p_ate, '[]'), null, 'indisponivel', 'dono', 'não vem (teste)', timestamptz '2026-11-04 10:01-03'
    from public.payees p where p.name = p_nome and p.active
$f$;
create function pg_temp.vem(p_nome text, p_dias date[]) returns void language sql as $f$
  insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_em)
  select p.id, daterange(d, d, '[]'), null, 'disponivel', 'dono', 'Você disse que vem (sob demanda)', timestamptz '2026-11-04 10:00-03'
    from public.payees p, unnest(p_dias) d where p.name = p_nome and p.active
$f$;
-- uma alocação publicada (o plano que já existia), de turno, como o motor publica
create function pg_temp.publicar(p_numero text, p_nome text, p_dia date, p_turno text, p_presenca text default 'turno') returns void
language plpgsql as $f$
begin
  perform set_config('agenda.hoje', '2026-11-04', true);
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  values (pg_temp.os(p_numero), case when p_nome = 'dono' then public._agenda_dono(null) else pg_temp.pessoa(p_nome) end, p_dia,
          p_turno, p_presenca, 'execucao', 'publicada', 'motor', timestamptz '2026-11-02 16:30-03');
end $f$;
-- as propostas vivas do gestor: "Alex instala 2 · Bruno ajudante 1 · …" (pelo nome)
create function pg_temp.propostas() returns text language sql stable as $f$
  select coalesce(string_agg(format('%s %s %s', public._agenda_nome_curto(py.name), e.etiqueta, e.nivel), ' · '
                             order by public._agenda_nome_curto(py.name), e.etiqueta), '-')
    from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
   where e.origem = 'gestor' and e.estado = 'proposta'
$f$;
create function pg_temp.pergunta_aberta() returns public.agenda_perguntas language sql stable as $f$
  select q.* from public.agenda_perguntas q
   where q.tipo = 'habilidade' and q.chave like 'habilidade:equipe:%' and q.estado = 'aberta'
   order by q.criada_em desc, q.id desc limit 1
$f$;
-- a linha (n) do fechamento com a pergunta da equipe, no modo pedido
create function pg_temp.linha_n(p_dia date, p_modo text default 'ligado') returns jsonb language sql stable as $f$
  select l from jsonb_array_elements(public._agenda_linhas_do_fechamento(p_dia)) l
   where l ->> 'tipo' = 'pergunta' and l ->> 'modo' = p_modo and l ->> 'texto' like '%quem faz o quê%' limit 1
$f$;
-- o fechamento mostrou estas linhas (o registro do Secretário depois de enviado)
create function pg_temp.registrar(p_dia date, p_hora text, p_linhas jsonb) returns jsonb language sql as $f$
  select public.agenda_fechamento_registrar(p_dia,
           (select jsonb_agg(jsonb_build_object('pergunta_id', l -> 'pergunta_id', 'acao_ids', coalesce(l -> 'acao_ids', '[]'::jsonb))
                             || case when jsonb_typeof(l -> 'pergunta_ids') = 'array' then jsonb_build_object('pergunta_ids', l -> 'pergunta_ids')
                                     else '{}'::jsonb end)
              from jsonb_array_elements(p_linhas) l),
           'fechamento', pg_temp.em(p_dia, p_hora))
$f$;

-- O texto literal do R5.1-6 (a equipe de hoje).
create function pg_temp.texto_real() returns text language sql immutable as $f$
  select 'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: Alex instala sozinho, também com 220 V ou banco de bateria, e sobe no teto (você disse que ele vem todo dia útil). Comissionar Victron fica com você. Se você não responder até as 18:00 do próximo dia útil depois de ver esta pergunta, fica assim. Para corrigir, me diga numa frase (ex.: "o Alex não sobe no teto" ou "o Alex é ajudante").'
$f$;
-- O texto da sintética (as 5 propostas: encolhe para o rótulo curto e cabe em 600)
create function pg_temp.texto_sintetica() returns text language sql immutable as $f$
  select 'Para não mandar ninguém sozinho em serviço de risco, marquei quem faz o quê: Alex instala sozinho (você disse que ele vem todo dia útil); Roberto instala sozinho (33 diárias desde 23/08); João é ajudante (entrou em 29/09, 15 diárias); Rafael é ajudante (entrou em 01/09, ainda sem diária); Bruno é novo (começou em 20/10, 3 diárias). Comissionar Victron fica com você. Se você não responder até as 18:00 do próximo dia útil depois de ver esta pergunta, fica assim. Para corrigir, me diga numa frase (ex.: "o João instala sozinho" ou "o Alex não sobe no teto").'
$f$;

-- ── R1real. A equipe real (só o Alex e o dono; antes da sintética: a variante é escolhida quando a 7b carrega) ───────────────
do $r1real$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  q     public.agenda_perguntas;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
begin
  if not pg_temp.na_bancada() or exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    insert into _resultado values ('R1real a equipe real', true, 'PULADO: sem as fixtures da 7b e da 7c (rode pela bancada)');
    return;
  end if;
  begin
    perform set_config('agenda_teste.fase7b_equipe', 'real', true);
    execute current_setting('agenda_teste.fase7c');
    perform set_config('agenda_teste.fase7b_equipe', '', true);
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t1 := pg_temp.propostas();
    t2 := (select e.motivo || ' ' || (e.evidencia ->> 'declarado') || ' ' || (e.evidencia -> 'dias')::text
             from public.agenda_etiquetas e where e.payee_id = pg_temp.pessoa('Alex') and e.estado = 'proposta');
    q := pg_temp.pergunta_aberta();
    t3 := q.modo || ' | ' || q.chave || ' | ' || coalesce(q.veto_ate::text, 'sem prazo') || ' | ' || q.texto;
    t4 := (select h.texto from public.agenda_habilidades(date '2026-11-04', array[pg_temp.pessoa('Alex')]) h);
    t5 := (v ->> 'pessoas') || ' ' || jsonb_array_length(v -> 'propostas');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform set_config('agenda_teste.fase7b_equipe', '', true);
  v_res := pg_temp.ok(v_res, 'R1real a equipe real (só o Alex e o dono): uma pessoa na população, uma proposta — Alex instala 2, pelo técnico que o dono declarou ("você disse que ele vem todo dia útil"; evidência declarado, os dias seg a sex) — e mais ninguém',
    t1 = 'Alex instala 2' and t2 = 'você disse que ele vem todo dia útil true [1, 2, 3, 4, 5]' and t5 = '1 1', concat_ws(' | ', t1, t2, t5));
  v_res := pg_temp.ok(v_res, 'R1real a pergunta da equipe real: ligada, habilidade:equipe:2026-11-04, sem prazo antes de ser vista, e o texto do R5.1-6 byte a byte (sem data: o prazo só existe depois de vista)',
    t3 = 'ligado | habilidade:equipe:2026-11-04 | sem prazo | ' || pg_temp.texto_real(), t3);
  v_res := pg_temp.ok(v_res, 'R1real a proposta não vale antes do prazo: o Alex continua "pode tudo, menos comissionar (padrão)" (agenda_habilidades)',
    t4 = 'Alex: pode tudo, menos comissionar (padrão).', t4);
  perform pg_temp.gravar(v_res);
end
$r1real$;

-- A sintética, sem etiquetas (os R começam sem nenhuma), uma vez; cada caso abaixo roda numa subtransação desfeita.
do $carga$
begin
  if not pg_temp.na_bancada() then
    return;
  end if;
  execute current_setting('agenda_teste.fase7c');
end
$carga$;
create function pg_temp.carregada() returns boolean language sql stable as $f$
  select exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97171')
     and exists (select 1 from public.service_orders so where so.service_order_number = 'OS-97101')
$f$;
create function pg_temp.gestor(p_modo text) returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = p_modo, modo_encaixe_aprovacao = p_modo, modo_revisao_diaria = p_modo, modo_compre_ate = p_modo,
         modo_vaga_fechamento = p_modo, gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = case when p_modo = 'ligado' then timestamptz '2026-10-29 16:46-03' end, modo_proposta = 'ligado'
   where id
$f$;

-- A definição de antes de _agenda_linhas_do_fechamento (a da 20261101100860) como pg_temp, a régua do "desligado = antes".
do $antes$
declare
  v_m text := coalesce(current_setting('agenda_teste.mig_correcao3_fase7b', true), '');
begin
  if v_m <> '' then
    execute replace(pg_temp.inteira(v_m, '_agenda_linhas_do_fechamento'), 'create or replace function public._agenda_linhas_do_fechamento(',
                    'create function pg_temp.linhas_antes(');
  end if;
end
$antes$;
create function pg_temp.ligadas(p jsonb) returns jsonb language sql immutable as $f$
  select coalesce(jsonb_agg(l order by o), '[]'::jsonb) from jsonb_array_elements(p) with ordinality t(l, o) where l ->> 'modo' = 'ligado'
$f$;

-- ── R1, R1b. A proposta pela grade e pelo técnico que o dono declarou (a sintética) ─────────────────────────────────────
do $r1$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
  t6    text;
  t7    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R1 a proposta pela grade', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    -- o Mateus da 7b, dito pelo dono só em qui 12 e sex 13/11: vem sob demanda (o gestor não lhe propõe nada)
    perform pg_temp.vem('Mateus', array[date '2026-11-12', date '2026-11-13']);
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t1 := pg_temp.propostas();
    t2 := (select string_agg(public._agenda_nome_curto(py.name) || ': ' || e.motivo, ' | ' order by public._agenda_nome_curto(py.name))
             from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id where e.estado = 'proposta');
    t3 := (select string_agg(public._agenda_nome_curto(py.name) || ' ' || (e.evidencia - 'cadastro' - 'desde')::text || ' desde '
                             || left(e.evidencia ->> 'desde', 10), ' | ' order by public._agenda_nome_curto(py.name))
             from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id
            where e.estado = 'proposta' and py.name in ('Roberto', 'João', 'Alex'));
    t4 := (v ->> 'pessoas') || ' pessoas, ' || jsonb_array_length(v -> 'propostas') || ' propostas';
    t5 := (select count(*)::text from public.agenda_etiquetas e where e.payee_id in (pg_temp.pessoa('Mateus'), pg_temp.pessoa('Mickael')));
    t6 := (select string_agg(e.origem || '/' || e.estado || '/' || coalesce(e.vale_desde::text, '-') || '/' || e.criado_em::text, ' ')
             from public.agenda_etiquetas e where e.payee_id = pg_temp.pessoa('Bruno'));
    -- a proposta não muda o que vale: agenda_habilidades igual antes do prazo
    t7 := (select string_agg(h.texto, ' ' order by h.nome) from public.agenda_habilidades(date '2026-11-04') h);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R1a a sintética: Alex instala 2 (o técnico declarado), Roberto instala 2 (o histórico), João ajudante 2, Rafael ajudante 2 (sem diária), Bruno ajudante 1 (o novato da 7b); nunca comissiona nem altura',
    t1 = 'Alex instala 2 · Bruno ajudante 1 · João ajudante 2 · Rafael ajudante 2 · Roberto instala 2', t1);
  v_res := pg_temp.ok(v_res, 'R1b os motivos da §6.2: "você disse que ele vem todo dia útil", "33 diárias desde 23/08", "entrou em 29/09, 15 diárias", "entrou em 01/09, ainda sem diária", "começou em 20/10, 3 diárias"',
    t2 = 'Alex: você disse que ele vem todo dia útil | Bruno: começou em 20/10, 3 diárias | João: entrou em 29/09, 15 diárias | Rafael: entrou em 01/09, ainda sem diária | Roberto: 33 diárias desde 23/08',
    t2);
  v_res := pg_temp.ok(v_res, 'R1c as evidências: o declarado {declarado, dias, desde a 1ª linha do dono, o cadastro}; o histórico {diarias na janela de 90 dias, desde a 1ª vigência, dias_de_casa}',
    t3 = 'Alex {"dias": [1, 2, 3, 4, 5], "declarado": true} desde 2026-10-30 | João {"janela": 90, "diarias": 15, "dias_de_casa": 36} desde 2026-09-29 | Roberto {"janela": 90, "diarias": 33, "dias_de_casa": 73} desde 2026-08-23',
    t3);
  v_res := pg_temp.ok(v_res, 'R1d a população é a grade sem o dono e sem quem vem sob demanda: 5 pessoas e 5 propostas; o Mateus (dito só em datas) e o Mickael (fora da grade) sem nada',
    t4 = '5 pessoas, 5 propostas' and t5 = '0', t4 || ' | Mateus/Mickael ' || t5);
  v_res := pg_temp.ok(v_res, 'R1e a proposta é do gestor, em proposta, sem vale_desde, com criado_em = a hora da rodada; e não vale: agenda_habilidades igual (o Bruno novo e o Mateus sob demanda pela regra, os outros pelo padrão)',
    t6 = 'gestor/proposta/-/2026-11-04 16:10:00-03'
    and t7 = 'Alex: pode tudo, menos comissionar (padrão). Bruno: é novo: nunca vai sozinho (começou em 20/10, 3 diárias). Você: comissiona Victron sozinho; instala sozinho e ensina; sobe no teto (padrão). João: pode tudo, menos comissionar (padrão). Mateus: nunca vai sozinho (vem só nos dias que você diz). Rafael: pode tudo, menos comissionar (padrão). Roberto: pode tudo, menos comissionar (padrão).',
    t6 || ' | ' || t7);

  -- R1f: o Mateus cadastrado agora com "toda terça" dita pelo dono (com e sem um perfil de hoje)
  for t7 in select unnest(array['mateus_terca', 'mateus_terca_sem_perfil']) loop
    begin
      perform set_config('agenda_teste.fase7c_variante', t7, true);
      execute current_setting('agenda_teste.fase7c');
      perform set_config('agenda_teste.fase7c_variante', '', true);
      perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
      v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
      t1 := coalesce((select string_agg(e.etiqueta || ' ' || e.nivel || ' ' || e.motivo, ', ') from public.agenda_etiquetas e
                       where e.payee_id = pg_temp.pessoa('Mateus')), 'nada');
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
    perform set_config('agenda_teste.fase7c_variante', '', true);
    v_res := pg_temp.ok(v_res, format('R1f %s: o Mateus cadastrado agora com "toda terça" do dono %s', t7,
                                      case t7 when 'mateus_terca' then 'e um perfil de hoje é o novato da 7b (ajudante 1), nunca instala pela palavra dos dias'
                                              else 'e sem perfil não recebe nada (o papel novo do dia fixo já o protege, agenda_habilidades)' end),
      t1 = case t7 when 'mateus_terca' then 'ajudante 1 começou em 04/11, ainda sem diária' else 'nada' end, t1);
  end loop;
  perform pg_temp.gravar(v_res);
end
$r1$;

-- ── R2. A pergunta: o texto, o modo, uma aberta, refeita quando muda ───────────────────────────────────────────────────
do $r2$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  q     public.agenda_perguntas;
  q2    public.agenda_perguntas;
  v_q1  uuid;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R2 a pergunta', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    q := pg_temp.pergunta_aberta();
    v_q1 := q.id;
    t1 := q.modo || ' ' || char_length(q.texto) || ' | ' || q.texto;
    -- a rodada de novo, sem mudança: não refaz
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:11'));
    t2 := (v ->> 'refeita') || ' ' || ((v ->> 'pergunta_id')::uuid = v_q1) || ' '
          || (select count(*) from public.agenda_perguntas x where x.tipo = 'habilidade' and x.estado = 'aberta')
          || ' ' || (select count(*) from public.agenda_etiquetas e where e.estado = 'proposta' and e.pergunta_id = v_q1);
    -- o dono diz "o João instala sozinho" antes de ver (pela conversa: a etiqueta do dono): a proposta do João sai, a pergunta é refeita
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em, criado_por)
    values (pg_temp.pessoa('João'), 'instala', 2, 'dono', 'vale', 'você disse', 'o João instala sozinho',
            pg_temp.em(date '2026-11-05', '09:00'), pg_temp.em(date '2026-11-05', '09:00'), pg_temp.adm());
    v := public._agenda_habilidade_propor(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:10'));
    q2 := pg_temp.pergunta_aberta();
    t3 := (v ->> 'refeita') || ' | ' || (select x.estado || ' ' || x.resolvida_motivo from public.agenda_perguntas x where x.id = v_q1)
          || ' | ' || q2.chave || ' | ' || pg_temp.propostas() || ' | '
          || (select count(*) from public.agenda_etiquetas e where e.estado = 'proposta' and e.pergunta_id is distinct from q2.id)
          || ' | ' || (q2.texto like '%João%');
    -- o modo muda (em teste): a ligada nunca vista sai e nasce a de teste
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    v := public._agenda_habilidade_propor(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:20'));
    t4 := (v ->> 'refeita') || ' ' || (pg_temp.pergunta_aberta()).modo || ' '
          || (select x.estado from public.agenda_perguntas x where x.id = q2.id);
    -- sem nenhuma proposta viva (todas valendo), a aberta sai
    update public.agenda_etiquetas set estado = 'vale', vale_desde = pg_temp.em(date '2026-11-05', '17:00') where estado = 'proposta';
    v := public._agenda_habilidade_propor(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:10'));
    t5 := (v ->> 'refeita') || ' ' || coalesce(v ->> 'pergunta_id', 'nula') || ' ' || ((pg_temp.pergunta_aberta()).id is null) || ' '
          || (select x.resolvida_motivo from public.agenda_perguntas x where x.tipo = 'habilidade' order by x.criada_em desc, x.id desc limit 1);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R2a o texto da pergunta da sintética, byte a byte (as 5 propostas encolhem para o rótulo curto e cabem em 600: primeiro quem instala sozinho, depois o ajudante e o novo), ligada',
    t1 = 'ligado ' || char_length(pg_temp.texto_sintetica()) || ' | ' || pg_temp.texto_sintetica(), t1);
  v_res := pg_temp.ok(v_res, 'R2b a rodada de novo sem mudança não refaz: a mesma pergunta, uma aberta só, as 5 propostas apontando para ela',
    t2 = 'false true 1 5', t2);
  v_res := pg_temp.ok(v_res, 'R2c o dono disse outra coisa do João antes de ver (a etiqueta dele substitui a proposta): a pergunta é refeita sem o João — a de antes descartada ("a proposta mudou: perguntei de novo"), as 4 vivas apontando para a nova',
    t3 = 'true | descartada a proposta mudou: perguntei de novo | habilidade:equipe:2026-11-05 | Alex instala 2 · Bruno ajudante 1 · Rafael ajudante 2 · Roberto instala 2 | 0 | false',
    t3);
  v_res := pg_temp.ok(v_res, 'R2d o modo da pergunta muda com o modo de agora (em teste: a ligada nunca vista é descartada e nasce a de teste)',
    t4 = 'true sombra descartada', t4);
  v_res := pg_temp.ok(v_res, 'R2e sem nenhuma proposta viva, a pergunta aberta sai ("a proposta mudou: não sobrou nada a perguntar") e nenhuma nasce',
    t5 = 'true nula true a proposta mudou: não sobrou nada a perguntar', t5);

  -- R2f: em teste desde o começo — a pergunta nasce em teste e a linha (n) só existe no detalhe (sombra); a ligada não muda
  begin
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t1 := (pg_temp.pergunta_aberta()).modo || ' ' || (pg_temp.linha_n(date '2026-11-04', 'sombra') is not null) || ' '
          || (pg_temp.linha_n(date '2026-11-04', 'ligado') is null) || ' '
          || coalesce((pg_temp.ligadas(public._agenda_linhas_do_fechamento(date '2026-11-04'))
                       = pg_temp.ligadas(pg_temp.linhas_antes(date '2026-11-04')))::text, 'sem a régua');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R2f em teste, a pergunta nasce em teste e a linha (n) com ela só existe no detalhe (sombra); as linhas ligadas do fechamento são as de antes (a 20261101100860)',
    t1 = 'sombra true true true', t1);
  perform pg_temp.gravar(v_res);
end
$r2$;

-- ── R2g–R2j. A linha (n) do fechamento: a forma curta com o prazo, o "Também", o portão separado e o "desligado = antes" ──────
do $r2l$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  l     jsonb;
  q     public.agenda_perguntas;
  v_tel uuid;
  v_ch  uuid;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
  r     record;
  v_dif text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R2g a linha (n) do fechamento', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- (g) a forma curta com o prazo, contada; o prazo gravado depois é a data do texto
  begin
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    q := pg_temp.pergunta_aberta();
    l := pg_temp.linha_n(date '2026-11-04');
    t1 := concat_ws(' | ', l ->> 'perda', l ->> 'texto_curto', (l -> 'pergunta_ids')::text = jsonb_build_array(q.id)::text,
                    l ->> 'pergunta_id' = q.id::text, l ->> 'texto' = 'Agenda: ' || q.texto);
    -- o Secretário cheio mandou a forma curta: o registro conta a pergunta como vista
    perform pg_temp.registrar(date '2026-11-04', '17:31', jsonb_build_array(l));
    v := public._agenda_habilidade_vetos(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:10'));
    t2 := (select x.mostrada_vezes || ' ' || public._dia_curto((x.veto_ate at time zone 'America/Sao_Paulo')::date) || ' às '
                  || to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'HH24:MI') from public.agenda_perguntas x where x.id = q.id);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R2g a linha (n) com a pergunta da equipe (a 1ª da linha): perda 75 (nunca vista), o texto inteiro, pergunta_id e pergunta_ids = ela, e a forma curta com o que foi marcado e o prazo ("… sem resposta até qui 05/11 às 18:00, fica assim")',
    t1 = '75 | Agenda, equipe: quem faz o quê — marquei: Alex instala sozinho, Roberto instala sozinho, João é ajudante, Rafael é ajudante e Bruno é novo; sem resposta até qui 05/11 às 18:00, fica assim. *agenda pendências* mostra. | t | t | t',
    t1);
  v_res := pg_temp.ok(v_res, 'R2h a forma curta mostrada conta como vista, e o veto_ate que a rodada grava depois é a data do texto (qui 05/11 às 18:00)',
    t2 = '1 qui 05/11 às 18:00', t2);

  -- (i) como "Também" (o telefone do Alex, da 7b, na frente): não conta como vista e a forma curta não promete prazo
  begin
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    update public.agenda_config set modo_cadastro = 'ligado' where id;
    insert into public.agenda_perguntas (tipo, chave, payee_id, texto, opcoes, modo, criada_em)
    values ('equipe_cadastro', 'equipe_cadastro:telefone:' || pg_temp.pessoa('Alex'), pg_temp.pessoa('Alex'),
            'Alex não tem telefone no cadastro: sem ele não mando a ficha da véspera. Para pôr, diga: o telefone do Alex é …', '[]'::jsonb,
            'ligado', pg_temp.em(date '2026-11-04', '16:00'))
    returning id into v_tel;
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    q := pg_temp.pergunta_aberta();
    l := pg_temp.linha_n(date '2026-11-04');
    t3 := concat_ws(' | ', l ->> 'perda', l ->> 'pergunta_id' = v_tel::text, (l -> 'pergunta_ids')::text = jsonb_build_array(v_tel)::text,
                    l ->> 'texto' like '% Também: quem faz o quê (marquei: Alex instala sozinho, Roberto instala sozinho, João é ajudante, Rafael é ajudante e Bruno é novo; responda em *agenda pendências*).',
                    l ->> 'texto_curto');
    perform pg_temp.registrar(date '2026-11-04', '17:31', jsonb_build_array(l));
    t4 := (select string_agg(x.tipo || ' ' || x.mostrada_vezes, ', ' order by x.tipo) from public.agenda_perguntas x where x.id in (v_tel, q.id));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  -- FASE 7c: (correção 2 da revisão, 20261102100590, achado 11) a de quem faz o quê da equipe, ligada, que vai como "Também" leva o que foi
  -- marcado E o prazo — na inteira e na curta, como a forma curta que já contava — e conta como vista (fica em pergunta_ids; o registro a
  -- conta). Antes ela saía de pergunta_ids e não contava: na semana real a chamada e depois o telefone do Alex iam sempre primeiro, e o
  -- prazo nunca começava. O telefone continua primeiro.
  v_res := pg_temp.ok(v_res, 'R2i como "Também" (o telefone do Alex na frente): com o prazo, fica em pergunta_ids, a forma curta diz o que foi marcado e o prazo, e o registro a conta como vista (correção 2, achado 11)',
    t3 like '75 | t | f | f | Agenda, equipe: o telefone do Alex; quem faz o quê — marquei: Alex instala sozinho, Roberto instala sozinho, João é ajudante, Rafael é ajudante e Bruno é novo; sem resposta até qui 05/11 às 18:00, fica assim. *agenda pendências* mostra.'
    and t4 = 'equipe_cadastro 1, habilidade 1',
    t3 || ' || ' || t4);
  -- FASE 7c: fim

  -- (j) o portão separado: a 7b desligada e a 7c em teste — a chamada da 7a fica na pergunta de fato (e), e as ligadas são as de antes
  begin
    perform pg_temp.modos7b('desligado');
    perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
    insert into public.agenda_perguntas (tipo, chave, texto, opcoes, modo, criada_em)
    values ('equipe_cadastro', 'equipe_cadastro:chamada:2026-11-04',
            'A equipe da agenda está certa? Conto com Alex (você disse todo dia útil). Se mudou, me diga quem saiu ou quem entrou.',
            '[]'::jsonb, 'ligado', pg_temp.em(date '2026-11-03', '16:52'))
    returning id into v_ch;
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    v := public._agenda_linhas_do_fechamento(date '2026-11-04');
    t5 := concat_ws(' | ',
            (select count(*) from jsonb_array_elements(v) x where x -> 'pergunta_ids' ? v_ch::text),
            (select string_agg(x ->> 'perda', ',') from jsonb_array_elements(v) x
              where x ->> 'tipo' = 'pergunta' and x ->> 'modo' = 'ligado' and x ->> 'texto' like '%(e mais %'),
            pg_temp.ligadas(v) = pg_temp.ligadas(pg_temp.linhas_antes(date '2026-11-04')),
            (select count(*) from jsonb_array_elements(v) x where x ->> 'modo' = 'sombra' and x ->> 'texto' like '%quem faz o quê%'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R2j com a 7b desligada e a 7c em teste, a chamada da 7a não vai para a linha (n) (fica na pergunta de fato, perda 30: as linhas ligadas são as de antes) e a pergunta da equipe da 7c vai só no detalhe',
    t5 = '0 | 30 | t | 1', t5);

  -- (k) desligado = antes: os modos da 7c desligados (com uma pergunta da 7c que ficou aberta em teste), a 7b desligada e em teste, com e sem
  -- as perguntas de fornecedor abertas e nunca vistas (as de produção): a saída inteira é a da 20261101100860
  v_dif := null;
  for r in select * from (values ('desligado', false), ('desligado', true), ('sombra', false), ('sombra', true)) t(m7b, sem_forn) loop
    begin
      perform pg_temp.modos7b(r.m7b);
      perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
      v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
      perform pg_temp.modos7c('desligado', 'desligado', 'desligado');
      if r.sem_forn then
        update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste'
         where tipo in ('fornecedor_cadastro', 'fornecedores_prazo') and estado = 'aberta';
      end if;
      for t1 in select unnest(array['2026-11-04', '2026-11-05', '2026-11-06']) loop
        if public._agenda_linhas_do_fechamento(t1::date) is distinct from pg_temp.linhas_antes(t1::date) then
          v_dif := concat_ws('; ', v_dif, format('7b %s, fornecedor %s, %s', r.m7b, case when r.sem_forn then 'fechadas' else 'abertas' end, t1));
        end if;
      end loop;
      -- em teste: só as linhas ligadas são as de antes
      perform pg_temp.modos7c('sombra', 'sombra', 'sombra');
      if pg_temp.ligadas(public._agenda_linhas_do_fechamento(date '2026-11-04'))
         is distinct from pg_temp.ligadas(pg_temp.linhas_antes(date '2026-11-04')) then
        v_dif := concat_ws('; ', v_dif, format('em teste: 7b %s, fornecedor %s', r.m7b, case when r.sem_forn then 'fechadas' else 'abertas' end));
      end if;
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'R2k com os modos da 7c desligados, a saída inteira de _agenda_linhas_do_fechamento (qua 04, qui 05 e sex 06/11) é a da 20261101100860 rodada como pg_temp — com a 7b desligada e em teste, com e sem as perguntas de fornecedor abertas e nunca vistas; com a 7c em teste, as linhas ligadas também',
    v_dif is null and to_regprocedure('pg_temp.linhas_antes(date)') is not null, coalesce(v_dif, 'iguais nas 4 combinações'));
  perform pg_temp.gravar(v_res);
end
$r2l$;

-- ── R3. O prazo de veto: conta da 1ª vez que a pergunta foi vista ────────────────────────────────────────────────────────
do $r3$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  q     public.agenda_perguntas;
  v4    jsonb;
  v5    jsonb;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
  t6    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R3 o prazo de veto', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    -- ter 03/11: a rodada propõe e o fechamento das 17:30 mostra a pergunta inteira
    v := public._agenda_habilidade_propor(date '2026-11-03', pg_temp.em(date '2026-11-03', '16:10'));
    q := pg_temp.pergunta_aberta();
    perform pg_temp.registrar(date '2026-11-03', '17:30', jsonb_build_array(pg_temp.linha_n(date '2026-11-03')));
    -- qua 04/11 16:10: a rodada grava o prazo (qua 04/11 18:00) e nada vale ainda
    v4 := public._agenda_habilidade_vetos(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t1 := v4::text || ' | ' || (select to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || ' ' || x.estado
                                  from public.agenda_perguntas x where x.id = q.id)
          || ' | ' || (select count(*) from public.agenda_etiquetas e where e.pergunta_id = q.id and e.estado = 'proposta');
    -- o fechamento de qua mostra de novo: o prazo não muda
    perform pg_temp.registrar(date '2026-11-04', '17:30', jsonb_build_array(pg_temp.linha_n(date '2026-11-04')));
    t2 := (select x.mostrada_vezes || ' ' || to_char(x.veto_ate at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
             from public.agenda_perguntas x where x.id = q.id);
    -- qui 05/11 16:10: o prazo passou — as propostas valem, a pergunta fecha e a ação vai ao "o que mudou"
    v5 := public._agenda_habilidade_vetos(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:10'));
    t3 := v5::text || ' | ' || (select x.estado || ' ' || x.resolvida_motivo from public.agenda_perguntas x where x.id = q.id)
          || ' | ' || (select string_agg(distinct e.estado || ' ' || e.vale_desde::text, ',') from public.agenda_etiquetas e where e.pergunta_id = q.id);
    t4 := (select string_agg(a.texto || ' | ' || a.executada || ' ' || a.origem || ' ' || a.dia || ' ' || coalesce(a.desfazivel_ate::text, 'sem desfaz')
                             || ' ' || jsonb_array_length(a.depois -> 'payees'), ' // ')
             from public.agenda_acoes a where a.tipo = 'habilidade');
    t5 := (select string_agg(h.texto, ' ' order by h.nome) from public.agenda_habilidades(date '2026-11-05') h where not h.eh_dono);
    t6 := (select string_agg((l ->> 'modo') || ' ' || (l ->> 'tipo'), ', ')
             from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-05')) l
            where l ->> 'texto' like '%Quem faz o quê: sem resposta no prazo, ficou como eu marquei%');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R3a mostrada ter 03/11 às 17:30: a rodada de qua 04/11 grava o prazo uma vez (qua 04/11 18:00: veto_du 1, veto_hora 18:00) e nada vale ainda',
    t1 = '{"prazos": 1, "valeram": 0} | 04/11 18:00 aberta | 5', t1);
  v_res := pg_temp.ok(v_res, 'R3b mostrar de novo não adia (o veto_ate vai de nulo a valor uma vez)', t2 = '2 04/11 18:00', t2);
  v_res := pg_temp.ok(v_res, 'R3c qui 05/11 16:10 (depois do prazo): as 5 propostas valem (vale_desde = a hora da rodada) e a pergunta fecha ("sem resposta no prazo: ficou como eu marquei")',
    t3 = '{"prazos": 0, "valeram": 5} | resolvida sem resposta no prazo: ficou como eu marquei | vale 2026-11-05 16:10:00-03', t3);
  v_res := pg_temp.ok(v_res, 'R3d UMA ação habilidade (a vigia, executada, sem *desfaz*, do dia, com as 5 pessoas) com o texto da §6.5',
    t4 = 'Quem faz o quê: sem resposta no prazo, ficou como eu marquei — Alex instala sozinho; Roberto instala sozinho; João é ajudante; Rafael é ajudante; Bruno é novo. Para mudar, me diga (ex.: "o João instala sozinho"). | true vigia 2026-11-05 sem desfaz 5',
    t4);
  v_res := pg_temp.ok(v_res, 'R3e depois do prazo vale o que foi marcado (agenda_habilidades: "eu marquei: …") e a ação entra no "o que mudou" do fechamento de qui (ligado: a agenda automática está ligada)',
    t5 = 'Alex: instala sozinho (eu marquei: você disse que ele vem todo dia útil). Bruno: é novo: nunca vai sozinho (eu marquei: começou em 20/10, 3 diárias). João: é ajudante: não vai sozinho em serviço de risco (eu marquei: entrou em 29/09, 15 diárias). Rafael: é ajudante: não vai sozinho em serviço de risco (eu marquei: entrou em 01/09, ainda sem diária). Roberto: instala sozinho (eu marquei: 33 diárias desde 23/08).'
    and t6 like '%ligado%', t5 || ' | ' || coalesce(t6, 'nenhuma linha'));

  -- a nunca mostrada nunca vale (nem duas semanas depois); a de teste também não
  t1 := '';
  for t2 in select unnest(array['ligado', 'sombra']) loop
    begin
      perform pg_temp.modos7c('sombra', 'sombra', t2);
      v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
      q := pg_temp.pergunta_aberta();
      if t2 = 'sombra' then
        -- a de teste até mostrada (o detalhe) não vence: o prazo é só da ligada
        update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(date '2026-11-04', '17:30'), mostrada_via = 'fechamento'
         where id = q.id;
      end if;
      v := public._agenda_habilidade_vetos(date '2026-11-18', pg_temp.em(date '2026-11-18', '16:10'));
      t1 := t1 || t2 || ': ' || v::text || ' ' || (select x.estado || ' ' || coalesce(x.veto_ate::text, 'sem prazo') from public.agenda_perguntas x where x.id = q.id)
            || ' ' || (select count(*) from public.agenda_etiquetas e where e.estado = 'vale') || '; ';
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'R3f a pergunta ligada que nunca foi mostrada nunca vale (nem duas semanas depois); a de teste também não (o prazo é só da ligada)',
    t1 = 'ligado: {"prazos": 0, "valeram": 0} aberta sem prazo 0; sombra: {"prazos": 0, "valeram": 0} aberta sem prazo 0; ', t1);
  perform pg_temp.gravar(v_res);
end
$r3$;

-- ── R4. O que o dono disse não é proposto por cima ───────────────────────────────────────────────────────────────────
do $r4$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t1    text;
  t2    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R4 o que o dono disse', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    -- "o Roberto é ajudante" e "o Bruno instala sozinho" (do dono); "o João não sobe no teto" (só a altura: não segura a proposta dele)
    insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em, criado_por)
    select pg_temp.pessoa(t.n), t.e, t.nv, 'dono', 'vale', 'você disse', t.tr, pg_temp.em(date '2026-11-04', '09:00'),
           pg_temp.em(date '2026-11-04', '09:00'), pg_temp.adm()
      from (values ('Roberto', 'ajudante', 2::smallint, 'o Roberto é ajudante'), ('Bruno', 'instala', 2::smallint, 'o Bruno instala sozinho'),
                   ('João', 'altura', 0::smallint, 'o João não sobe no teto')) t(n, e, nv, tr);
    v := public._agenda_habilidade_propor(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t1 := pg_temp.propostas();
    t2 := (select string_agg(public._agenda_nome_curto(py.name) || ' ' || e.etiqueta || ' ' || e.nivel || ' ' || e.estado, ', '
                             order by public._agenda_nome_curto(py.name), e.etiqueta)
             from public.agenda_etiquetas e join public.payees py on py.id = e.payee_id where e.origem = 'dono');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R4 o que o dono disse em instala ou ajudante não é proposto por cima (Roberto e Bruno sem proposta; as linhas do dono intactas); só a altura dita não segura a proposta do João',
    t1 = 'Alex instala 2 · João ajudante 2 · Rafael ajudante 2'
    and t2 = 'Bruno instala 2 vale, João altura 0 vale, Roberto ajudante 2 vale', t1 || ' | ' || t2);
  perform pg_temp.gravar(v_res);
end
$r4$;

-- As etiquetas dos testes M e V (Roberto instala 2 e não sobe no teto; João ajudante 2; Bruno novo) para a conferência e as medidas
-- (carregadas dentro de cada caso, na subtransação).
create function pg_temp.mv() returns void language plpgsql as $f$
begin
  perform set_config('agenda_teste.fase7c_etiquetas', 'mv', true);
  execute current_setting('agenda_teste.fase7c');
  perform set_config('agenda_teste.fase7c_etiquetas', '', true);
end $f$;

-- ── R5. A conferência em teste ───────────────────────────────────────────────────────────────────────────────────────
do $r5$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  v2    jsonb;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
  d     date;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R5 a conferência em teste', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.mv();
    perform pg_temp.modos7c('sombra', 'sombra', 'desligado');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    -- o Alex e o Rafael (que também instalam sozinhos) fora em ter 10 e qua 11/11: quem eu poria é o Roberto
    perform pg_temp.nao_vem('Alex', date '2026-11-10', date '2026-11-11');
    perform pg_temp.nao_vem('Rafael', date '2026-11-10', date '2026-11-11');
    -- publicados: o Bruno sozinho no Hugo (qua 11/11 de manhã), o João no Edu (qua 11/11, os dois turnos; o Roberto fez o 1º dia); a 179
    -- (o João sozinho na ter 10/11) é da fixture
    perform pg_temp.publicar('OS-97178', 'Bruno', date '2026-11-11', 'manha');
    perform pg_temp.publicar('OS-97175', 'João', date '2026-11-11', 'manha');
    perform pg_temp.publicar('OS-97175', 'João', date '2026-11-11', 'tarde');
    v := public._agenda_habilidade_conferir(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t1 := (select string_agg(a.texto, ' // ' order by a.antes ->> 'dia', a.antes ->> 'turno' nulls first, a.texto)
             from public.agenda_acoes a where a.tipo = 'habilidade' and not a.executada);
    t2 := (select string_agg(distinct a.origem || ' ' || a.dia || ' ' || coalesce(a.desfazivel_ate::text, '-') || ' ' || (a.service_order_id is not null), ',')
             from public.agenda_acoes a where a.tipo = 'habilidade');
    t3 := v::text;
    -- a mesma conferência de novo, no mesmo dia: nada se repete
    v2 := public._agenda_habilidade_conferir(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:40'));
    t4 := (v2 ->> 'acoes') || ' ' || (select count(*) from public.agenda_acoes a where a.tipo = 'habilidade');
    -- as ações de teste vão às linhas de sombra (o detalhe), nunca às ligadas (o texto do dono)
    t5 := (select count(*) filter (where l ->> 'modo' = 'ligado') || ' ' || count(*) filter (where l ->> 'modo' = 'sombra')
             from jsonb_array_elements(public._agenda_linhas_do_fechamento(date '2026-11-04')) l
            where l ->> 'texto' like '%Em teste (quem faz o quê)%' or l ->> 'texto' like '%Em teste (responsável fixo)%');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R5a em teste, o publicado avaliado com as regras de ligado vira as ações da §6.6: o João sozinho no último meio-dia que pede 220 V (eu poria Roberto), o Bruno novo sozinho (eu poria alguém junto) e o responsável fixo (os dois turnos do mesmo dia numa linha)',
    t1 = 'Em teste (quem faz o quê): Ivo, ter 10/11 à tarde — João iria sozinho, e esse dia pede quem instala sozinho com 220 V ou banco de bateria; eu poria Roberto.'
         || ' // Em teste (responsável fixo): Edu, qua 11/11 — o responsável é Roberto (fez o 1º dia), mas o dia está com João; eu manteria Roberto.'
         || ' // Em teste (quem faz o quê): Hugo, qua 11/11 de manhã — Bruno é novo e iria sozinho; eu poria alguém junto.'
         || ' // Em teste (quem faz o quê): Edu, qua 11/11 à tarde — João iria sozinho, e esse dia pede quem instala sozinho com 220 V ou banco de bateria; eu poria Roberto.',
    t1);
  v_res := pg_temp.ok(v_res, 'R5b as ações de teste são da vigia, do dia, sem *desfaz*, com a OS; a contagem diz 3 meios-dias sem quem o serviço pede e 2 sem o responsável',
    t2 = 'vigia 2026-11-04 - true' and t3 = '{"de": "2026-11-05", "ate": "2026-11-18", "acoes": 4, "cortadas": 0, "sem_lider": 2, "meios_sem_quem_pede": 3}',
    t2 || ' | ' || t3);
  v_res := pg_temp.ok(v_res, 'R5c a mesma conferência de novo no mesmo dia não repete nada (o mesmo meio-dia e código)', t4 = '0 4', t4);
  v_res := pg_temp.ok(v_res, 'R5d as ações de teste vão só às linhas de sombra do fechamento (o detalhe), nunca às ligadas', t5 = '0 1', t5);

  -- sem ninguém livre com o que o serviço pede: "eu mudaria o dia"; e o teto de 6 por dia
  begin
    perform pg_temp.mv();
    perform pg_temp.modos7c('sombra', 'desligado', 'desligado');
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    perform pg_temp.nao_vem('Alex', date '2026-11-10', date '2026-11-10');
    perform pg_temp.nao_vem('Rafael', date '2026-11-10', date '2026-11-10');
    perform pg_temp.nao_vem('Roberto', date '2026-11-10', date '2026-11-10');
    v := public._agenda_habilidade_conferir(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t1 := (select a.texto from public.agenda_acoes a where a.tipo = 'habilidade' and a.antes ->> 'dia' = '2026-11-10');
    -- o Bruno sozinho no Duda em 8 meios-dias (12, 13, 16 e 17/11): com a 179, 9 meios-dias — 6 ações e 3 cortadas
    foreach d in array array[date '2026-11-12', date '2026-11-13', date '2026-11-16', date '2026-11-17'] loop
      perform pg_temp.publicar('OS-97174', 'Bruno', d, 'manha');
      perform pg_temp.publicar('OS-97174', 'Bruno', d, 'tarde');
    end loop;
    v2 := public._agenda_habilidade_conferir(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:40'));
    t2 := v2::text || ' ' || (select count(*) from public.agenda_acoes a where a.tipo = 'habilidade' and a.dia = date '2026-11-04');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R5e sem ninguém livre que dê conta no meio-dia (o Alex, o Rafael e o Roberto fora): "ninguém com isso está livre: eu mudaria o dia"',
    t1 = 'Em teste (quem faz o quê): Ivo, ter 10/11 à tarde — João iria sozinho, e esse dia pede quem instala sozinho com 220 V ou banco de bateria; ninguém com isso está livre: eu mudaria o dia.',
    t1);
  v_res := pg_temp.ok(v_res, 'R5f no máximo 6 ações de teste por dia: com 9 meios-dias a conferir, a 2ª conferência põe as 5 que faltam até 6 e corta 3',
    t2 = '{"de": "2026-11-05", "ate": "2026-11-18", "acoes": 5, "cortadas": 3, "sem_lider": 0, "meios_sem_quem_pede": 9} 6', t2);
  perform pg_temp.gravar(v_res);
end
$r5$;

-- ── R6. A pergunta por OS (só ligado) ───────────────────────────────────────────────────────────────────────────────
do $r6$
declare
  v_res jsonb := '[]'::jsonb;
  v     jsonb;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R6 a pergunta por OS', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.gestor('ligado'); perform pg_temp.modos7b('desligado'); perform pg_temp.modos7c('ligado', 'ligado', 'desligado');
    -- o motor de hoje (a vigia, persistido): a 173 Caio (comissionamento em todos, o dono "nunca") fica de fora por habilidade
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97173')], '{}'::jsonb, true, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:05'));
    t1 := (select string_agg(f ->> 'motivo', ',') from jsonb_array_elements(v -> 'fora') f where f ->> 'numero' = 'OS-97173');
    v := public._agenda_habilidade_perguntas_os(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:10'));
    t2 := (v - 'proposta')::text || ' | ' || (select (x.chave = 'habilidade:os:' || pg_temp.os('OS-97173'))::text || ' ' || x.modo || ' ' || x.critica
                                                     || ' ' || coalesce(x.perda_em::text, 'sem perda') || ' | ' || x.texto
                                                from public.agenda_perguntas x where x.tipo = 'habilidade' and x.estado = 'aberta');
    -- de novo: uma aberta por OS
    v := public._agenda_habilidade_perguntas_os(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:11'));
    t3 := (v - 'proposta')::text;
    -- o dono diz que o Caio não precisa de quem comissiona: o motor de hoje o encaixa e a pergunta fecha
    update public.os_planejamento set exigencias_ditas = '{"comissionamento": "nao"}' where service_order_id = pg_temp.os('OS-97173');
    v := public.agenda_propor('os', null, null, array[pg_temp.os('OS-97173')], '{}'::jsonb, true, 'vigia', null, date '2026-11-04',
                              pg_temp.em(date '2026-11-04', '16:30'));
    v := public._agenda_habilidade_perguntas_os(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:31'));
    t4 := (v - 'proposta')::text || ' | ' || (select x.estado || ' ' || x.resolvida_motivo from public.agenda_perguntas x
                                                where x.chave = 'habilidade:os:' || pg_temp.os('OS-97173'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R6a com a 7c ligada, a OS que o motor de hoje deixou de fora por falta de quem o serviço pede ganha a pergunta habilidade:os:<os> (ligada, não crítica, sem prazo) com o texto da §6.4',
    t1 = 'habilidade'
    and t2 = '{"abertas": 1, "resolvidas": 0} | true ligado false sem perda | Caio: o serviço pede quem comissiona Victron em todos os dias, e nas próximas 6 semanas não acho ninguém com isso livre. Quem pode? Me diga numa frase (ex.: "o responsável do Caio é o Alex" ou "o Caio não precisa de quem comissiona Victron").',
    t1 || ' | ' || t2);
  v_res := pg_temp.ok(v_res, 'R6b uma aberta por OS: a rodada de novo não abre outra', t3 = '{"abertas": 0, "resolvidas": 0}', t3);
  v_res := pg_temp.ok(v_res, 'R6c quando a OS volta a caber (o dono disse que não precisa de quem comissiona), a pergunta fecha: "coube: a equipe tem quem o serviço pede"',
    t4 = '{"abertas": 0, "resolvidas": 1} | resolvida coube: a equipe tem quem o serviço pede', t4);
  perform pg_temp.gravar(v_res);
end
$r6$;

-- ── R7. As medidas ───────────────────────────────────────────────────────────────────────────────────────────────────
do $r7$
declare
  v_res jsonb := '[]'::jsonb;
  m     jsonb;
  t1    text;
  t2    text;
  t3    text;
  d     date;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R7 as medidas', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  begin
    perform pg_temp.mv();
    update public.agenda_config set habilidade_fechamento_cobre = false where id;
    -- os 3 meios-dias do dono de turno em 20, 22 e 27/10 numa OS de 12 V (o Hugo: não pede ninguém em especial), com o Roberto livre
    foreach d in array array[date '2026-10-20', date '2026-10-22', date '2026-10-27'] loop
      perform pg_temp.publicar('OS-97178', 'dono', d, 'manha');
    end loop;
    m := public.agenda_habilidade_medidas(date '2026-10-05', date '2026-11-18', date '2026-11-04');
    t1 := concat_ws(' | ', m ->> 'dono_em_tarefa_de_outro', m ->> 'sozinho_em_risco', m ->> 'sem_lider', m ->> 'troca_de_lider',
                    m ->> 'correcoes_quem_vai', m -> 'etiquetas', m ->> 'retrabalho');
    t2 := (select string_agg(x ->> 'numero' || ' ' || (x ->> 'dia') || ' ' || (x ->> 'turno') || ' ' || (x ->> 'falta'), ', ')
             from jsonb_array_elements(m -> 'detalhe' -> 'sozinho_em_risco') x);
    t3 := (select string_agg((x ->> 'dia') || ' ' || (x ->> 'quem'), ', ') from jsonb_array_elements(m -> 'detalhe' -> 'dono_em_tarefa_de_outro') x)
          || ' | ' || pg_temp.como(pg_temp.adm(), 'authenticated',
                        'select (public.agenda_habilidade_medidas(date ''2026-10-05'', date ''2026-11-18'', date ''2026-11-04'') ->> ''dono_em_tarefa_de_outro'')');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R7a as medidas: dono_em_tarefa_de_outro = 3 (os 3 meios-dias do dono numa OS de 12 V com alguém da equipe livre que dava conta), sozinho_em_risco = 2 (a 179 e, já passado, o João sozinho na 97006 da 7a), nenhuma troca, as etiquetas (1 do dono, 3 do gestor valendo) e o retrabalho não medido',
    t1 = '3 | 2 | 0 | 0 | 0 | {"dono": 1, "propostas": 0, "gestor_vale": 3} | nao_medido', t1);
  v_res := pg_temp.ok(v_res, 'R7b sozinho_em_risco é a janela inteira, as passadas também (a 97006 de ter 03/11, pelas etiquetas de hoje) e a 179 (o João sozinho no último meio-dia, que pede 220 V); os 3 meios-dias do dono com quem faria (o menos qualificado que dava conta); o admin logado lê as medidas',
    t2 = 'OS-97006 2026-11-03 manha energizado, OS-97179 2026-11-10 tarde energizado' and t3 = '2026-10-20 João, 2026-10-22 João, 2026-10-27 João | 3', t2 || ' | ' || t3);
  perform pg_temp.gravar(v_res);
end
$r7$;

-- ── R8. A rodada ─────────────────────────────────────────────────────────────────────────────────────────────────────
create function pg_temp.mensagens() returns text language sql stable as $f$
  select concat_ws(' ', (select count(*) from public.agenda_equipe_mensagens), (select count(*) from public.agenda_cliente_mensagens),
                   (select count(*) from public.agenda_fornecedor_mensagens), (select count(*) from public.agenda_dono_avisos))
$f$;
create function pg_temp.chaves(p jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(k, ',' order by k), '-') from jsonb_object_keys(coalesce(p, '{}'::jsonb)) k
$f$;
do $r8$
declare
  v_res jsonb := '[]'::jsonb;
  r     jsonb;
  t1    text;
  t2    text;
  t3    text;
  t4    text;
  t5    text;
  t6    text;
  v_msg text;
  v_n   text;
begin
  if not pg_temp.carregada() then
    insert into _resultado values ('R8 a rodada', true, 'PULADO: sem as fixtures (rode pela bancada)');
    return;
  end if;
  -- (a) a hora, uma vez por dia, a linha da rotina e nenhuma mensagem
  begin
    perform pg_temp.mv();
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    v_msg := pg_temp.mensagens();
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:05'));
    t1 := (r - 'hora')::text;
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    t2 := (r ->> 'rodou') || ' ' || (r ->> 'erros') || ' ' || pg_temp.chaves(r -> 'contagens') || ' ' || (r -> 'modos')::text;
    t3 := (select x.rotina || ' ' || x.p_hoje || ' ' || pg_temp.chaves(x.contagens) || ' ' || x.erros
             from public.agenda_vigia_rodadas x where x.rotina = 'habilidade');
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:30'));
    t4 := r::text || ' ' || (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'habilidade') || ' '
          || (pg_temp.mensagens() = v_msg);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R8a antes de habilidade_hora (16:10) a rodada não roda (cedo)',
    t1 = '{"cedo": true, "modos": {"modo_lider": "sombra", "modo_habilidade": "sombra", "modo_habilidade_propor": "ligado"}, "rodou": false}', t1);
  v_res := pg_temp.ok(v_res, 'R8b no 1º tique depois da hora, os passos do modo (em teste: propor, vetos, conferir, medir; perguntas_os só ligado) e a linha da rotina habilidade com as contagens, os modos e as falhas',
    t2 = 'true 0 conferir,medir,propor,vetos {"modo_lider": "sombra", "modo_habilidade": "sombra", "modo_habilidade_propor": "ligado"}'
    and t3 = 'habilidade 2026-11-04 conferir,falhas,medir,modos,propor,vetos 0', t2 || ' | ' || t3);
  v_res := pg_temp.ok(v_res, 'R8c uma vez por dia (o 2º tique: ja_rodou, sem outra linha) e nenhuma mensagem nova a ninguém (equipe, cliente, fornecedor, aviso ao dono)',
    t4 = '{"modos": {"modo_lider": "sombra", "modo_habilidade": "sombra", "modo_habilidade_propor": "ligado"}, "rodou": false, "ja_rodou": true} 1 true', t4);

  -- (b) com tudo desligado: só o prazo e a medida rodam, e nada é escrito além da linha da rodada
  begin
    perform pg_temp.mv();
    perform pg_temp.modos7c('desligado', 'desligado', 'desligado');
    v_n := (select count(*) from public.agenda_etiquetas) || ' ' || (select count(*) from public.agenda_perguntas) || ' '
           || (select count(*) from public.agenda_acoes);
    r := public.agenda_habilidade(date '2026-11-05', pg_temp.em(date '2026-11-05', '16:15'));
    t5 := pg_temp.chaves(r -> 'contagens') || ' ' || (((select count(*) from public.agenda_etiquetas) || ' '
          || (select count(*) from public.agenda_perguntas) || ' ' || (select count(*) from public.agenda_acoes)) = v_n);
    -- ligada: perguntas_os roda e conferir não (nada em teste)
    perform pg_temp.modos7c('ligado', 'ligado', 'ligado');
    r := public.agenda_habilidade(date '2026-11-06', pg_temp.em(date '2026-11-06', '16:15'));
    t5 := t5 || ' | ' || pg_temp.chaves(r -> 'contagens');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R8d com os 3 modos desligados só o prazo (vetos) e a medida rodam, e nada além da linha da rodada é escrito; ligada, perguntas_os roda e conferir não',
    t5 = 'medir,vetos true | medir,perguntas_os,propor,vetos', t5);

  -- (c) o passo que falha: a rodada segue, os outros rodam, a falha vai a app_error_logs (agenda / habilidade:<passo>)
  begin
    perform pg_temp.mv();
    perform pg_temp.modos7c('sombra', 'sombra', 'ligado');
    create or replace function public._agenda_habilidade_conferir(p_hoje date, p_agora timestamptz) returns jsonb
    language plpgsql as $x$ begin raise exception 'falha de teste na conferência'; end $x$;
    r := public.agenda_habilidade(date '2026-11-04', pg_temp.em(date '2026-11-04', '16:15'));
    t6 := (r ->> 'erros') || ' ' || (r -> 'falhas' -> 0 ->> 'passo') || ' ' || pg_temp.chaves(r -> 'contagens') || ' '
          || (select count(*) from public.app_error_logs e where e.context = 'agenda' and e.action = 'habilidade:conferir') || ' '
          || (select x.erros || ' ' || jsonb_array_length(x.contagens -> 'falhas') from public.agenda_vigia_rodadas x where x.rotina = 'habilidade')
          || ' ' || (select count(*) from public.agenda_etiquetas e where e.estado = 'proposta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.ok(v_res, 'R8e o passo que falha (conferir): a rodada não lança, conta 1 erro e diz qual, os outros passos rodaram (a proposta gravou), a falha está em app_error_logs (agenda / habilidade:conferir) e na linha da rodada',
    t6 = '1 conferir medir,propor,vetos 1 1 1 2', t6);
  perform pg_temp.gravar(v_res);
end
$r8$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
