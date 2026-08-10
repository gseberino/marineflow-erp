/**
 * `Deno` para o typecheck do FRONTEND.
 *
 * Alguns testes de `src/test/` importam módulos de `supabase/functions/_shared/**` para
 * exercitar a lógica pura das Edge Functions sem subir Deno (ex.: `ai-finance-tools.test.ts`
 * importa `_shared/ai/tools/finance-rules`). Esses módulos leem variáveis de ambiente por
 * `Deno.env.get(...)`, e o projeto do frontend não conhece o global — daí o
 * `TS2304: Cannot find name 'Deno'`.
 *
 * Declarar o mínimo aqui é melhor que as alternativas: puxar `@types/deno` traria um
 * ambiente inteiro que não existe no navegador, e um `// @ts-ignore` na linha esconderia
 * erros de verdade no mesmo arquivo.
 *
 * Só o que é de fato usado nesse cruzamento. Se um dia o frontend precisar de mais API do
 * Deno, é sinal de que a fronteira está no lugar errado — e aí a resposta é mover a lógica
 * para um módulo puro, não crescer este arquivo.
 */
declare const Deno: {
  env: {
    get(key: string): string | undefined;
  };
};
