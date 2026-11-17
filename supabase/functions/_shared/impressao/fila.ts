// Imprimir na Brother do escritório pelo assistente (17/11/2026).
//
// Pedido do dono: "imprimir ordens de serviço, orçamentos e vias do técnico pelo assistente do WhatsApp, já que ele
// roda no PC que está no mesmo Wi-Fi da impressora — até um técnico pedindo e ele imprimindo". Decisões dele (17/11):
//   · só sob pedido (nada de impressão automática); o assistente só SUGERE na hora certa (o resumo da manhã);
//   · o dono e os técnicos podem pedir (o técnico só a via do técnico, que não leva preço);
//   · versão simples, sem nada sofisticado.
//
// O caminho reaproveita tudo o que existe:
//   PDF            → o mesmo do WhatsApp (gerar-e-guardar.ts / via-do-tecnico-envio.ts), 3 min no bucket privado
//   fila           → ai_jobs, a fila do HBR AI Gateway (provider 'local-print'); NENHUMA tabela nova
//   quem imprime   → o "HBR Print Worker" no PC do escritório (repo hbr-ai-gateway, worker hbr-pc-print), que só
//                    reivindica 'local-print' (ai_gateway_workers.allowed_providers) e imprime com o SumatraPDF
//   resposta       → esperamos o job terminar (até ~45 s) e dizemos a verdade: impresso, na fila da impressora, ou não.
//
// Um pedido = uma tentativa (max_attempts 1): repetir sozinho poderia imprimir duas vezes. Prazo curto (deadline_at):
// pedido feito com o PC desligado não sai horas depois, de surpresa.

// deno-lint-ignore no-explicit-any
type Admin = any;

export const PROVEDOR_DA_IMPRESSORA = "local-print";
export const WORKER_DA_IMPRESSORA = "hbr-pc-print";
export const MODELO_DO_JOB = "impressao-v1";
export const PERFIL_DO_JOB = "impressao";
export const PROMPT_DO_JOB = "imprimir";
export const TIPO_NO_METADATA = "impressao";
export const COPIAS_MAX = 5;
/** O worker manda sinal de vida a cada ~30 s (ai_gateway_ping/claim): mais de 3 min calado = fora do ar. */
export const VIVO_HA_MS = 3 * 60_000;
/** Quanto a tool espera o PC confirmar. O MCP da assinatura Max dá 120 s à tool; o PDF leva ~10 s antes. */
export const ESPERA_PADRAO_MS = 45_000;
/** Janela anti-duplicado: o mesmo papel pedido de novo nesse intervalo não sai duas vezes. */
export const JANELA_ANTI_DUPLICADO_MS = 2 * 60_000;

/** Por que o worker diz que a impressora não está disponível (ai_gateway_workers.estado), em palavras. */
const MOTIVOS_DO_WORKER: Record<string, string> = {
  sem_impressora: "a impressora não está instalada no PC do escritório",
  impressora_offline: "a impressora está desligada ou fora do Wi-Fi",
  impressora_com_erro: "a impressora está com erro (papel, tinta ou tampa aberta)",
  sem_sumatra: "falta o programa de impressão (SumatraPDF) no PC do escritório",
};

export function motivoDoWorker(reason: unknown): string {
  const r = String(reason ?? "");
  const codigo = r.split(":").pop() ?? r;
  return MOTIVOS_DO_WORKER[codigo] ?? MOTIVOS_DO_WORKER[r] ?? `a impressora está indisponível (${r || "sem motivo"})`;
}

const horaBR = (d: Date) =>
  new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit" }).format(d);

/** O programa da impressora está no ar? Lê o sinal de vida do worker. Nunca lança. */
export async function impressoraNoAr(admin: Admin, agora: Date = new Date()): Promise<{ ok: true } | { ok: false; motivo: string }> {
  try {
    const { data, error } = await admin.from("ai_gateway_workers")
      .select("enabled, last_seen_at, estado").eq("id", WORKER_DA_IMPRESSORA).maybeSingle();
    if (error) return { ok: false, motivo: `não consegui ver se a impressora está no ar (${error.message})` };
    if (!data) return { ok: false, motivo: "o programa da impressora ainda não foi instalado no PC do escritório" };
    if (data.enabled === false) return { ok: false, motivo: "a impressão pelo assistente está desligada" };
    const visto = data.last_seen_at ? new Date(data.last_seen_at) : null;
    if (!visto || agora.getTime() - visto.getTime() > VIVO_HA_MS) {
      return {
        ok: false,
        motivo: `o PC do escritório (ou o programa da impressora) está fora do ar${visto ? ` desde ${horaBR(visto)}` : ""}`,
      };
    }
    const prov = data.estado?.providers?.[PROVEDOR_DA_IMPRESSORA];
    if (prov && prov.available === false) return { ok: false, motivo: motivoDoWorker(prov.reason) };
    return { ok: true };
  } catch (e) {
    return { ok: false, motivo: `não consegui ver se a impressora está no ar (${e instanceof Error ? e.message : String(e)})` };
  }
}

