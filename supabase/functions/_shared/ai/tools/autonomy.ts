import type { ToolDef } from "./registry.ts";
import { AUTONOMY_PREFIX, EXPLICACAO_DA_TRAVA_POR_ARGUMENTO, NEVER_AUTONOMOUS, autonomyKey } from "../autonomy-policy.ts";
import { PERFIL_ADMIN, PERFIL_OPERACAO } from "../perfil-operacao.ts";

// Onda 2 — autonomia item-a-item.
// O dono vai liberando, uma ação por vez, o que o agente pode fazer sem pedir confirmação.
// Conceder autonomia é, ele próprio, um ato sensível: exige confirmação + PIN e só admin.

// ─── O nome existe? A autonomia vale no perfil ativo? (19/11/2026) ──────────────────────────
// set_tool_autonomy aceitava qualquer nome e respondia "a partir de agora eu executo sozinho". Mas a autonomia só vale
// para a ferramenta que o modelo VÊ (agent.ts: `autonomo = toolDef && !foraDoPerfil`): pela rede/ferramenta_extra toda
// gravação vira pendência, de propósito. Com ai_tool_profile = 'admin_enxuto', o admin vê só PERFIL_ADMIN — liberar o
// resto era gravar uma chave sem efeito e dizer que valia. Decisão: NÃO estender a autonomia à ferramenta_extra (a
// trava foi pensada para o modelo que chama sem ter lido a descrição); recusar com a explicação.

let catalogo: ReadonlyMap<string, ToolDef> = new Map();

/** tools/index.ts registra allTools aqui (importar index daqui seria ciclo). */
export function registrarCatalogoDaAutonomia(tools: readonly ToolDef[]): void {
  catalogo = new Map(tools.map((t) => [t.name, t]));
}

/** Perfil de tools gravado (agent.ts, aplicarPerfilDeTools): 'admin_enxuto', 'operacao' ou outro (= todas à vista). */
export type PerfilDeTools = "admin_enxuto" | "operacao" | "todas";

export function perfilDeTools(valor: unknown): PerfilDeTools {
  const v = String(valor ?? "").trim();
  return v === "admin_enxuto" ? "admin_enxuto" : v === "operacao" ? "operacao" : "todas";
}

/**
 * A ferramenta fica À VISTA do administrador no perfil? (o mesmo filtro de aplicarPerfilDeTools para o cargo admin:
 * no enxuto, PERFIL_ADMIN; em 'operacao', risco alto ou PERFIL_OPERACAO; sem perfil, todas). Fora da vista, chega só
 * pela ferramenta_extra, e por ali nada roda sozinho.
 */
export function autonomiaValeNoPerfil(tool: Pick<ToolDef, "name" | "risk">, perfil: PerfilDeTools): boolean {
  if (perfil === "admin_enxuto") return PERFIL_ADMIN.has(tool.name);
  if (perfil === "operacao") return tool.risk === "high" || PERFIL_OPERACAO.has(tool.name);
  return true;
}

function parecidos(nome: string): string[] {
  const termo = nome.toLowerCase().replace(/[^a-z0-9]+/g, "_").split("_").filter((p) => p.length >= 4);
  if (!termo.length) return [];
  return [...catalogo.keys()].filter((n) => termo.some((p) => n.includes(p))).slice(0, 6);
}

