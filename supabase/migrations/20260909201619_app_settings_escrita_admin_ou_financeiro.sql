-- Recuperada do transcript da sessão (C--Users-PC/a12c77fb-6295-4d2c-86c2-da5fd7d7a34a.jsonl, 2026-09-09T20:16:32.909Z) em 14/09/2026 —
-- a migration foi aplicada em produção pela ferramenta MCP apply_migration, que registrou a
-- versão 20260909201619 sem gravar arquivo no repositório (MF-AUD-058). Conteúdo abaixo é o que
-- foi enviado ao banco naquela chamada.

-- MF-AUD-062 / MF-AUD-014 item 4: a tela de Configurações exige admin, mas o banco
-- aceitava INSERT/UPDATE/DELETE de QUALQUER autenticado em QUALQUER chave (exceto
-- cron_worker_secret) — técnico podia gravar chave direto pela API REST, inclusive
-- as que derrubam painéis quando malformadas (NOVO-lev-32, survey_valor_limiar).
--
-- Pré-condição satisfeita: o PDFOptionsDialog parou de persistir em app_settings
-- (MF-AUD-014, integrado 11/08) — apertar a escrita não quebra PDF de não-admin.
-- Escrita = is_admin_or_financial (painéis de agenda/cobrança/WhatsApp são usados
-- pelo financeiro); leitura segue como estava; deny_internal_secrets (RESTRICTIVE)
-- permanece por cima de tudo.

drop policy if exists "app_settings_auth_insert" on public.app_settings;
create policy "app_settings_auth_insert" on public.app_settings
  for insert to authenticated
  with check (is_admin_or_financial(auth.uid()) and key <> 'cron_worker_secret');

drop policy if exists "app_settings_auth_update" on public.app_settings;
create policy "app_settings_auth_update" on public.app_settings
  for update to authenticated
  using (is_admin_or_financial(auth.uid()) and key <> 'cron_worker_secret')
  with check (is_admin_or_financial(auth.uid()) and key <> 'cron_worker_secret');

drop policy if exists "app_settings_auth_delete" on public.app_settings;
create policy "app_settings_auth_delete" on public.app_settings
  for delete to authenticated
  using (is_admin_or_financial(auth.uid()) and key <> 'cron_worker_secret');

insert into supabase_migrations.schema_migrations (version, name)
values ('20260909160000', 'app_settings_escrita_admin_ou_financeiro')
on conflict (version) do nothing;
