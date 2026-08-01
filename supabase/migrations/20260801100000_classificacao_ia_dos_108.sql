-- ═══════════════════════════════════════════════════════════════════════════
-- Classificação dos 108 serviços que a palavra-chave não fechou
-- Plano: plans/marineflow-execucao-os-roteiro.md, seção 10-ter (P27-P29)
--
-- Decisão do dono em 31/07: "a IA classifica os que sobraram e eu reviso só os
-- incertos". A camada de palavra-chave fechou 154 dos 261; estes 108 são o
-- resto — 87 com verbo mas sem sistema, 17 sem nada e 4 com sistema mas sem
-- verbo.
--
-- TRÊS DISTINÇÕES QUE ORIENTARAM A CLASSIFICAÇÃO:
--
-- 1. `nenhum` ≠ `null`. NULL quer dizer "ninguém classificou ainda"; `nenhum`
--    quer dizer "olhei e este serviço não toca sistema físico algum" — mão de
--    obra, frete, hospedagem, consultoria, projeto. Eles NÃO devem receber
--    abertura de segurança: não há alimentação para desligar em um frete.
--
-- 2. Fora do escopo declarado (pintura, para-brisa, laminação) entra como
--    `nenhum` de propósito: o serviço existe no catálogo e é vendido, mas a HBR
--    não tem roteiro técnico para ele.
--
-- 3. Confiança honesta: 0.9 quando o nome diz o sistema sem ambiguidade, 0.6
--    quando foi inferência razoável e 0.3 quando é chute educado. O dono revisa
--    o que estiver abaixo de 0.9 na tela — que é exatamente o combinado.
-- ═══════════════════════════════════════════════════════════════════════════

update public.services s set
  service_system = coalesce(v.sistema, s.service_system),
  service_verb   = coalesce(v.verbo, s.service_verb),
  classified_by  = 'ai',
  classified_at  = now(),
  classification_confidence = v.conf
