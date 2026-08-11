# [F-NFSE-02] Cadastro fiscal dos serviços — levantamento e proposta

**Data:** 10/08/2026 · **Status:** proposta, NADA executado · **Gate:** aplicação é decisão do Gustavo,
com os códigos que a contabilidade devolver.

---

## 1. O que os últimos 12 meses mostram

| | |
|---|---:|
| Linhas de serviço em OS não canceladas | 122 |
| OS envolvidas | 45 |
| **Serviços distintos do catálogo usados** | **64** |
| Linhas avulsas, sem `service_id` | 34 |
| Total faturado em serviço | **R$ 178.197,53** |
| Período com dado real | 07/04/2026 a 07/08/2026 |

**O catálogo tem 243 serviços ativos, mas só 64 foram usados.** O backfill não precisa cobrir 243 —
precisa cobrir 64, e na prática muito menos: os **12 primeiros concentram R$ 105 mil dos R$ 178 mil**
(59%).

As **34 linhas sem `service_id`** são digitadas à mão na OS. Elas não têm cadastro para receber código
e vão continuar exigindo escolha manual na emissão — a menos que virem serviço de catálogo. Vale
saber disso antes, porque nenhum backfill as alcança.

### Os 12 que pagam a conta

| # | Serviço | Vezes | Faturado | Sistema · Verbo |
|---:|---|---:|---:|---|
| 1 | Instalação e configuração de gerenciamento de energia — Victron | 4 | R$ 25.604 | eletrico_dc · instalacao |
| 2 | Diagnóstico e reparação de módulos eletrônicos Seakeeper | 1 | R$ 16.890 | eletronico · reparo |
| 3 | Mão de obra | 1 | R$ 12.000 | nenhum · logistica |
| 4 | Sistema personalizado de alarmes de segurança | 1 | R$ 8.900 | eletronico · instalacao |
| 5 | Instalação de parelha de motores Mercury V8 300HP | 1 | R$ 7.800 | mecanico · instalacao |
| 6 | Substituição de alto-falante e subwoofer | 2 | R$ 6.400 | eletronico · substituicao |
| 7 | Instalação de equipamentos + entrega técnica — Victron | 1 | R$ 6.240 | eletrico_dc · instalacao |
| 8 | Instalação, configuração e entrega técnica | 1 | R$ 5.500 | eletrico_dc · instalacao |
| 9 | Instalação e configuração do sistema | 2 | R$ 5.100 | eletrico_dc · configuracao |
| 10 | Substituição de baterias — chumbo para lítio | 3 | R$ 4.400 | eletrico_dc · substituicao |
| 11 | Configuração e parametrização dos equipamentos | 4 | R$ 3.900 | eletrico_dc · configuracao |
| 12 | Instalação do novo sistema elétrico LiFePO4/Usina | 2 | R$ 3.600 | eletrico_dc · instalacao |

---

## 2. O problema com "por categoria"

A tarefa pede backfill **por categoria**, no padrão que já existe para produtos. Medi antes de propor:

| Chave de agrupamento | Preenchida no catálogo ativo (243) | Valores distintos |
|---|---:|---:|
| `services.service_verb` | **242 (99,6%)** | **10** |
| `services.service_system` | 236 (97%) | ~8 |
| `services.category` | **5 (2%)** | 1 útil ("Sistema elétrico") |

**A categoria de serviço está vazia em 98% do catálogo, e não existe tabela `service_categories`.**
Um backfill por categoria hoje atingiria cinco serviços e deixaria os outros 238 exatamente como estão
— inclusive os doze que faturam.

Há ainda uma armadilha: a categoria tem **duas formas de vazio**, `NULL` e string vazia. Qualquer
agrupamento que trate só `NULL` produz um grupo fantasma.

### A chave que funciona é o VERBO — e não é só por estar preenchida

