-- Prova da migration de dado da Fase 7g da Agenda de Produção (pacote P7; 20261112100990_agenda_fase7g_modos.sql), que a bancada NÃO aplica (FORA_DA_BANCADA): aqui
-- ela roda como está, numa subtransação desfeita, com o freio de produção (gestor_so_propor = true) — spec-fase7g §5.8 e §8.3 (agenda_fase7g_modos.sql) com R9.2,
-- R9.4-2, R9.13 e R9.14. Molde: agenda_fase7e_dado.sql. P5b (20261112100700): o dado põe ok_marcacao em veto_tipos (§4.4, §5.8, AG7-15) e a trava conta 8.
-- bancada: depende de 20261112100700
--
--   S  os 4 interruptores da 7g: desligado → sombra; marcacoes_desde, nula → a hora do dado; veto_tipos ganha ok_marcacao no fim (P5b); o resto da linha igual
--      (o freio, os modos de antes, os números da 7g); atualizado_por nulo e a hora nova; o dado sozinho não escreve mais nada; de novo não muda nada (nem a hora); ligado nunca é rebaixado e
--      sombra fica sombra; a hora já gravada fica
--   T  a trava: sem o código da 7g no banco (uma função de estrutura, a do P5b também, ou agenda_ver sem os focos da 100600), recusa e nada muda; o cabeçalho diz quantas migrations
--      de estrutura lista, e é o número da trava (T0)
--   D  o DESFAZER do cabeçalho: um comando (o with … select, um UPDATE de agenda_config, nenhum DELETE nem outra tabela); volta os 4 a desligado e nada mais (a hora
--      fica, R9.14, e o ok_marcacao de veto_tipos também); não mexe no ligado e diz quais ficam ligados; com nada a voltar, não muda nada (nem a hora)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado. Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.res(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), case when not coalesce(p_ok, false) then p_detalhe end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.adm() returns uuid language sql stable as $f$ select id from public.app_users where role = 'admin' and active order by id limit 1 $f$;
-- Os 4 interruptores da 7g, na ordem: o porquê, as leituras, o placar, o rebaixar.
create function pg_temp.modos() returns text language sql stable as $f$
  select concat_ws(' ', c.modo_porque, c.modo_explicar, c.modo_placar, c.modo_rebaixar) from public.agenda_config c where c.id
$f$;
-- A linha de agenda_config sem o que o dado grava e o carimbo (o que a migration não pode mexer).
create function pg_temp.resto() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_porque' - 'modo_explicar' - 'modo_placar' - 'modo_rebaixar' - 'marcacoes_desde' - 'veto_tipos' - 'atualizado_em' - 'atualizado_por'
    from public.agenda_config c where c.id
$f$;
-- veto_tipos (P5b: o dado põe ok_marcacao no fim)
create function pg_temp.veto() returns text[] language sql stable as $f$
  select c.veto_tipos from public.agenda_config c where c.id
$f$;
create function pg_temp.linha() returns jsonb language sql stable as $f$
  select to_jsonb(c) from public.agenda_config c where c.id
$f$;
-- O que o dado sozinho não pode mexer (o plano, o que a agenda decidiu, mediu e mandou).
create function pg_temp.foto() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_acoes a),
    'perguntas', (select md5(coalesce(string_agg(to_jsonb(q)::text, '|' order by q.id), '')) from public.agenda_perguntas q),
    'marcacoes', (select count(*) from public.agenda_marcacoes),
    'tipos', (select count(*) from public.agenda_tipos_os),
    'placar', (select count(*) from public.agenda_placar_semanas),
    'avisos', (select count(*) from public.agenda_dono_avisos),
    'fila', (select count(*) from public.whatsapp_send_queue),
    'rodadas', (select count(*) from public.agenda_vigia_rodadas))
