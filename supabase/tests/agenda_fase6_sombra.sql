-- Prova da migration de dado da Fase 6 da Agenda de Produção (pacote P8; 20261029101000_agenda_fase6_sombra.sql), que a
-- bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a história de sex 30/10
-- (fixture-fase6.sql).
-- bancada: depende de 20261029100800
--
--   S  o modo: desligado (com a lista vazia) → sombra; a lista fica {}; o resto da linha igual; de novo não muda nada (nem a
--      hora); ligado nunca é rebaixado; o desligado que já teve item ligado (o dono parou até a medição) não volta a teste
--   N  nada muda fora disso: a medição, o que foi aprendido, as ações, as perguntas, a fila e o plano iguais; e em sombra a
--      rodada calcula (agenda_aprendizado em sombra) sem usar nada (nenhuma linha em uso, nenhuma ação nem pergunta)
--   D  o DESFAZER do cabeçalho: um bloco só (do $desfaz$ … $desfaz$;), um UPDATE, nenhum DELETE; volta a sombra a desligado
--      e não mexe no ligado
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é o
--   supabase/tests/agenda_fase6_pos_deploy.sql (só leitura). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create function pg_temp.res(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false),
                                                      case when not coalesce(p_ok, false) then p_detalhe end))
$f$;
-- A linha de agenda_config sem o modo do aprendizado, a lista e o carimbo (o que a migration não pode mexer).
create function pg_temp.resto_da_config() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_aprendizado' - 'aprendizado_ligados' - 'atualizado_em' - 'atualizado_por'
    from public.agenda_config c
$f$;
create function pg_temp.modo() returns text language sql stable as $f$
  select c.modo_aprendizado || ' ' || c.aprendizado_ligados::text from public.agenda_config c
$f$;
-- O que não pode mudar: o que a agenda mediu, aprendeu e gravou, o que sai e o plano.
create function pg_temp.contagens() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'medidas', (select md5(coalesce(string_agg(to_jsonb(m)::text, '|' order by m.service_order_id), '')) from public.agenda_medidas_os m),
    'aprendizado', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.item, a.chave), '')) from public.agenda_aprendizado a),
    'fila', (select count(*) from public.whatsapp_send_queue),
    'acoes', (select count(*) from public.agenda_acoes),
    'perguntas', (select count(*) from public.agenda_perguntas),
    'plano', (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.service_order_id), '')) from public.os_planejamento p))
