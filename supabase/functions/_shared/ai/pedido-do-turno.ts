// O que o SISTEMA diz sobre o que o turno fez e decidiu — nunca o modelo (aprovação em lote, Fase 1, 29/10/2026).
//
// "IA pensa, sistema preenche": quem conta o que entrou, o que falhou e como uma pendência terminou é o banco. Em 90
// dias, 6 de 11 respostas do modelo a "você fez?" saíram erradas; 20 gravações diretas falharam em 17 turnos e o texto
// final citou uma; o "sim" do WhatsApp nunca entrava na conversa (0 de 53), então o modelo não sabia o que já tinha sido
// feito. Tudo aqui é texto montado do banco ou do resultado das ferramentas, e o que vai para a conversa é TEXTO —
// nunca um tool_result solto, que a API recusa (400) sem o tool_use dele.
import { tituloDaAcao, type ToolEvent } from "./agent.ts";
import { ehLeituraPeloNome } from "./perfil-operacao.ts";
import { ERRO_DO_SISTEMA_PARA_O_DONO, erroParaODono } from "./whatsapp-resposta.ts";

/**
 * Uma gravação que rodou direto (sem "sim") e voltou com erro. `depoisDeuCerto` = quantas vezes a MESMA ação deu certo
 * numa ida seguinte ao modelo (pode ser a tentativa de novo, pode ser outro item — o recibo diz o fato, não adivinha).
 */
export interface FalhaDeGravacao {
  ferramenta: string;
  erro: string;
  depoisDeuCerto?: number;
}

const LIMITE_DE_MOTIVOS = 5;

/**
 * As ferramentas de risco baixo que rodam direto, não têm prefixo de leitura no nome (perfil-operacao.ts,
 * ehLeituraPeloNome) e SÓ LEEM — conferido no execute de cada uma em 29/10/2026 (as RPCs que chamam são STABLE).
 * Fora daqui, toda ferramenta que não é leitura pelo nome conta como "pode ter gravado": na dúvida, avisar em vez de
 * refazer o turno, e o recibo fala da falha.
 */
export const SO_LEEM_SEM_PREFIXO: ReadonlySet<string> = new Set([
  "agenda_ver", "analise_do_negocio", "gastos_por_categoria", "ler_email", "preview_fiscal_note", "preview_fiscal_service_note",
  "size_dc_cable", "suggest_suppliers", "identify_contact", "sugerir_conciliacao", "optimize_text", "agent_health_report",
  "maintenance_reminder_metrics", "survey_material_list", "suggest_maintenance_plans", "present_options",
]);

/** A ferramenta pode ter gravado algo (cadastro, OS, agenda, mensagem)? A régua do recibo e da guarda da reserva. */
export function podeGravar(nome: string): boolean {
  return !!nome && !ehLeituraPeloNome(nome) && !SO_LEEM_SEM_PREFIXO.has(nome);
}

function temErro(resultado: unknown): boolean {
  return resultado !== null && typeof resultado === "object" && Boolean((resultado as { error?: unknown }).error);
}

/**
 * "Conferido pelo sistema": as gravações que rodaram direto e deram erro. Só fala de falha real (rodou e devolveu
 * `error`) e nunca conta gravação certa — resultado sem erro nem sempre gravou (needs_choice, ja_cadastrado), e um
 * "nenhuma falhou" seria a mentira de outro jeito. Quando a mesma ação deu certo numa ida seguinte ao modelo, diz isso
 * na linha: em 90 dias, 9 das 20 falhas foram seguidas da mesma ação dando certo ("Montar orçamento" sem a embarcação →
 * cadastra a embarcação → monta de novo), mas também pode ser OUTRO item — esconder seria apostar. "" = nada a dizer.
 */
