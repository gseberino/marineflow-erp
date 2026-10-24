-- Prova das leituras da Fase 2 (Agenda de Produção, pacote P5; migration 20261025100500): o que o dono lê reflete o
-- plano.
-- bancada: depende de 20261025100500
--
-- Sobre a carteira de qui 29/10/2026 (scripts/bancada-agenda/fixture-fase2.sql) publicada pela vigia às 16:30 com os dois
-- modos ligados — a semana de 03 a 06/11: Vanderlei (OS-00069) ter 03 a qui 05/11 (você abre e fecha, Roberto os 3 dias),
-- Rodrigo (OS-00096) ter 03/11 à tarde (você), Lenine (OS-00074) qua 04 a seg 09/11 (você abre e fecha, João de manhã,
-- Roberto na segunda), a reserva do Flávio (OS-00104) qua 04 à tarde e sex 06 de manhã; o Nelson (OS-00112) virou a
-- decisão "não cabe" — e sobre o cenário à mão do motor (scripts/bancada-agenda/cenario-motor.sql: Antônio, Beatriz e a
-- reserva do Caio condicionada à compra do cabo):
--   V  v_agenda_dia e agenda_linhas_do_dia: os textos byte a byte, o corte em 40 e 50 sem cortar palavra, a reserva
--   M  o marcado em 'ligado' (a semana, o dia do dono, o dia de uma pessoa com e sem login)
--   F  o fechamento: as linhas (semana, decisão, dia, mudanças, pergunta) com a perda e o modo, sem a projeção da Fase 1
--      em 'ligado', o que foi registrado não volta, a decisão volta
--   G  agenda_ver: os focos decisoes, mudancas e plano, em ligado, sombra e desligado
--   E  agenda_estado_das_os: programada, reserva, compra
--   C  get_agenda_conflicts: o conflito por turno (a OS-00104 com janela de 06 a 08/10 e alocação só na manhã de 07/10)
--      e o ramo do dono
--   R  a RLS da view: o técnico vê o próprio payee, o financeiro tudo, anon nada
--   D  determinismo (md5 2×)
-- Sempre (com ou sem as fixtures):
--   P  portas: anon sem nada; authenticated e service_role leem; a view com security_invoker; as duas definer com
--      search_path fixo; get_agenda_conflicts com a ACL de antes; foco fora da lista lança 22023
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261025100500
--   Em produção, só DEPOIS de aplicar 20261025100000..100500, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase2_leituras.sql
--   Sem as fixtures (produção) os cenários saem PULADO e só P roda. Os cenários mexem em linhas só dentro de subtransações
--   desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.igual(p_res jsonb, p_nome text, p_visto text, p_esperado text) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, p_visto is not distinct from p_esperado,
           case when p_visto is distinct from p_esperado then 'veio: ' || coalesce(p_visto, '(null)') end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia, modo_leitura = 'ligado' where id
$f$;
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, (p_dia + p_hora::time) at time zone 'America/Sao_Paulo')
$f$;
-- A hora de agora para a agenda_ver (desfazer ainda vale?): agenda.agora, como o *grava* do P4.
create function pg_temp.agora(p_dia date, p_hora text) returns void language sql as $f$
  select set_config('agenda.agora', ((p_dia + p_hora::time) at time zone 'America/Sao_Paulo')::text, true)
$f$;
create function pg_temp.ver(p_foco text, p_periodo text, p_hoje date) returns text language sql as $f$
  select public.agenda_ver(null, p_periodo, null, p_foco, null, null, false, p_hoje) ->> 'texto'
$f$;
-- As linhas do dia em texto: "08:00 Vanderlei (OS-00069), dia 1 de 3: … | 13:00 …".
create function pg_temp.linhas(p_dia date, p_max int, p_hoje date) returns text language sql as $f$
  select coalesce(string_agg((x ->> 'hora') || ' ' || (x ->> 'texto'), ' | ' order by o), '')
    from jsonb_array_elements(public.agenda_linhas_do_dia(p_dia, p_max, p_hoje)) with ordinality t(x, o)
$f$;
-- As linhas do fechamento em texto: "semana/60/ligado: … || decisao/50/ligado: …".
create function pg_temp.fechamento(p_hoje date) returns text language sql as $f$
  select coalesce(string_agg((x ->> 'tipo') || '/' || (x ->> 'perda') || '/' || (x ->> 'modo') || ': ' || (x ->> 'texto'), ' || ' order by o), '')
    from jsonb_array_elements(public.agenda_textos_do_fechamento(p_hoje, null) -> 'linhas') with ordinality t(x, o)
$f$;
-- Executa p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou o erro.
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
-- A carteira de 29/10 publicada pela vigia às 16:30 (p_proposta, p_vigia = os modos).
create function pg_temp.fase2(p_proposta text default 'ligado', p_vigia text default 'ligado') returns jsonb language plpgsql as $f$
begin
  execute current_setting('agenda_teste.fase2');
  perform pg_temp.modos(p_proposta, p_vigia);
  return pg_temp.vigiar(date '2026-10-29', '16:30');
end $f$;
create function pg_temp.cenario() returns jsonb language plpgsql as $f$
begin
  execute current_setting('agenda_teste.cenario_motor');
  perform pg_temp.modos('ligado', 'ligado');
  return pg_temp.vigiar(date '2026-10-29', '16:30');
