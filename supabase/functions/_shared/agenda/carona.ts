// Agenda de Produção, Fase 3 (P6, 24/10/2026; spec-fase3.md §9.5): a carona — no fim de uma resposta do assistente ao
// DONO sobre UMA OS, no máximo uma pergunta aberta dela ("Aproveitando: o painel 7\" do Nelson … Chegou?"), uma vez por OS
// a cada carona_por_os_dias. Quem decide se cabe, qual pergunta e quando é o banco (agenda_carona, migration
// 20261026100500): aqui só se lê de quais OS o turno falou e se junta o texto pronto.
//
//   osDoTurno(eventos)        puro: as OS que as ferramentas do turno citaram (os, p_os, service_order_id, os_id nos
//                             argumentos e no resultado), de uma lista fechada de ferramentas; como vieram (número, nome
//                             ou id). O número vira id no banco (agenda_resolver_os), nunca aqui.
//   caronaDoTurno(...)        a RPC agenda_carona; null quando não cabe. Nunca lança (erro = sem carona).
//   comCarona(...)            o texto do turno com a carona no fim (ou igual). Nunca lança.
//   aplicarCarona(turno, c)   junta a carona na resposta do loop e na última mensagem do assistente (para o histórico ter
//                             o que o dono leu e o modelo saber, no turno seguinte, que a pergunta foi da agenda).
//
// Nunca age com cartão de "sim" (proposal), lista de opções (options), fluxo que já falou (fluxo) nem erro no turno: a
// carona não disputa a atenção com uma decisão.

/** As ferramentas cujas OS contam para a carona (a OS dita ou mostrada no turno). */
export const FERRAMENTAS_DA_CARONA: ReadonlySet<string> = new Set([
  "agenda_ver", "os_planejar", "material_informar", "os_registrar_andamento", "get_service_order",
  "update_service_order_status", "schedule_service_order", "add_service_order_item", "registrar_diaria",
]);

/** As chaves em que uma ferramenta diz a OS (argumentos e resultado). */
const CHAVES_DA_OS = ["os", "p_os", "service_order_id", "os_id"] as const;

/** Mais do que isto já não tem carona (só cabe com UMA OS no turno): não vale a pena ler o resto. */
const MAX_REFERENCIAS = 10;

/** Um evento de ferramenta do turno (o ToolEvent do agent.ts). */
export interface EventoDaFerramenta {
  name: string;
  args?: unknown;
  result?: unknown;
}

function objeto(v: unknown): Record<string, unknown> | null {
  return v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : null;
}

/** "OS-00112", "Nelson", um id; listas também (registrar_diaria leva várias). Texto vazio e não-texto ficam de fora. */
function referencias(v: unknown): string[] {
  const lista = Array.isArray(v) ? v : [v];
  return lista
    .map((x) => (typeof x === "number" && Number.isFinite(x) ? String(x) : x))
    .filter((x): x is string => typeof x === "string")
    .map((x) => x.replace(/\s+/g, " ").trim())
    .filter((x) => x.length > 0 && x.length <= 80);
}

/**
 * As OS do turno, na ordem em que apareceram e sem repetir: de cada ferramenta da lista, as chaves os, p_os,
 * service_order_id e os_id dos argumentos e do resultado. Puro.
 */
export function osDoTurno(eventos: readonly EventoDaFerramenta[] | null | undefined): string[] {
  const vistas: string[] = [];
  for (const e0 of eventos ?? []) {
    // a ferramenta_extra (perfil enxuto do admin) leva a de verdade em {nome, argumentos}: vale a de dentro
    const e = e0?.name === "ferramenta_extra"
      ? { name: String(objeto(e0.args)?.nome ?? ""), args: objeto(e0.args)?.argumentos, result: e0.result }
      : e0;
    if (!e || !FERRAMENTAS_DA_CARONA.has(e.name)) continue;
    for (const fonte of [objeto(e.args), objeto(e.result)]) {
      if (!fonte) continue;
      for (const chave of CHAVES_DA_OS) {
        for (const r of referencias(fonte[chave])) {
          if (!vistas.includes(r)) vistas.push(r);
          if (vistas.length >= MAX_REFERENCIAS) return vistas;
        }
      }
    }
  }
  return vistas;
}

/**
 * As OS de um turno do Claude Max: o erp-mcp guarda em ai_jobs.metadata.os_do_turno (ai_job_registrar_os) o que
 * osDoTurno leu de cada ferramenta que rodou. Puro.
 */
