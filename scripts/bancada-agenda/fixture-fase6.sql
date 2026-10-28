-- Fixture da Fase 6 da Agenda de Produção: a história de 07/09 a 29/10/2026 que o aprendizado mede, SINTÉTICA.
-- = fixture-fase5.sql (que executa as das Fases 4, 3 e 2 e o pós-rodada da Fase 1 por dentro) + 14 OS concluídas com o que a
-- medição lê: os dias que o dono disse, as alocações com o resultado da conferência, as diárias ligadas, a mão de obra, a 1ª
-- promessa ao cliente e os avisos de atraso enviados. Roda dentro do begin/rollback do teste (o rodar.mjs passa este arquivo
-- em agenda_teste.fase6 e os de antes nos seus nomes). NUNCA rodar em produção. Só primeiros nomes; nenhum telefone (nada
-- sai para cliente nenhum); ids novos com o prefixo d6000000/c6000000/f6000000 e as OS 131 a 144 (livres em 28/10).
--
-- Hoje é sex 30/10/2026 (p_hoje), a rodada do aprendizado às 16:05 (p_agora). O relógio da bancada continua o da C2 (ter
-- 27/10 15:00): todo teste passa p_hoje/p_agora.
--
-- P1 (28/10) — as OS concluídas (spec-fase6 §8.2), o que cada uma deve medir (o M4 de agenda_fase6_medicao.sql fixa):
--   OS       classe          dias ditos        o que aconteceu (R = Roberto, J = João, M = Mickael, G = o dono)      fator
--   131 Ana  rv:energia      1 (dono)          R 08/09 manhã e tarde                                                  1,00
--   132 Bruno rv:energia     1 (aceita)        R 09/09 manhã e tarde                                                  1,00
--   133 Caio rv:energia      2 (dono; rediz 3  R 15 e 16/09 inteiros, 17/09 manhã                                     1,25
--                            em 17/09, depois
--                            do check-in)
--   134 Davi rv:energia      1                 R 19/10 inteiro, 20/10 manhã (a diária de 20/10 dividida com a 135)    1,50
--   135 Elisa rv:energia     2                 R 20/10 tarde, 21 e 22/10 inteiros, 23/10 manhã NÃO cumprida (material) 1,50
--                                              e tarde; J 21/10 manhã (o mesmo meio-dia do R: conta uma vez)
--   136 Fábio rv:energia     2                 R 26 a 28/10 inteiros, 29/10 manhã e tarde PARCIAIS                    1,75
--   137 Gil  rv:energia      1                 J 26/10 inteiro + a diária de J de 27/10 ligada SEM alocação (2 meios  2,00
--                                              fora do plano)
--   138 Hugo barco:motor     1                 R 10/09 inteiro                                                        1,00
--   139 Íris barco:motor     1                 R 11/09 inteiro, M 14/09 manhã                                         1,50
--   140 Jonas rv:diagnostico 1                 G (o dono) 22/09 inteiro, diagnóstico: só o dono, vale sem diária     1,00
--   141 Lara rv:geral        — (só a sugerida) R 23/09 inteiro                          inválida: dias_sugeridos
--   142 Murilo barco:energia 1                 R 24/09 manhã; a tarde SEM REGISTRO        inválida: conferencia_incompleta
--   143 Noel outro:geral     1                 R 25/09 inteiro, a diária dele NÃO ligada  inválida: sem_diaria
--   144 Otto rv:conforto     1                 R 28/09 inteiro                                                        1,00
--   (a 144 é a "reaberta" da spec: o M5 a reabre numa subtransação, e a medida seguinte fica inválida, motivo reaberta.)
--   O P80 das 7 rv:energia (1,0 · 1,0 · 1,25 · 1,5 · 1,5 · 1,75 · 2,0) é 1,70: o "hoje seria 1,7×". Válidas: 11 (as 7, as 2
--   de barco, a do dono e a 144); as de barco caem no nível "todas" (barco:motor, sistema:motor e bem:barco têm 2).
--   As OS concluídas das fixtures de antes também são medidas (OS-00050, 121, 122 e 123): nenhuma tem dias ditos nem plano
--   — inválidas pelos motivos delas.
-- R$ por diária: a mão de obra das 7 rv:energia é R$ 690 × as diárias ligadas de cada uma (16,5 diárias, R$ 11.385).
-- Cliente (a pontualidade e a folga do aviso):
--   · a 1ª promessa: 131 08/09, 132 10/09, 133 18/09, 134 21/10, 135 21/10, 136 30/10 pelo prometido_original_ate (prometidas
--     antes da Fase 6) e a 137 23/10 pelo prometido_primeiro_ate: o aviso "ainda faltam peças sem data" de 20/10 zerou o
--     prometido e o original, e o aviso da peça de 23/10 gravou 26/10 como se fosse o 1º (NOVO-agenda-44). No prazo: 131,
--     132, 133, 134 e 136 (5 de 7); 135 e 137 dois dias úteis depois;
--   · os avisos de atraso enviados (pode_atrasar): 133 (faixa até 15/09), 134 (20/10), 135 (21/10), 136 (26/10) e a 137 (o sem
--     data, sem faixa, e o da peça, até 26/10): a conclusão 2, 0, 2, 3 e 1 dia útil depois da faixa → P80 2,2 (a folga 2).
--     Os avisos que estreitam a faixa dentro da promessa (133, 134, 136) estouram a faixa sem atrasar a promessa.
-- O que os pacotes seguintes acrescentam (em seções próprias no fim deste arquivo): as intervenções do dono de 20/10, 22/10 e
-- 27/10 (P2: na 134, na 135 e na 136, e uma "passou"), os fornecedores (P3), as semanas do dono no plano (P4) e o plano
-- cumprido das semanas de 05, 12 e 19/10 (P6). As alocações daqui ocupam as semanas de 07/09 a 02/10 e de 19 a 29/10
-- (notas-fase6.md diz quantas por semana e de quem).
-- Os modos ao fim: os da fixture-fase5 e modo_aprendizado desligado, como a linha nasce: cada teste liga o que precisa.

