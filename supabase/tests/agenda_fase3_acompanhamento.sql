-- Prova do acompanhamento da Agenda de Produção, Fase 3 (pacote P6; migration 20261026100500): o PPC, as linhas novas do
-- fechamento das 17:30, os focos novos da agenda_ver, o "livre de verdade" pela simulação e a carona.
-- bancada: depende de 20261026100500
--
-- Sobre a carteira da Fase 3 (scripts/bancada-agenda/fixture-fase3.sql: qui 29/10/2026, a semana de 03 a 06/11 publicada
-- pela vigia — Vanderlei (OS-00069) ter 03 a qui 05/11, o Roberto o dia todo, você abre e fecha; Flávio (OS-00104) ter 03
-- (você e o João à tarde) e qua 04/11 (de manhã); Rodrigo (OS-00096) qua 04/11 à tarde (você); Lenine (OS-00074) sex 06 a
-- ter 10/11; o Nelson (OS-00112) com a decisão "não cabe" aberta; o Roberto (telefone sintético) na rotina; o João sem
-- telefone; seg 02/11 é Finados e ter 03/11 o 1º dia útil de novembro):
--   P  o PPC: a semana de 03 a 06/11 com 1 não cumprido (imprevisto) e 1 sem conferência; a alocação criada no próprio
--      dia depois do início fica fora; a sexta com feriado (20/11) põe a linha na quinta; semana sem compromisso
--   D  a linha dia: o Roberto confirmou e a diária lançada, o João a confirmar; o Roberto sem resposta ainda; sem nada da
--      equipe (byte a byte o da Fase 2); o último dia da OS; só o Roberto, tudo confirmado; a sombra da diária no detalhe
--   X  a linha diaria (crítica): as opções, a recomendação e as palavras; 80 com 2 dias úteis; em sombra
--   C  a linha conclusao: o que o gestor concluiu pela palavra do técnico, com o *desfaz* pelo número; contada não volta
--   F  a comissão no 1º dia útil do mês (e não nos outros); a sombra da vigia; a ordem pela perda
--   V  a agenda_ver: os focos ppc, diarias, marcos, comissao e equipe; o mês dito; foco inválido; livre em ligado e sombra
--   L  agenda_livre_de_verdade: nenhuma tabela da agenda muda (contagem e md5), determinística, < 2 s, projeção fora de
--      ligado, quem pode ver
--   K  a carona: 1 OS com pergunta aberta (a crítica primeiro); de novo na semana não; 8 dias depois sim; 2 OS não; a vigia
--      em sombra não; outro autor não; a que saiu hoje no fechamento não
--   M  _agenda_mudancas na ordem de gravação (criada_em, OS, id): o G10 da Fase 2 deixa de depender do id aleatório
-- Sempre (com ou sem a fixture):
--   J  portas: anon sem nada; as leituras para authenticated e service_role; a carona e o registro do job só service_role
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261026100500
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase3_acompanhamento.sql
--   Sem a fixture (produção) os cenários saem PULADO e só J roda. Os cenários mexem em linhas só dentro de subtransações
--   desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

set local timezone = 'UTC';

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
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.modos(p_equipe text, p_diaria text) returns void language sql as $f$
  update public.agenda_config set modo_equipe = p_equipe, modo_diaria = p_diaria, modo_leitura = 'ligado' where id
