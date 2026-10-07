// Caixa de sugestões da agenda pelo assistente (07/10/2026, frente operacional).
//
// Pedido do dono: "o que tem na caixa de sugestões?", "aceita a sugestão de ligar para o Miguel,
// mas amanhã às 10h", "descarta a sugestão do fornecedor de tinta", "aceita todas as de hoje".
//
// Caminho da tela, peça por peça (src/hooks/use-agenda.ts):
//   listar     → useSuggestions: agenda_suggestions pendentes, por confiança e data;
//   aceitar    → useAcceptSuggestion: cria a tarefa (source 'ai', nota com a origem e a frase)
//                e marca a sugestão accepted + resolved_at/resolved_by/created_task_id;
//   descartar  → useDismissSuggestion: dismissed + resolved_at/resolved_by/dismiss_reason.
// Não há função do banco para nada disso; a tool grava os mesmos campos.
//
// Diferenças de propósito em relação à tela (que a tela também deveria ter):
//   · só resolve sugestão AINDA pendente (a gravação confere status = pending) — aceitar duas
//     vezes a mesma criava duas tarefas;
//   · se marcar a sugestão falhar, a tarefa recém-criada é apagada — senão sobrava tarefa órfã
//     e a sugestão continuava na caixa;
//   · o service role do WhatsApp não tem RLS: quem não é admin só vê e resolve as sugestões
//     sem destinatário ou as dele (a mesma regra da policy agenda_suggestions_select).

import type { ToolCtx, ToolDef } from "./registry.ts";
import { comFusoDeBrasilia } from "../fuso.ts";
import { prioridadeDaTarefa } from "./agenda.ts";

const DETECTOR: Record<string, string> = {
  promise: "Você prometeu",
  client_request: "Cliente pediu",
  third_party_deadline: "Prazo combinado",
  followup: "Sem resposta",
  voice_note: "Seu recado",
};

const COLS =
  "id, title, kind, suggested_due_at, suggested_start_at, priority, evidence, confidence, detector, origin, contact_label, related_entity_type, related_entity_id, client_id, target_user_id, status, created_at";

const semAcento = (s: unknown) =>
  String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();

const PALAVRAS_VAZIAS = new Set(["de", "do", "da", "dos", "das", "o", "a", "os", "as", "e", "em", "no", "na", "com", "para", "pra", "um", "uma", "sugestao", "tarefa", "que"]);

/** Começo de hoje em Brasília, em ISO UTC. */
function inicioDeHojeBR(agora = new Date()): string {
  const dia = new Date(agora.getTime() - 3 * 3600_000).toISOString().slice(0, 10);
  return new Date(`${dia}T00:00:00-03:00`).toISOString();
}

// deno-lint-ignore no-explicit-any
type Sugestao = Record<string, any>;

/** Uma linha legível da sugestão — o que a tela mostra no cartão. */
function resumo(s: Sugestao) {
  return {
    id: s.id,
    titulo: s.title,
    tipo: s.kind === "appointment" ? "compromisso" : "tarefa",
    quando: s.suggested_start_at || s.suggested_due_at || null,
    contato: s.contact_label || null,
    motivo: DETECTOR[s.detector] || "Sugestão",
    origem: s.origin === "whatsapp" ? "conversa no WhatsApp" : "recado",
    prioridade: s.priority,
    frase: String(s.evidence ?? "").slice(0, 240),
    criada_em: s.created_at,
  };
}

/** As pendentes que quem pede pode ver (até 1000, o teto do PostgREST). */
async function pendentesVisiveis(ctx: ToolCtx, desde?: string): Promise<Sugestao[] | { error: string }> {
  let q = ctx.sb.from("agenda_suggestions").select(COLS).eq("status", "pending");
  if (ctx.userRole !== "admin") q = q.or(`target_user_id.is.null,target_user_id.eq.${ctx.userId}`);
  if (desde) q = q.gte("created_at", desde);
  const { data, error } = await q
    .order("confidence", { ascending: false })
    .order("created_at", { ascending: false })
    .range(0, 999);
  if (error) return { error: `Não consegui ler a caixa de sugestões: ${error.message}` };
  return (data ?? []) as Sugestao[];
}

