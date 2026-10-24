-- Prova da porta única de status e das datas da OS, Agenda de Produção Fase 2 (pacote P1; migration 20261025100100).
-- bancada: depende de 20261025100100
--
--   P  cada linha da tabela de regras (de → para → caminho → resultado e frase), com o status no banco depois e
--      quantas linhas entraram em agenda_acoes (mudança = 1; nada muda = 0): encerrada e orçamento não mudam;
--      concluir/cancelar não é pela porta; agendar de aberta/aprovada; aguardando peças só com o material na mão;
--      aguardando o cliente só pelo dono, pela tela ou pela aprovação; em andamento nunca volta, de nenhum caminho;
--      a OC em OS em andamento não muda nada; "parou" só do dono com o motivo; tirar de agendada volta ao de antes;
--      as laterais; igual = nada
--   K  o início (check_in_at): gravado uma vez, com a hora dita ou a da porta; nunca sobrescrito
--   L  em modo_proposta 'ligado', agendada só com dia no plano (reserva, dia passado e "não cumprido" não contam)
--   R  o registro em agenda_acoes: tipo status, antes/depois, a frase, o caminho, a origem de cada caminho, o
--      desfazer só do motor/vigia (p_agora + desfazer_validade); nada em ai_lifecycle_events além do gatilho de
--      produção
--   Q  quem pode: admin com login; técnico ligado à OS; técnico não ligado = 42501; sem login, autor obrigatório
--      (menos motor/vigia), ativo e com cargo; JWT de outro papel sem login = 42501; caminho/status/OS que não
--      existem
--   D  o gatilho das datas: desligado e sombra aceitam; ligado recusa a escrita direta (inclusive do técnico, que
--      não lê agenda_config), aceita valor igual e outra coluna, e aceita pela _agenda_escrever_os (a chave volta a
--      off); o espelho escreve o 1º e o último meio-dia vigente (sem reserva nem "não cumprido") e limpa quando a
--      OS sai do plano; fora de ligado não escreve
--   J  portas das funções e o gatilho em service_orders
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261025100100
--   Em produção, só DEPOIS de aplicar as migrations 20261025100000 e 100100, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase2_porta.sql
--   Seguro em produção: o cliente, a unidade, os logins, as pessoas e as OS de teste ("TESTE AG3", OS-TESTE-AG3-*) só
--   são inseridos; o modo da agenda muda só dentro da transação; termina em ROLLBACK. Os gatilhos de status de
--   produção (estoque, ciclo de vida, comissão) rodam nas OS de teste e são desfeitos junto.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.erro_de(p_sql text) returns text language plpgsql as $f$
declare
  v_estado text; v_msg text;
begin
  execute p_sql;
  return 'sem erro';
exception when others then
  get stacked diagnostics v_estado = returned_sqlstate, v_msg = message_text;
  return v_estado || ' ' || v_msg;
end $f$;

-- Executa p_sql (que devolve um valor) como o papel p_papel com o login p_uid: o resultado em texto, ou
-- 'erro <estado>: <mensagem>'. Volta ao dono do teste no fim.
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

