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

### Via do técnico — como é montada hoje (a via aprovada, 16/11/2026)

Uma folha só, em `supabase/functions/_shared/pdf/via-do-tecnico.ts` (`montarViaDoTecnico` →
`buildRouteSheetHtml`): a tela imprime (`src/lib/route-sheet.ts` reexporta + `src/hooks/use-via-do-tecnico.ts`),
e o assistente e a agenda mandam o MESMO HTML em PDF pelo WhatsApp (`/api/pdf`). `viaHeaderFromOrder` é o
único montador do cabeçalho. A referência do desenho é a bancada aprovada pelo dono (`render-r3.ts`, base
"limpa" + rodadas 1, 2 e 3; porte da via v2, F1). A ficha vai **pendurada no veículo**.

Ordem da folha: cabeçalho (número da OS em 28 pt) → o veículo numa linha grande própria → aviso
"Orçamento em aprovação" (só orçamento, `isQuoteStatus`) → rosto numa linha (Quando · Onde · Com quem falar;
o Técnico embaixo) → pedido do cliente, instruções do escritório, o que já se sabe do sistema elétrico →
antes de sair (materiais em 2 colunas, ou o aviso de que não há nenhum) → limite de escopo → um cartão por
serviço (número da OS inteira, situação, Instrução na mesma linha do rótulo, a volta feito / parcial / não
feito) → "com outra pessoa" (via de uma pessoa) → levantamento → quadro **Atenção** (1 linha por risco grave)
→ fechamento num bloco que não se parte: chegada/saída com os telefones do cliente ao lado, relato, material
extra, assinaturas, a faixa "No fim: fotografe todas as folhas preenchidas…" e o rodapé. Número da OS e
"pág. X de Y" pelo `@page`.

Regras que os testes guardam:
- **Linha com R$ não sai** (`semValores`), nem da descrição nem do texto dos serviços.
- **As observações da OS (`extra_notes`) não saem**: carregam condição de pagamento e, em
  algumas OS, valores. Ressalva técnica vai para a instrução ao técnico (fase 2 da avaliação).
- **O link do portal do cliente (`/view/<token>`) não sai**: a página mostra preço e o botão
  "Aprovar e Assinar".
- Sugestão da IA não aprovada não vai para o papel; passo já feito sai marcado (modo roteiro).
- **Sem segurança por sistema na via.** No lugar, o quadro Atenção (`_shared/pdf/via-atencao.ts`): as
  energias vêm do sistema de cada linha (o gravado nela ou, na falta, o do cadastro do serviço — decisão 3A)
  e de palavras inteiras no nome, notas, pedido e material. A via não lê mais a RPC `seguranca_da_via` (a
  agenda continua usando). O painel Roteiro (modo `roteiro`, escondido) imprime o roteiro completo, sem quadro.
- **Número do serviço = o da OS inteira** (`numerarLinhas`, ordem `created_at, id`), o mesmo da tela
  "Lançar a via" e do "serviço N" do assistente — também na via de uma pessoa (2, 5, 7…).
- **Cobrança não vai ao papel** (resposta 4A): frete, deslocamento e insumos no título curto
  (`ehCobranca`, `_shared/pdf/via-texto.ts`; casos em `via-cobranca-casos.ts`) saem dos cartões e do "Lançar a
  via"; os outros mantêm o número. A linha de cobrança conta para o quadro Atenção.
- **Telefones fora da folha 1**: o rosto diz "telefone no fim da ficha"; os números vão ao fechamento. O
  cabeçalho continua completo (o aviso antes de imprimir lê dele).
- **Sem local na OS = "Oficina HBR"** (`ONDE_PADRAO`); campo vazio continua virando frase para o técnico
  ("A combinar com o escritório", "sem telefone no cadastro"), nunca recado para o escritório.
- **Nota interna do material não vai** ("Cadastrado pelo orçamento — confirmar preço…", `notaDoMaterial`).
- **A marca HBR (25/11/2026)**: via e relatório do assistente usam `_shared/pdf/marca.ts` — cores, Archivo
  (títulos) e Hanken Grotesk (texto) EMBUTIDAS no HTML (`marca-fontes.ts`, woff2 latino), fio em degradê, slogan.
  Documento novo reaproveita daqui. A pilha é `"Hanken Grotesk", "Open Sans", …`: o que a marca não tiver sai na
  Open Sans do servidor.
