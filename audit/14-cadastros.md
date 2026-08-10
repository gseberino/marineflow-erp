# 14 — Cadastros: Clientes, Embarcações, Marinas, Produtos, Serviços, Fornecedores (Etapa 2, módulo 5)

Superfície: `src/pages/{ClientList,ClientDetail,VesselList,VesselDetail,MarinaList,ProductList,ServiceList,SupplierList}.tsx`,
as gêmeas em `src/v2/pages/*V2.tsx`, `src/v2/components/DataTable.tsx`, os diálogos de formulário
(`ClientFormDialog`, `VesselFormDialog`, `MarinaFormDialog`, `ProductFormDialog`, `ServiceFormDialog`,
`SupplierFormDialog`, `QuickProductDialog`, `QuickSupplierDialog`) e os hooks correspondentes.

---

## 14.0 Hipótese #3 do briefing: **CORRIGIDA** (nas duas gerações da UI)

A hipótese era "overflow de layout nas páginas de lista (Clientes, Embarcações, Marinas e demais) — cards
poluídos, sem paginação". Não se sustenta no código atual:

**Listas legadas** — paginação de 20 e colunas que somem por breakpoint:
```ts
// src/pages/ClientList.tsx:27,70-71 (idem VesselList.tsx:16,70-71 e MarinaList.tsx:26,67-68)
const PAGE_SIZE = 20;
const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
const paginated  = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
```
```tsx
// src/pages/VesselList.tsx:134-146 — colunas secundárias escondidas no celular
<th className="… hidden md:table-cell">…  <th className="… hidden lg:table-cell">…
```

**Listas V2** — o problema foi resolvido por construção, não por remendo:
```tsx
/* src/v2/components/DataTable.tsx:68-76
 * Princípio 0 — zero scroll horizontal, por construção:
 * um ResizeObserver mede a largura real do contêiner e a tabela exibe apenas
 * as colunas que cabem (ordenadas por `priority`); as demais ficam na linha
 * expansível "▾", a um clique. O wrapper usa overflow-hidden — se a conta
 * falhar, o conteúdo trunca; nunca aparece barra de rolagem lateral. */
```
com orçamento de largura calculado em `:110-131` e `PAGE_SIZE = 20` nas páginas (`ClientsListV2.tsx:25,83-84`).

É, junto com o link público amarrado ao token (módulo 20), o melhor trabalho de engenharia que encontrei no
repositório.

---

## 14.1 Achados

### [MF-AUD-037] 7.397 linhas de telas legadas mantidas vivas por uma saída de emergência
- **Módulo:** Cadastros (e todo o ERP)
- **Arquivo:linha:** `src/App.tsx:126-139` (`LegadoOuV2`) e as 19 páginas legadas listadas na evidência
- **Categoria:** C/H — **Severidade:** P2
- **Descrição:** Desde 30/07/2026 todas as rotas com gêmea V2 **redirecionam** para a V2; a tela antiga só abre
  com `?legacy=1`, descrito no próprio código como "saída de emergência enquanto a transição não termina (o
  código v1 permanece no repositório)". Ou seja: 19 páginas, **7.397 linhas**, que nenhum usuário vê no fluxo
  normal, mas que continuam compilando, entrando no bundle e — o custo real — **exigindo correção em dobro**.
  Cada achado desta auditoria que toque uma dessas telas precisa ser decidido: corrijo nas duas, ou aceito que o
  `?legacy=1` passe a mostrar comportamento diferente do atual?

  ```
   895  FinancialPage      → FinancialV2        767  InventoryPage    → InventoryV2
   804  ServiceOrderList   → OrdersListV2       546  QuoteList        → OrdersListV2
   533  PurchaseOrdersPage → PurchaseOrdersV2   513  Dashboard        → DashboardV2
   468  ReportsPage        → ReportsV2          370  CollectionsPage  → CollectionsV2
   290  ProductList        → ProductsListV2     259  AuditLogPage     → AuditLogV2
   256  ClientDetail       → ClientDetailV2     247  SmartPurchasePage→ SmartPurchaseV2
   236  CommissionsPage    → CommissionsV2      223  MarinaList       → MarinasListV2
   222  ClientList         → ClientsListV2      216  SupplierList     → SuppliersListV2
   207  VesselList         → VesselsListV2      191  ServiceList      → ServicesListV2
   154  CRMKanbanPage      → CRMKanbanV2
  ```
  Observação importante: **isto não vale para OS, Fiscal, Settings, Agenda e WhatsApp** — nessas, a "V2" é só
  uma casca de tema sobre a página legada (`src/v2/pages/wrapped.tsx:31-49`), então não há duplicação. A dívida é
  exatamente destas 19.
- **Evidência:**
  ```tsx
  // src/App.tsx:132-139
  function LegadoOuV2({ to, legacy }: { to: string; legacy: ReactNode }) {
    const params = useParams(); const location = useLocation();
    if (new URLSearchParams(location.search).get('legacy') === '1') return <>{legacy}</>;
    let path = to; for (const [k, v] of Object.entries(params)) path = path.replace(`:${k}`, v ?? '');
    return <Navigate to={path + location.search} replace />;
  }
  ```
