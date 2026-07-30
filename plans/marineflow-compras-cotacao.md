# MarineFlow — Compras & Cotação: dar corpo ao que existe e fechar o ciclo

> **STATUS 29/07/2026 — EXECUTADO.** Branch `session/compras` (worktree
> `marineflow-erp--compras`), 5 commits, aguardando integração+deploy autorizados.
> Decisões do dono: D1 = cotação→OC **com compra direta também possível** · D2 = **os dois**
> (diálogo na hora + faixa + tarefa) · D3 = peças em falta + itens de texto livre ·
> D4 = não separar v1/v2 (um componente por tela, servido nas duas rotas).
>
> | Fase | Estado | Onde |
> |---|---|---|
> | C0 fundação | ✅ | `src/lib/purchase-needs.ts` + 14 testes · `src/hooks/use-purchase-needs.ts` |
> | C1 telas de cotação | ✅ | `QuoteRequestsPage`, `QuoteRequestDetailPage`, `NewQuoteRequestDialog`, `src/lib/quote-comparison.ts` + 19 testes |
> | C2 elo da aprovação | ✅ | `PurchaseNeedsDialog` (substituiu o `StockConfirmationDialog` quebrado), `PurchaseNeedsBanner`, regra **R16** |
> | C3 Central de Compras | ✅ | `PurchasingHubPage` em `/purchasing` |
> | C4 OC na entrada por XML | ✅ | sugestão do pedido provável em `ImportFiscalXML` |
> | C5 follow-up e limpeza | ✅ parcial | descrição da tool, regra **R17**, `SmartPurchasePage` religada |
>
> **Bugs reais corrigidos no caminho** (todos explicam as 0 OCs / 0 respostas em produção):
> 1. `StockConfirmationDialog` lia `stock_quantity` cru (ignorava reserva), buscava
>    fornecedor em `product_suppliers` (**0 registros**), não descontava OC aberta,
>    ignorava texto livre e criava uma OC por item.
> 2. Descrição de `send_supplier_quote_request` mandava o agente parar no envio.
> 3. `SmartPurchasePage`: botão que só emitia toast + filtro comparando com a string
>    `'minimum_stock'` em vez da coluna.
> 4. Entrada por XML listava todas as OCs sem sugerir a do fornecedor da nota.
>
> **Não feito de propósito** (precisa de migration/autorização): recalibrar a RLS
> `USING(true)` das 5 tabelas de compras; dropar `product_suppliers`; histórico de preço
> por fornecedor na tela; frete/desconto **persistidos** por fornecedor (hoje são estado
> da sessão de comparação, o que não exigiu migration nenhuma).


> Plano elaborado em 29/07/2026 a pedido do dono: **(a)** dar uma tela à cotação, para
> organizar e ver a operação de compras de forma ampla; **(b)** avisar/oferecer ação de
> compra quando o orçamento é aprovado e entra na sequência de OS.
> Base: auditoria do código + consulta ao banco de produção (`okurngvcodmljjicopdp`) +
> pesquisa de mercado até saturação (§2).

---

## 1. Estado verificado (não é suposição — é o banco de produção)

| Frente | Código | Uso real | Onde parou |
|---|---|---|---|
| **Ordens de Compra** (08/05) | Completo: `purchase_orders`/`_items`, `receive_po` (estoque+conta a pagar atômico), tela CRUD+CSV, `ReceivePODialog`, `useCreatePOFromOS` | **0 registros** | Nunca usada. Ganhou réplica v2 em 26/07 (só paridade visual) |
| **Entrada por XML** (22/07) | Casamento em cascata (GTIN→de-para→SKU→descrição), `preview_nfe_import`, `revert_nfe_import`, conferência em 3 vias | **3 notas, R$ 53.910** (22–23/07) | Funciona. Mas `purchase_order_id` NULL nas 3 → a 3ª via nunca foi exercitada |
| **Cotação** (21–22/07) | 7 tools de IA: criar, enviar, registrar resposta (texto/áudio/PDF/imagem), comparar, aplicar custo, gerar OC | **3 cotações, 31 itens, 2 fornecedores, 0 respostas** | **Aqui.** Zero telas (`grep quote_request src/` = nada). Exercitado até o envio |
| **Devolução ao fornecedor** | NF-e de devolução completa (vIPIDevol, CSOSN 900, ref. por item) | 20 documentos emitidos | Maduro, evoluiu até 27/07 |
| **Fornecedores** | 530 cadastrados | 31 de-para (todos do XML) | Só 31 de 423 produtos com fornecedor |

