# Turno da noite — 10→11/08/2026

## Resumo executivo

1. **Nada foi para produção.** Sem migration aplicada, sem deploy, sem merge na main, sem emissão fiscal, `active_environment` intocado. Quatro branches no GitHub esperando PR.
2. **Não consegui abrir os PRs:** o `gh` não está autenticado nesta máquina e autenticar exige fluxo interativo. Cada tarefa abaixo traz o link "Abrir PR" e o corpo pronto para colar — um clique e um Ctrl+V cada. Rodar `gh auth login` uma vez destrava as próximas noites.
3. **Duas das seis tarefas já estavam feitas** e a fila não sabia: MF-AUD-043 está completo em `origin/main` (0 erros de `tsc` hoje) e a RLS do MF-AUD-020 **já foi aplicada em produção em 10/08**. Não refiz nem inventei diff.
4. **Ordem sugerida de revisão:** (1) `fix/mf-aud-009-cascata-recebiveis` — é dinheiro e corrige um furo real; (2) `feat/f2-ui-financeiro` — mexe nas duas telas mais usadas; (3) `test/mf-aud-020-rls` — só testes, risco zero; (4) `feat/nfse-nacional` — o maior, mas travado pela contabilidade de qualquer forma.
5. **MF-AUD-009 (o mais importante):** o agente alterava itens de OS e o título a receber ficava com o valor antigo — e dava para derrubar o total abaixo do que o cliente já pagou, algo que a tela recusa. Corrigido extraindo a fórmula para um módulo puro que tela e agente compartilham, em vez de escrevê-la duas vezes.
6. **F2-UI:** Extrato e Conciliação viraram rotas de verdade, com os `?tab=` antigos redirecionando. Entreguei **3 das 4 abas** da Conciliação.
7. **MF-AUD-020:** o que faltava não era a migration, eram os **testes** — não existia nenhum. Entreguei o teste real (precisa de banco) e uma guarda que roda no CI e falha se uma migration futura apagar a barreira do técnico.
8. **F-NFSE-03:** verbos fiscais com herança, prontos e **vazios de propósito** — nenhum código de tributação foi inventado por mim.

### Três decisões esperando você

| # | Decisão | Por que travou |
|---|---|---|
| **1** | **NOVO-014** — `iss_withheld` deve herdar do verbo? | A coluna é `not null default false`, então o `COALESCE` nunca alcança o verbo. Fazer funcionar exige dizer o que significam os `false` que já existem — **retenção tributária**, não schema. |
| **2** | **NOVO-015** — a aba "Sugeridas" da Conciliação | Exige fixar tolerância de valor, janela de data e se o casamento vira estado gravado. Palpite errado casa recebível com o depósito do cliente errado. |
| **3** | **MF-AUD-009** — fossilizar a fórmula em SQL? | Daria atomicidade real (hoje RPC + updates não são atômicos). Custo: a regra passa a viver em dois idiomas. Proposta detalhada na seção 5. |

E três pendências antigas continuam de pé: classificação de **"MÃO DE OBRA"** (NOVO-012), os
**códigos da contabilidade** (comece por `instalacao`, 44% do faturado) e o **percentual da
faixa do Simples** (`nfse_total_tax_rate_sn`), que bloqueia a primeira NFS-e sozinho.

---

> Daqui em diante é o diário, em ordem de execução.
---

## ⛔ Bloqueio que afeta TODA a fila: `gh` não está autenticado

```
$ gh auth status
You are not logged into any GitHub hosts.
$ echo $GH_TOKEN $GITHUB_TOKEN
(vazio)
```

**Consequência:** não consegui rodar `gh pr create` em nenhuma tarefa. Autenticar exige um
fluxo OAuth interativo, que não posso executar sozinho — e não vou ler `.git-credentials`
nem qualquer store de credencial para contornar (regra de segurança do CLAUDE.md).

**O que fiz no lugar:** todo trabalho está **commitado e com o branch no GitHub**. Cada tarefa
abaixo traz o link "Abrir PR" e o **corpo do PR pronto para colar**. Abrir cada um é um clique
mais um Ctrl+V.

**Para destravar as próximas noites:** `gh auth login` uma vez, no seu terminal.

---

## 1. [F-NFSE-03] Cadastro fiscal por verbo, com herança ✅