do $fase6$
begin
  if coalesce(current_setting('agenda_teste.fase5', true), '') = '' then
    raise exception 'fixture-fase6: falta agenda_teste.fase5 (rode pela bancada: scripts/bancada-agenda/rodar.mjs)';
  end if;
  execute current_setting('agenda_teste.fase5');
end
$fase6$;

-- As alocações do passado entram como se já existissem antes da publicação de qui 29/10: o contador do plano fica como a
-- fixture-fase3 o deixou (a pergunta crítica aberta guarda a versão dele).
create temp table _fase6_versao on commit drop as select versao_plano from public.agenda_config where id;
-- O resultado é do dia que já chegou: o "hoje" da agenda é sex 30/10 enquanto a história entra.
select set_config('agenda.hoje', '2026-10-30', true);

-- ── Os clientes e os bens ───────────────────────────────────────────────────────────────────────────────
insert into public.clients (id, type, name)
select ('c6000000-0000-4000-8000-000000000' || n)::uuid, 'individual', nome
  from (values ('131', 'Ana'), ('132', 'Bruno'), ('133', 'Caio'), ('134', 'Davi'), ('135', 'Elisa'), ('136', 'Fábio'),
               ('137', 'Gil'), ('138', 'Hugo'), ('139', 'Íris'), ('140', 'Jonas'), ('141', 'Lara'), ('142', 'Murilo'),
               ('143', 'Noel'), ('144', 'Otto')) as c(n, nome);

insert into public.vessels (id, client_id, name, asset_type)
select ('f6000000-0000-4000-8000-000000000' || n)::uuid, ('c6000000-0000-4000-8000-000000000' || n)::uuid, tipo, tipo
  from (values ('131', 'Motorhome'), ('132', 'Motorhome'), ('133', 'Motorhome'), ('134', 'Motorhome'), ('135', 'Motorhome'),
               ('136', 'Motorhome'), ('137', 'Motorhome'), ('138', 'Lancha'), ('139', 'Lancha'), ('140', 'Motorhome'),
               ('141', 'Camper'), ('142', 'Lancha'), ('143', 'Equipamento'), ('144', 'Motorhome')) as v(n, tipo);

