---
description: Quais documentos uma ordem de serviço gera, o que entra em cada um e para quem. Usar SEMPRE que a conversa envolver PDF, impressão, "documento do cliente", "via do técnico", job card, folha de campo, ou quando alguém pedir para esconder/mostrar valores num documento. Também ao criar um documento novo ou mexer no pdf-generator.
---

# Documentos de uma ordem de serviço — MarineFlow

## O que a HBR gera hoje

| Documento | Para quem | Existe? |
|---|---|---|
| **Orçamento** | cliente, antes | sim |
| **Ordem de serviço** | cliente, depois | sim |
| **Fatura** | cliente/financeiro | sim |
| **Recibo** | cliente, no pagamento | sim |
| **Via do técnico** (a folha de roteiro terminada) | técnico, em campo | sim — menu Ações da OS e painel de Roteiro |

### Via do técnico — como é montada hoje (01/10/2026)

`src/lib/route-sheet.ts` (`buildRouteSheetHtml`) + `src/hooks/use-via-do-tecnico.ts`
(`viaHeaderFromOrder` é o único montador do cabeçalho; os dois botões usam o mesmo).
Ordem da folha: rosto (veículo, quando, onde, com quem falar, pedido do cliente) → antes de
sair (materiais, ou o aviso de que não há nenhum) → limite de escopo → um cartão por serviço
com a volta (feito / parcial / não feito) → levantamento → roteiro, se houver → chegada e
saída, relato, material extra, assinaturas com o que o cliente atesta. Número da OS e
"pág. X de Y" pelo `@page`.

Regras que os testes guardam:
- **Linha com R$ não sai** (`semValores`), nem da descrição nem do texto dos serviços.
- **As observações da OS (`extra_notes`) não saem**: carregam condição de pagamento e, em
  algumas OS, valores. Ressalva técnica vai para a instrução ao técnico (fase 2 da avaliação).
- **O link do portal do cliente (`/view/<token>`) não sai**: a página mostra preço e o botão
  "Aprovar e Assinar".
