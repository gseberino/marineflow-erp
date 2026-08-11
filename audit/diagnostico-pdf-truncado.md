# Diagnóstico P1 — PDF baixado sai truncado

**Data:** 10/08/2026 · **Natureza:** somente leitura, nenhuma alteração de código
**Sintoma relatado:** orçamento baixado em produção sai **sem o fim do documento** (condições de pagamento,
termos e o que vem depois).

---

## Veredito: **B — a correção não resolve; o bug persiste na main atual**

E a causa está identificada, com linha e número: **o `html2canvas` é chamado com uma altura fixa medida ANTES
de o `html2pdf` inserir os espaçadores de quebra de página.** O documento cresce depois da medição, a captura
não acompanha, e o excedente — que é o **fim** do documento — é cortado fora.

Não é build velho (A está descartado com evidência), e não é o dado (as chaves de termos estão preenchidas,
verificado no diagnóstico anterior).

---

## 1. Hipótese A descartada: a produção **tem** a correção

O frontend **não** depende do workflow que morreu. Ele é publicado pela **integração GitHub do Vercel**: todo
push na `main` gera um deployment de produção automaticamente. O workflow `deploy-edge-functions.yml`
(desligado) só publica **Edge Functions**, que são outra coisa.

Deployments de produção relevantes (projeto `prj_yGePvK6z47Bvm1FR51bdykAP1enI`, todos `state: READY`):

| Commit | Mensagem | Deployment |
|---|---|---|
| `d6edee9` | merge: CSS do PDF escopado + quebra de página | `dpl_5Doaohat…` |
| `31111a6` | merge: impressão sem erro + **paginação medida no PDF baixado** | `dpl_JAsUSaJP…` |
| `85523f7` | Merge branch 'session/otimizacao-tokens' | `dpl_Frj6x8B7…` ← **produção atual** |

Verificação de ancestralidade contra o build em produção:
```
$ git merge-base --is-ancestor <commit> 85523f7
14f4af6    SIM, está no build de produção
e957937    SIM, está no build de produção
31111a6    SIM, está no build de produção
d6edee9    SIM, está no build de produção
```

**Conclusão:** o usuário testou uma build que já contém as duas correções. O bug é atual.

> Nota de contexto: a `main` local está **10 commits à frente** do último deployment (trabalho das posições 1 e
> 2 de hoje, ainda sem push). Isso não afeta este diagnóstico — nenhum desses commits toca o PDF.

### Sobre o workflow de deploy que morreu (pedido no passo 1)

`.github/workflows/deploy-edge-functions.yml` está com o gatilho `push` comentado desde 22/07, porque falhava
em todo push por falta de `SUPABASE_ACCESS_TOKEN` e `SUPABASE_PROJECT_ID`. **Para reativar com segurança:**

1. criar os dois segredos em *Settings → Secrets and variables → Actions*
   (`SUPABASE_PROJECT_ID = okurngvcodmljjicopdp`; o token é pessoal do Supabase);
2. descomentar o bloco `push:` com `paths: ['supabase/functions/**']`, que já está escrito lá;
3. **antes de ligar**, decidir o que fazer com as funções que hoje só existem no deploy — um
   `supabase functions deploy` sem argumento publica **todas** as do repositório, e há 10 funções ACTIVE em
   produção sem fonte local (MF-AUD-055). Ligar sem resolver isso não apaga nada, mas cristaliza a divergência.

**Isso não é urgente para o PDF** — o frontend nunca dependeu desse workflow.

---

## 2. A cadeia causal, provada por leitura de código

### 2.1 Nosso código mede a altura e a congela

`src/lib/pdf-generator.ts`:

```ts
// :339-368  — paginação medida: insere as marcas de quebra no DOM
const alvoDaPaginacao = container.querySelector('.container') ?? container;
const filhos = Array.from(alvoDaPaginacao.children)…
for (const i of planPageBreaks(blocos).reverse()) {
  const marca = document.createElement('div');
  marca.className = 'html2pdf__page-break';
  filhos[i].parentNode?.insertBefore(marca, filhos[i]);
}

// :380 — altura medida AQUI. As marcas são divs vazias: não somam altura.
const captureHeight = container.scrollHeight;

// :405-425 — e é congelada nas opções do html2canvas
html2canvas: { scale, width: A4_WIDTH_PX, height: captureHeight,
               windowWidth: A4_WIDTH_PX, windowHeight: captureHeight, … }
```

### 2.2 O html2pdf então **acrescenta altura** ao documento

`node_modules/html2pdf.js/dist/html2pdf.js`, plugin de pagebreak — roda em `toContainer()`, **antes** da captura:

```js
// :373 — no modo legacy, a marca recebe quebra DEPOIS dela
after: mode.legacy && legacyEls.indexOf(el) !== -1,

// :420-428 — e a quebra é implementada inserindo uma DIV DE PADDING no DOM
if (rules.after) {
  var pad = createElement('div', { style: {
    display: 'block',
    height: pxPageHeight - clientRect.bottom % pxPageHeight + 'px'   // até uma página inteira
  }});
  el.parentNode.insertBefore(pad, el.nextSibling);
}
```

Cada quebra insere um espaçador de **até 1031 px**. Com N quebras, o documento fica até N × 1031 px mais alto
do que era quando `captureHeight` foi medido.

### 2.3 A captura não acompanha

```js
// :771-775 — as opções são repassadas COMO ESTÃO, com o height congelado
var options = Object.assign({}, this.opt.html2canvas);
delete options.onrendered;
return html2canvas(this.prop.container, options);
```

