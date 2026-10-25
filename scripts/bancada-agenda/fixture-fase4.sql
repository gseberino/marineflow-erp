-- Fixture da Fase 4 da Agenda de Produção: a carteira de sex 30/10/2026, SINTÉTICA.
-- = fixture-fase3.sql (que executa a da Fase 2 e o pós-rodada da Fase 1 por dentro) + os fornecedores da Fase 4. Roda
-- dentro do begin/rollback do teste (o rodar.mjs passa este arquivo em agenda_teste.fase4 e os de antes nos seus nomes).
-- NUNCA rodar em produção. Só primeiros nomes; telefones do tipo "55479000002xx"; CNPJ inventados (não são de ninguém);
-- ids novos com o prefixo d4000000 e os fornecedores dd000000-…-0005 em diante (livres nas fixtures e nos testes em 25/10).
--
-- P1 (25/10) — os fornecedores, espelho do que os SELECTs de 25/10 mostraram (spec-fase4 §2; sql/j01, j01b, j06, k01):
--   · Premel com a cidade "Itaja" + U+FFFD, como a importação de 12/04 deixou (NOVO-agenda-30): a regra tolerante a põe
--     em "entrega local";
--   · Kamell de Vila Velha/ES com CNPJ de 14 dígitos, telefone e contato; a de Itajaí/SC continua ATIVA como na fixture de
--     23/10 (o cadastro repetido que a spec descreve; em produção ela já está inativa — o B5 prova os dois casos);
--   · Mateus Honório com telefone (sem cidade e sem UF, como em produção);
--   · AliExpress (importado, pelo nome), Toli (Curitiba/PR), Mercado Pago (marketplace, pelo nome), Correa (Balneário
--     Camboriú, em maiúsculas e sem acento) e Souper (Itajaí quebrado, com o MESMO telefone de um cliente com OS: o Rodrigo);
--   · o dono também cadastrado como fornecedor (inativo, com o telefone do login dele): o detector (P4) nunca o lê;
--   · o painel do Nelson (OS-00112) comprado na AliExpress qui 15/10, com previsão qua 04/11 (13 dias úteis: os terços caem
--     em qui 22/10 e qua 28/10). A linha volta a faltar e é comprada de novo, como uma compra nova: o original (ter 03/11,
--     da fixture de 23/10) vai ao histórico, e o novo original (qua 04/11, o dono) é gravado com o dia 15/10.
-- Os pacotes seguintes acrescentam o que é deles, em seções próprias no fim deste arquivo: P3 (o e-mail com as NF-e 51038
-- da Kamell e 812 da Correa; o Pix de R$ 480,00 à Premel com a fila financeira), P4 (a conversa do Mateus: "Recebeu o
-- compressor? Deu tudo certo?" ter 20/10).
-- Os modos ao fim: os da fixture-fase3 (proposta e vigia ligados; equipe, diária, material, detector e fornecedor
-- desligados, como a linha nasce na bancada): cada teste liga o que precisa.

do $fase4$
begin
  if coalesce(current_setting('agenda_teste.fase3', true), '') = '' then
    raise exception 'fixture-fase4: falta agenda_teste.fase3 (rode pela bancada: scripts/bancada-agenda/rodar.mjs)';
  end if;
  execute current_setting('agenda_teste.fase3');
end
$fase4$;

-- ── Os fornecedores ─────────────────────────────────────────────────────────────────────────────────────
update public.suppliers set city = 'Itaja' || chr(65533) where id = 'dd000000-0000-4000-8000-000000000001';   -- Premel
update public.suppliers set cnpj_cpf = '11222333000144', phone = '5547900000202', contact_name = 'Carla'
 where id = 'dd000000-0000-4000-8000-000000000002';                                                              -- Kamell ES
update public.suppliers set phone = '5547900000201', contact_name = 'Mateus'
 where id = 'dd000000-0000-4000-8000-000000000004';                                                              -- Mateus Honório

insert into public.suppliers (id, name, trade_name, cnpj_cpf, phone, contact_name, city, state, active) values
  ('dd000000-0000-4000-8000-000000000005', 'ALIEXPRESS', 'AliExpress', null, null, null, null, null, true),
  ('dd000000-0000-4000-8000-000000000006', 'TOLI CURITIBA', null, '22333444000155', '5541900000206', 'Paulo', 'CURITIBA', 'PR', true),
  ('dd000000-0000-4000-8000-000000000007', 'MERCADO PAGO INSTITUICAO DE PAGAMENTO LTDA', null, '33444555000166', null, null,
   'Osasco', 'SP', true),
  ('dd000000-0000-4000-8000-000000000008', 'CORREA MATERIAIS ELETRICOS L3 BALNEARIO', null, '44555666000177', '5547900000208',
   'Rita', 'BALNEARIO CAMBORIU', 'SC', true),
  ('dd000000-0000-4000-8000-000000000009', 'Gustavo', null, null, '5547900000210', null, 'ITAJA' || chr(65533), 'SC', false),
  ('dd000000-0000-4000-8000-000000000010', 'SOUPER', null, '55666777000188', '5547900000211', null, 'Itaja' || chr(65533), 'SC', true);

-- O dono (o login admin) com o telefone dele; o Rodrigo (cliente com OS) com o mesmo telefone da Souper.
update public.app_users set phone_normalized = '5547900000210' where id = 'aa000000-0000-4000-8000-000000000001';
update public.clients set phone = '5547900000211' where id = 'c1000000-0000-4000-8000-000000000006';

-- ── O painel do Nelson: comprado na AliExpress qui 15/10, previsão qua 04/11 ─────────────────────────────
-- O dia da escrita é 15/10 (o gatilho do original grava previsao_original_em com _agenda_hoje()).
select set_config('agenda.hoje', '2026-10-15', true);
update public.os_material
   set situacao = 'falta', quantidade_na_mao = 0, chegou_em = null, previsao_de = null, previsao_ate = null,
       previsao_fonte = null
 where service_order_part_id = md5('peca:112:4')::uuid;                                    -- Painel Touch HBR 7"
update public.os_material
   set situacao = 'comprado', comprado_em = date '2026-10-15', comprado_fonte = 'dono',
       previsao_ate = date '2026-11-04', previsao_fonte = 'dono', fonte = 'dono',
       fornecedor_id = 'dd000000-0000-4000-8000-000000000005', fornecedor_nome = null,
       trecho = 'o painel do Nelson eu comprei na AliExpress dia 15, chega dia 4',
       conferido_em = timestamptz '2026-10-15 18:00-03', atualizado_por = 'aa000000-0000-4000-8000-000000000001'
 where service_order_part_id = md5('peca:112:4')::uuid;
select set_config('agenda.hoje', '', true);

do $confere$
begin
  if (select count(*) from public.os_material where service_order_part_id = md5('peca:112:4')::uuid
         and situacao = 'comprado' and previsao_original = date '2026-11-04' and previsao_original_em = date '2026-10-15') <> 1 then
    raise exception 'fixture-fase4: o painel do Nelson não ficou comprado com o original de qua 04/11';
  end if;
end
$confere$;

-- ══ P3 (25/10) — as notas do e-mail e o Pix ════════════════════════════════════════════════════════════
-- (a) O material de volta a faltar, como a amostra da spec §6.5 pede ("Vanderlei: 4 itens a comprar"; "Nelson: Cerbo GX …
--     pela nota 51038; 2 itens sem fornecedor") e o P3 precisa (as perguntas da nota e do Pix só falam de OS com falta):
--     · o Vanderlei (OS-00069) não recebeu: os 4 itens faltam, e o dono disse que compra da Premel (fonte dono, sem data);
--     · o Nelson (OS-00112): o KIT, o Cerbo GX (Kamell de Vila Velha, pelo produto) e o Orion voltam a faltar (a linha do
--       sistema: fonte nula); o painel continua comprado na AliExpress (a seção do P1).
update public.os_material
   set situacao = 'falta', quantidade_na_mao = 0, chegou_em = null, compra_prevista_em = null, fonte = 'dono',
       fornecedor_id = 'dd000000-0000-4000-8000-000000000001', fornecedor_nome = null,
       trecho = 'o material do Vanderlei eu compro na Premel', conferido_em = timestamptz '2026-10-27 18:00-03'
 where service_order_id = '05000000-0000-4000-8000-000000000069';
update public.os_material
   set situacao = 'falta', quantidade_na_mao = 0, chegou_em = null, compra_prevista_em = null, fonte = null,
       previsao_de = null, previsao_ate = null, previsao_fonte = null, trecho = null, conferido_em = null
 where service_order_part_id in (md5('peca:112:1')::uuid, md5('peca:112:2')::uuid, md5('peca:112:3')::uuid);

-- (b) O e-mail com as NF-e (o que o leitor do email-imap grava em dados_extraidos, já com os campos da Fase 4):
--     · Kamell (Vila Velha/ES, CNPJ da fixture) nota 51038, emitida e saída seg 26/10, modFrete 0, o Cerbo GX; o e-mail
--       chegou ter 27/10 08:10 (0,6 dia depois, como os de produção);
--     · Correa (Balneário Camboriú/SC) nota 812, qui 29/10, modFrete 9 (sem transporte: retirada), fita e abraçadeiras
--       (material de estoque, não de serviço).
--     As chaves têm o dígito verificador certo e são inventadas; nenhuma das duas foi importada (fiscal_notes vazia).
insert into public.email_accounts (id, address, label) values
  ('d4000000-0000-4000-8000-0000000003e0', 'financeiro@exemplo-ag4.test', 'Financeiro (teste)');
insert into public.email_messages (id, account_id, dedup_key, from_name, from_address, subject, received_at, has_attachments,
                                   supplier_id, match_confidence, match_reason, dados_extraidos)
values
  ('d4000000-0000-4000-8000-0000000003e1', 'd4000000-0000-4000-8000-0000000003e0', 'teste-ag4:nfe-51038', 'Kamell',
   'nfe@kamell-ag4.test', 'NF-e 51038', timestamptz '2026-10-27 08:10-03', true, 'dd000000-0000-4000-8000-000000000002', 1,
   'nfe_cnpj',
   '{"nfes": [{"anexo_indice": 0, "chave": "32261011222333000144550010000510381000000014",
               "emitente": "KAMELL COMERCIO GLOBAL LTDA", "emitente_cnpj": "11222333000144", "numero": "51038",
               "serie": "1", "valor": 3054.44, "data": "2026-10-26", "para_empresa": true, "saida": "2026-10-26",
               "mod_frete": "0", "uf": "ES", "municipio": "Vila Velha",
               "itens": [{"n": 1, "descricao": "CENTRAL DE CONTROLE CERBO GX VICTRON ENERGY", "qtd": 1, "un": "UN"}],
               "anexo_id": "d4000000-0000-4000-8000-0000000003a1"}],
     "boletos": []}'),
  ('d4000000-0000-4000-8000-0000000003e2', 'd4000000-0000-4000-8000-0000000003e0', 'teste-ag4:nfe-812', 'Correa',
   'nfe@correa-ag4.test', 'NF-e 812', timestamptz '2026-10-29 18:20-03', true, 'dd000000-0000-4000-8000-000000000008', 1,
   'nfe_cnpj',
   '{"nfes": [{"anexo_indice": 0, "chave": "42261044555666000177550010000008121000000023",
               "emitente": "CORREA MATERIAIS ELETRICOS L3 BALNEARIO", "emitente_cnpj": "44555666000177", "numero": "812",
               "serie": "1", "valor": 187.30, "data": "2026-10-29", "para_empresa": true, "saida": null,
               "mod_frete": "9", "uf": "SC", "municipio": "Balneario Camboriu",
               "itens": [{"n": 1, "descricao": "FITA ISOLANTE 3M 20M", "qtd": 2, "un": "UN"},
                         {"n": 2, "descricao": "ABRACADEIRA NYLON 200MM", "qtd": 100, "un": "UN"}],
               "anexo_id": "d4000000-0000-4000-8000-0000000003a2"}],
     "boletos": []}');
