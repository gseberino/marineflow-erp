-- NOVO-historico-03 (decisão do dono, 20/11/2026: "Admin e financeiro" — o mesmo cargo que já mexe nos termos e no
-- PIX, app_settings/NOVO-historico-04; o sistema continua gravando como sempre).
--
-- A policy auth_update_signatures de service_order_signatures deixava QUALQUER usuário logado (técnico, vendedor)
-- alterar a prova de assinatura do cliente pela API: nome aceito, hash do documento, imagem, "substituída em".
-- O histórico (trg_historico) registrava, mas não impedia.
--
-- QUEM GRAVA ASSINATURA HOJE (conferido no código e no banco em 20/11/2026):
--   · a assinatura do cliente: a página pública /view/:token chama a edge submit-signature, que grava com
--     service_role (INSERT da assinatura + UPDATE "Reassinatura solicitada" nas anteriores). service_role passa por
--     cima da RLS: NÃO muda nada aqui.
--   · a assinatura que deixa de valer quando o documento muda depois de assinado:
--       - private.linha_pede_nova_assinatura (gatilho das peças e serviços): já é SECURITY DEFINER, não muda;
--       - public.detect_so_change_after_signature (gatilho BEFORE UPDATE de service_orders): era SECURITY INVOKER,
--         ou seja, o UPDATE que ela faz nas assinaturas rodava COM O PAPEL DE QUEM EDITOU A OS. Restringir só a
--         policy faria a edição de um técnico/vendedor numa OS assinada deixar a assinatura velha valendo em
--         silêncio (UPDATE filtrado pela RLS = 0 linhas, sem erro). Por isso ela passa a SECURITY DEFINER, com o
--         mesmo corpo (só ALTER, nada reescrito).
--   · nenhuma tela grava a tabela (só lê: ServiceOrderSignatures, PublicServiceOrderView); assinatura-do-link e o
--     agrupar-os só leem.
--
-- O QUE MUDA
--   1. auth_update_signatures: UPDATE só para admin e financeiro (is_admin_or_financial, o mesmo helper de cargo da
--      app_settings — termos e PIX —, NOVO-historico-04). Técnico e vendedor externo ficam de fora.
--   2. detect_so_change_after_signature: SECURITY DEFINER, search_path fixo, EXECUTE só do dono (gatilho não
--      precisa de EXECUTE de quem dispara; ninguém a chama pela API).
--   3. Segunda barreira: anon perde INSERT/UPDATE/DELETE na tabela (nenhuma policy deixava; o portal só LÊ pelo
--      token, e esse SELECT continua).
--
-- O QUE NÃO MUDA: leitura (auth_read_signatures, anon_read_signatures_by_token), submit-signature, os gatilhos
-- trg_historico e trg_dropbox_assinatura, private.linha_pede_nova_assinatura.
--
-- PROVA: supabase/tests/assinaturas_admin_financeiro_altera.sql (begin … rollback).

drop policy if exists "auth_update_signatures" on public.service_order_signatures;
create policy "auth_update_signatures" on public.service_order_signatures
  for update to authenticated
  using (public.is_admin_or_financial((select auth.uid())))
  with check (public.is_admin_or_financial((select auth.uid())));

alter function public.detect_so_change_after_signature() security definer;
alter function public.detect_so_change_after_signature() set search_path = public, pg_temp;
revoke all on function public.detect_so_change_after_signature() from public, anon, authenticated;

revoke insert, update, delete on public.service_order_signatures from anon;
