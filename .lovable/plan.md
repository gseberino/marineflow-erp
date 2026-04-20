

## Diagnóstico — Tela de loading infinito

### Causa raiz

A aplicação tem uma **race condition de autenticação**:

1. Quando você abre/recarrega o app, `AuthProvider` começa a restaurar a sessão Supabase do `localStorage` (operação assíncrona).
2. Ao mesmo tempo, **todas as páginas começam a fazer queries** (`useClients`, `useDashboardData`, `useNotifications`, etc.) sem esperar a sessão estar pronta.
3. Se uma query parte **antes** do token JWT ser anexado ao cliente Supabase, ela bate em RLS, retorna 401 e falha.
4. Existe `retry: 3` no `App.tsx`, mas com backoff exponencial (1s, 2s, 4s = 7s totais). Em conexões lentas ou abas suspensas pelo navegador, a sessão pode demorar mais que isso, e a query falha **permanentemente** — `isLoading` continua `true` no React Query até a próxima `invalidate`, gerando loading infinito.
5. Como `staleTime: 0` (global) força refetch agressivo a cada navegação, o problema **vai piorando**: cada nova página dispara novas queries, algumas pegam o momento ruim e travam, então mais áreas da UI ficam vazias.
6. Quando você dá F5, o estado em memória se perde mas o `localStorage` da sessão pode estar parcialmente renovando token — nova rajada de queries cai no mesmo buraco e nada carrega.

### Sintomas correspondentes
- "Alguns elementos não carregam" → queries paralelas, algumas pegam o momento ruim.
- "Depois páginas inteiras" → mais queries acumulam estado de erro/loading.
- "F5 e nada carrega" → refresh de token coincide com burst de queries.
- Não há padrão → depende do timing de rede, suspensão da aba, expiração do token.

---

## Correções (todas no nível raiz, sem alterar páginas individualmente)

### Fix 1 — Gate global de autenticação no `AuthProvider`
Em `src/hooks/use-auth.tsx`:
- Adicionar `authReady: boolean` ao contexto, separado de `loading`. `authReady = true` quando `getSession()` resolveu **e** (se há sessão) o perfil foi carregado.
- Expor `authReady` no `useAuth()`.

### Fix 2 — Gatear queries via `QueryClient` global
Em `src/App.tsx`, configurar o `QueryClient` para **só executar queries quando autenticado**, usando um wrapper. Como não dá para passar `enabled` global, vamos:
- Criar um pequeno componente `<QueryGate>` dentro do `AuthProvider` que monta os filhos só depois que `authReady === true`. Assim, **nenhuma query é montada antes da sessão estar pronta** — elimina a race em todas as 26+ hooks de uma só vez, sem precisar editar cada uma.
- Mantém `<LoginPage>` e `<ResetPasswordPage>` fora do gate (eles não fazem queries autenticadas).

### Fix 3 — Tornar `retry` mais resiliente
Em `src/App.tsx`:
- Aumentar `retry` para 5 e adicionar lógica que **não conta retries por erro de auth** (`401`) durante a janela inicial. Se o erro for `JWT expired`/`401`, força um `supabase.auth.refreshSession()` antes de tentar de novo.
- Subir `staleTime` global para `30s` (em vez de 0) para evitar o burst de refetch a cada navegação. Hooks que precisam tempo real (notifications, dashboard) já têm `refetchInterval` próprio.

### Fix 4 — Listener de refresh de token
Em `src/hooks/use-auth.tsx`:
- No `onAuthStateChange`, ao receber evento `TOKEN_REFRESHED`, chamar `queryClient.invalidateQueries()` para revalidar dados com o token novo. Isso resolve o caso "fica horas aberto, depois nada carrega".
- Para acessar `queryClient` dentro do hook, exportar uma instância singleton de `src/lib/query-client.ts` em vez de criar inline em `App.tsx`.

### Fix 5 — Timeout máximo de loading no `ProtectedRoute`
Em `src/components/ProtectedRoute.tsx`:
- Adicionar timeout de 10 segundos. Se `loading` continuar `true` após 10s, mostrar botão "Recarregar" em vez de spinner infinito. Não conserta a causa, mas dá saída ao usuário se algo escapar.

### Fix 6 — Tratamento de visibilidade da aba
Em `src/hooks/use-auth.tsx`:
- Adicionar listener `visibilitychange`: ao voltar à aba, chamar `supabase.auth.getSession()` para forçar re-checagem do token. Quando o navegador suspende a aba (mobile/desktop), o refresh automático do Supabase pode não rodar — voltar à aba deve revalidar.

---

## Arquivos que serão alterados

| Arquivo | Mudança |
|---|---|
| `src/lib/query-client.ts` | **Novo** — singleton do `QueryClient` com retry inteligente |
| `src/App.tsx` | Importar singleton; envolver rotas autenticadas com `<QueryGate>` |
| `src/hooks/use-auth.tsx` | Adicionar `authReady`, `TOKEN_REFRESHED` invalidation, visibility listener |
| `src/components/QueryGate.tsx` | **Novo** — bloqueia render de filhos até `authReady` |
| `src/components/ProtectedRoute.tsx` | Timeout de loading com botão "Recarregar" |

**Nenhum arquivo de página, hook de dados, formulário ou lógica de negócio será alterado** — a correção é arquitetural, no provider raiz.

---

## Por que isso resolve definitivamente

O bug acontece **uma vez** (no boot), em **um único lugar** (auth restoration). Em vez de tapar buraco em cada hook, o `<QueryGate>` garante que **nenhum** `useQuery` da árvore protegida é montado antes de existir um JWT válido. Isso elimina toda a categoria de erro 401-na-inicialização, não só os sintomas que você viu.

Após implementar, vou pedir que você teste:
1. Refresh duro (Ctrl+Shift+R) várias vezes.
2. Deixar a aba em background por 30+ minutos e voltar.
3. Navegar rapidamente entre 5-6 páginas seguidas.