**Infra já pronta que este plano reusa (e que barateia tudo):**

- **Motor `task-automations`** (cron 15 min) com R1–R15, dedupe por `automation_key`,
  auto-resolução, dispensa manual com cooldown de 7 dias e **botão-que-resolve no card**.
  Já tem regras de compras: **R7** "Cobrar entrega da OC", **R8** "Repor produto",
  **R11** "NF com pendência". → O aviso da aprovação é **uma regra a mais**, não um mecanismo novo.
- **Modelo de reserva de estoque v2 LIGADO** (`app_settings.stock_model_v2 = 'on'`,
  8 produtos com reserva): view `product_availability` com
  `available_quantity = stock_quantity − reserved_quantity`. → É o insumo exato do cálculo
  de necessidade líquida. Decisão já registrada na migration: *"falta de estoque não bloqueia
  o orçamento (só avisa na efetivação)"*.
- **Ponto de encaixe da aprovação**: `use-service-orders.ts:176-196` — a primeira transição
  para fora de `draft` (ORÇ-00042 → OS-00042, grava `converted_to_os_at` e
  `original_quote_amount`). 34 orçamentos já passaram por aqui.
- **Kit v2**: PageShell, DataTable (com `renderExpanded`/`rowClassName`), KPIStat, StatusChip,
  V2Shell (2 temas), verificador `scripts/v2-viewport-check.mjs`.

---

## 2. Pesquisa de mercado (saturada — as últimas rodadas só repetiam)

