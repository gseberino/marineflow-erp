// O aprendiz de regras no banco (proporRegrasNoBanco, index.ts): leitura que falha derruba o aprendizado do dia,
// não o refaz com dado faltando (segunda revisão de 22/10/2026). O comportamento das regras propostas é testado
// sem banco em src/test/banking-regras-aprendidas.test.ts; aqui, só a estrutura das leituras.
// Rodar com:
//   deno test --allow-all --no-check --node-modules-dir=none supabase/functions/finance-review/aprendiz_test.ts
import { assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

const INDEX = Deno.readTextFileSync(new URL("./index.ts", import.meta.url));
const aprendiz = INDEX.slice(INDEX.indexOf("async function proporRegrasNoBanco("), INDEX.indexOf("async function lerCompraParcelada("));

Deno.test("estrutura: as categorias são lidas com o erro, e o erro derruba o aprendizado", () => {
  // Engolir o erro deixava o mapa de grupos vazio, e toda regra proposta ia gravada como despesa_operacional
  // ("Aplicação RDB → Aplicação financeira" entraria no resultado como despesa, se o dono aceitasse).
  assert(aprendiz.length > 0, "proporRegrasNoBanco não encontrada");
  assert(/const \{ data: cats, error: eCats \} = await admin\s*\.from\("financial_categories"\)/.test(aprendiz),
    "a leitura de financial_categories não pega o erro");
  assert(aprendiz.includes("if (eCats) throw eCats;"), "o erro das categorias não derruba o aprendizado");
});

Deno.test("estrutura: fornecedores e regras continuam lidos com o erro (1ª rodada)", () => {
  assert(aprendiz.includes("if (eForn) throw eForn;"));
  assert(aprendiz.includes("if (eRegras) throw eRegras;"));
});
