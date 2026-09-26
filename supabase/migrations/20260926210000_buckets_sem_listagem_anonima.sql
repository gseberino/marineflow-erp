-- Buckets com dado de cliente: ninguém anônimo LISTA mais o conteúdo.
--
-- ═══ O QUE ESTAVA EXPOSTO (conferido em 26/09/2026) ═══
--
-- É a mesma exposição que o bucket 'documents' tinha (20260926180000): uma regra de SELECT
-- para public/anon só com `bucket_id = ...`. As funções de listagem do Storage
-- (storage.search, search_v2, list_objects_with_delimiter) são SECURITY INVOKER e anon tem
-- EXECUTE nelas, então quem tem a chave publicável (vai dentro do front) lista o bucket e
-- depois baixa cada arquivo pelo link público. Provado com `set local role anon`:
--
--   signatures            6 objetos visíveis — 3 PDFs 'signed-*.pdf' (o orçamento assinado,
--                         com os dados do cliente) e 3 PNGs de assinatura, em
--                         <service_order_id>/. A listagem da raiz entrega os 3 ids de OS.
--   whatsapp_status       3 imagens visíveis.
--   expense-receipts      0 hoje, mas todo comprovante de despesa/sinal (PIX com nome, banco
--                         e valor) que subir amanhã já nasceria listável.
--   service-order-photos  0 hoje, idem para as fotos de OS e de levantamento.
--
-- ═══ O QUE FICA ═══
--
-- CONTENÇÃO, não fechamento: os quatro continuam public=true. O link público por caminho
-- exato (/object/public/...) não passa pela RLS e continua abrindo — é o que o portal do
-- cliente (share token), a tela interna, o PDF e a Evolution usam. Os caminhos têm UUID/id de
-- OS e só chegam a quem já recebeu o link. O que acaba é descobrir os caminhos listando.
--
-- Leitura para LOGADO só onde o código precisa dela (conferido no storage-js 2.105, que é a
-- versão do front: upload novo exige só INSERT; upload com upsert exige SELECT+INSERT+UPDATE;
-- remove exige SELECT+DELETE; getPublicUrl não exige nada):
--
--   expense-receipts      "remover comprovante" no sinal (RegisterDepositDialog) e na despesa
--                         da OS (ServiceOrderForm) chama remove(). Sem SELECT o DELETE do
--                         Storage não enxerga a linha, apaga ZERO objetos e devolve sucesso —
--                         o comprovante ficaria no bucket, abrindo pelo link, sem ninguém saber.
--   service-order-photos  "Excluir esta foto" (ServiceOrderPhotos) chama remove() — mesmo
--                         problema, pior: a foto some da tela e continua no ar. E a foto do
--                         levantamento (uploadSurveyPhoto) sobe com upsert:true, que sem
--                         SELECT falha com erro de RLS e o técnico não consegue anexar.
--
-- ═══ A LEITURA DO LOGADO SEGUE A TABELA DONA DE CADA CAMINHO ═══
--
-- As duas regras novas NÃO são as antigas com `to authenticated`. Cada bucket guarda dois tipos
-- de arquivo, e cada tipo pertence a uma tabela com RLS própria (pg_policies de 26/09/2026):
--
--   expense-receipts      expenses/<os>/   comprovante de despesa da OS — service_order_expenses:
--                                          qualquer logado.
--                         deposits/<os>/   comprovante de SINAL (PIX com nome, banco e valor do
--                                          cliente) — payments: só is_admin_or_financial.
--   service-order-photos  <os>/            foto da OS — service_order_photos: qualquer logado.
--                         surveys/<id>/    foto do levantamento — service_surveys e
--                                          service_survey_answers: NOT is_external_seller.
--
-- Uma regra só com `bucket_id = ...` deixaria técnico e vendedor externo listarem os
-- comprovantes de sinal, e o vendedor externo listar as fotos de levantamento — dado que as
-- tabelas donas já escondem deles. Por isso:
--
--   expense_receipts_logado_le  expenses/ para qualquer logado; o resto (deposits/) só para
--                               admin/financeiro OU para quem subiu o arquivo (owner_id, que a
--                               API do Storage grava com o `sub` do JWT). O dono é o que mantém
--                               o "remover comprovante" do RegisterDepositDialog: ele só apaga o
--                               arquivo que o próprio usuário acabou de anexar, antes de o sinal
--                               existir.
--   so_photos_logado_le         tudo, menos surveys/ para vendedor externo. O upsert da foto do
--                               levantamento (use-service-survey.ts, upsert:true) exige que a
--                               linha nova passe no SELECT: passa para técnico, admin, financeiro
--                               e vendedor interno (is_external_seller = false); o vendedor
--                               externo nem chega ao levantamento, a tabela já o barra.
--
-- O que muda para quem está logado: técnico e vendedor deixam de LISTAR sinal que não subiram, e
-- o vendedor externo deixa de listar foto de levantamento. Como remove() também passa pelo
-- SELECT, eles deixam igualmente de APAGAR esses arquivos pela API (as regras de DELETE
-- continuam só com o bucket) — o que nenhuma tela faz. Nenhuma tela perde função, e o link
-- público por caminho exato continua abrindo para todos (é CONTENÇÃO, ver acima).
--
-- signatures e whatsapp_status NÃO ganham regra para logado, porque nenhum código precisa:
-- o bucket signatures só é escrito pela edge submit-signature com a chave de serviço (que
-- ignora a RLS), e a tela de status só faz upload novo + getPublicUrl. Efeito colateral
-- conhecido: whatsapp_status_auth_delete fica inerte pela API (remove exige SELECT) — nenhum
-- código apaga desse bucket; o painel do Supabase usa a chave de serviço.
--
-- company-assets (logo) e product-images (fotos de catálogo) continuam com leitura pública:
-- são públicos por natureza e não têm dado de cliente.

