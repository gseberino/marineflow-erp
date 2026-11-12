-- Prova das marcações medidas e do tipo de OS em teste, Fase 7g (pacote P5; migration 20261112100400; spec-fase7g §3.1 itens 7 e 8, §5.5, §8.3
-- agenda_fase7g_correcoes.sql e o bloco R9: R9.3-1, R9.4-2, R9.4-4, R9.5-7, 8, 9, 21, R9.12, R9.13 — "K1 sem olhar para trás; K2 com as 4 formas de histórico;
-- K2b repetir os dias; K2b2 dizer o número corrigido; K2c conferida; K2d cliente; K3 só teria; K11 com query_canceled e sem linha ociosa. Saem K4 a K9").
-- bancada: depende de 20261112100400
--
-- O cenário (pg_temp.cenario_k): hoje é qui 19/11/2026, a rodada às 16:40; marcacoes_desde = seg 09/11 00:00; correcao_janela_du = 7 (09/11 + 7 dias úteis =
-- qua 18/11). Cada OS (OS-K<nome>, motorhome) tem a sua pessoa, para os meios-dias não se chocarem. As ações e as alocações vão direto nas tabelas, na forma
-- de produção (ação executada por OS, alocações publicadas com acao_id, duracao_fonte orcamento, criterio unico), com modo_porque desligado (sem o gatilho do
-- porquê): a1, a2 aceitas (a2 com a manhã cumprida); b1 a b5 ajustadas (o dono mexe pela tela, pelo WhatsApp com o degrau pessoa, pelo assistente cancelando,
-- regrava os dias, muda o material; b5 também fixa sem mudar o lugar, o que não conta); c1 desfeita pelo dono; c2 remarcada pela vigia (c2m é a nova, aberta);
-- c3 saiu (os_saiu); c4 aceita pela janela; c5 aberta; c6 remarcada pelo cliente (c6c não entra); c7 desfeita pela vigia (remarcada, não desfeita); d1, d2 do
-- dono; d3 (ação do cliente), d4 (alocação do cliente), d5 (só reserva), d6 (antes de marcacoes_desde) e d7 (depois de agora) não entram; h1 a h12 as formas
-- do histórico de os_planejamento (R9.4-2), a saída do dono (R9.3-1) e as chaves que não são correção.
--
--   K0  o catálogo: as 4 novas (a rodada definer; as 3 de dentro invoker), search_path, volatilidade, as portas (só service_role); a migration só cria as 4
--   K1  o registro: sem marcacoes_desde nada; desligado nada; quem entra e quem não (o cliente, a reserva, antes de marcacoes_desde, depois de agora); a do
--       dono sem desfecho; os campos de uma linha; 2× = 1×
--   K2  o desfecho de cada uma (aceita, ajustada por dia, pessoa, tirou, duração e material, desfeita, remarcada, saiu, aceita pela janela, aberta), as 4
--       formas do histórico (com hora, só o dia, o mesmo dia da marcação, por gestor), K2b (repetir os dias), K2b2 (dizer o número corrigido), K2c conferida,
--       K2d o cliente; a versão e o histórico da marcação
--   K3  o tipo de OS: só teria e texto (sombra e ligado), a amostra, n, corrigidas, aceitas seguidas, a taxa, a trava, 2× = 1×, desligado nada
--   K11 a rodada: desligado, domingo, cedo, já rodou e nada não gravam linha; uma vez por dia; o passo que falha não derruba o outro; query_canceled registra,
--       grava parou_no e encerra; as portas com login
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs
--   Em produção, só DEPOIS de aplicar a migration, com o OK nomeado: npx supabase@2.111.0 db query --linked -f supabase/tests/agenda_fase7g_correcoes.sql
--   Seguro em produção: termina em ROLLBACK. O que usa o cenário ou a migration como texto só roda na bancada (fora dela sai PULADO).
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;
create temp table _k (k text primary key, acao uuid not null) on commit drop;

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
-- Uma consulta como um papel (e um login): o texto que volta ou "erro <sqlstate>: <mensagem>" (o molde de agenda_fase7g_livre.sql).
create function pg_temp.como(p_uid uuid, p_papel text, p_sql text) returns text language plpgsql as $f$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_papel)::text
         else json_build_object('sub', p_uid, 'role', p_papel)::text end, true);
  begin
    execute format('set local role %I', p_papel);
    execute p_sql into v;
    reset role;
  exception when others then
    v := 'erro ' || sqlstate || ': ' || sqlerrm;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  return v;
end $f$;

-- O cenário: ids pelo md5 de '7g5:…'.
create function pg_temp.o(p_n text) returns uuid language sql immutable as $f$ select md5('7g5:os:' || p_n)::uuid $f$;
create function pg_temp.p(p_n text) returns uuid language sql immutable as $f$ select md5('7g5:payee:' || p_n)::uuid $f$;
create function pg_temp.al(p_k text, p_i int) returns uuid language sql immutable as $f$ select md5('7g5:aloc:' || p_k || ':' || p_i)::uuid $f$;
create function pg_temp.nova_os(p_n text, p_serv text default 'Troca do inversor') returns uuid language plpgsql as $f$
declare
  v_os  uuid := pg_temp.o(p_n);
  v_cli uuid := md5('7g5:cli:' || p_n)::uuid;
  v_bem uuid := md5('7g5:bem:' || p_n)::uuid;
begin
  insert into public.clients (id, type, name) values (v_cli, 'individual', 'Cliente ' || p_n);
  insert into public.vessels (id, client_id, name, asset_type) values (v_bem, v_cli, 'Motorhome', 'Motorhome');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type, created_at, updated_at, converted_to_os_at)
  values (v_os, 'OS-K' || p_n, v_cli, v_bem, 'open', 'approved', 'repair', timestamptz '2026-11-05 10:00-03', timestamptz '2026-11-05 10:00-03',
          timestamptz '2026-11-06 09:00-03');
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity, unit_price_snapshot, line_total, created_at)
  values (md5('7g5:srv:' || p_n)::uuid, v_os, null, p_serv, 'unit', 1, 500, 500, timestamptz '2026-11-05 10:00-03');
  insert into public.payees (id, name, kind, active) values (pg_temp.p(p_n), 'Teo ' || p_n, 'prestador', true);
  return v_os;
end $f$;
-- Uma ação executada na OS p_n e os meios-dias que ela criou ('AAAA-MM-DD:turno'), publicados, da pessoa da OS.
create function pg_temp.marca(p_k text, p_n text, p_origem text, p_tipo text, p_em timestamptz, p_dias text[],
                              p_aloc_origem text default 'motor', p_reserva boolean default false, p_cancela uuid[] default '{}',
                              p_sup jsonb default null, p_degrau text default null) returns uuid language plpgsql as $f$
declare
  v_acao uuid := md5('7g5:acao:' || p_k)::uuid;
  v_ids  uuid[] := array(select pg_temp.al(p_k, i) from generate_series(1, coalesce(cardinality(p_dias), 0)) i);
  v_i    int;
