-- Prova da correção de 30/10 da Agenda de Produção: quem é da equipe (migration 20261030100600).
-- bancada: depende de 20261030100600
--
-- O defeito (produção, 30/10): o dono tirou Roberto, João e Mickael e declarou o Alex "todo dia útil, manhã e tarde" (o
-- Alex é prestador, sem work_profiles). agenda_capacidade, agenda_capacidade_semanal e agenda_resolver_pessoa exigiam a
-- diária cadastrada (work_profiles) para alguém ser da equipe: a equipe ficou vazia, o motor não marcava nada, "o Alex não
-- vem amanhã" dava "Não conheço ninguém chamado Alex", e a pergunta equipe_sem_dias pedia "o valor da diária".
-- A regra nova: é da equipe quem está ativo (prestador, diarista ou funcionário) com a diária cadastrada vigente OU uma
-- linha vigente que o dono declarou (agenda_disponibilidade, origem dono); no resolver, também quem está na lista da rotina
-- sem ter parado (agenda_equipe_contato, parou_em nulo).
--
-- O cenário de HOJE é a fixture-2310.sql que a bancada sempre carrega, com os modos ligados, a vigia de qui 29/10 às 16:30
-- (a reserva do Lenine com Roberto e João) e a troca de produção de sex 30/10 às 00:11 (os três saem; o Alex entra pelo
-- dono, na lista da rotina pelo dono) — o mesmo cenário da seção E de agenda_correcao_2910_revisao.sql:
--   E  o Alex entra na agenda_capacidade (1 meio-dia por turno de seg a sex; sábado e domingo fora) e na capacidade semanal
--      (5 diárias, 4 comprometíveis); o resolver acha "Alex", "alex" e "o Alex"; Roberto, João e Mickael (a diária
--      cadastrada, sem disponibilidade em vigor) continuam fora da capacidade; quem só tem dias do histórico ou do
--      assistente, sem a diária, continua fora (da capacidade, da semanal e do resolver); quem não é da equipe pelo tipo
--      (comissionado) também; quem está na lista da rotina sem dias é achado pelo resolver (e não entra na capacidade), quem
--      parou não; a vigia de 00:15 não pergunta da equipe sem dias ("a equipe tem dias"); quando ninguém conta (o Alex com
--      dias só do assistente), a pergunta nasce com o texto novo, sem pedir a diária, no singular e no plural; e resolve
--      quando o dono declara os dias
--   N  o que NÃO muda: fora da regra nova (todos da fixture têm a diária cadastrada), as 3 leituras dão o mesmo que as
--      definições de antes (rodadas como pg_temp), byte a byte, na fixture-2310, na fixture-fase3 e na fixture-fase6, em
--      vários dias; o passo da vigia sem ninguém de fora dá o mesmo que antes (o mesmo retorno e o mesmo texto)
-- Sempre (com ou sem as fixtures):
--   K  as cópias: as 4 recriadas só mudam nos blocos "-- CORREÇÃO 30/10 (equipe):" (as linhas trocadas voltam do
--      "-- antes:"); _agenda_equipe_tem_dias não muda (só o comentário)
--   P  portas: as 3 leituras como antes (sem anon; authenticated e service_role; invoker, STABLE, search_path fixo); o passo
--      da vigia, ninguém de fora
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_correcao_2910_equipe.sql
--   Sem as fixtures (produção) os cenários saem PULADO e só K e P rodam. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia, modo_leitura = 'ligado' where id
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, pg_temp.em(p_dia, p_hora))
$f$;
-- A troca de produção de sex 30/10 às 00:11: Roberto, João e Mickael saem da agenda (as linhas deles ficam substituídas; o
-- cadastro de diarista continua), o Alex entra com os dias que p_origem diz (o dono, em produção) e na lista da rotina.
create function pg_temp.troca_de_producao(p_origem text) returns void language plpgsql as $f$
begin
  update public.agenda_disponibilidade set substituida_em = pg_temp.em(date '2026-10-30', '00:11')
   where substituida_em is null and payee_id in ('bb000000-0000-4000-8000-000000000002', 'bb000000-0000-4000-8000-000000000003',
                                                 'bb000000-0000-4000-8000-000000000004');
  insert into public.payees (id, name, kind, active) values ('bb000000-0000-4000-8000-0000000000a1', 'Alex Gonçalves Machado', 'prestador', true);
  insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_em)
  values ('bb000000-0000-4000-8000-0000000000a1', '{1,2,3,4,5}', null, 'disponivel', p_origem,
          case p_origem when 'dono' then 'você disse em 29/10' else 'anotado pelo assistente' end,
          case p_origem when 'dono' then 'dono 29/10: Alex todo dia útil, manhã e tarde' end,
          pg_temp.em(date '2026-10-30', '00:11'));
  insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
  values ('bb000000-0000-4000-8000-0000000000a1', true, 'dono', pg_temp.em(date '2026-10-30', '00:11'));