O `html2canvas` recebe `height: captureHeight` e captura exatamente isso. **Tudo que os espaçadores empurraram
para além dessa altura fica de fora da imagem** — e como o empurrão é sempre para baixo, o que se perde é
sempre o **fim** do documento.

### 2.4 Por que o sintoma é "sumiu o fim", e não "cortou no meio"

O tamanho do corte ≈ soma dos espaçadores ≈ o espaço em branco que sobra no pé de cada página. Num documento de
2 páginas (1 quebra), some do fim um trecho equivalente ao branco do pé da página 1. Em 3 páginas, o dobro.

**Previsão verificável:** documento de **1 página** (nenhuma quebra, nenhum espaçador) **não trunca**. O defeito
só aparece com 2+ páginas, e piora com o comprimento. É exatamente o que o passo 3 pedia para determinar.

---

## 3. Ordem dos blocos finais — o que se perde primeiro

Sequência de blocos de primeiro nível no fim do orçamento (`pdf-generator.ts:1195-1254`):

```
… itens e totais
buildPaymentSection            ← condições de pagamento
buildPaymentHistorySection     ← histórico de pagamentos
financial_notes                (card, se houver)
dados bancários / PIX          (card, se showBankDetails)
assinaturas                    (grid, margin-top:40px)
photoGallery                   (se houver fotos)
TERMOS                         ← "Condições Gerais e Garantia"
<footer>                       ← MarineFlow ERP · Documento Digital Autenticado
```

O relato do usuário ("sem condições de pagamento, termos, etc.") indica corte **a partir do bloco de
pagamento** — ou seja, um truncamento grande, compatível com documento de 3+ páginas ou com várias quebras.

Isto também **reabre o MF-AUD-014 / hipótese #2 do briefing** com outra explicação: os termos são o penúltimo
bloco. O relato antigo de "os termos não aparecem" provavelmente **sempre foi este mesmo defeito**, e não a
preferência global — que já havia sido descartada (`showTerms: true` nos dois tipos). Ver `diagnostico-terms.md`,
que ficou sem causa: **esta é a causa.**

---

## 4. Reprodução: o que fiz e o que não fiz

**Não automatizei com navegador headless, e não vou dizer que automatizei.** O caminho exigiria subir o app,
autenticar com conta real e navegar até um orçamento com conteúdo — e a instrução era não alterar
`package.json` (Playwright não está instalado; `npx playwright` baixaria browser e escreveria em disco fora do
escopo). Diante do custo, priorizei a prova por código, que é determinística e não depende de ambiente.

**Procedimento manual exato para confirmar (2 minutos):**

1. Abrir um orçamento **longo** (com itens suficientes para 2+ páginas) em produção.
2. Ações → **Baixar** (não Imprimir — imprimir usa outro caminho, paginado pelo navegador, e não tem o defeito).
3. Abrir o PDF e ir ao fim. Esperado com o bug: o documento acaba antes do rodapé
   "MarineFlow ERP · Documento Digital Autenticado".
4. **Teste de controle:** repetir com um orçamento **curto** (1 página). Previsão: sai completo, com rodapé.
   Se o curto sair completo e o longo truncado, a cadeia da §2 está confirmada ponta a ponta.
5. Opcional, no console do navegador antes de baixar: `document.querySelectorAll('.html2pdf__page-break').length`
   não serve (as marcas só existem durante a geração). O sinal indireto é o aviso
   `[generatePDFBlob] documento longo (Npx)` no console, que mostra o `captureHeight` usado.

---

## 5. Hipótese de correção (não implementada — este é um diagnóstico)

Três caminhos, do mais direto ao mais estrutural:

1. **Não congelar a altura.** Remover `height`/`windowHeight` das opções do `html2canvas` e deixar o
   html2canvas medir o container no momento da captura, já com os espaçadores. É a mudança de menor superfície.
   Risco: aquelas opções foram postas de propósito ("garante que o html2canvas capture o conteúdo de largura
   cheia a partir da origem — sem clipping à direita"), então precisa de teste nos dois eixos.
2. **Não usar o `legacy`.** Como já calculamos as quebras com as alturas medidas, dava para inserir nós mesmos
   os espaçadores **antes** de medir `captureHeight`, e tirar `legacy` do `pagebreak.mode`. Aí a altura medida
   já inclui tudo, e o html2pdf não mexe mais no DOM.
3. **Paginar de verdade**, gerando uma página por vez em vez de fatiar uma imagem única. É a solução correta a
   longo prazo e a mais cara.

A opção 2 me parece a melhor relação custo/risco: mantém o controle que a correção de ontem conquistou e
elimina a mutação do DOM que ninguém está medindo.

**Cuidado para quem for corrigir:** há um segundo problema no `legacy`, latente. O loop
(`html2pdf.js:369`) percorre `root.querySelectorAll('*')` e usa `getBoundingClientRect()` de cada elemento —
mas vai **inserindo espaçadores durante o próprio loop**, o que invalida as coordenadas dos elementos
seguintes. Com uma quebra só o efeito é pequeno; com várias, as posições calculadas depois da primeira já estão
erradas.

---

## 6. Achado registrado

**NOVO-007** — o defeito desta análise, em `audit/novos-achados.md`, com a ressalva de que ele
**provavelmente explica também** o sintoma dos termos que ficou sem causa em `diagnostico-terms.md`.
