---
description: Desenhar documento de campo — folha de levantamento, folha de roteiro, job card. Usar ao criar ou alterar qualquer papel que o técnico leva para o local, e ao decidir o que entra num checklist operacional. Também quando alguém perguntar por que um orçamento estourou ou por que trabalho feito não foi cobrado.
---

# Papel que vai a campo — MarineFlow

## Por que orçamento estoura, e o que o papel resolve

Três causas, e nenhuma se resolve imprimindo um questionário:

**1. O que sempre aparece e ninguém orça.** *"Se você costuma abrir paredes e
sabe o que costuma achar, ponha isso na estimativa desde o início em vez de
tratar cada ocorrência como surpresa."* A folha carrega o histórico real
daquele serviço — quantas execuções, quanto costumou levar, o pior caso.

**2. O "já que você está aqui".** O cliente pede mais uma coisa, o técnico faz,
e como não foi registrado no momento aquilo não existe: não chega ao
faturamento nem à precificação. Bloco próprio, preenchido na hora.

**3. A incerteza que não é dita.** O que não deu para verificar volta como
surpresa na execução. Declarado, vira contingência no preço.

## Regras de construção (Gawande, *The Checklist Manifesto*)

- **DO-CONFIRM, não READ-DO.** Técnico experiente trabalha do jeito dele; a
  folha serve para conferir depois, não para conduzir. READ-DO só para
  procedimento desconhecido ou de uma chance só.
- **Killer items primeiro.** O que é perigoso pular, não o que é fácil listar.
  Aqui: as perguntas de impacto ALTO no preço, destacadas e antes das demais.
- **Cada bloco em menos de 90 segundos.** Passou disso, quem está em campo
  começa a pular etapa — e aí a folha inteira perde a confiança.
- **Uma página quando possível**, sem cor decorativa, maiúscula e minúscula.

## O que só existe em papel de verdade

- **Unidade impressa ao lado do campo de medida.** "14" anotado sozinho volta e
  ninguém sabe se é metro ou centímetro — e quem mediu já foi embora.
- **Caixa de marcar, não linha em branco**, para o que é sim/não.
- **Quadriculado para croqui.** Passagem de cabo e de mangueira é espacial e não
  cabe em texto.
- **Memória do ativo impressa**, com caixa "continua igual": confirmar é mais
  rápido que medir de novo.
- **Fotografar ANTES de mexer**, no bloco de partida — depois de desmontado não
  há como provar como estava.
- **Fechamento que força decisão**: dá para orçar, com ressalva, ou preciso
  voltar? Sair do local sem decidir é o que produz orçamento chutado.
- **"Se precisar voltar, levar: ___"** — a segunda viagem já sai planejada.

## Nunca

- **Número inventado.** Com menos de 3 execuções não se mostra média: diz-se
  que não há base e pede-se a estimativa de quem está lá. Quem lê trata número
  como fato.
- **Valor no papel do técnico.** Preço e margem são informação de escritório —
  ver a skill `documentos-de-servico`.
- **Papel sem volta.** Folha que não tem como ser lançada no sistema vira
  gaveta. O par de toda folha é o lançamento em lote: tudo na frente, não em
  fila de uma pergunta por tela.

## Campo em branco ≠ resposta vazia

A distinção que mais rende: pergunta **sem resposta** é informação (alguém não
conseguiu verificar, e isso vira contingência); pergunta **ausente** é
esquecimento, e some sem rastro. No lançamento da folha, branco vira
`skipped_reason`, nunca `answer_value = ''`.

## Onde está no código

- `src/lib/survey-sheet.ts` — folha de levantamento (antes de orçar)
- `src/lib/route-sheet.ts` — folha de roteiro (durante a execução)
- `src/components/service-orders/SurveySheetEntryDialog.tsx` — lançamento em lote
- `src/components/service-orders/SheetEntryDialog.tsx` — lançamento do roteiro

## Fontes

Estouro de escopo e estimativa: [Dataforma](https://www.dataforma.com/job-cost-overruns-happen-field-service-how-prevent/),
[Fieldmotion](https://fieldmotion.com/blog/how-to-prevent-scope-creep/),
[ArboStar](https://arbostar.com/education-hub/how-poor-job-data-destroys-margins-in-field-service-companies).
Checklist: Atul Gawande, *The Checklist Manifesto*.
Site survey técnico: [SafetyCulture](https://safetyculture.com/library/energy-and-utilities/solar-and-battery-site-survey-checklist-jb4sbjbw69r1o6ga),
[SepiSolar](https://www.sepisolar.com/solar-pv-site-survey-checklists/solar-site-survey-checklist-energy-storage-lp/).