/** Filtra pelo que foi dito: título e contato primeiro; a frase original só se nada casar. */
export function filtrarSugestoes(lista: Sugestao[], busca: unknown): Sugestao[] {
  const alvo = semAcento(busca);
  if (!alvo) return lista;
  const palavras = alvo.split(" ").filter((p) => p.length >= 3 && !PALAVRAS_VAZIAS.has(p));
  if (palavras.length === 0) return [];
  const casa = (texto: string) => palavras.every((p) => texto.includes(p));
  const porTitulo = lista.filter((s) => casa(semAcento(`${s.title} ${s.contact_label ?? ""}`)));
  if (porTitulo.length) return porTitulo;
  return lista.filter((s) => casa(semAcento(`${s.title} ${s.contact_label ?? ""} ${s.evidence ?? ""}`)));
}

const ehErroDeLeitura = (x: unknown): x is { error: string } => !!x && typeof x === "object" && !Array.isArray(x) && "error" in x;

/**
 * Quais sugestões o pedido aponta: ids, todas (de hoje) ou uma busca. Busca que casa com mais
 * de uma, sem "todas", devolve as opções — nunca escolhe sozinho.
 */
async function escolher(ctx: ToolCtx, args: Sugestao, limite: number): Promise<{ escolhidas: Sugestao[]; restantes: number } | { error: string; opcoes?: unknown[] }> {
  const todas = args.todas === true || args.todas_de_hoje === true;
  const ids: string[] = Array.isArray(args.ids) ? args.ids.map(String).filter(Boolean) : [];
  if (!ids.length && !todas && !String(args.busca ?? "").trim()) {
    return { error: "Diga qual sugestão: pelo texto (ex.: 'ligar para o Miguel'), pelo id (list_agenda_suggestions) ou 'todas'." };
  }
  const lidas = await pendentesVisiveis(ctx, args.todas_de_hoje === true ? inicioDeHojeBR() : undefined);
  if (ehErroDeLeitura(lidas)) return lidas;
  let escolhidas: Sugestao[];
  if (ids.length) {
    escolhidas = lidas.filter((s) => ids.includes(s.id));
    const faltam = ids.filter((id) => !escolhidas.some((s) => s.id === id));
    if (faltam.length) return { error: `${faltam.length === 1 ? "Uma sugestão pedida não está" : `${faltam.length} sugestões pedidas não estão`} mais pendente(s) na caixa (já resolvida ou de outra pessoa). Nada foi feito — confira com list_agenda_suggestions.` };
  } else {
    escolhidas = filtrarSugestoes(lidas, args.busca);
    if (!escolhidas.length) {
      return { error: String(args.busca ?? "").trim() ? `Nenhuma sugestão pendente fala de "${args.busca}".` : "Não há sugestão pendente na caixa." };
    }
    if (!todas && escolhidas.length > 1) {
      return { error: `"${args.busca}" serve para ${escolhidas.length} sugestões. Qual delas? (ou diga 'todas')`, opcoes: escolhidas.slice(0, 8).map(resumo) };
    }
  }
  return { escolhidas: escolhidas.slice(0, limite), restantes: Math.max(0, escolhidas.length - limite) };
}

const LIMITE_POR_VEZ = 30;

