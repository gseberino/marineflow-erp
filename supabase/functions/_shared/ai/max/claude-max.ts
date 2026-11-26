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
// Termos da Anthropic: a assinatura é para uso individual do assinante. Só o ASSINANTE vai pelo Max:
// a pessoa listada em app_settings.ai_max_assinantes, e não o cargo (S5 do pacote 1, 24/11/2026; até
// então era "qualquer admin"). Qualquer outro usuário segue no OpenRouter ou, com a reserva desligada,
// lê que o assistente atende só o titular (naoAssinanteSemReserva). O gateway confere de novo, pela
// lista dele (requested_by), que este código não lê.
import type { ClaudeMessage, ClaudeTextBlock } from "../anthropic.ts";
import type { FerramentasDoTurno } from "../agent.ts";

export const CHAVE_DO_PROVEDOR = "ai_provedor_whatsapp";
export const CHAVE_DO_MODELO = "ai_whatsapp_max_modelo";
export const CHAVE_DA_RESERVA = "ai_whatsapp_max_reserva";
/** Chat do app (painel): mesma ideia, chave própria (03/10/2026). */
export const CHAVE_DO_PROVEDOR_PAINEL = "ai_provedor_painel";
export const CHAVE_DO_MODELO_PAINEL = "ai_painel_max_modelo";
export const TIPO_DO_JOB = "agente_whatsapp";
export const TIPO_DO_PAINEL = "agente_painel";
/** O mesmo turno, para ensaio: o erp-mcp atende, mas não há entrega no WhatsApp (o gatilho ignora). */
export const TIPO_DE_ENSAIO = "agente_ensaio";
/** Tipos de job que o erp-mcp atende. */
export const TIPOS_DO_AGENTE = new Set([TIPO_DO_JOB, TIPO_DO_PAINEL, TIPO_DE_ENSAIO]);

export type ProvedorDoAgente = "claude_max" | "openrouter";
export type NivelDoModelo = "haiku" | "sonnet" | "opus";
export type CanalDoAgente = "whatsapp" | "panel";

// ═══ QUEM É O ASSINANTE (S5 do pacote 1, 24/11/2026) ═══
//
// A assinatura é de UMA pessoa. Até aqui a edge mandava pelo Max qualquer administrador: um administrador inativo que
// fosse reativado entraria na fila do Max, e a única trava seria a lista do gateway, no PC. Agora a edge confere a pessoa,
// pelo mesmo critério do gateway (o app_users.id que vai em ai_jobs.requested_by).
//
//   · chave AUSENTE          → regra antiga (cargo admin), com aviso no log. É o que deixa o deploy sair antes da
//                              migration 20270301130000_assinatura_max_por_pessoa, que grava a chave.
//   · chave presente         → só quem está na lista, seja qual for o cargo.
//   · chave presente e vazia → ninguém.
//
// Nenhum id mora no código: a lista é do banco. Apagar a chave volta à regra do cargo (o gateway continua barrando).

/** Quem pode usar a assinatura Claude: lista de app_users.id separados por vírgula. */
export const CHAVE_DOS_ASSINANTES = "ai_max_assinantes";

const FORMA_DE_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/**
 * A lista como está na chave: ids em minúscula, sem repetição. null = a chave NÃO EXISTE (regra antiga); lista vazia = a
 * chave existe e não libera ninguém. Tolera espaço, maiúscula, quebra de linha e ponto e vírgula; o que não tem forma de
 * id é descartado, porque não pode ser pessoa nenhuma.
 */
function listaDosAssinantes(settings: Record<string, string>): string[] | null {
  if (!Object.hasOwn(settings, CHAVE_DOS_ASSINANTES)) return null;
  const ids = String(settings[CHAVE_DOS_ASSINANTES] ?? "").toLowerCase().split(/[\s,;]+/).filter((t) => FORMA_DE_ID.test(t));
  return [...new Set(ids)];
}

/** O aviso da chave ausente sai uma vez por instância da função, não a cada chamada de ferramenta. */
let avisouQueFaltaAChave = false;

/**
 * A pessoa pode usar a assinatura? Pessoa, não cargo (ver o quadro acima). `cargo` só decide enquanto a chave não existe.
 * Com a chave presente e sem id de pessoa, ninguém passa.
 */