-- ── As OS concluídas (pela porta: a entrega e o status só entram com a chave local) ─────────────────────
select set_config('agenda.porta', 'on', true);
insert into public.service_orders (id, service_order_number, client_id, vessel_id, status, quote_status, service_type,
  created_at, updated_at, converted_to_os_at, check_in_at, check_out_at, delivered_at, grand_total)
select ('05000000-0000-4000-8000-000000000' || n)::uuid, 'OS-00' || n, ('c6000000-0000-4000-8000-000000000' || n)::uuid,
       ('f6000000-0000-4000-8000-000000000' || n)::uuid, 'completed', 'approved', 'repair',
       (entra::timestamp - interval '20 days') at time zone 'America/Sao_Paulo', entregue::timestamp at time zone 'America/Sao_Paulo',
       (entra::timestamp - interval '14 days') at time zone 'America/Sao_Paulo',
       entra::timestamp at time zone 'America/Sao_Paulo', sai::timestamp at time zone 'America/Sao_Paulo',
       entregue::timestamp at time zone 'America/Sao_Paulo', total
  from (values
    ('131', '2026-09-08 08:00', '2026-09-08 17:00', '2026-09-09 10:00', 690),
    ('132', '2026-09-09 08:00', '2026-09-09 17:00', '2026-09-10 10:00', 690),
    ('133', '2026-09-15 08:00', '2026-09-17 12:00', '2026-09-18 10:00', 2070),
    ('134', '2026-10-19 08:00', '2026-10-20 12:00', '2026-10-21 10:00', 1035),
    ('135', '2026-10-20 13:00', '2026-10-23 17:00', '2026-10-24 10:00', 2760),
    ('136', '2026-10-26 08:00', '2026-10-29 17:00', '2026-10-30 09:00', 2760),
    ('137', '2026-10-26 08:00', '2026-10-27 17:00', '2026-10-28 10:00', 1380),
    ('138', '2026-09-10 08:00', '2026-09-10 17:00', '2026-09-11 10:00', 2400),
    ('139', '2026-09-11 08:00', '2026-09-14 12:00', '2026-09-15 10:00', 7800),
    ('140', '2026-09-22 08:00', '2026-09-22 17:00', '2026-09-22 17:30', 250),
    ('141', '2026-09-23 08:00', '2026-09-23 17:00', '2026-09-24 10:00', 1380),
    ('142', '2026-09-24 08:00', '2026-09-24 17:00', '2026-09-25 10:00', 450),
    ('143', '2026-09-25 08:00', '2026-09-25 17:00', '2026-09-26 10:00', 600),
    ('144', '2026-09-28 08:00', '2026-09-28 17:00', '2026-09-29 10:00', 900)
  ) as o(n, entra, sai, entregue, total);
select set_config('agenda.porta', 'off', true);

-- ── As linhas de serviço (texto livre, por visita: nunca material, nunca hora) ──────────────────────────
-- A principal é a de maior valor (as palavras da classe); a 135 e a 136 têm o deslocamento à parte (menor). Textos das linhas
-- de produção (f6p1/q01_principais).
insert into public.service_order_services (id, service_order_id, service_id, name_snapshot, billing_unit_snapshot, quantity,
  unit_price_snapshot, line_total, created_at)