begin
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_criadas, alocacoes_canceladas,
                                   antes, depois, texto, degrau)
  values (v_acao, p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, p_origem, p_tipo, pg_temp.o(p_n), array[pg_temp.o(p_n)], v_ids, p_cancela,
          '{}'::jsonb, '{}'::jsonb, 'Ação de teste ' || p_k, p_degrau);
  insert into _k values (p_k, v_acao);
  for v_i in 1 .. coalesce(cardinality(p_dias), 0) loop
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, reserva_de, estado, origem, publicada_em, acao_id,
                                         duracao_fonte, criterio, suposicoes, criado_em)
    values (v_ids[v_i], pg_temp.o(p_n), pg_temp.p(p_n), split_part(p_dias[v_i], ':', 1)::date, split_part(p_dias[v_i], ':', 2), 'turno',
            case when p_reserva then 'reserva' else 'execucao' end, case when p_reserva then 'teto' end, 'publicada', p_aloc_origem, p_em, v_acao,
            'orcamento', 'unico', p_sup, p_em);
  end loop;
  return v_acao;
end $f$;
-- O *desfaz* de uma ação: a ação desfazer e a desfeita marcada nela.
create function pg_temp.desfaz(p_k text, p_acao uuid, p_origem text, p_em timestamptz, p_cancela uuid[] default '{}') returns uuid language plpgsql as $f$
declare
  v_id uuid := md5('7g5:acao:' || p_k)::uuid;
begin
  insert into public.agenda_acoes (id, criada_em, dia, executada, origem, tipo, service_order_id, os_ids, alocacoes_canceladas, texto, desfaz_a)
  select v_id, p_em, (p_em at time zone 'America/Sao_Paulo')::date, true, p_origem, 'desfazer', a.service_order_id, a.os_ids, p_cancela, 'Desfeito: teste', a.id
    from public.agenda_acoes a where a.id = p_acao;
  insert into _k values (p_k, v_id);
  update public.agenda_acoes set desfeita_em = p_em, desfeita_pela = v_id where id = p_acao;
  return v_id;
end $f$;
create function pg_temp.cancela(p_al uuid, p_motivo text, p_em timestamptz) returns void language sql as $f$
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = p_motivo, cancelada_em = p_em where id = p_al
$f$;
-- A linha de os_planejamento com o histórico dado (os dias do dono; estimativa_em é a hora gravada na linha).
create function pg_temp.plan(p_n text, p_est timestamptz, p_hist jsonb) returns void language sql as $f$
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, historico) values (pg_temp.o(p_n), 3, 'dono', p_est, p_hist)
$f$;

create function pg_temp.cenario_k() returns void language plpgsql as $f$
declare
  v_a uuid;
  v_n text;
