---
description: Retrato read-only do estado da frente — git, fila, gates, banco, deploys e o que espera decisão
argument-hint: "[baseline opcional — commit ou branch; padrão: main]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(npm *), Bash(npx *), Read, Write, Grep, Glob
---

Baseline: **$ARGUMENTS** (se vazio, use `main`).

Produza um retrato honesto do estado desta frente. **A única escrita permitida é o próprio relatório** — nenhum
arquivo de código, nenhuma migration, nenhum deploy, nenhum push. Se durante o levantamento você encontrar um
defeito, ele vira linha no relatório, não commit.

Salve em `audit/status-<frente>-<AAAAMMDD>.md` e siga este template. Cada seção é obrigatória; seção sem
conteúdo escreve "nada" em vez de sumir.

## 1. Resumo

Três a cinco linhas: o que esta frente se propôs, onde parou, e a única coisa que o leitor precisa saber se
ler só isto.

## 2. Git bruto desde o baseline

Saída real, não parafraseada: `git log --oneline <baseline>..HEAD`, `git diff --stat <baseline>..HEAD`, e
`git status --short`. Se houver trabalho não commitado, diga em voz alta — é o que se perde primeiro.

## 3. Commit → achado

Tabela: commit · achado atendido (`MF-AUD-0XX` / `NOVO-<slug>-NN`) · como foi verificado. Commit sem achado
correspondente aparece com "—" e uma linha dizendo por que existe.

## 4. Status da fila

Cada item de `audit/fila-noturna.md` (ou da fila da frente): concluído, em curso, pulado ou não reproduz —
com o motivo. Item pulado sem motivo escrito é item perdido.

## 5. Gates, executados agora

Rode os quatro **neste momento** e cole o número obtido: `npm run typecheck` · `npm test` ·
`npm run test:edge` · `npm run build`. Não reaproveite número de relatório anterior. Se algum falhar, o
relatório diz qual e por quê — não se conserta durante um checkpoint.

## 6. Banco e deploys

Migrations aplicadas × arquivos em disco (leitura pura: `list_migrations` contra `supabase/migrations/`).
Divergência é a primeira coisa da seção. Deploys de Edge Function e do frontend: o que está no ar e de qual
commit.

## 7. Decisões tomadas sem o Gustavo

Toda escolha de comportamento feita durante a frente, com a alternativa que foi descartada e por quê. Se não
houve, escreva "nenhuma" — mas releia os diffs antes de afirmar isso.

## 8. Achados novos

Os registrados nesta frente, com ID e uma linha cada. Diga explicitamente quais **não** foram corrigidos.

## 9. A pergunta pendente

**Uma** pergunta — a que mais destrava a frente se respondida. Com as opções e a sua recomendação. Se houver
mais de uma, escolha a que bloqueia o resto e liste as outras abaixo dela.
