# Tela fiscal — decomposição em etapas (D33)

**20/09/2026** · decisão D33 aceita em 17/09 · `src/pages/FiscalEmission.tsx` tem 3.638 linhas, das
quais **3.373 estão dentro de um único componente** (`FiscalEmission()`, linhas 265–3638): 39
`useState`, 26 handlers e 10 diálogos no mesmo escopo. A extração mecânica que resolveu
`SettingsPage` (funções de topo → arquivos) **não se aplica aqui**: não há funções de topo, há um
corpo só. Este plano define o corte.

## 1. Mapa do que existe (por linha, em 20/09)

| Bloco | Linhas | O que é |
|---|---|---|
| Tipos e hooks locais | 83–263 | `DraftItem`, `DiagnosticsResult`, `AddressState`; `useCompanyFiscalSettings`, `useIssuedFiscalDocuments`, `useFiscalEnvironment`, `useFiscalDiagnostics` |
| Estado NFS-e | 352–530 | estado e handlers do padrão nacional |
| Config da empresa | 531–669 | estado do diálogo "Dados Fiscais da Empresa" |
| Diálogo de emissão | 670–702 | abertura/fechamento |
| Rascunhos | 703–1582 | carregar/salvar/aplicar rascunho, itens, impostos resolvidos, diagnóstico |
| Ações do histórico | 1583–2004 | cancelar, CC-e, exportar, baixar estoque + recebível, reenviar |
| JSX: NFS-e | 2005–2009 | `NfseSection` (já é componente) |
| JSX: Saúde Fiscal | 2010–2084 | painel de diagnóstico |
| JSX: Histórico | 2085–2257 | lista de documentos emitidos |
| Diálogo: empresa emissora | 2258–2567 | inclui bloco NFS-e (2387) |
| Diálogo: emitir NF-e | 2568–3102 | destinatário (2672), itens (2737), totais, pagamento |
| Diálogo: rascunhos | 3103–3164 | |
| Diálogo: conferir antes de emitir | 3165–3208 | |
| Diálogo: detalhes fiscais do item | 3209–3321 | |
| Diálogo: cancelar | 3322–3362 | |
| Diálogo: CC-e | 3363–3394 | |
| Diálogo: exportar XMLs | 3395–3428 | |
| Diálogo: detalhe do erro | 3429–3492 | |
| Diálogo: baixar estoque + recebível | 3493–3638 | |

## 2. Rede antes do corte (etapa 0)

- `src/test/fiscal-payload-builder.test.ts` já protege o payload da NF-e. Acrescentar:
  - smoke de render que **abre cada um dos 10 diálogos** (hoje o smoke só monta a página);
  - teste de comportamento do fluxo "rascunho → conferir → emitir" com a edge mockada (o que sai
    no `invoke('fiscal-emit')` tem que ser byte-igual antes e depois de cada etapa).
- Emissão real em **homologação** ao fim de cada etapa (depende da resposta do dono sobre usar o
  ambiente de homologação — D29 tem a mesma dependência).

## 3. Etapas, da menor para a maior (mesmo método que funcionou no formulário da OS)

Método provado em 29/07: extrair o JSX do diálogo para um componente com `props: any` e call site
`{...({} as any)}`, rodar `tsc -b`, colher TODOS os "Cannot find name" de uma vez (é a lista exata
de props), e só então escrever a interface com props obrigatórias. Byte-idêntico no JSX; estado
desce para o componente quando só ele usa.

1. **Diálogos independentes** (cada um 40–150 linhas, estado próprio pequeno): cancelar, CC-e,
   exportar XMLs, detalhe do erro, rascunhos, detalhes fiscais do item, conferir antes de emitir →
   `src/components/fiscal/dialogs/*.tsx`. Sete commits pequenos; ganho: ~600 linhas.
2. **Baixar estoque + recebível** (3493–3638) → `SettleNfeDialog.tsx`; chama a RPC
   `settle_nfe_stock_and_receivable`, que já tem teste SQL.
3. **Dados Fiscais da Empresa** (2258–2567, com o bloco NFS-e) → `CompanyFiscalDialog.tsx` +
   hook `useCompanyFiscalForm()` levando o estado de 531–669.
4. **Histórico e Saúde Fiscal** (2010–2257) → `FiscalHealthPanel.tsx` e `IssuedDocumentsTable.tsx`
   (a tabela vai para a DataTable v2, que já tem orçamento de colunas: zero scroll lateral).
5. **Emitir NF-e** (2568–3102), o maior: primeiro o **estado** vira `useNfeDraft()` (rascunhos,
   itens, impostos resolvidos, diagnóstico — 703–1582), depois o JSX vira `EmitNfeDialog.tsx` com
   subseções `RecipientSection`, `ItemsSection`, `TotalsAndPaymentSection`. Aqui a rede da etapa 0
   é obrigatória: é onde o payload nasce.
6. O que sobra na página: ~300 linhas (hooks de carga, composição das seções, roteamento de
   diálogos). Meta: `FiscalEmission.tsx` ≤ 400 linhas.

## 4. Portões
Cada etapa: `tsc -b` limpo, smoke abre o diálogo extraído, testes do payload verdes, commit próprio
com deploy automático. Etapa 5 só depois de uma emissão em homologação com o payload comparado ao
anterior.

## 5. Tamanho
Etapas 1–4: um dia. Etapa 5: um dia com a rede. Total: dois blocos de trabalho.
