# 10 — Ordens de Serviço + Orçamentos (Etapa 2, módulo 1)

Superfície auditada: `src/hooks/use-service-orders.ts` (881 l), `src/components/ServiceOrderForm.tsx` (2.584 l),
`src/components/service-order/*` (10), `src/components/service-orders/*` (12), `src/pages/ServiceOrderDetail.tsx`,
`ServiceOrderList.tsx`, `QuoteList.tsx`, `src/v2/pages/OrdersListV2.tsx`, `src/lib/os-financials.ts`,
`src/lib/cascade-updates.ts`, `supabase/functions/_shared/ai/tools/{service-orders,so-ops,quotes,quote-builder}.ts`,
migrations de `service_orders`.

---

## 10.0 Fatos de arquitetura estabelecidos (relevantes para todo o resto da auditoria)

**Orçamento e OS são a mesma tabela.** `service_orders.status='draft'` = orçamento (numeração `ORÇ-XXXXX`);
qualquer outro status = OS (`OS-XXXXX`). A troca acontece na primeira saída de `draft`, preservando o número da
sequência (`use-service-orders.ts:194-199`). O ciclo do orçamento tem uma **segunda máquina de estados** na
coluna `quote_status` (`draft → sent → awaiting_approval → approved → awaiting_deposit`), independente de `status`.

**Status válidos de `service_orders.status`** (CHECK vigente, `supabase/migrations/20260422155330_*.sql:3`):
```sql
CHECK (status = ANY (ARRAY['draft','scheduled','open','in_progress','awaiting_parts',
                           'awaiting_client','approved','completed','invoiced','cancelled']));
```
Este é o gabarito usado em todos os achados de status abaixo.

**A "UI V2" não é uma segunda implementação da tela de OS.** `src/v2/pages/wrapped.tsx:31-49` mostra que
`ServiceOrderDetailV2`, `FiscalEmissionV2`, `SettingsV2`, `AgendaV2` e as telas de WhatsApp/orçamento externo são
**cascas de tema** (`wrap(Comp) => <V2Shell><Comp/></V2Shell>`) em volta das páginas legadas. Só as **listas**
(`OrdersListV2`, `ClientsListV2`, …) são reescritas de verdade. Correção da leitura preliminar da Etapa 0: o risco
de divergência legado×V2 está concentrado nas listas, não no formulário de OS.

---

## 10.1 Achados

### [MF-AUD-005] Dropdown de OS da Agenda filtra por status que não existem e omite os que existem
- **Módulo:** OS + Agenda — **confirma a hipótese #4 do briefing**
- **Arquivo:linha:** `src/hooks/use-agenda.ts:163`
- **Categoria:** A — **Severidade:** P1
- **Descrição:** `useSchedulableOrders()` restringe a lista de OS agendáveis a
  `['draft','pending','approved','scheduled','in_progress','waiting_parts','waiting_approval','reopened']`.
  Comparando com o CHECK da tabela: **`pending`, `waiting_parts`, `waiting_approval` e `reopened` não existem** —
  nenhuma linha do banco pode ter esses valores. Pior: **`open` está ausente da lista**, e `open` é o status
  natural de uma OS aberta e ainda não iniciada; `awaiting_parts` e `awaiting_client` (os nomes reais) também
  ficam de fora. Resultado prático: o dialog de agendamento só enxerga OS em `draft`, `approved`, `scheduled` e
  `in_progress`. Numa operação onde a maior parte das OS ativas está em `open`/`awaiting_*`, o dropdown aparece
  vazio ou quase — exatamente o sintoma relatado.
- **Evidência:**
  ```ts
  // src/hooks/use-agenda.ts:161-163
  // Valid schedulable statuses — includes draft/approved so newly created/approved
  // orders appear in the Agenda scheduling dialog before being assigned a technician
  .in('status', ['draft', 'pending', 'approved', 'scheduled', 'in_progress', 'waiting_parts', 'waiting_approval', 'reopened'])
  ```
  contra `supabase/migrations/20260422155330_a263a2c2-22bc-4c12-b351-506c95fc51ec.sql:3`.
- **Ação recomendada:** substituir a lista literal por uma constante única derivada do CHECK (ex.: exportar
  `SCHEDULABLE_STATUSES` de `use-service-orders.ts`, onde `STATUS_TRANSITIONS` já enumera os status reais) e
  cobrir com um teste que falhe se a lista sair do conjunto válido.
- **Esforço:** S — **Decisão do Gustavo:** Sim — decidir se `completed`/`invoiced` devem poder ser reagendados
  (hoje ficariam de fora, o que parece correto).

