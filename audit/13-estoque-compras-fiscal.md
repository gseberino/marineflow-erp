# 13 — Estoque, Compras e Fiscal (Etapa 2, módulo 4)

Superfície: `src/pages/{InventoryPage,SmartPurchasePage,PurchaseOrdersPage,PurchasingHubPage,QuoteRequestsPage,
QuoteRequestDetailPage,ImportFiscalXML,FiscalEmission}.tsx` e gêmeas V2, `src/components/purchasing/*` (4),
`ReceivePODialog`, `BarcodeScannerModal`, `ImportWizard`, `BulkEditor`, libs `purchase-needs.ts`,
`quote-comparison.ts`, `nfe-xml-parser.ts`, `nfe-info-complementar.ts`, `danfe-espelho.ts`,
`fiscal-emission-item.ts`, `fiscal-draft-state.ts`, `supabase/functions/_shared/fiscal/*` (8),
`fiscal-emit`, `fiscal-webhook`, `fiscal-reconcile`, `fiscal-email`, `process-nfe-xml`, e as RPCs de estoque/NF-e.

---

## 13.0 Estado das promessas dos planos

**`marineflow-compras-cotacao.md` (declarado EM PRODUÇÃO em 30/07) — confere item a item:**

| Item | Promessa | Verificação |
|---|---|---|
| `[V-34]` | `src/lib/purchase-needs.ts` + 14 testes + `use-purchase-needs.ts` | ✅ ambos existem; `purchase-needs.test.ts` presente |
| `[V-35]` | `quote-comparison.ts` + 19 testes; telas de cotação | ✅ `quote-comparison.test.ts`, `QuoteRequestsPage`, `QuoteRequestDetailPage`, `NewQuoteRequestDialog` |
| `[V-36]` | Regras R16 e R17 no motor | ✅ `task-automations/rules.ts:512` e `:692` |
| `[V-37]` | `StockConfirmationDialog` (quebrado) substituído por `PurchaseNeedsDialog` | ✅ o antigo **não existe mais**; o novo está em `src/components/purchasing/` |
| `[V-38]` | RLS de compras por cargo | ✅ migration `20260730215125_rls_compras_por_cargo` aplicada; políticas granulares confirmadas no banco |
| `[V-39]` | `product_suppliers` **não** deve ser dropada (4 pontos de uso) | ✅ preservada; usada em `ServiceOrderForm`, `SupplierList`, `use-product-suppliers`, `use-purchase-orders` |
| `[V-40]` | Em aberto: frete/desconto por fornecedor não persistem | — não reverificado (declarado em aberto pelo próprio plano) |

**Fiscal (NF-e/NFS-e):** a camada trocável existe e é séria — `supabase/functions/_shared/fiscal/` com
`factory.ts`, `contora-provider.ts`, `payload-builder.ts`, `nfe-sanitize.ts`, `apply-status.ts`, `ibge.ts`,
`product-fiscal.ts`, `types.ts`. **Dez arquivos de teste** cobrem o domínio (`fiscal-contora`,
`fiscal-payload-builder`, `fiscal-product-fiscal`, `fiscal-emission-item`, `fiscal-draft-state`, `nfe-sanitize`,
`nfe-xml-parser`, `nfe-info-complementar`, `danfe-espelho`, `danfe-filename`). O ciclo de importação por XML tem
as três RPCs previstas (`preview_nfe_import`, `confirm_nfe_import`, `revert_nfe_import`) mais
`settle_nfe_stock_and_receivable` e `match_nfe_item`. As regras de `docs/fiscal-devolucao-simples.md` (`[V-23]`)
têm contraparte no código (`nfe-info-complementar.ts` + teste).

---

## 13.1 Achados