- **Ação recomendada:** definir uma **data de corte**. Enquanto ela não vier, a regra prática para a Fase 2 é:
  corrigir só na V2 e registrar no achado que a legada ficou para trás. Remover as 19 é uma tarefa de uma sessão
  e devolve ~7,4 mil linhas de superfície de manutenção.
- **Esforço:** M — **Decisão do Gustavo:** Sim — **a mais importante decisão estrutural desta auditoria.**
  As telas legadas ainda servem para alguma coisa (comparação, medo de regressão) ou podem ser apagadas?

### [MF-AUD-042] Lista de Marinas lê colunas que não existem — contato nunca aparece
- **Módulo:** Cadastros
- **Arquivo:linha:** `src/pages/MarinaList.tsx:154` e `:158`
- **Categoria:** A/J — **Severidade:** P3 (seria P2 se a tela legada ainda fosse a servida — ver nota ao final)
- **Descrição:** A coluna "Contato" da lista de marinas renderiza `m.contact_phone` e `m.contact_email`. A tabela
  `marinas` **não tem essas colunas** — os campos reais são `phone` e `email`
  (`src/integrations/supabase/types.ts:4617-4635`). Como o acesso é a uma propriedade inexistente, o valor é
  `undefined`: o telefone nunca é concatenado ao nome do contato, e o bloco inteiro do e-mail
  (`{m.contact_email && (…)}`) nunca renderiza. O usuário vê o nome do contato e conclui que a marina não tem
  telefone cadastrado.
  Este é o tipo de erro que `tsc` pega — e de fato pega (ver MF-AUD-045): `error TS2551: Property 'contact_phone'
  does not exist … Did you mean 'contact_name'?`. Passou porque a compilação de tipos não roda em lugar nenhum.
- **Evidência:**
  ```tsx
  // src/pages/MarinaList.tsx:151-158
  {m.contact_name && (
    <div className="flex items-center gap-1.5">
      <Phone className="h-3 w-3 shrink-0" />
      {m.contact_name}{m.contact_phone ? ` · ${m.contact_phone}` : ''}
    </div>
  )}
  {m.contact_email && (
  ```
  ```
  marinas.Row: { … contact_name: string | null; email: string | null; phone: string | null; … }
  ```
- **Ação recomendada:** trocar por `m.phone` / `m.email`.
  **Nota que muda a prioridade:** a gêmea `MarinasListV2.tsx:91-97` — que é a tela realmente servida hoje — já
  usa as colunas certas (`[m.contact_name, m.phone].filter(Boolean).join(' · ')` e `m.email`). O defeito só
  aparece com `?legacy=1`. É a ilustração perfeita do custo descrito em MF-AUD-037: a correção foi feita na V2 e
  a legada ficou para trás, silenciosamente.
- **Esforço:** S — **Decisão do Gustavo:** Não (mas depende da decisão de MF-AUD-037: se as legadas forem
  apagadas, este achado desaparece junto).

### [MF-AUD-038] Diálogos de cadastro fora do i18n
- **Módulo:** Cadastros + i18n
- **Arquivo:linha:** `src/components/AppUserEditDialog.tsx` (30 ocorrências), `ClientFormDialog`,
  `MarinaFormDialog`, `VesselFormDialog` — ver contagem completa no módulo 22
- **Categoria:** E — **Severidade:** P3
- **Descrição:** Subconjunto do MF-AUD-028, anotado aqui porque é o ponto de maior densidade: os formulários de
  cadastro concentram rótulos, placeholders e mensagens de validação, e nenhum deles passa pelo `useI18n`.
- **Evidência:** ver tabela em `audit/22-i18n.md` §22.1.
- **Ação recomendada:** tratar junto com MF-AUD-028.
- **Esforço:** S por arquivo — **Decisão do Gustavo:** Não.

---

## 14.2 Verificações feitas que **não** produziram achado

- **Paginação:** presente nas duas gerações, com `PAGE_SIZE = 20`.
- **Responsividade:** legadas usam `hidden md:table-cell`/`hidden lg:table-cell`; V2 usa orçamento de colunas
  medido em runtime. Nenhuma lista de cadastro tem `min-w-[NNNpx]` forçando scroll lateral (os `min-w` grandes
  que existem estão em painéis financeiros — ver módulo 12).
- **Renomeação de colunas (`be13642`):** não encontrei resíduo de `full_name_or_company_name`, `boat_name`,
  `product_name` ou `marina_name` em `src/**` referindo-se às tabelas renomeadas. Os hooks usam `name` e os
  selects embutidos também (`clients(name, phone, whatsapp)`, `vessels(name, manufacturer, model)`,
  `marinas(name, latitude, longitude)`). A ressalva conhecida — `external_quote_leads.boat_name`/`marina_name`
  são colunas legítimas — continua válida.
- **`QuickProductDialog`:** o bug histórico (inserir `product_name` com `as any`) não está mais presente.

---

*Módulo 5 auditado. 2 achados (`MF-AUD-037`, `MF-AUD-038`). Hipótese #3 do briefing: **corrigida**.*
