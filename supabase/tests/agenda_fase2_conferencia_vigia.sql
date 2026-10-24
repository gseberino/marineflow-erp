-- Prova da conferência do dia, da vigia, da saúde e do que foi contado ao dono (Agenda de Produção, Fase 2, pacote P3;
-- migration 20261025100300).
-- bancada: depende de 20261025100300
--
-- Sobre o cenário à mão do motor (scripts/bancada-agenda/cenario-motor.sql: qui 29/10/2026; A = Antônio OS-00201, 2 dias
-- de ter 03 a qua 04/11; B = Beatriz OS-00202, diagnóstico na qui 05/11 de manhã; C = Caio OS-00203, reserva
-- condicionada à compra do cabo de qui 05 à tarde a ter 10/11 de manhã, "compre até ter 03/11"):
--   R  conferência: *dia feito* (resultado, em andamento com o check-in das 08:00 de Brasília, nenhuma diária, a pergunta
--      respondida, idempotente), o dia sem dia dito (d19), "ontem", só o que já começou, *dia não cliente* (replano depois
--      do congelado, 1 ação não crítica com desfazer, o espelho, *desfaz*), *choveu* (e o crítico que vira pergunta),
--      *dia parcial* sem motivo, o motivo que não existe, o dia que não chegou, sombra, quem não é administrador, a correção
--   V  vigia: desligada; a quinta das 16:29, 16:30 e 16:45; a sombra; a conferência; sem registro; as violações (e o
--      acorde); as reservas (promove, solta); o material (porta, encaixe da que ficou pronta); o dia não cumprido pela tela;
--      chegou?; parada?; estouro; duração e material; dono sem padrão; pouco serviço na fila; poda; a falha forçada num passo
--   A  o acorde: só ligada, só a perda de hoje/amanhã, no máximo acordes_dia_max por dia
--   S  saúde: zerada, enxergando a crítica forçada sem pergunta e a não crítica que a regra diz crítica; o espelho; o
--      fechamento que leu o plano
--   F  fechamento e acorde registrados
-- Sempre (com ou sem as fixtures):
--   J  portas: anon sem nada; a vigia, o replano e os registros só service_role; as palavras e a saúde também authenticated
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261025100300
--   Em produção, só DEPOIS de aplicar 20261025100000..100300, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase2_conferencia_vigia.sql
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
create function pg_temp.cenario() returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.cenario_motor');
end $f$;
create function pg_temp.modos(p_proposta text, p_vigia text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_proposta, modo_vigia = p_vigia where id
$f$;
-- Um tique da vigia no dia e na hora de Brasília.
create function pg_temp.vigiar(p_dia date, p_hora text) returns jsonb language sql as $f$
  select public.agenda_vigiar(p_dia, (p_dia + p_hora::time) at time zone 'America/Sao_Paulo')
$f$;
create function pg_temp.em(p_dia date, p_hora text) returns timestamptz language sql immutable as $f$
  select (p_dia + p_hora::time) at time zone 'America/Sao_Paulo'
$f$;
-- O cenário com a semana de 03 a 06/11 publicada pela vigia na qui 29/10 às 16:30 (os dois modos ligados).
create function pg_temp.publicado(p_proposta text default 'ligado', p_vigia text default 'ligado') returns jsonb language plpgsql as $f$
begin
  perform pg_temp.cenario();
  perform pg_temp.modos(p_proposta, p_vigia);
  return pg_temp.vigiar(date '2026-10-29', '16:30');
end $f$;
-- Uma OS a mais no cenário (o molde do teste do motor): sinal pago, aprovada em 20/10, com os dias e a equipe ditos.
create function pg_temp.os_extra(p_n text, p_cliente text, p_dias numeric, p_presenca text, p_equipe jsonb,
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
  values (v_os, 'OS-' || lpad(p_n, 5, '0'), v_cl, ('f4000000-0000-4000-8000-' || lpad(p_n, 12, '0'))::uuid, 'approved', 'approved',
          'repair', timestamptz '2026-10-15 12:00-03', timestamptz '2026-10-20 12:00-03', timestamptz '2026-10-20 12:00-03', 2160);
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at)
  values (md5('cen:servico:' || p_n)::uuid, v_os, '5e000000-0000-4000-8000-000000000003', 'Revisão do sistema elétrico', 'unit', 1,
          2160, 2160, timestamptz '2026-10-15 12:00-03');
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status, paid_amount,
                                  balance_amount, is_deposit)
  values (md5('cen:sinal:' || p_n)::uuid, v_cl, v_os, 'Sinal', date '2026-10-20', date '2026-10-20', 500, 'paid', 500, 0, true);
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em)
  values (v_os, p_dias, case when p_dias is not null then 'dono' end, case when p_dias is not null then timestamptz '2026-10-28 18:00-03' end,
          p_presenca, case when p_conferido then timestamptz '2026-10-28 18:00-03' end);
  for e in select x from jsonb_array_elements(coalesce(p_equipe, '[]'::jsonb)) x loop
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_os, (e ->> 'payee')::uuid, e ->> 'turnos');
  end loop;
  return v_os;
end $f$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $conf$
declare
  v_fix     boolean := coalesce(current_setting('agenda_teste.cenario_motor', true), '') <> ''
                       and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002');
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_tecnico constant uuid := 'aa000000-0000-4000-8000-000000000002';
  c_dono    constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao    constant uuid := 'bb000000-0000-4000-8000-000000000003';

  v_res     jsonb := '[]'::jsonb;
  r         jsonb;
  r2        jsonb;
  x         jsonb;
  v_txt     text;
  v_txt2    text;
  v_n       int;
  v_n2      int;
  v_id      uuid;
  v_os      uuid;
