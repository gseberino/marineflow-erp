-- Prova do rascunho dos pedidos do dono pela conversa (Agenda de Produção, Fase 2, pacote P4; migration 20261025100400).
-- bancada: depende de 20261025100400
--
-- Sobre o cenário à mão do motor (scripts/bancada-agenda/cenario-motor.sql: qui 29/10/2026; A = Antônio OS-00201, 2 dias
-- de ter 03 a qua 04/11; B = Beatriz OS-00202, diagnóstico na qui 05/11 de manhã; C = Caio OS-00203, reserva
-- condicionada à compra) publicado pela vigia na qui 29/10 às 16:30, com uma OS a mais quando o caso precisa (D = Daniel
-- OS-00204, 1 dia com o Roberto; E = Elisa OS-00205, precisa até qua 04/11):
--   M  marcar: nada muda antes do *grava*; o *grava* marca (fixada pelo dono, agendada, a data no espelho); a correção
--      substitui a linha; não cabe = a pergunta com o 1º dia que dá; em teste = só a simulação
--   P  publicar: a proposta aberta pela agenda_propor_dito; nada muda antes; o *grava* publica; a agenda que mudou
--      (proposta velha) não grava nada
--   D  decidir: sem a opção a pergunta volta (o banco não escolhe); a releitura; o *grava* responde (critica = true com
--      pergunta_id, respondida_via); opção que não existe
--   X  desfazer: nada muda antes; o *grava* desfaz; expirado não grava; o que já começou não se desfaz
--   A  andamento: trabalhou + não foi numa linha só; o *grava* anota (cumprido, não cumprido com o motivo, em andamento);
--      começou; parou (aguardando peças, sai da agenda o que não começou); concluir recusado; motivo pedido; técnico 42501
--   L  lote: um item recusado no *grava* não deixa gravar nada (nem o fato da Fase 1)
--   F  fora de ligado: o lote com pedido à agenda não grava
--   G  planejar: adiantavel_patio (o número no trecho, o máximo, limpar) e a coluna gravada
--   S  agenda_propor_dito: simular não grava; tirar; OS que não existe; escopo que não existe
--   T  paridade de statusAoAgendar com a porta (via tela_agendar, fora de ligado) — src/test/porta-unica-status.test.ts lê
--      a lista marcada abaixo e cobra a mesma tabela de service-order-status.ts
-- Sempre (com ou sem as fixtures):
--   J  portas: anon sem nada; os pedidos para authenticated e service_role; as internas só service_role; o CHECK do tipo
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261025100400
--   Em produção, só DEPOIS de aplicar 20261025100000..100400, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase2_rascunho.sql
--   Sem as fixtures (produção) os cenários saem PULADO e só J roda. Os cenários mexem em linhas só dentro de
--   subtransações desfeitas na hora; termina em ROLLBACK.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp.ok(p_res jsonb, p_nome text, p_ok boolean, p_detalhe text default null) returns jsonb
language sql immutable as $f$
  select p_res || jsonb_build_array(jsonb_build_array(p_nome, coalesce(p_ok, false), p_detalhe))
$f$;
create function pg_temp.gravar(p_res jsonb) returns void language sql as $f$
  insert into _resultado select e ->> 0, (e ->> 1)::boolean, e ->> 2 from jsonb_array_elements(p_res) e
$f$;
create function pg_temp.os(p_n text) returns uuid language sql immutable as $f$
  select ('05000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid
$f$;
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
-- As células vigentes de uma OS: "03/11 manha Roberto turno [resultado]".
create function pg_temp.vigentes(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(to_char(a.dia, 'DD/MM') || ' ' || a.turno || ' ' || public._agenda_nome_curto(py.name) || ' ' || a.presenca
                             || coalesce(' ' || a.resultado, ''),
                             ' | ' order by a.dia, a.turno = 'tarde', public._agenda_nome_curto(py.name), a.presenca), '')
    from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
$f$;
-- Uma foto do que o rascunho NÃO pode tocar antes do *grava*: o plano (todas as alocações, em qualquer estado), as
-- ações, as propostas, as perguntas (estado) e o status/datas das OS.
create function pg_temp.foto() returns text language sql stable as $f$
  select md5(concat_ws('#',
    (select string_agg(a.id::text || a.estado || coalesce(a.resultado, '-'), ',' order by a.id) from public.agenda_alocacoes a),
    (select count(*)::text from public.agenda_acoes),
    (select string_agg(p.id::text || p.estado, ',' order by p.id) from public.agenda_propostas p),
    (select string_agg(q.id::text || q.estado, ',' order by q.id) from public.agenda_perguntas q),
    (select string_agg(so.id::text || so.status || coalesce(so.scheduled_start_at::text, '-') || coalesce(so.check_in_at::text, '-'),
                       ',' order by so.id) from public.service_orders so),
    (select string_agg(pl.service_order_id::text || coalesce(pl.prioridade_manual::text, '-') || coalesce(pl.adiantavel_patio_dias::text, '-'),
                       ',' order by pl.service_order_id) from public.os_planejamento pl),
    (select (versao_plano)::text from public.agenda_config where id)))
$f$;
create function pg_temp.cenario() returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.cenario_motor');
end $f$;
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia where id
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O *grava* na hora dada (a hora do *grava* é now(); a bancada a fixa por agenda.agora, como agenda.hoje).
create function pg_temp.grava(p_autor uuid, p_dia date, p_hora text) returns jsonb language plpgsql as $f$
begin
  perform set_config('agenda.agora', pg_temp.em(p_dia, p_hora)::text, true);
  return public.agenda_rascunho_gravar(p_autor, p_dia);
end $f$;
-- Uma OS a mais no cenário (o molde do teste do motor): sinal pago, aprovada em 20/10, com os dias, a equipe e (se dita)
-- até quando o cliente precisa; p_status para a paridade com a porta.
create function pg_temp.os_extra(p_n text, p_cliente text, p_dias numeric, p_presenca text, p_equipe jsonb,
                                 p_precisa date default null, p_status text default 'approved',
                                 p_conferido boolean default true) returns uuid language plpgsql as $f$
declare
  v_os uuid := pg_temp.os(p_n);
  v_cl uuid := ('c4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid;
  e jsonb;
begin
  insert into public.clients (id, type, name) values (v_cl, 'individual', p_cliente);
  insert into public.vessels (id, client_id, name, asset_type) values (('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, v_cl, 'Lancha', 'Lancha');
  insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                     created_at, updated_at, converted_to_os_at, grand_total)
  values (v_os, case when p_status = 'draft' then 'ORÇ-' else 'OS-' end || lpad(p_n, 5, '0'), v_cl,
          ('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, p_status, 'approved',
          'repair', timestamptz '2026-10-15 12:00-03', timestamptz '2026-10-20 12:00-03',
          case when p_status <> 'draft' then timestamptz '2026-10-20 12:00-03' end, 2160);
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at)
  values (md5('cen:servico:' || p_n)::uuid, v_os, '5e000000-0000-4000-8000-000000000003', 'Revisão do sistema elétrico', 'unit', 1,
          2160, 2160, timestamptz '2026-10-15 12:00-03');
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                  balance_amount, is_deposit)
  values (md5('cen:sinal:' || p_n)::uuid, v_cl, v_os, 'Sinal', date '2026-10-20', date '2026-10-20', 500, 'paid', 500, 0, true);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, precisa_ate,
                                      material_conferido_em)
  values (v_os, p_dias, case when p_dias is not null then 'dono' end, case when p_dias is not null then timestamptz '2026-10-28 18:00-03' end,
          p_presenca, p_precisa, case when p_conferido then timestamptz '2026-10-28 18:00-03' end);
  for e in select x from jsonb_array_elements(coalesce(p_equipe, '[]'::jsonb)) x loop
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_os, (e ->> 'payee')::uuid, e ->> 'turnos');
  end loop;
  return v_os;
