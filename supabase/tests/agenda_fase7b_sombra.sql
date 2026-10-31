-- Prova da migration de dado da Fase 7b da Agenda de Produção (pacote P5; 20261101100900_agenda_fase7b_sombra.sql), que a bancada NÃO
-- aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a equipe de verdade de 30/10 (a fixture da 7b).
-- bancada: depende de 20261101100400
--
--   S  os 5 modos da 7b: desligado → sombra (dias, dupla, sabado, cadastro, chamar); o resto da linha igual (os modos das Fases 1–6 e da
--      7a, os números); de novo não muda nada (nem a hora); ligado nunca é rebaixado
--   N  nada muda fora disso: alocações, propostas, ações, perguntas, mensagens, a fila, a disponibilidade e o planejamento iguais; e em
--      sombra o cartão do Lenine diz "Em teste: eu marcaria …" e a saúde dos dias tem os zeros em 0
--   D  o DESFAZER do cabeçalho: um comando só (with … select), dois UPDATE (agenda_config e os_planejamento), nenhum DELETE; volta a
--      sombra a desligado e não mexe no ligado; com o modo_dupla saindo de teste, a dupla dita no início ou no fim vira "o tempo todo"
--      (com o motivo e o histórico) e o resultado lista as OS; com o modo_dupla ligado, a dita fica
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Fora da bancada não há a migration como texto: PULADO. NUNCA rodar em produção como prova do dado: lá a prova é o pós-deploy
--   (supabase/tests/agenda_fase7b_pos_deploy.sql, só leitura). Termina em ROLLBACK.
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
-- A linha de agenda_config sem os 5 modos da 7b e o carimbo (o que a migration não pode mexer).
create function pg_temp.resto_da_config() returns jsonb language sql stable as $f$
  select to_jsonb(c) - 'modo_dias' - 'modo_dupla' - 'modo_sabado' - 'modo_cadastro' - 'modo_chamar' - 'atualizado_em' - 'atualizado_por'
    from public.agenda_config c
$f$;
create function pg_temp.modos() returns text language sql stable as $f$
  select concat_ws(' ', c.modo_dias, c.modo_dupla, c.modo_sabado, c.modo_cadastro, c.modo_chamar) from public.agenda_config c
$f$;
-- O que não pode mudar: o plano, as propostas, as ações, as perguntas, as mensagens, a fila, a disponibilidade e o planejamento.
create function pg_temp.contagens() returns jsonb language sql stable as $f$
  select jsonb_build_object(
    'alocacoes', (select md5(coalesce(string_agg(to_jsonb(a)::text, '|' order by a.id), '')) from public.agenda_alocacoes a),
    'propostas', (select count(*) from public.agenda_propostas),
    'acoes', (select count(*) from public.agenda_acoes),
    'perguntas', (select count(*) from public.agenda_perguntas),
    'equipe', (select count(*) from public.agenda_equipe_mensagens),
    'cliente', (select count(*) from public.agenda_cliente_mensagens),
    'fila', (select count(*) from public.whatsapp_send_queue),
    'disponibilidade', (select md5(coalesce(string_agg(to_jsonb(d)::text, '|' order by d.id), '')) from public.agenda_disponibilidade d),
    'plano', (select md5(coalesce(string_agg(to_jsonb(p)::text, '|' order by p.service_order_id), '')) from public.os_planejamento p))
