-- Prova do A5 + A4 do pacote 1 do assistente (26/11/2026; migration 20270301120400_agenda_p1_manha_de_ontem.sql): a conferência do dia útil anterior
-- ainda aberta e as perguntas que sobraram do fechamento das 17:30 vão na manhã das 07:30, até agenda_config.manha_sobras_max linhas (nasce 0 = como
-- antes; ligar = 3). Sem mensagem nova, sem número de opção, sem prazo.
-- bancada: depende de 20270301120400
--
--   P0  a forma (vale em produção, nada grava): _agenda_ontem_da_manha invoker, stable, search_path=public, ninguém de fora executa (a porta de
--       _agenda_terminou_da_manha), nenhum UPDATE/DELETE/INSERT, nenhum log (a manhã roda na transação só de leitura do PostgREST);
--       agenda_aprovacoes_da_manha continua definer, stable, só service_role; tirados os 3 blocos "-- P1 AGENDA:" o corpo é o de produção de
--       26/11/2026 (md5 sem CR c72a562b…), e tirados também os "-- TERMINOU:", o de 19/11 (2b1ce097…); as 3 saídas embrulhadas, nada mais; o
--       comentário de antes + o trecho P1 AGENDA, uma vez
--   P1  as recusas: sem o dia ou a hora (22004); com a chave em 0 a interna devolve p_cli como veio (até nulo), sem ler nada
--   Sobre a fixture-fase5 (a semana de 03 a 06/11 publicada: qui 05/11 o Vanderlei, OS-00069, com o Roberto o dia todo e o Gustavo, o dono,
--   fechando; sex 06/11 o Lenine, OS-00074, com o João de manhã e o Gustavo abrindo; a pergunta crítica do Nelson aberta) e as perguntas de teste:
--   M1  chave 0: agenda_aprovacoes_da_manha = a de antes (o corpo sem os blocos P1, rodado como pg_temp), byte a byte, nas 3 saídas (modo_cliente
--       fora de ligado; ligado sem mensagem; ligado com a véspera do Flávio), com a conferência e as sobras presentes; chave 3: a de antes + o bloco
--   M2  chave 3: a conferência de ontem aberta é a 1ª linha, com o texto exato e a data do dia útil anterior: sex 06/11 diz "Ontem (qui 05/11)";
--       seg 09/11 (segunda depois de sexta) diz "Em sex 06/11" e o cabeçalho "ficou de sex 06/11"; até 3 OS no plano, "e mais N"; a de outro dia,
--       em teste ou fechada não entra; só a conferência: sem a última linha
--   M3  chave 3: as sobras na ordem de agenda_perguntas_em_ordem, até 3 linhas contando a conferência, "• e mais N em *agenda pendências*" certo;
--       fora a mostrada no fechamento de ontem (o último dia guardado; o de antes não esconde; o que caiu não esconde), a cliente_aprovar e a
--       terminou:%
--   M4  nenhuma linha casa a régua de AGENDA_NUMERADA_NA_CONVERSA (whatsapp-channel.ts) nem traz "Sem resposta até" ou "opção"
--   M5  a pergunta com mostrada_vezes >= perguntas_vezes_max não sai (a 1 vez a menos sai)
--   M6  toda linha de linhas[] tem pergunta_id (aprovacoesDaResposta lança sem ela); a guarda da manhã aceita as linhas como o Secretário as manda
--       e, com a fila em sent, cada uma conta 1 vez via manha, sem prazo nascer (veto_ate continua nulo) e sem tocar a que não foi escrita
--   M7  nada sobrando e sem conferência: a resposta é p_cli inalterado (a interna e a manhã inteira = a de antes)
--   M8  (crítica de risco) nenhuma linha do bloco com "?" sem a palavra de comando entre asteriscos; a da conferência não pergunta
--   M9  (correção desta construção) a pergunta com prazo gravado (veto_ate) não sai: mostrar o título sem a data armaria a opção padrão
--       (_agenda_gestor_vetos); nem a com opção escolhida, nem a que um aviso do gestor de hoje levou (a crítica, sim): as regras do bloco das 17:30
--   M10 erro ao montar (agenda_perguntas_em_ordem recusa o papel): p_cli como veio + ontem.erro; o bloco do cliente e o "terminou?" ficam
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_p1_manha.sql
--   Sem a fixture (produção) M sai PULADO; P0 e P1 rodam e não gravam nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O corpo (prosrc, sem CR) de uma função pela assinatura.
create function pg_temp.src(p_assinatura text) returns text language sql stable as $f$
  select replace(p.prosrc, chr(13), '') from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- Tira os blocos "-- <marca>: … -- <marca>: fim", devolvendo as linhas "--antes:" de dentro deles: o corpo de antes.
create function pg_temp.sem_blocos(p text, p_marca text) returns text language sql immutable as $st$
  select array_to_string(array(
           select case when dentro > 0 and l ~ '^--antes:' then substr(l, 9) else l end
             from (select l, o, sum(case when l ~ ('^\s*-- (' || p_marca || '):') and l !~ ('^\s*-- (' || p_marca || '): fim') then 1
                                         when l ~ ('^\s*-- (' || p_marca || '): fim') then -1 else 0 end)
                                over (order by o rows between unbounded preceding and current row) as dentro,
                          l ~ ('^\s*-- (' || p_marca || '): fim') as fecha
                     from unnest(string_to_array(replace(p, chr(13), ''), E'\n')) with ordinality u(l, o)) x
            where (dentro = 0 and not fecha) or (dentro > 0 and l ~ '^--antes:')
            order by o), E'\n')
$st$;
-- A porta de uma função: "definer volatilidade | anon authenticated service_role public" (EXECUTE; t ou f).
create function pg_temp.porta(p_assinatura text) returns text language sql stable as $f$
  select format('%s %s | %s %s %s %s', p.prosecdef, p.provolatile, has_function_privilege('anon', p.oid, 'execute'),
                has_function_privilege('authenticated', p.oid, 'execute'), has_function_privilege('service_role', p.oid, 'execute'),
                coalesce((select bool_or(a.grantee = 0) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.privilege_type = 'EXECUTE'), false))
    from pg_proc p where p.oid = to_regprocedure(p_assinatura)
