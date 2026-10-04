# Roteiro de execução e levantamento: o que é verdade hoje (04/10/2026)

Avaliação feita só com leitura: SELECT no banco de produção e leitura do código do main (`f3febfa3`).
Nada foi alterado. As consultas estão em `scratchpad/avaliacao-roteiro/*.sql`, e o resultado de cada uma está no `.out` com o mesmo nome.

## Veredito curto

O dono tinha razão em parte. Das cinco afirmações do cartão, **uma estava errada** ("116 passos esperam aprovação") e **uma estava velha** (os 35 achados: 29 já foram corrigidos em 09–10/09). O resto continua verdade: **nenhum passo foi feito**, há **só 2 levantamentos**, e os defeitos **lev-05 e lev-06 continuam no código**. Os dois, porém, **nunca aconteceram com um dado real**.

Também apareceu uma coisa que a medição de 30/09 não tinha como ver. Desde 01/10, a **Via do Técnico** imprime a parte de segurança do roteiro. Aposentar tudo tiraria essa parte do papel.

**Recomendação: ESCONDER sem apagar**, com uma exceção: manter a segurança por sistema que a via imprime, e fazê-la sair sozinha.

---

## 1. Afirmação por afirmação

| O cartão dizia | Hoje | Situação |
|---|---|---|
| "255 passos, nenhum feito" | 255 passos, **todos `pending`**. Nenhum tem `started_at`, `completed_at`, medida ou responsável. O último foi criado e mexido em **14/08**. Nada nos últimos 30 dias. | **Verdade** |
| "só 2 levantamentos" | 2 levantamentos e 13 respostas no total. O último é de **31/08**. Nenhum nos últimos 30 dias. | **Verdade** |
| "116 passos esperam aprovação" | **Nada no roteiro espera aprovação.** Os 116 eram os blocos componíveis de 31/07, e o dono aprovou todos no mesmo dia (116/116). Hoje há **136 blocos, 34 moldes e 93 perguntas, todos aprovados e ativos**. O que ainda espera aprovação são **5 regras de material** do levantamento, de 05/08. O "116" provavelmente veio da memória antiga ou da estimativa de linhas do Postgres para `service_step_blocks`. | **ERRADA** |
| "total da OS não recalcula com material do levantamento (lev-06)" | Continua no código e no banco: veja a seção 3. **Zero ocorrências reais.** | Verdade, sem estrago |
| "resposta gravada pela posição pode sobrescrever outra (lev-05)" | Continua: veja a seção 3. **Zero ocorrências reais.** | Verdade, sem estrago |
| (memória) "35 achados ABERTOS NOVO-lev-01..35" | **29 dos 35 foram corrigidos em 09–10/09.** O livro `audit/novos-achados.md` já marca isso como RESOLVIDO, mas a memória não foi atualizada. Abertos: **05, 06, 09, 19, 27, 28**. | **VELHA** |

## 2. Estado real hoje

### Roteiro (`service_order_steps`)
- **8 ordens** têm roteiro, todas geradas entre **31/07 e 14/08**. Desde 15/08 foram criadas 33 ordens (4 viraram OS e 7 foram concluídas), e nenhuma ganhou roteiro.
- **5 são OS reais em aberto**, de clientes reais:
  - OS-00051, aguardando peça desde junho
  - OS-00061, aberta
  - OS-00069, aberta
  - OS-00074, aberta
  - OS-00076, aguardando o cliente

  Essas OS foram mexidas até 03/10, mas os passos delas não.
- **3 são orçamentos recusados**: ORÇ-00068, ORÇ-00072 e ORÇ-00079, com 82 passos. São restos inofensivos.
- Conteúdo dos passos:
  - 173 de 255 (68%) estão marcados como CRÍTICO.
  - 95 são de abertura ou fechamento de sistema, isto é, de segurança.
  - 48 pedem foto e 22 pedem medida.
