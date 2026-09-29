-- Assinaturas e comprovantes em bucket PRIVADO (decisão do dono, 29/09/2026: "Sim, pode fechar").
--
-- Os buckets `signatures` e `expense-receipts` eram públicos: a listagem anônima foi fechada em
-- 26/09, mas quem tivesse o link baixava o arquivo sem login, para sempre. O PDF assinado traz
-- nome, CPF/CNPJ e endereço do cliente. Agora:
--   * os dois buckets ficam privados (link público para de funcionar);
--   * admin e financeiro leem `signatures` para a ficha da OS gerar link temporário; técnico e
--     vendedor continuam sem ver (o PDF traz CPF e endereço). expense-receipts já tinha a regra
--     expense_receipts_logado_le (despesa: qualquer logado; sinal: admin/financeiro ou quem subiu);
--   * o cliente sem login vê a IMAGEM da assinatura pela edge assinatura-do-link, que confere o
--     token da OS; o PDF assinado só abre para quem está logado;
--   * as colunas *_url passam a guardar o CAMINHO no bucket (a regra de leitura, que aceita
--     também o link antigo, é _shared/arquivo-privado.ts).
--
-- Dados convertidos: 3 imagens e 3 PDFs em service_order_signatures e 4 cópias em
-- service_orders.client_signature_url. Comprovantes: nenhum registro usa (0 objetos no bucket).
-- O gatilho de "alterado depois da assinatura" não olha client_signature_url.
--
-- ORDEM: publicar o site e as edges (submit-signature, assinatura-do-link) junto com esta
-- migration; a tela antiga mostraria "imagem indisponível" no lugar da assinatura até o site novo.

update storage.buckets set public = false where id in ('signatures', 'expense-receipts');

drop policy if exists assinaturas_admin_financeiro_le on storage.objects;
create policy assinaturas_admin_financeiro_le on storage.objects
  for select to authenticated
  using (bucket_id = 'signatures' and public.is_admin_or_financial((select auth.uid())));

update public.service_order_signatures
   set signature_image_url = regexp_replace(signature_image_url, '^.*/object/public/signatures/', '')
 where signature_image_url like '%/object/public/signatures/%';

update public.service_order_signatures
   set signed_pdf_url = regexp_replace(signed_pdf_url, '^.*/object/public/signatures/', '')
 where signed_pdf_url like '%/object/public/signatures/%';

update public.service_orders
   set client_signature_url = regexp_replace(client_signature_url, '^.*/object/public/signatures/', '')
 where client_signature_url like '%/object/public/signatures/%';

insert into supabase_migrations.schema_migrations (version, name)
values ('20260929220000', 'assinaturas_e_comprovantes_privados')
on conflict do nothing;