begin
  perform pg_temp.nova_os(n) from unnest(array['a1', 'a2', 'b1', 'b2', 'b3', 'b4', 'b5', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'd1', 'd2', 'd3', 'd4', 'd5',
                                                'd6', 'd7', 'h1', 'h2', 'h3', 'h4', 'h4b', 'h5', 'h6', 'h7', 'h8', 'h8c', 'h9', 'h10', 'h11', 'h12']) n;
  -- aceitas: o 1º dia chegou sem nada; a2 com a manhã cumprida (conferida)
  perform pg_temp.marca('a1', 'a1', 'vigia', 'criar', timestamptz '2026-11-10 09:00-03', array['2026-11-12:manha', '2026-11-12:tarde'],
                        p_sup => '[{"codigo": "uma_pessoa", "detalhe": {}}]'::jsonb);
  perform pg_temp.marca('a2', 'a2', 'vigia', 'publicar', timestamptz '2026-11-10 09:05-03', array['2026-11-13:manha']);
  perform set_config('agenda.hoje', '2026-11-19', true);
  update public.agenda_alocacoes set resultado = 'cumprido', resultado_via = 'tela' where id = pg_temp.al('a2', 1);
  -- ajustadas: pela tela (mover, sem degrau: dia), pelo WhatsApp (degrau pessoa), pelo assistente (cancelar: tirou), os dias regravados (duração), o material
  perform pg_temp.marca('b1', 'b1', 'vigia', 'criar', timestamptz '2026-11-10 09:10-03', array['2026-11-16:manha']);
  perform pg_temp.marca('b1d', 'b1', 'tela', 'mover', timestamptz '2026-11-11 10:00-03', '{}');
  perform pg_temp.marca('b2', 'b2', 'vigia', 'criar', timestamptz '2026-11-10 09:15-03', array['2026-11-16:tarde']);
  perform pg_temp.marca('b2d', 'b2', 'dono', 'mover', timestamptz '2026-11-11 10:00-03', '{}', p_degrau => 'pessoa');
  perform pg_temp.marca('b3', 'b3', 'vigia', 'criar', timestamptz '2026-11-10 09:20-03', array['2026-11-17:manha']);
  perform pg_temp.marca('b3d', 'b3', 'assistente', 'cancelar', timestamptz '2026-11-11 10:00-03', '{}');
  perform pg_temp.marca('b4', 'b4', 'vigia', 'criar', timestamptz '2026-11-10 09:25-03', array['2026-11-17:tarde']);
  perform pg_temp.plan('b4', timestamptz '2026-11-11 10:00-03',
                       '[{"em": "2026-11-11", "autor": null, "trecho": "são 3 dias", "antes": {"dias": 2}, "depois": {"dias": 3}}]');
  perform pg_temp.marca('b5', 'b5', 'vigia', 'criar', timestamptz '2026-11-10 09:30-03', array['2026-11-18:manha']);
  perform pg_temp.marca('b5f', 'b5', 'dono', 'fixar', timestamptz '2026-11-11 09:00-03', '{}');
  insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, fonte, atualizado_em)
  values (pg_temp.o('b5'), 'dono', 'Inversor 3 kW', 1, 'dono', timestamptz '2026-11-11 11:00-03');
  -- desfeita pelo dono
  v_a := pg_temp.marca('c1', 'c1', 'vigia', 'criar', timestamptz '2026-11-10 09:35-03', array['2026-11-18:tarde']);
  perform pg_temp.desfaz('c1u', v_a, 'dono', timestamptz '2026-11-10 12:00-03', array[pg_temp.al('c1', 1)]);
  -- remarcada pela vigia: a nova (c2m) é outra marcação
  perform pg_temp.marca('c2', 'c2', 'vigia', 'criar', timestamptz '2026-11-10 09:40-03', array['2026-11-20:manha']);
  perform pg_temp.cancela(pg_temp.al('c2', 1), 'replanejado', timestamptz '2026-11-11 10:00-03');
  perform pg_temp.marca('c2m', 'c2', 'vigia', 'mover', timestamptz '2026-11-11 10:00-03', array['2026-11-24:manha'], p_cancela => array[pg_temp.al('c2', 1)]);
  -- saiu: a OS saiu da carteira
  perform pg_temp.marca('c3', 'c3', 'vigia', 'criar', timestamptz '2026-11-10 09:45-03', array['2026-11-25:manha']);
  perform pg_temp.cancela(pg_temp.al('c3', 1), 'os_saiu', timestamptz '2026-11-12 10:00-03');
  -- aceita pela janela (o 1º dia em dezembro); aberta (marcada ontem)
  perform pg_temp.marca('c4', 'c4', 'vigia', 'criar', timestamptz '2026-11-09 10:00-03', array['2026-12-15:manha']);
  perform pg_temp.marca('c5', 'c5', 'vigia', 'criar', timestamptz '2026-11-18 10:00-03', array['2026-11-26:manha']);
  -- o cliente mudou o dia: remarcada, não correção; a ação dele (com a alocação de origem cliente) não é marcação
  perform pg_temp.marca('c6', 'c6', 'vigia', 'criar', timestamptz '2026-11-10 09:50-03', array['2026-11-27:manha']);
  perform pg_temp.cancela(pg_temp.al('c6', 1), 'cliente', timestamptz '2026-11-12 10:00-03');
  perform pg_temp.marca('c6c', 'c6', 'cliente', 'mover', timestamptz '2026-11-12 10:00-03', array['2026-11-30:manha'], p_aloc_origem => 'cliente',
                        p_cancela => array[pg_temp.al('c6', 1)]);
  -- desfeita pela vigia: não é o dono (a régua de _agenda_gestor_desfeito) → remarcada
  v_a := pg_temp.marca('c7', 'c7', 'vigia', 'criar', timestamptz '2026-11-10 09:55-03', array['2026-11-19:tarde']);
  perform pg_temp.cancela(pg_temp.al('c7', 1), 'desfeito', timestamptz '2026-11-10 13:00-03');
  perform pg_temp.desfaz('c7u', v_a, 'vigia', timestamptz '2026-11-10 13:00-03', array[pg_temp.al('c7', 1)]);
  -- do dono: pela origem da ação (tela) e pela alocação de origem dono
  perform pg_temp.marca('d1', 'd1', 'tela', 'criar', timestamptz '2026-11-10 10:00-03', array['2026-11-23:manha']);
  perform pg_temp.marca('d2', 'd2', 'vigia', 'criar', timestamptz '2026-11-10 10:05-03', array['2026-11-23:tarde'], p_aloc_origem => 'dono');
  -- não entram: a ação do cliente, a alocação do cliente, só reserva, antes de marcacoes_desde, depois de agora
  perform pg_temp.marca('d3', 'd3', 'cliente', 'criar', timestamptz '2026-11-10 10:10-03', array['2026-11-24:tarde']);
  perform pg_temp.marca('d4', 'd4', 'vigia', 'criar', timestamptz '2026-11-10 10:15-03', array['2026-11-25:tarde'], p_aloc_origem => 'cliente');
  perform pg_temp.marca('d5', 'd5', 'vigia', 'criar', timestamptz '2026-11-10 10:20-03', array['2026-11-26:tarde'], p_reserva => true);
  perform pg_temp.marca('d6', 'd6', 'vigia', 'criar', timestamptz '2026-11-08 10:00-03', array['2026-11-12:manha']);
  perform pg_temp.marca('d7', 'd7', 'vigia', 'criar', timestamptz '2026-11-19 17:00-03', array['2026-11-27:tarde']);
  -- o histórico de os_planejamento: marcadas ter 10/11 às 09:00 (12:00 UTC), o 1º dia seg 16/11 de manhã
  foreach v_n in array array['h1', 'h2', 'h3', 'h4', 'h4b', 'h5', 'h6', 'h7', 'h8', 'h8c', 'h9', 'h10', 'h11', 'h12'] loop
    perform pg_temp.marca(v_n, v_n, 'vigia', 'criar', timestamptz '2026-11-10 09:00-03', array['2026-11-16:manha']);
  end loop;
  -- a do gestor (_agenda_gestor_gravar_dias), por gestor: não é correção; a mesma, por dono (a pergunta que o dono respondeu): é
  perform pg_temp.plan('h1', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "quando": "2026-11-11T13:00:00+00:00", "autor": null, "por": "gestor",
    "motivo": "pergunta", "pergunta": null, "antes": {"dias": 2}, "depois": {"dias": 3}}]');
  perform pg_temp.plan('h2', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "quando": "2026-11-11T13:00:00+00:00", "autor": null, "por": "dono",
    "motivo": "pergunta", "pergunta": null, "antes": {"dias": 2}, "depois": {"dias": 3}}]');
  -- as 2 do *desfaz* (agenda_desfazer): com quando; e com em com hora (h4b: antes da marcação no mesmo dia, não conta)
  perform pg_temp.plan('h3', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "quando": "2026-11-11T14:00:00+00:00", "autor": null, "por": "dono",
    "motivo": "desfeito", "acao": null, "antes": {"dias": 3}, "depois": {"dias": 2}}]');
  perform pg_temp.plan('h4', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11T15:00:00+00:00", "autor": null, "por": "dono", "trecho": "desfeito",
    "acao": null, "antes": {"dias": 3}, "depois": {"dias": 2}}]');
  perform pg_temp.plan('h4b', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-10T11:00:00+00:00", "autor": null, "por": "dono", "trecho": "desfeito",
    "acao": null, "antes": {"dias": 3}, "depois": {"dias": 2}}]');
  -- a do *grava* (_agenda_aplicar_planejar: só o dia) no dia da marcação: antes dela (estimativa_em 08:00) não conta; depois (11:00) conta
  perform pg_temp.plan('h5', timestamptz '2026-11-10 08:00-03', '[{"em": "2026-11-10", "autor": null, "trecho": "3 dias", "antes": {"dias": 2}, "depois": {"dias": 3}}]');
  perform pg_temp.plan('h6', timestamptz '2026-11-10 11:00-03', '[{"em": "2026-11-10", "autor": null, "trecho": "3 dias", "antes": {"dias": 2}, "depois": {"dias": 3}}]');
  -- K2b: repetir os dias (a saída do dono, R9.3-1); K2b2: dizer o número corrigido (também a saída); o controle: o mesmo número sem a saída é correção
  perform pg_temp.plan('h7', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "autor": null, "trecho": "3 dias mesmo",
    "antes": {"dias": 3, "vies_dono_fixo": false}, "depois": {"dias": 3, "vies_dono_fixo": true}}]');
  perform pg_temp.plan('h8', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "autor": null, "trecho": "3 e meio",
    "antes": {"dias": 3, "vies_dono_fixo": false}, "depois": {"dias": 3.5, "vies_dono_fixo": true}}]');
  perform pg_temp.plan('h8c', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "autor": null, "trecho": "3 e meio",
    "antes": {"dias": 3}, "depois": {"dias": 3.5}}]');
  -- só o congelado da 7e (vies_marcado, marcado_em, aprovado_com_vies): não é correção; antes do dia da marcação: não conta
  perform pg_temp.plan('h9', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "autor": null, "trecho": null,
    "antes": {"vies_marcado": 1, "marcado_em": null, "aprovado_com_vies": null}, "depois": {"vies_marcado": 1.2, "marcado_em": "2026-11-11", "aprovado_com_vies": {"dias": 3}}}]');
  perform pg_temp.plan('h10', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-09", "autor": null, "trecho": "3 dias", "antes": {"dias": 2}, "depois": {"dias": 3}}]');
  -- a equipe e a dupla (pessoa)
  perform pg_temp.plan('h11', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "autor": null, "trecho": "vai o Teo",
    "antes": {"equipe": []}, "depois": {"equipe": [{"payee_id": "x", "turnos": "dia"}]}}]');
  perform pg_temp.plan('h12', timestamptz '2026-11-05 10:00-03', '[{"em": "2026-11-11", "autor": null, "trecho": "em dupla",
    "antes": {"dupla_dita": null}, "depois": {"dupla_dita": true}}]');