from (values
  -- ── Elétrico DC ────────────────────────────────────────────────────────
  ('b2627dc5-0cf0-4663-bf28-c9eb20b826c9'::uuid,'eletronico',null,0.9),   -- multimídia de console (o typo "multimedia" enganou a palavra-chave)
  ('6110db0b-e959-421b-94c0-6d2bdd1d4278'::uuid,'eletrico_dc',null,0.9),  -- conectores/cabos p/ carregamento de trailer
  ('8e7b1744-836d-4eba-9cf9-128327d25da7'::uuid,'eletrico_dc',null,0.9),  -- elevação de vidros/janelas
  ('3ecdd2b2-5d57-4387-977f-91b3af1fe3eb'::uuid,'eletrico_dc',null,0.9),  -- painel start/stop
  ('05cc34b9-c77f-4ddc-a318-a2f1a737a9eb'::uuid,'eletrico_dc',null,0.9),  -- painel de acionamento e proteção
  ('cf66042d-c619-4697-b979-b9361ab44f7d'::uuid,'eletrico_dc',null,0.9),  -- inspeção ABYC (norma elétrica)
  ('d5d8c531-bde1-4894-b576-63f718cbe297'::uuid,'eletrico_dc',null,0.9),  -- resolução de falhas elétricas
  ('3424c514-f7bd-4907-adc2-358c9ae8ab5f'::uuid,'eletrico_dc',null,0.9),  -- testes de funcionamento elétrico
  ('72050c43-3341-4b37-9300-fcd175c7c930'::uuid,'eletrico_dc',null,0.9),  -- verificação do sistema elétrico
  ('30dba1f5-0b6c-4c6b-a482-ec81296b445c'::uuid,'eletrico_dc',null,0.9),  -- cabos elétricos de motores
  ('14d98f65-2f4d-487b-883b-cf10699bc87a'::uuid,'eletrico_dc',null,0.9),  -- desmontagem do sistema elétrico
  ('409ed629-f389-4a5f-9075-37427ccef976'::uuid,'eletrico_dc',null,0.9),  -- configuração/parametrização (pacote LiFePO4)
  ('c094e1af-5d9d-4749-a049-1b39244b4944'::uuid,'eletrico_dc',null,0.9),  -- testes e comissionamento (pacote)
  ('d48da19f-0113-4086-a526-7d64841c519b'::uuid,'eletrico_dc','reparo',0.9), -- falha vidros elétricos
  ('974045ac-aefb-451b-acba-c3bb17facdd2'::uuid,'eletrico_dc',null,0.8),  -- diagnóstico de falha elétrica
  ('723991a7-dd25-4e5b-921b-811c14a72879'::uuid,'eletrico_dc',null,0.6),  -- painel de teclas (config+instalação)
  ('5a0bffb6-c1ff-4087-b65d-dc583057c64d'::uuid,'eletrico_dc',null,0.6),  -- painel de teclas
  ('0b091207-ecde-45f3-89bc-031d99304967'::uuid,'eletrico_dc',null,0.6),  -- exaustor de casa de máquinas
  ('c36e1e24-5ba9-4d71-bffc-80a0a19faf31'::uuid,'eletrico_dc',null,0.6),  -- "instalação e configuração do sistema"
  ('78f33aec-39b7-49df-9e73-073930e713b7'::uuid,'eletrico_dc',null,0.6),  -- instalação/config/substituição do sistema atual
  ('c3c9b27a-7199-49bb-a9c4-896aba3a6cbd'::uuid,'eletrico_dc',null,0.6),  -- projeto elétrico
  ('a8332f82-0a43-49aa-9064-554812491dff'::uuid,'eletrico_dc',null,0.6),  -- assessoria/projetos elétricos
  ('1783d10e-f9dd-4912-a7c7-b7dadf160c30'::uuid,'eletrico_dc',null,0.6),  -- reparo de chicote elétrico
  ('6745b069-1f2b-42c0-9e43-2c994aaf431f'::uuid,'eletrico_dc',null,0.6),  -- restauração de chicote elétrico
  ('96f4dd0f-ae29-47a3-90a8-e15221a61f56'::uuid,'eletrico_dc',null,0.6),  -- isolamento de bobina de campo
  ('1a90e060-b374-49e8-b101-35061393e1fe'::uuid,'eletrico_dc',null,0.6),  -- motor de partida (elétrico, não mecânico)
  ('c9192ffd-f35e-47cd-a037-ec153cdecf4e'::uuid,'eletrico_dc',null,0.6),  -- atuador elétrico
  ('1ea2c19f-1c7f-4cd4-8fdf-4bfa7251cff7'::uuid,'eletrico_dc',null,0.6),  -- componentes elétricos
  ('1e8cc37f-8c02-4ec1-a278-c6aaaed06d13'::uuid,'eletrico_dc',null,0.6),  -- bomba de porão (a falha costuma ser elétrica)
  ('7318d88e-60e8-4ef2-8699-4379fc6e88a0'::uuid,'eletrico_dc','reparo',0.6), -- falha bomba porão
  ('a824089e-b5dd-407c-86dc-3bd00c376eed'::uuid,null,'instalacao',0.9),   -- conversor isolador Victron ("INISTALAÇÃO")
  ('62cafa74-f506-4bf4-94a2-2ba443f65991'::uuid,null,'instalacao',0.9),   -- passagem de cabos 12V
  ('fbf135eb-9c06-4e39-a052-eced2d52be2c'::uuid,null,'instalacao',0.9),   -- passagem e crimpagem de cabos de bateria

  -- ── Elétrico AC ────────────────────────────────────────────────────────
  ('7011f547-f8e3-41f6-8dd2-e005a712063e'::uuid,'eletrico_ac',null,0.9),  -- disjuntores e DDR da entrada de cais
  ('28c9b317-8c3a-41af-a7a9-bde30f63d18b'::uuid,'eletrico_ac',null,0.8),  -- plugue/tomada de extensão externa
  ('90eb6ba4-4f9e-4eae-afb9-d6e278b3b510'::uuid,'eletrico_ac',null,0.6),  -- churrasqueira elétrica

  -- ── Eletrônico / dados ─────────────────────────────────────────────────
  ('8c7edca4-7bae-4b5a-9b48-6643d1309557'::uuid,'eletronico',null,0.9),   -- interface Volvo EasyConnect NMEA2000
  ('6f2e7a46-e606-48f9-9af0-56da8c4c2c25'::uuid,'eletronico',null,0.9),   -- módulos eletrônicos Seakeeper
  ('7be0d338-79a3-4687-9071-372737adf010'::uuid,'eletronico',null,0.9),   -- módulo sonar Furuno
  ('c808c44d-5d55-4242-83ae-facc0d47be92'::uuid,'eletronico',null,0.9),   -- radar marítimo
  ('3387ae73-4bf5-4e3a-be5f-9fbe20005d5e'::uuid,'eletronico',null,0.9),   -- kit áudio JBL
  ('3b02e314-2d11-41cf-a009-b4ca113d06fb'::uuid,'eletronico',null,0.9),   -- audio receiver Fusion cockpit
  ('ff5af032-35f5-4e29-8f0f-ed849ab2b902'::uuid,'eletronico',null,0.9),   -- audio receiver repetidor Fusion fly
  ('ffb5374a-e27f-45f0-b150-8215d22049b5'::uuid,'eletronico',null,0.9),   -- sistema de áudio Fosgate
  ('9019b34d-d3e1-483f-8b24-bafae4726ef8'::uuid,'eletronico',null,0.9),   -- estação meteorológica
  ('e4563d25-7978-4421-bfed-04fc12dafa04'::uuid,'eletronico',null,0.9),   -- reinstalação de eletrônicos
  ('e3039950-30c5-4a01-a479-40d32f3d2e31'::uuid,'eletronico',null,0.9),   -- módulo eletrônico Caterpillar
  ('dae79e92-8632-4bbc-804f-03505b1832d7'::uuid,'eletronico',null,0.9),   -- sistema de controle Volvo EDC
  ('d71bf88c-f2a2-4f0c-863a-b79ba0331c03'::uuid,'eletronico',null,0.9),   -- direção eletrônica Volvo
  ('3691afeb-cdc9-4909-8e84-e1a8418dbd0b'::uuid,'eletronico',null,0.9),   -- relógio de dados Volvo Penta
  ('1aa6ec94-5139-4ab6-a775-f6a31af38476'::uuid,'eletronico',null,0.9),   -- cabo de dados radar B&G Halo
  ('e2279af5-80ec-45a2-8148-e1134e2fcbf8'::uuid,'eletronico','instalacao',0.9), -- alarmes de segurança
  ('fd1524f5-5d45-481c-9554-29b96d159948'::uuid,'eletronico',null,0.8),   -- chicote de DADOS Volvo (dados, não potência)
  ('2fd4ec1a-ce81-4d97-af0a-ffd41a4cac86'::uuid,'eletronico',null,0.6),   -- painel de comando de vaso elétrico
  ('08b73a74-7c35-4650-ac52-760f50201ef0'::uuid,'eletronico',null,0.6),   -- relógios de temperatura

  -- ── Refrigeração ───────────────────────────────────────────────────────
  ('cbee3c3e-8766-41b7-8cc9-8ec9b678946c'::uuid,'refrigeracao',null,0.9), -- fluido refrigerante do chiller
  ('04cc13ee-0075-4279-b4cf-539c5e547528'::uuid,'refrigeracao',null,0.9), -- controlador eletrônico do chiller

  -- ── Hidráulico ─────────────────────────────────────────────────────────
  ('2fde63c3-2c3b-43ce-bcdd-6c51446f839e'::uuid,'hidraulico',null,0.9),   -- pedal do vaso sanitário
  ('09b4fce7-a34b-43ae-85c2-118cb26425ac'::uuid,null,'adequacao',0.7),    -- calafetagem do box do chuveiro
  ('fc040486-07e5-471a-8427-0f84cd6494d4'::uuid,'hidraulico',null,0.5),   -- conexões de bronze (pode ser mecânico)

  -- ── Mecânico ───────────────────────────────────────────────────────────
  ('88684d14-b6cb-4a33-9b88-83c8c16c7049'::uuid,'mecanico',null,0.9),     -- parelha de motores Mercury
  ('e34ed88c-3bf6-4c9b-8256-2c78b9890e30'::uuid,'mecanico',null,0.9),     -- bicos injetores
  ('dea56987-cba0-457a-b07b-e408c6701ba3'::uuid,'mecanico',null,0.9),     -- turbina Volvo Penta
  ('0d3af97b-7fbd-419c-aa3a-0a8f1d650d57'::uuid,'mecanico',null,0.9),     -- corrente de âncora
  ('0c600b0d-d777-4445-98c1-01c46bb0acee'::uuid,'mecanico','manutencao',0.9), -- dessalinização do motor de guincho
  ('936e1e95-6647-45f8-a310-fa862eee229b'::uuid,'mecanico','adequacao',0.7),  -- palhetas de limpadores
  ('6f1504d6-02aa-43b6-840f-b93950a4f314'::uuid,'mecanico',null,0.6),     -- limpeza de reservatório de diesel
  ('d1f3f7c7-23c5-4bf0-8a90-a0c516fc3cee'::uuid,'mecanico',null,0.6),     -- bocal de abastecimento
  ('40e30a5f-24c5-4769-b1c2-8979ab7d7432'::uuid,'mecanico',null,0.6),     -- respiro de ventilação do tanque

  -- ── `nenhum`: não toca sistema físico — mão de obra, viagem, projeto ────
  ('e4205908-ae0e-44eb-bd8b-f2c0e2b96b89'::uuid,'nenhum',null,0.9),       -- consultoria técnica
  ('f8815228-9f56-45e0-8090-3126f610d376'::uuid,'nenhum',null,0.9),       -- deslocamento de equipe
  ('2cf02ccd-081d-40f2-8358-deb4adc020f6'::uuid,'nenhum',null,0.9),       -- frete de equipamento
  ('5518a4c2-419d-494f-93d3-ae63bfdc6afc'::uuid,'nenhum',null,0.9),       -- mão de obra
  ('96536666-b076-4f6c-8234-bb4d7d7a11bb'::uuid,'nenhum',null,0.9),       -- mão de obra geral
  ('e696c3ed-7643-4fd0-9f58-ecef4c0eb9e7'::uuid,'nenhum',null,0.8),       -- mão de obra de instalação
  ('4ff1e20a-4573-47dc-8a69-3341f31920f5'::uuid,'nenhum',null,0.9),       -- assessoria de adequação a normas
  ('26fb4ba3-09ed-4a25-a4d7-ebf5afa72f3f'::uuid,'nenhum','logistica',0.9),-- hospedagem
  ('a44d9057-2c34-4f6a-8764-08c48ddaafa4'::uuid,'nenhum','logistica',0.9),-- locação de veículo
  ('de2e11d9-4275-4496-be96-bf9704a95f50'::uuid,'nenhum','logistica',0.9),-- "serviço de venda"
  ('87d8cf38-8cb1-4df0-a800-7a21f8537e5e'::uuid,'nenhum','logistica',0.9),-- galvanização a fogo (terceirizado)
  ('0c0d6a5f-3817-4748-ab26-65fcb1e56c48'::uuid,'nenhum','logistica',0.9),-- galvanização de corrente (terceirizado)
  ('308f6682-ec66-48c0-b647-e89d12ac3f1b'::uuid,'nenhum','logistica',0.5),-- termorretráteis: é MATERIAL lançado como serviço
  ('7a1c524f-2a63-4a32-9995-87258e487e76'::uuid,'nenhum',null,0.6),       -- diagnóstico em bancada (sem sistema definido)
  ('d70a0160-eb16-4063-8d5b-1bd18f1ac110'::uuid,'nenhum',null,0.5),       -- diagnóstico no local (genérico)
  ('6eb2b8a9-5803-41fd-b292-173287ae16c7'::uuid,'nenhum',null,0.5),       -- diagnóstico de equipamentos (genérico)
  ('821125a7-2978-471b-b8a0-ff7d172b5017'::uuid,'nenhum',null,0.5),       -- teste técnico de funcionamento (genérico)
  ('9d6e2403-e4c1-4c62-873e-c6a9b77d37d1'::uuid,'nenhum',null,0.4),       -- comissionamento/validação de garantia
  ('3db1f0b5-e344-403e-b3b4-91a4e771758d'::uuid,'nenhum',null,0.3),       -- "CT - Instalação e Fixação"
  ('61d69409-f3ad-449f-9c98-0202eccbbc51'::uuid,'nenhum',null,0.3),       -- "IT - Instalação e Configuração"
  ('fa29568f-a6a3-41c8-866c-9d6be3b783a0'::uuid,'nenhum',null,0.3),       -- "Substituição e Instalação Equipamentos"
  ('f4340279-f29c-424a-8a5b-429ce89c1c99'::uuid,'nenhum','logistica',0.3),-- assistência técnica autorizada (guarda-chuva)

  -- ── Fora do escopo declarado (pintura, para-brisa, laminação) ───────────
  ('058f09e4-8ace-4c40-bcf9-a35eeedfc1e9'::uuid,'nenhum','adequacao',0.9),-- pintura gelcoat
  ('3ac59224-a003-45fa-8efa-e274475739dc'::uuid,'nenhum','adequacao',0.9),-- pintura anticorrosiva
  ('5bb02e78-52aa-42c6-9c65-d8d6b17f3160'::uuid,'nenhum',null,0.9),       -- adesivo de vedação do para-brisa
  ('797298bd-c6ee-405e-88ad-caa6cb777503'::uuid,'nenhum','adequacao',0.8),-- selante de vedação de vidros

  -- ── Restos de teste: classificados como `nenhum` para não gerar roteiro ─
  -- Estes deviam sair do catálogo; a inativação é decisão do dono.
  ('6b5479b9-47bf-4c9d-8908-3395588ca64a'::uuid,'nenhum','logistica',0.2),
  ('884b3962-beed-4ef1-b530-64f9353ec0f4'::uuid,'nenhum','logistica',0.2),
  ('b36a5930-ed56-4411-b7be-0d5f61d57f2f'::uuid,'nenhum',null,0.2),
  ('b85d1790-17b1-4128-a7d5-4dfd9fed7b13'::uuid,'nenhum',null,0.2),
  ('694e540d-9b3f-4dcc-8f4c-f2422625ba71'::uuid,'nenhum',null,0.2),
  ('5a61d45b-b3dc-4bd2-bd7c-da96c4982f72'::uuid,'nenhum',null,0.2),
  ('d2197dbe-52e3-4bba-a13d-ef1736c9b41a'::uuid,'nenhum',null,0.2),
  ('98b65aae-c97f-4c8b-905f-2cc5bce1cef9'::uuid,'nenhum',null,0.2),
  ('a25af8fe-8a5b-40af-8d89-b3b73a769934'::uuid,'nenhum',null,0.2),
  ('fa9feaa5-52f7-4225-a951-7e89f7a8f325'::uuid,'nenhum',null,0.2),
  ('70092082-3fd6-4e04-ab55-1cebc46ebe28'::uuid,'nenhum',null,0.2),
  ('337677e0-0c62-415d-9682-dc023e9b746d'::uuid,'nenhum',null,0.2),
  ('048cda93-d91d-4bf8-a195-893a1cdafcbb'::uuid,'nenhum',null,0.2)
) as v(id, sistema, verbo, conf)
where s.id = v.id;
