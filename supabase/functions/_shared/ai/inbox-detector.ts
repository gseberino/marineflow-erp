// Detector de compromissos em conversa — núcleo da Caixa de Entrada da Agenda (Fase 9).
// Lógica pura + chamada LLM isolada, para ser testável sem rede.
// Princípio: SUGERIR ≫ CRIAR. Nada aqui grava tarefa; só propõe, sempre com a frase
// literal que originou a proposta (evidência). Sem evidência → descarta a proposta.

import { callClaude, type ClaudeToolSchema } from "./anthropic.ts";
import { MODEL_LITE } from "./models.ts";

export type DetectorKind = "promise" | "client_request" | "third_party_deadline" | "followup";

export interface ConversationMessage {
  id: string;
  direction: string;       // 'inbound' | 'outbound'
  body: string | null;
  occurred_at: string;
  message_type?: string | null;
}

export interface RawProposal {
  title: string;
  evidence: string;
  detector: DetectorKind;
  confidence: number;
  due_date?: string | null;   // YYYY-MM-DD
  time?: string | null;       // HH:MM
  priority?: string | null;
  evidence_message_index?: number | null;
}

export interface Proposal extends RawProposal {
  source_message_id: string | null;
  evidence_at: string | null;
  suggested_due_at: string | null;
  suggested_start_at: string | null;
  kind: "task" | "appointment";
}

/** Limiar por detector: quanto mais ruidoso o sinal, mais alta a régua. */
export const CONFIDENCE_FLOOR: Record<DetectorKind, number> = {
  promise: 0.6,
  client_request: 0.65,
  third_party_deadline: 0.7,
  followup: 0.75,
};

/** Mensagens curtas/sem conteúdo não geram compromisso — filtra antes de gastar LLM. */
export function isWorthAnalyzing(msgs: ConversationMessage[]): boolean {
  const texts = msgs
    .map((m) => (m.body || "").trim())
    .filter((t) => t.length > 0 && t !== "[audio]" && t !== "[imagem]" && t !== "[documento]");
  if (texts.length === 0) return false;
  const totalChars = texts.reduce((s, t) => s + t.length, 0);
  // Conversa só de "ok/obrigado/bom dia" não vira tarefa
  return totalChars >= 40;
}

/** Normaliza a proposta crua do modelo: valida evidência, limiar e datas. */
export function normalizeProposal(
  raw: RawProposal,
  msgs: ConversationMessage[],
  nowBRT: Date,
): Proposal | null {
  const title = String(raw.title || "").trim();
  const evidence = String(raw.evidence || "").trim();
  if (!title || title.length < 4) return null;
  // Evidência é obrigatória e precisa EXISTIR na conversa (anti-alucinação).
  if (!evidence || evidence.length < 8) return null;
  const haystack = msgs.map((m) => (m.body || "").toLowerCase()).join("\n");
  const needle = evidence.toLowerCase().slice(0, 40);
  if (!haystack.includes(needle)) return null;

  const detector = raw.detector;
  if (!CONFIDENCE_FLOOR[detector]) return null;
  const confidence = Number(raw.confidence);
  if (!Number.isFinite(confidence) || confidence < CONFIDENCE_FLOOR[detector]) return null;

  // Mensagem-fonte: índice informado pelo modelo, ou a que contém a evidência
  let src: ConversationMessage | undefined;
  const idx = raw.evidence_message_index;
  if (typeof idx === "number" && idx >= 0 && idx < msgs.length) src = msgs[idx];
  if (!src) src = msgs.find((m) => (m.body || "").toLowerCase().includes(needle));

  const dateStr = raw.due_date && /^\d{4}-\d{2}-\d{2}$/.test(raw.due_date) ? raw.due_date : null;
  const timeStr = raw.time && /^\d{2}:\d{2}$/.test(raw.time) ? raw.time : null;

  let suggested_due_at: string | null = null;
  let suggested_start_at: string | null = null;
  if (dateStr && timeStr) {
    suggested_start_at = new Date(`${dateStr}T${timeStr}:00-03:00`).toISOString();
  } else if (dateStr) {
    suggested_due_at = new Date(`${dateStr}T08:00:00-03:00`).toISOString();
  }
  // Data no passado não faz sentido para compromisso futuro — descarta a data, mantém a tarefa
  if (suggested_due_at && new Date(suggested_due_at) < nowBRT) suggested_due_at = null;
  if (suggested_start_at && new Date(suggested_start_at) < nowBRT) {
    suggested_start_at = null;
  }

  const priority = ["low", "normal", "high", "urgent"].includes(String(raw.priority))
    ? String(raw.priority) : "normal";

  return {
    ...raw,
    title,
    evidence,
    confidence,
    priority,
    kind: suggested_start_at ? "appointment" : "task",
    suggested_due_at,
    suggested_start_at,
    source_message_id: src?.id ?? null,
    evidence_at: src?.occurred_at ?? null,
  };
}

