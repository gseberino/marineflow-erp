-- Prova da migration de dado da Fase 4 da Agenda de Produção (pacote P6; 20261027101000_agenda_fase4_sombra.sql), que a
-- bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a carteira de sex 30/10
-- (fixture-fase4.sql: o painel do Nelson comprado com a previsão e o original de qua 04/11).
-- bancada: depende de 20261027100600
--
--   S  os modos: desligado → sombra (material, detector, fornecedor); o resto da linha igual; de novo não muda nada (nem a
--      hora); ligado nunca é rebaixado; os três ligados = nada muda
--   O  o original herdado: a linha com previsão e sem original (gravada antes do gatilho do original) ganha o original = a
--      previsão de agora, a fonte pela regra do gatilho, o dia nulo e a marca; a que já tem original não muda; a previsão,
--      a situação e a fonte da linha não mudam; depois, agenda_saude().material.previsao_sem_original = 0; de novo não
--      muda nada
--   N  nada sai nem muda fora disso: a fila do WhatsApp, as mensagens ao fornecedor, as remessas, os sinais, as ações e as
--      perguntas iguais
--   D  o DESFAZER do cabeçalho: os três modos de volta a desligado e o original herdado tirado só das linhas marcadas
--      (nada apagado; o original de verdade fica); é UM comando (um bloco do $desfaz$): linha por linha, o update do
--      original sem a chave local é revertido calado pelo gatilho (revisão C2, R7)
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é o
--   supabase/tests/agenda_fase4_pos_deploy.sql (só leitura). Termina em ROLLBACK.
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
-- A linha de agenda_config sem os modos da Fase 4 e sem o carimbo (o que a migration não pode mexer).
create function pg_temp.resto_da_config() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_material' - 'modo_detector' - 'modo_fornecedor' - 'atualizado_em' - 'atualizado_por'
    from public.agenda_config c
$f$;
create function pg_temp.modos() returns text language sql stable as $f$
  select c.modo_material || '/' || c.modo_detector || '/' || c.modo_fornecedor from public.agenda_config c
$f$;
-- O que não pode mudar: o que sai, o que a sombra grava e as linhas de material fora dos campos do original.
create function pg_temp.contagens() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'fila', (select count(*) from public.whatsapp_send_queue),
    'mensagens', (select count(*) from public.agenda_fornecedor_mensagens),
    'remessas', (select count(*) from public.material_remessas),
    'sinais', (select count(*) from public.material_sinais),
    'acoes', (select count(*) from public.agenda_acoes),
    'perguntas', (select count(*) from public.agenda_perguntas),
    'material', (select md5(string_agg((to_jsonb(m) - 'previsao_original' - 'previsao_original_fonte' - 'previsao_original_em'
                                         - 'evidencia' - 'atualizado_em')::text, '|' order by m.id))
                   from public.os_material m))
$f$;
-- A linha "antiga" (gravada antes do gatilho do original): a previsão sem o original, com o gatilho desligado só aqui.
create function pg_temp.linha_antiga(p_parte uuid, p_prev date, p_fonte text) returns void language plpgsql as $f$
begin
  alter table public.os_material disable trigger os_material_previsao_original;
  update public.os_material
     set situacao = 'a_caminho', previsao_ate = p_prev, previsao_fonte = p_fonte, previsao_original = null,
         previsao_original_fonte = null, previsao_original_em = null
   where service_order_part_id = p_parte;
  alter table public.os_material enable trigger os_material_previsao_original;
