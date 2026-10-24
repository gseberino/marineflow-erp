-- Fixture da Fase 3 da Agenda de Produção: a carteira de qui 29/10/2026 com a semana de 03 a 06/11 PUBLICADA, SINTÉTICA.
-- = fixture-fase2.sql (que executa o pós-rodada da Fase 1 por dentro) + o que a execução precisa. Roda dentro do
-- begin/rollback do teste (o rodar.mjs passa este arquivo em agenda_teste.fase3 e os da Fase 2 nos seus nomes). NUNCA
-- rodar em produção. Usada pela conclusão (P2), pela rotina da equipe e pela diária (P4), pela comissão (P5) e pelo
-- acompanhamento (P6). Ids novos com o prefixo d3000000 (livre nas fixtures e nos testes em 24/10).
--
-- O que este arquivo acrescenta, nesta ordem (o dado primeiro: a publicação já sai com ele):
--   · perfis de diária: Roberto R$ 180 e João R$ 150 (o Mickael fica nos R$ 200 da fixture de 23/10). Só o valor do
--     perfil muda; as diárias lançadas guardam o valor delas (200), como em produção;
--   · telefone sintético só do Roberto (5547900000001); o João segue sem telefone (como em produção) e o Mickael também;
--   · agenda_equipe_contato: o Roberto recebe a rotina, pela regra (o que a migration de dado 20261026101000 semeia);
--   · condições de pagamento (presets com os rótulos e as parcelas dos de produção, SELECT de 24/10):
--       - Lenine (OS-00074): "50% de sinal + 50% na entrega" (Entrada 50% na aprovação, Saldo 50% na entrega) e SEM
--         sinal pago — o sinal de R$ 2.280 da fixture de 23/10 sai. Na conclusão, as duas parcelas nascem (a regra da
--         tela: nenhum recebível vivo → o plano inteiro da condição);
--       - Vanderlei (OS-00069): "50% mão de obra + 100% materiais antecipados", com o sinal pago (R$ 4.500, da fixture
--         de 23/10) e o saldo na entrega pendente (R$ 2.800 = 50% dos R$ 5.600 de serviço, due_on_completion, com a
--         cobrança em collections, como o register_deposit_and_convert grava). Na conclusão nada nasce (já há
--         recebível vivo) e o gatilho do vencimento põe o saldo para o dia da saída;
--       - as duas com mão de obra e peças preenchidas (labor_cost_total, parts_cost_total), que é de onde a conta das
--         parcelas parte (depositBaseFromOrder);
--   · um acerto FECHADO do João em outubro: nº 1, de 29/09 a 17/10 (as 8 diárias dele até a última lançada, a R$ 200),
--     fechado seg 19/10. A trava trg_dia_em_acerto_fechado (20261006220000) recusa mexer em dia desse período;
--   · a publicação: modo_proposta e modo_vigia ligados e a vigia de qui 29/10 às 16:30 publica a semana de 03 a 06/11
--     (o Nelson, que não cabe até qui 05/11, fica com a pergunta crítica aberta). O arquivo para com erro se não
--     publicar. As linhas da publicação, como a vigia as escreveu na bancada em 24/10 (sem o sinal, o Lenine perde a
--     vez para o Flávio e passa para sex 06 a ter 10/11):
--       "Vanderlei (OS-00069): ter 03 a qui 05/11, você abre e fecha, Roberto os 3 dias."
--       "Flávio (OS-00104): ter 03 e qua 04/11, você, João os 2 dias."
--       "Rodrigo (OS-00096): qua 04/11, você."
--       "Lenine (OS-00074): sex 06 a ter 10/11, você abre e fecha, João (sex 06 e ter 10/11), Roberto (seg 09 e ter 10/11)."
--     e a pergunta crítica aberta "Não cabe tudo até qui 05/11. Qual aceita atrasar? 1) Nelson (OS-00112) atrasa: …".
--     Quem fixar uma célula deste plano num teste confere antes contra agenda_alocacoes (o motor é quem decide).
-- Os modos ao fim: proposta e vigia LIGADOS (o publicado só existe em ligado); equipe e diária como a linha nasce na
-- bancada (desligado): cada teste liga o que precisa.

do $fase3$
begin
  if coalesce(current_setting('agenda_teste.fase2', true), '') = '' then
    raise exception 'fixture-fase3: falta agenda_teste.fase2 (rode pela bancada: scripts/bancada-agenda/rodar.mjs)';
  end if;
  execute current_setting('agenda_teste.fase2');
end
$fase3$;

-- ── A equipe ────────────────────────────────────────────────────────────────────────────────────────────
update public.work_profiles set valor_diaria = 180 where id = 'cc000000-0000-4000-8000-000000000002';   -- Roberto
update public.work_profiles set valor_diaria = 150 where id = 'cc000000-0000-4000-8000-000000000003';   -- João

