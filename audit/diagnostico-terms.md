# Diagnóstico — "os termos e condições não aparecem no PDF"

**Data:** 09/08/2026 · **Origem:** hipótese #2 do briefing da auditoria · **Tarefa:** S3 do Adendo 01
**Natureza desta investigação:** somente leitura. Nenhum código foi alterado.

---

## Veredito

**Causa provável identificada, com uma ressalva honesta: não consegui reproduzir o sintoma para confirmá-la.**

A explicação que sobrevive a todas as verificações é a **paginação do PDF baixado**, que até hoje
(09/08/2026) fatiava o documento sem respeitar os limites dos blocos — e o bloco de termos é o **penúltimo do
documento**, a posição mais exposta a esse defeito. Essa causa **já foi corrigida** por outra frente, no commit
`e957937`, horas antes deste diagnóstico.

As três explicações mais óbvias — dado ausente, preferência desligada, divergência entre os construtores —
**foram descartadas com evidência** e devem sair de consideração.

---

## 1. O que foi descartado (com evidência)

### 1.1 As cinco chaves de termos estão preenchidas ❌ não é a causa

```sql
select key, length(value::text) as len, (value is null) as is_null,
       btrim(value::text) = '' as vazia
from app_settings where key like 'terms_%';
```
```
terms_cancellation      | 400 | false | false
terms_delivery          | 468 | false | false
terms_general           | 580 | false | false
terms_responsibilities  | 473 | false | false
terms_warranty          | 494 | false | false
```
Nenhuma nula, nenhuma vazia. Somadas com os separadores, são ~2.4 mil caracteres de texto — muito conteúdo,
o que aliás **agrava** a hipótese de paginação (§2).

### 1.2 A preferência `showTerms` está ligada ❌ não é a causa
Verificado na T0.2 do checkpoint:
```
pdf_options_quote         → {..., "showTerms":true, ...}
pdf_options_service_order → {..., "showTerms":true, ...}
```
Isto **refuta a explicação principal do MF-AUD-014**. O mecanismo descrito naquele achado (preferência de um
usuário virando padrão global a cada download) continua real e perigoso — mas **não** produziu este sintoma.

### 1.3 Limite de paginação da API sobre `app_settings` ❌ não é a causa
Hipótese: os dois construtores fazem `.select('key, value')` **sem filtro**, e se a tabela passasse do limite
padrão do PostgREST as chaves `terms_*` poderiam não vir no lote.
```sql
select count(*) from app_settings;  -- 98
```
98 linhas, muito abaixo de qualquer limite. Descartada.

### 1.4 Divergência entre os dois construtores de `PDFData` ❌ não é a causa
O MF-AUD-013 provou que `fetchPDFData` (caminho de lote) e `usePDFData` (caminho do diálogo) divergem — mas
**a divergência é no levantamento (`survey`), não nos termos.** Ambos montam `terms` do mesmo jeito, das mesmas
cinco chaves:
```
src/hooks/use-pdf.ts:219-225   (usePDFData)     terms: [get('terms_general'), get('terms_warranty'),
src/hooks/use-pdf.ts:398-404   (fetchPDFData)    get('terms_cancellation'), get('terms_delivery'),
                                                 get('terms_responsibilities')].filter(Boolean).join('\n\n')
```
Idênticos. Descartada.

### 1.5 RLS escondendo as chaves ❌ não é a causa
As políticas de `app_settings` só excluem `cron_worker_secret` (por comando) e, na RESTRICTIVE
`deny_internal_secrets`, os prefixos `cron_%` e `internal_%`. `terms_*` não é alcançado por nenhuma delas.

### 1.6 A renderização condicional está correta ❌ não é a causa
`src/lib/pdf-generator.ts:1243-1247`:
```html
${options.showTerms && data.terms ? `
<div style="margin-top:30px;padding-top:10px;border-top:1px dashed var(--pdf-border);">
  <div ...>Condições Gerais e Garantia</div>
  <div ...>${esc(data.terms)}</div>
</div>` : ''}
```
Com `showTerms: true` e `data.terms` preenchido, o bloco entra no HTML. As duas pontas estão satisfeitas.

---

## 2. A causa que sobrevive: paginação do PDF **baixado**

O documento tem dois caminhos de geração com mecânicas **completamente diferentes**, e isso é o centro do
problema. Nas palavras do commit `e957937` (de hoje, ao corrigir um sintoma vizinho):

> Ao IMPRIMIR quem pagina é o navegador, e ele respeita a regra. Ao BAIXAR, o html2canvas rasteriza o
> documento inteiro numa IMAGEM e o html2pdf fatia essa imagem em folhas A4. **Imagem não tem CSS — o corte
> cai onde calhar o pixel. Nenhuma regra de folha de estilo alcança isso.**

E, sobre o que fazia o corte errar:

> tirei o modo `avoid-all` do html2pdf, que tentava decidir sozinho onde não partir e era quem errava

