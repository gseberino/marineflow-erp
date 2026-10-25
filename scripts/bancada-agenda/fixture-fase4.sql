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