-- A OS de teste número n.
create function pg_temp.os(n int) returns uuid language sql immutable as $f$
  select ('c3000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $f$;

-- Chama a porta com o dia e a hora fixos (qui 29/10/2026 16:30) e devolve o que ela disse, mais o status e o início
-- que ficaram no banco e quantas linhas entraram em agenda_acoes para a OS.
create function pg_temp.passa(p_n int, p_para text, p_via text, p_motivo text default null,
                              p_autor uuid default 'a3000000-0000-4000-8000-000000000001',
                              p_check_in timestamptz default null) returns jsonb language plpgsql as $f$
declare
  v_antes bigint := (select count(*) from public.agenda_acoes where service_order_id = pg_temp.os(p_n));
  r jsonb;
begin
  r := public.os_transicionar_status(pg_temp.os(p_n), p_para, p_via, p_motivo, p_autor, p_check_in,
                                     date '2026-10-29', timestamptz '2026-10-29 16:30-03');
  return r || jsonb_build_object(
    'linhas', (select count(*) from public.agenda_acoes where service_order_id = pg_temp.os(p_n)) - v_antes,
    'status', (select status from public.service_orders where id = pg_temp.os(p_n)),
    'check_in_banco', (select check_in_at from public.service_orders where id = pg_temp.os(p_n)));
end $f$;

-- Confere uma resposta da porta: ok, mudou, o status no banco, as linhas novas e a frase (exata, ou "~padrão like").
create function pg_temp.confere(p_teste text, r jsonb, p_ok boolean, p_mudou boolean, p_status text, p_linhas int,
                                p_texto text default null) returns void language plpgsql as $f$
begin
  insert into _resultado values (p_teste,
    coalesce((r ->> 'ok')::boolean = p_ok and (r ->> 'mudou')::boolean = p_mudou and r ->> 'status' = p_status
             and (r ->> 'linhas')::int = p_linhas
             and (p_texto is null or r ->> 'texto' = p_texto
                  or (left(p_texto, 1) = '~' and r ->> 'texto' like substr(p_texto, 2))), false),
    format('ok %s, mudou %s, status %s, linhas %s: %s', r ->> 'ok', r ->> 'mudou', r ->> 'status', r ->> 'linhas', r ->> 'texto'));
end $f$;

select set_config('agenda.hoje', '2026-10-29', true);

-- ── Montagem ────────────────────────────────────────────────────────────────────────────────────────────
do $m$
declare
  v_status text[] := array[
    'completed', 'invoiced', 'cancelled', 'draft', 'open', 'open', 'approved', 'approved', 'awaiting_parts',
    'awaiting_parts', 'awaiting_client', 'in_progress', 'open', 'scheduled', 'in_progress', 'scheduled',
    'awaiting_parts', 'awaiting_client', 'open', 'approved', 'scheduled', 'in_progress', 'awaiting_parts', 'open',
    'open', 'open', 'open', 'approved', 'approved', 'awaiting_client', 'scheduled'];
  i int;
begin
  insert into public.clients (id, type, name) values ('c3a00000-0000-4000-8000-000000000001', 'individual', 'Flávio TESTE AG3');
  insert into public.vessels (id, client_id, name) values ('c3b00000-0000-4000-8000-000000000001', 'c3a00000-0000-4000-8000-000000000001', 'Lancha TESTE AG3');

  insert into public.app_users (id, full_name, email, role, active) values
    ('a3000000-0000-4000-8000-000000000001', 'TESTE AG3 admin', 'teste-ag3-admin@teste.invalid', 'admin', true),
    ('a3000000-0000-4000-8000-000000000002', 'TESTE AG3 técnico', 'teste-ag3-tecnico@teste.invalid', 'technician', true),
    ('a3000000-0000-4000-8000-000000000003', 'TESTE AG3 outro técnico', 'teste-ag3-outro@teste.invalid', 'technician', true),
    ('a3000000-0000-4000-8000-000000000004', 'TESTE AG3 admin inativo', 'teste-ag3-inativo@teste.invalid', 'admin', false);
  insert into public.payees (id, name, kind, active, app_user_id) values
    ('b3000000-0000-4000-8000-000000000002', 'TESTE AG3 Roberto', 'prestador', true, 'a3000000-0000-4000-8000-000000000002'),
    ('b3000000-0000-4000-8000-000000000003', 'TESTE AG3 João', 'prestador', true, null);

  for i in 1 .. cardinality(v_status) loop
    insert into public.service_orders (id, client_id, vessel_id, service_order_number, status, quote_status, check_in_at)
    values (pg_temp.os(i), 'c3a00000-0000-4000-8000-000000000001', 'c3b00000-0000-4000-8000-000000000001',
            'OS-TESTE-AG3-' || lpad(i::text, 2, '0'), v_status[i],
            case when v_status[i] = 'draft' then 'sent' else 'approved' end,
            case when i = 14 then timestamptz '2026-10-20 09:00-03' end);
  end loop;

  -- O técnico está ligado só à OS 25.
  insert into public.service_order_technicians (service_order_id, user_id)
  values (pg_temp.os(25), 'a3000000-0000-4000-8000-000000000002');

  -- OS 09: o compressor ainda falta (o dono contou, sem fornecedor). OS 10: nenhum material conferido.
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, situacao, fonte, critico)
  values ('97300000-0000-4000-8000-000000000009', pg_temp.os(9), 'dono', 'Compressor 12V SS65', 1, 'falta', 'dono', true);
end
$m$;

-- ── P. A tabela de regras ───────────────────────────────────────────────────────────────────────────────
do $p$
declare
  v_via text;