end $f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_sombra_fase4', true);
  v_res    jsonb := '[]'::jsonb;
  v_resto  jsonb;
  v_cont   jsonb;
  v_linha  jsonb;
  v_m      jsonb;
  v_desf   text;
  v_bloco  text;
  c_kit    constant uuid := md5('peca:112:1')::uuid;      -- KIT do Nelson (a linha antiga do teste)
  c_painel constant uuid := md5('peca:112:4')::uuid;      -- Painel do Nelson (o original de verdade, qua 04/11)
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.fase4', true), '') = '' then
    insert into _resultado values ('S0 a migration 20261027101000 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase4 ou agenda_teste.fase4 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  -- O DESFAZER do cabeçalho: as linhas de SQL ("--   …") entre "-- DESFAZER" e a linha "--" que fecha o bloco.
  v_bloco := substr(v_mig, position(E'\n-- DESFAZER' in v_mig) + 1);
  v_bloco := left(v_bloco, position(E'\n--\n' in v_bloco));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into v_desf
    from regexp_split_to_table(v_bloco, E'\n') with ordinality t(l, n)
   where t.l like '--   %';

  execute current_setting('agenda_teste.fase4');

  -- ── S e O: a 1ª vez, a 2ª vez, o ligado ─────────────────────────────────────────────────────────────────
  begin
    update public.agenda_config set modo_material = 'desligado', modo_detector = 'desligado', modo_fornecedor = 'desligado',
                                    atualizado_em = timestamptz '2026-10-30 12:00-03' where id;
    perform pg_temp.linha_antiga(c_kit, date '2026-11-05', 'dono');
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    v_res := pg_temp.res(v_res, 'O0 antes: 1 linha com previsão e sem original (a saúde conta 1)',
      (select count(*) from public.os_material where previsao_ate is not null and previsao_original is null) = 1
      and (public.agenda_saude(date '2026-10-30', timestamptz '2026-10-30 12:00-03') #>> '{material,previsao_sem_original}')::int = 1, null);

    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S1 desligado → sombra: modo_material, modo_detector e modo_fornecedor',
      pg_temp.modos() = 'sombra/sombra/sombra', v_linha::text);
    v_res := pg_temp.res(v_res, 'S2 o resto da linha não muda (leitura, proposta, vigia, equipe, diária, cliente, os números); atualizado_por nulo',
      pg_temp.resto_da_config() = v_resto and v_linha ->> 'atualizado_por' is null, pg_temp.resto_da_config()::text);
    v_m := (select to_jsonb(m) from public.os_material m where m.service_order_part_id = c_kit);
    v_res := pg_temp.res(v_res, 'O1 a linha antiga ganha o original = a previsão de agora (qui 05/11), a fonte dela (dono), o dia nulo e a marca',
      v_m ->> 'previsao_original' = '2026-11-05' and v_m ->> 'previsao_original_fonte' = 'dono'
      and v_m ->> 'previsao_original_em' is null and v_m #>> '{evidencia,original_herdado}' = '20261027101000'
      and v_m ->> 'previsao_ate' = '2026-11-05' and v_m ->> 'situacao' = 'a_caminho' and v_m ->> 'previsao_fonte' = 'dono', v_m::text);
    v_m := (select to_jsonb(m) from public.os_material m where m.service_order_part_id = c_painel);
    v_res := pg_temp.res(v_res, 'O2 a linha que já tinha original (o painel: qua 04/11, de 15/10) não muda e não ganha a marca',
      v_m ->> 'previsao_original' = '2026-11-04' and v_m ->> 'previsao_original_em' = '2026-10-15'
      and not (v_m -> 'evidencia') ? 'original_herdado', v_m::text);
    v_res := pg_temp.res(v_res, 'O3 depois: nenhuma linha com previsão sem original; a saúde conta 0',
      (select count(*) from public.os_material where previsao_ate is not null and previsao_original is null) = 0
      and (public.agenda_saude(date '2026-10-30', timestamptz '2026-10-30 12:00-03') #>> '{material,previsao_sem_original}')::int = 0, null);
    v_res := pg_temp.res(v_res, 'N1 nada sai nem muda fora disso: a fila, as mensagens ao fornecedor, as remessas, os sinais, as ações, as perguntas e o material (fora o original) iguais',
      pg_temp.contagens() = v_cont, pg_temp.contagens()::text);

    v_linha := (select to_jsonb(c) from public.agenda_config c)
               || jsonb_build_object('material', (select jsonb_agg(to_jsonb(m) order by m.id) from public.os_material m));
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S3 idempotente: a 2ª vez não muda nada (nem a hora, nem o original, nem a marca)',
      (select to_jsonb(c) from public.agenda_config c)
      || jsonb_build_object('material', (select jsonb_agg(to_jsonb(m) order by m.id) from public.os_material m)) = v_linha, null);

    update public.agenda_config set modo_material = 'ligado', modo_detector = 'desligado', modo_fornecedor = 'sombra' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 nunca rebaixa ligado (o material ligado fica; o detector desligado vai a sombra; o fornecedor em sombra fica)',
      pg_temp.modos() = 'ligado/sombra/sombra', pg_temp.modos());
    update public.agenda_config set modo_material = 'ligado', modo_detector = 'ligado', modo_fornecedor = 'ligado',
                                    atualizado_em = timestamptz '2026-10-30 12:00-03' where id;
    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S5 os três ligados: nada muda (nem a hora)',
      pg_temp.modos() = 'ligado/ligado/ligado'
      and (v_linha ->> 'atualizado_em')::timestamptz = timestamptz '2026-10-30 12:00-03', v_linha::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D: o DESFAZER do cabeçalho ─────────────────────────────────────────────────────────────────────────
  begin
    v_res := pg_temp.res(v_res, 'D0 o cabeçalho tem o DESFAZER: dois UPDATE e a chave local do desfazer ligada e desligada, nenhum DELETE',
      v_desf is not null and (length(v_desf) - length(replace(v_desf, 'update public.', ''))) / length('update public.') = 2
      and (length(v_desf) - length(replace(v_desf, 'set_config(''agenda.desfazer_material''', '')))
          / length('set_config(''agenda.desfazer_material''') = 2
      and position('delete' in lower(v_desf)) = 0, coalesce(v_desf, '(sem o bloco)'));
    update public.agenda_config set modo_material = 'desligado', modo_detector = 'desligado', modo_fornecedor = 'desligado' where id;
    perform pg_temp.linha_antiga(c_kit, date '2026-11-05', 'dono');
    execute v_mig;
    v_cont := pg_temp.contagens();
    execute v_desf;
    v_m := (select to_jsonb(m) from public.os_material m where m.service_order_part_id = c_kit);
    v_res := pg_temp.res(v_res, 'D1 o DESFAZER volta os três modos a desligado e tira o original herdado só da linha marcada (o painel fica com o dele)',
      pg_temp.modos() = 'desligado/desligado/desligado'
      and v_m ->> 'previsao_original' is null and v_m ->> 'previsao_original_fonte' is null
      and not (v_m -> 'evidencia') ? 'original_herdado' and v_m ->> 'previsao_ate' = '2026-11-05'
      and (select previsao_original = date '2026-11-04' from public.os_material where service_order_part_id = c_painel)
      and coalesce(current_setting('agenda.desfazer_material', true), '') = ''
      and pg_temp.contagens() = v_cont, concat_ws(' | ', pg_temp.modos(), v_m));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D2: por que um bloco só — o update do original rodado sozinho (sem a chave local) ───────────────────────
  begin
    update public.agenda_config set modo_material = 'desligado', modo_detector = 'desligado', modo_fornecedor = 'desligado' where id;
    perform pg_temp.linha_antiga(c_kit, date '2026-11-05', 'dono');
    execute v_mig;
    update public.os_material set previsao_original = null, previsao_original_fonte = null, evidencia = evidencia - 'original_herdado'
     where evidencia ->> 'original_herdado' = '20261027101000' and previsao_original_em is null;
    v_m := (select to_jsonb(m) from public.os_material m where m.service_order_part_id = c_kit);
    v_res := pg_temp.res(v_res, 'D2 linha por linha não serve: sem a chave local, o original fica e a marca some (o gatilho); o DESFAZER é um bloco só (do $desfaz$ … $desfaz$;)',
      v_m ->> 'previsao_original' = '2026-11-05' and not (v_m -> 'evidencia') ? 'original_herdado'
      and v_desf ~ '^\s*do \$desfaz\$' and v_desf ~ '\$desfaz\$;\s*$'
      and (length(v_desf) - length(replace(v_desf, '$desfaz$', ''))) / length('$desfaz$') = 2,
      concat_ws(' | ', v_m, v_desf));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
