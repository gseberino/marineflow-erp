-- FASE 1 do conserto do link público. Só banco, sem mexer no frontend.
--
-- Contexto: as políticas anônimas do link público checam apenas
-- "share_token IS NOT NULL" — nunca comparam o token apresentado. Quem tem a
-- chave publicável (que vai no bundle, por definição) lê TODAS as OS
-- compartilhadas, não só a sua. O filtro por token existe, mas mora no
-- frontend, e filtro de cliente não é controle de acesso.
--
-- Esta fase corrige o que dá para corrigir sem deploy coordenado. A amarração do
-- token em si é a fase 2 e exige mudança no app.

-- 1) Assinaturas: a política CERTA já existia (compara so.share_token com
--    signatures.share_token), mas ao lado dela havia uma frouxa. Políticas são
--    somadas com OU, então a frouxa anulava a correta. Removida.
--    Conferido antes: a única assinatura existente tem token batendo com a OS,
--    então nada deixa de ser visível para quem tem o link legítimo.
drop policy if exists anon_service_order_signatures_via_share_token on public.service_order_signatures;

-- 2) Condições de pagamento: a política era "true" — catálogo comercial inteiro
--    aberto. Passa a expor só os presets efetivamente usados em OS compartilhada
--    (4 de 11 hoje), que é o que a tela pública precisa mostrar.
drop policy if exists anon_payment_condition_presets_select on public.payment_condition_presets;

create policy anon_payment_condition_presets_via_share_token
  on public.payment_condition_presets
  for select
  to anon
  using (
    exists (
      select 1 from public.service_orders so
       where so.payment_condition_preset_id = payment_condition_presets.id
         and so.share_token is not null
    )
  );
