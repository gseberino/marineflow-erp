# 99 — Sumário Executivo (Etapa 4)

**Auditoria técnica MarineFlow ERP — Fase 1 (READ-ONLY)** · 08/08/2026
Repositório: `Documents/Claude Code/marineflow-erp`, branch `main`, HEAD `14e3fd2`
Escopo auditado: 146.500 linhas de TS/TSX, 243 migrations, 46 Edge Functions em produção, 121 tabelas, 48 `.md`

**59 achados** (`MF-AUD-001` a `MF-AUD-071`, com 12 referências cruzadas entre módulos).

---

## 🔴 P0 — corrigir antes de qualquer outra coisa

### [MF-AUD-053] `whatsapp-webhook` expõe conversas de clientes e apaga registros por GET anônimo

`supabase/functions/whatsapp-webhook/index.ts:81-175` · `verify_jwt: false` · deploy confirmado ACTIVE v46

A função não valida token, assinatura nem origem — e aceita `GET`:

- **`GET ?healthcheck=1`** devolve `phone` e **corpo integral** das últimas 5 mensagens recebidas
  (`:139-149`). Sem autenticação.
- **`GET` sem parâmetro** executa "limpeza de leads fantasmas" e **DELETA** linhas de `whatsapp_leads`
  (`:157-173`), com service role.

A URL é adivinhável (`https://<project-ref>.supabase.co/functions/v1/whatsapp-webhook`) e o `project-ref` está no
bundle público. Os outros webhooks do próprio projeto fazem certo: `pluggy-webhook` valida token e rejeita tudo
se o secret faltar; `fiscal-webhook` valida HMAC; `submit-signature` valida `share_token`.

**Correção:** exigir segredo compartilhado da Evolution + remover (ou proteger) os dois caminhos `GET`.
Esforço S. É a primeira tarefa da Fase 2.

---

## Top 10 achados por severidade

| # | ID | Achado | Sev. | Cat. | Esforço |
|---|---|---|---|---|---|
| 1 | **MF-AUD-053** | Webhook do WhatsApp público: vaza conversas e deleta leads por GET | **P0** | F | S |
| 2 | **MF-AUD-020** | Financeiro (`payments`, `receivables`, `bank_transactions`, `invoices`, `payables`) sem regra de cargo no banco — barreira só no frontend | P1 | F | M |
| 3 | **MF-AUD-050** | 4 funcionalidades sumiram da UI na migração V2: programação de caixa, cobrança em lote, extrato do cliente, widget de tarefas | P1 | B/C | M |
| 4 | **MF-AUD-005** | Dropdown de OS da Agenda filtra 4 status inexistentes e omite `open` — **a hipótese #4 do briefing** | P1 | A | S |
| 5 | **MF-AUD-009** | Alterar itens de OS pelo agente não atualiza recebíveis nem respeita o piso do já pago | P1 | A | M |
| 6 | **MF-AUD-014** | Preferências de PDF de um usuário sobrescrevem a config da empresa a cada download — **explica a hipótese #2** | P1 | A/F | S |
| 7 | **MF-AUD-055** | 10 Edge Functions ACTIVE em produção sem fonte no repositório; uma delas com cron de hora em hora | P1 | J/C | M |
| 8 | **MF-AUD-031/032** | 16 tools do agente com service role sem cargo — incluindo `adjust_inventory`, que grava estoque sem gate nem autoria | P1 | F | M |
| 9 | **MF-AUD-043** | `tsc -b` acusa 16 erros que ninguém vê: não há script de typecheck nem CI | P1 | I | M |
| 10 | **MF-AUD-021/022/058** | Repositório não reconstrói a produção: 35 migrations aplicadas sem arquivo, correções de RLS que só existem no banco, e migrations que — se replayadas — **reabrem `clients` e `vessels` para anônimos** | P1 | J/F | L |

---

## Achados por categoria

| Cat. | Tipo | Qtd. |
|---|---|---:|
| A | Bug funcional | 12 |
| B | Divergência docs × código | 5 |
| C | Código morto / duplicado | 7 |
| D | Inacabado | 3 |
| E | i18n | 6 |
| F | Segurança | 11 |
| G | Performance | 4 |
| H | Inconsistência de padrão | 8 |
| I | Testes / CI | 3 |
| J | Banco de dados | 8 |

*(alguns achados contam em duas categorias)*

## Achados por módulo

