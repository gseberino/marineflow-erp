# 23 — Hooks, utilitários compartilhados e higiene de build (Etapa 2, módulo 12)

Superfície: 75 hooks em `src/hooks/`, 61 libs em `src/lib/`, `src/lib/query-client.ts`, `tsconfig*.json`,
`vitest.config.ts`, `eslint.config.js`, `.github/workflows/`, e o resultado de execução real de
`npm test`, `npx tsc -b` e `npm run build`.

---

## 23.0 O que foi executado (evidência de primeira mão)

| Comando | Resultado |
|---|---|
| `npx vitest run` | ✅ **70 arquivos, 842 testes, 0 falhas**, 89 s |
| `npx tsc -b` | ❌ **16 erros de tipo** em 6 arquivos |
| `npm run build` | ✅ built in 32,43 s — com aviso de chunk (2.188 kB) |

O contraste entre a primeira e a segunda linha é o achado central deste módulo.

---

## 23.1 Achados

### [MF-AUD-043] `tsc` não passa — e não roda em lugar nenhum
- **Módulo:** Build / qualidade
- **Arquivo:linha:** `package.json:6-13` (sem script de typecheck), `.github/workflows/deploy-edge-functions.yml:12-16`
  (único workflow, com gatilho desligado), `tsconfig.json:12` (`"files": []`)
