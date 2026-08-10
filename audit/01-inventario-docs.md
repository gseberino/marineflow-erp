# 01 — Inventário de Documentação e Memórias (Etapa 1)

**48 arquivos `.md`** no repositório (fora `node_modules`, `.git`, `dist`). Datas = último commit que tocou o arquivo.
Os itens marcados `[V-nn]` são **verificáveis** e alimentam a matriz da Etapa 3 (`90-docs-vs-codigo.md`).

---

## 1.1 Documentos de operação do repositório

### `CLAUDE.md` — 13 linhas — 03/08/2026
Propósito: instrução operacional única, sobre deploy de Edge Function.
- `[V-01]` Afirma que `supabase functions deploy` **trava sem erro** quando o Docker não está rodando, e que o
  correto é sempre `--use-api` com `--project-ref okurngvcodmljjicopdp`.
- `[V-02]` Fixa `okurngvcodmljjicopdp` como o project-ref canônico.

> Observação: este `CLAUDE.md` **não** contém arquitetura, convenções de código, regras de teste ou mapa de
> módulos — é um bilhete de deploy. Toda a doutrina do projeto está no `~/.claude/CLAUDE.md` global e nos `plans/`.

### `README.md` — 3 linhas — 01/01/2025
```markdown
# Welcome to your Lovable project

TODO: Document your project here
```
- `[V-03]` README é o **placeholder original do Lovable**, nunca preenchido, num projeto de 146 mil linhas.

### `.lovable/plan.md` — 154 linhas — 25/04/2026
Propósito: plano original do Agente de IA (documento fundador do módulo AI). **É a fonte da hipótese #8 do briefing.**
- `[V-04]` "Modelo padrão: `google/gemini-2.5-pro`" via `https://ai.gateway.lovable.dev/v1/chat/completions` com `LOVABLE_API_KEY`.
- `[V-05]` "Limite: **máx. 8 iterações** de tool-calling por requisição."
- `[V-06]` Confirmação em duas etapas obrigatória: `propose_action` antes de qualquer escrita/envio.
- `[V-07]` Lista de **22 tools** nominais (8 de leitura, 11 de escrita, 3 de WhatsApp).
- `[V-08]` "Tokens **Z-API** permanecem no backend"; `send_whatsapp_message` "envia via **Z-API**".
- `[V-09]` Tools de escrita "validam payload com **Zod** antes de tocar o banco"; "Nenhum SQL bruto".
- `[V-10]` Nomes de coluna antigos nas tools: `full_name_or_company_name`, `boat_name`, `product_name`.
- `[V-11]` Fora do escopo v1: persistência de histórico no banco, streaming, voz, envio em lote.

### `.claude/skills/*/SKILL.md` — 4 skills
`env-check` (83 l, 02/07), `multi-session-guard` (91 l, 23/07), `catalogo-fotos` (117 l, 27/07),
`dimensionamento-cabo-cc` (86 l, 05/08).
- `[V-12]` `multi-session-guard` prescreve worktree isolado e staging por arquivo (nunca `git add -A`).
- `[V-13]` `dimensionamento-cabo-cc` implica lógica de cabo CC no código (`src/lib/cable-sizing.test.ts` existe).

### `infra/evolution/TUNNEL.md` — 62 linhas — 11/06/2026
- `[V-14]` Evolution API roda **local** em `localhost:8081`, exposta por **Cloudflare Quick Tunnel**, com URL
  nova a cada reinício e um auto-update que reescreve o segredo. Dependência de infra de máquina do dono.

### `scripts/catalogo-fotos/README.md` — 81 linhas — 27/07/2026
Script auxiliar de catálogo de fotos.

### `reports/staging-readiness-*.md` — 20 arquivos, 12-14 linhas cada — todos de 19/05/2026
Saídas automáticas de um verificador de staging. Conteúdo idêntico entre si, tabelas todas com `(0)` registros.
- `[V-15]` 20 arquivos de relatório efêmero versionados no repo, apontando para `C:\temp\.env.staging.local`.
  Candidato a limpeza (categoria C).

---

## 1.2 Documentação técnica (`docs/`, 3 arquivos)

### `docs/HANDOFF-EVOLUTION-CUTOVER.md` — 262 linhas — 23/07/2026
Migração Z-API → Evolution API.
- `[V-16]` Declara-se em estado **"cutover executado, em fase de validação ponta a ponta (debug de mensagem
  recebida não gravada)"** — ou seja, documento **congelado num bloqueio**.
