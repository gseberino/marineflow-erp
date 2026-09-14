-- Registro em schema_migrations das migrations que foram aplicadas em produção por
-- 'db query -f' (que executa o SQL e não escreve no histórico) e nunca registradas —
-- MF-AUD-058, reconciliação de 14/09/2026 (audit/migrations-reconciliacao-20260914.md).
--
-- Evidência por arquivo (classe e contagem no comentário de cada linha): 'total' = todos os
-- objetos que o arquivo cria/altera/derruba estão em produção como ele descreve; 'parcial' =
-- diferenças explicadas (constraints derrubadas por migrations posteriores; revogações que uma
-- migration perdida reabriu — fila do dono); 'so_dados' = correções de dados executadas pelas
-- sessões que as escreveram (29/07 a 04/08, conferidas no livro); 'sem_evidencia' = grants,
-- search_path e RLS conferidos à mão no catálogo. Registrar é o que impede um 'db push'
-- futuro de reaplicar correção de dados e DDL sem IF NOT EXISTS.
--
-- Arquivos que compartilhavam timestamp foram renomeados para +1 s (o Supabase só admite um
-- arquivo por versão); o que casa com o nome registrado manteve a versão.

insert into supabase_migrations.schema_migrations (version, name) values
  ('20260515154305', '181f62a3-65ed-4079-9d89-f0546223e92c'),  -- sem_evidencia
  ('20260722220000', 'log_app_error_service_role'),  -- sem_evidencia
  ('20260724180001', 'fiscal_emission_drafts'),  -- total 12/12
  ('20260727120001', 'bank_transactions_dedupe_enriquecimento'),  -- total 4/4
  ('20260727120002', 'contact_identity'),  -- total 7/7
  ('20260727120003', 'get_promo_candidates_rpc'),  -- total 2/2
  ('20260727180001', 'balance_due_on_completion'),  -- total 3/3
  ('20260727180002', 'entity_open_loops'),  -- total 10/10
  ('20260727200000', 'balance_reminders_cron'),  -- total 1/1
  ('20260727200001', 'open_loops_fixes'),  -- parcial 7/11
  ('20260728010000', 'search_path_security_definer'),  -- sem_evidencia
  ('20260728015000', 'rls_anon_fase1_fecha_assinaturas_e_presets'),  -- sem_evidencia
  ('20260729211000', 'dedupe_extrato_fatura_cartao_sinonimos'),  -- sem_evidencia
  ('20260730010000', 'preenche_contraparte_pelo_cadastro'),  -- so_dados
  ('20260730020000', 'ciclo_servico_levantamento'),  -- parcial 17/18
  ('20260730120000', 'rls_compras_por_cargo'),  -- sem_evidencia
  ('20260731020001', 'ciclo_servico_materiais_e_margem'),  -- total 8/8
  ('20260731030000', 'categoria_comissoes'),  -- so_dados
  ('20260731040000', 'ciclo_servico_composicao_de_roteiro'),  -- parcial 11/13
  ('20260803120001', 'rpc_get_os_purchase_needs'),  -- total 2/2
  ('20260803140001', 'envio_real_de_cotacao'),  -- total 5/5
  ('20260804010000', 'credito_em_cartao_nunca_e_receita'),  -- so_dados
  ('20260804020000', 'pix_no_credito_nao_e_receita'),  -- so_dados
  ('20260805100001', 'separa_material_de_mao_de_obra')  -- total 7/7
on conflict (version) do nothing;

-- Auto-registro da versão deste arquivo (regra 1 do CLAUDE.md).

insert into supabase_migrations.schema_migrations (version, name)

values ('20260914100000', 'registra_migrations_aplicadas_sem_registro')

on conflict (version) do nothing;