$f$;
-- UPDATE/DELETE sem WHERE no nível de cima (o detector da 20261112300000, resumido: sem comentários nem strings).
create function pg_temp.sem_where(p_corpo text) returns setof text language sql immutable as $f$
  with c as (
    select regexp_replace(regexp_replace(p_corpo, '--[^\n]*', '', 'g'), '''(?:[^'']|'''')*''', '''''', 'g') as corpo
  )
  select btrim(regexp_replace(m[1], '\s+', ' ', 'g'))
    from c, regexp_matches(c.corpo, '(?<![a-z0-9_.])((?:update|delete\s+from)\s+(?:only\s+)?(?!(?:set|of|on|or|loop|skip|nowait)\M)(?:[a-z_][a-z0-9_]*\.)?[a-z_][a-z0-9_]*\M[^;]*)', 'gi') as m
   where m[1] !~* '\mwhere\M'
$f$;
-- O bloco da manhã que esta frente junta (do "Da agenda, ficou de" ao fim do texto) e as linhas dele.
create function pg_temp.bloco(p_r jsonb) returns text language sql immutable as $f$
  select case when position('Da agenda, ficou de ' in coalesce(p_r ->> 'texto', '')) > 0
              then substr(p_r ->> 'texto', position('Da agenda, ficou de ' in p_r ->> 'texto')) end
$f$;
-- As linhas de linhas[] que vieram do bloco (as de pergunta_id na lista dada), na ordem.
create function pg_temp.ids(p_r jsonb) returns text language sql immutable as $f$
  select coalesce(string_agg(x ->> 'pergunta_id', ',' order by o), '') from jsonb_array_elements(coalesce(p_r -> 'linhas', '[]'::jsonb)) with ordinality t(x, o)
$f$;
-- Uma pergunta de teste, aberta em ligado (o gatilho do padrão preenche padrao_chave/padrao_efeito pelo tipo).
create function pg_temp.perg(p_tipo text, p_chave text, p_os uuid, p_texto text, p_criada timestamptz, p_opcoes jsonb default '[]'::jsonb,
                             p_rec smallint default null, p_padrao smallint default null, p_veto timestamptz default null,
                             p_escolhida smallint default null, p_vezes smallint default 0) returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  insert into public.agenda_perguntas (tipo, chave, service_order_id, os_ids, texto, modo, criada_em, opcoes, recomendacao, opcao_padrao, veto_ate,
                                       opcao_escolhida, mostrada_vezes, mostrada_em, mostrada_via)
  values (p_tipo, p_chave, p_os, case when p_os is null then '{}'::uuid[] else array[p_os] end, p_texto, 'ligado', p_criada, p_opcoes, p_rec, p_padrao, p_veto,
          p_escolhida, p_vezes, case when p_vezes > 0 then p_criada end, case when p_vezes > 0 then 'fechamento' end)
  returning id into v;
  return v;
end $f$;
-- (da agenda_aprovacao_na_manha.sql) liga a mensagem ao cliente; e a véspera do Flávio (ter 03/11), pela rodada, registrada às 09:30 de sex 30/10.
create function pg_temp.ligar(p_aprov int default 3) returns void language sql as $f$
  update public.agenda_config
     set modo_cliente = 'ligado', cliente_aprovacao_dias = p_aprov,
         cliente_tipos_ligados = array['confirmar', 'vespera', 'acesso', 'material_chegou', 'andamento', 'pode_atrasar', 'nova_data',
                                       'pronto', 'pronto_lembrete', 'pos_servico', 'mudanca_no_dia']
   where id
$f$;
create function pg_temp.vespera_flavio() returns uuid language plpgsql as $f$
declare
  r jsonb;
begin
  perform set_config('agenda_teste.hoje', '2026-10-30', true);
  r := public._agenda_cliente_registrar('vespera', null, '05000000-0000-4000-8000-000000000104', date '2026-11-03', '{}'::jsonb,
                                        pg_temp.em(date '2026-11-02', '09:00'), null, 'rodada', null, pg_temp.em(date '2026-10-30', '09:30'));
  return (r ->> 'id')::uuid;
end $f$;

-- ── P0. A forma (vale em produção; nada grava) ───────────────────────────────────────────────────────────────────────────────────────
do $p0$
declare
  v_res   jsonb := '[]'::jsonb;
  c_nova  constant text := 'public._agenda_ontem_da_manha(jsonb,date,timestamptz)';
  c_manha constant text := 'public.agenda_aprovacoes_da_manha(date,timestamptz)';
  v_txt   text;
  v_nova  text;
  v_com   text;