$f$;
-- O DESFAZER do cabeçalho, como está escrito: as linhas entre as marcas, sem o "--   " (molde: agenda_fase7e_dado.sql). É 1 comando.
create function pg_temp.desfazer(p_mig text) returns text language sql immutable as $f$
  select string_agg(substr(l, 6), E'\n' order by o)
    from (select l, o, sum(case when l like '-- DESFAZER-INICIO%' then 1 when l like '-- DESFAZER-FIM%' then -1 else 0 end) over (order by o) as dentro
            from unnest(string_to_array(replace(p_mig, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
   where dentro = 1 and l not like '-- DESFAZER-INICIO%'
$f$;
-- O estado de partida, o de produção depois das 7 migrations de estrutura da 7g: os 4 desligados, a hora nula, com o freio.
create function pg_temp.partida() returns void language plpgsql as $f$
begin
  update public.agenda_config
     set modo_porque = 'desligado', modo_explicar = 'desligado', modo_placar = 'desligado', modo_rebaixar = 'desligado', marcacoes_desde = null,
         gestor_so_propor = true, gestor_so_propor_em = timestamptz '2026-11-04 23:43-03',
         atualizado_em = timestamptz '2026-11-01 12:00-03', atualizado_por = pg_temp.adm()   -- quem mexeu por último (uma pessoa): o dado tem de pôr nulo
   where id;
end $f$;
-- A definição inteira de uma função no texto de uma migration (do create ao $function$;), para pôr a versão de antes por cima (a T2)
create function pg_temp.inteira(p_mig text, p_nome text) returns text language plpgsql immutable as $f$
declare
  v text := replace(p_mig, E'\r\n', E'\n');
begin
  v := substr(v, position(format('create or replace function public.%s(', p_nome) in v));
  return left(v, position(E'\n$function$;' in v) + length(E'\n$function$;') - 1);
end $f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_modos_fase7g', true);
  v_res    jsonb := '[]'::jsonb;
  v_desf   text;
  v_resto  jsonb;
  v_linha  jsonb;
  v_foto   jsonb;
  v_err    text;
  v_cab    text[];
  v_trv    text[];
  v_dt     record;
  v_hora   timestamptz;
  v_veto   text[];
begin
  if coalesce(v_mig, '') = '' then
    insert into _resultado values ('S0 a migration 20261112100990 como texto', true, 'PULADO: sem agenda_teste.mig_modos_fase7g (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_desf := pg_temp.desfazer(v_mig);

  -- ── S: a 1ª vez, a 2ª vez, o ligado, a hora já gravada ──
  begin
    perform pg_temp.partida();
    v_resto := pg_temp.resto();
    v_veto := pg_temp.veto();
    v_foto := pg_temp.foto();
    execute v_mig;
    v_linha := pg_temp.linha();
    v_res := pg_temp.res(v_res, 'S1 os 4 interruptores de desligado para sombra (o porquê, as leituras, o placar e o rebaixar)',
                         pg_temp.modos() = 'sombra sombra sombra sombra', pg_temp.modos());
    v_res := pg_temp.res(v_res, 'S2 marcacoes_desde, nula, passa à hora do dado (R9.4-2: nada de antes entra na medida)',
                         (v_linha ->> 'marcacoes_desde')::timestamptz = now(), v_linha ->> 'marcacoes_desde');
    v_res := pg_temp.res(v_res, 'S3c (P5b) veto_tipos ganha ok_marcacao no fim e nada mais (a pergunta "Pode marcar assim?" pode vencer pelo prazo, AG7-15)',
                         not ('ok_marcacao' = any (v_veto)) and pg_temp.veto() = v_veto || '{ok_marcacao}'::text[], array_to_string(pg_temp.veto(), ','));
    v_res := pg_temp.res(v_res, 'S3 o resto da linha não muda (o freio, os modos das Fases 1–6 e de 7a–7f, os números da 7g); atualizado_por nulo e a hora nova',
                         pg_temp.resto() = v_resto and v_linha ->> 'atualizado_por' is null and (v_linha ->> 'atualizado_em')::timestamptz <> timestamptz '2026-11-01 12:00-03'
                         and (v_linha ->> 'gestor_so_propor')::boolean, pg_temp.resto()::text);
    v_res := pg_temp.res(v_res, 'S3b o dado sozinho não escreve mais nada: o plano, as propostas, as ações, as perguntas, as marcações, os tipos, o placar, os avisos, a fila e as rodadas iguais',
                         pg_temp.foto() = v_foto, pg_temp.foto()::text);
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 idempotente: a 2ª vez não muda nada (nem a hora)', pg_temp.linha() = v_linha, null);
    update public.agenda_config set modo_porque = 'ligado', modo_explicar = 'desligado', modo_rebaixar = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5 nunca rebaixa ligado nem mexe no que está em sombra; só o desligado vai a sombra', pg_temp.modos() = 'ligado sombra sombra sombra', pg_temp.modos());
    v_hora := timestamptz '2026-11-20 08:00-03';
    update public.agenda_config set modo_explicar = 'desligado', marcacoes_desde = v_hora where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5b a hora já gravada fica (nunca move marcacoes_desde); o desligado vai a sombra',
                         (pg_temp.linha() ->> 'marcacoes_desde')::timestamptz = v_hora and pg_temp.modos() = 'ligado sombra sombra sombra', pg_temp.linha() ->> 'marcacoes_desde');
    update public.agenda_config set atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := pg_temp.linha();
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5c com os 4 fora de desligado e a hora gravada, a linha não muda (nem a hora)', pg_temp.linha() = v_linha, pg_temp.modos());
    update public.agenda_config set marcacoes_desde = null, atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5d com os 4 fora de desligado e a hora nula, só a hora (a guarda olha os dois)',
                         (pg_temp.linha() ->> 'marcacoes_desde')::timestamptz = now() and pg_temp.modos() = 'ligado sombra sombra sombra', pg_temp.linha() ->> 'marcacoes_desde');
    update public.agenda_config set veto_tipos = array_remove(veto_tipos, 'ok_marcacao'), atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_resto := pg_temp.resto();
    v_hora := (pg_temp.linha() ->> 'marcacoes_desde')::timestamptz;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5e (P5b) com os 4 fora de desligado e a hora gravada, só falta ok_marcacao em veto_tipos: só ele volta (uma vez, no fim; a guarda olha os três)',
                         pg_temp.veto() = array_remove(pg_temp.veto(), 'ok_marcacao') || '{ok_marcacao}'::text[]
                         and (select count(*) from unnest(pg_temp.veto()) x where x = 'ok_marcacao') = 1
                         and (pg_temp.linha() ->> 'marcacoes_desde')::timestamptz = v_hora and pg_temp.resto() = v_resto and pg_temp.modos() = 'ligado sombra sombra sombra',
                         array_to_string(pg_temp.veto(), ','));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── T: a trava ──
  v_cab := regexp_match(v_mig, 'Aplica DEPOIS das (\d+) migrations de estrutura da 7g \(([^)]*)\)');
  v_trv := regexp_match(v_mig, 'vem depois das (\d+) migrations de estrutura da 7g');
  v_res := pg_temp.res(v_res, 'T0 o cabeçalho diz quantas migrations de estrutura lista, e é o número da frase da trava (8, com a do P5b)',
                       v_cab is not null and v_trv is not null and v_trv[1] = '8' and v_cab[1] = v_trv[1]
                       and v_cab[1]::int = (select count(*) from regexp_matches(v_cab[2], '\m\d{6}(\d{8})?\M', 'g')),
                       format('cabeçalho %s (lista: %s); trava %s', v_cab[1], v_cab[2], v_trv[1]));
  begin
    perform pg_temp.partida();
    v_linha := pg_temp.linha();
    alter function public.agenda_placar(date, date, timestamptz) rename to agenda_placar_fora;
    begin
      execute v_mig;
      v_err := 'passou';
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_res := pg_temp.res(v_res, 'T1 sem uma função de estrutura da 7g (o placar, da 100500), recusa: diz o que falta, e nada muda',
                         v_err like 'O dado 20261112100990 vem depois%agenda_placar(date, date, timestamptz)%Nada mudou.' and pg_temp.linha() = v_linha, v_err);
    alter function public.agenda_placar_fora(date, date, timestamptz) rename to agenda_placar;
    -- (P5b) sem a do P5b (o passo ok, da 20261112100700), recusa
    alter function public._agenda_explicar_ok(date, timestamptz) rename to _agenda_explicar_ok_fora;
    begin
      execute v_mig;
      v_err := 'passou';
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_res := pg_temp.res(v_res, 'T1b (P5b) sem a migration do P5b (o passo ok), recusa: diz o que falta, e nada muda',
                         v_err like 'O dado 20261112100990 vem depois das 8%_agenda_explicar_ok(date, timestamptz)%Nada mudou.' and pg_temp.linha() = v_linha, v_err);
    alter function public._agenda_explicar_ok_fora(date, timestamptz) rename to _agenda_explicar_ok;
    -- agenda_ver sem os focos (a de antes da 100600 por cima)
    execute pg_temp.inteira(current_setting('agenda_teste.mig_leituras_fase7d'), 'agenda_ver');
    begin
      execute v_mig;
      v_err := 'passou';
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_res := pg_temp.res(v_res, 'T2 com agenda_ver sem os focos da 7g (a de antes da 100600 por cima), recusa e nada muda',
                         v_err like '%os focos novos em public.agenda_ver (20261112100600)%Nada mudou.' and pg_temp.linha() = v_linha, v_err);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D: o DESFAZER ──
  v_res := pg_temp.res(v_res, 'D0 o DESFAZER é um comando: um with … select com um UPDATE de agenda_config; nenhum DELETE, ALTER nem outra tabela',
                       v_desf ~ '^with antes as \(' and (select count(*) from regexp_matches(v_desf, ';', 'g')) = 1 and v_desf ~ ';\s*$'
                       and v_desf !~* '\m(delete|drop|alter|insert|truncate)\M' and (select count(*) from regexp_matches(v_desf, 'update public\.', 'g')) = 1
                       and (select count(*) from regexp_matches(v_desf, 'public\.([a-z_]+)', 'g')) = (select count(*) from regexp_matches(v_desf, 'public\.agenda_config', 'g')),
                       v_desf);
  begin
    perform pg_temp.partida();
    execute v_mig;
    v_hora := (pg_temp.linha() ->> 'marcacoes_desde')::timestamptz;
    v_resto := pg_temp.resto();
    update public.agenda_config set modo_placar = 'ligado' where id;
    execute v_desf into v_dt;
    v_res := pg_temp.res(v_res, 'D1 volta a desligado só o que está em sombra; o ligado fica e é dito; a hora da medida fica (R9.14); o resto da linha igual',
                         pg_temp.modos() = 'desligado desligado ligado desligado' and v_dt.linha_mudou = 1 and v_dt.ficam_ligados = 'modo_placar'
                         and (pg_temp.linha() ->> 'marcacoes_desde')::timestamptz = v_hora and pg_temp.resto() = v_resto and 'ok_marcacao' = any (pg_temp.veto()),
                         format('%s; %s; %s', pg_temp.modos(), v_dt.linha_mudou, v_dt.ficam_ligados));
    update public.agenda_config set modo_placar = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := pg_temp.linha();
    execute v_desf into v_dt;
    v_res := pg_temp.res(v_res, 'D2 com os 4 já desligados, não muda nada (nem a hora) e diz nenhum',
                         pg_temp.linha() = v_linha and v_dt.linha_mudou = 0 and v_dt.ficam_ligados = 'nenhum', format('%s; %s', v_dt.linha_mudou, v_dt.ficam_ligados));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  perform pg_temp.gravar(v_res);
end
$s$;

select teste, ok, detalhe from _resultado order by teste collate "C";
rollback;
