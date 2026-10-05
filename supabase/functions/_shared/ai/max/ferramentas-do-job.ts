// Quais ferramentas um job do agente pelo Claude Max pode ver e alcançar no erp-mcp.
// Os nomes vêm do job (calculados pelo ai-agent no momento do pedido, com o perfil de tools), mas
// são REVALIDADOS aqui pelo cargo atual do usuário e pelo canal: um nome que não passa no filtro
// simplesmente não existe para o modelo.
//
// Perfil enxuto do admin (05/10/2026): a rede do ADMIN alcança tudo que cargo e canal liberam (dos
// outros cargos, só SO_PELA_REDE), e a ferramenta_extra — que não existe em allTools — é remontada
// aqui com os nomes da rede já revalidados. É por ela que o modelo, no Max, chega ao que saiu do
// perfil: o erp-mcp só lista as visíveis.
import { allTools, type Role, type ToolDef } from "../tools/index.ts";
import { filtrarPorCanal } from "../channel-scope.ts";
import { SO_PELA_REDE } from "../perfil-operacao.ts";
import { construirFerramentaExtra, NOME_DA_FERRAMENTA_EXTRA } from "../ferramenta-extra.ts";

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
  const toolsByName: Record<string, ToolDef> = Object.fromEntries(
    nomes(visiveis).filter((n) => porNome.has(n)).map((n) => [n, porNome.get(n)!]),
  );
  const alcancaveisPelaRede: Record<string, ToolDef> = Object.fromEntries(
    nomes(rede)
      .filter((n) => porNome.has(n) && !toolsByName[n] && (cargo === "admin" || SO_PELA_REDE.has(n)))
      .map((n) => [n, porNome.get(n)!]),
  );
  if (nomes(visiveis).includes(NOME_DA_FERRAMENTA_EXTRA) && Object.keys(alcancaveisPelaRede).length > 0) {
    toolsByName[NOME_DA_FERRAMENTA_EXTRA] = construirFerramentaExtra(Object.keys(alcancaveisPelaRede));
  }
  return { toolsByName, alcancaveisPelaRede };
}
