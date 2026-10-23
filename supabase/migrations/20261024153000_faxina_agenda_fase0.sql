-- Agenda de Produção, Fase 0 — faxina dos dados velhos (decisão d02 do dono, 23/10/2026: "pode arquivar e
-- fechar como recomendado; a OS-00096 e o ORÇ-00083 você me pergunta na conversa").
-- Spec: scratchpad agenda-pesquisa/spec-fase0.md, pacote P6.
--
-- ═══ GRAVA DADO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
-- NÃO APLICADA. Este arquivo existe para revisão e espera o OK do dono.
--
-- POR QUE: dado zumbi faz a primeira resposta de agenda sair errada. A única pergunta de agenda feita ao
-- assistente até hoje ("Algum serviço agendado para hoje?", 05/10) listou tarefas de OS já concluídas.
--
-- O QUE MUDA (conferido por SELECT em 23/10/2026; reconferir no dia com a prova abaixo):
--   1. COT-00001 a COT-00005 (abertas desde 23/07 e 17/08, 0 envios, 0 respostas) → status 'cancelled'
--      (o CHECK chk_qr_status só aceita open/closed/cancelled; "arquivar" = cancelled com a nota). Os itens
--      ficam como estão. As 5 tarefas R18 "Enviar a cotação COT-0000x" → 'done' com a nota.
--   2. OC-00001 (sent desde 31/07; a OS-00073 dela está faturada; 0 de 2 itens recebidos pelo sistema) →
--      'cancelled' com a nota. Não vira 'received': isso repetiria a "OC recebida que não recebeu nada"
--      (incidente corrigido em 29/08). A tarefa R7 "Cobrar entrega da OC OC-00001" → 'done'.
--   3. As 22 tarefas manuais (source 'ai') criadas de 28/07 a 16/08, nenhuma mexida desde → 'cancelled'
--      com a nota de arquivamento. Arquivar não apaga: continuam consultáveis (Concluídas não as lista).
--   4. As 13 tarefas do motor (cobranças R3/R4 e contas R5) presas no usuário "Usuário Demo (UI v2)"
--      (cargo financial, que o dono não usa) → passam para o admin (Gustavo). São títulos de dinheiro
--      vivos: fechar esconderia cobrança real. Os lembretes delas já foram todos enviados (sent_at
--      preenchido), então a troca não dispara aviso nenhum.
--   5. payees "Gustavo Seberino da Silva" (sócio) ganha app_user_id = o admin. É o vínculo pessoa↔login que a
--      agenda usa (plano §3.1). _comprovante_socio e acharSocio já escolhiam esse sócio (único ativo).
--
-- FORA DAQUI (de propósito): OS-00096 e ORÇ-00083 (conversa com o dono); as compras da OS-00104 e da
-- OS-00112 (rodada de aprontar da Fase 1); as "16 diárias esperando sim" (não existem: 10 expiraram em
-- 29/09); Mickael fora da equipe (agenda_disponibilidade, Fase 1); desativar o "Usuário Demo (UI v2)"
-- (pergunta ao dono: é acesso, não faxina).
--
-- IDEMPOTENTE: cada UPDATE confere o id E o estado de antes; rodar de novo não muda nada. O que o dono já
-- tiver mexido na tela neste meio-tempo fica como ele deixou.
--
-- PROVA (só leitura): scratchpad agenda-pesquisa/sql/f20_faxina_prova.sql
--   antes (23/10): cot_abertas 5 · r18_vivas 5 · oc1_aberta 1 · r7_oc1_viva 1 · manuais_vivas 22 ·
--                  demo_vivas 13 · admin_vivas 35 · socio_sem_login 1 · vivas_total 48
--   depois:        0 · 0 · 0 · 0 · 0 · 0 · 20 · 0 · 20
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261024153000_faxina_agenda_fase0.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024153000', 'faxina_agenda_fase0');"
--
-- DESFAZER (um item ou todos):
--   update public.quote_requests set status = 'open', closed_at = null
--    where status = 'cancelled' and notes like '%[faxina Fase 0 da Agenda]%';
--   update public.purchase_orders set status = 'sent'
--    where po_number = 'OC-00001' and status = 'cancelled' and notes like '%[faxina Fase 0 da Agenda]%';
--   update public.agenda_tasks set status = 'pending', completed_at = null
--    where notes like '%[faxina Fase 0 da Agenda]%' and status in ('done', 'cancelled');
--   update public.agenda_tasks set assignee_user_id = '05684333-44d3-4cac-b361-4c1067b5b7a4'
--    where notes like '%[faxina Fase 0 da Agenda] Trazida%';
--   update public.payees set app_user_id = null where id = 'ea2cdf81-15d1-4054-84d2-ca2944531fc8';

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. As 5 cotações nunca enviadas e as 5 tarefas R18 delas
-- ---------------------------------------------------------------------------------------------
update public.quote_requests
   set status = 'cancelled',
       closed_at = now(),
       notes = concat_ws(E'\n', notes,
         '[faxina Fase 0 da Agenda] Arquivada: aberta desde ' || to_char(created_at at time zone 'America/Sao_Paulo', 'DD/MM')
         || ', nunca enviada a nenhum fornecedor. Para reabrir: status = open.')
 where id in (
   '1f931368-c080-4203-befe-be5efab29203',  -- COT-00001 (ORÇ-00066)
   '403a67b0-e43a-4897-b8ed-83b7c7ddc83f',  -- COT-00002 (sem OS)
   'e9f1e60d-5c7c-452b-89a6-da3b479b45ee',  -- COT-00003 (ORÇ-00066)
   'c7526347-3b71-4869-ae06-eefaa6d0e8d2',  -- COT-00004 (ORÇ-00080)
   'adc0c3d6-b348-4c4a-b225-0703be3cd2fe'   -- COT-00005 (sem OS)
 )
   and status = 'open'
   and not exists (select 1 from public.quote_request_sends s where s.quote_request_id = quote_requests.id);

update public.agenda_tasks
   set status = 'done',
       completed_at = now(),
       notes = concat_ws(E'\n', notes, '[faxina Fase 0 da Agenda] Resolvido: a cotação foi arquivada sem envio.')
 where id in (
   '96f17891-1b65-4c1d-b13a-f75b687f4311',  -- R18 COT-00001
   '0b2a7cb1-d931-42ba-a8dd-2d910bb1cc2c',  -- R18 COT-00002
   '6b88848d-da66-42e1-bda6-76677b4ca5e9',  -- R18 COT-00003
   'a4d72a37-2f8d-4110-93c8-49caead74d52',  -- R18 COT-00004
   'a75ba34f-9f4c-4dea-95b5-b6343dd42ac3'   -- R18 COT-00005
 )
   and automation_key like 'r18:quote:%'
   and status in ('pending', 'in_progress')
   and exists (select 1 from public.quote_requests q
                where q.id = agenda_tasks.related_entity_id and q.status <> 'open');

-- ---------------------------------------------------------------------------------------------
-- 2. A OC-00001 (compra entregue por fora em 04/08; a OS-00073 está faturada) e a tarefa R7 dela
-- ---------------------------------------------------------------------------------------------
update public.purchase_orders
   set status = 'cancelled',
       notes = concat_ws(E'\n', notes,
         '[faxina Fase 0 da Agenda] Fechada sem entrada no sistema: a compra chegou por fora (a OS-00073 foi '
         || 'faturada). Não é "recebida" porque nada foi recebido pela OC. Para reabrir: status = sent.')
 where id = '121e9ddc-859a-491e-a855-7360ba4b7717'  -- OC-00001
   and status in ('sent', 'partial', 'draft')
   and coalesce((select sum(i.received_qty) from public.purchase_order_items i
                  where i.purchase_order_id = purchase_orders.id), 0) = 0;

update public.agenda_tasks
   set status = 'done',
       completed_at = now(),
       notes = concat_ws(E'\n', notes, '[faxina Fase 0 da Agenda] Resolvido: a OC foi fechada (a OS dela está faturada).')
 where id = '7056d14e-8c05-4012-a50b-1c6504b46efa'  -- R7 OC-00001
   and automation_key = 'r7:po:121e9ddc-859a-491e-a855-7360ba4b7717'
   and status in ('pending', 'in_progress')
   and exists (select 1 from public.purchase_orders p
                where p.id = '121e9ddc-859a-491e-a855-7360ba4b7717' and p.status in ('received', 'cancelled'));

-- ---------------------------------------------------------------------------------------------
-- 3. As 22 tarefas manuais de julho e agosto
-- ---------------------------------------------------------------------------------------------
update public.agenda_tasks
   set status = 'cancelled',
       notes = concat_ws(E'\n', notes,
         '[faxina Fase 0 da Agenda] Arquivada: tarefa de ' || to_char(created_at at time zone 'America/Sao_Paulo', 'DD/MM')
         || ' sem nenhuma mudança desde então. Para reabrir: status = pending.')
 where id in (
   '76a39c25-2328-4aae-abe1-1deea82305e2',  -- Acompanhar chegada de baterias do fornecedor (60 dias)
   'b80c150c-aabc-4003-964d-ad0cb0d7759a',  -- Preparar tudo para ir à oficina arrumar o barco
   'f76f8ec1-f5dc-4ee8-b99c-c5f0e71951a7',  -- DONNA V - Entrega de itens faltantes Victron + Empirbus
   '1781ec32-9926-4f59-968e-ea89a89db238',  -- Documento de transferência de endereço com o contador
   '0260028c-edfb-4ea1-959a-ecb3261fa40c',  -- Verificar situação do fogão do cliente
   '4f0bf1cd-0e85-496d-ae18-f379f9c1b066',  -- Cobrar João Luiz Hang - saldo R$ 1.710,00 (repete R3/R4 vivas)
   '85772fd2-33ed-412c-9f1e-fb45e69a4dcd',  -- Ligar para cliente sobre estabilizador
   'b8c40c28-f5ab-42dc-a304-5cc736e10ea9',  -- Inversor do motorhome da MP Motor Homes
   'aa081c22-ba26-4478-8691-14ea643d3005',  -- Luz de freio da S10 (Hamilton)
   'aeb4ef7d-f5a6-4f8f-bac4-15f651414795',  -- Tributação para ativar NFS-e
   '8e06b50c-acdf-461e-9158-3a8d7c34a43b',  -- Marcar as caixas conforme instruções do Brocca
   '65f50cc5-2b4b-4ac7-8277-4e2860fc5a2d',  -- Diagnosticar OS-00060 (concluída em 13/08)
   '7746d909-5e20-4452-b30e-dbcb719f06ca',  -- NF do fogão para Charline
   'aaa2fa08-a20c-45b8-93a9-8a3b096241af',  -- Extratos de 2026 para a SR Contabilidade
   'e7abccf7-c5c1-48c5-b0ec-806573ec4cfa',  -- Orçamento Starlink do Rodrigo (virou OS-00076)
   '8acbcd63-90a3-4e09-ac06-d23c13fd13e0',  -- Data do aluguel com Adrian
   '04c67c8c-7ffc-4480-821e-bcd94a59c4d3',  -- Orçamento de lítio do camper
   '5215adc7-98bc-46e1-a1d1-e50e7867cc5a',  -- Orçamento de lítio ao Nelson (virou OS-00112)
   'a94de8bd-7002-4adf-819c-96ae24130a09',  -- Confirmar ida à locação (14/08)
   '0837e0c1-cd34-4fc9-80d8-578336fe2cb4',  -- Pró-labore, INSS e honorários de 07/2026
   '2039ece5-1d53-4d61-8ca6-c6af922f69ef',  -- Cálculo das lâmpadas para carregar bateria
   '59d32989-abdb-4424-87c3-f6861e0ee310'   -- Resposta ao Vanderlei
 )
   and source = 'ai'
   and automation_key is null
   and status in ('pending', 'in_progress')
   and created_at < '2026-08-17'
   and updated_at < '2026-09-01';

-- ---------------------------------------------------------------------------------------------
-- 4. As 13 tarefas de dinheiro presas no usuário que o dono não usa → admin
-- ---------------------------------------------------------------------------------------------
update public.agenda_tasks
   set assignee_user_id = 'ece63ee6-4036-4167-91ba-80226388b534',  -- Gustavo (admin, ativo)
       notes = concat_ws(E'\n', notes,
         '[faxina Fase 0 da Agenda] Trazida para você: estava no usuário "Usuário Demo (UI v2)", que não é usado.')
 where id in (
   'ec3b6423-3f6e-4a79-81f5-cea41572689d',  -- R4 Lírio R$ 756,00
   'e2967e7e-da0f-4ef6-952d-171d1f354c68',  -- R4 MP MOTOR HOMES R$ 1.650,00
   'be9f211b-1653-4e40-aeab-96bcf87a9a81',  -- R4 João Luiz Hang R$ 1.710,00
   '4e7c725e-97e1-4e4a-911b-6d0fdcc6eb9a',  -- R5 R$ 550,00
   '89194ef5-627d-41f1-b407-f0e589b81f2b',  -- R5 R$ 500,00
   '6c916c70-6801-405f-b636-75ac80ec2296',  -- R5 R$ 250,00 (01/10)
   '64786dc7-94b2-415a-922f-1571ab7a9693',  -- R5 R$ 250,00 (09/10)
   'db90188b-6abc-4ea9-81cd-9ce96ff26920',  -- R3 APOLO R$ 5.237,99
   '4fbbf367-441b-4480-8b97-39d8db95f4da',  -- R3 João Luiz Hang R$ 1.710,00
   '058c8b3d-6163-4814-9583-f42d75927471',  -- R3 Marcelo Marco Bertoldi R$ 16.890,00
   'dd587c73-ee87-41b2-9cf2-325c5e5a8d0d',  -- R4 Marcelo Marco Bertoldi R$ 16.890,00
   '50d07f96-cf62-47bc-b9bb-54874477728b',  -- R5 TSD LOGISTICA R$ 785,07
   '05feaf41-0441-4099-becc-d5dbaad66424'   -- R4 APOLO R$ 5.237,99
 )
   and assignee_user_id = '05684333-44d3-4cac-b361-4c1067b5b7a4'  -- "Usuário Demo (UI v2)"
   and status in ('pending', 'in_progress');

-- ---------------------------------------------------------------------------------------------
-- 5. O sócio ganha o login dele (pessoa da agenda = payees; plano §3.1)
-- ---------------------------------------------------------------------------------------------
update public.payees
   set app_user_id = 'ece63ee6-4036-4167-91ba-80226388b534'
 where id = 'ea2cdf81-15d1-4054-84d2-ca2944531fc8'  -- Gustavo Seberino da Silva (socio)
   and kind = 'socio'
   and app_user_id is null
   and not exists (select 1 from public.payees o where o.app_user_id = 'ece63ee6-4036-4167-91ba-80226388b534');

commit;