- **O ponto principal: a execução não é registrada em lugar nenhum do sistema**, e não só no roteiro:
  - `time_entries`: 0 linhas
  - `work_shifts` (Diárias) ligados a OS: 0
  - `service_order_services.field_status`: 249 de 249 linhas em `a_fazer`, que é o padrão
  - **Usuários técnicos ativos: 0** (3 cadastrados, todos inativos)

  Ou seja, "nenhum passo feito" não é descuido com a ferramenta. Hoje não existe ninguém com login para marcar os passos. A execução acontece no papel e no WhatsApp.

### Levantamento (`service_surveys`)
- **OS-00074** (bateria chumbo→lítio): aberto em 05/08 pela tela, 9 respostas (1 pulada), **ainda em rascunho**. A aba Levantamento só aparece em orçamento, então este não pode mais ser continuado pela tela.
- **Sem OS ligada**: fechado em 31/08 pelo assistente no painel, com 4 respostas e confiança "alta". É uma instalação elétrica em motorhome. Ficou solto, sem orçamento apontando para ele.
- Nenhuma foto de levantamento foi gravada.
- `service_cases`: 10 casos, nenhum utilizável. A estimativa por analogia nunca teve dado.
- A trava D11 ("concluir exige levantamento") está **inerte**: 0 serviços estão marcados como `requires_survey`.

### Uso pelo assistente (histórico inteiro de `ai_operator_audit`)
- **`size_dc_cable` (bitola de cabo): 24 chamadas entre 17/08 e 31/08**, no painel e no WhatsApp. É a parte mais usada da frente.
- Levantamento:
  - 31/08, no painel, numa sessão só: `start_service_survey` 1, `record_survey_answer` 9, `assess_survey_confidence` 7, `close_service_survey` 6, `survey_material_list` 7
  - `check_needs_survey`: 2 chamadas, a última em 16/09
- Roteiro: só `get_service_order_route` 1 vez e `get_route_drafting_context` 1 vez, ambas em 05/08. **Nenhum passo foi iniciado nem concluído pelo assistente.**

### Onde aparece hoje
- **Tela:**
  - Aba **Roteiro** em toda OS (`ServiceOrderDetail.tsx:104`; a tela v2 usa a mesma página)
  - Aba **Levantamento** em todo orçamento (`:109`)
  - Itens de menu "**Quadro do Dia**" e "**Roteiros Padrão**" (`AppLayout.tsx:184-185`)
  - Painel "**costuma entrar junto**" (`RelatedMaterialsPanel`) dentro do formulário de toda OS e orçamento (`ServiceOrderForm.tsx:2276`)
  - Botão "analisar a descrição → levantamento" no formulário
- **Assistente:**
  - `prompt.ts:362-382` ensina as seções "ROTEIRO DE EXECUÇÃO" e "LEVANTAMENTO ANTES DE ORÇAR".
  - `perfil-operacao.ts` põe em todo turno 9 tools de roteiro, 6 de levantamento e `size_dc_cable`.
  - `channel-scope.ts` mantém essas tools no WhatsApp de propósito, "para o técnico". Só que o WhatsApp só atende usuários ativos com IA ligada, e nenhum técnico está nessa situação.
- **Via do Técnico (NOVO desde a medição de 30/09):**
  - Desde o commit `03c8f22b` de 01/10, a via impressa pelo menu Ações leva **só a segurança de cada sistema** tirada do roteiro (`route-sheet.ts:81 passosDeSeguranca`).
  - Ela também leva o levantamento inteiro.
  - **Como nenhuma OS desde 14/08 tem roteiro, as vias recentes saem sem a parte de segurança, e sem aviso.** O `faltasDaVia` (`route-sheet.ts:129`) avisa quando falta local, telefone, data, serviços ou material, mas não avisa quando falta a segurança.
