-- Prova da migration de dado da Fase 7b da Agenda de Produção (pacotes P5 e DADO; 20261101100900_agenda_fase7b_sombra.sql), que a
-- bancada NÃO aplica (FORA_DA_BANCADA): aqui ela roda como está, numa subtransação desfeita, sobre a equipe de verdade de 30/10 (a
-- fixture da 7b).
-- bancada: depende de 20261101100500
--
--   S  os 5 modos da 7b: desligado → sombra (dias, dupla, sabado, cadastro, chamar); o resto da linha igual (os modos das Fases 1–6 e da
--      7a, os números); de novo não muda nada (nem a hora); ligado nunca é rebaixado
--   N  nada muda fora disso: alocações, propostas, ações, perguntas, mensagens, a fila, a disponibilidade e o planejamento iguais; e em
--      sombra o cartão do Lenine diz "Em teste: eu marcaria …" e a saúde dos dias tem os zeros em 0. N3: sobre o estado de produção (o
--      gestor da 7a em teste, nunca ligado), a rodada da semana da equipe (qui 16:45) e a do gestor (16:53) depois do dado não gravam
--      alocação, proposta, ação, mensagem ao cliente, disponibilidade nem fila; a pergunta da semana ao Rafael fica só registrada
--      (sombra); as perguntas novas (a chamada e o contato) nascem em teste; o passo equipe da 7a cede ({pulado: modo_cadastro}); o
--      passo dupla só conta; o chamar faz a conta em teste e só o foco a mostra ("Em teste: quem chamar")
--   D  o DESFAZER do cabeçalho: um comando só (with … select), dois UPDATE (agenda_config e os_planejamento), nenhum DELETE; volta a
--      sombra a desligado e não mexe no ligado; com o modo_dupla saindo de teste, a dupla dita no início ou no fim vira "o tempo todo"
--      (com o motivo e o histórico) e o resultado lista as OS; com o modo_dupla ligado, a dita fica; com tudo desligado e nada em
--      parte, nada muda; com o modo_dupla já desligado e uma dita no início (o que um desligar à mão deixaria), ela também vira "o
--      tempo todo" (D5)
--   U  o DESLIGAR SÓ A DUPLA do cabeçalho (§10 "um comportamento", R4.3(b)): um comando só, dois UPDATE, nenhum DELETE, e em
--      agenda_config só o modo_dupla; de ligado e de teste, o modo_dupla vai a desligado, os outros 4 e o resto da linha ficam, a dita
--      no início e no fim vira "o tempo todo" (o motivo, o histórico), a "o tempo todo" e a "não" ficam, o resultado diz o modo de
--      antes e lista as OS; o porquê: com só o Alex e o gestor ligado, o Lenine dito no início espera a 2ª pessoa (classe 4 dupla)
--      depois do comando, e só desligar o modo o deixaria ir com 1 pessoa (classe 2); com o modo já desligado e nada em parte (e de
--      novo), nada muda (nem a hora)
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
-- Um bloco de SQL do cabeçalho da migration: as linhas "--   …" depois da linha que começa com p_titulo, até a linha "--" que fecha.
create function pg_temp.bloco(p_mig text, p_titulo text) returns text language plpgsql immutable as $f$
declare
  v text;
  r text;
begin
  if position(E'\n' || p_titulo in p_mig) = 0 then return null; end if;
  v := substr(p_mig, position(E'\n' || p_titulo in p_mig) + 1);
  v := left(v, position(E'\n--\n' in v));
  select string_agg(substr(t.l, 3), E'\n' order by t.n) into r
    from regexp_split_to_table(v, E'\n') with ordinality t(l, n)
   where t.l like '--   %';
  return r;
end $f$;
-- O gestor da 7a ligado (a regra uma_pessoa vale fora da simulação) e só o Alex na grade (o Rafael e o Bruno fora, como em produção).
create function pg_temp.gestor_ligado_so_alex() returns void language sql as $f$
  update public.agenda_config
     set modo_marcar_sozinho = 'ligado', modo_encaixe_aprovacao = 'ligado', modo_revisao_diaria = 'ligado', modo_compre_ate = 'ligado',
         modo_vaga_fechamento = 'ligado', gestor_so_propor = false, gestor_so_propor_em = null,
         marcar_sozinho_desde = timestamptz '2026-10-29 16:46-03'
   where id;
  update public.agenda_disponibilidade set substituida_em = timestamptz '2026-11-05 10:00-03'
   where substituida_em is null and payee_id in (select id from public.payees where name in ('Rafael', 'Bruno'));