- `[V-17]` "§3 ⚠️ BLOQUEIO ATUAL — onde paramos" + §4 instruções para criar tabela de debug e função
  `evolution-debug` temporária, e §4.5 "Reapontar para produção". Verificar se sobrou lixo desse debug.
- `[V-18]` Aponta para a branch `claude/keen-brown-j2pgw0` e diz "este arquivo foi salvo solto em
  `D:\PC\marineflow-erp` — **não está commitado**" (mas está: vive em `docs/`).
- `[V-19]` §8 documenta procedimento de **rollback para Z-API** — implica código Z-API ainda presente.

### `docs/ai-operator-setup.md` — 103 linhas — 06/07/2026
- `[V-20]` "**Fase 1: migração para Claude via OpenRouter**" — o agente deveria rodar **Claude**, roteado por
  **OpenRouter**, não Gemini/Lovable. **Contradiz diretamente `[V-04]`.**
- `[V-21]` Secrets esperados no Supabase (§"Secrets a configurar").
- `[V-22]` §"Fase 4 — canal WhatsApp interno (equipe)": secret novo, habilitar funcionário, **PIN para ações de
  risco alto**.

### `docs/fiscal-devolucao-simples.md` — 93 linhas — 27/07/2026
Referência fiscal (ICMS destacado, IPI em `impostoDevol`/`vIPIDevol`, infCpl, referência VC02-14).
- `[V-23]` Regras fiscais concretas verificáveis contra `fiscal-emit`/`nfe-*`.

---

## 1.3 Planos (`plans/`, 17 arquivos, 4.422 linhas)

| Arquivo | Data | Linhas | Status declarado |
|---|---|---:|---|
| `marineflow-execucao-os-roteiro.md` | 31/07 | 1.509 | Roteiro rev.2 (Ciclo do Serviço) |
| `marineflow-agenda-tarefas.md` | 24/07 | 461 | **Fases 0-4 CONCLUÍDAS e em produção** |
| `marineflow-compras-cotacao.md` | 05/08 | 367 | **EM PRODUÇÃO** (C0-C4 ✅, C5 ✅ parcial) |
| `marineflow-integracao-bancaria.md` | 27/07 | 338 | **PROPOSTA — aguardando decisões da Fase 0** |
| `marineflow-agenda-benchmark-mercado.md` | 24/07 | 279 | Benchmark + roadmap Fases 5-8 |
| `marineflow-agenda-autonoma.md` | 26/07 | 195 | Proposta Fases 9-11 + decisões tomadas |
| `marineflow-contexto-vivo.md` | 06/08 | 172 | **Fases 13 e 14 ✅ CONCLUÍDAS**; F12 idem |
| `marineflow-conciliacao-inteligente.md` | 27/07 | 163 | **ENTREGUE Fases 1-3**; Fase 4 não feita |
| `marineflow-ciclo2-fase1-execucao.md` | 22/07 | 159 | Blocos A-F, "B FEITO via prompt" |
| `marineflow-open-finance-auditoria-e-roteiro.md` | 08/08 | 146 | Roteiro Fases A-F (o mais recente) |
| `marineflow-comunicacao-inteligente.md` | 23/07 | 143 | Plano-piloto Fases 0-3 |
| `marineflow-conciliacao-definitiva.md` | 05/08 | 112 | Fases F1-F5 |
| `marineflow-contexto-unificado-escopo.md` | 22/07 | 99 | Etapas 1-3 |
| `marineflow-executivo-financeiro.md` | 29/07 | 92 | **PROPOSTA — aguardando 5 decisões** |
| `marineflow-transcricao-ligacoes-avaliacao.md` | 26/07 | 85 | Avaliação — nada construído |
| `marineflow-llm-orquestra-codigo-executa.md` | 22/07 | 62 | Plano de eficiência |
| *(`marineflow-agenda-benchmark` contabilizado acima)* | | | |

### Itens verificáveis extraídos dos planos

**`marineflow-agenda-tarefas.md` (Fases 0-4, declaradas concluídas 24/07)**
- `[V-24]` Rename `technician_user_id → assignee_user_id` em `agenda_tasks`, propagado a `use-agenda.ts`,
  `AgendaPage.tsx`, `AgendaTaskDialog.tsx`, `_shared/ai/tools/agenda.ts`, `_shared/ai/tools/field-ops.ts`.