begin
  v_res := pg_temp.ok(v_res, format('P0a %s: invoker, stable | anon authenticated service_role public = ninguém (a porta de _agenda_terminou_da_manha) e search_path=public', c_nova),
    pg_temp.porta(c_nova) = 'f s | f f f f' and pg_temp.porta(c_nova) = pg_temp.porta('public._agenda_terminou_da_manha(jsonb,date,timestamptz)')
    and exists (select 1 from pg_proc p, unnest(p.proconfig) c where p.oid = to_regprocedure(c_nova) and replace(c, '"', '') = 'search_path=public'),
    coalesce(pg_temp.porta(c_nova), 'NÃO EXISTE') || ' config ' || coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure(c_nova)), '-'));
  v_res := pg_temp.ok(v_res, format('P0b %s: a porta de antes (definer, stable, só service_role) e search_path=public', c_manha),
    pg_temp.porta(c_manha) = 't s | f f t f'
    and exists (select 1 from pg_proc p, unnest(p.proconfig) c where p.oid = to_regprocedure(c_manha) and replace(c, '"', '') = 'search_path=public'),
    coalesce(pg_temp.porta(c_manha), 'NÃO EXISTE'));
  v_nova := coalesce(pg_temp.src(c_nova), '');
  v_res := pg_temp.ok(v_res, 'P0c a nova só lê: nenhum UPDATE/DELETE sem WHERE, nenhum insert/update/delete, nenhum log_app_error nem perform (a manhã roda em transação só de leitura)',
    not exists (select 1 from pg_temp.sem_where(v_nova))
    and regexp_replace(v_nova, '--[^\n]*', '', 'g') !~* '\m(insert\s+into|update\s+public|delete\s+from|log_app_error|perform)\M',
    (select string_agg(x, ' | ') from pg_temp.sem_where(v_nova) x));
  v_txt := coalesce(pg_temp.src(c_manha), '');
  v_res := pg_temp.ok(v_res, 'P0d agenda_aprovacoes_da_manha sem os 3 blocos "-- P1 AGENDA:" = o corpo de produção de 26/11/2026 (md5 sem CR c72a562b…); sem eles e sem os "-- TERMINOU:", o de 19/11 (2b1ce097…)',
    md5(pg_temp.sem_blocos(v_txt, 'P1 AGENDA')) = 'c72a562b840b91cf02be23b722113a5c'
    and md5(pg_temp.sem_blocos(pg_temp.sem_blocos(v_txt, 'P1 AGENDA'), 'TERMINOU')) = '2b1ce097e178e73c5668fad5b44298e0'
    and md5(v_txt) <> 'c72a562b840b91cf02be23b722113a5c'
    and (select count(*) from regexp_matches(v_txt, '-- P1 AGENDA: fim', 'g')) = 3,
    format('%s / %s / %s blocos', md5(pg_temp.sem_blocos(v_txt, 'P1 AGENDA')), md5(pg_temp.sem_blocos(pg_temp.sem_blocos(v_txt, 'P1 AGENDA'), 'TERMINOU')),
           (select count(*) from regexp_matches(v_txt, '-- P1 AGENDA: fim', 'g'))));
  v_res := pg_temp.ok(v_res, 'P0e as 3 saídas embrulhadas e só elas: 3 chamadas _agenda_ontem_da_manha(public._agenda_terminou_da_manha(…), p_hoje, p_agora) e nenhuma _agenda_terminou_da_manha solta fora do --antes:',
    (select count(*) from regexp_matches(v_txt, 'return public\._agenda_ontem_da_manha\(public\._agenda_terminou_da_manha\([^\n]*, p_hoje, p_agora\), p_hoje, p_agora\);', 'g')) = 3
    and (select count(*) from regexp_matches(v_txt, '(^|\n)[ \t]+return public\._agenda_terminou_da_manha\(', 'g')) = 0
    and (select count(*) from regexp_matches(v_txt, '(^|\n)--antes:[ \t]+return public\._agenda_terminou_da_manha\(', 'g')) = 3,
    null);
  v_com := coalesce(obj_description(to_regprocedure(c_manha), 'pg_proc'), '');
  v_res := pg_temp.ok(v_res, 'P0f o comentário da manhã: o de antes (Opção A e TERMINOU) + o trecho P1 AGENDA, uma vez; a nova tem o dela',
    v_com like 'Agenda de Produção%' and v_com like '% TERMINOU (23/11/2026%'
    and (select count(*) from regexp_matches(v_com, 'P1 AGENDA \(A5/A4, 26/11/2026', 'g')) = 1
    and coalesce(obj_description(to_regprocedure(c_nova), 'pg_proc'), '') like 'Agenda de Produção, pacote 1 do assistente, A5/A4%',
    right(v_com, 120));
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── P1. As recusas (nada grava) ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $p1$
declare
  v_res jsonb := '[]'::jsonb;
  v_err text := '';
  c_cli constant jsonb := '{"total": 1, "linhas": [{"pergunta_id": "x"}], "texto": "📨 o cliente"}';
begin
  begin
    perform public._agenda_ontem_da_manha('{}'::jsonb, null, now());
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  begin
    perform public._agenda_ontem_da_manha('{}'::jsonb, current_date, null);
  exception when others then v_err := v_err || sqlstate || ';';
  end;
  v_res := pg_temp.ok(v_res, 'P1a sem o dia ou a hora: 22004 nas duas', v_err = '22004;22004;', v_err);
  -- a chave como está agora (nasce 0): com 0, p_cli como veio, até o nulo
  if (select c.manha_sobras_max from public.agenda_config c where c.id) = 0 then
    v_res := pg_temp.ok(v_res, 'P1b chave 0: a interna devolve p_cli como veio (o objeto, byte a byte, e o nulo)',
      public._agenda_ontem_da_manha(c_cli, current_date, now())::text = c_cli::text
      and public._agenda_ontem_da_manha(null, current_date, now()) is null, null);
  else
    insert into _resultado values ('P1b chave 0: a interna devolve p_cli como veio', true,
                                   'PULADO: a chave já está ligada aqui (' || (select c.manha_sobras_max from public.agenda_config c where c.id) || ')');
  end if;
  perform pg_temp.gravar(v_res);
end
$p1$;