### 2.1 O processo canônico (procure-to-pay)
Necessidade → **requisição** → **RFQ** → **avaliação das cotações** → **pedido de compra** →
**recebimento** → **conferência a 3 vias (pedido × nota × recebimento)** → pagamento.
O passo que a HBR pula hoje é a *avaliação formal*, e o que ela tem sem usar é o *pedido*.
Fontes: [Kissflow](https://kissflow.com/procurement/procure-to-pay-process-guide/) ·
[IBM](https://www.ibm.com/think/topics/procure-to-pay) · [Taulia](https://taulia.com/glossary/what-is-procure-to-pay/) ·
[Ramp](https://ramp.com/blog/7-steps-of-procurement-a-comprehensive-guide)

### 2.2 O elo venda → compra (exatamente o que foi pedido)

| Sistema | Como resolve | O que vale copiar |
|---|---|---|
| **Odoo** — *Replenish on Order (MTO)* | Confirmar a venda dispara RFQ/PO automaticamente; **smart button** no topo da venda leva à RFQ e vice-versa | O rastro nos **dois sentidos** e o botão contextual no documento de origem |
| **SAP Business One** — *Procurement Confirmation Wizard* | O assistente **abre ao adicionar o pedido de venda** e oferece gerar requisição/cotação/PO; mapa de relacionamento entre os documentos | **O gatilho no momento exato da confirmação** — é o padrão mais próximo do que foi pedido |
| **Dynamics 365 BC** — *Special Order* + *Requisition Worksheet* | Marca-se a linha como pedido especial; a planilha de requisição faz **"Get Sales Orders"** e gera as POs em lote, **vinculadas** à venda | A **planilha de lote**: várias OS aprovadas viram compras numa tela só |
| **ERPNext** | Material Request → RFQ (multi-fornecedor) → Supplier Quotation → comparativo → PO em 1 clique | A **cadeia explícita** e o comparativo como etapa nomeada |
| **ServiceTitan** (field service) | Técnico cria PO no app; escritório **revisa, aprova e envia ao fornecedor**; recebimento atualiza estoque | Separar **quem pede** de **quem efetiva** |
| **simPRO** (field service) | "Raise purchase order" a partir do job/quote, com catálogo de fornecedor e histórico de preço | A compra nasce **de dentro do job**, não de um módulo à parte |

Fontes: [Odoo MTO](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/warehouses_storage/replenishment/mto.html) ·
[SAP B1 Wizard](https://help.sap.com/docs/SAP_BUSINESS_ONE/68a2e87fb29941b5bf959a184d9c6727/95adcf102d2e486797b85c6123775f43.html) ·
[BC Special Orders](https://usedynamics.com/business-central/purchase/special-orders-from-requisition-worksheet/) ·
[BC Drop Ship vs Special Order](https://archerpoint.com/drop-shipments-and-special-orders-in-business-central/) ·
[ERPNext RFQ](https://docs.erpnext.com/docs/v13/user/manual/en/buying/request-for-quotation) ·
[ServiceTitan](https://help.servicetitan.com/docs/manage-parts-purchase-orders-2) ·
[simPRO](https://helpguide.simprogroup.com/Content/Service-and-Enterprise/Service-Jobs.htm)

### 2.3 O comparativo de cotações (o coração da tela nova)

- **Odoo — "Compare Order Lines"**: agrupa **por produto**, cada produto expande mostrando
  todas as ofertas; botões **"Choose"** (escolhe aquela linha) e **"Clear"** (zera);
  ao confirmar, pergunta *"e as RFQs alternativas?"* → **Cancelar** ou **Manter**.
- **Mapa de cotação (padrão brasileiro)**: fornecedores em **colunas**, ordenadas **do melhor
  pacote para o pior**, com **selo no melhor**; o cálculo do "melhor" soma itens − desconto +
  frete; o cabeçalho traz CNPJ, cidade/UF, **validade da proposta**, contato, condição de
  pagamento e prazo de entrega.
- **Bid tabulation (construção)**: itens em linhas, fornecedores em colunas; *bid leveling*
  (ajustar por inclusões/exclusões antes de comparar); **sinalizar quem desvia muito da média**;
  conferir `qty × unitário = total` porque fornecedor erra conta; registrar a **justificativa**
  da escolha.

Fontes: [Odoo Alternative RfQs](https://www.odoo.com/documentation/18.0/applications/inventory_and_mrp/purchase/manage_deals/calls_for_tenders.html) ·
[Sienge — mapa de cotação](https://sienge.com.br/blog/mapa-de-cotacao-saiba-o-que-e-como-fazer-o-seu/) ·
[WK — Mapa de Cotações](https://ajuda.wk.com.br/710/wk/Workspaces/Mapa_de_Cotacoes.htm) ·
[Procore — bid tabulation](https://www.procore.com/library/bid-tabulation) ·
[Sankhya](https://www.sankhya.com.br/sistema-de-gestao-erp-para-compras-e-cotacao/)

### 2.4 Cotação sem resposta (nosso caso: 3 enviadas, 0 respostas)
Janela normal de resposta: **3 a 5 dias úteis**; meta de taxa de resposta **> 70%**;
o remédio recomendado é **lembrete automático** em vez de caçar no inbox — o custo escondido
do RFQ por e-mail/WhatsApp é justamente o *chase* manual.
Fontes: [Kavida](https://www.kavida.ai/use-cases/rfq-followups/) ·
[AuraVMS](https://www.auravms.com/blogs/how-to-evaluate-rfq-responses-scoring-supplier-quotes) ·
[Meshworks](https://www.meshworks.com/blog/the-hidden-cost-of-running-rfqs-over-email)

### 2.5 A matemática do aviso (necessidade líquida)
`Necessidade = Bruto − (em mãos − reservado) − já pedido (+ estoque de segurança)`.
Positivo → gera sugestão de compra; zero ou negativo → nada a fazer.
**Temos os três termos**: `service_order_parts.quantity`, `product_availability`
(`stock_quantity − reserved_quantity`) e `purchase_order_items` em OCs abertas.
Fontes: [Craftybase](https://craftybase.com/blog/gross-to-net-calculations-for-mrp/) ·
[ERP Information](https://www.erp-information.com/net-requirements.html) ·
[User Solutions](https://usersolutions.com/blog/mrp-net-requirements-calculation)

### 2.6 Visão ampla (a "operação de compras como um todo")
Regra dos dashboards de compras: **5 a 7 indicadores por visão** — encher de métrica mata a
adoção. Os que fazem sentido aqui: cotações abertas e **aging**, taxa de resposta por
fornecedor, ciclo cotação→pedido, pedidos em atraso de entrega, **economia obtida** (melhor
oferta × oferta escolhida), lead time por fornecedor.
Fontes: [Ivalua](https://www.ivalua.com/blog/procurement-dashboard/) ·
[Kissflow KPIs](https://kissflow.com/procurement/procurement-kpis/) ·
[Varisource](https://www.varisource.com/blog/procurement-dashboard-kpis-types-why-dashboards-fail)

### 2.7 O que a pesquisa ofereceu e eu **descarto** (com motivo)

| Prática de mercado | Por que NÃO aqui |
|---|---|
| Requisição de compra com alçadas hierárquicas | Operador único. Alçada é cerimônia sem ganho — a literatura de PME recomenda 1 aprovação |
| **Portal do fornecedor** (ERPNext/Sankhya) | Fornecedor náutico não vai logar em sistema. O canal real é o WhatsApp, que já está de pé |
| *Call for tender* formal / edital | Exigência do setor público. Aqui só burocratiza |
| Contratos guarda-chuva / *blanket orders* | Compra sob demanda, sem volume recorrente |
| Scoring multicritério ponderado | Sem massa de dados de qualidade/entrega. Começa por preço, prazo e histórico; peso vem depois |
| MRP com horizonte e *time-phasing* | Não há produção nem previsão de demanda. Necessidade líquida pontual resolve |
| Baixa automática no recebimento **sem** conferência | O `receive_po` já é atômico, mas a conferência a 3 vias é justamente a proteção que falta |

---

## 3. Princípios do desenho (derivados da pesquisa + do que já existe aqui)

1. **Dar corpo, não recomeçar.** O ciclo de cotação existe inteiro em tools; falta olho humano.
2. **Necessidade líquida, nunca "tem ou não tem".** Usar `product_availability`.
3. **Sugerir ≫ criar** — princípio já vigente na Agenda Autônoma. Nada de OC nascendo sozinha.
4. **Um lugar só para ver a operação** (Central de Compras), no formato de fila já validado
   no DashboardV2 ("Precisa de você hoje" com ação por item).
5. **Rastro nos dois sentidos**: OS ↔ COT ↔ OC ↔ NF, como o smart button do Odoo.
6. **Zero rolagem horizontal** (Princípio 0 do dono) — o mapa de cotação é o pior caso possível
   de largura; ver §5 para como resolver sem scroll lateral.
7. **Nada que gaste dinheiro sozinho.** Enviar cotação e gerar OC seguem sob confirmação.

---

## 4. Decisões pendentes (assumidas na recomendação; confirmar antes da C1)

| # | Decisão | Assumido | Se mudar |
|---|---|---|---|
| D1 | O documento central: OC entra? | **Cotação → OC → recebimento** (aproveita `receive_po` e o `purchase_order_id` do fiscal; fecha as duas portas de entrada) | Se for "compra direta sem OC", a Fase C4 muda de forma e a tela de OC entra em aposentadoria |
| D2 | Comportamento na aprovação | **Diálogo na hora + tarefa de retaguarda** (padrão SAP B1, com rede do motor) | Se for "só faixa + tarefa", cai o item C2.1 (metade da fase) |
| D3 | Escopo de "falta comprar" | **Peças com saldo insuficiente + itens de texto livre** (as 3 cotações reais são cheias de texto livre) | Se for só catálogo, o cálculo simplifica e a cobertura cai muito |
| D4 | Onde nascem as telas | **Direto em /v2** | v1 também = manter duas telas em sincronia durante o churn |

---

## 5. O plano em fases

### Fase C0 — Fundação de leitura (sem migration, risco zero)

- `src/lib/purchase-needs.ts` — cálculo puro de necessidade líquida por OS:
  para cada `service_order_parts`: `falta = qty − max(0, available) − em_OC_aberta`;
  itens de texto livre (`product_id IS NULL`) entram com `falta = qty`.
  Saída por item: `{ origem, descrição, qty, disponível, em_pedido, falta, status }`
  com status ∈ `ok | parcial | falta | sem_cadastro`.
- **Testes vitest** pinando os casos: sem reserva, reserva parcial, OC aberta cobrindo,
  texto livre, qty fracionária, produto sem `minimum_stock`.
- RPC de leitura `get_os_purchase_needs(p_so_id uuid)` espelhando a lib para o agente/tools
  (`security invoker` + `REVOKE` de anon na mesma migration — [[feedback_supabase_view_security_invoker]]).

**Aceite:** a mesma OS produz o mesmo resultado na lib (front) e na RPC (agente).

### Fase C1 — Tela de Cotações (o pedido central)

**C1.1 Lista — `/v2/purchasing/quotes`**
DataTable com: código, OS/cliente vinculado, itens, fornecedores consultados,
**respostas recebidas (2/3)**, **aging** ("enviada há 6 dias" — âmbar ≥3 dias úteis,
vermelho ≥5, conforme §2.4), melhor oferta, status.
KPIStat: cotações abertas · sem resposta há 3+ dias · valor em negociação · ciclo médio.
Filtros e presets no padrão `FilterPresets` já existente.

**C1.2 Mapa de cotação — `/v2/purchasing/quotes/:id`** (o coração)
- **Itens em linhas, fornecedores em colunas** (padrão mapa de cotação BR + bid tabulation).
- Cabeçalho de coluna: fornecedor, prazo, condição de pagamento, frete, validade,
  **total do pacote**, e **selo "melhor pacote"** (itens − desconto + frete).
- Colunas ordenadas do melhor para o pior pacote.
- Por célula: unitário, subtotal, e **destaque do melhor preço da linha**.
- **Botão "Escolher"** por item (Odoo *Choose*) → monta a "cesta escolhida", que pode ser
  **dividida entre fornecedores**; rodapé mostra o total da cesta × o melhor pacote único.
- **Sinalizar desvio**: célula que fica >30% acima da média da linha ganha marca (bid leveling).
- **Registrar resposta manualmente** — hoje só a IA sabe fazer isso (`record_quote_response`);
  a tela precisa do mesmo poder, com `source='manual'` e `source_excerpt` opcional.
- Ações de saída: **aplicar custo no orçamento** (`apply_quote_price`, recalcula margem),
  **gerar OC** (`create_purchase_order_from_quote`), **fechar cotação**, e
  **"e as outras?"** → cancelar ou manter (padrão Odoo).

**Zero scroll horizontal (Princípio 0):** com N fornecedores as colunas não cabem. Solução:
até 3 fornecedores = colunas; a partir de 4, **cada item vira card expansível** com as ofertas
empilhadas e ordenadas, e um seletor "comparar 3 de N" no topo. Garantia pelo verificador
`v2-viewport-check.mjs` em 5 larguras × 2 temas.

**Aceite:** as 3 cotações reais (COT-00001..3) abrem, aceitam resposta manual, comparam e
geram OC — sem uma linha de scroll lateral em nenhum viewport.

### Fase C2 — O elo da aprovação (o que foi pedido)

**C2.1 Diálogo na transição ORÇ → OS** (`use-service-orders.ts:176-196`)
Ao gravar `converted_to_os_at`, se a necessidade líquida > 0, abrir o resumo:

```
OS-00061 aprovada. 4 itens precisam de compra:
  • Fusível MIDI 200A ...... precisa 6 · disponível 0 · falta 6   [cotar] [comprar]
  • Porta-fusível MIDI ..... precisa 2 · disponível 1 · falta 1   [cotar] [comprar]
  • "Cabo 70mm² vermelho" .. item sem cadastro · falta 3 m        [cotar]
  ✓ Terminal M8 ............ precisa 4 · disponível 9 · reservado

  Já existe a COT-00002 ligada a esta OS (2 fornecedores, sem resposta há 6 dias)
  [ Abrir cotação ]  [ Cobrar resposta ]

[ Criar cotação com os 3 itens ]  [ Criar OC direto ]  [ Depois ]
```

Regra de ouro: **não bloqueia** (coerente com a decisão registrada no modelo de estoque v2).
"Depois" fecha e deixa o rastro para o motor.

**C2.2 Faixa persistente na OS**
Na seção G ("Compras vinculadas", já existente em `summary-sections.tsx`): faixa tonalizada
"faltam 3 itens para executar esta OS" com as mesmas ações — e a seção passa a listar
**cotações** além de OCs (hoje só `useSOLinkedPOs`).

**C2.3 Regra R16 no motor `task-automations`**
`automation_key = 'r16:' || service_order_id` — "OS aprovada com itens a comprar".
Título: *"Comprar 3 itens da OS-00061 — Cliente X"*. Card com botão-que-resolve
("Abrir cotação" / "Criar cotação"), no padrão já validado em R7/R8.
**Auto-resolve** quando a necessidade zera (cotação aplicada, OC criada ou nota recebida);
**dispensa manual** respeita o cooldown de 7 dias. Nasce **ON** (é interno, não fala com cliente).

**Aceite:** aprovar uma OS com falta gera diálogo + tarefa; resolver a compra fecha a tarefa
sozinha no tick seguinte; concluir a tarefa na mão não a faz voltar em 15 min.

### Fase C3 — Central de Compras — `/v2/purchasing` (a visão ampla)

Fila única "Precisa de você", no formato do DashboardV2, agregando o que já existe:
OS aprovadas com falta (R16) · cotações sem resposta · cotações respondidas aguardando decisão ·
OCs a enviar · **OCs com entrega atrasada** (R7) · notas com pendência (R11) · itens abaixo do mínimo (R8).
KPIs (máx. 7, §2.6): em negociação · aguardando entrega · economia do mês
(melhor oferta × escolhida) · ciclo cotação→pedido · taxa de resposta · atrasos · a pagar em 30d.
Entrada no menu: grupo **"Estoque & Compras"** já existe em `AppLayout.tsx:171-186`.

### Fase C4 — Fechar o ciclo no recebimento (depende de D1)

- Vincular a OC na entrada por XML: o campo `fiscal_notes.purchase_order_id` **já existe e está
  NULL** nas 3 notas; a RPC `confirm_nfe_import` já aceita `p_purchase_order_id`. Falta a tela
  **sugerir** a OC provável (mesmo fornecedor, aberta, itens compatíveis) e mostrar o confronto.
- Confronto pedido × nota já implementado em 22/07 (commit `55b7485`) — passa a ter dado real.
- Ao receber, a necessidade da OS zera → R16 auto-resolve. **O ciclo fecha.**

### Fase C5 — Follow-up, memória de preço e limpeza

- **R17 — cotação sem resposta há 2 dias úteis**: tarefa com botão "Cobrar resposta"
  (reusa `send_supplier_quote_request`/WhatsApp). Nasce ON — é interno; a mensagem ao
  fornecedor segue sob confirmação.
- **Histórico de preço por fornecedor**: `supplier_product_mappings` já guarda o de-para;
  passar a exibir "último custo pago, com quem, quando" na cotação e no mapa (padrão simPRO).
- **Corrigir a descrição de `send_supplier_quote_request`** (`whatsapp.ts:76`): ainda diz
  *"a consolidação é manual (MVP). NÃO cria ordem de compra"* — texto que **contradiz** as tools
  de comparativo/OC criadas no mesmo commit. Suspeito nº 1 das 0 respostas registradas.
- **`SmartPurchasePage`**: hoje é casca (o botão só emite toast, `SmartPurchasePage.tsx:54-62`)
  e a query `.filter('stock_quantity','lte','minimum_stock')` compara com o **literal**
  `'minimum_stock'`, não com a coluna. Duas saídas: ligar de verdade (seleção → cotação) ou
  remover a tela e deixar a reposição por R8. **Recomendo ligar** — é a porta de entrada do
  "comprar para estoque", que a Central não cobre.

---

## 6. Dívidas que este plano encosta (e o que faço com elas)

| Dívida | Ação neste plano |
|---|---|
| RLS `USING(true)` em `purchase_orders`, `purchase_order_items`, `quote_requests`, `quote_request_items`, `quote_responses` | Recalibrar **na C1**, por comando e por papel (nunca `FOR ALL` — lição da Agenda). Cai 5 dos 23 `rls_policy_always_true` da Fase 2 do roadmap |
| `product_suppliers` (0 linhas) × `supplier_product_mappings` (31) | Confirmar órfã e **dropar** em migration nomeada, ou documentar o motivo de existir |
| `SmartPurchasePage` casca + query suspeita | C5 |
| Descrição desatualizada da tool de envio | C5 (1 linha, pode ir antes de tudo) |
| Conferência a 3 vias sem dado | C4 |

---

## 7. Validação por fase

- **C0**: vitest da lib (7+ casos) + paridade lib × RPC na mesma OS.
- **C1**: `npx tsc -b` (NÃO `--noEmit` — tsconfig com `files: []`); `npm run build`;
  **smoke test de render** das telas novas (padrão `agenda-components.smoke.test.tsx` —
  build verde não pega TDZ); `v2-viewport-check.mjs` 2 temas × 5 larguras.
- **C2**: teste do motor em `rules_test.ts` (cria, auto-resolve, não recria após dispensa);
  render do diálogo; **teste E2E numa OS real de rascunho**.
- **C3**: verificador + conferência dos KPIs contra SQL manual.
- **C4**: importar um XML real de nota já recebida contra uma OC criada à mão e ver o confronto.
- **Deno**: `deno check` nas edges tocadas (o `tsc` do projeto não cobre `supabase/functions`).

---

## 8. Riscos

- **A tela de cotação toca dinheiro de forma indireta**: `apply_quote_price` altera o custo do
  item do orçamento e **recalcula margem**. Precisa de teste de paridade com `os-financials.ts`
  antes de expor o botão.
- **`create_purchase_order_from_quote` nunca rodou** (0 OCs no banco). Tratar como código não
  provado: primeira execução em OS de teste, conferindo `receive_po` depois.
- **Migration em produção** (RLS + RPC): exige autorização nomeada do dono.
- **Sessões paralelas**: `ServiceOrderForm`/`summary-sections` estão sendo decompostas por outra
  sessão (Fase 3 da UI). C2.2 encosta em `summary-sections.tsx` → **trabalhar em worktree
  (`guard.sh worktree compras`)** e integrar sob lock, rebase em `origin/main` (não na `main` local).
- **R16 pode virar ruído** se a necessidade líquida der falso positivo em item de texto livre
  repetido. Mitigação: dedupe por OS (uma tarefa por OS, não por item) e cooldown de dispensa.

---

## 9. Ordem recomendada de execução

`C5 (1 linha da tool)` → `C0` → `C1` → `C2` → `C3` → `C4` → `resto do C5`

Justificativa: a correção da descrição é grátis e pode revelar que o ciclo do agente já
funciona; C0 é a fundação de todo o resto; C1 entrega o pedido central; C2 entrega o segundo
pedido; C3 dá a visão ampla; C4 fecha o ciclo. Cada fase é uma sessão com gate de aceite.