| | |
|---|---|
| **Status** | Pronto para revisão |
| **Branch** | `feat/nfse-nacional` (pushado) |
| **Commit** | `b7d66a8` |
| **Abrir PR** | https://github.com/gseberino/marineflow-erp/pull/new/feat/nfse-nacional |
| **Gates** | tsc 0 · vitest 951 · deno 267 · build OK |
| **Produção** | **nada aplicado** — migration commitada e não executada |

### O que mudou em relação ao desenho aprovado, e por quê

Você aprovou "tabela `service_fiscal_verbs` (10 verbos) + `services.fiscal_verb` com FK".
Implementei exatamente isso, com **uma diferença de forma** que só apareceu com o código na mão:

**O catálogo de verbos já existia.** `service_verbs` está no banco desde 03/08, com os mesmos
dez slugs, `name` e `is_fieldwork` — e `services.service_verb` já é FK dele. A proposta da
F-NFSE-02 não sabia disso e desenhou uma tabela do zero.

Então `service_fiscal_verbs` **estende** `service_verbs` (a PK *é* a FK) em vez de repetir os
dez slugs. Se eu tivesse seguido ao pé da letra, ficariam duas fontes para a mesma verdade:
renomear um verbo em uma tabela e não na outra é o tipo de divergência que só aparece quando a
nota sai errada. O nome da tabela, a contagem de linhas e o campo `services.fiscal_verb` são os
que você aprovou.

**O que confirmou que `fiscal_verb` precisa ser coluna separada:** o verbo operacional decide o
roteiro do técnico, o fiscal decide o código de tributação. Se fossem a mesma coluna, "MÃO DE
OBRA" obrigaria a escolher entre quebrar o roteiro dela ou aceitar o código fiscal duvidoso.
Separadas, ela fica operacionalmente classificada e fiscalmente em branco — que é a verdade.

### Gate de decisão encontrado: `iss_withheld` não consegue herdar (NOVO-014)

`services.iss_withheld` é `not null default false`. Como **toda** linha já tem `false` gravado,
um `COALESCE(serviço, verbo)` nunca alcançaria o verbo — a herança existiria no código e não
valeria nada.

Fazer funcionar exige dizer o que significam os `false` que já existem: decisão explícita de
"sem retenção", ou campo nunca preenchido? **Isso é decisão de retenção tributária, não de
schema** — retenção errada muda quem recolhe o imposto. Não adivinhei.

**Como ficou:** os outros quatro campos herdam normalmente; `iss_withheld` continua valendo o
do serviço, exatamente como hoje. Documentado na migration, no espelho TS, e travado por teste
nos dois lados. Registrado como NOVO-014.

### O que fica esperando você

1. **Conferir a classificação de "MÃO DE OBRA"** (NOVO-012) — sai sem verbo fiscal de propósito.
2. **Códigos da contabilidade**, começando por `instalacao`: sozinho é 44% do faturado.
3. **Decidir o NOVO-014** (acima).
4. Ao aplicar a migration: regenerar `src/integrations/supabase/types.ts` e trocar o `db`
   destipado de `use-service-fiscal.ts` por `supabase` — está marcado com ⚠ no arquivo.

Segue bloqueando a primeira emissão, independente disto: `nfse_total_tax_rate_sn` (percentual
da faixa do Simples, E0712).

<details>
<summary><strong>Corpo do PR — copiar e colar</strong></summary>

> **Nada foi aplicado em produção.** A migration está commitada e **não executada**. As dez
> linhas de verbo nascem com os campos fiscais **nulos** — os códigos vêm da contabilidade,
> que ainda não respondeu. Nenhum código de tributação foi inventado.

## O que este PR faz

Dá ao serviço o mesmo mecanismo de herança fiscal que o produto já tem, trocando a chave: onde
o produto herda da **categoria**, o serviço herda do **verbo**.

| | |
|---|---|
| `service_fiscal_verbs` | 10 linhas (uma por verbo), campos fiscais **nulos** |
| `services.fiscal_verb` | FK nova; backfill vincula 242 serviços |
| `resolve_service_fiscal` | `COALESCE(próprio, verbo)` em SQL |
| `_shared/fiscal/service-fiscal.ts` | o mesmo, em TS, para o `fiscal-emit` |
| `v_services_fiscal_efetivo` | código efetivo + procedência, para a tela |

## Por que verbo, e não categoria

A tarefa original pedia backfill "por categoria", no padrão dos produtos. O levantamento da
F-NFSE-02 mediu antes de propor:

```
services.service_verb    242 de 243 (99,6%)
services.service_system  236 de 243 (97%)
services.category          5 de 243 (2%)   ← um backfill aqui atinge CINCO serviços
```

