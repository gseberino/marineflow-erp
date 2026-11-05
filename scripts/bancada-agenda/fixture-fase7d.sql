-- Fixture da Fase 7d da Agenda de Produção ("onde, quando e com o bem em que estado"), SINTÉTICO, por cima da da 7c (fixture-fase7c.sql,
-- que carrega a 7b, a 7a e o replay real de 29/10) (spec-fase7d §8.2, com o R6.10, que vale sobre ela). Roda dentro do begin/rollback do
-- teste (o rodar.mjs passa este arquivo em agenda_teste.fase7d e o da 7c em agenda_teste.fase7c); o que ainda não foi carregado nesta
-- transação é carregado antes. Pode rodar de novo na mesma transação (confere se já está lá). NUNCA rodar em produção.
-- Só primeiros nomes; telefones fictícios (55479000002NN); ids novos com o prefixo d7d00000.
--
-- A equipe é a sintética da 7c (Roberto e João de volta, Alex, Rafael, Bruno): com agenda_teste.fase7b_equipe = 'real' esta fixture recusa.
-- Ela não mexe em agenda_config: os 6 modos ficam como cada teste os puser, autorizacao_antecedencia_du fica no padrão (2; o R6.10 tirou o
-- "= 4" da §8.2) e onde_fica_desde fica nula (o teste do M11 grava: R6.7a).
--
-- Os NÚMEROS das OS são OS-J1 a OS-J14 e OS-D1 a OS-D3: são os dos textos da §6 da spec, byte a byte (nos desvios, as notas do P1). O
-- resolver de OS só lê número com dígitos: quem resolve pela frase passa o id da OS, não "OS-J1".
--
-- Os locais (agenda_locais; as marinas que o replay não trouxe entram com ids d7d00000…0002NN):
--   Marina Itajaí   Itajaí/SC          conferida pelo dono em 01/07/2027: exige autorização, sábado de manhã, 08–18, garagem seca
--   Tedesco         Balneário Camb./SC só pesquisa (nota, 29/10/2026), garagem seca, coordenadas
--   MP Motorhomes   Balneário Camb./SC o pátio da HBR (AG7-18: UM local só, e nenhum pátio em Itajaí), vagas = 3, deslocamento 0
--   Iate Clube Caiobá  Guaratuba/PR    sem coordenadas
--   Veleiros da Ilha   Florianópolis/SC  sem coordenadas
-- app_settings: a base do deslocamento e a cidade da empresa, as de produção (rec7d_settings).
--
-- Cenário J — julho (hoje = sex 16/07/2027, p_agora 16:20; ter 20/07/2027 é feriado em BC). Aprovadas em 01/07, fora o dito abaixo:
--   OS-J1  Lenine    motorhome na MP (pela OS), 1 dia, pronta; publicada ter 20/07 (manhã e tarde, Alex) de antes da 7d: 20/07 fora com o
--                    calendário ligado; a violação local da publicada
--   OS-J2  Nelson    veleiro na Marina Itajaí, 2 dias, dupla marcada (7b), Roberto e João ditos, só o Roberto autorizado (os_autorizados),
--                    garagem seca dita, quem desce: a marina, "Teste de mar" numa linha; publicada ter 20/07 com os dois. O acesso NÃO é
--                    filtro: com modo_local_autorizacao ligado, J2 sai igual ao de sombra (M3, md5). Marina Itajaí fica em Itajaí: 20/07
--                    não fecha para ela
--   OS-J3  Vanderlei, OS-J4 Renato e OS-J5 Vanderlei
--                    3 motorhomes sem local (suposição: o pátio), 2 dias cada. O pátio tem 3 vagas e J1 + J3 + J4 ocupam: o 4º (J5) entra
--                    quando um sai; com vagas nulas, todos juntos. Também caem em 20/07 (o pátio é em BC)
--   OS-J6  Kalmar    barco no Iate Clube Caiobá (pela OS), 2 dias: pernoite, 4 + 2 = 6 meios seguidos, a mesma equipe, sem abre e fecha
--   OS-J7  Sílvio    barco no Veleiros da Ilha (pela OS), 1 dia: ida e volta, 2 + 2 = 4 meios em 2 dias
--   OS-J8  Tiago     barco sem local, cliente em Penha: chave c:penha, suposição
--   OS-J9  Marcos e OS-J10 Igor
--                    barcos na Marina Itajaí, meio dia cada: no mesmo dia; quem já está lá
--   OS-J11 Carla     motorhome sem local, aprovado ontem (qui 15/07), sem entrada: M11 motorhome
--   OS-J12 Beto      lancha na Marina Itajaí, sem situação, aprovada há 20 dias (sáb 26/06), publicada seg 26/07 (Rafael): M11 pelo 1º dia
--   OS-J13 Júlio     barco sem local, 1º dia "amanhã": seg 19/07, o próximo dia útil (amanhã é sábado) (Rafael): sem M11, a véspera cuida
--   OS-J14 Nuno      barco com o local dito pelo dono (Tedesco, os_planejamento.local_id): sem M11
-- As respostas do cliente ao M11 (§8.2) são do teste do P6: elas só existem com a mensagem registrada. A de J2 ("na marina itajai, fica na
-- garagem, quem desce é a marina") pede J2 sem a situação dita: o P6 limpa antes (a porta do M11 é "barco sem situação").
--
-- Cenário D — dezembro (hoje = seg 30/11/2026; temporada). O dia da OS-D1 sai de agenda_teste.fase7d_d_dia (padrão ter 01/12/2026; para o
-- "mesmo cenário em julho", fora da temporada, passe o dia em julho antes de carregar):
--   OS-D1  Otto      barco na Tedesco (BC), publicada nesse dia de manhã com o Roberto
--   OS-D2  Rui       barco sem local, cliente em Penha, meio dia
--   OS-D3  Saulo     barco sem local, cliente em Balneário Camboriú, meio dia (mesmo município da D1, OUTRO local: prova a troca sozinha,
--                    sem o "mesmo local")
-- D2 e D3 disputam a tarde do Roberto; a troca de cidade é só na temporada.

do $f7d$
declare
  c_mar     constant text := 'd7d00000-0000-4000-8000-0000000002';   -- + 2 dígitos: as marinas que o replay não trouxe
  c_cli     constant text := 'd7d00000-0000-4000-8000-0000000003';   -- + 2 dígitos: os clientes
  c_bem     constant text := 'd7d00000-0000-4000-8000-0000000004';   -- + 2 dígitos: os bens
  c_os      constant text := 'd7d00000-0000-4000-8000-000000097';    -- + 3 dígitos: as OS (201 a 214 = J1 a J14; 221 a 223 = D1 a D3)
  c_aprov   constant timestamptz := timestamptz '2027-07-01 10:00-03';  -- a aprovação de J (fora as ditas): há 15 dias, fora da janela do M11
  c_pubs    constant timestamptz := timestamptz '2027-07-08 16:30-03';  -- a publicação de antes da 7d em J
  c_pubs_d  constant timestamptz := timestamptz '2026-11-26 16:30-03';  -- a publicação de D
  v_dia_d   date := coalesce(nullif(current_setting('agenda_teste.fase7d_d_dia', true), ''), '2026-12-01')::date;
  v_mar_it  uuid;
  v_mar_mp  uuid;
  v_loc_it  uuid;
  v_loc_ted uuid;
  v_dono_u  uuid;
  v_alex    uuid;
  v_roberto uuid;
  v_joao    uuid;
  v_rafael  uuid;
  v_os      uuid;
  r         record;
begin
  -- ── 0. A base: a 7c (que carrega a 7b, a 7a e o replay) ────────────────────────────────────────────
  if coalesce(current_setting('agenda_teste.fase7b_equipe', true), '') = 'real' then
    raise exception 'fixture-fase7d: é por cima da equipe sintética da 7c (Roberto, João, Rafael): agenda_teste.fase7b_equipe = ''real'' não serve';
  end if;
  if not exists (select 1 from public.service_orders where service_order_number = 'OS-97171') then
    if coalesce(current_setting('agenda_teste.fase7c', true), '') = '' then
      raise exception 'fixture-fase7d: falta a fixture da 7c (agenda_teste.fase7c; rode pela bancada)';
    end if;
    execute current_setting('agenda_teste.fase7c');
  end if;

  if exists (select 1 from public.service_orders where service_order_number = 'OS-J1') then
    return;  -- já carregada nesta transação
  end if;

  select id into strict v_dono_u from public.app_users where role = 'admin' and active order by id limit 1;
  select id into strict v_alex from public.payees where name = 'Alex' and active;
  select id into strict v_roberto from public.payees where name = 'Roberto' and active;
  select id into strict v_joao from public.payees where name = 'João' and active;
  select id into strict v_rafael from public.payees where name = 'Rafael' and active;
  select id into strict v_mar_it from public.marinas where name = 'Marina Itajaí';
  select id into strict v_mar_mp from public.marinas where name = 'MP Motorhomes';

  -- ── 1. A base do deslocamento (app_settings) e as marinas ──────────────────────────────────────────
  insert into public.app_settings (key, value)
  values ('travel_base_lat', '-26.9189'), ('travel_base_lng', '-48.6728'), ('company_city', 'Itajaí'), ('company_state', 'SC')
  on conflict (key) do nothing;

  insert into public.marinas (id, name, city, state, latitude, longitude)
  values ((c_mar || '01')::uuid, 'Tedesco Marina Garden Plaza', 'Balneário Camboriú', 'SC', -27.0061359, -48.6159906),
         ((c_mar || '02')::uuid, 'Iate Clube Caiobá', 'Guaratuba', 'PR', null, null),
         ((c_mar || '03')::uuid, 'Veleiros da Ilha', 'Florianópolis', 'SC', null, null);

  -- ── 2. Os locais ───────────────────────────────────────────────────────────────────────────────────
  insert into public.agenda_locais (marina_id, nome, apelidos, tipo, municipio, uf, latitude, longitude, abre, fecha, sabado,
                                    exige_autorizacao, autorizacao_texto, tem_garagem_seca, conferido_em, conferido_por)
  values (v_mar_it, 'Marina Itajaí', '{marina de itajai,marina itajai}', 'marina', 'Itajaí', 'SC', -26.910923, -48.651596,
          time '08:00', time '18:00', 'manha', true, 'autorização escrita do dono do barco com nome e documento de quem vai e as datas',
          true, date '2027-07-01', 'dono')
  returning id into v_loc_it;

  insert into public.agenda_locais (marina_id, nome, apelidos, tipo, municipio, uf, latitude, longitude, tem_garagem_seca,
                                    conferido_em, conferido_por, fonte_texto)
  values ((c_mar || '01')::uuid, 'Tedesco Marina Garden Plaza', '{tedesco,garden plaza}', 'marina', 'Balneário Camboriú', 'SC',
          -27.006136, -48.615991, true, date '2026-10-29', 'pesquisa', 'Pesquisa de 29/10/2026: 3 hangares de até 4 andares.')
  returning id into v_loc_ted;

  insert into public.agenda_locais (marina_id, nome, apelidos, tipo, municipio, uf, vagas, deslocamento_min, nota_dono)
  values (v_mar_mp, 'MP Motorhomes', '{mp motorhomes,mp motorhome,mp motor home,patio,patio da hbr,oficina,na hbr,com voces}', 'patio_hbr',
          'Balneário Camboriú', 'SC', 3, 0,
          'O espaço da HBR fica dentro do pátio da MP Motorhomes, em Balneário Camboriú (AG7-18).');

  insert into public.agenda_locais (marina_id, nome, apelidos, tipo, municipio, uf)
  values ((c_mar || '02')::uuid, 'Iate Clube Caiobá', '{caioba,iate clube caioba}', 'marina', 'Guaratuba', 'PR'),
         ((c_mar || '03')::uuid, 'Veleiros da Ilha', '{veleiros da ilha}', 'marina', 'Florianópolis', 'SC');

  -- ── 3. As OS ───────────────────────────────────────────────────────────────────────────────────────
  -- Vanderlei é um cliente só, com 2 motorhomes (OS-J3 e OS-J5): os textos da §6.2 dizem "Vanderlei" nas duas.
  for r in
    select * from (values
      -- n,   número,   c,    nome,        bem,         marina da OS,   cidade,               meios, serviço, aprovada
      ('201', 'OS-J1',  '01', 'Lenine',    'Motorhome', v_mar_mp,                 null::text,           2, 'Troca do inversor',               c_aprov),
      ('202', 'OS-J2',  '02', 'Nelson',    'Veleiro',   v_mar_it,                 null,                 3, 'Revisão do banco de baterias',    c_aprov),
      ('203', 'OS-J3',  '03', 'Vanderlei', 'Motorhome', null::uuid,               null,                 4, 'Instalação de carregador',        c_aprov),
      ('204', 'OS-J4',  '04', 'Renato',    'Motorhome', null,                     null,                 4, 'Instalação de placa solar',       c_aprov),
      ('205', 'OS-J5',  '03', 'Vanderlei', 'Motorhome', null,                     null,                 4, 'Troca do quadro 12V',             c_aprov),
      ('206', 'OS-J6',  '06', 'Kalmar',    'Lancha',    (c_mar || '02')::uuid,    null,                 4, 'Revisão do piloto automático',    c_aprov),
      ('207', 'OS-J7',  '07', 'Sílvio',    'Lancha',    (c_mar || '03')::uuid,    null,                 2, 'Troca do GPS',                    c_aprov),
      ('208', 'OS-J8',  '08', 'Tiago',     'Lancha',    null,                     'Penha',              2, 'Revisão do rádio',                c_aprov),
      ('209', 'OS-J9',  '09', 'Marcos',    'Lancha',    v_mar_it,                 null,                 1, 'Troca de bomba de porão',         c_aprov),
      ('210', 'OS-J10', '10', 'Igor',      'Lancha',    v_mar_it,                 null,                 1, 'Troca de luminárias',             c_aprov),
      ('211', 'OS-J11', '11', 'Carla',     'Motorhome', null,                     null,                 2, 'Instalação de tomada 12V',        timestamptz '2027-07-15 10:00-03'),
      ('212', 'OS-J12', '12', 'Beto',      'Lancha',    v_mar_it,                 null,                 2, 'Revisão do quadro elétrico',      timestamptz '2027-06-26 10:00-03'),
      ('213', 'OS-J13', '13', 'Júlio',     'Lancha',    null,                     null,                 2, 'Revisão da iluminação',           c_aprov),
      ('214', 'OS-J14', '14', 'Nuno',      'Lancha',    null,                     null,                 2, 'Revisão do carregador',           c_aprov),
      ('221', 'OS-D1',  '21', 'Otto',      'Lancha',    (c_mar || '01')::uuid,    null,                 1, 'Revisão do som',                  timestamptz '2026-11-20 10:00-03'),
      ('222', 'OS-D2',  '22', 'Rui',       'Lancha',    null,                     'Penha',              1, 'Troca de bomba de porão',         timestamptz '2026-11-20 10:00-03'),
      ('223', 'OS-D3',  '23', 'Saulo',     'Lancha',    null,                     'Balneário Camboriú', 1, 'Troca de luminárias',             timestamptz '2026-11-20 10:00-03')
    ) as t(n, numero, c, nome, bem, marina, cidade, meios, servico, aprovada)
  loop
    v_os := (c_os || r.n)::uuid;
    insert into public.clients (id, type, name, phone, city)
    values ((c_cli || r.c)::uuid, 'individual', r.nome, '55479000002' || r.c, r.cidade)
    on conflict (id) do nothing;
    insert into public.vessels (id, client_id, marina_id, name, asset_type)
    values ((c_bem || right(r.n, 2))::uuid, (c_cli || r.c)::uuid, r.marina, r.bem, r.bem);
    insert into public.service_orders (id, service_order_number, client_id, vessel_id, marina_id, status, quote_status, service_type,
                                       created_at, updated_at, converted_to_os_at)
    values (v_os, r.numero, (c_cli || r.c)::uuid, (c_bem || right(r.n, 2))::uuid, r.marina, 'open', 'approved', 'repair',
            r.aprovada - interval '2 days', r.aprovada, r.aprovada);
    insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                               unit_price_snapshot, line_total, created_at)
    values (md5('d7d:servico:' || r.n)::uuid, v_os, null, r.servico, 'unit', 1, 382 * r.meios, 382 * r.meios, r.aprovada - interval '2 days');
    insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, atualizado_por)
    values (v_os, greatest(r.meios, 1) / 2.0, 'dono', r.aprovada, v_dono_u);
  end loop;

  -- OS-J1: 1 dia; as publicadas sem o dono (o que elas provam é o dia, não a presença dele)
  update public.os_planejamento set dono_presenca = 'nunca'
   where service_order_id = any (array[(c_os || '201')::uuid, (c_os || '202')::uuid, (c_os || '212')::uuid, (c_os || '213')::uuid,
                                       (c_os || '221')::uuid]);

  -- OS-J2 Nelson: 2 dias (a linha do "Teste de mar" soma o 4º meio-dia), a dupla, a garagem seca dita e quem desce, Roberto e João ditos,
  -- só o Roberto autorizado
  insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
                                             unit_price_snapshot, line_total, created_at)
  values (md5('d7d:servico:202b')::uuid, (c_os || '202')::uuid, null, 'Teste de mar', 'unit', 1, 382, 382, timestamptz '2027-06-29 10:00-03');
  update public.os_planejamento
     set dias = 2, dupla_dita = 'todos', dupla_motivo = 'você disse: Nelson com dupla', dupla_em = timestamptz '2027-07-01 10:05-03',
         bem_situacao = 'garagem_seca', bem_situacao_fonte = 'dono', bem_situacao_em = timestamptz '2027-07-01 10:05-03',
         descer_quem = 'a marina'
   where service_order_id = (c_os || '202')::uuid;
  insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos, criado_em)
  values ((c_os || '202')::uuid, v_roberto, 'dia', timestamptz '2027-07-01 10:10-03'),
         ((c_os || '202')::uuid, v_joao, 'dia', timestamptz '2027-07-01 10:10-03');
  insert into public.os_autorizados (service_order_id, payee_id, local_id, valido_ate, fonte, trecho, criado_em, criado_por)
  values ((c_os || '202')::uuid, v_roberto, v_loc_it, date '2027-07-23', 'dono', 'o Roberto está autorizado na Marina Itajaí',
          timestamptz '2027-07-01 10:15-03', v_dono_u);

  -- OS-J14 Nuno: o local dito pelo dono
  update public.os_planejamento
     set local_id = v_loc_ted, local_fonte = 'dono', local_em = timestamptz '2027-07-01 10:20-03'
   where service_order_id = (c_os || '214')::uuid;

  -- ── 4. As publicadas de antes da 7d ────────────────────────────────────────────────────────────────
  insert into public.agenda_alocacoes (id, service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em)
  select md5('d7d:aloc:' || t.n || ':' || t.quem || ':' || t.turno)::uuid, (c_os || t.n)::uuid, t.payee, t.dia, t.turno, 'turno', 'execucao',
         'publicada', 'motor', t.pubs
    from (values
      ('201', 'alex',    v_alex,    date '2027-07-20', 'manha', c_pubs),
      ('201', 'alex',    v_alex,    date '2027-07-20', 'tarde', c_pubs),
      ('202', 'roberto', v_roberto, date '2027-07-20', 'manha', c_pubs),
      ('202', 'roberto', v_roberto, date '2027-07-20', 'tarde', c_pubs),
      ('202', 'joao',    v_joao,    date '2027-07-20', 'manha', c_pubs),
      ('202', 'joao',    v_joao,    date '2027-07-20', 'tarde', c_pubs),
      ('212', 'rafael',  v_rafael,  date '2027-07-26', 'manha', c_pubs),
      ('212', 'rafael',  v_rafael,  date '2027-07-26', 'tarde', c_pubs),
      ('213', 'rafael',  v_rafael,  date '2027-07-19', 'manha', c_pubs),
      ('213', 'rafael',  v_rafael,  date '2027-07-19', 'tarde', c_pubs),
      ('221', 'roberto', v_roberto, v_dia_d,           'manha', c_pubs_d)
    ) as t(n, quem, payee, dia, turno, pubs);
end
$f7d$;