export function reciboDasGravacoes(falhas: FalhaDeGravacao[]): string {
  if (falhas.length === 0) return "";
  // as iguais (mesma ação, mesmo motivo) numa linha só: "Remover item do orçamento: Item não encontrado (4×)"
  const grupos = new Map<string, { titulo: string; motivo: string; n: number; depois: number }>();
  for (const f of falhas) {
    const titulo = tituloDaAcao(f.ferramenta);
    const paraODono = erroParaODono(f.erro);
    const motivo = (paraODono === ERRO_DO_SISTEMA_PARA_O_DONO ? "erro do sistema (já anotado)" : paraODono).replace(/[\s.]+$/, "");
    const chave = `${titulo}\u0000${motivo}`;
    const g = grupos.get(chave);
    if (g) {
      g.n++;
      g.depois = Math.max(g.depois, f.depoisDeuCerto ?? 0);
    } else grupos.set(chave, { titulo, motivo, n: 1, depois: f.depoisDeuCerto ?? 0 });
  }
  const linhas = [...grupos.values()].map((g) =>
    `- ${g.titulo}: ${g.motivo}${g.n > 1 ? ` (${g.n}×)` : ""}${g.depois > 0 ? ` — depois a mesma ação deu certo ${g.depois}×` : ""}`
  );
  const mostradas = linhas.slice(0, LIMITE_DE_MOTIVOS);
  if (linhas.length > LIMITE_DE_MOTIVOS) mostradas.push(`- e mais ${linhas.length - LIMITE_DE_MOTIVOS} motivo(s)`);
  const cabeca = falhas.length === 1 ? "1 tentativa de gravar deu erro" : `${falhas.length} tentativas de gravar deram erro`;
  return `⚠️ Conferido pelo sistema: ${cabeca}.\n${mostradas.join("\n")}`;
}

/**
 * Uma execução direta do turno, na ordem em que rodou. `rodada` = a ida ao modelo em que a chamada veio (no Max, que não
 * tem rodada, a hora: chamadas a mais de 1,5 s uma da outra são de idas diferentes — medido em 28/10).
 */
interface Execucao {
  ferramenta: string;
  erro: string | null;
  rodada: number;
}

const INTERVALO_DE_UMA_IDA_AO_MODELO_MS = 1_500;

/**
 * Todas as falhas, cada uma com quantas vezes a mesma ação deu certo numa ida SEGUINTE ao modelo. A mesma ação dando
 * certo na mesma resposta do modelo é outro item do lote, não conta.
 */
function falhasDoTurno(execucoes: Execucao[]): FalhaDeGravacao[] {
  return execucoes.flatMap((e, i) => {
    if (e.erro === null) return [];
    const depoisDeuCerto = execucoes.filter((o, j) => j > i && o.erro === null && o.ferramenta === e.ferramenta && o.rodada > e.rodada).length;
    return [{ ferramenta: e.ferramenta, erro: e.erro, ...(depoisDeuCerto ? { depoisDeuCerto } : {}) }];
  });
}

/** As falhas do turno pelo OpenRouter: a gravação que rodou agora (executou) e voltou com erro. */
export function falhasDosEventos(eventos: ToolEvent[]): FalhaDeGravacao[] {
  return falhasDoTurno(
    eventos
      .filter((e) => e.executou === true && podeGravar(e.ferramenta ?? e.name))
      .map((e) => ({
        ferramenta: e.ferramenta ?? e.name,
        erro: temErro(e.result) ? String((e.result as { error: unknown }).error) : null,
        rodada: e.rodada ?? 0,
      })),
  );
}

/**
 * As falhas do turno pelo Claude Max: a auditoria que o erp-mcp gravou com `turno` = o job (as ferramentas rodam lá,
 * uma requisição por chamada). Leitura que falha devolve [] — o recibo só fala do que o sistema conseguiu ler.
 */
// deno-lint-ignore no-explicit-any
export async function falhasDaAuditoria(admin: any, sessionId: string, turnoId: string): Promise<FalhaDeGravacao[]> {
  try {
    const { data, error } = await admin
      .from("ai_operator_audit")
      .select("event_type, payload, created_at")
      .eq("session_id", sessionId)
      .eq("payload->>turno", turnoId)
      .like("event_type", "tool:%")
      .order("created_at", { ascending: true })
      .limit(500);
    if (error) return [];
    const linhas = ((data ?? []) as Array<{ event_type: string; payload: Record<string, unknown> | null; created_at?: string | null }>)
      .map((l) => ({
        ferramenta: l.event_type.slice("tool:".length),
        erro: typeof l.payload?.erro === "string" && l.payload.erro.trim() ? l.payload.erro : null,
        quando: l.created_at ? Date.parse(l.created_at) : 0,
      }));
    // sem rodada no Max: uma ida nova ao modelo começa quando a chamada vem 1,5 s ou mais depois da anterior (contando
    // as leituras, que também são chamadas do modelo)
    let rodada = 0;
    const execucoes = linhas.map((l, i) => {
      if (i > 0 && l.quando - linhas[i - 1].quando >= INTERVALO_DE_UMA_IDA_AO_MODELO_MS) rodada++;
      return { ferramenta: l.ferramenta, erro: l.erro, rodada };
    });
    return falhasDoTurno(execucoes.filter((e) => podeGravar(e.ferramenta)));
  } catch {
    return [];
  }
}