E não é só disponibilidade de dado: **a LC 116 organiza serviço por atividade**, não por
sistema. "Instalação de sistema elétrico" e "instalação de refrigeração" são o mesmo item da
lista. O verbo é a chave por natureza; estar preenchido em 242 de 243 confirma a escolha.

## Duas decisões de desenho que fugiram da proposta — e por quê

**1. `service_fiscal_verbs` estende `service_verbs`; não repete o catálogo.** A proposta
desenhou uma tabela nova com os dez slugs. Ao implementar, descobri que **o catálogo já existe
desde 03/08** e que `services.service_verb` já é FK dele. Duas tabelas com os mesmos dez slugs
dariam duas fontes para a mesma verdade. Aqui a PK **é** a FK.

**2. `services.fiscal_verb` é coluna separada de `services.service_verb`.** O verbo operacional
decide o **roteiro do técnico**; o fiscal decide o **código de tributação**. O caso que força a
separação já existe: "MÃO DE OBRA" (R$ 12.000) está em `logistica`, classificação que o
NOVO-012 registra como suspeita. Com uma coluna só, seria escolher entre quebrar o roteiro ou
aceitar o código duvidoso. Com duas, o serviço fica **fiscalmente em branco** — que é a
verdade. O backfill pula essa linha, como combinado.

## ⚠ Gate: `iss_withheld` não herda (NOVO-014)

A coluna é `not null default false`. Como toda linha já tem `false`, um `COALESCE` **nunca
alcançaria o verbo**. Distinguir "explicitamente sem retenção" de "nunca preenchido" é
**decisão de retenção tributária**, não de schema. Os outros quatro campos herdam;
`iss_withheld` continua valendo o do serviço, e o teste trava esse comportamento nos dois lados.

## Como a paridade SQL ↔ TS é garantida

O teste lê a migration, extrai os pares `COALESCE` e falha se a ordem divergir do TypeScript.
**Provei que ele pega:** invertendo um `coalesce(s.cnae, f.default_cnae)`, o teste falha.

Sendo honesto sobre o limite: isso **não** é rodar as duas implementações lado a lado — para
isso precisaria de um banco. Pega a divergência que de fato acontece (inverter um lado e
esquecer o outro); não pega diferença de semântica do Postgres em runtime.

## Antes de aplicar

1. Conferir a classificação de **"MÃO DE OBRA"** (NOVO-012).
2. Códigos da contabilidade, **`instalacao`** primeiro: 44% do faturado.
3. Aplicar a migration, **regenerar os tipos** e trocar o `db` destipado por `supabase`.
4. Decidir o NOVO-014.

## Gates

`tsc -b` 0 erros · vitest **951** · deno test **267** · build OK

</details>

---

## 2. [MF-AUD-020] RLS do financeiro por cargo ⚠ **já estava aplicada**

| | |
|---|---|
| **Status** | A tarefa pedida já existia. Cobri a lacuna real: testes |
| **Branch** | `test/mf-aud-020-rls` (pushado) · **Commit** `fd94699` |
| **Abrir PR** | https://github.com/gseberino/marineflow-erp/pull/new/test/mf-aud-020-rls |
| **Gates** | tsc 0 · vitest 911 |

**A fila estava desatualizada.** O pedido foi "PREPARAR APENAS: migration idempotente + testes
RLS + coerência do tool-gate. NÃO aplicar." Mas a migration `20260810113036_tecnico_nao_ve_financeiro`
**já foi aplicada em produção em 10/08**, e a coerência do tool-gate já tinha sido feita na T1.5.

Duas diferenças em relação ao enunciado, para você saber:

- O predicado no banco chama-se **`is_technician`**, não `is_admin_or_financial`. A regra é a
  mesma (técnico barrado; admin/financeiro plenos) — só o nome difere, e ele nega em vez de
  afirmar. Renomear agora exigiria reescrever cinco políticas em produção sem ganho nenhum.
- `payables` recebeu a barreira por `ALTER`, preservando a regra de categoria sensível da T1.4.

**O que de fato faltava eram os testes** — não existia nenhum. Entreguei dois:

1. `supabase/tests/rls_tecnico_financeiro.sql` — o teste de verdade. Cria técnico e admin,
   troca o JWT e conta linhas nas cinco tabelas. Roda dentro de transação que termina em
   `ROLLBACK`, então é seguro até em produção. **Precisa de banco — não roda no CI.**

   ```
   supabase db query --linked -f supabase/tests/rls_tecnico_financeiro.sql
   ```

   Testa as **duas direções**: técnico vê zero **e** admin ainda vê. Sem a segunda metade, uma
   política que bloqueasse todo mundo passaria no teste e derrubaria o financeiro inteiro. E
   avisa quando a tabela está vazia, em vez de contar "0 visíveis" como prova.