select md5('servico6:' || n || ':' || k)::uuid, ('05000000-0000-4000-8000-000000000' || n)::uuid, null, nome, 'visit', 1,
       total, total, '2026-09-01 12:00-03'::timestamptz + make_interval(secs => k)
  from (values
    ('131', 1, 'Instalação 2x Carregador DC/DC 50A', 690),
    ('132', 1, 'Realocação do banco de baterias de lítio (8× 12V 100Ah)', 690),
    ('133', 1, 'REPARO DE CONVERSOR E CARREGADOR TECHNOMASTER', 2070),
    ('134', 1, 'SUBSTITUIÇÃO BATERIAS - CHUMBO PARA LITIO', 1035),
    ('135', 1, 'Barramento e proteções do sistema de corrente contínua', 2560),
    ('135', 2, 'Deslocamento técnico', 200),
    ('136', 1, 'Instalação do novo sistema elétrico LiFePO4/Usina', 2560),
    ('136', 2, 'Deslocamento técnico', 200),
    ('137', 1, 'Instalação e conversão do sistema de baterias de chumbo para lítio', 1380),
    ('138', 1, 'Posicionamento, alinhamento, base, coxins e fixação do gerador', 2400),
    ('139', 1, 'INSTALAÇÃO TÉCNICA DE PARELHA DE MOTORES MERCURY V8 300HP CMS', 7800),
    ('140', 1, 'DIAGNÓSTICO TÉCNICO NO LOCAL', 250),
    ('141', 1, 'Substituição da esteira porta-cabos do slide-out', 1380),
    ('142', 1, 'AJUSTE DE LIGAÇÃO ELÉTRICA DE CARREGADOR DE BATERIAS', 450),
    ('143', 1, 'Instalação e configuração do sistema', 600),
    ('144', 1, 'Substituição da Placa Controladora do Ar Condicionado', 900)
  ) as s(n, k, nome, total);

-- ── O que o dono disse (os dias) e o que foi dito ao cliente ────────────────────────────────────────────
-- A 141 não tem planejamento (só a duração sugerida). A 133: o dono disse 2 dias em 10/09 e, depois do check-in de 15/09,
-- disse 3 (17/09): a medida usa os 2 do início (o histórico do planejar, como o _agenda_aplicar_planejar grava).
insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, historico,
  prometido_tipo, prometido_de, prometido_ate, prometido_original_ate, prometido_em, prometido_fonte, prometido_primeiro_ate)
select ('05000000-0000-4000-8000-000000000' || n)::uuid, dias, fonte, em::timestamp at time zone 'America/Sao_Paulo',
       coalesce(hist, '[]')::jsonb, ptipo, pde::date, pate::date, porig::date,
       case when ptipo is not null then (pem::timestamp at time zone 'America/Sao_Paulo') end,
       case when ptipo is not null then pfonte end, pprim::date
  from (values
    ('131', 1, 'dono',   '2026-09-04 10:00', null, 'firme', '2026-09-08', '2026-09-08', '2026-09-08', '2026-09-04 10:00', 'dono', null),
    ('132', 1, 'aceita', '2026-09-05 10:00', null, 'firme', '2026-09-10', '2026-09-10', '2026-09-10', '2026-09-05 10:00', 'dono', null),
    ('133', 3, 'dono',   '2026-09-17 10:00',
     '[{"em": "2026-09-10", "autor": "aa000000-0000-4000-8000-000000000001", "trecho": "a do Caio são 2 dias",
        "antes": {"dias": null, "estimativa_fonte": null}, "depois": {"dias": 2, "estimativa_fonte": "dono"}},
       {"em": "2026-09-17", "autor": "aa000000-0000-4000-8000-000000000001", "trecho": "a do Caio vai dar 3 dias",
        "antes": {"dias": 2}, "depois": {"dias": 3}}]',
     'condicional', '2026-09-15', '2026-09-15', '2026-09-18', '2026-09-14 10:00', 'mensagem', null),
    ('134', 1, 'dono',   '2026-10-16 10:00', null, 'firme', '2026-10-20', '2026-10-20', '2026-10-21', '2026-10-19 17:00', 'mensagem', null),
    ('135', 2, 'dono',   '2026-10-16 10:00', null, 'faixa', '2026-10-20', '2026-10-21', '2026-10-21', '2026-10-20 17:00', 'mensagem', null),
    ('136', 2, 'dono',   '2026-10-22 10:00', null, 'condicional', '2026-10-26', '2026-10-26', '2026-10-30', '2026-10-22 10:00', 'mensagem', null),
    ('137', 1, 'dono',   '2026-10-22 10:00', null, 'condicional', '2026-10-26', '2026-10-26', '2026-10-26', '2026-10-23 10:00', 'mensagem', '2026-10-23'),
    ('138', 1, 'dono',   '2026-09-08 10:00', null, null, null, null, null, null, null, null),
    ('139', 1, 'dono',   '2026-09-08 10:00', null, null, null, null, null, null, null, null),
    ('140', 1, 'dono',   '2026-09-18 10:00', null, null, null, null, null, null, null, null),
    ('142', 1, 'dono',   '2026-09-21 10:00', null, null, null, null, null, null, null, null),
    ('143', 1, 'dono',   '2026-09-21 10:00', null, null, null, null, null, null, null, null),
    ('144', 1, 'dono',   '2026-09-25 10:00', null, null, null, null, null, null, null, null)
  ) as p(n, dias, fonte, em, hist, ptipo, pde, pate, porig, pem, pfonte, pprim);