export const agendaSugestaoTools: ToolDef[] = [
  {
    name: "list_agenda_suggestions",
    description:
      "Lista a CAIXA DE SUGESTÕES da agenda — tarefas que o sistema achou nas conversas e recados e que esperam o dono aceitar ou descartar (Agenda › Caixa de entrada). " +
      "Use para 'o que tem na caixa de sugestões?', 'tem sugestão de tarefa?'. Mostra a frase original de cada uma. Filtros: busca (texto), de_hoje.",
    input_schema: {
      type: "object",
      properties: {
        busca: { type: "string", description: "Só as que falam disto (título, contato ou frase)." },
        de_hoje: { type: "boolean", description: "Só as que chegaram hoje." },
        limite: { type: "number", description: "Quantas mostrar (padrão 20, máx. 50)." },
      },
    },
    risk: "low",
    async execute(args, ctx) {
      const lidas = await pendentesVisiveis(ctx, args.de_hoje === true ? inicioDeHojeBR() : undefined);
      if (ehErroDeLeitura(lidas)) return lidas;
      const filtradas = filtrarSugestoes(lidas, args.busca);
      const limite = Math.min(Math.max(Number(args.limite) || 20, 1), 50);
      return {
        total_pendentes: filtradas.length,
        mostrando: Math.min(limite, filtradas.length),
        sugestoes: filtradas.slice(0, limite).map(resumo),
        ...(filtradas.length > limite ? { obs: `Há mais ${filtradas.length - limite} — refine pela busca ou peça as de hoje.` } : {}),
      };
    },
  },
  {
    name: "accept_agenda_suggestions",
    description:
      "ACEITA sugestão(ões) da caixa da agenda: cria a tarefa de verdade (como o botão Aceitar da tela) e tira a sugestão da caixa. " +
      "Aponte por busca (texto: 'ligar para o Miguel'), ids (de list_agenda_suggestions) ou todas/todas_de_hoje. " +
      "Ajustes valem para o que for aceito: quando (nova data/hora — 'mas amanhã às 10h'), title, assignee_user_id, priority. Busca que serve para mais de uma devolve as opções sem aceitar nada.",
    input_schema: {
      type: "object",
      properties: {
        busca: { type: "string", description: "Texto da sugestão como o dono falou." },
        ids: { type: "array", items: { type: "string" }, description: "Ids das sugestões (de list_agenda_suggestions)." },
        todas: { type: "boolean", description: "Todas as pendentes (que casam com a busca, se houver)." },
        todas_de_hoje: { type: "boolean", description: "Todas as pendentes que chegaram hoje." },
        quando: { type: "string", description: "Nova data/hora ISO (sem fuso = Brasília). Vira o prazo da tarefa ou o início do compromisso." },
        title: { type: "string", description: "Título ajustado (só quando aceitar UMA)." },
        assignee_user_id: { type: "string", description: "Responsável (app_users.id). Padrão: o destinatário da sugestão, senão quem pediu." },
        priority: { type: "string", description: "baixa | normal | alta | urgente" },
      },
    },
    risk: "low",
    async execute(args, ctx) {
      const prioridade = prioridadeDaTarefa(args.priority);
      if (prioridade && typeof prioridade === "object") return prioridade;
      let quando: string | null = null;
      if (args.quando) {
        const q = comFusoDeBrasilia(String(args.quando));
        const d = typeof q === "string" ? new Date(q) : null;
        if (!d || Number.isNaN(d.getTime())) return { error: `Não entendi a data "${args.quando}" — mande data e hora (AAAA-MM-DDTHH:MM).` };
        quando = d.toISOString();
      }
      const alvo = await escolher(ctx, args, LIMITE_POR_VEZ);
      if (ehErroDeLeitura(alvo)) return alvo;
      if (args.title && alvo.escolhidas.length > 1) return { error: "Título ajustado só vale para aceitar UMA sugestão." };

      const criadas: Array<{ sugestao: string; tarefa_id: string; titulo: string; quando: string | null }> = [];
      const falhas: string[] = [];
      for (const s of alvo.escolhidas) {
        const kind = s.kind === "appointment" ? "appointment" : "task";
        if (kind === "appointment" && !quando && !s.suggested_start_at) {
          falhas.push(`${s.title}: é compromisso e veio sem hora — diga quando`);
          continue;
        }
        // Mesma linha que useAcceptSuggestion grava; o ajuste "quando" vai para o campo do tipo.
        const row = {
          title: (typeof args.title === "string" && args.title.trim()) || s.title,
          kind,
          status: "pending",
          priority: prioridade || s.priority || "normal",
          assignee_user_id: args.assignee_user_id || s.target_user_id || ctx.userId,
          due_at: kind === "task" ? (quando ?? s.suggested_due_at ?? null) : (s.suggested_due_at ?? null),
          scheduled_start_at: kind === "appointment" ? (quando ?? s.suggested_start_at ?? null) : (s.suggested_start_at ?? null),
          scheduled_end_at: null,
          client_id: s.client_id ?? null,
          related_entity_type: s.related_entity_type ?? null,
          related_entity_id: s.related_entity_id ?? null,
          notes: `Origem: ${s.origin === "whatsapp" ? `conversa com ${s.contact_label || "contato"}` : "recado de voz"}\n"${s.evidence}"`,
          source: "ai",
          created_by: ctx.userId,
        };
        const { data: tarefa, error } = await ctx.sb.from("agenda_tasks").insert(row).select("id").single();
        if (error || !tarefa) { falhas.push(`${s.title}: ${error?.message ?? "sem retorno"}`); continue; }
        const { data: marcada, error: erroMarca } = await ctx.sb.from("agenda_suggestions").update({
          status: "accepted", resolved_at: new Date().toISOString(), resolved_by: ctx.userId, created_task_id: tarefa.id,
        }).eq("id", s.id).eq("status", "pending").select("id");
        if (erroMarca || !marcada?.length) {
          // A sugestão não saiu da caixa (falhou, ou alguém resolveu antes): a tarefa nova sai.
          await ctx.sb.from("agenda_tasks").delete().eq("id", tarefa.id);
          falhas.push(`${s.title}: ${erroMarca ? erroMarca.message : "já tinha sido resolvida por outra pessoa"}`);
          continue;
        }
        criadas.push({ sugestao: s.title, tarefa_id: tarefa.id, titulo: row.title, quando: row.scheduled_start_at || row.due_at });
      }
      if (!criadas.length) return { error: `Nenhuma sugestão foi aceita. ${falhas.join("; ")}` };
      return {
        ok: true,
        aceitas: criadas.length,
        tarefas_criadas: criadas,
        ...(falhas.length ? { nao_aceitas: falhas } : {}),
        ...(alvo.restantes ? { faltam: `${alvo.restantes} ainda na caixa (até ${LIMITE_POR_VEZ} por vez) — peça de novo para continuar.` } : {}),
      };
    },
  },
  {
    name: "dismiss_agenda_suggestions",
    description:
      "DESCARTA sugestão(ões) da caixa da agenda (como o X da tela): sai da caixa sem criar tarefa. Aponte por busca ('a do fornecedor de tinta'), ids ou todas/todas_de_hoje; motivo opcional fica registrado. " +
      "Busca que serve para mais de uma devolve as opções sem descartar nada.",
    input_schema: {
      type: "object",
      properties: {
        busca: { type: "string", description: "Texto da sugestão como o dono falou." },
        ids: { type: "array", items: { type: "string" }, description: "Ids das sugestões (de list_agenda_suggestions)." },
        todas: { type: "boolean", description: "Todas as pendentes (que casam com a busca, se houver)." },
        todas_de_hoje: { type: "boolean", description: "Todas as pendentes que chegaram hoje." },
        motivo: { type: "string", description: "Por que descartou (opcional)." },
      },
    },
    risk: "low",
    async execute(args, ctx) {
      const alvo = await escolher(ctx, args, LIMITE_POR_VEZ);
      if (ehErroDeLeitura(alvo)) return alvo;
      const motivo = String(args.motivo ?? "").trim().slice(0, 300) || null;
      const ids = alvo.escolhidas.map((s) => s.id);
      const { data, error } = await ctx.sb.from("agenda_suggestions").update({
        status: "dismissed", resolved_at: new Date().toISOString(), resolved_by: ctx.userId, dismiss_reason: motivo,
      }).in("id", ids).eq("status", "pending").select("id, title");
      if (error) return { error: `Não consegui descartar: ${error.message}` };
      const feitas = (data ?? []) as Sugestao[];
      return {
        ok: true,
        descartadas: feitas.length,
        titulos: feitas.map((s) => s.title),
        ...(feitas.length < ids.length ? { obs: `${ids.length - feitas.length} já tinham sido resolvidas por outra pessoa.` } : {}),
        ...(alvo.restantes ? { faltam: `${alvo.restantes} ainda na caixa (até ${LIMITE_POR_VEZ} por vez) — peça de novo para continuar.` } : {}),
      };
    },
  },
];
