---
description: As regras absolutas do turno sem supervisão, em versão curta — para colar em qualquer frente autônoma
disable-model-invocation: true
---

Você está trabalhando **sem revisor**. Vale até ordem contrária:

1. **Produção congelada.** Nenhum `git push`. Nenhuma migration aplicada — escrever o arquivo pode, aplicar
   não. Nenhum deploy de Edge Function ou frontend.
2. **Branch próprio, um commit por tarefa.** Antes de cada commit, quatro gates verdes: `npm run typecheck`,
   `npm test`, `npm run test:edge`, `npm run build`. Gate vermelho que não cede: reverta o WIP, registre o
   motivo, pule. Nunca empurre qualidade caindo.
3. **Território.** Não toque em arquivo de outra frente aberta. Em dúvida, não toque — registre.
4. **Achado novo:** `NOVO-<slug-da-frente>-NN` em `audit/novos-achados.md`. Registrar, **não** corrigir de
   passagem.
5. **Você não decide produto.** Ambiguidade ou trade-off do dono: registre as opções e a sua recomendação, e
   pule. Item `[DECISÃO]` jamais se implementa.
6. **Autoavaliação por tarefa:** releia o próprio diff perguntando "o que uma revisão adversarial pegaria?".
   Caminho não verificado ponta a ponta: escreva **NÃO ATIVAR** e explique. Dizer "pronto" sobre o não
   verificado é o erro mais caro que já cometemos aqui.
7. **Cast para calar o compilador é proibido** (`as typeof` e afins ao trocar fonte de dados).
8. **O livro é o estado.** Atualize o relatório da frente **após cada tarefa**, não no final: o que foi feito,
   o commit, o que a revisão deve olhar, achados, decisões puladas. Sessão que morre com livro em dia não
   perdeu nada.

Parar por limite de uso ou contexto **não é falha** — é o fim natural do turno. A última ação, sempre: livro
completo e commitado.