- `[V-25]` Edge `scheduling-automations` **apagada** (declarada morta).
- `[V-26]` Constraint `btree_gist` rejeitando double-booking.
- `[V-27]` Motor `task-automations` com regras **R1-R8** + auto-resolução + dedupe, cron `*/15`.
- `[V-28]` R9 (cliente) nasce **OFF**; R10 (técnico).
- `[V-29]` **9 tools de agenda** para a IA substituindo as 4 antigas.
- `[V-30]` Briefing 07:30 com "Sua agenda hoje".
- `[V-31]` "semana mobile **sem scroll horizontal**" (aceite explícito) — cruza com hipótese #5 do briefing.
- `[V-32]` `EntityTasksPanel` em OS/cliente/orçamento + widget no Dashboard.
- `[V-33]` Fase 4 (recorrência RRULE, drag-and-drop, snooze, métricas BI) marcada como opcional/posterior.

**`marineflow-compras-cotacao.md` (EM PRODUÇÃO 30/07)**
- `[V-34]` `src/lib/purchase-needs.ts` + **14 testes**; `src/hooks/use-purchase-needs.ts`.
- `[V-35]` `src/lib/quote-comparison.ts` + **19 testes**; telas `QuoteRequestsPage`, `QuoteRequestDetailPage`.
- `[V-36]` Regra **R16** (tarefas de compra na aprovação) e **R17** (cobrança de cotação parada) no motor.
- `[V-37]` `PurchaseNeedsDialog` substituiu o `StockConfirmationDialog` "quebrado" — o antigo não deve mais existir.
- `[V-38]` RLS das 5 tabelas de compras em `is_admin_or_financial`, uma política por comando, `TO authenticated`,
  revoke de anon.
- `[V-39]` `product_suppliers` **não deve ser dropada** (vazia, mas com 4 pontos de uso).
- `[V-40]` Em aberto: frete/desconto por fornecedor não persistem; `scripts/v2-viewport-check.mjs` não rodado nas
  rotas novas.

**`marineflow-conciliacao-inteligente.md` (ENTREGUE Fases 1-3, 27/07)**
- `[V-41]` `supabase/functions/_shared/banking/{types,matching,quote-deposit}.ts`.
- `[V-42]` Pesos: valor 45 · documento 25 · nome 15 · data 15 · bônus 12; tolerância 2% limitada a R$ 50.
- `[V-43]` `banking-reconcile` com 5 origens de candidatos e `action: 'suggest' | 'auto'`; **`verify_jwt=false`
  com auth dupla (JWT ou cron)** — ponto de atenção de segurança (módulo 18/20).
- `[V-44]` Tools `listar_transacoes_pendentes`, `sugerir_conciliacao` (risk low), `conciliar_transacao` (risk high).
- `[V-45]` "Testes: 24 do motor, 8 de paridade, 4 de render. **Suíte 304**." — número total de testes verificável.
- `[V-46]` Fase 4 (memória de conciliação, 1-para-muitos, parcial, juros/tarifa) **não feita** — mas
  `reconciliation_memory` e `remember_reconciliation` existem no schema (checar).

**`marineflow-conciliacao-definitiva.md` (05/08)**
- `[V-47]` ~380 transações "ignoradas" sem tela nem desfazer → F1 "Livro das ignoradas + desfazer (URGENTE)".
  Existe `IgnoradasPanel.tsx` — verificar se F1 foi entregue.
- `[V-48]` "Estado único da linha bancária" como decisão de arquitetura.

**`marineflow-contexto-vivo.md` (Fases 12-14 concluídas)**
- `[V-49]` `entity_open_loops` + view `erp_open_loop_facts` + `refresh_entity_open_loops()` rodando **dentro do
  motor de 15 min**, SQL puro, zero IA.
- `[V-50]` Painel de fios soltos é **somente leitura** (nenhum botão "resolver").
- `[V-51]` Título só vira fio dentro de **15 dias** do vencimento.
- `[V-52]` Tool `get_open_loops` para o agente.
- `[V-53]` Bug corrigido: detector filtrava OS por status inexistentes (`waiting_parts`, `waiting_approval`,
  `reopened`) e omitia `open`/`awaiting_parts` — **verificar se a correção sobreviveu**.
- `[V-54]` Aceite F12: **≥70%** das mensagens dos últimos 30 dias com contato identificado.

**`marineflow-integracao-bancaria.md` (proposta, mas com auditoria embutida de 27/07)**
- `[V-55]` "⚠️ Auditoria 27/07/2026 — a Fase 0.5 JÁ EXISTIA (e estava com bugs)".
- `[V-56]` Camada trocável `_shared/banking` com interface mínima em `types.ts`.
- `[V-57]` Segredos em Supabase secrets, **nunca no repo**.