$f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_sombra_fase6', true);
  v_res    jsonb := '[]'::jsonb;
  v_resto  jsonb;
  v_cont   jsonb;
  v_linha  jsonb;
  v_desf   text;
  v_bloco  text;
  v_acoes  int;
  v_perg   int;
  r        jsonb;
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.fase6', true), '') = '' then
    insert into _resultado values ('S0 a migration 20261029101000 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase6 ou agenda_teste.fase6 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  -- O DESFAZER do cabeçalho: as linhas de SQL ("--   …") entre "-- DESFAZER" e a linha "--" que fecha o bloco.
  v_bloco := substr(v_mig, position(E'\n-- DESFAZER' in v_mig) + 1);
  v_bloco := left(v_bloco, position(E'\n--\n' in v_bloco));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into v_desf
    from regexp_split_to_table(v_bloco, E'\n') with ordinality t(l, n)
   where t.l like '--   %';

  execute current_setting('agenda_teste.fase6');

  -- ── S: a 1ª vez, a 2ª vez, o ligado, o desligado com itens ─────────────────────────────────────────────
  begin
    update public.agenda_config set modo_aprendizado = 'desligado', aprendizado_ligados = '{}',
                                    atualizado_em = timestamptz '2026-10-30 12:00-03' where id;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S1 desligado (a lista vazia) → sombra; a lista dos itens fica {}', pg_temp.modo() = 'sombra {}', pg_temp.modo());
    v_res := pg_temp.res(v_res, 'S2 o resto da linha não muda (os outros modos e todos os números); atualizado_por nulo e a hora nova',
      pg_temp.resto_da_config() = v_resto and v_linha ->> 'atualizado_por' is null
      and (v_linha ->> 'atualizado_em')::timestamptz <> timestamptz '2026-10-30 12:00-03', pg_temp.resto_da_config()::text);
    v_res := pg_temp.res(v_res, 'N1 nada muda fora disso: as medidas, o que foi aprendido, as ações, as perguntas, a fila e o plano iguais',
      pg_temp.contagens() = v_cont, pg_temp.contagens()::text);

    execute v_mig;
    v_res := pg_temp.res(v_res, 'S3 idempotente: a 2ª vez não muda nada (nem a hora)',
      (select to_jsonb(c) from public.agenda_config c) = v_linha, null);

    -- em sombra a rodada calcula e não usa: nada em uso, nenhuma ação nem pergunta do aprendizado, nada na fila
    v_acoes := (select count(*) from public.agenda_acoes);
    v_perg := (select count(*) from public.agenda_perguntas);
    r := public.agenda_aprender(date '2026-10-30', (timestamp '2026-10-30 16:05') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.res(v_res, 'N2 em sombra a rodada das 16:05 calcula (linhas em sombra) e não usa nada: nenhuma em uso, nenhuma ação nem pergunta, nada na fila',
      (r ->> 'rodou')::boolean and r ->> 'modo' = 'sombra'
      and exists (select 1 from public.agenda_aprendizado a where a.estado = 'sombra')
      and not exists (select 1 from public.agenda_aprendizado a where a.estado in ('em_uso', 'pergunta', 'travado') or a.em_uso is not null)
      and (select count(*) from public.agenda_acoes) = v_acoes and (select count(*) from public.agenda_perguntas) = v_perg
      and (select count(*) from public.whatsapp_send_queue) = (v_cont ->> 'fila')::bigint,
      r::text);

    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = array['fator'],
                                    atualizado_em = timestamptz '2026-10-30 12:00-03' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 nunca rebaixa ligado (o fator ligado fica, com a lista e a hora)',
      pg_temp.modo() = 'ligado {fator}'
      and (select atualizado_em from public.agenda_config) = timestamptz '2026-10-30 12:00-03', pg_temp.modo());
    update public.agenda_config set modo_aprendizado = 'desligado' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5 o dono parou até a medição depois de ligar um item (desligado com a lista): a migration não volta a teste calada',
      pg_temp.modo() = 'desligado {fator}', pg_temp.modo());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D: o DESFAZER do cabeçalho ─────────────────────────────────────────────────────────────────────────
  begin
    v_res := pg_temp.res(v_res, 'D0 o cabeçalho tem o DESFAZER num bloco só (do $desfaz$ … $desfaz$;): um UPDATE, nenhum DELETE',
      v_desf is not null and v_desf ~ '^\s*do \$desfaz\$' and v_desf ~ '\$desfaz\$;\s*$'
      and (length(v_desf) - length(replace(v_desf, '$desfaz$', ''))) / length('$desfaz$') = 2
      and (length(v_desf) - length(replace(v_desf, 'update public.', ''))) / length('update public.') = 1
      and position('delete' in lower(v_desf)) = 0, coalesce(v_desf, '(sem o bloco)'));
    update public.agenda_config set modo_aprendizado = 'desligado', aprendizado_ligados = '{}' where id;
    execute v_mig;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_desf;
    v_res := pg_temp.res(v_res, 'D1 o DESFAZER volta a sombra a desligado; o resto da linha e o que foi medido e aprendido ficam',
      pg_temp.modo() = 'desligado {}' and pg_temp.resto_da_config() = v_resto and pg_temp.contagens() = v_cont
      and (select atualizado_por from public.agenda_config) is null, pg_temp.modo());
    update public.agenda_config set modo_aprendizado = 'ligado', aprendizado_ligados = array['mo'] where id;
    execute v_desf;
    v_res := pg_temp.res(v_res, 'D2 o DESFAZER não mexe no que já foi ligado (para isso, o "tudo na hora" da §10: sombra)',
      pg_temp.modo() = 'ligado {mo}', pg_temp.modo());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
