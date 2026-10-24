-- Fixture da Fase 2 da Agenda de Produção: a carteira de qui 29/10/2026, SINTÉTICA.
-- = fixture-2310.sql (a carteira de 23/10) + fixture-2310-pos-rodada.sql (o *grava* do áudio R01) + o que o dono teria
-- respondido até qua 28/10. Roda dentro do begin/rollback do teste (o rodar.mjs passa este arquivo em
-- agenda_teste.fase2 e o pós-rodada em agenda_teste.pos_rodada, que este arquivo executa primeiro). NUNCA rodar em
-- produção. Usada pelo teste do motor (P2), pelas leituras e textos (P5) e pelos evals (P6: a vigia de qui 29/10 16:30
-- publica a semana de 03 a 06/11).
--
-- O que o dono respondeu de 24 a 28/10:
--   · Lenine (OS-00074) e Flávio (OS-00104): "não tem peça a comprar" (material conferido; responde também às peças
--     embutidas do Flávio);
--   · Vanderlei (OS-00069): os 4 itens chegaram da Premel em ter 27/10 (na mão);
--   · Giancarlo (OS-00100): a peça embutida foi respondida (nada a comprar); o motorhome só volta em qui 12/11 (fora até
--     11/11); dá para adiantar 1 dia no pátio (barramento e chicote);
--   · Nelson (OS-00112): o painel continua "chega ter 03/11" (o dono disse); o cliente precisa dele até qui 05/11;
--   · Rodrigo (OS-00096): meio dia de diagnóstico, você o tempo todo; nada a comprar.
-- O resto como no pós-rodada: o dono em campo de seg a sex (sexta à tarde não); a equipe pela semente das diárias.

do $fase2$
begin
  if coalesce(current_setting('agenda_teste.pos_rodada', true), '') = '' then
    raise exception 'fixture-fase2: falta agenda_teste.pos_rodada (rode pela bancada: scripts/bancada-agenda/rodar.mjs)';
  end if;
  execute current_setting('agenda_teste.pos_rodada');
end
$fase2$;

update public.os_planejamento
   set material_conferido_em = timestamptz '2026-10-28 18:00-03'
 where service_order_id in ('05000000-0000-4000-8000-000000000074', '05000000-0000-4000-8000-000000000104',
                            '05000000-0000-4000-8000-000000000100');

update public.os_material
   set situacao = 'na_mao', quantidade_na_mao = quantidade_necessaria, chegou_em = date '2026-10-27', compra_prevista_em = null,
       fonte = 'dono', trecho = 'o material do Vanderlei chegou da Premel', conferido_em = timestamptz '2026-10-27 18:00-03'
 where service_order_id = '05000000-0000-4000-8000-000000000069';

update public.os_planejamento
   set bem_indisponivel = '{[2026-10-23,2026-11-12)}', adiantavel_patio_dias = 1,
       trecho = 'o motorhome do Giancarlo só volta dia 12; dá para adiantar um dia no pátio'
 where service_order_id = '05000000-0000-4000-8000-000000000100';

update public.os_planejamento
   set precisa_ate = date '2026-11-05', trecho = 'o Nelson precisa do barco até quinta, dia 5'
 where service_order_id = '05000000-0000-4000-8000-000000000112';

insert into public.os_planejamento (service_order_id, dias, estimativa_fonte, estimativa_em, dono_presenca, material_conferido_em,
                                    trecho, atualizado_por)
values ('05000000-0000-4000-8000-000000000096', 0.5, 'dono', timestamptz '2026-10-28 18:00-03', 'sempre',
        timestamptz '2026-10-28 18:00-03', 'o Rodrigo é meio dia, eu vou; não tem peça', 'aa000000-0000-4000-8000-000000000001');
