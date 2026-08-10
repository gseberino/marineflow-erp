# CHECKPOINT — Status da Fase 2

**Data:** 09/08/2026 · **Baseline:** `14e3fd2` · **HEAD no início do checkpoint:** `d6edee9`
Sessão de checkpoint: **somente leitura**. Nenhum código foi alterado, commitado ou deployado aqui.

> ⚠️ **O HEAD mudou durante a escrita deste relatório.** Ao coletar os dados, `main` estava em `d6edee9`;
> ao gravar o arquivo, estava em **`31111a6`**. Dois commits de outra sessão entraram no intervalo:
> ```
> 31111a6 merge: impressao sem erro + paginacao medida no PDF baixado
> e957937 fix(pdf): erro ao imprimir e bloco cortado na quebra de pagina
> ```
> Nenhum deles é desta frente e nenhum toca os arquivos das tarefas concluídas. **Todos os números,
> gates e listagens deste relatório referem-se a `d6edee9`** — o retrato é fiel a esse ponto, não ao HEAD
> de agora. Isso não é um detalhe: mostra que o repositório recebe integrações de outras sessões em
> intervalos de minutos, e qualquer checkpoint aqui é uma fotografia com data e hora, não um estado estável.

---

## 1. Resumo executivo

Desde `14e3fd2` a `main` avançou **27 commits**, dos quais **apenas 4 são desta frente da Fase 2** — os
outros 23 são de sessões paralelas (financeiro, PDF, custo de IA, dimensionamento, fiscal). Da fila, **duas
tarefas foram concluídas e verificadas em produção**: T0.1 (MF-AUD-053, webhook exposto) e T1.1 (MF-AUD-054,
que na execução virou **três** funções, não duas). T0.2 foi executada agora, neste checkpoint, e **derrubou a
hipótese**: `showTerms` está `true` nos dois tipos de PDF, então a preferência global **não** explica o sintoma
dos termos que não renderizam — a causa segue desconhecida. Os gates estão como no baseline: `tsc -b` com **16
erros** (nenhum corrigido, nenhum novo), Vitest **875 verdes**, Deno **252 verdes**, build OK, lint com **2.455
erros** (nunca foi verde). Preocupa: uma migration foi aplicada hoje em produção **sem arquivo no repositório**,
repetindo o MF-AUD-058. Dependem do Gustavo: as 4 decisões da T0.3 e o clique da T1.3.

---

## 2. Git — estado bruto

### `git branch --show-current`
```
main
```
(worktree desta frente: `session/p0-webhook`, em `Documents/Claude Code/marineflow-erp--p0-webhook`, árvore limpa)

### `git log --oneline 14e3fd2..HEAD` — completo, 27 commits
```
d6edee9 merge: CSS do PDF escopado (fim da distorcao) + quebra de pagina
14f4af6 fix(pdf): a "gambiarra" que distorcia a tela, e a quebra de pagina que faltava
602f3aa merge: reorganização do financeiro — Extrato tria, Conciliação confere (F1+F2)
28445fd fix(whatsapp): MF-AUD-054 exigir x-cron-secret nos workers expostos
8b88b1d fix(financeiro): entrada não herda classificação feita de despesa
74b4320 feat(financeiro): Extrato tria, Conciliação confere — a inversão desfeita
b14d99e feat(financeiro): Extrato e Conciliação viram duas perguntas — modelos de leitura
c8acdf5 feat(financeiro): a situação real de cada linha do extrato — F1 do plano
b7a246f merge: fix critico React #310 — tela de orcamento voltou a abrir
a4004da fix(os): React #310 — a tela de orcamento nao abria, e a culpa e minha
b89bd8c feat(financeiro): compra no cartão mostra o que ELA tem — ramo, categoria e cartão
671b598 chore(audit): registra NOVO-002 (eventos da Evolution sem consumidor + base64)
8be2bef chore(audit): registra NOVO-001 (deno check quebra por node_modules do frontend)
566e43c fix(whatsapp): MF-AUD-053 exigir segredo no webhook e parar de expor conversas
bd52877 merge: ampacidade preenchida (ABYC) e fatores de correcao corrigidos
8ae9303 feat(dimensionamento): ampacidade preenchida — e o caso real sobe de 62 para 70 mm2
ae6e1bd feat(financeiro): MCC ganha os códigos REAIS do extrato, medidos e não supostos
b87987a merge: suite verde (teste fiscal alinhado ao codigo) + 7 perguntas dos buracos medidos
360203b fix(fiscal): teste ficou para tras do codigo; e as perguntas dos buracos medidos
440f19e Merge branch 'session/otimizacao-tokens'
3331e6a feat(ia): Fase 1 — um caminho so para montar orcamento, e o codigo cobrando a regra
5f70d95 fix(banking): dois defeitos que so a verificacao final revelou
7697a9e Merge branch 'main' into session/otimizacao-tokens
5e020c3 revert(ia): TTL de 1h no cache sai mais caro que o de 5min
385de3f fix(ia): precos reais do OpenRouter — Bedrock, promocional, gravacao e adicional
3047c36 feat(ia): custo real do OpenRouter em vez de estimativa por tabela
1c0dde4 perf(ia): custo de token visivel e cache de 1h — Fases 0 e 3
```