export interface PedidoDeImpressao {
  /** URL assinada do PDF no Storage deste projeto (o worker recusa qualquer outra). */
  url: string;
  /** Nome do arquivo (aparece na fila do Windows). */
  nome: string;
  copias?: number;
  colorido?: boolean;
  /** "Via do técnico OS-00136", "Orçamento ORÇ-00086": vai para o registro. */
  descricao: string;
  /** Quem pediu: o usuário do sistema (dono/financeiro) ou a pessoa da equipe (payee). */
  pedidoPor: { usuario?: string | null; payee?: string | null; nome?: string | null };
  /** Chave anti-duplicado (o mesmo papel, pela mesma pessoa, em 2 min). */
  chave: string;
}

export type ResultadoDaImpressao =
  | { ok: true; situacao: "impresso" | "na_fila_da_impressora"; paginas: number | null; repetido?: false }
  | { ok: true; repetido: true }
  | { ok: false; motivo: string; aindaPodeSair?: boolean };

export function limitarCopias(c: unknown): number {
  const n = Math.trunc(Number(c));
  if (!Number.isFinite(n) || n < 1) return 1;
  return Math.min(n, COPIAS_MAX);
}

/** O mesmo papel já foi pedido há instantes (e não falhou)? Erro na leitura = não (melhor repetir que calar). */
export async function jaPedidoHaPouco(admin: Admin, chave: string, agora: Date = new Date()): Promise<boolean> {
  try {
    const desde = new Date(agora.getTime() - JANELA_ANTI_DUPLICADO_MS).toISOString();
    const { data, error } = await admin.from("ai_jobs").select("id")
      .eq("provider", PROVEDOR_DA_IMPRESSORA)
      .eq("metadata->>chave", chave)
      .in("status", ["pending", "processing", "completed"])
      .gte("created_at", desde)
      .limit(1);
    if (error) return false;
    return Array.isArray(data) && data.length > 0;
  } catch {
    return false;
  }
}

/** Quantos papéis esta pessoa da equipe já pediu hoje (Brasília). Erro = 0. */
export async function impressoesDeHojeDaPessoa(admin: Admin, payeeId: string, agora: Date = new Date()): Promise<number> {
  try {
    const dia = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" }).format(agora);
    const { count, error } = await admin.from("ai_jobs").select("id", { count: "exact", head: true })
      .eq("provider", PROVEDOR_DA_IMPRESSORA)
      .eq("metadata->>pedido_por_payee", payeeId)
      .gte("created_at", `${dia}T00:00:00-03:00`);
    if (error) return 0;
    return count ?? 0;
  } catch {
    return 0;
  }
}

const dormirPadrao = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** A linha de ai_jobs do pedido (o contrato do HBR Print Worker, versão 1). */
export function linhaDoJob(p: PedidoDeImpressao, agora: Date = new Date()) {
  return {
    source: "marineflow",
    provider: PROVEDOR_DA_IMPRESSORA,
    model: MODELO_DO_JOB,
    task_profile: PERFIL_DO_JOB,
    response_format: "json",
    prompt: PROMPT_DO_JOB,
    input: {
      versao: 1,
      arquivo: { url: p.url, nome: p.nome },
      copias: limitarCopias(p.copias),
      colorido: p.colorido !== false,
    },
    metadata: {
      tipo: TIPO_NO_METADATA,
      chave: p.chave,
      descricao: p.descricao.slice(0, 200),
      pedido_por_usuario: p.pedidoPor.usuario ?? null,
      pedido_por_payee: p.pedidoPor.payee ?? null,
      pedido_por_nome: p.pedidoPor.nome ?? null,
    },
    priority: 10,
    max_attempts: 1,
    timeout_seconds: 120,
    // A URL vale 3 min (gerar-e-guardar.ts); depois disso o pedido não tem mais o que imprimir.
    deadline_at: new Date(agora.getTime() + 2 * 60_000).toISOString(),
  };
}