| Módulo | Arquivo | Achados | P0/P1 |
|---|---|---:|---:|
| Documentação | `01-inventario-docs.md` | 4 | — |
| OS + Orçamentos | `10-os-orcamentos.md` | 8 | 3 |
| PDFs | `11-pdfs.md` | 7 | 2 |
| Financeiro/Cobranças | `12-financeiro-cobrancas.md` | 2 | 1 |
| Estoque/Compras/Fiscal | `13-estoque-compras-fiscal.md` | 1 | — |
| Cadastros | `14-cadastros.md` | 3 | — |
| Agenda | `15-agenda.md` | 2 | — |
| Settings | `16-settings.md` | 2 | — |
| WhatsApp | `17-whatsapp.md` | 1 | — |
| Edge Functions | `18-edge-functions.md` | 5 | 3 |
| Agente AI | `19-agente-ai.md` | 3 | 2 |
| Auth + RLS | `20-auth-rls.md` | 8 | 3 |
| Banco de dados | `21-banco-de-dados.md` | 3 | 1 |
| i18n | `22-i18n.md` | 3 | — |
| Hooks/Utils/Build | `23-hooks-utils.md` | 7 | 1 |

---

## Quick wins (P2/P3 com esforço S)

Correções de menos de meia hora cada, sem decisão pendente:

| ID | O quê |
|---|---|
| MF-AUD-006/007/008 | Alinhar as três listas de status restantes ao CHECK da tabela (`overview.ts`, `prompt.ts`, `ServiceOrderTimeline.tsx`) |
| MF-AUD-010 | Checar `error` no delete+insert de técnicos da OS |
| MF-AUD-013 | Fazer `fetchPDFData` buscar o levantamento igual ao `usePDFData` |
| MF-AUD-019 | Remover import morto de `usePDFData` em `form-parts.tsx:65` |
| MF-AUD-023 | Replicar o predicado de categoria sensível no UPDATE/DELETE de `payables` |
| MF-AUD-025 | `REVOKE EXECUTE ... FROM anon` nas 3 funções de trigger expostas |
| MF-AUD-026 | Ligar proteção contra senha vazada no painel do Supabase (1 clique) |
| MF-AUD-030 | Acrescentar `address.dontKnowCep` ao `en.ts` + teste de paridade de chaves |
| MF-AUD-042 | `m.phone`/`m.email` em `MarinaList.tsx:154` |
| MF-AUD-045 | `s.email` em `PayableFormDialog.tsx:123` |
| MF-AUD-047 | `"test:edge": "deno test -A supabase/functions"` no `package.json` |
| MF-AUD-054 | Validar `x-cron-secret` nos dois workers de WhatsApp (copiar padrão existente) |
| MF-AUD-067 | Corrigir o JSDoc de `whatsapp/factory.ts` |
| MF-AUD-002/003 | README mínimo; tirar `reports/` do versionamento |

---

## Plano de ataque sugerido — em ondas

### 🌊 Onda 1 — Fechar as portas (P0 + P1 de segurança)
*Objetivo: nada aqui muda comportamento visível ao usuário; tudo reduz exposição.*

1. **MF-AUD-053** — webhook do WhatsApp (P0). Primeiro item, sem exceção.
2. **MF-AUD-054** — `x-cron-secret` nos dois workers.
3. **MF-AUD-025 / MF-AUD-026** — revoke das funções de trigger + senha vazada.
4. **MF-AUD-023** — fechar o bypass de categoria sensível em `payables`.
5. **MF-AUD-031 / MF-AUD-032** — cargo nas 16 tools; `adjust_inventory` vira `risk: high` com autoria.
6. **MF-AUD-020** `[DECISÃO]` — RLS por cargo no financeiro.
7. **MF-AUD-021** — migration de convergência que dropa as duas políticas anônimas do repositório (no-op em
   produção, corretiva em ambiente novo).

### 🌊 Onda 2 — Devolver o que o usuário perdeu + quick wins
*Objetivo: o que ele sente no dia a dia.*

1. **MF-AUD-050** `[DECISÃO]` — repor as 4 funcionalidades na V2 (quais?).
2. **MF-AUD-005** + MF-AUD-006/007/008 — a classe inteira dos status fantasma, com constante única e teste de
   guarda.