-- Os avisos de atraso que saíram (M6, pode_atrasar), mandados de verdade (modo ligado, enviados).
insert into public.agenda_cliente_mensagens (id, client_id, service_order_id, tipo, variante, origem, dia_alvo, faixa_de, faixa_ate,
  prometido_tipo, modo, texto, base, enviar_em, valida_ate, aprovacao, estado, dedupe_key, enviada_em, criada_em)
select ('d6000000-0000-4000-8000-0000000006' || k)::uuid, ('c6000000-0000-4000-8000-000000000' || n)::uuid,
       ('05000000-0000-4000-8000-000000000' || n)::uuid, 'pode_atrasar', variante, 'rodada', fa::date, fd::date, fa::date,
       case when fa is not null then 'condicional' end, 'ligado', texto, '{}'::jsonb,
       quando::timestamp at time zone 'America/Sao_Paulo', (quando::timestamp + interval '9 hours') at time zone 'America/Sao_Paulo',
       'livre', 'enviada', format('agenda-cliente:pode_atrasar:05000000-0000-4000-8000-000000000%s:%s', n, coalesce(fa, 'sem_data')),
       (quando::timestamp + interval '30 seconds') at time zone 'America/Sao_Paulo',
       (quando::timestamp - interval '1 hour') at time zone 'America/Sao_Paulo'
  from (values
    ('31', '133', 'peca', '2026-09-15', '2026-09-15', '2026-09-14 10:00',
     'Caio, a peça chega amanhã: o serviço no seu motorhome fica para terça (15/09). Qualquer coisa, me avise.'),
    ('34', '134', 'execucao', '2026-10-20', '2026-10-20', '2026-10-19 17:00',
     'Davi, o serviço no seu motorhome vai até terça (20/10), de manhã. Qualquer coisa, me avise.'),
    ('35', '135', 'execucao', '2026-10-20', '2026-10-21', '2026-10-20 17:00',
     'Elisa, o serviço no seu motorhome deve terminar entre terça (20/10) e quarta (21/10). Qualquer coisa, me avise.'),
    ('36', '136', 'peca', '2026-10-26', '2026-10-26', '2026-10-22 10:00',
     'Fábio, a peça chegou: o serviço no seu motorhome fica para segunda (26/10). Qualquer coisa, me avise.'),
    ('37', '137', 'peca_sem_data', null, null, '2026-10-20 10:00',
     'Gil, quero te avisar com antecedência: ainda faltam peças sem data de chegada, então o serviço no seu motorhome, que estava para sexta (23/10), vai atrasar. Te digo a nova data assim que elas chegarem.'),
    ('38', '137', 'peca', '2026-10-26', '2026-10-26', '2026-10-23 10:00',
     'Gil, a peça chegou: o serviço no seu motorhome fica para segunda (26/10). Qualquer coisa, me avise.')
  ) as m(k, n, variante, fd, fa, quando, texto);