begin
  -- Encerrada e orçamento: a agenda não mexe.
  perform pg_temp.confere('P01 concluída → agendada: recusa', pg_temp.passa(1, 'scheduled', 'dono'), false, false, 'completed', 0,
    'A OS-TESTE-AG3-01 está concluída: a agenda não muda o status dela.');
  perform pg_temp.confere('P01 faturada → em andamento: recusa', pg_temp.passa(2, 'in_progress', 'check_in'), false, false, 'invoiced', 0,
    'A OS-TESTE-AG3-02 está faturada: a agenda não muda o status dela.');
  perform pg_temp.confere('P01 cancelada → agendada: recusa', pg_temp.passa(3, 'scheduled', 'motor', null, null), false, false, 'cancelled', 0,
    'A OS-TESTE-AG3-03 está cancelada: a agenda não muda o status dela.');
  perform pg_temp.confere('P01 orçamento → agendada: recusa', pg_temp.passa(4, 'scheduled', 'tela_agendar'), false, false, 'draft', 0,
    'Isso ainda é orçamento: converta antes.');
  -- Concluir, faturar, cancelar e voltar a orçamento não são pela porta.
  perform pg_temp.confere('P02 aberta → concluída: recusa', pg_temp.passa(5, 'completed', 'dono'), false, false, 'open', 0,
    'Concluir é pela tela (botão Concluir da OS); cancelar é Cancelar OS.');
  perform pg_temp.confere('P02 aberta → faturada: recusa', pg_temp.passa(5, 'invoiced', 'assistente'), false, false, 'open', 0,
    'Concluir é pela tela (botão Concluir da OS); cancelar é Cancelar OS.');
  perform pg_temp.confere('P02 aberta → cancelada: recusa', pg_temp.passa(5, 'cancelled', 'dono'), false, false, 'open', 0,
    'Concluir é pela tela (botão Concluir da OS); cancelar é Cancelar OS.');
  perform pg_temp.confere('P02 aberta → orçamento: recusa', pg_temp.passa(5, 'draft', 'dono'), false, false, 'open', 0,
    'Uma OS não volta a ser orçamento pela agenda.');

  -- Agendar de aberta/aprovada (fora de ligado não precisa de dia no plano).
  perform pg_temp.confere('P03 aberta → agendada (dono)', pg_temp.passa(6, 'scheduled', 'dono'), true, true, 'scheduled', 1,
    'Flávio (OS-TESTE-AG3-06): de aberta para agendada.');
  perform pg_temp.confere('P03 aprovada → agendada (tela de agendar)', pg_temp.passa(7, 'scheduled', 'tela_agendar'), true, true, 'scheduled', 1,
    'Flávio (OS-TESTE-AG3-07): de aprovada para agendada.');
  -- Igual = nada.
  perform pg_temp.confere('P04 agendada → agendada: nada', pg_temp.passa(6, 'scheduled', 'tela_agendar'), true, false, 'scheduled', 0,
    'Flávio (OS-TESTE-AG3-06) já está agendada.');
  -- Tirar de agendada: só a agenda ou o dono, e volta ao de antes.
  perform pg_temp.confere('P05 agendada → aprovada pela tela de agendar: recusa', pg_temp.passa(6, 'approved', 'tela_agendar'), false, false, 'scheduled', 0,
    'A OS está agendada: para tirar da agenda, desmarque o dia.');
  perform pg_temp.confere('P05 agendada → aprovada pelo assistente: recusa', pg_temp.passa(6, 'approved', 'assistente'), false, false, 'scheduled', 0,
    'A OS está agendada: para tirar da agenda, desmarque o dia.');
  perform pg_temp.confere('P05 agendada → aprovada pelo motor: volta ao de antes (aberta)', pg_temp.passa(6, 'approved', 'motor', null, null), true, true, 'open', 1,
    'Flávio (OS-TESTE-AG3-06): de agendada para aberta.');
  perform pg_temp.confere('P05 agendada sem registro de antes → volta a aprovada (vigia)', pg_temp.passa(31, 'open', 'vigia', null, null), true, true, 'approved', 1,
    'Flávio (OS-TESTE-AG3-31): de agendada para aprovada.');

  -- Aguardando peças: só sai com o material na mão.
  perform pg_temp.confere('P06 aguardando peças → agendada com o compressor faltando: continua', pg_temp.passa(9, 'scheduled', 'motor', null, null), true, false, 'awaiting_parts', 0,
    'Ainda falta "Compressor 12V SS65" na mão: a OS continua aguardando peças.');
  update public.os_material set situacao = 'na_mao', quantidade_na_mao = 1, chegou_em = '2026-10-28'
   where id = '97300000-0000-4000-8000-000000000009';
  perform pg_temp.confere('P06 …com o compressor na mão: agendada, com o motivo na frase', pg_temp.passa(9, 'scheduled', 'motor', 'o compressor está na mão.', null), true, true, 'scheduled', 1,
    'Flávio (OS-TESTE-AG3-09): de aguardando peças para agendada — o compressor está na mão.');
  perform pg_temp.confere('P06 aguardando peças sem material conferido → aprovada: continua', pg_temp.passa(10, 'approved', 'dono'), true, false, 'awaiting_parts', 0,
    'O material desta OS ainda não foi conferido (diga se tem peça a comprar): a OS continua aguardando peças.');
  perform pg_temp.confere('P06 …e → agendada também não', pg_temp.passa(10, 'scheduled', 'tela_agendar'), true, false, 'awaiting_parts', 0,
    'O material desta OS ainda não foi conferido (diga se tem peça a comprar): a OS continua aguardando peças.');

  -- Aguardando o cliente: só pelo dono, pela tela de agendar ou pela aprovação.
  perform pg_temp.confere('P07 aguardando o cliente → agendada pelo motor: continua', pg_temp.passa(11, 'scheduled', 'motor', null, null), true, false, 'awaiting_client', 0,
    'O cliente ainda não liberou: a OS continua aguardando o cliente.');
  perform pg_temp.confere('P07 aguardando o cliente → agendada pela aprovação', pg_temp.passa(11, 'scheduled', 'aprovacao'), true, true, 'scheduled', 1,
    'Flávio (OS-TESTE-AG3-11): de aguardando o cliente para agendada.');
  perform pg_temp.confere('P07 aguardando o cliente → aprovada pela vigia: continua', pg_temp.passa(30, 'approved', 'vigia', null, null), true, false, 'awaiting_client', 0,
    'O cliente ainda não liberou: a OS continua aguardando o cliente.');
  perform pg_temp.confere('P07 aguardando o cliente → aprovada pelo dono', pg_temp.passa(30, 'approved', 'dono'), true, true, 'approved', 1,
    'Flávio (OS-TESTE-AG3-30): de aguardando o cliente para aprovada.');

  -- Em andamento nunca volta, de nenhum caminho.
  foreach v_via in array array['tela_agendar', 'aprovacao', 'assistente', 'check_in', 'oc', 'motor', 'vigia', 'conferencia', 'dono', 'desfazer'] loop
    perform pg_temp.confere(format('P08 em andamento → agendada (%s): continua', v_via), pg_temp.passa(12, 'scheduled', v_via), true, false, 'in_progress', 0,
      'A OS já começou: não volta para agendada.');
    perform pg_temp.confere(format('P08 em andamento → aprovada (%s): continua', v_via), pg_temp.passa(12, 'approved', v_via), true, false, 'in_progress', 0,
      'A OS já começou: não volta para aprovada.');
    perform pg_temp.confere(format('P08 em andamento → aberta (%s): continua', v_via), pg_temp.passa(12, 'open', v_via), true, false, 'in_progress', 0,
      'A OS já começou: não volta para aberta.');
  end loop;

  -- Começar: de aberta, aprovada, agendada e das duas esperas.
  perform pg_temp.confere('P09 agendada → em andamento', pg_temp.passa(16, 'in_progress', 'conferencia'), true, true, 'in_progress', 1,
    'Flávio (OS-TESTE-AG3-16): de agendada para em andamento (qui 29/10 às 16:30).');
  perform pg_temp.confere('P09 aguardando peças → em andamento', pg_temp.passa(17, 'in_progress', 'check_in'), true, true, 'in_progress', 1, null);
  perform pg_temp.confere('P09 aguardando o cliente → em andamento', pg_temp.passa(18, 'in_progress', 'dono'), true, true, 'in_progress', 1, null);

  -- Aguardar: de aberta, aprovada, agendada, e a lateral entre as duas esperas.
  perform pg_temp.confere('P10 aberta → aguardando peças (OC)', pg_temp.passa(19, 'awaiting_parts', 'oc'), true, true, 'awaiting_parts', 1,
    'Flávio (OS-TESTE-AG3-19): de aberta para aguardando peças.');
  perform pg_temp.confere('P10 aprovada → aguardando o cliente', pg_temp.passa(20, 'awaiting_client', 'assistente'), true, true, 'awaiting_client', 1, null);
  perform pg_temp.confere('P10 agendada → aguardando peças', pg_temp.passa(21, 'awaiting_parts', 'vigia', null, null), true, true, 'awaiting_parts', 1, null);
  perform pg_temp.confere('P10 aguardando peças → aguardando o cliente (lateral; pelo desfazer)', pg_temp.passa(23, 'awaiting_client', 'desfazer'), true, true, 'awaiting_client', 1, null);
  perform pg_temp.confere('P10 aberta → aprovada (lateral)', pg_temp.passa(24, 'approved', 'assistente'), true, true, 'approved', 1,
    'Flávio (OS-TESTE-AG3-24): de aberta para aprovada.');

  -- Em andamento → aguardando: a OC não muda nada; só o "parou" do dono, com o motivo.
  perform pg_temp.confere('P11 em andamento → aguardando peças pela OC: segue em andamento, sem erro', pg_temp.passa(22, 'awaiting_parts', 'oc'), true, false, 'in_progress', 0,
    'A OS segue em andamento; a compra foi registrada.');
  perform pg_temp.confere('P11 em andamento → aguardando peças pelo motor: recusa', pg_temp.passa(22, 'awaiting_parts', 'motor', 'falta peça', null), false, false, 'in_progress', 0,
    'A OS já começou: só volta a aguardar quando você diz que parou e por quê.');
  perform pg_temp.confere('P11 em andamento → aguardando o cliente pelo dono sem motivo: recusa', pg_temp.passa(22, 'awaiting_client', 'dono', '  '), false, false, 'in_progress', 0,
    'A OS já começou: só volta a aguardar quando você diz que parou e por quê.');
  perform pg_temp.confere('P11 em andamento → aguardando peças pelo dono com o motivo ("parou")', pg_temp.passa(22, 'awaiting_parts', 'dono', 'parou: falta o cabo de 50 mm'), true, true, 'awaiting_parts', 1,
    'Flávio (OS-TESTE-AG3-22): de em andamento para aguardando peças — parou: falta o cabo de 50 mm.');
