-- Fixture da bancada da Agenda de Produção: o estado "PÓS-RODADA" de 23/10/2026, escrito À MÃO.
-- É o que o *grava* do áudio R01 da rodada de aprontar (spec §8.5) tem de deixar no banco — nada mais, nada menos.
-- Carregada DEPOIS de fixture-2310.sql (e das migrations até 20261024160600). NUNCA rodar em produção.
--
-- O áudio R01 (transcrito):
--   "Lenine dois dias com o Roberto, eu abro e fecho, o João ajuda à tarde. O compressor do Flávio chegou dia 14, tá
--    aqui, é um dia, eu e o Roberto. Do Nelson, Cerbo, Orion e os cabos tão aqui, o painel chega dia 3, são dois dias.
--    Vanderlei eu compro na Premel terça, são três dias com o Roberto. Giancarlo é só a primeira parte, baterias e
--    barramento, três dias, mas o motorhome só fica livre dia 3. Eu fico em campo de segunda a sexta; sexta à tarde,
--    escritório."
--
-- Quem usa:
--   · supabase/tests/agenda_fase1_rascunho.sql (C8): roda o R01 pelas RPCs + *grava* e compara as 4 tabelas
--     (os_planejamento, os_planejamento_equipe, os_material, agenda_disponibilidade) com o que este arquivo deixa;
--     o rodar.mjs passa o arquivo em agenda_teste.pos_rodada;
--   · os evals do P7 que começam "depois da rodada" (L05a: "a peça do Nelson chegou").
--
-- Nenhum número nem data que o dono não disse: "hoje" (23/10) só como o "desde" implícito de "tão aqui". O Nelson e o
-- Giancarlo ficam SEM equipe (ninguém foi dito); o Lenine fica sem "material conferido" (o dono não falou de peça).

-- ── 1. As linhas espelho do material das três OS do áudio (o *grava* sincroniza as mesmas antes de aplicar) ──────
select public.os_material_sincronizar(o.id, date '2026-10-23')
  from (values ('05000000-0000-4000-8000-000000000069'::uuid),
               ('05000000-0000-4000-8000-000000000104'::uuid),
               ('05000000-0000-4000-8000-000000000112'::uuid)) as o(id);

-- ── 2. Lenine (OS-00074): 2 dias, Roberto o dia todo e João à tarde; o dono abre e fecha ─────────────────────────
insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, trecho,
                                    atualizado_por)
values ('05000000-0000-4000-8000-000000000074', 2, 'dono', now(), 'abre_e_fecha',
        'Lenine dois dias com o Roberto, eu abro e fecho, o João ajuda à tarde.', 'aa000000-0000-4000-8000-000000000001');
insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values
  ('05000000-0000-4000-8000-000000000074', 'bb000000-0000-4000-8000-000000000002', 'dia'),
  ('05000000-0000-4000-8000-000000000074', 'bb000000-0000-4000-8000-000000000003', 'tarde');

-- ── 3. Flávio (OS-00104): o compressor (item da OC-00004) na mão desde 14/10; 1 dia, o dono e o Roberto ─────────
update public.os_material
   set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-10-14', fonte = 'dono',
       trecho = 'O compressor do Flávio chegou dia 14, tá aqui', atualizado_por = 'aa000000-0000-4000-8000-000000000001'
 where purchase_order_item_id = '71000000-0000-4000-8000-000000000001';
insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, trecho, atualizado_por)
values ('05000000-0000-4000-8000-000000000104', 1, 'dono', now(), 'é um dia, eu e o Roberto',
        'aa000000-0000-4000-8000-000000000001');
insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values
  ('05000000-0000-4000-8000-000000000104', 'bb000000-0000-4000-8000-000000000001', 'dia'),
  ('05000000-0000-4000-8000-000000000104', 'bb000000-0000-4000-8000-000000000002', 'dia');

-- ── 4. Nelson (OS-00112): Cerbo, Orion e o kit de cabos na mão (desde hoje); o painel chega ter 03/11 (o dono
--       disse: nível C); 2 dias, sem equipe ─────────────────────────────────────────────────────────────────────────
update public.os_material
   set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-10-23', fonte = 'dono',
       trecho = 'Do Nelson, Cerbo, Orion e os cabos tão aqui', atualizado_por = 'aa000000-0000-4000-8000-000000000001'
 where service_order_part_id in (md5('peca:112:1')::uuid,    -- KIT Cabos Comunicação e Energia para Lítio
                                 md5('peca:112:2')::uuid,    -- Central de controle Cerbo GX
                                 md5('peca:112:3')::uuid);   -- Orion-Tr Smart
update public.os_material
   set situacao = 'a_caminho', previsao_ate = date '2026-11-03', previsao_original = date '2026-11-03',
       previsao_fonte = 'dono', fonte = 'dono', trecho = 'o painel chega dia 3',
       atualizado_por = 'aa000000-0000-4000-8000-000000000001'
 where service_order_part_id = md5('peca:112:4')::uuid;      -- Painel Touch HBR 7"
insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, trecho, atualizado_por)
values ('05000000-0000-4000-8000-000000000112', 2, 'dono', now(), 'são dois dias', 'aa000000-0000-4000-8000-000000000001');

-- ── 5. Vanderlei (OS-00069): os 4 itens o dono compra na Premel ter 27/10; 3 dias com o Roberto ─────────────────
update public.os_material
   set situacao = 'falta', fonte = 'dono', fornecedor_id = 'dd000000-0000-4000-8000-000000000001',
       compra_prevista_em = date '2026-10-27', trecho = 'Vanderlei eu compro na Premel terça',
       atualizado_por = 'aa000000-0000-4000-8000-000000000001'
 where service_order_id = '05000000-0000-4000-8000-000000000069';
insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, trecho, atualizado_por)
values ('05000000-0000-4000-8000-000000000069', 3, 'dono', now(), 'são três dias com o Roberto',
        'aa000000-0000-4000-8000-000000000001');
insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values
  ('05000000-0000-4000-8000-000000000069', 'bb000000-0000-4000-8000-000000000002', 'dia');

-- ── 6. Giancarlo (OS-00100): só a primeira parte; 3 dias; o motorhome livre a partir de ter 03/11; sem equipe ────
insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, escopo_decidido,
                                    bem_indisponivel, trecho, atualizado_por)
values ('05000000-0000-4000-8000-000000000100', 3, 'dono', now(), 'só a primeira parte, baterias e barramento',
        '{[2026-10-23,2026-11-03)}',
        'Giancarlo é só a primeira parte, baterias e barramento, três dias, mas o motorhome só fica livre dia 3.',
        'aa000000-0000-4000-8000-000000000001');

-- ── 7. O dono: em campo de segunda a sexta; sexta à tarde, não (escritório) ─────────────────────────────────────
-- Ele não tinha padrão (a semente só mede a equipe): nada é substituído.
insert into public.agenda_disponibilidade (payee_id, dias_semana, turno, situacao, origem, nota, trecho, criado_por) values
  ('bb000000-0000-4000-8000-000000000001', '{1,2,3,4,5}', null, 'disponivel', 'dono', 'você disse em 23/10',
   'Eu fico em campo de segunda a sexta; sexta à tarde, escritório.', 'aa000000-0000-4000-8000-000000000001'),
  ('bb000000-0000-4000-8000-000000000001', '{5}', 'tarde', 'indisponivel', 'dono', 'você disse em 23/10',
   'Eu fico em campo de segunda a sexta; sexta à tarde, escritório.', 'aa000000-0000-4000-8000-000000000001');