-- ── As diárias: as novas de outubro (Roberto e João) e as ligadas a cada OS ─────────────────────────────
-- As de setembro do Roberto e do Mickael são as da fixture de 23/10 (fração 1). A de 25/09 do Roberto fica SEM OS (a 143).
insert into public.work_shifts (id, work_profile_id, data, tipo, fracao, valor_diaria, origem, status,
                                registrado_por, aprovado_por, aprovado_em)
select md5('ws:' || perfil || ':' || dia)::uuid, perfil::uuid, dia::date, 'diaria', fracao, valor, 'painel', 'aprovado',
       'aa000000-0000-4000-8000-000000000001', 'aa000000-0000-4000-8000-000000000001', (dia || ' 20:00-03')::timestamptz
  from (values
    ('cc000000-0000-4000-8000-000000000002', '2026-10-19', 1, 180), ('cc000000-0000-4000-8000-000000000002', '2026-10-20', 1, 180),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-21', 1, 180), ('cc000000-0000-4000-8000-000000000002', '2026-10-22', 1, 180),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-23', 1, 180), ('cc000000-0000-4000-8000-000000000002', '2026-10-26', 1, 180),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-27', 1, 180), ('cc000000-0000-4000-8000-000000000002', '2026-10-28', 1, 180),
    ('cc000000-0000-4000-8000-000000000002', '2026-10-29', 1, 180),
    ('cc000000-0000-4000-8000-000000000003', '2026-10-21', 0.5, 150), ('cc000000-0000-4000-8000-000000000003', '2026-10-26', 1, 150),
    ('cc000000-0000-4000-8000-000000000003', '2026-10-27', 1, 150)
  ) as d(perfil, dia, fracao, valor);

insert into public.work_shift_os (shift_id, service_order_id)
select md5('ws:cc000000-0000-4000-8000-00000000000' || p || ':' || dia)::uuid, ('05000000-0000-4000-8000-000000000' || n)::uuid
  from (values
    ('2', '2026-09-08', '131'), ('2', '2026-09-09', '132'), ('2', '2026-09-10', '138'),
    ('2', '2026-09-11', '139'), ('4', '2026-09-14', '139'),
    ('2', '2026-09-15', '133'), ('2', '2026-09-16', '133'), ('2', '2026-09-17', '133'),
    ('2', '2026-09-23', '141'), ('2', '2026-09-24', '142'), ('2', '2026-09-28', '144'),
    ('2', '2026-10-19', '134'), ('2', '2026-10-20', '134'),
    ('2', '2026-10-20', '135'), ('2', '2026-10-21', '135'), ('2', '2026-10-22', '135'), ('2', '2026-10-23', '135'),
    ('3', '2026-10-21', '135'),
    ('2', '2026-10-26', '136'), ('2', '2026-10-27', '136'), ('2', '2026-10-28', '136'), ('2', '2026-10-29', '136'),
    ('3', '2026-10-26', '137'), ('3', '2026-10-27', '137')
  ) as l(p, dia, n);

-- ── O plano publicado de cada OS e a conferência de cada meio-dia ───────────────────────────────────────
-- Publicado na véspera às 16:30; o resultado dito no próprio dia às 17:30 (pelo "como foi hoje?").
insert into public.agenda_alocacoes (service_order_id, payee_id, dia, turno, presenca, tipo, estado, origem, publicada_em,
                                     resultado, motivo, resultado_via, resultado_em)
