// A "ferramenta extra" do perfil enxuto do administrador (05/10/2026).
//
// Com app_settings.ai_tool_profile = 'admin_enxuto', o admin vê só PERFIL_ADMIN
// (perfil-operacao.ts). O que saiu continua alcançável por ESTA ferramenta, que fica sempre à
// vista: { nome, argumentos, descrever }. Ela é necessária por causa do Claude Max — lá o modelo só
// conhece as ferramentas que o erp-mcp lista, e chamar de memória um nome escondido nem chega ao
// servidor (a rede de segurança antiga, que esperava a chamada direta, não alcançava nada).
//
// Quem executa é executarChamadaDeTool (agent.ts): o pedido é redespachado pelo MESMO caminho da
// rede — argumentos conferidos contra o input_schema, escrita vira pendência com o nome REAL (o
// "sim" executa a ferramenta certa), leitura roda direto, auditoria 'fora_do_perfil:<nome>'.
// `descrever: true` devolve a descrição e o esquema sem executar, para o modelo ler os limites
// da ferramenta antes de uma escrita.
//
// A lista de nomes vai no enum: fixa por cargo e canal, então não quebra o cache do prompt.
import type { ToolDef } from "./tools/registry.ts";

export const NOME_DA_FERRAMENTA_EXTRA = "ferramenta_extra";

export function construirFerramentaExtra(nomes: readonly string[]): ToolDef {
  const enumDeNomes = [...new Set(nomes)].filter((n) => n !== NOME_DA_FERRAMENTA_EXTRA).sort();
  return {
    name: NOME_DA_FERRAMENTA_EXTRA,
    description:
      "Acesso às ferramentas do sistema que não estão na sua lista. Use quando o pedido precisar de uma ferramenta " +
      "que o prompt cita e você não tem à vista. Com descrever=true, devolve a descrição e os argumentos dela sem " +
      "executar — faça isso antes de qualquer gravação. Sem descrever, executa: leitura roda na hora; gravação vira " +
      "um pedido de confirmação ao dono, como as ações sensíveis.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string", enum: enumDeNomes, description: "Nome exato da ferramenta." },
        argumentos: { type: "object", description: "Os argumentos da ferramenta, como no input_schema dela." },
        descrever: { type: "boolean", description: "true = só mostrar descrição e argumentos, sem executar." },
      },
      required: ["nome"],
    },
    risk: "low",
    // Nunca roda por aqui: executarChamadaDeTool intercepta pelo nome e redespacha.
    execute: () => Promise.resolve({ error: "ferramenta_extra é despachada pelo executor do agente." }),
  } as unknown as ToolDef;
}