- **Potencial, se gerado:**
  - 88 de 105 linhas de serviço das ordens recentes (84%) são texto livre, sem serviço do catálogo.
  - O classificador reconhece o **sistema** em 73 dessas 88. Para essas linhas, a abertura e o fechamento de segurança sairiam.
  - Em 4 das 12 ordens com linha de catálogo, o catálogo monta um corpo de roteiro completo.

## 3. Os defeitos citados no cartão

### NOVO-lev-06: material lançado não mexe no total da OS. **CONTINUA**
- No banco:
  - `service_order_parts` tem 3 gatilhos (reserva, garantia, updated_at) e `service_order_services` tem 2. **Nenhum chama recálculo.**
  - `apply_survey_materials` não chama `recalc_so_totals`. Já ganhou a mensagem de motivo do descarte (lev-08), mas não o recálculo.
- No código:
  - `useApplySurveyMaterials` (`use-survey-material-rules.ts:71`) não chama `recalcTotals`.
  - `useAddRelated` (`RelatedMaterialsPanel.tsx:45`) também não. Só as chaves de cache foram corrigidas (lev-07).
- Parente da mesma classe: `apply_service_material_kit` (tool do assistente) também insere peça sem recalcular. Nunca foi usada.
- **Estrago real: zero.** `service_order_parts` tem 333 linhas, todas `source='manual'`. Nenhuma peça entrou pelo levantamento (`survey`) nem pelo "costuma entrar junto" (`ai`).
- **Ponto de atenção:** o painel "costuma entrar junto" está visível em todo formulário de OS, fora das abas que seriam escondidas. Se ele ficar na tela, o lev-06 continua armado ali.

### NOVO-lev-05: resposta gravada pela posição. **CONTINUA**, e em mais lugares do que o livro diz
- O índice único continua sendo `service_survey_answers_uk (survey_id, seq)`.
- Os quatro caminhos de escrita gravam pela posição:
  - tela (`SurveyPanel.tsx:169`, `seq: idx + 1`)
  - transcrição da folha (`SurveySheetEntryDialog.tsx:110/127`)
  - assistente (`survey-ops.ts:184-193`, `onConflict survey_id,seq`)
  - "analisar a descrição" (`ServiceOrderForm.tsx:338`)
- O último caminho grava a posição de uma lista diferente da que a tela usa depois. É a forma mais provável do defeito acontecer.
- O estrago grande do reabrir/F5 (lev-25) foi contido em 10/09: a tela continua do maior `seq` já gravado.
- **Estrago real: zero.** Só existem 2 levantamentos, e nenhum foi reaberto depois de uma pergunta nova ser aprovada.

### Os 35 achados de agosto (NOVO-lev-01..35)
- **Corrigidos: 29**
  - 01, 02, 03, 04, 07, 08, 10–18, 20–26, 29–35, todos em 22/08 ou entre 09 e 10/09
  - Conferi no código ou no banco vivo: 04, 07, 08, 20, 21, 24, 25 e 31/32 (pela migration)
- **Abertos: 6**
  - **05**: posição × pergunta
  - **06**: total da OS
  - **09**: a trava de duplicata no lançamento de material; não há `ON CONFLICT`
  - **19**: a folha usa `compose_survey_for_order` com limite 14, e a tela que a transcreve usa `compose_survey_for_service` com limite 9
  - **27**: o bucket `service-order-photos` continua **público**; nenhuma foto de levantamento existe hoje
  - **28**: `related_materials` ainda conta orçamento recusado ou cancelado como "vezes que você usou"
- **Os 5 que erravam um número que decide material:**
  - **4 corrigidos:**
    - lev-04: `survey_cable_sizing` tem o filtro `skipped_reason is null` nas leituras (7 ocorrências)
    - lev-20: `dc_cable_sizing` devolve `mm2_minimo` nulo quando falta um critério, e `como_dizer` só afirma a bitola com `pronto === true`
    - lev-21: as perguntas de tensão, casa de máquinas e feixe estão ativas, e a função declara `presumido`
    - lev-24: o upsert sempre grava `numeric_value`
  - **1 aberto: lev-06**, sem nenhuma ocorrência.
  - Ou seja: **o risco físico (bitola de cabo) foi fechado. O que sobra é risco de dinheiro, num caminho que nunca foi usado.**