end $f$;
-- A grade de uma pessoa: "dd/mm turno situação meios", na ordem.
create function pg_temp.grade(p_pessoa uuid, p_de date, p_ate date, p_hoje date) returns text language sql stable as $f$
  select coalesce(string_agg(format('%s %s %s %s', to_char(g.dia, 'DD/MM'), g.turno, g.situacao, g.meios_esperados), ', '
                             order by g.dia, g.turno), '(fora)')
    from public.agenda_capacidade(p_de, p_ate, p_hoje) g where g.payee_id = p_pessoa
$f$;

-- O corpo de uma função numa migration (entre o "as $function$" e o fecho) e a definição inteira.
create function pg_temp.corpo(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
  v_i int := position('create or replace function public.' || p_nome || '(' in v);
  v_tag text;
begin
  if v_i = 0 then return null; end if;
  v := substr(v, v_i);
  v_tag := substring(v from E'\nas (\\$[a-z_]*\\$)\n');
  v := substr(v, position(E'\nas ' || v_tag in v) + length(E'\nas ' || v_tag));
  return left(v, position(v_tag in v) - 1);
end $f$;
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;
-- As linhas fora dos blocos "-- CORREÇÃO 30/10 (equipe): … fim"; as linhas que um bloco trocou ("-- antes: <a linha>")
-- voltam, com o recuo do bloco mais o que vem depois do "-- antes: ".
create function pg_temp.sem_equipe(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and l ~ '^\s*-- CORREÇÃO 30/10 \(equipe\):' and l !~ '^\s*-- CORREÇÃO 30/10 \(equipe\): fim' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro then
      if l ~ '^\s*-- CORREÇÃO 30/10 \(equipe\): fim' then
        v_dentro := false;
      elsif l ~ '^\s*-- antes: ' then
        v_fora := v_fora || regexp_replace(l, '^(\s*)-- antes: ', '\1');
      end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;

-- As definições de ANTES rodadas como pg_temp (a régua do que não muda): as 3 leituras da Fase 1 (20261024160400) e o passo
-- da vigia da revisão do lote (20261030100500).
do $antes$
declare
  v_f1  text := coalesce(current_setting('agenda_teste.mig_prontidao_fase1', true), '');
  v_rev text := coalesce(current_setting('agenda_teste.mig_correcao_revisao', true), '');
begin
  if v_f1 = '' or v_rev = '' then return; end if;
  execute replace(pg_temp.inteira(v_f1, 'agenda_capacidade'),
                  'create or replace function public.agenda_capacidade(', 'create function pg_temp.capacidade_antes(');
  execute replace(pg_temp.inteira(v_f1, 'agenda_capacidade_semanal'),
                  'create or replace function public.agenda_capacidade_semanal(', 'create function pg_temp.semanal_antes(');
  execute replace(pg_temp.inteira(v_f1, 'agenda_resolver_pessoa'),
                  'create or replace function public.agenda_resolver_pessoa(', 'create function pg_temp.resolver_antes(');
  execute replace(pg_temp.inteira(v_rev, '_agenda_vigia_equipe_sem_dias'),
                  'create or replace function public._agenda_vigia_equipe_sem_dias(', 'create function pg_temp.sem_dias_antes(');
end
$antes$;

-- ── E. O cenário de produção de 30/10 (fixture-2310) ────────────────────────────────────────────────────────
do $hoje$
declare
  v_fix   boolean := exists (select 1 from public.service_orders where id = '05000000-0000-4000-8000-000000000074')
                     and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002');
  c_qui   constant date := date '2026-10-29';
  c_sex   constant date := date '2026-10-30';
  c_seg   constant date := date '2026-11-02';
  c_alex  constant uuid := 'bb000000-0000-4000-8000-0000000000a1';
  c_rob   constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao  constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_mick  constant uuid := 'bb000000-0000-4000-8000-000000000004';
  c_pedro constant uuid := 'bb000000-0000-4000-8000-0000000000a2';
  c_paulo constant uuid := 'bb000000-0000-4000-8000-0000000000a3';
  c_caio  constant uuid := 'bb000000-0000-4000-8000-0000000000a4';
  c_bruno constant uuid := 'bb000000-0000-4000-8000-0000000000a5';
  c_davi  constant uuid := 'bb000000-0000-4000-8000-0000000000a6';
  c_semana_alex constant text := '09/11 manha livre 1, 09/11 tarde livre 1, 10/11 manha livre 1, 10/11 tarde livre 1, '
    || '11/11 manha livre 1, 11/11 tarde livre 1, 12/11 manha livre 1, 12/11 tarde livre 1, 13/11 manha livre 1, '
    || '13/11 tarde livre 1, 14/11 manha fim_de_semana 0, 14/11 tarde fim_de_semana 0, 15/11 manha fim_de_semana 0, '
    || '15/11 tarde fim_de_semana 0';
  c_equipe constant text := 'Não consigo marcar nenhum dos 11 serviços que esperam: ninguém da equipe tem dias na agenda. '
    || 'Alex tem dias na agenda, mas não está na equipe. Se for, me diga em que dias vem. Por exemplo: "Alex vem de segunda a sexta".';
  c_equipe2 constant text := 'Não consigo marcar nenhum dos 11 serviços que esperam: ninguém da equipe tem dias na agenda. '
    || 'Alex e Pedro têm dias na agenda, mas não estão na equipe. Se forem, me diga em que dias cada um vem. Por exemplo: "Alex vem de segunda a sexta".';
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  v_t     text;
  q       public.agenda_perguntas;
begin
  if not v_fix then
    insert into _resultado values ('E0 o cenário de produção de 30/10 (fixture-2310)', true, 'PULADO: sem a fixture-2310 (rode pela bancada)');
    return;
  end if;

  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(c_qui, '16:30');
    perform pg_temp.troca_de_producao('dono');
    -- quem não é da equipe pela regra nova: dias só do histórico (a semente) ou do assistente, sem a diária; um comissionado
    -- com uma linha do dono; quem está na lista da rotina sem dias (Bruno) e quem parou (Davi)
    insert into public.payees (id, name, kind, active) values
      (c_pedro, 'Pedro Teste', 'prestador', true), (c_paulo, 'Paulo Teste', 'diarista', true),
      (c_caio, 'Caio Teste', 'comissionado', true), (c_bruno, 'Bruno Teste', 'prestador', true),
      (c_davi, 'Davi Teste', 'prestador', true);
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, frequencia, nota) values
      (c_pedro, '{1,2,3,4,5}', null, 'disponivel', 'agente', null, 'anotado pelo assistente'),
      (c_paulo, '{1,2,3,4,5}', null, 'disponivel', 'historico', 0.8, 'semente'),
      (c_caio, '{1,2,3,4,5}', null, 'disponivel', 'dono', null, 'você disse');
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por) values (c_bruno, true, 'dono');
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, parou_em, parou_motivo)
    values (c_davi, false, 'dono', pg_temp.em(c_qui, '10:00'), 'saiu');

    v_res := pg_temp.igual(v_res, 'E1 o Alex (declarado pelo dono, sem a diária cadastrada) entra na agenda_capacidade: 1 meio-dia por turno de seg 09 a sex 13/11, sábado e domingo fora',
      pg_temp.grade(c_alex, date '2026-11-09', date '2026-11-15', c_sex), c_semana_alex);
    r := public.agenda_capacidade_semanal(c_sex);
    v_res := pg_temp.ok(v_res, 'E2 e na capacidade semanal: só ele, 5 diárias, 4 comprometíveis (o dono sem padrão não conta)',
      r -> 'pessoas' = jsonb_build_array(jsonb_build_object('payee_id', c_alex, 'nome', 'Alex', 'eh_dono', false, 'diarias_semana', 5.00))
      and (r ->> 'diarias_semana')::numeric = 5 and (r ->> 'comprometivel')::numeric = 4 and not (r ->> 'conta_dono')::boolean,
      (r - 'ultima_diaria' - 'dias_sem_lancar' - 'aviso')::text);
    v_res := pg_temp.igual(v_res, 'E3 o resolver acha "Alex", "alex" e "o Alex" (antes: "Não conheço ninguém chamado Alex na equipe.")',
      (select string_agg(coalesce(public.agenda_resolver_pessoa(x, null, c_sex) ->> 'status', '-') || ':'
                         || coalesce(public.agenda_resolver_pessoa(x, null, c_sex) ->> 'payee_id', '-') || ':'
                         || coalesce(public.agenda_resolver_pessoa(x, null, c_sex) ->> 'texto', '-'), ' | ' order by o)
         from unnest(array['Alex', 'alex', 'o Alex']) with ordinality u(x, o)),
      'ok:' || c_alex || ':Alex | ok:' || c_alex || ':Alex | ok:' || c_alex || ':Alex');
    v_res := pg_temp.ok(v_res, 'E4 Roberto, João e Mickael (a diária cadastrada, sem disponibilidade em vigor) continuam fora da capacidade e da semanal; o resolver ainda os acha (pela diária, como antes)',
      not exists (select 1 from public.agenda_capacidade(c_sex, c_sex + 42, c_sex) g where g.payee_id in (c_rob, c_joao, c_mick))
      and not exists (select 1 from jsonb_array_elements(r -> 'pessoas') e where (e ->> 'payee_id')::uuid in (c_rob, c_joao, c_mick))
      and public.agenda_resolver_pessoa('Roberto', null, c_sex) ->> 'status' = 'ok'
      and public.agenda_resolver_pessoa('Mickael', null, c_sex) ->> 'status' = 'ok', null);
    v_res := pg_temp.ok(v_res, 'E5 quem só tem dias do assistente (Pedro) ou do histórico (Paulo), sem a diária, continua fora: da capacidade, da semanal e do resolver',
      not exists (select 1 from public.agenda_capacidade(c_sex, c_sex + 42, c_sex) g where g.payee_id in (c_pedro, c_paulo))
      and not exists (select 1 from jsonb_array_elements(r -> 'pessoas') e where (e ->> 'payee_id')::uuid in (c_pedro, c_paulo))
      and public.agenda_resolver_pessoa('Pedro', null, c_sex) ->> 'texto' = 'Não conheço ninguém chamado Pedro na equipe.'
      and public.agenda_resolver_pessoa('Paulo', null, c_sex) ->> 'status' = 'nao_achei', null);
    v_res := pg_temp.ok(v_res, 'E6 quem não é da equipe pelo tipo (comissionado), mesmo com uma linha do dono, continua fora',
      not exists (select 1 from public.agenda_capacidade(c_sex, c_sex + 42, c_sex) g where g.payee_id = c_caio)
      and not exists (select 1 from jsonb_array_elements(r -> 'pessoas') e where (e ->> 'payee_id')::uuid = c_caio)
      and public.agenda_resolver_pessoa('Caio', null, c_sex) ->> 'status' = 'nao_achei', null);
    v_res := pg_temp.ok(v_res, 'E7 a lista da rotina: o resolver acha quem está nela sem ter parado (Bruno, sem dias nem diária), que não entra na capacidade; quem parou (Davi), não',
      public.agenda_resolver_pessoa('Bruno', null, c_sex) ->> 'payee_id' = c_bruno::text
      and not exists (select 1 from public.agenda_capacidade(c_sex, c_sex + 42, c_sex) g where g.payee_id = c_bruno)
      and public.agenda_resolver_pessoa('Davi', null, c_sex) ->> 'status' = 'nao_achei', null);
    r := pg_temp.vigiar(c_sex, '00:15');
    v_res := pg_temp.ok(v_res, 'E8 a vigia de 00:15 não pergunta da equipe sem dias: o Alex conta ("a equipe tem dias")',
      r #>> '{contagens,equipe_sem_dias,motivo}' = 'a equipe tem dias'
      and not exists (select 1 from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias'), (r -> 'contagens' -> 'equipe_sem_dias')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- quando ninguém conta: o Alex com os dias só anotados pelo assistente (não declarados pelo dono) e sem a diária
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(c_qui, '16:30');
    perform pg_temp.troca_de_producao('agente');
    r := pg_temp.vigiar(c_sex, '00:15');
    select x.* into q from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias';
    v_res := pg_temp.ok(v_res, 'E9 ninguém conta (o Alex só com dias do assistente): a pergunta nasce uma vez na semana, com o Alex pelo nome',
      r -> 'contagens' -> 'equipe_sem_dias' = '{"criada": true, "motivo": "ninguém da equipe tem dias", "servicos": 11, "sem_diaria": ["Alex"]}'::jsonb
      and q.chave = 'equipe_sem_dias:2026-10-26' and q.modo = 'ligado' and q.estado = 'aberta',
      (r -> 'contagens' -> 'equipe_sem_dias')::text);
    v_res := pg_temp.igual(v_res, 'E10 o texto pergunta os dias, não a diária', q.texto, c_equipe);
    v_res := pg_temp.ok(v_res, 'E11 nenhuma palavra sobre diária ou cadastro', q.texto not like '%diária%' and q.texto not like '%cadastr%', q.texto);
    -- o dono responde "o Alex vem de segunda a sexta": a linha do dono
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_em)
    values (c_alex, '{1,2,3,4,5}', null, 'disponivel', 'dono', 'você disse em 30/10', 'o Alex vem de segunda a sexta',
            pg_temp.em(c_sex, '08:00'));
    r := pg_temp.vigiar(c_sex, '08:15');
    v_res := pg_temp.ok(v_res, 'E12 o dono declara os dias do Alex: a pergunta resolve ("alguém da equipe voltou a ter dias na agenda")',
      (select x.estado || ' | ' || x.resolvida_motivo from public.agenda_perguntas x where x.id = q.id)
        = 'resolvida | alguém da equipe voltou a ter dias na agenda'
      and r #>> '{contagens,equipe_sem_dias,motivo}' in ('a equipe tem dias', 'já perguntei nesta semana'),
      (r -> 'contagens' -> 'equipe_sem_dias')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.modos('ligado', 'ligado');
    perform pg_temp.vigiar(c_qui, '16:30');
    perform pg_temp.troca_de_producao('agente');
    insert into public.payees (id, name, kind, active) values (c_pedro, 'Pedro Teste', 'prestador', true);
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota)
    values (c_pedro, '{2,4}', null, 'disponivel', 'agente', 'anotado pelo assistente');
    r := pg_temp.vigiar(c_sex, '00:15');
    v_res := pg_temp.igual(v_res, 'E13 dois de fora: o plural ("Alex e Pedro têm dias na agenda, mas não estão na equipe. Se forem, …")',
      (select x.texto from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias'), c_equipe2);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$hoje$;

-- ── N. O que não muda: as definições de antes, byte a byte, nas fixtures da bancada ─────────────────────────────
do $nada$
declare
  v_ok    boolean := to_regprocedure('pg_temp.capacidade_antes(date, date, date)') is not null
                     and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002');
  v_res   jsonb := '[]'::jsonb;
  v_fx    text;
  v_dia   date;
  v_dif   text[];
  v_n     int;
  a       text;
  b       text;
  r1      jsonb;
  r2      jsonb;
  t1      text;
  t2      text;
begin
  if not v_ok then
    insert into _resultado values ('N0 o que não muda (fixtures da bancada)', true, 'PULADO: sem as fixtures nem as migrations de antes (rode pela bancada)');
    return;
  end if;
  foreach v_fx in array array['2310', 'fase3', 'fase6'] loop
    begin
      if v_fx <> '2310' then
        if coalesce(current_setting('agenda_teste.' || v_fx, true), '') = '' then
          v_res := pg_temp.ok(v_res, format('N1 fixture-%s: as 3 leituras são as de antes', v_fx), false, 'sem agenda_teste.' || v_fx);
          raise exception 'desfaz' using errcode = 'P0099';
        end if;
        execute current_setting('agenda_teste.' || v_fx);
      end if;
      v_dif := '{}';
      v_n := 0;
      foreach v_dia in array array[date '2026-10-23', date '2026-10-29', date '2026-10-30', date '2026-11-03', date '2026-11-10'] loop
        select string_agg(g::text, '|' order by g.eh_dono desc, g.pessoa, g.payee_id, g.dia, g.turno) into a
          from public.agenda_capacidade(v_dia - 7, v_dia + 28, v_dia) g;
        select string_agg(g::text, '|' order by g.eh_dono desc, g.pessoa, g.payee_id, g.dia, g.turno) into b
          from pg_temp.capacidade_antes(v_dia - 7, v_dia + 28, v_dia) g;
        v_n := v_n + coalesce(length(a), 0);
        if a is distinct from b then v_dif := v_dif || ('capacidade ' || v_dia); end if;
        if public.agenda_capacidade_semanal(v_dia) is distinct from pg_temp.semanal_antes(v_dia) then
          v_dif := v_dif || ('semanal ' || v_dia);
        end if;
        select string_agg(public.agenda_resolver_pessoa(x, 'aa000000-0000-4000-8000-000000000001', v_dia)::text, '|' order by o) into a
          from unnest(array['eu', 'Roberto', 'Rob', 'João', 'joao', 'Mickael', 'Gustavo', 'Pedro', 'o João', '']) with ordinality u(x, o);
        select string_agg(pg_temp.resolver_antes(x, 'aa000000-0000-4000-8000-000000000001', v_dia)::text, '|' order by o) into b
          from unnest(array['eu', 'Roberto', 'Rob', 'João', 'joao', 'Mickael', 'Gustavo', 'Pedro', 'o João', '']) with ordinality u(x, o);
        if a is distinct from b then v_dif := v_dif || ('resolver ' || v_dia); end if;
      end loop;
      v_res := pg_temp.ok(v_res, format('N1 fixture-%s: a grade, a semanal e o resolver são os de antes, byte a byte (5 dias; a grade não vazia)', v_fx),
        cardinality(v_dif) = 0 and v_n > 0, array_to_string(v_dif, ', '));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;

  -- o passo da vigia sem ninguém de fora: a equipe sai e ninguém entra ("Quem vem e em que dias da semana?"), e com a equipe
  -- da fixture ("a equipe tem dias")
  foreach t1 in array array['sem ninguém', 'com a equipe'] loop
    begin
      perform pg_temp.modos('ligado', 'ligado');
      if t1 = 'sem ninguém' then
        update public.agenda_disponibilidade set substituida_em = pg_temp.em(date '2026-10-30', '00:11') where substituida_em is null;
      end if;
      begin
        r1 := public._agenda_vigia_equipe_sem_dias(date '2026-10-30', pg_temp.em(date '2026-10-30', '00:15'));
        a := (select string_agg(x.chave || ' ' || x.texto, '|') from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias');
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      r2 := pg_temp.sem_dias_antes(date '2026-10-30', pg_temp.em(date '2026-10-30', '00:15'));
      b := (select string_agg(x.chave || ' ' || x.texto, '|') from public.agenda_perguntas x where x.tipo = 'equipe_sem_dias');
      v_res := pg_temp.ok(v_res, format('N2 o passo da vigia %s: o retorno e o texto de antes', t1),
        r1 = r2 and a is not distinct from b
        and (t1 <> 'sem ninguém' or a like '%Quem vem e em que dias da semana?')
        and (t1 <> 'com a equipe' or r1 ->> 'motivo' = 'a equipe tem dias'),
        r1::text || ' × ' || r2::text || ' | ' || coalesce(a, '-'));
      raise exception 'desfaz' using errcode = 'P0099';
    exception when sqlstate 'P0099' then null;
    end;
  end loop;
  perform pg_temp.gravar(v_res);
end
$nada$;

-- ── K. As cópias (sempre que as migrations de origem vierem como texto) ─────────────────────────────────────────
do $copia$
declare
  f record;
  v_fonte text;
  v_novo text;
  v_mig text;
begin
  for f in select * from (values
      ('agenda_capacidade', 'public.agenda_capacidade(date, date, date)', 'mig_prontidao_fase1', '20261024160400', 1),
      ('agenda_capacidade_semanal', 'public.agenda_capacidade_semanal(date)', 'mig_prontidao_fase1', '20261024160400', 1),
      ('agenda_resolver_pessoa', 'public.agenda_resolver_pessoa(text, uuid, date)', 'mig_prontidao_fase1', '20261024160400', 2),
      ('_agenda_vigia_equipe_sem_dias', 'public._agenda_vigia_equipe_sem_dias(date, timestamptz)', 'mig_correcao_revisao', '20261030100500', 4))
      as x(nome, sig, mig, versao, blocos) loop
    v_mig := coalesce(current_setting('agenda_teste.' || f.mig, true), '');
    if v_mig = '' then
      insert into _resultado values (format('K1 %s: a cópia', f.nome), true,
        format('PULADO: sem agenda_teste.%s (rode pela bancada)', f.mig));
      continue;
    end if;
    v_fonte := pg_temp.corpo(v_mig, f.nome);
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = f.sig::regprocedure;
    insert into _resultado values (
      format('K1 %s: sem os blocos "-- CORREÇÃO 30/10 (equipe):" (e com as linhas trocadas de volta), é o corpo de %s (com %s blocos)',
             f.nome, f.versao, f.blocos),
      v_fonte is not null and pg_temp.sem_equipe(v_novo) = v_fonte
      and (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 30/10 \(equipe\): fim', 'g')) = f.blocos,
      format('fonte %s × novo sem blocos %s caracteres; blocos %s', length(v_fonte), length(pg_temp.sem_equipe(v_novo)),
             (select count(*) from regexp_matches(v_novo, '-- CORREÇÃO 30/10 \(equipe\): fim', 'g'))));
  end loop;
  v_mig := coalesce(current_setting('agenda_teste.mig_correcao_revisao', true), '');
  if v_mig = '' then
    insert into _resultado values ('K2 _agenda_equipe_tem_dias: o corpo', true, 'PULADO: sem agenda_teste.mig_correcao_revisao (rode pela bancada)');
  else
    insert into _resultado
    select 'K2 _agenda_equipe_tem_dias: o corpo é o de 20261030100500 (não muda); o comentário novo diz a régua nova',
           replace(p.prosrc, E'\r\n', E'\n') = pg_temp.corpo(v_mig, '_agenda_equipe_tem_dias')
           and obj_description(p.oid, 'pg_proc') like '%CORREÇÃO 30/10 (equipe)%'
           and obj_description(p.oid, 'pg_proc') not like '%(agenda_capacidade: a diária cadastrada vigente e os dias na agenda)%',
           obj_description(p.oid, 'pg_proc')
      from pg_proc p where p.oid = 'public._agenda_equipe_tem_dias(date)'::regprocedure;
  end if;
end
$copia$;

-- ── P. Portas (sempre) ───────────────────────────────────────────────────────────────────────────────────────
with f(sig) as (values ('public.agenda_capacidade(date, date, date)'), ('public.agenda_capacidade_semanal(date)'),
                       ('public.agenda_resolver_pessoa(text, uuid, date)'))
insert into _resultado
select 'P1 as 3 leituras como antes: sem anon; authenticated e service_role executam; invoker, STABLE, search_path fixo',
       bool_and(not has_function_privilege('anon', f.sig, 'execute') and has_function_privilege('authenticated', f.sig, 'execute')
                and has_function_privilege('service_role', f.sig, 'execute') and not p.prosecdef and p.provolatile = 's'
                and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%') and count(*) = 3,
       string_agg(f.sig, ', ') filter (where has_function_privilege('anon', f.sig, 'execute'))
  from f join pg_proc p on p.oid = f.sig::regprocedure;
insert into _resultado
select 'P2 o passo da vigia continua peça de dentro: ninguém de fora (nem anon, nem authenticated, nem service_role); invoker, search_path fixo',
       not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute') and not p.prosecdef
       and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%', null
  from pg_proc p where p.oid = 'public._agenda_vigia_equipe_sem_dias(date, timestamptz)'::regprocedure;

select teste, ok, detalhe from _resultado order by teste;

rollback;
