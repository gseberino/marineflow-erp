# Relatório noturno — 10/08/2026

**Branch:** `session/noturno` · **Worktree:** `marineflow-erp--noturno` · **Base:** `0a4cc64` (main)

Regras desta noite (dadas pelo Gustavo): nenhum `git push`, nenhuma migration aplicada, nenhum deploy de
Edge Function. Produção não muda. Um commit por tarefa, gates locais verdes antes de cada commit. Nada de
CashForecastPanel/financeiro — aquela frente roda em outra sessão. Dúvida ou decisão de produto: registrar
aqui e pular, nunca decidir.

**Este arquivo é o estado.** Se a sessão morrer, é por ele que se retoma.

---

## Fila e situação

| # | Tarefa | Situação |
|---|---|---|
| 0 | Mover o lint do `ci.yml` para workflow próprio | ✅ concluída |
| 1 | T3.2 — preferências de PDF (decisão #4) | ⏳ pendente |
| 2 | NOVO-006b — PDF de execução sem bloco financeiro | ⏳ pendente |
| 3 | T3.8 — paridade i18n pt-BR × en (MF-AUD-030) | ⏳ pendente |
| 4 | NOVO-006a — view de `service_orders` sem valores | ⏳ pendente |
| 5 | Fila infinita — cobertura de teste em módulos categoria I | ⏳ pendente |

---

## 0 — Lint fora do CI (concluída)

**Commit:** `ci: separa o lint do CI em workflow proprio (MF-AUD-043)`

O job `lint` saiu de `.github/workflows/ci.yml` e virou `.github/workflows/lint.yml`, com os mesmos
gatilhos (push na `main`, pull_request, disparo manual), `concurrency` própria (`lint-<ref>`) e o mesmo
`continue-on-error: true`. Nenhum comportamento de execução mudou: o lint continua rodando, continua
reportando os 2.455 erros herdados e continua sem bloquear ninguém.

**O que muda é a leitura:** a run "CI" passa a conter só gates bloqueantes, então CI verde quer dizer
exatamente "typecheck, testes de frontend, testes de Edge Function e build passaram" — sem um job vermelho
ao lado que o leitor precisa aprender a ignorar. O estado do lint continua visível, na run "Lint".

**Gates:** typecheck 0 · vitest 904 · deno 267 · build OK. YAML dos dois workflows conferido por parser
(`ci.yml` → job `gates`; `lint.yml` → job `lint`).

**Para a revisão matinal:** nada verificável localmente aqui — só o GitHub diz se o workflow novo aparece.
Depois do push, conferir em Actions que passaram a existir **duas** runs por push (CI e Lint) e que a de CI
fica verde. Se a organização tiver required checks configurados apontando para o job `lint` dentro do
workflow CI, esse nome de check mudou e precisa ser reapontado — não encontrei configuração dessas no
repositório, mas ela vive no GitHub, não em arquivo.
