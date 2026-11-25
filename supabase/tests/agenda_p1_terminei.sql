-- Prova do A3 do pacote 1 do assistente (24/11/2026; migrations 20270301120000_agenda_p1_chaves.sql e 20270301120200_agenda_p1_terminei_pergunta.sql):
-- com agenda_config.equipe_terminei_conclui = false (o padrão) e o motor ligado, o "terminei" (ou o "ok") do técnico no último dia do plano não
-- conclui a OS em nome da equipe; vira a pergunta "terminou ou falta dia?" ao dono (concluir, chave terminou:<os>), uma por dia. Com true, o de antes.
-- bancada: depende de 20270301120200
--
--   P0  a forma (vale em produção, nada grava): as 4 chaves de agenda_config (tipo, DEFAULT, NOT NULL, CHECK e comentário; cada CHECK recusa o seu
--       caso, P0g) e _agenda_cfg() com elas;
--       a porta de _agenda_rotina_conclusao (a de antes: invoker, ninguém de fora executa); nenhum UPDATE/DELETE sem WHERE; tirados os 3 blocos
--       "-- P1 AGENDA:", o corpo é o de produção de 24/11 (md5 sem CR ae91e221…); tirados também os "-- TERMINOU:", o de 23/11 (ff5397d8…)
--   Sobre a fixture-fase3 (o Roberto no Vanderlei, OS-00069, de ter 03 a qui 05/11 o dia todo; o Gustavo, o dono, abre na terça de manhã e fecha na
--   quinta à tarde: a presença "abre e fecha", o padrão da casa):
--   T1  chave false, só o técnico no último dia, "ok, terminei" às 17:15: nada conclui, a OS fica em andamento e nasce 1 pergunta concluir
--       terminou:<os> com o texto exato ("disse em qui 05/11 que terminou")
--   T2  o "ok" puro: o mesmo, e o texto diz "respondeu *ok*" (correção da crítica de risco)
--   T3  o tique seguinte não abre outra; depois de *falta dia* no mesmo dia nenhuma terminou:<os> nasce de novo e, com o dia novo no plano, a
--       mensagem já perguntada não abre a pergunta do "dia sobrando" (T3d, revisão de 25/11) (LIMITE que fica: o *falta dia* do mesmo dia marca
--       o dia ANTERIOR, NOVO-agenda-p1-01)
--   T4  a manhã seguinte traz a linha; *concluiu* conclui pela porta e a pergunta fecha no tique seguinte; *falta dia* a fecha e devolve a OS ao motor
--   T5  chave true: o de antes (conclui pela porta, via equipe); T5b a chave virada para true DEPOIS da pergunta feita não conclui a OS dela
--   T6  chave false com o motor em teste (sombra): o de antes (só a ação "Em teste: concluiria…")
--   S   A SOBREVIVÊNCIA AO PASSO INTEIRO (agenda_rotina_rodar; no fim do passo conclusao roda _agenda_terminou_rodar, que fecha a pergunta concluir
--       terminou:% cuja OS tenha meio-dia de hoje em diante sem resultado ou não esteja em andamento; correção da crítica de viabilidade):
--   S1  17h, só o técnico (os meios-dias dele com resultado): SOBREVIVE ao passo, aos tiques do dia e ao 1º do dia seguinte
--   S2  17h, o padrão da casa com o *dia feito* do dono ANTES da resposta: SOBREVIVE
--   S3  LIMITE CONHECIDO — 17h, o padrão da casa (o meio-dia do dono sem resultado): a pergunta é fechada no mesmo passo ("a OS voltou a ter dia no
--       plano"); a OS não conclui; no dia seguinte nasce a pergunta geral e a manhã das 07:30 a mostra
--   S4  LIMITE CONHECIDO — 12h (o "como foi" na hora mais cedo que o CHECK deixa, 12:00; a tarde dele por começar): fechada no mesmo passo;
--       quando a tarde ganha resultado (no tique das 17:30) nasce a pergunta geral, e a manhã das 07:30 a mostra
--   S5  LIMITE CONHECIDO — "terminei" seco com a OS ainda agendada: fechada no mesmo passo ("a OS não está mais em andamento") e nenhuma pergunta
--       nasce no dia seguinte (a geral exige a OS em andamento)
--   S6  por que não a chave terminou:<os>:equipe (a saída que a crítica propôs): _agenda_terminou_rodar a fecha do mesmo jeito (o filtro é
--       like 'terminou:%'), a manhã a mostra e *concluiu* a fecha, mas *falta dia* não a fecha (o filtro é a chave exata)
--   Os LIMITES são o comportamento de hoje, escrito para ninguém o tomar por acerto: a pergunta com o que o técnico disse só chega ao dono quando
--   nenhum meio-dia de hoje da OS ficou sem resultado e a OS está em andamento. Em nenhum dos casos a OS conclui (o conserto de segurança vale
--   sempre). Consertar a pergunta pede mexer em _agenda_terminou_rodar (e, para o S5, em _agenda_terminou_candidatas, _agenda_terminou_da_manha e
--   agenda_falta_dia_dito, que exigem a OS em andamento): decisão de desenho, fora deste lote; quando isso entrar, S3 a S5 passam a exigir a
--   pergunta ABERTA.
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar as migrations:  npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_p1_terminei.sql
--   Sem a fixture (produção) T e S saem PULADO; P0 roda e não grava nada. Termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
-- Tira os blocos "-- <marca>: … -- <marca>: fim" (p_marca é uma alternância de regex: 'P1 AGENDA', 'P1 AGENDA|TERMINOU'), devolvendo as linhas
-- "--antes:" de dentro deles: o corpo de antes.
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
-- A rotina inteira (o passo inteiro) e a resposta do Roberto (o telefone sintético da fixture-fase3).
create function pg_temp.rodar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_rotina_rodar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
create function pg_temp.resp(p_texto text, p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_resposta_da_equipe('5547900000001', p_texto, md5(p_texto || p_dia || p_hora), pg_temp.em(p_dia, p_hora))
$f$;
-- As perguntas concluir de uma OS, em ordem: "chave curta|estado|motivo" (a chave sem o uuid da OS).
create function pg_temp.pergs(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s|%s|%s', replace(q.chave, p_os::text, '<os>'), q.estado, coalesce(q.resolvida_motivo, '-')), ' ; '
                             order by q.criada_em, q.id), '(nenhuma)')
    from public.agenda_perguntas q where q.tipo = 'concluir' and q.service_order_id = p_os
$f$;

-- ── P0. A forma (vale em produção; nada grava) ───────────────────────────────────────────────────────────────────────────────────────
do $p0$
declare
  v_res jsonb := '[]'::jsonb;
  c_f   constant text := 'public._agenda_rotina_conclusao(date,timestamptz)';
  r     record;
  v_txt text;
begin
  for r in select x.*, a.attnum, format_type(a.atttypid, a.atttypmod) as tipo_de_fato, a.attnotnull, pg_get_expr(d.adbin, d.adrelid) as padrao_de_fato,
                  col_description(a.attrelid, a.attnum) as comentario,
                  (select string_agg(pg_get_constraintdef(c.oid), ' ; ' order by c.conname) from pg_constraint c
                    where c.conrelid = a.attrelid and c.contype = 'c' and c.conkey = array[a.attnum]) as regra_de_fato
             from (values
               ('equipe_silencio_acao',    'text',     true,  '''tirar''::text', 'tirar.*manter',  'Pacote 1, A2 %'),
               ('equipe_terminei_conclui', 'boolean',  true,  'false',           null,             'Pacote 1, A3: %'),
               ('sinal_cobrar_max_dias',   'integer',  false, null,              '>= 1.*<= 120',   'Pacote 1, A1b %'),
               ('manha_sobras_max',        'smallint', true,  '0',               '>= 0.*<= 3',     'Pacote 1, A5/A4: %')
             ) x(coluna, tipo, obrigatoria, padrao, regra, comentario_como)
             left join pg_attribute a on a.attrelid = 'public.agenda_config'::regclass and a.attname = x.coluna and not a.attisdropped
             left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  loop
    v_res := pg_temp.ok(v_res, format('P0a agenda_config.%s: %s, %s, DEFAULT %s, CHECK %s, com comentário', r.coluna, r.tipo,
                                      case when r.obrigatoria then 'NOT NULL' else 'aceita nulo' end, coalesce(r.padrao, 'nenhum (nulo)'),
                                      coalesce(r.regra, 'nenhum')),
      r.attnum is not null and r.tipo_de_fato = r.tipo and r.attnotnull = r.obrigatoria and r.padrao_de_fato is not distinct from r.padrao
      and (case when r.regra is null then r.regra_de_fato is null else coalesce(r.regra_de_fato, '') ~ r.regra end)
      and coalesce(r.comentario, '') like r.comentario_como,
      format('%s | not null %s | default %s | check %s | %s', coalesce(r.tipo_de_fato, 'NÃO EXISTE'), r.attnotnull, coalesce(r.padrao_de_fato, '-'),
             coalesce(r.regra_de_fato, '-'), left(coalesce(r.comentario, '(sem comentário)'), 40)));
  end loop;
  v_res := pg_temp.ok(v_res, 'P0b _agenda_cfg() devolve a linha com as 4 chaves (agenda_config%rowtype: chegam sozinhas às funções)',
    (select to_jsonb(public._agenda_cfg()) ?& array['equipe_silencio_acao', 'equipe_terminei_conclui', 'sinal_cobrar_max_dias', 'manha_sobras_max']), null);
  v_res := pg_temp.ok(v_res, format('P0c %s: a porta de antes (invoker, volátil | anon authenticated service_role public = ninguém) e search_path=public', c_f),
    pg_temp.porta(c_f) = 'f v | f f f f'
    and exists (select 1 from pg_proc p, unnest(p.proconfig) c where p.oid = to_regprocedure(c_f) and replace(c, '"', '') = 'search_path=public'),
    coalesce(pg_temp.porta(c_f), 'NÃO EXISTE') || ' config '
    || coalesce((select array_to_string(p.proconfig, ',') from pg_proc p where p.oid = to_regprocedure(c_f)), '-'));
  v_res := pg_temp.ok(v_res, format('P0d %s: nenhum UPDATE/DELETE sem WHERE (pg_safeupdate)', c_f),
    not exists (select 1 from pg_temp.sem_where(coalesce(pg_temp.src(c_f), ''))),
    (select string_agg(x, ' | ') from pg_temp.sem_where(coalesce(pg_temp.src(c_f), '')) x));
  v_txt := coalesce(pg_temp.src(c_f), '');
  v_res := pg_temp.ok(v_res, 'P0e sem os 3 blocos "-- P1 AGENDA:" o corpo é o de produção de 24/11/2026 (md5 sem CR ae91e221…); sem eles e sem os "-- TERMINOU:", o de 23/11 (ff5397d8…)',
    md5(pg_temp.sem_blocos(v_txt, 'P1 AGENDA')) = 'ae91e2216c9eede4ce794e7a9ba86b2f'
    and md5(pg_temp.sem_blocos(v_txt, 'P1 AGENDA|TERMINOU')) = 'ff5397d86f0ae999dda0b3f74a730170'
    and md5(v_txt) <> 'ae91e2216c9eede4ce794e7a9ba86b2f'
    and (select count(*) from regexp_matches(v_txt, '-- P1 AGENDA: fim', 'g')) = 3,
    format('%s / %s / %s blocos', md5(pg_temp.sem_blocos(v_txt, 'P1 AGENDA')), md5(pg_temp.sem_blocos(v_txt, 'P1 AGENDA|TERMINOU')),
           (select count(*) from regexp_matches(v_txt, '-- P1 AGENDA: fim', 'g'))));
  v_res := pg_temp.ok(v_res, 'P0f o ramo novo só vale com a chave em false e o motor ligado, e nada nele chama a porta (os_registrar_marco fica fora dos blocos)',
    v_txt like '%if not cf.equipe_terminei_conclui and cf.modo_proposta = ''ligado'' then%'
    and (select count(*) from regexp_matches(v_txt, 'os_registrar_marco', 'g'))
        = (select count(*) from regexp_matches(pg_temp.sem_blocos(v_txt, 'P1 AGENDA'), 'os_registrar_marco', 'g')),
    null);
  -- P0g: cada CHECK novo recusa o seu caso, pelo nome (o B de agenda_fase1_base.sql deixa estes 3 para cá). Cada UPDATE é recusado dentro
  -- de um bloco próprio: nada grava.
  v_txt := null;
  for r in select * from (values
      ('equipe_silencio_acao',  '''apagar''', 'agenda_config_equipe_silencio_acao_check'),
      ('sinal_cobrar_max_dias', '0',          'agenda_config_sinal_cobrar_max_dias_check'),
      ('sinal_cobrar_max_dias', '121',        'agenda_config_sinal_cobrar_max_dias_check'),
      ('manha_sobras_max',      '-1',         'agenda_config_manha_sobras_max_check'),
      ('manha_sobras_max',      '4',          'agenda_config_manha_sobras_max_check')
    ) x(coluna, valor, regra)
  loop
    declare
      v_est text;
      v_reg text;
    begin
      execute format('update public.agenda_config set %I = %s where id', r.coluna, r.valor);
      v_txt := concat_ws('; ', v_txt, format('%s = %s passou', r.coluna, r.valor));
      raise exception 'desfaz' using errcode = 'P0095';
    exception
      when sqlstate 'P0095' then null;
      when check_violation then
        get stacked diagnostics v_est = returned_sqlstate, v_reg = constraint_name;
        if v_reg is distinct from r.regra then
          v_txt := concat_ws('; ', v_txt, format('%s = %s recusado por %s', r.coluna, r.valor, v_reg));
        end if;
    end;
  end loop;
  v_res := pg_temp.ok(v_res, 'P0g os 3 CHECKs novos recusam, pelo nome: equipe_silencio_acao ''apagar'', sinal_cobrar_max_dias 0 e 121, manha_sobras_max -1 e 4',
    v_txt is null, v_txt);
  perform pg_temp.gravar(v_res);
end
$p0$;

-- ── T e S. O Roberto no último dia do Vanderlei (a fixture-fase3) ────────────────────────────────────────────────────────────────────
do $t$
declare
  v_res     jsonb := '[]'::jsonb;
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_gustavo constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_vand    constant uuid := '05000000-0000-4000-8000-000000000069';
  d04       constant date := date '2026-11-04';
  d05       constant date := date '2026-11-05';
  d06       constant date := date '2026-11-06';
  c_chave   constant text := 'terminou:05000000-0000-4000-8000-000000000069';
  c_disse   constant text := 'O Roberto disse em qui 05/11 que terminou a OS-00069 (Vanderlei). Responda *concluiu OS-00069* para fechar, ou *falta dia OS-00069* se ainda tem serviço.';
  c_ok      constant text := 'O Roberto respondeu *ok* ao "como foi hoje?" no último dia da OS-00069 (Vanderlei). Responda *concluiu OS-00069* para fechar, ou *falta dia OS-00069* se ainda tem serviço.';
  c_geral   constant text := 'A OS-00069 (Vanderlei) terminou ou falta dia? Responda *concluiu OS-00069* ou *falta dia OS-00069*.';
  q         public.agenda_perguntas;
  r         jsonb;
  r1        jsonb;
  r2        jsonb;
  v_st      text;
  v_txt     text;
  v_n       int;
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('T1–T6 e S1–S6 (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  begin
  execute current_setting('agenda_teste.fase3');
  -- O registrar_diaria recusa "dia no futuro" pelo relógio de verdade (_hoje_brt): aqui o "hoje" do teste vale também para ele (como em
  -- agenda_fase3_equipe_diarias.sql). Dentro da transação: o ROLLBACK do fim desfaz.
  create or replace function public._hoje_brt() returns date language sql stable set search_path to 'public' as $h$
    select coalesce(nullif(current_setting('agenda_teste.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date)
  $h$;
  perform set_config('agenda_teste.hoje', '2026-11-08', true);
  update public.agenda_config set modo_equipe = 'ligado', modo_diaria = 'ligado' where id;

  v_res := pg_temp.ok(v_res, 'T0 o ponto de partida: a chave nasce false, o motor ligado, o Vanderlei agendado, e na quinta 05/11 (o último dia) o Roberto de manhã e à tarde e o Gustavo à tarde',
    (select not c.equipe_terminei_conclui and c.modo_proposta = 'ligado' from public.agenda_config c)
    and (select so.status from public.service_orders so where so.id = c_vand) = 'scheduled'
    and (select string_agg(a.turno || ' ' || case a.payee_id when c_roberto then 'Roberto' when c_gustavo then 'Gustavo' else '?' end, ', '
                           order by a.turno, a.payee_id)
           from public.agenda_alocacoes a
          where a.service_order_id = c_vand and a.dia >= d05 and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva')
        = 'manha Roberto, tarde Gustavo, tarde Roberto',
    (select string_agg(a.dia || ' ' || a.turno || ' ' || a.payee_id, ', ' order by a.dia, a.turno, a.payee_id) from public.agenda_alocacoes a
      where a.service_order_id = c_vand and a.dia >= d05 and a.estado in ('publicada', 'fixada')));

  -- ── T1, T3, T4, S1. Só o técnico no último dia (o meio-dia do Gustavo sai), "ok, terminei" às 17:15 ──
  begin
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok, terminei', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    select * into q from public.agenda_perguntas x where x.chave = c_chave;
    v_res := pg_temp.ok(v_res, 'T1a chave false, "ok, terminei" no último dia: nada conclui — a OS fica em andamento, sem check-out, sem ação concluir (nem em teste) e a mensagem sem ação',
      (select so.status = 'in_progress' and so.check_out_at is null from public.service_orders so where so.id = c_vand)
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand)
      and (r #>> '{contagens,conclusao,concluidas}')::int = 0 and (r ->> 'erros')::int = 0
      and (select m.acao_id is null and (m.leitura ->> 'terminou')::boolean from public.agenda_equipe_mensagens m
            where m.payee_id = c_roberto and m.tipo = 'como_foi' and m.dia = d05),
      (r #> '{contagens,conclusao}')::text || ' | falhas ' || (r -> 'falhas')::text || ' | ' || (select so.status from public.service_orders so where so.id = c_vand));
    v_res := pg_temp.ok(v_res, 'T1b nasce 1 pergunta: concluir, terminou:<os>, ligado, aberta, do técnico (payee_id), a OS em service_order_id e os_ids, dia = hoje, sem prazo, sem opções, não crítica',
      (r #>> '{contagens,conclusao,perguntas}')::int = 1 and (select count(*) from public.agenda_perguntas x where x.chave = c_chave) = 1
      and q.tipo = 'concluir' and q.estado = 'aberta' and q.modo = 'ligado' and q.payee_id = c_roberto and q.service_order_id = c_vand
      and q.os_ids = array[c_vand] and q.dia = d05 and q.criada_em = pg_temp.em(d05, '17:30') and q.expira_em is null and q.veto_ate is null
      and q.opcoes = '[]'::jsonb and not coalesce(q.critica, false) and q.mostrada_vezes = 0,
      (r #> '{contagens,conclusao}')::text || ' | ' || coalesce(to_jsonb(q)::text, '(sem pergunta)'));
    v_res := pg_temp.ok(v_res, 'T1c o texto exato: "O Roberto disse em qui 05/11 que terminou a OS-00069 (Vanderlei). Responda *concluiu OS-00069* para fechar, ou *falta dia OS-00069* se ainda tem serviço."',
      q.texto = c_disse, q.texto);
    v_res := pg_temp.ok(v_res, 'S1a 17h, só o técnico: a pergunta SOBREVIVE ao passo inteiro (_agenda_terminou_rodar, no fim do passo, não a fecha)',
      q.estado = 'aberta' and (r #>> '{contagens,conclusao,terminou,fechadas}')::int = 0 and r #>> '{contagens,conclusao,terminou,erro}' is null,
      (r #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));
    r1 := pg_temp.rodar(d05, '17:45');
    r2 := pg_temp.rodar(d05, '19:45');
    v_res := pg_temp.ok(v_res, 'T3a os tiques seguintes do dia (17:45 e 19:45) não abrem outra nem fecham a de agora: uma por dia',
      (r1 #>> '{contagens,conclusao,perguntas}')::int = 0 and (r2 #>> '{contagens,conclusao,perguntas}')::int = 0
      and (r1 #>> '{contagens,conclusao,terminou,fechadas}')::int = 0 and (r2 #>> '{contagens,conclusao,terminou,fechadas}')::int = 0
      and pg_temp.pergs(c_vand) = 'terminou:<os>|aberta|-',
      (r1 #> '{contagens,conclusao}')::text || ' / ' || (r2 #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));

    -- T3b/T3c: *falta dia* dito no mesmo dia
    begin
      r1 := public.agenda_falta_dia_dito(c_admin, 'Vanderlei', 'whatsapp', d05, pg_temp.em(d05, '18:00'));
      select * into q from public.agenda_perguntas x where x.chave = c_chave;
      r2 := pg_temp.rodar(d05, '18:15');
      v_res := pg_temp.ok(v_res, 'T3b depois de *falta dia Vanderlei* no mesmo dia a pergunta fica respondida e o tique seguinte não abre outra terminou:<os>',
        (r1 ->> 'ok')::boolean and r1 ->> 'status' = 'ok' and (r1 ->> 'pergunta')::int = 1 and q.estado = 'respondida' and q.respondida_por = c_admin
        and (select count(*) from public.agenda_perguntas x where x.chave = c_chave) = 1
        and (select so.status from public.service_orders so where so.id = c_vand) = 'in_progress',
        (r1 ->> 'texto') || ' | ' || pg_temp.pergs(c_vand));
      v_res := pg_temp.ok(v_res, 'T3c LIMITE do *falta dia* no MESMO dia: ele marca como parcial o dia ANTERIOR (qua 04/11; NOVO-agenda-p1-01)',
        (r1 ->> 'dia')::date = d04, format('dia marcado %s', r1 ->> 'dia'));
      v_txt := (select string_agg(a.dia::text, ', ' order by a.dia) from (select distinct a.dia from public.agenda_alocacoes a
                 where a.service_order_id = c_vand and a.dia > d05 and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva') a);
      r := pg_temp.rodar(d05, '19:45');
      v_res := pg_temp.ok(v_res, 'T3d com o dia novo no plano, os tiques seguintes (18:15 e 19:45) não releem a mensagem já perguntada: nenhuma pergunta do "dia sobrando" (concluir:<os>:<dia>), nenhuma outra, a OS em andamento e a mensagem sem ação',
        v_txt is not null
        and (r2 #>> '{contagens,conclusao,perguntas}')::int = 0 and (r #>> '{contagens,conclusao,perguntas}')::int = 0
        and (r2 #>> '{contagens,conclusao,concluidas}')::int = 0 and (r #>> '{contagens,conclusao,concluidas}')::int = 0
        and not exists (select 1 from public.agenda_perguntas x where x.chave like 'concluir:' || c_vand || ':%')
        and pg_temp.pergs(c_vand) = 'terminou:<os>|respondida|-'
        and (select so.status from public.service_orders so where so.id = c_vand) = 'in_progress'
        and (select m.acao_id is null from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'como_foi' and m.dia = d05),
        format('dias novos %s | %s / %s | %s', coalesce(v_txt, '(nenhum)'), r2 #> '{contagens,conclusao}', r #> '{contagens,conclusao}',
               pg_temp.pergs(c_vand)));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;

    -- T4, S1b: o dia seguinte
    r1 := pg_temp.rodar(d06, '00:15');
    select * into q from public.agenda_perguntas x where x.chave = c_chave;
    v_res := pg_temp.ok(v_res, 'S1b o 1º tique do dia seguinte (00:15) não a fecha nem abre outra: ela chega aberta à manhã',
      q.estado = 'aberta' and (r1 #>> '{contagens,conclusao,terminou,fechadas}')::int = 0 and (r1 #>> '{contagens,conclusao,terminou,abertas}')::int = 0
      and pg_temp.pergs(c_vand) = 'terminou:<os>|aberta|-',
      (r1 #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));
    r1 := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'T4a a manhã seguinte (07:30) traz a linha: "🔧 " + o texto, a pergunta em linhas[]',
      r1 ->> 'texto' = '🔧 ' || c_disse and jsonb_array_length(r1 -> 'linhas') = 1 and r1 #>> '{linhas,0,pergunta_id}' = q.id::text
      and (r1 #>> '{terminou,total}')::int = 1, r1::text);
    begin
      r1 := public.agenda_concluir_dito(c_admin, 'OS-00069', 'whatsapp', d06, pg_temp.em(d06, '08:00'));
      v_st := (select so.status from public.service_orders so where so.id = c_vand);
      r2 := pg_temp.rodar(d06, '08:15');
      select * into q from public.agenda_perguntas x where x.chave = c_chave;
      v_res := pg_temp.ok(v_res, 'T4b *concluiu OS-00069* conclui pela porta (pelo dono) e a pergunta fecha no tique seguinte (resolvida: "a OS foi concluída")',
        (r1 ->> 'ok')::boolean and v_st = 'completed'
        and exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand and a.executada and a.origem = 'dono')
        and not exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand and a.origem = 'equipe')
        and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS foi concluída' and (r2 #>> '{contagens,conclusao,terminou,fechadas}')::int = 1,
        format('%s | %s | %s | origens %s', v_st, pg_temp.pergs(c_vand), r2 #> '{contagens,conclusao}',
               (select string_agg(a.origem, ',') from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand)));
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    begin
      r1 := public.agenda_falta_dia_dito(c_admin, 'OS-00069', 'whatsapp', d06, pg_temp.em(d06, '08:00'));
      r2 := pg_temp.rodar(d06, '08:15');
      select * into q from public.agenda_perguntas x where x.chave = c_chave;
      v_res := pg_temp.ok(v_res, 'T4c *falta dia OS-00069* na manhã seguinte: o 05/11 vira "em parte (estimativa)", a pergunta fica respondida (whatsapp, pelo dono) e o tique seguinte não abre outra',
        (r1 ->> 'ok')::boolean and r1 ->> 'status' = 'ok' and (r1 ->> 'dia')::date = d05 and (r1 ->> 'pergunta')::int = 1
        and q.estado = 'respondida' and q.respondida_via = 'whatsapp' and q.respondida_por = c_admin and q.resposta = 'falta dia OS-00069'
        and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_vand and a.dia = d05
                          and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva'
                          and (a.resultado is distinct from 'parcial' or a.motivo is distinct from 'estimativa'))
        and (r2 #>> '{contagens,conclusao,perguntas}')::int = 0 and (r2 #>> '{contagens,conclusao,terminou,abertas}')::int = 0
        and pg_temp.pergs(c_vand) = 'terminou:<os>|respondida|-',
        (r1 ->> 'texto') || ' | ' || pg_temp.pergs(c_vand) || ' | ' || (r2 #> '{contagens,conclusao}')::text);
      raise exception 'desfaz' using errcode = 'P0097';
    exception when sqlstate 'P0097' then null;
    end;
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── T2. O "ok" puro (só o técnico no último dia) ──
  begin
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    select * into q from public.agenda_perguntas x where x.chave = c_chave;
    v_res := pg_temp.ok(v_res, 'T2a o "ok" puro no último dia (o leitor lê "terminou" sem ninguém dizer): nada conclui e a pergunta nasce, aberta',
      (select so.status = 'in_progress' and so.check_out_at is null from public.service_orders so where so.id = c_vand)
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand)
      and (r #>> '{contagens,conclusao,concluidas}')::int = 0 and (r #>> '{contagens,conclusao,perguntas}')::int = 1
      and (select m.leitura ->> 'tipo' = 'ok' and (m.leitura ->> 'terminou')::boolean from public.agenda_equipe_mensagens m
            where m.payee_id = c_roberto and m.tipo = 'como_foi' and m.dia = d05)
      and q.estado = 'aberta' and q.payee_id = c_roberto,
      (r #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));
    v_res := pg_temp.ok(v_res, 'T2b o texto diz o que ele disse: "O Roberto respondeu *ok* ao "como foi hoje?" no último dia da OS-00069 (Vanderlei). Responda *concluiu OS-00069* para fechar, ou *falta dia OS-00069* se ainda tem serviço."',
      q.texto = c_ok and q.texto not like '%disse%', q.texto);
    r1 := pg_temp.rodar(d06, '00:15');
    r1 := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'T2c e é esse o texto que a manhã seguinte mostra',
      r1 ->> 'texto' = '🔧 ' || c_ok, r1 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── T5. A chave em true: o de antes ──
  begin
    update public.agenda_config set equipe_terminei_conclui = true where id;
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok, terminei', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    v_res := pg_temp.ok(v_res, 'T5 chave true: o de antes — a OS concluída pela porta (via equipe), desfazível, a mensagem ligada à ação e nenhuma pergunta terminou:<os>',
      (select so.status from public.service_orders so where so.id = c_vand) = 'completed'
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand and a.origem = 'equipe'
                                                    and a.executada and a.desfazivel_ate is not null)
      and (r #>> '{contagens,conclusao,concluidas}')::int = 1 and (r #>> '{contagens,conclusao,perguntas}')::int = 0
      and (select m.acao_id is not null from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'como_foi' and m.dia = d05)
      and not exists (select 1 from public.agenda_perguntas x where x.chave like 'terminou:%' and x.service_order_id = c_vand),
      (r #> '{contagens,conclusao}')::text || ' | ' || (select so.status from public.service_orders so where so.id = c_vand) || ' | ' || pg_temp.pergs(c_vand));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── T5b. A chave virada para true DEPOIS da pergunta feita (só o técnico no último dia): a mensagem já perguntada não é relida ──
  begin
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok', d05, '17:15');
    r1 := pg_temp.rodar(d05, '17:30');
    update public.agenda_config set equipe_terminei_conclui = true where id;
    r := pg_temp.rodar(d05, '17:45');
    select * into q from public.agenda_perguntas x where x.chave = c_chave;
    v_res := pg_temp.ok(v_res, 'T5b a chave virada para true às 17:40, depois da pergunta das 17:30: o tique das 17:45 NÃO conclui a OS pela mensagem já perguntada, e a pergunta segue aberta para o dono',
      (r1 #>> '{contagens,conclusao,perguntas}')::int = 1
      and (r #>> '{contagens,conclusao,concluidas}')::int = 0 and (r #>> '{contagens,conclusao,perguntas}')::int = 0
      and (select so.status from public.service_orders so where so.id = c_vand) = 'in_progress'
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand)
      and q.estado = 'aberta' and q.texto = c_ok
      and (select m.acao_id is null from public.agenda_equipe_mensagens m where m.payee_id = c_roberto and m.tipo = 'como_foi' and m.dia = d05),
      (r #> '{contagens,conclusao}')::text || ' | ' || (select so.status from public.service_orders so where so.id = c_vand) || ' | ' || pg_temp.pergs(c_vand));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── T6. A chave em false com o motor em teste: o de antes ──
  begin
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok, terminei', d05, '17:15');
    update public.agenda_config set modo_proposta = 'sombra' where id;
    r := pg_temp.rodar(d05, '17:30');
    v_res := pg_temp.ok(v_res, 'T6 chave false com o motor em teste (sombra): o de antes — nada conclui, só a ação concluir com executada = false ("Em teste: concluiria…") e nenhuma pergunta',
      (select so.status from public.service_orders so where so.id = c_vand) <> 'completed'
      and exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and not a.executada and a.service_order_id = c_vand
                                                    and a.texto like 'Em teste: concluiria %')
      and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'concluir' and x.service_order_id = c_vand),
      (r #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S2. O padrão da casa, com o *dia feito* do dono antes da resposta do técnico ──
  begin
    perform pg_temp.rodar(d05, '17:00');
    r1 := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', d05, pg_temp.em(d05, '17:10'));
    perform pg_temp.resp('ok, terminei', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    r2 := pg_temp.rodar(d05, '17:45');
    select * into q from public.agenda_perguntas x where x.chave = c_chave;
    v_res := pg_temp.ok(v_res, 'S2 17h, o padrão da casa com o *dia feito* do dono ANTES da resposta (nenhum meio-dia de hoje da OS sem resultado): a pergunta SOBREVIVE ao passo e ao tique seguinte',
      (r1 ->> 'ok')::boolean and q.estado = 'aberta' and q.texto = c_disse
      and (r #>> '{contagens,conclusao,perguntas}')::int = 1 and (r #>> '{contagens,conclusao,terminou,fechadas}')::int = 0
      and (r2 #>> '{contagens,conclusao,terminou,fechadas}')::int = 0
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_vand and a.dia >= d05
                        and a.estado in ('publicada', 'fixada') and a.resultado is null)
      and (select so.status from public.service_orders so where so.id = c_vand) = 'in_progress',
      (r #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S3. LIMITE: o padrão da casa (o meio-dia do Gustavo, à tarde, sem resultado) ──
  begin
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok, terminei', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    select * into q from public.agenda_perguntas x where x.chave = c_chave;
    v_res := pg_temp.ok(v_res, 'S3a LIMITE CONHECIDO — 17h, o padrão da casa (o meio-dia do dono sem resultado): a OS NÃO conclui, mas a pergunta do técnico é fechada NO MESMO PASSO por _agenda_terminou_rodar ("a OS voltou a ter dia no plano"), sem ser mostrada',
      (select so.status = 'in_progress' and so.check_out_at is null from public.service_orders so where so.id = c_vand)
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand)
      and (r #>> '{contagens,conclusao,concluidas}')::int = 0 and (r #>> '{contagens,conclusao,perguntas}')::int = 1
      and (r #>> '{contagens,conclusao,terminou,fechadas}')::int = 1
      and q.texto = c_disse and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS voltou a ter dia no plano' and q.mostrada_vezes = 0
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = c_vand and a.dia = d05 and a.payee_id = c_gustavo
                    and a.estado in ('publicada', 'fixada') and a.resultado is null),
      (r #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));
    r1 := pg_temp.rodar(d05, '17:45');
    v_res := pg_temp.ok(v_res, 'S3b o tique seguinte não a recria (uma por dia: a de hoje, mesmo fechada, não nasce de novo)',
      (r1 #>> '{contagens,conclusao,perguntas}')::int = 0 and (select count(*) from public.agenda_perguntas x where x.chave = c_chave) = 1,
      (r1 #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));
    r1 := pg_temp.rodar(d06, '00:15');
    r2 := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'S3c no dia seguinte _agenda_terminou_rodar abre a pergunta GERAL (sem o que o técnico disse) e a manhã das 07:30 a mostra: o dono é perguntado, a OS segue em andamento',
      (r1 #>> '{contagens,conclusao,terminou,abertas}')::int = 1
      and pg_temp.pergs(c_vand) = 'terminou:<os>|resolvida|a OS voltou a ter dia no plano ; terminou:<os>|aberta|-'
      and (select x.texto = c_geral and x.payee_id is null from public.agenda_perguntas x where x.chave = c_chave and x.estado = 'aberta')
      and r2 ->> 'texto' = '🔧 ' || c_geral
      and (select so.status from public.service_orders so where so.id = c_vand) = 'in_progress',
      (r1 #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand) || ' | ' || coalesce(r2 ->> 'texto', '(manhã vazia)'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S4. LIMITE: a resposta às 12h (só o técnico; o "como foi" às 12:00, a hora mais cedo que o CHECK tarefas_hora deixa) ──
  begin
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    update public.agenda_config set tarefas_hora = '12:00', equipe_hora_como_foi = '12:00' where id;
    perform pg_temp.rodar(d05, '12:00');
    perform pg_temp.resp('ok', d05, '12:10');
    v_txt := (select string_agg(a.turno || '=' || coalesce(a.resultado, 'sem resultado'), ', ' order by a.turno) from public.agenda_alocacoes a
               where a.service_order_id = c_vand and a.dia = d05 and a.estado in ('publicada', 'fixada'));
    r := pg_temp.rodar(d05, '12:15');
    select * into q from public.agenda_perguntas x where x.chave = c_chave;
    v_res := pg_temp.ok(v_res, 'S4 LIMITE CONHECIDO — 12h (a tarde dele por começar: só a manhã ganha resultado): a OS NÃO conclui, mas a pergunta é fechada NO MESMO PASSO ("a OS voltou a ter dia no plano")',
      v_txt = 'manha=cumprido, tarde=sem resultado'
      and (select so.status = 'in_progress' and so.check_out_at is null from public.service_orders so where so.id = c_vand)
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand)
      and (r #>> '{contagens,conclusao,concluidas}')::int = 0 and (r #>> '{contagens,conclusao,perguntas}')::int = 1
      and (r #>> '{contagens,conclusao,terminou,fechadas}')::int = 1
      and q.texto = c_ok and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS voltou a ter dia no plano',
      v_txt || ' | ' || (r #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand));
    r1 := pg_temp.rodar(d05, '17:30');
    v_txt := (select string_agg(a.turno || '=' || coalesce(a.resultado || ' via ' || a.resultado_via, 'sem resultado'), ', ' order by a.turno)
                from public.agenda_alocacoes a where a.service_order_id = c_vand and a.dia = d05 and a.estado in ('publicada', 'fixada'));
    r2 := pg_temp.rodar(d06, '00:15');
    q := null;
    select * into q from public.agenda_perguntas x where x.chave = c_chave and x.estado = 'aberta';
    r := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'S4b depois do 12h: o tique das 17:30 não recria a do técnico (uma por dia), mas com a tarde já com resultado abre a pergunta GERAL; ela passa a noite aberta e a manhã das 07:30 a mostra; a OS segue em andamento',
      (r1 #>> '{contagens,conclusao,perguntas}')::int = 0 and (r1 #>> '{contagens,conclusao,terminou,abertas}')::int = 1
      and (r2 #>> '{contagens,conclusao,terminou,fechadas}')::int = 0
      and q.texto = c_geral and q.payee_id is null and r ->> 'texto' = '🔧 ' || c_geral
      and (select so.status from public.service_orders so where so.id = c_vand) = 'in_progress',
      v_txt || ' | ' || (r1 #> '{contagens,conclusao}')::text || ' / ' || (r2 #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand)
      || ' | ' || coalesce(r ->> 'texto', '(manhã vazia)'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S5. LIMITE: o "terminei" seco (o leitor não entende os turnos: o dia não é anotado e a OS continua agendada) ──
  begin
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('terminei', d05, '17:15');
    r := pg_temp.rodar(d05, '17:30');
    select * into q from public.agenda_perguntas x where x.chave = c_chave;
    r1 := pg_temp.rodar(d06, '00:15');
    r2 := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    v_res := pg_temp.ok(v_res, 'S5 LIMITE CONHECIDO — "terminei" seco com a OS ainda agendada: nada conclui, a pergunta é fechada NO MESMO PASSO ("a OS não está mais em andamento") e no dia seguinte nenhuma pergunta nasce (a manhã não diz nada)',
      (select so.status from public.service_orders so where so.id = c_vand) = 'scheduled'
      and not exists (select 1 from public.agenda_acoes a where a.tipo = 'concluir' and a.service_order_id = c_vand)
      and (r #>> '{contagens,conclusao,perguntas}')::int = 1 and (r #>> '{contagens,conclusao,terminou,fechadas}')::int = 1
      and q.texto = c_disse and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS não está mais em andamento'
      and (r1 #>> '{contagens,conclusao,terminou,abertas}')::int = 0
      and pg_temp.pergs(c_vand) = 'terminou:<os>|resolvida|a OS não está mais em andamento'
      and r2 ->> 'texto' is null,
      (r #> '{contagens,conclusao}')::text || ' | ' || pg_temp.pergs(c_vand) || ' | manhã: ' || coalesce(r2 ->> 'texto', '(vazia)'));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  -- ── S6. Por que não a chave terminou:<os>:equipe ──
  begin
    -- (a) no padrão da casa, a pergunta com a chave :equipe (posta à mão, como o ramo novo a poria) é fechada do mesmo jeito
    -- ("foi o dia todo": o dia dele fica anotado e a OS em andamento, sem "terminou" — o ramo novo não entra; só a pergunta posta à mão)
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('foi o dia todo', d05, '17:15');
    perform public._agenda_equipe_perguntar('concluir', c_chave || ':equipe', c_roberto, c_vand, d05, c_disse, 'ligado', pg_temp.em(d05, '17:20'));
    r := public._agenda_terminou_rodar(d05, pg_temp.em(d05, '17:30'));
    select * into q from public.agenda_perguntas x where x.chave = c_chave || ':equipe';
    v_res := pg_temp.ok(v_res, 'S6a a chave terminou:<os>:equipe NÃO escapa: _agenda_terminou_rodar (filtro like ''terminou:%'') a fecha no padrão da casa, pelo mesmo motivo',
      (r ->> 'fechadas')::int = 1 and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS voltou a ter dia no plano',
      r::text || ' | ' || pg_temp.pergs(c_vand));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- (b) só o técnico (ela sobrevive): a manhã a mostra, mas *falta dia* não a fecha (agenda_falta_dia_dito fecha a chave exata terminou:<os>)
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('foi o dia todo', d05, '17:15');
    perform public._agenda_equipe_perguntar('concluir', c_chave || ':equipe', c_roberto, c_vand, d05, c_disse, 'ligado', pg_temp.em(d05, '17:20'));
    r := pg_temp.rodar(d05, '17:30');
    r := pg_temp.rodar(d06, '00:15');
    r1 := public.agenda_aprovacoes_da_manha(d06, pg_temp.em(d06, '07:30'));
    r2 := public.agenda_falta_dia_dito(c_admin, 'OS-00069', 'whatsapp', d06, pg_temp.em(d06, '08:00'));
    select * into q from public.agenda_perguntas x where x.chave = c_chave || ':equipe';
    v_res := pg_temp.ok(v_res, 'S6b com a chave terminou:<os>:equipe, quando sobrevive, a manhã a mostra, mas *falta dia OS-00069* anota o dia e NÃO a fecha (fica aberta para sempre: a palavra fecha só a chave exata)',
      r1 ->> 'texto' = '🔧 ' || c_disse and (r2 ->> 'ok')::boolean and r2 ->> 'status' = 'ok' and (r2 ->> 'pergunta')::int = 0 and q.estado = 'aberta',
      coalesce(r1 ->> 'texto', '(manhã vazia)') || ' | falta dia: pergunta ' || (r2 ->> 'pergunta') || ' | ' || pg_temp.pergs(c_vand));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;
  begin
    -- (c) só o técnico, *concluiu* na manhã seguinte: a chave :equipe fecha (pelo mesmo like 'terminou:%' de _agenda_terminou_rodar)
    update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'dono'
     where service_order_id = c_vand and dia = d05 and payee_id = c_gustavo and estado in ('publicada', 'fixada');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('foi o dia todo', d05, '17:15');
    perform public._agenda_equipe_perguntar('concluir', c_chave || ':equipe', c_roberto, c_vand, d05, c_disse, 'ligado', pg_temp.em(d05, '17:20'));
    perform pg_temp.rodar(d05, '17:30');
    perform pg_temp.rodar(d06, '00:15');
    r1 := public.agenda_concluir_dito(c_admin, 'OS-00069', 'whatsapp', d06, pg_temp.em(d06, '08:00'));
    r2 := pg_temp.rodar(d06, '08:15');
    select * into q from public.agenda_perguntas x where x.chave = c_chave || ':equipe';
    v_res := pg_temp.ok(v_res, 'S6c com a chave terminou:<os>:equipe, *concluiu OS-00069* conclui e o tique seguinte a fecha ("a OS foi concluída"): só o *falta dia* fica sem fechá-la',
      (r1 ->> 'ok')::boolean and (select so.status from public.service_orders so where so.id = c_vand) = 'completed'
      and q.estado = 'resolvida' and q.resolvida_motivo = 'a OS foi concluída',
      (r1 ->> 'texto') || ' | ' || pg_temp.pergs(c_vand));
    raise exception 'desfaz' using errcode = 'P0098';
  exception when sqlstate 'P0098' then null;
  end;

  raise exception 'desfaz' using errcode = 'P0096';
  exception when sqlstate 'P0096' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$t$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
