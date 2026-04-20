
Objetivo: eliminar definitivamente o loading infinito atacando a causa raiz no bootstrap de autenticação e removendo todos os pontos do código que transformam erro/estado indefinido em spinner permanente.

1. Reestruturar o bootstrap de autenticação em `src/hooks/use-auth.tsx`
- Remover o `await loadUserProfile(...)` de dentro do callback de `onAuthStateChange`. Hoje isso faz consulta ao banco dentro do fluxo de eventos de autenticação, o que pode bloquear/embaralhar a restauração da sessão.
- Separar claramente três fases:
  - restauração inicial da sessão,
  - carregamento do perfil,
  - liberação final do app (`loading=false` e `authReady=true`).
- Manter o listener registrado antes do `getSession()`, mas o callback passará a:
  - atualizar `session`,
  - limpar usuário em `SIGNED_OUT`,
  - disparar carregamento de perfil sem prender o pipeline de auth,
  - invalidar/limpar queries conforme o evento.
- Adicionar proteção contra resposta obsoleta: se duas leituras de perfil acontecerem em sequência, só a mais recente poderá atualizar `user`.
- Adicionar fallback com timeout no carregamento do perfil: se a leitura de `app_users` travar ou demorar além do razoável, o app continua com usuário mínimo em vez de ficar preso no boot.

2. Blindar o `QueryClient` em `src/lib/query-client.ts`
- Trocar o `refreshSession()` atual por um mecanismo single-flight:
  - se várias queries falharem por auth ao mesmo tempo, apenas uma tentativa real de refresh será feita;
  - as demais reaproveitam a mesma promessa, evitando tempestade de refresh e revogação de token em cascata.
- Manter retry diferenciado para erro de autenticação, mas com controle:
  - retry maior só para 401/JWT,
  - retry comum para demais erros,
  - sem disparar refresh infinito.
- Preservar `staleTime` mais alto para reduzir rajadas de refetch logo após navegação/refresh.

3. Ajustar a orquestração raiz em `src/App.tsx`, `src/components/QueryGate.tsx` e `src/components/ProtectedRoute.tsx`
- Manter o `QueryGate`, mas garantir que ele só dependa do estado final e consistente de bootstrap do `use-auth`.
- Evitar janelas em que `ProtectedRoute` e `QueryGate` possam divergir sobre o estado de readiness.
- Preservar a saída de segurança do timeout em `ProtectedRoute`, mas baseada no fluxo corrigido de autenticação, para que ela vire exceção real e não comportamento comum.

4. Corrigir todos os loaders permanentes causados por condição incorreta de render
- Revisão completa dos pontos auditados onde o código usa `isLoading || !data` para continuar mostrando loading mesmo após erro ou resultado indefinido.
- Corrigir especificamente:
  - `src/pages/ReportsPage.tsx`
  - `src/pages/Dashboard.tsx`
- Padrão a aplicar:
  - `isLoading` mostra skeleton/loading,
  - `error` mostra estado de erro com mensagem e ação de tentar novamente,
  - ausência de dados sem erro mostra estado vazio,
  - nunca usar `!data` como gatilho automático de spinner infinito.
- Fazer uma segunda varredura no projeto para localizar qualquer outro uso equivalente e corrigir no mesmo padrão.

5. Revisar hooks e consumidores compartilhados que impactam todas as páginas
- Validar os hooks que disparam consultas logo na montagem da shell autenticada, com foco especial em:
  - `src/hooks/use-dashboard.ts`
  - `src/hooks/use-reports.ts`
  - `src/hooks/use-notifications.ts`
- Garantir que falha de uma consulta compartilhada nunca deixe cabeçalho, dashboard ou abas presos em “carregando”.
- Onde necessário, converter falhas silenciosas/ausência de retorno em erro explícito ou estado vazio explícito.

6. Passo de saneamento final contra novos pontos de loading infinito
- Fazer uma auditoria final por padrões de risco no código:
  - `if (isLoading || !data)`
  - `return <Loading...>` sem tratamento de `error`
  - callbacks de auth com chamadas assíncronas bloqueantes
  - retries de auth sem coordenação
- Corrigir qualquer ocorrência restante encontrada na mesma rodada, para que o problema não reapareça em outra página.

7. Validação final após a implementação
- Verificar build TypeScript limpo.
- Revisar console para confirmar que não restaram erros relacionados ao fluxo de carregamento.
- Validar o comportamento esperado nestes cenários:
  - refresh do navegador com sessão ativa,
  - navegação rápida entre várias páginas,
  - aba em background por longo período e retorno,
  - abertura pelo domínio publicado.
- Só concluir quando não houver mais nenhum caminho de spinner permanente identificado na autenticação, shell e páginas auditadas.

Detalhes técnicos
- Causa principal confirmada: o app ainda faz trabalho assíncrono de perfil dentro de `onAuthStateChange`, exatamente no ponto mais sensível do bootstrap de sessão.
- Causa secundária confirmada: o retry global atual pode gerar múltiplos `refreshSession()` concorrentes sob falha de auth.
- Causa terciária confirmada: ainda existem telas com lógica de render que converte erro/`undefined` em loading eterno, especialmente em relatórios e dashboard.
- Arquivos centrais da correção:
  - `src/hooks/use-auth.tsx`
  - `src/lib/query-client.ts`
  - `src/App.tsx`
  - `src/components/QueryGate.tsx`
  - `src/components/ProtectedRoute.tsx`
  - `src/pages/ReportsPage.tsx`
  - `src/pages/Dashboard.tsx`