2. `src/test/rls-financeiro-tecnico.test.ts` — guarda estática, roda no CI sem banco. Lê as
   migrations, acha a **última** que mexeu em cada política e falha se o predicado tiver
   perdido a barreira. **Simulei a regressão** (uma migration futura reescrevendo
   `authenticated_all_payments` sem o predicado): o teste falha e **nomeia o arquivo culpado**.

O risco é concreto, não hipotético: `ALTER POLICY` substitui o predicado inteiro. Quem mexer
nessas políticas por outro motivo e escrever o `USING` do zero apaga a barreira sem perceber.

---

## 3. [MF-AUD-043] Typecheck + CI ✅ **já estava pronto, nada a fazer**

Confirmei as três partes em `origin/main`, uma a uma:

| Pedido | Estado |
|---|---|
| script de typecheck no `package.json` | ✅ `"typecheck": "tsc -b"` |
| corrigir os 16 erros do `tsc -b` | ✅ `npx tsc -b` acusa **0** hoje |
| step de CI | ✅ job "Gates bloqueantes", step Typecheck |

Commits `55b2f03` (T2.1/T2.2) e `87a18ea`. **Nenhum branch novo, nenhum commit** — não havia o
que fazer, e inventar mudança aqui só criaria diff para você revisar à toa.

⚠ **Um commit solto:** `87a18ea` ("separa o lint do CI em workflow próprio") está no branch
`session/noturno` e **não foi integrado à main**. Não é meu; não toquei nele. Vale decidir se entra.

---

## 4. [F2-UI] Extrato ≠ Conciliação ✅ (3 das 4 abas)

| | |
|---|---|
| **Status** | Pronto para revisão, com uma aba a menos — ver gate |
| **Branch** | `feat/f2-ui-financeiro` (pushado) · **Commit** `ddd13ff` |
| **Abrir PR** | https://github.com/gseberino/marineflow-erp/pull/new/feat/f2-ui-financeiro |
| **Gates** | tsc 0 · vitest 919 (14 novos) · build OK |

Entregue conforme as decisões confirmadas:

- **`/v2/financial/extrato`** — fila única, mecânica da Caixa de entrada, abas
  **Conta bancária · Cartão · Fora da fila**. Créditos entram.
- **`/v2/financial/conciliacao`** — parte dos lançamentos, abas **Sem par · Casadas ·
  Fechamento**. O `FechamentoPanel` mudou de endereço, não de comportamento.
- **Redirects** dos cinco `?tab=` antigos (`inbox`, `cartoes`, `ignoradas`, `reconciliation`,
  `fechamento`), com teste para cada um. Sem isso, meses de links salvos e favoritos abririam a
  Visão Geral — sem erro, sem aviso, só no lugar errado.
- **As abas saíram** da tela financeira: manter aba além da rota daria dois caminhos para o
  mesmo destino, que é exatamente a confusão que se veio desfazer.
- **Menu lateral** aponta para as rotas reais.

### Gate: a aba "Sugeridas" não entrou (NOVO-015)

O desenho previa quatro abas. Entreguei três. **O motor de sugestão não existe** — o que há
hoje é ordenação de candidatos por proximidade de valor, dentro do fluxo de "sem par", que é
outra coisa: ajuda a escolher depois que a pessoa já abriu o lançamento, não propõe casamento.

Definir "sugestão" exige fixar tolerância de valor, janela de data, o que fazer com múltiplos
candidatos e se o casamento vira estado gravado. É decisão sobre conciliação de dinheiro, e um
palpite errado casa recebível com o depósito do cliente errado.

Não deixei a aba vazia de propósito: abriria sem nada para sempre e ninguém saberia se é falta
de dado ou falta de recurso. **Há teste travando a ausência dela.**

### Cinco testes mudaram — e não foi afrouxamento de gate

Travavam a estrutura **antiga** (abas em `FinancialV2`, menu com `?tab=inbox`). Cada um foi
reescrito para travar a **nova**, e acrescentei um que **falha se alguém reintroduzir**
Extrato/Conciliação como aba. A intenção de cada teste continua coberta — em alguns casos por
dois testes onde havia um.

