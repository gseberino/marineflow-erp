-- Prova da migration de dado da Fase 7e da Agenda de Produção (pacote P8; 20261111100900_agenda_fase7e_dado.sql), que a bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como
-- está, numa subtransação desfeita, com o freio de produção (gestor_so_propor = true) — spec-fase7e §5.7, §8.3 (agenda_fase7e_dado.sql) com R7.2, R7.3-1, R7.6, R7.11, R7.13 e R7.14.
-- bancada: depende de 20261111100600
--
--   S  os 6 interruptores da 7e: desligado → sombra (modo_promessa também: em teste para sempre, AG7-32); fornecedor_n_min 5 → 3 e o DEFAULT 3; o resto da linha igual (o freio, o
--      aprendizado, os modos das Fases 1–6, de 7a–7d e da 7f, os outros números da 7e); atualizado_por nulo e a hora nova; o dado sozinho não escreve mais nada; de novo não muda nada
--      (nem a hora); ligado nunca é rebaixado e sombra fica sombra; o 4 que o dono pôs no fornecedor fica; com nada a mudar, nenhuma linha muda (nem a hora)
--   T  a trava: sem o código da 7e no banco (uma função de estrutura, ou a rodada sem os passos da margem), recusa e nada muda; o cabeçalho diz quantas migrations de estrutura
--      lista, e é o número da trava (T0)
--   N  com a carteira da fixture da 7e: o dado sozinho não muda o motor, a prontidão, os meios das OS, a vigia nem a rodada do cliente (md5); a rodada do aprendizado com o dado roda os
--      6 passos da margem em teste, sem erro, e só grava as linhas deles em teste (nada em uso, nenhuma ação nem pergunta da margem); depois dela, o motor e o resto continuam os de
--      antes do dado (md5); o controle morde (o viés ligado sem o freio e em uso muda os meios das OS); o foco aprendizado ganha o bloco 8 (§6.2) e só ele; a saúde: a margem com os
--      zeros e os modos crus em teste; o puxar na véspera em teste só escreve o diário do gestor
--   D  o DESFAZER do cabeçalho: dois comandos (o with … select, um UPDATE de agenda_config, nenhum DELETE nem outra tabela; e o ALTER do DEFAULT); volta os 6 a desligado, o 3 a 5 e o
--      DEFAULT a 5, e nada mais; não mexe no ligado e diz quais ficam ligados; o 4 do dono fica; com nada a voltar, não muda nada (nem a hora); depois dele a rodada não roda a margem
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é o pós-deploy (supabase/tests/agenda_fase7e_pos_deploy.sql, só
--   leitura). Termina em ROLLBACK.
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
-- Os 6 interruptores da 7e, na ordem: viés, folga da semana, urgência, prazo real, tempo de compra, folga da compra.
create function pg_temp.modos() returns text language sql stable as $f$
  select concat_ws(' ', c.modo_vies, c.modo_folga_semana, c.modo_urgencia, c.modo_promessa, c.modo_tempo_compra, c.modo_folga_compra) from public.agenda_config c where c.id
$f$;
create function pg_temp.padrao() returns text language sql stable as $f$
  select i.column_default::text from information_schema.columns i where i.table_schema = 'public' and i.table_name = 'agenda_config' and i.column_name = 'fornecedor_n_min'
$f$;
-- A linha de agenda_config sem o que o dado grava e o carimbo (o que a migration não pode mexer).
create function pg_temp.resto() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_vies' - 'modo_folga_semana' - 'modo_urgencia' - 'modo_promessa' - 'modo_tempo_compra' - 'modo_folga_compra' - 'fornecedor_n_min'
         - 'atualizado_em' - 'atualizado_por' from public.agenda_config c where c.id
$f$;
create function pg_temp.linha() returns jsonb language sql stable as $f$
  select to_jsonb(c) from public.agenda_config c where c.id