- **Categoria:** I — **Severidade:** P1
- **Descrição:** Três lacunas que se somam:
  1. **Não existe script de verificação de tipos.** `package.json` tem `dev`, `build`, `build:dev`, `lint`,
     `preview`, `test`, `test:watch` — nenhum `typecheck`.
  2. **`tsc --noEmit` sem `-b` não verifica nada**, porque o `tsconfig.json` raiz tem `"files": []` e só
     referencia os projetos. Quem rodar o comando "óbvio" recebe sucesso imediato e falso.
  3. **Não há CI.** O único workflow é de *deploy* de Edge Functions e está com o gatilho `push` comentado,
     com o motivo documentado no próprio arquivo ("falhava em TODO push porque os segredos … não estão
     configurados"). **Nenhum push roda testes, lint, typecheck ou build.**

  Consequência medida agora: `npx tsc -b` acusa **16 erros** que ninguém vê. Dois deles são bugs funcionais reais
  (MF-AUD-042 e MF-AUD-049), seis são imports de arquivos inexistentes (MF-AUD-046), dois são `Cannot find name
  'Deno'` (MF-AUD-047), e os demais são tipos frouxos em `zip.ts`, `use-service-orders.ts` e um mock de teste.

  A suíte de 842 testes, que é boa, dá uma sensação de rede de proteção que a verificação de tipos não confirma.
- **Evidência:**
  ```
  $ npx tsc -b
  16 erros:  6× TS2307 (módulo não encontrado) · 3× TS2339 · 2× TS2551 (propriedade inexistente)
             2× TS2304 (nome não encontrado)  · 1× TS2345 · 1× TS2322 · 1× TS2740
  ```
  ```json
  // tsconfig.json:12 — a razão de --noEmit não checar nada
  "files": [], "references": [{ "path": "./tsconfig.app.json" }, { "path": "./tsconfig.node.json" }]
  ```
- **Ação recomendada:** (a) adicionar `"typecheck": "tsc -b"` ao `package.json`; (b) criar um workflow de CI que
  rode `npm ci && npm run lint && npm run typecheck && npm test && npm run build` em push e PR — sem segredos,
  portanto sem o problema que derrubou o workflow existente; (c) só depois zerar os 16 erros.
  A ordem importa: corrigir sem CI significa que voltam.
- **Esforço:** M — **Decisão do Gustavo:** Não (é infraestrutura, não muda comportamento do produto).

### [MF-AUD-044] Componente de inspeção órfão importando seis módulos que não existem
- **Módulo:** Inspeção (frente inacabada)
- **Arquivo:linha:** `src/components/inspection/ServiceOrderInspectionTab.tsx:18-23`
- **Categoria:** D — **Severidade:** P2
- **Descrição:** O arquivo é o **único** da pasta `src/components/inspection/` e importa seis módulos que não
  existem no repositório: `@/lib/inspection/marine-template`, `@/lib/inspection/report-preview`,
  `@/lib/inspection/voltage-drop`, `./InspectionChecklist`, `./VoltageDropPreview`,
  `./InspectionReportPreview`. O diretório `src/lib/inspection/` **não existe**. Nenhum arquivo do projeto
  importa `ServiceOrderInspectionTab` — verificado por varredura.

  Ou seja: uma frente de trabalho (aba de inspeção/vistoria com checklist marítimo, queda de tensão e prévia de
  laudo) foi interrompida no meio, deixando a casca. O build passa porque o Vite só resolve o que está no grafo
  a partir do entry — o arquivo nunca é alcançado. Mas ele conta 16 ocorrências de texto pt-BR, entra nas buscas,
  e a próxima pessoa que abrir a pasta vai supor que existe um módulo de inspeção.
- **Evidência:**
  ```
  src/components/inspection/ServiceOrderInspectionTab.tsx(18,8): error TS2307: Cannot find module '@/lib/inspection/marine-template'
  …(19,56) '@/lib/inspection/report-preview'   …(20,40) '@/lib/inspection/voltage-drop'
  …(21,37) './InspectionChecklist'             …(22,36) './VoltageDropPreview'
  …(23,41) './InspectionReportPreview'
  ```
  ```
  $ ls src/lib/inspection → No such file or directory
  $ grep -rn "ServiceOrderInspectionTab" src --include=*.tsx  → (nenhum importador)
  ```
- **Ação recomendada:** decidir com o Gustavo: retomar a frente (e então os seis arquivos precisam ser escritos)
  ou remover o arquivo. Enquanto ficar assim, é ruído que se parece com funcionalidade.
- **Esforço:** S (remover) / L (concluir) — **Decisão do Gustavo:** Sim — a aba de inspeção/vistoria ainda está
  no plano? Note que existe um módulo de **levantamento** funcionando (`service_surveys`, `SurveyPanel`), que
  pode ter tornado esta frente obsoleta.

### [MF-AUD-045] Combobox de fornecedor busca por um campo que não existe
- **Módulo:** Financeiro / Cadastros
- **Arquivo:linha:** `src/components/PayableFormDialog.tsx:123`
- **Categoria:** A — **Severidade:** P3
- **Descrição:** `searchTerms: [s.cnpj_cpf || '', s.contact_email || '']` — a tabela `suppliers` tem `email`, não
  `contact_email` (`types.ts` §suppliers: `contact_name`, `email`, `phone`). O termo de busca por e-mail é sempre
  `''`, então digitar o e-mail do fornecedor no combobox de contas a pagar nunca encontra nada. A busca por CNPJ
  funciona, o que mascara o defeito.
- **Evidência:**
  ```
  src/components/PayableFormDialog.tsx(123,55): error TS2339: Property 'contact_email' does not exist on type '{ … }'
  ```
- **Ação recomendada:** trocar por `s.email`.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-046] Tools de Edge Function compiladas com o `tsconfig` do frontend
- **Módulo:** Edge Functions / build
- **Arquivo:linha:** `supabase/functions/_shared/ai/tools/finance-rules.ts:53,60`
- **Categoria:** H — **Severidade:** P3
- **Descrição:** `tsc -b` acusa `TS2304: Cannot find name 'Deno'` nesse arquivo — sinal de que ele está sendo
  puxado para dentro do projeto do frontend (que não tem os tipos do Deno). Só esse arquivo aparece, o que
  sugere um import cruzado pontual, não uma regra. O efeito prático: os erros de tipo das Edge Functions **não**
  são verificados de forma sistemática (o `include` do `tsconfig.app.json` é só `src`), e ao mesmo tempo um
  arquivo Deno vaza para a compilação do frontend, gerando ruído. A memória do projeto já registra a
  consequência: um bug de assinatura foi para produção porque "o `tsc` do projeto NÃO cobre `supabase/functions`".