Fiscalmente, a **LC 116 organiza serviço por atividade**, não por sistema. "Instalação de sistema
elétrico" e "instalação de sistema de refrigeração" são o mesmo item da lista; "instalação" e
"reparo" do MESMO sistema são itens diferentes. Ou seja: o verbo é a chave certa por natureza, e o
fato de estar preenchido em 242 de 243 é sorte que confirma a escolha, não a razão dela.

São **10 verbos**: `adequacao, configuracao, diagnostico, instalacao, logistica, manutencao, projeto,
remocao, reparo, substituicao`. Dez linhas para a contabilidade preencher em uma sentada — contra 243.

---

## 3. Proposta

### 3.1 Espelhar o padrão dos produtos, com a chave certa

O que existe hoje para produto:

```
products.use_global_fiscal = false → valores próprios do produto
                           = true  → product_categories.default_*  →  app_settings.default_*
```

O equivalente proposto para serviço, trocando a categoria (vazia) pelo verbo (preenchido):

```
services.use_group_fiscal = false → national_tax_code/cnae/iss_rate próprios do serviço
                          = true  → service_fiscal_defaults (por verbo)  →  company_fiscal_settings
```

**Tabela nova `service_fiscal_defaults`** — uma linha por verbo:

| coluna | tipo | por quê |
|---|---|---|
| `service_verb` | text, PK | a chave; 10 linhas |
| `default_national_tax_code` | text, 6 dígitos | evita **E0310** |
| `default_service_code` | text | código municipal, informativo |
| `default_cnae` | text, 7 dígitos | |
| `default_iss_rate` | numeric | percentual |
| `default_iss_withheld` | boolean | retenção típica da atividade |
| `notes` | text | onde a contabilidade registra a justificativa do código |

**Colunas novas em `services`** — só a chave de override:

- `use_group_fiscal boolean not null default true` — o serviço herda por padrão; desmarcar é a exceção.

Os campos fiscais do serviço (`national_tax_code`, `cnae`, `iss_rate`, `iss_withheld`, `service_code`)
**já existem** — entraram na F-NFSE-01 e continuam sendo o override.

> **Por que `default true` e não `false`:** com `false`, os 243 serviços nasceriam "com valores
> próprios" vazios e o default nunca se aplicaria — o backfill não faria nada. Com `true`, preencher
> dez linhas resolve o catálogo inteiro, e quem precisar de exceção desmarca.

### 3.2 O resolvedor, espelhando `product-fiscal.ts`

Arquivo novo `_shared/fiscal/service-fiscal.ts`, **puro** (sem fetch/Deno), como o de produto — roda
no Vitest e no edge. Assinatura simétrica:

```ts
resolveServiceFiscal(
  service: ServiceFiscalInput,
  groupDefaults: ServiceFiscalDefaults | undefined,
  companyDefaults: CompanyFiscalDefaults,
): ResolvedServiceFiscal
```

O `nfse-payload-builder` passa a receber o resultado disso, em vez de ler o serviço direto. A
validação atual (E0310/E0712/E0160/E0120) continua igual e passa a valer para o valor **efetivo**.

### 3.3 Backfill proposto — o que ele faria

Uma migration em duas partes, **executada só com o seu aval e com os códigos da contabilidade**:

1. **Semeia `service_fiscal_defaults`** com as 10 linhas, valores vindos da contabilidade.
2. **Não escreve em `services`.** O default se aplica por resolução, em tempo de emissão.

> **Por que não gravar em `services`:** gravar copiaria o código para 243 linhas, e a primeira
> correção da contabilidade exigiria um segundo backfill para desfazer. Resolvido em tempo de leitura,
> corrigir uma linha de default corrige o catálogo inteiro. É a mesma razão pela qual o produto
> resolve `default_ncm` em vez de copiá-lo.

**Reversível:** apagar as 10 linhas devolve o estado atual. Nenhum dado existente é sobrescrito.

### 3.4 Candidatos de código — ponto de partida, NÃO decisão

