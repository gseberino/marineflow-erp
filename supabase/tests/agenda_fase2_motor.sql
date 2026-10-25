-- Prova do motor da Agenda de Produção, Fase 2 (pacote P2; migration 20261025100200).
-- bancada: depende de 20261025100200
--
-- Com o cenário à mão (scripts/bancada-agenda/cenario-motor.sql: qui 29/10/2026, o dono, o Roberto e o João, as OS A, B
-- e C da spec §14.2), a carteira de 29/10 (fixture-fase2.sql) e o replay da OS-00104 (fixture-replay-0104.sql):
--   M  insumos: o molde dos meios-dias (agenda_meios_da_os), a grade (agenda_grade: as pontas do dono, o ocupado), a
--      classe de cada OS (_agenda_classe_da_os)
--   E  o encaixe do cenário célula por célula (A ter 03–qua 04, B qui 05 de manhã, C reserva condicionada de qui 05 à
--      tarde a ter 10/11 de manhã com "compre até ter 03/11"), nada em 02/11 nem em 29–30/10, a carga (Roberto 5 de 6,
--      João 2 de 3), o tipo diagnóstico, os textos
--   I  invariantes por INSERT/UPDATE/DELETE direto sobre o que o motor publicou
--   S  estabilidade: uma OS nova de prioridade 1 não move o publicado
--   C  congelamento: nada novo em qui 29 e sex 30/10; o evento real (a pessoa que não vem amanhã) replaneja, e a OS em
--      andamento pode usar o meio-dia livre do congelado — nenhuma outra OS
--   T  teto por pessoa e semana: 80% de compromisso; com acima_da_carga até 100%
--   P  presença do dono: abre e fecha (curta), sempre (diagnóstico), dono sem padrão (a ponta vale; a OS "sempre" fica de
--      fora com "falta você dizer quais dias fica em campo")
--   U  multi-dia: 1 interrupção aceita; 2 recusam esse início
--   F  Finados e Consciência Negra: nunca alocados, e o bloco que os atravessa não conta interrupção
--   R  replay da OS-00104 em sex 02/10: nada antes de qua 07/10, reserva condicionada à compra ("comprando hoje" /
--      "compre até"), nada na ter 06/10
--   O  sobrecarga: X fora com a pergunta nao_cabe (opções e recomendação); aplicar sem a resposta não publica X;
--      agenda_decidir publica com critica = true e pergunta_id
--   D  desfazer: dentro do prazo volta exatamente; depois do 1º meio-dia começar, recusa sem mudar nada
--   V  validar e aplicar: proposta válida; o vigente mudou = recusa com a lista; obsoleta (o motor refaz); expirada
--   K  marcar (o pedido do dono) e não caber; decidir; desfazível; a OS do dia; a regra do que é crítico
--   Z  sombra: a proposta é gravada em sombra e nada é publicado
--   Q  a prontidão com o plano (programada, a evidência, parada só sem dia) e a cópia de os_prontidao igual à da Fase 1
--      fora dos pontos "-- FASE 2:"
--   X  determinismo (md5 2×) e custo (< 2 s na bancada)
-- Sempre (com ou sem as fixtures):
--   J  portas: anon sem nada; o motor que grava só service_role; marcar e as leituras também authenticated
--
-- ═══ COMO RODAR ═══
--   Na bancada (sempre):  node scripts/bancada-agenda/rodar.mjs --ate 20261025100200
--   Em produção, só DEPOIS de aplicar 20261025100000..100200, com o OK nomeado do dono:
--     npx supabase db query --linked -f supabase/tests/agenda_fase2_motor.sql
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
-- As células de uma OS numa proposta: "03/11 manha Roberto turno | …" (dia, turno, nome, presença).
create function pg_temp.celulas(p_r jsonb, p_numero text, p_op text default 'criar') returns text language sql immutable as $f$
  select coalesce(string_agg(to_char((a ->> 'dia')::date, 'DD/MM') || ' ' || (a ->> 'turno') || ' ' || (a ->> 'nome') || ' ' || (a ->> 'presenca'),
                             ' | ' order by (a ->> 'dia')::date, a ->> 'turno' = 'tarde', a ->> 'nome', a ->> 'presenca'), '')
    from jsonb_array_elements(coalesce(p_r -> 'itens', '[]'::jsonb)) i, jsonb_array_elements(i -> 'alocacoes') a
   where i ->> 'numero' = p_numero and i ->> 'op' = p_op
$f$;
-- As células vigentes (publicadas/fixadas) de uma OS no banco, no mesmo formato.
create function pg_temp.vigentes(p_os uuid) returns text language sql stable as $f$
  select coalesce(string_agg(to_char(a.dia, 'DD/MM') || ' ' || a.turno || ' ' || public._agenda_nome_curto(py.name) || ' ' || a.presenca,
                             ' | ' order by a.dia, a.turno = 'tarde', public._agenda_nome_curto(py.name), a.presenca), '')
    from public.agenda_alocacoes a join public.payees py on py.id = a.payee_id
   where a.service_order_id = p_os and a.estado in ('publicada', 'fixada')
$f$;
create function pg_temp.item(p_r jsonb, p_numero text, p_op text default 'criar') returns jsonb language sql immutable as $f$
  select i from jsonb_array_elements(coalesce(p_r -> 'itens', '[]'::jsonb)) with ordinality t(i, k)
   where i ->> 'numero' = p_numero and i ->> 'op' = p_op order by k limit 1
$f$;
-- Meios-dias de turno (compromisso ou reserva) de uma pessoa nos itens "criar", na semana que começa em p_seg.
create function pg_temp.meios(p_r jsonb, p_nome text, p_seg date, p_reserva boolean default false) returns int
language sql immutable as $f$
  select count(*)::int
    from jsonb_array_elements(coalesce(p_r -> 'itens', '[]'::jsonb)) i, jsonb_array_elements(i -> 'alocacoes') a
   where i ->> 'op' = 'criar' and a ->> 'nome' = p_nome and a ->> 'presenca' = 'turno'
     and (a ->> 'dia')::date between p_seg and p_seg + 6 and ((i ->> 'tipo') = 'reserva') = p_reserva
$f$;
-- A proposta com a hora padrão (16:30 de Brasília do dia).
create function pg_temp.propor(p_escopo text, p_hoje date, p_restr jsonb default '{}'::jsonb, p_os uuid[] default null,
                               p_persistir boolean default false, p_agora timestamptz default null) returns jsonb
language sql as $f$
  select public.agenda_propor(p_escopo, null, null, p_os, p_restr, p_persistir, 'motor', null, p_hoje,
                              coalesce(p_agora, (p_hoje + time '16:30') at time zone 'America/Sao_Paulo'))
$f$;
-- Propõe e aplica pelo motor; devolve a resposta do aplicar com o id da proposta.
create function pg_temp.publicar(p_escopo text, p_hoje date, p_os uuid[] default null, p_restr jsonb default '{}'::jsonb)
returns jsonb language plpgsql as $f$
declare
  r jsonb := pg_temp.propor(p_escopo, p_hoje, p_restr, p_os, true);
begin
  return public.agenda_aplicar((r ->> 'proposta_id')::uuid, null, 'motor', null, null, p_hoje,
                               ((p_hoje + time '16:31') at time zone 'America/Sao_Paulo')) || jsonb_build_object('proposta', r);
end $f$;
create function pg_temp.cenario() returns void language plpgsql as $f$
begin
  execute current_setting('agenda_teste.cenario_motor');
end $f$;
create function pg_temp.modo(p_modo text) returns void language sql as $f$
  update public.agenda_config set modo_proposta = p_modo where id
$f$;
-- Uma OS a mais no cenário (sinal pago, material conferido, aprovada em 20/10): número, cliente, dias, presença do dono e
-- a equipe [{payee, turnos}].
create function pg_temp.os_extra(p_n text, p_cliente text, p_dias numeric, p_presenca text, p_equipe jsonb,
                                 p_prio int default null, p_precisa date default null) returns uuid language plpgsql as $f$
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
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, precisa_ate,
                                      prioridade_manual, material_conferido_em)
  values (v_os, p_dias, 'dono', timestamptz '2026-10-28 18:00-03', p_presenca, p_precisa, p_prio, timestamptz '2026-10-28 18:00-03');
  for e in select x from jsonb_array_elements(coalesce(p_equipe, '[]'::jsonb)) x loop
    insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values (v_os, (e ->> 'payee')::uuid, e ->> 'turnos');
  end loop;
  return v_os;
end $f$;

-- ── Os cenários ─────────────────────────────────────────────────────────────────────────────────────────
do $motor$
declare
  v_fix     boolean := coalesce(current_setting('agenda_teste.cenario_motor', true), '') <> ''
                       and coalesce(current_setting('agenda_teste.fase2', true), '') <> ''
                       and coalesce(current_setting('agenda_teste.replay_0104', true), '') <> ''
                       and exists (select 1 from public.payees where id = 'bb000000-0000-4000-8000-000000000002');
  c_hoje    constant date := date '2026-10-29';
  c_agora   constant timestamptz := timestamptz '2026-10-29 16:30-03';
  c_admin   constant uuid := 'aa000000-0000-4000-8000-000000000001';
  c_dono    constant uuid := 'bb000000-0000-4000-8000-000000000001';
  c_roberto constant uuid := 'bb000000-0000-4000-8000-000000000002';
  c_joao    constant uuid := 'bb000000-0000-4000-8000-000000000003';
  c_a       constant text := '03/11 manha Gustavo abertura | 03/11 manha Roberto turno | 03/11 tarde João turno | 03/11 tarde Roberto turno'
                             || ' | 04/11 manha Roberto turno | 04/11 tarde Gustavo fechamento | 04/11 tarde João turno | 04/11 tarde Roberto turno';
  c_b       constant text := '05/11 manha Gustavo turno | 05/11 manha Roberto turno';
  c_c       constant text := '05/11 tarde Roberto turno | 06/11 manha Roberto turno | 06/11 tarde Roberto turno'
                             || ' | 09/11 manha Roberto turno | 09/11 tarde Roberto turno | 10/11 manha Roberto turno';
  v_res     jsonb := '[]'::jsonb;
  r         jsonb;
  r2        jsonb;
  r3        jsonb;
  x         jsonb;
  v_txt     text;
  v_txt2    text;
  v_n       int;
  v_n2      bigint;
  v_id      uuid;
  v_id2     uuid;
  v_ok      boolean;
  v_t0      timestamptz;
  v_ms      numeric;
  v_os      uuid;