- **Evidência:**
  ```
  supabase/functions/_shared/ai/tools/finance-rules.ts(53,18): error TS2304: Cannot find name 'Deno'.
  supabase/functions/_shared/ai/tools/finance-rules.ts(60,21): error TS2304: Cannot find name 'Deno'.
  ```
- **Ação recomendada:** rastrear o import que puxa esse arquivo para `src` (provável reuso de tipo/constante em
  teste) e cortá-lo; e adicionar `deno check` das funções ao mesmo CI proposto em MF-AUD-043.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-047] 23 arquivos de teste Deno não rodam em lugar nenhum
- **Módulo:** Testes
- **Arquivo:linha:** `vitest.config.ts:11` (`include: ["src/**/*.{test,spec}.{ts,tsx}"]`) vs 23 arquivos
  `supabase/functions/**/*_test.ts`
- **Categoria:** I — **Severidade:** P2
- **Descrição:** O Vitest só coleta `src/**`. Os 23 testes escritos em Deno — que cobrem o coração do agente
  (`agent_test`, `autonomy-policy_test`, `context-pruning_test`, `intent-router_test`, `keyword-resolver_test`,
  `memory-scope_test`, `whatsapp-channel_test`, `whatsapp-pin_test`, `inbox-detector_test`, `phone_test`), as
  regras do motor da agenda (`task-automations/rules_test.ts`), a camada de comunicação
  (`comms/{compliance-guard,exemplars,message-linter,reply-cadence,voice-profiles}_test.ts`) e três de tools —
  **só rodam se alguém digitar `deno test` manualmente**. Não há script no `package.json` nem CI. São
  provavelmente os testes mais valiosos do repositório (cobrem o que mais custa quando quebra) e são os únicos
  que ninguém executa por padrão.
  Detalhe consistente: `npx vitest run` reportou **70** arquivos, enquanto `find` encontra 71 arquivos com
  `.test.` — o 71º é `supabase/functions/_shared/ai/product-fiscal.test.ts`, fora do `include`.
- **Evidência:** `vitest.config.ts:11`; lista dos 23 arquivos; contagem 70 × 71.
- **Ação recomendada:** `"test:edge": "deno test -A supabase/functions"` no `package.json` e no CI proposto.
- **Esforço:** S — **Decisão do Gustavo:** Não.

### [MF-AUD-048] Bundle principal de 2,19 MB num único chunk
- **Módulo:** Performance
- **Arquivo:linha:** saída de `npm run build`
- **Categoria:** G — **Severidade:** P2
- **Descrição:** `dist/assets/index-*.js` = **2.188 kB** (603 kB gzip), acima do limite de aviso do Vite.
  Somando os companheiros grandes (`html2pdf` 638 kB, `generateCategoricalChart` 374 kB, `html2canvas` 201 kB),
  o primeiro carregamento é pesado — e o app é usado no celular, em marina, com 4G irregular. Já existe
  code-splitting parcial (os chunks nomeados mostram que Vite separou o financeiro em `AgingReportPanel-*`),
  então a infraestrutura está lá; falta aplicar `React.lazy` às rotas.
- **Evidência:**
  ```
  dist/assets/index-DWKcn4sy.js   2,188.14 kB │ gzip: 603.06 kB
  (!) Some chunks are larger than 500 kB after minification.
  ```
- **Ação recomendada:** `React.lazy` + `Suspense` nas rotas de `App.tsx` (o arquivo já importa ~60 páginas
  estaticamente); e import dinâmico de `html2pdf` só quando o usuário pedir um PDF. Remover as 19 páginas
  legadas (MF-AUD-037) ajuda de graça.
- **Esforço:** M — **Decisão do Gustavo:** Não.