> **Todos os 27 commits têm o mesmo autor git (`gseberino`)** — a autoria do git não distingue sessões. A
> separação abaixo (minha × de outras sessões) é feita pelo conteúdo e pela mensagem, não pelo autor.

### `git status --short`
```
?? audit/00-mapa-do-projeto.md
?? audit/01-inventario-docs.md
?? audit/10-os-orcamentos.md
?? audit/11-pdfs.md
?? audit/12-financeiro-cobrancas.md
?? audit/13-estoque-compras-fiscal.md
?? audit/14-cadastros.md
?? audit/15-agenda.md
?? audit/16-settings.md
?? audit/17-whatsapp.md
?? audit/18-edge-functions.md
?? audit/19-agente-ai.md
?? audit/20-auth-rls.md
?? audit/21-banco-de-dados.md
?? audit/22-i18n.md
?? audit/23-hooks-utils.md
?? audit/90-docs-vs-codigo.md
?? audit/95-hipoteses-conhecidas.md
?? audit/99-sumario-executivo.md
?? tsconfig.app.tsbuildinfo
?? tsconfig.node.tsbuildinfo
```
Nada modificado, nada em staging. Os 19 arquivos são **os relatórios da Fase 1, que nunca foram commitados**
— `git ls-files audit/` devolve só `audit/novos-achados.md`. Os dois `.tsbuildinfo` são artefatos de
`tsc -b` (um pré-existia ao baseline; o outro foi gerado pela auditoria e está declarado no
`99-sumario-executivo.md`).

### Houve push?
**Eu não executei nenhum `git push`.** Mas os commits **foram publicados** por outra sessão:
```
$ git rev-parse HEAD origin/main
d6edee90d3979f1f59057bb808c8e4d6212936ae
d6edee90d3979f1f59057bb808c8e4d6212936ae
$ git rev-list --left-right --count origin/main...HEAD
0	0
```
E os quatro commits desta frente estão contidos em `origin/main`:
```
566e43c -> SIM (publicado)
8be2bef -> SIM (publicado)
671b598 -> SIM (publicado)
28445fd -> SIM (publicado)
```
Remote/branch: `origin/main`.

---

## 3. Mapeamento commit → achado

| hash | mensagem (resumo) | MF-AUD atendido | fila |
|---|---|---|---|
| `566e43c` | webhook: exigir segredo, parar de expor conversas | **MF-AUD-053** | **T0.1 — dentro** |
| `8be2bef` | registra NOVO-001 | — (registro, regra 5) | dentro (subproduto de T0.1) |
| `671b598` | registra NOVO-002 | — (registro, regra 5) | dentro (subproduto de T0.1) |
| `28445fd` | workers: exigir `x-cron-secret` | **MF-AUD-054** | **T1.1 — dentro** |
| `1c0dde4` `3047c36` `385de3f` `5e020c3` `3331e6a` `5f70d95` `7697a9e` `440f19e` | custo de token visível, preço real do OpenRouter, TTL revertido, caminho único de orçamento | nenhum | **FORA DA FILA** — frente de otimização de tokens/custo de IA, sessão paralela |
| `360203b` `b87987a` | teste fiscal alinhado ao código + perguntas dos buracos | nenhum | **FORA DA FILA** — frente fiscal/levantamento, sessão paralela |
| `ae6e1bd` `8ae9303` `bd52877` | MCC com códigos reais; ampacidade ABYC | nenhum | **FORA DA FILA** — frentes financeiro e dimensionamento de cabo |
| `a4004da` `b7a246f` | React #310: tela de orçamento não abria | nenhum | **FORA DA FILA** — correção crítica de produção, sessão paralela |
| `b89bd8c` `c8acdf5` `b14d99e` `74b4320` `8b88b1d` `602f3aa` | reorganização do financeiro (Extrato tria / Conciliação confere) | nenhum | **FORA DA FILA** — frente de conciliação, sessão paralela |
| `14f4af6` `d6edee9` | CSS do PDF escopado + quebra de página | nenhum | **FORA DA FILA** — frente de PDF, sessão paralela |