/**
 * Põe o PDF na fila da impressora e espera o PC responder. Nunca lança.
 * `esperarMs` estourado: pedido ainda na fila = cancelado (nada sai depois, de surpresa); já com o PC = "pode sair".
 */
export async function imprimirPelaFila(
  admin: Admin,
  p: PedidoDeImpressao,
  o: { esperarMs?: number; intervaloMs?: number; dormir?: (ms: number) => Promise<void>; agora?: () => Date } = {},
): Promise<ResultadoDaImpressao> {
  const dormir = o.dormir ?? dormirPadrao;
  const agora = o.agora ?? (() => new Date());
  const esperarMs = o.esperarMs ?? ESPERA_PADRAO_MS;
  const intervaloMs = o.intervaloMs ?? 1_500;
  try {
    if (await jaPedidoHaPouco(admin, p.chave, agora())) return { ok: true, repetido: true };
    const { data: job, error } = await admin.from("ai_jobs").insert(linhaDoJob(p, agora())).select("id").single();
    if (error || !job?.id) return { ok: false, motivo: `não consegui pôr o pedido na fila da impressora (${error?.message ?? "sem id"})` };

    const inicio = agora().getTime();
    let ultimo = "pending";
    while (agora().getTime() - inicio < esperarMs) {
      await dormir(intervaloMs);
      const { data: linha, error: lerErr } = await admin.from("ai_jobs")
        .select("status, response, error, error_code").eq("id", job.id).maybeSingle();
      if (lerErr || !linha) continue;
      ultimo = linha.status;
      if (linha.status === "completed") {
        const d = linha.response?.data ?? {};
        const paginas = Number.isFinite(Number(d.paginas)) && Number(d.paginas) > 0 ? Number(d.paginas) : null;
        return { ok: true, situacao: d.situacao === "na_fila" ? "na_fila_da_impressora" : "impresso", paginas };
      }
      if (linha.status === "failed" || linha.status === "cancelled") {
        const motivo = linha.error_code === "deadline_exceeded"
          ? "o PC do escritório não pegou o pedido a tempo"
          : String(linha.error || "a impressão falhou");
        return { ok: false, motivo };
      }
    }
    if (ultimo === "pending") {
      // Ninguém pegou: cancela, para não sair horas depois. Se o worker pegou neste instante, o update não acha 'pending'.
      const { data: cancelado } = await admin.from("ai_jobs")
        .update({ status: "cancelled", completed_at: new Date().toISOString(), error_code: "cancelled", error: "Ninguém pegou o pedido a tempo." })
        .eq("id", job.id).eq("status", "pending").select("id");
      if (Array.isArray(cancelado) && cancelado.length) {
        return { ok: false, motivo: "o PC do escritório não pegou o pedido a tempo (pode estar ocupado ou desligado); nada foi impresso" };
      }
    }
    return { ok: false, aindaPodeSair: true, motivo: "a impressora ainda não confirmou; o papel pode sair em instantes" };
  } catch (e) {
    return { ok: false, motivo: `falha ao pedir a impressão (${e instanceof Error ? e.message : String(e)})` };
  }
}

/** A frase para quem pediu. `oque` = "a via do técnico da OS-00136". */
export function fraseDoResultado(oque: string, r: ResultadoDaImpressao, copias = 1): string {
  if (r.ok && r.repetido) return `Esse papel (${oque}) já foi para a impressora há instantes; não repeti.`;
  if (r.ok) {
    const pags = r.paginas ? ` (${r.paginas} página${r.paginas === 1 ? "" : "s"}${copias > 1 ? `, ${copias} cópias` : ""})` : copias > 1 ? ` (${copias} cópias)` : "";
    return r.situacao === "impresso"
      ? `🖨️ Impresso: ${oque}${pags}. Está na impressora do escritório.`
      : `🖨️ Mandei ${oque}${pags} para a impressora do escritório; está na fila dela e sai em instantes.`;
  }
  return r.aindaPodeSair
    ? `🖨️ Mandei ${oque} para a impressora, mas ela ainda não confirmou. Pode sair em instantes; se não sair, peça de novo.`
    : `Não consegui imprimir ${oque}: ${r.motivo}.`;
}