end
$p$;

-- ── K. O início (check_in_at) ───────────────────────────────────────────────────────────────────────────
do $k$
declare
  r jsonb;
begin
  r := pg_temp.passa(13, 'in_progress', 'check_in', null, 'a3000000-0000-4000-8000-000000000001', timestamptz '2026-11-03 08:10-03');
  perform pg_temp.confere('K1 aberta → em andamento com a hora dita', r, true, true, 'in_progress', 1,
    'Flávio (OS-TESTE-AG3-13): de aberta para em andamento (ter 03/11 às 08:10).');
  insert into _resultado values ('K1 …o início gravado é a hora dita', (r ->> 'check_in_banco')::timestamptz = timestamptz '2026-11-03 08:10-03', r ->> 'check_in_banco');

  r := pg_temp.passa(14, 'in_progress', 'check_in', null, 'a3000000-0000-4000-8000-000000000001', timestamptz '2026-11-03 08:10-03');
  perform pg_temp.confere('K2 agendada com início já gravado → em andamento', r, true, true, 'in_progress', 1,
    'Flávio (OS-TESTE-AG3-14): de agendada para em andamento.');
  insert into _resultado values ('K2 …o início de antes fica (nunca sobrescrito)', (r ->> 'check_in_banco')::timestamptz = timestamptz '2026-10-20 09:00-03', r ->> 'check_in_banco');

  r := pg_temp.passa(16, 'in_progress', 'conferencia');
  insert into _resultado values ('K3 sem hora dita, o início é o p_agora da porta (qui 29/10 16:30)',
    (r ->> 'check_in_banco')::timestamptz = timestamptz '2026-10-29 16:30-03', r ->> 'check_in_banco');

  r := pg_temp.passa(15, 'in_progress', 'conferencia', null, 'a3000000-0000-4000-8000-000000000001', timestamptz '2026-10-28 13:00-03');
  perform pg_temp.confere('K4 em andamento sem início: grava o início (o status fica)', r, true, true, 'in_progress', 1,
    'Flávio (OS-TESTE-AG3-15): início registrado (qua 28/10 às 13:00).');
  insert into _resultado values ('K4 …com a hora dita', (r ->> 'check_in_banco')::timestamptz = timestamptz '2026-10-28 13:00-03', r ->> 'check_in_banco');
  r := pg_temp.passa(15, 'in_progress', 'conferencia', null, 'a3000000-0000-4000-8000-000000000001', timestamptz '2026-10-29 08:00-03');
  perform pg_temp.confere('K4 em andamento com início: nada (o início fica)', r, true, false, 'in_progress', 0,
    'Flávio (OS-TESTE-AG3-15) já está em andamento.');
  insert into _resultado values ('K4 …o início continua o de qua 28/10 13:00', (r ->> 'check_in_banco')::timestamptz = timestamptz '2026-10-28 13:00-03', r ->> 'check_in_banco');

  -- A escrita de baixo também nunca sobrescreve o início.
  perform public._agenda_escrever_os(pg_temp.os(14), null, timestamptz '2026-12-01 08:00-03', null, null, false);
  insert into _resultado values ('K5 _agenda_escrever_os não sobrescreve o início',
    (select check_in_at from public.service_orders where id = pg_temp.os(14)) = timestamptz '2026-10-20 09:00-03', null);