**Resumo:** 4 commits desta frente (2 de correção, 2 de registro); **23 commits de outras sessões**, nenhum
deles endereçando achado da auditoria. Não há commit meu fora da fila.

---

## 4. Status da fila

| Tarefa | Status | Commit | Observação |
|---|---|---|---|
| **T0.1** (053) | **Feita** | `566e43c` | Deployada e verificada — evidência abaixo |
| **T0.2** (verificação 014) | **Feita neste checkpoint** | — | Resultado **contraria** a hipótese — ver abaixo |
| **T0.3** (decisões) | **Não iniciada** | — | 4 decisões pendentes do Gustavo |
| **T1.1** (054) | **Feita diferente do especificado** | `28445fd` | Especificava 2 funções; foram **3** — ver abaixo |
| **T1.2** (025) | **Não iniciada** | — | Próxima da fila; DDL em produção, aguarda seu aval |
| **T1.3** (026) | **Não iniciada** | — | Ação manual sua no painel (1 clique) |
| **T1.4** (023) | Não iniciada | — | |
| **T1.5** (031+032) | Não iniciada | — | |
| **T1.6** (021) | Não iniciada | — | |
| **T1.7** (020) | Não iniciada | — | Bloqueada pela decisão #3 |
| **T1.8** (055a) | Não iniciada | — | Ver nota sobre `ai-cost-reconcile` na seção 8 |
| **T2.1** (043) | **Não iniciada** | — | `tsc -b` segue com 16 erros; não há script `typecheck` nem CI |
| **T2.2** (047) | **Não iniciada** | — | Não existe script `test:edge` no `package.json` |
| **T3.1**–**T3.9** | Não iniciadas | — | Bloco 3 depende das decisões #1, #2, #4 |

### T0.1 — detalhamento exigido

**Commitado?** Sim, `566e43c`. **Deployado?** Sim. **Versão ACTIVE atual do `whatsapp-webhook`: 48**
(era 46 no baseline da auditoria; há um 47 intermediário do mesmo deploy).

Testes contra produção, colados da sessão de execução:
```
=== 1. GET anonimo no healthcheck (esperado 401) ===
{"error":"unauthorized"}
HTTP 401
=== 2. GET anonimo sem parametro (esperado 401, nao apaga lead) ===
{"error":"unauthorized"}
HTTP 401
=== 3. POST anonimo (esperado 401) ===
{"error":"unauthorized"}
HTTP 401
```
```
=== 4. healthcheck COM token (esperado 200, sem telefone nem corpo) ===
{"webhook_url":"...","health_status":"ok","total_inbound":2743,"last_24h":41,
 "last_message_at":"2026-08-09T14:05:53.221653+00:00","minutes_since_last":2,
 "recent_messages":[{"at":"2026-08-09T14:05:53.221653+00:00","type":"text"},
                    {"at":"2026-08-09T13:57:10.138609+00:00","type":"video"}, ...],
 "checked_at":"2026-08-09T14:08:06.926Z"}
HTTP 200
```
Sem `phone`, sem `body` — o vazamento morreu. O caminho GET que **deletava** `whatsapp_leads` foi removido do
código (não apenas protegido); hoje devolve `405`.

Fluxo legítimo preservado, dos logs da Edge Function (versão 48):
```
POST | 200 | .../whatsapp-webhook?token=e411…  version 48   ← Evolution
POST | 401 | .../whatsapp-webhook              version 48   ← anônimo
POST | 200 | .../whatsapp-webhook              version 47   ← a versão ANTIGA aceitava sem token
```

### T0.2 — detalhamento exigido