export const autonomyTools: ToolDef[] = [
  {
    name: "get_autonomy_settings",
    description:
      "Mostra o que o agente já pode fazer SOZINHO (sem pedir confirmação) e o que continua pedindo. Use quando o usuário perguntar 'o que você faz sozinho?', 'o que já liberei?'. Só leitura.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    async execute(_args, { sb }) {
      const { data, error } = await sb.from("app_settings").select("key, value").like("key", `${AUTONOMY_PREFIX}%`);
      if (error) return { error: `Não consegui ler a configuração de autonomia (${error.message}).` };
      const { data: linhaPerfil } = await sb.from("app_settings").select("value").eq("key", "ai_tool_profile").maybeSingle();
      const perfil = perfilDeTools(linhaPerfil?.value);
      const liberadas: string[] = [];
      const desligadas: string[] = [];
      // 'auto' gravado que não vale: ferramenta fora do perfil (só pela ferramenta_extra) ou que não existe mais.
      const semEfeito: string[] = [];
      for (const r of (data as any[]) || []) {
        const nome = String(r.key).slice(AUTONOMY_PREFIX.length);
        if (String(r.value ?? "").trim().toLowerCase() === "auto") {
          const tool = catalogo.get(nome);
          if (NEVER_AUTONOMOUS.has(nome) || (catalogo.size > 0 && (!tool || !autonomiaValeNoPerfil(tool, perfil)))) semEfeito.push(nome);
          else liberadas.push(nome);
        } else desligadas.push(nome);
      }
      return {
        agindo_sozinho: liberadas,
        pedindo_confirmacao: desligadas,
        ...(semEfeito.length
          ? {
            liberadas_sem_efeito: semEfeito,
            sem_efeito_explicacao: `Estas têm 'auto' gravado, mas continuam pedindo confirmação: estão fora do perfil de ferramentas atual (${perfil}), não existem mais ou são travadas para sempre.`,
          }
          : {}),
        nunca_liberaveis: [...NEVER_AUTONOMOUS],
        // Liberável só em parte: o dono pode ter dado 'auto' e ainda ver o pedido de "sim" no
        // modo travado — sem isto, o agente diria que a ação está liberada por inteiro.
        liberaveis_so_em_parte: EXPLICACAO_DA_TRAVA_POR_ARGUMENTO,
        explicacao:
          "Ações de baixo risco (buscas, montar orçamento, cadastros) sempre executam direto. As sensíveis pedem confirmação até serem liberadas uma a uma. As da lista 'nunca_liberaveis' envolvem dinheiro ou são destrutivas e exigem confirmação para sempre — por decisão de projeto, não dá para liberar.",
      };
    },
  },
  {
    name: "set_tool_autonomy",
    description:
      "Libera ou revoga a autonomia do agente para UMA ação específica (ex.: passar a enviar lembrete de cobrança sem pedir confirmação). Só admin, e é ação forte: pede confirmação e PIN. Ações que mexem em dinheiro ou destrutivas NÃO podem ser liberadas — a tool recusa. Também recusa nome que não existe e ação fora do perfil de ferramentas atual (lá a liberação não teria efeito). Sempre confirme com o usuário QUAL ação e explique o que muda antes de chamar.",
    input_schema: {
      type: "object",
      properties: {
        action_name: { type: "string", description: "Nome técnico da ação (ex.: send_collection_reminder)." },
        mode: { type: "string", enum: ["auto", "confirm"], description: "'auto' = age sozinho; 'confirm' = volta a pedir confirmação." },
      },
      required: ["action_name", "mode"],
    },
    risk: "high",
    roles: ["admin"],
    async execute(args, { sb, userRole }) {
      if (userRole !== "admin") return { error: "Só um administrador pode alterar a autonomia do agente." };
      const nome = String(args.action_name || "").trim();
      const modo = String(args.mode || "").trim().toLowerCase();
      if (!nome) return { error: "Informe o nome da ação." };
      if (modo !== "auto" && modo !== "confirm") return { error: "mode deve ser 'auto' ou 'confirm'." };

      if (NEVER_AUTONOMOUS.has(nome) && modo === "auto") {
        return {
          error: `"${nome}" mexe em dinheiro ou é destrutiva — não pode ser liberada para agir sozinha. Essa trava é permanente, por segurança.`,
        };
      }

      const chave = autonomyKey(nome);
      const { data: existente, error: erroLeitura } = await sb.from("app_settings").select("key").eq("key", chave).maybeSingle();
      if (erroLeitura) return { error: `Não consegui ler a configuração (${erroLeitura.message}); nada foi alterado.` };

      const tool = catalogo.get(nome);
      // Revogar uma chave que já existe é sempre seguro (inclusive de ferramenta que saiu do sistema).
      if (!tool && !(modo === "confirm" && existente)) {
        const sugestoes = parecidos(nome);
        return {
          error: `Não existe ação chamada "${nome}"; nada foi alterado.` + (sugestoes.length ? ` Parecidas: ${sugestoes.join(", ")}.` : ""),
        };
      }
      if (modo === "auto" && tool) {
        const { data: linhaPerfil, error: erroPerfil } = await sb.from("app_settings").select("value").eq("key", "ai_tool_profile").maybeSingle();
        if (erroPerfil) return { error: `Não consegui conferir o perfil de ferramentas (${erroPerfil.message}); nada foi alterado.` };
        const perfil = perfilDeTools(linhaPerfil?.value);
        if (!autonomiaValeNoPerfil(tool, perfil)) {
          return {
            error:
              `Não liberei "${nome}": no perfil de ferramentas atual (${perfil}) ela não fica à vista do assistente — chega só pela ` +
              "ferramenta_extra, e por ali toda gravação pede confirmação, por segurança. Liberar não teria efeito nenhum, então nada foi alterado. " +
              "Para valer, a ação precisaria entrar no perfil do administrador (mudança no sistema, não na configuração).",
            fora_do_perfil: true,
          };
        }
        if (tool.risk === "low" && !tool.computeRisk) {
          return { ok: true, acao: nome, modo: "auto", alterado: false, efeito: `"${nome}" já roda sem pedir confirmação (é de risco baixo); nada foi alterado.` };
        }
      }

      if (existente) {
        const { data: gravou, error } = await sb.from("app_settings").update({ value: modo }).eq("key", chave).select("key");
        if (error) throw error;
        if (!Array.isArray(gravou) || gravou.length === 0) return { error: "A configuração não foi alterada (sem permissão)." };
      } else {
        const { error } = await sb.from("app_settings").insert({ key: chave, value: modo });
        if (error) throw error;
      }

      return {
        ok: true,
        acao: nome,
        modo: modo,
        efeito: modo === "auto"
          ? `A partir de agora eu executo "${nome}" sozinho, sem pedir confirmação. Fica registrado na auditoria como ação autônoma.${EXPLICACAO_DA_TRAVA_POR_ARGUMENTO[nome] ? ` Exceção: ${EXPLICACAO_DA_TRAVA_POR_ARGUMENTO[nome]}` : ""}`
          : `"${nome}" voltou a pedir sua confirmação antes de executar.`,
      };
    },
  },
];
