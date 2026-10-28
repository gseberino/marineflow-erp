-- Prova da migration de dado da Fase 5 da Agenda de Produção (pacote P6; 20261028101000_agenda_fase5_sombra.sql), que a
-- bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a carteira de sex 30/10
-- (fixture-fase5.sql).
-- bancada: depende de 20261028100600
--
--   S  o modo: desligado (com a lista das ondas vazia) → sombra; a lista fica {}; o resto da linha igual; de novo não muda
--      nada (nem a hora); ligado nunca é rebaixado; o desligado que já teve onda ligada (o dono parou tudo) não volta a teste
--   N  nada sai nem muda fora disso: a fila do WhatsApp, as mensagens ao cliente, as respostas, as ações e as perguntas iguais;
--      e em sombra a rodada do cliente não põe nada na fila agenda-cliente
--   D  o DESFAZER do cabeçalho: um bloco só (do $desfaz$ … $desfaz$;), um UPDATE, nenhum DELETE; volta a sombra a desligado
--      e não mexe no ligado
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é o
--   supabase/tests/agenda_fase5_pos_deploy.sql (só leitura). Termina em ROLLBACK.
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
-- A linha de agenda_config sem o modo do cliente, a lista e o carimbo (o que a migration não pode mexer).
create function pg_temp.resto_da_config() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_cliente' - 'cliente_tipos_ligados' - 'atualizado_em' - 'atualizado_por'
    from public.agenda_config c
$f$;
create function pg_temp.modo() returns text language sql stable as $f$
  select c.modo_cliente || ' ' || c.cliente_tipos_ligados::text from public.agenda_config c
$f$;
-- O que não pode mudar: o que sai e o que a agenda gravou.
create function pg_temp.contagens() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'fila', (select count(*) from public.whatsapp_send_queue),
    'mensagens', (select md5(coalesce(string_agg(to_jsonb(m)::text, '|' order by m.id), '')) from public.agenda_cliente_mensagens m),
    'respostas', (select count(*) from public.agenda_cliente_respostas),
    'acoes', (select count(*) from public.agenda_acoes),
    'perguntas', (select count(*) from public.agenda_perguntas),
    'plano', (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.service_order_id), '')) from public.os_planejamento p))
$f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_sombra_fase5', true);
  v_res    jsonb := '[]'::jsonb;
  v_resto  jsonb;
  v_cont   jsonb;
  v_linha  jsonb;
  v_desf   text;
  v_bloco  text;
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    insert into _resultado values ('S0 a migration 20261028101000 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase5 ou agenda_teste.fase5 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  -- O DESFAZER do cabeçalho: as linhas de SQL ("--   …") entre "-- DESFAZER" e a linha "--" que fecha o bloco.
  v_bloco := substr(v_mig, position(E'\n-- DESFAZER' in v_mig) + 1);
  v_bloco := left(v_bloco, position(E'\n--\n' in v_bloco));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into v_desf
    from regexp_split_to_table(v_bloco, E'\n') with ordinality t(l, n)
   where t.l like '--   %';

  execute current_setting('agenda_teste.fase5');
  perform set_config('agenda_teste.hoje', '2026-10-30', true);

  -- ── S: a 1ª vez, a 2ª vez, o ligado, o desligado com ondas ──────────────────────────────────────────────
  begin
    update public.agenda_config set modo_cliente = 'desligado', cliente_tipos_ligados = '{}',
                                    atualizado_em = timestamptz '2026-10-30 12:00-03' where id;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S1 desligado (a lista vazia) → sombra; a lista das ondas fica {}', pg_temp.modo() = 'sombra {}', pg_temp.modo());
    v_res := pg_temp.res(v_res, 'S2 o resto da linha não muda (leitura, proposta, vigia, equipe, diária, material, detector, fornecedor, os números); atualizado_por nulo e a hora nova',
      pg_temp.resto_da_config() = v_resto and v_linha ->> 'atualizado_por' is null
      and (v_linha ->> 'atualizado_em')::timestamptz <> timestamptz '2026-10-30 12:00-03', pg_temp.resto_da_config()::text);
    v_res := pg_temp.res(v_res, 'N1 nada sai nem muda fora disso: a fila, as mensagens ao cliente, as respostas, as ações, as perguntas e o plano iguais',
      pg_temp.contagens() = v_cont, pg_temp.contagens()::text);

    execute v_mig;
    v_res := pg_temp.res(v_res, 'S3 idempotente: a 2ª vez não muda nada (nem a hora)',
      (select to_jsonb(c) from public.agenda_config c) = v_linha, null);

    -- em sombra a rodada grava o que mandaria e nada vai à fila
    perform public.agenda_cliente_vigiar(date '2026-10-30', (timestamp '2026-10-30 17:00') at time zone 'America/Sao_Paulo');
    v_res := pg_temp.res(v_res, 'N2 em sombra a rodada das 17:00 grava as mensagens em teste e nada entra na fila agenda-cliente',
      exists (select 1 from public.agenda_cliente_mensagens m where m.modo = 'sombra')
      and not exists (select 1 from public.agenda_cliente_mensagens m where m.modo = 'ligado'
                         and m.id <> 'd5000000-0000-4000-8000-0000000000a1')
      and not exists (select 1 from public.whatsapp_send_queue q where q.source = 'agenda-cliente'),
      (select count(*)::text from public.agenda_cliente_mensagens m where m.modo = 'sombra'));

    update public.agenda_config set modo_cliente = 'ligado', cliente_tipos_ligados = array['material_chegou', 'nova_data', 'pode_atrasar'],
                                    atualizado_em = timestamptz '2026-10-30 12:00-03' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 nunca rebaixa ligado (a onda 1 ligada fica, com a lista e a hora)',
      pg_temp.modo() = 'ligado {material_chegou,nova_data,pode_atrasar}'
      and (select atualizado_em from public.agenda_config) = timestamptz '2026-10-30 12:00-03', pg_temp.modo());
    update public.agenda_config set modo_cliente = 'desligado' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S5 o dono parou tudo depois de ligar uma onda (desligado com a lista): a migration não volta a teste calada',
      pg_temp.modo() = 'desligado {material_chegou,nova_data,pode_atrasar}', pg_temp.modo());
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
    update public.agenda_config set modo_cliente = 'desligado', cliente_tipos_ligados = '{}' where id;
    execute v_mig;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_desf;
    v_res := pg_temp.res(v_res, 'D1 o DESFAZER volta a sombra a desligado; o resto da linha e o que foi gravado ficam',
      pg_temp.modo() = 'desligado {}' and pg_temp.resto_da_config() = v_resto and pg_temp.contagens() = v_cont
      and (select atualizado_por from public.agenda_config) is null, pg_temp.modo());
    update public.agenda_config set modo_cliente = 'ligado', cliente_tipos_ligados = array['pronto'] where id;
    execute v_desf;
    v_res := pg_temp.res(v_res, 'D2 o DESFAZER não mexe no que já foi ligado (para isso, o "parar tudo" da §10)',
      pg_temp.modo() = 'ligado {pronto}', pg_temp.modo());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
