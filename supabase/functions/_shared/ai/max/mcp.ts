// Servidor MCP mínimo (JSON-RPC sobre HTTP, respostas application/json, sem estado) que expõe as
// ferramentas do ERP ao Claude Code do gateway local. Só os métodos que o cliente usa:
// initialize, notifications/*, ping, tools/list e tools/call. Puro: quem executa a ferramenta e
// quem decide o que listar é o ServidorDoTurno que a edge erp-mcp monta para o job.

export const VERSAO_DO_PROTOCOLO = "2025-06-18";

export interface DefinicaoDeFerramenta {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

export interface ChamadaRespondida {
  resultado: unknown;
  /** A ferramenta encerrou o turno (pendência para o usuário confirmar, ou opções para escolher). */
  interrompe?: boolean;
}

export interface ServidorDoTurno {
  listar(): DefinicaoDeFerramenta[];
  chamar(nome: string, argumentos: unknown): Promise<ChamadaRespondida>;
}

type Resposta = Record<string, unknown>;

const erro = (id: unknown, code: number, message: string): Resposta => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });
const ok = (id: unknown, result: unknown): Resposta => ({ jsonrpc: "2.0", id, result });

function temErro(r: unknown): boolean {
  return r !== null && typeof r === "object" && Boolean((r as { error?: unknown }).error);
}

export const AVISO_DE_INTERRUPCAO =
  "TURNO ENCERRADO: o usuário precisa decidir (confirmar a ação ou escolher uma opção). Não chame mais ferramentas; " +
  "responda só com uma frase curta — o sistema mostra a confirmação/opções ao usuário.";

/** Responde UMA mensagem JSON-RPC. Notificação (sem id) devolve null → HTTP 202 sem corpo. */
export async function responderMcp(msg: unknown, srv: ServidorDoTurno): Promise<Resposta | null> {
  if (!msg || typeof msg !== "object" || Array.isArray(msg)) return erro(null, -32600, "Requisição JSON-RPC inválida");
  const m = msg as { jsonrpc?: unknown; id?: unknown; method?: unknown; params?: Record<string, unknown> };
  if (m.jsonrpc !== "2.0" || typeof m.method !== "string") return erro(m.id, -32600, "Requisição JSON-RPC inválida");
  if (m.id === undefined || m.id === null) return null; // notificação

  switch (m.method) {
    case "initialize":
      return ok(m.id, {
        protocolVersion: typeof m.params?.protocolVersion === "string" ? m.params.protocolVersion : VERSAO_DO_PROTOCOLO,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "marineflow-erp", version: "1.0.0" },
      });
    case "ping":
      return ok(m.id, {});
    case "tools/list":
      return ok(m.id, {
        tools: srv.listar().map((t) => ({ name: t.name, description: t.description, inputSchema: t.input_schema })),
      });
    case "tools/call": {
      const nome = m.params?.name;
      if (typeof nome !== "string" || !nome) return erro(m.id, -32602, "tools/call sem name");
      const r = await srv.chamar(nome, m.params?.arguments ?? {});
      const content: Array<{ type: "text"; text: string }> = [{ type: "text", text: JSON.stringify(r.resultado ?? null) }];
      if (r.interrompe) content.push({ type: "text", text: AVISO_DE_INTERRUPCAO });
      return ok(m.id, { content, isError: temErro(r.resultado) });
    }
    default:
      return erro(m.id, -32601, `Método não suportado: ${m.method}`);
  }
}