### [MF-AUD-069] `FiscalEmission.tsx`: 3.505 linhas e 95 strings fora do i18n
- **Módulo:** Fiscal
- **Arquivo:linha:** `src/pages/FiscalEmission.tsx`
- **Categoria:** H/E — **Severidade:** P2
- **Descrição:** O maior arquivo de UI do projeto (2,4× o segundo colocado) e o campeão de texto fixo em
  português (95 ocorrências), apesar de importar `useI18n`. Concentra emissão, espelho, retorno do provedor,
  correção (CC-e), devolução e faturamento de orçamento. Não encontrei bug atribuível ao tamanho — a lógica de
  domínio está em `_shared/fiscal` e nas libs testadas, o que é a decisão certa —, mas é o arquivo com maior
  probabilidade de acidente em qualquer alteração futura, e tem apenas um smoke test de render.
  A "V2" desta tela é casca de tema sobre ela mesma (`wrapped.tsx`), então não há duplicação — só massa.
- **Evidência:** `wc -l` → 3.505; varredura de i18n → 95 ocorrências; `FiscalEmission.smoke.test.tsx` é o único
  teste da página.
- **Ação recomendada:** decompor por etapa do fluxo (rascunho → validação → emissão → retorno → documentos),
  extraindo cada aba para um componente próprio, **com teste de render por aba antes de mover**. Não é urgente;
  é a próxima dívida a pagar quando a frente fiscal voltar.
- **Esforço:** L — **Decisão do Gustavo:** Sim — vale a decomposição agora ou só quando houver mudança fiscal?

### [MF-AUD-070] `adjust_inventory` sobrescreve estoque sem gate, cargo ou autoria — ver [MF-AUD-032] (P1)
Registrado no módulo 19. É o achado mais sério deste domínio: a tool do agente grava `stock_quantity` com valor
absoluto, com service role, sem aprovação, e o movimento correspondente não registra quem fez
(ver também MF-AUD-061).

### [MF-AUD-071] Tabelas de importação e edição em massa forçam rolagem lateral — ver [MF-AUD-052]
`ImportWizard.tsx:213,264` (`min-w-[600px]`, `min-w-[500px]`) e `BulkEditor.tsx:213` (`min-w-[1000px]`).

---

## 13.2 Verificações feitas que **não** produziram achado

- **Modelo de estoque v2:** a flag `stock_model_v2` em `app_settings` alterna entre "o banco gerencia estoque"
  (reserva na OS comprometida, baixa física na conclusão, via trigger `so_status_stock`) e o comportamento
  antigo do frontend. O código do frontend **respeita a flag** e evita dupla contagem, com o motivo documentado
  (`use-service-orders.ts:7-13, 420-421, 481-483`). Há migrations de endurecimento
  (`cancel_cascade_v2_stock_guard`, `stock_bom_security_hardening`, `stock_v2_status_sets_fix`,
  `estoque_estorno_com_referencia_e_idempotente`, `estoque_negativo_avisa_em_vez_de_silenciar`) e um backup
  (`products_stock_backup_pre_v2`, MF-AUD-059). A frente foi tratada com o cuidado que o histórico do problema
  exigia.
- **Compras:** as quatro correções de bug listadas no plano (`StockConfirmationDialog` lendo estoque cru,
  descrição de tool que parava o agente, botão que só emitia toast na `SmartPurchasePage`, XML sem sugerir a OC
  do fornecedor) estão refletidas no código atual.
- **BOM/kit:** `product_components`, `recompute_product_cost`, `produce_composed_product`,
  `apply_service_material_kit` — presentes, com trigger de roll-up (`product_components_rollup`).
- **Fiscal — sequência de numeração:** `fiscal_document_sequences` + `next_fiscal_number` +
  `set_fiscal_next_number`, com a tabela fechada por RLS (só service role) — correto para um contador fiscal.
- **Entrada por XML:** casamento em cascata (`match_nfe_item`: GTIN → de-para → SKU → descrição) com
  `supplier_product_mappings` e `product_aliases`; pré-visualização e desfazer implementados como RPC.

---

*Módulo 4 auditado. 1 achado próprio (`MF-AUD-069`) + 2 referências cruzadas.*