end $f$;
-- O cenário publicado pela vigia na qui 29/10 às 16:30 (os dois modos ligados), com o Daniel (1 dia, Roberto) a mais.
create function pg_temp.publicado_com_daniel() returns uuid language plpgsql as $f$
declare
  v uuid;
begin
  perform pg_temp.cenario();
  perform pg_temp.modos('ligado', 'ligado');
  perform public.agenda_vigiar(date '2026-10-29', pg_temp.em(date '2026-10-29', '16:30'));
  v := pg_temp.os_extra('204', 'Daniel', 1, 'nunca',
                        jsonb_build_array(jsonb_build_object('payee', 'bb000000-0000-4000-8000-000000000002', 'turnos', 'dia')));
  return v;
end $f$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $rasc$
declare
  v_fix     boolean := coalesce(current_setting('agenda_teste.cenario_motor', true), '') <> ''
                       and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002');
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tecnico constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao    constant uuid := 'bb000000-0000-4000-8000-000000000003';
  d29       constant date := date '2026-10-29';

  v_res     jsonb := '[]'::jsonb;
  r         jsonb;
  r2        jsonb;
  r3        jsonb;
  v_foto    text;
  v_txt     text;
  v_txt2    text;
  v_n       int;
  v_id      uuid;
  v_os      uuid;
