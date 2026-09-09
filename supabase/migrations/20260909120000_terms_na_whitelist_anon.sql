-- NOVO-lev-40 (o mais grave da frente Levantamento — CONTRATUAL): os TERMOS nunca
-- chegavam ao cliente. A migration 20260723080000 trocou a leitura anônima de
-- app_settings por whitelist e as 5 chaves terms_* ficaram de fora — regressão datada:
-- desde 23/07 a tela pública (PublicServiceOrderView) renderiza o documento SEM os
-- termos de garantia/cancelamento/entrega/responsabilidades/gerais, e o cliente
-- Rodrigo assinou em 29/07 com accepted_terms_snapshot vazio.
--
-- Correção: as 5 chaves entram na whitelist. São texto contratual FEITO para o cliente
-- ler — não há dado sensível; o risco era a ausência, não a exposição.
--
-- Rollback: recriar a policy sem as 5 chaves terms_*.

drop policy if exists "anon_public_settings_whitelist" on public.app_settings;

create policy "anon_public_settings_whitelist" on public.app_settings
  for select to anon
  using (
    key like 'public_view_%' or key in (
      'company_name','company_logo_url','company_address','company_city','company_state',
      'company_neighborhood','company_postal_code','company_country',
      'address_line_1','address_number','neighborhood','city','postal_code',
      'phone','email','cnpj','pix_key','bank_name','bank_agency','bank_account',
      'app_public_url','base_currency','display_currency','language','card_fee_percent',
      -- NOVO-lev-40: termos contratuais que a tela pública de assinatura precisa exibir
      'terms_general','terms_warranty','terms_cancellation','terms_delivery','terms_responsibilities'
    )
  );

-- Auto-registro da versão do ARQUIVO (regra 1 do CLAUDE.md): a aplicação via MCP grava
-- timestamp próprio; esta linha garante que um futuro `db push` não tente reexecutar.
insert into supabase_migrations.schema_migrations (version, name)
values ('20260909120000', 'terms_na_whitelist_anon')
on conflict (version) do nothing;
