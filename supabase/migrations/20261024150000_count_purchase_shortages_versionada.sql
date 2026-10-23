-- MF-AUD-058: count_purchase_shortages versionada a partir do snapshot.
-- Agenda de Produção, Fase 0, pacote P5 (passo 1). Spec: scratchpad agenda-pesquisa/spec-fase0.md.
--
-- VERSIONA O QUE JÁ RODA; APLICAR É NO-OP (CREATE OR REPLACE idêntico).
--
-- A função existe em produção desde antes do repositório guardar todas as migrations (MF-AUD-058: SQL
-- aplicado sem arquivo). Ela é o que o motor R16 (task-automations/rules.ts) chama para saber quantos
-- itens faltam comprar por OS, e só aparecia no snapshot supabase/schemas/producao/05-funcoes.sql:5771-5789.
-- O P5 mexe na família (get_os_purchase_needs e classify_service_text, nas migrations 150100 e 150200):
-- sem este arquivo, a próxima mudança nela partiria de um texto que o repositório não tinha.
--
-- O corpo abaixo é cópia EXATA do pg_get_functiondef de produção, conferido em 23/10/2026:
--   md5 94c8a07fdc881616b984b2ce82c43422, 475 caracteres (f11_defs), igual ao do snapshot.
-- O comentário é o de produção (obj_description, f22). A ACL de produção já é
-- {postgres, authenticated, service_role}: o revoke de public/anon e o grant abaixo só a deixam escrita.
--
-- APLICAR (CLAUDE.md, regra 1 — só com o OK):
--   npx supabase db query --linked -f supabase/migrations/20261024150000_count_purchase_shortages_versionada.sql
--   npx supabase db query --linked -e "insert into supabase_migrations.schema_migrations (version, name)
--     values ('20261024150000', 'count_purchase_shortages_versionada');"

CREATE OR REPLACE FUNCTION public.count_purchase_shortages(p_so_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_object_agg(
           t.so_id,
           (public.get_os_purchase_needs(t.so_id)->>'shortageCount')::int
         ), '{}'::jsonb)
  from (select distinct unnest(coalesce(p_so_ids, '{}'::uuid[])) as so_id) t
  where (public.get_os_purchase_needs(t.so_id)->>'shortageCount')::int > 0;
$function$
;

COMMENT ON FUNCTION public.count_purchase_shortages(p_so_ids uuid[]) IS 'Quantos itens faltam comprar, por OS, em lote. Fonte unica da regra: o motor R16 consome em vez de reimplementar a formula em Deno.';

revoke all on function public.count_purchase_shortages(uuid[]) from public, anon;
grant execute on function public.count_purchase_shortages(uuid[]) to authenticated, service_role;