### [MF-AUD-006] A visão "sem próxima ação" do agente ignora todas as OS em `open`
- **Módulo:** Agente AI / OS
- **Arquivo:linha:** `supabase/functions/_shared/ai/tools/overview.ts:159`
- **Categoria:** A — **Severidade:** P1
- **Descrição:** Mesma classe de erro do achado anterior, num caminho diferente. A tool de visão geral monta
  "OS ativas sem tarefa viva vinculada" filtrando por
  `['approved','scheduled','in_progress','waiting_parts','waiting_approval','reopened']`. Três desses status são
  inexistentes e **`open`, `awaiting_parts` e `awaiting_client` estão fora**. O painel/resumo do agente reporta um
  número de "OS sem próxima ação" sistematicamente menor que a realidade — um falso "está tudo coberto".
- **Evidência:**
  ```ts
  // supabase/functions/_shared/ai/tools/overview.ts:156-159
  .from("service_orders")
  .select("id, service_order_number, status, clients(name)")
  .in("status", ["approved", "scheduled", "in_progress", "waiting_parts", "waiting_approval", "reopened"])
  ```
- **Ação recomendada:** mesma constante única do achado MF-AUD-005, compartilhada com as Edge Functions
  (`_shared/` já é o lugar natural).
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-007] O system prompt ensina ao agente quatro status que o banco rejeita
- **Módulo:** Agente AI
- **Arquivo:linha:** `supabase/functions/_shared/ai/prompt.ts:16-17`
- **Categoria:** A/D — **Severidade:** P2
- **Descrição:** A tabela de status embutida no prompt estável inclui `pending`, `waiting_parts`,
  `waiting_approval` e `reopened`. O modelo aprende que esses valores são legítimos e pode emitir
  `update_service_order_status` com um deles; o INSERT/UPDATE quebra no CHECK (`23514`) e o usuário recebe um erro
  incompreensível — ou, se a tool engolir o erro, uma confirmação falsa. Também desperdiça tokens do prefixo
  estável (que já é a maior parte do custo do agente).
- **Evidência:**
  ```ts
  // supabase/functions/_shared/ai/prompt.ts:16-17
  const STATUS_LABELS_TEXT =
    "draft=Orçamento, open=Aberto, pending=Pendente, approved=Aprovado, scheduled=Agendado, in_progress=Em andamento, waiting_parts=Aguardando peças, waiting_approval=Aguardando aprovação, completed=Concluído, cancelled=Cancelado, invoiced=Faturado, reopened=Reaberto.";
  ```
- **Ação recomendada:** gerar `STATUS_LABELS_TEXT` a partir da mesma constante única; remover os quatro inválidos
  e acrescentar `awaiting_client`.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-008] Timeline da OS tem rótulos para status inexistentes
- **Módulo:** OS
- **Arquivo:linha:** `src/components/ServiceOrderTimeline.tsx:48-49`
- **Categoria:** C — **Severidade:** P3
- **Descrição:** `waiting_parts: 'Aguardando peças'` e `waiting_approval: 'Aguardando aprovação'` no mapa de
  rótulos. São chaves mortas (nenhum registro pode tê-las) e, pior, mascaram a ausência dos rótulos corretos
  `awaiting_parts`/`awaiting_client` — se um deles não estiver mapeado, a timeline mostra a chave crua.
- **Evidência:** `src/components/ServiceOrderTimeline.tsx:48-49`
- **Ação recomendada:** alinhar o mapa aos status reais; verificar de passagem se `awaiting_client` tem rótulo.
- **Esforço:** S — **Decisão do Gustavo:** Não.

> **Nota de classe.** Os quatro achados acima são a mesma falha, replicada. O plano `plans/marineflow-contexto-vivo.md`
> (§7, "Bug encontrado de passagem") relata **esta exata lista fantasma** sendo corrigida no detector da agenda em
> 27/07/2026 — mas a correção foi pontual e os outros quatro call sites ficaram. Recomendação estrutural para a
> Fase 2: eliminar a possibilidade de repetir, com uma constante única exportada e um teste de guarda.

### [MF-AUD-009] Alterar itens de uma OS pelo agente não atualiza os recebíveis (e não respeita o piso do já pago)
- **Módulo:** OS + Financeiro + Agente AI
- **Arquivo:linha:** `src/lib/cascade-updates.ts:12-30` vs `supabase/migrations/20260715163000_create_recalc_so_totals.sql:26-101`;
  chamadas em `supabase/functions/_shared/ai/tools/service-orders.ts:17`, `so-ops.ts:301,534`, `quotes.ts:623`,
  `quote-builder.ts:197`
