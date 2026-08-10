# 21 — Banco de dados: migrations × schema × uso (Etapa 2, módulo 11)

Superfície: 243 arquivos em `supabase/migrations/`, `src/integrations/supabase/types.ts` (gerado, 10.523 l), e o
**estado real** do projeto `okurngvcodmljjicopdp` (`pg_tables`, `pg_policies`, `cron.job`,
`supabase_migrations.schema_migrations`) — tudo por consulta de leitura.

---

## 21.0 Panorama

| | Repositório | Banco de produção |
|---|---:|---:|
| Migrations | **243 arquivos** | **278 aplicadas** |
| Primeira / última | `20260407192937` / `20260808120000` | `20260407192937` / `20260808214128` |
| Tabelas em `public` | — | **121** |
| Views | — | ~10 |
| Funções/RPC | — | ~90 |
| Políticas RLS | — | 214 (1 RESTRICTIVE) |
| Jobs de cron | — | 17 (todos ativos) |

**35 migrations aplicadas não têm arquivo no repositório.**

---

## 21.1 Achados

### [MF-AUD-058] 35 migrations aplicadas em produção sem arquivo versionado — inclusive uma correção de segurança
- **Módulo:** Banco / governança
- **Arquivo:linha:** `supabase_migrations.schema_migrations` (278 linhas) × `ls supabase/migrations/*.sql` (243)
- **Categoria:** J — **Severidade:** P1
- **Descrição:** A diferença tem **duas naturezas distintas**, e é importante não confundi-las:

  **(a) Trabalho em andamento em worktrees — legítimo, temporário.** Dez das migrations aplicadas hoje
  (08/08) são de outra frente: `custo_de_ia_visivel`, `custo_real_do_openrouter`,
  `cron_reconciliacao_de_custo`, `precos_reais_bedrock_openrouter`, `reverter_ttl_1h_…`,
  `extrato_captura_dados_que_o_provedor_manda`, `compra_no_cartao_e_despesa_nao_conta_a_pagar`,
  `conexao_bancaria_saude_e_consentimento`, `trilha_de_conciliacao_e_fechamento_de_periodo`,
  `fecha_funcoes_de_periodo_para_anon`. Confirmei que ao menos `custo_real_do_openrouter` existe em
  `Documents/Claude Code/marineflow-erp--tokens/supabase/migrations/20260808140000_custo_real_do_openrouter.sql`
  — ou seja, está versionada num worktree e chegará à `main` no merge. Isso é o modelo de trabalho do projeto,
  não um defeito. **Vale registrar, porém, que essas migrations já estão aplicadas na produção antes do merge.**

  **(b) Migrations que não existem em lugar nenhum.** O caso comprovado e mais grave é
  **`20260706165104_remove_remaining_open_anon_policies`**: aplicada no banco em 06/07, **não existe no
  repositório canônico nem em nenhum dos 15 worktrees** (busca por nome em todo `Documents/Claude Code/`).
  É justamente a migration que removeu as políticas `Public clients viewing via service order` e
  `Public vessels viewing via service order` — a correção que explica por que o achado MF-AUD-021 **não** é um
  vazamento hoje. O conserto existe só no banco; o repositório continua descrevendo o estado vulnerável.
- **Evidência:**
  ```sql
  select count(*) from supabase_migrations.schema_migrations;   -- 278
  ```
  ```
  $ ls supabase/migrations/*.sql | wc -l                        # 243
  $ find "Documents/Claude Code" -name "*remove_remaining_open_anon*"   # (nenhum resultado)
  ```
  ```
  20260706164927  remove_staging_open_anon_policies      ← existe no repo
  20260706165104  remove_remaining_open_anon_policies    ← NÃO existe em lugar nenhum
  ```
- **Ação recomendada:** duas coisas diferentes. Para (a): nada — só ter consciência de que produção anda à
  frente da `main`. Para (b): extrair do banco o que essas migrations fizeram (comparando `pg_policies`,
  `pg_proc` e `information_schema` com o que as migrations do repo produziriam) e commitar uma migration de
  convergência. Sem isso, o repositório não reconstrói a produção — que é a definição de perda de
  reprodutibilidade.
- **Esforço:** L — **Decisão do Gustavo:** Sim — mesma decisão de MF-AUD-022.

### [MF-AUD-059] Duas tabelas de backup/reparo esquecidas no banco de produção
- **Módulo:** Banco
- **Arquivo:linha:** `pg_tables` → `products_stock_backup_pre_v2`, `reparo_coremma_20260805`
- **Categoria:** J — **Severidade:** P3
- **Descrição:** `products_stock_backup_pre_v2` é rastreável (criada junto do modelo de estoque v2 e protegida
  por `20260725120000_secure_products_stock_backup_pre_v2.sql`) — é um snapshot de segurança, e faz sentido
  mantê-lo enquanto o modelo v2 estiver em observação; vale definir uma data de descarte.
  `reparo_coremma_20260805` **não existe em nenhuma migration do repositório**, tem RLS ligada e nenhuma política
  (portanto só acessível por service role), e o nome indica um reparo pontual de 05/08. É resíduo.
- **Evidência:** `pg_tables` (121 tabelas, as duas presentes); `grep -rn "reparo_coremma" supabase/` → nada;
  advisor `rls_enabled_no_policy` lista `reparo_coremma_20260805`.
- **Ação recomendada:** conferir o conteúdo das duas antes de qualquer coisa; descartar a de reparo e agendar a
  de backup.
- **Esforço:** S — **Decisão do Gustavo:** Sim — autorizar o `DROP` (é destrutivo, exige autorização explícita).

