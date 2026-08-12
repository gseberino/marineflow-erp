# Fila noturna — serviço designado da Parte 1

Lida pelo `/modo-noturno` no início do turno. **Editar este arquivo é como a fila evolui** — o comando não
muda. Item concluído: mover para "Concluídos" com o commit; item que não reproduz mais: mover para "Não
reproduzem" com a data da verificação.

Regra que vale para todos: **re-verificar que o defeito ainda reproduz antes de corrigir.** Com várias
frentes ativas, achado envelhece — o MF-AUD-030 já chegou morto na fila uma vez.

Cada item vira **um commit**, com testes cobrindo o caso e as bordas, e os quatro gates verdes.

---

## Em aberto, nesta ordem

### 1. NOVO-017 — o importador de CSV corrompe dinheiro
`1.234,56` entra como `1,23` (o `replace(',', '.')` troca só a primeira ocorrência e não remove o ponto de
milhar); `1.500` unidades viram `1`. E, no cadastro de clientes, `Telefone` vazio **apaga o celular** já lido,
porque as duas colunas mapeiam para `phone` e a segunda sobrescreve sempre.
**Entregar:** correção + testes; **e um script de auditoria somente-leitura** que liste os registros já
gravados errado, com o critério usado impresso junto. Corrigir os dados passados é decisão do dono — o script
mostra o estrago, não o conserta.
`src/lib/import-detector.ts:142-143,170-178`

### 2. NOVO-024 — deslocamento
4 técnicos custam o mesmo que 1 (`hourly[n] || hourly[1]`, tabela até 3); e `calculateDisplacement` ignora a
tarifa configurada, devolvendo `cost_per_km: 1.10` fixo em código.
**Entregar:** correção + testes cobrindo 1, 3 e 4 técnicos e a tarifa vinda da configuração. A regra para
acima de 3 é **decisão comercial** — se não houver resposta, registrar as opções e corrigir só a parte da
tarifa ignorada.
`src/lib/displacement.ts:59,85-93`

### 3. NOVO-009 — preço explode quando margem + imposto + comissão = 100%
O guard `divisor <= 0` não pega, porque em ponto flutuante `1 - 0.6 - 0.3 - 0.1` dá `+2,78e-17`. O preço sai
3,6 × 10¹⁸ — e o formulário grava esse número no cadastro do produto.
**Entregar:** comportamento seguro definido — erro claro ao usuário, nunca número absurdo no campo. Testes de
borda em 99%, 100% e 101%. O caso hoje está no teste com `it.fails`; ao corrigir, vira `it()`.
`src/lib/price-calculator.ts:30-39` · `src/components/PriceCalculator.tsx:53-60`

### 4. NOVO-022 — toggles que mentem na via de execução
Com "Via de execução" marcada, os outros toggles ficam cinzas **mas continuam valendo** — não dá para tirar os
termos da folha de campo. E `showPaymentInstructions` e `showSignature` são **mortos** (pré-existentes): a
tela nova de padrão passou a oferecê-los ao dono.
**Entregar:** desabilitar só os toggles financeiros. Atenção: o catálogo (`src/lib/pdf-options-catalog.ts`)
**ainda não distingue** financeiro de não-financeiro — `CatalogEntry` só tem `requiresProductImages`,
`perDocumentOnly` e `overridesOthers`. Marcar quais são financeiros faz parte da tarefa. Toggle morto que
exigir decisão de produto — remover da tela ou fazer funcionar — registrar e pular.
`src/components/PDFOptionsDialog.tsx:139` · `src/lib/pdf-generator.ts:1302,1472`

### 5. NOVO-019 — export de CSV
Coluna "Marina" repete o nome do barco (as duas entradas usam `key: 'name'`); aspas escapadas sem envelope; e
**injeção de fórmula** — célula começando com `=`, `+`, `-` ou `@` é executada ao abrir a planilha.
**Entregar:** correção + testes, incluindo as quatro células perigosas.
`src/lib/export-utils.ts:16-23,80`

### 6. NOVO-018 — captura rápida perde o "3"
"comprar 3 cabos" vira tarefa das 03:00 chamada "comprar cabos": número solto é lido como hora. E `30/02` vira
02/03 do ano seguinte, sem aviso.
**Entregar:** exigir marcador de hora (`h`, `:` ou "às"); recusar data inexistente conferindo o dia depois de
construir. Testes dos dois.
`src/lib/quick-task-parser.ts:47-56,61-69`

### 7. NOVO-023 — o guarda do hash de assinatura lê a migration pelo nome
Procura o arquivo `f41d70d9`. Trigger alterado em migration nova passa batido, e a suíte fica verde no
cenário exato que o teste diz impedir.
**Entregar:** varrer todas as migrations e usar a definição mais recente de
`detect_so_change_after_signature`, como o teste de status da OS já faz com o `CHECK`.
`src/lib/document-hash.test.ts:145`

### 8. NOVO-021 — edição durante o Salvar em voo se perde
`setDirty(new Set())` limpa o conjunto inteiro no sucesso, inclusive o que entrou depois de a requisição
partir. A tela diz que salvou, o banco tem o valor antigo, e o botão volta desabilitado.
**Entregar:** remover de `dirty` só as chaves enviadas, ou desabilitar os checkboxes enquanto `isPending`.
Teste cobrindo a corrida.
`src/pages/SettingsPage.tsx:1832,1870-1874`

---

## Concluídos

_(mover para cá com o commit que fechou)_

## Não reproduzem mais

_(mover para cá com a data da verificação e como foi verificado)_