**A consulta foi executada agora, neste checkpoint** (leitura pura), não durante a Fase 2.

```sql
select key, value from app_settings where key like 'pdf_options_%';
```
```
pdf_options_quote         → {"showServicePrices":true, ..., "showTerms":true, ...}
pdf_options_service_order → {"showServicePrices":true, ..., "showTerms":true, ...}
```

**`showTerms` está `true` nos dois.** Portanto:
- **Nenhum dado foi corrigido** (não havia o que corrigir).
- **A hipótese #2 do briefing continua sem causa identificada.** A explicação mais provável do relatório
  (`MF-AUD-014`: alguém desmarcou "Termos" e a preferência global propagou) **está refutada por este dado**.
  O mecanismo perigoso descrito em MF-AUD-014 continua real e vale corrigir — mas ele **não** é a causa do
  sintoma relatado.
- O que sobra para investigar, se o sintoma persistir: se as cinco chaves `terms_*` em `app_settings` têm
  conteúdo (a concatenação em `use-pdf.ts:219-225` cai para `undefined` se todas forem vazias), e por qual
  caminho o PDF foi gerado quando o problema foi visto.

### T1.1 — por que "feita diferente do especificado"

A tarefa dizia "os dois workers". Na execução, ao conferir uma a uma, **`whatsapp-process-scheduled` também
não validava nada** — só declarava `x-cron-secret` no CORS, o que não valida. Ela roda a cada 30 s e dispara
envios agendados. Incluí as três no mesmo commit, por ser a mesma causa raiz e a mesma correção.
Ela escapou da auditoria original por um falso negativo de grep (a palavra "token" aparecia no arquivo por
outro motivo) — isso é uma falha do meu método na Fase 1, registrada aqui.

Verificação em produção (versões novas):
```
whatsapp-queue-worker:         anonimo -> HTTP 401     (v42 → v43)
whatsapp-status-worker:        anonimo -> HTTP 401     (v35 → v36)
whatsapp-process-scheduled:    anonimo -> HTTP 401     (v34 → v35)
```
```
POST | 200 | .../whatsapp-queue-worker       version 43   ← cron legítimo
POST | 401 | .../whatsapp-queue-worker       version 43   ← anônimo
POST | 200 | .../whatsapp-status-worker      version 36
POST | 401 | .../whatsapp-status-worker      version 36
POST | 200 | .../whatsapp-process-scheduled  version 35
POST | 401 | .../whatsapp-process-scheduled  version 35
```
E as respostas que o `pg_net` recebeu nos 5 min seguintes: **24 respostas, todas 200, nenhum 401.**

---

## 5. Gates de qualidade — executados neste checkpoint

| Gate | Comando | Resultado |
|---|---|---|
| Typecheck | `npx tsc -b` | ❌ **16 erros** |
| Testes (front) | `npx vitest run` | ✅ **875 passando** (0 falhas) |
| Testes (edge) | `npx deno test --allow-all --no-check supabase/functions/` | ✅ **252 passando** (0 falhas) |
| Build | `npm run build` | ✅ **built in 21.12s** (com aviso de chunk > 500 kB) |
| Lint | `npx eslint .` | ❌ **2.490 problemas (2.455 erros, 35 warnings)** |

**Typecheck — os 16 erros são exatamente os mesmos do baseline** (nenhum corrigido, nenhum introduzido):
```
6× src/components/inspection/ServiceOrderInspectionTab.tsx  TS2307 (módulos inexistentes)
4× src/pages/MarinaList.tsx                                 TS2551/TS2339 (contact_phone/contact_email)
2× supabase/functions/_shared/ai/tools/finance-rules.ts     TS2304 (Cannot find name 'Deno')
1× src/components/PayableFormDialog.tsx                     TS2339 (contact_email)
1× src/hooks/use-service-orders.ts                          TS2345
1× src/lib/pdf-generator.test.ts                            TS2740
1× src/lib/zip.ts                                           TS2322
```

**Scripts ausentes** (confirmando T2.1/T2.2 não iniciadas) — `package.json:6-14`:
```json
"scripts": { "dev", "build", "build:dev", "lint", "preview", "test", "test:watch" }
```
Não há `typecheck` nem `test:edge`. O `deno test` só roda com `--no-check` (ver NOVO-001).

