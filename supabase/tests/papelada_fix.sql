-- Prova: a papelada do financeiro de 20/10/2026 (migrations 20261020120000_arquivar_regras_sugeridas_paradas e
-- 20261020121000_entradas_recusadas_fora_da_fila). Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-papelada-fix.md
--
--   T1 B1: das 103 sugestões de 08/10, as 88 sem alcance não estão mais como sugestão (arquivadas com a nota, ou já
--      decididas pelo dono) e nenhuma das 15 com movimento foi arquivada
--   T2 B1: desfazer o arquivamento de uma regra (o SQL do cabeçalho) a devolve como sugestão, sem conflito no índice
--      único das ativas/propostas
--   T3 B3: as 5 entradas antigas recusadas (4 estornos de pedágio e os R$ 0,35) estão fora da fila — manual, motivo
--      'Recusada na fila: …', quem recusou, quando — com 1 trilha 'ignorou' cada; a de R$ 1.000 não foi tocada
--   T4 B3: a leitura do resumo ("entradas sem identificação": crédito do banco, reconciled=false, dismissed_at nulo)
--      não conta mais as 5; a de R$ 1.000 continua lá enquanto o dono não decidir
--   T5 B3: o saldo da conta não muda — soma_transacoes_conexao com as marcas = sem as marcas ('manual' não é
--      duplicata nem estorno: o dinheiro entrou)
--   T6 B3: desfazer (o SQL do cabeçalho, o mesmo efeito do Extrato › Fora da fila › trazer de volta) devolve a linha
--      ao resumo
--   T7 A2: o motivo das 5 começa com o prefixo que a recusa da edge grava ('Recusada na fila:'), então o desfazer da
--      edge (reopen → undismiss) trata as antigas e as novas do mesmo jeito
--
-- ═══ COMO RODAR ═══ (só com o OK nomeado, DEPOIS das duas migrations; também roda no ensaio PGlite da bancada,
--   D:/IA-HBR/comprovantes-bancada/pglite-ensaio/rodar-papelada-fix.mjs)
--
--   supabase db query --linked -f supabase/tests/papelada_fix.sql --output json
--
-- Seguro em produção: só lê, e o que T2/T5/T6 mudam para provar é desfeito pelo ROLLBACK do fim. Nenhum id inventado:
-- os ids são os das migrations.
--
-- A tabela final tem de mostrar ok = true em todas as linhas. Uma linha false é defeito.
begin;

create temp table _resultado (teste text, ok boolean, detalhe text) on commit drop;

create function pg_temp._arquivadas() returns uuid[] language sql immutable as $$
  select array[
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
  ]::uuid[]
$$;

create function pg_temp._ficam() returns uuid[] language sql immutable as $$
  select array[
    '2598af11-e31f-4373-a739-342c6dff6b2a', '688777d9-4223-4170-9092-0af0c79a7523', '7603b9dc-57f5-4467-af38-4900da133095',
    '83ad0704-06b6-4b18-8b93-7782616bed01', '904b93e3-b2af-44b2-bdc4-34b2e6f93c69', 'a2f05992-bd4e-4dea-b61b-fdaf3999fc9e',
    'a6d64808-71e5-466c-ae8b-dfb43115623b', 'fbfad134-d36b-4fce-9b8c-a76aa542ee68', '2d8f0cb8-d7a9-414c-b0b6-d8040636fc34',
    '63427038-e76b-4020-a55c-31a7e24c0088', '78a77881-ce47-4494-b328-9448a9fbea36', '7a39e680-f894-4880-8011-603bd3de0830',
    '7ab6e555-56bc-47d7-a04c-e661c059d273', '8b4d3aa1-07f1-4c74-8819-e9fa8791b168', 'add9a670-a5e5-4b63-8571-7cddec68fe14'
  ]::uuid[]
$$;

create function pg_temp._entradas() returns uuid[] language sql immutable as $$
  select array['c40b8d03-82b5-459d-b979-790537551de7', '14bce45c-d889-44df-aa48-ba7a099e8a9b',
               '34cc3028-eb49-430e-b4e2-5654b87bdca5', '59777142-d985-4a53-954d-5f0c0dacb75d',
               'eb1c966c-b2a0-4e1f-82e0-494b0fb907ad']::uuid[]
$$;

create function pg_temp._mil() returns uuid language sql immutable as $$ select '16e364db-99da-4a29-80a0-224e30387b72'::uuid $$;

