# 11 — Geração de PDFs (Etapa 2, módulo 2)

Superfície auditada: `src/lib/pdf-generator.ts` (1.396 l), `src/lib/pdf-print.ts`, `src/hooks/use-pdf.ts` (2
construtores de `PDFData`), `src/components/PDFOptionsDialog.tsx`, `src/lib/document-type.ts`,
`src/components/SendViaWhatsAppDialog.tsx`, consumidores em `ServiceOrderList`, `QuoteList`, `OrdersListV2`,
`ServiceOrderForm`, e os 6 arquivos de teste de PDF em `src/lib/`.

Tipos de documento: `quote`, `service_order`, `receipt`, `invoice` (`PDFDocumentType`).

---

## 11.1 Achados

### [MF-AUD-013] O caminho de download em lote gera PDF **sem o levantamento técnico**
- **Módulo:** PDFs
- **Arquivo:linha:** `src/hooks/use-pdf.ts:240-252` (`fetchPDFData`) vs `:55-72` (`usePDFData`)
- **Categoria:** A/H — **Severidade:** P1
- **Descrição:** Existem dois construtores do mesmo `PDFData`. O hook `usePDFData` embute
  `service_surveys(... service_survey_answers(...))` no `select` e monta `survey: buildSurveyForPdf(...)`. O
  fetcher imperativo `fetchPDFData` — usado no **download em lote** e no download rápido sem diálogo
  (`ServiceOrderList.tsx:151,170`, `QuoteList.tsx:189`, `OrdersListV2.tsx:324`) — **não busca nem monta o
  levantamento**. O mesmo orçamento, baixado por dois botões diferentes da mesma tela, sai com conteúdo
  diferente. O próprio código declara a garantia oposta.

  O peso disso está no comentário do tipo (`pdf-generator.ts:76-83`): o levantamento "vai para o documento porque
  é ele que sustenta o preço diante do cliente … Sem isso o orçamento é um número sem defesa, e a conversa de
  desconto começa do zero".
- **Evidência:**
  ```ts
  // use-pdf.ts:236-237 — a promessa
  /** Standalone async fetcher — same logic as usePDFData but imperative (no React hook). */
  // Mirrors the 3-query structure of usePDFData to guarantee identical PDF output.
  ```
  ```ts
  // use-pdf.ts:61-66 — usePDFData tem o levantamento
  service_order_parts(*, products(name, sku, image_url)),
  service_surveys!service_surveys_service_order_id_fkey(
    answered_at, confidence_rationale, status,
    service_survey_answers(seq, question_snapshot, answer_value, skipped_reason, photo_path)),
  service_order_expenses(category, description, amount, paid_by),
  ```
  ```ts
  // use-pdf.ts:246-249 — fetchPDFData salta direto de parts para expenses
  service_order_parts(*, products(name, sku, image_url)),
  service_order_expenses(category, description, amount, paid_by),
  ```
  Diff automatizado dos campos montados: `survey` é o único campo de conteúdo presente num e ausente no outro.
- **Ação recomendada:** extrair um único `buildPDFData(so, settings, receivables, payments)` puro e fazer as duas
  entradas (hook e fetcher) compartilharem `select` + montagem. Cobrir com um teste que compare o resultado dos
  dois caminhos para o mesmo mock.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-014] Preferências de PDF de um usuário sobrescrevem a configuração da empresa a cada download