end
$k$;

-- ── L. Com a agenda automática ligada, agendada só com dia no plano ─────────────────────────────────────
do $l$
declare
  v_rob  uuid := 'b3000000-0000-4000-8000-000000000002';
  v_joao uuid := 'b3000000-0000-4000-8000-000000000003';
begin
  update public.agenda_config set modo_proposta = 'ligado';
  perform pg_temp.confere('L1 ligado, aprovada → agendada sem dia no plano: continua', pg_temp.passa(8, 'scheduled', 'tela_agendar'), true, false, 'approved', 0,
    'Sem dia no plano: a OS continua aprovada.');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, reserva_de, estado)
  values (pg_temp.os(8), v_rob, '2026-11-03', 'manha', 'reserva', 'teto', 'publicada');
  perform pg_temp.confere('L1 …só com reserva: continua', pg_temp.passa(8, 'scheduled', 'tela_agendar'), true, false, 'approved', 0,
    'Sem dia no plano: a OS continua aprovada.');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (pg_temp.os(8), v_rob, '2026-10-27', 'tarde', 'publicada');
  perform pg_temp.confere('L1 …só com dia que já passou: continua', pg_temp.passa(8, 'scheduled', 'motor', null, null), true, false, 'approved', 0,
    'Sem dia no plano: a OS continua aprovada.');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, resultado, motivo)
  values (pg_temp.os(8), v_joao, '2026-10-29', 'manha', 'publicada', 'nao_cumprido', 'clima');
  perform pg_temp.confere('L1 …com o dia de hoje "não cumprido": continua', pg_temp.passa(8, 'scheduled', 'motor', null, null), true, false, 'approved', 0,
    'Sem dia no plano: a OS continua aprovada.');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (pg_temp.os(8), v_joao, '2026-11-04', 'tarde', 'publicada');
  perform pg_temp.confere('L1 …com um meio-dia publicado de hoje em diante: agendada', pg_temp.passa(8, 'scheduled', 'motor', null, null), true, true, 'scheduled', 1,
    'Flávio (OS-TESTE-AG3-08): de aprovada para agendada.');
  perform pg_temp.confere('L2 agendada com dia no plano → aprovada pelo motor: recusa', pg_temp.passa(8, 'approved', 'motor', null, null), false, false, 'scheduled', 0,
    'A OS ainda tem dia no plano: tire o dia antes.');
  update public.agenda_config set modo_proposta = 'desligado';
end
$l$;

-- ── R. O registro ───────────────────────────────────────────────────────────────────────────────────────
insert into _resultado
select 'R1 a mudança deixa a linha certa: tipo status, executada, antes/depois, o dia, a OS, quem pediu, sem desfazer (foi o dono)',
       a.tipo = 'status' and a.executada and not a.critica and a.origem = 'dono' and a.status_antes = 'open'
       and a.status_depois = 'scheduled' and a.dia = date '2026-10-29' and a.os_ids = array[pg_temp.os(6)]
       and a.autor = 'a3000000-0000-4000-8000-000000000001' and a.desfazivel_ate is null
       and a.antes ->> 'status' = 'open' and a.depois ->> 'status' = 'scheduled' and a.depois ->> 'via' = 'dono'
       and a.texto = 'Flávio (OS-TESTE-AG3-06): de aberta para agendada.',
       row_to_json(a)::text
  from public.agenda_acoes a
 where a.service_order_id = pg_temp.os(6) and a.status_depois = 'scheduled';

insert into _resultado
select 'R2 a mudança do motor é desfazível até p_agora + desfazer_validade (sex 30/10 16:30), sem autor',
       a.origem = 'motor' and a.desfazivel_ate = timestamptz '2026-10-30 16:30-03' and a.autor is null,
       format('%s %s %s', a.origem, a.desfazivel_ate, a.autor)
  from public.agenda_acoes a
 where a.service_order_id = pg_temp.os(6) and a.status_antes = 'scheduled';

insert into _resultado
select format('R3 o caminho %s fica como origem %s', x.via, x.origem),
       exists (select 1 from public.agenda_acoes a
                where a.service_order_id = pg_temp.os(x.n) and a.tipo = 'status' and a.origem = x.origem
                  and a.depois ->> 'via' = x.via),
       (select string_agg(a.origem || '/' || (a.depois ->> 'via'), ', ') from public.agenda_acoes a where a.service_order_id = pg_temp.os(x.n))
  from (values (6, 'dono', 'dono'), (7, 'tela_agendar', 'tela'), (11, 'aprovacao', 'aprovacao'), (24, 'assistente', 'assistente'),
               (13, 'check_in', 'sistema'), (19, 'oc', 'sistema'), (16, 'conferencia', 'conferencia'), (6, 'motor', 'motor'),
               (31, 'vigia', 'vigia'), (23, 'desfazer', 'dono')) as x(n, via, origem);