/**
 * Acrescenta o texto do sistema à última fala do assistente no histórico do turno (o que vai ser gravado na conversa),
 * para o modelo ler na próxima vez. Não mexe na mensagem que vai ao dono — quem chama decide onde ela aparece.
 */
export function anexarAoHistoricoDoTurno(messages: Array<{ role: string; content: unknown }>, texto: string): void {
  if (!texto) return;
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i];
    if (m.role !== "assistant") continue;
    if (typeof m.content === "string") {
      m.content = m.content ? `${m.content}\n\n${texto}` : texto;
      return;
    }
    if (Array.isArray(m.content)) {
      const blocos = m.content as Array<{ type: string; text?: string }>;
      for (let j = blocos.length - 1; j >= 0; j--) {
        if (blocos[j].type === "text") {
          blocos[j].text = blocos[j].text ? `${blocos[j].text}\n\n${texto}` : texto;
          return;
        }
      }
      blocos.push({ type: "text", text: texto });
    }
    return;
  }
}

/** O PIN (e qualquer número de 3 a 8 dígitos) não vai para a conversa: "sim 4321" fica "sim ••••". */
export function mascararPin(texto: string): string {
  return texto.replace(/\b\d{3,8}\b/g, "••••");
}

/**
 * Grava na conversa a resposta do dono a uma pendência no WhatsApp (o "sim"/"não", com o PIN mascarado) e o que o
 * sistema respondeu, 1 ms depois — sem os dois na mesma hora, a ordem volta indefinida do banco (precedente:
 * secretario/confirmar.ts). Até 29/10/2026 nada disso entrava: 0 das 53 aprovações pelo WhatsApp em 90 dias, e o modelo
 * respondia "você fez?" sem saber. Nunca lança: a conversa é enriquecimento, a decisão já aconteceu.
 */
export async function gravarDecisaoNaConversa(
  // deno-lint-ignore no-explicit-any
  admin: any,
  p: { sessionId: string; resposta: string; texto: string; agora?: Date },
): Promise<void> {
  if (!p.texto.trim()) return;
  const agora = p.agora ?? new Date();
  try {
    const { error } = await admin.from("ai_operator_messages").insert([
      { session_id: p.sessionId, role: "user", content: mascararPin(p.resposta), source: "whatsapp", created_at: agora.toISOString() },
      { session_id: p.sessionId, role: "assistant", content: p.texto, source: "whatsapp", created_at: new Date(agora.getTime() + 1).toISOString() },
    ]);
    if (error) throw error;
  } catch (e) {
    console.error("[ai-agent][whatsapp] decisão: falha ao gravar na conversa:", (e as { message?: string })?.message ?? e);
  }
}

/** Uma pendência como o banco a guarda — o que o desfecho precisa. */
export interface PendenciaDecidida {
  title?: string | null;
  status?: string | null;
  executed_at?: string | null;
  rejected_at?: string | null;
  approved_at?: string | null;
  expires_at?: string | null;
  result?: unknown;
}

function quandoFoi(iso: string | null | undefined, agora: Date): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const dia = (x: Date) => x.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
  const hora = d.toLocaleTimeString("pt-BR", { timeZone: "America/Sao_Paulo", hour: "2-digit", minute: "2-digit" });
  return dia(d) === dia(agora)
    ? ` às ${hora}`
    : ` em ${d.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo", day: "2-digit", month: "2-digit" })} às ${hora}`;
}

/**
 * Como uma pendência que já saiu de "pending" terminou, lido do banco (aprovação em lote, 29/10/2026). Até aqui o
 * WhatsApp dizia "Essa pendência não existe mais ou já foi decidida" e o painel "Esta pendência já foi rejected" — o
 * dono não sabia se tinha sido feito.
 */
