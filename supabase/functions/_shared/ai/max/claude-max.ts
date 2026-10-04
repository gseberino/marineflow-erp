// Agente do WhatsApp pela assinatura Claude Max do dono (03/10/2026).
//
// Provedor alternável por UMA chave em app_settings:
//   ai_provedor_whatsapp = 'claude_max' | 'openrouter'   (qualquer outro valor = openrouter)
//
// No modo Max o turno vira um job em ai_jobs (task_profile 'erp_agent'). O HBR AI Gateway, no PC
// do dono, roda o Claude Code com o servidor MCP "erp" (edge function erp-mcp): cada ferramenta é
// executada AQUI no servidor, pela mesma executarChamadaDeTool do loop do OpenRouter — mesmas
// travas de risco, PIN, autonomia e auditoria. Quando o job termina, um gatilho no banco chama
// ai-agent (type 'entregar_turno_max'), que responde no WhatsApp ou, se o Max falhou, refaz o
// turno pelo OpenRouter (reserva legítima; nunca para contornar limite: o limite pausa o Max).
//
// Termos da Anthropic: a assinatura é para uso individual do assinante. Só o admin (o dono) vai
// pelo Max; qualquer outro usuário do WhatsApp segue no OpenRouter. O gateway confere de novo.
import type { ClaudeMessage, ClaudeTextBlock } from "../anthropic.ts";
import type { FerramentasDoTurno } from "../agent.ts";

export const CHAVE_DO_PROVEDOR = "ai_provedor_whatsapp";
export const CHAVE_DO_MODELO = "ai_whatsapp_max_modelo";
export const CHAVE_DA_RESERVA = "ai_whatsapp_max_reserva";
export const TIPO_DO_JOB = "agente_whatsapp";
/** O mesmo turno, para ensaio: o erp-mcp atende, mas não há entrega no WhatsApp (o gatilho ignora). */
export const TIPO_DE_ENSAIO = "agente_ensaio";

export type ProvedorDoAgente = "claude_max" | "openrouter";
export type NivelDoModelo = "haiku" | "sonnet" | "opus";

/** Quem atende o turno. Max só se a chave pedir E o usuário for o admin. */
export function provedorDoTurno(settings: Record<string, string>, cargo: string): ProvedorDoAgente {
  const pedido = (settings[CHAVE_DO_PROVEDOR] || "").trim().toLowerCase();
  if (pedido !== "claude_max") return "openrouter";
  return cargo === "admin" ? "claude_max" : "openrouter";
}

export function modeloDoMax(settings: Record<string, string>): NivelDoModelo {
  const v = (settings[CHAVE_DO_MODELO] || "").trim().toLowerCase();
  return v === "haiku" || v === "opus" ? v : "sonnet";
}

/** Se o Max falhar (PC desligado, limite, erro), o turno é refeito pelo OpenRouter? Padrão: sim. */
export function reservaLigada(settings: Record<string, string>): boolean {
  return (settings[CHAVE_DA_RESERVA] || "").trim().toLowerCase() !== "off";
}

/** O gateway avisou nos últimos 45 s e o claude-local não está em pausa (limite/login). */
// deno-lint-ignore no-explicit-any
export async function maxDisponivel(admin: any): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc("ai_claude_max_disponivel");
    return !error && data === true;
  } catch {
    return false;
  }
}

/** Texto do system prompt (os blocos estável e volátil) + o adendo das ferramentas MCP. */
export function textoDoSistema(system: ClaudeTextBlock[]): string {
  return system.map((b) => b.text).join("\n\n") + "\n\n" + ADENDO_DO_MAX;
}

export const ADENDO_DO_MAX = [
  "## Ferramentas neste modo",
  "As ferramentas do ERP aparecem com o prefixo mcp__erp__ (ex.: mcp__erp__search_clients = search_clients). Use-as",
  "exatamente como as ferramentas descritas acima. Quando uma ferramenta devolver {\"pending\": true} (ação aguardando",
  "a confirmação do usuário) ou disser que o turno foi encerrado, PARE de chamar ferramentas e responda só com uma",
  "frase curta: o sistema mostra a confirmação ao usuário. Não invente resultado de ferramenta.",
].join("\n");

const LIMITE_DE_TRECHO = 1_200;
const LIMITE_DA_TRANSCRICAO = 120_000;

function cortar(t: string, n: number): string {
  return t.length > n ? `${t.slice(0, n)}… [cortado]` : t;
}

