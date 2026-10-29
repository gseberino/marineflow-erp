-- Prova da correção de 29/10 da Agenda de Produção, pacote P1 (migration 20261030100000): o que o dono VÊ quando pergunta.
-- bancada: depende de 20261030100000
--
-- O defeito (auditoria de 29/10): às 17:03 de qui 29/10 *agenda* respondeu "Esta semana (seg 26/10 a sáb 31/10) não tem nada
-- marcado…" e "Quer que eu pergunte o que falta para montar a semana que vem?" com a semana que vem já publicada às 16:30 (a
-- reserva do Lenine em 05, 06 e 10/11); *agenda plano* não dizia quem vai na reserva e cortava o bloco no sábado.
--
-- Sobre a carteira de qui 29/10 (scripts/bancada-agenda/fixture-fase2.sql) publicada pela vigia às 16:30 com os dois modos
-- ligados — Vanderlei ter 03 a qui 05/11, Rodrigo (OS-00096) ter 03/11 à tarde, Lenine qua 04 a seg 09/11, a reserva acima da
-- carga do Flávio qua 04 e sex 06/11 — e sobre o cenário à mão do motor (cenario-motor.sql: Antônio ter 03 e qua 04/11,
-- Beatriz qui 05/11 e a reserva do Caio condicionada à compra do cabo, qui 05 a ter 10/11, como a do Lenine em produção):
--   A  *agenda* (a semana desta) de quinta a sábado e no domingo: o resto desta semana e a semana que vem montada, com o bloco
--      inteiro (o dia depois do sábado também), dentro do teto; a oferta diz o que já tem; os dados
--   B  *agenda semana que vem*: o bloco inteiro e quem vai (no teto, sai primeiro o com quem, depois o nome, e a linha diz
--      onde está tudo); a oferta
--   C  *agenda plano*: a reserva diz quem vai e "reservado, se …" (depois "(mesma condição)"; acima da carga), e o bloco que
--      passa do fim do período aparece inteiro ("(continua)")
--   N  o que NÃO muda: sem plano na semana que vem e com o que fazer nesta (a semana e a oferta de antes, byte a byte pela
--      definição de antes rodada como pg_temp); fora de ligado (sombra: byte a byte); o *livre* (o resumo e o livre de
--      agenda_semana, byte a byte); sem nada publicado, a oferta de sempre; as linhas do dia da manhã e do fechamento
--   D  determinismo (md5 2×)
-- Sempre (com ou sem as fixtures):
--   K  as cópias: as 3 recriadas só acrescentam os blocos "-- CORREÇÃO 29/10 (P1):" (× a migration de onde cada uma foi
--      copiada; com as migrations como texto)
--   P  portas: anon não executa as 2 novas nem as 3 recriadas; authenticated e service_role executam; invoker e STABLE
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_correcao_2910_p1.sql
--   Sem as fixtures (produção) os cenários saem PULADO e só P roda. Os cenários mexem em linhas só dentro de subtransações
--   desfeitas na hora; termina em ROLLBACK: nada fica gravado e nenhuma mensagem sai.
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
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, (p_dia + p_hora::time) at time zone 'America/Sao_Paulo')
$f$;
create function pg_temp.agora(p_dia date, p_hora text) returns void language sql as $f$
  select set_config('agenda.agora', ((p_dia + p_hora::time) at time zone 'America/Sao_Paulo')::text, true)
$f$;
-- A agenda_ver do dono pelo WhatsApp (service_role, sem login), como a palavra a chama (executar.ts → paraAgendaVer).
create function pg_temp.ver(p_foco text, p_periodo text, p_hoje date) returns text language sql as $f$
  select public.agenda_ver(null, p_periodo, null, p_foco, null, null, false, p_hoje) ->> 'texto'
$f$;
-- O tamanho do texto de agenda_semana: o teto texto_max vale aqui. (A agenda_ver troca depois a linha do livre pela da
-- simulação, que pode ser mais longa; isso é da Fase 3 e não muda nesta correção.)
create function pg_temp.tam(p_de date, p_ate date, p_hoje date) returns int language sql as $f$
  select char_length(public.agenda_semana(p_de, p_ate, p_hoje) ->> 'texto')
