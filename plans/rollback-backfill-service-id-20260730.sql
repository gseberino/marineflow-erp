-- ROLLBACK do backfill de service_id em service_order_services (30/07/2026)
--
-- Estado ANTES do backfill: 56 das 135 linhas de serviço (41,5%) estavam sem
-- vínculo com o catálogo — texto digitado à mão. Rodar este arquivo devolve
-- exatamente esse estado, desfazendo todos os vínculos criados no backfill.
--
-- Não desfaz a CRIAÇÃO dos serviços novos no catálogo: para isso, desative-os
--   update public.services set active = false where id in (...);
-- em vez de apagar, senão as linhas já vinculadas perdem a referência.

update public.service_order_services set service_id = null where id in (
  '917601c0-87f6-4517-a6c4-80c707f87c9d', '8c902438-d45f-4124-80a1-52715ea4ba01',
  'a08a2316-1565-4b0b-9ec0-7a4f44c570b4', '16dc13f4-045d-435c-82c4-4096811d9b5b',
  'f583dbb6-7734-4122-a5d9-3a4454154b45', '5b7359b2-9edd-41e3-8251-890db72a29e9',
  'c421e01a-b25e-44a6-95cc-6fecaeeefef1', '0a78b8c2-dbf9-4024-8937-2e9379b6adf2',
  '41cb38a7-7a26-406f-81e0-c1e52fe55015', '8dfe7b48-462d-4625-9fa2-3927a8499f95',
  'e73b95ba-0cd0-4113-aec7-88098a8e0f7a', '173dd3b1-56f2-4780-856e-f5cbe2fe1c4a',
  '476662dc-ead5-4be1-8ce2-de05a33de4d6', '8f8c55bd-6330-4ca3-b445-57bc2deb5523',
  'dd8071a4-4f5e-4450-a612-3f27581fca48', '86caaca8-21d1-49fc-b33e-e8fd4385109f',
  '8b17ab9f-e3ef-44d8-8000-a9330c3125bc', '3bae14af-161a-45f8-8bcb-f07da54aa88b',
  '015d2b3e-1a92-4d36-a5d1-3c08d439f96d', 'c60f3963-1961-437f-b2ea-c73c0811a4c7',
  '87989976-44d6-4354-bab8-d3a23f41a7ac', '1bdea929-26b5-4e27-85f8-d6a5adb8a9c0',
  'e4f9966a-8b6a-4ca8-9ad4-996452d87df8', '7fb43bb6-9564-4ca3-b4b0-e82303ac3916',
  'af4400a6-13da-4996-bd8d-8166b92855d9', 'b4cf3999-6a0a-4509-953f-216be7d271cd',
  '8ef63ee9-624e-46bd-baf4-9f4a3f03d225', '3c733624-f353-4fbf-9a72-578e617874ec',
  '1377bf18-dcfc-47e5-a6e2-95b658daf921', 'd076b3cb-9322-4502-b2d2-a425de227824',
  'e3dccdf1-3124-4f94-a97a-b5ee9d8ef35f', '444cff73-1f72-484a-8db2-3aa7216b41fe',
  '044bfd1d-bbb5-4fda-820e-1084ee2c1233', 'b20bf535-f50a-4592-b2d9-6641c0571a04',
  '4d2e1bdb-db0f-42f6-84b2-1b01d8293062', '56913571-beca-4d4a-a768-832e1c41d788',
  '1eeeee2e-5e39-4ced-9607-eb56263c8aca', '63154e13-e428-468c-a979-da18569464ec',
  'ff4149e4-931d-444a-aa5d-d96a4dc42c9d', 'eede6dcb-f5ec-48ef-b888-4a8de410d699',
  'e49dd15d-0be5-4184-9c92-b492197af3f7', 'c605aeda-080d-4dde-be76-acf197bbc384',
  'c90320a5-0ab1-4892-9c0b-558113dc2deb', '26088684-5cca-4494-b7b0-848a705f2868',
  '73f4fc09-163a-4fb7-8c37-a35811b10df7', '5748fc22-5ab1-4bde-aded-f91208f3db36',
  'aa150dee-cfb6-4b1c-983c-9939dce00376', '0ecbfbbf-cc21-4ba2-a604-be4f10e3c46f',
  '225e3fc8-5307-4b3d-8741-d8de289228d4', '4ad37d9d-160a-4fbc-8bda-f063a2af1fdf',
  '58815ccd-caf2-4e45-8063-7d934c8051cd', '96c8a85a-59f0-4e82-b68c-ceb05c9eed7a',
  'd016e3d7-5d90-4cd8-ba8c-2e9098fd1905', '07388e42-94d9-4772-b1ef-f29ead1dd37b',
  '486d146c-ea06-45bb-9951-3e061d64719f', '579b725a-3540-444e-856b-09b1772ab0f1'
);
