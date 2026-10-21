-- Papelada do financeiro (20/10/2026), item B1: as regras que o aprendiz sugeriu e que não alcançariam nada
-- vão para "guardadas". Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-papelada-fix.md (B1).
--
-- ═══ GRAVA DADO — OK NOMEADO ═══ (só dado; nenhuma função, tabela, policy ou cron)
--
-- O QUE MUDA: 88 das 103 regras sugeridas (finance_rules origin='ai', status='proposed', todas nascidas na mesma
-- rodada de 08/10/2026 09:30) passam a status 'rejected' com a nota "Arquivada em 20/10/2026 …". Ficam como
-- sugestão as 15 que alcançariam alguma saída do extrato dos últimos 90 dias.
--
-- POR QUE 'rejected' (e não um status novo): o CHECK finance_rules_status_check só aceita active, paused,
-- proposed e rejected. 'paused' NÃO serve: o aprendiz (sugerirRegras, _shared/banking/proposals.ts) só deixa de
-- propor de novo o alvo que tem regra active/proposed/rejected — uma pausada voltaria amanhã como sugestão nova
-- (teste "não insiste em regra que já existe ou que foi recusada", src/test/banking-proposals.test.ts). A nota
-- diz que foi arquivamento, não recusa do dono. A tela de regras não lista 'rejected': some da contagem
-- ("103 regras sugeridas" vira 15) e do resumo.
--
-- COMO FOI MEDIDO (produção, SELECT, 20/10/2026; janela de 90 dias = saídas desde 22/07/2026):
--   * "alcança" = o mesmo teste do motor (acharRegra): regra por NOME casa o nome da contraparte normalizado
--     (normalizeText) igual ao da regra; regra por FORNECEDOR casa pelo documento (ou a raiz do CNPJ) ou pelo
--     nome igual ao do cadastro ativo;
--   * FICAM 15 (8 por nome, 7 por fornecedor): alcançariam ao menos uma saída nos 90 dias;
--   * ARQUIVADAS 70 paradas (62 por nome, 8 por fornecedor): nenhuma saída do alvo em 90 dias;
--   * ARQUIVADAS 18 "alvo vivo, regra que nunca casa" (por nome): o alvo aparece nos 90 dias só na DESCRIÇÃO do
--     extrato (ex.: "PGTO FAT CARTAO C6", "JUROS LIMITE CONTA") — o aprendiz montou a regra pelo supplier_name da
--     despesa, que é a descrição, mas o motor compara o nome da contraparte, que nessas linhas vem vazio. Aceitas
--     como estão, não classificariam nada. (O conserto do aprendiz é outro passo.)
--
-- IDEMPOTENTE: só toca a regra que ainda está 'proposed', origin 'ai' e nasceu naquela rodada; rodar de novo não
-- muda nada. A regra que o dono já aceitou ou recusou na tela neste meio-tempo fica como ele deixou.
--
-- DESFAZER (uma regra ou todas): volta a ser sugestão, sem perder nada (o índice único das ativas/propostas não
-- conflita: o aprendiz não propõe alvo arquivado).
--   update public.finance_rules set status = 'proposed', note = null
--    where status = 'rejected' and note like 'Arquivada em 20/10/2026%' [and id = '…'];