$f$;
-- A linha n (1…) de um texto.
create function pg_temp.linha(p_t text, p_n int) returns text language sql immutable as $f$
  select (string_to_array(p_t, E'\n'))[p_n]
$f$;
-- A última linha de um texto.
create function pg_temp.ultima(p_t text) returns text language sql immutable as $f$
  select (string_to_array(p_t, E'\n'))[cardinality(string_to_array(p_t, E'\n'))]
$f$;
-- A carteira de 29/10 publicada pela vigia às 16:30 (p_proposta, p_vigia = os modos) e o cenário do motor.
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

-- O corpo (entre as duas marcas $…$) e a função inteira (do "create or replace" ao fecho) de p_nome na migration p_mig.
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
-- As linhas fora dos blocos "-- CORREÇÃO 29/10 (P1): … -- CORREÇÃO 29/10 (P1): fim".
create function pg_temp.sem_blocos(p text) returns text language plpgsql immutable as $f$
declare
  v_fora text[] := '{}';
  v_dentro boolean := false;
  l text;
begin
  foreach l in array string_to_array(replace(p, E'\r\n', E'\n'), E'\n') loop
    if not v_dentro and ltrim(l) like '-- CORREÇÃO 29/10 (P1):%' and ltrim(l) not like '-- CORREÇÃO 29/10 (P1): fim%' then
      v_dentro := true;
      continue;
    end if;
    if v_dentro then
      if ltrim(l) like '-- CORREÇÃO 29/10 (P1): fim%' then v_dentro := false; end if;
      continue;
    end if;
    v_fora := v_fora || l;
  end loop;
  return array_to_string(v_fora, E'\n');
end $f$;

-- A definição de ANTES de _agenda_semana_de e de agenda_semana (20261024160500), rodada como pg_temp: a régua do que não muda.
do $antes$
declare
  v_mig text := coalesce(current_setting('agenda_teste.mig_leituras_fase1', true), '');
begin
  if v_mig = '' then return; end if;
  execute replace(pg_temp.inteira(v_mig, '_agenda_semana_de'), 'create or replace function public._agenda_semana_de(',
                  'create function pg_temp.semana_de_antes(');
  execute replace(replace(pg_temp.inteira(v_mig, 'agenda_semana'), 'create or replace function public.agenda_semana(',
                          'create function pg_temp.agenda_semana_antes('),
                  'public._agenda_semana_de(', 'pg_temp.semana_de_antes(');
end
$antes$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $cenarios$
declare
  v_fix   boolean := coalesce(current_setting('agenda_teste.fase2', true), '') <> ''
                     and coalesce(current_setting('agenda_teste.cenario_motor', true), '') <> ''
                     and coalesce(current_setting('agenda_teste.mig_leituras_fase1', true), '') <> ''
                     and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002');
  c_hoje  constant date := date '2026-10-29';
  c_aviso constant text := 'nenhuma diária foi lançada depois de sáb 17/10: não sei o que a equipe fez de seg 19/10 até hoje';
  c_aviso_m constant text := 'Nenhuma diária foi lançada depois de sáb 17/10: não sei o que a equipe fez de seg 19/10 até hoje';
  c_oferta_antes constant text := 'Quer que eu pergunte o que falta para montar a semana que vem? Uma resposta por OS; dá para responder num áudio.';
  c_fim_oferta constant text := ', preciso de umas respostas suas: quer que eu pergunte? Uma resposta por OS; dá para responder num áudio.';
  v_res   jsonb := '[]'::jsonb;
  r       jsonb;
  x       jsonb;
  v_t     text;
  v_t2    text;
  v_max   int;