end $f$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $leituras$
declare
  v_fix     boolean := coalesce(current_setting('agenda_teste.fase2', true), '') <> ''
                       and coalesce(current_setting('agenda_teste.cenario_motor', true), '') <> ''
                       and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002');
  c_hoje    constant date := date '2026-10-29';
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec     constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_fin     constant uuid := 'aa000000-0000-4000-8000-0000000000f1';
  c_dono    constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao    constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_semana  constant text := 'Agenda: publiquei a semana de 03 a 06/11 (seg 02 é Finados): Vanderlei (ter 03 a qui 05/11), '
                             || 'Rodrigo OS-00096 (ter 03/11), Lenine (qua 04 a seg 09/11) e reserva para Flávio (qua 04 e sex 06/11). '
                             || 'Fora: Nelson (preciso de você) e Giancarlo (começa qui 26/11). Depois desta semana, só tem 6,5 dias '
                             || 'de serviço pronto na fila. *agenda plano* mostra tudo; *desfaz semana* volta.';
  c_decisao constant text := 'Agenda, preciso de você. Não cabe tudo até qui 05/11. Qual aceita atrasar? 1) Nelson (OS-00112) '
                             || 'atrasa: termina ter 17/11 em vez de qui 05/11; 2) Deixo o Nelson fora do plano por enquanto. '
                             || 'Recomendo a 1: é o menor atraso (8 dias úteis). Me responda aqui.';
  v_res     jsonb := '[]'::jsonb;
  r         jsonb;
  x         jsonb;
  v_txt     text;
  v_txt2    text;
  v_n       int;
  v_id      uuid;