$f$;

do $s$
declare
  v_mig    text := current_setting('agenda_teste.mig_sombra_fase7b', true);
  v_res    jsonb := '[]'::jsonb;
  v_resto  jsonb;
  v_cont   jsonb;
  v_linha  jsonb;
  v_desf   text;
  v_desl   text;
  v_len    uuid;
  v_van    uuid;
  v_k33    uuid;
  v_fla    uuid;
  v_lista  record;
  v_q0     uuid[];
  v_m0     uuid[];
  v_e      jsonb;
  v_g      jsonb;
  v_foco   text;
  v_livre  text;
  v_mot    jsonb;
  v_dia    jsonb;
  v_nq     text;
  v_nm     text;
  v_cl     text;
  v_cl2    text;
  r        jsonb;
  p        record;
begin
  if coalesce(v_mig, '') = '' or coalesce(current_setting('agenda_teste.fase7b', true), '') = '' then
    insert into _resultado values ('S0 a migration 20261101100900 como texto', true,
      'PULADO: sem agenda_teste.mig_sombra_fase7b ou agenda_teste.fase7b (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  -- O DESFAZER e o DESLIGAR SÓ A DUPLA do cabeçalho.
  v_desf := pg_temp.bloco(v_mig, '-- DESFAZER');
  v_desl := pg_temp.bloco(v_mig, '-- DESLIGAR SÓ A DUPLA');

  execute current_setting('agenda_teste.fase7b');
  insert into public.os_planejamento (service_order_id, dono_presenca)
  select so.id, 'abre_e_fecha' from public.service_orders so where so.service_order_number in ('OS-00074', 'OS-00069')
  on conflict (service_order_id) do update set dono_presenca = 'abre_e_fecha';
  select so.id into v_len from public.service_orders so where so.service_order_number = 'OS-00074';
  select so.id into v_van from public.service_orders so where so.service_order_number = 'OS-00069';
  select so.id into v_k33 from public.service_orders so where so.service_order_number = 'OS-00033';
  select so.id into v_fla from public.service_orders so where so.service_order_number = 'OS-00104';

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

  -- ── N3: o dado sobre o estado de produção (o gestor da 7a em teste, nunca ligado) e as rodadas da quinta ─────────────
  begin
    update public.agenda_config
       set modo_marcar_sozinho = 'sombra', modo_vaga_fechamento = 'sombra', modo_encaixe_aprovacao = 'sombra',
           modo_revisao_diaria = 'sombra', modo_compre_ate = 'sombra', marcar_sozinho_desde = null, gestor_so_propor = false,
           modo_dias = 'desligado', modo_dupla = 'desligado', modo_sabado = 'desligado', modo_cadastro = 'desligado',
           modo_chamar = 'desligado'
     where id;
    v_cont := pg_temp.contagens();
    select coalesce(array_agg(q.id), '{}') into v_q0 from public.agenda_perguntas q;
    select coalesce(array_agg(m.id), '{}') into v_m0 from public.agenda_equipe_mensagens m;
    execute v_mig;
    v_e := public.agenda_equipe_semana(date '2026-11-05', (timestamp '2026-11-05 16:45') at time zone 'America/Sao_Paulo');
    v_g := public.agenda_gestor_rodar(date '2026-11-05', (timestamp '2026-11-05 16:53') at time zone 'America/Sao_Paulo');
    select d.chamar into v_dia from public.agenda_gestor_dia d where d.dia = date '2026-11-05';
    -- o *livre* e os motivos da pergunta da quinta (a semana de 16/11) antes de mexer no texto_max
    v_livre := public.agenda_livre_de_verdade(date '2026-11-05', (timestamp '2026-11-05 17:00') at time zone 'America/Sao_Paulo') ->> 'texto_completo';
    v_mot := public._agenda_dias_semana_motivos(date '2026-11-16', date '2026-11-05') -> 'motivos';
    -- o foco inteiro: a carteira da fixture enche o foco e o corte do texto_max (no meio) esconderia o bloco; só para ler
    update public.agenda_config set texto_max = 3000 where id;
    v_foco := public._agenda_ver_gestor(date '2026-11-05') ->> 'texto';
    select string_agg(format('%s %s %s', q.tipo, q.modo, split_part(q.chave, ':', 2)), '; ' order by q.chave) into v_nq
      from public.agenda_perguntas q where not (q.id = any (v_q0));
    select string_agg(format('%s %s %s %s', py.name, m.tipo, m.modo, m.estado), '; ' order by py.name, m.tipo) into v_nm
      from public.agenda_equipe_mensagens m join public.payees py on py.id = m.payee_id where not (m.id = any (v_m0));
    v_res := pg_temp.res(v_res, 'N3a sobre o estado de produção, depois do dado, a rodada da semana da equipe (qui 16:45) e a do gestor (16:53) não gravam alocação, proposta, ação, mensagem ao cliente, disponibilidade, planejamento nem fila',
      coalesce((v_e ->> 'rodou')::boolean, false) and coalesce((v_g ->> 'rodou')::boolean, false) and coalesce((v_g ->> 'diaria')::boolean, false)
      and pg_temp.contagens() - 'perguntas' - 'equipe' = v_cont - 'perguntas' - 'equipe',
      concat_ws(' | ', pg_temp.contagens()::text, left((v_e - 'contagens')::text, 300), left((v_g - 'contagens')::text, 300)));
    v_res := pg_temp.res(v_res, 'N3b nada sai à equipe: a pergunta da semana ao Rafael fica só registrada (sombra); as perguntas novas ao dono (a chamada da equipe e o contato do Bruno) nascem em teste',
      v_nm = 'Rafael dias sombra registrada'
      and v_nq = 'equipe_cadastro sombra chamada; equipe_cadastro sombra contato',
      concat_ws(' | ', v_nm, v_nq));
    v_res := pg_temp.res(v_res, 'N3c na rodada do gestor, o passo equipe da 7a cede à chamada da 7b ({pulado: modo_cadastro}), o passo dupla só conta (em teste) e o chamar faz a conta em teste; só o foco *agenda gestor* a mostra ("Em teste: quem chamar …"): nem o *livre* nem a pergunta da quinta',
      v_g #>> '{contagens,equipe,pulado}' = 'modo_cadastro'
      and coalesce((v_g #>> '{contagens,dupla,pulado}')::boolean, false) and coalesce((v_g #>> '{contagens,dupla,em_teste}')::boolean, false)
      and v_g #>> '{contagens,chamar,modo}' = 'sombra' and v_dia ->> 'modo' = 'sombra'
      and v_dia ->> 'texto' like 'Quem chamar (só sugiro; quem chama é você):%'
      and position('Em teste: quem chamar (só sugiro; quem chama é você):' in coalesce(v_foco, '')) > 0
      and position('Sem lugar com a equipe de hoje' in coalesce(v_livre, '')) = 0
      and not coalesce(v_mot, '[]'::jsonb) ? 'chamar',
      concat_ws(' | ', v_g #>> '{contagens,equipe}', v_g #>> '{contagens,dupla}', v_g #>> '{contagens,chamar}', v_dia ->> 'modo',
                v_mot::text, right(v_livre, 300), v_foco));
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
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    update public.agenda_config set modo_dias = 'desligado', modo_dupla = 'desligado', modo_sabado = 'desligado', modo_cadastro = 'desligado',
                                    modo_chamar = 'desligado', atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_cont := pg_temp.contagens();
    execute v_desf into v_lista;
    v_res := pg_temp.res(v_res, 'D4 o DESFAZER com tudo desligado e nenhuma dita em parte do serviço não muda nada (nem a hora)',
      (select to_jsonb(c) from public.agenda_config c) = v_linha and pg_temp.contagens() = v_cont
      and v_lista.modos_desligados = 0 and v_lista.dupla_passou_a_todos = 'nenhuma',
      (select to_jsonb(c) from public.agenda_config c)::text);
    -- D5: o modo_dupla já desligado (um desligar à mão, sem o comando) com a dita no início que ficou
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2, dupla_em = timestamptz '2026-11-05 10:00-03' where service_order_id = v_len;
    execute v_desf into v_lista;
    select pl.dupla_dita, pl.dupla_meios, pl.dupla_motivo into p from public.os_planejamento pl where pl.service_order_id = v_len;
    v_res := pg_temp.res(v_res, 'D5 com o modo_dupla já desligado e a dita no início que ficou (um desligar à mão), o DESFAZER também a passa a o tempo todo e lista a OS; a linha da config não muda',
      p.dupla_dita = 'todos' and p.dupla_meios is null and p.dupla_motivo = 'dupla em parte do serviço desligada: vai em dupla o tempo todo'
      and v_lista.modos_desligados = 0 and v_lista.dupla_passou_a_todos = 'OS-00074'
      and (select to_jsonb(c) from public.agenda_config c) = v_linha,
      concat_ws(' | ', p.dupla_dita, p.dupla_meios, p.dupla_motivo, v_lista.dupla_passou_a_todos));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── U: o DESLIGAR SÓ A DUPLA do cabeçalho ────────────────────────────────────────────────────────────────
  v_res := pg_temp.res(v_res, 'U0 o cabeçalho tem o DESLIGAR SÓ A DUPLA num comando só (with … select … ;): dois UPDATE, nenhum DELETE, e em agenda_config só o modo_dupla (e o carimbo)',
    v_desl is not null and v_desl ~ '^\s*with antes as \(' and v_desl ~ ';\s*$'
    and (length(v_desl) - length(replace(v_desl, ';', ''))) = 1
    and (length(v_desl) - length(replace(v_desl, 'update public.', ''))) / length('update public.') = 2
    and position('update public.agenda_config set modo_dupla = ''desligado'', atualizado_em = now(), atualizado_por = null where id and modo_dupla <> ''desligado''' in v_desl) > 0
    and position('update public.os_planejamento' in v_desl) > 0
    and position('delete' in lower(v_desl)) = 0, coalesce(v_desl, '(sem o bloco)'));
  begin
    perform pg_temp.gestor_ligado_so_alex();
    update public.agenda_config set modo_dias = 'sombra', modo_dupla = 'ligado', modo_sabado = 'sombra', modo_cadastro = 'ligado',
                                    modo_chamar = 'ligado' where id;
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2, dupla_em = timestamptz '2026-11-05 10:00-03' where service_order_id = v_len;
    update public.os_planejamento set dupla_dita = 'fim', dupla_meios = 1, dupla_em = timestamptz '2026-11-05 10:00-03' where service_order_id = v_van;
    insert into public.os_planejamento (service_order_id, dupla_dita, dupla_em) values (v_k33, 'todos', timestamptz '2026-11-05 10:00-03')
    on conflict (service_order_id) do update set dupla_dita = 'todos', dupla_meios = null;
    insert into public.os_planejamento (service_order_id, dupla_dita, dupla_em) values (v_fla, 'nao', timestamptz '2026-11-05 10:00-03')
    on conflict (service_order_id) do update set dupla_dita = 'nao', dupla_meios = null;
    v_resto := pg_temp.resto_da_config();
    v_cont := pg_temp.contagens();
    execute v_desl into v_lista;
    select pl.dupla_dita, pl.dupla_meios, pl.dupla_motivo, pl.historico -> -1 as h into p from public.os_planejamento pl where pl.service_order_id = v_len;
    v_res := pg_temp.res(v_res, 'U1 de ligado: o modo_dupla vai a desligado e os outros 4 e o resto da linha ficam (atualizado_por nulo); o plano, as mensagens e a disponibilidade ficam; o resultado diz o modo de antes',
      pg_temp.modos() = 'sombra desligado sombra ligado ligado' and pg_temp.resto_da_config() = v_resto
      and (select atualizado_por from public.agenda_config) is null and pg_temp.contagens() - 'plano' = v_cont - 'plano'
      and v_lista.modo_dupla_antes = 'ligado' and v_lista.desligou = 1,
      concat_ws(' | ', pg_temp.modos(), v_lista.modo_dupla_antes, v_lista.desligou));
    v_res := pg_temp.res(v_res, 'U2 na mesma transação, a dita no início e no fim vira o tempo todo (sem os meios-dias, com o motivo e o antes no histórico); a o tempo todo e a "não" ficam; o resultado lista as OS',
      p.dupla_dita = 'todos' and p.dupla_meios is null
      and p.dupla_motivo = 'dupla em parte do serviço desligada: vai em dupla o tempo todo'
      and p.h -> 'antes' = '{"dupla": "inicio", "dupla_meios": 2}'::jsonb and p.h -> 'depois' = '{"dupla": "todos"}'::jsonb
      and p.h ->> 'trecho' like 'DESLIGAR SÓ A DUPLA (20261101100900)%'
      and (select dupla_dita = 'todos' and dupla_meios is null from public.os_planejamento where service_order_id = v_van)
      and (select dupla_dita = 'todos' and dupla_motivo is null from public.os_planejamento where service_order_id = v_k33)
      and (select dupla_dita = 'nao' and dupla_motivo is null from public.os_planejamento where service_order_id = v_fla)
      and v_lista.dupla_passou_a_todos = 'OS-00069, OS-00074',
      concat_ws(' | ', p.dupla_dita, p.dupla_meios, p.dupla_motivo, p.h::text, v_lista.dupla_passou_a_todos));
    v_cl := (select (x ->> 'classe') || ' ' || coalesce(x ->> 'motivo', '-') from public._agenda_classe_agora(v_len, date '2026-11-05') x);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o mesmo, só desligando o modo (sem o comando): a dita no início fica, e a 7a não a vê
    perform pg_temp.gestor_ligado_so_alex();
    update public.agenda_config set modo_dias = 'sombra', modo_dupla = 'ligado', modo_sabado = 'sombra', modo_cadastro = 'ligado',
                                    modo_chamar = 'ligado' where id;
    update public.os_planejamento set dupla_dita = 'inicio', dupla_meios = 2, dupla_em = timestamptz '2026-11-05 10:00-03' where service_order_id = v_len;
    update public.agenda_config set modo_dupla = 'desligado' where id;
    v_cl2 := (select (x ->> 'classe') || ' ' || coalesce(x ->> 'motivo', '-') from public._agenda_classe_agora(v_len, date '2026-11-05') x);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  v_res := pg_temp.res(v_res, 'U3 o porquê: com só o Alex e o gestor ligado, depois do comando o Lenine (dito no início) espera a 2ª pessoa (classe 4 dupla); só desligar o modo o deixaria ir com 1 pessoa (classe 2 pronta)',
    v_cl = '4 dupla' and v_cl2 = '2 pronta', concat_ws(' | ', v_cl, v_cl2));
  begin
    update public.agenda_config set modo_dias = 'sombra', modo_dupla = 'sombra', modo_sabado = 'sombra', modo_cadastro = 'sombra',
                                    modo_chamar = 'sombra' where id;
    update public.os_planejamento set dupla_dita = 'fim', dupla_meios = 2, dupla_em = timestamptz '2026-11-05 10:00-03' where service_order_id = v_len;
    execute v_desl into v_lista;
    v_res := pg_temp.res(v_res, 'U4 de teste: o modo_dupla vai a desligado, os outros 4 ficam em teste, e a dita no fim vira o tempo todo',
      pg_temp.modos() = 'sombra desligado sombra sombra sombra' and v_lista.modo_dupla_antes = 'sombra' and v_lista.desligou = 1
      and (select dupla_dita = 'todos' and dupla_meios is null from public.os_planejamento where service_order_id = v_len)
      and v_lista.dupla_passou_a_todos = 'OS-00074',
      concat_ws(' | ', pg_temp.modos(), v_lista.modo_dupla_antes, v_lista.dupla_passou_a_todos));
    update public.agenda_config set atualizado_em = timestamptz '2026-11-01 12:00-03' where id;
    v_linha := (select to_jsonb(c) from public.agenda_config c);
    v_cont := pg_temp.contagens();
    execute v_desl into v_lista;
    v_res := pg_temp.res(v_res, 'U5 de novo (o modo já desligado, nada em parte do serviço): nada muda (nem a hora), desligou 0 e nenhuma OS',
      (select to_jsonb(c) from public.agenda_config c) = v_linha and pg_temp.contagens() = v_cont
      and v_lista.modo_dupla_antes = 'desligado' and v_lista.desligou = 0 and v_lista.dupla_passou_a_todos = 'nenhuma',
      concat_ws(' | ', (select to_jsonb(c) from public.agenda_config c)::text, v_lista.dupla_passou_a_todos));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(v_res) e;
end
$s$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