begin
  if not v_fix then
    insert into _resultado values ('A–D cenários da correção P1', true,
      'PULADO: sem as fixtures (agenda_teste.fase2, cenario_motor e mig_leituras_fase1): rode pela bancada');
    return;
  end if;
  perform set_config('agenda.hoje', c_hoje::text, true);
  v_max := (select texto_max from public.agenda_config where id);

  -- ── A e B na carteira da Fase 2 (4 OS na semana que vem) ──
  begin
    r := pg_temp.fase2();
    perform pg_temp.agora(c_hoje, '17:40');
    v_res := pg_temp.ok(v_res, 'A0 a vigia publicou a semana de 03 a 06/11 (17 meios-dias; o Lenine segue na seg 09/11)',
      (r #>> '{contagens,publicacao,publicadas}')::int = 17
      and exists (select 1 from public.v_agenda_dia v where v.dia = date '2026-11-09' and v.numero = 'OS-00074'),
      (r #> '{contagens,publicacao}')::text);

    v_t := pg_temp.ver(null, 'semana', c_hoje);
    v_res := pg_temp.igual(v_res, 'A1 *agenda* qui 29/10 depois da publicação: a 1ª linha diz o resto desta semana (nada mais) e o aviso das diárias',
      pg_temp.linha(v_t, 1), 'De hoje a sáb 31/10 não tem mais nada marcado, e ' || c_aviso || '.');
    v_res := pg_temp.igual(v_res, 'A2 *agenda* qui 29/10: a semana que vem montada, cada OS com o bloco inteiro (o Lenine até seg 09/11) e a reserva como reserva',
      pg_temp.linha(v_t, 2),
      'A semana que vem (seg 02/11 a sáb 07/11): Vanderlei (ter 03 a qui 05/11), Rodrigo OS-00096 (ter 03/11 às 13:00), '
      || 'Lenine (qua 04 a seg 09/11) e Flávio (reserva, qua 04 e sex 06/11).');
    v_res := pg_temp.igual(v_res, 'A3 *agenda* qui 29/10: a oferta continua (a porta da rodada de aprontar) e diz que já tem semana montada',
      pg_temp.ultima(v_t), 'Para marcar mais na semana que vem' || c_fim_oferta);
    v_res := pg_temp.ok(v_res, 'A4 *agenda* qui 29/10: agenda_semana dentro do teto (texto_max), sem "nada marcado" na semana que vem, sem a oferta de antes',
      pg_temp.tam(null, null, c_hoje) <= v_max and v_t not like '%Esta semana (seg 26/10 a sáb 31/10) não tem nada marcado%'
      and position(c_oferta_antes in v_t) = 0 and v_t like '%Prontos para começar:%' and v_t like '%Livre de verdade%',
      format('%s caracteres: %s', char_length(v_t), v_t));
    x := public.agenda_ver(null, 'semana', null, null, null, null, false, c_hoje) #> '{dados,semana_que_vem}';
    v_res := pg_temp.ok(v_res, 'A5 os dados: semana_que_vem {modo estendida, de seg 02/11 a sáb 07/11, 4 OS com dias_bloco, o plano em ordem, nada no resto}',
      x ->> 'modo' = 'estendida' and x ->> 'de' = '2026-11-02' and x ->> 'ate' = '2026-11-07'
      and jsonb_array_length(x -> 'marc') = 4 and x -> 'resto' = '[]'::jsonb
      and x -> 'plano' = '["Vanderlei", "Rodrigo OS-00096", "Lenine", "a reserva para Flávio"]'::jsonb
      and (select e -> 'dias_bloco' from jsonb_array_elements(x -> 'marc') e where e #>> '{o,numero}' = 'OS-00074')
          = '["2026-11-04", "2026-11-05", "2026-11-06", "2026-11-09"]'::jsonb, x::text);
    -- sábado: o resto é só hoje; domingo: esta semana já passou (o aviso vai na linha da semana que vem)
    v_res := pg_temp.igual(v_res, 'A6 *agenda* no sábado 31/10: "Hoje (sáb 31/10) não tem mais nada marcado"',
      pg_temp.linha(pg_temp.ver(null, 'semana', date '2026-10-31'), 1),
      'Hoje (sáb 31/10) não tem mais nada marcado, e ' || c_aviso || '.');
    v_t := pg_temp.ver(null, 'semana', date '2026-11-01');
    v_res := pg_temp.igual(v_res, 'A7 *agenda* no domingo 01/11: só a semana que vem (a de amanhã), com o aviso das diárias',
      pg_temp.linha(v_t, 1),
      'A semana que vem (seg 02/11 a sáb 07/11): Vanderlei (ter 03 a qui 05/11), Rodrigo OS-00096 (ter 03/11 às 13:00), '
      || 'Lenine (qua 04 a seg 09/11) e Flávio (reserva, qua 04 e sex 06/11). ' || c_aviso_m || '.');
    -- no meio da semana com plano: o resto desta (de hoje ao sábado) e a continuação na semana que vem
    v_t := pg_temp.ver(null, 'semana', date '2026-11-04');
    v_res := pg_temp.ok(v_res, 'A8 *agenda* qua 04/11: o resto desta semana (de hoje ao sábado) e a semana que vem com o 4º dia do Lenine; a oferta diz o que já tem',
      pg_temp.linha(v_t, 1) like 'De hoje a sáb 07/11: Vanderlei (qua 04 e qui 05/11)%'
      and pg_temp.linha(v_t, 2) = 'A semana que vem (seg 09/11 a sáb 14/11): Lenine (seg 09/11 às 08:00).'
      and pg_temp.ultima(v_t) = 'Para marcar mais que Lenine na semana que vem' || c_fim_oferta
      and pg_temp.tam(null, null, date '2026-11-04') <= v_max, v_t);

    -- B. *agenda semana que vem*: o bloco inteiro; com 4 OS o com quem não cabe no teto e sai antes de qualquer nome
    v_t := pg_temp.ver(null, 'proxima_semana', c_hoje);
    v_res := pg_temp.igual(v_res, 'B1 *agenda semana que vem* (4 OS): o bloco inteiro de cada uma; no teto sai o com quem, nenhum nome',
      pg_temp.linha(v_t, 1),
      'A semana que vem (seg 02/11 a sáb 07/11): Vanderlei (ter 03 a qui 05/11), Rodrigo OS-00096 (ter 03/11 às 13:00), '
      || 'Lenine (qua 04 a seg 09/11) e Flávio (reserva, qua 04 e sex 06/11). ' || c_aviso_m || '.');
    v_res := pg_temp.ok(v_res, 'B2 *agenda semana que vem*: a oferta diz que já tem semana montada; dentro do teto',
      pg_temp.ultima(v_t) = 'Para marcar mais na semana que vem' || c_fim_oferta
      and pg_temp.tam(date '2026-11-02', date '2026-11-07', c_hoje) <= v_max, v_t);
    x := public.agenda_ver(null, 'proxima_semana', null, null, null, null, false, c_hoje) -> 'dados';
    v_res := pg_temp.ok(v_res, 'B3 os dados: o marcado com o texto com quem (o que coube só sem ele) e semana_que_vem {modo bloco}',
      x #>> '{semana_que_vem,modo}' = 'bloco'
      and (select e ->> 'texto_semana' from jsonb_array_elements(x -> 'marcados') e where e #>> '{o,numero}' = 'OS-00074')
          = 'Lenine (qua 04 a seg 09/11, com você, João e Roberto)'
      and (select e ->> 'texto_curto' from jsonb_array_elements(x -> 'marcados') e where e #>> '{o,numero}' = 'OS-00074')
          = 'Lenine (qua 04 a seg 09/11)', x::text);
    -- com o teto apertado, depois do com quem saem os nomes do fim, e a linha diz onde está tudo
    update public.agenda_config set texto_max = 700 where id;
    v_t := pg_temp.ver(null, 'proxima_semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'B4 teto apertado (700): a semana que vem perde nome do fim e diz "(*agenda plano* mostra tudo)"; *agenda* também',
      pg_temp.linha(v_t, 1) like 'A semana que vem (seg 02/11 a sáb 07/11): Vanderlei (ter 03 a qui 05/11)% e mais _ (*agenda plano* mostra tudo).%'
      and pg_temp.tam(date '2026-11-02', date '2026-11-07', c_hoje) <= 700 and pg_temp.tam(null, null, c_hoje) <= 700
      and pg_temp.linha(pg_temp.ver(null, 'semana', c_hoje), 2) like 'A semana que vem (seg 02/11 a sáb 07/11): Vanderlei (ter 03 a qui 05/11)% e mais _ (*agenda plano* mostra tudo).',
      v_t);
    update public.agenda_config set texto_max = 1000 where id;

    -- C. *agenda plano*: a reserva acima da carga diz quem vai e que é reserva; o bloco do Lenine continua na seg 09/11
    v_res := pg_temp.igual(v_res, 'C1 *agenda plano* qui 29/10: o publicado dia a dia, a reserva com quem vai, e o dia do Lenine depois do sábado ("(continua)")',
      pg_temp.ver('plano', null, c_hoje),
      'De qui 29/10 a sáb 07/11, o que está publicado:' || E'\n'
      || 'Seg 02/11: Finados.' || E'\n'
      || 'Ter 03/11: 08:00 Vanderlei (OS-00069), dia 1 de 3: você abre, Roberto o dia todo; 13:00 Rodrigo (OS-00096): você.' || E'\n'
      || 'Qua 04/11: 08:00 Vanderlei (OS-00069), dia 2 de 3: Roberto o dia todo; 08:00 Lenine (OS-00074), dia 1 de 4: você abre, João; '
      || '13:00 Flávio (OS-00104): João — reservado (acima da carga).' || E'\n'
      || 'Qui 05/11: 08:00 Vanderlei (OS-00069), dia 3 de 3: você fecha, Roberto o dia todo; 08:00 Lenine (OS-00074), dia 2 de 4: João.' || E'\n'
      || 'Sex 06/11: 08:00 Lenine (OS-00074), dia 3 de 4: João; 08:00 Flávio (OS-00104): Roberto — reservado (acima da carga).' || E'\n'
      || 'Seg 09/11 (continua): 08:00 Lenine (OS-00074), dia 4 de 4: você fecha, Roberto.');
    v_res := pg_temp.ok(v_res, 'C2 *agenda plano* da semana que vem: começa na segunda e também mostra a seg 09/11 do Lenine',
      pg_temp.ver('plano', 'proxima_semana', c_hoje) like 'A semana que vem (seg 02/11 a sáb 07/11), o que está publicado:' || E'\n' || 'Seg 02/11: Finados.%'
      and pg_temp.ultima(pg_temp.ver('plano', 'proxima_semana', c_hoje)) = 'Seg 09/11 (continua): 08:00 Lenine (OS-00074), dia 4 de 4: você fecha, Roberto.',
      pg_temp.ver('plano', 'proxima_semana', c_hoje));
    -- N. as linhas do dia (a manhã e o fechamento) não mudam: a reserva continua "Reserva: …"
    v_res := pg_temp.igual(v_res, 'N1 agenda_linhas_do_dia (a manhã e o fechamento) não muda: qua 04/11 com "Reserva: Flávio (OS-00104): João"',
      (select string_agg((x2 ->> 'hora') || ' ' || (x2 ->> 'texto'), ' | ' order by o)
         from jsonb_array_elements(public.agenda_linhas_do_dia(date '2026-11-04', null, c_hoje)) with ordinality t(x2, o)),
      '08:00 Vanderlei (OS-00069), dia 2 de 3: Roberto o dia todo | 08:00 Lenine (OS-00074), dia 1 de 4: você abre, João'
      || ' | 13:00 Reserva: Flávio (OS-00104): João');
    -- N. sem plano na semana que vem e com o que fazer nesta (seg 09/11: o último dia do Lenine): tudo como antes, byte a byte
    v_res := pg_temp.igual(v_res, 'N2 *agenda* seg 09/11 (o que fazer nesta, nada na que vem): a semana de antes, byte a byte',
      public.agenda_semana(null, null, date '2026-11-09')::text, pg_temp.agenda_semana_antes(null, null, date '2026-11-09')::text);
    v_res := pg_temp.ok(v_res, 'N3 *agenda* seg 09/11: a oferta de sempre e nenhuma linha da semana que vem',
      pg_temp.ver(null, 'semana', date '2026-11-09') like 'Esta semana (seg 09/11 a sáb 14/11): Lenine (seg 09/11 às 08:00).%'
      and pg_temp.ver(null, 'semana', date '2026-11-09') not like '%A semana que vem%'
      and pg_temp.ultima(pg_temp.ver(null, 'semana', date '2026-11-09')) = c_oferta_antes,
      pg_temp.ver(null, 'semana', date '2026-11-09'));
    -- N. o *livre*: o resumo e o livre de agenda_semana, de onde a leitura do livre tira o texto, são os de antes
    x := public.agenda_semana(null, null, c_hoje);
    r := pg_temp.agenda_semana_antes(null, null, c_hoje);
    v_res := pg_temp.ok(v_res, 'N4 *livre*: o resumo, o livre, a fila, a capacidade e o livre em faixa de agenda_semana são os de antes (qui 29/10, com a semana estendida)',
      x #> '{dados,textos,resumo}' = r #> '{dados,textos,resumo}' and x #> '{dados,textos,livre}' = r #> '{dados,textos,livre}'
      and x #> '{dados,fila}' = r #> '{dados,fila}' and x #> '{dados,capacidade}' = r #> '{dados,capacidade}'
      and x #> '{dados,livre}' = r #> '{dados,livre}' and x #> '{dados,marcados}' = r #> '{dados,marcados}', null);
    v_t := pg_temp.ver('livre', null, c_hoje);
    v_res := pg_temp.ok(v_res, 'N5 *livre* (agenda_ver foco livre) não ganha a semana que vem nem a oferta',
      v_t like 'Livre ela não está:%' and v_t not like '%semana que vem (seg%' and v_t not like '%Para marcar mais%', v_t);
    -- D. determinismo
    v_res := pg_temp.ok(v_res, 'D1 *agenda*, *agenda semana que vem* e *agenda plano* duas vezes: o mesmo texto (md5)',
      md5(pg_temp.ver(null, 'semana', c_hoje) || pg_temp.ver(null, 'proxima_semana', c_hoje) || pg_temp.ver('plano', null, c_hoje))
      = md5(pg_temp.ver(null, 'semana', c_hoje) || pg_temp.ver(null, 'proxima_semana', c_hoje) || pg_temp.ver('plano', null, c_hoje)), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── A, B e C no cenário do motor: a reserva condicionada (como a do Lenine em produção) ──
  begin
    r := pg_temp.cenario();
    perform pg_temp.agora(c_hoje, '17:40');
    v_t := pg_temp.ver(null, 'semana', c_hoje);
    v_res := pg_temp.igual(v_res, 'A9 cenário: *agenda* qui 29/10 com a reserva do Caio inteira (qui 05 a ter 10/11)',
      pg_temp.linha(v_t, 2), 'A semana que vem (seg 02/11 a sáb 07/11): Antônio (ter 03 e qua 04/11), Beatriz (qui 05/11 às 08:00) e Caio (reserva, qui 05 a ter 10/11).');
    v_res := pg_temp.igual(v_res, 'A10 cenário: a oferta diz o que já tem ("a reserva para Caio", sem artigo antes do nome)',
      pg_temp.ultima(v_t), 'Para marcar mais que Antônio, Beatriz e a reserva para Caio na semana que vem' || c_fim_oferta);
    v_res := pg_temp.igual(v_res, 'B5 cenário: *agenda semana que vem* com o bloco inteiro e quem vai (cabe no teto)',
      pg_temp.linha(pg_temp.ver(null, 'proxima_semana', c_hoje), 1),
      'A semana que vem (seg 02/11 a sáb 07/11): Antônio (ter 03 e qua 04/11, com você, João e Roberto), Beatriz (qui 05/11 às 08:00, '
      || 'com você e Roberto) e Caio (reserva, qui 05 a ter 10/11, com Roberto). ' || c_aviso_m || '.');
    v_res := pg_temp.igual(v_res, 'C3 cenário: *agenda plano* — a reserva com quem vai e a condição na 1ª vez, depois "(mesma condição)", até ter 10/11',
      pg_temp.ver('plano', null, c_hoje),
      'De qui 29/10 a sáb 07/11, o que está publicado:' || E'\n'
      || 'Seg 02/11: Finados.' || E'\n'
      || 'Ter 03/11: 08:00 Antônio (OS-00201), dia 1 de 2: você abre, Roberto o dia todo, João à tarde.' || E'\n'
      || 'Qua 04/11: 08:00 Antônio (OS-00201), dia 2 de 2: você fecha, Roberto o dia todo, João à tarde.' || E'\n'
      || 'Qui 05/11: 08:00 Beatriz (OS-00202): você, Roberto; 13:00 Caio (OS-00203): Roberto — reservado, se "Cabo de bateria…" '
      || 'estiver na mão (compre até ter 03/11, fornecedor Premel).' || E'\n'
      || 'Sex 06/11: 08:00 Caio (OS-00203): Roberto o dia todo — reservado (mesma condição).' || E'\n'
      || 'Seg 09/11 (continua): 08:00 Caio (OS-00203): Roberto o dia todo — reservado (mesma condição).' || E'\n'
      || 'Ter 10/11 (continua): 08:00 Caio (OS-00203): Roberto — reservado (mesma condição).');
    v_res := pg_temp.igual(v_res, 'C4 cenário: a manhã e o fechamento continuam com "Reserva: Caio (OS-00203), se …" (agenda_linhas_do_dia não muda)',
      (select x2 ->> 'texto' from jsonb_array_elements(public.agenda_linhas_do_dia(date '2026-11-05', null, c_hoje)) x2
        where (x2 ->> 'reserva')::boolean),
      'Reserva: Caio (OS-00203), se "Cabo de bateria…" estiver na mão (compre até ter 03/11, fornecedor Premel)');
    -- a reserva do pátio diz "reservado no pátio" (a mesma reserva, como se fosse do pátio)
    update public.agenda_alocacoes set reserva_de = 'patio' where tipo = 'reserva' and estado in ('publicada', 'fixada');
    v_res := pg_temp.ok(v_res, 'C5 a reserva do pátio: "— reservado no pátio, se …"',
      pg_temp.ver('plano', null, c_hoje) like '%13:00 Caio (OS-00203): Roberto — reservado no pátio, se "Cabo de bateria…" estiver na mão%',
      pg_temp.ver('plano', null, c_hoje));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── N. Sem nada publicado e fora de ligado ──
  begin
    execute current_setting('agenda_teste.fase2');
    perform pg_temp.modos('ligado', 'ligado');
    v_t := pg_temp.ver(null, 'semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'N6 ligado sem nada publicado (qui 29/10 antes das 16:30): a semana que vem "ainda não tem nada marcado" e a oferta de sempre',
      pg_temp.linha(v_t, 1) = 'De hoje a sáb 31/10 não tem mais nada marcado, e ' || c_aviso || '.'
      and pg_temp.linha(v_t, 2) = 'A semana que vem (seg 02/11 a sáb 07/11) ainda não tem nada marcado.'
      and pg_temp.ultima(v_t) = c_oferta_antes and pg_temp.tam(null, null, c_hoje) <= v_max, v_t);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    r := pg_temp.fase2('sombra', 'sombra');
    v_res := pg_temp.ok(v_res, 'N7 sombra: *agenda* e *agenda semana que vem* de qui 29/10 são os de antes, byte a byte',
      public.agenda_semana(null, null, c_hoje)::text = pg_temp.agenda_semana_antes(null, null, c_hoje)::text
      and public.agenda_semana(date '2026-11-02', date '2026-11-07', c_hoje)::text
          = pg_temp.agenda_semana_antes(date '2026-11-02', date '2026-11-07', c_hoje)::text
      and public.agenda_semana(null, null, c_hoje) #> '{dados,semana_que_vem}' is null, null);
    v_res := pg_temp.ok(v_res, 'N8 sombra: *agenda plano* continua "Em teste (nada foi publicado): eu montaria assim", sem "reservado"',
      pg_temp.ver('plano', null, c_hoje) like 'Em teste (nada foi publicado): eu montaria assim — %'
      and pg_temp.ver('plano', null, c_hoje) not like '%reservado%', pg_temp.ver('plano', null, c_hoje));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$cenarios$;

-- ── K. As cópias ─────────────────────────────────────────────────────────────────────────────────────────
do $copia$
declare
  v_f1   text := coalesce(current_setting('agenda_teste.mig_leituras_fase1', true), '');
  v_f2   text := coalesce(current_setting('agenda_teste.mig_leituras_fase2', true), '');
  v_nome text;
  v_sig  text;
  v_fonte text;
  v_novo text;
begin
  if v_f1 = '' or v_f2 = '' then
    insert into _resultado values ('K0 as cópias só acrescentam os blocos "-- CORREÇÃO 29/10 (P1):"', true,
      'PULADO: sem agenda_teste.mig_leituras_fase1/mig_leituras_fase2 (rode pela bancada)');
    return;
  end if;
  foreach v_sig in array array['_agenda_semana_de(jsonb, date, date, jsonb, jsonb)', 'agenda_semana(date, date, date)',
                               '_agenda_ver_plano(date, date, date, timestamptz)'] loop
    v_nome := split_part(v_sig, '(', 1);
    v_fonte := pg_temp.corpo(case when v_nome = '_agenda_ver_plano' then v_f2 else v_f1 end, v_nome);
    select replace(p.prosrc, E'\r\n', E'\n') into v_novo from pg_proc p where p.oid = ('public.' || v_sig)::regprocedure;
    insert into _resultado values (
      format('K1 %s: sem os blocos "-- CORREÇÃO 29/10 (P1):", é o corpo de %s (com pelo menos um bloco)', v_nome,
             case when v_nome = '_agenda_ver_plano' then '20261025100500' else '20261024160500' end),
      v_fonte is not null and position('-- CORREÇÃO 29/10 (P1):' in v_novo) > 0 and pg_temp.sem_blocos(v_novo) = v_fonte,
      format('fonte %s × novo sem blocos %s caracteres', length(v_fonte), length(pg_temp.sem_blocos(v_novo))));
  end loop;
end
$copia$;

-- ── P. Portas (sempre) ───────────────────────────────────────────────────────────────────────────────────
with f(sig) as (values
  ('public._agenda_marcados_bloco(jsonb, date, date, boolean)'), ('public._agenda_plano_reservas(jsonb, date, uuid[])'),
  ('public._agenda_semana_de(jsonb, date, date, jsonb, jsonb)'), ('public.agenda_semana(date, date, date)'),
  ('public._agenda_ver_plano(date, date, date, timestamptz)'))
insert into _resultado
select 'P1 anon não executa as 2 novas nem as 3 recriadas', not bool_or(has_function_privilege('anon', sig, 'execute')),
       string_agg(sig, ', ') filter (where has_function_privilege('anon', sig, 'execute'))
  from f
union all
select 'P2 authenticated (o painel) e service_role (o WhatsApp) executam todas',
       bool_and(has_function_privilege('authenticated', sig, 'execute') and has_function_privilege('service_role', sig, 'execute')),
       string_agg(sig, ', ') filter (where not (has_function_privilege('authenticated', sig, 'execute')
                                               and has_function_privilege('service_role', sig, 'execute')))
  from f
union all
select 'P3 todas invoker, STABLE e com search_path fixo',
       bool_and(not p.prosecdef and p.provolatile = 's' and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=public%'),
       string_agg(f.sig, ', ') filter (where p.prosecdef or p.provolatile <> 's'
                                          or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=public%')
  from f join pg_proc p on p.oid = f.sig::regprocedure;

select teste, ok, detalhe from _resultado order by teste;

rollback;