begin
  if not v_fix then
    insert into _resultado values ('V–D cenários das leituras', true,
      'PULADO: sem as fixtures (agenda_teste.fase2 e cenario_motor): rode pela bancada');
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);

  -- ── V. O plano por dia e as linhas do dia ──
  begin
    r := pg_temp.fase2();
    v_res := pg_temp.ok(v_res, 'V0 a vigia publicou a semana (17 meios-dias vigentes, a decisão do Nelson aberta)',
      (r #>> '{contagens,publicacao,publicadas}')::int = 17
      and exists (select 1 from public.agenda_perguntas q where q.tipo = 'nao_cabe' and q.estado = 'aberta'), (r #> '{contagens,publicacao}')::text);
    v_res := pg_temp.ok(v_res, 'V1 v_agenda_dia: uma linha por dia e OS (10), o dono primeiro, o dia n de N da OS',
      (select count(*) from public.v_agenda_dia) = 10
      and (select v.pessoas = jsonb_build_array(
                    jsonb_build_object('payee_id', c_dono, 'nome', 'Gustavo', 'eh_dono', true, 'turnos', '["manha"]'::jsonb, 'presenca', 'abertura'),
                    jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'eh_dono', false, 'turnos', '["manha", "tarde"]'::jsonb, 'presenca', 'turno'))
                  and v.dia_n = 1 and v.dias_total = 3 and not v.reserva and v.tipo = 'execucao'
             from public.v_agenda_dia v where v.dia = date '2026-11-03' and v.numero = 'OS-00069'),
      (select string_agg(to_char(v.dia, 'DD/MM') || ' ' || v.numero || ' ' || coalesce(v.dia_n::text, '-') || '/' || coalesce(v.dias_total::text, '-'), ', '
                         order by v.dia, v.numero) from public.v_agenda_dia v));
    v_res := pg_temp.ok(v_res, 'V2 v_agenda_dia: a reserva do Flávio (teto) sem dia n de N; o fechamento do dono no último dia do Vanderlei',
      (select bool_and(v.reserva and v.tipo = 'reserva' and v.reserva_de = 'teto' and v.dia_n is null)
         from public.v_agenda_dia v where v.numero = 'OS-00104')
      and (select v.pessoas -> 0 ->> 'presenca' = 'fechamento' and v.dia_n = 3 from public.v_agenda_dia v
            where v.dia = date '2026-11-05' and v.numero = 'OS-00069'), null);
    v_res := pg_temp.igual(v_res, 'V3 agenda_linhas_do_dia ter 03/11: o texto pronto, na ordem do 1º início',
      pg_temp.linhas(date '2026-11-03', null, c_hoje),
      '08:00 Vanderlei (OS-00069), dia 1 de 3: você abre, Roberto o dia todo | 13:00 Rodrigo (OS-00096): você');
    v_res := pg_temp.igual(v_res, 'V4 agenda_linhas_do_dia qua 04/11: o 2º dia, o 1º de 4 do Lenine e a reserva',
      pg_temp.linhas(date '2026-11-04', null, c_hoje),
      '08:00 Vanderlei (OS-00069), dia 2 de 3: Roberto o dia todo | 08:00 Lenine (OS-00074), dia 1 de 4: você abre, João'
      || ' | 13:00 Reserva: Flávio (OS-00104): João');
    v_res := pg_temp.igual(v_res, 'V5 corte em 40 (o "Hoje" da manhã): as pessoas saem, o número e o "dia n de N" ficam',
      pg_temp.linhas(date '2026-11-03', 40, c_hoje), '08:00 Vanderlei (OS-00069), dia 1 de 3 | 13:00 Rodrigo (OS-00096): você');
    v_res := pg_temp.igual(v_res, 'V6 corte em 50 (o "Amanhã" do fechamento): a 1ª pessoa fica, inteira, com "…"',
      pg_temp.linhas(date '2026-11-03', 50, c_hoje), '08:00 Vanderlei (OS-00069), dia 1 de 3: você abre… | 13:00 Rodrigo (OS-00096): você');
    v_res := pg_temp.ok(v_res, 'V7 nenhuma linha passa do corte e nenhuma corta palavra (termina inteira ou com "…" depois de uma pessoa inteira)',
      not exists (select 1 from generate_series(date '2026-11-03', date '2026-11-09', interval '1 day') d,
                         jsonb_array_elements(public.agenda_linhas_do_dia(d::date, 40, c_hoje)) e
                   where char_length(e ->> 'texto') > 40),
      null);
    x := public.agenda_linhas_do_dia(date '2026-11-03', null, c_hoje) -> 0;
    v_res := pg_temp.ok(v_res, 'V8 hora e ord (o 1º início em UTC, para o secretário ordenar com as tarefas)',
      x ->> 'hora' = '08:00' and x ->> 'ord' = '2026-11-03T11:00:00+00:00' and x ->> 'os' = pg_temp.os('069')::text
      and (x ->> 'dia_n')::int = 1 and (x ->> 'dias_total')::int = 3, x::text);
    v_res := pg_temp.ok(v_res, 'V9 dia sem plano (sáb 07/11 e seg 02/11 Finados) = lista vazia',
      public.agenda_linhas_do_dia(date '2026-11-07', 40, c_hoje) = '[]'::jsonb
      and public.agenda_linhas_do_dia(date '2026-11-02', 40, c_hoje) = '[]'::jsonb, null);

    -- ── M. O marcado em 'ligado' ──
    v_txt := split_part(pg_temp.ver(null, 'proxima_semana', c_hoje), E'\n', 1);
    v_res := pg_temp.igual(v_res, 'M1 agenda_ver semana que vem: o marcado é o plano (os dias de verdade; a reserva diz que é reserva)',
      v_txt, 'A semana que vem (seg 02/11 a sáb 07/11): Vanderlei (ter 03 a qui 05/11), Rodrigo OS-00096 (ter 03/11 às 13:00), '
             || 'Lenine (qua 04 a sex 06/11) e Flávio (reserva, qua 04 e sex 06/11). Nenhuma diária foi lançada depois de sáb 17/10: '
             || 'não sei o que a equipe fez de seg 19/10 até hoje.');
    v_txt := split_part(pg_temp.ver(null, 'hoje', date '2026-11-03'), E'\n', 1);
    v_res := pg_temp.igual(v_res, 'M2 agenda hoje (ter 03/11): a hora, o dia n de N e quem vai',
      v_txt, 'Hoje (ter 03/11): Vanderlei às 08:00, dia 1 de 3 (você abre, Roberto o dia todo) e Rodrigo OS-00096 às 13:00 (você).');
    v_res := pg_temp.igual(v_res, 'M3 o dia do Roberto (login inativo) na qua 04/11 sai do plano',
      public.agenda_dia_da_pessoa(c_roberto, date '2026-11-04', c_hoje) ->> 'texto',
      'Qua 04/11, Roberto tem Vanderlei (OS-00069) o dia todo. Costuma vir de seg a sex (pelas diárias das últimas 8 semanas).');
    v_res := pg_temp.igual(v_res, 'M4 o dia do João (sem login nenhum) na qua 04/11: as duas OS, com quem mais vai',
      public.agenda_dia_da_pessoa(c_joao, date '2026-11-04', c_hoje) ->> 'texto',
      'Qua 04/11, João tem Lenine (OS-00074) de manhã (com você abrindo) e Flávio (OS-00104) à tarde, reserva. '
      || 'Costuma vir de ter a sex (pelas diárias das últimas 8 semanas: 2 de 3 quartas).');
    v_res := pg_temp.igual(v_res, 'M5 o seu dia na ter 03/11: abrindo o Vanderlei (com o Roberto) e o Rodrigo à tarde',
      public.agenda_dia_da_pessoa(c_dono, date '2026-11-03', c_hoje) ->> 'texto',
      'Ter 03/11, você tem Vanderlei (OS-00069) abrindo (com Roberto o dia todo) e Rodrigo (OS-00096) à tarde. '
      || 'Você costuma ficar em campo de seg a sex (você disse).');
    v_res := pg_temp.ok(v_res, 'M6 agenda_ver pessoa "Roberto" + dia vai ao dia dele pelo plano',
      public.agenda_ver(c_admin, '04/11', 'Roberto', null, null, null, false, c_hoje) ->> 'texto' like 'Qua 04/11, Roberto tem Vanderlei (OS-00069) o dia todo.%',
      public.agenda_ver(c_admin, '04/11', 'Roberto', null, null, null, false, c_hoje) ->> 'texto');

    -- ── F. O fechamento ──
    r := public.agenda_textos_do_fechamento(c_hoje, date '2026-10-30');
    v_res := pg_temp.igual(v_res, 'F1 qui 29/10 17:30: a semana publicada (60) e a decisão do Nelson (50), na ordem da perda',
      pg_temp.fechamento(c_hoje), 'semana/60/ligado: ' || c_semana || ' || decisao/50/ligado: ' || c_decisao);
    v_res := pg_temp.ok(v_res, 'F2 com a agenda automática ligada a projeção da semana que vem (Fase 1) sai vazia; dia_do_plano continua',
      r -> 'semana_que_vem' = '[]'::jsonb and (r ->> 'dia_do_plano')::boolean and r ->> 'cauda_amanha' is not null, (r -> 'semana_que_vem')::text);
    x := (select y from jsonb_array_elements(r -> 'linhas') y where y ->> 'tipo' = 'semana');
    v_res := pg_temp.ok(v_res, 'F3 a linha da semana leva as 4 publicações e os 3 status que vieram com elas (para ficarem contados)',
      jsonb_array_length(x -> 'acao_ids') = 7
      and (select count(*) from public.agenda_acoes a where a.id in (select y::uuid from jsonb_array_elements_text(x -> 'acao_ids') y)
             and a.tipo = 'publicar') = 4
      and (select count(*) from public.agenda_acoes a where a.id in (select y::uuid from jsonb_array_elements_text(x -> 'acao_ids') y)
             and a.tipo = 'status') = 3, (x -> 'acao_ids')::text);
    v_res := pg_temp.ok(v_res, 'F4 a linha da decisão leva a pergunta (a mostrada_vezes sobe quando o fechamento sai)',
      (select y ->> 'pergunta_id' from jsonb_array_elements(r -> 'linhas') y where y ->> 'tipo' = 'decisao')
        = (select q.id::text from public.agenda_perguntas q where q.tipo = 'nao_cabe'), null);
    perform public.agenda_fechamento_registrar(c_hoje, r -> 'linhas', 'fechamento', timestamptz '2026-10-29 17:31-03');
    v_res := pg_temp.igual(v_res, 'F5 registrado o que saiu: a semana não volta (contada); a decisão volta até ser respondida',
      pg_temp.fechamento(c_hoje), 'decisao/50/ligado: ' || c_decisao);
    v_res := pg_temp.ok(v_res, 'F6 o registro: as 7 ações contadas pelo fechamento, a pergunta mostrada 1 vez',
      (select count(*) from public.agenda_acoes a where a.contada_via = 'fechamento') = 7
      and (select q.mostrada_vezes = 1 and q.mostrada_via = 'fechamento' from public.agenda_perguntas q where q.tipo = 'nao_cabe'), null);

    -- ── G. Os focos novos da agenda_ver ──
    perform pg_temp.agora(c_hoje, '17:40');
    v_res := pg_temp.igual(v_res, 'G1 foco plano: o publicado dia a dia, com o feriado no meio',
      pg_temp.ver('plano', null, c_hoje),
      'De qui 29/10 a sáb 07/11, o que está publicado:' || E'\n'
      || 'Seg 02/11: Finados.' || E'\n'
      || 'Ter 03/11: 08:00 Vanderlei (OS-00069), dia 1 de 3: você abre, Roberto o dia todo; 13:00 Rodrigo (OS-00096): você.' || E'\n'
      || 'Qua 04/11: 08:00 Vanderlei (OS-00069), dia 2 de 3: Roberto o dia todo; 08:00 Lenine (OS-00074), dia 1 de 4: você abre, João; '
      || '13:00 Reserva: Flávio (OS-00104): João.' || E'\n'
      || 'Qui 05/11: 08:00 Vanderlei (OS-00069), dia 3 de 3: você fecha, Roberto o dia todo; 08:00 Lenine (OS-00074), dia 2 de 4: João.' || E'\n'
      || 'Sex 06/11: 08:00 Lenine (OS-00074), dia 3 de 4: João; 08:00 Reserva: Flávio (OS-00104): Roberto.');
    v_res := pg_temp.ok(v_res, 'G2 foco plano com o período dito (a semana que vem) começa na segunda',
      pg_temp.ver('plano', 'proxima_semana', c_hoje) like 'A semana que vem (seg 02/11 a sáb 07/11), o que está publicado:' || E'\n' || 'Seg 02/11: Finados.%',
      pg_temp.ver('plano', 'proxima_semana', c_hoje));
    v_res := pg_temp.igual(v_res, 'G3 foco decisoes: a decisão numerada como o rascunho resolve "a 1", e como responder',
      pg_temp.ver('decisoes', null, c_hoje),
      'Uma decisão espera você na agenda:' || E'\n'
      || 'Decisão 1: Não cabe tudo até qui 05/11. Qual aceita atrasar? 1) Nelson (OS-00112) atrasa: termina ter 17/11 em vez de qui 05/11; '
      || '2) Deixo o Nelson fora do plano por enquanto. Recomendo a 1: é o menor atraso (8 dias úteis).' || E'\n'
      || 'Para responder, diga a decisão e a opção (por exemplo, "na decisão 1, a opção 2"). Eu não escolho por você.');
    v_txt := pg_temp.ver('mudancas', null, c_hoje);
    v_res := pg_temp.ok(v_res, 'G4 foco mudancas: a publicação da semana numa linha, com *desfaz semana* (ainda vale às 17:40)',
      v_txt like 'O que mudei sozinho na agenda desde ontem:' || E'\n'
                 || '• Publiquei a semana de 03 a 06/11 (seg 02 é Finados): Vanderlei (OS-00069): ter 03 a qui 05/11, você abre e fecha, Roberto os 3 dias.%'
      and v_txt like '%Reserva (acima da carga) Flávio (OS-00104): qua 04 à tarde a sex 06/11 de manhã, João à tarde, Roberto de manhã. *desfaz semana* volta como estava.'
      and (select count(*) from regexp_matches(v_txt, '•', 'g')) = 1, v_txt);
    perform pg_temp.agora(date '2026-10-31', '09:00');
    v_txt := pg_temp.ver('mudancas', null, date '2026-10-30');
    v_res := pg_temp.ok(v_res, 'G5 foco mudancas no dia seguinte, depois do prazo de desfazer: sem *desfaz*',
      v_txt like 'O que mudei sozinho na agenda desde ontem:%' and v_txt not like '%*desfaz%', v_txt);
    v_res := pg_temp.igual(v_res, 'G6 foco mudancas dois dias depois: nada desde ontem',
      pg_temp.ver('mudancas', null, date '2026-10-31'), 'Não mudei nada na agenda desde ontem.');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── G (sombra e desligado) ──
  begin
    r := pg_temp.fase2('sombra', 'sombra');
    perform pg_temp.agora(c_hoje, '17:40');
    v_res := pg_temp.ok(v_res, 'G7 sombra: nada vigente, nenhuma linha do dia; o fechamento só com linhas de sombra (o que diria)',
      (select count(*) from public.v_agenda_dia) = 0 and public.agenda_linhas_do_dia(date '2026-11-03', 40, c_hoje) = '[]'::jsonb
      and (select bool_and(y ->> 'modo' = 'sombra') and count(*) = 2
             from jsonb_array_elements(public.agenda_textos_do_fechamento(c_hoje, null) -> 'linhas') y), pg_temp.fechamento(c_hoje));
    v_res := pg_temp.ok(v_res, 'G8 sombra: a projeção da semana que vem (Fase 1) continua no dia do plano',
      jsonb_array_length(public.agenda_textos_do_fechamento(c_hoje, null) -> 'semana_que_vem') = 3, null);
    v_txt := pg_temp.ver('plano', null, c_hoje);
    v_res := pg_temp.ok(v_res, 'G9 sombra, foco plano: "Em teste (nada foi publicado): eu montaria assim"',
      v_txt like 'Em teste (nada foi publicado): eu montaria assim — Semana de 03 a 06/11 (seg 02 é Finados).' || E'\n'
                 || 'Vanderlei (OS-00069): ter 03 a qui 05/11, você abre e fecha, Roberto os 3 dias.%'
      and v_txt like '%Fora: Robson (ORÇ-00083): assinado em 23/08 e nunca virou OS: converter ou arquivar?' || E'\n' || '%', v_txt);
    v_res := pg_temp.ok(v_res, 'G10 sombra, foco mudancas: "Em teste (nada foi mudado)" e o que teria feito',
      pg_temp.ver('mudancas', null, c_hoje) like 'Em teste (nada foi mudado): desde ontem eu teria feito isto.' || E'\n'
                                                 || '• Publicaria a semana de 03 a 06/11 (seg 02 é Finados): Vanderlei (OS-00069):%',
      pg_temp.ver('mudancas', null, c_hoje));
    v_res := pg_temp.ok(v_res, 'G11 sombra, foco decisoes: "Em teste (nada foi perguntado de verdade)" com a pergunta',
      pg_temp.ver('decisoes', null, c_hoje) like 'Em teste (nada foi perguntado de verdade): eu perguntaria isto.' || E'\n'
                                                 || '• Não cabe tudo até qui 05/11.%', pg_temp.ver('decisoes', null, c_hoje));
    perform pg_temp.modos('desligado', 'desligado');
    v_res := pg_temp.ok(v_res, 'G12 desligado: sem linhas no fechamento; plano, mudanças e decisões dizem que está desligada',
      public.agenda_textos_do_fechamento(c_hoje, null) -> 'linhas' = '[]'::jsonb
      and pg_temp.ver('plano', null, c_hoje) = 'A agenda automática está desligada: não há plano publicado.'
      and pg_temp.ver('mudancas', null, c_hoje) = 'A agenda automática está desligada: eu não mudo nada sozinho.'
      and pg_temp.ver('decisoes', null, c_hoje) = 'Nada esperando você na agenda agora.', null);
    update public.agenda_config set modo_leitura = 'desligado' where id;
    v_res := pg_temp.ok(v_res, 'G13 leitura desligada: o fechamento cala (linhas vazias) e a agenda_ver diz desligada',
      public.agenda_textos_do_fechamento(c_hoje, null) -> 'linhas' = '[]'::jsonb
      and (public.agenda_ver(null, null, null, 'plano', null, null, false, c_hoje) ->> 'desligada')::boolean, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── E. O estado das OS ──
  begin
    perform pg_temp.fase2();
    v_res := pg_temp.ok(v_res, 'E1 Vanderlei: programada, próximo dia ter 03/11, nada a comprar; Flávio: só a reserva (não programada)',
      (select e ->> 'programada' = 'true' and e ->> 'proximo_dia' = '2026-11-03' and e -> 'compra' = 'null'::jsonb and e ->> 'estado' = 'programada'
         from public.agenda_estado_das_os(c_hoje) e where e ->> 'numero' = 'OS-00069')
      and (select e ->> 'programada' = 'false' and e ->> 'reserva_dia' = '2026-11-04'
             from public.agenda_estado_das_os(c_hoje) e where e ->> 'numero' = 'OS-00104')
      and (select count(*) from public.agenda_estado_das_os(c_hoje) e where e ->> 'numero' like 'ORÇ%') = 0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.cenario();
    x := (select y from public.agenda_estado_das_os(c_hoje) y where y ->> 'numero' = 'OS-00203');
    v_res := pg_temp.igual(v_res, 'E2 Caio: a compra até o dia-limite da reserva condicionada',
      x -> 'compra' ->> 'texto', 'Caio (OS-00203): 1 item a comprar até ter 03/11 para a reserva de qui 05/11');
    v_res := pg_temp.ok(v_res, 'E3 Caio: compre_ate ter 03/11, para qui 05/11, é reserva; não está parada nem programada',
      x #>> '{compra,compre_ate}' = '2026-11-03' and x #>> '{compra,para_dia}' = '2026-11-05' and (x #>> '{compra,reserva}')::boolean
      and not (x ->> 'parada')::boolean and not (x ->> 'programada')::boolean, x::text);
    v_res := pg_temp.igual(v_res, 'E4 a reserva condicionada na linha do dia: a condição pronta do motor',
      pg_temp.linhas(date '2026-11-05', null, c_hoje),
      '08:00 Beatriz (OS-00202): você, Roberto | 13:00 Reserva: Caio (OS-00203), se "Cabo de bateria…" estiver na mão '
      || '(compre até ter 03/11, fornecedor Premel)');
    v_res := pg_temp.igual(v_res, 'F7 o cenário na quinta: a semana sem "Fora" e com a fila vazia da vigia',
      pg_temp.fechamento(c_hoje),
      'semana/60/ligado: Agenda: publiquei a semana de 03 a 06/11 (seg 02 é Finados): Antônio (ter 03 e qua 04/11), Beatriz (qui 05/11) '
      || 'e reserva para Caio (qui 05 a ter 10/11). Depois desta semana, não tem serviço pronto na fila. *agenda plano* mostra tudo; '
      || '*desfaz semana* volta.');
    perform public.agenda_fechamento_registrar(c_hoje, public.agenda_textos_do_fechamento(c_hoje, null) -> 'linhas', 'fechamento',
                                               timestamptz '2026-10-29 17:31-03');
    -- sex 30/10: o Roberto avisa que não vem qui 05/11 de manhã → a vigia move a Beatriz (fora do congelado: sem acorde)
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-11-05', date '2026-11-06'), 'manha', 'indisponivel', 'dono', 'médico');
    perform pg_temp.vigiar(date '2026-10-30', '09:15');
    v_id := (select a.id from public.agenda_acoes a where a.dia = date '2026-10-30' and a.tipo = 'mover' and a.origem = 'vigia');
    v_res := pg_temp.igual(v_res, 'F8 sex 30/10 (sem plano no dia): o que mudou sozinho numa linha (40), com *desfaz*',
      pg_temp.fechamento(date '2026-10-30'),
      'mudancas/40/ligado: Agenda, mudei sozinho. Beatriz (OS-00202): de qui 05/11 para qui 05/11 — quem ia não está mais livre. '
      || '*desfaz Beatriz* volta como estava.');
    v_res := pg_temp.ok(v_res, 'F9 a linha das mudanças leva a ação (para ficar contada)',
      (select y -> 'acao_ids' = jsonb_build_array(v_id) from jsonb_array_elements(public.agenda_textos_do_fechamento(date '2026-10-30', null) -> 'linhas') y),
      null);
    -- ter 03/11 13:30: o último meio-dia de hoje começou → a conferência; o mover de sex 30/10 não foi contado: vai junto
    perform pg_temp.vigiar(date '2026-11-03', '13:30');
    v_res := pg_temp.igual(v_res, 'F10 ter 03/11: a conferência do dia (70) com o que mudou sozinho e ainda não foi contado',
      pg_temp.fechamento(date '2026-11-03'),
      'dia/70/ligado: Agenda de hoje: Antônio (OS-00201) — você abre, Roberto o dia todo, João à tarde. Foi isso? Responda *dia feito* '
      || 'ou conte o que mudou. Mudei sozinho: Beatriz (OS-00202): de qui 05/11 para qui 05/11 — quem ia não está mais livre. '
      || '*desfaz Beatriz* volta como estava.');
    perform public.agenda_fechamento_registrar(date '2026-11-03', public.agenda_textos_do_fechamento(date '2026-11-03', null) -> 'linhas',
                                               'fechamento', timestamptz '2026-11-03 17:31-03');
    v_res := pg_temp.igual(v_res, 'F11 registrado: a mudança não volta; a conferência aberta volta (é a pergunta de hoje)',
      pg_temp.fechamento(date '2026-11-03'),
      'dia/70/ligado: Agenda de hoje: Antônio (OS-00201) — você abre, Roberto o dia todo, João à tarde. Foi isso? Responda *dia feito* '
      || 'ou conte o que mudou.');
    -- as perguntas de fato: duas "chegou?" (uma só no fechamento, a que perde primeiro, e "e mais 1")
    insert into public.agenda_perguntas (tipo, chave, service_order_id, perda_em, texto, modo, criada_em) values
      ('chegou', 'chegou:teste:1', pg_temp.os('203'), date '2026-11-05', 'O cabo do Caio tinha previsão para ter 03/11. Chegou?', 'ligado',
       timestamptz '2026-11-03 12:00-03'),
      ('chegou', 'chegou:teste:2', pg_temp.os('202'), date '2026-11-06', 'A peça da Beatriz tinha previsão para ter 03/11. Chegou?', 'ligado',
       timestamptz '2026-11-03 12:00-03');
    v_txt := pg_temp.fechamento(date '2026-11-03');
    v_res := pg_temp.ok(v_res, 'F12 a pergunta de fato (30) depois do dia: uma só, a que perde primeiro, com "e mais 1"',
      v_txt like 'dia/70/ligado: % || pergunta/30/ligado: Agenda: O cabo do Caio tinha previsão para ter 03/11. Chegou? (e mais 1 em *agenda pendências*)',
      v_txt);
    update public.agenda_perguntas set mostrada_vezes = (select perguntas_vezes_max from public.agenda_config) where chave = 'chegou:teste:1';
    v_res := pg_temp.ok(v_res, 'F13 a que já apareceu perguntas_vezes_max vezes sai; fica a outra, sozinha',
      pg_temp.fechamento(date '2026-11-03') like '% || pergunta/30/ligado: Agenda: A peça da Beatriz tinha previsão para ter 03/11. Chegou?',
      pg_temp.fechamento(date '2026-11-03'));
    -- a perda da decisão: até amanhã útil 100, até 2 dias úteis 80
    insert into public.agenda_perguntas (tipo, chave, service_order_id, perda_em, texto, opcoes, recomendacao, modo) values
      ('atraso_longo', 'atraso_longo:teste:1', pg_temp.os('201'), date '2026-11-04', 'Sigo com o Antônio em qua 18/11?',
       '[{"n":1,"texto":"sigo"},{"n":2,"texto":"deixo fora"}]', 1, 'ligado'),
      ('atraso_longo', 'atraso_longo:teste:2', pg_temp.os('202'), date '2026-11-05', 'Sigo com a Beatriz em qua 18/11?',
       '[{"n":1,"texto":"sigo"},{"n":2,"texto":"deixo fora"}]', 1, 'ligado');
    v_txt := pg_temp.fechamento(date '2026-11-03');
    v_res := pg_temp.ok(v_res, 'F14 a decisão que perde amanhã útil vem primeiro (100), a de 2 dias úteis depois (80), antes do dia (70)',
      v_txt like 'decisao/100/ligado: Agenda, preciso de você. Sigo com o Antônio em qua 18/11? Me responda aqui. || '
                 || 'decisao/80/ligado: Agenda, preciso de você. Sigo com a Beatriz em qua 18/11? Me responda aqui. || dia/70/ligado: %', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── C. O conflito de agenda da tela ──
  begin
    perform pg_temp.fase2();
    v_txt := (select string_agg(c.source || ' ' || c.label || ' ' || to_char(c.starts_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
                                || '-' || to_char(c.ends_at at time zone 'America/Sao_Paulo', 'HH24:MI'), ', ' order by c.starts_at, c.label)
                from public.get_agenda_conflicts(c_admin, timestamptz '2026-11-03 00:00-03', timestamptz '2026-11-06 00:00-03') c);
    v_res := pg_temp.igual(v_res, 'C1 o dono (pelo payee sócio, sem ser técnico das OS): a abertura, o turno e o fechamento, não a janela',
      v_txt, 'alocacao OS-00069 03/11 08:00-09:00, alocacao OS-00096 03/11 13:00-17:00, alocacao OS-00074 04/11 08:00-09:00, '
             || 'alocacao OS-00069 05/11 16:00-17:00');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.fase2');
    perform pg_temp.modos('sombra', 'sombra');
    -- a OS-00104 com a janela de 06 a 08/10 e o Roberto técnico dela
    update public.service_orders set scheduled_start_at = timestamptz '2026-10-06 08:00-03', scheduled_end_at = timestamptz '2026-10-08 17:00-03'
     where id = pg_temp.os('104');
    insert into public.service_order_technicians (service_order_id, user_id) values (pg_temp.os('104'), c_tec) on conflict do nothing;
    v_txt := (select string_agg(c.source || ' ' || to_char(c.starts_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || '-'
                                || to_char(c.ends_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), ', ' order by c.starts_at)
                from public.get_agenda_conflicts(c_tec, timestamptz '2026-10-06 00:00-03', timestamptz '2026-10-09 00:00-03') c);
    v_res := pg_temp.igual(v_res, 'C2 sem alocação: a janela corrida inteira, como antes', v_txt, 'service_order 06/10 08:00-08/10 17:00');
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, origem)
    values (pg_temp.os('104'), c_roberto, date '2026-10-07', 'manha', 'publicada', 'dono');
    v_txt := (select string_agg(c.source || ' ' || to_char(c.starts_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || '-'
                                || to_char(c.ends_at at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), ', ' order by c.starts_at)
                from public.get_agenda_conflicts(c_tec, timestamptz '2026-10-06 00:00-03', timestamptz '2026-10-09 00:00-03') c);
    v_res := pg_temp.igual(v_res, 'C3 com alocação só na manhã de 07/10: o conflito é só das 08 às 12 de 07/10', v_txt,
      'service_order 07/10 08:00-07/10 12:00');
    v_res := pg_temp.ok(v_res, 'C4 a OS de fora (p_exclude_so) não conta', not exists (
      select 1 from public.get_agenda_conflicts(c_tec, timestamptz '2026-10-06 00:00-03', timestamptz '2026-10-09 00:00-03', null, pg_temp.os('104'))), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── R. A RLS da view ──
  begin
    perform pg_temp.fase2();
    update public.app_users set active = true where id = c_tec;
    insert into public.app_users (id, full_name, email, role, active) values (c_fin, 'Financeiro', 'fin@bancada.invalid', 'financial', true);
    v_txt := pg_temp.como(c_tec, 'authenticated',
      $q$select string_agg(to_char(v.dia, 'DD/MM') || ' ' || v.numero || ' ' || (v.pessoas)::text, ' | ' order by v.dia, v.numero) from public.v_agenda_dia v$q$);
    v_res := pg_temp.ok(v_res, 'R1 o técnico (Roberto) vê só os dias em que ele está, e só ele, com o próprio nome',
      v_txt not like '%Gustavo%' and v_txt not like '%João%' and v_txt like '03/11 OS-00069 [{"nome": "Roberto"%'
      and (select count(*) from regexp_matches(v_txt, ' \| ', 'g')) = 4, v_txt);
    v_res := pg_temp.igual(v_res, 'R2 o técnico lê a linha do dia dele (sem config nenhuma: a view não lê agenda_config)',
      pg_temp.como(c_tec, 'authenticated', $q$select string_agg(x ->> 'texto', ' | ') from jsonb_array_elements(public.agenda_linhas_do_dia(date '2026-11-03', null, date '2026-10-29')) x$q$),
      'Vanderlei (OS-00069), dia 1 de 3: Roberto o dia todo');
    v_res := pg_temp.igual(v_res, 'R3 o financeiro vê tudo (10 linhas)',
      pg_temp.como(c_fin, 'authenticated', 'select count(*)::text from public.v_agenda_dia'), '10');
    v_res := pg_temp.ok(v_res, 'R4 anon não lê a view',
      pg_temp.como(null, 'anon', 'select count(*)::text from public.v_agenda_dia') like 'erro 42501%', null);
    v_res := pg_temp.igual(v_res, 'R5 o nome de outra pessoa não sai para o técnico (_agenda_pessoa)',
      pg_temp.como(c_tec, 'authenticated', format('select public._agenda_pessoa(%L)::text', c_joao)), '{"nome": null, "eh_dono": false}');
    v_res := pg_temp.igual(v_res, 'R6 os payees de outro login não saem para o técnico (_agenda_payees_do_usuario)',
      pg_temp.como(c_tec, 'authenticated', format('select public._agenda_payees_do_usuario(%L)::text', c_admin)), '{}');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D. Determinismo ──
  begin
    perform pg_temp.fase2();
    perform pg_temp.agora(c_hoje, '17:40');
    v_res := pg_temp.ok(v_res, 'D1 mesma entrada, mesma saída (md5 2×): as linhas do dia, o fechamento, o plano, as decisões, o estado das OS',
      md5(public.agenda_linhas_do_dia(date '2026-11-04', 50, c_hoje)::text) = md5(public.agenda_linhas_do_dia(date '2026-11-04', 50, c_hoje)::text)
      and md5(public.agenda_textos_do_fechamento(c_hoje, null)::text) = md5(public.agenda_textos_do_fechamento(c_hoje, null)::text)
      and md5(pg_temp.ver('plano', null, c_hoje)) = md5(pg_temp.ver('plano', null, c_hoje))
      and md5(pg_temp.ver('decisoes', null, c_hoje)) = md5(pg_temp.ver('decisoes', null, c_hoje))
      and md5((select jsonb_agg(e)::text from public.agenda_estado_das_os(c_hoje) e))
          = md5((select jsonb_agg(e)::text from public.agenda_estado_das_os(c_hoje) e)), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$leituras$;

-- ── P. Portas (sempre) ──────────────────────────────────────────────────────────────────────────────────
create temp table _funcoes_p5 (f text) on commit drop;
insert into _funcoes_p5 values
  ('public._agenda_pessoa(uuid)'), ('public._agenda_payees_do_usuario(uuid)'), ('public._agenda_pessoas_do_dia(jsonb)'),
  ('public.agenda_linhas_do_dia(date, integer, date)'), ('public._agenda_marcados(date, date, date, uuid, uuid)'),
  ('public._agenda_parte_da_pessoa(jsonb)'), ('public.agenda_dia_da_pessoa(uuid, date, date)'),
  ('public._agenda_mudancas(date, date, boolean, boolean, timestamptz)'), ('public._agenda_mudanca_texto(jsonb, boolean)'),
  ('public._agenda_ver_decisoes(date, timestamptz)'), ('public._agenda_ver_mudancas(date, timestamptz)'),
  ('public._agenda_ver_plano(date, date, date, timestamptz)'),
  ('public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)'),
  ('public._agenda_linha_da_semana(uuid, jsonb, boolean, date)'), ('public._agenda_linhas_do_fechamento(date)'),
  ('public.agenda_textos_do_fechamento(date, date)'), ('public.agenda_estado_das_os(date)'),
  ('public.get_agenda_conflicts(uuid, timestamptz, timestamptz, uuid, uuid)');

insert into _resultado
select 'P1 anon não executa nenhuma função das leituras (nem a get_agenda_conflicts recriada)',
       not bool_or(has_function_privilege('anon', f, 'execute')),
       string_agg(f, ', ') filter (where has_function_privilege('anon', f, 'execute'))
  from _funcoes_p5;

insert into _resultado
select 'P2 authenticated (o painel, a tela) e service_role (WhatsApp, fechamento) executam todas',
       bool_and(has_function_privilege('authenticated', f, 'execute') and has_function_privilege('service_role', f, 'execute')),
       string_agg(f, ', ') filter (where not has_function_privilege('authenticated', f, 'execute')
                                      or not has_function_privilege('service_role', f, 'execute'))
  from _funcoes_p5;

insert into _resultado
select 'P3 só _agenda_pessoa e _agenda_payees_do_usuario são security definer; todas STABLE/IMMUTABLE com search_path fixo',
       bool_and(p.prosecdef = (p.proname in ('_agenda_pessoa', '_agenda_payees_do_usuario')))
       and bool_and(p.provolatile in ('s', 'i'))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%') and count(*) = 18,
       count(*)::text || ' | ' || coalesce(string_agg(p.oid::regprocedure::text, ', ')
                                    filter (where p.prosecdef <> (p.proname in ('_agenda_pessoa', '_agenda_payees_do_usuario'))
                                               or p.provolatile not in ('s', 'i')
                                               or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%'), '')
  from pg_proc p
 where p.oid in (select f::regprocedure::oid from _funcoes_p5);

insert into _resultado
select 'P4 v_agenda_dia: security_invoker = on; anon sem select; authenticated e service_role com select',
       coalesce((select 'security_invoker=on' = any (c.reloptions) from pg_class c where c.oid = 'public.v_agenda_dia'::regclass), false)
       and not has_table_privilege('anon', 'public.v_agenda_dia', 'select')
       and has_table_privilege('authenticated', 'public.v_agenda_dia', 'select')
       and has_table_privilege('service_role', 'public.v_agenda_dia', 'select')
       and not has_table_privilege('authenticated', 'public.v_agenda_dia', 'insert'),
       (select array_to_string(c.reloptions, ',') from pg_class c where c.oid = 'public.v_agenda_dia'::regclass);

insert into _resultado
select 'P5 get_agenda_conflicts com a mesma assinatura (uma versão só) e o mesmo retorno',
       count(*) = 1 and bool_and(pg_get_function_result(p.oid) like 'TABLE(source text, ref_id uuid, label text, starts_at timestamp with time zone, ends_at timestamp with time zone)'),
       string_agg(p.oid::regprocedure::text, ', ')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'get_agenda_conflicts';

insert into _resultado
select 'P6 uma versão só de agenda_ver, agenda_textos_do_fechamento, agenda_dia_da_pessoa e _agenda_marcados (mesmas assinaturas)',
       count(*) = 4, string_agg(p.oid::regprocedure::text, ', ')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('agenda_ver', 'agenda_textos_do_fechamento', 'agenda_dia_da_pessoa', '_agenda_marcados');

do $p7$
declare
  v_st text;
begin
  begin
    perform public.agenda_ver(null, null, null, 'qualquer', null, null, false, date '2026-10-29');
    v_st := 'sem erro';
  exception when others then
    v_st := sqlstate;
  end;
  insert into _resultado values ('P7 agenda_ver com foco fora da lista lança 22023 (os novos entram: decisoes, mudancas, plano)',
    v_st = '22023', v_st);
end
$p7$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
