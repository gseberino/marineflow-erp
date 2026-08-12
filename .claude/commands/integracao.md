---
description: Ritual diurno de levar um branch à main — revisão adversarial, OK diff a diff, ff-only, push, CI, deploy
argument-hint: "[branch a integrar]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(npm *), Bash(npx *), Read, Write, Edit, Grep, Glob
---

Branch a integrar: **$ARGUMENTS**.

Este é o único ritual autorizado a alcançar produção, e é por ele existir que o turno noturno pode trabalhar
em paz. O porquê de cada etapa está em @docs/rituais.md — leia se alguma parecer cerimônia. Execute na
ordem; **não pule etapa para ganhar tempo**.

## 1. Levantar o terreno antes de qualquer coisa

`git fetch`, e responda por escrito: a `main` avançou desde que o branch nasceu? O ff-only ainda é possível?
Que outros branches remotos existem e o que colide com este? Há colisão de IDs de achado entre eles?
**A main avança durante a conversa** — reconfira antes do merge, não só no começo.

## 2. Apresentar o livro do branch

Leia o relatório/livro da frente e apresente ao Gustavo: o que foi feito, gates, achados registrados, decisões
que ficaram pendentes. Ele revisa o **resumo** aqui — os diffs vêm na etapa 4.

## 3. Revisão adversarial — antes de mostrar os diffs

Um revisor independente **por tarefa**, cada achado passando por **refutação** antes de virar reporte. O
revisor procura defeito, não descrição: caminho não verificado, vazamento, perda de dado, teste tautológico,
comentário que afirma o que o código não faz.

Você é o autor do que está sendo revisado — **presuma viés próprio**. Se um revisor contrariar o que você
escreveu no livro, confira no código antes de defender. Foi assim que se pegou a entrega que apagaria doze
campos financeiros a cada Salvar.

Achado confirmado que bloqueia: **diga isso ao Gustavo antes de ele aprovar**, com a sua recomendação.

## 4. Diff a diff, aguardando OK

Apresente tarefa por tarefa com diff resumido e **espere a resposta**. Nada entra sem OK explícito.

Rejeição **vira retrabalho registrado, nunca descarte**: o material vai para `audit/retrabalho/` com o
código preservado e uma spec do que a próxima tentativa precisa entregar. O commit sai do branch por rebase;
o conflito no livro é seu para resolver.

## 5. Migrations aprovadas — ANTES do push que as usa

Ordem que não se inverte: aplicar a migration → **regenerar `src/integrations/supabase/types.ts`** → só então
o push do código que depende dela. Push primeiro deixa uma janela em que o frontend publicado consulta o que
não existe.

Migration não aprovada não é aplicada. Nenhuma exceção.

## 6. ff-only, gates, push único

Rebase sobre a `main` atual se preciso, rode os quatro gates **na main já integrada** (não confie no número do
branch), e faça `git merge --ff-only`. Um push só, no fim.

## 7. Confirmar o que o push causou

Não termine sem: **CI verde** nas duas runs (CI e Lint) e **deployment do Vercel** com o commit certo em
`READY` e `target: production`. Deploy que não saiu, ou saiu de outro commit, é parte do relatório final.

## 8. Relatório final

O que entrou, o que foi rejeitado e onde foi parar, o que o banco recebeu, o estado das outras frentes, e o
que continua esperando decisão.