export function assinanteDoMax(settings: Record<string, string>, userId: string, cargo: string): boolean {
  const lista = listaDosAssinantes(settings);
  if (lista === null) {
    if (!avisouQueFaltaAChave) {
      avisouQueFaltaAChave = true;
      console.warn(
        `[claude-max] app_settings.${CHAVE_DOS_ASSINANTES} não existe: a assinatura segue pela regra antiga (cargo admin). ` +
          "Falta aplicar a migration 20270301130000_assinatura_max_por_pessoa.",
      );
    }
    return cargo === "admin";
  }
  const id = String(userId ?? "").trim().toLowerCase();
  return id !== "" && lista.includes(id);
}

/**
 * O id do assinante, quando a lista tem exatamente UM; senão null (chave ausente, lista vazia ou com dois ou mais).
 *
 * Para os pedidos automáticos, em que não há pessoa falando: eles rodam em nome do assinante e usam este id como
 * requested_by, que é o que o gateway confere. null = não há em nome de quem pedir, e quem chama NÃO enfileira. Com a
 * chave ausente também é null: a regra antiga é por cargo, e do cargo não sai um id.
 */
export function idDoAssinante(settings: Record<string, string>): string | null {
  const lista = listaDosAssinantes(settings);
  return lista?.length === 1 ? lista[0] : null;
}

/** A chave do canal pede o Claude da assinatura? */
function canalPedeOMax(settings: Record<string, string>, canal: CanalDoAgente): boolean {
  const chave = canal === "panel" ? CHAVE_DO_PROVEDOR_PAINEL : CHAVE_DO_PROVEDOR;
  return (settings[chave] || "").trim().toLowerCase() === "claude_max";
}

/** Quem atende o turno. Max só se a chave do canal pedir E a pessoa for assinante (assinanteDoMax). */
export function provedorDoTurno(
  settings: Record<string, string>,
  cargo: string,
  canal: CanalDoAgente = "whatsapp",
  userId = "",
): ProvedorDoAgente {
  if (!canalPedeOMax(settings, canal)) return "openrouter";
  return assinanteDoMax(settings, userId, cargo) ? "claude_max" : "openrouter";
}

/**
 * O canal está no Claude da assinatura, quem fala NÃO é assinante e a reserva está desligada: não há quem responda a
 * essa pessoa. Sem isto ela cairia no laço do OpenRouter com a reserva desligada, porque o desvio do C2 só vale dentro do
 * ramo do Max, e ela nunca entra nele. Quem chama fecha o turno com a frase do código nao_assinante (causa-da-falha.ts).
 *
 * false com a reserva ligada (a pessoa segue pelo OpenRouter, como sempre) e false quando o canal não está no Claude
 * (aí todos vão pelo OpenRouter por escolha do dono, e a chave da reserva não diz nada).
 */
export function naoAssinanteSemReserva(settings: Record<string, string>, cargo: string, canal: CanalDoAgente, userId: string): boolean {
  return canalPedeOMax(settings, canal) && !reservaLigada(settings) && !assinanteDoMax(settings, userId, cargo);
}

export function modeloDoMax(settings: Record<string, string>, canal: CanalDoAgente = "whatsapp"): NivelDoModelo {
  const v = (settings[canal === "panel" ? CHAVE_DO_MODELO_PAINEL : CHAVE_DO_MODELO] || "").trim().toLowerCase();
  return v === "haiku" || v === "opus" ? v : "sonnet";
}

/**
 * Se o Max falhar (PC desligado, limite, erro), o turno é refeito pelo OpenRouter? Padrão: sim.
 * Desligada (C2, 24/11/2026): nos dois canais, o Max que não atende — antes ou depois de existir pedido — vira aviso com
 * a causa dita (causa-da-falha.ts) e nada chega ao OpenRouter. Quem liga ou desliga é o dono, pela tela.
 */
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
export function transcreverConversa(messages: ClaudeMessage[], canal: CanalDoAgente = "whatsapp"): string {
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
    historico ? `Conversa recente ${canal === "panel" ? "no chat do app" : "no WhatsApp"} (mais antiga primeiro):\n<historico>\n${historico}\n</historico>\n` : "",
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
  /** Padrão: WhatsApp. O painel espera a resposta na própria requisição. */
  canal?: CanalDoAgente;
}