Estes são palpites de leigo para a contabilidade confirmar ou corrigir. **Nenhum deve ser aplicado
como está** — código de tributação errado declara à prefeitura serviço que não foi prestado, e ninguém
confere isso depois de a nota estar autorizada.

| Verbo | Faturado 12m | Item da LC 116 que parece caber | Observação para a contabilidade |
|---|---:|---|---|
| `instalacao` | ~R$ 78 mil | 14.06 — instalação e montagem de aparelhos, máquinas e equipamentos | maior volume; confirmar primeiro |
| `reparo` | ~R$ 18 mil | 14.01 — manutenção e conservação de máquinas e aparelhos | |
| `configuracao` | ~R$ 13 mil | 14.01 ou 1.07 (suporte técnico) | pode divergir: é serviço técnico ou de informática? |
| `logistica` | ~R$ 12 mil | 11.04 / 26.01, ou não tributável no município | o "MÃO DE OBRA" de R$ 12 mil caiu aqui — **classificação suspeita**, ver §4 |
| `substituicao` | ~R$ 12 mil | 14.01 | |
| `diagnostico` | ~R$ 6 mil | 14.01 | |
| `projeto` | ~R$ 4 mil | 7.03 — elaboração de projetos de engenharia | exige responsável técnico? |
| `adequacao` | menor | 14.01 ou 7.02 | |
| `remocao` | menor | 14.01 | |
| `manutencao` | menor | 14.01 | |

O CNAE mais provável para o grosso é **3313901** (manutenção e reparação de motores elétricos) — o
mesmo que a própria doc da Contora usa no exemplo de Salvador. **A alíquota de ISS é de Itajaí e só a
contabilidade sabe.**

### 3.5 Filtro "sem código fiscal" na lista de serviços

Na tela de serviços, um filtro ao lado dos existentes:

- **Sem código fiscal** — `national_tax_code` nulo **e** o default do verbo também nulo. É o que
  importa: um serviço sem código próprio mas com default resolvido **não** está pendente.
- Coluna nova mostrando o código **efetivo** e de onde ele veio (`próprio` / `verbo` / `—`), como a
  tela de produtos já faz com o NCM.
- Contador no topo: "N serviços sem código fiscal" — some quando zera.

> Um filtro que olhasse só `services.national_tax_code` mostraria 238 pendentes para sempre, mesmo com
> os defaults preenchidos e tudo emitindo. Seria um alarme que ninguém pode desligar.

---

## 4. O que encontrei e NÃO corrigi (regra 3)

- **"MÃO DE OBRA", R$ 12.000, classificado como `logistica`** — a terceira maior linha de faturamento
  do período está num verbo que sugere transporte/deslocamento. Se a classificação estiver errada, o
  código fiscal sai errado junto, e é R$ 12 mil. Registrar como achado próprio.
- **34 linhas de serviço sem `service_id`** (R$ a apurar) — digitadas à mão, fora do alcance de
  qualquer backfill.
- **`services.category` com dois vazios distintos** (`NULL` e `''`) — se algum dia a categoria voltar a
  ser usada para algo, isso morde.
- **`classification_confidence`** existe na tabela e não foi consultada nesta análise; se a
  classificação por verbo tiver confiança baixa em parte do catálogo, o backfill herda o erro. Vale
  conferir antes de aplicar.

---

## 5. O que preciso de você

1. **Aval do desenho** — verbo como chave em vez de categoria, e resolução em tempo de leitura em vez
   de cópia para 243 linhas.
2. **Os códigos da contabilidade** para as 10 linhas: código nacional (6 dígitos), CNAE (7 dígitos) e
   alíquota de ISS de Itajaí. Comece por `instalacao`, que sozinho é 44% do faturado.
3. **O percentual total da faixa do Simples** (`nfse_total_tax_rate_sn`) — continua bloqueando a
   primeira emissão, independente deste backfill.

Com 1 e 2, escrevo a migration, os testes do resolvedor e o filtro. **Não aplico nada sem o item 1.**