-- ---------------------------------------------------------------------------------------------
-- 1. As 18 de alvo vivo cuja regra nunca casa (o nome da contraparte vem vazio nas linhas do alvo)
-- ---------------------------------------------------------------------------------------------
update public.finance_rules
   set status = 'rejected',
       note = 'Arquivada em 20/10/2026 (papelada): o alvo aparece nos últimos 90 dias só na descrição do extrato, e a '
           || 'regra por nome compara o nome da contraparte, que nessas linhas vem vazio — como está, não classificaria '
           || 'nada. Não foi recusa sua: para voltar a ser sugestão, status = proposed.',
       updated_at = now()
 where id in (
   '0cea844e-1334-438c-9615-f8d594876bf1', '16af6051-5651-416b-a281-fe401a367057', '1752cbee-99d0-4bf1-a9c5-6e4960aa13f6',
   '1ba0987e-ef09-4351-9869-a69758d7ffc3', '26f4c304-a864-45d2-9e26-1a21afbfb535', '400f9397-cc24-4a9d-b31e-c1b7da666801',
   '5bd88f1c-2fb3-4640-afba-e98c2c547e33', '6229d52f-bb88-44ef-a441-80d1d168f043', '6f57006b-711a-4183-96e4-050670c4ac7e',
   '838e4780-28d4-4fc6-b4e5-7667ef158305', '8e7afa13-dd81-41e2-8ad4-0e3382d6496b', 'a4b0b15e-f1ec-420c-b4ec-2957c7c7fbe1',
   'b16db9b8-b0ae-4c55-8616-3d0853496646', 'bd081137-c0ac-40e2-942c-9e7efb2d9f6a', 'd45fac1f-40bd-46cb-8cb7-856cf647ee41',
   'd7a645d2-d85d-4e6e-896a-913e5d4f4fe1', 'e3e4a0b7-a729-4c20-b00a-c60e78a90777', 'f377fcf8-b06b-4ba6-96f9-bb3a477234f8'
 )
   and status = 'proposed' and origin = 'ai'
   and created_at >= '2026-10-08 09:30:00+00' and created_at < '2026-10-08 09:31:00+00';