### [MF-AUD-049] Tipagem desligada por configuração, com 1.003 `as any` como consequência
- **Módulo:** Qualidade
- **Arquivo:linha:** `tsconfig.json:2-10`, `tsconfig.app.json` (`"strict": false`)
- **Categoria:** H — **Severidade:** P2
- **Descrição:** As flags de rigor estão todas desligadas: `strict: false`, `strictNullChecks: false`,
  `noImplicitAny: false`, `noUnusedLocals: false`, `noUnusedParameters: false`. É a herança do scaffold Lovable.
  O efeito acumulado é medível: **1.003 ocorrências de `as any`** em `src/` e `supabase/functions/`, concentradas
  em `use-pdf.ts` (66), `fiscal-payload-builder.test.ts` (47), `ServiceOrderForm.tsx` (41), `FiscalEmission.tsx`
  (37), `use-quote-requests.ts` (32), `FinancialPage.tsx` (28).

  Isto não é preciosismo: a memória do projeto registra que foi exatamente um `as any` que deixou passar para
  produção o `product_name` depois do rename de colunas — o compilador saberia. E `noUnusedLocals: false` é o
  motivo de imports mortos como o de MF-AUD-019 sobreviverem.
- **Evidência:** contagem por `grep -ro "as any"`; conteúdo dos dois `tsconfig`.
- **Ação recomendada:** não ligar `strict` de uma vez (seriam centenas de erros). Ligar
  **`noUnusedLocals`/`noUnusedParameters` primeiro** (barato, pega lixo), depois `strictNullChecks` por
  diretório, começando por `src/lib` (que já é código puro e testado).
- **Esforço:** L — **Decisão do Gustavo:** Sim — vale investir em rigor de tipos ou o projeto segue no modo
  atual? A resposta define se MF-AUD-043 tem valor duradouro.

---

## 23.2 Verificações feitas que **não** produziram achado

- **`staleTime` — item do "Prompt #23" do briefing: resolvido estruturalmente.** Existe um default global
  (`src/lib/query-client.ts`: `staleTime: 60_000`, `gcTime: 5 min`, `refetchOnWindowFocus: false`), então os 28
  hooks que não declaram `staleTime` **não** estão sem cache — herdam 60 s. Outros 34 hooks declaram valores
  próprios. Não há achado aqui.
- **`useAppUsers` duplicado — item do "Prompt #23": resolvido.** Uma única definição, em
  `src/hooks/use-app-users.ts:48`.
- **`NavLink.tsx` e `mock-data.ts` — item do "Prompt #23": resolvido.** Nenhum dos dois existe; `src/data/`
  também não.
- **`useAppSettings` ausente — item do "Prompt #23": resolvido.** `src/hooks/use-app-settings.ts` exporta
  `useAppSettings()` e `useAppSetting(key, fallback)`.
- **Tratamento de expiração de sessão:** o `QueryClient` tem lógica dedicada — `isAuthError` reconhece 401/
  `PGRST301`/mensagens de JWT e dispara um `refreshSession()` **único** (guardado por `inflightRefresh`) antes de
  repetir a query. É um cuidado acima da média e evita a tempestade de refresh.
- **Bibliotecas puras bem separadas:** `os-financials.ts`, `quote-deposit.ts`, `purchase-needs.ts`,
  `quote-comparison.ts`, `route-sheet.ts`, `client-statement.ts`, `dre.ts`, `bank-parser.ts`,
  `nfe-xml-parser.ts` — todas sem dependência de React ou Supabase, todas com teste. É o melhor padrão do
  repositório e vale como referência para futuras extrações.

---

*Módulo 12 auditado. 7 achados (`MF-AUD-043`..`MF-AUD-049`). Quatro dos seis itens do "Prompt #23" citados no
briefing estão resolvidos; os outros dois viraram MF-AUD-029 (STATUS_LABELS) e MF-AUD-019 (import morto).*