**Por que isso atinge justamente os termos:** eles são o **penúltimo bloco** do documento — só o `<footer>` vem
depois (`pdf-generator.ts:1243-1254`). São também um dos blocos mais altos (~2.4 mil caracteres em fonte 8,5 px).
Um bloco alto, no fim da última folha, é exatamente o candidato a ser empurrado para fora do corte ou fatiado
num ponto que o faz sumir da vista.

**Estado após a correção de hoje** (verificado no código atual):
- a paginação passou a **medir** cada bloco antes da captura e inserir `.html2pdf__page-break`
  (`pdf-generator.ts:339-368`);
- o alvo é `container.querySelector('.container')`, e o bloco de termos **é filho direto dele** —
  `pageWrapper` monta `<div class="pdf-root"><div class="container">${body}</div></div>`
  (`pdf-generator.ts:761`), e o bloco de termos está no nível de topo do `body`. **Logo, ele é medido.**
- ele é classificado como **divisível** (`indivisivel: el.classList.contains('card') || !!el.querySelector('table')`
  — o bloco de termos não tem classe `card` nem tabela), o que é o comportamento correto: texto corrido pode
  continuar na página seguinte, ao contrário de um card de dados bancários.

Ou seja: **a mecânica que provavelmente causava o sintoma foi trocada hoje por uma que mede em vez de adivinhar.**

---

## 3. Mapa dos caminhos de geração (para o teste de confirmação)

| Caminho | Como monta o `PDFData` | Como resolve as opções | Termos? |
|---|---|---|---|
| Diálogo → **Baixar** | `usePDFData` | `PDFOptionsDialog` (estado da tela) | sujeito à paginação de imagem — **suspeito** |
| Diálogo → **Imprimir** | `usePDFData` | idem | paginado pelo navegador — **não suspeito** |
| Download **rápido** (sem diálogo) | `fetchPDFData` | `DEFAULT_PDF_OPTIONS` (`showTerms: true`) | mesmo suspeito |
| Download **em lote** | `fetchPDFData` por OS | `DEFAULT_PDF_OPTIONS` | mesmo suspeito |
| **WhatsApp** | `usePDFData` | `resolvePdfOptions(appSettings, documentType)` | mesmo suspeito |

Chamadores: `ServiceOrderList.tsx:139,144,153,172` · `QuoteList.tsx:173,182,191` ·
`OrdersListV2.tsx:304,326` · `ServiceOrderForm.tsx:2384` · `SendViaWhatsAppDialog.tsx:151-161`.

**Observação:** todos os caminhos convergem para o mesmo HTML e o mesmo `data.terms`. A diferença que importa
não é qual construtor foi usado — é **baixar × imprimir**.

---

## 4. O que eu NÃO consegui fazer, e por quê

**Não reproduzi o sintoma.** A reprodução fiel exige navegador real: `html2canvas` rasteriza o DOM e
`html2pdf` fatia o bitmap; nada disso acontece em jsdom nem em Node. Rodar isso exigiria Playwright com a
aplicação de pé e uma OS com termos — fora do escopo "somente leitura" desta tarefa (a app precisaria subir e
autenticar).

**Consequência honesta:** a causa da §2 é a mais provável e é consistente com toda a evidência, mas
**permanece não confirmada**. Não sei dizer se o sintoma que o Gustavo viu era "termos cortados ao meio",
"termos ausentes na última página" ou "documento sem a seção" — e essas três aparências têm a mesma origem
provável, mas confirmam-se de formas diferentes.

**Também não sei** por qual caminho o PDF foi gerado quando o problema foi observado (baixar? imprimir?
WhatsApp?), nem em que data — e isso muda o diagnóstico: se foi **imprimindo**, a hipótese da §2 cai, porque
nesse caminho quem pagina é o navegador.

---

## 5. Como confirmar em 2 minutos (para o Gustavo)

1. Abra um orçamento que tenha termos e clique em **Baixar**. Role o PDF **até o fim**.
2. Se a seção "Condições Gerais e Garantia" estiver lá e inteira → o defeito era a paginação, e a correção de
   hoje (`e957937`) resolveu. Encerra-se a hipótese #2.
3. Se continuar faltando → me diga **por qual caminho** (Baixar, Imprimir ou WhatsApp) e, se possível, mande o
   PDF. Com o caminho identificado, o próximo passo é instrumentar aquele caminho especificamente.

---

## 6. Achado colateral (registrado, não corrigido)

**Nenhum teste cobre os termos.** Busca por `showTerms`/`terms` em `src/lib/*.test.ts` e `src/test/*.test.ts`
não retorna nada, apesar de existirem **sete** arquivos de teste de PDF (`pdf-generator`,
`pdf-generator.payment-history`, `pdf-canvas-scale`, `pdf-css-isolation`, `pdf-survey`, `pdf-html-isolation`,
`pdf-pagination`). É barato cobrir a parte determinística: dado `showTerms: true` + `terms` preenchido, o HTML
gerado contém "Condições Gerais e Garantia" e o texto; com `showTerms: false`, não contém. Isso não testa a
rasterização — mas trava para sempre a metade do problema que é lógica pura.

Registrado como **NOVO-004** em `audit/novos-achados.md`.
