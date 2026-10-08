-- Dropbox: fim do ensaio, passa a valer a pasta real (08/10/2026 — plans/marineflow-dropbox-fase2.md).
-- O ensaio em /HBR-Testes/B2C passou (pasta 0026.007.26_Above_Beyond com as 8 subpastas, PDF
-- "2026-10-08 ORÇ-00113 v1.pdf" com o Ç certo, repetição barrada por "sem mudança"). Aqui:
--   1. esquece o que o ensaio registrou (senão o barco ficaria preso à pasta de teste, o número
--      0026.007.26 ficaria gasto e o "sem mudança" barraria o primeiro envio de verdade);
--   2. a pasta-base passa a ser a dos clientes.
-- A pasta /HBR-Testes no Dropbox fica como está (o sistema nunca apaga nada lá).

delete from public.dropbox_envios
 where caminho like '/HBR-Testes/%'
    or order_id in (select so.id from public.service_orders so
                     join public.pastas_dropbox p on p.vessel_id = so.vessel_id
                    where p.caminho like '/HBR-Testes/%');

delete from public.pastas_dropbox where caminho like '/HBR-Testes/%';

update public.app_settings set value = '/MANAGEMENT/COMMERCIAL/B2C', updated_at = now()
 where key = 'dropbox_pasta_base';