insert into _resultado
select 'R4 só motor e vigia ganham prazo de desfazer',
       bool_and((a.desfazivel_ate is not null) = (a.origem in ('motor', 'vigia'))),
       string_agg(a.origem || ':' || coalesce(a.desfazivel_ate::text, '-'), ', ')
  from public.agenda_acoes a join public.service_orders so on so.id = a.service_order_id
 where so.service_order_number like 'OS-TESTE-AG3-%';

insert into _resultado
select 'R5 a porta não escreve em ai_lifecycle_events (fora o status_change do gatilho de produção)', count(*) = 0, count(*)::text
  from public.ai_lifecycle_events e join public.service_orders so on so.id = e.entity_id
 where so.service_order_number like 'OS-TESTE-AG3-%' and e.event_type <> 'status_change';

-- ── Q. Quem pode ────────────────────────────────────────────────────────────────────────────────────────
do $q$
declare
  v_admin  uuid := 'a3000000-0000-4000-8000-000000000001';
  v_tec    uuid := 'a3000000-0000-4000-8000-000000000002';
  v_outro  uuid := 'a3000000-0000-4000-8000-000000000003';
  v_inativo uuid := 'a3000000-0000-4000-8000-000000000004';
  v text;
  porta constant text := $s$select (public.os_transicionar_status(%L, %L, %L, null, %L, null, date '2026-10-29', timestamptz '2026-10-29 16:30-03') ->> 'mudou')$s$;
begin
  v := pg_temp.como(v_tec, 'authenticated', format(porta, pg_temp.os(25), 'in_progress', 'check_in', null));
  insert into _resultado values ('Q1 o técnico ligado à OS dá o início pelo painel', v = 'true'
    and (select status from public.service_orders where id = pg_temp.os(25)) = 'in_progress'
    and (select autor from public.agenda_acoes where service_order_id = pg_temp.os(25)) = v_tec, v);
  v := pg_temp.como(v_outro, 'authenticated', format(porta, pg_temp.os(26), 'in_progress', 'check_in', null));
  insert into _resultado values ('Q2 o técnico que não é da OS: 42501', v = 'erro 42501: Você não pode mudar o status desta OS.', v);
  v := pg_temp.como(v_admin, 'authenticated', format(porta, pg_temp.os(27), 'scheduled', 'tela_agendar', v_outro));
  insert into _resultado values ('Q3 o admin pelo painel: vale o login, não o p_autor', v = 'true'
    and (select autor from public.agenda_acoes where service_order_id = pg_temp.os(27)) = v_admin, v);
  v := pg_temp.como(v_inativo, 'authenticated', format(porta, pg_temp.os(26), 'scheduled', 'dono', null));
  insert into _resultado values ('Q4 admin com o login desligado: 42501', v = 'erro 42501: Você não pode mudar o status desta OS.', v);

  -- Sem login (service role, o próprio banco): p_autor obrigatório, menos motor e vigia; ativo e com cargo.
  v := pg_temp.erro_de(format($s$select public.os_transicionar_status(%L, 'scheduled', 'dono', null, null, null, date '2026-10-29', now())$s$, pg_temp.os(26)));
  insert into _resultado values ('Q5 sem login e sem autor, pelo dono: 42501', v = '42501 Você não pode mudar o status desta OS.', v);
  v := pg_temp.erro_de(format($s$select public.os_transicionar_status(%L, 'scheduled', 'dono', null, %L, null, date '2026-10-29', now())$s$, pg_temp.os(26), v_inativo));
  insert into _resultado values ('Q5 autor inativo: 42501', v = '42501 Você não pode mudar o status desta OS.', v);
  v := pg_temp.erro_de(format($s$select public.os_transicionar_status(%L, 'in_progress', 'check_in', null, %L, null, date '2026-10-29', now())$s$, pg_temp.os(26), v_outro));
  insert into _resultado values ('Q5 autor técnico que não é da OS: 42501', v = '42501 Você não pode mudar o status desta OS.', v);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  v := pg_temp.erro_de(format($s$select public.os_transicionar_status(%L, 'scheduled', 'motor', null, null, null, date '2026-10-29', now())$s$, pg_temp.os(26)));
  perform set_config('request.jwt.claims', '', true);
  insert into _resultado values ('Q6 um JWT de outro papel sem login não vale, nem pelo motor: 42501', v = '42501 Você não pode mudar o status desta OS.', v);
  insert into _resultado values ('Q6 …e nada mudou na OS', (select status from public.service_orders where id = pg_temp.os(26)) = 'open', null);

  -- O que não existe.
  v := pg_temp.erro_de(format($s$select public.os_transicionar_status(%L, 'scheduled', 'chute')$s$, pg_temp.os(26)));
  insert into _resultado values ('Q7 caminho que não existe: 22023', v = '22023 Caminho desconhecido para mudar o status: "chute".', v);
  v := pg_temp.erro_de(format($s$select public.os_transicionar_status(%L, 'pending', 'dono', null, %L)$s$, pg_temp.os(26), v_admin));
  insert into _resultado values ('Q7 status que não existe: 22023', v = '22023 Status desconhecido: "pending".', v);
  v := pg_temp.erro_de(format($s$select public.os_transicionar_status(gen_random_uuid(), 'scheduled', 'motor')$s$));
  insert into _resultado values ('Q7 OS que não existe: P0002', v = 'P0002 Não encontrei a OS.', v);
end
$q$;

-- ── D. O gatilho das datas e o espelho ──────────────────────────────────────────────────────────────────
do $d$
declare
  v_rob  uuid := 'b3000000-0000-4000-8000-000000000002';
  v_joao uuid := 'b3000000-0000-4000-8000-000000000003';
  v_tec  uuid := 'a3000000-0000-4000-8000-000000000002';
  c_msg constant text := 'P0001 Com a agenda automática ligada, a data da OS é da agenda. Para mudar, diga na conversa (por exemplo "passa o Lenine para quinta") ou use Agendar na tela da Agenda.';
  v text; r jsonb; a uuid; b uuid;