3. **MF-AUD-014** `[DECISÃO]` — separar preferência do usuário de padrão da empresa. **Antes disso**, conferir o
   valor de `app_settings.pdf_options_quote` em produção (pode resolver a hipótese #2 na hora).
4. **MF-AUD-009** `[DECISÃO]` — cascata de recebíveis no caminho do agente.
5. **MF-AUD-013** — levantamento no PDF do download em lote.
6. Todos os quick wins da tabela acima.

### 🌊 Onda 3 — Parar de acumular dívida
*Objetivo: impedir que os achados desta auditoria voltem.*

1. **MF-AUD-043** — script `typecheck` + CI (`lint`, `typecheck`, `test`, `test:edge`, `build`) **antes** de
   zerar os 16 erros de tipo.
2. **MF-AUD-058 / MF-AUD-022** `[DECISÃO]` — conciliar `pg_policies`/migrations e commitar a convergência.
3. **MF-AUD-055** `[DECISÃO]` — classificar as 10 funções órfãs: apagar ou versionar (`ai-cost-reconcile` está
   viva e agendada).
4. **MF-AUD-037** `[DECISÃO]` — data de corte para as 19 telas legadas (só depois da Onda 2, que depende delas).
5. **MF-AUD-047 / MF-AUD-057** — testes Deno no CI; religar ou formalizar o deploy.

### 🌊 Onda 4 — Qualidade e limpeza
1. **MF-AUD-028** `[DECISÃO]` — i18n: 1.052 strings, priorizadas por exposição (`PublicServiceOrderView` primeiro).
2. **MF-AUD-011** `[DECISÃO]` — fonte única da fórmula de total da OS.
3. **MF-AUD-048** — code-splitting (bundle de 2,19 MB).
4. **MF-AUD-044** `[DECISÃO]` — módulo de inspeção órfão: concluir ou remover.
5. **MF-AUD-052** — tabelas financeiras com rolagem lateral.
6. **MF-AUD-069** `[DECISÃO]` — decompor `FiscalEmission.tsx`.
7. **MF-AUD-049** `[DECISÃO]` — rigor de tipos gradual.
8. **MF-AUD-059 / MF-AUD-003 / MF-AUD-002 / MF-AUD-041 / MF-AUD-064** — limpeza.

---

## `[DECISÃO]` — itens que exigem sua resposta antes de qualquer ação

| # | Decisão | Por quê importa |
|---|---|---|
| 1 | **MF-AUD-050:** quais das 4 funcionalidades perdidas devem voltar? (programação de caixa, cobrança em lote por WhatsApp, extrato do cliente, widget de tarefas) | Maior impacto imediato no uso diário |
| 2 | **MF-AUD-037:** as 19 telas legadas (7.397 linhas) podem ser apagadas, ou o `?legacy=1` ainda serve? | Define se cada correção da Fase 2 é feita uma ou duas vezes |
| 3 | **MF-AUD-020:** matriz de acesso do financeiro — técnico vê o financeiro da OS dele? vê `payments`? | Define o predicado da RLS |
| 4 | **MF-AUD-014:** preferências de PDF = padrão da empresa (admin) + override local por usuário? | Muda o desenho da correção |
| 5 | **MF-AUD-009 / MF-AUD-011:** a regra de redistribuição de recebíveis e a fórmula única do total podem ser fossilizadas em SQL? | É caminho crítico de dinheiro; exige janela de validação |
| 6 | **MF-AUD-015 / MF-AUD-016:** a validade do orçamento corre da **emissão original** ou de cada reimpressão? E `quote_validity_date` passa a ser gravada, ou some? | Decisão comercial, não técnica |
| 7 | **MF-AUD-055 / MF-AUD-059:** autorizar remoção das funções órfãs (`zapi-configure-webhook`, `evolution-debug`, `scheduling-automations`, as 5 `ai-*` dormentes) e das tabelas de reparo | Alterações destrutivas em produção |
| 8 | **MF-AUD-058 / MF-AUD-022:** autorizar a migration de convergência do RLS | DDL em produção, ainda que idempotente |
| 9 | **MF-AUD-028:** o inglês é requisito real de produto? | Move a linha inteira de i18n entre P1 e P3 |
| 10 | **MF-AUD-044:** a frente de inspeção/vistoria continua no plano, ou o módulo de levantamento a tornou obsoleta? | Concluir (L) vs remover (S) |
| 11 | **MF-AUD-033:** aceitar cortar tools sem uso em troca de custo por conversa? | 188 tools, ~69 mil tokens de prefixo |
| 12 | **MF-AUD-018:** a OS impressa deve mostrar a data agendada? | O campo existe e não é renderizado |

---

## O que está notavelmente bem

Um relatório só de defeitos daria uma impressão falsa deste projeto. Registro o que encontrei de qualidade
acima da média, porque isso muda a estratégia da Fase 2 (há padrões bons para imitar, não só erros para corrigir):

- **Link público da OS** (`20260729144824_rls_anon_fase2_token_amarrado.sql`): políticas anônimas amarradas ao
  cabeçalho `x-share-token`, negando por omissão, com comparação em texto para não virar oráculo, e verificação
  registrada com o papel `anon` real. Trabalho de segurança de primeira linha.
- **`DataTable` da V2**: zero rolagem horizontal *por construção* — ResizeObserver + orçamento de colunas +
  `overflow-hidden`. Resolve a classe do problema, não o sintoma.
- **842 testes, todos verdes**, com libs puras bem separadas (`os-financials`, `quote-deposit`,
  `purchase-needs`, `quote-comparison`, `dre`, `nfe-*`) e teste de **paridade** entre frontend e backend.
- **Arquitetura de tools do agente**: `sb` com RLS por padrão, service role como exceção declarada, `risk` com
  gate de aprovação determinístico, `blockTechnician` como defesa em profundidade. O problema é adesão, não
  desenho.
- **Retry centralizado** em `callClaude` com classificação por status e orçamento de tempo contra o teto da Edge
  Function.
- **Comentários que explicam o porquê**, não o quê. Vários achados desta auditoria foram possíveis porque o
  código documenta suas próprias decisões e invariantes (o comentário da `recalc_so_totals` sobre OS cancelada, a
  nota do `AUTO_DISAMBIG` sobre `list_service_orders`, o cabeçalho da migration `scope_internal_tables_to_staff`
  admitindo que nunca chegou ao banco). Isso é raro e vale preservar.

---

## Critério de conclusão da Fase 1

- [x] Todos os módulos auditados, cada um com arquivo em `audit/` (16 arquivos)
- [x] Todos os `.md` inventariados (48) e cruzados com o código (71 itens `[V-nn]`)
- [x] As 10 hipóteses conhecidas com status verificado (`audit/95-hipoteses-conhecidas.md`)
- [x] Sumário executivo com plano de ondas
- [x] Zero alterações em arquivos de código, configuração ou documentação

### `git status` ao final

```
$ git status --short
?? audit/
?? tsconfig.app.tsbuildinfo
?? tsconfig.node.tsbuildinfo

$ git branch --show-current
main
$ git log -1 --oneline
14e3fd2 merge: cabecalho sticky, autosave e alvos de toque na tela de OS
```

**Declaração honesta do que foi tocado fora de `audit/`:** nenhum arquivo versionado foi criado, alterado,
movido ou removido. Três artefatos **não versionados** foram gerados por comandos de verificação que executei:

- `tsconfig.app.tsbuildinfo` — criado por `npx tsc -b` (o `tsconfig.node.tsbuildinfo` já existia antes da
  sessão, consta do `git status` inicial);
- `dist/` — regenerado por `npm run build` (ignorado pelo git, por isso não aparece acima).

Nenhum dos dois afeta código-fonte; ambos são recriados a cada build. **Não os removi** porque apagar também
seria uma alteração não autorizada — se preferir a árvore exatamente como estava, `rm tsconfig.app.tsbuildinfo`
resolve.

**Banco de dados:** executei apenas `SELECT` (em `pg_policies`, `pg_tables`, `cron.job`,
`supabase_migrations.schema_migrations` e um agregado de `app_users` sem PII) e o *security advisor*. Nenhum DDL,
nenhuma escrita, nenhuma migration aplicada. As consultas foram necessárias porque o repositório **não** descreve
o estado real do RLS — e é exatamente essa diferença que produziu os achados MF-AUD-021, 022, 055 e 058.

---

## Índice dos relatórios

| Arquivo | Conteúdo |
|---|---|
| `00-mapa-do-projeto.md` | Escolha do repositório, stack, volumetria, módulos, superfície de banco |
| `01-inventario-docs.md` | 48 `.md` inventariados, 71 itens verificáveis, 4 achados |
| `10-os-orcamentos.md` | Núcleo OS/orçamento — 8 achados |
| `11-pdfs.md` | Geração de PDFs — 7 achados |
| `12-financeiro-cobrancas.md` | Financeiro, cobranças, bancário — 2 achados |
| `13-estoque-compras-fiscal.md` | Estoque, compras, fiscal — 1 achado |
| `14-cadastros.md` | Clientes/embarcações/marinas/produtos — 3 achados |
| `15-agenda.md` | Agenda, day board, automações — 2 achados |
| `16-settings.md` | Settings / `app_settings` — 2 achados |
| `17-whatsapp.md` | Integração WhatsApp — 1 achado |
| `18-edge-functions.md` | 46 funções em produção — 5 achados (1 P0) |
| `19-agente-ai.md` | Agente AI, 188 tools — 3 achados |
| `20-auth-rls.md` | Auth + RLS, com estado real do banco — 8 achados |
| `21-banco-de-dados.md` | Migrations × schema × uso — 3 achados |
| `22-i18n.md` | i18n — 3 achados |
| `23-hooks-utils.md` | Hooks, utils, build, CI — 7 achados |
| `90-docs-vs-codigo.md` | Matriz dos 71 itens verificáveis |
| `95-hipoteses-conhecidas.md` | Status das 10 hipóteses do briefing |
| `99-sumario-executivo.md` | Este arquivo |