- **Módulo:** PDFs + Settings — **explica a hipótese #2 do briefing sem nenhum bug de renderização**
- **Arquivo:linha:** `src/components/PDFOptionsDialog.tsx:131-133`, `src/lib/pdf-generator.ts:44-55`
- **Categoria:** A/F — **Severidade:** P1
- **Descrição:** Toda vez que alguém clica em Baixar/Imprimir, o diálogo persiste o estado dos checkboxes em
  `app_settings` na chave `pdf_options_<tipo>` — uma tabela **global da empresa**, não uma preferência por
  usuário. A escrita é fire-and-forget (o retorno não é checado). Consequências:
  1. Um usuário que desmarque "Incluir termos e condições" uma única vez **desliga os termos para todos os
     usuários e para todos os PDFs futuros daquele tipo**, inclusive os enviados automaticamente por WhatsApp
     (`SendViaWhatsAppDialog.tsx:161` usa `resolvePdfOptions(appSettings, documentType)`).
  2. O mesmo vale para preços de serviços/peças, desconto, dados bancários e assinatura — a lista inteira de
     `PDFOptions`.
  3. É a explicação mais provável para "os termos não renderizam" relatado no briefing: o código está correto
     (`pdf-generator.ts:1155-1158` renderiza quando `options.showTerms && data.terms`), os termos padrão **estão
     semeados no banco** (`20260407223837_*.sql:73-89`, cinco chaves com texto pronto) e são concatenados em
     `use-pdf.ts:219-225`. O que falta verificar em runtime é o valor de `app_settings.pdf_options_quote`.
  4. Agravante de permissão: a política vigente de `app_settings` é
     `authenticated_full_access ... FOR ALL TO authenticated USING (true) WITH CHECK (true)`
     (`20260420172126_*.sql:12-16`) — qualquer usuário logado, inclusive técnico, grava configuração da empresa
     só por gerar um PDF.
