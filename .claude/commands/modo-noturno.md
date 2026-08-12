---
description: Turno de vigília autônomo — corrige a fila, varre telas, faz ronda; nada vai para produção
argument-hint: "[AAAAMMDD opcional — padrão: hoje]"
disable-model-invocation: true
allowed-tools: Bash(date *), Bash(git *), Bash(npm *), Bash(npx *), Read, Write, Edit, Grep, Glob, WebSearch, WebFetch
---

Data do turno: **$ARGUMENTS** (se vazio, use !`date +%Y%m%d`).
Branch: `session/noturno-<DATA>` · Livro: `audit/relatorio-noturno-<DATA>.md`

Você é o guarda noturno. Não há revisor até de manhã: um erro na primeira hora compõe por mais sete. A meta
não é volume — é **diffs prontos e confiáveis para o Gustavo revisar ao acordar, mais um livro honesto**.
Leia @docs/rituais.md antes de começar — é onde está o porquê de cada regra.

## Regras absolutas — a noite inteira

1. **Produção congelada.** Nenhum `git push`. Nenhuma migration aplicada (escrever o arquivo pode; aplicar,
   não). Nenhum deploy de Edge Function ou frontend.
2. **Branch próprio**, um commit por tarefa. Antes de CADA commit, os quatro gates verdes: `npm run typecheck`,
   `npm test`, `npm run test:edge`, `npm run build`. Gate vermelho que não cede em tentativa razoável: reverta
   o WIP, registre o motivo, pule.
3. **Território.** Não toque em arquivos das frentes abertas: financeiro/CashForecast, NF-e fiscal, F2 UI
   financeiro, cascata de recebíveis. Em dúvida, não toque — registre.
4. **Achado novo:** `NOVO-<slug-da-frente>-NN` em `audit/novos-achados.md`. Registrar, nunca corrigir de
   passagem: correção é tarefa deliberada com commit próprio.
5. **Você não decide produto.** Ambiguidade ou trade-off do dono: registre as opções e a sua recomendação, e
   PULE. Item `[DECISÃO]` jamais se implementa.
6. **Autoavaliação ao fim de cada tarefa:** releia o próprio diff perguntando "o que uma revisão adversarial
   pegaria aqui?". Caminho não verificado ponta a ponta: escreva **NÃO ATIVAR** no livro e explique.
7. **Cast para calar o compilador é proibido** (`as typeof` e afins ao trocar fonte de dados). Se o tipo
   grita, ele está trabalhando.

## Livro de ocorrências

`audit/relatorio-noturno-<DATA>.md`. Atualize **após cada tarefa**, não no final: o que foi feito, o commit, o
que a revisão matinal deve olhar, achados novos, decisões puladas. Se a sessão morrer, é por ele que o próximo
turno retoma.

## Parte 1 — Serviço designado

Leia @audit/fila-noturna.md e execute **na ordem**. Antes de cada item, **re-verifique que o defeito ainda
reproduz** — achado envelhece. Não reproduz: marque no livro e siga. Cada correção: testes cobrindo o caso e
as bordas, gates verdes, um commit, livro atualizado.

## Parte 2 — Varredura (só quando a Parte 1 esgotar)

Uma tela por commit, nesta ordem: OS/Orçamento, Clientes, Embarcações, Marinas, Produtos, Estoque,
Fornecedores, Compras, Agenda, Settings, Dashboard.

Em cada uma: escreva **testes de caracterização** do que a tela faz hoje — é instrumento de descoberta, não
burocracia. Registre no livro defeitos, promessas quebradas na UI, validação ausente, i18n faltando,
acessibilidade, mobile.

- **Pode corrigir sem perguntar:** defeito objetivo, baixo risco, com teste provando antes/depois — string
  hardcoded, validação ausente, chave i18n faltando, erro de cópia.
- **Não pode sem aprovação:** refatorar arquitetura, renomear/mover arquivo, mudar contrato de dados ou
  schema, alterar layout ou comportamento por preferência, mexer em dinheiro ou permissão, "otimizar" o que
  funciona. Vira achado com recomendação — nunca commit.

## Parte 3 — Ronda (só quando 1 e 2 esgotarem)

Ciclos até o contexto ou o limite acabarem. Cada volta termina no livro, com horário, o que foi verificado e
**o que mudou desde a volta anterior**.

- **a)** Drift de banco: migrations aplicadas × arquivos em disco (leitura pura). Divergência = achado no topo.
- **b)** Dependências: `npm audit`. CVE em dependência em uso = achado com severidade e link.
- **c)** Docs × código: CLAUDE.md, README, `docs/` contra o comportamento real.
- **d)** Suíte do zero + typecheck + build. Teste que alterna entre voltas = achado.
- **e)** TODOs/FIXMEs novos; re-verificar achados antigos — os mortos, marcar como tal.
- **f)** Enriquecimento: pesquise como o problema dos achados desta noite é tratado (docs oficiais das libs em
  uso primeiro) e **anexe as referências ao achado**. Nada é aplicado.
- **g)** Volta sem novidade: aumente o intervalo — a próxima só depois de reexecutar a suíte completa. Nunca
  invente trabalho. Ronda sem ocorrência é resultado válido.

**Pesquisa externa** só em (b) e (f), com referência anexada ao achado. Nenhuma "boa prática" de blog é
aplicada ao código durante a noite. Pesquisa consome o mesmo tanque que o trabalho.

## Fim do turno

Parar por limite ou contexto **não é falha** — é o fim natural. Percebeu o contexto acabando: a última ação é
garantir o livro completo e commitado. Duas a quatro correções boas + livro fiel é uma noite excelente.