- **Nenhum caractere fora da Open Sans do servidor** (a única fonte do `/api/pdf`): nada de "⚠" (o triângulo é
  SVG) nem "→" (entre as datas sai "até"). O teste usa as faixas de `_shared/pdf/open-sans-faixas.ts`.
- **Mudou o desenho ou a regra do papel? Suba `VERSAO_DA_VIA`** (hoje 4) e regrave a trava de
  `via-do-tecnico_test.ts`: a agenda só reenvia quando o DADO muda (`impressaoDaVia`).
- Hora de agendamento: o formulário converte com `src/lib/datetime-local.ts`. Mandar o texto
  do `datetime-local` direto gravava a hora local como UTC (3 h de diferença).

Fase 2 (01/10/2026), campos que só existem para a via:
- `service_orders.technician_instructions` ("Instrução ao técnico") e `site_access` ("Local do
  serviço e acesso", sugerido de `vessels.access_notes`).
- `service_order_services.technician_instructions`, `field_status` (a_fazer, so_levantar,
  aguarda_peca, feito, parcial, nao_feito) e `field_status_note` — controle "Na via do
  técnico" embaixo de cada linha (`line-via-tecnico.tsx`).
- Contato no local = `requested_by_contact_id` → `vessel_contacts` (nome, função, telefone).
- Antes de imprimir, `faltasDaVia` lista o que vai faltar no papel (`aviso-antes-da-via.tsx`):
  telefone de contato, data e hora, serviços (sem contar a cobrança) e material. "Local e acesso" e
  "segurança" saíram em 16/11/2026 (a via diz "Oficina HBR" e não imprime mais a segurança por sistema).
  O item do menu fica desabilitado ("carregando…") até serviços, material e cabeçalho chegarem.
- Volta do papel: "Lançar a via" (`ViaEntryDialog` + `use-lancar-via`), com o número de cada serviço igual ao
  da via (cobrança escondida, os outros mantêm o número). O relato entra
  EMBAIXO das notas do técnico, com data; a tela da OS recebe as notas novas para o
  salvamento automático não desfazê-las.

### Folha de comissionamento (versão de teste)

`src/lib/folha-comissionamento.ts`, menu Ações → "Folha de comissionamento". Um bloco por
equipamento reconhecido pelo nome das peças da OS (`tipoDeEquipamento`: DC-DC, carregador,
inversor, MPPT, lítio, nessa ordem), identificação preenchida, coluna "Esperado (manual,
pág.)" em toda linha — NUNCA valor de torque/tensão/corrente fixo (regra do dono). Serve a
todas as marcas. Instrumentos da HBR: multímetro + alicate DC, torquímetro, testador Ikro,
scanner Multimec X3. Registro dos valores no sistema (5c) espera o teste em campo.

### O link público da OS só lê colunas do cliente (corrigido em 01/10/2026)

`PublicServiceOrderView` e o PDF do portal (`carregarPDFData(id, sb, { publico: true })`)
pedem só as colunas de `supabase/functions/_shared/pdf/colunas-publicas.ts`. No banco
(migration `20261001190104`), o anon tem SELECT **por coluna** nas 10 tabelas que o link
alcança — todas menos `COLUNAS_INTERNAS` (custo de peça, comissão, notas internas, custo e
margem de produto, taxa de cartão…). Consequências:
- **`select('*')` como anon dá 42501.** Qualquer leitura nova pelo link precisa de colunas
  explícitas.
- **Coluna nova nessas tabelas nasce fechada para o anon.** Se o portal precisar dela,
  incluir em `colunas-publicas.ts` E numa migration que faça o grant.
- Nomes enganosos: `labor_cost_total`, `parts_cost_total`, `operational_cost_total`,
  `subcontract_cost_total` de `service_orders` são valores de VENDA (entram no subtotal); as
  notas do técnico e as observações financeiras saem no documento da OS do cliente — por
  isso ficam públicas. Margem de verdade está em `service_order_parts.unit_cost_snapshot`.
- O anon não lê `services`: o PDF público usa `name_snapshot` (o embed `services(name)`
  derrubava a consulta com 42501).
- `colunas-publicas.test.ts` amarra a lista do código à da migration e confere os campos do
  hash da assinatura.

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
