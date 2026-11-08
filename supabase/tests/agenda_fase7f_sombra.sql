-- Prova da migration de dado da Fase 7f da Agenda de Produção (pacote P8; 20261109100900_agenda_fase7f_sombra.sql), que a bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda
-- como está, numa subtransação desfeita, com o freio de produção (gestor_so_propor = true) — spec-fase7f §5.8 com R8.2, R8.6, R8.8, R8.14; a decisão do fio de 08/11 (só os 3
-- modos com código vão a sombra: modo_bloco_agenda, modo_veto e modo_lote_dono; modo_equipe_previsto, modo_equipe_convite e modo_cliente_camadas ficam desligados).
-- bancada: depende de 20261109100600
--
--   S  os 3 com código: desligado → sombra; os 3 sem código ficam desligados (nem a sombra posta à mão muda); o resto da linha igual (os modos das Fases 1–6 e de 7a–7d, os
--      números da 7f, cliente_tipos_ligados sem semana, o freio); atualizado_por nulo e a hora nova; o dado sozinho não escreve mais nada; de novo não muda nada (nem a hora);
--      ligado nunca é rebaixado e sombra fica sombra; com os 3 fora de desligado, nenhuma linha muda (nem a hora)
--   N  o tique: sem o dado (os 6 desligados) a rodada comunicar não grava linha; com ele, grava 1 por tique (2 tiques = 2 linhas), sem erro, com os 4 passos da equipe "ainda
--      não existe", e nada vai à fila, à equipe, ao cliente nem ao aviso do dono; o plano e as ações iguais; as perguntas só mudam nas medidas (veto_teria_em, destrava);
--      no domingo não roda; a saúde da comunicação diz os 3 em teste e os 3 desligados, com os zeros
--   D  o DESFAZER do cabeçalho: um comando só (with … select), um UPDATE de agenda_config, nenhum DELETE e nenhuma outra tabela; volta os 3 a desligado e nada mais (o resto
--      da linha igual, os 3 sem código como estavam); não mexe no ligado e diz quais ficam ligados; com os 3 já desligados não muda nada (nem a hora); depois dele a rodada
--      comunicar volta a não gravar linha
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é o pós-deploy
--   (supabase/tests/agenda_fase7f_pos_deploy.sql, só leitura). Termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
set local timezone = 'UTC';

create function pg_temp.res(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), case when not coalesce(p_ok, false) then p_detalhe end))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- Os 6 interruptores da 7f, na ordem: bloco, veto, lote, previsto, convite, camadas.
create function pg_temp.modos() returns text language sql stable as $f$
  select concat_ws(' ', c.modo_bloco_agenda, c.modo_veto, c.modo_lote_dono, c.modo_equipe_previsto, c.modo_equipe_convite, c.modo_cliente_camadas) from public.agenda_config c where c.id
$f$;
-- A linha de agenda_config sem os 3 que o dado grava e o carimbo (o que a migration não pode mexer).
create function pg_temp.resto() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_bloco_agenda' - 'modo_veto' - 'modo_lote_dono' - 'atualizado_em' - 'atualizado_por' from public.agenda_config c where c.id
$f$;
create function pg_temp.linha() returns jsonb language sql stable as $f$
  select to_jsonb(c) from public.agenda_config c where c.id
$f$;
-- O que o dado e o tique em sombra não podem mexer (as perguntas sem as 2 medidas da 7f: veto_teria_em e destrava).
create function pg_temp.foto() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_acoes a),
    'perguntas', (select md5(coalesce(string_agg((to_jsonb(q) - 'veto_teria_em' - 'destrava')::text, '|' order by q.id), '')) from public.agenda_perguntas q),
    'equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select count(*) from public.agenda_cliente_mensagens),
    'avisos', (select count(*) from public.agenda_dono_avisos),
    'fila', (select count(*) from public.whatsapp_send_queue),
    'disponibilidade', (select md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '')) from public.agenda_disponibilidade d),
    'plano', (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.service_order_id), '')) from public.os_planejamento p),
    'erros', (select count(*) from public.app_error_logs e where e.context = 'agenda' and e.action like 'comunicar:%'))
$f$;
create function pg_temp.rodadas() returns int language sql stable as $f$
  select count(*)::int from public.agenda_vigia_rodadas r where r.rotina = 'comunicar'