- Sugestão da IA não aprovada não vai para o papel; passo já feito sai marcado.
- Campo vazio vira frase para o técnico ("Local não informado na OS. Confirme com o
  cliente"), nunca recado para o escritório.
- Hora de agendamento: o formulário converte com `src/lib/datetime-local.ts`. Mandar o texto
  do `datetime-local` direto gravava a hora local como UTC (3 h de diferença).
- Roteiro: a via (menu Ações) leva só a segurança de cada sistema (`passosDeSeguranca`);
  o painel Roteiro imprime o roteiro completo.

Fase 2 (01/10/2026), campos que só existem para a via:
- `service_orders.technician_instructions` ("Instrução ao técnico") e `site_access` ("Local do
  serviço e acesso", sugerido de `vessels.access_notes`).
- `service_order_services.technician_instructions`, `field_status` (a_fazer, so_levantar,
  aguarda_peca, feito, parcial, nao_feito) e `field_status_note` — controle "Na via do
  técnico" embaixo de cada linha (`line-via-tecnico.tsx`).
- Contato no local = `requested_by_contact_id` → `vessel_contacts` (nome, função, telefone).
- Antes de imprimir, `faltasDaVia` lista o que vai faltar no papel (`aviso-antes-da-via.tsx`).
- Volta do papel: "Lançar a via" (`ViaEntryDialog` + `use-lancar-via`). O relato entra
  EMBAIXO das notas do técnico, com data; a tela da OS recebe as notas novas para o
  salvamento automático não desfazê-las.

### Folha de comissionamento (versão de teste)

`src/lib/folha-comissionamento.ts`, menu Ações → "Folha de comissionamento". Um bloco por
equipamento reconhecido pelo nome das peças da OS (`tipoDeEquipamento`: DC-DC, carregador,
inversor, MPPT, lítio, nessa ordem), identificação preenchida, coluna "Esperado (manual,
pág.)" em toda linha — NUNCA valor de torque/tensão/corrente fixo (regra do dono). Serve a
todas as marcas. Instrumentos da HBR: multímetro + alicate DC, torquímetro, testador Ikro,
scanner Multimec X3. Registro dos valores no sistema (5c) espera o teste em campo.

### Atenção: o portal do cliente lê `select('*')` como anon

`PublicServiceOrderView` lê `service_orders`, `vessels` e `service_order_parts` com `*`.
Custos, comissão, notas internas e as colunas da via chegam ao navegador do cliente (não
aparecem na tela). Achado em 01/10/2026, aguardando decisão do dono.

## A distinção que importa

A literatura de field service separa dois papéis, e confundi-los é a origem de
quase todo problema de documento:

> **Work order** autoriza o trabalho antes de ele começar.
> **Job card / job sheet** registra o que aconteceu.
> Um diz ao técnico o que fazer; o outro prova que ele fez.

Daí decorre a regra prática: **preço e margem são informação de escritório.**
Não vão na via do técnico — não por sigilo, mas porque não ajudam a executar e
competem por espaço com o que ajuda.

## O que a via do técnico precisa ter

Da pesquisa, cruzada com o que a HBR faz:

- **Identificação**: número da OS, cliente, ativo (embarcação/motorhome), local
- **Contato no local** e como acessar — porteiro, marina, chave
- **Descrição específica do problema**, não genérica. "Não *consertar sistema*,
  mas *inversor não liga — cliente relata que parou após tempestade*"
- **Serviços contratados** e **peças/materiais**, com quantidade — sem preço
- **Roteiro de execução**, com marcas de segurança e passos críticos
- **Levantamento**, com as respostas e quais têm foto
- **Espaço para escrever**: medições, o que foi encontrado, o que ficou pendente
- **Assinaturas**: quem executou e quem recebeu, com data e hora

## O que NUNCA vai na via do técnico

Preço unitário, total de linha, subtotal, desconto, imposto, taxa de cartão,
comissão, margem, dados bancários, chave PIX, condições de pagamento, termos
comerciais.

## Regras do gerador (pdf-generator.ts)

**Esconder valor esconde o valor INTEIRO.** `showServicePrices: false` tira
unitário, total da linha e o cabeçalho da coluna. Sem preço em nenhuma seção, o
resumo financeiro some junto. Já foi diferente: a opção tirava só a coluna
"Unitário" e o documento saía com os totais, e foi assim que uma OS impressa
para os técnicos chegou às mãos deles com os valores. A decisão mora em
`pdf-visibility.ts`, com teste que procura os valores formatados no HTML final.

**Opção ausente vale como marcada** — o documento do cliente não pode perder
valor porque alguém esqueceu de passar a preferência.

**Todo CSS do documento é escopado** por `scopeCss` antes de sair. Regra global
(`*`, `body`, `h1`) repinta o app inteiro durante a captura do PDF.

**Imprimir e baixar são motores diferentes**, e isso explica quase toda
diferença entre os dois: imprimir usa o navegador (vetorial, respeita
`page-break-*`); baixar usa html2canvas, que rasteriza numa imagem e fatia — CSS
de quebra não alcança imagem, por isso a paginação é calculada em
`pdf-pagination.ts`, medindo os blocos antes da captura.

## Ao criar documento novo

1. Decida o papel: autoriza ou registra? Cliente ou equipe?
2. Liste o que NÃO entra antes do que entra — é a lista curta e a que erra.
3. Se for de campo, deixe espaço para escrever à mão. Papel de campo que não
   aceita anotação volta com anotação na margem, ou não volta.
4. Teste pelo HTML final, procurando o que não deveria estar lá. Testar só o
   que aparece deixa passar justamente o vazamento.

## Fontes

Job card e work order: [FieldMotion](https://fieldmotion.com/blog/what-is-a-job-card/),
[BigChange](https://www.bigchange.com/blog/job-card-best-practices-to-optimise-field-services),
[Dynamics 365 Field Service](https://learn.microsoft.com/en-us/dynamics365/field-service/work-order-experience).
Rastreabilidade e histórico do ativo: ABNT NBR 5674 (gestão de manutenção —
toda intervenção registrada, histórico reconstituível).