select ('05000000-0000-4000-8000-000000000' || n)::uuid, ('bb000000-0000-4000-8000-00000000000' || p)::uuid, dia::date, turno,
       'turno', tipo, 'publicada', 'motor', (dia::date - 1 + time '16:30') at time zone 'America/Sao_Paulo',
       resultado, motivo, 'dia_feito', (dia::date + time '17:30') at time zone 'America/Sao_Paulo'
  from (values
    ('131', '2', '2026-09-08', 'manha', 'execucao', 'cumprido', null), ('131', '2', '2026-09-08', 'tarde', 'execucao', 'cumprido', null),
    ('132', '2', '2026-09-09', 'manha', 'execucao', 'cumprido', null), ('132', '2', '2026-09-09', 'tarde', 'execucao', 'cumprido', null),
    ('138', '2', '2026-09-10', 'manha', 'execucao', 'cumprido', null), ('138', '2', '2026-09-10', 'tarde', 'execucao', 'cumprido', null),
    ('139', '2', '2026-09-11', 'manha', 'execucao', 'cumprido', null), ('139', '2', '2026-09-11', 'tarde', 'execucao', 'cumprido', null),
    ('139', '4', '2026-09-14', 'manha', 'execucao', 'cumprido', null),
    ('133', '2', '2026-09-15', 'manha', 'execucao', 'cumprido', null), ('133', '2', '2026-09-15', 'tarde', 'execucao', 'cumprido', null),
    ('133', '2', '2026-09-16', 'manha', 'execucao', 'cumprido', null), ('133', '2', '2026-09-16', 'tarde', 'execucao', 'cumprido', null),
    ('133', '2', '2026-09-17', 'manha', 'execucao', 'cumprido', null),
    ('140', '1', '2026-09-22', 'manha', 'diagnostico', 'cumprido', null), ('140', '1', '2026-09-22', 'tarde', 'diagnostico', 'cumprido', null),
    ('141', '2', '2026-09-23', 'manha', 'execucao', 'cumprido', null), ('141', '2', '2026-09-23', 'tarde', 'execucao', 'cumprido', null),
    ('142', '2', '2026-09-24', 'manha', 'execucao', 'cumprido', null), ('142', '2', '2026-09-24', 'tarde', 'execucao', 'sem_registro', null),
    ('143', '2', '2026-09-25', 'manha', 'execucao', 'cumprido', null), ('143', '2', '2026-09-25', 'tarde', 'execucao', 'cumprido', null),
    ('144', '2', '2026-09-28', 'manha', 'execucao', 'cumprido', null), ('144', '2', '2026-09-28', 'tarde', 'execucao', 'cumprido', null),
    ('134', '2', '2026-10-19', 'manha', 'execucao', 'cumprido', null), ('134', '2', '2026-10-19', 'tarde', 'execucao', 'cumprido', null),
    ('134', '2', '2026-10-20', 'manha', 'execucao', 'cumprido', null),
    ('135', '2', '2026-10-20', 'tarde', 'execucao', 'cumprido', null),
    ('135', '2', '2026-10-21', 'manha', 'execucao', 'cumprido', null), ('135', '2', '2026-10-21', 'tarde', 'execucao', 'cumprido', null),
    ('135', '3', '2026-10-21', 'manha', 'execucao', 'cumprido', null),
    ('135', '2', '2026-10-22', 'manha', 'execucao', 'cumprido', null), ('135', '2', '2026-10-22', 'tarde', 'execucao', 'cumprido', null),
    ('135', '2', '2026-10-23', 'manha', 'execucao', 'nao_cumprido', 'material'),
    ('135', '2', '2026-10-23', 'tarde', 'execucao', 'cumprido', null),
    ('136', '2', '2026-10-26', 'manha', 'execucao', 'cumprido', null), ('136', '2', '2026-10-26', 'tarde', 'execucao', 'cumprido', null),
    ('136', '2', '2026-10-27', 'manha', 'execucao', 'cumprido', null), ('136', '2', '2026-10-27', 'tarde', 'execucao', 'cumprido', null),
    ('136', '2', '2026-10-28', 'manha', 'execucao', 'cumprido', null), ('136', '2', '2026-10-28', 'tarde', 'execucao', 'cumprido', null),
    ('136', '2', '2026-10-29', 'manha', 'execucao', 'parcial', 'imprevisto_tecnico'),
    ('136', '2', '2026-10-29', 'tarde', 'execucao', 'parcial', 'imprevisto_tecnico'),
    ('137', '3', '2026-10-26', 'manha', 'execucao', 'cumprido', null), ('137', '3', '2026-10-26', 'tarde', 'execucao', 'cumprido', null)
  ) as a(n, p, dia, turno, tipo, resultado, motivo);