**`marineflow-open-finance-auditoria-e-roteiro.md` (08/08 — o mais recente)**
- `[V-58]` "2.141 transações reais" medidas; "tratamos cartão com o modelo de dados de transferência bancária".
- `[V-59]` FASE F — "Correções pendentes já identificadas" (lista de dívidas abertas).

**`marineflow-ciclo2-fase1-execucao.md`**
- `[V-60]` "**63 tools** reais, conferidas em 2026-07-21" em `_shared/ai/tools/*.ts` — contagem verificável.
- `[V-61]` Bloco B (voz → plano → confirmação) "FEITO via prompt — 2026-07-21".
- `[V-62]` Blocos A, A′, C, D, E, F com definição de pronto de 9 pontos.

**`marineflow-llm-orquestra-codigo-executa.md`**
- `[V-63]` Incidente medido: 1 pedido real → ~15 chamadas de LLM → estouro do teto de **150 s** da Edge Function
  (**HTTP 546**). Alavancas: macro-tools, resolvedor por palavra-chave, cache.

**`marineflow-execucao-os-roteiro.md` (1.509 l — o maior)**
- `[V-64]` Modelo de dados proposto (§4 e §4-bis): tabelas de roteiro, levantamento, materiais e aprendizado —
  cruzar com `service_order_steps`, `service_step_blocks`, `service_step_templates`, `service_surveys`,
  `survey_material_rules`, `service_cases`, `work_stop_reasons`, `time_entries`.
- `[V-65]` Telas prometidas: Quadro do Dia (gestor), Modo Foco (técnico/celular), Painel do Roteiro, Levantamento.
- `[V-66]` 22 princípios de produto (P1-P22) — os operacionalizáveis: P6 "parada tem código"
  (`work_stop_reasons`), P8/P18 "estimativa é faixa", P19 "miudeza se rateia", P21 "sinal de aprendizado é o diff".

**Planos em estado de PROPOSTA (nada deveria estar implementado):**
- `[V-67]` `marineflow-executivo-financeiro.md` — 5 decisões pendentes, 5 módulos não construídos.
- `[V-68]` `marineflow-transcricao-ligacoes-avaliacao.md` — "**Isto é uma AVALIAÇÃO, não uma implementação.
  Nada foi construído**".
- `[V-69]` `marineflow-comunicacao-inteligente.md` — Fases 0-3 de inteligência de comunicação.
- `[V-70]` `marineflow-contexto-unificado-escopo.md` — Etapas 1-3 (Ficha 360, resolução de contato, memória).
- `[V-71]` `marineflow-agenda-autonoma.md` — Fases 9-11 (caixa de entrada de sugestões, captura por voz,
  autonomia graduada). Existe `agenda-voice-capture` e `agenda_suggestions` — verificar o que foi além do plano.

---

## 1.4 Memórias locais (fora do repositório)

Diretório `D:\IA-HBR\Claude-Code-State\projects\C--Users-PC\memory\` — índice `MEMORY.md` com **~50 memórias**.
São observações datadas do assistente, não documentação do produto; entram na auditoria apenas como **fonte de
hipótese**, nunca como evidência. As diretamente relevantes:

- `project_marineflow_repo_canonical` — fixa pasta/branch/projeto Supabase canônicos (usada na Etapa 0).
- `feedback_edge_functions_deno_check` — "o `tsc` do projeto **NÃO** cobre `supabase/functions`".
- `feedback_marineflow_tsc_e_mobile` — "`--noEmit` NÃO checa nada neste repo (`tsconfig files:[]`)".
- `feedback_validar_por_render` — incidente de TDZ; origem dos 18 `*.smoke.test.tsx`.
- `feedback_supabase_view_security_invoker` / `feedback_rls_policy_sem_to_authenticated` /
  `feedback_supabase_revoke_anon_function` — três classes de vazamento de RLS já vividas no projeto.
- `project_marineflow_otimizacao_tokens` — prefixo de 68.941 tokens, 135/188 tools sem uso.

---

## 1.5 Achados já registráveis desta etapa

### [MF-AUD-001] Documentação do agente AI se contradiz sobre o provedor de LLM
- **Módulo:** Documentação / Agente AI
- **Arquivo:linha:** `.lovable/plan.md:36-37,116-117` vs `docs/ai-operator-setup.md:1-6`
- **Categoria:** B — **Severidade:** P2
- **Descrição:** Dois documentos vivos no repositório descrevem provedores de LLM incompatíveis para a mesma
  Edge Function (`ai-agent`). Quem entrar no projeto lendo `.lovable/plan.md` configurará `LOVABLE_API_KEY`;
  quem ler `docs/ai-operator-setup.md` configurará OpenRouter. Nenhum dos dois se declara obsoleto.
- **Evidência:**
  - `.lovable/plan.md:36-37` — "│  - Lovable AI Gateway        │ │  - Modelo: gemini-2.5-pro    │"
  - `.lovable/plan.md:116-117` — "Usa `LOVABLE_API_KEY` … `https://ai.gateway.lovable.dev/v1/chat/completions`" / "Modelo padrão: `google/gemini-2.5-pro`"
  - `docs/ai-operator-setup.md:1` — "# AI Operator — Setup (Fase 1: migração para Claude via OpenRouter)"
