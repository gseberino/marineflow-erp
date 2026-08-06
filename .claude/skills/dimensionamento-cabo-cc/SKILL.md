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

A **ampacidade não está calculada**: a tabela da ABYC E-11 é norma paga e não
existe em texto público. A tabela `dc_ampacity_ratings` está **vazia** de
propósito, esperando ser preenchida com a fonte na mão. Enquanto estiver vazia,
toda resposta vem com `pronto: false` e o aviso de que só metade da conta foi
feita.

## Como agir

**Nunca afirme uma bitola sem os quatro dados**: corrente (A), comprimento do
trecho (m), tensão do sistema (V) e se o circuito é crítico. Faltando qualquer
um, pergunte — não assuma. A única suposição aceitável é 3% quando a
criticidade não foi dita, porque erra para o lado do cabo mais grosso.

**Chame `survey_cable_sizing(survey_id)`** quando houver levantamento; ele lê
as respostas pelos papéis em `service_survey_templates.affects` (`corrente`,
`comprimento`, `tensao`, `criticidade`, `casa_maquinas`, `feixe`).

**Diga sempre qual critério mandou** e, enquanto a ampacidade não estiver
cadastrada, repita que ela não foi verificada. Um número redondo sem essa
ressalva vira decisão.

**Nunca reproduza tabela de ampacidade de memória**, nem AWG↔mm² "de cabeça"
para justificar uma escolha. Se a tabela não estiver cadastrada, o caminho é
dizer que falta conferir na ABYC E-11 ou no Circuit Wizard da Blue Sea.

**Regra de material que aponta para cabo é suspeita por natureza**: ela fixa um
produto e não sabe a corrente do circuito. Ao encontrar uma, verifique a
bitola contra o cálculo antes de deixar passar.

## O que dizer ao cliente

Errado: "vai cabo de 35 mm²".

Certo: "para 250 A nesse trecho de 2,5 m em 12 V, mantendo os 3% de queda que a
ABYC pede em alimentador principal, o cabo precisa de pelo menos 62 mm². Falta
conferir a ampacidade na tabela da norma, que pode pedir mais."
