// Quais ferramentas um job do agente pelo Claude Max pode ver e alcançar no erp-mcp.
// Os nomes vêm do job (calculados pelo ai-agent no momento do pedido, com o perfil de tools), mas
// são REVALIDADOS aqui pelo cargo atual do usuário e pelo canal: um nome que não passa no filtro
// simplesmente não existe para o modelo.
import { allTools, type Role, type ToolDef } from "../tools/index.ts";
import { filtrarPorCanal } from "../channel-scope.ts";
import { SO_PELA_REDE } from "../perfil-operacao.ts";

export function ferramentasDoJob(
  cargo: Role,
  visiveis: unknown,
  rede: unknown,
  canal: string = "whatsapp",
  todas: ToolDef[] = allTools,
): { toolsByName: Record<string, ToolDef>; alcancaveisPelaRede: Record<string, ToolDef> } {
  const liberadas = filtrarPorCanal(todas.filter((t) => !t.roles || t.roles.includes(cargo)), canal);
  const porNome = new Map(liberadas.map((t) => [t.name, t]));
  const nomes = (v: unknown) => (Array.isArray(v) ? v.filter((n): n is string => typeof n === "string") : []);
  return {
    toolsByName: Object.fromEntries(nomes(visiveis).filter((n) => porNome.has(n)).map((n) => [n, porNome.get(n)!])),
    alcancaveisPelaRede: Object.fromEntries(
      nomes(rede).filter((n) => porNome.has(n) && SO_PELA_REDE.has(n)).map((n) => [n, porNome.get(n)!]),
    ),
  };
}