export function osDoJob(metadata: unknown): string[] {
  const lista = objeto(metadata)?.os_do_turno;
  return Array.isArray(lista) ? referencias(lista).slice(0, MAX_REFERENCIAS) : [];
}

/** O que o turno trouxe além do texto: cartão de "sim", lista de opções, fluxo que já falou, erro. */
export interface TurnoDaCarona {
  proposal?: unknown;
  options?: unknown;
  fluxo?: unknown;
  error?: unknown;
}

/** O turno pede a atenção do dono para outra coisa (o "sim", a opção, o fluxo) ou falhou: sem carona. */
export function turnoSemCarona(turno: TurnoDaCarona | null | undefined): boolean {
  return !!(turno?.proposal || turno?.options || turno?.fluxo || turno?.error);
}

// deno-lint-ignore no-explicit-any
type Cliente = any;

export interface OpcoesDaCarona {
  canal?: "whatsapp" | "painel";
  /** só em teste: o dia e a hora (o banco usa os de Brasília) */
  hoje?: string;
  agora?: string;
}

/**
 * A carona do turno: o texto pronto do banco ("Aproveitando: …") ou null (não cabe: 0 ou 2+ OS, nenhuma pergunta aberta
 * dela, já teve carona na semana, a vigia não está ligada, não é o dono, o turno tem cartão/opções/fluxo). Nunca lança: o
 * erro do banco é sem carona (a resposta do assistente sai igual).
 */
export async function caronaDoTurno(
  admin: Cliente,
  autorId: string,
  refs: readonly string[],
  turno: TurnoDaCarona | null | undefined,
  opcoes: OpcoesDaCarona = {},
): Promise<string | null> {
  if (turnoSemCarona(turno) || !autorId || refs.length === 0) return null;
  try {
    const params: Record<string, unknown> = { p_autor: autorId, p_os: [...refs], p_canal: opcoes.canal ?? "whatsapp" };
    if (opcoes.hoje) params.p_hoje = opcoes.hoje;
    if (opcoes.agora) params.p_agora = opcoes.agora;
    const { data, error } = await admin.rpc("agenda_carona", params);
    if (error) return null;
    const texto = objeto(data)?.texto;
    return typeof texto === "string" && texto.startsWith("Aproveitando: ") ? texto : null;
  } catch {
    return null;
  }
}

/** O texto do turno com a carona no fim, num parágrafo seu. */
export function juntarCarona(texto: string, carona: string): string {
  const t = (texto ?? "").trimEnd();
  return t ? `${t}\n\n${carona}` : carona;
}

/** comCarona(admin, autor, refs, texto, turno): o texto com a carona, ou o mesmo texto. Nunca lança. */
export async function comCarona(
  admin: Cliente,
  autorId: string,
  refs: readonly string[],
  texto: string,
  turno: TurnoDaCarona | null | undefined,
  opcoes: OpcoesDaCarona = {},
): Promise<string> {
  const c = await caronaDoTurno(admin, autorId, refs, turno, opcoes);
  return c ? juntarCarona(texto, c) : texto;
}

/** Um bloco de conteúdo de mensagem (o formato nativo do loop: text, tool_use, tool_result). */
interface BlocoDeTexto {
  type: string;
  text?: string;
}

/**
 * Junta a carona na resposta do loop (message.content) e na ÚLTIMA mensagem do assistente (o bloco de texto dela, ou um
 * novo), para o histórico gravado ter o que o dono leu.
 */
export function aplicarCarona(
  turno: { message: { content: string }; messages?: Array<{ role: string; content: unknown }> },
  carona: string,
): void {
  turno.message.content = juntarCarona(turno.message.content, carona);
  const msgs = turno.messages ?? [];
  for (let i = msgs.length - 1; i >= 0; i--) {
    const m = msgs[i];
    if (m.role !== "assistant") continue;
    if (typeof m.content === "string") {
      m.content = juntarCarona(m.content, carona);
      return;
    }
    if (Array.isArray(m.content)) {
      const blocos = m.content as BlocoDeTexto[];
      for (let j = blocos.length - 1; j >= 0; j--) {
        if (blocos[j].type === "text") {
          blocos[j].text = juntarCarona(blocos[j].text ?? "", carona);
          return;
        }
      }
      blocos.push({ type: "text", text: carona });
    }
    return;
  }
}
