-- Bucket PRIVADO para o PDF que o assistente manda pelo WhatsApp (send_document_pdf_to_self).
--
-- O arquivo existe por segundos: a Edge Function sobe o PDF, gera uma URL assinada de 10
-- minutos, a Evolution baixa por ela para anexar na conversa, e a tool apaga o objeto logo
-- depois do envio (no sucesso e na falha).
--
-- Por que não o bucket 'documents', que a tela já usa: ele é PÚBLICO, com leitura para anon
-- no bucket inteiro e sem limpeza — hoje guarda para sempre os PDFs de orçamento enviados
-- pela tela. O PDF leva preço, PIX e dados do cliente; o do assistente não entra lá.
--
-- Sem policy nenhuma em storage.objects para este bucket, de propósito: anon e authenticated
-- não leem nem escrevem; só a service role (que ignora RLS) mexe. Conferido em 25/09/2026:
-- as 24 policies de storage.objects filtram por bucket_id, então nenhuma alcança este.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pdf-agente', 'pdf-agente', false, 26214400, array['application/pdf'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (select 1 from storage.buckets where id = 'pdf-agente' and public = false) then
    raise exception 'bucket pdf-agente não ficou privado';
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and coalesce(qual, '') not ilike '%bucket_id%'
       and coalesce(with_check, '') not ilike '%bucket_id%'
  ) then
    raise exception 'há policy em storage.objects sem filtro de bucket: o bucket pdf-agente ficaria exposto';
  end if;
end $$;