-- ---------------------------------------------------------------------------------------------
-- 2. As 70 paradas: nenhuma saída do alvo nos últimos 90 dias
-- ---------------------------------------------------------------------------------------------
update public.finance_rules
   set status = 'rejected',
       note = 'Arquivada em 20/10/2026 (papelada): nenhuma saída deste alvo nos 90 dias até 20/10/2026. '
           || 'Não foi recusa sua: para voltar a ser sugestão, status = proposed.',
       updated_at = now()
 where id in (
   -- por nome (62)
   '04ea421b-f7ee-4580-9ba2-9c211b7bc7f5', '093aa406-bb15-4e75-8a72-428a1dcbff57', '14e9434c-5bae-4449-853e-300430d8ed7e',
   '2255c607-213e-451b-94e3-813e2751ceec', '27a39132-877b-41db-8eaa-c5833fbc5fd5', '31b200d9-ca05-4fe6-8fb9-242e84140b7e',
   '31bf9486-ab5a-4b0b-b929-ef1280e89e2f', '37ea8429-757b-4e50-85f9-c84fa572c53f', '393d0290-9cb7-4d67-bc32-e7d9190b773b',
   '3d2a4f0f-6328-473d-868e-ec9a0f0fc70f', '3f0580c7-5aed-4859-b5f6-aad4c019c7f1', '3f9f33b2-9679-4252-9160-e7db6eccd07d',
   '408a8564-b073-4ebf-aa64-e834b7a9359e', '40cd727f-0cca-4cd1-9aa0-79716ba3b5a5', '432e2876-c827-4cca-a303-eefffa3c0317',
   '4703d054-1655-4124-96f0-c0bfd429b529', '4bdc9907-8c0c-4201-ba31-6d073df5d78b', '4ec1cd44-ea56-40fb-8754-38aa07f6be27',
   '5140042a-dab8-43d5-a2a2-21c3845dd850', '515d5463-0215-4a39-971c-f580e8ab5f02', '5aa4fca6-cb41-409e-b0df-1cb1635cddad',
   '5d8055f9-0c92-46cc-852a-843bedaf7994', '5e6c2604-b8fb-4ea4-a104-c3a513b9efd6', '634dc8af-fdd4-4e66-ae0a-599c42c62531',
   '6d960a50-f20d-485b-869c-324a50c2116e', '75bfa93a-182a-42b3-b6a4-ede8e67a5fb5', '77c2c097-dc10-43cb-845e-571b6536e9fe',
   '7a90db43-b6fe-4eeb-a5d9-cdd7685428c6', '7ba0c7f8-e6ba-4ea6-a8db-9c39485f567f', '7d5fedcf-f5d0-41cb-aa6b-d396c501e341',
   '7d619a8e-40ca-42be-847c-ebfff189dd49', '84e55c41-5a87-4dbb-919c-49d73e8cbeab', '8c8a97f8-d472-4b1e-bf67-a802fffb397e',
   '92eaec95-1bb0-48c1-88fe-e8c2f137640f', '9542dd4b-1180-43df-9e99-ffc572240b06', '96403db8-a931-484f-bec6-cf493c984ccb',
   '9e0cbd64-ec1e-4404-8d77-ecbf2faa23d3', 'a0660e30-a420-44cf-8fb0-4dfedf279643', 'a5621fb4-6885-4aab-96d7-5d4ceeb6e70e',
   'a5c19da2-1b05-4b2b-b807-49ef4c4b5181', 'ac0ef059-b22f-406e-b9eb-cb7c682c59aa', 'ac40232e-9cd7-4285-8c6e-da892cfe2b70',
   'b507d285-8d97-43b0-be3e-274abc636366', 'c28f63b2-51e5-4ac2-bb29-b9140d9a7105', 'c8c1a14a-db7c-4a55-8f61-74a7cdefaa6a',
   'cd366b3e-c5b6-4e15-b4aa-09b8d5969c13', 'd0703284-465f-4c6a-9b01-27d35a5d2d34', 'd27212f8-83e2-476c-a902-6a19a5ca1de1',
   'd9a5be22-f175-4fc1-9500-2c85e62c0a4e', 'db981a6e-2de2-4647-b726-ea4237771fb7', 'db9e8cb1-0bfb-4bf2-b54c-cc910457146e',
   'e0e71db3-4ebe-415f-88bd-306b71fa8f8f', 'e1525f1d-eebd-4b29-afdc-eecba67b1f5b', 'e4947345-071e-4f34-b2b8-9c573f3a0d42',
   'e9ae016e-1f6f-4ec1-9991-b71bb7ed1f80', 'ea8b4ac1-361b-49db-9ef1-488a7b17f100', 'f5ea3cab-37f2-4990-848b-0e68b7f0bc68',
   'f88fb33c-ec70-4745-a415-618902edb988', 'f8c2d8bd-78c4-48f5-891e-0f474c2fa6a7', 'f966d308-9d54-4601-853e-712a26b3a31b',
   'fb8232ae-102a-4602-93b9-ca989bebb8f7', 'fe9b3434-104c-4653-96f5-03bdfc005051',
   -- por fornecedor (8)
   '0b5273ed-e8db-4655-835c-529e0fe23fe0', '24705976-f18f-4c8e-8a0c-cca55f562cd4', '85b9b641-3e5c-4aa6-ad8e-09d4e66b48ab',
   'a6e95a49-ae30-40ee-aa8a-59cc7108e88e', 'b81ef4e0-8859-4c94-927c-88a03aa033ff', 'e8beab3c-d52a-4267-b344-54989ee9bf48',
   'f1c7b009-695f-4a9d-a227-49d5e892520c', 'f6c3bd86-164e-41a5-b5f9-0120c9736598'
 )
   and status = 'proposed' and origin = 'ai'
   and created_at >= '2026-10-08 09:30:00+00' and created_at < '2026-10-08 09:31:00+00';

-- ---------------------------------------------------------------------------------------------
-- 3. Prova (antes do registro da versão): nenhuma das 88 ficou como sugestão; as 15 que ficam não foram tocadas
-- ---------------------------------------------------------------------------------------------
do $$
declare
  v_ainda_propostas integer;
  v_arquivadas integer;
  v_ficam_tocadas integer;