$f$;
-- O que o dado sozinho não pode mexer (o plano, o que a agenda decidiu e mandou, o que mediu).
create function pg_temp.foto() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_acoes a),
    'perguntas', (select md5(coalesce(string_agg(to_jsonb(q)::text, '|' order by q.id), '')) from public.agenda_perguntas q),
    'aprendizado', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.item, a.chave), '')) from public.agenda_aprendizado a),
    'medidas_os', (select count(*) from public.agenda_medidas_os),
    'medidas_compra', (select count(*) from public.agenda_medidas_compra),
    'planejamento', (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.service_order_id), '')) from public.os_planejamento p),
    'equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select count(*) from public.agenda_cliente_mensagens),
    'avisos', (select count(*) from public.agenda_dono_avisos),
    'fila', (select count(*) from public.whatsapp_send_queue),
    'gestor_dia', (select md5(coalesce(string_agg(to_jsonb(g)::text, '|' order by g.dia), '')) from public.agenda_gestor_dia g),
    'rodadas', (select count(*) from public.agenda_vigia_rodadas),
    'erros', (select count(*) from public.app_error_logs e where e.context = 'agenda'))
$f$;
-- O DESFAZER do cabeçalho, como está escrito: as linhas entre as marcas, sem o "--   " (molde: agenda_fase7f_sombra.sql). São 2 comandos: o 1º termina no 1º ";" do fim de linha.
create function pg_temp.desfazer(p_mig text) returns text language sql immutable as $f$
  select string_agg(substr(l, 6), E'\n' order by o)
    from (select l, o, sum(case when l like '-- DESFAZER-INICIO%' then 1 when l like '-- DESFAZER-FIM%' then -1 else 0 end) over (order by o) as dentro
            from unnest(string_to_array(replace(p_mig, E'\r\n', E'\n'), E'\n')) with ordinality u(l, o)) x
   where dentro = 1 and l not like '-- DESFAZER-INICIO%'
$f$;
create function pg_temp.desfazer_1(p_d text) returns text language sql immutable as $f$
  select left(p_d, position(E';\n' in p_d))
$f$;
create function pg_temp.desfazer_2(p_d text) returns text language sql immutable as $f$
  select btrim(substr(p_d, position(E';\n' in p_d) + 2), E' \n')
$f$;
-- O estado de partida, o de produção depois das 8 migrations de estrutura da 7e: os 6 desligados, o fornecedor em 5 (linha e DEFAULT), com o freio e o aprendizado ligado.
create function pg_temp.partida() returns void language plpgsql as $f$
begin
  alter table public.agenda_config alter column fornecedor_n_min set default 5;
  update public.agenda_config
     set modo_vies = 'desligado', modo_folga_semana = 'desligado', modo_urgencia = 'desligado', modo_promessa = 'desligado', modo_tempo_compra = 'desligado',
         modo_folga_compra = 'desligado', fornecedor_n_min = 5, gestor_so_propor = true, gestor_so_propor_em = timestamptz '2026-11-04 23:43-03', modo_aprendizado = 'ligado',
         atualizado_em = timestamptz '2026-11-01 12:00-03', atualizado_por = pg_temp.adm()   -- quem mexeu por último (uma pessoa): o dado tem de pôr nulo
   where id;
end $f$;

-- ── N: as leituras e as rodadas que o dado não pode mudar (o molde do R7 de agenda_fase7e_rodada.sql) ──────────────────────────────────────────────────────────────────────────────
create function pg_temp.limpa(p jsonb) returns jsonb language plpgsql immutable as $f$
begin
  return case jsonb_typeof(p)
    when 'object' then coalesce((select jsonb_object_agg(e.k, pg_temp.limpa(e.v)) from jsonb_each(p) e(k, v) where e.k !~ '^(ms|duracao|duracao_ms|tempo)$'), '{}'::jsonb)
    when 'array' then coalesce((select jsonb_agg(pg_temp.limpa(a.v) order by a.o) from jsonb_array_elements(p) with ordinality a(v, o)), '[]'::jsonb)
    else p end;
end $f$;
create function pg_temp.semid(p jsonb) returns text language sql immutable as $f$
  select regexp_replace(pg_temp.limpa(p)::text, '"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"', '"U"', 'g')