$f$;
create function pg_temp.rodar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_rotina_rodar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
create function pg_temp.resp(p_texto text, p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_resposta_da_equipe('5547900000001', p_texto, md5(p_texto || p_dia || p_hora), pg_temp.em(p_dia, p_hora))
$f$;
-- A hora de agora para o que o banco lê de now() (a agenda_ver: desfazer ainda vale? a decisão venceu?).
create function pg_temp.agora(p_dia date, p_hora text) returns void language sql as $f$
  select set_config('agenda.agora', pg_temp.em(p_dia, p_hora)::text, true)
$f$;
create function pg_temp.ver(p_foco text, p_periodo text, p_hoje date, p_os text default null) returns text language sql as $f$
  select public.agenda_ver('aa000000-0000-4000-8000-000000000001', p_periodo, null, p_foco, p_os, null, false, p_hoje) ->> 'texto'
$f$;
-- As linhas do fechamento: "tipo/perda/modo: texto || …", na ordem do banco.
create function pg_temp.fech(p_hoje date) returns text language sql as $f$
  select coalesce(string_agg((x ->> 'tipo') || '/' || (x ->> 'perda') || '/' || (x ->> 'modo') || ': ' || (x ->> 'texto'), ' || ' order by o), '')
    from jsonb_array_elements(public.agenda_textos_do_fechamento(p_hoje, null) -> 'linhas') with ordinality t(x, o)
$f$;
-- Uma linha do fechamento pelo tipo e pelo modo (a 1ª), inteira.
create function pg_temp.linha(p_hoje date, p_tipo text, p_modo text default 'ligado') returns jsonb language sql as $f$
  select x from jsonb_array_elements(public.agenda_textos_do_fechamento(p_hoje, null) -> 'linhas') with ordinality t(x, o)
   where x ->> 'tipo' = p_tipo and x ->> 'modo' = p_modo order by o limit 1
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
-- O retrato de TODAS as tabelas agenda_* (linhas e md5 de cada uma), para provar que a simulação não grava nada.
create function pg_temp.retrato() returns jsonb language plpgsql as $f$
declare
  t text;
  v jsonb := '{}'::jsonb;
  n bigint;
  h text;
begin
  for t in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
            where s.nspname = 'public' and c.relkind = 'r' and c.relname like 'agenda\_%' order by 1 loop
    execute format('select count(*), md5(coalesce(string_agg(x::text, ''|'' order by x::text), '''')) from public.%I x', t) into n, h;
    v := v || jsonb_build_object(t, jsonb_build_object('n', n, 'md5', h));
  end loop;
  return v;
end $f$;
-- Um resultado no plano (sem passar pela conversa): o dia já chegou para quem escreve (agenda.hoje).
create function pg_temp.resultado(p_os text, p_dia date, p_resultado text, p_motivo text default null) returns void language plpgsql as $f$
begin
  perform set_config('agenda.hoje', '2026-11-20', true);
  update public.agenda_alocacoes a set resultado = p_resultado, motivo = p_motivo, resultado_via = 'tela'
   where a.service_order_id = ('05000000-0000-4000-8000-' || lpad(p_os, 12, '0'))::uuid and a.dia = p_dia
     and a.estado in ('publicada', 'fixada') and a.tipo <> 'reserva';
  perform set_config('agenda.hoje', '', true);
end $f$;

-- ── M. As mudanças na ordem de gravação (a carteira da Fase 2 publicada em sombra: o G10) ────────────────
do $ordem$
declare
  v_res jsonb := '[]'::jsonb;
  g     jsonb;
  v_esp jsonb;
begin
  if coalesce(current_setting('agenda_teste.fase2', true), '') = '' then
    insert into _resultado values ('M0 a ordem (fixture-fase2)', true, 'PULADO: sem agenda_teste.fase2 (rode pela bancada)');
    return;
  end if;
  -- numa subtransação desfeita na hora (a carteira da Fase 2 em sombra não pode ficar para os outros cenários)
  begin
  execute current_setting('agenda_teste.fase2');
  update public.agenda_config set modo_proposta = 'sombra', modo_vigia = 'sombra', modo_leitura = 'ligado' where id;
  perform public.agenda_vigiar(date '2026-10-29', (date '2026-10-29' + time '16:30') at time zone 'America/Sao_Paulo');
  g := (select x from jsonb_array_elements(public._agenda_mudancas(date '2026-10-28', date '2026-10-29', false, false, null)) x
         where x ->> 'tipo' = 'publicacao' limit 1);
  select jsonb_agg(a.texto order by a.criada_em, a.service_order_id, a.id) into v_esp
    from public.agenda_acoes a where a.tipo = 'publicar' and not a.executada;
  v_res := pg_temp.ok(v_res, 'M1 a publicação em sombra: os itens na ordem criada_em, OS, id (o Vanderlei, OS-00069, primeiro)',
    g -> 'itens' = v_esp and g #>> '{itens,0}' like 'Vanderlei (OS-00069):%', coalesce(g::text, 'null'));
  v_res := pg_temp.ok(v_res, 'M2 a mesma leitura duas vezes, o mesmo resultado (md5)',
    md5(public._agenda_mudancas(date '2026-10-28', date '2026-10-29', false, false, null)::text)
    = md5(public._agenda_mudancas(date '2026-10-28', date '2026-10-29', false, false, null)::text), null);
  raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end $ordem$;

-- ── Os cenários sobre a carteira da Fase 3 (só na bancada) ───────────────────────────────────────────────
do $acomp$
declare
  v_res     jsonb := '[]'::jsonb;
  r         jsonb;
  r2        jsonb;
  x         jsonb;
  v_txt     text;
  v_id      uuid;
  v_ret     jsonb;
  v_t0      timestamptz;
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec     constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_mickael constant uuid := 'bb000000-0000-4000-8000-000000000004';
  c_vand    constant uuid := '05000000-0000-4000-8000-000000000069';
  c_nelson  constant uuid := '05000000-0000-4000-8000-000000000112';
  d30 constant date := date '2026-10-30';
  d02 constant date := date '2026-11-02';
  d03 constant date := date '2026-11-03';
  d04 constant date := date '2026-11-04';
  d05 constant date := date '2026-11-05';
  d06 constant date := date '2026-11-06';
  d09 constant date := date '2026-11-09';
  -- o começo do texto da conferência da vigia de ter 03/11 (Fase 2: agenda_fase2_conferencia_vigia.sql)
  c_dia03 constant text := 'Agenda de hoje: Vanderlei (OS-00069) — você abre, Roberto o dia todo; Flávio (OS-00104) — você, João.';
  c_cauda constant text := ' Foi isso? Responda *dia feito* ou conte o que mudou.';
  c_joao  constant text := ' Foi isso para o João? *dia feito* lança a meia diária dele, ou conte o que mudou.';
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    insert into _resultado values ('A0 os cenários (fixture-fase3)', true, 'PULADO: sem agenda_teste.fase3 (rode pela bancada)');
    return;
  end if;
  execute current_setting('agenda_teste.fase3');
  -- O registrar_diaria (a decisão do dono) recusa "dia no futuro" pelo relógio de verdade (_hoje_brt): aqui o "hoje" do
  -- teste vale também para ele (como no agenda_fase3_equipe_diarias.sql). O ROLLBACK do fim desfaz.
  create or replace function public._hoje_brt() returns date language sql stable set search_path to 'public' as $h$
    select coalesce(nullif(current_setting('agenda_teste.hoje', true), '')::date, (now() at time zone 'America/Sao_Paulo')::date)
  $h$;
  perform set_config('agenda_teste.hoje', '2026-11-20', true);

  -- ── P. O PPC ───────────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('desligado', 'desligado');
    perform pg_temp.resultado('69', d03, 'cumprido');
    perform pg_temp.resultado('104', d03, 'cumprido');
    perform pg_temp.resultado('69', d04, 'nao_cumprido', 'imprevisto_tecnico');
    perform pg_temp.resultado('96', d04, 'cumprido');
    -- o Flávio de qua 04/11 fica sem conferência
    perform pg_temp.resultado('69', d05, 'cumprido');
    perform pg_temp.resultado('74', d06, 'cumprido');
    r := public.agenda_ppc(null, d06);
    v_res := pg_temp.ok(v_res, 'P1 sex 06/11: 7 compromissos, 5 cumpridos, 1 não cumprido, 1 sem conferência; ppc = 5/6',
      (r ->> 'compromissos')::int = 7 and (r ->> 'cumpridos')::int = 5 and jsonb_array_length(r -> 'nao_cumpridos') = 1
      and jsonb_array_length(r -> 'sem_conferencia') = 1 and (r ->> 'ppc')::numeric = 0.8333 and (r ->> 'meta')::numeric = 0.70
      and (r ->> 'ultimo_dia_util')::boolean and r -> 'semana' = '{"de": "2026-11-03", "ate": "2026-11-06"}'::jsonb, r::text);
    v_res := pg_temp.igual(v_res, 'P2 o texto da conversa (a meta, o motivo da lista e quem estava no dia sem conferência)', r ->> 'texto',
      'Semana de 03 a 06/11 (seg 02 é Finados): 5 de 6 dias de serviço cumpridos (83%; a meta é 70%).' || E'\n'
      || 'Não cumprido: Vanderlei qua 04/11 — imprevisto.' || E'\n'
      || 'Sem conferência: qua 04/11 (Flávio: você e João).');
    v_res := pg_temp.igual(v_res, 'P3 a linha do fechamento (uma só), com o *dia feito dd/mm* que a palavra entende', r ->> 'linha',
      'Semana de 03 a 06/11 (seg 02 é Finados): 5 de 6 dias de serviço cumpridos (83%). Não cumprido: Vanderlei qua 04/11 '
      || '(imprevisto). Sem conferência: qua 04/11 (Flávio) — *dia feito 04/11* confirma.');
    v_res := pg_temp.ok(v_res, 'P4 os motivos por código LCI e o motivo_texto do não cumprido',
      r -> 'motivos' = '{"imprevisto_tecnico": 1}'::jsonb and r #>> '{nao_cumpridos,0,motivo_texto}' = 'imprevisto'
      and r #>> '{nao_cumpridos,0,numero}' = 'OS-00069' and r #>> '{sem_conferencia,0,pessoas}' = 'você e João', r::text);
    -- a alocação criada no próprio dia, depois do início, não é compromisso; a da véspera é
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, origem, publicada_em)
    values (c_nelson, c_mickael, d05, 'manha', 'publicada', 'dono', pg_temp.em(d05, '10:00')),
           (c_nelson, c_mickael, d06, 'tarde', 'publicada', 'dono', pg_temp.em(d05, '18:00'));
    r := public.agenda_ppc(null, d06);
    v_res := pg_temp.ok(v_res, 'P5 publicada qui 05/11 às 10:00 para qui 05/11 fica fora; a de qui 05/11 18:00 para sex 06/11 conta (sem conferência)',
      (r ->> 'compromissos')::int = 8 and jsonb_array_length(r -> 'sem_conferencia') = 2
      and r -> 'sem_conferencia' @> jsonb_build_array(jsonb_build_object('dia', '2026-11-06', 'nome', 'Nelson'))
      and not (r -> 'sem_conferencia' @> jsonb_build_array(jsonb_build_object('dia', '2026-11-05', 'nome', 'Nelson'))), r::text);
    -- o fechamento: na sexta (o último dia útil) a linha ppc, uma só; na quinta não
    perform pg_temp.modos('desligado', 'desligado');
    x := pg_temp.linha(d06, 'ppc');
    v_res := pg_temp.ok(v_res, 'P6 o fechamento de sex 06/11 tem a linha ppc (55, ligada pela vigia) e só uma',
      (x ->> 'perda')::int = 55 and x ->> 'texto' = (r ->> 'linha')
      and (select count(*) from jsonb_array_elements(public.agenda_textos_do_fechamento(d06, null) -> 'linhas') y where y ->> 'tipo' = 'ppc') = 1,
      coalesce(x::text, pg_temp.fech(d06)));
    v_res := pg_temp.ok(v_res, 'P7 qui 05/11 não é o último dia útil: sem a linha ppc', pg_temp.linha(d05, 'ppc') is null, pg_temp.fech(d05));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a semana de 16 a 20/11: sex 20/11 é Consciência Negra → o último dia útil é qui 19/11
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, origem, publicada_em)
    values (c_nelson, c_mickael, date '2026-11-16', 'manha', 'publicada', 'dono', pg_temp.em(date '2026-11-13', '18:00'));
    r := public.agenda_ppc(null, date '2026-11-19');
    v_res := pg_temp.ok(v_res, 'P8 feriado na sexta (20/11): a linha sai na quinta 19/11; na quarta não; o título diz o feriado',
      (r ->> 'ultimo_dia_util')::boolean and r ->> 'linha' like 'Semana de 16 a 19/11 (sex 20 é Consciência Negra): 1 dia de serviço, nenhum conferido ainda.%'
      and pg_temp.linha(date '2026-11-19', 'ppc') is not null and pg_temp.linha(date '2026-11-18', 'ppc') is null
      and r -> 'ppc' = 'null'::jsonb, r::text);
    r := public.agenda_ppc(d30, d30);
    v_res := pg_temp.ok(v_res, 'P9 semana sem compromisso (26 a 30/10): nada a medir, sem linha (o fechamento de sex 30/10 não tem ppc)',
      (r ->> 'compromissos')::int = 0 and r -> 'linha' = 'null'::jsonb
      and r ->> 'texto' = 'Semana de 26 a 30/10: nada publicado na agenda para medir.' and pg_temp.linha(d30, 'ppc') is null, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D. A linha dia ────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(d03, '13:30');
    perform pg_temp.rodar(d03, '17:00');
    r := pg_temp.resp('ok', d03, '17:12');
    x := pg_temp.linha(d03, 'dia');
    v_res := pg_temp.igual(v_res, 'D1 ter 03/11: o Roberto confirmou e a diária lançada; o João (sem telefone) a confirmar pelo *dia feito*',
      x ->> 'texto', c_dia03 || ' O Roberto confirmou o dia todo e lancei a diária dele (R$ 180,00).' || c_joao);
    v_res := pg_temp.ok(v_res, 'D2 a linha leva a conferência (pergunta_id) e conta a ação da diária (acao_ids); perda 70',
      x ->> 'pergunta_id' = (select q.id::text from public.agenda_perguntas q where q.tipo = 'conferencia' and q.dia = d03 and q.estado = 'aberta')
      and x -> 'acao_ids' @> jsonb_build_array((select a.id from public.agenda_acoes a where a.tipo = 'diaria' and a.payee_id = c_roberto and a.executada))
      and (x ->> 'perda')::int = 70, x::text);
    -- registrado o fechamento: a diária fica contada e a frase dela não volta (a confirmação fica)
    perform public.agenda_fechamento_registrar(d03, public.agenda_textos_do_fechamento(d03, null) -> 'linhas', 'fechamento', pg_temp.em(d03, '17:31'));
    v_res := pg_temp.igual(v_res, 'D3 depois de registrado: sem "lancei" (a diária foi contada), o João ainda a confirmar',
      pg_temp.linha(d03, 'dia') ->> 'texto', c_dia03 || ' O Roberto confirmou o dia todo.' || c_joao);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(d03, '13:30');
    perform pg_temp.rodar(d03, '17:00');
    v_res := pg_temp.igual(v_res, 'D4 o Roberto ainda não respondeu ao "como foi hoje?": quando responder, eu lanço',
      pg_temp.linha(d03, 'dia') ->> 'texto',
      c_dia03 || ' O Roberto ainda não respondeu como foi; quando responder, eu lanço a diária.' || c_joao);
    perform pg_temp.modos('desligado', 'desligado');
    v_res := pg_temp.igual(v_res, 'D5 sem a equipe nem a diária: a linha dia é o texto da conferência, byte a byte (a Fase 2)',
      pg_temp.linha(d03, 'dia') ->> 'texto',
      (select q.texto from public.agenda_perguntas q where q.tipo = 'conferencia' and q.dia = d03 and q.estado = 'aberta'));
    v_res := pg_temp.igual(v_res, 'D6 e o texto da conferência é o começo de sempre com a pergunta da Fase 2',
      pg_temp.linha(d03, 'dia') ->> 'texto', c_dia03 || c_cauda);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- qui 05/11: o último dia do Vanderlei no plano (equipe e diária desligadas: só a pergunta do dono). A conferência
    -- nasce quando o último meio-dia começa: o fechamento do dono, às 16:00.
    perform pg_temp.modos('desligado', 'desligado');
    perform pg_temp.vigiar(d05, '16:30');
    v_res := pg_temp.igual(v_res, 'D7 o último dia da OS: *concluiu Vanderlei* fecha a OS (saída e cobranças da condição)',
      pg_temp.linha(d05, 'dia') ->> 'texto',
      'Agenda de hoje: Vanderlei (OS-00069) — você fecha, Roberto o dia todo. Hoje era o último dia do Vanderlei (OS-00069) no '
      || 'plano: terminou? *concluiu Vanderlei* fecha a OS (saída e cobranças da condição).' || c_cauda);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- seg 09/11: só o Roberto (de manhã) no Lenine; ele confirma e a conferência fecha: a linha dia própria
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(d09, '08:30');
    perform pg_temp.rodar(d09, '17:00');
    perform pg_temp.resp('ok', d09, '17:12');
    x := pg_temp.linha(d09, 'dia');
    v_res := pg_temp.igual(v_res, 'D8 seg 09/11, tudo confirmado pela equipe: a linha diz a diária e como corrigir',
      x ->> 'texto',
      'Agenda de hoje: Lenine (OS-00074) — Roberto. O Roberto confirmou meio dia e lancei a meia diária dele (R$ 90,00). '
      || '*diária Roberto inteira* corrige.');
    v_res := pg_temp.ok(v_res, 'D9 sem a conferência aberta: pergunta_id nulo e a ação da diária contada pela linha',
      x -> 'pergunta_id' = 'null'::jsonb and jsonb_array_length(x -> 'acao_ids') = 1
      and not exists (select 1 from public.agenda_perguntas q where q.tipo = 'conferencia' and q.dia = d09 and q.estado = 'aberta'), x::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a diária em sombra (a equipe ligada): a frase do que lançaria só no detalhe
    perform pg_temp.modos('ligado', 'sombra');
    perform pg_temp.vigiar(d03, '13:30');
    perform pg_temp.rodar(d03, '17:00');
    perform pg_temp.resp('ok', d03, '17:12');
    v_txt := pg_temp.fech(d03);
    v_res := pg_temp.ok(v_res, 'D10 diária em sombra: a linha ligada diz só a confirmação; a de sombra (detalhe) diz o que lançaria',
      pg_temp.linha(d03, 'dia') ->> 'texto' = c_dia03 || ' O Roberto confirmou o dia todo.' || c_cauda
      and pg_temp.linha(d03, 'dia', 'sombra') ->> 'texto'
          = c_dia03 || ' O Roberto confirmou o dia todo.' || c_cauda || ' Em teste: eu lançaria a diária do Roberto (R$ 180,00).'
      and not exists (select 1 from jsonb_array_elements(public.agenda_textos_do_fechamento(d03, null) -> 'linhas') y
                       where y ->> 'modo' = 'ligado' and y ->> 'texto' like '%Em teste%'), v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── X. A linha diaria (crítica) ───────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d03, '17:00');
    perform pg_temp.resp('fiquei só de manhã', d03, '17:12');
    x := pg_temp.linha(d03, 'diaria');
    v_res := pg_temp.igual(v_res, 'X1 a diária que diverge: a pergunta, as 3 opções, a recomendação e as palavras que respondem',
      x ->> 'texto',
      'Diária, preciso de você: O Roberto respondeu "fiquei só de manhã" e o plano de ter 03/11 era o dia todo no Vanderlei '
      || '(OS-00069). 1) meia diária no Vanderlei (OS-00069) (R$ 90,00), como o Roberto disse; 2) dia inteiro no Vanderlei '
      || '(OS-00069) (R$ 180,00), como estava no plano; 3) não lançar. Recomendo a 1: é o que o Roberto respondeu às 17:12. '
      || '*diária Roberto meia* · *diária Roberto inteira* · *diária Roberto não*.');
    v_res := pg_temp.ok(v_res, 'X2 perda 50, a pergunta na linha e nenhuma linha decisao repetindo a diária',
      (x ->> 'perda')::int = 50 and x ->> 'pergunta_id' = (select q.id::text from public.agenda_perguntas q where q.tipo = 'diaria' and q.estado = 'aberta')
      and not exists (select 1 from jsonb_array_elements(public.agenda_textos_do_fechamento(d03, null) -> 'linhas') y
                       where y ->> 'tipo' = 'decisao' and y ->> 'texto' like '%fiquei só de manhã%'), pg_temp.fech(d03));
    v_res := pg_temp.ok(v_res, 'X3 dois dias úteis sem resposta (qui 05/11): perda 80',
      (pg_temp.linha(d05, 'diaria') ->> 'perda')::int = 80, pg_temp.linha(d05, 'diaria')::text);
    perform pg_temp.agora(d03, '17:40');
    v_txt := pg_temp.ver('decisoes', null, d03);
    v_res := pg_temp.ok(v_res, 'X4 agenda_ver decisoes: a decisão da diária com as opções e as palavras (o modelo não escolhe)',
      v_txt like '%Decisão _: O Roberto respondeu "fiquei só de manhã"%1) meia diária no Vanderlei (OS-00069) (R$ 90,00)%'
                 || 'Recomendo a 1:%*diária Roberto não*.%'
      and v_txt like '%Eu não escolho por você.%', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'sombra');
    perform pg_temp.rodar(d03, '17:00');
    perform pg_temp.resp('fiquei só de manhã', d03, '17:12');
    v_res := pg_temp.ok(v_res, 'X5 com a diária em sombra a pergunta é de sombra: a linha só no detalhe',
      pg_temp.linha(d03, 'diaria') is null and pg_temp.linha(d03, 'diaria', 'sombra') is not null, pg_temp.fech(d03));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── C. A linha conclusao ──────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.rodar(d05, '17:00');
    perform pg_temp.resp('ok, terminei', d05, '17:12');
    perform pg_temp.rodar(d05, '17:15');
    x := pg_temp.linha(d05, 'conclusao');
    v_id := (select a.id from public.agenda_acoes a where a.tipo = 'concluir' and a.origem = 'equipe' and a.executada);
    v_res := pg_temp.igual(v_res, 'C1 o técnico disse que terminou no último dia: a conclusão, a cobrança que ela disse e o *desfaz* pelo número',
      x ->> 'texto',
      'Concluí o Vanderlei (OS-00069): o Roberto disse que terminou e era o último dia do plano. As cobranças já existiam '
      || '(sinal pago); o saldo na entrega (R$ 2.800,00) passa a vencer hoje. *desfaz OS-00069* reabre.');
    v_res := pg_temp.ok(v_res, 'C2 perda 45, a ação contada pela linha',
      (x ->> 'perda')::int = 45 and x -> 'acao_ids' = jsonb_build_array(v_id), x::text);
    v_res := pg_temp.ok(v_res, 'C3 sex 06/11 (não contada ainda): a mesma, com o dia e o vencimento de qui 05/11',
      pg_temp.linha(d06, 'conclusao') ->> 'texto' like 'Concluí o Vanderlei (OS-00069) qui 05/11: %passa a vencer qui 05/11. *desfaz OS-00069* reabre.',
      pg_temp.linha(d06, 'conclusao')::text);
    perform public.agenda_fechamento_registrar(d05, public.agenda_textos_do_fechamento(d05, null) -> 'linhas', 'fechamento', pg_temp.em(d05, '17:31'));
    v_res := pg_temp.ok(v_res, 'C4 registrado o fechamento: a conclusão não volta', pg_temp.linha(d06, 'conclusao') is null, pg_temp.fech(d06));
    -- os marcos da OS concluída (fora da carteira) pelo número
    v_txt := pg_temp.ver('marcos', null, d06, 'OS-00069');
    v_res := pg_temp.ok(v_res, 'C5 agenda_ver foco marcos com a OS concluída (fora da carteira): a conclusão qui 05/11, sem entrega',
      v_txt like 'Vanderlei (OS-00069): Entrada % · início % · conclusão qui 05/11% · entrega —.', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── F. A comissão e a ordem ────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('desligado', 'desligado');
    x := pg_temp.linha(d03, 'comissao');
    v_res := pg_temp.ok(v_res, 'F1 ter 03/11 (1º dia útil de novembro: dom 01, seg 02 Finados): a linha da comissão de outubro, perda 20',
      x ->> 'texto' = public.comissao_resumo_do_mes(null, d03) ->> 'linha'
      and x ->> 'texto' like 'Comissão de outubro (teste, nada pago): %*comissão outubro* mostra a conta.'
      and (x ->> 'perda')::int = 20, coalesce(x::text, pg_temp.fech(d03)));
    v_res := pg_temp.ok(v_res, 'F2 só no 1º dia útil: nem qua 04/11 nem seg 02/11',
      pg_temp.linha(d04, 'comissao') is null and pg_temp.linha(d02, 'comissao') is null, null);
    update public.agenda_config set modo_vigia = 'sombra' where id;
    v_res := pg_temp.ok(v_res, 'F3 vigia em sombra: a comissão e o PPC só no detalhe',
      pg_temp.linha(d03, 'comissao') is null and pg_temp.linha(d03, 'comissao', 'sombra') is not null, pg_temp.fech(d03));
    update public.agenda_config set modo_vigia = 'ligado' where id;
    v_res := pg_temp.ok(v_res, 'F4 as linhas na ordem da perda (a maior primeiro)',
      (select bool_and(a.p >= b.p)
         from (select (y ->> 'perda')::int as p, o from jsonb_array_elements(public.agenda_textos_do_fechamento(d03, null) -> 'linhas')
                 with ordinality t(y, o)) a
         join (select (y ->> 'perda')::int as p, o from jsonb_array_elements(public.agenda_textos_do_fechamento(d03, null) -> 'linhas')
                 with ordinality t(y, o)) b on b.o = a.o + 1), pg_temp.fech(d03));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── V. A agenda_ver ─────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(d03, '13:30');
    perform pg_temp.rodar(d03, '17:00');
    perform pg_temp.resp('ok', d03, '17:12');
    perform pg_temp.agora(d03, '17:40');
    v_res := pg_temp.igual(v_res, 'V1 foco diarias: o que a agenda lançou na semana, com a correção',
      pg_temp.ver('diarias', null, d03),
      'Diárias que a agenda lançou de seg 02/11 a sáb 07/11:' || E'\n'
      || '• Roberto, ter 03/11: dia inteiro no Vanderlei (OS-00069), R$ 180,00 — ele confirmou às 17:12. *diária Roberto meia* corrige.');
    v_res := pg_temp.igual(v_res, 'V2 foco equipe: o que o Roberto respondeu hoje, o próximo dia útil e quem não tem a rotina',
      pg_temp.ver('equipe', null, d03),
      'Hoje (ter 03/11) — Roberto: o "como foi hoje?": respondeu "ok" às 17:12.' || E'\n'
      || 'Amanhã (qua 04/11) — Roberto: nada mandado ainda.' || E'\n'
      || 'Sem a rotina (o dia é pelo *dia feito*): João.');
    v_res := pg_temp.igual(v_res, 'V3 foco ppc (a semana de hoje, até hoje)', pg_temp.ver('ppc', null, d03),
      public.agenda_ppc(d03, d03) ->> 'texto');
    v_res := pg_temp.ok(v_res, 'V4 foco ppc até ter 03/11: o título diz até quando',
      pg_temp.ver('ppc', null, d03) like 'Semana de 03 a 06/11 (seg 02 é Finados) até ter 03/11: %', pg_temp.ver('ppc', null, d03));
    v_txt := pg_temp.ver('marcos', null, d03, 'Vanderlei');
    v_res := pg_temp.ok(v_res, 'V5 foco marcos (pelo nome): entrada, início ter 03/11, conclusão e entrega ainda não',
      v_txt like 'Vanderlei (OS-00069): Entrada % · início ter 03/11% · conclusão — · entrega —.', v_txt);
    r := public.agenda_ver(c_admin, null, null, 'marcos', null, null, false, d03);
    v_res := pg_temp.ok(v_res, 'V6 foco marcos sem a OS: pede qual',
      not (r ->> 'ok')::boolean and r ->> 'rota' = 'marcos' and r ->> 'pergunta' like 'Diga qual OS%', r::text);
    v_txt := pg_temp.ver('comissao', 'outubro', d03);
    v_res := pg_temp.ok(v_res, 'V7 foco comissao "outubro": o resumo do mês, "nada foi pago", e a rota',
      v_txt = public.comissao_resumo_do_mes(date '2026-10-01', d03) ->> 'texto' and v_txt like 'Comissão de outubro%nada foi pago%'
      and public.agenda_ver(c_admin, 'outubro', null, 'comissao', null, null, false, d03) ->> 'rota' = 'comissao', v_txt);
    v_res := pg_temp.ok(v_res, 'V8 o mês dito: "mês passado" (outubro), "setembro", sem mês = o resumo decide (no 1º dia útil, outubro)',
      pg_temp.ver('comissao', 'mês passado', d03) = v_txt and pg_temp.ver('comissao', null, d03) = v_txt
      and pg_temp.ver('comissao', 'setembro', d03) like 'Comissão de setembro%', pg_temp.ver('comissao', 'setembro', d03));
    r := public.agenda_ver(c_admin, 'banana', null, 'comissao', null, null, false, d03);
    v_res := pg_temp.ok(v_res, 'V9 mês que não entendi: a pergunta, nunca um erro cru',
      not (r ->> 'ok')::boolean and r ->> 'rota' = 'periodo' and r ->> 'texto' like 'Não entendi o mês "banana".%', r::text);
    v_txt := pg_temp.como(c_tec, 'authenticated',
      $q$select public.agenda_ver('aa000000-0000-4000-8000-000000000002', 'outubro', null, 'comissao', null, null, false, '2026-11-03') ->> 'texto'$q$);
    v_res := pg_temp.ok(v_res, 'V10 o técnico não vê a comissão: a agenda_ver nem lê a agenda dele (P0002) e o resumo recusa (42501)',
      v_txt like 'erro P0002%'
      and pg_temp.como(c_tec, 'authenticated', $q$select public._agenda_ver_comissao('2026-10-01', '2026-11-03') ->> 'texto'$q$) like 'erro 42501%',
      v_txt);
    v_res := pg_temp.ok(v_res, 'V11 foco fora da lista lança 22023 (e a mensagem cita os focos novos)',
      (select pg_temp.como(null, 'service_role',
         $q$select public.agenda_ver(null, null, null, 'comissoes', null, null, false, '2026-11-03') ->> 'texto'$q$))
      -- FASE 4 (P6): a lista ganhou compras e fornecedores (os 17); FASE 5 (P5): e clientes (os 18); FASE 6 (P8): e aprendizado (os 19)
      like 'erro 22023: agenda_ver: foco "comissoes" não existe (%ppc, diarias, marcos, comissao, equipe, compras, fornecedores, clientes ou aprendizado)', null);
    -- em sombra e desligada
    perform pg_temp.modos('sombra', 'sombra');
    v_res := pg_temp.ok(v_res, 'V12 equipe em sombra: "Em teste (nada foi mandado à equipe)"; diária em sombra: "Em teste (nada foi lançado)" ou nada',
      pg_temp.ver('equipe', null, d03) like 'Em teste (nada foi mandado à equipe):%'
      and pg_temp.ver('diarias', null, d03) like 'Nenhuma diária que eu lançaria (em teste) pela agenda de seg 02/11 a sáb 07/11.',
      pg_temp.ver('equipe', null, d03) || ' | ' || pg_temp.ver('diarias', null, d03));
    perform pg_temp.modos('desligado', 'desligado');
    v_res := pg_temp.ok(v_res, 'V13 desligadas: a rotina e a diária dizem que estão desligadas',
      pg_temp.ver('equipe', null, d03) = 'A rotina da equipe está desligada: eu não mando nada à equipe.'
      and pg_temp.ver('diarias', null, d03) = 'A diária automática está desligada: quem lança a diária é você, como sempre.', null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.agora(d30, '17:40');
    v_txt := pg_temp.ver('livre', null, d30);
    v_res := pg_temp.ok(v_res, 'V14 foco livre em ligado: a simulação ("pela simulação", "É simulação: não muda nada.")',
      v_txt like '%Livre de verdade (pela simulação da agenda): %' and v_txt like '%É simulação: não muda nada.%', v_txt);
    v_txt := pg_temp.ver(null, 'semana', d30);
    v_res := pg_temp.ok(v_res, 'V15 a semana em ligado: a frase do livre é a da simulação', v_txt like '%Livre de verdade (pela simulação da agenda): %', v_txt);
    update public.agenda_config set modo_proposta = 'sombra' where id;
    v_txt := pg_temp.ver('livre', null, d30);
    v_res := pg_temp.ok(v_res, 'V16 foco livre em sombra: a projeção da Fase 1 (sem "pela simulação")',
      v_txt not like '%pela simulação%' and v_txt <> '', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── L. O livre de verdade não grava nada ────────────────────────────────────────────────────────────────
  begin
    v_ret := pg_temp.retrato();
    v_t0 := clock_timestamp();
    r := public.agenda_livre_de_verdade(d30, pg_temp.em(d30, '17:40'));
    v_txt := (clock_timestamp() - v_t0)::text;
    r2 := public.agenda_livre_de_verdade(d30, pg_temp.em(d30, '17:40'));
    v_res := pg_temp.ok(v_res, 'L1 nenhuma tabela agenda_* muda (contagem e md5 de cada uma, antes e depois de duas simulações)',
      pg_temp.retrato() = v_ret, null);
    v_res := pg_temp.ok(v_res, 'L2 determinística: duas vezes, a mesma resposta (md5, sem o tempo)',
      md5((r - 'ms')::text) = md5((r2 - 'ms')::text), r::text);
    v_res := pg_temp.ok(v_res, 'L3 custa menos de 2 s na bancada', clock_timestamp() - v_t0 < interval '4 seconds'
      and (r ->> 'ms')::int < 2000, v_txt || ' / ms=' || (r ->> 'ms'));
    v_res := pg_temp.ok(v_res, 'L4 a simulação: fonte, a segunda-feira do "melhor", o Nelson fora da conta (a decisão é sua) e o texto',
      r ->> 'fonte' = 'simulacao' and extract(isodow from (r ->> 'melhor')::date) = 1
      and r -> 'esperando_voce' @> '[{"numero": "OS-00112"}]'::jsonb
      and r ->> 'texto' like 'Livre de verdade (pela simulação da agenda): % Fora da conta, esperando a sua decisão: Nelson. É simulação: não muda nada.',
      r::text);
    update public.agenda_config set modo_proposta = 'sombra' where id;
    v_res := pg_temp.ok(v_res, 'L5 fora de ligado: {fonte: projecao} (quem chama usa a frase da Fase 1)',
      public.agenda_livre_de_verdade(d30, pg_temp.em(d30, '17:40')) ->> 'fonte' = 'projecao', null);
    update public.agenda_config set modo_proposta = 'ligado' where id;
    v_txt := pg_temp.como(c_tec, 'authenticated', $q$select public.agenda_livre_de_verdade('2026-10-30', '2026-10-30 17:40-03')::text$q$);
    v_res := pg_temp.ok(v_res, 'L6 o técnico não vê (42501); o service_role vê',
      v_txt like 'erro 42501%'
      and pg_temp.como(null, 'service_role', $q$select public.agenda_livre_de_verdade('2026-10-30', '2026-10-30 17:40-03') ->> 'fonte'$q$) = 'simulacao',
      v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── K. A carona ─────────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.vigiar(d04, '09:00');   -- o "chegou?" do painel do Nelson
    r := public.agenda_carona(c_admin, array['Nelson'], 'whatsapp', d04, pg_temp.em(d04, '10:00'));
    v_res := pg_temp.ok(v_res, 'K1 1 OS (o Nelson) com perguntas abertas: a crítica primeiro, "Aproveitando: …"',
      r ->> 'texto' like 'Aproveitando: Não cabe tudo até qui 05/11.%' and r ->> 'tipo' = 'nao_cabe', coalesce(r::text, 'null'));
    v_res := pg_temp.ok(v_res, 'K2 marcada: carona_em, mostrada_vezes + 1 e mostrada_via conversa',
      (select q.carona_em = pg_temp.em(d04, '10:00') and q.mostrada_via = 'conversa' and q.mostrada_vezes = 1
         from public.agenda_perguntas q where q.id = (r ->> 'pergunta_id')::uuid), null);
    v_res := pg_temp.ok(v_res, 'K3 de novo no mesmo dia, ou 6 dias depois: nada (1 por OS a cada carona_por_os_dias)',
      public.agenda_carona(c_admin, array['OS-00112'], 'whatsapp', d04, pg_temp.em(d04, '15:00')) is null
      and public.agenda_carona(c_admin, array['Nelson'], 'painel', date '2026-11-10', pg_temp.em(date '2026-11-10', '10:00')) is null, null);
    r2 := public.agenda_carona(c_admin, array['Nelson', 'OS-00112'], 'whatsapp', date '2026-11-12', pg_temp.em(date '2026-11-12', '10:00'));
    v_res := pg_temp.ok(v_res, 'K4 8 dias depois, de novo (o nome e o número da mesma OS contam como uma)', r2 is not null, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.vigiar(d04, '09:00');
    v_res := pg_temp.ok(v_res, 'K5 duas OS no turno: nada',
      public.agenda_carona(c_admin, array['Nelson', 'Vanderlei'], 'whatsapp', d04, pg_temp.em(d04, '10:00')) is null, null);
    v_res := pg_temp.ok(v_res, 'K6 outro autor (o técnico): nada; nenhuma OS: nada',
      public.agenda_carona(c_tec, array['Nelson'], 'whatsapp', d04, pg_temp.em(d04, '10:00')) is null
      and public.agenda_carona(c_admin, '{}'::text[], 'whatsapp', d04, pg_temp.em(d04, '10:00')) is null, null);
    -- a que saiu hoje no fechamento não vai de novo
    update public.agenda_perguntas set mostrada_vezes = 1, mostrada_em = pg_temp.em(d04, '08:00'), mostrada_via = 'fechamento'
     where tipo = 'nao_cabe' and estado = 'aberta';
    v_res := pg_temp.ok(v_res, 'K7 a escolhida já saiu hoje no fechamento: nada',
      public.agenda_carona(c_admin, array['Nelson'], 'whatsapp', d04, pg_temp.em(d04, '10:00')) is null, null);
    update public.agenda_config set modo_vigia = 'sombra' where id;
    v_res := pg_temp.ok(v_res, 'K8 a vigia em sombra: nada',
      public.agenda_carona(c_admin, array['Nelson'], 'whatsapp', date '2026-11-05', pg_temp.em(date '2026-11-05', '10:00')) is null, null);
    update public.agenda_config set modo_vigia = 'ligado' where id;
    r := public.agenda_carona(c_admin, array['Nelson'], 'whatsapp', date '2026-11-05', pg_temp.em(date '2026-11-05', '10:00'));
    v_res := pg_temp.ok(v_res, 'K9 no dia seguinte (a de ontem no fechamento não conta): a crítica', r ->> 'tipo' = 'nao_cabe', coalesce(r::text, 'null'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- sem a crítica (respondida), o "chegou?"
    perform pg_temp.vigiar(d04, '09:00');
    update public.agenda_perguntas set estado = 'descartada', resolvida_motivo = 'teste' where tipo = 'nao_cabe' and estado = 'aberta';
    r := public.agenda_carona(c_admin, array['OS-00112'], 'whatsapp', d04, pg_temp.em(d04, '10:00'));
    v_res := pg_temp.igual(v_res, 'K10 sem a crítica: o "chegou?" do painel', r ->> 'texto',
      'Aproveitando: Nelson (OS-00112): "Painel Touch de…" tinha previsão para ter 03/11. Chegou?');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end $acomp$;

-- ── J. Portas (rodam sempre) ────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('J1 %s: authenticated e service_role; anon não', f),
       has_function_privilege('authenticated', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute'), null
  from unnest(array[
    'public.agenda_ppc(date, date)',
    'public.agenda_livre_de_verdade(date, timestamptz)',
    'public.agenda_ver(uuid, text, text, text, text, jsonb, boolean, date)',
    'public._agenda_linhas_do_fechamento(date)',
    'public._agenda_mudancas(date, date, boolean, boolean, timestamptz)',
    'public._agenda_ver_equipe(date)',
    'public._agenda_ver_diarias(date, date, date)',
    'public._agenda_ver_comissao(date, date)',
    'public._agenda_mes_dito(text, date)',
    'public._agenda_texto_da_diaria(uuid)',
    'public._agenda_dia_da_equipe(date)']) f;

insert into _resultado
select format('J2 %s: só service_role', f),
       not has_function_privilege('authenticated', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute'), null
  from unnest(array[
    'public.agenda_carona(uuid, text[], text, date, timestamptz)',
    'public.ai_job_registrar_os(uuid, text[])']) f;

insert into _resultado
select 'J3 as duas definer novas (o livre de verdade e a carona) com search_path fixo; o PPC e a agenda_ver invoker',
       (select bool_and(p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
          from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('agenda_livre_de_verdade', 'agenda_carona', 'ai_job_registrar_os'))
       and (select bool_and(not p.prosecdef) from pg_proc p where p.pronamespace = 'public'::regnamespace
             and p.proname in ('agenda_ppc', 'agenda_ver', '_agenda_linhas_do_fechamento', '_agenda_dia_da_equipe')), null;

insert into _resultado
select 'J4 o mês dito: outubro, dezembro (o do ano passado), 10/2026, mês passado, este mês, vazio e "do mês"',
       public._agenda_mes_dito('outubro', '2026-11-03') = date '2026-10-01'
       and public._agenda_mes_dito('Dezembro', '2026-11-03') = date '2025-12-01'
       and public._agenda_mes_dito('dezembro de 2026', '2026-11-03') = date '2026-12-01'
       and public._agenda_mes_dito('10/2026', '2026-11-03') = date '2026-10-01'
       and public._agenda_mes_dito('mês passado', '2026-11-03') = date '2026-10-01'
       and public._agenda_mes_dito('do mês passado', '2026-11-03') = date '2026-10-01'
       and public._agenda_mes_dito('este mês', '2026-11-03') = date '2026-11-01'
       and public._agenda_mes_dito('', '2026-11-03') is null
       and public._agenda_mes_dito('do mês', '2026-11-03') is null
       and public._agenda_mes_dito('de outubro', '2026-11-03') = date '2026-10-01', null;

select teste, ok, detalhe from _resultado order by teste;

rollback;