begin
  if not v_fix then
    insert into _resultado values ('M–T cenários do rascunho da Fase 2', true,
      'PULADO: sem as fixtures (agenda_teste.cenario_motor): rode pela bancada');
    return;
  end if;

  -- ── M. Marcar ──
  begin
    v_os := pg_temp.publicado_com_daniel();
    v_foto := pg_temp.foto();
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'sexta', null, null, 'marca o Daniel pra sexta', d29,
                                       pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'M1 "marca o Daniel pra sexta": a releitura do encaixe que o motor acha agora (sex 30/10, Roberto o dia todo)',
      (r ->> 'ok')::boolean
      and r ->> 'releitura' = E'Entendi assim, confere?\n• Marco na agenda: Daniel (OS-00204), sex 30/10, Roberto o dia todo.\nResponda *grava* ou corrija o que estiver errado.',
      r::text);
    v_res := pg_temp.ok(v_res, 'M2 antes do *grava* nada muda: nem alocação (nem em proposta), nem ação, nem proposta, nem a OS',
      pg_temp.foto() = v_foto and pg_temp.vigentes(v_os) = ''
      and (select count(*) from public.agenda_rascunho where tipo = 'marcar' and chave = 'marcar:' || v_os and estado = 'aberto'
             and dados ->> 'de' = '2026-10-30' and dados ->> 'ate' = '2026-10-30' and dados #>> '{simulado,de}' = '2026-10-30') = 1, null);
    r2 := pg_temp.grava(c_admin, d29, '17:05');
    v_res := pg_temp.ok(v_res, 'M3 o *grava* marca: sex 30/10 de manhã e à tarde com o Roberto, fixada pelo dono, e diz o que fez',
      (r2 ->> 'ok')::boolean and (r2 ->> 'gravados')::int = 1
      and pg_temp.vigentes(v_os) = '30/10 manha Roberto turno | 30/10 tarde Roberto turno'
      and (select bool_and(a.estado = 'fixada' and a.fixado_por = 'dono' and a.origem = 'dono')
             from public.agenda_alocacoes a where a.service_order_id = v_os and a.estado in ('publicada', 'fixada'))
      and r2 ->> 'texto' like E'Gravado. Agora:\n• Mudei: Daniel (OS-00204)%', r2 ->> 'texto');
    v_res := pg_temp.ok(v_res, 'M4 a OS fica agendada pela porta e a data da OS é a do plano (o espelho)',
      (select status = 'scheduled' and scheduled_start_at = timestamptz '2026-10-30 08:00-03' and scheduled_end_at = timestamptz '2026-10-30 17:00-03'
         from public.service_orders where id = v_os)
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = v_os and a.tipo = 'criar' and a.origem = 'dono'
                    and a.executada and a.autor = c_admin and a.desfazivel_ate = timestamptz '2026-10-30 08:00-03')
      and (select estado from public.agenda_rascunho where chave = 'marcar:' || v_os) = 'gravado',
      (select status || ' ' || coalesce(scheduled_start_at::text, '-') from public.service_orders where id = v_os));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'dia 30', null, null, 'marca o Daniel dia 30', d29,
                                       pg_temp.em(d29, '17:00'));
    r2 := public.agenda_rascunho_marcar(c_admin, 'painel', 'Daniel', 'sexta', null, 'Roberto', 'na sexta, com o Roberto', d29,
                                        pg_temp.em(d29, '17:01'));
    v_res := pg_temp.ok(v_res, 'M5 a correção substitui a linha (uma aberta por OS) e o que foi dito de novo vale (o Roberto)',
      (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean
      and (select count(*) from public.agenda_rascunho where chave = 'marcar:' || v_os and estado = 'aberto') = 1
      and (select count(*) from public.agenda_rascunho where chave = 'marcar:' || v_os and estado = 'substituido') = 1
      and (select dados ->> 'pessoa' = c_roberto::text and trecho = 'marca o Daniel dia 30 / na sexta, com o Roberto'
             from public.agenda_rascunho where chave = 'marcar:' || v_os and estado = 'aberto'), r2::text);
    v_foto := pg_temp.foto();
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'segunda', null, null, 'marca o Daniel na segunda', d29,
                                       pg_temp.em(d29, '17:02'));
    v_res := pg_temp.ok(v_res, 'M6 não cabe (seg 02/11 é Finados): a pergunta com o 1º dia que dá, nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'nao_cabe' and r ->> 'pergunta' like 'Não cabe seg 02/11%'
      and r ->> 'pergunta' like '%O primeiro dia que dá é % Marco nesse dia?'
      and (select count(*) from public.agenda_rascunho where chave = 'marcar:' || v_os and estado = 'aberto'
             and dados ->> 'de' = '2026-11-02') = 0 and pg_temp.foto() = v_foto, r ->> 'pergunta');
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'terça', null, null, 'marca o Daniel na sexta', d29,
                                       pg_temp.em(d29, '17:03'));
    v_res := pg_temp.ok(v_res, 'M7 a data tem de estar no que o dono disse',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' = 'Não achei "terça" no que você disse; me diga de novo.', r ->> 'pergunta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.cenario();
    perform pg_temp.modos('sombra', 'sombra');
    v_os := pg_temp.os_extra('204', 'Daniel', 1, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_roberto, 'turnos', 'dia')));
    v_foto := pg_temp.foto();
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'sexta', null, null, 'marca o Daniel pra sexta', d29,
                                       pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'M8 em teste (sombra): só a simulação — "mostro como ficaria, mas não marco nada", nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'em_teste'
      and r ->> 'pergunta' = 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada. Ficaria assim: Daniel (OS-00204), sex 30/10, Roberto o dia todo.'
      and not exists (select 1 from public.agenda_rascunho where tipo = 'marcar') and pg_temp.foto() = v_foto, r ->> 'pergunta');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── P. Publicar uma proposta aberta ──
  begin
    v_os := pg_temp.publicado_com_daniel();
    v_n := (select count(*) from public.agenda_propostas);
    r := public.agenda_propor_dito(c_admin, 'whatsapp', 'os', array['Daniel'], null, null, null, false, false, d29, pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'P1 agenda_propor_dito com simular = false: só a proposta ABERTA (nada vigente do Daniel)',
      (r ->> 'ok')::boolean and not (r ->> 'simulacao')::boolean
      and (select count(*) from public.agenda_propostas) = v_n + 1
      and (select estado = 'aberta' and modo = 'ligado' and criada_por = 'dono' from public.agenda_propostas where id = (r ->> 'proposta_id')::uuid)
      and pg_temp.vigentes(v_os) = '', r ->> 'texto');
    v_id := (r ->> 'proposta_id')::uuid;
    v_foto := pg_temp.foto();
    r2 := public.agenda_rascunho_aplicar(c_admin, 'whatsapp', 'a última', null, null, null, 'pode publicar', d29, pg_temp.em(d29, '17:01'));
    v_res := pg_temp.ok(v_res, 'P2 "pode publicar": a releitura do que entra; nada muda antes do *grava*',
      (r2 ->> 'ok')::boolean and r2 ->> 'releitura' like E'Entendi assim, confere?\n• Publico na agenda: Daniel (OS-00204), %'
      and pg_temp.foto() = v_foto
      and (select dados ->> 'proposta_id' from public.agenda_rascunho where chave = 'aplicar:' || v_id and estado = 'aberto') = v_id::text,
      r2::text);
    r3 := pg_temp.grava(c_admin, d29, '17:02');
    v_res := pg_temp.ok(v_res, 'P3 o *grava* publica a proposta (aplicada pelo dono) e o Daniel entra no plano',
      (r3 ->> 'ok')::boolean and (select estado from public.agenda_propostas where id = v_id) = 'aplicada'
      and pg_temp.vigentes(v_os) <> '' and (select status from public.service_orders where id = v_os) = 'scheduled'
      and r3 ->> 'texto' like E'Gravado. Agora:\n• Mudei: Daniel (OS-00204)%', r3 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_propor_dito(c_admin, 'whatsapp', 'os', array['Daniel'], null, null, null, false, false, d29, pg_temp.em(d29, '17:00'));
    v_id := (r ->> 'proposta_id')::uuid;
    r2 := public.agenda_rascunho_aplicar(c_admin, 'whatsapp', '1', null, null, null, 'publica a 1', d29, pg_temp.em(d29, '17:01'));
    -- a agenda muda entre a releitura e o *grava*
    update public.agenda_config set versao_plano = versao_plano + 1 where id;
    v_foto := pg_temp.foto();
    r3 := pg_temp.grava(c_admin, d29, '17:02');
    v_res := pg_temp.ok(v_res, 'P4 a agenda mudou desde a releitura: não grava nada e diz por quê; a linha continua aberta',
      (r2 ->> 'ok')::boolean and not (r3 ->> 'ok')::boolean and (r3 ->> 'gravados')::int = 0
      and r3 ->> 'texto' = 'Não gravei nada. A agenda mudou desde a releitura: A agenda mudou desde que eu montei: peça de novo que eu refaço. Me peça de novo.'
      and pg_temp.foto() = v_foto and (select estado from public.agenda_propostas where id = v_id) = 'aberta'
      and (select estado from public.agenda_rascunho where chave = 'aplicar:' || v_id) = 'aberto', r3 ->> 'texto');
    r := public.agenda_rascunho_aplicar(c_admin, 'whatsapp', 'a última', null, null, null, 'pode publicar', d29, pg_temp.em(d29, '17:03'));
    v_res := pg_temp.ok(v_res, 'P5 a proposta velha também é recusada na releitura ("peça de novo que eu refaço")',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' = 'A agenda mudou desde que eu montei: peça de novo que eu refaço.', r::text);
    r := public.agenda_rascunho_aplicar(c_admin, 'whatsapp', '7', null, null, null, 'publica a 7', d29, pg_temp.em(d29, '17:03'));
    v_res := pg_temp.ok(v_res, 'P6 proposta que não existe: diz quais existem',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' = 'Não tenho o plano 7 montado.', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D. Responder uma decisão crítica ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modos('ligado', 'ligado');
    update public.os_planejamento set prioridade_manual = 1 where service_order_id = pg_temp.os('201');
    v_os := pg_temp.os_extra('205', 'Elisa', 1, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_roberto, 'turnos', 'dia')),
                             date '2026-11-04');
    perform public.agenda_vigiar(d29, pg_temp.em(d29, '16:30'));
    r := public.agenda_decisoes_abertas(pg_temp.em(d29, '17:00'));
    v_id := (r -> 0 ->> 'id')::uuid;
    v_res := pg_temp.ok(v_res, 'D1 a publicação deixa a decisão nao_cabe aberta (n = 1); nem a Elisa nem o Antônio entram sem ela',
      jsonb_array_length(r) = 1 and r -> 0 ->> 'tipo' = 'nao_cabe' and (r -> 0 ->> 'n')::int = 1
      and pg_temp.vigentes(v_os) = '' and pg_temp.vigentes(pg_temp.os('201')) = '', r::text);
    v_foto := pg_temp.foto();
    r2 := public.agenda_rascunho_aplicar(c_admin, 'whatsapp', null, null, '1', null, 'resolve aí do jeito que achar melhor', d29,
                                         pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'D2 sem a opção dita, a pergunta volta com as opções: o banco nunca escolhe; nada no rascunho',
      not (r2 ->> 'ok')::boolean and r2 ->> 'motivo' = 'sem_opcao' and r2 ->> 'pergunta' like '%1)%2)%'
      and jsonb_array_length(r2 -> 'opcoes') = 2 and not exists (select 1 from public.agenda_rascunho where tipo = 'aplicar')
      and pg_temp.foto() = v_foto, r2 ->> 'pergunta');
    r2 := public.agenda_rascunho_aplicar(c_admin, 'whatsapp', null, null, '1', '9', 'a nove', d29, pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'D3 opção que não existe: recusa com as opções, nada no rascunho',
      not (r2 ->> 'ok')::boolean and r2 ->> 'pergunta' like 'Essa opção não existe. As opções são: 1) Elisa (OS-00205) atrasa%'
      and not exists (select 1 from public.agenda_rascunho where tipo = 'aplicar'), r2 ->> 'pergunta');
    r2 := public.agenda_rascunho_aplicar(c_admin, 'whatsapp', null, null, 'Elisa', 'Antônio', 'pode atrasar o Antônio', d29,
                                         pg_temp.em(d29, '17:01'));
    v_res := pg_temp.ok(v_res, 'D4 "pode atrasar o Antônio" (a decisão pelo nome da OS, a opção pelo nome de quem atrasa): a releitura; a pergunta continua aberta',
      (r2 ->> 'ok')::boolean and r2 ->> 'releitura' like E'Entendi assim, confere?\n• Decisão: Antônio (OS-00201) passa para % (sem data dita pelo cliente).\n%'
      and (select estado from public.agenda_perguntas where id = v_id) = 'aberta' and pg_temp.foto() = v_foto
      and (select (dados ->> 'opcao')::int from public.agenda_rascunho where chave = 'decisao:' || v_id and estado = 'aberto') = 2,
      r2::text);
    r3 := pg_temp.grava(c_admin, d29, '17:02');
    v_res := pg_temp.ok(v_res, 'D5 o *grava* responde: respondida, opção 2, as palavras do dono, pelo WhatsApp',
      (r3 ->> 'ok')::boolean
      and (select estado = 'respondida' and opcao_escolhida = 2 and resposta = 'pode atrasar o Antônio' and respondida_via = 'whatsapp'
                  and respondida_por = c_admin
             from public.agenda_perguntas where id = v_id)
      and r3 ->> 'texto' like E'Gravado. Agora:\n• Mudei: Antônio (OS-00201): qua 11 e qui 12/11, %', r3 ->> 'texto');
    v_res := pg_temp.ok(v_res, 'D6 as ações saem critica = true com pergunta_id (a Elisa antes de qua 04/11; o Antônio depois)',
      (select count(*) from public.agenda_acoes a where a.pergunta_id = v_id and a.critica and a.executada and a.tipo <> 'status') >= 2
      and (select max(dia) from public.agenda_alocacoes where service_order_id = v_os and estado in ('publicada', 'fixada')) <= date '2026-11-04'
      and pg_temp.vigentes(pg_temp.os('201')) <> ''
      and (public.agenda_saude(d29, pg_temp.em(d29, '17:03')) #>> '{criticas,sem_decisao}')::int = 0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── X. Desfazer ──
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'sexta', null, null, 'marca o Daniel pra sexta', d29, pg_temp.em(d29, '17:00'));
    r := pg_temp.grava(c_admin, d29, '17:05');
    v_id := (select a.id from public.agenda_acoes a where a.service_order_id = v_os and a.tipo = 'criar' and a.executada);
    v_foto := pg_temp.foto();
    r2 := public.agenda_rascunho_desfazer(c_admin, 'whatsapp', 'Daniel', 'desfaz o Daniel', d29, pg_temp.em(d29, '17:10'));
    v_res := pg_temp.ok(v_res, 'X1 "desfaz o Daniel": a releitura com o que eu mudei e quando; nada muda antes do *grava*',
      (r2 ->> 'ok')::boolean and r2 ->> 'releitura' like E'Entendi assim, confere?\n• Desfaço: Daniel (OS-00204): % (mudei hoje às __:__).\n%'
      and pg_temp.foto() = v_foto
      and (select dados -> 'acao_ids' ->> 0 from public.agenda_rascunho where chave = 'desfazer:' || v_id and estado = 'aberto') = v_id::text,
      r2::text);
    r3 := pg_temp.grava(c_admin, d29, '17:11');
    v_res := pg_temp.ok(v_res, 'X2 o *grava* desfaz: o Daniel sai da agenda, volta a aprovada, a ação fica desfeita',
      (r3 ->> 'ok')::boolean and pg_temp.vigentes(v_os) = ''
      and (select status from public.service_orders where id = v_os) = 'approved'
      and (select desfeita_em is not null from public.agenda_acoes where id = v_id)
      and r3 ->> 'texto' like E'Gravado. Agora:\n• Desfeito: %', r3 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'sexta', null, null, 'marca o Daniel pra sexta', d29, pg_temp.em(d29, '17:00'));
    r := pg_temp.grava(c_admin, d29, '17:05');
    r2 := public.agenda_rascunho_desfazer(c_admin, 'whatsapp', 'Daniel', 'desfaz o Daniel', d29, pg_temp.em(d29, '17:10'));
    -- a releitura passou da validade
    update public.agenda_rascunho set criado_em = now() - interval '2 days', expira_em = now() - interval '1 minute'
     where tipo = 'desfazer' and estado = 'aberto';
    v_foto := pg_temp.foto();
    r3 := pg_temp.grava(c_admin, d29, '17:11');
    v_res := pg_temp.ok(v_res, 'X3 expirado não grava: nada muda e a linha fica expirada',
      (r3 ->> 'gravados')::int = 0 and (r3 ->> 'expirados')::int = 1 and r3 ->> 'texto' like 'A releitura de % expirou%'
      and pg_temp.foto() = v_foto and (select estado from public.agenda_rascunho where tipo = 'desfazer') = 'expirado',
      r3 ->> 'texto');
    r2 := public.agenda_rascunho_desfazer(c_admin, 'whatsapp', 'Daniel', 'desfaz o Daniel', date '2026-10-30',
                                          pg_temp.em(date '2026-10-30', '09:00'));
    v_res := pg_temp.ok(v_res, 'X4 depois de começar não se desfaz: a frase pronta, nada no rascunho',
      not (r2 ->> 'ok')::boolean and r2 ->> 'pergunta' = 'Não tenho mudança minha no Daniel para desfazer agora.'
      and (select count(*) from public.agenda_rascunho where tipo = 'desfazer' and estado = 'aberto') = 0, r2::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── A. Andamento ──
  begin
    v_os := pg_temp.publicado_com_daniel();
    v_foto := pg_temp.foto();
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Antônio', 'trabalhou', 'hoje', array['Roberto'], null,
                                          'hoje o Roberto fez o dia todo no Antônio', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    r2 := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Antônio', 'nao_foi', null, array['João'], 'equipe',
                                           'o João não foi', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:41'));
    v_res := pg_temp.ok(v_res, 'A1 "o Roberto fez o dia todo; o João não foi": duas linhas, uma releitura só da OS no dia; nada muda',
      (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean
      and r2 ->> 'releitura' = E'Entendi assim, confere?\n• Hoje (ter 03/11), Antônio (OS-00201): Roberto trabalhou o dia todo; João não foi (equipe).\nResponda *grava* ou corrija o que estiver errado.'
      and (select count(*) from public.agenda_rascunho where tipo = 'andamento' and estado = 'aberto') = 2
      and pg_temp.foto() = v_foto, r2::text);
    r3 := pg_temp.grava(c_admin, date '2026-11-03', '17:45');
    v_res := pg_temp.ok(v_res, 'A2 o *grava* anota: Roberto cumprido, João não cumprido (equipe), pela conversa',
      (r3 ->> 'ok')::boolean
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('201') and a.dia = date '2026-11-03'
             and a.payee_id = c_roberto and a.resultado = 'cumprido' and a.resultado_via = 'conversa') = 2
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('201') and a.dia = date '2026-11-03'
             and a.payee_id = c_joao and a.resultado = 'nao_cumprido' and a.motivo = 'equipe_faltou') = 1, r3 ->> 'texto');
    v_res := pg_temp.ok(v_res, 'A3 o Antônio passa a em andamento, com o início no 1º meio-dia (08:00 de Brasília); nenhuma diária',
      (select status = 'in_progress' and check_in_at = timestamptz '2026-11-03 08:00-03' from public.service_orders where id = pg_temp.os('201'))
      and r3 ->> 'texto' like E'Gravado. Agora:\n• Anotado, hoje (ter 03/11): Antônio (OS-00201) feito, com %', r3 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_os := pg_temp.publicado_com_daniel();
    v_foto := pg_temp.foto();
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Antônio', 'concluiu', null, null, null, 'o Antônio terminou hoje',
                                          date '2026-11-04', pg_temp.em(date '2026-11-04', '17:40'));
    -- FASE 3: com 20261026100200 (agenda_concluir_dito existe), concluir deixa de ser recusado e vira rascunho com a
    -- releitura da saída e das cobranças (os testes dela: agenda_fase3_caminhos.sql). Este arquivo roda nos dois cortes.
    if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'agenda_concluir_dito') then
      v_res := pg_temp.ok(v_res, 'A4 "terminou" (Fase 3): vira o rascunho de concluir, com a releitura da saída e das cobranças',
        (r ->> 'ok')::boolean
        and r ->> 'releitura' like E'Entendi assim, confere?
• Concluo o Antônio (OS-00201) hoje (qua 04/11): fica registrada a saída, e %'
        and (select count(*) from public.agenda_rascunho where tipo = 'andamento' and estado = 'aberto' and dados ->> 'evento' = 'concluiu') = 1
        and (select status from public.service_orders where id = pg_temp.os('201')) <> 'completed', r::text);
      -- (o A5 abaixo confere que o "não foi" sem motivo não entra no rascunho: o de concluir sai antes)
      delete from public.agenda_rascunho where tipo = 'andamento';
    else
      v_res := pg_temp.ok(v_res, 'A4 "terminou": concluir é pela tela; nada no rascunho',
        not (r ->> 'ok')::boolean
        and r ->> 'pergunta' = 'Concluir ainda é pela tela (botão Concluir da OS): é lá que saem a saída e as cobranças.'
        and not exists (select 1 from public.agenda_rascunho where tipo = 'andamento'), r::text);
    end if;
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Antônio', 'nao_foi', null, array['João'], null, 'o João não foi',
                                          date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'A5 "não foi" sem o motivo: pede o motivo (da lista), nada no rascunho',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'sem_motivo'
      and not exists (select 1 from public.agenda_rascunho where tipo = 'andamento'), r ->> 'pergunta');
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Antônio', 'trabalhou', null, array['Roberto'], null, 'o Roberto trabalhou',
                                          date '2026-11-02', pg_temp.em(date '2026-11-02', '17:40'));
    v_res := pg_temp.ok(v_res, 'A6 fora do plano do dia (seg 02/11, Finados): recusa, e aponta a diária',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'fora_do_plano', r ->> 'pergunta');
    v_txt := pg_temp.erro_de(format($s$select public.agenda_rascunho_andamento(%L, 'whatsapp', 'Antônio', 'trabalhou', null, null, null,
                                     'fiz', date '2026-11-03', timestamptz '2026-11-03 17:40-03')$s$, c_tecnico));
    v_res := pg_temp.ok(v_res, 'A7 o técnico não pede à agenda: 42501 (marcar, andamento, desfazer)',
      v_txt like '42501%'
      and pg_temp.erro_de(format($s$select public.agenda_rascunho_marcar(%L, 'whatsapp', 'Daniel', 'sexta', null, null, 'sexta')$s$, c_tecnico)) like '42501%'
      and pg_temp.erro_de(format($s$select public.agenda_rascunho_desfazer(%L, 'whatsapp', 'Daniel', 'desfaz')$s$, c_tecnico)) like '42501%',
      v_txt);
    v_res := pg_temp.ok(v_res, 'A8 nada mudou com as recusas', pg_temp.foto() = v_foto, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_rascunho_andamento(c_admin, 'painel', 'Beatriz', 'comecou', 'hoje', null, null, 'a Beatriz começou hoje',
                                          date '2026-11-05', pg_temp.em(date '2026-11-05', '10:00'));
    v_res := pg_temp.ok(v_res, 'A9 "começou hoje": a releitura com o início que o banco deriva (a manhã do dia dito)',
      (r ->> 'ok')::boolean
      and r ->> 'releitura' = E'Entendi assim, confere?\n• Hoje (qui 05/11), Beatriz (OS-00202): começou (início às 08:00).\nResponda *grava* ou corrija o que estiver errado.'
      and (select status from public.service_orders where id = pg_temp.os('202')) = 'scheduled', r::text);
    r2 := pg_temp.grava(c_admin, date '2026-11-05', '10:01');
    v_res := pg_temp.ok(v_res, 'A10 o *grava* põe a Beatriz em andamento pela porta (via dono), com o início às 08:00',
      (r2 ->> 'ok')::boolean
      and (select status = 'in_progress' and check_in_at = timestamptz '2026-11-05 08:00-03' from public.service_orders where id = pg_temp.os('202'))
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('202') and a.tipo = 'status' and a.origem = 'dono'
                    and a.status_depois = 'in_progress'), r2 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Antônio', 'parou', null, null, 'imprevisto', 'o Antônio parou',
                                          date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'A11 "parou" sem material nem cliente: pergunta qual dos dois',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'parou_motivo', r ->> 'pergunta');
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Antônio', 'parou', null, null, 'material', 'o Antônio parou, falta peça',
                                          date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'A12 "parou, falta peça": a releitura diz o status e o que sai da agenda',
      (r ->> 'ok')::boolean
      and r ->> 'releitura' like E'%• Hoje (ter 03/11), Antônio (OS-00201): parou (material): passa a aguardando peças e sai da agenda qua 04/11.%',
      r::text);
    r2 := pg_temp.grava(c_admin, date '2026-11-03', '17:45');
    v_res := pg_temp.ok(v_res, 'A13 o *grava*: aguardando peças pela porta (o dono, com o motivo); qua 04/11 cancelada (material); ter 03/11 fica; a data da OS acompanha',
      (r2 ->> 'ok')::boolean
      and (select status = 'awaiting_parts' and scheduled_start_at = timestamptz '2026-11-03 08:00-03'
                  and scheduled_end_at = timestamptz '2026-11-03 17:00-03' from public.service_orders where id = pg_temp.os('201'))
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('201') and a.dia = date '2026-11-04'
                        and a.estado in ('publicada', 'fixada'))
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('201') and a.dia = date '2026-11-04'
                    and a.estado = 'cancelada' and a.cancelada_motivo = 'material')
      and pg_temp.vigentes(pg_temp.os('201')) like '03/11%' and pg_temp.vigentes(pg_temp.os('201')) not like '%04/11%'
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('201') and a.tipo = 'cancelar' and a.origem = 'dono'
                    and a.executada and a.desfazivel_ate is null)
      and r2 ->> 'texto' like '%aguardando peças%Tirei da agenda qua 04/11.%', r2 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── L. Tudo ou nada ──
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Caio', '{"prioridade": 1}'::jsonb, 'o Caio passa na frente', d29);
    r2 := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'sexta', null, null, 'marca o Daniel pra sexta', d29, pg_temp.em(d29, '17:00'));
    -- entre a releitura e o *grava*, o Roberto avisa que não vem na sexta
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_por, criado_em)
    values (c_roberto, daterange(date '2026-10-30', date '2026-10-30', '[]'), null, 'indisponivel', 'dono', 'não vem', c_admin,
            timestamptz '2026-10-29 17:01-03');
    v_foto := pg_temp.foto();
    r3 := pg_temp.grava(c_admin, d29, '17:05');
    v_res := pg_temp.ok(v_res, 'L1 o pedido que não cabe mais derruba o lote inteiro: nem o fato da Fase 1 (a prioridade do Caio) grava',
      (r ->> 'ok')::boolean and (r2 ->> 'ok')::boolean and not (r3 ->> 'ok')::boolean and (r3 ->> 'gravados')::int = 0
      and r3 ->> 'texto' like 'Não gravei nada. A agenda mudou desde a releitura: % Me peça de novo.'
      and pg_temp.foto() = v_foto
      and (select count(*) from public.agenda_rascunho where estado = 'aberto' and tipo in ('planejar', 'marcar')) = 2, r3 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── F. Fora de ligado ──
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Daniel', 'sexta', null, null, 'marca o Daniel pra sexta', d29, pg_temp.em(d29, '17:00'));
    perform pg_temp.modos('sombra', 'sombra');
    v_foto := pg_temp.foto();
    r2 := pg_temp.grava(c_admin, d29, '17:05');
    v_res := pg_temp.ok(v_res, 'F1 a agenda voltou para teste: o lote com pedido à agenda não grava (e diz o que fazer)',
      (r ->> 'ok')::boolean and not (r2 ->> 'ok')::boolean and r2 ->> 'motivo' = 'em_teste'
      and pg_temp.foto() = v_foto and pg_temp.vigentes(v_os) = ''
      and (select estado from public.agenda_rascunho where tipo = 'marcar') = 'aberto', r2 ->> 'texto');
    r := public.agenda_rascunho_andamento(c_admin, 'whatsapp', 'Antônio', 'trabalhou', null, null, null, 'fizemos o Antônio',
                                          date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    r2 := public.agenda_rascunho_desfazer(c_admin, 'whatsapp', 'Daniel', 'desfaz', d29, pg_temp.em(d29, '17:10'));
    r3 := public.agenda_rascunho_aplicar(c_admin, 'whatsapp', 'a última', null, null, null, 'pode publicar', d29, pg_temp.em(d29, '17:10'));
    v_res := pg_temp.ok(v_res, 'F2 em teste, andamento, desfazer e publicar são recusados na hora: "mostro como ficaria, mas não marco nada"',
      r ->> 'motivo' = 'em_teste' and r2 ->> 'motivo' = 'em_teste' and r3 ->> 'motivo' = 'em_teste'
      and r3 ->> 'pergunta' = 'A agenda automática ainda está em teste: mostro como ficaria, mas não marco nada.', r3::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── G. O planejar: dá para adiantar no pátio ──
  begin
    perform pg_temp.cenario();
    r := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Caio', '{"adiantavel_patio": 1}'::jsonb,
                                         'do Caio dá para adiantar um dia no pátio', d29);
    v_res := pg_temp.ok(v_res, 'G1 "dá para adiantar um dia no pátio": a releitura',
      (r ->> 'ok')::boolean and r ->> 'item' = 'Caio (OS-00203): dá para adiantar 1 dia no pátio', r::text);
    r2 := public.agenda_rascunho_gravar(c_admin, d29);
    v_res := pg_temp.ok(v_res, 'G2 o *grava* grava a coluna (e o histórico diz o que mudou)',
      (r2 ->> 'ok')::boolean
      and (select adiantavel_patio_dias = 1 and (historico -> -1 -> 'depois' ->> 'adiantavel_patio_dias')::numeric = 1
                  and historico -> -1 -> 'antes' -> 'adiantavel_patio_dias' = 'null'::jsonb
             from public.os_planejamento where service_order_id = pg_temp.os('203')), r2 ->> 'texto');
    r := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Caio', '{"adiantavel_patio": 2}'::jsonb, 'dá para adiantar no pátio', d29);
    r2 := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Caio', '{"adiantavel_patio": 4}'::jsonb, 'dá para adiantar 4 dias no pátio', d29);
    r3 := public.agenda_rascunho_planejar(c_admin, 'whatsapp', 'Caio', '{"limpar": ["patio"]}'::jsonb, 'não dá para adiantar nada no pátio', d29);
    v_res := pg_temp.ok(v_res, 'G3 o número tem de estar no trecho; não passa dos dias do serviço (3); "limpar patio" tira',
      r ->> 'motivo' = 'fora_do_trecho' and r2 ->> 'motivo' = 'patio_maior'
      and r2 ->> 'pergunta' = 'O serviço todo é de 3 dias: no pátio dá para adiantar no máximo isso. Quanto dá?'
      and (r3 ->> 'ok')::boolean and r3 ->> 'item' = 'Caio (OS-00203): nada a adiantar no pátio', r3::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S. agenda_propor_dito ──
  begin
    v_os := pg_temp.publicado_com_daniel();
    v_foto := pg_temp.foto();
    r := public.agenda_propor_dito(c_admin, 'painel', 'proxima_semana', null, null, array['Beatriz'], null, false, true, d29,
                                   pg_temp.em(d29, '17:00'));
    v_res := pg_temp.ok(v_res, 'S1 "e se eu tirar a Beatriz da semana?": simulação, sem a Beatriz, nada gravado',
      (r ->> 'ok')::boolean and (r ->> 'simulacao')::boolean and r ->> 'texto' like '%É simulação: não muda nada.'
      and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'numero' = 'OS-00202')
      and pg_temp.foto() = v_foto, r ->> 'texto');
    r := public.agenda_propor_dito(c_admin, 'whatsapp', 'os', array['Zé Ninguém'], null, null, null, false, true, d29, pg_temp.em(d29, '17:00'));
    v_txt := pg_temp.erro_de(format($s$select public.agenda_propor_dito(%L, 'whatsapp', 'mes', null)$s$, c_admin));
    v_res := pg_temp.ok(v_res, 'S2 OS que não existe vira a frase (nada calculado); escopo que não existe = 22023',
      not (r ->> 'ok')::boolean and r ->> 'pergunta' is not null and v_txt like '22023%' and pg_temp.foto() = v_foto, v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── T. Paridade de statusAoAgendar com a porta (via tela_agendar, fora de ligado; aguardando peças sem o material) ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modos('desligado', 'desligado');
    v_txt := null;
    v_n := 300;
    for r in select jsonb_build_object('status', e.status, 'esperado', e.esperado) from (values
        -- PARIDADE statusAoAgendar (início): src/test/porta-unica-status.test.ts lê esta lista. Status → o que a porta faz
        -- ao agendar pela tela (tela_agendar), fora de ligado e com o material de aguardando peças em falta; recusa = nada
        -- muda e a tela não agenda.
        ('draft', 'draft'),
        ('open', 'scheduled'),
        ('approved', 'scheduled'),
        ('scheduled', 'scheduled'),
        ('in_progress', 'in_progress'),
        ('awaiting_parts', 'awaiting_parts'),
        ('awaiting_client', 'scheduled'),
        ('completed', 'recusa'),
        ('invoiced', 'recusa'),
        ('cancelled', 'recusa')
        -- PARIDADE statusAoAgendar (fim)
      ) e(status, esperado) loop
      v_n := v_n + 1;
      v_os := pg_temp.os_extra(v_n::text, 'Teste ' || (r ->> 'status'), 1, 'nunca', '[]'::jsonb, null, r ->> 'status', false);
      r2 := public.os_transicionar_status(v_os, 'scheduled', 'tela_agendar', null, c_admin, null, d29, pg_temp.em(d29, '17:00'));
      v_txt2 := case when not (r2 ->> 'ok')::boolean and r2 ->> 'de' in ('completed', 'invoiced', 'cancelled') then 'recusa'
                     else r2 ->> 'para' end;
      if v_txt2 is distinct from r ->> 'esperado' then
        v_txt := concat_ws(' ', v_txt, format('%s→%s (esperado %s)', r ->> 'status', coalesce(v_txt2, '?'), r ->> 'esperado'));
      end if;
    end loop;
    v_res := pg_temp.ok(v_res, 'T1 a porta pela tela de agendar, status a status, é a tabela marcada (a mesma de statusAoAgendar)',
      v_txt is null and v_n = 310, coalesce(v_txt, 'iguais'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── Revisão da Fase 2: "marca o Flávio pra terça" antes de o compressor chegar (o replay da OS-00104) ──
  begin
    execute current_setting('agenda_teste.replay_0104');
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, criado_por, criado_em)
    values ('bb000000-0000-4000-8000-000000000001', '{1,2,3,4,5}', null, 'disponivel', 'dono', 'você disse', c_admin,
            timestamptz '2026-10-01 18:00-03'),
           (c_roberto, '{1,2,3,4,5}', null, 'disponivel', 'dono', 'você disse', c_admin, timestamptz '2026-10-01 18:00-03');
    perform pg_temp.modos('ligado', 'ligado');
    v_foto := pg_temp.foto();
    r := public.agenda_rascunho_marcar(c_admin, 'whatsapp', 'Flávio', 'terça', null, null, 'marca o Flávio pra terça',
                                       date '2026-10-02', timestamptz '2026-10-02 10:00-03');
    v_res := pg_temp.ok(v_res, 'M9 o dia pedido antes do material: a releitura vira a pergunta (o aviso do compressor e "Marco mesmo assim?"); nada muda',
      (r ->> 'ok')::boolean
      and r ->> 'releitura' = E'Entendi assim, confere?\n• Marco na agenda: Flávio (OS-00104), ter 06/10, você, Roberto o dia todo — mas falta comprar "Compressor 12V SS65": comprando hoje, chega por volta de ter 06/10 (pronto qua 07/10). Marco mesmo assim?\nResponda *grava* ou corrija o que estiver errado.'
      and r ->> 'pergunta' = 'Flávio (OS-00104): falta comprar "Compressor 12V SS65": comprando hoje, chega por volta de ter 06/10 (pronto qua 07/10). Marco mesmo assim? Se sim, mande *grava*.'
      and r ->> 'aviso_material' like 'falta comprar "Compressor 12V SS65"%'
      and pg_temp.foto() = v_foto and pg_temp.vigentes(pg_temp.os('104')) = '', r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── Revisão da Fase 2: agenda_propor_dito confere o dia de fixar e de "só depois de" nas palavras do dono ──
  begin
    v_os := pg_temp.publicado_com_daniel();
    r := public.agenda_propor_dito(c_admin, 'whatsapp', 'os', null,
           jsonb_build_array(jsonb_build_object('os', 'Daniel', 'quando', 'sexta')), null, null, false, false, d29, pg_temp.em(d29, '17:00'));
    r2 := public.agenda_propor_dito(c_admin, 'whatsapp', 'os', null,
           jsonb_build_array(jsonb_build_object('os', 'Daniel', 'quando', '30/10')), null, null, false, false, d29, pg_temp.em(d29, '17:00'),
           'marca o Daniel pra quinta');
    r3 := public.agenda_propor_dito(c_admin, 'whatsapp', 'os', null, null, null,
           jsonb_build_array(jsonb_build_object('os', 'Daniel', 'quando', '2026-11-05')), false, true, d29, pg_temp.em(d29, '17:00'),
           'o Daniel só depois de quinta');
    v_res := pg_temp.ok(v_res, 'S5 fixar sem as palavras do dono, com um dia que ele não disse, ou "só depois de" com data calculada: recusa, nada aberto',
      not (r ->> 'ok')::boolean and r ->> 'motivo' = 'sem_trecho'
      and not (r2 ->> 'ok')::boolean and r2 ->> 'pergunta' = 'Não achei "30/10" no que você disse; me diga de novo.'
      and not (r3 ->> 'ok')::boolean and r3 ->> 'motivo' = 'fora_do_trecho'
      and not exists (select 1 from public.agenda_propostas p where p.estado = 'aberta' and v_os = any (p.os_alvo)),
      r::text || ' / ' || r2::text || ' / ' || r3::text);
    r := public.agenda_propor_dito(c_admin, 'whatsapp', 'os', null,
           jsonb_build_array(jsonb_build_object('os', 'Daniel', 'quando', 'sexta')), null, null, false, true, d29, pg_temp.em(d29, '17:00'),
           'marca o Daniel pra sexta');
    v_res := pg_temp.ok(v_res, 'S6 com o dia nas palavras do dono, a simulação sai (sex 30/10)',
      (r ->> 'ok')::boolean and r ->> 'texto' like '%Daniel (OS-00204): sex 30/10%', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end $rasc$;

-- ── J. Portas (rodam sempre) ────────────────────────────────────────────────────────────────────────────
insert into _resultado
select format('J1 %s: authenticated e service_role executam; anon não', f),
       has_function_privilege('authenticated', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute'), null
  from unnest(array[
    'public.agenda_rascunho_marcar(uuid, text, text, text, text, text, text, date, timestamptz)',
    'public.agenda_rascunho_aplicar(uuid, text, text, text[], text, text, text, date, timestamptz)',
    'public.agenda_rascunho_desfazer(uuid, text, text, text, date, timestamptz)',
    'public.agenda_rascunho_andamento(uuid, text, text, text, text, text[], text, text, date, timestamptz)',
    'public.agenda_propor_dito(uuid, text, text, text[], jsonb, text[], jsonb, boolean, boolean, date, timestamptz, text)',
    'public.agenda_decisoes_abertas(timestamptz)', 'public.agenda_propostas_abertas(timestamptz)',
    'public.agenda_rascunho_planejar(uuid, text, text, jsonb, text, date)', 'public.agenda_rascunho_gravar(uuid, date)']) f;

insert into _resultado
select format('J2 %s: só service_role', f),
       not has_function_privilege('authenticated', f::regprocedure, 'execute')
       and not has_function_privilege('anon', f::regprocedure, 'execute')
       and has_function_privilege('service_role', f::regprocedure, 'execute'), null
  from unnest(array[
    'public._agenda_pedido_recusa(text, text, text)', 'public._agenda_frase_do_encaixe(jsonb, uuid)',
    'public._agenda_nao_cabe(jsonb, uuid, date, uuid, date, timestamptz, boolean)',
    'public._agenda_aplicar_pedido(uuid, text, uuid, jsonb, text, text, date, timestamptz)',
    'public._agenda_rascunho_frase(text, jsonb)', 'public._agenda_aplicar_planejar(uuid, uuid, jsonb, text, date)']) f;

insert into _resultado
select 'J3 os 5 pedidos são security definer com search_path fixo; a numeração e o _agenda_aplicar_pedido não',
       bool_and(p.prosecdef = (p.proname in ('agenda_rascunho_marcar', 'agenda_rascunho_aplicar', 'agenda_rascunho_desfazer',
                                             'agenda_rascunho_andamento', 'agenda_propor_dito')))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%'),
       string_agg(p.proname, ', ')
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('agenda_rascunho_marcar', 'agenda_rascunho_aplicar', 'agenda_rascunho_desfazer', 'agenda_rascunho_andamento',
                     'agenda_propor_dito', 'agenda_decisoes_abertas', 'agenda_propostas_abertas', '_agenda_aplicar_pedido',
                     '_agenda_pedido_recusa', '_agenda_frase_do_encaixe', '_agenda_nao_cabe');

insert into _resultado
select 'J4 o CHECK do tipo do rascunho aceita os 4 tipos novos e recusa o resto',
       pg_get_constraintdef(c.oid) like '%marcar%' and pg_get_constraintdef(c.oid) like '%aplicar%'
       and pg_get_constraintdef(c.oid) like '%desfazer%' and pg_get_constraintdef(c.oid) like '%andamento%'
       and pg_get_constraintdef(c.oid) like '%planejar%' and pg_get_constraintdef(c.oid) not like '%outro%',
       pg_get_constraintdef(c.oid)
  from pg_constraint c
 where c.conrelid = 'public.agenda_rascunho'::regclass and c.conname = 'agenda_rascunho_tipo_check';

select teste, ok, detalhe from _resultado order by teste;

rollback;