- **Ação recomendada:** determinar o provedor real no código (feito no módulo 19) e marcar o documento perdedor
  como histórico, com aviso no topo. Não apagar — `.lovable/plan.md` é o documento fundador do módulo.
- **Esforço:** S — **Decisão do Gustavo:** Não (basta refletir o código).

### [MF-AUD-002] README é o placeholder do Lovable
- **Módulo:** Documentação
- **Arquivo:linha:** `README.md:1-3`
- **Categoria:** D — **Severidade:** P3
- **Descrição:** Único ponto de entrada padrão de um repositório com 146 mil linhas diz literalmente
  "TODO: Document your project here". Custo real quando entra alguém novo (ou uma sessão de IA sem memória).
- **Evidência:** `README.md` completo: `# Welcome to your Lovable project` / `TODO: Document your project here`
- **Ação recomendada:** README mínimo: o que é, como rodar, onde ficam `plans/`, qual o project-ref, como
  deployar edge function (mover o conteúdo do `CLAUDE.md`).
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-003] 20 relatórios efêmeros de maio versionados em `reports/`
- **Módulo:** Documentação / limpeza
- **Arquivo:linha:** `reports/staging-readiness-2026-05-19T*.md` (20 arquivos, 272 linhas no total)
- **Categoria:** C — **Severidade:** P3
- **Descrição:** Saídas datadas de um verificador de staging de 19/05/2026, todas com resultado idêntico e
  tabelas vazias `(0)`. Referenciam um caminho de máquina (`C:\temp\.env.staging.local`). Ruído permanente em
  buscas e em qualquer varredura de `.md`.
- **Evidência:** `reports/staging-readiness-2026-05-19T17-03-17-427Z.md:1-12` — "Status: ready_for_schema_validation
  … Env file path: C:\temp\.env.staging.local … - clients: readable (0)"
- **Ação recomendada:** remover o diretório do versionamento e adicionar `reports/` ao `.gitignore`.
- **Esforço:** S — **Decisão do Gustavo:** Sim — confirmar que nenhum desses relatórios tem valor histórico.

### [MF-AUD-004] `docs/HANDOFF-EVOLUTION-CUTOVER.md` congelado num bloqueio já superado
- **Módulo:** Documentação / WhatsApp
- **Arquivo:linha:** `docs/HANDOFF-EVOLUTION-CUTOVER.md:2-8, 86-104`
- **Categoria:** B — **Severidade:** P2
- **Descrição:** O handoff se apresenta como estado atual ("Última atualização: cutover executado, em fase de
  validação ponta a ponta (debug de mensagem recebida não gravada)") e tem uma seção "⚠️ BLOQUEIO ATUAL — onde
  paramos". A Evolution está em produção desde junho. O documento também afirma "este arquivo foi salvo solto em
  D:\PC\marineflow-erp para leitura — **não está commitado**" enquanto está commitado em `docs/`. Instrui a criar
  uma função `evolution-debug` e uma tabela de debug temporárias e reapontar o webhook — instruções perigosas se
  seguidas hoje por engano.
- **Evidência:** `docs/HANDOFF-EVOLUTION-CUTOVER.md:2-5` e `:86` ("## 3. ⚠️ BLOQUEIO ATUAL — onde paramos"),
  `:119` ("### 4.2 — Função `evolution-debug`"), `:143` ("### 4.3 — Apontar o webhook para o debug (temporário)")
- **Ação recomendada:** marcar como histórico no topo, ou extrair a parte ainda útil (§5 caminhos locais, §6
  comandos de verificação, §8 rollback) para um doc de operação atual.
- **Esforço:** S — **Decisão do Gustavo:** Não.

---

*Etapa 1 concluída. 71 itens verificáveis (`[V-01]`..`[V-71]`) catalogados para a Etapa 3.*
