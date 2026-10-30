-- Fixture da Fase 7a da Agenda de Produção: o que a carteira real de 29/10 (fixture-replay-2910.sql) não tem, SINTÉTICO, por cima
-- dela (spec-fase7a §8.2). Roda dentro do begin/rollback do teste (o rodar.mjs passa este arquivo em agenda_teste.fase7a e o replay
-- em agenda_teste.replay2910); se o replay ainda não foi carregado nesta transação, carrega antes. NUNCA rodar em produção.
-- Só primeiros nomes; nenhum telefone, documento ou e-mail; ids novos com o prefixo f7a00000 e as OS 97001 a 97008 (livres).
--
-- Hoje é qui 29/10/2026 16:52 (o padrão do replay); todo teste passa p_hoje/p_agora. A equipe é a do replay (Roberto e João pela
-- semente; o dono sem linha). O que cada peça é (P1, 30/10):
--   OS-97001 Paulo   em andamento, check-in seg 26/10, 1 linha de R$ 1.528 (2 diárias); a diária do Roberto de ter 27/10 ligada
--                    à OS (o rastro: a OS começou de verdade — o "quanto falta?" do gestor conta 1 dia)
--   OS-97002 Sérgio  aberta, banco de baterias de lítio (R$ 3.056 = 4 diárias), o dono disse *Sérgio com dupla*
--                    (os_planejamento.dupla_dita = 'todos'); 4 baterias que estavam NA MÃO (o item que volta a faltar: defeito)
--   OS-97003 Tânia   aberta, "Deslocamento técnico" por hora (2 h, R$ 400) + revisão do quadro 12 V (R$ 764): a mão de obra
--                    limpa tira o deslocamento
--   OS-97004 Úrsula  aberta, 2 dias ditos pelo dono; o cliente ouviu o dia: prometido FIRME de seg 09/11 a ter 10/11
--   OS-97005 Vera    aberta, painel solar (R$ 1.528); o sinal combinado (R$ 1.000) e NÃO pago (AG7-09: marco e cobro)
--   OS-97006 Wagner, OS-97007 Xavier e OS-97008 Yara — meio dia cada (o dono disse), publicadas com o João: ter 03/11 manhã,
--                    ter 03/11 tarde e qua 04/11 manhã (3 OS com o mesmo diarista: a onda quando ele faltar)
--   A ficha LIGADA do João de ter 03/11 enfileirada (o dia já avisado à equipe).
--   Só com agenda_teste.fase7a_sabado = 'on': o Roberto com o padrão de sábado de manhã (o cenário do sábado, P12).
-- O "orçamento enviado de R$ 34.480" da spec é o real: ORÇ-00126 (MP, enviado, mexido em 20/10) já vem no replay — não se repete.

do $f7a$
declare
  c_cli   constant text := 'f7a00000-0000-4000-8000-0000000001';   -- + 2 dígitos: os clientes
  c_bem   constant text := 'f7a00000-0000-4000-8000-0000000002';   -- os bens
  c_os    constant text := 'f7a00000-0000-4000-8000-000000097';    -- + 3 dígitos: as OS (o número da OS no fim)
  v_joao    uuid;
  v_roberto uuid;
  v_perfil  uuid;
  v_dono_u  uuid;
  v_ws      uuid;
  v_os      uuid;
  r         record;
