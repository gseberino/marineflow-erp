-- Comprovantes F1 (11/10/2026): bucket PRIVADO 'comprovantes' para o original de cada arquivo.
--
-- Caminho: AAAA/MM/<comprovante_id>.<ext> (mês de São Paulo da chegada). Um objeto por linha de
-- public.comprovantes: apagar o objeto de um duplicado nunca apaga o original de outro CMP.
--
-- Sem policy nenhuma em storage.objects para este bucket, de propósito (como o 'pdf-agente'):
-- anon e authenticated não leem nem escrevem; só a service role (que ignora RLS) mexe. O leitor
-- do PC baixa por URL assinada de 24 h que a edge cria. Não reusa o 'expense-receipts' (qualquer
-- logado apaga lá).
--
-- GRAVA DADO — OK NOMEADO: uma linha em storage.buckets. Idempotente.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('comprovantes', 'comprovantes', false, 20971520,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
              'application/pdf', 'application/xml', 'text/xml'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Prova. Cada expressão de cada policy de storage.objects (qual e with_check, separadas) tem de
-- começar por um filtro de IGUALDADE com um bucket literal: "(bucket_id = 'x'::text)" sozinho ou
-- "((bucket_id = 'x'::text) AND …)" — o Postgres reescreve a expressão com todos os parênteses,
-- então um "OR" no topo, um "bucket_id <> 'x'" ou um "bucket_id is not null" não passam. Conferido
-- em 11/10/2026: as 22 policies de produção seguem este formato.
do $$
declare
  v_filtro constant text := '^\((\(bucket_id = ''[^'']+''::text\) AND .+|bucket_id = ''[^'']+''::text)\)$';
  v_nome text;
begin
  if not exists (select 1 from storage.buckets where id = 'comprovantes' and public = false) then
    raise exception 'bucket comprovantes não ficou privado';
  end if;
  select p.policyname into v_nome
    from pg_policies p
   where p.schemaname = 'storage' and p.tablename = 'objects'
     and ((p.qual is null and p.with_check is null)
          or (p.qual is not null and p.qual !~ v_filtro)
          or (p.with_check is not null and p.with_check !~ v_filtro))
   limit 1;
  if v_nome is not null then
    raise exception 'policy % em storage.objects sem filtro de igualdade de bucket: o bucket comprovantes ficaria exposto', v_nome;
  end if;
  if exists (
    select 1 from pg_policies
     where schemaname = 'storage'
       and position('''comprovantes''' in coalesce(qual, '') || coalesce(with_check, '')) > 0
  ) then
    raise exception 'alguma policy de storage cita o bucket comprovantes: ele é só da service role';
  end if;
end $$;

insert into supabase_migrations.schema_migrations (version, name)
values ('20261011101000', 'comprovantes_bucket')
on conflict do nothing;
