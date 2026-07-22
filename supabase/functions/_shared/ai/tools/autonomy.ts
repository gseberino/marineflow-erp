import type { ToolDef } from "./registry.ts";
import { AUTONOMY_PREFIX, NEVER_AUTONOMOUS, autonomyKey } from "../autonomy-policy.ts";

// Onda 2 — autonomia item-a-item.
// O dono vai liberando, uma ação por vez, o que o agente pode fazer sem pedir confirmação.
// Conceder autonomia é, ele próprio, um ato sensível: exige confirmação + PIN e só admin.

export const autonomyTools: ToolDef[] = [
  {
    name: "get_autonomy_settings",
    description:
      "Mostra o que o agente já pode fazer SOZINHO (sem pedir confirmação) e o que continua pedindo. Use quando o usuário perguntar 'o que você faz sozinho?', 'o que já liberei?'. Só leitura.",
    input_schema: { type: "object", properties: {} },
    risk: "low",
    async execute(_args, { sb }) {
      const { data } = await sb.from("app_settings").select("key, value").like("key", `${AUTONOMY_PREFIX}%`);
      const liberadas: string[] = [];
      const desligadas: string[] = [];
      for (const r of (data as any[]) || []) {
        const nome = String(r.key).slice(AUTONOMY_PREFIX.length);
        if (String(r.value ?? "").trim().toLowerCase() === "auto") liberadas.push(nome);
        else desligadas.push(nome);
      }
      return {
        agindo_sozinho: liberadas,
        pedindo_confirmacao: desligadas,
        nunca_liberaveis: [...NEVER_AUTONOMOUS],
        explicacao:
          "Ações de baixo risco (buscas, montar orçamento, cadastros) sempre executam direto. As sensíveis pedem confirmação até serem liberadas uma a uma. As da lista 'nunca_liberaveis' envolvem dinheiro ou são destrutivas e exigem confirmação para sempre — por decisão de projeto, não dá para liberar.",
      };
    },
  },
  {
    name: "set_tool_autonomy",
    description:
      "Libera ou revoga a autonomia do agente para UMA ação específica (ex.: passar a enviar lembrete de cobrança sem pedir confirmação). Só admin, e é ação forte: pede confirmação e PIN. Ações que mexem em dinheiro ou destrutivas NÃO podem ser liberadas — a tool recusa. Sempre confirme com o usuário QUAL ação e explique o que muda antes de chamar.",
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
      const { data: existente } = await sb.from("app_settings").select("key").eq("key", chave).maybeSingle();
      if (existente) {
        const { error } = await sb.from("app_settings").update({ value: modo }).eq("key", chave);
        if (error) throw error;
      } else {
        const { error } = await sb.from("app_settings").insert({ key: chave, value: modo });
        if (error) throw error;
      }

      return {
        ok: true,
        acao: nome,
        modo: modo,
        efeito: modo === "auto"
          ? `A partir de agora eu executo "${nome}" sozinho, sem pedir confirmação. Fica registrado na auditoria como ação autônoma.`
          : `"${nome}" voltou a pedir sua confirmação antes de executar.`,
      };
    },
  },
];