begin
  if not v_fix then
    insert into _resultado values ('R–F cenários da conferência e da vigia', true,
      'PULADO: sem as fixtures (agenda_teste.cenario_motor): rode pela bancada');
    return;
  end if;

  -- ── R. A conferência do dia ──
  begin
    perform pg_temp.publicado();
    v_n := (select count(*) from public.work_shifts);
    v_n2 := (select count(*) from public.work_shift_os);
    r := pg_temp.vigiar(date '2026-11-03', '13:05');
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'R1 *dia feito*: os 4 meio-dias do A em ter 03/11 cumpridos, pela palavra, por quem disse',
      (r ->> 'ok')::boolean and (r ->> 'mudou')::boolean and (r ->> 'alocacoes')::int = 4
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('201') and a.dia = date '2026-11-03'
             and a.resultado = 'cumprido' and a.resultado_via = 'dia_feito' and a.resultado_por = c_admin
             and a.resultado_em = pg_temp.em(date '2026-11-03', '17:40')) = 4, r::text);
    v_res := pg_temp.ok(v_res, 'R2 o A passa a em andamento pela porta, com o check-in na hora do 1º meio-dia (08:00 de Brasília)',
      (select status = 'in_progress' and check_in_at = timestamptz '2026-11-03 08:00-03' from public.service_orders where id = pg_temp.os('201'))
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('201') and a.tipo = 'status'
                    and a.origem = 'conferencia' and a.status_antes = 'scheduled' and a.status_depois = 'in_progress'), null);
    v_res := pg_temp.ok(v_res, 'R3 nenhuma diária criada nem mudada (work_shifts e work_shift_os iguais)',
      (select count(*) from public.work_shifts) = v_n and (select count(*) from public.work_shift_os) = v_n2, null);
    v_res := pg_temp.ok(v_res, 'R4 a pergunta da conferência de ter 03/11 fica respondida (pelo WhatsApp)',
      (select estado = 'respondida' and respondida_via = 'whatsapp' and respondida_por = c_admin
         from public.agenda_perguntas where chave = 'conferencia:2026-11-03'), null);
    v_res := pg_temp.ok(v_res, 'R5 uma ação resultado (conferência, sem desfazer) e a frase ao dono',
      (select count(*) from public.agenda_acoes a where a.tipo = 'resultado' and a.origem = 'conferencia' and a.executada
         and a.desfazivel_ate is null and a.service_order_id = pg_temp.os('201')) = 1
      and r ->> 'texto' = 'Anotado, hoje (ter 03/11): Antônio (OS-00201) feito, com você, Roberto e João. Antônio agora está em andamento.',
      r ->> 'texto');
    v_n := (select count(*) from public.agenda_acoes);
    r2 := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:42'));
    v_res := pg_temp.ok(v_res, 'R6 *dia feito* de novo: nada muda (idempotente)',
      (r2 ->> 'ok')::boolean and not (r2 ->> 'mudou')::boolean and (select count(*) from public.agenda_acoes) = v_n
      and (select check_in_at from public.service_orders where id = pg_temp.os('201')) = timestamptz '2026-11-03 08:00-03'
      and r2 ->> 'texto' = 'Já estava anotado hoje (ter 03/11): Antônio (OS-00201) feito.', r2 ->> 'texto');
    v_res := pg_temp.ok(v_res, 'R7 o resto do plano não é tocado (qua 04 do A e qui 05 do B sem resultado; a reserva do C igual)',
      not exists (select 1 from public.agenda_alocacoes a where a.dia > date '2026-11-03' and a.resultado is not null)
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('203') and a.estado = 'publicada') = 6, null);
    -- a correção: o dono diz que foi parcial (imprevisto) pela tela
    r2 := public.agenda_registrar_dia(c_admin, date '2026-11-03', 'parcial', 'imprevisto', pg_temp.os('201'), array[c_roberto], 'tela',
                                      'o Roberto parou à tarde', date '2026-11-03', pg_temp.em(date '2026-11-03', '18:00'));
    v_res := pg_temp.ok(v_res, 'R8 corrigir o resultado (parcial, imprevisto, pela tela): fica o histórico de antes e o replano entra',
      (r2 ->> 'ok')::boolean
      and (select bool_and(a.resultado = 'parcial' and a.motivo = 'imprevisto_tecnico' and a.resultado_via = 'tela'
                           and jsonb_array_length(a.historico) = 1 and a.historico -> 0 ->> 'de' = 'cumprido')
             from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('201') and a.dia = date '2026-11-03' and a.payee_id = c_roberto)
      and r2 ->> 'replano' is not null and r2 ->> 'texto' like 'Anotado, hoje (ter 03/11): Antônio (OS-00201) andou em parte (imprevisto).%',
      r2 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- d19: sem dia dito, a conferência aberta mais recente; "ontem"; só o que já começou
    perform pg_temp.publicado();
    r := pg_temp.vigiar(date '2026-11-03', '13:05');
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', date '2026-11-04', pg_temp.em(date '2026-11-04', '07:00'));
    v_res := pg_temp.ok(v_res, 'R9 *dia feito* às 07:00 de qua 04/11, sem dia: vale a conferência aberta (ter 03/11), nunca a quarta',
      (r ->> 'ok')::boolean and r ->> 'dia' = '2026-11-03' and r ->> 'texto' like 'Anotado, ontem (ter 03/11):%'
      and not exists (select 1 from public.agenda_alocacoes a where a.dia = date '2026-11-04' and a.resultado is not null), r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado();
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '07:30'));
    v_res := pg_temp.ok(v_res, 'R10 antes de começar o dia e sem conferência aberta: "Hoje ainda não começou nada do plano."',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Hoje ainda não começou nada do plano.'
      and not exists (select 1 from public.agenda_alocacoes a where a.resultado is not null), r ->> 'texto');
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '11:00'));
    v_res := pg_temp.ok(v_res, 'R11 às 11:00: só a manhã (o que já começou) fica cumprida; a tarde espera',
      (r ->> 'ok')::boolean and pg_temp.vigentes(pg_temp.os('201')) like
        '03/11 manha Gustavo abertura cumprido | 03/11 manha Roberto turno cumprido | 03/11 tarde João turno | 03/11 tarde Roberto turno |%',
      pg_temp.vigentes(pg_temp.os('201')));
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, 'ontem', 'whatsapp', date '2026-11-04', pg_temp.em(date '2026-11-04', '10:00'));
    v_res := pg_temp.ok(v_res, 'R12 *dia feito ontem* (dito) na qua 04/11: a tarde de ter 03/11 também fica cumprida',
      (r ->> 'ok')::boolean and r ->> 'dia' = '2026-11-03'
      and (select count(*) from public.agenda_alocacoes a where a.dia = date '2026-11-03' and a.resultado = 'cumprido') = 4
      and not exists (select 1 from public.agenda_alocacoes a where a.dia = date '2026-11-04' and a.resultado is not null), r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- *dia não cliente*: só o A no plano (a equipe livre: o replano é curto e o gestor faz sozinho)
    perform pg_temp.cenario();
    update public.service_orders set status = 'cancelled' where id in (pg_temp.os('202'), pg_temp.os('203'));
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(date '2026-10-29', '16:30');
    r := public.agenda_conferir_dia(c_admin, 'nao_cumprido', 'cliente', null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'R13 *dia não cliente*: os 4 meio-dias de ter 03/11 não cumpridos (cliente_ou_bem); a OS não começa',
      (r ->> 'ok')::boolean
      and (select count(*) from public.agenda_alocacoes a where a.dia = date '2026-11-03' and a.resultado = 'nao_cumprido'
             and a.motivo = 'cliente_ou_bem') = 4
      and (select status from public.service_orders where id = pg_temp.os('201')) = 'scheduled', r ->> 'texto');
    v_id := (select a.id from public.agenda_acoes a where a.service_order_id = pg_temp.os('201') and a.executada
               and a.tipo in ('criar', 'mover') and a.origem = 'conferencia');
    v_res := pg_temp.ok(v_res, 'R14 o resto do A volta depois do congelado (qui 05/11), numa ação não crítica com desfazer (até qua 04/11 17:40)',
      v_id is not null
      and (select not critica and desfazivel_ate = pg_temp.em(date '2026-11-04', '17:40') from public.agenda_acoes where id = v_id)
      and pg_temp.vigentes(pg_temp.os('201')) like '%05/11 manha Roberto turno%'
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('201') and a.estado = 'publicada'
                        and a.resultado is null and a.dia > date '2026-11-03' and a.dia < date '2026-11-04'),
      pg_temp.vigentes(pg_temp.os('201')));
    v_res := pg_temp.ok(v_res, 'R15 o espelho das datas sem o dia que não andou: de qua 04/11 08:00 a qui 05/11 17:00',
      (select scheduled_start_at = timestamptz '2026-11-04 08:00-03' and scheduled_end_at = timestamptz '2026-11-05 17:00-03'
         from public.service_orders where id = pg_temp.os('201')), null);
    v_res := pg_temp.ok(v_res, 'R16 a frase: "não andou (cliente). Replanejei: … *desfaz Antônio* volta como estava."',
      r ->> 'texto' like 'Anotado, hoje (ter 03/11): Antônio (OS-00201) não andou (cliente). Replanejei: Antônio (OS-00201): qui 05/11, %*desfaz Antônio* volta como estava.',
      r ->> 'texto');
    r2 := public.agenda_desfazer_dito(c_admin, 'Antônio', 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:50'));
    v_res := pg_temp.ok(v_res, 'R17 *desfaz Antônio*: o dia novo sai e o plano volta ao que era (a ação fica desfeita)',
      (r2 ->> 'ok')::boolean and pg_temp.vigentes(pg_temp.os('201')) not like '%05/11%'
      and (select desfeita_em is not null from public.agenda_acoes where id = v_id), r2 ->> 'texto');
    r2 := public.agenda_desfazer_dito(c_admin, 'Antônio', 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:51'));
    v_res := pg_temp.ok(v_res, 'R18 *desfaz Antônio* de novo: não há o que desfazer, nada muda',
      not (r2 ->> 'ok')::boolean and r2 ->> 'status' = 'nenhuma', r2 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- *choveu*: só o A (replano curto) e depois com A, B e C (o atraso longo vira pergunta)
    perform pg_temp.cenario();
    update public.service_orders set status = 'cancelled' where id in (pg_temp.os('202'), pg_temp.os('203'));
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(date '2026-10-29', '16:30');
    r := public.agenda_choveu(c_admin, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'R19 *choveu*: todo o plano de ter 03/11 não cumprido por clima, e o replano',
      (r ->> 'ok')::boolean
      and (select count(*) from public.agenda_alocacoes a where a.dia = date '2026-11-03' and a.resultado = 'nao_cumprido' and a.motivo = 'clima') = 4
      and r ->> 'texto' like 'Anotado, hoje (ter 03/11): não deu por causa da chuva (Antônio). Replanejei: %', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado();
    r := public.agenda_choveu(c_admin, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'R20 *choveu* com a semana cheia: o A só termina 7 dias depois → pergunta crítica aberta, nada crítico executado',
      (r ->> 'ok')::boolean and r ->> 'texto' like '%Preciso de você: Antônio (OS-00201) só dá para terminar em %'
      and exists (select 1 from public.agenda_perguntas q where q.critica and q.estado = 'aberta' and q.service_order_id = pg_temp.os('201'))
      and not exists (select 1 from public.agenda_acoes a where a.critica), r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado();
    v_n := (select count(*) from public.agenda_acoes);
    r := public.agenda_conferir_dia(c_admin, 'parcial', null, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'R21 *dia parcial* sem motivo: pede o motivo e nada muda',
      not (r ->> 'ok')::boolean and r ->> 'pede' = 'motivo'
      and r ->> 'texto' = 'Me diga o motivo junto: *dia parcial imprevisto* (ou material, cliente, equipe, clima, anterior, informação, estimativa, urgência, esqueci).'
      and not exists (select 1 from public.agenda_alocacoes a where a.resultado is not null) and (select count(*) from public.agenda_acoes) = v_n,
      r ->> 'texto');
    r := public.agenda_conferir_dia(c_admin, 'nao_cumprido', 'porque sim', null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'R22 *dia não* com um motivo que não existe: pede de novo, com as palavras que valem',
      not (r ->> 'ok')::boolean and r ->> 'texto' like 'Me diga o motivo junto: *dia não cliente*%', r ->> 'texto');
    r := public.agenda_registrar_dia(c_admin, date '2026-11-04', 'cumprido', null, null, null, 'dia_feito', null, date '2026-11-03',
                                     pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'R23 o dia que ainda não chegou: "Qua 04/11 ainda não chegou…", nada muda',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Qua 04/11 ainda não chegou: não dá para dizer como foi.', r ->> 'texto');
    v_txt := pg_temp.erro_de(format('select public.agenda_conferir_dia(%L, %L)', c_tecnico, 'cumprido'));
    v_res := pg_temp.ok(v_res, 'R24 quem não é administrador não anota o dia (42501)', v_txt like '42501%', v_txt);
    v_res := pg_temp.ok(v_res, 'R25 os motivos pelas palavras do dono',
      public._agenda_motivo_dito('Cliente') = 'cliente_ou_bem' and public._agenda_motivo_dito('chuva') = 'clima'
      and public._agenda_motivo_dito('equipe') = 'equipe_faltou' and public._agenda_motivo_dito('imprevisto') = 'imprevisto_tecnico'
      and public._agenda_motivo_dito('urgência') = 'urgencia_outra_os' and public._agenda_motivo_dito('informação') = 'informacao'
      and public._agenda_motivo_dito('trabalho_anterior') = 'trabalho_anterior' and public._agenda_motivo_dito('qualquer coisa') is null,
      null);
    perform pg_temp.modos('sombra', 'sombra');
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    v_res := pg_temp.ok(v_res, 'R26 fora de ligado: "Ainda não tenho plano publicado: a agenda automática está em teste."',
      not (r ->> 'ok')::boolean and r ->> 'texto' = 'Ainda não tenho plano publicado: a agenda automática está em teste.', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── V. A vigia ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modos('desligado', 'desligado');
    r := pg_temp.vigiar(date '2026-10-29', '16:30');
    v_res := pg_temp.ok(v_res, 'V1 os dois modos desligados: a vigia não roda e não grava rodada',
      not (r ->> 'rodou')::boolean and not exists (select 1 from public.agenda_vigia_rodadas)
      and not exists (select 1 from public.agenda_propostas), r::text);
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(date '2026-10-29', '16:29');
    v_res := pg_temp.ok(v_res, 'V2 qui 29/10 às 16:29: não publica (antes da hora do plano)',
      not (r #>> '{contagens,publicacao,publicou}')::boolean and not exists (select 1 from public.agenda_alocacoes)
      and r #>> '{contagens,backlog,calculado}' = 'false', (r -> 'contagens' -> 'publicacao')::text);
    r := pg_temp.vigiar(date '2026-10-29', '16:30');
    v_res := pg_temp.ok(v_res, 'V3 às 16:30 publica a semana de 03 a 06/11: 16 meio-dias em vigor, A e B agendadas pela vigia',
      (r #>> '{contagens,publicacao,publicou}')::boolean and (r #>> '{contagens,publicacao,publicadas}')::int = 16
      and (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')) = 16
      and (select count(*) from public.agenda_acoes a where a.tipo = 'publicar' and a.origem = 'vigia' and a.executada) = 3
      and (select status from public.service_orders where id = pg_temp.os('201')) = 'scheduled'
      and (select status from public.service_orders where id = pg_temp.os('202')) = 'scheduled'
      and r #>> '{contagens,publicacao,texto}' like 'Publiquei a semana de 03 a 06/11 (seg 02 é Finados): %*desfaz semana* volta como estava.',
      (r -> 'contagens' -> 'publicacao')::text);
    r := pg_temp.vigiar(date '2026-10-29', '16:45');
    v_res := pg_temp.ok(v_res, 'V4 o tique das 16:45 não publica de novo (uma proposta da semana da vigia, nada a mais em vigor)',
      not (r #>> '{contagens,publicacao,publicou}')::boolean and r #>> '{contagens,publicacao,motivo}' = 'a semana já saiu'
      and (select count(*) from public.agenda_propostas where escopo = 'semana' and criada_por = 'vigia') = 1
      and (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')) = 16, null);
    v_res := pg_temp.ok(v_res, 'V5 uma rodada por tique em agenda_vigia_rodadas, com os modos e as contagens',
      (select count(*) from public.agenda_vigia_rodadas) = 3
      and (select bool_and(x.modo_proposta = 'ligado' and x.modo_vigia = 'ligado' and x.erros = 0 and x.contagens ? 'publicacao')
             from public.agenda_vigia_rodadas x), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    r := pg_temp.publicado('sombra', 'sombra');
    v_res := pg_temp.ok(v_res, 'V6 sombra na quinta 16:30: nada publicado, nenhum status nem data mudou; a proposta fica em sombra',
      not (r #>> '{contagens,publicacao,publicou}')::boolean and r #>> '{contagens,publicacao,modo}' = 'sombra'
      and not exists (select 1 from public.agenda_alocacoes where estado in ('publicada', 'fixada'))
      and (select bool_and(status = 'approved' and scheduled_start_at is null and scheduled_end_at is null) from public.service_orders
            where id in (pg_temp.os('201'), pg_temp.os('202'), pg_temp.os('203')))
      and (select estado = 'aberta' and modo = 'sombra' from public.agenda_propostas where escopo = 'semana'), null);
    v_res := pg_temp.ok(v_res, 'V7 sombra: as 3 ações que faria entram com executada = false (nenhuma executada)',
      (select count(*) from public.agenda_acoes where not executada and tipo = 'publicar') = 3
      and not exists (select 1 from public.agenda_acoes where executada), null);
    r := pg_temp.vigiar(date '2026-10-29', '16:45');
    v_res := pg_temp.ok(v_res, 'V8 sombra: o tique seguinte não repete (a mesma proposta, as mesmas 3 ações)',
      (select count(*) from public.agenda_acoes) = 3 and (select count(*) from public.agenda_propostas) = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado();
    r := pg_temp.vigiar(date '2026-11-03', '12:30');
    v_res := pg_temp.ok(v_res, 'V9 conferência: ter 03/11 às 12:30 (a tarde ainda não começou) não pergunta',
      not (r #>> '{contagens,conferencia,criada}')::boolean and not exists (select 1 from public.agenda_perguntas where tipo = 'conferencia'),
      (r -> 'contagens' -> 'conferencia')::text);
    r := pg_temp.vigiar(date '2026-11-03', '13:05');
    v_res := pg_temp.ok(v_res, 'V10 às 13:05 (o último meio-dia começou): "Agenda de hoje: … Foi isso? Responda *dia feito* ou conte o que mudou."',
      (r #>> '{contagens,conferencia,criada}')::boolean
      and (select texto = 'Agenda de hoje: Antônio (OS-00201) — você abre, Roberto o dia todo, João à tarde. Foi isso? Responda *dia feito* ou conte o que mudou.'
                  and modo = 'ligado' and dia = date '2026-11-03' and not critica
             from public.agenda_perguntas where chave = 'conferencia:2026-11-03'),
      (select texto from public.agenda_perguntas where chave = 'conferencia:2026-11-03'));
    r := pg_temp.vigiar(date '2026-11-03', '13:20');
    v_res := pg_temp.ok(v_res, 'V11 uma conferência por dia (o tique seguinte não abre outra)',
      not (r #>> '{contagens,conferencia,criada}')::boolean and (select count(*) from public.agenda_perguntas where tipo = 'conferencia') = 1, null);
    -- sem registro: em qui 05/11 o dia de ter 03/11 (2 dias úteis antes) fica sem registro; qua 04/11 ainda não
    r := pg_temp.vigiar(date '2026-11-05', '09:00');
    v_res := pg_temp.ok(v_res, 'V12 sem registro: na qui 05/11, os 4 meio-dias de ter 03/11 (2 dias úteis) viram sem_registro; os de qua 04/11 não',
      (r #>> '{contagens,sem_registro,n}')::int = 4
      and (select count(*) from public.agenda_alocacoes a where a.dia = date '2026-11-03' and a.resultado = 'sem_registro'
             and a.resultado_via = 'sistema') = 4
      and not exists (select 1 from public.agenda_alocacoes a where a.dia = date '2026-11-04' and a.resultado is not null), null);
    v_res := pg_temp.ok(v_res, 'V13 a conferência de ter 03/11 se resolve sozinha ("o dia ficou sem registro") na limpeza seguinte',
      (select estado = 'aberta' from public.agenda_perguntas where chave = 'conferencia:2026-11-03'), null);
    r := pg_temp.vigiar(date '2026-11-05', '09:15');
    v_res := pg_temp.ok(v_res, 'V14 …e na rodada seguinte a limpeza a resolve',
      (select estado = 'resolvida' and resolvida_motivo = 'o dia ficou sem registro' from public.agenda_perguntas
        where chave = 'conferencia:2026-11-03'), (r -> 'contagens' -> 'limpeza')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- violações e o acorde: o Roberto avisa (na sex 30/10) que não vem ter 03/11 — a perda do próximo dia útil
    perform pg_temp.publicado();
    r := pg_temp.vigiar(date '2026-10-30', '09:00');
    v_res := pg_temp.ok(v_res, 'V15 violações: sem nada novo, nada a replanejar e nenhum acorde',
      (r #>> '{contagens,violacoes,violadas}')::int = 0 and r -> 'acordes' = '[]'::jsonb, (r -> 'contagens' -> 'violacoes')::text);
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-11-03', date '2026-11-04'), 'indisponivel', 'dono', 'médico');
    r := pg_temp.vigiar(date '2026-10-30', '09:15');
    v_res := pg_temp.ok(v_res, 'V16 o Roberto não vem ter 03/11: o A sai do plano (fato) e o novo encaixe, 8 dias depois, vira pergunta crítica',
      (r #>> '{contagens,violacoes,violadas}')::int = 1 and pg_temp.vigentes(pg_temp.os('201')) = ''
      and exists (select 1 from public.agenda_perguntas q where q.tipo = 'atraso_longo' and q.estado = 'aberta'
                    and q.service_order_id = pg_temp.os('201'))
      and not exists (select 1 from public.agenda_acoes a where a.critica)
      and (select status from public.service_orders where id = pg_temp.os('201')) = 'approved', (r -> 'contagens' -> 'violacoes')::text);
    x := r -> 'acordes' -> 0;
    v_res := pg_temp.ok(v_res, 'V17 o acorde (perda de ter 03/11, o próximo dia útil): a mudança, o *desfaz* e a decisão que ficou com você',
      jsonb_array_length(r -> 'acordes') = 1 and x ->> 'assunto' = 'os:' || pg_temp.os('201') and x ->> 'chave' = 'agenda:' || (x ->> 'acao_id')
      and x ->> 'perda_em' = '2026-11-03'
      and x ->> 'texto' like 'Mudei a agenda de ter 03/11: Antônio (OS-00201): sai ter 03/11 — quem ia não está mais livre%*desfaz Antônio* volta como estava. Preciso de você: Antônio (OS-00201) só dá para terminar em %',
      x ->> 'texto');
    r := pg_temp.vigiar(date '2026-10-30', '09:30');
    v_res := pg_temp.ok(v_res, 'V18 o tique seguinte não replaneja de novo nem acorda de novo',
      (r #>> '{contagens,violacoes,violadas}')::int = 0 and r -> 'acordes' = '[]'::jsonb, (r -> 'contagens' -> 'violacoes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a vigia em sombra (a proposta ligada) replaneja, mas não acorda
    perform pg_temp.publicado('ligado', 'sombra');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-11-03', date '2026-11-04'), 'indisponivel', 'dono', 'médico');
    r := pg_temp.vigiar(date '2026-10-30', '09:15');
    v_res := pg_temp.ok(v_res, 'A1 com a vigia em sombra o replano acontece (a proposta está ligada), mas nenhum acorde sai',
      (r #>> '{contagens,violacoes,violadas}')::int = 1 and r -> 'acordes' = '[]'::jsonb
      and (select modo from public.agenda_perguntas where tipo = 'atraso_longo') = 'ligado', (r -> 'acordes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o limite do dia: já saiu 1 acorde hoje (acordes_dia_max = 1) → o próximo fica para o fechamento
    perform pg_temp.publicado();
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, texto, contada_em, contada_via)
    values (date '2026-10-30', true, 'vigia', 'mover', pg_temp.os('202'), 'um acorde que já saiu hoje', pg_temp.em(date '2026-10-30', '08:30'), 'acorde');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-11-03', date '2026-11-04'), 'indisponivel', 'dono', 'médico');
    r := pg_temp.vigiar(date '2026-10-30', '09:15');
    v_res := pg_temp.ok(v_res, 'A2 no máximo acordes_dia_max (1) por dia: com um já contado hoje, o replano acontece e não acorda',
      (r #>> '{contagens,violacoes,violadas}')::int = 1 and r -> 'acordes' = '[]'::jsonb, (r -> 'acordes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a perda que não é de hoje nem do próximo dia útil (qui 05/11, vista na sex 30/10) replaneja sem acorde
    perform pg_temp.publicado();
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-11-05', date '2026-11-06'), 'manha', 'indisponivel', 'dono', 'médico');
    r := pg_temp.vigiar(date '2026-10-30', '09:15');
    v_res := pg_temp.ok(v_res, 'A3 a perda de qui 05/11 (fora do congelado): replaneja e não acorda (vai no fechamento)',
      (r #>> '{contagens,violacoes,violadas}')::int >= 1 and r -> 'acordes' = '[]'::jsonb, (r -> 'contagens' -> 'violacoes')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- reservas: o cabo do Caio chega (promove); sem o cabo, a reserva vence e é solta
    perform pg_temp.publicado();
    r := pg_temp.vigiar(date '2026-11-03', '09:00');
    v_res := pg_temp.ok(v_res, 'V19 reservas: na ter 03/11 (o dia-limite) sem o cabo, nada (nem promove nem solta)',
      (r #>> '{contagens,reservas,promovidas}')::int = 0 and (r #>> '{contagens,reservas,soltas}')::int = 0
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('203') and a.estado = 'publicada') = 6,
      (r -> 'contagens' -> 'reservas')::text);
    r := pg_temp.vigiar(date '2026-11-04', '09:00');
    v_res := pg_temp.ok(v_res, 'V20 na qua 04/11 a reserva venceu sem o cabo: solta (ação soltar_reserva da vigia, com desfazer)',
      (r #>> '{contagens,reservas,soltas}')::int = 1 and pg_temp.vigentes(pg_temp.os('203')) = ''
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('203') and a.cancelada_motivo = 'condicao_vencida') = 6
      and (select tipo = 'soltar_reserva' and origem = 'vigia' and executada and desfazivel_ate is not null
                  and texto = 'Caio (OS-00203): soltei a reserva de qui 05 a ter 10/11 — a condição venceu em ter 03/11.'
             from public.agenda_acoes where service_order_id = pg_temp.os('203') and tipo = 'soltar_reserva'),
      (select texto from public.agenda_acoes where service_order_id = pg_temp.os('203') and tipo = 'soltar_reserva'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado();
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = 1, chegou_em = date '2026-10-30'
     where service_order_id = pg_temp.os('203');
    r := pg_temp.vigiar(date '2026-10-30', '09:00');
    v_res := pg_temp.ok(v_res, 'V21 o cabo chegou: a reserva do Caio vira compromisso pelo motor (promover_reserva; a reserva sai como promovida)',
      (r #>> '{contagens,reservas,promovidas}')::int = 1
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('203') and a.tipo = 'promover_reserva'
                    and a.executada and not a.critica)
      and (select count(*) from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('203') and a.cancelada_motivo = 'promovida') = 6
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('203') and a.estado = 'publicada'
                    and a.tipo = 'execucao')
      and (select status from public.service_orders where id = pg_temp.os('203')) = 'scheduled', (r -> 'contagens' -> 'reservas')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- material: a OS com dia no plano que ficou "aguardando peças" e tem tudo na mão vai para agendada pela porta
    perform pg_temp.publicado();
    update public.service_orders set status = 'awaiting_parts' where id in (pg_temp.os('201'), pg_temp.os('202'));
    -- o B tem uma peça a caminho (chega sex 30/10, antes do dia dele): o material não está completo
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao, fonte,
                                    previsao_ate, previsao_fonte, conferido_em)
    values (pg_temp.os('202'), 'dono', 'Sensor de nível', 1, 0, true, 'a_caminho', 'dono', date '2026-10-30', 'dono',
            timestamptz '2026-10-29 18:00-03');
    r := pg_temp.vigiar(date '2026-10-29', '17:00');
    v_res := pg_temp.ok(v_res, 'V22 material: o A (dia no plano, tudo na mão) volta a agendada pela vigia; o B (peça a caminho) continua aguardando',
      (r #>> '{contagens,material,agendadas}')::int = 1
      and (select status from public.service_orders where id = pg_temp.os('201')) = 'scheduled'
      and (select status from public.service_orders where id = pg_temp.os('202')) = 'awaiting_parts'
      and exists (select 1 from public.agenda_acoes a where a.service_order_id = pg_temp.os('201') and a.tipo = 'status' and a.origem = 'vigia'
                    and a.status_antes = 'awaiting_parts' and a.status_depois = 'scheduled'), (r -> 'contagens' -> 'material')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- material: a OS que ficou pronta (entrou na classe 2 desde a rodada anterior) é encaixada na hora
    perform pg_temp.cenario();
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(date '2026-10-26', '09:00');
    v_res := pg_temp.ok(v_res, 'V23 a 1ª rodada só anota quem está pronto (A e B): nada é encaixado fora da quinta',
      (r #>> '{contagens,material,primeira_rodada}')::boolean and (r #>> '{contagens,material,encaixadas}')::int = 0
      and jsonb_array_length(r #> '{contagens,material,prontas}') = 2 and not exists (select 1 from public.agenda_alocacoes), null);
    r := pg_temp.vigiar(date '2026-10-26', '09:15');
    v_res := pg_temp.ok(v_res, 'V24 quem já estava pronto na rodada anterior não é reproposto a cada 15 min',
      (r #>> '{contagens,material,encaixadas}')::int = 0 and not exists (select 1 from public.agenda_propostas), null);
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = 1, chegou_em = date '2026-10-26'
     where service_order_id = pg_temp.os('203');
    r := pg_temp.vigiar(date '2026-10-26', '09:30');
    v_res := pg_temp.ok(v_res, 'V25 o cabo do Caio chegou (ficou pronto): a vigia o encaixa na hora, só ele',
      (r #>> '{contagens,material,encaixadas}')::int = 1
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = pg_temp.os('203') and a.estado in ('publicada', 'fixada'))
      and not exists (select 1 from public.agenda_alocacoes a where a.service_order_id in (pg_temp.os('201'), pg_temp.os('202'))
                        and a.estado in ('publicada', 'fixada'))
      and (select count(*) from public.agenda_propostas p where p.criada_por = 'vigia' and p.escopo = 'os') = 1,
      (r -> 'contagens' -> 'material')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o dia não cumprido gravado pela tela (a rede da conferência)
    perform pg_temp.publicado();
    r := pg_temp.vigiar(date '2026-11-03', '18:00');
    v_res := pg_temp.ok(v_res, 'V26 dia não cumprido: sem nada gravado, nada a replanejar', (r #>> '{contagens,dia_nao_cumprido,os}')::int = 0, null);
    perform set_config('agenda.hoje', '2026-11-03', true);
    update public.agenda_alocacoes set resultado = 'nao_cumprido', motivo = 'clima', resultado_via = 'tela',
                                       resultado_em = pg_temp.em(date '2026-11-03', '18:05')
     where service_order_id = pg_temp.os('201') and dia = date '2026-11-03';
    r := pg_temp.vigiar(date '2026-11-03', '18:15');
    v_res := pg_temp.ok(v_res, 'V27 o não cumprido gravado pela tela é replanejado pela vigia',
      (r #>> '{contagens,dia_nao_cumprido,os}')::int = 1
      and exists (select 1 from public.agenda_propostas p where p.escopo = 'replano' and pg_temp.os('201') = any (p.os_alvo)
                    and p.criada_por = 'vigia'), (r -> 'contagens' -> 'dia_nao_cumprido')::text);
    r := pg_temp.vigiar(date '2026-11-03', '18:30');
    v_res := pg_temp.ok(v_res, 'V28 …uma vez só', (r #>> '{contagens,dia_nao_cumprido,os}')::int = 0, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- chegou? e parada?
    perform pg_temp.cenario();
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao,
                                    fonte, previsao_ate, previsao_fonte, conferido_em)
    values ('a4000000-0000-4000-8000-000000000202', pg_temp.os('202'), 'dono', 'Sensor de nível', 1, 0, true, 'a_caminho', 'dono',
            date '2026-10-27', 'dono', timestamptz '2026-10-26 18:00-03'),
           -- a previsão ainda não venceu: não pergunta
           ('a4000000-0000-4000-8000-000000000201', pg_temp.os('201'), 'dono', 'Disjuntor 40A', 1, 0, true, 'a_caminho', 'dono',
            date '2026-10-30', 'dono', timestamptz '2026-10-26 18:00-03');
    update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-20 08:00-03' where id = pg_temp.os('203');
    r := pg_temp.vigiar(date '2026-10-29', '09:00');
    v_res := pg_temp.ok(v_res, 'V29 chegou?: o sensor da Beatriz tinha previsão para ter 27/10 e não chegou → uma pergunta (o disjuntor do Antônio, que chega sex 30/10, não)',
      (r #>> '{contagens,chegou,criadas}')::int = 1
      and (select texto = 'Beatriz (OS-00202): "Sensor de nível" tinha previsão para ter 27/10. Chegou?'
                  and chave = 'chegou:a4000000-0000-4000-8000-000000000202:2026-10-27'
                  and os_material_id = 'a4000000-0000-4000-8000-000000000202' and modo = 'ligado'
             from public.agenda_perguntas where tipo = 'chegou'),
      (select texto || ' / ' || chave from public.agenda_perguntas where tipo = 'chegou'));
    v_res := pg_temp.ok(v_res, 'V30 parada?: o Caio em andamento desde 20/10, sem nada depois e sem dia no plano → "Parou?"',
      (r #>> '{contagens,parada,criadas}')::int = 1
      and (select texto = 'Caio (OS-00203) está em andamento e não andou desde ter 20/10. Parou?' and chave = 'parada:' || pg_temp.os('203') || ':2026-10-20'
             from public.agenda_perguntas where tipo = 'parada'),
      (select texto from public.agenda_perguntas where tipo = 'parada'));
    r := pg_temp.vigiar(date '2026-10-29', '09:15');
    v_res := pg_temp.ok(v_res, 'V31 chegou? e parada? uma vez só (por previsão e por evidência)',
      (r #>> '{contagens,chegou,criadas}')::int = 0 and (r #>> '{contagens,parada,criadas}')::int = 0
      and (select count(*) from public.agenda_perguntas) = 2, null);
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = 1, chegou_em = date '2026-10-29', previsao_ate = null,
                                  previsao_fonte = null
     where id = 'a4000000-0000-4000-8000-000000000202';
    r := pg_temp.vigiar(date '2026-10-29', '09:30');
    v_res := pg_temp.ok(v_res, 'V32 o sensor chegou: a limpeza resolve a pergunta com o fato',
      (select estado = 'resolvida' and resolvida_motivo = '"Sensor de nível" chegou' from public.agenda_perguntas where tipo = 'chegou'),
      (select estado || ' ' || coalesce(resolvida_motivo, '-') from public.agenda_perguntas where tipo = 'chegou'));
    update public.service_orders set status = 'scheduled' where id = pg_temp.os('203');
    r := pg_temp.vigiar(date '2026-10-29', '09:45');
    v_res := pg_temp.ok(v_res, 'V33 o Caio saiu de em andamento: a "parada?" se resolve',
      (select estado = 'resolvida' and resolvida_motivo = 'a OS voltou a andar' from public.agenda_perguntas where tipo = 'parada'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- parada? não pergunta de quem tem dia no plano; estouro
    perform pg_temp.publicado();
    update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-20 08:00-03' where id = pg_temp.os('201');
    v_os := pg_temp.os_extra('210', 'Fábio', 1, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_joao, 'turnos', 'tarde')));
    v_id := pg_temp.os_extra('211', 'Gilda', 1, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_joao, 'turnos', 'tarde')));
    perform set_config('agenda.hoje', '2026-10-30', true);
    -- o Fábio já teve 4 meio-dias (o combinado é 1 dia = 2); a Gilda, 3 (no limite de 1,5 × 2)
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado, resultado, resultado_via)
    select v_os, c_joao, d, 'tarde', 'execucao', 'publicada', 'cumprido', 'tela'
      from unnest(array[date '2026-10-20', date '2026-10-21', date '2026-10-22', date '2026-10-23']) d;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado, resultado, resultado_via)
    select v_id, c_joao, d, 'manha', 'execucao', 'publicada', 'cumprido', 'tela'
      from unnest(array[date '2026-10-20', date '2026-10-21', date '2026-10-22']) d;
    update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-20 13:00-03' where id in (v_os, v_id);
    r := pg_temp.vigiar(date '2026-10-30', '09:00');
    v_res := pg_temp.ok(v_res, 'V34 parada?: o Antônio em andamento com dia no plano não é perguntado',
      not exists (select 1 from public.agenda_perguntas where tipo = 'parada' and service_order_id = pg_temp.os('201')), null);
    v_res := pg_temp.ok(v_res, 'V35 estouro: o Fábio teve 4 meio-dias e o combinado era 2 → "O que falta?"; a Gilda (3, no limite) não',
      (r #>> '{contagens,estouro,criadas}')::int = 1
      and (select texto = 'Fábio (OS-00210) já teve 2 dias de serviço e o combinado era 1 dia. O que falta?' and chave = 'estouro:' || v_os || ':2'
             from public.agenda_perguntas where tipo = 'estouro'),
      (select string_agg(texto, ' / ') from public.agenda_perguntas where tipo = 'estouro'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- duração e material: a OS só com reserva porque os dias são só sugeridos / o material não foi conferido (só o A fica do
    -- cenário, para sobrar lugar para as reservas na semana)
    perform pg_temp.cenario();
    update public.service_orders set status = 'cancelled' where id in (pg_temp.os('202'), pg_temp.os('203'));
    perform pg_temp.modos('ligado', 'ligado');
    v_os := pg_temp.os_extra('212', 'Hugo', null, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_roberto, 'turnos', 'dia')));
    v_id := pg_temp.os_extra('213', 'Ivo', 1, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_joao, 'turnos', 'tarde')), false);
    r := pg_temp.vigiar(date '2026-10-29', '16:30');
    v_res := pg_temp.ok(v_res, 'V36 o Hugo (dias só sugeridos) e o Ivo (material não conferido) ficam como reserva na semana',
      exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_os and a.tipo = 'reserva' and a.condicao_tipo = 'duracao')
      and exists (select 1 from public.agenda_alocacoes a where a.service_order_id = v_id and a.tipo = 'reserva' and a.condicao_tipo = 'conferir_material'),
      pg_temp.vigentes(v_os) || ' / ' || pg_temp.vigentes(v_id));
    v_res := pg_temp.ok(v_res, 'V37 …e a vigia pergunta "quantos dias?" a um e "tem peça a comprar?" ao outro (uma por OS)',
      (r #>> '{contagens,duracao_material,duracao}')::int = 1 and (r #>> '{contagens,duracao_material,material_conferir}')::int = 1
      and (select texto like 'Quantos dias leva Hugo (OS-00212), e com quem? Guardei lugar a partir de %; preciso saber até %.'
             from public.agenda_perguntas where chave = 'duracao:' || v_os)
      and (select texto like 'Ivo (OS-00213) tem peça a comprar? Guardei lugar a partir de %; preciso saber até %.'
             from public.agenda_perguntas where chave = 'material_conferir:' || v_id),
      (select string_agg(texto, ' / ' order by chave) from public.agenda_perguntas where tipo in ('duracao', 'material_conferir')));
    v_res := pg_temp.ok(v_res, 'V38 a OS que o dono já disse (A) não ganha pergunta de duração nem de material',
      not exists (select 1 from public.agenda_perguntas q where q.tipo in ('duracao', 'material_conferir')
                    and q.service_order_id = pg_temp.os('201')), null);
    update public.os_planejamento set material_conferido_em = timestamptz '2026-10-29 17:00-03' where service_order_id = v_id;
    r := pg_temp.vigiar(date '2026-10-29', '17:15');
    v_res := pg_temp.ok(v_res, 'V39 o dono conferiu o material do Ivo: a pergunta se resolve',
      (select estado = 'resolvida' and resolvida_motivo = 'o material foi conferido' from public.agenda_perguntas where chave = 'material_conferir:' || v_id),
      null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o dono sem padrão: a OS em que ele fica o turno inteiro fica fora e a vigia pergunta os dias (uma por semana)
    perform pg_temp.cenario();
    perform pg_temp.modos('ligado', 'ligado');
    r := pg_temp.vigiar(date '2026-10-29', '16:30');
    v_res := pg_temp.ok(v_res, 'V40 com o seu padrão dito, nenhuma pergunta de padrão',
      not (r #>> '{contagens,padrao_do_dono,criada}')::boolean and not exists (select 1 from public.agenda_perguntas where tipo = 'padrao_do_dono'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.cenario();
    perform pg_temp.modos('ligado', 'ligado');
    update public.agenda_disponibilidade set substituida_em = timestamptz '2026-10-29 10:00-03' where payee_id = c_dono and substituida_em is null;
    r := pg_temp.vigiar(date '2026-10-29', '16:30');
    v_res := pg_temp.ok(v_res, 'V41 você sem padrão: a Beatriz (você o turno todo) fica fora e a vigia pergunta quais dias você vai',
      (r #>> '{contagens,padrao_do_dono,criada}')::boolean
      and (select texto = 'Para marcar Beatriz (OS-00202), preciso saber em que dias você fica em campo. Quais dias da semana você vai?'
                  and chave = 'padrao_do_dono:2026-10-26' from public.agenda_perguntas where tipo = 'padrao_do_dono'),
      (select texto from public.agenda_perguntas where tipo = 'padrao_do_dono'));
    r := pg_temp.vigiar(date '2026-10-29', '16:45');
    v_res := pg_temp.ok(v_res, 'V42 uma por semana', (select count(*) from public.agenda_perguntas where tipo = 'padrao_do_dono') = 1, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- pouco serviço pronto na fila (a frase da quinta) e a poda
    r := pg_temp.publicado();
    v_res := pg_temp.ok(v_res, 'V43 na quinta depois da publicação: a fila depois da semana, contra a capacidade, e a frase pronta',
      (r #>> '{contagens,backlog,calculado}')::boolean and (r #>> '{contagens,backlog,abaixo}')::boolean
      and r #>> '{contagens,backlog,texto}' = 'Depois desta semana, não tem serviço pronto na fila.', (r -> 'contagens' -> 'backlog')::text);
    r := pg_temp.vigiar(date '2026-10-30', '09:00');
    v_res := pg_temp.ok(v_res, 'V44 fora do dia do plano, nada', r #>> '{contagens,backlog,calculado}' = 'false', null);
    insert into public.agenda_vigia_rodadas (p_hoje, p_agora, modo_proposta, modo_vigia)
    values (date '2026-08-29', timestamptz '2026-08-29 09:00-03', 'sombra', 'sombra'),
           (date '2026-09-01', timestamptz '2026-09-01 09:00-03', 'sombra', 'sombra');
    r := pg_temp.vigiar(date '2026-10-30', '09:15');
    v_res := pg_temp.ok(v_res, 'V45 poda: a rodada de mais de 60 dias sai; a de 59 fica',
      (r #>> '{contagens,poda,apagadas}')::int = 1
      and not exists (select 1 from public.agenda_vigia_rodadas x where x.p_hoje = date '2026-08-29')
      and exists (select 1 from public.agenda_vigia_rodadas x where x.p_hoje = date '2026-09-01'), (r -> 'contagens' -> 'poda')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a falha forçada num passo: a pergunta "parada?" quebra; os outros passos rodam e o erro fica consultável
    perform pg_temp.cenario();
    perform pg_temp.modos('ligado', 'ligado');
    insert into public.os_material (service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico, situacao,
                                    fonte, previsao_ate, previsao_fonte, conferido_em)
    values (pg_temp.os('202'), 'dono', 'Sensor de nível', 1, 0, true, 'a_caminho', 'dono', date '2026-10-27', 'dono',
            timestamptz '2026-10-26 18:00-03');
    update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-20 08:00-03' where id = pg_temp.os('203');
    create function public._teste_quebra_parada() returns trigger language plpgsql as $q$
    begin
      if new.tipo = 'parada' then raise exception 'falha de teste na parada'; end if;
      return new;
    end $q$;
    create trigger _teste_quebra_parada before insert on public.agenda_perguntas
      for each row execute function public._teste_quebra_parada();
    r := pg_temp.vigiar(date '2026-10-29', '09:00');
    v_res := pg_temp.ok(v_res, 'V46 a falha num passo (parada) não derruba a vigia: erros = 1, os outros passos rodam (chegou? perguntou)',
      (r ->> 'rodou')::boolean and (r ->> 'erros')::int = 1 and r -> 'falhas' -> 0 ->> 'passo' = 'parada'
      and not (r -> 'contagens' ? 'parada') and (r #>> '{contagens,chegou,criadas}')::int = 1
      and r -> 'contagens' ? 'poda' and r -> 'contagens' ? 'publicacao', (r -> 'falhas')::text);
    v_res := pg_temp.ok(v_res, 'V47 o erro vai para app_error_logs (db, context agenda, action vigia:parada) e a rodada guarda erros = 1',
      exists (select 1 from public.app_error_logs e where e.source = 'db' and e.context = 'agenda' and e.action = 'vigia:parada'
                and e.message like 'vigia da agenda, passo parada: falha de teste na parada%')
      and (select x.erros from public.agenda_vigia_rodadas x order by x.rodou_em desc limit 1) = 1,
      (select string_agg(e.message, ' / ') from public.app_error_logs e where e.context = 'agenda'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── L. A limpeza das propostas e das perguntas ──
  begin
    perform pg_temp.publicado();
    -- uma proposta aberta que o dono pediu (simulação gravada), outra que vai vencer, e uma pergunta com validade
    r := public.agenda_propor('os', null, null, array[pg_temp.os('203')], '{}'::jsonb, true, 'dono', c_admin, date '2026-10-29',
                              pg_temp.em(date '2026-10-29', '16:40'));
    v_id := (r ->> 'proposta_id')::uuid;
    -- (uma conferência de um dia ainda sem resultado: a limpeza não a resolve pelo fato, só pela validade)
    insert into public.agenda_perguntas (tipo, chave, dia, texto, modo, expira_em)
    values ('conferencia', 'estouro:teste:vence', date '2026-11-03', 'Pergunta que vence', 'ligado', pg_temp.em(date '2026-10-29', '16:50'));
    r := pg_temp.vigiar(date '2026-10-29', '16:45');
    v_res := pg_temp.ok(v_res, 'L1 a proposta aberta da versão de agora fica aberta (nada mudou no plano)',
      (r #>> '{contagens,limpeza,obsoletas}')::int = 0 and (select estado from public.agenda_propostas where id = v_id) = 'aberta', null);
    update public.agenda_config set versao_plano = versao_plano + 1 where id;
    r := pg_temp.vigiar(date '2026-10-29', '17:00');
    v_res := pg_temp.ok(v_res, 'L2 o plano mudou depois dela: obsoleta, e as alocações de proposta dela saem; a pergunta que venceu fica vencida',
      (r #>> '{contagens,limpeza,obsoletas}')::int = 1 and (select estado from public.agenda_propostas where id = v_id) = 'obsoleta'
      and not exists (select 1 from public.agenda_alocacoes where proposta_id = v_id and estado = 'proposta')
      and (r #>> '{contagens,limpeza,vencidas}')::int = 1
      and (select estado from public.agenda_perguntas where chave = 'estouro:teste:vence') = 'vencida', (r -> 'contagens' -> 'limpeza')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.cenario();
    perform pg_temp.modos('sombra', 'sombra');
    r := pg_temp.vigiar(date '2026-10-29', '16:30');
    v_id := (select id from public.agenda_propostas where escopo = 'semana');
    -- a proposta em sombra vence no início do 1º meio-dia dela (ter 03/11 08:00)
    r := pg_temp.vigiar(date '2026-11-03', '09:00');
    v_res := pg_temp.ok(v_res, 'L3 a proposta em sombra não fica obsoleta (o plano não muda em sombra): vence (expirada) e as alocações dela saem',
      (r #>> '{contagens,limpeza,expiradas}')::int = 1 and (select estado from public.agenda_propostas where id = v_id) = 'expirada'
      and not exists (select 1 from public.agenda_alocacoes where proposta_id = v_id), (r -> 'contagens' -> 'limpeza')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── Z. O replano em sombra e o *desfaz* da semana ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modos('sombra', 'sombra');
    r := public.agenda_replanejar(array[pg_temp.os('201')], 'teste', 'vigia', date '2026-10-29', pg_temp.em(date '2026-10-29', '16:30'));
    v_res := pg_temp.ok(v_res, 'Z1 agenda_replanejar em sombra: a proposta fica aberta em sombra e o que faria entra com executada = false',
      (r ->> 'ok')::boolean and (r ->> 'simulacao')::boolean and r ->> 'texto' like 'Em teste (nada foi mudado): eu teria feito assim — Antônio (OS-00201): %'
      and (select modo = 'sombra' and estado = 'aberta' and escopo = 'replano' from public.agenda_propostas where id = (r ->> 'proposta_id')::uuid)
      and (select count(*) from public.agenda_acoes where not executada and service_order_id = pg_temp.os('201')) = 1
      and not exists (select 1 from public.agenda_alocacoes where estado in ('publicada', 'fixada')), r ->> 'texto');
    perform pg_temp.modos('desligado', 'sombra');
    r := public.agenda_replanejar(array[pg_temp.os('201')], 'teste', 'vigia', date '2026-10-29', pg_temp.em(date '2026-10-29', '16:35'));
    v_res := pg_temp.ok(v_res, 'Z2 com a proposta desligada, replanejar não faz nada', not (r ->> 'ok')::boolean, r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado();
    r := public.agenda_desfazer_dito(c_admin, null, 'whatsapp', date '2026-10-29', pg_temp.em(date '2026-10-29', '16:40'));
    v_res := pg_temp.ok(v_res, 'Z3 *desfaz* sem nome com 3 publicações: pergunta qual, nada muda',
      not (r ->> 'ok')::boolean and r ->> 'status' = 'ambiguo' and r ->> 'texto' like 'Qual? %'
      and (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')) = 16, r ->> 'texto');
    r := public.agenda_desfazer_dito(c_admin, 'semana', 'whatsapp', date '2026-10-29', pg_temp.em(date '2026-10-29', '16:41'));
    v_res := pg_temp.ok(v_res, 'Z4 *desfaz semana*: as 3 publicações desfeitas de uma vez; nada fica em vigor e A e B voltam a aprovadas',
      (r ->> 'ok')::boolean and r ->> 'texto' like 'Desfiz a publicação da semana (3 mudanças): %'
      and not exists (select 1 from public.agenda_alocacoes where estado in ('publicada', 'fixada'))
      and (select count(*) from public.agenda_acoes where tipo = 'publicar' and desfeita_em is not null) = 3
      and (select bool_and(status = 'approved') from public.service_orders where id in (pg_temp.os('201'), pg_temp.os('202'))), r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- tudo ou nada: com o dia da Beatriz já anotado, *desfaz semana* não desfaz nenhuma das três
    perform pg_temp.publicado();
    perform set_config('agenda.hoje', '2026-11-05', true);
    update public.agenda_alocacoes set resultado = 'cumprido', resultado_via = 'tela' where service_order_id = pg_temp.os('202');
    r := public.agenda_desfazer_dito(c_admin, 'semana', 'whatsapp', date '2026-10-29', pg_temp.em(date '2026-10-29', '16:41'));
    v_res := pg_temp.ok(v_res, 'Z5 *desfaz semana* com uma das três que não dá mais: recusa e nada é desfeito (tudo ou nada)',
      not (r ->> 'ok')::boolean and r ->> 'texto' like 'Não dá para desfazer%'
      and (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')) = 16
      and not exists (select 1 from public.agenda_acoes where desfeita_em is not null or tipo = 'desfazer'), r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── X. A carteira de 29/10 (fixture-fase2): o custo do tique e a quinta de verdade ──
  begin
    if coalesce(current_setting('agenda_teste.fase2', true), '') = '' then
      v_res := pg_temp.ok(v_res, 'X1 a carteira de 29/10', true, 'PULADO: sem agenda_teste.fase2');
    else
      execute current_setting('agenda_teste.fase2');
      perform pg_temp.modos('ligado', 'ligado');
      v_txt := clock_timestamp()::text;
      r := pg_temp.vigiar(date '2026-10-29', '16:20');
      v_n := (extract(epoch from clock_timestamp() - v_txt::timestamptz) * 1000)::int;
      v_txt := clock_timestamp()::text;
      r2 := pg_temp.vigiar(date '2026-10-29', '16:30');
      v_n2 := (extract(epoch from clock_timestamp() - v_txt::timestamptz) * 1000)::int;
      v_res := pg_temp.ok(v_res, 'X1 a carteira de 29/10: o tique comum em menos de 3 s e o da publicação em menos de 5 s na bancada, sem erro',
        v_n < 3000 and v_n2 < 5000 and (r ->> 'erros')::int = 0 and (r2 ->> 'erros')::int = 0, v_n || ' ms / ' || v_n2 || ' ms');
      v_res := pg_temp.ok(v_res, 'X2 a carteira de 29/10: a quinta publica, o Nelson (precisa até qui 05/11, não cabe) fica com a decisão aberta e a saúde fecha',
        (r2 #>> '{contagens,publicacao,publicou}')::boolean and (r2 #>> '{contagens,publicacao,perguntas}')::int = 1
        and pg_temp.vigentes(pg_temp.os('112')) = ''
        and exists (select 1 from public.agenda_perguntas q where q.tipo = 'nao_cabe' and q.estado = 'aberta' and q.service_order_id = pg_temp.os('112'))
        and (public.agenda_saude(date '2026-10-29', pg_temp.em(date '2026-10-29', '16:50')) ->> 'ok')::boolean,
        (r2 -> 'contagens' -> 'publicacao')::text);
    end if;
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S. A saúde ──
  begin
    perform pg_temp.publicado();
    r := pg_temp.vigiar(date '2026-11-03', '17:00');
    r := public.agenda_conferir_dia(c_admin, 'cumprido', null, null, 'whatsapp', date '2026-11-03', pg_temp.em(date '2026-11-03', '17:40'));
    r := public.agenda_saude(date '2026-11-03', pg_temp.em(date '2026-11-03', '17:45'));
    v_res := pg_temp.ok(v_res, 'S1 saúde no cenário publicado e conferido: sem_decisao = 0, pela_regra_sem_decisao = 0, choques = 0, ok',
      (r ->> 'ok')::boolean and (r #>> '{criticas,sem_decisao}')::int = 0 and (r #>> '{criticas,pela_regra_sem_decisao}')::int = 0
      and (r #>> '{invariantes,choques}')::int = 0 and (r #>> '{invariantes,espelho_divergente}')::int = 0
      and (r #>> '{invariantes,vigente_de_os_fora_da_carteira}')::int = 0, r::text);
    v_res := pg_temp.ok(v_res, 'S2 saúde: a vigia rodou nas últimas 2 h; hoje 1 resultado e 1 status; os modos',
      (r #>> '{vigia,rodou_nas_ultimas_2h}')::boolean and (r #>> '{hoje,resultado}')::int = 1 and (r #>> '{hoje,status}')::int = 1
      and r #>> '{modos,proposta}' = 'ligado' and r #>> '{modos,vigia}' = 'ligado'
      and (r #>> '{plano,os_programadas}')::int = 2, r::text);
    -- forçando: uma ação crítica executada com a pergunta ainda aberta (o gatilho desligado só aqui dentro)
    insert into public.agenda_perguntas (id, tipo, chave, service_order_id, texto, opcoes, recomendacao, modo)
    values ('a6000000-0000-4000-8000-000000000001', 'nao_cabe', 'nao_cabe:teste', pg_temp.os('202'), 'Pergunta de teste',
            '[{"n": 1, "texto": "a"}, {"n": 2, "texto": "b"}]'::jsonb, 1, 'ligado');
    alter table public.agenda_acoes disable trigger agenda_acoes_critica_decidida;
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, critica, pergunta_id, texto)
    values (date '2026-11-03', true, 'motor', 'mover', pg_temp.os('202'), true, 'a6000000-0000-4000-8000-000000000001', 'crítica forçada');
    alter table public.agenda_acoes enable trigger agenda_acoes_critica_decidida;
    r := public.agenda_saude(date '2026-11-03', pg_temp.em(date '2026-11-03', '17:46'));
    v_res := pg_temp.ok(v_res, 'S3 a métrica enxerga: uma ação crítica executada sem decisão → sem_decisao = 1 e ok = false',
      (r #>> '{criticas,sem_decisao}')::int = 1 and not (r ->> 'ok')::boolean, (r -> 'criticas')::text);
    -- e o erro de classificação: um "mover" não crítico que andou 9 dias (a regra diz atraso longo)
    insert into public.agenda_acoes (id, dia, executada, origem, tipo, service_order_id, atraso_du, antes, depois, texto)
    values ('a6000000-0000-4000-8000-000000000002', date '2026-11-03', true, 'vigia', 'mover', pg_temp.os('202'), 5,
            '{"fim": "2026-11-05"}'::jsonb, '{"fim": "2026-11-14"}'::jsonb, 'atraso longo não perguntado');
    r := public.agenda_saude(date '2026-11-03', pg_temp.em(date '2026-11-03', '17:47'));
    v_res := pg_temp.ok(v_res, 'S4 …e o "mover" não crítico de 9 dias aparece em pela_regra_sem_decisao',
      (r #>> '{criticas,pela_regra_sem_decisao}')::int = 1
      and r -> 'criticas' -> 'pela_regra_acoes' = '["a6000000-0000-4000-8000-000000000002"]'::jsonb, (r -> 'criticas')::text);
    v_res := pg_temp.ok(v_res, 'S5 a regra reconferida por ação: o 1º atraso não é "segundo"; um 2º atraso não desfeito é',
      public._agenda_criticidade_da_acao('a6000000-0000-4000-8000-000000000002') = 'atraso_longo'
      and (select public._agenda_criticidade_da_acao(a.id) from public.agenda_acoes a
            where a.service_order_id = pg_temp.os('201') and a.tipo = 'publicar') is null, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.publicado();
    perform pg_temp.modos('sombra', 'ligado');
    update public.service_orders set scheduled_end_at = timestamptz '2026-11-06 17:00-03' where id = pg_temp.os('201');
    perform pg_temp.modos('ligado', 'ligado');
    if to_regclass('public.resumo_tarde') is null then
      create table public.resumo_tarde (dia date, phone_normalized text, detalhe jsonb not null default '{}');
    end if;
    insert into public.resumo_tarde (dia, phone_normalized, detalhe)
    values (date '2026-10-29', '5547999999999', '{"agenda": {"linhas_diria": [], "linhas_mostrou": []}}'::jsonb);
    r := public.agenda_saude(date '2026-10-29', pg_temp.em(date '2026-10-29', '17:45'));
    v_res := pg_temp.ok(v_res, 'S6 o espelho que divergiu do plano aparece (1); o fechamento que leu a agenda hoje também',
      (r #>> '{invariantes,espelho_divergente}')::int = 1 and (r #>> '{fechamento,leu_o_plano_hoje}')::boolean, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    r := pg_temp.publicado('sombra', 'sombra');
    r := public.agenda_saude(date '2026-10-29', pg_temp.em(date '2026-10-29', '16:50'));
    v_res := pg_temp.ok(v_res, 'S7 em sombra a saúde conta o que faria (3) e nada executado; ok',
      (r ->> 'ok')::boolean and (r #>> '{hoje,sombra}')::int = 3 and (r #>> '{hoje,publicar}')::int = 0
      and (r #>> '{plano,alocacoes_vigentes_futuras}')::int = 0 and (r #>> '{propostas,sombra_7d}')::int = 1, r::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── F. O que foi contado ──
  begin
    perform pg_temp.publicado();
    r := pg_temp.vigiar(date '2026-11-03', '13:05');
    v_id := (select id from public.agenda_perguntas where chave = 'conferencia:2026-11-03');
    x := (select jsonb_agg(a.id order by a.id) from public.agenda_acoes a where a.tipo = 'publicar');
    r := public.agenda_fechamento_registrar(date '2026-11-03', jsonb_build_array(jsonb_build_object('pergunta_id', v_id, 'acao_ids', x)),
                                            'fechamento', pg_temp.em(date '2026-11-03', '17:30'));
    v_res := pg_temp.ok(v_res, 'F1 o fechamento mostrou a conferência e a publicação: mostrada 1 vez; as 3 ações contadas no fechamento',
      (r ->> 'perguntas')::int = 1 and (r ->> 'acoes')::int = 3
      and (select mostrada_vezes = 1 and mostrada_via = 'fechamento' and mostrada_em = pg_temp.em(date '2026-11-03', '17:30')
             from public.agenda_perguntas where id = v_id)
      and (select bool_and(contada_via = 'fechamento') from public.agenda_acoes where tipo = 'publicar'), r::text);
    r := public.agenda_fechamento_registrar(date '2026-11-04', jsonb_build_array(jsonb_build_object('pergunta_id', v_id, 'acao_ids', x)),
                                            'fechamento', pg_temp.em(date '2026-11-04', '17:30'));
    v_res := pg_temp.ok(v_res, 'F2 no dia seguinte: a pergunta vai a 2 vezes; as ações já contadas não contam de novo',
      (r ->> 'perguntas')::int = 1 and (r ->> 'acoes')::int = 0
      and (select mostrada_vezes from public.agenda_perguntas where id = v_id) = 2, r::text);
    v_id := (select a.id from public.agenda_acoes a where a.tipo = 'status' and a.service_order_id = pg_temp.os('201'));
    r := public.agenda_acorde_registrado(v_id, null, false, pg_temp.em(date '2026-10-29', '16:31'));
    r2 := public.agenda_acorde_registrado(v_id, 'a6000000-0000-4000-8000-0000000000aa', true, pg_temp.em(date '2026-10-29', '16:32'));
    v_res := pg_temp.ok(v_res, 'F3 o acorde que não saiu não conta; o que saiu fica contado_via acorde',
      not (r ->> 'marcada')::boolean and (r2 ->> 'marcada')::boolean
      and (select contada_via = 'acorde' and contada_em = pg_temp.em(date '2026-10-29', '16:32') from public.agenda_acoes where id = v_id),
      r::text || ' / ' || r2::text);
    v_txt := pg_temp.erro_de($s$select public.agenda_fechamento_registrar('2026-11-03', '[]'::jsonb, 'email')$s$);
    v_res := pg_temp.ok(v_res, 'F4 por onde foi mostrado fora da lista: recusado (22023)', v_txt like '22023%', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$conf$;

-- ── J. Portas ───────────────────────────────────────────────────────────────────────────────────────────
with f(assinatura, leitura, servico) as (values
  ('public.agenda_saude(date, timestamptz)', true, true),
  ('public._agenda_criticidade_da_acao(uuid)', true, true),
  ('public._agenda_motivo_dito(text)', true, true),
  ('public._agenda_classe_agora(uuid, date)', true, true),
  ('public.agenda_registrar_dia(uuid, date, text, text, uuid, uuid[], text, text, date, timestamptz, text)', true, true),
  ('public.agenda_conferir_dia(uuid, text, text, text, text, date, timestamptz)', true, true),
  ('public.agenda_choveu(uuid, text, text, date, timestamptz)', true, true),
  ('public.agenda_desfazer_dito(uuid, text, text, date, timestamptz)', true, true),
  ('public.agenda_replanejar(uuid[], text, text, date, timestamptz, uuid)', false, true),
  ('public.agenda_vigiar(date, timestamptz)', false, true),
  ('public.agenda_fechamento_registrar(date, jsonb, text, timestamptz)', false, true),
  ('public.agenda_acorde_registrado(uuid, uuid, boolean, timestamptz)', false, true),
  ('public._agenda_propor_e_aplicar(text, uuid[], text, uuid, date, timestamptz)', false, false),
  ('public._agenda_acoes_da_sombra(uuid, text, uuid, date, timestamptz)', false, false),
  ('public._agenda_vigia_perguntar(text, text, uuid, uuid, date, date, text, text, timestamptz, boolean, uuid[])', false, false),
  ('public._agenda_vigia_limpeza(date, timestamptz)', false, false),
  ('public._agenda_vigia_violacoes(date, timestamptz)', false, false),
  ('public._agenda_vigia_publicacao(date, timestamptz)', false, false),
  ('public._agenda_vigia_poda(date, timestamptz)', false, false))
insert into _resultado
select 'J1 anon sem nada; a vigia, o replano e os registros só service_role; as palavras e a saúde também authenticated; os passos, ninguém',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = f.leitura
                and has_function_privilege('service_role', f.assinatura, 'execute') = f.servico),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> f.leitura
                                              or has_function_privilege('service_role', f.assinatura, 'execute') <> f.servico)
  from f;

insert into _resultado
select 'J2 nenhuma função da agenda executável por anon',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname ~ '^_?agenda_' and has_function_privilege('anon', p.oid, 'execute')),
       (select string_agg(p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname ~ '^_?agenda_' and has_function_privilege('anon', p.oid, 'execute'));

insert into _resultado
select 'J3 security definer só as que gravam (palavras, replano, vigia, registros); os passos e a saúde invoker; search_path fixo',
       bool_and(p.prosecdef = (p.proname in ('agenda_registrar_dia', 'agenda_conferir_dia', 'agenda_choveu', 'agenda_desfazer_dito',
                                             'agenda_replanejar', 'agenda_vigiar', 'agenda_fechamento_registrar',
                                             'agenda_acorde_registrado')))
       and bool_and(coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')
       and bool_and(case p.proname when 'agenda_saude' then p.provolatile = 's' when '_agenda_criticidade_da_acao' then p.provolatile = 's'
                                   else true end),
       string_agg(p.proname || ':' || p.prosecdef::text || ':' || p.provolatile::text, ', ' order by p.proname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('agenda_registrar_dia', 'agenda_conferir_dia', 'agenda_choveu', 'agenda_desfazer_dito', 'agenda_replanejar',
                     'agenda_vigiar', 'agenda_fechamento_registrar', 'agenda_acorde_registrado', 'agenda_saude',
                     '_agenda_criticidade_da_acao', '_agenda_propor_e_aplicar', '_agenda_acoes_da_sombra', '_agenda_classe_agora',
                     '_agenda_vigia_perguntar', '_agenda_vigia_ja_tentou', '_agenda_vigia_limpeza', '_agenda_vigia_sem_registro',
                     '_agenda_vigia_violacoes', '_agenda_vigia_reservas', '_agenda_vigia_material', '_agenda_vigia_dia_nao_cumprido',
                     '_agenda_vigia_publicacao', '_agenda_vigia_conferencia', '_agenda_vigia_chegou', '_agenda_vigia_parada',
                     '_agenda_vigia_estouro', '_agenda_vigia_duracao_material', '_agenda_vigia_padrao_do_dono',
                     '_agenda_vigia_backlog', '_agenda_vigia_poda');

select teste, ok, detalhe from _resultado order by teste;

rollback;