begin
  update public.agenda_config set modo_proposta = 'desligado';
  v := pg_temp.erro_de(format($s$update public.service_orders set scheduled_start_at = '2026-11-03 08:00-03', scheduled_end_at = '2026-11-03 17:00-03' where id = %L$s$, pg_temp.os(28)));
  insert into _resultado values ('D1 desligado: a data muda direto, como hoje', v = 'sem erro', v);
  update public.agenda_config set modo_proposta = 'sombra';
  v := pg_temp.erro_de(format($s$update public.service_orders set scheduled_start_at = '2026-11-04 08:00-03', scheduled_end_at = '2026-11-04 17:00-03' where id = %L$s$, pg_temp.os(28)));
  insert into _resultado values ('D1 sombra: a data muda direto, como hoje', v = 'sem erro', v);

  update public.agenda_config set modo_proposta = 'ligado';
  v := pg_temp.erro_de(format($s$update public.service_orders set scheduled_start_at = '2026-11-05 08:00-03' where id = %L$s$, pg_temp.os(28)));
  insert into _resultado values ('D2 ligado: mudar o início direto é recusado, com a frase', v = c_msg, v);
  v := pg_temp.erro_de(format($s$update public.service_orders set scheduled_end_at = null where id = %L$s$, pg_temp.os(28)));
  insert into _resultado values ('D2 ligado: apagar o fim direto é recusado', v = c_msg, v);
  v := pg_temp.erro_de(format($s$update public.service_orders set scheduled_start_at = '2026-11-04 08:00-03', scheduled_end_at = '2026-11-04 17:00-03', internal_notes = 'salvei o formulário' where id = %L$s$, pg_temp.os(28)));
  insert into _resultado values ('D3 ligado: o formulário que salva a mesma data passa', v = 'sem erro', v);
  v := pg_temp.erro_de(format($s$update public.service_orders set problem_description = 'outra coisa' where id = %L$s$, pg_temp.os(28)));
  insert into _resultado values ('D3 ligado: mudar outra coisa da OS passa', v = 'sem erro', v);
  v := pg_temp.como(v_tec, 'authenticated', format($s$update public.service_orders set scheduled_start_at = '2026-11-06 08:00-03' where id = %L returning 1$s$, pg_temp.os(25)));
  insert into _resultado values ('D4 ligado: o técnico (que não lê agenda_config) também é barrado',
    v = 'erro P0001: ' || substr(c_msg, 7), v);
  v := pg_temp.erro_de(format($s$select public._agenda_escrever_os(%L, null, null, '2026-11-05 08:00-03', '2026-11-05 17:00-03', true)$s$, pg_temp.os(28)));
  insert into _resultado values ('D5 ligado: pela _agenda_escrever_os a data muda',
    v = 'sem erro' and (select scheduled_start_at = timestamptz '2026-11-05 08:00-03' and scheduled_end_at = timestamptz '2026-11-05 17:00-03'
                          from public.service_orders where id = pg_temp.os(28)), v);
  insert into _resultado values ('D5 …e a chave volta a off', current_setting('agenda.porta', true) = 'off', current_setting('agenda.porta', true));
  v := pg_temp.erro_de(format($s$update public.service_orders set scheduled_start_at = '2026-11-09 08:00-03' where id = %L$s$, pg_temp.os(28)));
  insert into _resultado values ('D5 …e depois dela a escrita direta volta a ser recusada', v = c_msg, v);

  -- O espelho: em sombra não escreve; em ligado, o 1º e o último meio-dia vigente, sem reserva nem "não cumprido".
  update public.agenda_config set modo_proposta = 'sombra';
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado, resultado, motivo)
  values (pg_temp.os(29), v_rob, '2026-10-27', 'manha', 'publicada', 'nao_cumprido', 'cliente_ou_bem');
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (pg_temp.os(29), v_rob, '2026-11-10', 'manha', 'publicada') returning id into a;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, estado)
  values (pg_temp.os(29), v_joao, '2026-11-11', 'tarde', 'publicada') returning id into b;
  insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, reserva_de, estado)
  values (pg_temp.os(29), v_rob, '2026-11-12', 'manha', 'reserva', 'teto', 'publicada');
  r := public._agenda_espelhar_datas(pg_temp.os(29), date '2026-10-29');
  insert into _resultado values ('D6 sombra: o espelho não escreve nada',
    (r ->> 'mudou')::boolean = false and r ->> 'modo' = 'sombra'
    and (select scheduled_start_at is null and scheduled_end_at is null from public.service_orders where id = pg_temp.os(29)), r::text);

  update public.agenda_config set modo_proposta = 'ligado';
  r := public._agenda_espelhar_datas(pg_temp.os(29), date '2026-10-29');
  insert into _resultado values ('D7 ligado: espelho = ter 10/11 08:00 a qua 11/11 17:00 (sem a reserva de qui 12 nem o "não cumprido" de 27/10)',
    (r ->> 'mudou')::boolean
    and (select scheduled_start_at = timestamptz '2026-11-10 08:00-03' and scheduled_end_at = timestamptz '2026-11-11 17:00-03'
           from public.service_orders where id = pg_temp.os(29)), r::text);
  r := public._agenda_espelhar_datas(pg_temp.os(29), date '2026-10-29');
  insert into _resultado values ('D7 de novo, sem mudança: não escreve', (r ->> 'mudou')::boolean = false, r::text);
  update public.agenda_alocacoes set estado = 'cancelada', cancelada_motivo = 'replanejado' where id in (a, b);
  r := public._agenda_espelhar_datas(pg_temp.os(29), date '2026-10-29');
  insert into _resultado values ('D8 a OS saiu do plano: as duas datas ficam vazias',
    (r ->> 'mudou')::boolean
    and (select scheduled_start_at is null and scheduled_end_at is null from public.service_orders where id = pg_temp.os(29)), r::text);
  insert into _resultado values ('D8 …e a chave voltou a off', current_setting('agenda.porta', true) = 'off', current_setting('agenda.porta', true));
  r := public._agenda_espelhar_datas(pg_temp.os(5), date '2026-10-29');
  insert into _resultado values ('D9 OS sem data e sem plano: não escreve', (r ->> 'mudou')::boolean = false, r::text);
  v := pg_temp.erro_de($s$select public._agenda_espelhar_datas(gen_random_uuid(), date '2026-10-29')$s$);
  insert into _resultado values ('D9 OS que não existe: P0002', v = 'P0002 Não encontrei a OS.', v);
  update public.agenda_config set modo_proposta = 'desligado';