$f$;
-- O DESFAZER do cabeçalho, como está escrito: as linhas entre as marcas, sem o "--   " (molde: agenda_fase7d_semente.sql)
create function pg_temp.desfazer(p_mig text) returns text language sql immutable as $f$
  select string_agg(substr(l, 6), E'\n' order by o)
    from (select l, o, sum(case when l like '-- DESFAZER-INICIO%' then 1 when l like '-- DESFAZER-FIM%' then -1 else 0 end) over (order by o) as dentro
            from unnest(string_to_array(replace(p_mig, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
   where dentro = 1 and l not like '-- DESFAZER-INICIO%'
$f$;
-- O estado de partida, o de produção depois das migrations de estrutura da 7f: os 6 desligados, com o freio.
create function pg_temp.partida() returns void language sql as $f$
  update public.agenda_config
     set modo_bloco_agenda = 'desligado', modo_veto = 'desligado', modo_lote_dono = 'desligado', modo_equipe_previsto = 'desligado', modo_equipe_convite = 'desligado',
         modo_cliente_camadas = 'desligado', gestor_so_propor = true, gestor_so_propor_em = timestamptz '2026-11-04 23:43-03',
         cliente_tipos_ligados = array_remove(cliente_tipos_ligados, 'semana'), atualizado_em = timestamptz '2026-11-01 12:00-03',
         atualizado_por = 'f7f00000-0000-4000-8000-0000000008aa'   -- quem mexeu por último (uma pessoa): o dado tem de pôr nulo
   where id;
$f$;

do $s$
declare
  v_mig   text := current_setting('agenda_teste.mig_sombra_fase7f', true);
  v_res   jsonb := '[]'::jsonb;
  v_desf  text;
  v_resto jsonb;
  v_linha jsonb;
  v_foto  jsonb;
  v_n     int;
  v_r     jsonb;
  v_r2    jsonb;
  v_ult   record;
  v_s     jsonb;
  v_dt    record;
  v_teria int;
  v_abertas int;
  c_ter   constant date := date '2026-11-10';   -- ter 10/11: um dia útil
  c_dom   constant date := date '2026-11-15';
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.fase7f', true), '') = '' then
    insert into _resultado values ('S0 a migration 20261109100900 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase7f ou a fixture da 7f (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_desf := pg_temp.desfazer(v_mig);
  -- a fixture da 7f (as 8 perguntas abertas, 2 com o prazo escrito que vence ter 10/11 18:00; as ações não contadas; a equipe e o cliente): o dado e o tique têm o que mexer
  execute current_setting('agenda_teste.fase7f');

  -- ── S: a 1ª vez, a 2ª vez, o ligado ──────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.partida();
    v_resto := pg_temp.resto();
    v_foto := pg_temp.foto();
    execute v_mig;
    v_linha := pg_temp.linha();
    v_res := pg_temp.res(v_res, 'S1 os 3 com código de desligado para sombra (bloco, veto, lote)', split_part(pg_temp.modos(), ' ', 1) || split_part(pg_temp.modos(), ' ', 2)
                         || split_part(pg_temp.modos(), ' ', 3) = 'sombrasombrasombra', pg_temp.modos());
    v_res := pg_temp.res(v_res, 'S2 os 3 sem código ficam desligados (previsto, convite, camadas): a decisão do fio de 08/11',
                         pg_temp.modos() = 'sombra sombra sombra desligado desligado desligado', pg_temp.modos());
    v_res := pg_temp.res(v_res, 'S3 o resto da linha não muda (os modos das Fases 1–6 e de 7a–7d, os números da 7f, os outros 3); atualizado_por nulo e a hora nova',
                         pg_temp.resto() = v_resto and v_linha ->> 'atualizado_por' is null and (v_linha ->> 'atualizado_em')::timestamptz <> timestamptz '2026-11-01 12:00-03',
                         pg_temp.resto()::text);
    v_res := pg_temp.res(v_res, 'S3b o freio fica (gestor_so_propor = true) e cliente_tipos_ligados não ganha semana',
                         (v_linha ->> 'gestor_so_propor')::boolean and not (v_linha -> 'cliente_tipos_ligados') ? 'semana', v_linha ->> 'cliente_tipos_ligados');
    v_res := pg_temp.res(v_res, 'S3c o dado sozinho não escreve mais nada: o plano, as propostas, as ações, as perguntas, as mensagens, a fila, a disponibilidade e o planejamento iguais',
                         pg_temp.foto() = v_foto, pg_temp.foto()::text);
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 idempotente: a 2ª vez não muda nada (nem a hora)', pg_temp.linha() = v_linha, null);
    update public.agenda_config set modo_veto = 'ligado', modo_lote_dono = 'sombra', modo_bloco_agenda = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5 nunca rebaixa ligado nem mexe no que está em sombra; só o desligado vai a sombra (veto ligado antes)',
                         pg_temp.modos() = 'sombra ligado sombra desligado desligado desligado', pg_temp.modos());
    update public.agenda_config set modo_bloco_agenda = 'ligado', modo_veto = 'sombra', modo_lote_dono = 'ligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := pg_temp.linha();
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5b com os 3 fora de desligado, a linha não muda (nem a hora)', pg_temp.linha() = v_linha, pg_temp.modos());
    update public.agenda_config set modo_bloco_agenda = 'sombra', modo_veto = 'desligado', modo_lote_dono = 'ligado' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5d o bloco já em sombra não segura os outros: o prazo desligado vai a sombra, o lote ligado fica',
                         pg_temp.modos() = 'sombra sombra ligado desligado desligado desligado', pg_temp.modos());
    update public.agenda_config set modo_bloco_agenda = 'desligado', modo_equipe_previsto = 'sombra', modo_cliente_camadas = 'ligado' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5c os 3 sem código não são do dado: o que estiver neles fica (aqui, sombra e ligado postos à mão)',
                         pg_temp.modos() = 'sombra sombra ligado sombra desligado ligado', pg_temp.modos());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── N: o tique, sem e com o dado ─────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.partida();
    v_n := pg_temp.rodadas();
    v_r := public.agenda_comunicar_rodar(c_ter, pg_temp.em(c_ter, '18:15'));
    v_res := pg_temp.res(v_res, 'N1 sem o dado (os 6 desligados): a rodada comunicar não roda nem grava linha', not (v_r ->> 'rodou')::boolean and pg_temp.rodadas() = v_n, v_r::text);
    execute v_mig;
    v_foto := pg_temp.foto();
    v_teria := (select count(*) from public.agenda_perguntas q where q.veto_teria_em is not null);
    v_abertas := (select count(*) from public.agenda_perguntas q where q.estado = 'aberta');
    v_r := public.agenda_comunicar_rodar(c_ter, pg_temp.em(c_ter, '18:15'));
    select r.erros, r.contagens into v_ult from public.agenda_vigia_rodadas r where r.rotina = 'comunicar' order by r.rodou_em desc, r.p_agora desc limit 1;
    v_res := pg_temp.res(v_res, 'N2 com o dado: 1 linha no tique, rotina comunicar, sem erro',
                         (v_r ->> 'rodou')::boolean and pg_temp.rodadas() = v_n + 1 and v_ult.erros = 0 and (v_r ->> 'erros')::int = 0, v_r::text);
    v_res := pg_temp.res(v_res, 'N3 os modos da rodada: o bloco e o lote em teste, o prazo em teste (com o freio), e os 3 sem código desligados',
                         v_ult.contagens -> 'modos' = '{"bloco": "sombra", "lote": "sombra", "veto": "sombra", "previsto": "desligado", "convite": "desligado", "camadas": "desligado"}'::jsonb,
                         (v_ult.contagens -> 'modos')::text);
    v_res := pg_temp.res(v_res, 'N4 os 4 passos da equipe dizem "ainda não existe" (o P5 não existe)',
                         (select count(*) from unnest(array['previsto', 'mudancas_equipe', 'convites', 'convites_vencidos']) p
                           where v_ult.contagens -> p = '{"pulado": true, "motivo": "ainda não existe"}'::jsonb) = 4, v_ult.contagens::text);
    v_r2 := public.agenda_comunicar_rodar(c_ter, pg_temp.em(c_ter, '18:30'));
    v_res := pg_temp.res(v_res, 'N5 1 linha por tique: o 2º tique grava a 2ª', (v_r2 ->> 'rodou')::boolean and pg_temp.rodadas() = v_n + 2, v_r2::text);
    v_res := pg_temp.res(v_res, 'N6 em sombra, o tique não manda nada: a fila, a equipe, o cliente e o aviso do dono iguais; o plano e as ações iguais; as perguntas só nas medidas',
                         pg_temp.foto() = v_foto and jsonb_array_length(coalesce(v_r -> 'avisos', '[]')) = 0 and jsonb_array_length(coalesce(v_r2 -> 'avisos', '[]')) = 0,
                         pg_temp.foto()::text);
    v_res := pg_temp.res(v_res, 'N6b a sombra mediu de verdade (o controle do N6): o teto em teste gravou veto_teria_em, e nenhuma pergunta fechou',
                         (select count(*) from public.agenda_perguntas q where q.veto_teria_em is not null) > v_teria
                         and (select count(*) from public.agenda_perguntas q where q.estado = 'aberta') = v_abertas,
                         format('teria %s → %s; abertas %s → %s', v_teria, (select count(*) from public.agenda_perguntas q where q.veto_teria_em is not null), v_abertas,
                                (select count(*) from public.agenda_perguntas q where q.estado = 'aberta')));
    v_r := public.agenda_comunicar_rodar(c_dom, pg_temp.em(c_dom, '14:15'));
    v_res := pg_temp.res(v_res, 'N7 no domingo não roda nem grava', not (v_r ->> 'rodou')::boolean and v_r ->> 'motivo' = 'domingo' and pg_temp.rodadas() = v_n + 2, v_r::text);
    v_s := public._agenda_saude_comunicacao(c_ter, pg_temp.em(c_ter, '18:45'));
    v_res := pg_temp.res(v_res, 'N8 a saúde da comunicação: os 3 em teste e os 3 desligados (os modos crus), o freio, os zeros em 0 e as 2 rodadas',
                         v_s -> 'modos' = '{"bloco": "sombra", "lote": "sombra", "veto": "sombra", "previsto": "desligado", "convite": "desligado", "camadas": "desligado"}'::jsonb
                         and (v_s ->> 'freio')::boolean and (v_s ->> 'zeros_ok')::boolean and (v_s ->> 'rodadas_24h')::int = 2 and v_s -> 'numeros' <> '{}'::jsonb, v_s::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D: o DESFAZER ────────────────────────────────────────────────────────────────────────────────────
  v_res := pg_temp.res(v_res, 'D1 o DESFAZER é um comando só: with … select, um UPDATE de agenda_config, nenhum DELETE, nenhuma outra tabela',
                       v_desf like 'with antes as (%' and v_desf !~* '\mdelete\M' and v_desf !~* '\minsert\M'
                       and (select count(*) from regexp_matches(v_desf, '\mupdate public\.', 'g')) = 1 and v_desf ~ '\mupdate public\.agenda_config\M'
                       and (length(v_desf) - length(replace(v_desf, ';', ''))) = 1 and rtrim(v_desf) like '%;', left(v_desf, 300));
  begin
    perform pg_temp.partida();
    update public.agenda_config set modo_equipe_previsto = 'sombra' where id;
    execute v_mig;
    v_resto := to_jsonb(pg_temp.linha()) - 'modo_bloco_agenda' - 'modo_veto' - 'modo_lote_dono' - 'atualizado_em' - 'atualizado_por';
    v_foto := pg_temp.foto();
    execute v_desf into v_dt;
    v_res := pg_temp.res(v_res, 'D2 volta os 3 a desligado e nada mais: o resto da linha igual, o previsto em sombra posto à mão continua, nada fora de agenda_config muda',
                         pg_temp.modos() = 'desligado desligado desligado sombra desligado desligado'
                         and (to_jsonb(pg_temp.linha()) - 'modo_bloco_agenda' - 'modo_veto' - 'modo_lote_dono' - 'atualizado_em' - 'atualizado_por') = v_resto
                         and pg_temp.foto() = v_foto and v_dt.modos_desligados = 1 and v_dt.ficam_ligados = 'nenhum', pg_temp.modos() || ' ' || to_jsonb(v_dt)::text);
    update public.agenda_config set modo_equipe_previsto = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := pg_temp.linha();
    execute v_desf into v_dt;
    v_res := pg_temp.res(v_res, 'D3 com os 3 já desligados não muda nada (nem a hora)', pg_temp.linha() = v_linha and v_dt.modos_desligados = 0, to_jsonb(v_dt)::text);
    execute v_mig;
    update public.agenda_config set modo_veto = 'ligado' where id;
    execute v_desf into v_dt;
    v_res := pg_temp.res(v_res, 'D4 não mexe no ligado e diz quais ficam ligados (o prazo ligado: primeiro o DESFAZER do ligar-fase7f.sql)',
                         pg_temp.modos() = 'desligado ligado desligado desligado desligado desligado' and v_dt.ficam_ligados = 'modo_veto', pg_temp.modos() || ' ' || to_jsonb(v_dt)::text);
    update public.agenda_config set modo_veto = 'desligado' where id;
    v_n := pg_temp.rodadas();
    v_r := public.agenda_comunicar_rodar(c_ter, pg_temp.em(c_ter, '19:00'));
    v_res := pg_temp.res(v_res, 'D5 depois do DESFAZER a rodada comunicar volta a não rodar nem gravar linha', not (v_r ->> 'rodou')::boolean and pg_temp.rodadas() = v_n, v_r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(pg_temp.res(v_res, 'S quebrou', false, sqlstate || ': ' || sqlerrm));
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
