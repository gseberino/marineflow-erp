-- Fixture da Fase 7b da Agenda de Produção: a equipe de verdade de 30/10 e as pessoas que a etapa precisa, SINTÉTICO, por cima da
-- carteira real de 29/10 (fixture-replay-2910.sql) e da sintética da 7a (fixture-fase7a.sql) (spec-fase7b §8.2 e §R4.8). Roda dentro
-- do begin/rollback do teste (o rodar.mjs passa este arquivo em agenda_teste.fase7b, o da 7a em agenda_teste.fase7a e o replay em
-- agenda_teste.replay2910); o que ainda não foi carregado nesta transação é carregado antes. Pode rodar de novo na mesma transação
-- (cada parte confere se já está lá). NUNCA rodar em produção.
-- Só primeiros nomes; telefones fictícios (5547900000011…); ids novos com o prefixo f7b00000 e a OS 97101 (livre).
--
-- Hoje é qui 05/11/2026 16:45 (a fixture não usa now(): todo teste passa p_hoje/p_agora). O que cada peça é (P1, 31/10):
--   O 30/10 (o "replay de 30/10" do R4.8): o que mudou em produção entre o corte do replay (qui 29/10 16:52) e 30/10 09:00, com os
--   instantes e os textos do export de 30/10 04:04 (sql/wf7a_p1_02_replay.out.json, o mesmo que o gerador com o corte
--   2026-10-30T09:00:00-03:00 daria, sem reabrir a material_conferir, que o gerador reabre por não saber quando ela fechou):
--     · 30/10 00:11 a correção da equipe: a semente do Roberto e do João trocada (substituida_em), o contato do Roberto parado
--       ("saiu da equipe (o dono, 29/10)"), o Alex declarado pelo dono — seg a sex, turno nulo, "você disse em 29/10" — e na lista
--       da rotina (incluido_por dono); o Alex continua sem telefone e sem work_profiles. Mickael: perfil vigente, telefone, nenhuma
--       linha (nunca teve). João: perfil vigente, sem telefone, sem contato;
--     · 30/10 00:15 a vigia soltou as 12 reservas do Lenine (cancelada_motivo pessoa) e resolveu a material_conferir dele ("a reserva
--       saiu: o lugar que eu tinha guardado não existe mais");
--     · 30/10 00:15 a pergunta padrao_do_dono:sem_dias do lote (a vigia, _agenda_vigia_padrao_do_dono, com a equipe de 30/10),
--       ligada e vista 1 vez (o aviso do gestor de 30/10 09:30), aberta — como em produção em 31/10.
--   As pessoas (R4.8):
--     · Mateus — prestador, ativo, com telefone, SEM work_profiles, sem linha de disponibilidade, sem contato (quem vem sob demanda:
--       a fala "Mateus vem qua e qui" o põe). O "Mateus" de produção que é FORNECEDOR fica onde está (suppliers, no replay);
--     · Vinicius — sem payee (nada);
--     · Rafael — diarista, telefone, perfil de diária vigente desde 01/09, padrão dito por ele de seg a sex (origem diarista, 29/10),
--       na lista da rotina (regra): o único que recebe a pergunta da semana nos testes;
--     · Bruno — o novato: diarista, telefone, perfil desde 20/10 e 3 diárias (21, 22 e 27/10), uma data dita pelo dono (ter 10/11, o
--       dia todo), fora da rotina (o candidato ao "contato");
--     · com agenda_teste.fase7b_equipe = 'real' antes de carregar, Mateus, Rafael e Bruno ficam de fora (a equipe de produção:
--       só o Alex e o dono — "só o Alex na equipe", R4.9-1, M3a);
--     · o dono — sem linha (o de produção); com agenda_teste.fase7b_dono = 'campo' antes de carregar: a linha seg–sex de origem dono,
--       turno nulo, disponível, SEM frequencia (o CHECK frequencia_so_historico), criada sáb 31/10 10:00, e a pergunta
--       padrao_do_dono:sem_dias resolvida ("você disse os dias").
--   As OS: as reais do replay (as linhas da wf7b_08: Lenine OS-00074, Vanderlei OS-00069, Nelson OS-00112, Giancarlo OS-00130,
--     Kalmar OS-00032/00033, Flávio OS-00104, Rodrigo OS-00096, os orçamentos grandes); mais:
--     · Vanderlei (OS-00069): precisa_ate qua 18/11 (o prazo firme do sábado e do ajudante, R4.4 "prazo");
--     · OS-97101 Otávio: "Revisão do quadro na casa de máquinas" (R$ 764 = 1 diária) — a nota de espaço confinado (dupla_notas). É o
--       "Paulo" da §8.2: o nome Paulo já é da OS-97001 da fixture da 7a.

do $f7b$
declare
  c_pes      constant text := 'f7b00000-0000-4000-8000-0000000003';   -- + 2 dígitos: as pessoas
  c_perfil   constant text := 'f7b00000-0000-4000-8000-0000000004';   -- + 2 dígitos: os perfis de diária
  c_os       constant text := 'f7b00000-0000-4000-8000-000000097';    -- + 3 dígitos: as OS (o número da OS no fim)
  c_troca    constant timestamptz := timestamptz '2026-10-30 00:11:02.381928-03';  -- a correção da equipe em produção
  c_vigia    constant timestamptz := timestamptz '2026-10-30 00:15:04.658491-03';  -- a vigia que soltou a reserva
  v_dono_u   uuid;
  v_dono     uuid;
  v_alex     uuid;
  v_lenine   uuid;
  v_r        jsonb;
begin
  -- ── 0. A base: o replay de 29/10 e a sintética da 7a ─────────────────────────────────────────────────────────
  if not exists (select 1 from public.service_orders where service_order_number = 'OS-97001') then
    if coalesce(current_setting('agenda_teste.fase7a', true), '') = '' then
      raise exception 'fixture-fase7b: falta a fixture da 7a (agenda_teste.fase7a; rode pela bancada)';
    end if;
    execute current_setting('agenda_teste.fase7a');
  end if;

  select id into strict v_dono_u from public.app_users where role = 'admin' and active order by id limit 1;
  v_dono := public._agenda_dono(null);
  select id into strict v_alex from public.payees where name = 'Alex' and active;
  select so.id into strict v_lenine from public.service_orders so where so.service_order_number = 'OS-00074';

  -- ── 1. O 30/10: a correção da equipe (00:11) ───────────────────────────────────────────────────────────────
  if not exists (select 1 from public.agenda_disponibilidade d where d.payee_id = v_alex and d.substituida_em is null) then
    update public.agenda_disponibilidade set substituida_em = c_troca
     where substituida_em is null and payee_id in (select id from public.payees where name in ('Roberto', 'João', 'Mickael'));
    update public.agenda_equipe_contato set recebe_rotina = false, parou_em = c_troca, parou_motivo = 'saiu da equipe (o dono, 29/10)'
     where parou_em is null and payee_id in (select id from public.payees where name in ('Roberto', 'João', 'Mickael'));
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, criado_em)
    values (v_alex, '{1,2,3,4,5}', null, 'disponivel', 'dono', 'você disse em 29/10', c_troca);
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    values (v_alex, true, 'dono', c_troca)
    on conflict (payee_id) do update set recebe_rotina = true, parou_em = null, parou_motivo = null;

    -- ── 2. O 30/10: a vigia das 00:15 soltou a reserva do Lenine e resolveu a pergunta dela ─────────────────────
    update public.agenda_alocacoes
       set estado = 'cancelada', cancelada_em = c_vigia, cancelada_motivo = 'pessoa', atualizado_em = c_vigia
     where service_order_id = v_lenine and tipo = 'reserva' and estado = 'publicada';
    update public.agenda_perguntas
       set estado = 'resolvida', resolvida_motivo = 'a reserva saiu: o lugar que eu tinha guardado não existe mais'
     where chave = 'material_conferir:' || v_lenine and estado = 'aberta';

    -- ── 3. O 30/10: a pergunta dos dias do dono (a do lote), aberta e vista 1 vez ───────────────────────────────
    v_r := public._agenda_vigia_padrao_do_dono(date '2026-10-30', c_vigia);
    if not coalesce((v_r ->> 'criada')::boolean, false) then
      raise exception 'fixture-fase7b: a pergunta padrao_do_dono:sem_dias não nasceu (%)', v_r;
    end if;
    update public.agenda_perguntas
       set mostrada_vezes = 1, mostrada_em = timestamptz '2026-10-30 09:30-03', mostrada_via = 'aviso'
     where chave = 'padrao_do_dono:sem_dias' and estado = 'aberta';
  end if;

  -- ── 4. As pessoas da 7b (fora com agenda_teste.fase7b_equipe = 'real': a equipe de produção, só o Alex e o dono) ────────
  if coalesce(current_setting('agenda_teste.fase7b_equipe', true), '') <> 'real'
     and not exists (select 1 from public.payees where id = (c_pes || '01')::uuid) then
    insert into public.payees (id, name, kind, active, phone, created_at, updated_at) values
      ((c_pes || '01')::uuid, 'Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-02 10:00-03', timestamptz '2026-11-02 10:00-03'),
      ((c_pes || '02')::uuid, 'Rafael', 'diarista',  true, '5547900000012', timestamptz '2026-09-01 10:00-03', timestamptz '2026-09-01 10:00-03'),
      ((c_pes || '03')::uuid, 'Bruno',  'diarista',  true, '5547900000013', timestamptz '2026-10-20 10:00-03', timestamptz '2026-10-20 10:00-03');

    -- os perfis de diária (do pagamento: Rafael desde 01/09, Bruno desde 20/10; Mateus nenhum)
    insert into public.work_profiles (id, payee_id, tipo_vinculo, modo_pagamento, valor_diaria, jornada_diaria_horas,
                                      meia_diaria_ate_horas, vigencia_inicio, vigencia_fim, created_at, updated_at) values
      ((c_perfil || '02')::uuid, (c_pes || '02')::uuid, 'diarista', 'diaria', 200, 8, 4, date '2026-09-01', null,
       timestamptz '2026-09-01 10:00-03', timestamptz '2026-09-01 10:00-03'),
      ((c_perfil || '03')::uuid, (c_pes || '03')::uuid, 'diarista', 'diaria', 200, 8, 4, date '2026-10-20', null,
       timestamptz '2026-10-20 10:00-03', timestamptz '2026-10-20 10:00-03');

    -- as 3 diárias do Bruno (o novato: perfil há menos de 30 dias e menos de 10 diárias)
    insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status, registrado_por,
                                    aprovado_por, aprovado_em)
    select md5('f7b:diaria:bruno:' || d)::uuid, (c_perfil || '03')::uuid, d, 'diaria', 1, 200, 'painel', 'aprovado', v_dono_u,
           v_dono_u, (d + time '20:00') at time zone 'America/Sao_Paulo'
      from unnest(array[date '2026-10-21', date '2026-10-22', date '2026-10-27']) d;

    -- Rafael: o padrão que ele disse (seg a sex) e na lista da rotina
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_em)
    values ((c_pes || '02')::uuid, '{1,2,3,4,5}', null, 'disponivel', 'diarista', 'Disse em 29/10', 'seg a sex',
            timestamptz '2026-10-29 17:10-03');
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    values ((c_pes || '02')::uuid, true, 'regra', timestamptz '2026-09-02 10:00-03');

    -- Bruno: uma data dita pelo dono (ter 10/11, o dia todo), sem padrão e fora da rotina
    insert into public.agenda_disponibilidade (payee_id, periodo, turno, situacao, origem, nota, trecho, criado_em, criado_por)
    values ((c_pes || '03')::uuid, daterange(date '2026-11-10', date '2026-11-10', '[]'), null, 'disponivel', 'dono',
            'Você disse que vem', 'o Bruno vem terça dia 10', timestamptz '2026-11-03 10:00-03', v_dono_u);
  end if;

  -- ── 5. As OS: o prazo do Vanderlei e a nota de espaço confinado ─────────────────────────────────────────────────
  if not exists (select 1 from public.service_orders where id = (c_os || '101')::uuid) then
    insert into public.os_planejamento (service_order_id, precisa_ate, atualizado_por)
    select so.id, date '2026-11-18', v_dono_u from public.service_orders so where so.service_order_number = 'OS-00069'
    on conflict (service_order_id) do update set precisa_ate = excluded.precisa_ate;

    insert into public.clients (id, type, name) values ('f7b00000-0000-4000-8000-000000000101', 'individual', 'Otávio');
    insert into public.vessels (id, client_id, name, asset_type)
    values ('f7b00000-0000-4000-8000-000000000201', 'f7b00000-0000-4000-8000-000000000101', 'Lancha', 'Lancha');
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at)
    values ((c_os || '101')::uuid, 'OS-97101', 'f7b00000-0000-4000-8000-000000000101', 'f7b00000-0000-4000-8000-000000000201',
            'open', 'approved', 'repair', timestamptz '2026-10-27 10:00-03', timestamptz '2026-10-30 10:00-03',
            timestamptz '2026-10-30 10:00-03');
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                               unit_price_snapshot, line_total, created_at)
    values (md5('f7b:servico:97101:1')::uuid, (c_os || '101')::uuid, null, 'Revisão do quadro na casa de máquinas', 'unit', 1,
            764, 764, timestamptz '2026-10-27 10:00-03');
  end if;

  -- ── 6. Só com agenda_teste.fase7b_dono = 'campo': a linha do dono (seg a sex) e a pergunta do lote resolvida ────────
  if coalesce(current_setting('agenda_teste.fase7b_dono', true), '') = 'campo'
     and not exists (select 1 from public.agenda_disponibilidade d
                      where d.payee_id = v_dono and d.substituida_em is null and d.dias_semana is not null) then
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_em, criado_por)
    values (v_dono, '{1,2,3,4,5}', null, 'disponivel', 'dono', 'Você disse que fica em campo', 'fico em campo de segunda a sexta',
            timestamptz '2026-10-31 10:00-03', v_dono_u);
    update public.agenda_perguntas set estado = 'resolvida', resolvida_motivo = 'você disse os dias'
     where chave = 'padrao_do_dono:sem_dias' and estado = 'aberta';
  end if;
end
$f7b$;
