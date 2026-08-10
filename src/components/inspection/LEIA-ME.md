# Módulo de inspeção — frente interrompida, fora do typecheck

`ServiceOrderInspectionTab.tsx` é o único arquivo desta pasta e **não compila**: importa
seis módulos que nunca foram escritos.

```
@/lib/inspection/marine-template      ./InspectionChecklist
@/lib/inspection/report-preview       ./VoltageDropPreview
@/lib/inspection/voltage-drop         ./InspectionReportPreview
```

`src/lib/inspection/` não existe, e **nenhum arquivo do projeto importa este componente** —
ele não entra no bundle nem quebra o build, porque o Vite só resolve o que está no grafo a
partir do entry. Ver `audit/23-hooks-utils.md`, achado **MF-AUD-044**.

## Por que a pasta está no `exclude` do `tsconfig.app.json`

A T2.1 zerou os erros de tipo para o CI poder bloquear de verdade. Seis dos dezesseis vinham
daqui. As opções eram:

- **apagar** — o destino desta frente é a **decisão #10** do `audit/99-sumario-executivo.md`,
  ainda sem resposta do Gustavo. Apagar seria decidir por ele;
- **escrever os seis módulos** — é a frente inteira, não cabe numa tarefa de CI;
- **excluir do typecheck** — mantém o trabalho no lugar, deixa o CI honesto, e escreve na
  parede que este código está fora do sistema. Foi o escolhido.

## O que fazer quando a decisão #10 vier

- **Retomar a frente:** tirar `src/components/inspection` do `exclude` e escrever os seis
  módulos. O typecheck volta a cobrir a pasta e passa a ajudar em vez de atrapalhar.
- **Abandonar:** apagar a pasta e a linha do `exclude`. São dois comandos.

Enquanto nenhuma das duas acontece, vale saber: existe um módulo de **levantamento**
funcionando (`service_surveys`, `SurveyPanel`), que pode ter tornado esta frente obsoleta.