update public.agenda_config set versao_plano = (select versao_plano from _fase6_versao) where id;
select set_config('agenda.hoje', '', true);

-- ── Confere o estado de que os testes da Fase 6 partem ──────────────────────────────────────────────────
do $confere$
declare
  v_falta text;
begin
  v_falta := case
    when (select count(*) from public.service_orders so
           where so.service_order_number between 'OS-00131' and 'OS-00144' and so.status = 'completed') <> 14
      then 'as 14 OS concluídas da Fase 6 não estão lá'
    when (select count(*) from public.agenda_alocacoes a
           where a.service_order_id::text between '05000000-0000-4000-8000-000000000131' and '05000000-0000-4000-8000-000000000144'
             and a.estado = 'publicada') <> 45
      then 'as 45 alocações publicadas da Fase 6 não estão lá'
    when (select count(*) from public.work_shift_os wo
           where wo.service_order_id::text between '05000000-0000-4000-8000-000000000131' and '05000000-0000-4000-8000-000000000144') <> 24
      then 'as 24 diárias ligadas da Fase 6 não estão lá'
    when (select coalesce(sum(v.dias), 0) from public.v_dias_por_os_e_pessoa v
           where v.service_order_id::text between '05000000-0000-4000-8000-000000000131' and '05000000-0000-4000-8000-000000000137') <> 16.5
      then 'as 7 OS de energia não somam 16,5 diárias ligadas'
    when exists (select 1 from public.agenda_medidas_os)
      then 'agenda_medidas_os não começa vazia'
    when (select modo_aprendizado from public.agenda_config where id) <> 'desligado'
      then 'modo_aprendizado não está desligado'
  end;
  if v_falta is not null then
    raise exception 'fixture-fase6: %', v_falta;
  end if;
end
$confere$;

-- ── P2 (28/10): as idas do dono sem estar no plano (o insumo da presença aprendida) ─────────────────────
-- Três idas ditas pelo dono na conversa ("eu fui no Davi", manhã/tarde/dia) em 3 das 4 OS de energia em motorhome de outubro
-- (134 em 20/10, 135 em 22/10, 136 em 27/10) e uma "passou" da conferência na 137 (26/10), que não conta. A 1ª ida registrada
-- é a de 20/10: a presença conta as OS concluídas desde ela (134, 135, 136 e 137) → 3 de 4 → o dia todo (spec-fase6 §6.2).
insert into public.agenda_intervencoes_do_dono (service_order_id, dia, prevista, dita, classe, origem, trecho, criado_em)
select ('05000000-0000-4000-8000-000000000' || n)::uuid, dia::date, 'nenhuma', dita, 'execucao', origem, trecho,
       (dia::date + time '18:00') at time zone 'America/Sao_Paulo'
  from (values
    ('134', '2026-10-20', 'dia', 'conversa', 'hoje eu fiquei o dia todo no Davi'),
    ('135', '2026-10-22', 'manha', 'conversa', 'de manhã eu fui na Elisa'),
    ('136', '2026-10-27', 'tarde', 'conversa', 'à tarde eu fui no Fábio'),
    ('137', '2026-10-26', 'passou', 'conferencia', null)
  ) as i(n, dia, dita, origem, trecho);

do $confere_p2$
begin
  if (select count(*) from public.agenda_intervencoes_do_dono i
       where i.service_order_id::text between '05000000-0000-4000-8000-000000000131' and '05000000-0000-4000-8000-000000000144') <> 4
     or (select min(i.dia) from public.agenda_intervencoes_do_dono i) <> date '2026-10-20' then
    raise exception 'fixture-fase6 (P2): as 4 idas do dono (a 1ª em 20/10) não estão lá';
  end if;
end
$confere_p2$;
