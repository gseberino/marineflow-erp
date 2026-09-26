-- Bucket 'documents' (PDF de orçamento/OS que a tela manda pelo WhatsApp): fecha as regras.
--
-- ═══ O QUE ESTAVA EXPOSTO (conferido em 26/09/2026) ═══
--
-- documents_public_read dava SELECT a ANON no bucket inteiro. As funções de listagem do
-- Storage rodam com a permissão de quem chama, então qualquer pessoa com a chave publicável
-- (que vai dentro do front, como em todo app Supabase) listava os 41 PDFs — com CPF/CNPJ,
-- telefone, e-mail e endereço de clientes e o PIX da HBR — e baixava pelo link público.
-- Provado com `set local role anon`: 41 objetos visíveis. Além disso, QUALQUER conta logada
-- podia sobrescrever (UPDATE) e apagar (DELETE) o PDF de qualquer um.
--
-- ═══ O QUE FICA ═══
--
-- Só quem SUBIU o arquivo (owner_id) — ou um administrador — lê e apaga. É o que o envio pela
-- tela precisa: sobe, gera o link assinado (exige SELECT no objeto) e apaga depois. UPDATE sai:
-- nenhum código faz update/upsert no bucket (use-whatsapp-send.ts sobe com upsert:false).
-- INSERT continua para qualquer conta logada, como hoje — nenhum cargo perde o envio.
--
-- Esta migration é a CONTENÇÃO e não quebra nada: o bucket continua public=true até o front
-- novo (link assinado) estar no ar; o link público de download não passa pela RLS. O
-- fechamento de verdade é a migration seguinte (public=false).

drop policy if exists documents_public_read on storage.objects;
drop policy if exists documents_authenticated_update on storage.objects;
drop policy if exists documents_authenticated_delete on storage.objects;

create policy documents_dono_le on storage.objects
  for select to authenticated
  using (
    bucket_id = 'documents'
    and (owner_id = (select auth.uid())::text or public.is_admin((select auth.uid())))
  );

create policy documents_dono_apaga on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'documents'
    and (owner_id = (select auth.uid())::text or public.is_admin((select auth.uid())))
  );

do $$
begin
  -- Nenhuma regra do bucket pode alcançar anon/public.
  if exists (
    select 1 from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and (coalesce(qual, '') || coalesce(with_check, '')) like '%''documents''%'
       and (roles && array['anon', 'public']::name[])
  ) then
    raise exception 'ainda há regra do bucket documents para anon/public';
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('documents_public_read', 'documents_authenticated_update', 'documents_authenticated_delete')
  ) then
    raise exception 'regra antiga do bucket documents continua de pé';
  end if;
end $$;