### [MF-AUD-060] `service_orders.quote_validity_date` — coluna lida e nunca escrita
Ver **[MF-AUD-016]** (módulo 11). É o caso de coluna órfã mais consequente que encontrei: alimenta a tela pública
e o hash da assinatura, mas nenhum caminho do sistema a preenche.

### [MF-AUD-061] `inventory_movements` sem autoria em ajuste manual
- **Módulo:** Banco / Estoque
- **Arquivo:linha:** `supabase/functions/_shared/ai/tools/products.ts:244-249`
- **Categoria:** J — **Severidade:** P2
- **Descrição:** O `INSERT` de ajuste manual grava `product_id`, `quantity_delta`, `movement_type` e `notes` —
  **nenhum campo de usuário**. Como a tool roda com service role (MF-AUD-032), o movimento fica sem autor
  identificável. Num sistema que já sofreu com estoque fantasma, "quem mexeu" é a primeira pergunta de qualquer
  investigação. Verificar se a tabela sequer tem coluna para isso; se não tiver, é migration.
- **Evidência:** o `INSERT` citado; a tabela `inventory_movements` na listagem de `types.ts` (§4267).
- **Ação recomendada:** adicionar `created_by uuid` (se não existir) e preenchê-la em todos os caminhos de
  escrita — frontend (`use-service-orders.ts:432-439, 497-504`) e tools.
- **Esforço:** M — **Decisão do Gustavo:** Sim (é migration em produção).

---

## 21.2 Hipótese #10 do briefing — "MIG-01 a MIG-08": **funcionalidades verificadas, nomenclatura inexistente**

Primeiro, o registro factual: **a nomenclatura `MIG-01`..`MIG-08` não existe em lugar nenhum** — nem nos 48 `.md`
do repositório, nem nos 243 arquivos SQL, nem no código. As migrations reais usam timestamp
(`20260407192937_…`). Provavelmente é vocabulário de uma sessão anterior, ou da cópia `marineflow-staging`.

Verifiquei as **oito funcionalidades** nomeadas no briefing, ponta a ponta (existe migration → existe código →
está montado numa tela alcançável):

| # | Funcionalidade | Migration/banco | Código | Montado na UI | Status |
|---|---|---|---|---|---|
| 1 | Baixa de estoque | `so_status_stock` (`20260724190000_stock_reserve_model_v2`), `trg_deduct_stock_on_os_complete` | `isStockModelV2()` + `use-service-orders.ts:420-440` | sim (fluxo da OS) | ✅ **funcional**, com dois modos (flag `stock_model_v2`) |
| 2 | Alerta de estoque baixo | `products.minimum_stock` | `StockAlertDialog.tsx`, `use-inventory.ts:18` | `ServiceOrderForm.tsx:2233` | ✅ funcional |
| 3 | Controle de garantia | coluna `warranty_months` | `ServiceOrderForm`, `service-order/form-parts.tsx` | sim | ✅ funcional |
| 4 | Timer de serviço | `time_entries`, `trg_log_step_time_entry`, `trg_rollup_step_time` | `ServiceTimer.tsx` | `service-order/services-section.tsx:6` | ✅ funcional |
| 5 | Fotos de progresso da OS | `service_order_photos` | `ServiceOrderPhotos.tsx` | `service-order/general-sections.tsx:354` | ✅ funcional |
| 6 | Export CSV | — | `src/lib/export.ts`, `export-utils.ts` | várias telas | ✅ funcional |
| 7 | Gráfico de fluxo de caixa | — | `CashForecastPanel.tsx` **+** gráfico próprio no `FinancialV2` | ⚠️ **parcial** | ⚠️ o painel de programação semanal (com alerta de semana negativa e detecção de duplicatas) só existe na tela legada — **MF-AUD-050** |
| 8 | Web Push | `push_subscriptions` | `use-push-notifications.ts` (VAPID), `supabase/functions/send-push-notification` | disparo em `ServiceOrderForm.tsx:837,903` | ✅ presente ponta a ponta; depende de `VITE_VAPID_PUBLIC_KEY` estar configurada no ambiente |

**Sete das oito estão funcionais.** A oitava (fluxo de caixa) tem a ressalva do MF-AUD-050 — a funcionalidade não
sumiu, mas perdeu metade do escopo na migração para a V2.

---

## 21.3 Verificações feitas que **não** produziram achado

- **Integridade da série de migrations:** contígua e ordenada, sem buracos suspeitos no repositório; os nomes
  descrevem a intenção (o padrão melhorou muito a partir de julho — comparar
  `20260407192937_fb252897-…` com `20260806120000_regras_de_protecao`).
- **`types.ts` × banco:** as ~120 tabelas do arquivo gerado batem com as 121 de `pg_tables` (a diferença é
  `reparo_coremma_20260805`, que nunca foi regenerada — MF-AUD-059).
- **Views com `security_invoker`:** há migrations dedicadas (`open_loops_security_invoker`,
  `estoque_views_security_invoker_e_revoke_anon`) — a lição registrada na memória do projeto virou prática.
- **`search_path` em funções `SECURITY DEFINER`:** endereçado por duas migrations
  (`search_path_security_definer`, `harden_invoker_function_search_path`).
- **Triggers de `service_orders`:** sete, todos rastreáveis a migrations. Nenhum órfão.
- **Sequência de numeração de documento:** `next_document_number()` sobre sequência Postgres — correto sob
  concorrência.

---

*Módulo 11 auditado. 4 achados (`MF-AUD-058`, `MF-AUD-059`, `MF-AUD-061` próprios; `MF-AUD-060` cruzado).
Hipótese #10 do briefing respondida: 7 de 8 funcionais, 1 parcial.*
