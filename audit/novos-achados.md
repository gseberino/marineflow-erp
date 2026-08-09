# Novos achados encontrados durante a Fase 2

Itens fora do escopo da tarefa em execução, registrados conforme a regra 5 da fila.
Não foram corrigidos.

---

## [NOVO-001] `deno check`/`deno test` sem `--no-check` falha em qualquer função que importe supabase-js

- **Encontrado em:** T0.1 (MF-AUD-053), ao rodar o gate de teste
- **Categoria:** I (testes/CI) — **Severidade sugerida:** P2
- **Descrição:** `deno test --allow-all supabase/functions/...` aborta antes de executar quando o arquivo sob
  teste importa `https://esm.sh/@supabase/supabase-js@2.45.0`:
  ```
  error: Error: Could not find "@types/node" in a node_modules folder.
  Deno expects the node_modules/ directory to be up to date. Did you forget to run `deno install`?
  ```
  A causa é a presença de `node_modules/` do frontend na raiz: o type-checker do Deno tenta resolver as
  `@types` referenciadas pelo pacote npm e não encontra. Com `--no-check` a suíte roda normalmente
  (**240 testes, 0 falhas**).
- **Por que importa agora:** a tarefa **T2.2** vai colocar `deno test -A supabase/functions` no CI. Do jeito
  que está, ou o comando precisa de `--no-check`, ou o CI quebra em todas as funções que falam com o banco —
  que são quase todas. E usar `--no-check` significa que o CI **não** verifica tipos das Edge Functions, o que
  reabre exatamente o buraco descrito em MF-AUD-046 (o `tsc` do frontend não cobre `supabase/functions`).
- **Sugestão para T2.2:** rodar o teste com `--no-check` **e** acrescentar um passo separado de
  `deno check` com um `deno.json` próprio em `supabase/functions/` (que isole a resolução de tipos do
  `node_modules` do frontend). Assim o CI executa os testes e ainda verifica tipos.
- **Evidência:** saída dos dois comandos, executados em 08/08/2026 no worktree `session/p0-webhook`.