drop policy if exists signatures_public_read on storage.objects;
drop policy if exists expense_receipts_public_read on storage.objects;
drop policy if exists so_photos_bucket_select on storage.objects;
drop policy if exists whatsapp_status_public_read on storage.objects;

-- Reaplicar a migration não pode falhar por nome repetido.
drop policy if exists expense_receipts_logado_le on storage.objects;
drop policy if exists so_photos_logado_le on storage.objects;

create policy expense_receipts_logado_le on storage.objects
  for select to authenticated
  using (
    bucket_id = 'expense-receipts'
    and (
      name like 'expenses/%'
      or owner_id = (select auth.uid())::text
      or public.is_admin_or_financial((select auth.uid()))
    )
  );

create policy so_photos_logado_le on storage.objects
  for select to authenticated
  using (
    bucket_id = 'service-order-photos'
    and (
      name not like 'surveys/%'
      or not public.is_external_seller((select auth.uid()))
    )
  );

do $$
declare
  v_sobra text;
begin
  -- 1. Nenhuma regra que LÊ (SELECT ou ALL) desses quatro buckets pode alcançar anon/public.
  --    Julga pelo texto da regra, não pelo nome: em produção as regras do whatsapp_status
  --    nasceram fora das migrations e o nome de uma regra criada à mão pode ser qualquer um.
  select string_agg(policyname, ', ') into v_sobra
    from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd in ('SELECT', 'ALL')
     and roles && array['anon', 'public']::name[]
     and (coalesce(qual, '') || coalesce(with_check, ''))
         ~ '''(signatures|expense-receipts|service-order-photos|whatsapp_status)''';
  if v_sobra is not null then
    raise exception 'ainda há regra de leitura para anon/public nos buckets com dado de cliente: %', v_sobra;
  end if;

  -- 2. Nem regra de leitura SEM filtro de bucket para anon, public ou authenticated: para anon
  --    ela abriria todos os buckets de uma vez; para authenticated, reabriria por OR o que as
  --    duas regras abaixo fecham (sinal para técnico, levantamento para vendedor externo).
  select string_agg(policyname, ', ') into v_sobra
    from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd in ('SELECT', 'ALL')
     and roles && array['anon', 'public', 'authenticated']::name[]
     and coalesce(qual, '') not like '%bucket_id%';
  if v_sobra is not null then
    raise exception 'há regra de leitura em storage.objects sem filtro de bucket: %', v_sobra;
  end if;

  -- 3. As duas leituras que o código precisa existem, só SELECT e só para authenticated.
  if (select count(*) from pg_policies
       where schemaname = 'storage' and tablename = 'objects'
         and policyname in ('expense_receipts_logado_le', 'so_photos_logado_le')
         and cmd = 'SELECT'
         and roles = array['authenticated']::name[]) <> 2 then
    raise exception 'as regras de leitura para logado de expense-receipts/service-order-photos não ficaram como esperado';
  end if;

  -- 4. E seguem a tabela dona de cada caminho (o texto é o que o Postgres guarda, já
  --    normalizado: `name ~~ 'expenses/%'::text`, `NOT is_external_seller(...)`).
  if not exists (
       select 1 from pg_policies
        where schemaname = 'storage' and tablename = 'objects'
          and policyname = 'expense_receipts_logado_le'
          and position('''expenses/%''' in qual) > 0
          and position('owner_id' in qual) > 0
          and position('is_admin_or_financial' in qual) > 0) then
    raise exception 'expense_receipts_logado_le não restringe deposits/ a admin/financeiro ou ao dono';
  end if;
  if not exists (
       select 1 from pg_policies
        where schemaname = 'storage' and tablename = 'objects'
          and policyname = 'so_photos_logado_le'
          and position('''surveys/%''' in qual) > 0
          and position('is_external_seller' in qual) > 0) then
    raise exception 'so_photos_logado_le não esconde surveys/ do vendedor externo';
  end if;

  -- 5. Nenhuma OUTRA regra de leitura cita esses dois buckets. Regras PERMISSIVE somam por OR:
  --    uma `bucket_id = 'expense-receipts'` a mais, criada à mão no painel, desfaria o 4 inteiro.
  select string_agg(policyname, ', ') into v_sobra
    from pg_policies
   where schemaname = 'storage' and tablename = 'objects'
     and cmd in ('SELECT', 'ALL')
     and policyname not in ('expense_receipts_logado_le', 'so_photos_logado_le')
     and (coalesce(qual, '') || coalesce(with_check, ''))
         ~ '''(expense-receipts|service-order-photos)''';
  if v_sobra is not null then
    raise exception 'há outra regra de leitura em expense-receipts/service-order-photos: %', v_sobra;
  end if;
end $$;
