-- Fixture do pacote P8 da Fase 7c da Agenda de Produção (as tarefas do dia: as etapas da OS), SINTÉTICO, por cima da da 7c
-- (fixture-fase7c.sql, que carrega a da 7b, a da 7a e o replay real de 29/10) (spec-fase7c §16.8.2, R5.1-6 e R5.2). Roda dentro do
-- begin/rollback do teste (o rodar.mjs passa este arquivo em agenda_teste.fase7c_tarefas); o que ainda não foi carregado nesta transação é
-- carregado antes. Pode rodar de novo na mesma transação (cada parte confere se já está lá). NUNCA rodar em produção.
-- Só primeiros nomes; telefones fictícios; ids novos com o prefixo c7c80000 e as OS 97191 a 97196 (a "191 a 196" da spec, na faixa 97xxx das
-- fixtures da Fase 7, livre na bancada).
--
-- Hoje é qua 04/11/2026 (a fixture não usa now(): todo teste passa p_hoje/p_agora; 07:10 congela hoje, 16:20 o passo diário, 17:00 o "como
-- foi", 17:40 as respostas, 19:30 a ficha). O que entra:
--   · o catálogo do roteiro (a bancada traz as tabelas vazias): os sistemas (Elétrico DC, Elétrico AC, Refrigeração, Hidráulico,
--     Estrutural, Eletrônico; nenhum não é físico) e os blocos de segurança — abertura do Elétrico DC (45 min, nunca é etapa) e fechamento do
--     Elétrico DC (75 min), da Refrigeração (60) e do Hidráulico (30); nenhum do Estrutural;
--   · as pessoas: o dono (Gustavo, o do replay); o Alex (o de produção) com um perfil de diária desde seg 26/10, a etiqueta instala 2 do
--     dono, telefone fictício e na lista da rotina; o Mateus (o da 7b) com a etiqueta ajudante 2 do dono, um perfil de diária desde 01/09
--     (mais de novato_dias antes de hoje: está na equipe da agenda, e o replano da vigia não cancela a manhã dele na 192 por "pessoa"), um
--     padrão seg a sex dito por ele (origem diarista: não vem sob demanda — R5 da 192: só a distribuição é provada; o motor e a escada não
--     poriam quem nunca vai sozinho) e na lista da rotina. Com agenda_teste.fase7c_tarefas_variante = 'alex_sem_telefone' antes de
--     carregar, o Alex fica sem telefone (o de produção, R5.2);
--   · as OS (barco na Marina Itajaí), as linhas copiadas das reais do replay (o nome, a unidade, a quantidade, o valor, o sistema, o verbo, o
--     catálogo e o created_at); os clientes têm o nome dos da carteira real (Lenine também é a OS-00074; Flávio, a OS-00104; Vanderlei, a
--     OS-00069): pelo nome, agenda_resolver_os pergunta qual — os testes e os evals do P8 dizem a OS pelo número:
--       191 Flávio    as 3 linhas da OS-00104 (sem roteiro); dias ditos 2 (fonte dono); prazo sex 06/11; ter 03/11 manhã e tarde Alex
--                     (passado) e sex 06/11 manhã e tarde Alex, o dono no fechamento de sex à tarde
--       192 Lenine    as 3 linhas da OS-00074 e o roteiro (28 passos em 5 blocos: a abertura, as 3 linhas e o fechamento do Elétrico DC,
--                     com os minutos de produção, sql/wf7cp8_02); dias ditos 1,5; prazo sex 06/11; qua 04/11 manhã Mateus sozinho, qua
--                     tarde Alex, qui 05/11 manhã e tarde Alex (a tarde é o meio-dia que o replano do parcial de qua acrescentaria: a
--                     fixture já o traz), o dono no fechamento de qui à tarde
--       193 Lenine    as mesmas 3 linhas, sem roteiro e sem plano (as mesmas etapas da 192)
--       194 Vanderlei as 5 linhas da OS-00069 e o roteiro (31 passos, só os blocos das linhas: sem abertura nem fechamento); dias ditos 2;
--                     ter 10/11 e qua 11/11 manhã e tarde Alex, o dono no fechamento de qua à tarde
--       195 Giancarlo as 10 linhas da OS-00130 (sem roteiro); dias ditos 1; seg 09/11 manhã e tarde Alex
--       196 Rodrigo   as 3 linhas da OS-00076 e o roteiro (27 passos: a abertura, o deslocamento, a substituição do conector, o conector
--                     — material — e o fechamento do Elétrico DC); sem plano
-- O plano do dia (os_tarefas_dia) e as etapas (os_tarefas) não entram aqui: quem cria é a rodada (o teste a chama com o p_hoje/p_agora do
-- caso; para o passado, o teste congela no dia dele).

do $f7c8$
declare
  c_cli    constant text := 'c7c80000-0000-4000-8000-0000000001';   -- + 2 dígitos: os clientes (91 a 96)
  c_bem    constant text := 'c7c80000-0000-4000-8000-0000000002';   -- + 2 dígitos: os bens
  c_os     constant text := 'c7c80000-0000-4000-8000-000000097';    -- + 3 dígitos: as OS (191 a 196)
  c_pubs   constant timestamptz := timestamptz '2026-11-02 16:30-03';  -- a publicação de seg 02/11 (o plano que já existia)
  v_var    text := coalesce(current_setting('agenda_teste.fase7c_tarefas_variante', true), '');
  v_dono_u uuid;
  v_dono   uuid;
  v_alex   uuid;
  v_mateus uuid;
  v_marina uuid;
  v_os     uuid;
  v_hoje_antes text;
  r        record;
  l        record;
  b        record;
  k        int;
begin
  -- ── 0. A base: a 7c (que carrega a 7b, a 7a e o replay) ──────────────────────────────────────────────────────────────
  if not exists (select 1 from public.service_orders where service_order_number = 'OS-97171')
     and not exists (select 1 from public.service_orders where service_order_number = 'OS-97101') then
    if coalesce(current_setting('agenda_teste.fase7c', true), '') = '' then
      raise exception 'fixture-fase7c-tarefas: falta a fixture da 7c (agenda_teste.fase7c; rode pela bancada)';
    end if;
    execute current_setting('agenda_teste.fase7c');
  end if;
  if v_var <> '' and v_var not in ('alex_sem_telefone') then
    raise exception 'fixture-fase7c-tarefas: a variante % não existe', v_var;
  end if;
  if exists (select 1 from public.service_orders where service_order_number = 'OS-97191') then
    return;
  end if;

  select id into strict v_dono_u from public.app_users where role = 'admin' and active order by id limit 1;
  v_dono := public._agenda_dono(null);
  select id into strict v_alex from public.payees where name = 'Alex' and active;
  select id into v_marina from public.marinas where name = 'Marina Itajaí' order by id limit 1;
  if v_marina is null then
    insert into public.marinas (id, name) values ('c7c80000-0000-4000-8000-000000000301'::uuid, 'Marina Itajaí') returning id into v_marina;
  end if;

  -- ── 1. O catálogo do roteiro: os sistemas e os blocos de segurança ──────────────────────────────────────────────────
  insert into public.service_systems (slug, name, short_name, is_physical, sort, active)
  values ('eletrico_dc', 'Elétrico DC', null, true, 10, true), ('eletrico_ac', 'Elétrico AC', null, true, 20, true),
         ('refrigeracao', 'Refrigeração', null, true, 30, true), ('hidraulico', 'Hidráulico', null, true, 40, true),
         ('estrutural', 'Estrutural', null, true, 50, true), ('eletronico', 'Eletrônico', null, true, 60, true),
         ('nenhum', 'Nenhum', null, false, 99, true)
  on conflict (slug) do nothing;
  insert into public.service_step_blocks (block_role, applies_to_system, seq, title, kind, standard_minutes, origin, active)
  values ('abertura', 'eletrico_dc', 1, 'Desligar a alimentação e confirmar ausência de tensão', 'safety', 45, 'manual', true),
         ('fechamento', 'eletrico_dc', 1, 'Conferir polaridade e aperto de todos os terminais', 'check', 40, 'manual', true),
         ('fechamento', 'eletrico_dc', 2, 'Energizar por etapas e testar cada circuito', 'check', 35, 'manual', true),
         ('fechamento', 'refrigeracao', 1, 'Testar o ciclo de refrigeração e a temperatura', 'check', 60, 'manual', true),
         ('fechamento', 'hidraulico', 1, 'Pressurizar e conferir vazamentos', 'check', 30, 'manual', true);

  -- ── 2. As pessoas: o Alex (perfil, instala 2 do dono, telefone, rotina) e o Mateus (ajudante 2 do dono, padrão dele, rotina) ─────
  if not exists (select 1 from public.work_profiles w where w.payee_id = v_alex) then
    insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, jornada_diaria_horas,
                                      meia_diaria_ate_horas, vigencia_inicio, vigencia_fim, created_at, updated_at)
    values (v_alex, 'diarista', 'diaria', 200, 8, 4, date '2026-10-26', null, timestamptz '2026-10-26 10:00-03',
            timestamptz '2026-10-26 10:00-03');
  end if;
  update public.payees set phone = case when v_var = 'alex_sem_telefone' then null else '5547900000031' end where id = v_alex;
  if not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = v_alex) then
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    values (v_alex, true, 'dono', timestamptz '2026-10-30 00:11-03');
  end if;
  update public.agenda_equipe_contato set recebe_rotina = true, parou_em = null, parou_motivo = null where payee_id = v_alex;
  insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em, criado_por)
  values (v_alex, 'instala', 2, 'dono', 'vale', 'você disse', 'o Alex instala sozinho', timestamptz '2026-11-02 09:00-03',
          timestamptz '2026-11-02 09:00-03', v_dono_u);

  select id into v_mateus from public.payees where name = 'Mateus' and active order by id limit 1;
  if v_mateus is null then
    insert into public.payees (name, kind, active, phone, created_at, updated_at)
    values ('Mateus', 'prestador', true, '5547900000011', timestamptz '2026-11-02 10:00-03', timestamptz '2026-11-02 10:00-03')
    returning id into v_mateus;
  end if;
  -- um perfil de diária desde 01/09 (mais de novato_dias antes de hoje: não é novato) para ele estar na equipe da agenda (a régua de 30/10)
  if not exists (select 1 from public.work_profiles w where w.payee_id = v_mateus) then
    insert into public.work_profiles (payee_id, tipo_vinculo, modo_pagamento, valor_diaria, jornada_diaria_horas,
                                      meia_diaria_ate_horas, vigencia_inicio, vigencia_fim, created_at, updated_at)
    values (v_mateus, 'diarista', 'diaria', 150, 8, 4, date '2026-09-01', null, timestamptz '2026-09-01 10:00-03',
            timestamptz '2026-09-01 10:00-03');
  end if;
  insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_em)
  values (v_mateus, '{1,2,3,4,5}', null, 'disponivel', 'diarista', 'Disse em 03/11 (fixture do P8)', 'seg a sex',
          timestamptz '2026-11-03 10:40-03');
  if not exists (select 1 from public.agenda_equipe_contato c where c.payee_id = v_mateus) then
    insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
    values (v_mateus, true, 'dono', timestamptz '2026-11-03 10:40-03');
  end if;
  insert into public.agenda_etiquetas (payee_id, etiqueta, nivel, origem, estado, motivo, trecho, vale_desde, criado_em, criado_por)
  values (v_mateus, 'ajudante', 2, 'dono', 'vale', 'você disse', 'o Mateus é ajudante', timestamptz '2026-11-03 10:45-03',
          timestamptz '2026-11-03 10:45-03', v_dono_u);

  -- ── 3. As OS e as linhas copiadas das reais ────────────────────────────────────────────────────────────────────────
  for r in
    select * from (values
      ('191', '91', 'Flávio',    'OS-00104', 2.0::numeric, date '2026-11-06'),
      ('192', '92', 'Lenine',    'OS-00074', 1.5,          date '2026-11-06'),
      ('193', '93', 'Lenine',    'OS-00074', null,         null::date),
      ('194', '94', 'Vanderlei', 'OS-00069', 2.0,          null),
      ('195', '95', 'Giancarlo', 'OS-00130', 1.0,          null),
      ('196', '96', 'Rodrigo',   'OS-00076', null,         null)
    ) as t(n, c, nome, origem, dias, prazo)
  loop
    v_os := (c_os || r.n)::uuid;
    insert into public.clients (id, type, name) values ((c_cli || r.c)::uuid, 'individual', r.nome);
    insert into public.vessels (id, client_id, name, asset_type, marina_id)
    values ((c_bem || r.c)::uuid, (c_cli || r.c)::uuid, 'Barco', 'Lancha', v_marina);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, marina_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at)
    values (v_os, 'OS-97' || r.n, (c_cli || r.c)::uuid, (c_bem || r.c)::uuid, v_marina, 'open', 'approved', 'repair',
            timestamptz '2026-10-26 10:00-03', timestamptz '2026-10-28 10:00-03', timestamptz '2026-10-28 10:00-03');
    k := 0;
    for l in
      select s.* from public.service_order_services s join public.service_orders so on so.id = s.service_order_id
       where so.service_order_number = r.origem order by s.created_at, s.id
    loop
      k := k + 1;
      insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, description_snapshot,
                                                 billing_unit_snapshot, quantity, unit_price_snapshot, line_total, service_verb,
                                                 service_system, created_at)
      values (md5(format('c7c8:linha:%s:%s', r.n, k))::uuid, v_os, l.service_id, l.name_snapshot, l.description_snapshot,
              l.billing_unit_snapshot, l.quantity, l.unit_price_snapshot, l.line_total,
              coalesce(l.service_verb, (select sv.service_verb from public.services sv where sv.id = l.service_id)),
              coalesce(l.service_system, (select sv.service_system from public.services sv where sv.id = l.service_id)),
              l.created_at);
    end loop;
    if r.dias is not null then
      insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, precisa_ate, atualizado_por)
      values (v_os, r.dias, 'dono', timestamptz '2026-10-28 10:00-03', r.prazo, v_dono_u);
    end if;
  end loop;

  -- ── 4. Os roteiros (192, 194, 196): os blocos com os minutos de produção (sql/wf7cp8_02); a ordem dos blocos é a de produção ─────────
  for b in
    select * from (values
      -- 192 Lenine: abertura, a substituição (2ª linha do bloco na ordem de produção), a porta-fusíveis, a passagem, o fechamento
      ('192', 1, 'abertura:eletrico_dc', null::int, '1 · Antes de mexer — Elétrico DC', 5, 45),
      ('192', 2, 'linha', 1, '2 · Substituição baterias - chumbo para litio', 6, 135),
      ('192', 3, 'linha', 2, '3 · Instalação de porta fusíveis - distribuição de energia 1', 6, 180),
      ('192', 4, 'linha', 3, '4 · Serviço de passagem e crimpagem de cabos de bateria', 6, 180),
      ('192', 5, 'fechamento:eletrico_dc', null, '5 · Antes de entregar — Elétrico DC', 5, 75),
      -- 194 Vanderlei: só as 5 linhas, na ordem do roteiro de produção (adequação, desmontagem, testes, configuração, instalação)
      ('194', 1, 'linha', 4, '1 · Adequação de instalação elétrica e quadros', 5, 295),
      ('194', 2, 'linha', 3, '2 · Desmontagem do sistema elétrico atual', 5, 165),
      ('194', 3, 'linha', 1, '3 · Testes e comissionamento do sistema', 6, 190),
      ('194', 4, 'linha', 2, '4 · Configuração e parametrização dos equipamentos', 6, 140),
      ('194', 5, 'linha', 5, '5 · Instalação do novo sistema elétrico LiFePO4/Usina', 9, 430),
      -- 196 Rodrigo: a abertura, o deslocamento, a substituição do conector, o conector (material), o fechamento
      ('196', 1, 'abertura:eletrico_dc', null, '1 · Antes de mexer — Elétrico DC', 5, 45),
      ('196', 2, 'linha', 1, '2 · Deslocamento técnico', 5, 60),
      ('196', 3, 'linha', 2, '3 · Substituição de conector e emenda no cabo de dados Starlink', 6, 120),
      ('196', 4, 'linha', 3, '4 · Conector de cabo de dados Starlink', 6, 60),
      ('196', 5, 'fechamento:eletrico_dc', null, '5 · Antes de entregar — Elétrico DC', 5, 75)
    ) as t(n, bloco, chave, linha_k, rotulo, passos, minutos)
  loop
    v_os := (c_os || b.n)::uuid;
    for k in 1 .. b.passos loop
      insert into public.service_order_steps (id, service_order_id, service_order_service_id, seq, block, title, kind, mode,
                                              standard_minutes, status, origin, block_key, created_at, updated_at)
      values (md5(format('c7c8:passo:%s:%s:%s', b.n, b.bloco, k))::uuid, v_os,
              case when b.linha_k is not null then md5(format('c7c8:linha:%s:%s', b.n, b.linha_k))::uuid end,
              (select coalesce(max(st.seq), 0) + 1 from public.service_order_steps st where st.service_order_id = v_os),
              b.rotulo, format('Passo %s de %s', k, b.rotulo), 'do', 'do_confirm',
              b.minutos / b.passos + case when k = 1 then b.minutos % b.passos else 0 end, 'pending', 'template',
              case when b.linha_k is not null then 'linha:' || md5(format('c7c8:linha:%s:%s', b.n, b.linha_k))::uuid::text else b.chave end,
              timestamptz '2026-08-05 12:00-03', timestamptz '2026-08-05 12:00-03');
    end loop;
  end loop;

  -- ── 5. O plano (alocações publicadas). O passado é do dia que já chegou para quem escreve (agenda.hoje: qua 04/11). ──────────────
  v_hoje_antes := coalesce(current_setting('agenda.hoje', true), '');
  perform set_config('agenda.hoje', '2026-11-04', true);
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  select md5(format('c7c8:aloc:%s:%s:%s:%s', t.n, t.quem, t.dia, t.turno))::uuid, (c_os || t.n)::uuid,
         case t.quem when 'alex' then v_alex when 'mateus' then v_mateus else v_dono end, t.dia::date, t.turno, t.presenca, 'execucao',
         'publicada', 'motor', c_pubs
    from (values
      ('191', 'alex', '2026-11-03', 'manha', 'turno'), ('191', 'alex', '2026-11-03', 'tarde', 'turno'),
      ('191', 'alex', '2026-11-06', 'manha', 'turno'), ('191', 'alex', '2026-11-06', 'tarde', 'turno'),
      ('191', 'dono', '2026-11-06', 'tarde', 'fechamento'),
      ('192', 'mateus', '2026-11-04', 'manha', 'turno'), ('192', 'alex', '2026-11-04', 'tarde', 'turno'),
      ('192', 'alex', '2026-11-05', 'manha', 'turno'), ('192', 'alex', '2026-11-05', 'tarde', 'turno'),
      ('192', 'dono', '2026-11-05', 'tarde', 'fechamento'),
      ('194', 'alex', '2026-11-10', 'manha', 'turno'), ('194', 'alex', '2026-11-10', 'tarde', 'turno'),
      ('194', 'alex', '2026-11-11', 'manha', 'turno'), ('194', 'alex', '2026-11-11', 'tarde', 'turno'),
      ('194', 'dono', '2026-11-11', 'tarde', 'fechamento'),
      ('195', 'alex', '2026-11-09', 'manha', 'turno'), ('195', 'alex', '2026-11-09', 'tarde', 'turno')
    ) as t(n, quem, dia, turno, presenca);
  perform set_config('agenda.hoje', v_hoje_antes, true);
end
$f7c8$;
