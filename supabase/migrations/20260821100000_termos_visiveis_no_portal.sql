-- ═══════════════════════════════════════════════════════════════════════════
-- As cinco chaves de termos passam a ser visíveis no portal público
--
-- ═══ O QUE ESTAVA ACONTECENDO (NOVO-lev-40) ═══
--
-- `terms_general`, `terms_warranty`, `terms_cancellation`, `terms_delivery` e
-- `terms_responsibilities` existem no banco e ficaram FORA da whitelist do
-- `anon`. Provado com `set role anon`: as cinco existem, o anônimo enxerga zero.
--
-- Três efeitos, e o terceiro é o que pesa:
--   1. a seção de termos nunca renderiza no portal, embora
--      `public_view_show_terms` esteja `true` — o dono ligou e nada aparece;
--   2. o PDF que o cliente baixa sai sem termos;
--   3. `computeDocumentHash(order, services, termsText)` recebe o texto VAZIO.
--      O hash que existe para provar o que foi assinado estava provando um
--      documento SEM garantia, cancelamento, prazo de entrega e
--      responsabilidades.
--
-- ═══ POR QUE É SEGURO LIBERAR ═══
--
-- São os termos que a empresa já publica junto da proposta — o cliente precisa
-- lê-los ANTES de assinar, que é o ponto inteiro do portal. Não há dado de
-- terceiro, preço ou informação interna neles.
--
-- Só as cinco. A whitelist continua nominal: nada de `terms_%`, que abriria
-- qualquer chave futura começando com esse prefixo sem ninguém decidir.
-- ═══════════════════════════════════════════════════════════════════════════
begin;

drop policy if exists anon_public_settings_whitelist on public.app_settings;

create policy anon_public_settings_whitelist on public.app_settings
  for select to anon
  using (
    key like 'public_view_%'
    or key = any (array[
      -- Identificação e endereço da empresa, como já era.
      'company_name', 'company_logo_url', 'company_address', 'company_city',
      'company_state', 'company_neighborhood', 'company_postal_code',
      'company_country', 'address_line_1', 'address_number', 'neighborhood',
      'city', 'postal_code', 'phone', 'email', 'cnpj',
      -- Dados de pagamento que a proposta já carrega.
      'pix_key', 'bank_name', 'bank_agency', 'bank_account',
      -- Configuração de apresentação.
      'app_public_url', 'base_currency', 'display_currency', 'language',
      'card_fee_percent',
      -- NOVO-lev-40: os termos que o cliente assina. Sem estes, ele aceitava um
      -- documento cujas condições nunca lhe foram mostradas.
      'terms_general', 'terms_warranty', 'terms_cancellation',
      'terms_delivery', 'terms_responsibilities'
    ])
  );

comment on policy anon_public_settings_whitelist on public.app_settings is
  'O que o portal público pode ler de app_settings. Lista NOMINAL de propósito:
   `terms_%` abriria qualquer chave futura com esse prefixo sem decisão de
   ninguém. Inclui as cinco chaves de termos desde 21/08/2026 — o cliente assina
   o documento e precisa lê-las antes (NOVO-lev-40).';

commit;