begin
  select count(*) filter (where status = 'proposed'),
         count(*) filter (where status = 'rejected' and note like 'Arquivada em 20/10/2026%')
    into v_ainda_propostas, v_arquivadas
    from public.finance_rules
   where id in (
     '0cea844e-1334-438c-9615-f8d594876bf1', '16af6051-5651-416b-a281-fe401a367057', '1752cbee-99d0-4bf1-a9c5-6e4960aa13f6',
     '1ba0987e-ef09-4351-9869-a69758d7ffc3', '26f4c304-a864-45d2-9e26-1a21afbfb535', '400f9397-cc24-4a9d-b31e-c1b7da666801',
     '5bd88f1c-2fb3-4640-afba-e98c2c547e33', '6229d52f-bb88-44ef-a441-80d1d168f043', '6f57006b-711a-4183-96e4-050670c4ac7e',
     '838e4780-28d4-4fc6-b4e5-7667ef158305', '8e7afa13-dd81-41e2-8ad4-0e3382d6496b', 'a4b0b15e-f1ec-420c-b4ec-2957c7c7fbe1',
     'b16db9b8-b0ae-4c55-8616-3d0853496646', 'bd081137-c0ac-40e2-942c-9e7efb2d9f6a', 'd45fac1f-40bd-46cb-8cb7-856cf647ee41',
     'd7a645d2-d85d-4e6e-896a-913e5d4f4fe1', 'e3e4a0b7-a729-4c20-b00a-c60e78a90777', 'f377fcf8-b06b-4ba6-96f9-bb3a477234f8',
     '04ea421b-f7ee-4580-9ba2-9c211b7bc7f5', '093aa406-bb15-4e75-8a72-428a1dcbff57', '14e9434c-5bae-4449-853e-300430d8ed7e',
     '2255c607-213e-451b-94e3-813e2751ceec', '27a39132-877b-41db-8eaa-c5833fbc5fd5', '31b200d9-ca05-4fe6-8fb9-242e84140b7e',
     '31bf9486-ab5a-4b0b-b929-ef1280e89e2f', '37ea8429-757b-4e50-85f9-c84fa572c53f', '393d0290-9cb7-4d67-bc32-e7d9190b773b',
     '3d2a4f0f-6328-473d-868e-ec9a0f0fc70f', '3f0580c7-5aed-4859-b5f6-aad4c019c7f1', '3f9f33b2-9679-4252-9160-e7db6eccd07d',
     '408a8564-b073-4ebf-aa64-e834b7a9359e', '40cd727f-0cca-4cd1-9aa0-79716ba3b5a5', '432e2876-c827-4cca-a303-eefffa3c0317',
     '4703d054-1655-4124-96f0-c0bfd429b529', '4bdc9907-8c0c-4201-ba31-6d073df5d78b', '4ec1cd44-ea56-40fb-8754-38aa07f6be27',
     '5140042a-dab8-43d5-a2a2-21c3845dd850', '515d5463-0215-4a39-971c-f580e8ab5f02', '5aa4fca6-cb41-409e-b0df-1cb1635cddad',
     '5d8055f9-0c92-46cc-852a-843bedaf7994', '5e6c2604-b8fb-4ea4-a104-c3a513b9efd6', '634dc8af-fdd4-4e66-ae0a-599c42c62531',
     '6d960a50-f20d-485b-869c-324a50c2116e', '75bfa93a-182a-42b3-b6a4-ede8e67a5fb5', '77c2c097-dc10-43cb-845e-571b6536e9fe',
     '7a90db43-b6fe-4eeb-a5d9-cdd7685428c6', '7ba0c7f8-e6ba-4ea6-a8db-9c39485f567f', '7d5fedcf-f5d0-41cb-aa6b-d396c501e341',
     '7d619a8e-40ca-42be-847c-ebfff189dd49', '84e55c41-5a87-4dbb-919c-49d73e8cbeab', '8c8a97f8-d472-4b1e-bf67-a802fffb397e',
     '92eaec95-1bb0-48c1-88fe-e8c2f137640f', '9542dd4b-1180-43df-9e99-ffc572240b06', '96403db8-a931-484f-bec6-cf493c984ccb',
     '9e0cbd64-ec1e-4404-8d77-ecbf2faa23d3', 'a0660e30-a420-44cf-8fb0-4dfedf279643', 'a5621fb4-6885-4aab-96d7-5d4ceeb6e70e',
     'a5c19da2-1b05-4b2b-b807-49ef4c4b5181', 'ac0ef059-b22f-406e-b9eb-cb7c682c59aa', 'ac40232e-9cd7-4285-8c6e-da892cfe2b70',
     'b507d285-8d97-43b0-be3e-274abc636366', 'c28f63b2-51e5-4ac2-bb29-b9140d9a7105', 'c8c1a14a-db7c-4a55-8f61-74a7cdefaa6a',
     'cd366b3e-c5b6-4e15-b4aa-09b8d5969c13', 'd0703284-465f-4c6a-9b01-27d35a5d2d34', 'd27212f8-83e2-476c-a902-6a19a5ca1de1',
     'd9a5be22-f175-4fc1-9500-2c85e62c0a4e', 'db981a6e-2de2-4647-b726-ea4237771fb7', 'db9e8cb1-0bfb-4bf2-b54c-cc910457146e',
     'e0e71db3-4ebe-415f-88bd-306b71fa8f8f', 'e1525f1d-eebd-4b29-afdc-eecba67b1f5b', 'e4947345-071e-4f34-b2b8-9c573f3a0d42',
     'e9ae016e-1f6f-4ec1-9991-b71bb7ed1f80', 'ea8b4ac1-361b-49db-9ef1-488a7b17f100', 'f5ea3cab-37f2-4990-848b-0e68b7f0bc68',
     'f88fb33c-ec70-4745-a415-618902edb988', 'f8c2d8bd-78c4-48f5-891e-0f474c2fa6a7', 'f966d308-9d54-4601-853e-712a26b3a31b',
     'fb8232ae-102a-4602-93b9-ca989bebb8f7', 'fe9b3434-104c-4653-96f5-03bdfc005051',
     '0b5273ed-e8db-4655-835c-529e0fe23fe0', '24705976-f18f-4c8e-8a0c-cca55f562cd4', '85b9b641-3e5c-4aa6-ad8e-09d4e66b48ab',
     'a6e95a49-ae30-40ee-aa8a-59cc7108e88e', 'b81ef4e0-8859-4c94-927c-88a03aa033ff', 'e8beab3c-d52a-4267-b344-54989ee9bf48',
     'f1c7b009-695f-4a9d-a227-49d5e892520c', 'f6c3bd86-164e-41a5-b5f9-0120c9736598'
   );
  if v_ainda_propostas > 0 then
    raise exception 'B1: % das 88 regras ainda estão como sugestão depois do arquivamento', v_ainda_propostas;
  end if;

  select count(*) into v_ficam_tocadas
    from public.finance_rules
   where id in (
     '2598af11-e31f-4373-a739-342c6dff6b2a', '688777d9-4223-4170-9092-0af0c79a7523', '7603b9dc-57f5-4467-af38-4900da133095',
     '83ad0704-06b6-4b18-8b93-7782616bed01', '904b93e3-b2af-44b2-bdc4-34b2e6f93c69', 'a2f05992-bd4e-4dea-b61b-fdaf3999fc9e',
     'a6d64808-71e5-466c-ae8b-dfb43115623b', 'fbfad134-d36b-4fce-9b8c-a76aa542ee68', '2d8f0cb8-d7a9-414c-b0b6-d8040636fc34',
     '63427038-e76b-4020-a55c-31a7e24c0088', '78a77881-ce47-4494-b328-9448a9fbea36', '7a39e680-f894-4880-8011-603bd3de0830',
     '7ab6e555-56bc-47d7-a04c-e661c059d273', '8b4d3aa1-07f1-4c74-8819-e9fa8791b168', 'add9a670-a5e5-4b63-8571-7cddec68fe14'
   )
     and note like 'Arquivada em 20/10/2026%';
  if v_ficam_tocadas > 0 then
    raise exception 'B1: % das 15 regras com movimento foram arquivadas por engano', v_ficam_tocadas;
  end if;

  raise notice 'B1: % regra(s) arquivada(s) por esta migration (88 na primeira aplicação; as que o dono decidiu antes ficam como ele deixou)', v_arquivadas;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261020120000', 'arquivar_regras_sugeridas_paradas')
on conflict do nothing;