**Lint nunca esteve verde** — 2.455 erros é o estado herdado, não uma regressão desta frente. Não foi
verificado no baseline da Fase 1, então **não posso afirmar** se o número subiu ou desceu.

---

## 6. Banco e deploys

### Migrations
**Esta frente não criou nenhuma migration.** As 9 novas no repositório desde o baseline são de sessões
paralelas, e todas aparecem aplicadas em produção (nomes conferem; os timestamps de aplicação diferem dos
nomes de arquivo, padrão do projeto):

| Arquivo no repo | Aplicada como |
|---|---|
| `20260808130000_custo_de_ia_visivel.sql` | `20260808205657 custo_de_ia_visivel` |
| `20260808140000_custo_real_do_openrouter.sql` | `20260808212111 custo_real_do_openrouter` |
| `20260808150000_cron_reconciliacao_de_custo.sql` | `20260808212120 cron_reconciliacao_de_custo` |
| `20260808160000_precos_reais_bedrock_openrouter.sql` | `20260808212705 precos_reais_bedrock_openrouter` |
| `20260808170000_reverter_ttl_1h.sql` | `20260808214128 reverter_ttl_1h_gravacao_volta_a_25pct` |
| `20260809100000_perguntas_dos_buracos.sql` | `20260809100000` (igual) |
| `20260809110000_ampacidade_e_fatores_reais.sql` | `20260809110000` (igual) |
| `20260809120000_situacao_da_transacao_do_extrato.sql` | `20260809215337 situacao_da_transacao_do_extrato` |
| `20260809130000_extrato_e_conciliacao_sao_duas_perguntas.sql` | `20260809215732 extrato_e_conciliacao_sao_duas_perguntas` |

⚠️ **`20260809140033 corrige_categorias_que_o_mcc_desmente` está aplicada em produção e não tem arquivo em
lugar nenhum** — nem no repo canônico, nem em nenhum dos worktrees (`find` por nome retornou vazio). Ver §8.

### Edge Functions deployadas por esta frente

| Função | Antes → Depois | Tarefa |
|---|---|---|
| `whatsapp-webhook` | v46 → **v48** | T0.1 |
| `whatsapp-queue-worker` | v42 → **v43** | T1.1 |
| `whatsapp-status-worker` | v35 → **v36** | T1.1 |
| `whatsapp-process-scheduled` | v34 → **v35** | T1.1 |

Outras sessões deployaram `ai-agent` (v158→v160), `banking-sync`, `finance-review` e outras — fora do escopo
desta frente.

### Escritas em dados de produção (além de migrations)

**Uma, autorizada explicitamente por você:**
- **Secret `EVOLUTION_WEBHOOK_TOKEN` criado** no projeto `okurngvcodmljjicopdp`
  (`npx supabase secrets set`), com valor aleatório de 32 bytes gerado na hora. Era pré-requisito da T0.1;
  você aprovou a opção "Sequência sem downtime", que incluía este passo.
- Nenhuma outra escrita. Todas as demais interações com o banco foram `SELECT` (em `pg_policies`, `pg_tables`,
  `cron.job`, `net._http_response`, `supabase_migrations.schema_migrations`, `app_settings`,
  `whatsapp_messages` agregado) mais o *security advisor*.

**Configuração fora do banco alterada por você (não por mim):** a URL e os eventos do webhook no Evolution
Manager, e o desligamento do `Webhook Base64`.

---

## 7. Decisões tomadas sem o Gustavo