insert into public.email_attachments (id, message_id, filename, mime_type, size_bytes, storage_path, kind) values
  ('d4000000-0000-4000-8000-0000000003a1', 'd4000000-0000-4000-8000-0000000003e1',
   '32261011222333000144550010000510381000000014-nfe.xml', 'application/xml', 9000,
   'd4000000-0000-4000-8000-0000000003e1/0-32261011222333000144550010000510381000000014-nfe.xml', 'nfe_xml'),
  ('d4000000-0000-4000-8000-0000000003a2', 'd4000000-0000-4000-8000-0000000003e2',
   '42261044555666000177550010000008121000000023-nfe.xml', 'application/xml', 7000,
   'd4000000-0000-4000-8000-0000000003e2/0-42261044555666000177550010000008121000000023-nfe.xml', 'nfe_xml');

-- (c) O Pix de R$ 480,00 à Premel, seg 26/10, no extrato (Pluggy), com a fila financeira sugerindo a Premel em "Peças e
--     materiais" (pendente: o dono ainda não decidiu). Ninguém ligou a OS (como os 86 Pix de produção, NOVO-agenda-33).
insert into public.bank_transactions (id, transaction_date, description, amount, transaction_type, payment_method,
                                      counterparty_name, provider, source_type)
values ('d4000000-0000-4000-8000-0000000003b1', date '2026-10-26', 'PIX ENVIADO PREMEL MAT ELETRICOS', -480.00, 'debit', 'PIX',
        'PREMEL MAT ELETRICOS LTDA', 'pluggy', 'bank');