const PROPOSE_TOOL: ClaudeToolSchema = {
  name: "propose_tasks",
  description: "Registra os compromissos concretos encontrados na conversa. Se não houver nenhum, chame com lista vazia.",
  input_schema: {
    type: "object",
    properties: {
      proposals: {
        type: "array",
        items: {
          type: "object",
          properties: {
            title: { type: "string", description: "A ação, no imperativo e específica. Ex.: 'Ligar para o Carlos sobre o orçamento da lancha'." },
            evidence: { type: "string", description: "TRECHO LITERAL e contínuo da conversa que prova o compromisso. Copie exatamente, sem parafrasear." },
            evidence_message_index: { type: "number", description: "Índice [n] da mensagem de onde veio a evidência." },
            detector: { type: "string", enum: ["promise", "client_request", "third_party_deadline", "followup"] },
            confidence: { type: "number", description: "0 a 1. Use <0.6 quando for interpretação sua, não algo explícito." },
            due_date: { type: "string", description: "YYYY-MM-DD se a conversa indicar dia. Omita se não houver." },
            time: { type: "string", description: "HH:MM só se houver hora marcada explícita." },
            priority: { type: "string", enum: ["low", "normal", "high", "urgent"] },
          },
          required: ["title", "evidence", "detector", "confidence"],
        },
      },
    },
    required: ["proposals"],
  },
};

export function buildDetectorPrompt(hojeBRT: string, contactLabel: string): string {
  return `Você analisa uma conversa de WhatsApp de uma empresa de manutenção náutica (HBR Marine) e extrai APENAS compromissos concretos que geram trabalho para a EQUIPE DA HBR.

Hoje é ${hojeBRT} (America/Sao_Paulo). Conversa com: ${contactLabel}.

O que É compromisso (proponha):
- promise: alguém da HBR prometeu algo ("vou te mandar o orçamento amanhã", "te ligo segunda").
- client_request: o cliente pediu algo que exige ação ("consegue olhar meu motor essa semana?").
- third_party_deadline: terceiro deu um prazo que precisa ser acompanhado ("a peça chega dia 12").
- followup: pedido claro que ficou SEM resposta da HBR e precisa de retorno.

O que NÃO é compromisso (NÃO proponha):
- Saudações, agradecimentos, confirmações ("ok", "obrigado", "perfeito").
- Assunto já resolvido dentro da própria conversa.
- Conversa pessoal, spam, corrente, propaganda.
- Coisas que a HBR já fez (passado concluído).
- Suposição sua sem frase que sustente.

Regras invioláveis:
1. Toda proposta precisa de "evidence": um TRECHO LITERAL copiado da conversa. Se você não consegue copiar uma frase que prove, NÃO proponha.
2. Prefira NÃO propor a propor errado. Uma caixa de entrada com lixo é pior que vazia.
3. Título no imperativo, específico e curto (máx. ~70 caracteres), com o nome de quem/o quê.
4. Só coloque data/hora se a conversa disser. Nunca invente prazo.
5. No máximo 3 propostas por conversa — as mais importantes.`;
}

/** Formata a conversa para o modelo, com índices para a evidência. */
export function formatConversation(msgs: ConversationMessage[]): string {
  return msgs.map((m, i) => {
    const quem = m.direction === "inbound" ? "CLIENTE" : "HBR";
    const hora = new Date(m.occurred_at).toLocaleString("pt-BR", {
      timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
    });
    return `[${i}] (${hora}) ${quem}: ${(m.body || "").slice(0, 500)}`;
  }).join("\n");
}

/** Roda o detector numa conversa. Devolve propostas já normalizadas e filtradas. */
export async function detectInConversation(
  msgs: ConversationMessage[],
  contactLabel: string,
  now: Date = new Date(),
): Promise<Proposal[]> {
  if (!isWorthAnalyzing(msgs)) return [];

  const hojeBRT = new Date(now.getTime() - 3 * 3600000).toISOString().slice(0, 10);
  const result = await callClaude({
    model: MODEL_LITE,
    system: [{ type: "text", text: buildDetectorPrompt(hojeBRT, contactLabel) }],
    messages: [{ role: "user", content: [{ type: "text", text: formatConversation(msgs) }] }],
    tools: [PROPOSE_TOOL],
    maxTokens: 1500,
  });

  const call = result.content.find(
    (b): b is { type: "tool_use"; id: string; name: string; input: Record<string, unknown> } =>
      b.type === "tool_use" && b.name === "propose_tasks",
  );
  if (!call) return [];
  const raw = (call.input?.proposals as RawProposal[]) || [];
  if (!Array.isArray(raw)) return [];

  return raw
    .slice(0, 3)
    .map((p) => normalizeProposal(p, msgs, now))
    .filter((p): p is Proposal => p !== null);
}