update public.payees set phone = '5547900000001' where id = 'bb000000-0000-4000-8000-000000000002';      -- Roberto

insert into public.agenda_equipe_contato (payee_id, recebe_rotina, incluido_por, incluido_em)
values ('bb000000-0000-4000-8000-000000000002', true, 'regra', timestamptz '2026-10-24 12:00-03');

-- ── As condições de pagamento ───────────────────────────────────────────────────────────────────────────
insert into public.payment_condition_presets (id, label, sort_order, active, installments) values
  ('d3000000-0000-4000-8000-000000000001', '50% de sinal + 50% na entrega', 2, true,
   '[{"label":"Entrada 50%","tipo":"aprovacao","services_pct":50,"parts_pct":50,"expenses_pct":50,"days_after_approval":0},
     {"label":"Saldo 50%","tipo":"entrega","services_pct":50,"parts_pct":50,"expenses_pct":50,"days_after_approval":0}]'),
  ('d3000000-0000-4000-8000-000000000002', '50% mão de obra + 100% materiais antecipados', 3, true,
   '[{"label":"Sinal","tipo":"aprovacao","services_pct":50,"parts_pct":100,"expenses_pct":100,"days_after_approval":0},
     {"label":"Saldo","tipo":"entrega","services_pct":50,"parts_pct":0,"expenses_pct":0,"days_after_approval":0}]');

-- Lenine: a condição, a mão de obra (2.400 + 2.160 de serviço, nenhuma peça) e nenhum sinal.
update public.service_orders
   set payment_condition_preset_id = 'd3000000-0000-4000-8000-000000000001', labor_cost_total = 4560, parts_cost_total = 0
 where id = '05000000-0000-4000-8000-000000000074';
delete from public.receivables where id = md5('sinal:74')::uuid;

-- Vanderlei: a condição, mão de obra 5.600 e peças 2.005,40 (= os 7.605,40 da OS), o sinal pago (fica) e o saldo na
-- entrega, com a cobrança dele.
update public.service_orders
   set payment_condition_preset_id = 'd3000000-0000-4000-8000-000000000002', labor_cost_total = 5600, parts_cost_total = 2005.40
 where id = '05000000-0000-4000-8000-000000000069';
insert into public.receivables (id, client_id, service_order_id, description, issue_date, due_date, amount, status,
                                paid_amount, balance_amount, is_deposit, due_on_completion)
values ('d3000000-0000-4000-8000-000000000011', 'c1000000-0000-4000-8000-000000000001', '05000000-0000-4000-8000-000000000069',
        'Saldo — OS-00069', date '2026-07-29', date '2026-07-29', 2800, 'pending', 0, 2800, false, true);
insert into public.collections (id, service_order_id, receivable_id, client_id, amount, due_date, status, description)
values ('d3000000-0000-4000-8000-000000000012', '05000000-0000-4000-8000-000000000069', 'd3000000-0000-4000-8000-000000000011',
        'c1000000-0000-4000-8000-000000000001', 2800, date '2026-07-29', 'pending', 'Saldo');

-- ── O acerto fechado do João (outubro) ──────────────────────────────────────────────────────────────────
-- 29/09, 30/09 e 01/10 inteiras; falta em 05/10; meias de 06 a 09/10 e em 14 e 15/10; 16 e 17/10 inteiras = 8 diárias.
-- O número é fixo (a sequência não volta no rollback; o texto da trava diz "acerto nº 0001").
insert into public.acertos_diarias (id, numero, favorecido_id, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo,
                                    valor_do_acerto, status, criado_por, criado_em)
values ('d3000000-0000-4000-8000-000000000021', 1, 'bb000000-0000-4000-8000-000000000003', date '2026-09-29', date '2026-10-17',
        0, 8, 1600, 0, 1600, 'fechado', 'aa000000-0000-4000-8000-000000000001', timestamptz '2026-10-19 18:00-03');
select setval('public.recibo_diarias_seq', 1, true);

-- ── A publicação da semana de 03 a 06/11 ────────────────────────────────────────────────────────────────
update public.agenda_config set modo_proposta = 'ligado', modo_vigia = 'ligado' where id;

do $publica$
declare
  r jsonb := public.agenda_vigiar(date '2026-10-29', timestamptz '2026-10-29 16:30-03');
begin
  if not coalesce((r #>> '{contagens,publicacao,publicou}')::boolean, false) then
    raise exception 'fixture-fase3: a vigia de qui 29/10 16:30 não publicou a semana: %', r -> 'contagens' -> 'publicacao';
  end if;
end
$publica$;