- **Categoria:** A — **Severidade:** P1
- **Descrição:** Existem dois caminhos para alterar o valor de uma OS, e eles fazem coisas diferentes:
  - **Pela tela:** `recalcTotals()` (`use-service-orders.ts:335-393`) chama `updateReceivableFromSO()`, que
    (a) **bloqueia** a alteração se o novo total ficar abaixo do que o cliente já pagou
    (`GrandTotalBelowPaidError`) e (b) redistribui proporcionalmente os recebíveis pendentes.
  - **Pelo agente:** as tools chamam a RPC `recalc_so_totals`, que atualiza `labor_cost_total`,
    `parts_cost_total`, `card_fee_amount` e `grand_total` **em `service_orders` apenas**. Nenhuma cascata para
    `receivables`, nenhuma checagem do piso do já pago.

  Nenhum trigger cobre a lacuna: o único trigger de `service_orders` que toca em recebíveis é
  `trg_sync_balance_due_on_completion`, e ele só dispara em `AFTER UPDATE ... WHEN (NEW.status='completed' AND
  OLD.status IS DISTINCT FROM 'completed')` — ou seja, na conclusão, não em mudança de itens.

  Consequência: o agente adiciona/remove peça ou serviço, o total da OS muda, e o título a receber continua com o
  valor antigo. O financeiro passa a divergir da OS silenciosamente. E é possível, pelo agente, derrubar o total
  abaixo do valor já recebido do cliente — cenário que a tela bloqueia de propósito.
- **Evidência:**
  ```sql
  -- 20260715163000_create_recalc_so_totals.sql:94-99 — escopo da RPC
  update service_orders
  set labor_cost_total = v_labor, parts_cost_total = v_parts,
      card_fee_amount = v_card_fee_amount, grand_total = v_grand_total
  where id = so_id;
  ```
  ```ts
  // src/lib/cascade-updates.ts:24-29 — proteção que só existe no frontend
  const totalPaid = receivables.reduce((s, r) => s + Number(r.paid_amount || 0), 0);
  if (newTotal < totalPaid - 0.01) { throw new GrandTotalBelowPaidError(...) }
  ```
  ```sql
  -- 20260727180000_balance_due_on_completion.sql:46-50 — único trigger, só na conclusão
  CREATE TRIGGER trg_sync_balance_due_on_completion AFTER UPDATE ON public.service_orders
  FOR EACH ROW WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  ```
- **Ação recomendada:** mover a cascata para o banco — estender `recalc_so_totals` (ou criar
  `so_apply_total_change`) com a mesma regra de redistribuição e o mesmo piso, e fazer o frontend passar a chamá-la
  em vez de reimplementar. Enquanto isso não acontecer, qualquer tool que altere itens precisa replicar a cascata.
- **Esforço:** M — **Decisão do Gustavo:** Sim — confirmar que a regra de redistribuição proporcional
  (`cascade-updates.ts:33-52`: quitados nunca redimensionados, pendentes rateados pela participação anterior) é a
  regra de negócio desejada antes de fossilizá-la em SQL.

### [MF-AUD-010] Troca de técnicos da OS: apaga primeiro, insere depois, sem transação e sem checar erro
- **Módulo:** OS
- **Arquivo:linha:** `src/components/ServiceOrderForm.tsx:886-898` (e `:828-833` no caminho de criação)
- **Categoria:** A — **Severidade:** P2
- **Descrição:** Ao salvar uma OS existente, o formulário **deleta todos** os vínculos de
  `service_order_technicians` e só então insere os selecionados. As duas chamadas descartam o retorno — nem
  `error` é inspecionado. Se o INSERT falhar (RLS, rede, conflito), a OS fica **sem nenhum técnico** e o usuário
  vê a mensagem de sucesso. Não há transação nem rollback: o delete já foi commitado.
- **Evidência:**
  ```ts
  // src/components/ServiceOrderForm.tsx:892-898
  await supabase.from('service_order_technicians').delete().eq('service_order_id', orderId!);
  const validTechs = selectedTechnicians.filter(uid => uid && uid.trim() !== '');
  if (validTechs.length > 0) {
    await supabase.from('service_order_technicians').insert(
      validTechs.map((uid) => ({ service_order_id: orderId!, user_id: uid }))
    );
  }
  ```
- **Ação recomendada:** RPC `so_set_technicians(p_so_id uuid, p_user_ids uuid[])` que faça delete+insert numa
  transação, ou, no mínimo, calcular o diff (só remover os que saíram, só inserir os que entraram) e checar
  `error` nas duas chamadas.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-011] A mesma fórmula de total existe em três implementações independentes; a testada não é a que grava
- **Módulo:** OS
- **Arquivo:linha:** `src/lib/os-financials.ts:55-77` (pura, com testes) · `src/hooks/use-service-orders.ts:335-393`
  (inline, é a que grava pela tela) · `supabase/migrations/20260715163000_create_recalc_so_totals.sql:56-99` (SQL,
  é a que grava pelo agente)