begin
  if not exists (select 1 from public.service_orders where service_order_number = 'OS-00130') then
    if coalesce(current_setting('agenda_teste.replay2910', true), '') = '' then
      raise exception 'fixture-fase7a: falta o replay de 29/10 (agenda_teste.replay2910; rode pela bancada)';
    end if;
    execute current_setting('agenda_teste.replay2910');
  end if;

  select id into strict v_joao from public.payees where name = 'João' and active;
  select id into strict v_roberto from public.payees where name = 'Roberto' and active;
  select id into strict v_perfil from public.work_profiles where payee_id = v_roberto and vigencia_fim is null limit 1;
  select id into strict v_dono_u from public.app_users where role = 'admin' and active limit 1;

  -- ── Os clientes, os bens e as OS ──────────────────────────────────────────────────────────────────────────
  for r in
    select * from (values
      ('01', 'Paulo',  'in_progress', '2026-10-20 10:00-03', '2026-10-26 08:10-03'),
      ('02', 'Sérgio', 'open',        '2026-10-27 10:00-03', null),
      ('03', 'Tânia',  'open',        '2026-10-27 11:00-03', null),
      ('04', 'Úrsula', 'open',        '2026-10-22 10:00-03', null),
      ('05', 'Vera',   'open',        '2026-10-28 10:00-03', null),
      ('06', 'Wagner', 'open',        '2026-10-26 10:00-03', null),
      ('07', 'Xavier', 'open',        '2026-10-26 11:00-03', null),
      ('08', 'Yara',   'open',        '2026-10-26 12:00-03', null)
    ) as t(n, nome, status, convertida, check_in)
  loop
    insert into public.clients (id, type, name) values ((c_cli || r.n)::uuid, 'individual', r.nome);
    insert into public.vessels (id, client_id, name, asset_type)
    values ((c_bem || r.n)::uuid, (c_cli || r.n)::uuid, 'Motorhome', 'Motorhome');
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at, check_in_at)
    values ((c_os || '0' || r.n)::uuid, 'OS-970' || r.n, (c_cli || r.n)::uuid, (c_bem || r.n)::uuid, r.status, 'approved', 'repair',
            r.convertida::timestamptz - interval '3 days', r.convertida::timestamptz, r.convertida::timestamptz,
            r.check_in::timestamptz);
  end loop;

  -- As linhas de serviço (mão de obra = diárias × R$ 764).
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at)
  select md5('f7a:servico:' || l.os || ':' || l.n)::uuid, (c_os || '0' || l.os)::uuid, null, l.nome, l.unidade, l.qtd, l.preco,
         l.qtd * l.preco, timestamptz '2026-10-20 10:00-03' + make_interval(secs => l.n)
    from (values
      ('01', 1, 'Instalação de inversor e carregador', 'unit', 1, 1528),
      ('02', 1, 'Instalação de banco de baterias de lítio', 'unit', 1, 3056),
      ('03', 1, 'Deslocamento técnico', 'hour', 2, 200),
      ('03', 2, 'Revisão do quadro 12 V', 'unit', 1, 764),
      ('04', 1, 'Reparo do sistema elétrico', 'unit', 1, 3056),
      ('05', 1, 'Instalação de painel solar 200 W', 'unit', 1, 1528),
      ('06', 1, 'Troca de tomada USB', 'unit', 1, 382),
      ('07', 1, 'Troca de disjuntor', 'unit', 1, 382),
      ('08', 1, 'Ajuste de iluminação', 'unit', 1, 382)
    ) as l(os, n, nome, unidade, qtd, preco);

  -- ── OS-97001: a diária do Roberto de ter 27/10 ligada à OS (a que já existe nesse dia, senão uma nova) ─────────────
  select id into v_ws from public.work_shifts where work_profile_id = v_perfil and data = date '2026-10-27';
  if v_ws is null then
    v_ws := md5('f7a:diaria:roberto:2026-10-27')::uuid;
    insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status, registrado_por,
                                    aprovado_por, aprovado_em)
    values (v_ws, v_perfil, date '2026-10-27', 'diaria', 1, 200, 'painel', 'aprovado', v_dono_u, v_dono_u,
            timestamptz '2026-10-27 20:00-03');
  end if;
  insert into public.work_shift_os (shift_id, service_order_id) values (v_ws, (c_os || '001')::uuid) on conflict do nothing;

  -- ── OS-97002: o dono disse *Sérgio com dupla*; as 4 baterias estavam na mão ───────────────────────────────────
  insert into public.os_planejamento (service_order_id, dupla_dita, dupla_motivo, dupla_em, atualizado_por)
  values ((c_os || '002')::uuid, 'todos', 'você disse: Sérgio com dupla', timestamptz '2026-10-28 09:00-03', v_dono_u);
  insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico,
                                  situacao, fonte, chegou_em, conferido_em, atualizado_por)
  values (md5('f7a:material:97002:baterias')::uuid, (c_os || '002')::uuid, 'dono', 'Bateria de lítio 12 V 100 Ah', 4, 4, true,
          'na_mao', 'dono', date '2026-10-28', timestamptz '2026-10-28 09:00-03', v_dono_u);

  -- ── OS-97004: 2 dias ditos e o prometido firme de seg 09/11 a ter 10/11 ───────────────────────────────────────
  insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, prometido_tipo, prometido_de,
                                      prometido_ate, prometido_original_ate, prometido_em, prometido_fonte, atualizado_por)
  values ((c_os || '004')::uuid, 2, 'dono', timestamptz '2026-10-22 10:00-03', 'firme', date '2026-11-09', date '2026-11-10',
          date '2026-11-10', timestamptz '2026-10-23 10:00-03', 'dono', v_dono_u);

  -- ── OS-97005: o sinal combinado e não pago ───────────────────────────────────────────────────────────────────
  insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status,
                                  paid_amount, balance_amount, is_deposit)
  values (md5('f7a:sinal:97005')::uuid, (c_cli || '05')::uuid, (c_os || '005')::uuid, 'Sinal OS-97005', date '2026-10-28',
          date '2026-10-30', 1000, 'pending', 0, 1000, true);

  -- ── OS-97006/7/8: meio dia cada, publicadas com o João (ter 03/11 manhã e tarde, qua 04/11 manhã) ────────────────
  for r in
    select * from (values ('006', date '2026-11-03', 'manha'), ('007', date '2026-11-03', 'tarde'),
                          ('008', date '2026-11-04', 'manha')) as t(os, dia, turno)
  loop
    v_os := (c_os || r.os)::uuid;
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_por)
    values (v_os, 0.5, 'dono', timestamptz '2026-10-26 10:00-03', v_dono_u);
    insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
    values (md5('f7a:aloc:' || r.os)::uuid, v_os, v_joao, r.dia, r.turno, 'turno', 'execucao', 'publicada', 'motor',
            timestamptz '2026-10-29 16:30-03');
  end loop;

  -- ── A ficha ligada do João de ter 03/11, enfileirada (o dia já avisado à equipe) ──────────────────────────────
  insert into public.agenda_equipe_mensagens (id, payee_id, dia, tipo, modo, texto, enviar_em, estado, dedupe_key)
  values (md5('f7a:ficha:joao:2026-11-03')::uuid, v_joao, date '2026-11-03', 'ficha', 'ligado',
          'Amanhã (ter 03/11): Wagner de manhã, Xavier à tarde.', timestamptz '2026-11-02 19:30-03', 'enfileirada',
          'f7a:ficha:joao:2026-11-03');

  -- ── Só no cenário do sábado: o Roberto com o padrão de sábado de manhã ─────────────────────────────────────────
  if coalesce(current_setting('agenda_teste.fase7a_sabado', true), '') = 'on' then
    insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, criado_por)
    values (v_roberto, '{6}', 'manha', 'disponivel', 'dono', 'sábado de manhã, quando precisar (teste 7a)', v_dono_u);
  end if;
end
$f7a$;