$f$;
create function pg_temp.conta() returns text language sql stable as $f$
  select concat_ws(':', (select count(*) from public.agenda_perguntas), (select count(*) from public.agenda_acoes), (select count(*) from public.agenda_equipe_mensagens),
                   (select count(*) from public.agenda_cliente_mensagens), (select count(*) from public.agenda_propostas),
                   (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')), (select count(*) from public.whatsapp_send_queue))
$f$;
create function pg_temp.leituras(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $f$
declare
  v  jsonb := '{}';
  c0 text;
begin
  v := v || jsonb_build_object('agenda_propor', md5(pg_temp.semid(public.agenda_propor('semana', date '2027-01-11', date '2027-01-16', null, '{}'::jsonb, false, 'vigia', null, p_hoje, p_agora))));
  v := v || jsonb_build_object('os_prontidao', (select md5(string_agg(pg_temp.semid(public.os_prontidao(so.id, p_hoje)), '|' order by so.service_order_number))
                                                  from public.service_orders so where so.merged_into_id is null and so.status not in ('completed', 'invoiced', 'cancelled')));
  v := v || jsonb_build_object('agenda_meios_da_os', (select md5(string_agg(coalesce(pg_temp.semid(public.agenda_meios_da_os(so.id, p_hoje)), '-'), '|' order by so.service_order_number))
                                                        from public.service_orders so where so.merged_into_id is null and so.status not in ('completed', 'invoiced', 'cancelled')));
  v := v || jsonb_build_object('os_duracao_sugerida', (select md5(string_agg(coalesce(pg_temp.semid(public.os_duracao_sugerida(so.id)), '-'), '|' order by so.service_order_number))
                                                         from public.service_orders so where so.merged_into_id is null and so.status not in ('completed', 'invoiced', 'cancelled')));
  v := v || jsonb_build_object('carga', (select string_agg(public._agenda_carga_da_semana(s)::text, ' ' order by s)
                                           from generate_series(date '2027-01-11', date '2027-02-15', interval '7 days') g(s0) cross join lateral (select s0::date as s) x));
  v := v || jsonb_build_object('saude_sem_margem', md5(pg_temp.semid(public.agenda_saude(p_hoje, p_agora) - 'margem')));
  begin
    c0 := pg_temp.conta();
    v := v || jsonb_build_object('agenda_vigiar', md5(pg_temp.semid(public.agenda_vigiar(p_hoje, p_agora)) || c0 || '→' || pg_temp.conta()));
    raise exception 'desfaz' using errcode = 'P0097';
  exception when sqlstate 'P0097' then null;
  end;
  begin
    c0 := pg_temp.conta();
    v := v || jsonb_build_object('agenda_cliente_vigiar', md5(pg_temp.semid(public.agenda_cliente_vigiar(p_hoje, p_agora)) || c0 || '→' || pg_temp.conta()));
    raise exception 'desfaz' using errcode = 'P0097';
  exception when sqlstate 'P0097' then null;
  end;
  return v;
end $f$;
create function pg_temp.dif(p_a jsonb, p_b jsonb) returns text language sql immutable as $f$
  select string_agg(x.key, ', ' order by x.key) from jsonb_each_text(p_a) x where x.value is distinct from p_b ->> x.key
$f$;

-- A carteira da fixture da 7e (07/01/2027), como o R7 de agenda_fase7e_rodada.sql: só as OS-7E* e a OS-E0 contam; o estado de partida; o gestor ligado (como em produção)
create function pg_temp.carteira() returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.fase7e');
  perform set_config('marineflow.agrupar_orcamentos', 'on', true);
  update public.service_orders set merged_into_id = 'e7e00000-0000-4000-8000-000000000e00'
   where service_order_number not like 'OS-7E%' and service_order_number <> 'OS-E0' and merged_into_id is null;
  perform set_config('marineflow.agrupar_orcamentos', '', true);
  perform pg_temp.partida();
  update public.agenda_config set modo_marcar_sozinho = 'ligado' where id;
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
  v_mig    text := current_setting('agenda_teste.mig_dado_fase7e', true);
  v_res    jsonb := '[]'::jsonb;
  v_desf   text;
  v_d1     text;
  v_d2     text;
  v_resto  jsonb;
  v_linha  jsonb;
  v_foto   jsonb;
  v_dt     record;
  v_err    text;
  v_a0     jsonb;
  v_b0     jsonb;
  v_ra     jsonb;
  v_ca     text;
  v_na     int;
  v_a      jsonb;
  v_b      jsonb;
  v_c      jsonb;
  v_ctl    jsonb;
  v_r      jsonb;
  v_n      int;
  v_foco_a jsonb;
  v_foco_b jsonb;
  v_s      jsonb;
  v_c0     text;
  v_gd     jsonb;
  v_cab    text[];
  v_trv    text[];
  c_hoje   constant date := date '2027-01-07';
  c_agora  constant timestamptz := timestamptz '2027-01-07 16:05-03';
  c_margem constant text[] := array['vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor'];
begin
  if coalesce(v_mig, '') = '' then
    insert into _resultado values ('S0 a migration 20261111100900 como texto', true, 'PULADO: sem agenda_teste.mig_dado_fase7e (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_desf := pg_temp.desfazer(v_mig);
  v_d1 := pg_temp.desfazer_1(v_desf);
  v_d2 := pg_temp.desfazer_2(v_desf);

  -- ── S: a 1ª vez, a 2ª vez, o ligado, o número do dono ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  begin
    perform pg_temp.partida();
    v_resto := pg_temp.resto();
    v_foto := pg_temp.foto();
    execute v_mig;
    v_linha := pg_temp.linha();
    v_res := pg_temp.res(v_res, 'S1 os 6 interruptores de desligado para sombra (o viés, a folga da semana, a urgência, o prazo real, o tempo de compra e a folga da compra)',
                         pg_temp.modos() = 'sombra sombra sombra sombra sombra sombra', pg_temp.modos());
    v_res := pg_temp.res(v_res, 'S2 fornecedor_n_min de 5 para 3, e o DEFAULT da coluna 3 ("OK fornecedor com 3 entregas")',
                         (v_linha ->> 'fornecedor_n_min')::int = 3 and pg_temp.padrao() = '3', format('linha %s, DEFAULT %s', v_linha ->> 'fornecedor_n_min', pg_temp.padrao()));
    v_res := pg_temp.res(v_res, 'S3 o resto da linha não muda (o freio, o aprendizado, os modos das Fases 1–6, de 7a–7d e da 7f, os outros números da 7e); atualizado_por nulo e a hora nova',
                         pg_temp.resto() = v_resto and v_linha ->> 'atualizado_por' is null and (v_linha ->> 'atualizado_em')::timestamptz <> timestamptz '2026-11-01 12:00-03',
                         pg_temp.resto()::text);
    v_res := pg_temp.res(v_res, 'S3b nenhum interruptor ligado; o freio fica (gestor_so_propor = true) e o aprendizado ligado',
                         not pg_temp.modos() like '%ligado%' and (v_linha ->> 'gestor_so_propor')::boolean and v_linha ->> 'modo_aprendizado' = 'ligado', pg_temp.modos());
    v_res := pg_temp.res(v_res, 'S3c o dado sozinho não escreve mais nada: o plano, as propostas, as ações, as perguntas, o aprendizado, as medidas, as mensagens, a fila, o diário do gestor e as rodadas iguais',
                         pg_temp.foto() = v_foto, pg_temp.foto()::text);
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 idempotente: a 2ª vez não muda nada (nem a hora; o DEFAULT segue 3)', pg_temp.linha() = v_linha and pg_temp.padrao() = '3', null);
    update public.agenda_config set modo_vies = 'ligado', modo_urgencia = 'desligado', modo_tempo_compra = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5 nunca rebaixa ligado nem mexe no que está em sombra; só o desligado vai a sombra (o viés ligado antes)',
                         pg_temp.modos() = 'ligado sombra sombra sombra sombra sombra', pg_temp.modos());
    update public.agenda_config set modo_vies = 'sombra', modo_folga_semana = 'ligado', modo_urgencia = 'sombra', modo_promessa = 'sombra', modo_tempo_compra = 'ligado',
                                    modo_folga_compra = 'sombra', fornecedor_n_min = 3, atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := pg_temp.linha();
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5b com os 6 fora de desligado e o fornecedor fora de 5, a linha não muda (nem a hora)', pg_temp.linha() = v_linha, pg_temp.modos());
    update public.agenda_config set fornecedor_n_min = 4, modo_folga_compra = 'desligado' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5c o número que o dono pôs no fornecedor (4) fica: só o 5 de nascença vai a 3; a folga da compra desligada vai a sombra',
                         (pg_temp.linha() ->> 'fornecedor_n_min')::int = 4 and pg_temp.modos() = 'sombra ligado sombra sombra ligado sombra', format('%s; %s', pg_temp.linha() ->> 'fornecedor_n_min', pg_temp.modos()));
    update public.agenda_config set modo_promessa = 'desligado', fornecedor_n_min = 5 where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5d o prazo real vai a sombra como os outros (AG7-32: em teste para sempre; o ligar-fase7e.sql recusa ligar), e o 5 vai a 3 mesmo com os outros modos já mexidos',
                         split_part(pg_temp.modos(), ' ', 4) = 'sombra' and (pg_temp.linha() ->> 'fornecedor_n_min')::int = 3, format('%s; %s', pg_temp.linha() ->> 'fornecedor_n_min', pg_temp.modos()));
    update public.agenda_config set modo_vies = 'sombra', modo_folga_semana = 'sombra', modo_urgencia = 'sombra', modo_promessa = 'sombra', modo_tempo_compra = 'sombra',
                                    modo_folga_compra = 'sombra', fornecedor_n_min = 5 where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5e com os 6 já em teste e o fornecedor ainda em 5, o 5 vai a 3 (a guarda olha os dois)',
                         (pg_temp.linha() ->> 'fornecedor_n_min')::int = 3 and pg_temp.modos() = 'sombra sombra sombra sombra sombra sombra', format('%s; %s', pg_temp.linha() ->> 'fornecedor_n_min', pg_temp.modos()));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── T: a trava ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  -- T0 (a conferência do P8): o "Aplica DEPOIS das N migrations de estrutura da 7e (…)" do cabeçalho tem N = as versões que ele lista = o número da frase da trava (8)
  v_cab := regexp_match(v_mig, 'Aplica DEPOIS das (\d+) migrations de estrutura da 7e \(([^)]*)\)');
  v_trv := regexp_match(v_mig, 'vem depois das (\d+) migrations de estrutura da 7e');
  v_res := pg_temp.res(v_res, 'T0 o cabeçalho diz quantas migrations de estrutura lista, e é o número da frase da trava (8)',
                       v_cab is not null and v_trv is not null and v_trv[1] = '8' and v_cab[1] = v_trv[1]
                       and v_cab[1]::int = (select count(*) from regexp_matches(v_cab[2], '\m\d{6}(\d{8})?\M', 'g')),
                       format('cabeçalho %s (lista: %s); trava %s', v_cab[1], v_cab[2], v_trv[1]));
  begin
    perform pg_temp.partida();
    v_linha := pg_temp.linha();
    alter function public._agenda_saude_margem(date, timestamptz) rename to _agenda_saude_margem_fora;
    begin
      execute v_mig;
      v_err := 'passou';
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_res := pg_temp.res(v_res, 'T1 sem uma função de estrutura da 7e (a saúde da margem, da 100600), recusa: diz o que falta, e nada muda (os modos, o fornecedor e o DEFAULT)',
                         v_err like 'O dado 20261111100900 vem depois%_agenda_saude_margem(date, timestamptz)%Nada mudou.' and pg_temp.linha() = v_linha and pg_temp.padrao() = '5', v_err);
    alter function public._agenda_saude_margem_fora(date, timestamptz) rename to _agenda_saude_margem;
    -- a rodada sem os passos da margem (uma migration mais velha por cima da 100600): a versão de antes, sem a marca
    execute pg_temp.inteira(current_setting('agenda_teste.mig_correcao_calculo_fase6'), 'agenda_aprender');
    begin
      execute v_mig;
      v_err := 'passou';
    exception when sqlstate 'P0001' then v_err := sqlerrm;
    end;
    v_res := pg_temp.res(v_res, 'T2 com a rodada do aprendizado sem os passos da margem (a de antes da 100600 por cima), recusa e nada muda',
                         v_err like '%os passos da margem em public.agenda_aprender (20261111100600)%Nada mudou.' and pg_temp.linha() = v_linha and pg_temp.padrao() = '5', v_err);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── N: a carteira da fixture da 7e ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  -- a: sem o dado (o estado de produção entre o passo 1 e o passo 3: os 6 desligados); b: com o dado. Em cada uma, as leituras antes da rodada, a rodada do aprendizado das 16:05 e as
  -- leituras depois dela. A âncora de fora (o código de antes da 7e) é o replay da carteira real (f7e/p8/real.mjs); aqui, a mesma carteira sem e com o dado, e um controle que morde.
  if coalesce(current_setting('agenda_teste.fase7e', true), '') = '' then
    insert into _resultado values ('N0 a carteira da fixture da 7e', true, 'PULADO: sem agenda_teste.fase7e (rode pela bancada)');
  else
    begin
      begin
        perform pg_temp.carteira();
        v_a0 := pg_temp.leituras(c_hoje, c_agora);
        v_ra := public.agenda_aprender(c_hoje, c_agora);
        v_ca := pg_temp.conta();
        v_na := (select count(*) from public.agenda_aprendizado a where a.item = any (c_margem));
        v_a := pg_temp.leituras(c_hoje, c_agora);
        v_foco_a := public.agenda_ver(null, null, null, 'aprendizado', null, null, false, c_hoje);
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
      begin
        perform pg_temp.carteira();
        v_foto := pg_temp.foto();
        execute v_mig;
        v_res := pg_temp.res(v_res, 'N1b com a carteira da fixture, o dado sozinho não escreve fora de agenda_config (o plano, as ações, as perguntas, o aprendizado, as medidas, o planejamento das OS, as mensagens, a fila, o diário do gestor e as rodadas iguais)',
                             pg_temp.foto() = v_foto and (select count(*) from public.os_planejamento) > 0, pg_temp.foto()::text);
        v_b0 := pg_temp.leituras(c_hoje, c_agora);
        v_res := pg_temp.res(v_res, 'N1 o dado sozinho não muda o motor da semana, a prontidão, os meios e a duração de cada OS, a carga das 6 semanas, a saúde (fora a margem), a vigia nem a rodada do cliente (md5, com o que gravam)',
                             pg_temp.dif(v_a0, v_b0) is null and (select count(*) from jsonb_object_keys(v_a0)) = 8, coalesce(pg_temp.dif(v_a0, v_b0), v_a0::text));
        v_r := public.agenda_aprender(c_hoje, c_agora);
        v_res := pg_temp.res(v_res, 'N2 a rodada do aprendizado com o dado: rodou sem erro, com os 6 interruptores em teste em contagens.modos_margem e os 6 passos da margem chamados (sem o dado, nenhum)',
                             (v_r ->> 'rodou')::boolean and coalesce((v_r ->> 'erros')::int, 0) = 0
                             and v_r #> '{contagens,modos_margem}' = '{"vies": "sombra", "folga_semana": "sombra", "urgencia": "sombra", "promessa": "sombra", "tempo_compra": "sombra", "folga_compra": "sombra"}'::jsonb
                             and (v_r -> 'contagens') ?& c_margem and not ((v_ra -> 'contagens') ?| c_margem) and v_na = 0, left(v_r::text, 1500));
        v_res := pg_temp.res(v_res, 'N3 em teste a margem só mede: as linhas dela em teste (sombra ou medindo), nada em uso, nenhuma ação da margem; as perguntas, as ações, as mensagens, as propostas, o plano e a fila contam o mesmo que sem o dado',
                             (select count(*) from public.agenda_aprendizado a where a.item = any (c_margem)) > 0
                             and not exists (select 1 from public.agenda_aprendizado a where a.item = any (c_margem) and (a.em_uso is not null or a.estado not in ('sombra', 'medindo')))
                             and not exists (select 1 from public.agenda_acoes a where a.tipo = 'aprendizado' and (a.antes ->> 'item' = any (c_margem) or a.depois ->> 'item' = any (c_margem)))
                             and pg_temp.conta() = v_ca,
                             format('%s; conta %s × %s', (select string_agg(a.item || ':' || a.chave || ':' || a.estado || ':' || coalesce(a.em_uso::text, '-'), ', ') from public.agenda_aprendizado a where a.item = any (c_margem)), v_ca, pg_temp.conta()));
        v_b := pg_temp.leituras(c_hoje, c_agora);
        v_res := pg_temp.res(v_res, 'N4 depois da rodada em teste, o motor, a prontidão, os meios, a duração, a carga, a saúde (fora a margem), a vigia e a rodada do cliente são os de sem o dado (md5)',
                             pg_temp.dif(v_a, v_b) is null, coalesce(pg_temp.dif(v_a, v_b), '-'));
        -- o controle morde: o viés ligado de verdade, sem o freio, com o geral em uso, muda os meios das OS (a foto enxerga o viés)
        begin
          update public.agenda_config set modo_vies = 'ligado', gestor_so_propor = false where id;
          insert into public.agenda_aprendizado (item, chave, nivel, padrao, n_min, n, calculado, em_uso, em_uso_desde, estado, calculado_em)
          values ('vies', 'estimativa:todas', 'todas', 1, 1, 8, 1.40, 1.40, c_agora - interval '30 hours', 'em_uso', c_agora - interval '30 hours')
          on conflict (item, chave) do update set em_uso = 1.40, calculado = 1.40, estado = 'em_uso', em_uso_desde = c_agora - interval '30 hours';
          v_ctl := pg_temp.leituras(c_hoje, c_agora);
          raise exception 'desfaz' using errcode = 'P0097';
        exception when sqlstate 'P0097' then null;
        end;
        v_res := pg_temp.res(v_res, 'N4b o controle morde: com o viés ligado de verdade, sem o freio e 1,40 em uso, os meios das OS mudam (a foto enxerga o viés)',
                             coalesce(pg_temp.dif(v_b, v_ctl), '') like '%agenda_meios_da_os%', coalesce(pg_temp.dif(v_b, v_ctl), 'nenhuma diferença'));
        -- o foco aprendizado: o bloco 8 entra (§6.2), e o resto do foco é o de sem o dado
        v_foco_b := public.agenda_ver(null, null, null, 'aprendizado', null, null, false, c_hoje);
        v_res := pg_temp.res(v_res, 'N5 o foco aprendizado ganha o bloco 8 ("Margem", em teste) e só ele: os outros blocos iguais aos de sem o dado (sem o dado, nenhum bloco 8)',
                             not exists (select 1 from jsonb_array_elements(coalesce(v_foco_a #> '{dados,blocos}', '[]')) b where b ->> 'nome' = 'margem')
                             and exists (select 1 from jsonb_array_elements(coalesce(v_foco_b #> '{dados,blocos}', '[]')) b where b ->> 'nome' = 'margem')
                             and (select jsonb_agg(b order by o) from jsonb_array_elements(v_foco_b #> '{dados,blocos}') with ordinality t(b, o) where b ->> 'nome' <> 'margem')
                                 is not distinct from (select jsonb_agg(b order by o) from jsonb_array_elements(v_foco_a #> '{dados,blocos}') with ordinality t(b, o) where b ->> 'nome' <> 'margem'),
                             left(coalesce(v_foco_b ->> 'texto', '-'), 900));
        v_res := pg_temp.res(v_res, 'N5b as linhas do bloco 8 em teste: com texto, nenhuma em uso, nenhum termo proibido da §6 ("viés", "P80", "mediana", "du"…)',
                             exists (select 1 from jsonb_array_elements(v_foco_b #> '{dados,blocos}') b, jsonb_array_elements(b -> 'linhas') l where b ->> 'nome' = 'margem' and length(l ->> 'texto') > 0)
                             and not exists (select 1 from jsonb_array_elements(v_foco_b #> '{dados,blocos}') b, jsonb_array_elements(b -> 'linhas') l
                                              where b ->> 'nome' = 'margem' and (l ->> 'estado' = 'em_uso' or l ->> 'texto' ~* '(viés|dispersão|P80|percentil|mediana|credibilidade|amostra|\mdu\M)')),
                             (select string_agg(l ->> 'texto', ' | ') from jsonb_array_elements(v_foco_b #> '{dados,blocos}') b, jsonb_array_elements(b -> 'linhas') l where b ->> 'nome' = 'margem'));
        -- a saúde: a margem existe, com os zeros
        v_s := public.agenda_saude(c_hoje, c_agora + interval '1 minute');
        v_res := pg_temp.res(v_res, 'N6 a saúde: a chave margem com zeros_ok (nada em uso com o interruptor fora, nenhum passo maior que o limite, nenhum valor fora dos limites)',
                             coalesce((v_s #>> '{margem,zeros_ok}')::boolean, false), left(coalesce((v_s -> 'margem')::text, '-'), 900));
        -- o puxar na véspera em teste: só o diário do gestor (R7.7-1)
        v_c0 := pg_temp.conta();
        v_r := public._agenda_gestor_puxar(date '2027-01-06', timestamptz '2027-01-06 17:37-03');
        v_res := pg_temp.res(v_res, 'N7 o puxar na véspera, com o dado (a urgência em teste e o freio): rodou em teste e não escreveu proposta, ação, alocação, pergunta nem mensagem',
                             (v_r ->> 'rodou')::boolean and (v_r ->> 'em_teste')::boolean and pg_temp.conta() = v_c0 and coalesce((v_r ->> 'erros')::int, 0) = 0,
                             format('%s → %s; %s', v_c0, pg_temp.conta(), left(v_r::text, 600)));
        raise exception 'desfaz' using errcode = 'P0098';
      exception when sqlstate 'P0098' then null;
      end;
    exception when others then
      get stacked diagnostics v_err = pg_exception_context;
      v_res := pg_temp.res(v_res, 'N quebrou', false, sqlstate || ': ' || sqlerrm || ' ' || left(v_err, 400));
    end;
  end if;

  -- ── D: o DESFAZER ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  v_res := pg_temp.res(v_res, 'D1 o DESFAZER são 2 comandos: o with … select (um UPDATE de agenda_config, nenhum DELETE nem INSERT, nenhuma outra tabela) e o ALTER do DEFAULT a 5',
                       v_d1 like 'with antes as (%' and v_d1 !~* '\mdelete\M' and v_d1 !~* '\minsert\M'
                       and (select count(*) from regexp_matches(v_d1, '\mupdate public\.', 'g')) = 1 and v_d1 ~ '\mupdate public\.agenda_config\M'
                       and (length(v_d1) - length(replace(v_d1, ';', ''))) = 1 and rtrim(v_d1) like '%;'
                       and v_d2 = 'alter table public.agenda_config alter column fornecedor_n_min set default 5;', left(v_desf, 400));
  begin
    perform pg_temp.partida();
    execute v_mig;
    v_resto := pg_temp.resto();
    v_foto := pg_temp.foto();
    execute v_d1 into v_dt;
    execute v_d2;
    v_res := pg_temp.res(v_res, 'D2 volta os 6 a desligado, o 3 a 5 e o DEFAULT a 5, e nada mais: o resto da linha igual, nada fora de agenda_config muda',
                         pg_temp.modos() = 'desligado desligado desligado desligado desligado desligado' and (pg_temp.linha() ->> 'fornecedor_n_min')::int = 5 and pg_temp.padrao() = '5'
                         and pg_temp.resto() = v_resto and pg_temp.foto() = v_foto and v_dt.linha_mudou = 1 and v_dt.ficam_ligados = 'nenhum',
                         pg_temp.modos() || ' ' || to_jsonb(v_dt)::text);
    update public.agenda_config set atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := pg_temp.linha();
    execute v_d1 into v_dt;
    execute v_d2;
    v_res := pg_temp.res(v_res, 'D3 com os 6 já desligados e o fornecedor fora de 3, não muda nada (nem a hora)', pg_temp.linha() = v_linha and v_dt.linha_mudou = 0 and pg_temp.padrao() = '5', to_jsonb(v_dt)::text);
    execute v_mig;
    update public.agenda_config set modo_folga_semana = 'ligado', modo_tempo_compra = 'ligado', fornecedor_n_min = 4 where id;
    execute v_d1 into v_dt;
    v_res := pg_temp.res(v_res, 'D4 não mexe no ligado e diz quais ficam ligados (primeiro o DESFAZER[<modo>] do ligar-fase7e.sql); o 4 do dono fica',
                         pg_temp.modos() = 'desligado ligado desligado desligado ligado desligado' and v_dt.ficam_ligados = 'modo_folga_semana, modo_tempo_compra'
                         and (pg_temp.linha() ->> 'fornecedor_n_min')::int = 4, pg_temp.modos() || ' ' || to_jsonb(v_dt)::text);
    -- depois do DESFAZER, a rodada não roda os passos da margem (os 6 desligados)
    update public.agenda_config set modo_folga_semana = 'desligado', modo_tempo_compra = 'desligado', modo_aprendizado = 'ligado' where id;
    set local session_replication_role = replica; delete from public.agenda_vigia_rodadas x where x.rotina = 'aprender' and x.p_hoje = c_hoje; set local session_replication_role = origin;
    v_r := public.agenda_aprender(c_hoje, c_agora);
    v_res := pg_temp.res(v_res, 'D5 depois do DESFAZER a rodada do aprendizado não roda os passos da margem (com os 6 desligados)',
                         (v_r ->> 'rodou')::boolean and not ((v_r -> 'contagens') ?| array['vies', 'folga_semana', 'promessa', 'tempo_compra', 'folga_compra', 'prazo_sem_fornecedor']),
                         left(v_r::text, 900));
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
