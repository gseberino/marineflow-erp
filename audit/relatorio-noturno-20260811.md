# Livro de ocorrências — turno noturno 11→12/08/2026

**Branch:** `session/noturno-20260811` (de `d1a7bc7`) · **Guarda:** sessão autônoma
**Produção congelada:** nenhum push, nenhuma migration aplicada, nenhum deploy.

---

## Resumo executivo

*(consolidado no encerramento do turno — ver o fim do arquivo)*

---

## Estado do turno

| Tarefa | Situação | Commit |
|---|---|---|
| NOVO-017 — importador CSV | ✅ corrigido + auditoria | `a definir` |
| NOVO-016 — deslocamento | ⏳ | |
| NOVO-009 — preço 100% | ⏳ | |
| NOVO-022 — toggles | ⏳ | |
| NOVO-019 — export CSV | ⏳ | |
| NOVO-018 — captura rápida | ⏳ | |
| NOVO-023 — guarda do hash | ⏳ | |
| NOVO-021 — Salvar em voo | ⏳ | |

---

## 1. NOVO-017 — importador CSV corrompia dinheiro e apagava celular

**Reprodução confirmada** por leitura antes de mexer, nos dois casos.

### O que estava errado

`src/lib/import-detector.ts:171` fazia `parseFloat(str.replace(',', '.'))`. Dois furos que se
somam: `replace` sem flag global troca só a **primeira** vírgula, e o ponto de milhar
permanece. `"1.234,56"` virava `"1.234.56"`, que o `parseFloat` lê até o segundo ponto e
devolve **1.234**. Um produto de R$ 1.234,56 entrava no catálogo por R$ 1,23. O mesmo em
`parseInt` para estoque: `"1.500"` virava **1**.

`applyMapping:198` atribuía sem condição. O mapeamento de clientes manda **`Celular` e
`Telefone` para o mesmo campo `phone`**; como o laço percorre o mapeamento em ordem, um
`Telefone` vazio sobrescrevia com `null` o celular já lido — justamente o número do WhatsApp.

### O que fiz

`parseNumeroBR()` novo, que decide o separador decimal por regra explícita: com vírgula **e**
ponto, o último a aparecer é o decimal (cobre pt-BR e en-US); com um só tipo repetido, é
milhar; aparecendo uma vez, vírgula é decimal e ponto com exatamente 3 dígitos é milhar.
Trata `R$`, espaço não-quebrável do Excel e negativo contábil entre parênteses. Estoque
**trunca** em vez de arredondar — "1.500,80" são 1.500 unidades na prateleira.

Em `applyMapping`, valor `null` deixou de sobrescrever valor já preenchido. Preenchido
**continua** sobrescrevendo preenchido, então corrigir por uma segunda coluna segue possível.

**Testes:** os dois casos de caracterização que documentavam o defeito foram invertidos, mais
11 casos novos — pt-BR, en-US, moeda, negativo, truncamento, e os dois sentidos da ordem das
colunas de telefone. 34 no arquivo, 1140 na suíte.

### ⚠️ Autoavaliação — o que uma revisão adversarial pegaria

1. **`"1.500"` é ambíguo e eu escolhi.** Ponto seguido de exatamente 3 dígitos pode ser mil e
   quinhentos (pt-BR) ou 1,5 com três casas (en-US). Resolvi como **milhar**, porque é o que o
   Excel local gera e preço com 3 decimais é raro em catálogo. **É uma escolha, não um fato** —
   se o dono discordar, é uma linha em `parseNumeroBR`.
2. **Não mexi no `return 0` para texto sem dígito.** `"sob consulta"` continua virando preço 0,
   que é outra forma de corromper dinheiro em silêncio. Mudar para `null` ou recusar a linha é
   **decisão de produto** (o que fazer com a linha?), então registrei em vez de decidir — ver
   NOVO-import-01 abaixo.
3. **Não verifiquei o caminho ponta a ponta na tela.** Testei as funções puras; não subi o app
   nem importei arquivo real, porque isso seria escrita em produção. A correção é de função
   pura com teste, mas **quem revisar deve importar um CSV de teste** antes de considerar
   fechado.

### O script de auditoria — e o que ele NÃO prova

`supabase/tests/auditoria_import_csv_novo017.sql`, somente leitura (nenhum UPDATE/DELETE).

O defeito produz dois resultados e **só um deixa rastro**:

| Entrada | Virou | Detectável? |
|---|---|---|
| `1.234,56` | 1.234 | **sim** — 3 casas decimais |
| `12.500,00` | 12.5 | **não** — igual a um legítimo R$ 12,50 |
| `1.500` (estoque) | 1 | **não** — igual a um estoque real de 1 |

Rodei o critério forte nesta base: **zero produtos** com mais de 2 casas decimais. Isso **não
significa "nada foi corrompido"** — significa que, se houve, caiu nos casos sem rastro. Ter
certeza exige o CSV original.

Números lidos hoje, para a revisão matinal calibrar: 448 produtos (33 sem preço de venda, 100
sem custo, 3 com estoque exatamente 1) e 528 clientes, **148 sem telefone** — destes, os que
têm e-mail preenchido são os suspeitos do defeito (b), e o script os lista.

---

## Achados novos deste turno

### NOVO-import-01 — texto não numérico vira preço 0 em silêncio
- **Onde:** `src/lib/import-detector.ts`, `transformValue` — `return num === null ? 0 : num`.
- **O quê:** uma célula "sob consulta", "a combinar" ou um cabeçalho repetido no meio do
  arquivo entra como **preço zero**, sem aviso, no meio de centenas de linhas certas.
- **Por que não corrigi:** o certo depende de uma decisão que é do dono — recusar a linha
  inteira, importar com preço nulo e marcar para revisão, ou manter 0 e avisar na tela de
  conferência. Cada uma muda o fluxo do wizard.
- **Recomendação:** importar com `null` e mostrar as linhas afetadas no passo de conferência,
  que já existe. Nunca 0 silencioso: 0 é um preço válido e ninguém revisa o que parece certo.

### NOVO-import-02 — o wizard permite duas colunas para o mesmo campo, sem avisar
- **Onde:** `ImportWizard.tsx` + `applyMapping`.
- **O quê:** o mapeamento padrão de clientes já manda `Celular` **e** `Telefone` para `phone`.
  A correção desta noite impede a perda do dado, mas o conflito continua invisível: o usuário
  não sabe que duas colunas disputam um campo, nem qual vence.
- **Recomendação:** marcar o conflito no passo de mapeamento e deixar escolher qual coluna
  manda. É mudança de UI, portanto tarefa deliberada — não efeito colateral desta correção.

---

## Decisões que esperam o dono

1. **Ambiguidade do `"1.500"`** (§1, autoavaliação 1) — confirmar que milhar é a leitura certa
   para os arquivos que vocês recebem.
2. **NOVO-import-01** — o que fazer com célula não numérica em campo de preço.
3. **Correção dos dados já gravados** — o script lista suspeitos; corrigir é decisão sua, e nos
   casos sem rastro **exige o CSV original**. Não recomendo correção em lote pelo critério
   fraco: produto barato de verdade cai nele.