/**
 * A conversa em texto: o Claude Code recebe UM prompt, não o array de mensagens. Mantém quem
 * falou, as ferramentas chamadas e um trecho de cada resultado (os antigos já vêm podados por
 * podarHistoricoParaLLM). A última mensagem é a atual.
 */
export function transcreverConversa(messages: ClaudeMessage[]): string {
  const linhas: string[] = [];
  const anteriores = messages.slice(0, -1);
  for (const m of anteriores) {
    for (const b of m.content as Array<Record<string, any>>) {
      if (b.type === "text" && String(b.text ?? "").trim()) {
        linhas.push(`${m.role === "user" ? "Usuário" : "Assistente"}: ${String(b.text).trim()}`);
      } else if (b.type === "tool_use") {
        linhas.push(`  [ferramenta ${b.name}] ${cortar(JSON.stringify(b.input ?? {}), 400)}`);
      } else if (b.type === "tool_result") {
        linhas.push(`  [resultado] ${cortar(String(b.content ?? ""), LIMITE_DE_TRECHO)}`);
      }
    }
  }
  const ultima = messages[messages.length - 1];
  const atual = ultima
    ? (ultima.content as Array<Record<string, any>>).filter((b) => b.type === "text").map((b) => String(b.text ?? "")).join("\n").trim()
    : "";

  // Cabe no limite: corta do começo (o mais antigo sai primeiro).
  let historico = linhas.join("\n");
  if (historico.length > LIMITE_DA_TRANSCRICAO) {
    historico = "[… conversa mais antiga omitida …]\n" + historico.slice(historico.length - LIMITE_DA_TRANSCRICAO);
  }
  return [
    historico ? `Conversa recente no WhatsApp (mais antiga primeiro):\n<historico>\n${historico}\n</historico>\n` : "",
    `Mensagem atual do usuário — responda a ela:\n<mensagem>\n${atual}\n</mensagem>`,
  ].join("\n");
}

export async function sha256Hex(texto: string): Promise<string> {
  const bytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto)));
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Token de uso único do turno: o erp-mcp só atende quem o apresenta (o banco guarda só o sha256). */
export function novoTokenDoMcp(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export interface TurnoParaOMax {
  sessionId: string;
  appUserId: string;
  phone: string;
  modelo: NivelDoModelo;
  system: ClaudeTextBlock[];
  messages: ClaudeMessage[];
  ferramentas: FerramentasDoTurno;
  /** O texto efetivo do usuário (o que a reserva do OpenRouter usaria). */
  texto: string;
}

/** A linha de ai_jobs do turno (pura, para testar). */
export function linhaDoJob(t: TurnoParaOMax, token: string, tokenSha256: string, agora = Date.now()): Record<string, unknown> {
  return {
    source: "marineflow",
    requested_by: t.appUserId,
    provider: "claude-local",
    model: t.modelo,
    task_profile: "erp_agent",
    response_format: "text",
    prompt: transcreverConversa(t.messages),
    input: {
      system: textoDoSistema(t.system),
      mcp_token: token,
      ferramentas: {
        visiveis: t.ferramentas.tools.map((f) => f.name),
        rede: Object.keys(t.ferramentas.alcancaveisPelaRede),
      },
      sessao: t.sessionId,
      canal: "whatsapp",
      texto: t.texto,
    },
    metadata: {
      tipo: TIPO_DO_JOB,
      versao: 1,
      // Conversa no WhatsApp: prioriza latência, como o loop do OpenRouter (effort "low").
      effort: "low",
      session_id: t.sessionId,
      phone: t.phone,
      user_id: t.appUserId,
      mcp_token_sha256: tokenSha256,
    },
    // WhatsApp é conversa: na frente de pedidos longos; se o gateway não pegar em 75 s, o
    // relógio do banco (_ai_gateway_reap) falha o job e a entrega refaz pelo OpenRouter.
    priority: 50,
    timeout_seconds: 150,
    max_attempts: 1,
    allow_fallback: false,
    deadline_at: new Date(agora + 75_000).toISOString(),
  };
}

// deno-lint-ignore no-explicit-any
export async function enfileirarTurnoNoMax(admin: any, t: TurnoParaOMax): Promise<string> {
  const token = novoTokenDoMcp();
  const { data, error } = await admin.from("ai_jobs").insert(linhaDoJob(t, token, await sha256Hex(token))).select("id").single();
  if (error || !data?.id) throw new Error(`não consegui enfileirar o turno no Claude Max: ${error?.message ?? "sem id"}`);
  return data.id as string;
}
