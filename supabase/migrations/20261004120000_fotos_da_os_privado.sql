-- Fotos da OS e do levantamento: bucket PRIVADO (decisão do dono, 04/10/2026 — cartão
-- "fotos-os-privado": "Pode fechar").
--
-- Até aqui o bucket `service-order-photos` era público: quem tivesse o endereço de uma foto (o
-- barco, a casa do cliente) a via sem login e para sempre — o endereço ficava gravado em
-- service_order_photos.public_url. A listagem anônima já estava fechada desde 27/09 (migration
-- 20260927090000); faltava o link direto. Fechado com o bucket VAZIO (0 objetos, 0 linhas em
-- service_order_photos, 0 fotos de levantamento, conferido em 04/10): nada para de funcionar.
--
-- Daqui para a frente a tela gera link temporário a partir do caminho (src/lib/fotos-da-os.ts,
-- com a sessão de quem está logado; a regra de leitura `so_photos_logado_le` já existe), e o PDF
-- gerado no servidor usa a chave de serviço (_shared/pdf/fotos.ts).
--
-- `public_url` fica como coluna legada: a tela não grava mais nela, então ela perde o NOT NULL.

update storage.buckets
   set public = false
 where id = 'service-order-photos';

alter table public.service_order_photos
  alter column public_url drop not null;

comment on column public.service_order_photos.public_url is
  'LEGADO: link público de quando o bucket service-order-photos era público (até 04/10/2026). Não é mais gravado; a tela e o PDF geram link temporário a partir de storage_path.';