-- ── M. A manhã sobre a fixture-fase5 ─────────────────────────────────────────────────────────────────────────────────────────────────
do $m$
declare
  v_res    jsonb := '[]'::jsonb;
  c_manha  constant text := 'public.agenda_aprovacoes_da_manha(date,timestamptz)';
  c_van    constant uuid := '05000000-0000-4000-8000-000000000069';
  c_len    constant uuid := '05000000-0000-4000-8000-000000000074';
  c_fla    constant uuid := '05000000-0000-4000-8000-000000000104';
  c_rod    constant uuid := '05000000-0000-4000-8000-000000000096';
  c_mick   constant uuid := 'bb000000-0000-4000-8000-000000000004';
  d04      constant date := date '2026-11-04';
  d05      constant date := date '2026-11-05';
  d06      constant date := date '2026-11-06';
  d09      constant date := date '2026-11-09';
  c_ultima constant text := 'Não responda só *sim*: use as suas palavras ou as de *agenda pendências*, onde estão as opções de cada uma.';
  c_conf05 constant text := 'Ontem (qui 05/11) o plano era: Vanderlei (OS-00069) com o Roberto, o dia todo (você fecha). Se foi como o plano, responda *dia feito 05/11*; se não, *dia parcial* ou *dia não* com o motivo e a data (ex.: *dia parcial material 05/11*).';
  c_conf06 constant text := 'Em sex 06/11 o plano era: Lenine (OS-00074) com o João, de manhã (você abre). Se foi como o plano, responda *dia feito 06/11*; se não, *dia parcial* ou *dia não* com o motivo e a data (ex.: *dia parcial material 06/11*).';
  c_nelson constant text := 'Nelson: Não cabe tudo até qui 05/11.';
  c_qa     constant text := 'Vanderlei: A OS-00069 está parada desde segunda. Deixo como está no plano.';
  c_qb     constant text := 'A bomba do Lenine chegou? Conto que ainda não chegou. (*agenda pendências* mostra inteira)';
  c_qc     constant text := 'O Flávio passou da estimativa. Deixo como está no plano.';
  -- a régua de AGENDA_NUMERADA_NA_CONVERSA (supabase/functions/_shared/ai/whatsapp-channel.ts), a mesma em POSIX ARE
  c_numerada constant text := 'Decisão \d+:|(^|\s)1\) [^\n]*;\s2\) |(^|\n)[ \t]*1[.)] [^\n]*\n\s*2[.)] ';
  v_nelson uuid;
  v_conf05 uuid;
  v_conf06 uuid;
  qa uuid; qb uuid; qc uuid; qd uuid; qe uuid; qf uuid; qg uuid; qh uuid; qi uuid; qj uuid; qk uuid; ql uuid; qm uuid;
  v_todas  jsonb := '[]'::jsonb;   -- toda saída com o bloco, para M4, M6 e M8
  r        jsonb;
  r0       jsonb;
  r1       jsonb;
  a        jsonb;
  v_m      uuid;
  v_dia    date;
  v_manha  timestamptz;
  v_f      uuid;
  v_txt    text;
  v_n      int;
  v_ok     boolean;
  v_lin    text;
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('M1–M10 (fixture-fase5)', true, 'PULADO: sem agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase5');
  -- a manhã de antes: o corpo de hoje sem os blocos P1 (o de produção de 26/11), rodada como pg_temp, para o byte a byte
  execute format('create function pg_temp.manha_antes(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql stable as %L',
                 pg_temp.sem_blocos(pg_temp.src(c_manha), 'P1 AGENDA'));
  select x.id into v_nelson from public.agenda_perguntas x where x.estado = 'aberta' and x.tipo = 'nao_cabe';
  v_res := pg_temp.ok(v_res, 'M0 o ponto de partida: a chave nasce 0, perguntas_vezes_max 2, modo_cliente desligado, sábado não é dia útil; aberta só a crítica do Nelson',
    (select c.manha_sobras_max = 0 and c.perguntas_vezes_max = 2 and c.modo_cliente = 'desligado' and not c.sabado_util from public.agenda_config c where c.id)
    and (select count(*) from public.agenda_perguntas x where x.estado = 'aberta') = 1 and v_nelson is not null
    and public.agenda_somar_du(d06, -1) = d05 and public.agenda_somar_du(d09, -1) = d06,
    (select string_agg(x.tipo || ' ' || x.chave, ', ') from public.agenda_perguntas x where x.estado = 'aberta'));

  -- A conferência de qui 05/11 (como a vigia a cria às 13:00) e as perguntas de teste, na ordem em que nascem (agenda_perguntas_em_ordem: a crítica
  -- que perde até amanhã primeiro, depois criada_em). Elegíveis: Nelson, qa, qb, qc, qd, qe e qj (7). Fora: qf (o fechamento de ontem), qg
  -- (cliente_aprovar), qh (terminou:%), qi (mostrada 2 vezes), qk (prazo), ql (opção escolhida), qm (o aviso de hoje).
  insert into public.agenda_perguntas (tipo, chave, dia, texto, modo, criada_em, os_ids)
  values ('conferencia', 'conferencia:2026-11-05', d05, 'Agenda de hoje: Vanderlei (OS-00069) — você fecha, Roberto o dia todo. Foi isso? Responda *dia feito* ou conte o que mudou.',
          'ligado', pg_temp.em(d05, '13:00'), array[c_van])
  returning id into v_conf05;
  qa := pg_temp.perg('parada', 'parada:teste-a', c_van, 'A OS-00069 está parada desde segunda. Quer que eu tire o dia?', pg_temp.em(d05, '09:00'));
  qb := pg_temp.perg('chegou', 'chegou:teste-b', c_len, 'A bomba do Lenine chegou?', pg_temp.em(d05, '09:10'));
  qc := pg_temp.perg('estouro', 'estouro:teste-c', c_fla, 'O Flávio passou da estimativa. Aumento os dias?', pg_temp.em(d05, '09:20'));
  qd := pg_temp.perg('situacao', 'situacao:teste-d', c_rod, 'O Rodrigo começou sem rastro: quantos dias faltam? 1) 1 dia (recomendo) 2) 2 dias',
                     pg_temp.em(d05, '09:30'), '[{"n": 1, "texto": "1 dia"}, {"n": 2, "texto": "2 dias"}]'::jsonb, 1::smallint);
  qe := pg_temp.perg('parada', 'parada:teste-e', c_len, 'O Lenine parou por chuva. Remarco?', pg_temp.em(d05, '09:40'));
  qf := pg_temp.perg('estouro', 'estouro:teste-f', c_van, 'A OS-00069 estourou a estimativa.', pg_temp.em(d05, '09:50'));
  qg := pg_temp.perg('cliente_aprovar', 'cliente_aprovar:teste-g', c_fla, 'Aviso ao Flávio sobre o dia 06. Mando?', pg_temp.em(d05, '10:00'));
  qh := pg_temp.perg('concluir', 'terminou:' || c_len, c_len, 'A OS-00074 (Lenine) terminou ou falta dia? Responda *concluiu OS-00074* ou *falta dia OS-00074*.',
                     pg_temp.em(d05, '10:10'));
  qi := pg_temp.perg('parada', 'parada:teste-i', c_rod, 'O Rodrigo está parado. Quer que eu tire o dia?', pg_temp.em(d05, '10:20'), p_vezes => 2::smallint);
  qj := pg_temp.perg('chegou', 'chegou:teste-j', c_rod, 'O cabo do Rodrigo chegou?', pg_temp.em(d05, '10:30'), p_vezes => 1::smallint);
  qk := pg_temp.perg('situacao', 'situacao:teste-k', c_fla, 'O Flávio começou sem rastro: quantos dias faltam? 1) 1 dia (recomendo) 2) 2 dias',
                     pg_temp.em(d05, '10:40'), '[{"n": 1, "texto": "1 dia"}, {"n": 2, "texto": "2 dias"}]'::jsonb, 1::smallint, 1::smallint, pg_temp.em(d06, '18:00'));
  ql := pg_temp.perg('situacao', 'situacao:teste-l', c_van, 'O Vanderlei começou sem rastro: quantos dias faltam? 1) 1 dia (recomendo) 2) 2 dias',
                     pg_temp.em(d05, '10:50'), '[{"n": 1, "texto": "1 dia"}, {"n": 2, "texto": "2 dias"}]'::jsonb, 1::smallint, p_escolhida => 2::smallint);
  qm := pg_temp.perg('parada', 'parada:teste-m', c_fla, 'O Flávio está parado. Quer que eu tire o dia?', pg_temp.em(d05, '11:00'));
  -- o fechamento de qua 04/11 mostrou qb (o de antes: não esconde) e o de qui 05/11, qf (o último guardado antes de hoje: esconde)
  insert into public.agenda_fechamento_fila (dia, fila_id, via, linhas, estado, enviada_em, resolvida_em, criada_em)
  values (d04, gen_random_uuid(), 'fechamento', jsonb_build_array(jsonb_build_object('pergunta_id', qb, 'acao_ids', '[]'::jsonb)), 'registrada',
          pg_temp.em(d04, '17:31'), pg_temp.em(d04, '17:45'), pg_temp.em(d04, '17:30')),
         (d05, gen_random_uuid(), 'fechamento', jsonb_build_array(jsonb_build_object('pergunta_id', null, 'acao_ids', '[]'::jsonb, 'pergunta_ids', jsonb_build_array(qf))),
          'registrada', pg_temp.em(d05, '17:31'), pg_temp.em(d05, '17:45'), pg_temp.em(d05, '17:30'));
  -- um aviso do gestor de hoje (sex 06/11, 07:00) levou qm e a crítica do Nelson
  insert into public.agenda_dono_avisos (rodada, dia, texto, acao_ids, pergunta_ids, com_perguntas, telefone, enviar_em, estado, dedupe_key, enviada_em)
  values (pg_temp.em(d06, '07:00'), d06, 'Aviso de teste', array[gen_random_uuid()], array[qm, v_nelson], true, '5547900000210', pg_temp.em(d06, '07:00'),
          'enviada', 'agenda-dono:teste:' || d06, pg_temp.em(d06, '07:01'));

  -- ── M1. Chave 0: a manhã de antes, byte a byte, nas 3 saídas; chave 3: a de antes + o bloco ──
  begin
    -- saída 1: modo_cliente fora de ligado
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    r0 := pg_temp.manha_antes(d06, pg_temp.em(d06, '07:30'));
    update public.agenda_config set manha_sobras_max = 3 where id;
    r1 := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    update public.agenda_config set manha_sobras_max = 0 where id;
    v_res := pg_temp.ok(v_res, 'M1a saída 1 (modo_cliente desligado), chave 0: igual à de antes, byte a byte, com a conferência e as sobras presentes; chave 3: a de antes + o bloco',
      r::text = r0::text and r0 ->> 'texto' is null
      and r1 ->> 'texto' = pg_temp.bloco(r1) and r1 - 'texto' - 'linhas' - 'ontem' = r0 - 'texto' - 'linhas' and r1 ? 'ontem',
      r::text || ' | ' || r0::text || ' | ' || r1::text);
    -- saída 2: modo_cliente ligado, nenhuma mensagem esperando
    perform pg_temp.ligar(3);
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    r0 := pg_temp.manha_antes(d06, pg_temp.em(d06, '07:30'));
    update public.agenda_config set manha_sobras_max = 3 where id;
    r1 := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    update public.agenda_config set manha_sobras_max = 0 where id;
    v_res := pg_temp.ok(v_res, 'M1b saída 2 (ligado, nada esperando), chave 0: igual à de antes, byte a byte; chave 3: a de antes + o bloco',
      r::text = r0::text and (r0 ->> 'total')::int = 0
      and r1 ->> 'texto' = pg_temp.bloco(r1) and r1 - 'texto' - 'linhas' - 'ontem' = r0 - 'texto' - 'linhas',
      r::text || ' | ' || r0::text || ' | ' || r1::text);
    -- saída 3: a véspera do Flávio esperando o *manda cliente*
    v_m := pg_temp.vespera_flavio();
    select (m.valida_ate at time zone 'America/Sao_Paulo')::date into v_dia from public.agenda_cliente_mensagens m where m.id = v_m;
    v_manha := pg_temp.em(v_dia, '07:30');
    r := public.agenda_aprovacoes_da_manha(v_dia, v_manha);
    r0 := pg_temp.manha_antes(v_dia, v_manha);
    update public.agenda_config set manha_sobras_max = 3 where id;
    r1 := public.agenda_aprovacoes_da_manha(v_dia, v_manha);
    update public.agenda_config set manha_sobras_max = 0 where id;
    v_res := pg_temp.ok(v_res, 'M1c saída 3 (a véspera do Flávio esperando), chave 0: igual à de antes, byte a byte; chave 3: o texto de antes, uma linha em branco e o bloco; as linhas de antes primeiro',
      r::text = r0::text and (r0 ->> 'total')::int = 1 and r0 ->> 'texto' like '📨 %'
      and r1 ->> 'texto' = (r0 ->> 'texto') || E'\n\n' || pg_temp.bloco(r1)
      and (select jsonb_agg(x order by o) from jsonb_array_elements(r1 -> 'linhas') with ordinality t(x, o) where o <= jsonb_array_length(r0 -> 'linhas'))
          = r0 -> 'linhas'
      and jsonb_array_length(r1 -> 'linhas') = jsonb_array_length(r0 -> 'linhas') + (r1 #>> '{ontem,escritas}')::int
      and r1 - 'texto' - 'linhas' - 'ontem' = r0 - 'texto' - 'linhas',
      r1::text);
    v_todas := v_todas || jsonb_build_array(r1);
    raise exception 'desfaz' using errcode = 'P0091';
  exception when sqlstate 'P0091' then null;
  end;

  update public.agenda_config set manha_sobras_max = 3 where id;

  -- ── M2. A conferência de ontem ──
  r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
  v_todas := v_todas || jsonb_build_array(r);
  v_res := pg_temp.ok(v_res, 'M2a sex 06/11: a 1ª linha é a conferência de qui 05/11, com o texto exato (o plano de v_agenda_dia, *dia feito 05/11*), a pergunta dela em linhas[]; o cabeçalho "Da agenda, ficou de ontem:"',
    r #>> '{linhas,0,texto}' = c_conf05 and r #>> '{linhas,0,pergunta_id}' = v_conf05::text
    and pg_temp.bloco(r) like 'Da agenda, ficou de ontem:' || E'\n' || '• ' || c_conf05 || E'\n%',
    pg_temp.bloco(r));
  begin
    insert into public.agenda_perguntas (tipo, chave, dia, texto, modo, criada_em, os_ids)
    values ('conferencia', 'conferencia:2026-11-06', d06, 'Agenda de hoje: Lenine (OS-00074) — você abre, João de manhã. Foi isso? Responda *dia feito* ou conte o que mudou.',
            'ligado', pg_temp.em(d06, '13:00'), array[c_len])
    returning id into v_conf06;
    r := public.agenda_aprovacoes_da_manha(d09, pg_temp.em(d09, '07:30'));
    v_todas := v_todas || jsonb_build_array(r);
    v_res := pg_temp.ok(v_res, 'M2b seg 09/11 (segunda depois de sexta): a conferência de sex 06/11, "Em sex 06/11 o plano era: …", *dia feito 06/11*, e o cabeçalho "Da agenda, ficou de sex 06/11:"; a de qui 05/11 (dois dias úteis antes) não entra',
      r #>> '{linhas,0,texto}' = c_conf06 and r #>> '{linhas,0,pergunta_id}' = v_conf06::text
      and pg_temp.bloco(r) like 'Da agenda, ficou de sex 06/11:' || E'\n' || '• ' || c_conf06 || E'\n%'
      and pg_temp.ids(r) not like '%' || v_conf05 || '%',
      pg_temp.bloco(r));
    raise exception 'desfaz' using errcode = 'P0092';
  exception when sqlstate 'P0092' then null;
  end;
  begin
    -- qua 04/11 tinha 3 OS; uma 4ª (o Lenine com o Mickael de manhã, publicada à mão) passa das 3: "e mais 1"
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, periodo, tipo, estado, origem, publicada_em)
    values (c_len, c_mick, d04, 'manha', 'turno', tstzrange(pg_temp.em(d04, '08:00'), pg_temp.em(d04, '12:00')), 'execucao', 'publicada', 'dono', pg_temp.em(d04, '07:00'));
    insert into public.agenda_perguntas (tipo, chave, dia, texto, modo, criada_em, os_ids)
    values ('conferencia', 'conferencia:2026-11-04', d04, 'Agenda de hoje: o dia. Foi isso? Responda *dia feito* ou conte o que mudou.', 'ligado', pg_temp.em(d04, '13:00'), '{}');
    r := public.agenda_aprovacoes_da_manha(d05, pg_temp.em(d05, '07:30'));
    v_todas := v_todas || jsonb_build_array(r);
    v_txt := r #>> '{linhas,0,texto}';
    v_res := pg_temp.ok(v_res, 'M2c qui 05/11, a conferência de qua 04/11 com 4 OS no plano: as 3 primeiras (pela hora e pelo número, a ordem do veredito das 17:30), separadas por "; ", e "e mais 1"',
      v_txt like 'Ontem (qua 04/11) o plano era: %; %; %; e mais 1. Se foi como o plano, responda *dia feito 04/11*; %'
      and (select count(*) from regexp_matches(v_txt, '\(OS-\d+\)', 'g')) = 3,
      v_txt);
    raise exception 'desfaz' using errcode = 'P0092';
  exception when sqlstate 'P0092' then null;
  end;
  begin
    -- em teste (sombra) ou fechada, a conferência não entra
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_conf05;
    insert into public.agenda_perguntas (tipo, chave, dia, texto, modo, criada_em, os_ids)
    values ('conferencia', 'conferencia:2026-11-05', d05, 'Agenda de hoje: em teste. Foi isso? Responda *dia feito* ou conte o que mudou.', 'sombra', pg_temp.em(d05, '13:00'), '{}');
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'M2d a conferência de ontem fechada não entra, nem a em teste (sombra): a 1ª linha passa a ser a da crítica',
      pg_temp.bloco(r) not like '%o plano era:%' and r #>> '{linhas,0,texto}' = c_nelson, pg_temp.bloco(r));
    raise exception 'desfaz' using errcode = 'P0092';
  exception when sqlstate 'P0092' then null;
  end;
  begin
    -- só a conferência (as sobras fechadas): sem a última linha, sem "e mais"
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste'
     where estado = 'aberta' and tipo <> 'conferencia';
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_todas := v_todas || jsonb_build_array(r);
    v_res := pg_temp.ok(v_res, 'M2e só a conferência: o cabeçalho e a linha dela, sem "e mais" e sem a última linha ("Não responda só *sim*"); ontem = {total 1, escritas 1}',
      r ->> 'texto' = 'Da agenda, ficou de ontem:' || E'\n' || '• ' || c_conf05
      and jsonb_array_length(r -> 'linhas') = 1 and r -> 'ontem' = '{"total": 1, "escritas": 1}'::jsonb,
      r::text);
    raise exception 'desfaz' using errcode = 'P0092';
  exception when sqlstate 'P0092' then null;
  end;

  -- ── M3. As sobras ──
  r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
  v_res := pg_temp.ok(v_res, 'M3a com a conferência: 3 linhas no total (a conferência, a crítica do Nelson e qa, na ordem de agenda_perguntas_em_ordem), "• e mais 5 em *agenda pendências*" (as 7 elegíveis menos as 2 escritas) e a última linha',
    pg_temp.bloco(r) = 'Da agenda, ficou de ontem:' || E'\n' || '• ' || c_conf05 || E'\n' || '• ' || c_nelson || E'\n' || '• ' || c_qa
                       || E'\n' || '• e mais 5 em *agenda pendências*' || E'\n' || c_ultima
    and pg_temp.ids(r) = v_conf05 || ',' || v_nelson || ',' || qa and r -> 'ontem' = '{"total": 8, "escritas": 3}'::jsonb,
    pg_temp.bloco(r) || ' | ' || (r -> 'ontem')::text);
  begin
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_conf05;
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_todas := v_todas || jsonb_build_array(r);
    v_res := pg_temp.ok(v_res, 'M3b sem a conferência: as 3 primeiras sobras (Nelson, qa, qb; qb foi mostrada no fechamento de ANTEONTEM, que não esconde), "• e mais 4" e a última linha; o texto exato',
      r ->> 'texto' = 'Da agenda, ficou de ontem:' || E'\n' || '• ' || c_nelson || E'\n' || '• ' || c_qa || E'\n' || '• ' || c_qb
                      || E'\n' || '• e mais 4 em *agenda pendências*' || E'\n' || c_ultima
      and pg_temp.ids(r) = v_nelson || ',' || qa || ',' || qb and r -> 'ontem' = '{"total": 7, "escritas": 3}'::jsonb,
      r ->> 'texto');
    -- a ordem de agenda_perguntas_em_ordem: tirados os de fora, as 7 são Nelson, qa, qb, qc, qd, qe e qj, nesta ordem
    select string_agg(x ->> 'id', ',' order by (x ->> 'ordem')::int) into v_txt
      from jsonb_array_elements(public.agenda_perguntas_em_ordem(d06, pg_temp.em(d06, '07:30'))) x
     where (x ->> 'id')::uuid not in (qf, qg, qh, qi, qk, ql, qm);
    v_res := pg_temp.ok(v_res, 'M3c as escritas são as 3 primeiras de agenda_perguntas_em_ordem tirados os de fora, e todas as de fora estão lá (é esta função que as tira)',
      v_txt = concat_ws(',', v_nelson, qa, qb, qc, qd, qe, qj)
      and (select count(*) from jsonb_array_elements(public.agenda_perguntas_em_ordem(d06, pg_temp.em(d06, '07:30'))) x
            where (x ->> 'id')::uuid in (qf, qg, qh, qi, qk, ql, qm)) = 7,
      v_txt);
    -- o fechamento de ontem que caiu (a fila não mandou) não esconde: qf volta a contar
    update public.agenda_fechamento_fila set estado = 'caiu', motivo = 'nao_saiu', enviada_em = null where dia = d05 and via = 'fechamento';
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'M3d o fechamento de ontem que caiu não esconde (qf conta: "e mais 5"); o de anteontem continua sem esconder',
      r -> 'ontem' = '{"total": 8, "escritas": 3}'::jsonb and pg_temp.bloco(r) like '%• e mais 5 em *agenda pendências*%',
      (r -> 'ontem')::text);
    raise exception 'desfaz' using errcode = 'P0093';
  exception when sqlstate 'P0093' then null;
  end;

  -- ── M5, M7 e M9. Só as de fora abertas: nada sai; tirada a razão de cada uma, ela sai ──
  begin
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id in (v_conf05, v_nelson, qa, qb, qc, qd, qe, qj);
    a := jsonb_build_object('total', 2, 'linhas', jsonb_build_array(jsonb_build_object('pergunta_id', gen_random_uuid())), 'texto', '📨 o cliente');
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    r0 := pg_temp.manha_antes(d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'M7 nada sobrando e sem conferência (abertas só as de fora): a manhã inteira = a de antes, byte a byte, e a interna devolve p_cli inalterado',
      r::text = r0::text and public._agenda_ontem_da_manha(a, d06, pg_temp.em(d06, '07:30'))::text = a::text
      and public._agenda_ontem_da_manha('{"total": 0, "linhas": [], "texto": null}'::jsonb, d06, pg_temp.em(d06, '07:30'))::text
          = '{"total": 0, "linhas": [], "texto": null}'::jsonb::text,
      r::text || ' | ' || public._agenda_ontem_da_manha(a, d06, pg_temp.em(d06, '07:30'))::text);
    -- M5: mostrada 2 vezes (perguntas_vezes_max) não sai; 1 vez sai
    update public.agenda_perguntas set mostrada_vezes = 1 where id = qi;
    r := public._agenda_ontem_da_manha(a, d06, pg_temp.em(d06, '07:30'));
    update public.agenda_perguntas set mostrada_vezes = 2 where id = qi;
    v_res := pg_temp.ok(v_res, 'M5 mostrada perguntas_vezes_max (2) vezes não sai; com 1 a menos, sai (só ela)',
      pg_temp.ids(r) = (a #>> '{linhas,0,pergunta_id}') || ',' || qi and r -> 'ontem' = '{"total": 1, "escritas": 1}'::jsonb,
      r::text);
    -- M9: a com opção escolhida e a do aviso de hoje (não crítica) saem quando a razão sai; a do prazo nunca
    update public.agenda_perguntas set opcao_escolhida = null where id = ql;
    r := public._agenda_ontem_da_manha(a, d06, pg_temp.em(d06, '07:30'));
    update public.agenda_dono_avisos set estado = 'recusada', recusa_motivo = 'janela', enviada_em = null where dedupe_key = 'agenda-dono:teste:' || d06;
    r1 := public._agenda_ontem_da_manha(a, d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'M9a sem a opção escolhida, ql sai; sem o aviso de hoje (recusado), qm também; qk (com prazo gravado) nunca, nem qf, qg, qh e qi',
      pg_temp.ids(r) = (a #>> '{linhas,0,pergunta_id}') || ',' || ql and pg_temp.ids(r1) = (a #>> '{linhas,0,pergunta_id}') || ',' || ql || ',' || qm
      and r1 -> 'ontem' = '{"total": 2, "escritas": 2}'::jsonb,
      r::text || ' | ' || r1::text);
    raise exception 'desfaz' using errcode = 'P0094';
  exception when sqlstate 'P0094' then null;
  end;
  begin
    -- M9b: a crítica que o aviso de hoje levou sai assim mesmo (a regra do bloco das 17:30); a não crítica do mesmo aviso, não
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id in (v_conf05, qa, qb, qc, qd, qe, qj);
    r := public._agenda_ontem_da_manha('{"total": 0, "linhas": [], "texto": null}'::jsonb, d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'M9b a crítica do Nelson, levada pelo aviso de hoje, sai; qm (não crítica, no mesmo aviso) não',
      pg_temp.ids(r) = v_nelson::text and r -> 'ontem' = '{"total": 1, "escritas": 1}'::jsonb, r::text);
    raise exception 'desfaz' using errcode = 'P0094';
  exception when sqlstate 'P0094' then null;
  end;

  -- ── M6. Toda linha tem pergunta_id; a guarda da manhã aceita, a fila manda, conta via manha sem prazo nascer ──
  begin
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'teste' where id = v_conf05;
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    insert into public.whatsapp_send_queue (phone_normalized, message, source, priority, max_attempts, dedupe_key)
    values ('5547900000210', 'Manhã de teste', 'ai_briefing', 4, 3, 'teste_manha_p1:' || d06)
    returning id into v_f;
    -- como o Secretário manda (guardarAprovacoesDaManha): {pergunta_id, acao_ids: []}
    r0 := public.agenda_fechamento_guardar(d06, (select jsonb_agg(jsonb_build_object('pergunta_id', x ->> 'pergunta_id', 'acao_ids', '[]'::jsonb))
                                                  from jsonb_array_elements(r -> 'linhas') x), v_f, 'manha', pg_temp.em(d06, '07:30'));
    update public.whatsapp_send_queue set status = 'sent', sent_at = pg_temp.em(d06, '07:32') where id = v_f;
    r1 := public.agenda_aviso_conferir(pg_temp.em(d06, '07:45'));
    v_res := pg_temp.ok(v_res, 'M6 toda linha de linhas[] tem pergunta_id; a guarda da manhã as aceita (esperando); com a fila em sent cada escrita conta 1 vez via manha às 07:32, sem prazo nascer; qk (com prazo, não escrita) fica como estava',
      not exists (select 1 from jsonb_array_elements(r -> 'linhas') x where coalesce(x ->> 'pergunta_id', '') = '')
      and r0 ->> 'estado' = 'esperando'
      and (select bool_and(q.mostrada_vezes = 1 and q.mostrada_via = 'manha' and q.mostrada_em = pg_temp.em(d06, '07:32') and q.veto_ate is null)
             from public.agenda_perguntas q where q.id in (v_nelson, qa, qb))
      and (select q.mostrada_vezes = 0 and q.veto_ate = pg_temp.em(d06, '18:00') from public.agenda_perguntas q where q.id = qk),
      r0::text || ' | ' || r1::text || ' | '
      || (select string_agg(format('%s %s %s %s', q.chave, q.mostrada_vezes, q.mostrada_via, q.veto_ate), '; ') from public.agenda_perguntas q where q.id in (v_nelson, qa, qb, qk)));
    raise exception 'desfaz' using errcode = 'P0095';
  exception when sqlstate 'P0095' then null;
  end;

  -- ── M10. O erro ao montar não derruba a manhã ──
  begin
    perform set_config('request.jwt.claims', '{"role": "authenticated"}', true);
    a := jsonb_build_object('total', 1, 'linhas', jsonb_build_array(jsonb_build_object('pergunta_id', gen_random_uuid())), 'texto', '📨 o cliente');
    r := public._agenda_ontem_da_manha(a, d06, pg_temp.em(d06, '07:30'));
    perform set_config('request.jwt.claims', '', true);
    v_res := pg_temp.ok(v_res, 'M10 agenda_perguntas_em_ordem recusa (42501): a interna devolve p_cli como veio + ontem {erro, sqlstate}; o texto e as linhas de antes ficam',
      r - 'ontem' = a and r #>> '{ontem,sqlstate}' = '42501' and r #>> '{ontem,erro}' like 'As perguntas da agenda são com o administrador%',
      r::text);
    raise exception 'desfaz' using errcode = 'P0096';
  exception when sqlstate 'P0096' then null;
  end;

  -- ── M4 e M8, sobre todas as saídas com o bloco ──
  v_ok := true;
  v_txt := null;
  v_n := 0;
  for r in select x from jsonb_array_elements(v_todas) x loop
    if coalesce(r ->> 'texto', '') ~ c_numerada or coalesce(r ->> 'texto', '') ~* 'sem resposta até|op[çc][ãa]o \d' then
      v_ok := false;
      v_txt := concat_ws(' | ', v_txt, left(r ->> 'texto', 200));
    end if;
    v_n := v_n + 1;
  end loop;
  v_res := pg_temp.ok(v_res, format('M4 nenhuma das %s manhãs com o bloco casa a régua de AGENDA_NUMERADA_NA_CONVERSA nem traz "Sem resposta até" ou "opção N"', v_n),
    v_ok and v_n >= 6, v_txt);
  v_ok := true;
  v_txt := null;
  v_n := 0;
  for v_lin in select l from jsonb_array_elements(v_todas) x, unnest(string_to_array(pg_temp.bloco(x), E'\n')) l loop
    if v_lin ~ '[?]' and v_lin !~ '[*][^*[:space:]][^*]*[*]' then
      v_ok := false;
      v_txt := concat_ws(' | ', v_txt, v_lin);
    end if;
    if v_lin like '%(*agenda pendências* mostra inteira)' then
      v_n := v_n + 1;
    end if;
  end loop;
  v_res := pg_temp.ok(v_res, 'M8 nenhuma linha do bloco tem "?" sem a palavra de comando entre asteriscos (a que pergunta leva "(*agenda pendências* mostra inteira)"); a da conferência não pergunta',
    v_ok and v_n > 0 and c_conf05 !~ '[?]' and c_conf06 !~ '[?]',
    coalesce(v_txt, format('%s linhas com a palavra acrescentada', v_n)));

  raise exception 'desfaz' using errcode = 'P0090';
  exception when sqlstate 'P0090' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$m$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