## 4. Recomendação: ESCONDER sem apagar, mantendo a segurança na via

**Por que não ADOTAR agora.** Adotar o roteiro como "o técnico marca passo a passo" depende de técnico com login, e hoje há zero. Também vai contra o modelo que o dono escolheu em 01/10:
- a via em papel;
- o escritório lança o resultado com "Lançar a via";
- a situação é registrada por linha de serviço (feito, parcial, não feito), não por passo.

A marcação por passo ficou sem lugar nesse desenho. Antes de adotar, ainda seria preciso:
- corrigir o lev-05: troca de chave numa tabela com dados, em 4 caminhos;
- corrigir o lev-06: decisão de arquitetura entre gatilho e frontend;
- corrigir os lev-09, 19, 27 e 28;
- corrigir a qualidade do roteiro genérico (68% "crítico", passos que não servem ao veículo).

Seria investimento numa ferramenta sem usuário.

**Por que não APOSENTAR de vez.**
- A **segurança por sistema** é o único pedaço com consumidor vivo: a Via do Técnico de 01/10, que o dono chamou de "extremamente importante".
- O **dimensionamento de cabo** foi usado de verdade: 24 vezes em agosto.
- O catálogo aprovado tem 136 blocos e 93 perguntas e custou trabalho do dono.

Apagar perderia tudo isso. Esconder custa pouco e se desfaz religando uma chave.

### O que seria feito (nada disto foi feito; depende de OK do dono)
1. **Via do Técnico com segurança automática.** Ao imprimir a via, se a OS não tem roteiro, gerar só a abertura e o fechamento dos sistemas, ou pelo menos avisar "sem segurança: gerar?" no `faltasDaVia`. Hoje as vias recentes saem sem essa parte e sem avisar.
2. **Esconder atrás de uma chave em `app_settings`, desligada por padrão:**
   - a aba Roteiro (o painel de marcar passo, o Modo Foco e a reordenação);
   - a aba Levantamento;
   - os itens de menu "Quadro do Dia" e "Roteiros Padrão" (as rotas continuam abrindo pelo endereço, para o admin).
3. **Painel "costuma entrar junto":** esconder junto, ou, se o dono quiser mantê-lo, corrigir o lev-06 nele (recalcular depois de inserir) e o lev-28 (contar só ordens executadas). É o único pedaço que ficaria na tela com defeito.
4. **Assistente:**
   - tirar do `PERFIL_OPERACAO` as tools de passo (start, complete, skip, block e add step, além do rascunho de roteiro) e as de levantamento;
   - tirar do `prompt.ts` as duas seções correspondentes;
   - ajustar `prompt-ferramentas_test.ts`, que cruza prompt com perfil;
   - **manter o `size_dc_cable`**.

   São cerca de 15 tools a menos no prefixo, uns 3,8 mil tokens, na conta de 256 tokens por tool de `channel-scope.ts`. A mudança precisa de deploy da edge com OK nomeado.
5. **Não apagar nada:** os 255 passos, os 136 blocos, as 93 perguntas, as 5 regras e os 2 levantamentos ficam no banco. Os passos dos 3 orçamentos recusados podem ficar; são inofensivos.
6. **Atualizar a memória:**
   - `project_marineflow_varredura_levantamento`: são 6 abertos, não 35;
   - `project_marineflow_execucao_os`: nada espera aprovação; a via passou a consumir o roteiro;
   - o cartão do Diário: corrigir a frase do "116".

**Gatilho para reabrir:** quando houver técnico com login, ou quando o dono quiser registrar a execução por passo. Aí entram o lev-05, o lev-06, o lev-19, o lev-27 e a qualidade do roteiro, nessa ordem.