- **Categoria:** H — **Severidade:** P2
- **Descrição:** `computeOsFinancials` foi extraída justamente para "pinar o comportamento atual para que a
  decomposição do formulário nunca altere um centavo" e tem suíte própria (`os-financials.test.ts`). Mas o caminho
  de **gravação** não a usa: `recalcTotals()` reimplementa a soma à mão, e a RPC a reimplementa em PL/pgSQL. Hoje
  as três concordam (conferido linha a linha: subtotal, base, taxa de cartão pelo mesmo gross-up); o problema é
  estrutural — qualquer mudança de regra precisa ser feita em três lugares, e só um deles tem teste. Divergência
  já existente, ainda que menor: `recalcTotals` grava `labor_hours_total` (somando `time_entries` faturáveis) e a
  RPC **não**, então uma hora lançada pelo agente atualiza o valor mas deixa o total de horas defasado.
- **Evidência:** as três fórmulas transcritas acima; `use-service-orders.ts:386-392` grava `labor_hours_total`,
  ausente do `update` da RPC (`...:94-99`).
- **Ação recomendada:** eleger o SQL como fonte única (é o único ponto por onde os dois caminhos passam), fazer o
  frontend chamar a RPC e manter `os-financials.ts` só para a **projeção** em tela (o que ainda não foi salvo).
  Acrescentar `labor_hours_total` à RPC.
- **Esforço:** M — **Decisão do Gustavo:** Sim — é uma refatoração de caminho crítico de dinheiro; precisa de
  autorização explícita e de uma janela para validar.

### [MF-AUD-012] `recalcTotals` do frontend não protege OS cancelada, ao contrário da RPC
- **Módulo:** OS
- **Arquivo:linha:** `src/hooks/use-service-orders.ts:335-393` vs
  `supabase/migrations/20260715163000_create_recalc_so_totals.sql:51-54`
- **Categoria:** H — **Severidade:** P3
- **Descrição:** A RPC declara e implementa um invariante: "OS canceladas têm o total histórico congelado de
  propósito … a função nunca deve sobrescrever uma OS cancelada". O `recalcTotals` do frontend não tem essa
  guarda. Hoje o risco é baixo porque a tela bloqueia edição (`ServiceOrderForm.tsx:1665` —
  `isLocked = currentStatus === 'invoiced' || currentStatus === 'cancelled'`), mas a proteção depende de UI, não
  do dado. Qualquer caminho novo que chame `recalcTotals` numa OS cancelada destrói o histórico do estorno.
- **Evidência:**
  ```sql
  -- migration:51-54
  select status into v_status from service_orders where id = so_id;
  if not found or v_status = 'cancelled' then return; end if;
  ```
  Nada equivalente em `use-service-orders.ts:335`.
- **Ação recomendada:** resolvido de graça se MF-AUD-011 for adotado (frontend passa a chamar a RPC). Caso
  contrário, replicar a guarda.
- **Esforço:** S — **Decisão do Gustavo:** Não.

---

## 10.2 Verificações feitas que **não** produziram achado

- **Hipótese #6 do briefing (erro de UUID ao vincular técnico): CORRIGIDA.** O formulário tem o helper
  `uuidOrNull` aplicado a todos os campos UUID opcionais (`ServiceOrderForm.tsx:803, 809-813`) e filtra strings
  vazias antes de inserir técnicos (`:828, :893`). Todos os pontos que gravam `technician_user_id` usam
  `|| null`/`|| undefined` (`:874, :1375, :1415, :1481, :1615, :1632`). Nenhum caminho encontrado que envie `''`
  para uma coluna `uuid`.
- **Numeração de documentos:** correta e à prova de concorrência — `next_document_number()` sobre sequência
  Postgres (`use-service-orders.ts:73-77`), prefixo trocado sem perder o número na conversão (`:194-199`).
- **Reversão de alterações que baixariam o total abaixo do pago:** implementada com snapshot completo e
  re-inserção da linha removida (`:469-473, :510-519` para peças; `:721-742` para serviços). É um cuidado acima da
  média para o padrão do repositório.
- **Duplicação de OS (`useDuplicateServiceOrder`, `:752-880`):** desestrutura e descarta explicitamente 30 campos
  de runtime/financeiro/assinatura antes de copiar, e **não** baixa estoque na cópia (`:838-839`). Correto.
- **Invalidação de cache do React Query:** consistente nas mutations do módulo, incluindo as chaves cruzadas
  (`pdf-data`, `receivables`, `purchase-needs`, `products`).
- **`staleTime`:** presente onde importa em `useServiceOrders`/`useServiceOrder` (30 s). Ausente nas queries de
  sub-itens (`so-parts`, `so-services`, `time-entries`), o que é defensável para dados que mudam a cada ação do
  usuário — **não** classifico como achado.

---

*Módulo 1 auditado. 8 achados (`MF-AUD-005`..`MF-AUD-012`).*