end
$d$;

-- ── J. Portas das funções e o gatilho ───────────────────────────────────────────────────────────────────
insert into _resultado values
  ('J1 a porta: authenticated e service_role executam; anon nunca',
   has_function_privilege('authenticated', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz)', 'execute')
   and has_function_privilege('service_role', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz)', 'execute')
   and not has_function_privilege('anon', 'public.os_transicionar_status(uuid, text, text, text, uuid, timestamptz, date, timestamptz)', 'execute'), null);

insert into _resultado
select 'J2 a chave das datas: _agenda_escrever_os e _agenda_espelhar_datas sem grant a ninguém (nem service_role)',
       bool_and(not has_function_privilege(papel, f::regprocedure, 'execute')),
       string_agg(papel || ' ' || f, ', ') filter (where has_function_privilege(papel, f::regprocedure, 'execute'))
  from unnest(array['public._agenda_escrever_os(uuid, text, timestamptz, timestamptz, timestamptz, boolean)',
                    'public._agenda_espelhar_datas(uuid, date)']) f
 cross join unnest(array['anon', 'authenticated', 'service_role']) papel;

insert into _resultado
select 'J3 auxiliares de leitura: authenticated e service_role; anon nunca; a função do gatilho, de ninguém',
       bool_and(case when f like '%_so_datas_pela_agenda%'
                     then not has_function_privilege('anon', f::regprocedure, 'execute')
                          and not has_function_privilege('authenticated', f::regprocedure, 'execute')
                     else has_function_privilege('authenticated', f::regprocedure, 'execute')
                          and has_function_privilege('service_role', f::regprocedure, 'execute')
                          and not has_function_privilege('anon', f::regprocedure, 'execute') end),
       null
  from unnest(array['public._agenda_status_texto(text)', 'public._agenda_os_tem_dia(uuid, date)',
                    'public._agenda_falta_material(uuid, date)', 'public._agenda_porta_fica(boolean, text, text)',
                    'public._so_datas_pela_agenda()']) f;

insert into _resultado
select 'J4 security definer: a porta, a escrita, o espelho e o gatilho; as auxiliares não; search_path fixo',
       count(*) = 8
       and bool_and(p.prosecdef = (p.proname in ('os_transicionar_status', '_agenda_escrever_os', '_agenda_espelhar_datas',
                                                 '_so_datas_pela_agenda')))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text, ', ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('os_transicionar_status', '_agenda_escrever_os', '_agenda_espelhar_datas', '_so_datas_pela_agenda',
                     '_agenda_status_texto', '_agenda_os_tem_dia', '_agenda_falta_material', '_agenda_porta_fica');

insert into _resultado
select 'J5 o gatilho trg_so_datas_pela_agenda: BEFORE UPDATE OF scheduled_start_at, scheduled_end_at, por linha, ligado',
       count(*) = 1 and bool_and(t.tgenabled = 'O')
       and bool_and(pg_get_triggerdef(t.oid) like 'CREATE TRIGGER trg_so_datas_pela_agenda BEFORE UPDATE OF scheduled_start_at, scheduled_end_at ON public.service_orders FOR EACH ROW EXECUTE FUNCTION _so_datas_pela_agenda()'
                    or pg_get_triggerdef(t.oid) like 'CREATE TRIGGER trg_so_datas_pela_agenda BEFORE UPDATE OF scheduled_start_at, scheduled_end_at ON public.service_orders FOR EACH ROW EXECUTE FUNCTION public._so_datas_pela_agenda()'),
       string_agg(pg_get_triggerdef(t.oid), ' | ')
  from pg_trigger t
 where t.tgrelid = 'public.service_orders'::regclass and t.tgname = 'trg_so_datas_pela_agenda' and not t.tgisinternal;

insert into _resultado
select 'J6 o status em português, como a tela (os 10 do CHECK)',
       string_agg(public._agenda_status_texto(s), '|' order by o)
         = 'orçamento|agendada|aberta|em andamento|aguardando peças|aguardando o cliente|aprovada|concluída|faturada|cancelada',
       string_agg(public._agenda_status_texto(s), '|' order by o)
  from unnest(array['draft', 'scheduled', 'open', 'in_progress', 'awaiting_parts', 'awaiting_client', 'approved',
                    'completed', 'invoiced', 'cancelled']) with ordinality t(s, o);

select teste, ok, detalhe from _resultado order by teste;

rollback;