- **Evidência:**
  ```ts
  // PDFOptionsDialog.tsx:130-133
  // Persist options for next time — cache local instantâneo + backend (vale em qualquer
  // dispositivo). O backend é fire-and-forget: não atrasa a geração do PDF.
  saveLocalPrefs(documentType, options);
  updateSetting.mutate({ key: BACKEND_KEY(documentType), value: JSON.stringify(options) });
  ```
  ```ts
  // pdf-generator.ts:1155-1158 — a renderização, correta
  ${options.showTerms && data.terms ? `
  ...<div ...>${esc(data.terms)}</div>
  ```
- **Ação recomendada:** separar "preferência do usuário" (localStorage, que já existe: `PREFS_KEY`) de "padrão da
  empresa" (`app_settings`, editável só em Settings por admin). Parar de gravar no backend a cada clique.
  **Antes da Fase 2, conferir o valor atual de `app_settings.pdf_options_quote` em produção** — se `showTerms`
  estiver `false`, é o achado inteiro explicado, e a correção de dado é imediata.
- **Esforço:** S — **Decisão do Gustavo:** Sim — confirmar que a intenção é padrão da empresa (admin) + override
  local por usuário, e não o comportamento atual.

### [MF-AUD-015] Validade do orçamento no PDF é contada a partir de hoje, não da emissão
- **Módulo:** PDFs
- **Arquivo:linha:** `src/lib/pdf-generator.ts:903-915` e `:576-578`
- **Categoria:** A — **Severidade:** P2
- **Descrição:** `getValidityText()` calcula `expiry = hoje + N dias` e o cabeçalho imprime
  `Emissão: ${new Date().toLocaleDateString('pt-BR')}`. O `PDFData` **tem** `serviceOrder.created_at` disponível e
  não o usa. Efeitos: (a) reimprimir um orçamento de dois meses atrás produz um documento que se declara emitido
  hoje e válido por mais 15 dias — a validade se renova sozinha a cada reimpressão; (b) o cliente que compara duas
  cópias do mesmo `ORÇ-XXXXX` vê datas diferentes; (c) o texto padrão dos termos gerais diz "válidos por 15 dias a
  partir da data de emissão" (`20260407223837_*.sql:87-88`), então o documento contradiz o próprio rodapé quando
  reimpresso.
- **Evidência:**
  ```ts
  // pdf-generator.ts:905-909
  if (!v || v.mode === 'days') {
    const days = v?.days || 15;
    const expiry = new Date();
    expiry.setDate(expiry.getDate() + days);
  ```
  ```ts
  // pdf-generator.ts:577 — cabeçalho
  Emissão: ${new Date().toLocaleDateString('pt-BR')}<br/>
  ```
- **Ação recomendada:** usar `data.serviceOrder.created_at` como base da emissão e da contagem de validade;
  manter a data de hoje só quando for uma reemissão explícita (e então rotular como "Reemitido em").
- **Esforço:** S — **Decisão do Gustavo:** Sim — é uma decisão comercial: a validade deve correr da **emissão
  original** ou de cada **reimpressão**? O código atual escolheu a segunda sem dizer.

### [MF-AUD-016] `service_orders.quote_validity_date` nunca é gravada, mas é lida em dois lugares
- **Módulo:** PDFs + Banco + Portal público
- **Arquivo:linha:** coluna criada em `supabase/migrations/20260414120109_*.sql:4`; lida em
  `src/pages/PublicServiceOrderView.tsx:420-422` e `src/lib/document-hash.ts:50`; **nenhuma escrita** em `src/`
  nem em `supabase/functions/`
- **Categoria:** J — **Severidade:** P2
- **Descrição:** Varredura completa: a coluna `quote_validity_date` só aparece em `types.ts` (gerado), no cálculo
  do hash do documento assinado e no bloco de validade da tela pública. Nenhum formulário, hook, tool de IA ou
  Edge Function a escreve — o app grava apenas `quote_validity_days` (o número). Portanto:
  - o bloco `{show.validity && order.quote_validity_date && (...)}` da tela pública **nunca renderiza**;
  - `document-hash.ts` inclui `qvd: order.quote_validity_date || ''` — um campo sempre vazio no hash de
    integridade da assinatura, o que não quebra nada mas dá falsa sensação de cobertura;
  - o trigger de re-assinatura (`20260421161411_*.sql:25`) monitora mudanças nessa coluna que nunca ocorrem.
- **Evidência:** `grep -rn "quote_validity_date" src supabase/functions` retorna apenas leituras (linhas citadas)
  e as definições em `types.ts`.
- **Ação recomendada:** decidir entre (a) passar a gravar a data absoluta no momento em que o orçamento é enviado
  — o que também resolve MF-AUD-015 e alinha PDF, tela pública e hash; ou (b) remover a coluna e as leituras.
  A opção (a) é a que a modelagem original parecia pretender.
- **Esforço:** M — **Decisão do Gustavo:** Sim — (a) ou (b).

### [MF-AUD-017] PDF depende de fonte externa carregada por rede no momento da geração
- **Módulo:** PDFs
- **Arquivo:linha:** `src/lib/pdf-generator.ts:594`
- **Categoria:** G — **Severidade:** P2
- **Descrição:** O HTML do documento faz `@import url('https://fonts.googleapis.com/css2?family=Inter...')`.
  A geração roda no cliente (`html2pdf.js`), inclusive no celular do técnico em campo — cenário para o qual o
  projeto tem PWA, `OfflineIndicator` e service worker. Sem rede (ou com Google Fonts bloqueado), o navegador cai
  na fonte de fallback, alterando métricas de texto: quebra de linha e paginação mudam em relação ao que foi
  homologado. O `@import` também é assíncrono, então há corrida com o `html2canvas`.
- **Evidência:** `src/lib/pdf-generator.ts:594` — `@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap');`
- **Ação recomendada:** embutir a fonte como `@font-face` com woff2 em base64 (ou fixar uma stack de fontes de
  sistema). Há teste de escala de canvas (`pdf-canvas-scale.test.ts`) e de isolamento de CSS
  (`pdf-css-isolation.test.ts`), o que mostra que o time já trata o pipeline como sensível.
- **Esforço:** M — **Decisão do Gustavo:** Não.

### [MF-AUD-018] `scheduled_start_at` viaja até o `PDFData` e não é usado por nenhum documento
- **Módulo:** PDFs — **status da hipótese #1 do briefing**
- **Arquivo:linha:** `src/lib/pdf-generator.ts:98` (declaração), `src/hooks/use-pdf.ts:129` e `:311` (preenchimento)
- **Categoria:** C — **Severidade:** P3
- **Descrição:** A hipótese do briefing era "`scheduled_start_at` aparece em PDFs de orçamento e deveria aparecer
  só em `service_order`". **Não se confirma no código atual**: nenhum dos quatro construtores de HTML
  (`buildServiceOrderHTML`, `buildQuoteHTML` compartilhado, `buildReceiptHTML`, `buildInvoiceHTML`) referencia o
  campo — a única ocorrência de "scheduled" em `pdf-generator.ts` é a declaração de tipo na linha 98. Ou seja, a
  correção parece ter sido feita **removendo a renderização dos dois documentos**, e o campo ficou órfão no
  contrato de dados. Vale confirmar com o Gustavo se a data agendada **deveria** voltar a aparecer no PDF de OS.
- **Evidência:** `grep -n "scheduled" src/lib/pdf-generator.ts` → apenas `98:    scheduled_start_at?: string;`
- **Ação recomendada:** ou remover o campo do tipo e das duas montagens, ou reintroduzir a renderização **apenas**
  no ramo `!isQuote`.
- **Esforço:** S — **Decisão do Gustavo:** Sim — a OS impressa deve mostrar a data agendada?

### [MF-AUD-019] Import não utilizado de `usePDFData`
- **Módulo:** PDFs
- **Arquivo:linha:** `src/components/service-order/form-parts.tsx:65`
- **Categoria:** C — **Severidade:** P3
- **Descrição:** `import { usePDFData } from '@/hooks/use-pdf';` — única ocorrência do símbolo no arquivo (947
  linhas). Sobra da decomposição do `ServiceOrderForm`. Indica também que o ESLint do projeto não está barrando
  imports não usados (ver módulo 23).
- **Evidência:** `grep -c "usePDFData" src/components/service-order/form-parts.tsx` → 1 (a linha do import)
- **Ação recomendada:** remover; e avaliar ligar `@typescript-eslint/no-unused-vars` com `varsIgnorePattern` para
  pegar a classe inteira.
- **Esforço:** S — **Decisão do Gustavo:** Não.

---

## 11.2 Verificações feitas que **não** produziram achado

- **Rotulagem orçamento × OS:** correta e testada. `documentTypeFor(status)` vive em `src/lib/document-type.ts`
  com suíte própria (`document-type.test.ts` cobre `draft → 'quote'`, todos os demais → `'service_order'`, e os
  casos `null`/`undefined`/`''`). Todos os call sites sobrescrevem o `documentType: 'service_order'` default do
  construtor (`ServiceOrderForm.tsx:210`, `QuoteList.tsx:173,182,191`, `ServiceOrderList.tsx:139,144,153,172`,
  `OrdersListV2.tsx:304,326`, `SendViaWhatsAppDialog.tsx:151-152`).
- **Termos e condições — pipeline de dados:** íntegro. Cinco chaves (`terms_general`, `terms_warranty`,
  `terms_cancellation`, `terms_delivery`, `terms_responsibilities`) semeadas com texto padrão na migration
  inicial, editáveis em `SettingsPage.tsx:31-35`, concatenadas com `\n\n` e renderizadas com `white-space:pre-wrap`.
  O único ponto de falha é a preferência global — achado MF-AUD-014.
- **Falha de impressão silenciosa:** já tratada. `pdf-print.ts` existe justamente para transformar o `return`
  mudo (pop-up bloqueado) em toast de erro, com o raciocínio documentado.
- **Cobertura de teste do módulo:** a melhor do repositório — 6 arquivos (`pdf-generator.test.ts`,
  `pdf-generator.payment-history.test.ts`, `pdf-canvas-scale.test.ts`, `pdf-css-isolation.test.ts`,
  `pdf-survey.test.ts`, `download.test.ts`) mais `document-type.test.ts`.
- **Escapamento de HTML:** todo campo vindo do banco passa por `esc()` nos construtores auditados; não encontrei
  interpolação crua de dado de usuário.

---

*Módulo 2 auditado. 7 achados (`MF-AUD-013`..`MF-AUD-019`).*
