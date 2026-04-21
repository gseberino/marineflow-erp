

## Diagnóstico definitivo do loop de loading

Após reler `use-auth.tsx`, `query-client.ts`, `QueryGate`, `ProtectedRoute` e os hooks de query, identifiquei **três defeitos que se combinam** para produzir o sintoma exato que você descreve (loop infinito no F5, elementos que param de carregar ao trocar de página, só resolve limpando cache):

### Defeito 1 — Race condition entre `onAuthStateChange` e `getSession`
No `useEffect` do `AuthProvider`:
- O listener `onAuthStateChange` é registrado **antes** de `getSession()`.
- Em algumas inicializações (especialmente F5 com token expirado), o listener dispara `INITIAL_SESSION` com `session=null` **antes** do `getSession()` resolver com a sessão real do storage.
- O `applySession(null)` chama `finalize()` (libera o gate) e seta `user=null` → `ProtectedRoute` redireciona para `/login`.
- Quando `getSession()` finalmente resolve com a sessão real, já é tarde: o usuário foi expulso ou as queries dispararam sem JWT válido.

### Defeito 2 — Queries disparam sem JWT pronto
Hooks como `useDashboardData`, `useServiceOrders`, `useClients` (lista) **não têm `enabled` gate** dependente de `authReady`/`user.id`. Como o React Query monta no primeiro render do `AppLayout`, se `authReady` virar `true` por causa do `INITIAL_SESSION:null` (defeito 1) ou pelo safety timer de 2.5s, a query roda sem token e:
- Retorna 401 / array vazio (RLS bloqueia `auth.uid() IS NULL`).
- O retry do `query-client.ts` chama `refreshOnce()` mas **não invalida** as queries depois do refresh — então a tela fica com dados vazios/quebrados até navegar e remontar (que é exatamente o sintoma "alguns elementos não carregam ao mudar de página").

### Defeito 3 — Token refresh em background não re-dispara queries
`query-client.ts` faz `supabase.auth.refreshSession()` mas só retorna `failureCount < 1`. Quando o evento `TOKEN_REFRESHED` chega no `onAuthStateChange`, o handler atual chama `applySession` mas **não invalida o cache do React Query**. Resultado: queries que falharam por JWT expirado ficam com `error` permanente até hard reload.

---

## Correção (4 arquivos)

### 1) `src/hooks/use-auth.tsx` — reescrita do bootstrap
- **Inverter ordem**: chamar `getSession()` **primeiro** e só depois registrar `onAuthStateChange`. Isso elimina o race do `INITIAL_SESSION:null` prematuro.
- **Tratar `INITIAL_SESSION` e `TOKEN_REFRESHED` corretamente**: atualizar `session`/`user` mas, se já temos sessão válida e o evento chega com a mesma sessão, não recarregar perfil (evita re-render cascateado).
- **No evento `TOKEN_REFRESHED`**: chamar `queryClient.invalidateQueries()` para que queries que estavam com erro 401 sejam re-executadas com o novo JWT.
- **Aumentar safety timer para 5s** mas só usá-lo como fallback de UI — não como sinal de "auth pronto, pode buscar dados".
- Remover `loading` redundante (manter só `authReady`).

### 2) `src/lib/query-client.ts` — retry mais inteligente + invalidação após refresh
- Quando detectar erro de auth, chamar `refreshOnce()` e **aguardar** (await) antes de retornar `true` para retry — assim o retry usa o token novo.
- Após refresh bem-sucedido, disparar `queryClient.invalidateQueries()` (via export de uma função `triggerRefresh`).
- Limitar retry de auth a 2 tentativas (evita loop infinito se o refresh também falhar).

### 3) `src/components/QueryGate.tsx` — gate baseado em `session`, não só `authReady`
Renderizar children **somente quando** `authReady === true && session !== null`. Hoje libera apenas com `authReady`, então queries autenticadas podem rodar antes do JWT estar acessível ao Supabase client.

### 4) `src/components/ProtectedRoute.tsx` — não redirecionar durante refresh
Usar `authReady && !session` (em vez de `!user`) para decidir o redirect. Como `user` é populado em background pelo profile loader, hoje há uma janela onde `authReady=true` mas `user` ainda é `null`, causando flash de redirect indevido.

---

## Validação ponta a ponta (após implementar)

Vou usar o browser tool para reproduzir com seu login `gustavo@hbrmarine.com.br`:

1. **Login limpo**: navegar para `/login`, autenticar, verificar que cai em `/` sem flash.
2. **F5 em `/service-orders`**: confirmar que NÃO há loop de loading e que a lista carrega na primeira tentativa.
3. **Navegação entre páginas**: `/` → `/clients` → `/financial` → `/service-orders` sem perda de dados.
4. **Token refresh simulado**: aguardar ~50min ou forçar via console (`supabase.auth.refreshSession()`) e confirmar que queries continuam funcionando.
5. **Console limpo**: sem `[Auth] Safety timeout`, sem 401s, sem `Profile load failed`.

Critério de sucesso: 5 F5 consecutivos em rotas diferentes, todos carregando dados na primeira tentativa, sem `localStorage.clear()`.

---

## Fora de escopo (não vou tocar)
- RLS policies (já estão corretas — `auth.uid() IS NOT NULL`).
- `is_admin` function (já criada).
- Triggers `handle_new_user` (já existe).
- Qualquer arquivo de PDF, OS, financeiro, WhatsApp.

Foco cirúrgico: 4 arquivos de auth/query, validação real com browser.