/** Como cada canal enfileira: o WhatsApp responde depois; o painel espera na própria requisição. */
const PERFIL_DO_CANAL: Record<CanalDoAgente, { tipo: string; effort: string; prioridade: number; prazoMs: number; timeoutS: number }> = {
  // WhatsApp é conversa: na frente de pedidos longos; se o gateway não pegar em 75 s, o relógio
  // do banco (_ai_gateway_reap) falha o job e a entrega refaz pelo OpenRouter. Effort "low" como
  // o loop do OpenRouter no WhatsApp.
  whatsapp: { tipo: TIPO_DO_JOB, effort: "low", prioridade: 50, prazoMs: 75_000, timeoutS: 150 },
  // Painel: a tela está esperando — prazo curto para o gateway pegar (a própria edge refaz pelo
  // OpenRouter se não pegar) e teto que cabe na janela da edge. Effort "medium" como no painel.
  panel: { tipo: TIPO_DO_PAINEL, effort: "medium", prioridade: 60, prazoMs: 20_000, timeoutS: 110 },
};

/** A linha de ai_jobs do turno (pura, para testar). */
export function linhaDoJob(t: TurnoParaOMax, token: string, tokenSha256: string, agora = Date.now()): Record<string, unknown> {
  const canal: CanalDoAgente = t.canal ?? "whatsapp";
  const p = PERFIL_DO_CANAL[canal];
  return {
    source: "marineflow",
    requested_by: t.appUserId,
    provider: "claude-local",
    model: t.modelo,
    task_profile: "erp_agent",
    response_format: "text",
    prompt: transcreverConversa(t.messages, canal),
    input: {
      system: textoDoSistema(t.system),
      mcp_token: token,
      ferramentas: {
        visiveis: t.ferramentas.tools.map((f) => f.name),
        rede: Object.keys(t.ferramentas.alcancaveisPelaRede),
      },
      sessao: t.sessionId,
      canal,
      texto: t.texto,
    },
    metadata: {
      tipo: p.tipo,
      versao: 1,
      effort: p.effort,
      session_id: t.sessionId,
      ...(canal === "whatsapp" ? { phone: t.phone } : {}),
      user_id: t.appUserId,
      mcp_token_sha256: tokenSha256,
    },
    priority: p.prioridade,
    timeout_seconds: p.timeoutS,
    max_attempts: 1,
    allow_fallback: false,
    deadline_at: new Date(agora + p.prazoMs).toISOString(),
  };
}

// deno-lint-ignore no-explicit-any
export async function enfileirarTurnoNoMax(admin: any, t: TurnoParaOMax): Promise<string> {
  const token = novoTokenDoMcp();
  const { data, error } = await admin.from("ai_jobs").insert(linhaDoJob(t, token, await sha256Hex(token))).select("id").single();
  if (error || !data?.id) throw new Error(`não consegui enfileirar o turno no Claude Max: ${error?.message ?? "sem id"}`);
  return data.id as string;
}

/** O que a edge do painel faz com o job que está esperando (pura, para testar). */
export type DesfechoDoPainel =
  | { tipo: "pronto" }
  | { tipo: "esperar" }
  | { tipo: "reserva"; motivo: string }
  | { tipo: "tarde" };

export function desfechoDoPainel(
  job: { status: string; started_at?: string | null; error_code?: string | null } | null,
  decorridoMs: number,
  limites = { pegarMs: 20_000, esperarMs: 110_000 },
): DesfechoDoPainel {
  if (!job) return { tipo: "reserva", motivo: "job sumiu" };
  if (job.status === "completed") return { tipo: "pronto" };
  if (job.status === "failed" || job.status === "cancelled") return { tipo: "reserva", motivo: job.error_code || job.status };
  if (job.status === "pending" && decorridoMs > limites.pegarMs) return { tipo: "reserva", motivo: "o gateway não pegou o pedido a tempo" };
  if (decorridoMs > limites.esperarMs) return { tipo: "tarde" };
  return { tipo: "esperar" };
}