`BankReconciliation` continua desmontada da v2; o arquivo fica até a F4, como combinado. Ela
segue montada na tela **legada** (`/financial?legacy=1`) — não mexi ali: o corte das telas
legadas é a decisão #2, ainda pendente com você.

---

## 5. [MF-AUD-009] Cascata de recebíveis no caminho do agente ✅

| | |
|---|---|
| **Status** | Pronto para revisão |
| **Branch** | `fix/mf-aud-009-cascata-recebiveis` (pushado) · **Commit** `556a891` |
| **Abrir PR** | https://github.com/gseberino/marineflow-erp/pull/new/fix/mf-aud-009-cascata-recebiveis |
| **Gates** | tsc 0 · vitest 914 (10 novos) · deno 267 · build OK |

Havia dois caminhos para mudar o valor de uma OS, fazendo coisas diferentes: pela tela,
bloqueava abaixo do já pago e redistribuía os pendentes; pelo agente, a RPC atualizava
`service_orders` e parava. Nenhum trigger cobria a lacuna — o único que toca recebíveis dispara
na *conclusão* da OS, não em mudança de item.

**A correção não foi escrever a fórmula de novo.** A aritmética saiu de dentro de
`updateReceivableFromSO` e virou módulo puro que os dois caminhos usam. Escrever uma segunda
cópia repetiria exatamente o bug que originou a lib `quote-deposit`.

Três pisos, com teste para cada: agregado (bloqueia e não grava nada), título quitado não
encolhe, e nenhum título isolado cai abaixo do que já foi pago nele.

O bloqueio **não** é best-effort no agente: recalcular total continua tolerante a falha,
derrubar a OS abaixo do já pago não — senão a mesma operação é recusada para uma pessoa e
aceita para a IA. A trilha de auditoria passa a ser gravada também pelo agente.

### Proposta que espera decisão sua: fossilizar a fórmula em SQL

O que este commit **não** resolve, e está dito no código: a sequência `recalc_so_totals` +
updates **não é atômica**. Se o update do recebível falhar, a OS fica com o total novo e o
recebível com o antigo — que é o estado de hoje, não uma regressão introduzida agora.

A cura é mover a cascata para dentro de uma função SQL, junto com o recálculo, numa transação
só. Esboço:

```
create or replace function public.recalc_so_totals_com_cascata(so_id uuid)
returns jsonb language plpgsql security definer set search_path = public as ...
  perform public.recalc_so_totals(so_id);        -- peças, serviços, taxa, deslocamento
  -- piso agregado: RAISE aborta a transação INTEIRA, incluindo o recálculo
  if (novo grand_total) < (soma de paid_amount dos recebíveis ativos) - 0.01
     then raise exception 'Total abaixo do já pago';
  -- redistribuição proporcional dos pendentes, com piso individual
```

**Ganho:** atomicidade real, e uma fórmula só valendo para tela, agente e qualquer caminho
futuro (import de XML, integração bancária). **Custo:** a regra passa a viver em dois idiomas, e
o teste de paridade fica mais frágil que o de hoje (hoje são duas cópias de TypeScript rodando
lado a lado com as mesmas entradas; com SQL, viraria leitura de arquivo).

**Não criei arquivo de migration de propósito.** Migration dentro de `supabase/migrations/` é
aplicada pelo próximo `db push` de quem passar, e este repositório já tem histórico disso (35
migrations aplicadas sem arquivo — MF-AUD-058). Proposta que vira arquivo deixa de ser proposta.

---

## 6. CashForecastPanel na V2 — **não iniciado**

Era condicional ("se sobrar noite") e a noite não sobrou. **Nada começado, nada pela metade,
nenhum branch.** Continua inteiro para a próxima.

---

## Achados novos registrados (regra 3)

| ID | O quê | Onde |
|---|---|---|
| **NOVO-014** | `services.iss_withheld` é `not null default false` e por isso não consegue herdar do verbo | `audit/novos-achados.md`, branch `feat/nfse-nacional` |
| **NOVO-015** | A aba "Sugeridas" da Conciliação não tem motor por trás | `audit/novos-achados.md`, branch `feat/f2-ui-financeiro` |

---

## Nada foi para produção

Confirmado, item por item: **nenhuma migration aplicada** (a do F-NFSE-03 está commitada e não
executada), **nenhum deploy** de edge function, **nenhum merge na main**, **nenhuma emissão
fiscal**, `active_environment` **intocado**. Os quatro branches estão no GitHub aguardando PR.