export function textoDoDesfecho(p: PendenciaDecidida | null, agora: Date = new Date()): string {
  if (!p) return "Esse pedido não existe mais. Nada foi feito agora.";
  const titulo = String(p.title || "O pedido").trim();
  switch (p.status) {
    case "executed":
      return `Esse pedido já tinha sido decidido: ✅ ${titulo} — executado${quandoFoi(p.executed_at, agora)}.`;
    case "failed": {
      const erro = (p.result as { error?: unknown } | null)?.error;
      return `Esse pedido já tinha sido decidido: ⚠️ ${titulo} — falhou${quandoFoi(p.executed_at, agora)}: ${erroParaODono(erro)}`;
    }
    case "rejected":
      return `Esse pedido já tinha sido decidido: ❌ ${titulo} — cancelado${quandoFoi(p.rejected_at, agora)}. Nada foi feito.`;
    case "expired":
      return `⏰ ${titulo} — venceu sem resposta${quandoFoi(p.expires_at, agora)}. Nada foi feito; se ainda quiser, peça de novo.`;
    case "approved":
      return `⏳ ${titulo} — aprovado${quandoFoi(p.approved_at, agora)} e ainda sem resultado. Confira antes de pedir de novo.`;
    default:
      return `Esse pedido não está mais esperando resposta (${titulo}). Nada foi feito agora.`;
  }
}

/**
 * Um nome que o erp-mcp guardou em ai_jobs.metadata.ferramentas_usadas pode ter gravado algo? A ferramenta_extra vem
 * como "ferramenta_extra:<ferramenta chamada>" e, quando só pediu o esquema, "ferramenta_extra:descrever:<ferramenta>"
 * (nada roda).
 */
export function nomeQuePodeTerGravado(nome: string): boolean {
  const real = nome.startsWith("ferramenta_extra:") ? nome.slice("ferramenta_extra:".length) : nome;
  if (!real || real.startsWith("descrever:")) return false;
  // registro anterior a 29/10/2026: "ferramenta_extra" sem dizer qual ferramenta ela chamou
  if (real === "ferramenta_extra") return true;
  return podeGravar(real);
}

/**
 * O job do Claude Max deixou trabalho feito antes de falhar? Pendência criada, fluxo que já falou com o dono ou alguma
 * ferramenta que não é leitura. Refazer esse turno pelo OpenRouter repetiria gravações e duplicaria pendências
 * (aprovação em lote, Fase 1 — a guarda da reserva).
 */
export function jobDeixouTrabalho(meta: Record<string, unknown> | null | undefined): boolean {
  const interrupcao = (meta?.interrupcao ?? null) as Record<string, unknown> | null;
  if (interrupcao?.proposal || interrupcao?.fluxo) return true;
  const usadas = Array.isArray(meta?.ferramentas_usadas) ? (meta!.ferramentas_usadas as unknown[]) : [];
  return usadas.some((n) => typeof n === "string" && nomeQuePodeTerGravado(n));
}

/**
 * O mesmo pela auditoria (a lista do job é diagnóstico e pode ter ficado de fora do metadata cheio). Leitura que falha
 * conta como "deixou trabalho": na dúvida, avisar em vez de refazer.
 */
// deno-lint-ignore no-explicit-any
export async function trabalhoNaAuditoria(admin: any, sessionId: string, turnoId: string): Promise<boolean> {
  try {
    const { data, error } = await admin
      .from("ai_operator_audit")
      .select("event_type")
      .eq("session_id", sessionId)
      .eq("payload->>turno", turnoId)
      .limit(500);
    if (error) return true;
    return ((data ?? []) as Array<{ event_type: string }>).some((l) => {
      const [tipo, nome] = [l.event_type.split(":")[0], l.event_type.split(":").slice(1).join(":")];
      return tipo === "pending_action" || (tipo === "tool" && nomeQuePodeTerGravado(nome));
    });
  } catch {
    return true;
  }
}

/** O aviso de quando o Claude Max caiu depois de já ter feito algo (a reserva não refaz, para não repetir). */
export function avisoDoTurnoInterrompido(codigo: string | null | undefined): string {
  return `⚠️ O assistente parou no meio desta resposta (${codigo || "falha do Claude Max"}). O que ele já tinha feito ficou registrado e não foi repetido — confira antes de pedir de novo o que faltou.`;
}