insert into public.finance_review_queue (id, kind, status, bank_transaction_id, title, confidence, suggested_amount,
                                         suggested_date, suggested_category, suggested_supplier_id)
values ('d4000000-0000-4000-8000-0000000003b2', 'create_payable', 'pending', 'd4000000-0000-4000-8000-0000000003b1',
        'Pix à PREMEL MAT ELETRICOS', 60, 480.00, date '2026-10-26', 'Peças e materiais', 'dd000000-0000-4000-8000-000000000001');

-- ══ P4 (25/10) — a conversa do Mateus ══════════════════════════════════════════════════════════════════
-- "Recebeu o compressor? Deu tudo certo?" ter 20/10 09:58 (int-compras-prazos §4.7, trecho #10), numa mensagem só. Em
-- 30/10 ela já está fora da janela do detector (detector_janela_horas); o teste do detector a lê em 20/10, quando o
-- compressor já estava na mão (desde qua 14/10): não vira pergunta.
insert into public.whatsapp_messages (id, direction, phone_normalized, message_type, body, occurred_at, delivery_status)
values ('d4000000-0000-4000-8000-000000000420', 'inbound', '5547900000201', 'text', 'Recebeu o compressor? Deu tudo certo?',
        timestamptz '2026-10-20 09:58-03', 'received');

-- ══ P6 (25/10) — a aprovação da OS-00104 como em produção ═════════════════════════════════════════════
-- A OS-00104 (Flávio) foi aprovada ter 22/09 às 22:27 de Brasília (sql/j08_os104: qua 23/09 01:27 UTC). O dia que vale é o
-- de Brasília (a régua de os_carteira): 22/09, e a OC-00004 é de 13/10 — os 21 dias "da aprovação até a compra" do KPI
-- (spec §2 e §11, aceite 7). O ::date direto daria 23/09 (20 dias): o teste das leituras prova que não é.
update public.service_orders set converted_to_os_at = timestamptz '2026-09-22 22:27-03'
 where id = '05000000-0000-4000-8000-000000000104';
