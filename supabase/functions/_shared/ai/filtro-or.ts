// Termo dito pela pessoa dentro de um .or() do PostgREST.
//
// Vírgula, ponto, dois-pontos e parênteses são a sintaxe do próprio filtro: "cabo 2,5mm" virava
// `name.ilike.%cabo 2,5mm%` e o PostgREST lia "5mm%" como outra condição — erro, que a busca em lote
// de produtos contava como "sem resultado" (e o assistente tratava o item como valor provisório).
// Entre aspas duplas o valor é texto (documentação do PostgREST, "reserved characters"). Só aspas e
// barra invertida saem do termo; % e _ continuam curinga — casam a mais, nunca a menos.

/** `coluna.ilike."%termo%"` para cada coluna, separados por vírgula — pronto para `.or()`. */
export function orContem(colunas: string[], termo: string): string {
  const t = termo.replace(/["\\]/g, " ").trim();
  return colunas.map((c) => `${c}.ilike."%${t}%"`).join(",");
}