-- a leitura do resumo da manhã e da tarde (ai-daily-briefing: entradas sem identificação)
create function pg_temp._no_resumo(p_id uuid) returns boolean language sql stable as $$
  select exists (select 1 from public.bank_transactions t
                  where t.id = p_id and t.reconciled = false and t.transaction_type = 'credit'
                    and t.source_type = 'bank' and t.dismissed_at is null)
$$;

-- T1
do $$
declare
  v_listas_ok boolean := cardinality(pg_temp._arquivadas()) = 88 and cardinality(pg_temp._ficam()) = 15
                         and not (pg_temp._arquivadas() && pg_temp._ficam());
  v_ainda integer;
  v_nota integer;
  v_ficam_arquivadas integer;
begin
  select count(*) filter (where status = 'proposed'),
         count(*) filter (where status = 'rejected' and note like 'Arquivada em 20/10/2026%')
    into v_ainda, v_nota
    from public.finance_rules where id = any (pg_temp._arquivadas());
  select count(*) into v_ficam_arquivadas from public.finance_rules
   where id = any (pg_temp._ficam()) and note like 'Arquivada em 20/10/2026%';
  insert into _resultado values ('T1 B1: as 88 sem alcance não são mais sugestão; nenhuma das 15 com movimento foi arquivada',
    v_listas_ok and v_ainda = 0 and v_ficam_arquivadas = 0,
    'listas=' || v_listas_ok || ' ainda_sugestao=' || v_ainda || ' com_a_nota=' || v_nota || ' das_15_arquivadas=' || v_ficam_arquivadas);
end $$;

-- T2
do $$
declare
  v_id uuid;
  v_status text;
begin
  select id into v_id from public.finance_rules
   where id = any (pg_temp._arquivadas()) and status = 'rejected' and note like 'Arquivada em 20/10/2026%'
   order by id limit 1;
  if v_id is null then
    insert into _resultado values ('T2 B1: desfazer o arquivamento devolve a sugestão', true, 'nenhuma arquivada para desfazer (nada a provar)');
    return;
  end if;
  update public.finance_rules set status = 'proposed', note = null
   where status = 'rejected' and note like 'Arquivada em 20/10/2026%' and id = v_id;
  select status into v_status from public.finance_rules where id = v_id;
  insert into _resultado values ('T2 B1: desfazer o arquivamento devolve a sugestão', v_status = 'proposed',
    'status=' || coalesce(v_status, 'null') || ' (desfeito no rollback)');
