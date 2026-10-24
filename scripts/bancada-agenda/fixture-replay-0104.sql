-- Replay da OS-00104 (Flávio) na bancada da Agenda de Produção (Fase 2, P2): o estado de sex 02/10/2026, SINTÉTICO.
-- Roda POR CIMA de fixture-2310.sql, dentro do begin/rollback do teste (supabase/tests/agenda_fase2_motor.sql; o
-- rodar.mjs passa este arquivo em agenda_teste.replay_0104). NUNCA rodar em produção.
--
-- O que aconteceu de verdade: a OS-00104 foi marcada para ter 06 a qui 08/10 SEM o compressor na mão (a peça chegou
-- em 14/10) e a OS ficou "aguardando peças" até hoje. A pergunta do replay: com o motor, o que teria sido marcado em
-- sex 02/10? Esperado: nada de compromisso antes de qua 07/10 (comprando na sexta, o compressor chega ter 06 e a OS
-- fica pronta no dia útil seguinte), só uma reserva condicionada à compra ("comprando hoje" / "compre até"), e nada na
-- ter 06/10, o dia em que ela foi marcada.
--
-- O estado de 02/10:
--   · OS-00104 aberta (aprovada em 22/09, convertida em 23/09), sinal de R$ 2.070 pago; a janela real de 06–08/10 NÃO
--     está gravada (é o que se quer evitar);
--   · o dono disse: 1 dia, ele e o Roberto; nada mais a comprar além do compressor (material conferido em 01/10, o que
--     responde às linhas de texto livre — sem isso a OS esperaria "tem peça embutida?");
--   · o compressor "Compressor 12V SS65" falta, do fornecedor Mateus Honório. O cadastro real dele não tem cidade nem UF
--     (em produção o motor perguntaria "de quem e quando?" — o que também não marca nada); AQUI ele tem UF SC (classe
--     distribuidor_sc_pr, 2 dias úteis) para o replay calcular o "compre até";
--   · a OC-00004 (13/10) ainda não existia.

delete from public.purchase_order_items where id = '71000000-0000-4000-8000-000000000001';
delete from public.purchase_orders where id = '70000000-0000-4000-8000-000000000004';
update public.suppliers set state = 'SC' where id = 'dd000000-0000-4000-8000-000000000004';

update public.service_orders
   set status = 'open', scheduled_start_at = null, scheduled_end_at = null, updated_at = timestamptz '2026-10-01 18:00-03'
 where id = '05000000-0000-4000-8000-000000000104';

insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, material_conferido_em, trecho,
                                    atualizado_por)
values ('05000000-0000-4000-8000-000000000104', 1, 'dono', timestamptz '2026-10-01 18:00-03', timestamptz '2026-10-01 18:00-03',
        'o Flávio é um dia, eu e o Roberto; só falta o compressor, do Mateus', 'aa000000-0000-4000-8000-000000000001');
insert into public.os_planejamento_equipe (service_order_id, payee_id, turnos) values
  ('05000000-0000-4000-8000-000000000104', 'bb000000-0000-4000-8000-000000000001', 'dia'),
  ('05000000-0000-4000-8000-000000000104', 'bb000000-0000-4000-8000-000000000002', 'dia');
insert into public.os_material (id, service_order_id, origem, descricao, quantidade_necessaria, quantidade_na_mao, critico,
                                situacao, fonte, fornecedor_id, trecho, conferido_em, atualizado_por)
values ('a4000000-0000-4000-8000-000000000104', '05000000-0000-4000-8000-000000000104', 'dono', 'Compressor 12V SS65',
        1, 0, true, 'falta', 'dono', 'dd000000-0000-4000-8000-000000000004', 'só falta o compressor, do Mateus',
        timestamptz '2026-10-01 18:00-03', 'aa000000-0000-4000-8000-000000000001');
