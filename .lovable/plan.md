

## Botão "Exportar diagnóstico" para acelerar a depuração

Adicionar um botão discreto no header do `AppLayout` que gera e baixa um arquivo `.json` com tudo que precisamos para diagnosticar travamentos sem depender do usuário copiar/colar console.

### O que vai no pacote

Um único arquivo `marineflow-diagnostico-{timestamp}.json` contendo:

1. **Sessão** — `authReady`, presença de `session`, `expires_at`, `user.id`, `user.role`, `user.email`, idade do token (segundos até expirar).
2. **Ambiente** — `userAgent`, `language`, `online`, `viewport`, URL atual, timezone, build mode (`import.meta.env.MODE`).
3. **Storage** — chaves do `localStorage` relacionadas ao Supabase (presença + tamanho, **sem valores** para não vazar JWT) e flags da app (`marineflow:*`).
4. **Erros recentes** — últimos ~50 erros capturados via `window.addEventListener('error')` e `'unhandledrejection'` (instalado uma vez no `main.tsx`, buffer em memória).
5. **Rede recente** — últimas ~50 chamadas `fetch` (URL, método, status, duração, `ok`) via wrapper instalado no `main.tsx`. Sem corpos de request/response.
6. **React Query** — snapshot de `queryClient.getQueryCache().getAll()`: `queryKey`, `state.status`, `state.fetchStatus`, `dataUpdatedAt`, `errorUpdatedAt`, `error?.message`. Sem `data`.
7. **Audit log** — últimos 100 registros do `audit_log` do usuário atual (já existe a tabela; consulta direta via `supabase.from('audit_log').select(...)`).
8. **Console** — últimos ~100 logs (`log`/`warn`/`error`) capturados por wrapper de `console.*` instalado no `main.tsx`.

Tudo é mascarado: tokens, emails de terceiros e qualquer string que pareça JWT (`eyJ...`) são truncados.

### Arquivos

**Novos:**
- `src/lib/diagnostics.ts` — buffers em memória (`errorBuffer`, `networkBuffer`, `consoleBuffer`), funções `installDiagnostics()` (chamada uma vez) e `buildDiagnosticPackage()` (monta o JSON).
- `src/components/DiagnosticExportButton.tsx` — botão `Bug` no header que chama `buildDiagnosticPackage()`, gera `Blob`, dispara download e mostra toast "Diagnóstico exportado".

**Editados:**
- `src/main.tsx` — chamar `installDiagnostics()` antes do `createRoot`.
- `src/components/AppLayout.tsx` — montar `<DiagnosticExportButton />` no header, ao lado do `NotificationBell`. Visível para todos os usuários autenticados (admin vê sempre; demais veem mas com tooltip "Para suporte técnico").

### Comportamento

- Botão sempre habilitado (mesmo durante loop de loading, pois fica no header que renderiza independente das queries).
- Se `AppLayout` não montar (loop antes do login), adicionar versão de **fallback** num overlay minúsculo no canto inferior direito quando `authReady=false` por mais de 8s — assim você consegue exportar mesmo na tela travada.
- Buffers limitados (50 itens cada) para não vazar memória.
- Nenhum dado é enviado a servidor — só download local.

### Fora de escopo

- Envio automático para um endpoint (pode virar v2).
- Captura de screenshots (já temos console + network, suficiente para 90% dos casos).
- Mudanças em auth, RLS, queries existentes.