end $f$;

-- Como cada marcação ficou, numa linha: k=desfecho[ajustes]@ação!(conferida)
create function pg_temp.desfechos() returns text language sql as $f$
  select string_agg(k.k || '=' || coalesce(m.desfecho, '-')
                    || case when cardinality(m.ajustes) > 0 then '[' || array_to_string(m.ajustes, '+') || ']' else '' end
                    || coalesce('@' || (select k2.k from _k k2 where k2.acao = m.desfecho_acao_id), '')
                    || case when m.conferida then '!' else '' end, ',' order by k.k collate "C")
    from public.agenda_marcacoes m join _k k on k.acao = m.acao_id
$f$;

-- ── K0. O catálogo e a migration ─────────────────────────────────────────────────────────────────────
do $k0$
declare
  v_res jsonb := '[]'::jsonb;
  v     text;
begin
  select string_agg(p.proname || ':' || p.provolatile::text || ':' || case when p.prosecdef then 'definer' else 'invoker' end
                    || ':' || case when coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%' then 'sp' else 'sem_sp' end,
                    ',' order by p.proname collate "C") into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('agenda_explicar_rodar', '_agenda_explicar_marcacoes', '_agenda_explicar_tipos', '_agenda_marcacao_desfecho');
  v_res := pg_temp.igual(v_res, 'K0a as 4 novas: a rodada definer e volátil; as marcações e os tipos invoker e voláteis; o desfecho invoker e STABLE; todas com search_path', v,
    '_agenda_explicar_marcacoes:v:invoker:sp,_agenda_explicar_tipos:v:invoker:sp,_agenda_marcacao_desfecho:s:invoker:sp,agenda_explicar_rodar:v:definer:sp');
  select string_agg(f || ':' || r || '=' || has_function_privilege(r, f, 'execute')::text, ',' order by f, r) into v
    from unnest(array['public.agenda_explicar_rodar(date, timestamptz)', 'public._agenda_explicar_marcacoes(date, timestamptz)',
                      'public._agenda_explicar_tipos(date, timestamptz)', 'public._agenda_marcacao_desfecho(uuid, uuid, date)']) f,
         unnest(array['anon', 'authenticated']) r
   where has_function_privilege(r, f, 'execute');
  v_res := pg_temp.ok(v_res, 'K0b nenhuma das 4 executável por anon nem por authenticated (só a rodada do task-automations, que é service_role)', v is null, v);
  v_res := pg_temp.ok(v_res, 'K0c o service_role executa as 4',
    has_function_privilege('service_role', 'public.agenda_explicar_rodar(date, timestamptz)', 'execute')
    and has_function_privilege('service_role', 'public._agenda_explicar_marcacoes(date, timestamptz)', 'execute')
    and has_function_privilege('service_role', 'public._agenda_explicar_tipos(date, timestamptz)', 'execute')
    and has_function_privilege('service_role', 'public._agenda_marcacao_desfecho(uuid, uuid, date)', 'execute'), null);
  if coalesce(current_setting('agenda_teste.mig_correcoes_fase7g', true), '') = '' then
    v_res := pg_temp.ok(v_res, 'K0d as funções da migration', true, 'PULADO: sem agenda_teste.mig_correcoes_fase7g (rode pela bancada)');
  else
    select string_agg(m[1], ',' order by m[1] collate "C") into v
      from regexp_matches(current_setting('agenda_teste.mig_correcoes_fase7g'), 'create or replace function public\.([a-z_0-9]+)\(', 'g') m;
    v_res := pg_temp.igual(v_res, 'K0d a migration só cria as 4 novas: nenhuma função de antes é recriada (R9.1: o P5 não copia nada; o ok do dono é do P5b)', v,
      '_agenda_explicar_marcacoes,_agenda_explicar_tipos,_agenda_marcacao_desfecho,agenda_explicar_rodar');
  end if;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('K0 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$k0$;

-- ── K1 e K2. O registro e o desfecho ─────────────────────────────────────────────────────────────────
do $k12$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-11-19';
  c_agora constant timestamptz := timestamptz '2026-11-19 16:40-03';
  c_desde constant timestamptz := timestamptz '2026-11-09 00:00-03';
  v_r     jsonb;
  v       text;
  v2      text;
  v_m     public.agenda_marcacoes;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(jsonb_build_array(jsonb_build_array('K1 as marcações', true, 'PULADO: fora da bancada (rode pela bancada)')));
    return;
  end if;
  begin
    perform pg_temp.cenario_k();
    update public.agenda_config set modo_porque = 'sombra', marcacoes_desde = null, correcao_janela_du = 7 where id;

    -- K1a sem marcacoes_desde (a linha até o dado 20261112100990): nada entra (R9.4-2: sem olhar para trás)
    v_r := public._agenda_explicar_marcacoes(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'K1a sem marcacoes_desde, nenhuma marcação entra (o plano de antes da 7g não vira aceite)',
      (v_r ->> 'registradas')::int = 0 and not exists (select 1 from public.agenda_marcacoes m join _k k on k.acao = m.acao_id), v_r::text);
    -- K1b com modo_porque desligado: nada, nem com marcacoes_desde
    update public.agenda_config set modo_porque = 'desligado', marcacoes_desde = c_desde where id;
    v_r := public._agenda_explicar_marcacoes(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'K1b modo_porque desligado: {modo: desligado} e nada gravado',
      v_r = '{"modo": "desligado"}'::jsonb and not exists (select 1 from public.agenda_marcacoes m join _k k on k.acao = m.acao_id), v_r::text);

    update public.agenda_config set modo_porque = 'sombra' where id;
    v_r := public._agenda_explicar_marcacoes(c_hoje, c_agora);
    select string_agg(k.k, ',' order by k.k collate "C") into v from public.agenda_marcacoes m join _k k on k.acao = m.acao_id;
    v_res := pg_temp.igual(v_res, 'K1c entram as ações executadas desde marcacoes_desde até agora que criaram meio-dia sem reserva, uma por (ação, OS); não entram a ação do cliente (d3, c6c), a alocação do cliente (d4), só reserva (d5), antes de marcacoes_desde (d6), depois de agora (d7) nem as ações sem meio-dia (b1d, c1u…)', v,
      'a1,a2,b1,b2,b3,b4,b5,c1,c2,c2m,c3,c4,c5,c6,c7,d1,d2,h1,h10,h11,h12,h2,h3,h4,h4b,h5,h6,h7,h8,h8c,h9');
    select string_agg(k.k || ':' || m.quem || ':' || coalesce(m.desfecho, '-') || ':' || m.versao, ',' order by k.k collate "C") into v
      from public.agenda_marcacoes m join _k k on k.acao = m.acao_id where k.k in ('d1', 'd2', 'a1', 'c5');
    v_res := pg_temp.igual(v_res, 'K1d quem: dono pela origem da ação (tela, d1) e pela alocação de origem dono (d2), sem desfecho; o resto é do gestor', v,
      'a1:gestor:aceita:2,c5:gestor:aberta:1,d1:dono:-:1,d2:dono:-:1');
    select * into v_m from public.agenda_marcacoes m where m.acao_id = md5('7g5:acao:a1')::uuid;
    v_res := pg_temp.ok(v_res, 'K1e a linha de a1: OS, origem, tipo, classe, fonte e suposições da 1ª alocação, período, meios, pessoas, marcada_em, 1ª hora, aprovação (R9.5-7)',
      v_m.service_order_id = pg_temp.o('a1') and v_m.origem_acao = 'vigia' and v_m.tipo_acao = 'criar'
      and v_m.classe = public._agenda_classe_de_campo(pg_temp.o('a1')) ->> 'chave' and v_m.duracao_fonte = 'orcamento'
      and v_m.suposicoes = '{uma_pessoa}'::text[] and v_m.de = date '2026-11-12' and v_m.ate = date '2026-11-12' and v_m.meios = 2
      and v_m.pessoas = array[pg_temp.p('a1')] and v_m.marcada_em = timestamptz '2026-11-10 09:00-03'
      and v_m.primeiro_inicio = lower(public.agenda_periodo(date '2026-11-12', 'manha', 'turno'))
      and v_m.aprovada_em = timestamptz '2026-11-06 09:00-03' and v_m.zona is null and v_m.degrau is null,
      to_jsonb(v_m)::text);
    v_res := pg_temp.ok(v_res, 'K1f o retorno: registradas e decididas por desfecho',
      (v_r ->> 'registradas')::int >= 31 and (v_r #>> '{decididas,ajustada}')::int = 12 and (v_r #>> '{decididas,aceita}')::int = 10
      and (v_r #>> '{decididas,remarcada}')::int = 3 and (v_r #>> '{decididas,desfeita}')::int = 1 and (v_r #>> '{decididas,saiu}')::int = 1
      and not (v_r -> 'decididas') ? 'aberta', v_r::text);
    -- K1g 2× = 1×: nada novo, nada muda
    select md5(string_agg(to_jsonb(m)::text, '|' order by m.acao_id)) into v from public.agenda_marcacoes m;
    v_r := public._agenda_explicar_marcacoes(c_hoje, c_agora);
    select md5(string_agg(to_jsonb(m)::text, '|' order by m.acao_id)) into v2 from public.agenda_marcacoes m;
    v_res := pg_temp.ok(v_res, 'K1g a 2ª rodada não registra nem decide nada (2× = 1×, mesma versão)',
      v = v2 and (v_r ->> 'registradas')::int = 0 and v_r -> 'decididas' = '{}'::jsonb, v_r::text);

    -- K2. O desfecho de cada uma
    v_res := pg_temp.igual(v_res, 'K2a o desfecho de cada marcação (a ordem da spec: desfeita, ajustada, remarcada, saiu, aceita; a janela; aberta)', pg_temp.desfechos(),
      'a1=aceita,a2=aceita!,b1=ajustada[dia]@b1d,b2=ajustada[pessoa]@b2d,b3=ajustada[tirou]@b3d,b4=ajustada[duracao],b5=ajustada[material],c1=desfeita@c1u,'
      || 'c2=remarcada@c2m,c2m=aberta,c3=saiu,c4=aceita,c5=aberta,c6=remarcada@c6c,c7=remarcada@c7u,d1=-,d2=-,h1=aceita,h10=aceita,h11=ajustada[pessoa],'
      || 'h12=ajustada[pessoa],h2=ajustada[duracao],h3=ajustada[duracao],h4=ajustada[duracao],h4b=aceita,h5=aceita,h6=ajustada[duracao],h7=aceita,h8=aceita,'
      || 'h8c=ajustada[duracao],h9=aceita');
    -- as 4 formas, uma a uma (R9.4-2)
    select string_agg(k.k || '=' || m.desfecho, ',' order by k.k collate "C") into v from public.agenda_marcacoes m join _k k on k.acao = m.acao_id
     where k.k in ('b4', 'h1', 'h2', 'h3', 'h4', 'h4b', 'h5', 'h6', 'h10');
    v_res := pg_temp.igual(v_res, 'K2b0 as 4 formas do histórico: o *grava* (só o dia: b4; no dia da marcação, pela hora da linha: h5 antes não, h6 depois sim; antes do dia: h10 não), a do gestor (por gestor h1 não; por dono h2 sim) e as 2 do *desfaz* (h3 com quando; h4 com em com hora; h4b antes da marcação no mesmo dia, não)', v,
      'b4=ajustada,h1=aceita,h10=aceita,h2=ajustada,h3=ajustada,h4=ajustada,h4b=aceita,h5=aceita,h6=ajustada');
    select string_agg(k.k || '=' || m.desfecho, ',' order by k.k collate "C") into v from public.agenda_marcacoes m join _k k on k.acao = m.acao_id
     where k.k in ('h7', 'h8', 'h8c', 'h9');
    v_res := pg_temp.igual(v_res, 'K2b repetir os dias (h7) e K2b2 dizer o número corrigido (h8) são a saída do dono, não correção (R9.3-1); o mesmo número sem a saída é (h8c); o congelado da 7e não é (h9)', v,
      'h7=aceita,h8=aceita,h8c=ajustada,h9=aceita');
    select string_agg(k.k || ':' || m.conferida, ',' order by k.k collate "C") into v from public.agenda_marcacoes m join _k k on k.acao = m.acao_id
     where k.k in ('a1', 'a2');
    v_res := pg_temp.igual(v_res, 'K2c conferida: só a aceita com meio-dia cumprido ou parcial (a2); a1 ficou como fiz sem conferência (o silêncio não é aceite, R9.4-2)', v,
      'a1:false,a2:true');
    v_res := pg_temp.ok(v_res, 'K2d o cliente: o dia que ele mudou é remarcada (c6), não ajustada; a ação dele (c6c) e a alocação dele (d4) não são marcação',
      (select m.desfecho from public.agenda_marcacoes m where m.acao_id = md5('7g5:acao:c6')::uuid) = 'remarcada'
      and not exists (select 1 from public.agenda_marcacoes m join _k k on k.acao = m.acao_id where k.k in ('c6c', 'd3', 'd4')), null);
    select string_agg(k.k || '=' || to_char(m.desfecho_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), ',' order by k.k collate "C") into v
      from public.agenda_marcacoes m join _k k on k.acao = m.acao_id where k.k in ('a1', 'b1', 'b4', 'b5', 'c1', 'c2', 'c3', 'h2', 'h6');
    v_res := pg_temp.igual(v_res, 'K2e a hora do desfecho: a 1ª hora (aceita), a ação do dono, o dia regravado (só o dia: o começo dele), o material, o *desfaz*, a remarcação, a saída, o quando, a marcação (o mesmo dia)', v,
      'a1=12/11 08:00,b1=11/11 10:00,b4=11/11 00:00,b5=11/11 11:00,c1=10/11 12:00,c2=11/11 10:00,c3=12/11 10:00,h2=11/11 10:00,h6=10/11 09:00');
    v_res := pg_temp.ok(v_res, 'K2f aceita pela janela: o dia de marcacoes + correcao_janela_du dias úteis, no começo dele',
      (select m.desfecho_em from public.agenda_marcacoes m where m.acao_id = md5('7g5:acao:c4')::uuid)
        = public.agenda_somar_du(date '2026-11-09', 7)::timestamp at time zone 'America/Sao_Paulo'
      and public.agenda_somar_du(date '2026-11-09', 7) <= c_hoje, null);
    v_res := pg_temp.ok(v_res, 'K2g decidida: versão 2 e 1 entrada no histórico (de aberta para o desfecho); aberta e a do dono: versão 1, histórico vazio',
      not exists (select 1 from public.agenda_marcacoes m join _k k on k.acao = m.acao_id
                   where (m.desfecho in ('aceita', 'ajustada', 'desfeita', 'remarcada', 'saiu')
                          and not (m.versao = 2 and jsonb_array_length(m.historico) = 1 and m.historico #>> '{0,antes,desfecho}' = 'aberta'
                                   and m.historico #>> '{0,depois,desfecho}' = m.desfecho))
                      or (m.desfecho is distinct from 'aceita' and m.desfecho is distinct from 'ajustada' and m.desfecho is distinct from 'desfeita'
                          and m.desfecho is distinct from 'remarcada' and m.desfecho is distinct from 'saiu'
                          and not (m.versao = 1 and m.historico = '[]'::jsonb))), null);
    -- K2h: a de antes desta mudança fica: a marcação decidida não volta (o gatilho do P1); o desfecho é lido e não muda mais
    v_res := pg_temp.ok(v_res, 'K2h o desfecho direto da função: nulo para a do dono e para a que não existe',
      public._agenda_marcacao_desfecho(md5('7g5:acao:d1')::uuid, pg_temp.o('d1'), c_hoje) is null
      and public._agenda_marcacao_desfecho(gen_random_uuid(), pg_temp.o('d1'), c_hoje) is null, null);
    raise exception using errcode = 'PK001';
  exception when sqlstate 'PK001' then
    null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('K1 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$k12$;

-- ── K3. O tipo de OS: só teria ───────────────────────────────────────────────────────────────────────
do $k3$
declare
  v_res   jsonb := '[]'::jsonb;
  c_hoje  constant date := date '2026-11-19';
  c_agora constant timestamptz := timestamptz '2026-11-19 16:40-03';
  v_r     jsonb;
  v       text;
  v2      text;
  v_c     text;
  v_mt    text;
  v_t     public.agenda_tipos_os;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(jsonb_build_array(jsonb_build_array('K3 o tipo de OS', true, 'PULADO: fora da bancada (rode pela bancada)')));
    return;
  end if;
  begin
    -- conforto (a geladeira): 1 aceita (a mais nova) e 3 ajustadas; motor (o gerador): 2 aceitas
    perform pg_temp.nova_os(n, 'Conserto da geladeira') from unnest(array['e1', 'e2', 'e3', 'e4']) n;
    perform pg_temp.nova_os(n, 'Revisão do gerador') from unnest(array['m1', 'm2']) n;
    perform pg_temp.marca('e1', 'e1', 'vigia', 'criar', timestamptz '2026-11-10 09:00-03', array['2026-11-12:manha']);
    perform pg_temp.marca(n, n, 'vigia', 'criar', timestamptz '2026-11-10 09:00-03', array['2026-11-16:manha']) from unnest(array['e2', 'e3', 'e4']) n;
    perform pg_temp.marca(n || 'd', n, 'tela', 'mover', timestamptz '2026-11-11 10:00-03', '{}') from unnest(array['e2', 'e3', 'e4']) n;
    perform pg_temp.marca(n, n, 'vigia', 'criar', timestamptz '2026-11-10 09:00-03', array['2026-11-12:manha']) from unnest(array['m1', 'm2']) n;
    v_c := public._agenda_classe_de_campo(pg_temp.o('e1')) ->> 'chave';
    v_mt := public._agenda_classe_de_campo(pg_temp.o('m1')) ->> 'chave';
    update public.agenda_config set modo_porque = 'sombra', marcacoes_desde = timestamptz '2026-11-09 00:00-03', modo_rebaixar = 'desligado' where id;
    perform public._agenda_explicar_marcacoes(c_hoje, c_agora);
    -- K3a desligado: nada
    v_r := public._agenda_explicar_tipos(c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'K3a modo_rebaixar desligado: {modo: desligado} e nenhuma linha em agenda_tipos_os',
      v_r = '{"modo": "desligado"}'::jsonb and not exists (select 1 from public.agenda_tipos_os t where t.classe in (v_c, v_mt)), v_r::text);
    -- K3b em sombra
    update public.agenda_config set modo_rebaixar = 'sombra' where id;
    v_r := public._agenda_explicar_tipos(c_hoje, c_agora);
    select * into v_t from public.agenda_tipos_os t where t.classe = v_c;
    v_res := pg_temp.ok(v_res, 'K3b conforto em sombra: n 4, 3 corrigidas, 1 aceita seguida (a mais nova), teria espera_ok, o nível fica sozinho (sem desde nem ação)',
      v_c is distinct from v_mt and v_t.n = 4 and v_t.corrigidas = 3 and v_t.aceitas_seguidas = 1 and v_t.teria = 'espera_ok' and v_t.nivel = 'sozinho'
      and v_t.desde is null and v_t.acao_id is null and jsonb_array_length(v_t.amostra) = 4 and v_t.amostra #>> '{0,desfecho}' = 'aceita'
      and v_t.calculado_em = c_agora and jsonb_array_length(v_t.historico) = 1, to_jsonb(v_t)::text);
    v_res := pg_temp.igual(v_res, 'K3c o texto do §6.4 (sombra), com a classe pelo texto e os números do banco', v_t.texto,
      format('Em teste: nas OS de %s eu passaria a esperar o seu ok (você corrigiu 3 de 4).', public._agenda_classe_de_campo(pg_temp.o('e1')) ->> 'texto'));
    select t.teria || ':' || t.n || ':' || t.corrigidas || ':' || t.aceitas_seguidas || ':' || coalesce(t.texto, '-') into v from public.agenda_tipos_os t where t.classe = v_mt;
    v_res := pg_temp.igual(v_res, 'K3d motor: n 2 (abaixo de rebaixar_n_min) fica sozinho, sem texto', v, 'sozinho:2:0:2:-');
    v_res := pg_temp.ok(v_res, 'K3e o retorno: as classes, quantas teriam espera_ok; espera_ok e voltaram em 0 (o nível é do P5b)',
      (v_r ->> 'classes')::int >= 2 and (v_r ->> 'teria')::int >= 1 and (v_r ->> 'espera_ok')::int = 0 and (v_r ->> 'voltaram')::int = 0, v_r::text);
    -- K3f 2× = 1×
    select md5(string_agg(to_jsonb(t)::text, '|' order by t.classe)) into v from public.agenda_tipos_os t where t.classe in (v_c, v_mt);
    perform public._agenda_explicar_tipos(c_hoje, c_agora + interval '1 day');
    select md5(string_agg(to_jsonb(t)::text, '|' order by t.classe)) into v2 from public.agenda_tipos_os t where t.classe in (v_c, v_mt);
    v_res := pg_temp.ok(v_res, 'K3f a 2ª rodada sem nada novo não muda a linha (nem calculado_em)', v = v2, null);
    -- K3g ligado: o mesmo (só teria: o nível é do P5b, R9.4-4)
    update public.agenda_config set modo_rebaixar = 'ligado' where id;
    perform public._agenda_explicar_tipos(c_hoje, c_agora);
    select md5(string_agg(to_jsonb(t)::text, '|' order by t.classe)) into v2 from public.agenda_tipos_os t where t.classe in (v_c, v_mt);
    v_res := pg_temp.ok(v_res, 'K3g com modo_rebaixar ligado, o mesmo de sombra: nenhum nível muda', v = v2, null);
    -- K3h a taxa: 3 de 4 abaixo de 0,80 → sozinho, e o histórico ganha a troca
    update public.agenda_config set rebaixar_taxa = 0.80 where id;
    perform public._agenda_explicar_tipos(c_hoje, c_agora);
    select * into v_t from public.agenda_tipos_os t where t.classe = v_c;
    v_res := pg_temp.ok(v_res, 'K3h com rebaixar_taxa 0,80, 3 de 4 não chega: teria sozinho, sem texto, e o histórico ganha a troca',
      v_t.teria = 'sozinho' and v_t.texto is null and jsonb_array_length(v_t.historico) = 2 and v_t.historico #>> '{1,antes,teria}' = 'espera_ok'
      and v_t.historico #>> '{1,depois,teria}' = 'sozinho', to_jsonb(v_t)::text);
    -- K3i a trava: com travado_ate no futuro, sozinho mesmo com a taxa de volta
    update public.agenda_config set rebaixar_taxa = 0.50 where id;
    update public.agenda_tipos_os set travado_ate = c_hoje + 5 where classe = v_c;
    perform public._agenda_explicar_tipos(c_hoje, c_agora);
    select t.teria into v from public.agenda_tipos_os t where t.classe = v_c;
    update public.agenda_tipos_os set travado_ate = null where classe = v_c;
    perform public._agenda_explicar_tipos(c_hoje, c_agora);
    select t.teria into v2 from public.agenda_tipos_os t where t.classe = v_c;
    v_res := pg_temp.igual(v_res, 'K3i travado (o *desfaz espera* do P5b) fica sozinho; sem a trava, espera_ok de novo', v || '/' || v2, 'sozinho/espera_ok');
    raise exception using errcode = 'PK001';
  exception when sqlstate 'PK001' then
    null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('K3 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$k3$;

-- ── K11. A rodada ────────────────────────────────────────────────────────────────────────────────────
do $k11$
declare
  v_res   jsonb := '[]'::jsonb;
  c_admin constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tec   constant uuid := 'aa000000-0000-4000-8000-000000000002';
  v_r     jsonb;
  v       text;
  v_n     int;
begin
  if coalesce(current_setting('agenda_teste.fase7g', true), '') = '' then
    perform pg_temp.gravar(jsonb_build_array(jsonb_build_array('K11 a rodada', true, 'PULADO: fora da bancada (rode pela bancada)')));
    return;
  end if;
  begin
    perform pg_temp.cenario_k();
    update public.agenda_config set modo_porque = 'desligado', modo_rebaixar = 'desligado', modo_placar = 'desligado', marcacoes_desde = timestamptz '2026-11-09 00:00-03',
                                    correcao_janela_du = 7 where id;
    v_n := (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'explicar');
    -- K11a desligado: nada, nem linha
    v_r := public.agenda_explicar_rodar(date '2026-11-19', timestamptz '2026-11-19 16:40-03');
    v_res := pg_temp.ok(v_res, 'K11a os 3 modos desligados: {rodou: false, desligado}, sem linha e sem marcação (byte a byte o de antes)',
      v_r = '{"rodou": false, "desligado": true}'::jsonb and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'explicar') = v_n
      and not exists (select 1 from public.agenda_marcacoes m join _k k on k.acao = m.acao_id), v_r::text);
    update public.agenda_config set modo_porque = 'sombra', modo_rebaixar = 'sombra' where id;
    -- K11b domingo e K11c antes da hora: nada, sem linha
    v_r := public.agenda_explicar_rodar(date '2026-11-22', timestamptz '2026-11-22 16:40-03');
    v := v_r::text;
    v_r := public.agenda_explicar_rodar(date '2026-11-19', timestamptz '2026-11-19 16:00-03');
    v_res := pg_temp.ok(v_res, 'K11b domingo = {rodou: false, domingo}; antes de explicar_hora = {rodou: false, cedo}; sem linha e sem marcação',
      v::jsonb = '{"rodou": false, "domingo": true}'::jsonb and v_r ->> 'cedo' = 'true' and v_r ->> 'rodou' = 'false'
      and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'explicar') = v_n
      and not exists (select 1 from public.agenda_marcacoes m join _k k on k.acao = m.acao_id), v || ' | ' || v_r::text);
    -- K11d a rodada do dia: os 2 passos, uma linha
    v_r := public.agenda_explicar_rodar(date '2026-11-19', timestamptz '2026-11-19 16:40-03');
    v_res := pg_temp.ok(v_res, 'K11d às 16:40 roda: marcacoes e tipos, sem erro, uma linha rotina explicar do dia com os modos e a duração',
      v_r ->> 'rodou' = 'true' and v_r -> 'contagens' ? 'marcacoes' and v_r -> 'contagens' ? 'tipos' and not (v_r -> 'contagens') ? 'placar'
      and (v_r ->> 'erros')::int = 0 and v_r -> 'falhas' = '[]'::jsonb and not v_r ? 'parou_no'
      and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje = date '2026-11-19'
              and x.contagens #>> '{modos,porque}' = 'sombra' and x.contagens ? 'marcacoes' and x.erros = 0 and x.duracao_ms >= 0) = 1
      and exists (select 1 from public.agenda_marcacoes m join _k k on k.acao = m.acao_id), v_r::text);
    -- K11e a 2ª do dia: já rodou, sem linha nova
    v_r := public.agenda_explicar_rodar(date '2026-11-19', timestamptz '2026-11-19 16:55-03');
    v_res := pg_temp.ok(v_res, 'K11e o 2º tique do dia: {rodou: false, ja_rodou}, sem linha nova',
      v_r = '{"rodou": false, "ja_rodou": true}'::jsonb
      and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje = date '2026-11-19') = 1, v_r::text);
    -- K11f o passo que falha não derruba o outro: app_error_logs (agenda, explicar:marcacoes), a rodada grava e segue
    create or replace function public._agenda_explicar_marcacoes(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $q$
    begin
      raise exception 'quebrado no teste' using errcode = '22023';
    end $q$;
    v_r := public.agenda_explicar_rodar(date '2026-11-20', timestamptz '2026-11-20 16:40-03');
    v_res := pg_temp.ok(v_res, 'K11f o passo marcacoes que falha: erros 1, a falha com o passo, tipos roda, a linha do dia, app_error_logs explicar:marcacoes',
      v_r ->> 'rodou' = 'true' and (v_r ->> 'erros')::int = 1 and v_r #>> '{falhas,0,passo}' = 'marcacoes' and v_r #>> '{falhas,0,sqlstate}' = '22023'
      and v_r -> 'contagens' ? 'tipos' and not (v_r -> 'contagens') ? 'marcacoes' and not v_r ? 'parou_no'
      and exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje = date '2026-11-20' and x.erros = 1)
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'explicar:marcacoes'), v_r::text);
    -- K11g query_canceled: registra, grava parou_no e encerra (tipos não roda); o tique seguinte não repete
    create or replace function public._agenda_explicar_marcacoes(p_hoje date, p_agora timestamptz) returns jsonb language plpgsql as $q$
    begin
      raise exception 'canceling statement due to statement timeout' using errcode = 'query_canceled';
    end $q$;
    v_r := public.agenda_explicar_rodar(date '2026-11-23', timestamptz '2026-11-23 16:40-03');
    v := v_r::text;
    v_r := public.agenda_explicar_rodar(date '2026-11-23', timestamptz '2026-11-23 16:55-03');
    v_res := pg_temp.ok(v_res, 'K11g query_canceled no passo marcacoes: erros 1, parou_no marcacoes, tipos não roda, a linha do dia com parou_no; o tique seguinte = ja_rodou',
      (v::jsonb) ->> 'rodou' = 'true' and ((v::jsonb) ->> 'erros')::int = 1 and (v::jsonb) ->> 'parou_no' = 'marcacoes'
      and not ((v::jsonb) -> 'contagens') ? 'tipos' and (v::jsonb) #>> '{falhas,0,sqlstate}' = '57014'
      and (select count(*) from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje = date '2026-11-23'
              and x.contagens ->> 'parou_no' = 'marcacoes') = 1
      and v_r = '{"rodou": false, "ja_rodou": true}'::jsonb
      and exists (select 1 from public.app_error_logs e where e.context = 'agenda' and e.action = 'explicar:marcacoes'
                     and e.message like '%o tempo da rodada acabou%'), v || ' | ' || v_r::text);
    -- K11h nada a rodar: só o placar fora do dia do plano, e no dia do plano sem a função do placar (P6): sem linha
    update public.agenda_config set modo_porque = 'desligado', modo_rebaixar = 'desligado', modo_placar = 'sombra' where id;
    v_r := public.agenda_explicar_rodar(date '2026-11-24', timestamptz '2026-11-24 16:40-03');
    v := v_r::text;
    v_r := public.agenda_explicar_rodar(date '2026-11-26', timestamptz '2026-11-26 16:40-03');
    v_res := pg_temp.ok(v_res, 'K11h só o placar fora do dia do plano, e no dia do plano sem a função dele (é do P6): {rodou: false, nada}, sem linha',
      v::jsonb = '{"rodou": false, "nada": true}'::jsonb and v_r = '{"rodou": false, "nada": true}'::jsonb
      and to_regprocedure('public._agenda_explicar_placar(date, timestamp with time zone)') is null
      and not exists (select 1 from public.agenda_vigia_rodadas x where x.rotina = 'explicar' and x.p_hoje in (date '2026-11-24', date '2026-11-26')), v || ' | ' || v_r::text);
    -- K11i as portas: o admin com login não tem execute (42501 do grant); com o papel do service_role e o login de um técnico, a porta de dentro (42501); o
    -- service_role sem login roda
    update public.agenda_config set modo_porque = 'sombra' where id;
    v := pg_temp.como(c_admin, 'authenticated', 'select public.agenda_explicar_rodar(date ''2026-11-25'', timestamptz ''2026-11-25 16:40-03'')::text');
    v_res := pg_temp.ok(v_res, 'K11i o admin com login (authenticated) não roda a rodada: 42501', v like 'erro 42501%', v);
    v := pg_temp.como(c_tec, 'service_role', 'select public.agenda_explicar_rodar(date ''2026-11-25'', timestamptz ''2026-11-25 16:40-03'')::text');
    v_res := pg_temp.ok(v_res, 'K11j com o login de um técnico, a porta de dentro: 42501', v like 'erro 42501: A agenda de produção é com o administrador.%', v);
    v := pg_temp.como(null, 'service_role', 'select public.agenda_explicar_rodar(date ''2026-11-25'', timestamptz ''2026-11-25 16:40-03'') ->> ''rodou''');
    v_res := pg_temp.igual(v_res, 'K11k o service_role sem login (o task-automations) roda', v, 'true');
    raise exception using errcode = 'PK001';
  exception when sqlstate 'PK001' then
    null;
  end;
  perform pg_temp.gravar(v_res);
exception when others then
  perform pg_temp.gravar(v_res || jsonb_build_array(jsonb_build_array('K11 o bloco quebrou', false, sqlstate || ': ' || sqlerrm)));
end
$k11$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
