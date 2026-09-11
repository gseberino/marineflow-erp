-- O PDF baixado pelo cliente no portal (anon + share-token) lê `company.state` de
-- app_settings pela chave `state` — que nunca esteve na whitelist anônima (a lista de
-- 20260723080000 tem `company_state`, um nome antigo que o gerador não usa). Resultado:
-- o endereço da empresa sai sem UF no documento que o cliente recebe. Cosmético, mas é
-- documento que sai da empresa.
--
-- Mesma whitelist da 20260909120000 (que trouxe as 5 chaves terms_*), agora com `state`.

drop policy if exists "anon_public_settings_whitelist" on public.app_settings;

create policy "anon_public_settings_whitelist" on public.app_settings
  for select to anon
  using (
    key like 'public_view_%' or key in (
      'company_name','company_logo_url','company_address','company_city','company_state',
      'company_neighborhood','company_postal_code','company_country',
      'address_line_1','address_number','neighborhood','city','state','postal_code',
      'phone','email','cnpj','pix_key','bank_name','bank_agency','bank_account',
      'app_public_url','base_currency','display_currency','language','card_fee_percent',
      'terms_general','terms_warranty','terms_cancellation','terms_delivery','terms_responsibilities'
    )
  );

-- Auto-registro da versão do arquivo (regra 1 do CLAUDE.md).
insert into supabase_migrations.schema_migrations (version, name)
values ('20260910130000', 'state_na_whitelist_anon')
on conflict (version) do nothing;
