---
description: Dimensionar cabo de corrente contínua em embarcação, motorhome ou camper segundo ABYC E-11 e Blue Sea Systems. Usar SEMPRE que a conversa envolver bitola, seção, mm², AWG, queda de tensão, ampacidade, ou "que cabo usar" — e antes de sugerir, orçar ou aprovar qualquer cabo de alimentação. Também ao revisar regra de material que aponte para cabo.
---

# Dimensionamento de cabo CC — ABYC E-11 / Blue Sea

## Por que esta skill existe

No ORÇ-00074 o sistema sugeriu "Cabo flexível 35 mm²" e o dono perguntou se
aquilo batia com a Blue Sea ou a ABYC. Não batia com nada: era o produto que
alguém fixou numa regra que calcula **comprimento**, não bitola. Com a corrente
que o próprio levantamento já registrava — 250 A, 2,5 m, 12 V — a queda de
tensão de 3% exigia **62 mm²**. O cabo sugerido tinha pouco mais da metade.

Ninguém percebeu porque o número apareceu numa tela de "material sugerido", e
material sugerido parece dimensionado. O erro só não foi para a instalação
porque o dono desconfiou.

Cabo subdimensionado esquenta. Isto é segurança física, não precisão de
orçamento.

## A regra que manda

A ABYC E-11 exige **dois critérios independentes**, e vale **o maior dos dois**:

| Critério | O que protege | Do que depende |
|---|---|---|
| **Ampacidade** | O cabo não pode esquentar | bitola, isolação (60/75/90/105 °C), casa de máquinas, condutores no feixe |
| **Queda de tensão** | O equipamento tem que receber tensão | corrente, comprimento **ida e volta**, tensão do sistema, limite de queda |

Trecho curto com corrente alta costuma ser governado pela **ampacidade**.
Trecho longo, pela **queda de tensão**. Calcular só um dos dois não é
dimensionar — é adivinhar metade.

Limite de queda: **3% em circuito crítico** (navegação, bomba de porão,
alimentadores principais — o cabo do banco de baterias é crítico), **até 10%
em não crítico** (iluminação de cabine, acessórios).

## O que o sistema calcula e o que ele NÃO calcula

`dc_cable_sizing()` e `survey_cable_sizing()` calculam a **queda de tensão**
pela fórmula de circular mils, que é pública e verificável:

    CM = (10,75 × I × comprimento_ida_e_volta_em_pés) / (V × queda%)
    mm² = CM / 1973,53

O comprimento é de **ida e volta**: o positivo vai e o negativo volta, e a
corrente atravessa os dois. Calcular com o comprimento simples erra por 2 — é
o erro mais comum do ramo, e a função já dobra sozinha o trecho informado.

A **ampacidade também está calculada** desde 09/08/2026. A tabela
`dc_ampacity_ratings` foi preenchida com valores da ABYC E-11 reproduzidos por
Ancor e EXPLORIST.life, conferidos entre si, e cada linha guarda a procedência
no campo `source`.

Cobertura atual: **16, 25, 35, 50 e 70 mm²**, isolação 105 °C. Fora dessa faixa
a função devolve `pronto: false` e diz *"nenhuma bitola cadastrada aguenta esta
corrente"* — o que é mais honesto que devolver a maior e deixar parecer que
serve. Para cobrir mais, cadastrar nova linha com a fonte junto.

Fatores de correção, ambos aplicados sobre o valor de tabela:

| Condição | Fator |
|---|---|
| Casa de máquinas / compartimento de motor | **0,85** (ambiente 20 °C mais quente) |
| Condutores em feixe, qualquer quantidade | **0,70** |

O 0,70 vale para **qualquer** tamanho de feixe: a ABYC usa fator único em
corrente contínua. Os fatores que variam com o número de condutores (0,6 / 0,5
/ 0,4) são de corrente **alternada** — não misturar.

## Como agir

**Nunca afirme uma bitola sem os quatro dados**: corrente (A), comprimento do
trecho (m), tensão do sistema (V) e se o circuito é crítico. Faltando qualquer
um, pergunte — não assuma. A única suposição aceitável é 3% quando a
criticidade não foi dita, porque erra para o lado do cabo mais grosso.

**Chame `survey_cable_sizing(survey_id)`** quando houver levantamento; ele lê
as respostas pelos papéis em `service_survey_templates.affects` (`corrente`,
`comprimento`, `tensao`, `criticidade`, `casa_maquinas`, `feixe`).

**Diga sempre qual critério mandou.** Não é detalhe: trecho curto com corrente
alta costuma ser governado pela AMPACIDADE, e trecho longo pela QUEDA DE
TENSÃO. Medido no próprio sistema: 50 A em 2 m pede 16 mm² (ampacidade, contra
9,93 da queda); os mesmos 50 A em 10 m pedem 49,64 mm² (queda, contra 16 da
ampacidade).

**Nunca reproduza tabela de ampacidade de memória**, nem AWG↔mm² "de cabeça".
Chame `dc_cable_sizing` ou `survey_cable_sizing` — os valores estão no banco
com procedência. Se a corrente estiver fora da faixa cadastrada, a função diz
isso: repasse, não improvise.

**As linhas métricas são conservadoras de propósito.** A norma é em AWG e o
catálogo da HBR é métrico; cada bitola recebeu o valor do AWG de seção MENOR ou
igual. Um 16 mm² carrega o número do AWG 6 (13,30 mm²), que é mais fino — o
resultado pede cabo um pouco mais grosso do que o estritamente necessário, e
esse é o lado certo para errar.

**Regra de material que aponta para cabo é suspeita por natureza**: ela fixa um
produto e não sabe a corrente do circuito. Ao encontrar uma, verifique a
bitola contra o cálculo antes de deixar passar.

## O que dizer ao cliente

Errado: "vai cabo de 35 mm²".

Certo: "para 250 A nesse trecho de 2,5 m em 12 V, o cabo precisa de **70 mm²**.
Quem manda aqui é a ampacidade — pela queda de tensão bastariam 62 mm², mas o
cabo não pode esquentar, e vale o maior dos dois."

E note o desfecho do caso real: enquanto só a queda de tensão estava calculada,
a resposta era 62 mm². Com a ampacidade cadastrada, virou 70. **Meia conta
apresentada como conta inteira teria mandado comprar cabo insuficiente** — é
por isso que a função devolve `pronto: false` quando falta metade.