exception when others then
  insert into _resultado values ('T2 B1: desfazer o arquivamento devolve a sugestão', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- T3
do $$
declare
  v_fora integer;
  v_trilha integer;
  v_quem_certo integer;
  v_mil_tocada boolean;
begin
  select count(*) filter (where t.reconciled and t.dismissed_kind = 'manual' and t.dismissed_reason like 'Recusada na fila:%'
                               and t.dismissed_at is not null),
         count(*) filter (where t.dismissed_by is not distinct from
                               (select q.decided_by from public.finance_review_queue q
                                 where q.bank_transaction_id = t.id and q.kind = 'create_receivable' and q.status = 'rejected'
                                 order by q.decided_at desc nulls last, q.created_at desc limit 1))
    into v_fora, v_quem_certo
    from public.bank_transactions t where t.id = any (pg_temp._entradas());
  select count(*) into v_trilha from public.reconciliation_log
   where bank_transaction_id = any (pg_temp._entradas()) and acao = 'ignorou'
     and detalhe like '%tirada da fila pela papelada de 20/10/2026%';
  select coalesce(bool_or(dismissed_reason like 'Recusada na fila:%' and detalhe_mig), false) into v_mil_tocada
    from (select t.dismissed_reason,
                 exists (select 1 from public.reconciliation_log l where l.bank_transaction_id = t.id
                          and l.detalhe like '%papelada de 20/10/2026%') as detalhe_mig
            from public.bank_transactions t where t.id = pg_temp._mil()) x;
  insert into _resultado values ('T3 B3: as 5 entradas recusadas estão fora da fila, com quem recusou e 1 trilha cada; a de R$ 1.000 não',
    v_fora = 5 and v_quem_certo = 5 and v_trilha = 5 and not v_mil_tocada,
    'fora=' || v_fora || ' quem_certo=' || v_quem_certo || ' trilhas=' || v_trilha || ' mil_tocada=' || v_mil_tocada);
end $$;

-- T4
do $$
declare
  v_no_resumo integer;
  v_mil boolean;
  v_mil_decidida boolean;
begin
  select count(*) filter (where pg_temp._no_resumo(x)) into v_no_resumo from unnest(pg_temp._entradas()) x;
  v_mil := pg_temp._no_resumo(pg_temp._mil());
  -- se o dono já decidiu a de R$ 1.000 pela tela, ela sai do resumo por ele — não é falha da migration
  select coalesce(bool_or(t.reconciled or t.dismissed_reason is not null), false) into v_mil_decidida
    from public.bank_transactions t where t.id = pg_temp._mil();
  insert into _resultado values ('T4 B3: o resumo não conta mais as 5; a de R$ 1.000 continua para o dono',
    v_no_resumo = 0 and (v_mil or v_mil_decidida),
    'das_5_no_resumo=' || v_no_resumo || ' mil_no_resumo=' || v_mil || ' mil_decidida_pelo_dono=' || v_mil_decidida);
end $$;

-- T5
do $$
declare
  v_conexao uuid;
  v_com numeric;
  v_sem numeric;
begin
  select bank_connection_id into v_conexao from public.bank_transactions
   where id = any (pg_temp._entradas()) and bank_connection_id is not null limit 1;
  if v_conexao is null then
    insert into _resultado values ('T5 B3: o saldo da conta não muda com a marca', true, 'linhas sem conta (nada a provar)');
    return;
  end if;
  select soma into v_com from public.soma_transacoes_conexao(v_conexao, (now() at time zone 'America/Sao_Paulo')::date);
  -- tira QUALQUER marca das 5 (não só a 'manual'): se a migration tivesse gravado outra marca, o saldo mudaria aqui
  update public.bank_transactions set reconciled = false, dismissed_kind = null, dismissed_reason = null,
         dismissed_at = null, dismissed_by = null
   where id = any (pg_temp._entradas());
  select soma into v_sem from public.soma_transacoes_conexao(v_conexao, (now() at time zone 'America/Sao_Paulo')::date);
  insert into _resultado values ('T5 B3: o saldo da conta não muda com a marca', v_com = v_sem,
    'com_a_marca=' || v_com || ' sem_a_marca=' || v_sem || ' (desfeito no rollback)');
exception when others then
  insert into _resultado values ('T5 B3: o saldo da conta não muda com a marca', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- T6 (depois do T5 as 5 já estão sem a marca, dentro desta transação: refaz a marca numa e desfaz pelo SQL do cabeçalho)
do $$
declare
  v_id uuid := 'c40b8d03-82b5-459d-b979-790537551de7';
  v_antes boolean;
  v_depois boolean;
begin
  update public.bank_transactions set reconciled = true, dismissed_kind = 'manual',
         dismissed_reason = 'Recusada na fila: estorno de pedágio (Arteris), não é receita de cliente', dismissed_at = now()
   where id = v_id;
  v_antes := pg_temp._no_resumo(v_id);
  update public.bank_transactions set reconciled = false, dismissed_kind = null, dismissed_reason = null,
         dismissed_at = null, dismissed_by = null
   where id = v_id and dismissed_kind = 'manual' and dismissed_reason like 'Recusada na fila:%';
  v_depois := pg_temp._no_resumo(v_id);
  insert into _resultado values ('T6 B3: desfazer devolve a linha ao resumo',
    (not v_antes) and (v_depois or not exists (select 1 from public.bank_transactions where id = v_id)),
    'marcada_no_resumo=' || v_antes || ' desfeita_no_resumo=' || v_depois || ' (desfeito no rollback)');
exception when others then
  insert into _resultado values ('T6 B3: desfazer devolve a linha ao resumo', false, 'erro: ' || sqlstate || ' ' || sqlerrm);
end $$;

-- T7 (lê a trilha da migration: o motivo gravado nas 5 tem o prefixo da recusa da edge)
do $$
declare
  v_n integer;
begin
  select count(*) into v_n from public.reconciliation_log
   where bank_transaction_id = any (pg_temp._entradas()) and acao = 'ignorou' and detalhe like 'Recusada na fila: %';
  insert into _resultado values ('T7 A2: o motivo das 5 começa com o prefixo da recusa da edge (Recusada na fila:)', v_n = 5,
    'trilhas_com_o_prefixo=' || v_n);
end $$;

select teste, ok, detalhe from _resultado order by teste;

rollback;