$f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_sombra_fase7b', true);
  v_res    jsonb := '[]'::jsonb;
  v_resto  jsonb;
  v_cont   jsonb;
  v_linha  jsonb;
  v_desf   text;
  v_bloco  text;
  v_len    uuid;
  v_van    uuid;
  v_k33    uuid;
  v_lista  record;
  r        jsonb;
  p        record;
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    insert into _resultado values ('S0 a migration 20261101100900 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase7b ou agenda_teste.fase7b (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  -- O DESFAZER do cabeçalho: as linhas de SQL ("--   …") entre "-- DESFAZER" e a linha "--" que fecha o bloco.
  v_bloco := substr(v_mig, position(E'\n-- DESFAZER' in v_mig) + 1);
  v_bloco := left(v_bloco, position(E'\n--\n' in v_bloco));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into v_desf
    from regexp_split_to_table(v_bloco, E'\n') with ordinality t(l, n)
   where t.l like '--   %';

  execute current_setting('agenda_teste.fase7b');
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  select so.id into v_len from public.service_orders so where so.service_order_number = 'OS-00074';
  select so.id into v_van from public.service_orders so where so.service_order_number = 'OS-00069';
  select so.id into v_k33 from public.service_orders so where so.service_order_number = 'OS-00033';

  -- ── S: a 1ª vez, a 2ª vez, o ligado ────────────────────────────────────────────────────────────────────────
  begin
    update public.agenda_config
       set modo_dias = 'desligado', modo_dupla = 'desligado', modo_sabado = 'desligado', modo_cadastro = 'desligado',
           modo_chamar = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03'
     where id;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_mig;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_res := pg_temp.res(v_res, 'S1 os 5 modos da 7b de desligado para sombra (dias, dupla, sabado, cadastro, chamar)',
      pg_temp.modos() = 'sombra sombra sombra sombra sombra', pg_temp.modos());
    v_res := pg_temp.res(v_res, 'S2 o resto da linha não muda (os modos das Fases 1–6 e da 7a, os números); atualizado_por nulo e a hora nova',
      pg_temp.resto_da_config() = v_resto and v_linha ->> 'atualizado_por' is null
      and (v_linha ->> 'atualizado_em')::timestamptz <> timestamptz '2026-11-01 12:00-03', pg_temp.resto_da_config()::text);
    v_res := pg_temp.res(v_res, 'N1 nada muda fora disso: o plano, as propostas, as ações, as perguntas, as mensagens, a fila, a disponibilidade e o planejamento iguais',
      pg_temp.contagens() = v_cont, pg_temp.contagens()::text);

    execute v_mig;
    v_res := pg_temp.res(v_res, 'S3 idempotente: a 2ª vez não muda nada (nem a hora)', (select to_jsonb(c) from public.agenda_config c) = v_linha, null);

    -- em sombra: o cartão em teste e os zeros da saúde em 0
    r := public.os_plano_da_os(v_len, date '2026-11-05');
    v_res := pg_temp.res(v_res, 'N2 em sombra o cartão do Lenine diz o que eu marcaria ("Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias …") e a saúde dos dias tem os zeros em 0',
      r #>> '{equipe,texto}' like 'Em teste: eu marcaria 1 pessoa, em dupla nos 2 primeiros meios-dias (troca do banco de baterias).%'
      and (public.agenda_saude(date '2026-11-05', (timestamp '2026-11-05 17:10') at time zone 'America/Sao_Paulo') #>> '{equipe_dias,zeros_ok}')::boolean,
      r #>> '{equipe,texto}');

    update public.agenda_config set modo_dupla = 'ligado', modo_dias = 'ligado', modo_sabado = 'desligado',
                                    atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    execute v_mig;
    v_res := pg_temp.res(v_res, 'S4 nunca rebaixa ligado (a dupla e os dias ligados ficam); só o desligado vai a teste',
      pg_temp.modos() = 'ligado ligado sombra sombra sombra', pg_temp.modos());
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D: o DESFAZER do cabeçalho ─────────────────────────────────────────────────────────────────────────
  v_res := pg_temp.res(v_res, 'D0 o cabeçalho tem o DESFAZER num comando só (with … select … ;): dois UPDATE (agenda_config e os_planejamento), nenhum DELETE',
    v_desf is not null and v_desf ~ '^\s*with antes as \(' and v_desf ~ ';\s*$'
    and (length(v_desf) - length(replace(v_desf, ';', ''))) = 1
    and (length(v_desf) - length(replace(v_desf, 'update public.', ''))) / length('update public.') = 2
    and position('update public.agenda_config' in v_desf) > 0 and position('update public.os_planejamento' in v_desf) > 0
    and position('delete' in lower(v_desf)) = 0, coalesce(v_desf, '(sem o bloco)'));
  begin
    update public.agenda_config
       set modo_dias = 'desligado', modo_dupla = 'desligado', modo_sabado = 'desligado', modo_cadastro = 'desligado', modo_chamar = 'desligado'
     where id;
    execute v_mig;
    -- as ditas: o Lenine no início (2), o Vanderlei no fim (1), a Kalmar-33 o tempo todo (fica)
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2, dupla_em = timestamptz '2026-11-05 10:00-03' where service_order_id = v_len;
    update public.os_planejamento set dupla_dita = 'fim', dupla_meios = 1, dupla_em = timestamptz '2026-11-05 10:00-03' where service_order_id = v_van;
    insert into public.os_planejamento (service_order_id, dupla_dita, dupla_em) values (v_k33, 'todos', timestamptz '2026-11-05 10:00-03')
    on conflict (service_order_id) do update set dupla_dita = 'todos', dupla_meios = null;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_desf into v_lista;
    v_res := pg_temp.res(v_res, 'D1 o DESFAZER volta os 5 de sombra a desligado; o resto da linha, o plano, as mensagens e a disponibilidade ficam; atualizado_por nulo',
      pg_temp.modos() = 'desligado desligado desligado desligado desligado' and pg_temp.resto_da_config() = v_resto
      and pg_temp.contagens() - 'plano' = v_cont - 'plano' and (select atualizado_por from public.agenda_config) is null
      and v_lista.modos_desligados = 1, pg_temp.modos());
    select pl.dupla_dita, pl.dupla_meios, pl.dupla_motivo, pl.historico -> 0 as h into p from public.os_planejamento pl where pl.service_order_id = v_len;
    v_res := pg_temp.res(v_res, 'D2 com o modo_dupla saindo de teste, a dita no início e no fim vira o tempo todo (sem os meios-dias, com o motivo e o antes no histórico); o resultado lista as OS; a dita o tempo todo fica',
      p.dupla_dita = 'todos' and p.dupla_meios is null
      and p.dupla_motivo = 'dupla em parte do serviço desligada: vai em dupla o tempo todo'
      and p.h -> 'antes' = '{"dupla": "inicio", "dupla_meios": 2}'::jsonb and p.h -> 'depois' = '{"dupla": "todos"}'::jsonb
      and (select dupla_dita = 'todos' and dupla_meios is null from public.os_planejamento where service_order_id = v_van)
      and (select dupla_dita = 'todos' and dupla_motivo is null from public.os_planejamento where service_order_id = v_k33)
      and v_lista.dupla_passou_a_todos = 'OS-00069, OS-00074',
      concat_ws(' | ', p.dupla_dita, p.dupla_meios, p.dupla_motivo, p.h::text, v_lista.dupla_passou_a_todos));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set modo_dias = 'sombra', modo_dupla = 'ligado', modo_sabado = 'sombra', modo_cadastro = 'ligado',
                                    modo_chamar = 'sombra' where id;
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2, dupla_em = timestamptz '2026-11-05 10:00-03' where service_order_id = v_len;
    execute v_desf into v_lista;
    v_res := pg_temp.res(v_res, 'D3 o DESFAZER não mexe no que já foi ligado (a dupla e o cadastro ficam ligados) e, com a dupla ligada, a dita no início fica',
      pg_temp.modos() = 'desligado ligado desligado ligado desligado'
      and (select dupla_dita = 'inicio' and dupla_meios = 2 from public.os_planejamento where service_order_id = v_len)
      and v_lista.dupla_passou_a_todos = 'nenhuma', concat_ws(' | ', pg_temp.modos(), v_lista.dupla_passou_a_todos));
    update public.agenda_config set modo_dias = 'desligado', modo_dupla = 'desligado', modo_sabado = 'desligado', modo_cadastro = 'desligado',
                                    modo_chamar = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    execute v_desf into v_lista;
    v_res := pg_temp.res(v_res, 'D4 o DESFAZER com tudo desligado não muda nada (nem a hora)',
      (select to_jsonb(c) from public.agenda_config c) = v_linha and v_lista.modos_desligados = 0 and v_lista.dupla_passou_a_todos = 'nenhuma',
      (select to_jsonb(c) from public.agenda_config c)::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
