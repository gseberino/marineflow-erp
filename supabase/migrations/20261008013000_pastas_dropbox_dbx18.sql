-- DBX-18 (08/10/2026): arquivos soltos da MANAGEMENT levados para a pasta de cada cliente.
-- Registra as 3 pastas novas (numeradas no padrão do dono) e atualiza as 2 duplicadas, que
-- viraram subpastas das principais. Idempotente.

insert into public.pastas_dropbox (dropbox_id, caminho, client_id, vessel_id, codigo_projeto, situacao, observacao)
values
  ('id:sZCHZmtLl2AAAAAAAACi2g', '/MANAGEMENT/COMMERCIAL/B2C/0023.004.26_CAT33_Kalmar',
   'a45ed319-7bdb-40ea-b671-7fff67d1657b', '799d65f8-f98c-4d61-a8dc-bdb30bc68f67', '0023.004.26', 'vinculada',
   'Criada em 08/10/2026 com as propostas do CAT33 (Paulo Pamplona) que estavam soltas na raiz da MANAGEMENT.'),
  ('id:sZCHZmtLl2AAAAAAAACi3A', '/MANAGEMENT/COMMERCIAL/B2C/0024.005.26_Trust',
   '2a6ec19c-8cc9-4f17-9060-a370a13b4afa', '60cf7e2f-67c5-4a9c-af72-7f385e921eef', '0024.005.26', 'vinculada',
   'Criada em 08/10/2026 com o orçamento do Trust que estava solto na COMMERCIAL.'),
  ('id:sZCHZmtLl2AAAAAAAACi3g', '/MANAGEMENT/COMMERCIAL/B2C/0025.006.26_Overland_Vegini',
   'adf63c17-f6e6-4057-9491-960783a0c99e', 'e163d478-00ee-4336-b017-c33920dd586d', '0025.006.26', 'vinculada',
   'Criada em 08/10/2026 com os ORÇ-61 e ORÇ-62 que estavam soltos na raiz da MANAGEMENT.')
on conflict (dropbox_id) do update
   set caminho = excluded.caminho, client_id = excluded.client_id, vessel_id = excluded.vessel_id,
       codigo_projeto = excluded.codigo_projeto, situacao = excluded.situacao, observacao = excluded.observacao;

update public.pastas_dropbox
   set caminho = '/MANAGEMENT/COMMERCIAL/B2C/0020.001.26_La_Osadia/1- DOC''s',
       situacao = 'arquivo',
       observacao = 'Era a pasta duplicada "LA OSADIA - Jose Antonio Yege"; em 08/10/2026 virou a subpasta 1- DOC''s da 0020.001.26_La_Osadia.'
 where dropbox_id = 'id:sZCHZmtLl2AAAAAAAACalg';

update public.pastas_dropbox
   set caminho = '/MANAGEMENT/COMMERCIAL/B2C/LOBO DO MAR - Rafael Casagrande/2023 - Orçamentos antigos',
       situacao = 'arquivo',
       observacao = 'Era a pasta duplicada "CASAGRANDE - LOBO DO MAR"; em 08/10/2026 virou subpasta da LOBO DO MAR - Rafael Casagrande.'
 where dropbox_id = 'id:sZCHZmtLl2AAAAAAAAAAaw';