begin
  if not v_fix then
    insert into _resultado values ('M–X cenários do motor', true,
      'PULADO: sem as fixtures (agenda_teste.cenario_motor, fase2, replay_0104): rode pela bancada');
    return;
  end if;

  -- ── M. Insumos ──
  begin
    perform pg_temp.cenario();
    r := public.agenda_meios_da_os(pg_temp.os('201'), c_hoje);
    v_res := pg_temp.ok(v_res, 'M1 A: 4 meios-dias; você abre no 1º e fecha no 4º; de manhã o Roberto (1), à tarde o Roberto e o João (2)',
      r ->> 'total' = '4' and r ->> 'passos' = '4' and r ->> 'presenca' = 'abre_e_fecha' and (r ->> 'abre')::boolean
      and (r ->> 'fecha')::boolean and r #>> '{por_turno,manha,desejado}' = '1' and r #>> '{por_turno,tarde,desejado}' = '2'
      and r -> 'molde' -> 0 -> 'dono' = '["abertura"]'::jsonb and r -> 'molde' -> 3 -> 'dono' = '["fechamento"]'::jsonb
      and r -> 'molde' -> 1 -> 'dono' = '[]'::jsonb and r -> 'molde' -> 1 -> 'pessoas_ditas' @> '[{"nome": "João"}]'::jsonb, r::text);
    r := public.agenda_meios_da_os(pg_temp.os('202'), c_hoje);
    v_res := pg_temp.ok(v_res, 'M2 B: meio dia; você na equipe dita = o turno inteiro; 1 diarista (o Roberto); o tipo é diagnóstico',
      r ->> 'total' = '1' and r ->> 'presenca' = 'equipe' and (r #>> '{dono_turno,manha}')::boolean
      and r #>> '{por_turno,manha,desejado}' = '1' and r -> 'molde' -> 0 -> 'dono' = '["turno"]'::jsonb
      and r ->> 'regra_motivo' = 'diagnóstico', r::text);
    r := public.agenda_meios_da_os(pg_temp.os('203'), c_hoje);
    v_res := pg_temp.ok(v_res, 'M3 C: 6 meios-dias, abre e fecha pela regra (d05)',
      r ->> 'total' = '6' and r ->> 'restantes' = '6' and r ->> 'presenca' = 'abre_e_fecha' and r ->> 'presenca_motivo' = 'padrão', r::text);
    v_txt := (select string_agg(q.n || ':' || (public._agenda_classe_da_os(public.os_prontidao(pg_temp.os(q.n), c_hoje),
                                  public.agenda_meios_da_os(pg_temp.os(q.n), c_hoje), c_hoje) ->> 'classe')
                                || coalesce('/' || (public._agenda_classe_da_os(public.os_prontidao(pg_temp.os(q.n), c_hoje),
                                  public.agenda_meios_da_os(pg_temp.os(q.n), c_hoje), c_hoje) ->> 'condicao_tipo'), ''), ' ' order by q.n)
                from (values ('201'), ('202'), ('203')) q(n));
    v_res := pg_temp.ok(v_res, 'M4 classes: A e B 2 (prontas); C 3 (só reserva, condicionada à compra)', v_txt = '201:2 202:2 203:3/compra', v_txt);
    select string_agg(g.nome || ' ' || to_char(g.dia, 'DD/MM') || ' ' || g.turno || ' ' || g.situacao || ' ' || g.livre::text || ' '
                      || array_to_string(g.curta_livre, ','), ' | ' order by g.eh_dono desc, g.nome, g.dia, g.turno = 'tarde')
      into v_txt
      from public.agenda_grade(date '2026-11-02', date '2026-11-03', c_hoje) g
     where g.payee_id in (c_dono, c_joao) and (g.dia = date '2026-11-02' and g.turno = 'manha' or g.dia = date '2026-11-03');
    v_res := pg_temp.ok(v_res, 'M5 a grade: Finados sem ponta; ter 03 você livre com as duas pontas; o João só à tarde (de manhã sem padrão)',
      v_txt = 'Gustavo 02/11 manha feriado false  | Gustavo 03/11 manha livre true abertura,fechamento | Gustavo 03/11 tarde livre true abertura,fechamento'
              || ' | João 02/11 manha feriado false  | João 03/11 manha sem_padrao false  | João 03/11 tarde livre true ', v_txt);
    select count(*) into v_n from public.agenda_grade(date '2026-11-02', date '2026-11-08', c_hoje) g
     where g.payee_id = 'bb000000-0000-4000-8000-000000000004';
    v_res := pg_temp.ok(v_res, 'M6 o Mickael (sem padrão em vigor) não está na grade', v_n = 0, v_n::text);
    select array_to_string(g.curta_livre, ',') into v_txt from public.agenda_grade(date '2026-11-06', date '2026-11-06', c_hoje) g
     where g.payee_id = c_dono and g.turno = 'tarde';
    v_res := pg_temp.ok(v_res, 'M7 sexta à tarde (você no escritório): nenhuma ponta', v_txt = '', v_txt);
    -- o compromisso com hora do dono ocupa a ponta
    insert into public.agenda_tasks (title, assignee_user_id, created_by, status, priority, kind, source, scheduled_start_at, scheduled_end_at)
    values ('Reunião', c_admin, c_admin, 'pending', 'normal', 'appointment', 'manual',
            timestamptz '2026-11-03 08:00-03', timestamptz '2026-11-03 08:30-03');
    select array_to_string(g.curta_livre, ',') into v_txt from public.agenda_grade(date '2026-11-03', date '2026-11-03', c_hoje) g
     where g.payee_id = c_dono and g.turno = 'manha';
    v_res := pg_temp.ok(v_res, 'M8 compromisso com hora às 08:00 de ter 03: a abertura sai, o fechamento fica', v_txt = 'fechamento', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── E. O encaixe do cenário, célula por célula ──
  begin
    perform pg_temp.cenario();
    r := pg_temp.propor('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'E1 A: ter 03 manhã (Roberto + você abrindo), ter 03 tarde (Roberto + João), qua 04 manhã (Roberto), qua 04 tarde (Roberto + João + você fechando)',
      pg_temp.celulas(r, 'OS-00201') = c_a, pg_temp.celulas(r, 'OS-00201'));
    v_res := pg_temp.ok(v_res, 'E2 B: qui 05 manhã, você o turno inteiro + Roberto (ter 03 e qua 04 não dão)',
      pg_temp.celulas(r, 'OS-00202') = c_b and pg_temp.item(r, 'OS-00202') ->> 'tipo' = 'diagnostico', pg_temp.celulas(r, 'OS-00202'));
    x := pg_temp.item(r, 'OS-00203');
    v_res := pg_temp.ok(v_res, 'E3 C: reserva condicionada (compra) de qui 05 à tarde a ter 10/11 de manhã, os 6 meios do Roberto',
      pg_temp.celulas(r, 'OS-00203') = c_c and x ->> 'tipo' = 'reserva' and x ->> 'reserva_de' = 'condicionada'
      and x ->> 'condicao_tipo' = 'compra', pg_temp.celulas(r, 'OS-00203') || ' ' || x::text);
    v_res := pg_temp.ok(v_res, 'E4 C: condicao_ate ter 03/11 (05/11 − folga 1 − entrega local 1) e o "compre até" no texto',
      x ->> 'condicao_ate' = '2026-11-03' and x ->> 'condicao' like '%compre até ter 03/11%' and x ->> 'texto' like '%compre até ter 03/11%',
      x ->> 'condicao');
    v_res := pg_temp.ok(v_res, 'E5 nada em seg 02/11 (Finados) nem em qui 29 e sex 30/10 (congelado)',
      not exists (select 1 from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                   where (a ->> 'dia')::date in (date '2026-10-29', date '2026-10-30', date '2026-11-02')), null);
    v_res := pg_temp.ok(v_res, 'E6 carga da semana de 02/11: Roberto 5 de compromisso (teto 6) + 3 de reserva (teto 100% = 8); João 2 (teto 3); você 1 turno (teto 5)',
      pg_temp.meios(r, 'Roberto', date '2026-11-02') = 5 and pg_temp.meios(r, 'Roberto', date '2026-11-02', true) = 3
      and pg_temp.meios(r, 'João', date '2026-11-02') = 2 and pg_temp.meios(r, 'Gustavo', date '2026-11-02') = 1
      and r #>> array['carga', c_roberto::text, 'semanas', '0', 'teto80'] = '6'
      and r #>> array['carga', c_roberto::text, 'semanas', '0', 'teto100'] = '8'
      and r #>> array['carga', c_roberto::text, 'semanas', '0', 'compromisso'] = '5'
      and r #>> array['carga', c_roberto::text, 'semanas', '0', 'reserva'] = '3'
      and r #>> array['carga', c_joao::text, 'semanas', '0', 'teto80'] = '3'
      and r #>> array['carga', c_dono::text, 'semanas', '0', 'teto80'] = '5', (r -> 'carga')::text);
    v_res := pg_temp.ok(v_res, 'E7 nada de fora, nenhuma pergunta, nada a cancelar; simulação (sem id) e o aviso no texto',
      r -> 'fora' = '[]'::jsonb and r -> 'perguntas' = '[]'::jsonb and r ->> 'proposta_id' is null and (r ->> 'simulacao')::boolean
      and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'op' = 'cancelar')
      and r ->> 'texto' like '%É simulação: não muda nada.', r ->> 'texto');
    v_res := pg_temp.ok(v_res, 'E8 os textos: o título com o feriado e uma linha por OS',
      r #>> '{textos,titulo}' = 'Semana de 03 a 06/11 (seg 02 é Finados)'
      and r #>> '{textos,linhas,0}' = 'Antônio (OS-00201): ter 03 e qua 04/11, você abre e fecha, Roberto os 2 dias, João à tarde.'
      and r #>> '{textos,linhas,1}' = 'Beatriz (OS-00202), diagnóstico: qui 05/11, você, Roberto.'
      and r #>> '{textos,linhas,2}' like 'Reserva Caio (OS-00203): qui 05 à tarde a ter 10/11 de manhã, Roberto os 4 dias — se "Cabo de bateria…" estiver na mão (compre até ter 03/11, fornecedor Premel).',
      (r -> 'textos')::text);
    v_res := pg_temp.ok(v_res, 'E9 nenhuma alocação gravada sem persistir (nem proposta)',
      not exists (select 1 from public.agenda_alocacoes) and not exists (select 1 from public.agenda_propostas), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── I. Invariantes sobre o publicado (ligado) ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    v_n2 := (select versao_plano from public.agenda_config);
    r := pg_temp.publicar('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'I1 publicou: 16 alocações em vigor, a versão do plano subiu 16 (uma por linha que entrou), A e B agendadas',
      (r ->> 'ok')::boolean and (select count(*) from public.agenda_alocacoes where estado in ('publicada', 'fixada')) = 16
      and (select versao_plano from public.agenda_config) = v_n2 + 16
      and (select status from public.service_orders where id = pg_temp.os('201')) = 'scheduled'
      and (select status from public.service_orders where id = pg_temp.os('202')) = 'scheduled'
      and (select status from public.service_orders where id = pg_temp.os('203')) = 'approved'
      and pg_temp.vigentes(pg_temp.os('201')) = c_a, r ->> 'texto');
    v_id := (select id from public.agenda_alocacoes where service_order_id = pg_temp.os('201') and payee_id = c_roberto
              and dia = date '2026-11-03' and turno = 'manha');
    v_txt := pg_temp.erro_de(format($s$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado)
                                       values (%L, %L, '2026-11-03', 'manha', 'execucao', 'publicada')$s$, pg_temp.os('202'), c_roberto));
    v_res := pg_temp.ok(v_res, 'I2 o Roberto em dois lugares no vigente: recusado (23P01)', v_txt like '23P01%', v_txt);
    v_txt := pg_temp.erro_de(format($s$insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado, proposta_id)
                                       values (%L, %L, '2026-11-12', 'manha', 'execucao', 'proposta', %L),
                                              (%L, %L, '2026-11-12', 'manha', 'execucao', 'proposta', %L)$s$,
                                    pg_temp.os('202'), c_joao, r ->> 'proposta_id', pg_temp.os('203'), c_joao, r ->> 'proposta_id'));
    v_res := pg_temp.ok(v_res, 'I3 a mesma pessoa duas vezes dentro da proposta: recusado (23P01)', v_txt like '23P01%', v_txt);
    v_txt := pg_temp.erro_de(format('update public.agenda_alocacoes set dia = %L where id = %L', '2026-11-12', v_id));
    v_res := pg_temp.ok(v_res, 'I4 publicada não muda de dia', v_txt like '%Alocação publicada não muda%', v_txt);
    update public.agenda_alocacoes set estado = 'fixada', fixado_por = 'dono' where id = v_id;
    v_txt := pg_temp.erro_de(format('update public.agenda_alocacoes set estado = %L where id = %L', 'cancelada', v_id));
    v_res := pg_temp.ok(v_res, 'I5 fixada → cancelada sem a chave: recusado', v_txt like '%fixado: só sai com a decisão%', v_txt);
    v_txt := pg_temp.erro_de(format('delete from public.agenda_alocacoes where id = %L', v_id));
    v_txt2 := pg_temp.erro_de(format('delete from public.agenda_alocacoes where service_order_id = %L', pg_temp.os('203')));
    v_res := pg_temp.ok(v_res, 'I6 apagar o que vigorou (fixada, publicada): recusado', v_txt like '%não se apaga%' and v_txt2 like '%não se apaga%',
      v_txt || ' / ' || v_txt2);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, tipo, estado, proposta_id)
    values ('a5000000-0000-4000-8000-000000000001', pg_temp.os('202'), c_joao, date '2026-11-12', 'tarde', 'execucao', 'proposta',
            (r ->> 'proposta_id')::uuid);
    v_n2 := (select versao_plano from public.agenda_config);
    delete from public.agenda_alocacoes where id = 'a5000000-0000-4000-8000-000000000001';
    v_res := pg_temp.ok(v_res, 'I7 a alocação de proposta (nunca vigorou) se apaga, e a versão não sobe por ela',
      not exists (select 1 from public.agenda_alocacoes where id = 'a5000000-0000-4000-8000-000000000001')
      and (select versao_plano from public.agenda_config) = v_n2, null);
    v_txt := pg_temp.erro_de('delete from public.agenda_propostas');
    v_txt2 := pg_temp.erro_de('delete from public.agenda_acoes');
    v_res := pg_temp.ok(v_res, 'I8 propostas e ações não se apagam', v_txt like '%não se apaga%' and v_txt2 like '%não se apaga%',
      v_txt || ' / ' || v_txt2);
    v_txt := pg_temp.erro_de(format($s$insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, critica, texto)
                                       values ('2026-10-29', true, 'motor', 'mover', %L, true, 'teste')$s$, pg_temp.os('201')));
    v_res := pg_temp.ok(v_res, 'I9 ação crítica sem pergunta: recusada', v_txt like '23514%', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── S. Estabilidade ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    r := pg_temp.publicar('semana', c_hoje);
    v_txt := pg_temp.vigentes(pg_temp.os('201')) || '#' || pg_temp.vigentes(pg_temp.os('202')) || '#' || pg_temp.vigentes(pg_temp.os('203'));
    v_os := pg_temp.os_extra('206', 'Fábio', 0.5, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_joao, 'turnos', 'tarde')), 1);
    r2 := pg_temp.propor('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'S1 OS nova de prioridade 1: nada do publicado é cancelado ou movido; ela entra onde sobra (o João, qui 05 à tarde)',
      not exists (select 1 from jsonb_array_elements(r2 -> 'itens') i where i ->> 'op' = 'cancelar')
      and not exists (select 1 from jsonb_array_elements(r2 -> 'itens') i where i ->> 'op' = 'criar' and i ->> 'numero' <> 'OS-00206')
      and pg_temp.celulas(r2, 'OS-00206') = '05/11 tarde João turno', pg_temp.celulas(r2, 'OS-00206') || ' ' || (r2 -> 'itens')::text);
    r3 := pg_temp.publicar('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'S2 publicada a 2ª proposta, o que já estava no plano está igual',
      (r3 ->> 'ok')::boolean and v_txt = pg_temp.vigentes(pg_temp.os('201')) || '#' || pg_temp.vigentes(pg_temp.os('202')) || '#'
                                         || pg_temp.vigentes(pg_temp.os('203')), r3 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── C. Congelamento ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    -- publicado na ter 27/10: o A cai em qui 29 e sex 30/10
    r := pg_temp.publicar('os', date '2026-10-27', array[pg_temp.os('201')]);
    v_txt := pg_temp.vigentes(pg_temp.os('201'));
    r2 := pg_temp.propor('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'C1 na qui 29/10 nada novo entra em 29 ou 30/10',
      v_txt like '29/10 manha Gustavo abertura | 29/10 manha Roberto turno%'
      and not exists (select 1 from jsonb_array_elements(r2 -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                       where i ->> 'op' = 'criar' and (a ->> 'dia')::date <= date '2026-10-30'), v_txt || ' / ' || (r2 -> 'itens')::text);
    -- o Roberto avisa que não vem sex 30/10 de manhã
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-10-30', date '2026-10-31'), 'manha', 'indisponivel', 'dono', 'médico');
    r2 := pg_temp.propor('semana', c_hoje);
    x := pg_temp.item(r2, 'OS-00201', 'cancelar');
    v_res := pg_temp.ok(v_res, 'C2 evento real: o meio-dia do A na sex 30 de manhã sai (a pessoa não vem), como fato',
      x ->> 'motivo' = 'pessoa' and (x ->> 'violada')::boolean and pg_temp.celulas(r2, 'OS-00201', 'cancelar') like '30/10 manha Roberto turno%',
      pg_temp.celulas(r2, 'OS-00201', 'cancelar'));
    v_res := pg_temp.ok(v_res, 'C3 o resto do A volta no 1º lugar que dá (o evento real pode usar o que está livre no congelado)',
      (pg_temp.item(r2, 'OS-00201') ->> 'evento_real')::boolean, pg_temp.celulas(r2, 'OS-00201'));
    v_res := pg_temp.ok(v_res, 'C4 nenhuma OS fora a do evento entra em 29–30/10',
      not exists (select 1 from jsonb_array_elements(r2 -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                   where i ->> 'op' = 'criar' and (a ->> 'dia')::date <= date '2026-10-30' and i ->> 'numero' <> 'OS-00201'),
      (r2 -> 'itens')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a OS em andamento perde o meio-dia de amanhã (o Roberto não vem de manhã) e usa a tarde livre do congelado
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    v_os := pg_temp.os_extra('207', 'Gilberto', 1, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_roberto, 'turnos', 'dia')));
    update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-29 08:00-03' where id = v_os;
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado) values
      (v_os, c_roberto, date '2026-10-29', 'manha', 'execucao', 'publicada'),
      (v_os, c_roberto, date '2026-10-30', 'manha', 'execucao', 'publicada');
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-10-30', date '2026-10-31'), 'manha', 'indisponivel', 'dono', 'médico');
    r2 := pg_temp.propor('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'C5 a OS em andamento (classe 1) replaneja dentro do congelado: sex 30 à tarde, com o Roberto',
      pg_temp.celulas(r2, 'OS-00207', 'cancelar') = '30/10 manha Roberto turno' and pg_temp.celulas(r2, 'OS-00207') = '30/10 tarde Roberto turno'
      and (pg_temp.item(r2, 'OS-00207') ->> 'evento_real')::boolean,
      pg_temp.celulas(r2, 'OS-00207', 'cancelar') || ' → ' || pg_temp.celulas(r2, 'OS-00207'));
    v_res := pg_temp.ok(v_res, 'C6 e só ela entra no congelado',
      not exists (select 1 from jsonb_array_elements(r2 -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                   where i ->> 'op' = 'criar' and (a ->> 'dia')::date <= date '2026-10-30' and i ->> 'numero' <> 'OS-00207'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── T. Teto por pessoa ──
  begin
    perform pg_temp.cenario();
    v_os := pg_temp.os_extra('204', 'Diego', 2, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_roberto, 'turnos', 'dia')));
    r := pg_temp.propor('semana', c_hoje);
    r2 := pg_temp.propor('semana', c_hoje, '{"acima_da_carga": true}'::jsonb);
    v_res := pg_temp.ok(v_res, 'T1 com mais uma OS do Roberto: na semana de 02/11 ele fica em floor(0,8 × 8) = 6 meios de compromisso',
      pg_temp.meios(r, 'Roberto', date '2026-11-02') = 6, pg_temp.meios(r, 'Roberto', date '2026-11-02')::text || ' ' || (r -> 'itens')::text);
    v_res := pg_temp.ok(v_res, 'T2 com acima_da_carga passa de 6 e fica até floor(8) = 8',
      pg_temp.meios(r2, 'Roberto', date '2026-11-02') between 7 and 8, pg_temp.meios(r2, 'Roberto', date '2026-11-02')::text);
    v_res := pg_temp.ok(v_res, 'T3 nas duas, compromisso + reserva nunca passa de 8 na semana',
      pg_temp.meios(r, 'Roberto', date '2026-11-02') + pg_temp.meios(r, 'Roberto', date '2026-11-02', true) <= 8
      and pg_temp.meios(r2, 'Roberto', date '2026-11-02') + pg_temp.meios(r2, 'Roberto', date '2026-11-02', true) <= 8, null);
    x := (select i from jsonb_array_elements(r -> 'itens') i where i ->> 'numero' = 'OS-00202' and i ->> 'op' = 'criar');
    v_res := pg_temp.ok(v_res, 'T4 o B, que não coube na semana com 80%, ganha a reserva por teto (a equipe guarda o lugar; você não)',
      x ->> 'tipo' = 'reserva' and x ->> 'reserva_de' = 'teto' and x ->> 'condicao' is null
      and not exists (select 1 from jsonb_array_elements(x -> 'alocacoes') a where a ->> 'nome' = 'Gustavo'),
      pg_temp.celulas(r, 'OS-00202') || ' ' || coalesce(x::text, 'sem item'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- o pátio: o barco do Heitor está fora a semana toda; dá para adiantar 1 dia sem ele (só o João, à tarde)
    perform pg_temp.cenario();
    v_os := pg_temp.os_extra('208', 'Heitor', 2, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_joao, 'turnos', 'tarde')));
    update public.os_planejamento set bem_indisponivel = '{[2026-11-02,2026-11-09)}', adiantavel_patio_dias = 1
     where service_order_id = v_os;
    r := pg_temp.propor('semana', c_hoje);
    x := pg_temp.item(r, 'OS-00208');
    v_res := pg_temp.ok(v_res, 'T5 reserva no pátio: o Heitor ganha 1 dia (2 meios) do João nos dias com o barco fora, sem você',
      x ->> 'tipo' = 'reserva' and x ->> 'reserva_de' = 'patio' and pg_temp.celulas(r, 'OS-00208') = '05/11 tarde João turno | 06/11 tarde João turno',
      pg_temp.celulas(r, 'OS-00208') || ' ' || coalesce(x::text, 'sem item'));
    v_res := pg_temp.ok(v_res, 'T6 com o barco fora, o Heitor não tem compromisso na semana (só a reserva no pátio)',
      not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'numero' = 'OS-00208' and i ->> 'op' = 'criar'
                    and i ->> 'tipo' <> 'reserva'), (r -> 'itens')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- a porta: aguardando peças com tudo na mão sai para agendada quando publica; o desempate pelo mesmo local
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    update public.service_orders set status = 'awaiting_parts' where id = pg_temp.os('201');
    r := pg_temp.publicar('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'T7 o A estava aguardando peças com o material conferido: publicado, vai para agendada pela porta (1 ação status)',
      (select status from public.service_orders where id = pg_temp.os('201')) = 'scheduled'
      and (select count(*) from public.agenda_acoes where service_order_id = pg_temp.os('201') and tipo = 'status'
             and status_antes = 'awaiting_parts' and status_depois = 'scheduled' and origem = 'motor') = 1, r ->> 'texto');
    v_res := pg_temp.ok(v_res, 'T8 no empate de fim, turnos do dono e interrupções, vence o dia com outra OS no mesmo local; depois o 1º início',
      public._agenda_melhor('{"fim": 9, "md": 0, "int": 0, "mesmo": true, "d0": 5}'::jsonb, '{"fim": 9, "md": 0, "int": 0, "mesmo": false, "d0": 3}'::jsonb)
      and not public._agenda_melhor('{"fim": 9, "md": 0, "int": 1, "mesmo": true, "d0": 3}'::jsonb, '{"fim": 9, "md": 0, "int": 0, "mesmo": false, "d0": 5}'::jsonb)
      and public._agenda_melhor('{"fim": 8, "md": 2, "int": 1, "mesmo": false, "d0": 5}'::jsonb, '{"fim": 9, "md": 0, "int": 0, "mesmo": true, "d0": 3}'::jsonb)
      and public._agenda_melhor('{"fim": 9, "md": 0, "int": 0, "mesmo": false, "d0": 3}'::jsonb, '{"fim": 9, "md": 0, "int": 0, "mesmo": false, "d0": 5}'::jsonb),
      null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── P. Presença do dono ──
  begin
    perform pg_temp.cenario();
    r := pg_temp.propor('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'P1 abre e fecha: no A, 1 abertura no 1º meio-dia e 1 fechamento no último; nenhum turno inteiro seu',
      (select count(*) from jsonb_array_elements(pg_temp.item(r, 'OS-00201') -> 'alocacoes') a where a ->> 'nome' = 'Gustavo') = 2
      and pg_temp.celulas(r, 'OS-00201') like '03/11 manha Gustavo abertura%'
      and pg_temp.celulas(r, 'OS-00201') like '%04/11 tarde Gustavo fechamento%'
      and pg_temp.celulas(r, 'OS-00201') not like '%Gustavo turno%', pg_temp.celulas(r, 'OS-00201'));
    -- B sem você na equipe dita: a regra (diagnóstico) põe você o tempo todo
    delete from public.os_planejamento_equipe where service_order_id = pg_temp.os('202') and payee_id = c_dono;
    r := pg_temp.propor('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'P2 diagnóstico pela regra (sempre): o turno inteiro seu em todo meio-dia do B',
      public.agenda_meios_da_os(pg_temp.os('202'), c_hoje) ->> 'presenca' = 'sempre' and pg_temp.celulas(r, 'OS-00202') = c_b,
      pg_temp.celulas(r, 'OS-00202'));
    -- você sem padrão
    update public.agenda_disponibilidade set substituida_em = now() where payee_id = c_dono and substituida_em is null;
    r := pg_temp.propor('semana', c_hoje);
    v_res := pg_temp.ok(v_res, 'P3 você sem padrão: a abertura e o fechamento continuam (d11), no A',
      pg_temp.celulas(r, 'OS-00201') like '03/11 manha Gustavo abertura%' and pg_temp.celulas(r, 'OS-00201') like '%Gustavo fechamento%',
      pg_temp.celulas(r, 'OS-00201'));
    v_res := pg_temp.ok(v_res, 'P4 você sem padrão: a OS "sempre" fica de fora com "falta você dizer quais dias fica em campo"',
      pg_temp.item(r, 'OS-00202') is null
      and exists (select 1 from jsonb_array_elements(r -> 'fora') f
                   where f ->> 'numero' = 'OS-00202' and f ->> 'motivo' = 'padrao_do_dono'
                     and f ->> 'texto' like '%falta você dizer quais dias fica em campo%'), (r -> 'fora')::text);
    select g.situacao || ' ' || array_to_string(g.curta_livre, ',') into v_txt
      from public.agenda_grade(date '2026-11-03', date '2026-11-03', c_hoje) g where g.payee_id = c_dono and g.turno = 'manha';
    v_res := pg_temp.ok(v_res, 'P5 na grade: sem padrão, mas com as duas pontas', v_txt = 'sem_padrao abertura,fechamento', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── U. Multi-dia com no máximo 1 interrupção ──
  begin
    perform pg_temp.cenario();
    -- só o C, pronto (o cabo na mão), sem você
    update public.service_orders set status = 'cancelled' where id in (pg_temp.os('201'), pg_temp.os('202'));
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = 1, chegou_em = date '2026-10-28'
     where service_order_id = pg_temp.os('203');
    update public.os_planejamento set dono_presenca = 'nunca' where service_order_id = pg_temp.os('203');
    -- o João (que trocaria o Roberto à tarde) fora a semana toda: só a interrupção decide
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota)
    values (c_joao, daterange(date '2026-11-02', date '2026-11-08'), 'indisponivel', 'dono', 'viagem');
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-11-04', date '2026-11-05'), 'indisponivel', 'dono', 'folga');
    -- (com a folga, a semana do Roberto tem 6 meios-dias esperados: 80% = 4 travaria antes da interrupção; acima_da_carga
    -- deixa só a regra da interrupção decidir)
    r := pg_temp.propor('semana', c_hoje, '{"acima_da_carga": true}'::jsonb);
    x := pg_temp.item(r, 'OS-00203');
    v_res := pg_temp.ok(v_res, 'U1 3 dias com o Roberto fora no 2º dia útil: começa ter 03 e termina sex 06, com 1 interrupção',
      x ->> 'tipo' = 'execucao' and x ->> 'de' = '2026-11-03' and x ->> 'ate' = '2026-11-06' and x ->> 'interrupcoes' = '1'
      and pg_temp.celulas(r, 'OS-00203') not like '%04/11%', pg_temp.celulas(r, 'OS-00203'));
    insert into public.agenda_disponibilidade (payee_id, periodo, situacao, origem, nota)
    values (c_roberto, daterange(date '2026-11-06', date '2026-11-07'), 'indisponivel', 'dono', 'folga');
    r := pg_temp.propor('os', c_hoje, '{"acima_da_carga": true}'::jsonb, array[pg_temp.os('203')]);
    x := pg_temp.item(r, 'OS-00203');
    v_res := pg_temp.ok(v_res, 'U2 fora no 2º e no 4º dia útil: o início de ter 03 é recusado; o bloco começa qui 05 (1 interrupção)',
      x ->> 'de' = '2026-11-05' and x ->> 'ate' = '2026-11-10' and x ->> 'interrupcoes' = '1', pg_temp.celulas(r, 'OS-00203'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── F. Finados e Consciência Negra ──
  begin
    perform pg_temp.cenario();
    update public.service_orders set status = 'cancelled' where id in (pg_temp.os('201'), pg_temp.os('202'));
    update public.os_material set situacao = 'na_mao', quantidade_na_mao = 1, chegou_em = date '2026-10-27'
     where service_order_id = pg_temp.os('203');
    update public.os_planejamento set dono_presenca = 'nunca' where service_order_id = pg_temp.os('203');
    r := pg_temp.propor('os', date '2026-10-28', '{}'::jsonb, array[pg_temp.os('203')]);
    x := pg_temp.item(r, 'OS-00203');
    v_res := pg_temp.ok(v_res, 'F1 visto na qua 28/10: sex 30, (Finados) ter 03 e qua 04 — sem 02/11 e sem interrupção',
      pg_temp.celulas(r, 'OS-00203') = '30/10 manha Roberto turno | 30/10 tarde Roberto turno | 03/11 manha Roberto turno | 03/11 tarde Roberto turno'
                                       || ' | 04/11 manha Roberto turno | 04/11 tarde Roberto turno'
      and x ->> 'interrupcoes' = '0', pg_temp.celulas(r, 'OS-00203'));
    r := pg_temp.propor('os', c_hoje, jsonb_build_object('so_depois_de', jsonb_build_array(jsonb_build_object('os', pg_temp.os('203'), 'dia', '2026-11-18'))),
                        array[pg_temp.os('203')]);
    x := pg_temp.item(r, 'OS-00203');
    v_res := pg_temp.ok(v_res, 'F2 só depois de qua 18/11: qua 18, qui 19, (Consciência Negra) seg 23 — nada em 20/11, sem interrupção',
      pg_temp.celulas(r, 'OS-00203') = '18/11 manha Roberto turno | 18/11 tarde Roberto turno | 19/11 manha Roberto turno | 19/11 tarde Roberto turno'
                                       || ' | 23/11 manha Roberto turno | 23/11 tarde Roberto turno'
      and x ->> 'interrupcoes' = '0', pg_temp.celulas(r, 'OS-00203'));
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── R. Replay da OS-00104 em sex 02/10 ──
  begin
    execute current_setting('agenda_teste.replay_0104');
    r := pg_temp.propor('semana', date '2026-10-02');
    x := pg_temp.item(r, 'OS-00104');
    v_res := pg_temp.ok(v_res, 'R1 nenhum compromisso da OS-00104 antes de qua 07/10 (o compressor chega ter 06 + 1 dia útil)',
      not exists (select 1 from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                   where i ->> 'numero' = 'OS-00104' and i ->> 'op' = 'criar' and i ->> 'tipo' <> 'reserva' and (a ->> 'dia')::date < date '2026-10-07'),
      (r -> 'itens')::text);
    v_res := pg_temp.ok(v_res, 'R2 a OS-00104 sai como reserva condicionada à compra, com a data-limite e "comprando hoje" ou "compre até"',
      x ->> 'tipo' = 'reserva' and x ->> 'reserva_de' = 'condicionada' and x ->> 'condicao_tipo' = 'compra' and x ->> 'condicao_ate' is not null
      and (x ->> 'texto' like '%comprando hoje%' or x ->> 'texto' like '%compre até%') and (x ->> 'de')::date >= date '2026-10-07',
      x::text);
    v_res := pg_temp.ok(v_res, 'R3 nada da OS-00104 na ter 06/10 (o dia em que ela foi marcada sem a peça)',
      not exists (select 1 from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                   where i ->> 'numero' = 'OS-00104' and (a ->> 'dia')::date = date '2026-10-06'), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── O. Sobrecarga: a pergunta nao_cabe ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    update public.os_planejamento set prioridade_manual = 1 where service_order_id = pg_temp.os('201');
    v_os := pg_temp.os_extra('205', 'Elisa', 1, 'nunca', jsonb_build_array(jsonb_build_object('payee', c_roberto, 'turnos', 'dia')),
                             null, date '2026-11-04');
    r := pg_temp.propor('semana', c_hoje, '{}'::jsonb, null, true);
    x := r -> 'perguntas' -> 0;
    v_res := pg_temp.ok(v_res, 'O1 a Elisa (precisa até qua 04/11) não cabe: fica fora da proposta, com a pergunta',
      pg_temp.item(r, 'OS-00205') is null
      and exists (select 1 from jsonb_array_elements(r -> 'fora') f where f ->> 'numero' = 'OS-00205' and f ->> 'motivo' = 'nao_cabe'
                    and f ->> 'pergunta_chave' = x ->> 'chave'), (r -> 'fora')::text);
    v_res := pg_temp.ok(v_res, 'O2 a pergunta nao_cabe: 2 opções (Elisa atrasa; o Antônio passa para depois), a recomendação pelo fato (sem data dita)',
      x ->> 'tipo' = 'nao_cabe' and jsonb_array_length(x -> 'opcoes') = 2
      and x -> 'opcoes' -> 0 ->> 'texto' like 'Elisa (OS-00205) atrasa: termina % em vez de qua 04/11'
      and x -> 'opcoes' -> 1 ->> 'texto' like 'Antônio (OS-00201) passa para % (sem data dita pelo cliente)'
      and x ->> 'recomendacao' = '2' and x ->> 'recomendacao_texto' = 'o Antônio não tem data dita pelo cliente'
      and (select count(*) from public.agenda_perguntas p where p.chave = x ->> 'chave' and p.estado = 'aberta' and p.critica and p.modo = 'ligado') = 1,
      x::text);
    v_res := pg_temp.ok(v_res, 'O3 o Antônio (que a Elisa empurraria) fica na proposta como item crítico, esperando a decisão',
      pg_temp.item(r, 'OS-00201') ->> 'critica' = 'nao_cabe' and (pg_temp.item(r, 'OS-00201') ->> 'espera')::boolean,
      pg_temp.item(r, 'OS-00201')::text);
    r2 := public.agenda_aplicar((r ->> 'proposta_id')::uuid, null, 'motor', null, null, c_hoje, c_agora + interval '1 minute');
    v_res := pg_temp.ok(v_res, 'O4 aplicar sem a resposta publica o resto e não publica nem a Elisa nem o Antônio',
      (r2 ->> 'ok')::boolean and pg_temp.vigentes(v_os) = '' and pg_temp.vigentes(pg_temp.os('201')) = ''
      and pg_temp.vigentes(pg_temp.os('203')) <> '', r2 ->> 'texto');
    v_id := (select id from public.agenda_perguntas where chave = x ->> 'chave' and estado = 'aberta');
    r3 := public.agenda_decidir(v_id, 9::smallint, c_admin, 'whatsapp', 'a nove', c_hoje, c_agora + interval '2 minutes');
    v_res := pg_temp.ok(v_res, 'O5 opção que não existe: recusa e a pergunta continua aberta',
      not (r3 ->> 'ok')::boolean and (select estado from public.agenda_perguntas where id = v_id) = 'aberta', r3 ->> 'texto');
    r3 := public.agenda_decidir(v_id, 2::smallint, c_admin, 'whatsapp', 'pode atrasar o Antônio', c_hoje, c_agora + interval '3 minutes');
    v_res := pg_temp.ok(v_res, 'O6 agenda_decidir (opção 2): a Elisa entra antes de qua 04/11 e o Antônio depois',
      (r3 ->> 'ok')::boolean and pg_temp.vigentes(v_os) <> '' and pg_temp.vigentes(pg_temp.os('201')) <> ''
      and (select max(dia) from public.agenda_alocacoes where service_order_id = v_os and estado in ('publicada', 'fixada')) <= date '2026-11-04',
      r3 ->> 'texto');
    v_res := pg_temp.ok(v_res, 'O7 a decisão fica registrada (respondida, opção 2, as palavras do dono) e as ações saem critica = true com pergunta_id',
      (select estado = 'respondida' and opcao_escolhida = 2 and resposta = 'pode atrasar o Antônio' and respondida_via = 'whatsapp'
         from public.agenda_perguntas where id = v_id)
      and (select count(*) from public.agenda_acoes a where a.pergunta_id = v_id and a.critica and a.executada
             and a.service_order_id in (v_os, pg_temp.os('201')) and a.tipo <> 'status') = 2, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── D. Desfazer ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    -- só o A (com a equipe livre, o replano é curto: o gestor faz sozinho)
    update public.service_orders set status = 'cancelled' where id in (pg_temp.os('202'), pg_temp.os('203'));
    r := pg_temp.publicar('semana', c_hoje);
    v_txt := pg_temp.vigentes(pg_temp.os('201'));
    -- o barco do Antônio fica fora na ter 03: o A é replanejado um dia para a frente (mover, não crítico)
    update public.os_planejamento set bem_indisponivel = '{[2026-11-03,2026-11-04)}' where service_order_id = pg_temp.os('201');
    r2 := pg_temp.publicar('replano', c_hoje, array[pg_temp.os('201')]);
    v_id := (select id from public.agenda_acoes where service_order_id = pg_temp.os('201') and tipo = 'mover' and executada);
    v_res := pg_temp.ok(v_res, 'D1 o replano do A é uma ação "mover", desfazível por 24 h (até o 1º meio-dia novo)',
      v_id is not null and pg_temp.vigentes(pg_temp.os('201')) <> v_txt
      and (select desfazivel_ate from public.agenda_acoes where id = v_id) = least(c_agora + interval '1 minute' + interval '1 day',
            (select min(lower(a.periodo)) from public.agenda_alocacoes a where a.id = any ((select alocacoes_criadas from public.agenda_acoes where id = v_id)::uuid[]))),
      r2 ->> 'texto');
    v_txt2 := pg_temp.vigentes(pg_temp.os('201'));
    r3 := public.agenda_desfazer(v_id, c_admin, 'dono', date '2026-11-03', timestamptz '2026-11-03 08:30-03');
    v_res := pg_temp.ok(v_res, 'D2 depois de começar o 1º meio-dia novo: "Não dá para desfazer", nada muda',
      not (r3 ->> 'ok')::boolean and r3 ->> 'texto' like 'Não dá%' and pg_temp.vigentes(pg_temp.os('201')) = v_txt2, r3 ->> 'texto');
    r3 := public.agenda_desfazer(v_id, c_admin, 'dono', c_hoje, c_agora + interval '10 minutes');
    v_res := pg_temp.ok(v_res, 'D3 dentro do prazo e antes de começar: volta exatamente ao que era (mesma pessoa, dia, turno e presença)',
      (r3 ->> 'ok')::boolean and pg_temp.vigentes(pg_temp.os('201')) = v_txt
      and (select status from public.service_orders where id = pg_temp.os('201')) = 'scheduled'
      and (select desfeita_pela from public.agenda_acoes where id = v_id) = (r3 ->> 'acao_id')::uuid, r3 ->> 'texto');
    r3 := public.agenda_desfazer(v_id, c_admin, 'dono', c_hoje, c_agora + interval '11 minutes');
    v_res := pg_temp.ok(v_res, 'D4 desfazer de novo: "Isso já foi desfeito."', r3 ->> 'texto' = 'Isso já foi desfeito.', r3 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── V. Validar e aplicar ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    r := pg_temp.propor('semana', c_hoje, '{}'::jsonb, null, true);
    v_id := (r ->> 'proposta_id')::uuid;
    v_res := pg_temp.ok(v_res, 'V1 a proposta recém-calculada é válida (agenda_validar vazia)',
      public.agenda_validar(v_id, null, c_hoje, c_agora) = '[]'::jsonb
      and (select estado = 'aberta' and modo = 'ligado' and versao_base = (select versao_plano from public.agenda_config)
             from public.agenda_propostas where id = v_id), null);
    -- alguém pôs o Roberto em outro lugar na ter 03 de manhã (o vigente mudou)
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado)
    values (pg_temp.os('203'), c_roberto, date '2026-11-03', 'manha', 'execucao', 'publicada');
    v_res := pg_temp.ok(v_res, 'V2 o vigente mudou: agenda_validar aponta o choque (regra 2)',
      exists (select 1 from jsonb_array_elements(public.agenda_validar(v_id, null, c_hoje, c_agora)) e where (e ->> 'regra')::int = 2),
      public.agenda_validar(v_id, null, c_hoje, c_agora)::text);
    r2 := public.agenda_aplicar(v_id, null, 'tela', c_admin, null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V3 a versão do plano mudou: aplicar pela tela não aplica (obsoleta)',
      not (r2 ->> 'ok')::boolean and (select estado from public.agenda_propostas where id = v_id) = 'obsoleta'
      and not exists (select 1 from public.agenda_alocacoes where proposta_id = v_id and estado = 'proposta'), r2 ->> 'texto');
    r := pg_temp.propor('semana', c_hoje, '{}'::jsonb, null, true);
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado)
    values (pg_temp.os('203'), c_joao, date '2026-11-20', 'tarde', 'execucao', 'publicada');
    r2 := public.agenda_aplicar((r ->> 'proposta_id')::uuid, null, 'motor', null, null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V4 pelo motor, a obsoleta é refeita com os mesmos parâmetros e a nova é aplicada',
      (r2 ->> 'ok')::boolean and (r2 ->> 'refeita')::boolean and pg_temp.vigentes(pg_temp.os('202')) <> '', r2 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    r := pg_temp.propor('semana', c_hoje, '{}'::jsonb, null, true);
    r2 := public.agenda_aplicar((r ->> 'proposta_id')::uuid, null, 'motor', null, null, c_hoje, c_agora + interval '4 days');
    v_res := pg_temp.ok(v_res, 'V5 passou da validade: expirada, nada publicado',
      not (r2 ->> 'ok')::boolean and (select estado from public.agenda_propostas where id = (r ->> 'proposta_id')::uuid) = 'expirada'
      and not exists (select 1 from public.agenda_alocacoes where estado in ('publicada', 'fixada')), r2 ->> 'texto');
    r2 := public.agenda_aplicar((r ->> 'proposta_id')::uuid, null, 'motor', null, null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'V6 aplicar de novo: "Esse plano venceu…" (nunca "proposta": no negócio é o orçamento)', r2 ->> 'texto' = 'Esse plano venceu. Peça de novo que eu monto outro.', r2 ->> 'texto');
    r := pg_temp.propor('semana', c_hoje, '{}'::jsonb, null, true);
    r2 := public.agenda_descartar((r ->> 'proposta_id')::uuid, c_admin, 'não quero');
    v_res := pg_temp.ok(v_res, 'V7 descartar: a proposta fica (descartada, com o motivo) e as alocações dela saem; nada publicado',
      (r2 ->> 'ok')::boolean
      and (select estado = 'descartada' and decidida_em is not null and motivo_fim = 'não quero'
             from public.agenda_propostas where id = (r ->> 'proposta_id')::uuid)
      and not exists (select 1 from public.agenda_alocacoes where proposta_id = (r ->> 'proposta_id')::uuid), r2 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    -- As regras duras, uma a uma, sobre itens feitos à mão (o motor nunca entrega isto: é a rede de segurança).
    perform pg_temp.cenario();
    update public.service_orders set status = 'awaiting_client' where id = pg_temp.os('202');
    update public.os_planejamento set bem_indisponivel = '{[2026-11-24,2026-11-25)}' where service_order_id = pg_temp.os('201');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, tipo, estado, fixado_por, publicada_em)
    values ('a5000000-0000-4000-8000-000000000010', pg_temp.os('201'), c_joao, date '2026-12-01', 'tarde', 'execucao', 'fixada',
            'congelamento', now());
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado, publicada_em)
    values (pg_temp.os('201'), c_joao, date '2026-12-02', 'tarde', 'execucao', 'publicada', now());
    r := jsonb_build_array(
      -- (1) o João de manhã (sem padrão); (4) abre e fecha sem você
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('201'), 'numero', 'OS-00201', 'tipo', 'execucao', 'abre', true, 'fecha', true,
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', c_joao, 'nome', 'João', 'dia', '2026-11-03', 'turno', 'manha', 'presenca', 'turno'))),
      -- (7) no congelado; (10) a OS esperando o cliente
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('202'), 'numero', 'OS-00202', 'tipo', 'execucao',
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-10-30', 'turno', 'manha', 'presenca', 'turno'),
                                       jsonb_build_object('payee_id', c_dono, 'nome', 'Gustavo', 'dia', '2026-10-30', 'turno', 'manha', 'presenca', 'turno'))),
      -- (11) a classe 3 como compromisso
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('203'), 'numero', 'OS-00203', 'tipo', 'execucao',
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-12', 'turno', 'manha', 'presenca', 'turno'))),
      -- (9) fora da carteira
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('50'), 'numero', 'OS-00050', 'tipo', 'execucao',
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-13', 'turno', 'manha', 'presenca', 'turno'))),
      -- (3) com o bem fora; (13) dois dias úteis parados no meio; (6) 7 meios-dias do Roberto numa semana de 8 esperados (teto 6)
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('201'), 'numero', 'OS-00201', 'tipo', 'execucao', 'abre', false, 'fecha', false,
        'alocacoes', jsonb_build_array(
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-16', 'turno', 'manha', 'presenca', 'turno'),
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-16', 'turno', 'tarde', 'presenca', 'turno'),
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-17', 'turno', 'manha', 'presenca', 'turno'),
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-17', 'turno', 'tarde', 'presenca', 'turno'),
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-18', 'turno', 'manha', 'presenca', 'turno'),
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-18', 'turno', 'tarde', 'presenca', 'turno'),
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-19', 'turno', 'manha', 'presenca', 'turno'),
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-24', 'turno', 'manha', 'presenca', 'turno'),
          jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-11-27', 'turno', 'manha', 'presenca', 'turno'))),
      -- (12) três serviços no mesmo meio-dia (o A já tem o João na qua 02/12 à tarde)
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('203'), 'numero', 'OS-00203', 'tipo', 'reserva', 'reserva_de', 'condicionada',
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', c_roberto, 'nome', 'Roberto', 'dia', '2026-12-02', 'turno', 'tarde', 'presenca', 'turno'))),
      jsonb_build_object('op', 'criar', 'os', pg_temp.os('202'), 'numero', 'OS-00202', 'tipo', 'reserva', 'reserva_de', 'teto',
        'alocacoes', jsonb_build_array(jsonb_build_object('payee_id', c_dono, 'nome', 'Gustavo', 'dia', '2026-12-02', 'turno', 'tarde', 'presenca', 'turno'))),
      -- (8) tirar um fixado sem autorização; (14) item crítico sem a decisão
      jsonb_build_object('op', 'cancelar', 'os', pg_temp.os('201'), 'numero', 'OS-00201', 'motivo', 'replanejado', 'violada', false,
        'critica', 'atraso_longo',
        'alocacoes', jsonb_build_array(jsonb_build_object('alocacao_id', 'a5000000-0000-4000-8000-000000000010', 'payee_id', c_joao,
                                                          'dia', '2026-12-01', 'turno', 'tarde', 'presenca', 'turno', 'estado', 'fixada'))));
    x := public._agenda_validar_itens(r, '{}'::jsonb, c_hoje, c_agora, true);
    v_txt := (select string_agg(distinct (e ->> 'regra'), ',' order by (e ->> 'regra')) from jsonb_array_elements(x) e);
    v_res := pg_temp.ok(v_res, 'V8 as regras duras pegam cada erro: 1, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13 e 14 (a 2 está no V2, a 5 no motor)',
      (select array_agg(distinct (e ->> 'regra')::int order by (e ->> 'regra')::int) from jsonb_array_elements(x) e)
        @> array[1, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14]
      and not exists (select 1 from jsonb_array_elements(x) e where e ->> 'texto' is null or char_length(e ->> 'texto') < 10), x::text);
    v_res := pg_temp.ok(v_res, 'V9 sem p_aplicar (a conferência do próprio motor) a regra 14 não entra',
      not exists (select 1 from jsonb_array_elements(public._agenda_validar_itens(r, '{}'::jsonb, c_hoje, c_agora, false)) e
                   where (e ->> 'regra')::int = 14), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── K. Marcar, desfazível, a OS do dia, a regra do que é crítico ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    r := public.agenda_marcar_os(c_admin, pg_temp.os('201'), date '2026-11-05', null, null, 'tela', 'dono', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'K1 marcar pela tela (o A na qui 05): fixado pelo dono, origem dono, a OS agendada, sem desfazer (foi pedido)',
      (r ->> 'ok')::boolean
      and (select bool_and(estado = 'fixada' and fixado_por = 'dono' and origem = 'dono') and min(dia) = date '2026-11-05'
             from public.agenda_alocacoes where service_order_id = pg_temp.os('201') and estado in ('publicada', 'fixada'))
      and (select status from public.service_orders where id = pg_temp.os('201')) = 'scheduled'
      and (select desfazivel_ate from public.agenda_acoes where service_order_id = pg_temp.os('201') and tipo = 'criar') is null,
      r ->> 'texto');
    r := public.agenda_marcar_os(c_admin, pg_temp.os('202'), date '2026-11-05', null, null, 'tela', 'dono', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'K2 o B na qui 05 não cabe: diz por quê e o 1º dia que dá; nada é marcado',
      not (r ->> 'ok')::boolean and r ->> 'texto' like 'Não cabe qui 05/11: %' and r ->> 'texto' like '%O primeiro dia que dá é %'
      and pg_temp.vigentes(pg_temp.os('202')) = '', r ->> 'texto');
    v_txt := pg_temp.erro_de(format('select public.agenda_marcar_os(%L, %L, %L)', 'aa000000-0000-4000-8000-000000000002',
                                    pg_temp.os('202'), '2026-11-06'));
    v_res := pg_temp.ok(v_res, 'K3 quem não é administrador não marca (42501)', v_txt like '42501%', v_txt);
    r := public.agenda_os_do_dia(c_roberto, date '2026-11-05');
    v_res := pg_temp.ok(v_res, 'K4 agenda_os_do_dia: o Roberto na qui 05 está no A (manhã e tarde)',
      jsonb_array_length(r) = 1 and r -> 0 ->> 'numero' = 'OS-00201' and r -> 0 -> 'turnos' = '["manha", "tarde"]'::jsonb, r::text);
    perform pg_temp.modo('sombra');
    v_res := pg_temp.ok(v_res, 'K5 fora de ligado, agenda_os_do_dia é vazia', public.agenda_os_do_dia(c_roberto, date '2026-11-05') = '[]'::jsonb, null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    r := pg_temp.publicar('semana', c_hoje);
    r2 := public.agenda_acao_desfazivel('semana', c_hoje, c_agora + interval '5 minutes');
    v_res := pg_temp.ok(v_res, 'K6 "desfaz semana": as 3 publicações da semana',
      r2 ->> 'status' = 'ok' and jsonb_array_length(r2 -> 'acao_ids') = 3
      and (select bool_and(tipo = 'publicar') from public.agenda_acoes where id in (select y::uuid from jsonb_array_elements_text(r2 -> 'acao_ids') y)),
      r2::text);
    r2 := public.agenda_acao_desfazivel('Antônio', c_hoje, c_agora + interval '5 minutes');
    v_res := pg_temp.ok(v_res, 'K7 "desfaz Antônio": a última mudança dele (a publicação)',
      r2 ->> 'status' = 'ok' and (select tipo from public.agenda_acoes where id = (r2 ->> 'acao_id')::uuid) = 'publicar', r2::text);
    r2 := public.agenda_acao_desfazivel(null, c_hoje, c_agora + interval '5 minutes');
    v_res := pg_temp.ok(v_res, 'K8 "desfaz" sem nome com várias: pergunta qual', r2 ->> 'status' = 'ambiguo' and r2 ->> 'texto' like 'Qual? %', r2 ->> 'texto');
    r2 := public.agenda_acao_desfazivel('Antônio', c_hoje, c_agora + interval '2 days');
    v_res := pg_temp.ok(v_res, 'K9 depois do prazo não há o que desfazer', r2 ->> 'status' = 'nenhuma', r2 ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.cenario();
    update public.os_planejamento set precisa_ate = date '2026-11-04' where service_order_id = pg_temp.os('201');
    v_txt := concat_ws(' | ',
      public._agenda_criticidade(pg_temp.os('201'), null, null, date '2026-11-05', date '2026-11-03', c_hoje),
      coalesce(public._agenda_criticidade(pg_temp.os('201'), null, null, date '2026-11-04', date '2026-11-03', c_hoje), '-'),
      public._agenda_criticidade(pg_temp.os('202'), date '2026-11-05', null, date '2026-11-12', date '2026-11-12', c_hoje),
      coalesce(public._agenda_criticidade(pg_temp.os('202'), date '2026-11-05', null, date '2026-11-06', date '2026-11-06', c_hoje), '-'));
    insert into public.agenda_acoes (dia, executada, origem, tipo, service_order_id, atraso_du, texto)
    values (c_hoje, true, 'motor', 'mover', pg_temp.os('202'), 1, 'atrasou 1 dia');
    update public.service_orders set client_confirmed_for = timestamptz '2026-11-05 08:00-03' where id = pg_temp.os('203');
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, tipo, estado, fixado_por, publicada_em)
    values ('a5000000-0000-4000-8000-000000000009', pg_temp.os('203'), c_roberto, date '2026-11-12', 'manha', 'execucao', 'fixada', 'dono', now());
    v_txt := concat_ws(' | ', v_txt,
      public._agenda_criticidade(pg_temp.os('202'), date '2026-11-05', null, date '2026-11-06', date '2026-11-06', c_hoje),
      public._agenda_criticidade(pg_temp.os('203'), date '2026-11-06', date '2026-11-05', date '2026-11-10', date '2026-11-10', c_hoje),
      public._agenda_criticidade(pg_temp.os('203'), null, null, date '2026-11-12', date '2026-11-12', c_hoje,
                                 array['a5000000-0000-4000-8000-000000000009']::uuid[]),
      coalesce(public._agenda_criticidade(pg_temp.os('203'), null, null, date '2026-11-12', date '2026-11-12', c_hoje,
                                          array['a5000000-0000-4000-8000-000000000009']::uuid[],
                                          array['a5000000-0000-4000-8000-000000000009']::uuid[]), '-'));
    v_res := pg_temp.ok(v_res, 'K10 a regra do que é crítico: nao_cabe; dentro da data = nada; atraso_longo (7 dias); 1 dia = nada; segundo_atraso; remarcar_confirmado; fixada_pelo_dono (e nada quando ficou impossível)',
      v_txt = 'nao_cabe | - | atraso_longo | - | segundo_atraso | remarcar_confirmado | fixada_pelo_dono | -', v_txt);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── Z. Sombra ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('sombra');
    r := pg_temp.propor('semana', c_hoje, '{}'::jsonb, null, true);
    r2 := public.agenda_aplicar((r ->> 'proposta_id')::uuid, null, 'motor', null, null, c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'Z1 em sombra a proposta é gravada (modo sombra, aberta) com as alocações em estado proposta',
      (select modo = 'sombra' and estado = 'aberta' from public.agenda_propostas where id = (r ->> 'proposta_id')::uuid)
      and (select count(*) from public.agenda_alocacoes where proposta_id = (r ->> 'proposta_id')::uuid and estado = 'proposta') = 16, null);
    v_res := pg_temp.ok(v_res, 'Z2 aplicar em sombra não publica nada, não muda status nem data',
      not (r2 ->> 'ok')::boolean and r2 ->> 'texto' like 'A agenda automática ainda está em teste%'
      and not exists (select 1 from public.agenda_alocacoes where estado in ('publicada', 'fixada'))
      and not exists (select 1 from public.agenda_acoes)
      and (select bool_and(status = 'approved' and scheduled_start_at is null) from public.service_orders
            where id in (pg_temp.os('201'), pg_temp.os('202'), pg_temp.os('203'))), r2 ->> 'texto');
    perform pg_temp.modo('desligado');
    r := pg_temp.propor('semana', c_hoje, '{}'::jsonb, null, true);
    v_res := pg_temp.ok(v_res, 'Z3 desligado: o motor não grava proposta', not (r ->> 'ok')::boolean, r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── Q. A prontidão com o plano ──
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    r := pg_temp.publicar('semana', c_hoje);
    x := public.os_prontidao(pg_temp.os('201'), c_hoje);
    v_res := pg_temp.ok(v_res, 'Q1 o A publicado é "programada", com o plano (próximo dia ter 03, último qua 04, 4 meios)',
      x ->> 'estado' = 'programada' and x ->> 'estado_texto' = 'marcado de ter 03/11 a qua 04/11'
      and x #>> '{plano,proximo_dia}' = '2026-11-03' and x #>> '{plano,ultimo_dia}' = '2026-11-04'
      and x #>> '{plano,meios_vigentes}' = '4' and x #>> '{plano,meios_cumpridos}' = '0', (x -> 'plano')::text);
    x := public.os_prontidao(pg_temp.os('203'), c_hoje);
    v_res := pg_temp.ok(v_res, 'Q2 a reserva não é dia: o C continua sem dia (plano com as reservas)',
      x ->> 'estado' <> 'programada' and x #>> '{plano,proximo_dia}' is null and jsonb_array_length(x #> '{plano,reservas}') = 4,
      (x -> 'plano')::text);
    -- em andamento com dia futuro no plano não é parada; sem dia e sem evidência há 3 dias úteis é
    update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-20 08:00-03' where id = pg_temp.os('201');
    x := public.os_prontidao(pg_temp.os('201'), c_hoje);
    v_txt := x ->> 'estado';
    update public.service_orders set status = 'in_progress', check_in_at = timestamptz '2026-10-20 08:00-03' where id = pg_temp.os('203');
    x := public.os_prontidao(pg_temp.os('203'), c_hoje);
    v_res := pg_temp.ok(v_res, 'Q3 em andamento: com dia no plano é em execução; só com reserva e sem evidência recente é parada',
      v_txt = 'em_execucao' and x ->> 'estado' = 'parada' and x ->> 'ultima_evidencia' = '2026-10-20', v_txt || ' / ' || (x ->> 'estado'));
    -- a evidência: o meio-dia cumprido (de um dia que já passou) conta
    insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, tipo, estado, resultado, publicada_em)
    values (pg_temp.os('203'), c_joao, date '2026-10-28', 'tarde', 'execucao', 'publicada', 'cumprido', now());
    x := public.os_prontidao(pg_temp.os('203'), c_hoje);
    v_res := pg_temp.ok(v_res, 'Q4 o meio-dia cumprido de qua 28/10 é a última evidência: não é mais parada',
      x ->> 'ultima_evidencia' = '2026-10-28' and x ->> 'estado' = 'em_execucao' and x #>> '{plano,meios_cumpridos}' = '1', x::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── X. Determinismo e custo ──
  begin
    perform pg_temp.cenario();
    v_res := pg_temp.ok(v_res, 'X1 cenário: agenda_propor 2× = o mesmo md5',
      md5(pg_temp.propor('semana', c_hoje)::text) = md5(pg_temp.propor('semana', c_hoje)::text), null);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    execute current_setting('agenda_teste.fase2');
    v_t0 := clock_timestamp();
    r := pg_temp.propor('semana', c_hoje);
    v_ms := extract(epoch from clock_timestamp() - v_t0) * 1000;
    v_res := pg_temp.ok(v_res, 'X2 a carteira de 29/10: a semana inteira sai em menos de 2 s na bancada',
      v_ms < 2000, round(v_ms)::text || ' ms');
    v_res := pg_temp.ok(v_res, 'X3 a carteira de 29/10: 2× = o mesmo md5', md5(r::text) = md5(pg_temp.propor('semana', c_hoje)::text), null);
    v_res := pg_temp.ok(v_res, 'X4 a carteira de 29/10: o Giancarlo (motorhome fora até 11/11) não tem compromisso na semana',
      not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'numero' = 'OS-00100' and i ->> 'op' = 'criar'
                    and i ->> 'tipo' <> 'reserva')
      and exists (select 1 from jsonb_array_elements(r -> 'fora') f where f ->> 'numero' = 'OS-00100'), (r -> 'fora')::text);
    v_res := pg_temp.ok(v_res, 'X5 a carteira de 29/10: o Nelson precisa até qui 05/11 e não cabe — vira pergunta, nada dele é publicado',
      pg_temp.item(r, 'OS-00112') is null
      and exists (select 1 from jsonb_array_elements(r -> 'perguntas') q where q ->> 'tipo' = 'nao_cabe'
                    and q ->> 'service_order_id' = pg_temp.os('112')::text), (r -> 'perguntas')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- ── Revisão da Fase 2 ──
  -- R4–R6: o replay da OS-00104 com o padrão do dono e o pedido dele ("marca o Flávio pra terça 06/10"), sem o
  -- compressor: a decisão é dele e fica, mas o aviso vai junto (o incidente que a fase existe para evitar).
  begin
    execute current_setting('agenda_teste.replay_0104');
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, criado_por, criado_em)
    values (c_dono, '{1,2,3,4,5}', null, 'disponivel', 'dono', 'você disse', c_admin, timestamptz '2026-10-01 18:00-03'),
           (c_roberto, '{1,2,3,4,5}', null, 'disponivel', 'dono', 'você disse', c_admin, timestamptz '2026-10-01 18:00-03');
    perform pg_temp.modo('ligado');
    r := public.agenda_propor('os', null, null, array[pg_temp.os('104')],
           jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('104'), 'de', '2026-10-06', 'ate', '2026-10-06'))),
           false, 'dono', c_admin, date '2026-10-02', timestamptz '2026-10-02 10:00-03');
    x := pg_temp.item(r, 'OS-00104');
    v_res := pg_temp.ok(v_res, 'R4 o pedido do dono antes do material (ter 06/10): fica no dia pedido, com o aviso do compressor na frase e no texto',
      x ->> 'de' = '2026-10-06' and (x ->> 'fixar_dono')::boolean
      and x ->> 'aviso_material' = 'falta comprar "Compressor 12V SS65": comprando hoje, chega por volta de ter 06/10 (pronto qua 07/10)'
      and x ->> 'texto' = 'Flávio (OS-00104): ter 06/10, você, Roberto o dia todo — mas falta comprar "Compressor 12V SS65": comprando hoje, chega por volta de ter 06/10 (pronto qua 07/10).'
      and r ->> 'texto' like '%• Flávio (OS-00104): ter 06/10, você, Roberto o dia todo — mas falta comprar "Compressor 12V SS65"%', x::text);
    r := public.agenda_marcar_os(c_admin, pg_temp.os('104'), date '2026-10-06', date '2026-10-06', null, 'tela', 'dono',
                                 date '2026-10-02', timestamptz '2026-10-02 10:00-03');
    v_res := pg_temp.ok(v_res, 'R5 marcar pela tela: marca (fixado pelo dono), e o "Mudei:" e o aviso_material dizem que o compressor não chegou',
      (r ->> 'ok')::boolean
      and r ->> 'texto' = 'Mudei: Flávio (OS-00104): ter 06/10, você, Roberto o dia todo — mas falta comprar "Compressor 12V SS65": comprando hoje, chega por volta de ter 06/10 (pronto qua 07/10).'
      and r ->> 'aviso_material' like 'falta comprar "Compressor 12V SS65"%'
      and (select count(*) filter (where estado = 'fixada' and fixado_por = 'dono' and dia = date '2026-10-06') = 4 and count(*) = 4
             from public.agenda_alocacoes where service_order_id = pg_temp.os('104') and estado in ('publicada', 'fixada')),
      r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    r := public.agenda_marcar_os(c_admin, pg_temp.os('201'), date '2026-11-05', null, null, 'tela', 'dono', c_hoje, c_agora);
    v_res := pg_temp.ok(v_res, 'R6 com o material na mão (o A na qui 05), nada de aviso: o texto fica como era',
      (r ->> 'ok')::boolean and r ->> 'aviso_material' is null and r ->> 'texto' not like '%— mas%', r ->> 'texto');
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- G1–G2: a espera que o dono pôs ("deixa parada até sexta") só tira os dias dentro dela.
  begin
    perform pg_temp.cenario();
    perform pg_temp.modo('ligado');
    r := pg_temp.publicar('semana', c_hoje);
    update public.os_planejamento set congelada_ate = date '2026-10-30', revisar_em = date '2026-10-30'
     where service_order_id = pg_temp.os('201');
    r := pg_temp.propor('os', c_hoje, '{}'::jsonb, array[pg_temp.os('201')]);
    v_res := pg_temp.ok(v_res, 'G1 em espera até sex 30/10 (antes dos dias do A, ter 03 e qua 04/11): nada sai',
      not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'numero' = 'OS-00201' and i ->> 'op' = 'cancelar')
      and pg_temp.vigentes(pg_temp.os('201')) like '03/11 manha Gustavo abertura%', (r -> 'itens')::text);
    update public.os_planejamento set congelada_ate = date '2026-11-03', revisar_em = date '2026-11-03'
     where service_order_id = pg_temp.os('201');
    r := pg_temp.propor('os', c_hoje, '{}'::jsonb, array[pg_temp.os('201')]);
    x := (select i from jsonb_array_elements(r -> 'itens') i
           where i ->> 'numero' = 'OS-00201' and i ->> 'op' = 'cancelar' and i ->> 'motivo' = 'espera');
    v_res := pg_temp.ok(v_res, 'G2 em espera até ter 03/11: sai só a ter 03 ("você pôs em espera até ter 03/11"), nunca "saiu da carteira"',
      x is not null
      and (select array_agg(distinct a ->> 'dia') from jsonb_array_elements(x -> 'alocacoes') a) = array['2026-11-03']
      and x ->> 'texto' = 'Antônio (OS-00201): sai ter 03/11 — você pôs em espera até ter 03/11.'
      and not exists (select 1 from jsonb_array_elements(r -> 'itens') i where i ->> 'motivo' = 'os_saiu'), (r -> 'itens')::text);
    v_res := pg_temp.ok(v_res, 'G3 a qua 04/11, depois da espera, fica marcada: nada dela é replanejado (o que faltar o motor completa depois)',
      not exists (select 1 from jsonb_array_elements(r -> 'itens') i, jsonb_array_elements(i -> 'alocacoes') a
                   where i ->> 'numero' = 'OS-00201' and i ->> 'op' = 'cancelar' and a ->> 'dia' = '2026-11-04'), (r -> 'itens')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  -- W1–W2: o sábado combinado ("o Roberto e eu vimos sábado") a agenda automática não marca, e não sobe o teto.
  begin
    perform pg_temp.cenario();
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, criado_por, criado_em) values
      (c_roberto, '[2026-11-07,2026-11-08)', null, 'confirmada', 'dono', 'sábado combinado', c_admin, c_agora),
      (c_dono, '[2026-11-07,2026-11-08)', null, 'confirmada', 'dono', 'sábado combinado', c_admin, c_agora);
    r := pg_temp.propor('semana', c_hoje);
    x := (select s from jsonb_array_elements(r -> 'carga' -> c_roberto::text -> 'semanas') s where s ->> 'semana' = '2026-11-02');
    v_res := pg_temp.ok(v_res, 'W1 o sábado combinado não entra no esperado da semana: o teto do Roberto continua 6 de 8 (80% dos dias úteis)',
      (x ->> 'esperado')::numeric = 8 and (x ->> 'teto80')::int = 6, x::text);
    r := pg_temp.propor('os', c_hoje,
           jsonb_build_object('fixar', jsonb_build_array(jsonb_build_object('os', pg_temp.os('201'), 'de', '2026-11-07', 'ate', '2026-11-07'))),
           array[pg_temp.os('201')]);
    v_res := pg_temp.ok(v_res, 'W2 "marca o Antônio pra sábado": recusa dizendo que a agenda automática não marca sábado (combine direto)',
      exists (select 1 from jsonb_array_elements(r -> 'fora') f
               where f ->> 'texto' = 'Antônio (OS-00201): não cabe sáb 07/11: a agenda automática não marca sábado (sábado é só combinando direto com a equipe).'),
      (r -> 'fora')::text);
    raise exception 'desfaz' using errcode = 'P0099';
  exception when sqlstate 'P0099' then null;
  end;

  perform pg_temp.gravar(v_res);
end
$motor$;

-- ── Q5. A cópia de os_prontidao: fora dos pontos "-- FASE 2:", igual ao corpo da Fase 1 (160400) ──────
do $copia$
declare
  v_mig   text := current_setting('agenda_teste.mig_prontidao_fase1', true);
  v_ini   int;
  v_corpo text;
  v_novo  text := (select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname = 'os_prontidao');
  v_a     text[] := '{}';
  v_b     text[] := '{}';
  v_bloco boolean := false;
  l       text;
  v_tirada int := 0;
  -- FASE 4: os_prontidao foi recriada de novo em 20261027100100 (o prazo do fornecedor), com oito blocos
  -- "-- FASE 4: … -- FASE 4: fim"; as linhas da Fase 1 que eles trocaram (cada uma uma vez) saem do corpo antigo, e os
  -- blocos saem do novo (o mesmo do B7 de agenda_fase4_base.sql).
  v_trocadas_f4 text[] := array[
    '    select q.*, public._agenda_classe_do_fornecedor(q.forn_id) as classe',
    '    select q.*, public._agenda_prazo_da_classe(q.classe) as prazo',
    $l$             when q.prazo is not null then 'D'$l$,
    $l$             when q.sit in ('comprado', 'a_caminho') and q.prazo is not null then$l$,
    '               public.agenda_somar_du(coalesce(q.comprado_em, p_hoje), q.prazo)',
    $l$             when q.sit = 'falta' and q.prazo is not null then$l$,
    '               -- "Se comprar hoje" (ou no dia combinado): calculado, nunca gravado.',
    '               public.agenda_somar_du(greatest(coalesce(q.compra_prevista_em, p_hoje), p_hoje), q.prazo)',
    $l$           case when q.sit = 'falta' and q.prazo is not null and q.compra_prevista_em is null then$l$,
    '             public.agenda_somar_du(v_est_sm, -(c.folga_material_du + q.prazo)) end as compre_ate,',
    $l$                            public._dia_curto(public.agenda_somar_du(p_hoje, (v_compra ->> 'prazo_du')::int)))$l$];
  v_achadas_f4 text[] := '{}';
  -- FASE 4: fim
begin
  if coalesce(v_mig, '') = '' then
    insert into _resultado values ('Q5 a cópia de os_prontidao só muda nos pontos "-- FASE 2:"', true,
      'PULADO: sem agenda_teste.mig_prontidao_fase1 (rode pela bancada)');
    return;
  end if;
  v_mig := replace(v_mig, E'\r\n', E'\n');
  v_ini := position('create or replace function public.os_prontidao(' in v_mig);
  v_corpo := substr(v_mig, v_ini);
  v_corpo := substr(v_corpo, position(E'as $function$\n' in v_corpo) + length(E'as $function$'));
  v_corpo := left(v_corpo, position(E'\n$function$;' in v_corpo));
  -- o da Fase 1, sem a linha que o ponto 4 trocou
  foreach l in array string_to_array(v_corpo, E'\n') loop
    if l = '  return jsonb_build_object(' and v_tirada = 0 then
      v_tirada := 1;
      continue;
    end if;
    -- FASE 4: e sem as linhas que a Fase 4 trocou (cada uma uma vez)
    if l = any (v_trocadas_f4) and not (l = any (v_achadas_f4)) then
      v_achadas_f4 := v_achadas_f4 || l;
      continue;
    end if;
    -- FASE 4: fim
    v_a := v_a || l;
  end loop;
  -- o de agora, sem os blocos "-- FASE 2: … -- FASE 2: fim" (FASE 4: e sem os "-- FASE 4: … -- FASE 4: fim")
  foreach l in array string_to_array(v_novo, E'\n') loop
    if not v_bloco and l ~ '^\s*-- FASE [24]:' and l !~ '^\s*-- FASE [24]: fim' then
      v_bloco := true;
      continue;
    end if;
    if v_bloco then
      if l ~ '^\s*-- FASE [24]: fim' then v_bloco := false; end if;
      continue;
    end if;
    v_b := v_b || l;
  end loop;
  insert into _resultado values ('Q5 a cópia de os_prontidao só muda nos pontos "-- FASE 2:" e "-- FASE 4:" (fora deles, linha a linha igual à da Fase 1)',
    v_a = v_b and v_tirada = 1 and (select count(*) from regexp_matches(v_novo, '-- FASE 2: fim', 'g')) = 5
    and cardinality(v_achadas_f4) = cardinality(v_trocadas_f4)
    and (select count(*) from regexp_matches(v_novo, '-- FASE 4: fim', 'g')) = 8,
    format('linhas Fase 1 %s, cópia sem os blocos %s; 1ª diferente: %s', cardinality(v_a), cardinality(v_b),
           (select coalesce(min(i)::text, '-') from generate_series(1, greatest(cardinality(v_a), cardinality(v_b))) i
             where v_a[i] is distinct from v_b[i])));
end
$copia$;

-- ── T. O feriado no meio dos dias (revisão da Fase 2; sem fixture) ──────────────────────────────────────
insert into _resultado
select 'T1 os dias em texto dizem o feriado de semana no meio: "seg 14 a qui 17/06 (ter 15 é aniversário de Itajaí)", "sex 30/10 e ter 03/11 (seg 02 é Finados)"; o fim de semana e o dia que não é seguido, nada',
       string_agg(t, ' | ' order by o) = 'seg 14 a qui 17/06 (ter 15 é aniversário de Itajaí) | sex 30/10 e ter 03/11 (seg 02 é Finados)'
                                          || ' | sex 06 e seg 09/11 | ter 03 e qui 05/11 | ter 03 a qui 05/11',
       string_agg(t, ' | ' order by o)
  from (values (1, public._agenda_dias_texto(array[date '2027-06-14', date '2027-06-16', date '2027-06-17'])),
               (2, public._agenda_dias_texto(array[date '2026-10-30', date '2026-11-03'])),
               (3, public._agenda_dias_texto(array[date '2026-11-06', date '2026-11-09'])),
               (4, public._agenda_dias_texto(array[date '2026-11-03', date '2026-11-05'])),
               (5, public._agenda_dias_texto(array[date '2026-11-03', date '2026-11-04', date '2026-11-05']))) v(o, t);

-- ── J. Portas ───────────────────────────────────────────────────────────────────────────────────────────
with f(assinatura, leitura) as (values
  ('public.agenda_meios_da_os(uuid, date)', true),
  ('public.agenda_grade(date, date, date, uuid[])', true),
  ('public._agenda_classe_da_os(jsonb, jsonb, date, boolean, boolean)', true),
  ('public._agenda_criticidade(uuid, date, date, date, date, date, uuid[], uuid[])', true),
  ('public.agenda_validar(uuid, uuid[], date, timestamptz, uuid)', true),
  ('public.agenda_acao_desfazivel(text, date, timestamptz)', true),
  ('public.agenda_os_do_dia(uuid, date)', true),
  ('public._agenda_plano_da_os(uuid, date)', true),
  ('public._agenda_ultima_evidencia(uuid, date)', true),
  ('public.os_prontidao(uuid, date)', true),
  ('public.agenda_marcar_os(uuid, uuid, date, date, uuid, text, text, date, timestamptz)', true),
  ('public.agenda_propor(text, date, date, uuid[], jsonb, boolean, text, uuid, date, timestamptz)', false),
  ('public.agenda_aplicar(uuid, uuid[], text, uuid, uuid, date, timestamptz)', false),
  ('public.agenda_descartar(uuid, uuid, text)', false),
  ('public.agenda_desfazer(uuid, uuid, text, date, timestamptz)', false),
  ('public.agenda_decidir(uuid, smallint, uuid, text, text, date, timestamptz)', false),
  ('public._agenda_contexto(date, date, date, uuid[], uuid[])', false),
  ('public._agenda_encaixar(jsonb, jsonb, jsonb)', false),
  ('public._agenda_violacoes(uuid[], uuid[], boolean, jsonb, date, date)', false))
insert into _resultado
select 'J1 anon sem nada; o motor que grava só service_role; marcar e as leituras também authenticated',
       bool_and(not has_function_privilege('anon', f.assinatura, 'execute')
                and has_function_privilege('authenticated', f.assinatura, 'execute') = f.leitura
                and has_function_privilege('service_role', f.assinatura, 'execute')),
       string_agg(f.assinatura, ', ') filter (where has_function_privilege('anon', f.assinatura, 'execute')
                                              or has_function_privilege('authenticated', f.assinatura, 'execute') <> f.leitura
                                              or not has_function_privilege('service_role', f.assinatura, 'execute'))
  from f;

insert into _resultado
select 'J2 nenhuma função nova do motor executável por anon',
       not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname ~ '^_?agenda_' and has_function_privilege('anon', p.oid, 'execute')),
       (select string_agg(p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname ~ '^_?agenda_' and has_function_privilege('anon', p.oid, 'execute'));

select teste, ok, detalhe from _resultado order by teste;

rollback;