**Nenhuma decisão pendente (`[DECISÃO]` #1–#12 do sumário executivo) foi implementada.** As duas tarefas
concluídas (T0.1 e T1.1) estavam marcadas como "Decisão do Gustavo: Não" no relatório de auditoria.

Três escolhas de desenho foram feitas dentro do escopo autorizado, e registro para você poder discordar:

1. **Healthcheck mantido, porém sanitizado** (em vez de removido). A T0.1 permitia "remover **ou** proteger".
   Escolhi manter a rota — ela responde "o webhook está recebendo?", que é útil — mas tirei telefone e corpo
   da resposta **e da query**, para que nem com o token correto ela sirva de leitor de conversas.
   Onde: `supabase/functions/whatsapp-webhook/index.ts:156-200`.
2. **Faxina de leads removida, não protegida.** Um `DELETE` disparado por `GET` não é rota de webhook.
   Onde: `whatsapp-webhook/index.ts:201-207` (hoje devolve `405` com dica).
3. **Fail-closed no helper de cron**, divergindo do padrão fail-open de `task-automations:401`
   (`if (cronSecret && ...)` — se o env var sumir, a proteção some em silêncio). Documentei a divergência no
   próprio helper: `supabase/functions/_shared/cron-auth.ts:14-18`.

---

## 8. Novos achados e pendências

### `audit/novos-achados.md` (commitado, `8be2bef` e `671b598`)

- **NOVO-001** — `deno check`/`deno test` sem `--no-check` falha em qualquer função que importe supabase-js
  (`Could not find "@types/node"`, por causa do `node_modules/` do frontend na raiz). **Impacta a T2.2**: pôr
  `deno test` no CI exige `--no-check` ou um `deno.json` próprio em `supabase/functions/`.
- **NOVO-002** — os ~18 eventos ligados no Evolution Manager não têm consumidor no código (caem em
  `parseIncomingWebhook` → `ignored`), e `Webhook Base64` embutia mídia num payload que a função não lê.
  **Parcialmente resolvido:** você desligou o Base64. Os eventos sem consumidor continuam ligados.
  Oportunidade real registrada: `CONTACTS_UPSERT/UPDATE` alimentaria a identidade de contatos;
  `CONNECTION_UPDATE` permitiria avisar quando a instância cai.

### Achado novo deste checkpoint

- **NOVO-003 (não corrigido)** — a migration **`20260809140033 corrige_categorias_que_o_mcc_desmente`** está
  aplicada em produção **hoje** e não existe como arquivo em nenhum lugar do disco. É uma repetição em tempo
  real do **MF-AUD-058**: o repositório não reconstrói a produção. Como o nome sugere correção de dados
  (categorias), vale saber o que ela alterou antes que se perca.
- **Observação de higiene:** os **19 relatórios da Fase 1 continuam não versionados** (`git ls-files audit/`
  devolve apenas `novos-achados.md`). Se a pasta for perdida, a auditoria inteira se perde. Não commitei
  porque a Fase 1 proibia alterar qualquer coisa fora de `audit/` e a Fase 2 não pediu.

### O que está pela metade

Nada de código. As duas tarefas executadas estão completas, deployadas e verificadas. O worktree
`marineflow-erp--p0-webhook` está com árvore limpa e o branch `session/p0-webhook` integrado na `main`
(pode ser removido com `git worktree remove` quando você quiser).

### Riscos que pedem sua atenção

1. **Migration órfã de hoje** (NOVO-003) — o drift está acontecendo agora, não é história.
2. **Sem CI e sem typecheck** (T2.1/T2.2 não iniciadas): os 16 erros de tipo continuam invisíveis, e nada
   impede que voltem os defeitos corrigidos. A fila coloca isso antes do Bloco 3, e concordo.
3. **A causa da hipótese #2 (termos no PDF) segue desconhecida** — a explicação mais provável foi refutada
   pela T0.2.

---

## 9. Pergunta pendente

Sim. Ao encerrar a T1.1, deixei esta pergunta, e ela **não foi respondida**:

> Pela fila, **T1.2** (MF-AUD-025): `REVOKE EXECUTE ... FROM anon` nas três funções de trigger expostas como
> RPC (`trg_sync_fiscal_note_items`, `valida_categoria_de_despesa`, `valida_recebivel_coerente`). É migration
> pequena, sem risco de downtime — mas envolve **DDL em produção**, então confirmo com você antes de aplicar.

Contexto mínimo para decidir: são funções de **gatilho** expostas por engano na API REST. Chamá-las
diretamente por HTTP quase certamente falha (`can only be called as trigger`), então o risco atual é baixo;
o problema é de superfície e de higiene. A correção é uma migration de três linhas, reversível.
A migration `20260729120000_revoke_anon_execute_security_definer.sql` já fez exatamente isso para outras
funções — estas escaparam por terem sido criadas depois.

Além dela, seguem pendentes de você: **T1.3** (ligar a proteção contra senha vazada no painel do Supabase,
1 clique) e as **4 decisões da T0.3**, que travam todo o Bloco 3.

---

## Critério de conclusão

- [x] Relatório gravado em `audit/status-fase2-2026-08-09.md`
- [x] `git status --short` ao final, provando que nada além do relatório foi criado ou alterado — ver abaixo
