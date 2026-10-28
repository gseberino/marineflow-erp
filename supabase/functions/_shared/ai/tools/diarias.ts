// Diárias de freelancers pela conversa: "o Roberto não veio hoje", "Mickael meio período ontem na
// OS 1234", "quanto devo pro Roberto?".
//
// Substitui as 5 ferramentas de jornada (registrar_jornada, fechar_jornada, minhas_horas,
// apurar_pagamento, fechar_folha), que nunca foram chamadas — decisão D7 do dono, 28/09/2026.
// Princípio do dono: a IA pensa e chama a função; quem preenche é o sistema. Os argumentos são como
// a pessoa fala (nome, "ontem", número da OS); a diária, o dia único por pessoa, a trilha e o saldo
// ficam com as funções do banco (migration 20260928190000) — as MESMAS que a tela Financeiro ›
// Diárias usa.
//
// Toda diária pede confirmação (D8): mexe no que outra pessoa recebe. A confirmação mostra o pedido
// JÁ RESOLVIDO ("Roberto · qui 24/09 · dia inteiro · R$ 160,00 · OS 1234"), e o que era antes.
//
// Freelancer NOVO (01/10/2026, o João Marcelo no lugar do Mickael): cadastrar_freelancer. Antes não
// havia caminho — cadastrar_favorecido cria só o favorecido, e sem a diária registrar_diaria recusa o
// dia. Quem decide se cria ou reaproveita um cadastro é a função do banco (cadastrar_freelancer,
// migration 20261001183918); a confirmação é a própria função simulando, sem gravar.
import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { dataDita, escolherPorNome, normal, osPeloNumero } from "./caixa.ts";
import { enviarDocumentoWhatsapp } from "./whatsapp.ts";
import { CONTEXTO_DO_ENVIO } from "./documentos-pdf.ts";
import { chaveDeEnvio, liberarEnvio } from "../../whatsapp/idempotencia.ts";
import { desviadoPorTeste } from "../../whatsapp/marcar-enviado.ts";
import { guardarEEntregar, limitarNomeDoArquivo } from "../../pdf/gerar-e-guardar.ts";
import {
  CONTA_FALTA_APROVAR, montarExtratoHtml, montarReciboDeServicosHtml, montarReciboHtml, nomeDoArquivo, numeroDoRecibo, ROTULO_REEMBOLSO, ROTULO_REEMBOLSOS, type ContaDoExtrato, type DocumentoDoRecibo,
} from "../../diarias/extrato.ts";
import { codigoDoCmp } from "./comprovantes.ts";
import { logEdgeError } from "../../log-error.ts";

const CARGOS: Role[] = ["admin", "financial"];
const brl = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const DIAS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];
// "manter" (07/10/2026): só mexer nos extras/descontos (ou na OS, na observação) do dia já lançado —
// "desconta 30 da diária do Mickael de ontem". Vira a jornada que o dia já tem.
const JORNADAS = ["inteiro", "meio", "faltou", "apagar", "manter"] as const;
type Jornada = typeof JORNADAS[number];
const ROTULO: Record<Jornada, string> = { inteiro: "dia inteiro", meio: "meio período", faltou: "faltou", apagar: "apagar", manter: "como está" };
const FRACAO: Record<string, number> = { inteiro: 1, meio: 0.5, faltou: 0 };
// Falta não se lança mais (revisão de 24/10, padrão adotado pelo dono): o dia sem trabalho só fica sem
// diária — o saldo e o recibo contam os dias lançados. "faltou" continua no banco para as linhas antigas.
const JORNADAS_DITAS = ["inteiro", "meio", "apagar", "manter"] as const;
const SEM_FALTA =
  "Dia sem trabalho não se lança: ele só fica sem a diária desse dia (o saldo e o recibo contam só os dias lançados). " +
  "Nada foi registrado. Se foi numa OS do plano da agenda, o fato (quem não foi) vai por os_registrar_andamento; " +
  "se o dia foi lançado por engano, use apagar.";

function semAcesso(ctx: ToolCtx): { error: string } | null {
  const b = blockTechnician(ctx);
  if (b) return b;
  if (!CARGOS.includes(ctx.userRole as Role)) return { error: "Apenas administrador ou financeiro." };
  return null;
}

/** "qui 24/09" — o mesmo formato da tela e das mensagens do banco. */
export function diaCurto(iso: string): string {
  const [a, m, d] = iso.split("-").map(Number);
  return `${DIAS[new Date(Date.UTC(a, m - 1, d)).getUTCDay()]} ${String(d).padStart(2, "0")}/${String(m).padStart(2, "0")}`;
}

const DIA_DA_SEMANA: Record<string, number> = { domingo: 0, segunda: 1, terca: 2, quarta: 3, quinta: 4, sexta: 5, sabado: 6 };

/**
 * A data como se fala: o que dataDita entende ("hoje", "ontem", dd/mm, ISO) e também o dia da
 * semana ("segunda", "sexta-feira") — o mais recente até hoje, em Brasília ("segunda" numa segunda
 * é hoje). É o que faz "de segunda até hoje" funcionar.
 */
export function dataDoDito(d: unknown, hoje = new Date()): string | null {
  const s = normal(d).replace(/\s*feira$/, "");
  if (s in DIA_DA_SEMANA) {
    const base = new Date(hoje.getTime() - 3 * 3600_000);
    const atras = (base.getUTCDay() - DIA_DA_SEMANA[s] + 7) % 7;
    return new Date(base.getTime() - atras * 86_400_000).toISOString().slice(0, 10);
  }
  return dataDita(d, hoje);
}

/** Os dias de `de` a `ate` (inclusive), em ordem; sábado e domingo só com `fimDeSemana`. */
export function datasDoIntervalo(de: string, ate: string, fimDeSemana = false): string[] {
  const out: string[] = [];
  const [a, m, d] = de.split("-").map(Number);
  for (let t = Date.UTC(a, m - 1, d), i = 0; i < 400; t += 86_400_000, i++) {
    const iso = new Date(t).toISOString().slice(0, 10);
    if (iso > ate) break;
    const dow = new Date(t).getUTCDay();
    if (fimDeSemana || (dow !== 0 && dow !== 6)) out.push(iso);
  }
  return out;
}

interface Perfil { id: string; valor_diaria: number | null; vigencia_inicio: string; vigencia_fim: string | null }
export interface Freelancer { id: string; nome: string; perfis: Perfil[] }

/** Quem tem perfil de diária — só esses entram aqui (Alex e Felipe, por exemplo, não). */
async function freelancersComDiaria(ctx: ToolCtx): Promise<Freelancer[]> {
  const { data, error } = await ctx.admin.from("work_profiles")
    .select("id, payee_id, valor_diaria, vigencia_inicio, vigencia_fim, payees(id, name, active)")
    .eq("modo_pagamento", "diaria");
  // Erro engolido viraria "nenhum freelancer com diária".
  if (error) throw new Error(`Não consegui ler quem tem diária: ${error.message}`);
  const porPessoa = new Map<string, Freelancer>();
  for (const r of (data ?? []) as any[]) {
    const p = r.payees;
    if (!p || p.active === false) continue;
    const f: Freelancer = porPessoa.get(p.id) ?? { id: p.id, nome: p.name, perfis: [] };
    f.perfis.push({ id: r.id, valor_diaria: r.valor_diaria == null ? null : Number(r.valor_diaria), vigencia_inicio: r.vigencia_inicio, vigencia_fim: r.vigencia_fim });
    porPessoa.set(p.id, f);
  }
  return [...porPessoa.values()];
}

async function acharFreelancer(ctx: ToolCtx, dito: unknown): Promise<Freelancer | { error: string }> {
  const lista = await freelancersComDiaria(ctx);
  const nomes = lista.map((f) => f.nome).join(", ") || "nenhum";
  const r = escolherPorNome(String(dito ?? ""), lista);
  if ("achado" in r) return r.achado;
  if ("ambiguo" in r) return { error: `Qual deles: ${r.ambiguo.map((f) => f.nome).join(" ou ")}?` };
  return { error: `Não achei freelancer com diária chamado "${dito ?? ""}". Os que têm diária: ${nomes}.` };
}

export interface PedidoDeDiaria {
  freelancer: Freelancer;
  /** O primeiro dia (ou o único). */
  data: string;
  /** Todos os dias do pedido — um só, ou os do intervalo (data → data_ate). */
  datas: string[];
  /** Veio com data_ate: dia já lançado no intervalo fica como está (não é sobrescrito). */
  intervalo: boolean;
  fimDeSemana: boolean;
  jornada: Jornada;
  os: { id: string; numero: string }[];
  observacao: string | null;
  /** Valor DITO para o dia ("na quarta foram 130"); nulo = a diária do cadastro. */
  valorDiaria: number | null;
  /** Extras e descontos DO DIA (o total, como na tela); nulo = deixa como está (07/10/2026). */
  extras: number | null;
  descontos: number | null;
  /** O dia já lançado, quando a jornada dita foi "manter". */
  atual?: DiaLancado | null;
  /** O que a agenda tinha para a pessoa no dia (Agenda de Produção, Fase 2; só com a agenda automática ligada). */
  plano?: OsDoPlano[];
  /** Sem OS dita, a OS veio do plano. */
  osDoPlano?: boolean;
  /**
   * (revisão da Fase 2) Meia diária sem OS dita num dia em que o plano tem a pessoa em mais de uma OS: o plano não diz em
   * qual foi o meio-dia, então a diária fica sem OS e o "sim" pergunta qual.
   */
  perguntaDoPlano?: string;
}

/** Uma OS do plano da agenda de uma pessoa num dia, com os turnos dela ali. */
export interface OsDoPlano { id: string; numero: string; cliente: string | null; turnos: string[] }

/**
 * As OS do plano da agenda daquela pessoa no dia (agenda_os_do_dia — Agenda de Produção, Fase 2, P4). Só com a agenda
 * automática ligada; fora dela o banco devolve [] e a diária segue como sempre. Reserva não entra (não é compromisso).
 * Erro de leitura = sem sugestão (a diária segue só com a OS dita, como antes da agenda) e fica em app_error_logs: a
 * sugestão nunca é inventada.
 */
async function osDoPlanoNoDia(ctx: ToolCtx, payeeId: string, dia: string): Promise<OsDoPlano[]> {
  try {
    const { data, error } = await ctx.admin.rpc("agenda_os_do_dia", { p_payee: payeeId, p_dia: dia });
    if (error) throw error;
    return ((Array.isArray(data) ? data : []) as any[])
      .filter((o) => o && o.os && !o.reserva)
      .map((o) => ({
        id: String(o.os), numero: String(o.numero ?? ""), cliente: o.cliente_curto ? String(o.cliente_curto) : null,
        turnos: Array.isArray(o.turnos) ? o.turnos.map(String) : [],
      }));
  } catch (e) {
    await logEdgeError(ctx.admin, {
      context: "agenda", action: "diaria:plano", level: "warn", error: e,
      message: `agenda_os_do_dia falhou; a diária segue sem a sugestão do plano: ${(e as { message?: string })?.message ?? e}`,
    });
    return [];
  }
}

/**
 * Agenda de Produção, Fase 3 (P4): a agenda já lançou essa diária (a resposta do técnico ou o *dia feito* bateram com o
 * plano)? O banco devolve a frase pronta (agenda_diaria_da_agenda): "A agenda já lançou essa diária às 17:12 (corrige com
 * *diária Roberto meia*)." A função que ainda não existe (a migration não aplicada) = nada, sem registro; outro erro =
 * nada e um aviso em app_error_logs: a linha nunca é inventada.
 */
async function diariaDaAgenda(ctx: ToolCtx, payeeId: string, dia: string): Promise<string | null> {
  try {
    const { data, error } = await ctx.admin.rpc("agenda_diaria_da_agenda", { p_payee: payeeId, p_dia: dia });
    if (error) {
      const code = String((error as { code?: unknown }).code ?? "");
      if (code === "PGRST202" || code === "42883") return null;
      throw error;
    }
    const r = (data ?? {}) as { lancada?: unknown; texto?: unknown };
    return r.lancada === true && typeof r.texto === "string" && r.texto.trim() ? r.texto : null;
  } catch (e) {
    await logEdgeError(ctx.admin, {
      context: "agenda", action: "diaria:da_agenda", level: "warn", error: e,
      message: `agenda_diaria_da_agenda falhou; o resumo da diária segue sem a linha da agenda: ${(e as { message?: string })?.message ?? e}`,
    });
    return null;
  }
}

/** "OS-00069 (Vanderlei)". */
const osComCliente =(o: OsDoPlano) => `${o.numero}${o.cliente ? ` (${o.cliente})` : ""}`;

/** "de manhã", "à tarde", "o dia todo" (os turnos da pessoa numa OS do plano). */
function turnosEmTexto(turnos: string[]): string {
  const m = turnos.includes("manha");
  const t = turnos.includes("tarde");
  return m && t ? "o dia todo" : m ? "de manhã" : t ? "à tarde" : "nesse dia";
}

/**
 * Meia diária sem OS dita e o plano com a pessoa em mais de uma OS no dia: a pergunta do "sim". Ir nas duas dividiria o
 * valor entre elas, e ela trabalhou só um dos turnos.
 */
function perguntaDaMeiaDiaria(nome: string, plano: OsDoPlano[]): string {
  const onde = plano.map((o) => `na ${osComCliente(o)} ${turnosEmTexto(o.turnos)}`);
  const lista = onde.length > 1 ? `${onde.slice(0, -1).join(", ")} e ${onde[onde.length - 1]}` : onde[0];
  return `Pelo plano, ${nome} estava ${lista}: a meia diária é de qual? Diga a OS; sem ela, a diária fica sem OS.`;
}

/** "130", "130,00", "R$ 1.300,50", 130 → número; o resto, nulo. */
export function numeroDito(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  const s = String(v ?? "").replace(/R\$|\s/g, "");
  if (!s) return null;
  const n = Number(s.includes(",") ? s.replace(/\./g, "").replace(",", ".") : s);
  return Number.isFinite(n) ? n : null;
}

/** Até 31 dias por pedido — mais que isso é engano de data, não pedido. */
const MAX_DIAS = 31;

/** O que o plano da agenda decide para a OS de um dia de trabalho (inteiro ou meio) da pessoa. */
interface PlanoDoDia {
  plano: OsDoPlano[];
  /** As OS do dia: as ditas ou, sem OS dita, as do plano. */
  os: { id: string; numero: string }[];
  /** Sem OS dita, a OS veio do plano. */
  osDoPlano: boolean;
  /** Meia diária sem OS dita e duas OS no plano: a pergunta do "sim" (a diária fica sem OS). */
  pergunta?: string;
}

/**
 * Agenda de Produção, Fase 2 (P4): num dia de trabalho, sem OS dita a diária vai na OS do plano daquela pessoa no dia.
 * Revisão da Fase 2: meia diária com mais de uma OS no plano do dia não vai nas duas (o valor se dividiria e ela
 * trabalhou só um turno): fica sem OS e o "sim" pergunta qual. PÓS-MERGE (B): o mesmo para cada dia do lote.
 */
async function planoDoDia(
  ctx: ToolCtx, f: Freelancer, dia: string, jornada: Jornada, ditas: { id: string; numero: string }[],
): Promise<PlanoDoDia> {
  const plano = await osDoPlanoNoDia(ctx, f.id, dia);
  if (ditas.length || !plano.length) return { plano, os: ditas, osDoPlano: false };
  if (jornada === "meio" && plano.length > 1) return { plano, os: [], osDoPlano: false, pergunta: perguntaDaMeiaDiaria(f.nome, plano) };
  return { plano, os: plano.map((o) => ({ id: o.id, numero: o.numero })), osDoPlano: true };
}

/** Resolve o pedido como a pessoa falou. Devolve a pergunta quando há dúvida — sem gravar nada. */
export async function resolverDiaria(
  ctx: ToolCtx, args: Record<string, unknown>, opcoes: { semPlano?: boolean } = {},
): Promise<PedidoDeDiaria | { error: string }> {
  const jornada = String(args.jornada ?? "") as Jornada;
  if (jornada === "faltou") return { error: SEM_FALTA };
  if (!JORNADAS.includes(jornada)) return { error: `Jornada "${args.jornada}" não existe: use inteiro, meio, apagar ou manter.` };
  const f = await acharFreelancer(ctx, args.freelancer);
  if ("error" in f) return f;
  const hoje = dataDita("hoje")!;
  const data = args.data == null || args.data === "" ? hoje : dataDoDito(args.data);
  if (!data) return { error: `Não entendi a data "${args.data}". Use hoje, ontem, dd/mm ou o dia da semana.` };
  const fimDeSemana = args.fim_de_semana === true;
  let datas = [data];
  let intervalo = false;
  if (args.data_ate != null && args.data_ate !== "") {
    if (jornada === "apagar") return { error: "Apagar é um dia de cada vez: diga qual dia." };
    if (jornada === "manter") return { error: "Mexer só em extras/descontos é um dia de cada vez: diga qual dia." };
    const ate = dataDoDito(args.data_ate);
    if (!ate) return { error: `Não entendi até quando: "${args.data_ate}". Use hoje, ontem, dd/mm ou o dia da semana.` };
    if (ate < data) return { error: `O intervalo está invertido: ${diaCurto(data)} a ${diaCurto(ate)}.` };
    if (ate > hoje) return { error: `Não registro dia no futuro: o intervalo vai até ${diaCurto(ate)} e hoje é ${diaCurto(hoje)}.` };
    datas = datasDoIntervalo(data, ate, fimDeSemana);
    if (datas.length === 0) return { error: `Nenhum dia útil de ${diaCurto(data)} a ${diaCurto(ate)} (sábado e domingo só entram se a pessoa disser).` };
    if (datas.length > MAX_DIAS) return { error: `Intervalo grande demais (${datas.length} dias): até ${MAX_DIAS} por vez.` };
    intervalo = true;
  }
  const os: { id: string; numero: string }[] = [];
  const ditas = String(args.os ?? "").split(/[,;]|\be\b/).map((s) => s.trim()).filter(Boolean);
  for (const n of ditas) {
    const achada = await osPeloNumero(ctx, n);
    if (achada && "error" in achada) return achada;
    if (achada) os.push(achada);
  }
  // Agenda de Produção, Fase 2 (P4): num dia de trabalho (inteiro ou meio, um dia só), sem OS dita a diária vai na OS
  // do plano daquela pessoa no dia; com OS dita diferente do plano, o "sim" mostra a divergência.
  // Revisão da Fase 2: meia diária com mais de uma OS no plano do dia não vai nas duas (o valor se dividiria e ela
  // trabalhou só um turno): fica sem OS e o "sim" pergunta qual.
  // PÓS-MERGE (B): o lote (resolverLote) pede semPlano e faz a mesma decisão DIA A DIA (planoDoDia), também nos intervalos.
  let plano: OsDoPlano[] = [];
  let osDoPlano = false;
  let perguntaDoPlano: string | undefined;
  if (!opcoes.semPlano && !intervalo && (jornada === "inteiro" || jornada === "meio")) {
    const d = await planoDoDia(ctx, f, data, jornada, os);
    plano = d.plano;
    osDoPlano = d.osDoPlano;
    perguntaDoPlano = d.pergunta;
    if (osDoPlano) os.push(...d.os);
  }
  const observacao = typeof args.observacao === "string" && args.observacao.trim() ? args.observacao.trim() : null;
  // Valor do dia só vale para quem trabalhou; ao apagar não há o que valer.
  let valorDiaria: number | null = null;
  if (args.valor_diaria != null && args.valor_diaria !== "" && jornada !== "apagar") {
    valorDiaria = numeroDito(args.valor_diaria);
    if (valorDiaria == null || valorDiaria <= 0) return { error: `Não entendi o valor do dia: "${args.valor_diaria}".` };
  }
  // Extras e descontos do dia (07/10/2026): os mesmos campos do "Registrar dia" da tela.
  const extras = valorDoDito(args.extras);
  const descontos = valorDoDito(args.descontos);
  if (extras === undefined) return { error: `Não entendi o valor dos extras: "${args.extras}".` };
  if (descontos === undefined) return { error: `Não entendi o valor dos descontos: "${args.descontos}".` };
  let atual: DiaLancado | null = null;
  if (jornada === "manter") {
    atual = await diaLancado(ctx, f, data);
    if (!atual) return { error: `Não há dia lançado para ${f.nome} em ${diaCurto(data)}: diga se foi dia inteiro ou meio período.` };
    if (extras == null && descontos == null && valorDiaria == null && !os.length && !observacao) {
      return { error: "Diga o que mudar no dia: extras, descontos, OS, observação ou o valor." };
    }
  }
  const resolvida: Jornada = atual ? (atual.fracao === 1 ? "inteiro" : atual.fracao === 0.5 ? "meio" : "faltou") : jornada;
  return {
    freelancer: f, data, datas, intervalo, fimDeSemana, jornada: resolvida, os, observacao, valorDiaria, extras, descontos, atual,
    plano, osDoPlano, ...(perguntaDoPlano ? { perguntaDoPlano } : {}),
  };
}

/** A OS da diária na linha do "sim": "OS-00069 (Vanderlei), pelo plano" quando veio do plano. */
function osDaLinha(p: PedidoDeDiaria): string {
  if (p.osDoPlano && p.plano?.length) return ` · ${p.plano.map(osComCliente).join(", ")}, pelo plano`;
  return p.os.length ? ` · ${p.os.map((o) => o.numero).join(", ")}` : "";
}

/** A OS dita não é a do plano: a divergência é a pergunta do "sim". null = bate (ou não há plano). */
export function divergenciaDoPlano(p: PedidoDeDiaria): string | null {
  if (p.osDoPlano || !p.plano?.length || !p.os.length) return null;
  const doPlano = new Set(p.plano.map((o) => o.id));
  const ditas = new Set(p.os.map((o) => o.id));
  if (doPlano.size === ditas.size && [...ditas].every((id) => doPlano.has(id))) return null;
  return `Pelo plano, ${p.freelancer.nome} estava na ${p.plano.map(osComCliente).join(" e ")} nesse dia; vai na ` +
    `${p.os.map((o) => o.numero).join(" e ")}, como você disse.`;
}

// ── A semana numa frase só (F3 da revisão, 27/10/2026) ────────────────────────────────────────────
// "Roberto: seg a qui inteiro, sex meio, sáb inteiro" era três pendências, três "sim" e três gravações
// soltas (em 24/10 a semana foi cancelada no meio e o sábado nunca entrou). Agora é UMA chamada com
// `dias` (cada trecho: um dia ou um intervalo, com a jornada), UMA confirmação e UMA gravação
// (registrar_diarias_em_lote: ou entram todos, ou nenhum).

/**
 * Um trecho do lote. comPlano (PÓS-MERGE B): a jornada dita é de trabalho (inteiro ou meio) — os dias que entram leem o
 * plano da agenda um a um, como o registrar_diaria de um dia (o "manter" não lê, como lá).
 */
export type ItemDoLote = PedidoDeDiaria & { comPlano: boolean };
export interface PedidoDeLote { freelancer: Freelancer; itens: ItemDoLote[] }

/** Até 15 trechos por pedido — mais que isso é engano, não semana. */
const MAX_TRECHOS = 15;

export async function resolverLote(ctx: ToolCtx, args: Record<string, unknown>): Promise<PedidoDeLote | { error: string }> {
  const dias = args.dias;
  if (!Array.isArray(dias) || !dias.length) return { error: "Diga os dias: cada dia (ou cada intervalo) com a jornada." };
  if (dias.length > MAX_TRECHOS) return { error: `Trechos demais (${dias.length}): até ${MAX_TRECHOS} por pedido.` };
  const itens: ItemDoLote[] = [];
  for (const [i, d] of dias.entries()) {
    const item = (d ?? {}) as Record<string, unknown>;
    if (item.jornada === "apagar") return { error: "Apagar é um dia de cada vez, fora da lista: diga qual dia." };
    // PÓS-MERGE (B): o plano é lido dia a dia em diasDoLote (só os dias que entram), não aqui.
    const p = await resolverDiaria(ctx, { ...item, freelancer: args.freelancer, fim_de_semana: item.fim_de_semana ?? args.fim_de_semana },
      { semPlano: true });
    if ("error" in p) return { error: dias.length > 1 ? `Trecho ${i + 1}: ${p.error}` : p.error };
    itens.push({ ...p, comPlano: item.jornada === "inteiro" || item.jornada === "meio" });
  }
  const vistos = new Set<string>();
  for (const p of itens) {
    for (const d of p.datas) {
      if (vistos.has(d)) return { error: `O dia ${diaCurto(d)} aparece em dois trechos: diga cada dia uma vez só.` };
      vistos.add(d);
    }
  }
  return { freelancer: itens[0].freelancer, itens };
}

type DiaDoLote = {
  data: string; jornada: Jornada; os_ids: string[] | null; observacao: string | null;
  extras: number | null; descontos: number | null; valor_diaria: number | null;
};

/**
 * Os dias que o lote grava. Num intervalo, o dia já lançado fica como está (como no data_ate); o dia
 * dito sozinho corrige o que havia (como no registrar_diaria de um dia).
 */
type DiaResolvido = DiaDoLote & { item: ItemDoLote; plano: PlanoDoDia | null };

/** Só os campos que registrar_diarias_em_lote lê (o resto é da confirmação). */
const paraOBanco = ({ item: _i, plano: _p, ...d }: DiaResolvido): DiaDoLote => d;

async function diasDoLote(ctx: ToolCtx, l: PedidoDeLote) {
  const lancados = await diasLancados(ctx, l.freelancer, l.itens.flatMap((p) => p.datas));
  const aGravar: Array<{ item: ItemDoLote; data: string }> = [];
  const mantidos: string[] = [];
  const diasMantidos: string[] = [];
  const corrigidos: string[] = [];
  for (const p of l.itens) {
    for (const d of p.datas) {
      const atual = lancados.get(d);
      if (p.intervalo && atual) { mantidos.push(`${ddmm(d)} (${rotuloDaFracao(atual.fracao)})`); diasMantidos.push(d); continue; }
      if (atual) corrigidos.push(`${ddmm(d)} (era ${rotuloDaFracao(atual.fracao)}, ${brl.format(atual.valorDia)})`);
      aGravar.push({ item: p, data: d });
    }
  }
  // PÓS-MERGE (B): cada dia de trabalho que entra pergunta o plano DAQUELE dia (agenda_os_do_dia), como a diária de um
  // dia (Fase 2, P4): sem OS dita, vai na OS do plano; meia diária com duas OS no plano fica sem OS (o "sim" pergunta).
  const planos = await Promise.all(aGravar.map(({ item, data }) =>
    item.comPlano ? planoDoDia(ctx, l.freelancer, data, item.jornada, item.os) : Promise.resolve(null)));
  const dias: DiaResolvido[] = aGravar.map(({ item: p, data: d }, i) => {
    const plano = planos[i];
    const os = plano ? plano.os : p.os;
    return {
      item: p, plano, data: d, jornada: p.jornada, os_ids: os.length ? os.map((o) => o.id) : null, observacao: p.observacao,
      extras: p.extras, descontos: p.descontos, valor_diaria: p.valorDiaria,
    };
  });
  return { dias, mantidos, diasMantidos, corrigidos, lancados };
}

/** A OS de um dia do lote na linha do "sim": "OS-00069 (Vanderlei), pelo plano", a OS dita ou "" (sem OS). */
function osDoDiaNoSim(d: DiaResolvido): string {
  if (d.plano?.osDoPlano) return `${d.plano.plano.map(osComCliente).join(", ")}, pelo plano`;
  return d.item.os.map((o) => o.numero).join(", ");
}

/** "21/09, 22/09 OS-00069 (Vanderlei); 23/09 OS-00060 (Lenine)": os dias agrupados pela OS, na ordem. */
function osDosDiasNoSim(ds: DiaResolvido[]): string {
  const grupos: Array<{ texto: string; dias: string[] }> = [];
  for (const d of ds) {
    const texto = d.plano?.osDoPlano ? d.plano.plano.map(osComCliente).join(", ") : (osDoDiaNoSim(d) || "sem OS");
    const ultimo = grupos[grupos.length - 1];
    if (ultimo?.texto === texto) ultimo.dias.push(ddmm(d.data));
    else grupos.push({ texto, dias: [ddmm(d.data)] });
  }
  return grupos.map((g) => `${g.dias.join(", ")} ${g.texto}`).join("; ");
}

/** Linhas por dia, juntando os dias de texto igual: "seg 21/09, ter 22/09: <texto>". */
function linhasPorDia(pares: Array<[string, string]>): string[] {
  const grupos = new Map<string, string[]>();
  for (const [dia, texto] of pares) grupos.set(texto, [...(grupos.get(texto) ?? []), diaCurto(dia)]);
  return [...grupos].map(([texto, dias]) => `${dias.join(", ")}: ${texto}`);
}

/** O que o dia vai valer: a diária dita, a já gravada ou a do cadastro, mais extras, menos descontos. */
function valorDoDia(p: PedidoDeDiaria, data: string, atual: DiaLancado | undefined): number {
  const perfil = p.freelancer.perfis.find((x) => x.vigencia_inicio <= data && (!x.vigencia_fim || x.vigencia_fim >= data));
  const base = (p.valorDiaria ?? (atual?.valorDiaria || null) ?? perfil?.valor_diaria ?? 0) * (FRACAO[p.jornada] ?? 0);
  return Math.round((base + (p.extras ?? atual?.extras ?? 0) - (p.descontos ?? atual?.descontos ?? 0)) * 100) / 100;
}

/** A confirmação do lote: um trecho por linha, o total, e o que já estava lançado. */
export async function resumirLote(ctx: ToolCtx, args: Record<string, unknown>): Promise<string> {
  const l = await resolverLote(ctx, args);
  if ("error" in l) return `Registrar diárias\n⚠️ ${l.error} — nada vai ser gravado assim.`;
  const { dias, mantidos, diasMantidos, corrigidos, lancados } = await diasDoLote(ctx, l);
  const total = dias.reduce((s, d) => s + valorDoDia(d.item, d.data, lancados.get(d.data)), 0);
  const linhas = [`Registrar diárias de *${l.freelancer.nome}*: ${dias.length} dia(s) · ${brl.format(total)}`];
  for (const p of l.itens) {
    const ds = dias.filter((d) => d.item === p);
    if (!ds.length) continue;
    const valores = ds.map((d) => valorDoDia(p, d.data, lancados.get(d.data)));
    const quando = ds.length > 1
      ? `${diaCurto(ds[0].data)} a ${diaCurto(ds[ds.length - 1].data)} (${ds.length} dias${p.fimDeSemana ? "" : ", só dias úteis"})`
      : diaCurto(ds[0].data);
    const valor = valores.every((v) => v === valores[0])
      ? `${brl.format(valores[0])}${ds.length > 1 ? " cada" : ""}`
      : brl.format(valores.reduce((a, b) => a + b, 0));
    // PÓS-MERGE (B): a OS é de cada dia (a dita ou a do plano daquele dia); igual em todos, sai uma vez.
    const osDosDias = ds.map(osDoDiaNoSim);
    const os = osDosDias.every((o) => o === osDosDias[0])
      ? (osDosDias[0] ? ` · ${osDosDias[0]}` : "")
      : ` · pelo plano: ${osDosDiasNoSim(ds)}`;
    linhas.push(`• ${quando} · ${ROTULO[p.jornada]} · ${valor}` +
      (p.extras ? ` (extras ${brl.format(p.extras)})` : "") + (p.descontos ? ` (descontos ${brl.format(p.descontos)})` : "") +
      os + (p.observacao ? ` · ${p.observacao}` : ""));
  }
  // PÓS-MERGE (B): o que o "sim" de um dia diz sobre o plano, dia a dia — a OS dita diferente do plano e a pergunta da
  // meia diária com duas OS no plano; o valor que se divide entre as OS.
  const divergencias: Array<[string, string]> = [];
  const perguntas: Array<[string, string]> = [];
  for (const d of dias) {
    if (!d.plano) continue;
    const div = divergenciaDoPlano({ ...d.item, plano: d.plano.plano, osDoPlano: d.plano.osDoPlano });
    if (div) divergencias.push([d.data, div]);
    if (d.plano.pergunta) perguntas.push([d.data, d.plano.pergunta]);
  }
  linhas.push(...linhasPorDia(divergencias), ...linhasPorDia(perguntas));
  if (dias.some((d) => (d.os_ids?.length ?? 0) > 1)) linhas.push("O valor do dia se divide em partes iguais entre as OS.");
  if (corrigidos.length) linhas.push(`Já lançados, vão ser corrigidos (não duplicados): ${corrigidos.join(", ")}.`);
  if (mantidos.length) linhas.push(`Já lançados, ficam como estão: ${mantidos.join(", ")}.`);
  if (!dias.length) linhas.push("Todos esses dias já estão lançados: nada vai mudar.");
  const semPerfil = dias.filter((d) => !d.item.freelancer.perfis.some((x) => x.vigencia_inicio <= d.data && (!x.vigencia_fim || x.vigencia_fim >= d.data)));
  if (semPerfil.length) linhas.push(`⚠️ Sem diária cadastrada em ${semPerfil.map((d) => ddmm(d.data)).join(", ")}: o sistema vai recusar e nada entra.`);
  // PÓS-MERGE (B): como no "sim" de um dia (Fase 3, P4), o dia já lançado que foi a agenda que lançou diz isso, com a
  // palavra que corrige — o que vai ser corrigido e o que fica como está. Só os dias já lançados perguntam.
  const jaLancados = [...dias.map((d) => d.data), ...diasMantidos].filter((d) => lancados.has(d)).sort();
  const daAgenda = await Promise.all(jaLancados.map((d) => diariaDaAgenda(ctx, l.freelancer.id, d)));
  linhas.push(...jaLancados.flatMap((d, i) => (daAgenda[i] ? [`${diaCurto(d)}: ${daAgenda[i]}`] : [])));
  return linhas.join("\n");
}

async function registrarLote(ctx: ToolCtx, args: Record<string, unknown>) {
  const l = await resolverLote(ctx, args);
  if ("error" in l) return l;
  const { dias, mantidos } = await diasDoLote(ctx, l);
  if (!dias.length) {
    return { ok: true, registrados: [], mantidos, aviso: `Todos esses dias já estavam lançados para ${l.freelancer.nome}; nada mudou.` };
  }
  const r = await chamar(ctx, "registrar_diarias_em_lote", {
    p_favorecido_id: l.freelancer.id, p_dias: dias.map(paraOBanco), p_origem: "agente",
  }) as Record<string, unknown>;
  if (r && "error" in r) return r;
  const partes = [`${l.freelancer.nome} · ${dias.length} dia(s) registrado(s): ${dias.map((d) => ddmm(d.data)).join(", ")}.`];
  if (mantidos.length) partes.push(`Já lançados, mantidos: ${mantidos.join(", ")}.`);
  return { ok: true, registrados: dias.map((d) => d.data), mantidos, aviso: `${partes.join(" ")}${await saldoDito(ctx, l.freelancer)}`.trim() };
}

/**
 * Lançamentos da pessoa esperando o "sim" (F3, 27/10/2026): o PDF mandado antes do "sim" sai
 * desatualizado (4 assim em 10 e 24/10). As pendências guardam o nome como a pessoa falou: vale o
 * primeiro nome.
 */
async function lancamentosEsperandoSim(ctx: ToolCtx, f: Freelancer): Promise<number> {
  const { data } = await ctx.admin.from("ai_operator_pending_actions")
    .select("id, payload, expires_at")
    .eq("status", "pending")
    .in("action_name", ["registrar_diaria", "registrar_pagamento_freelancer", "dividir_pagamento_freelancer"]);
  const primeiro = normal(f.nome).split(" ")[0];
  const agora = Date.now();
  return ((data ?? []) as any[]).filter((p) =>
    (!p.expires_at || new Date(p.expires_at).getTime() > agora) && normal(p.payload?.freelancer ?? "").split(" ")[0] === primeiro).length;
}

const textoDoPdfEsperando = (f: Freelancer, n: number) =>
  `Há ${n} lançamento(s) de ${f.nome} esperando o seu "sim": o PDF sai depois que você confirmar (agora sairia desatualizado). Não mandei nada.`;

/** Extra/desconto dito: nulo = não disse; undefined = disse algo que não é valor (vira pergunta). */
function valorDoDito(v: unknown): number | null | undefined {
  if (v == null || v === "") return null;
  const n = numeroDito(v);
  return n == null || n < 0 ? undefined : Math.round(n * 100) / 100;
}

type DiaLancado = { id: string; fracao: number; valorDia: number; valorDiaria: number; extras: number; descontos: number };

/** Os dias já lançados para a pessoa nessas datas (no máximo um por data, pelo índice do banco). */
async function diasLancados(ctx: ToolCtx, f: Freelancer, datas: string[]): Promise<Map<string, DiaLancado>> {
  const { data: linhas } = await ctx.admin.from("work_shifts")
    .select("id, data, fracao, valor_diaria, valor_dia, extras, descontos")
    .in("work_profile_id", f.perfis.map((p) => p.id))
    .in("data", datas)
    .not("fracao", "is", null);
  return new Map(((linhas ?? []) as any[]).map((d) => [String(d.data), {
    id: d.id as string, fracao: Number(d.fracao), valorDia: Number(d.valor_dia),
    valorDiaria: Number(d.valor_diaria), extras: Number(d.extras ?? 0), descontos: Number(d.descontos ?? 0),
  }]));
}

async function diaLancado(ctx: ToolCtx, f: Freelancer, data: string): Promise<DiaLancado | null> {
  return (await diasLancados(ctx, f, [data])).get(data) ?? null;
}

const ddmm = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

const rotuloDaFracao = (f: number) => (f === 1 ? "dia inteiro" : f === 0.5 ? "meio período" : "faltou");

/** Valor dito diferente do cadastro: a confirmação deixa claro que não é a diária de sempre. */
function linhaDoValorDito(p: PedidoDeDiaria, perfil: Perfil | undefined): string[] {
  if (p.valorDiaria == null || !perfil || perfil.valor_diaria === p.valorDiaria) return [];
  return [`Diária ${p.intervalo ? "desses dias" : "desse dia"}: ${brl.format(p.valorDiaria)} (a do cadastro é ${brl.format(perfil.valor_diaria ?? 0)}).`];
}

/** Extras e descontos ditos, com o antes quando o dia já existe (o banco substitui, não soma). */
function linhasDosExtras(p: PedidoDeDiaria, atual: DiaLancado | null): string[] {
  const linhas: string[] = [];
  const uma = (rotulo: string, novo: number | null, antes: number | undefined) => {
    if (novo == null) return;
    linhas.push(`${rotulo}${p.intervalo ? " (cada dia)" : ""}: ${atual && antes !== novo ? `${brl.format(antes ?? 0)} → ` : ""}*${brl.format(novo)}*`);
  };
  uma("Extras", p.extras, atual?.extras);
  uma("Descontos", p.descontos, atual?.descontos);
  return linhas;
}

/** O texto da confirmação: o pedido resolvido, e como o dia está hoje quando já existe. */
export async function resumirDiaria(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  if (Array.isArray(args.dias)) return await resumirLote(ctx, args);
  const p = await resolverDiaria(ctx, args);
  if ("error" in p) return null;
  if (p.intervalo) return await resumirIntervalo(ctx, p);
  const atual = await diaLancado(ctx, p.freelancer, p.data);
  const quem = `*${p.freelancer.nome}* · ${diaCurto(p.data)}`;
  if (p.jornada === "apagar") {
    return atual
      ? `Apagar o dia de ${quem} (${rotuloDaFracao(atual.fracao)}, ${brl.format(atual.valorDia)}). Some do saldo dele (é o caminho do dia lançado por engano, inclusive o de quem não veio).`
      : `Apagar o dia de ${quem} — não há dia lançado nessa data; nada vai mudar.`;
  }
  const perfil = p.freelancer.perfis.find((x) => x.vigencia_inicio <= p.data && (!x.vigencia_fim || x.vigencia_fim >= p.data));
  // O banco guarda a diária e os extras/descontos do dia já lançado quando não vêm ditos (07/10/2026).
  const extras = p.extras ?? atual?.extras ?? 0;
  const descontos = p.descontos ?? atual?.descontos ?? 0;
  const base = (p.jornada === "faltou" ? 0 : (p.valorDiaria ?? (atual?.valorDiaria || null) ?? perfil?.valor_diaria ?? 0) * FRACAO[p.jornada]);
  const valor = Math.round((base + extras - descontos) * 100) / 100;
  const linhas = [`Registrar diária: ${quem} · *${ROTULO[p.jornada]}*${p.jornada === "faltou" && !extras ? " (sem diária)" : ` · ${brl.format(valor)}`}` +
    osDaLinha(p)];
  // A OS dita não é a do plano da agenda: a divergência vai no "sim" (Agenda de Produção, Fase 2).
  const divergencia = divergenciaDoPlano(p);
  if (divergencia) linhas.push(divergencia);
  if (p.perguntaDoPlano) linhas.push(p.perguntaDoPlano);
  linhas.push(...linhaDoValorDito(p, perfil));
  linhas.push(...linhasDosExtras(p, atual));
  if (p.os.length > 1) linhas.push("O valor do dia se divide em partes iguais entre as OS.");
  if (p.observacao) linhas.push(`Observação: ${p.observacao}`);
  if (atual) linhas.push(`Hoje está lançado: ${rotuloDaFracao(atual.fracao)} (${brl.format(atual.valorDia)}) — vai ser corrigido, não duplicado.`);
  else if (!perfil) linhas.push("⚠️ Sem diária cadastrada nessa data: o sistema vai recusar.");
  // Agenda de Produção (Fase 3, P4): quando foi a agenda que lançou, o "sim" diz (e a palavra que corrige).
  const daAgenda = await diariaDaAgenda(ctx, p.freelancer.id, p.data);
  if (daAgenda) linhas.push(daAgenda);
  return linhas.join("\n");
}

/**
 * Vários dias ("faltou desde 19/09", "a semana toda"): a confirmação lista os dias que vão entrar e
 * os que JÁ estão lançados — esses ficam como estão (um "faltou desde…" não apaga um dia inteiro
 * lançado no meio do caminho). Para mudar um deles, registra-se o dia sozinho.
 */
async function resumirIntervalo(ctx: ToolCtx, p: PedidoDeDiaria): Promise<string> {
  const lancados = await diasLancados(ctx, p.freelancer, p.datas);
  const novos = p.datas.filter((d) => !lancados.has(d));
  const primeiro = p.datas[0];
  const ultimo = p.datas[p.datas.length - 1];
  const perfil = p.freelancer.perfis.find((x) => x.vigencia_inicio <= primeiro && (!x.vigencia_fim || x.vigencia_fim >= primeiro));
  const valor = (p.jornada === "faltou" ? 0 : (p.valorDiaria ?? perfil?.valor_diaria ?? 0) * FRACAO[p.jornada]) +
    (p.extras ?? 0) - (p.descontos ?? 0);
  const linhas = [
    `Registrar diária: *${p.freelancer.nome}* · *${ROTULO[p.jornada]}* · ${novos.length} dia(s) de ${diaCurto(primeiro)} a ${diaCurto(ultimo)}` +
      (p.fimDeSemana ? "" : " (só dias úteis)") +
      (p.jornada === "faltou" && !p.extras ? " (sem diária)" : ` · ${brl.format(valor)} cada, ${brl.format(valor * novos.length)} no total`) +
      (p.os.length ? ` · ${p.os.map((o) => o.numero).join(", ")}` : ""),
    ...linhaDoValorDito(p, perfil),
    ...linhasDosExtras(p, null),
  ];
  if (novos.length) linhas.push(`Dias: ${novos.map(ddmm).join(", ")}`);
  if (lancados.size) {
    linhas.push(`Já lançados, ficam como estão: ${[...lancados].sort(([a], [b]) => a.localeCompare(b))
      .map(([d, x]) => `${ddmm(d)} (${rotuloDaFracao(x.fracao)})`).join(", ")}. Para mudar um deles, registre o dia sozinho.`);
  }
  if (!novos.length) linhas.push("Todos os dias do intervalo já estão lançados: nada vai mudar.");
  if (p.observacao) linhas.push(`Observação: ${p.observacao}`);
  if (!perfil) linhas.push("⚠️ Sem diária cadastrada no começo do intervalo: o sistema vai recusar esses dias.");
  return linhas.join("\n");
}

async function chamar(ctx: ToolCtx, fn: string, params: Record<string, unknown>) {
  const { data, error } = await ctx.sb.rpc(fn, { ...params, p_autor: ctx.userId || null });
  if (error) return { error: String(error.message).replace(/^(P0001|42501|23514|23505):\s*/, "") };
  return data;
}

/**
 * Períodos que a pessoa pode pedir (06/10/2026: "em aberto", "desde o último pagamento", 15 dias,
 * semana — além do mês e do tudo). Quem calcula é o banco (_periodo_do_atalho): "em aberto" de um
 * freelancer não é o do outro.
 */
const PERIODOS = ["tudo", "em_aberto", "desde_ultimo_pagamento", "ultimos_15_dias", "semana_atual", "este_mes", "mes_passado"] as const;
const ATALHO_NO_BANCO: Record<string, string | null> = {
  tudo: null, em_aberto: "em_aberto", desde_ultimo_pagamento: "desde_ultimo_pagamento",
  ultimos_15_dias: "ultimos_15_dias", semana_atual: "semana_atual", este_mes: "este_mes", mes_passado: "mes_anterior",
};

export type PeriodoPedido = { p_de: string | null; p_ate: string | null; p_atalho: string | null };

/**
 * O período como a pessoa disse: datas ("de 14/09 a 27/09", "desde segunda") mandam; sem datas,
 * o atalho. Devolve a pergunta quando não entende — sem consultar nada.
 */
export function periodoDito(args: Record<string, unknown>, hoje = new Date()): PeriodoPedido | { error: string } {
  const temDe = args.de != null && args.de !== "";
  const temAte = args.ate != null && args.ate !== "";
  if (temDe || temAte) {
    const de = temDe ? dataDoDito(args.de, hoje) : null;
    const ate = temAte ? dataDoDito(args.ate, hoje) : null;
    if (temDe && !de) return { error: `Não entendi a data inicial "${args.de}". Use dd/mm, ontem ou o dia da semana.` };
    if (temAte && !ate) return { error: `Não entendi a data final "${args.ate}". Use dd/mm, hoje ou o dia da semana.` };
    if (de && ate && de > ate) return { error: `O período está invertido: ${diaCurto(de)} a ${diaCurto(ate)}.` };
    return { p_de: de, p_ate: ate, p_atalho: null };
  }
  const p = String(args.periodo ?? "tudo");
  if (!(p in ATALHO_NO_BANCO)) return { error: `Período "${args.periodo}" não existe: use ${PERIODOS.join(", ")}, ou datas.` };
  return { p_de: null, p_ate: null, p_atalho: ATALHO_NO_BANCO[p] };
}

/** "desde 28/09", "14/09 a 27/09" — o período que o banco resolveu, para a resposta. */
function periodoResolvido(c: { de?: string | null; ate?: string | null }): string {
  if (c.de && c.ate) return `${ddmm(c.de)} a ${ddmm(c.ate)}`;
  if (c.de) return `desde ${ddmm(c.de)}`;
  return "desde o início da conta corrente";
}

const ESTADO: Record<string, string> = {
  deve: "você deve a ele", adiantado: "pago adiantado (ele deve dias)", quitado: "quitado", semdias: "há pagamento sem dia lançado",
};

async function saldoDito(ctx: ToolCtx, f: Freelancer): Promise<string> {
  const c = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, p_de: null, p_ate: null }) as Record<string, unknown>;
  return c && !("error" in c) ? ` Saldo com ${f.nome}: ${brl.format(Math.abs(Number(c.saldo_final) || 0))} (${ESTADO[String(c.estado)] ?? c.estado}).` : "";
}

// ── Cadastro de freelancer novo ──────────────────────────────────────────────────────────────────

const TIPOS_DE_CHAVE = ["cpf", "cnpj", "email", "telefone", "aleatoria"] as const;
const ROTULO_DA_CHAVE: Record<string, string> = { cpf: "CPF", cnpj: "CNPJ", email: "e-mail", telefone: "telefone", aleatoria: "chave aleatória" };
const textoOuNulo = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : null);

/**
 * Os argumentos do cadastro como a função do banco recebe — a MESMA montagem para simular (a
 * confirmação) e para gravar. Só o que a pessoa disse: o tipo da chave Pix, quem já existe, a
 * conta corrente e a regra por CPF ficam com o banco.
 */
export interface ParamsDoCadastro {
  p_nome: string;
  p_valor_diaria: number;
  p_desde: string | null;
  p_chave_pix: string | null;
  p_tipo_chave: string | null;
  p_documento: string | null;
  p_telefone: string | null;
  p_observacao: string | null;
}

export function paramsDoCadastro(args: Record<string, unknown>, hoje = new Date()): ParamsDoCadastro | { error: string } {
  const nome = textoOuNulo(args.nome);
  if (!nome) return { error: "Qual o nome do freelancer?" };
  const valor = numeroDito(args.valor_diaria);
  if (valor == null || valor <= 0) return { error: `Qual o valor da diária de ${nome}? (não invente: pergunte)` };
  let desde: string | null = null;
  if (args.desde != null && args.desde !== "") {
    desde = dataDoDito(args.desde, hoje);
    if (!desde) return { error: `Não entendi desde quando: "${args.desde}". Use hoje, ontem, dd/mm ou o dia da semana.` };
  }
  const tipo = textoOuNulo(args.tipo_chave)?.toLowerCase() ?? null;
  if (tipo && !TIPOS_DE_CHAVE.includes(tipo as typeof TIPOS_DE_CHAVE[number])) {
    return { error: `Tipo de chave Pix "${args.tipo_chave}" não existe: use cpf, cnpj, email, telefone ou aleatoria.` };
  }
  return {
    p_nome: nome, p_valor_diaria: valor, p_desde: desde,
    p_chave_pix: textoOuNulo(args.chave_pix), p_tipo_chave: tipo,
    p_documento: textoOuNulo(args.cpf), p_telefone: textoOuNulo(args.telefone), p_observacao: textoOuNulo(args.observacao),
  };
}

const semCodigo = (m: unknown) => String(m ?? "").replace(/^(P0001|42501|23514|23505):\s*/, "");

/**
 * O texto da confirmação: a função do banco SIMULANDO o cadastro (p_simular, sem gravar) — se cria
 * ou reaproveita um favorecido, o tipo da chave que ela entendeu, se nasce a regra por CPF. Uma
 * recusa (já tem diária, chave ambígua) aparece aqui, antes do "sim".
 */
export async function resumirCadastro(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const p = paramsDoCadastro(args);
  if ("error" in p) return null;
  const desde = p.p_desde ?? dataDita("hoje")!;
  const linhas = [`Cadastrar freelancer: *${p.p_nome}* · diária de ${brl.format(p.p_valor_diaria)} · desde ${diaCurto(desde)}`];
  const { data, error } = await ctx.admin.rpc("cadastrar_freelancer", { ...p, p_simular: true, p_autor: null });
  if (error) {
    linhas.push(`⚠️ ${semCodigo(error.message)} — o sistema vai recusar.`);
    return linhas.join("\n");
  }
  const s = (data ?? {}) as Record<string, any>;
  if (s.chave_pix) linhas.push(`Pix (${ROTULO_DA_CHAVE[s.tipo_chave] ?? s.tipo_chave}): ${s.chave_pix}`);
  if (s.acao === "diaria_no_cadastro_existente") {
    linhas.push(`Já existe o favorecido *${s.nome}*, sem diária: ele ganha a diária — não nasce um cadastro novo.`);
  }
  linhas.push(s.regra === "criada"
    ? "Pix para o CPF dele vão entrar sozinhos em Diárias de freelancers."
    : s.regra === "ja_existia"
    ? `Já existe regra para o CPF dele (${s.regra_categoria ?? "sem categoria"}); fica como está.`
    : "Sem CPF: os Pix para ele vão pedir a sua confirmação na fila do extrato.");
  linhas.push("Meio período = metade da diária. Ele passa a aparecer em Financeiro › Diárias.");
  return linhas.join("\n");
}

/**
 * Vários dias: registra, um por um, só os que ainda não estão lançados (o banco é idempotente por
 * dia, mas aqui NÃO se corrige dia existente — "faltou desde 19/09" não pode apagar um dia inteiro
 * lançado no meio). Relata o que entrou, o que ficou como estava e o que o banco recusou.
 */
async function registrarIntervalo(ctx: ToolCtx, p: PedidoDeDiaria) {
  const lancados = await diasLancados(ctx, p.freelancer, p.datas);
  const novos = p.datas.filter((d) => !lancados.has(d));
  const mantidos = [...lancados].sort(([a], [b]) => a.localeCompare(b)).map(([d, x]) => `${ddmm(d)} (${rotuloDaFracao(x.fracao)})`);
  if (!novos.length) {
    return { ok: true, registrados: [], mantidos, aviso: `Todos os dias de ${diaCurto(p.datas[0])} a ${diaCurto(p.datas[p.datas.length - 1])} já estavam lançados para ${p.freelancer.nome}; nada mudou.` };
  }
  const feitos: string[] = [];
  const falhas: string[] = [];
  for (const d of novos) {
    const r = await chamar(ctx, "registrar_diaria", {
      p_favorecido_id: p.freelancer.id, p_data: d, p_jornada: p.jornada,
      p_os_ids: p.os.length ? p.os.map((o) => o.id) : null, p_observacao: p.observacao,
      p_extras: p.extras, p_descontos: p.descontos, p_valor_diaria: p.valorDiaria, p_origem: "agente",
    }) as Record<string, unknown>;
    if (r && "error" in r) falhas.push(`${ddmm(d)}: ${r.error}`);
    else feitos.push(d);
  }
  const partes = [`${p.freelancer.nome} · ${ROTULO[p.jornada]} · ${feitos.length} dia(s) registrado(s)${feitos.length ? `: ${feitos.map(ddmm).join(", ")}` : ""}.`];
  if (mantidos.length) partes.push(`Já lançados, mantidos: ${mantidos.join(", ")}.`);
  if (falhas.length) partes.push(`Não entraram: ${falhas.join("; ")}.`);
  return { ok: falhas.length === 0, registrados: feitos, mantidos, falhas, aviso: `${partes.join(" ")}${await saldoDito(ctx, p.freelancer)}`.trim() };
}

// ── Pagamento a freelancer (06/10/2026) ──────────────────────────────────────────────────────────
// "paguei 100 pro Roberto no Pix", "dei 50 em dinheiro pro João", "paguei do meu bolso". As MESMAS
// funções do botão "Lançar" da tela: Pix → anotar_transacao (espera a linha do banco e, até lá,
// aparece no extrato de diárias como "aguardando o banco", já descontando); dinheiro →
// lancar_no_caixa (sai do Caixa); bolso do sócio → lancar_no_caixa como reembolso ao sócio, com o
// freelancer gravado como quem recebeu (D1).

const FORMAS = ["pix", "dinheiro", "bolso_do_socio"] as const;
type Forma = typeof FORMAS[number];
// O rótulo inteiro de como foi pago (15/10/2026): montar "em ${rótulo}" deu "em do bolso do sócio".
const ROTULO_DA_FORMA: Record<Forma, string> = { pix: "por Pix", dinheiro: "em dinheiro do Caixa", bolso_do_socio: "pago do bolso do sócio" };
const CATEGORIA_DIARIAS = "Diárias de freelancers";

/**
 * Que reembolsos este pagamento quita (resposta 4 do dono, 11/10/2026: "sim, mas eu sempre vou
 * sinalizar o que é o que"): a proposta do sistema (os do acerto primeiro, por data, enquanto cabem
 * no valor), nenhum ("sem reembolso": tudo em Diárias) ou os CMPs que a pessoa disse.
 */
export type ReembolsosDoPagamento = { modo: "proposta" } | { modo: "nenhum" } | { modo: "codigos"; codigos: string[] };

export interface PedidoDePagamento {
  freelancer: Freelancer;
  valor: number;
  forma: Forma;
  /** A data dita; nula = hoje (no Pix, sem data exata a anotação espera alguns dias de folga). */
  data: string | null;
  socio: { id: string; nome: string } | null;
  observacao: string | null;
  /** Ausente = a proposta (o padrão). */
  reembolsos?: ReembolsosDoPagamento;
}

/** "proposta" (padrão) | "nenhum"/"sem reembolso" | "CMP-00124, cmp 130" (ou a lista) → o modo; inválido = erro. */
export function reembolsosDitos(v: unknown): ReembolsosDoPagamento | { error: string } {
  if (v == null || v === "") return { modo: "proposta" };
  const lista = Array.isArray(v) ? v.map(String) : String(v).split(/[,;\n]| e /);
  const ditos = lista.map((s) => s.trim()).filter(Boolean);
  const so = normal(ditos.join(" "));
  if (["proposta", "padrao", "sugestao", "o que o sistema propor", "sim"].includes(so)) return { modo: "proposta" };
  if (["nenhum", "nenhuma", "sem reembolso", "sem reembolsos", "nao", "nada", "tudo em diarias", "nao dividir"].includes(so)) return { modo: "nenhum" };
  const codigos = ditos.map((s) => codigoDoCmp(s.replace(/^o\s+/i, "")));
  if (!codigos.length || codigos.some((c) => !c)) {
    return { error: `Não entendi os reembolsos "${String(v)}". Diga "proposta", "sem reembolso" ou os CMPs (ex.: CMP-00124, CMP-00130).` };
  }
  return { modo: "codigos", codigos: [...new Set(codigos as string[])] };
}

/** Um reembolso em aberto do técnico (proposta_de_divisao_do_pagamento). */
interface ReembolsoEmAberto { id: string; codigo: string | null; data: string; valor: number; categoria: string | null; descricao: string | null; acerto: number | null }

/** A divisão que a confirmação mostra e que vai ao banco. */
export interface DivisaoPedida {
  /** Os reembolsos em aberto dele (vazio = não há o que dividir: o caminho de antes). */
  emAberto: ReembolsoEmAberto[];
  escolhidos: ReembolsoEmAberto[];
  diarias: number;
  reembolsos: number;
}

/**
 * A divisão pedida: o banco propõe (proposta_de_divisao_do_pagamento, só leitura) e a pessoa
 * confirma ou ajusta. CMP que não é reembolso em aberto dele, ou soma acima do valor, é recusado
 * aqui com o porquê (o banco recusa de novo ao gravar).
 */
export async function divisaoPedida(
  ctx: Pick<ToolCtx, "admin" | "userId">,
  freelancer: Freelancer,
  valor: number,
  pedido: ReembolsosDoPagamento = { modo: "proposta" },
): Promise<DivisaoPedida | { error: string }> {
  const { data, error } = await ctx.admin.rpc("proposta_de_divisao_do_pagamento", {
    p_favorecido_id: freelancer.id, p_valor: valor, p_autor: ctx.userId || null,
  });
  // função ainda não aplicada no banco: o pagamento de antes (sem divisão), a não ser que a pessoa tenha dito os CMPs
  if (error && ["PGRST202", "42883"].includes(String(error.code ?? "")) && pedido.modo !== "codigos") {
    return { emAberto: [], escolhidos: [], diarias: valor, reembolsos: 0 };
  }
  if (error) return { error: `Não consegui ler os reembolsos em aberto de ${freelancer.nome}: ${String(error.message).replace(/^(P0001|42501|22023):\s*/, "")}` };
  const d = (data ?? {}) as Record<string, any>;
  const emAberto: ReembolsoEmAberto[] = ((d.em_aberto ?? []) as any[]).map((r) => ({
    id: String(r.id), codigo: r.codigo ?? null, data: String(r.data ?? ""), valor: Number(r.valor) || 0,
    categoria: r.categoria ?? null, descricao: r.descricao ?? null, acerto: r.acerto == null ? null : Number(r.acerto),
  }));
  let escolhidos: ReembolsoEmAberto[];
  if (pedido.modo === "nenhum") escolhidos = [];
  else if (pedido.modo === "proposta") {
    const ids = new Set(((d.propostos ?? []) as unknown[]).map(String));
    escolhidos = emAberto.filter((r) => ids.has(r.id));
  } else {
    const faltando = pedido.codigos.filter((c) => !emAberto.some((r) => r.codigo === c));
    if (faltando.length) {
      return { error: `${faltando.join(", ")} não ${faltando.length > 1 ? "são reembolsos" : "é reembolso"} em aberto de ${freelancer.nome}` +
        (emAberto.length ? ` (em aberto: ${emAberto.map((r) => r.codigo ?? "sem código").join(", ")}).` : " (ele não tem reembolso em aberto).") };
    }
    escolhidos = emAberto.filter((r) => r.codigo && pedido.codigos.includes(r.codigo));
  }
  const reembolsos = Math.round(escolhidos.reduce((s, r) => s + r.valor, 0) * 100) / 100;
  if (reembolsos > valor + 0.005) {
    return { error: `Os reembolsos escolhidos (${brl.format(reembolsos)}) passam do valor do pagamento (${brl.format(valor)}): escolha menos ou diga "sem reembolso".` };
  }
  return { emAberto, escolhidos, reembolsos, diarias: Math.round((valor - reembolsos) * 100) / 100 };
}

/**
 * "Divido: Diárias R$ 408,00 · Reembolso de despesas pagas pelo técnico R$ 92,00 (CMP-00124,
 * CMP-00130). Para não dividir: diga "sem reembolso"." — a linha do "sim". Sem reembolso em aberto,
 * nada (o pagamento de antes).
 */
export function textoDaDivisao(d: DivisaoPedida): string | null {
  if (!d.emAberto.length) return null;
  if (!d.escolhidos.length) {
    return `Sem dividir: tudo em Diárias (há ${ROTULO_REEMBOLSO.toLowerCase()} em aberto: ${d.emAberto.map((r) => r.codigo ?? "sem código").join(", ")}).`;
  }
  const codigos = d.escolhidos.map((r) => r.codigo ?? "sem código").join(", ");
  const fora = d.emAberto.filter((r) => !d.escolhidos.includes(r)).map((r) => r.codigo ?? "sem código");
  return `Divido: Diárias ${brl.format(d.diarias)} · ${ROTULO_REEMBOLSOS} ${brl.format(d.reembolsos)} (${codigos}).` +
    (fora.length ? ` Ficam em aberto: ${fora.join(", ")}.` : "") +
    ' Para não dividir: diga "sem reembolso".';
}

async function acharSocio(ctx: ToolCtx, dito: unknown): Promise<{ id: string; nome: string } | { error: string }> {
  const { data, error } = await ctx.admin.from("payees").select("id, name, app_user_id").eq("kind", "socio").eq("active", true);
  if (error) return { error: `Falha ao ler os sócios: ${error.message}` };
  const socios = ((data ?? []) as any[]).map((s) => ({ id: s.id as string, nome: s.name as string, app: s.app_user_id as string | null }));
  if (!socios.length) return { error: "Não há sócio cadastrado nos favorecidos." };
  if (dito) {
    const r = escolherPorNome(String(dito), socios);
    if ("achado" in r) return { id: r.achado.id, nome: r.achado.nome };
    return { error: `Qual sócio pagou: ${socios.map((s) => s.nome).join(" ou ")}?` };
  }
  const euMesmo = ctx.userId ? socios.find((s) => s.app === ctx.userId) : undefined;
  if (euMesmo) return { id: euMesmo.id, nome: euMesmo.nome };
  if (socios.length === 1) return { id: socios[0].id, nome: socios[0].nome };
  return { error: `Qual sócio pagou: ${socios.map((s) => s.nome).join(" ou ")}?` };
}

export async function resolverPagamento(ctx: ToolCtx, args: Record<string, unknown>): Promise<PedidoDePagamento | { error: string }> {
  const forma = String(args.forma ?? "") as Forma;
  if (!FORMAS.includes(forma)) return { error: `Como foi pago? pix, dinheiro ou bolso_do_socio.` };
  const valor = numeroDito(args.valor);
  if (valor == null || valor <= 0) return { error: "Qual o valor pago? (não invente: pergunte)" };
  const f = await acharFreelancer(ctx, args.freelancer);
  if ("error" in f) return f;
  let data: string | null = null;
  if (args.data != null && args.data !== "") {
    data = dataDoDito(args.data);
    if (!data) return { error: `Não entendi a data "${args.data}". Use hoje, ontem, dd/mm ou o dia da semana.` };
    if (data > dataDita("hoje")!) return { error: "Pagamento no futuro não se lança: lance quando pagar." };
  }
  let socio: { id: string; nome: string } | null = null;
  if (forma === "bolso_do_socio") {
    const s = await acharSocio(ctx, args.socio);
    if ("error" in s) return s;
    socio = s;
  }
  const observacao = textoOuNulo(args.observacao);
  const reembolsos = reembolsosDitos(args.reembolsos);
  if ("error" in reembolsos) return reembolsos;
  return { freelancer: f, valor: Math.round(valor * 100) / 100, forma, data, socio, observacao, reembolsos };
}

const descricaoDoPagamento = (p: PedidoDePagamento) =>
  p.observacao ?? `Pagamento de diárias — ${p.freelancer.nome.split(" ")[0]}`;

/** A confirmação: quem, quanto, como, quando — e o saldo com ele antes e depois. */
export async function resumirPagamento(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const p = await resolverPagamento(ctx, args);
  if ("error" in p) return null;
  const quando = diaCurto(p.data ?? dataDita("hoje")!);
  const linhas = [`Pagamento a *${p.freelancer.nome}*: *${brl.format(p.valor)}* ${ROTULO_DA_FORMA[p.forma]} · ${quando}` +
    (p.socio ? ` · pago por ${p.socio.nome} (fica como reembolso a ele)` : "")];
  linhas.push(`Descrição: ${descricaoDoPagamento(p)} · ${CATEGORIA_DIARIAS}`);
  // resposta 4 do dono: a divisão proposta entre diárias e reembolso (o dono confirma ou diz outra)
  const div = await divisaoPedida(ctx, p.freelancer, p.valor, p.reembolsos);
  if ("error" in div) linhas.push(`⚠️ ${div.error}`);
  else {
    const t = textoDaDivisao(div);
    if (t) linhas.push(t);
  }
  const { data: c } = await ctx.admin.rpc("conta_corrente_freelancer", { p_favorecido_id: p.freelancer.id, p_autor: null });
  if (c && c.saldo_final != null) {
    const antes = Number(c.saldo_final);
    linhas.push(`Saldo com ele: ${brl.format(antes)} → ${brl.format(antes - p.valor)}${antes - p.valor < 0 ? " (fica adiantado)" : ""}`);
  }
  if (p.forma === "pix") {
    linhas.push("O Pix fica anotado: aparece já no extrato de diárias (\"aguardando o banco\") e vira o pagamento quando a linha do banco chegar. Se você já lançou este mesmo Pix, responda não.");
  }
  return linhas.join("\n");
}

const FORMA_NO_BANCO: Record<Forma, "pix" | "dinheiro" | "socio"> = { pix: "pix", dinheiro: "dinheiro", bolso_do_socio: "socio" };

/** O sufixo que o banco põe no pagamento já dividido ("… (inclui reembolso de despesas pagas pelo técnico: R$ 92,00)"). */
const SUFIXO_DA_DIVISAO = `(inclui ${ROTULO_REEMBOLSOS.toLowerCase()}`;

/** Um pagamento das Diárias que veio do banco e se pode dividir (o mesmo critério da tela, use-diarias.ts). */
export interface PagamentoQueSeDivide { id: string; data: string; valor: number; conta: string; dividido: boolean }

/** A linha "pagamento" da conta corrente que se pode dividir: lançamento das Diárias numa linha do BANCO. */
export function pagamentoQueSeDivide(l: Record<string, any>): PagamentoQueSeDivide | null {
  const conta = String(l?.conta ?? "");
  if (l?.tipo !== "pagamento" || l.aguardando || !l.id || !conta) return null;
  if (conta === "Caixa (dinheiro)" || conta === "Sem conta ligada" || conta.startsWith("Bolso de ")) return null;
  const dividido = String(l.descricao ?? "").toLowerCase().includes(SUFIXO_DA_DIVISAO);
  if (l.categoria !== CATEGORIA_DIARIAS && !dividido) return null;
  return { id: String(l.id), data: String(l.data ?? ""), valor: Number(l.pago) || 0, conta, dividido };
}

/**
 * Qual pagamento dividir: os pagamentos das Diárias que vieram do banco (conta corrente inteira),
 * filtrados pelo dia e pelo valor ditos. Nenhum ou mais de um = a pergunta, com as opções.
 */
async function pagamentoParaDividir(ctx: ToolCtx, f: Freelancer, args: Record<string, unknown>): Promise<PagamentoQueSeDivide | { error: string }> {
  const c = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, p_de: null, p_ate: null, p_atalho: null }) as Record<string, any>;
  if (c && "error" in c) return { error: String(c.error) };
  let lista = ((c?.linhas ?? []) as any[]).map(pagamentoQueSeDivide).filter((x): x is PagamentoQueSeDivide => x !== null);
  const dia = args.data != null && args.data !== "" ? dataDoDito(args.data) : null;
  if (args.data != null && args.data !== "" && !dia) return { error: `Não entendi o dia "${String(args.data)}". Use dd/mm, 'ontem' ou o dia da semana.` };
  const valor = numeroDito(args.valor);
  if (dia) lista = lista.filter((x) => x.data === dia);
  if (valor != null && valor > 0) lista = lista.filter((x) => Math.abs(x.valor - valor) < 0.005);
  const filtro = [dia ? `em ${diaCurto(dia)}` : null, valor ? `de ${brl.format(valor)}` : null].filter(Boolean).join(" ");
  if (!lista.length) {
    return { error: `Não achei pagamento de diárias de ${f.nome} que veio do banco${filtro ? ` ${filtro}` : ""}. O Pix ainda só anotado ` +
      "divide ao registrar (registrar_pagamento_freelancer); dinheiro e bolso do sócio dividem na hora." };
  }
  if (lista.length > 1) {
    const ultimos = lista.slice(-5).map((x) => `${diaCurto(x.data)} ${brl.format(x.valor)}${x.dividido ? " (já dividido)" : ""}`);
    return { error: `Qual pagamento de ${f.nome}: ${ultimos.join("; ")}? Diga o dia ou o valor.` };
  }
  return lista[0];
}

/** A confirmação da divisão: qual pagamento e como fica (para o "sim"). */
export async function resumirDivisaoDoPagamento(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const f = await acharFreelancer(ctx, args.freelancer);
  if ("error" in f) return null;
  const pedido = reembolsosDitos(args.reembolsos);
  if ("error" in pedido) return null;
  const pag = await pagamentoParaDividir(ctx, f, args);
  if ("error" in pag) return `Dividir pagamento de *${f.nome}*\n⚠️ ${pag.error}`;
  const div = await divisaoPedida(ctx, f, pag.valor, pedido);
  if ("error" in div) return `Dividir pagamento de *${f.nome}*\n⚠️ ${div.error}`;
  const linhas = [`Dividir o pagamento de *${f.nome}*: ${brl.format(pag.valor)} · ${diaCurto(pag.data)} · ${pag.conta}`];
  linhas.push(div.escolhidos.length
    ? `Diárias ${brl.format(div.diarias)} · ${ROTULO_REEMBOLSOS} ${brl.format(div.reembolsos)} (${div.escolhidos.map((r) => r.codigo ?? "sem código").join(", ")}).`
    : "Tudo em Diárias de freelancers (sem reembolso).");
  linhas.push("O total do pagamento e o saldo com ele não mudam: só a categoria das partes.");
  return linhas.join("\n");
}

/**
 * A anotação ficou esperando e há, na fila, uma transação do mesmo valor nesses dias em outro nome. Só
 * CPF ou nome igual identificam (regra do dono): sem isso, não se sabe se é dele — e não se afirma.
 */
export function textoDaFilaSemIdentidade(p: Pick<PedidoDePagamento, "freelancer" | "valor">, nomeNoExtrato: string): string {
  return `Anotado: o Pix de ${brl.format(p.valor)} para ${p.freelancer.nome} já desconta no saldo dele. ` +
    `Na fila há uma transação de ${brl.format(p.valor)} nesses dias no nome "${nomeNoExtrato.slice(0, 120)}"; ` +
    `não liguei as duas sozinho porque o nome do extrato não identifica a pessoa (só o CPF ou o nome igual ao cadastro). ` +
    `Se aquela transação é desse pagamento, aprove-a na fila como diária dele: a anotação sai sozinha, sem contar duas vezes. ` +
    `Para ligar sem perguntar da próxima vez, ponha o CPF dele no cadastro.`;
}

async function registrarPagamento(ctx: ToolCtx, p: PedidoDePagamento) {
  const desc = descricaoDoPagamento(p);
  // resposta 4 do dono: com reembolso a quitar, o pagamento vai já dividido (o mesmo caminho da tela)
  const div = await divisaoPedida(ctx, p.freelancer, p.valor, p.reembolsos);
  if ("error" in div) return div;
  if (div.escolhidos.length) {
    // a data como veio: sem a data dita, o Pix vai sem ela (a anotação espera a linha de D-3 a D+7, como
    // no caminho sem divisão); dinheiro e bolso do sócio, o banco põe hoje
    return await chamar(ctx, "registrar_pagamento_do_freelancer", {
      p_favorecido_id: p.freelancer.id, p_valor: p.valor, p_data: p.data, p_forma: FORMA_NO_BANCO[p.forma],
      p_socio_id: p.socio?.id ?? null, p_reembolsos: div.escolhidos.map((r) => r.id), p_descricao: desc,
    }) as Record<string, unknown>;
  }
  if (p.forma === "pix") {
    const r = await chamar(ctx, "anotar_transacao", {
      p_sentido: "saida", p_valor: p.valor, p_data: p.data, p_documento: null, p_nome: null,
      p_fornecedor_id: null, p_favorecido_id: p.freelancer.id, p_cliente_id: null,
      p_categoria: CATEGORIA_DIARIAS, p_os_id: null, p_descricao: desc,
    }) as Record<string, unknown>;
    // 27/10/2026: o banco dizia "a transação na fila é de OUTRO (JOAO MARCELO RODRIGUES CORREA)" — era o
    // próprio João, com o cadastro sem CPF. Nome diferente não prova que é outra pessoa (nem que é a mesma):
    // diz o que se sabe e o que fazer, sem afirmar de quem é.
    if (r && !("error" in r) && r.outra_contraparte && !r.falta_quem) {
      return { ...r, message: textoDaFilaSemIdentidade(p, String(r.outra_contraparte)) };
    }
    return r;
  }
  return await chamar(ctx, "lancar_no_caixa", {
    p_sentido: "saida", p_valor: p.valor, p_descricao: desc, p_data: p.data, p_categoria: CATEGORIA_DIARIAS,
    p_fornecedor_id: null, p_favorecido_id: p.freelancer.id, p_cliente_id: null, p_os_id: null,
    p_pago_por: p.forma === "dinheiro" ? "caixa" : "socio", p_socio_id: p.socio?.id ?? null,
  }) as Record<string, unknown>;
}

// ── Extrato em PDF pelo WhatsApp (06/10/2026) ────────────────────────────────────────────────────
// "me manda o extrato do Roberto", "o PDF do que falta pagar pro João". O MESMO documento do botão
// "Extrato em PDF" da tela (_shared/diarias/extrato.ts) e o MESMO caminho do PDF do orçamento:
// renderiza no /api/pdf, guarda por minutos num bucket privado, manda pela Evolution, apaga. A
// credencial é um token de uso único (emitir_token_de_pdf) — extrato não tem link de ordem.

const janelaDeDoisMinutos = () => Math.floor(Date.now() / 120_000);

async function falhaDoExtrato(motivo: string) {
  return {
    error: `Não consegui mandar o PDF: ${motivo}.`,
    orientacao: "Diga que o anexo falhou (sem fingir que mandou); o extrato e o recibo em PDF também saem pela tela, em Financeiro › Diárias › Extrato.",
  };
}

type DocumentoPronto = { html: string; arquivo: string; legenda: string; chave: string };

async function cadastroDoFreelancer(ctx: ToolCtx, f: Freelancer) {
  const { data } = await ctx.admin.from("payees").select("name, document, pix_key, phone").eq("id", f.id).maybeSingle();
  return { nome: (data?.name as string) ?? f.nome, documento: (data?.document as string) ?? null, pix: (data?.pix_key as string) ?? null,
    telefone: String(data?.phone ?? "").replace(/\D/g, "") };
}

const empresaDosSettings = (s: Record<string, string>) =>
  ({ nome: s.company_name || "HBR", cnpj: s.cnpj || null, cidade: [s.city, s.state].filter(Boolean).join("/") || null });

/** O extrato do período (o mesmo do botão da tela). */
async function documentoDoExtrato(ctx: ToolCtx, f: Freelancer, periodo: PeriodoPedido): Promise<DocumentoPronto | { error: string }> {
  const conta = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, ...periodo }) as Record<string, any>;
  if (conta && "error" in conta) return { error: String(conta.error) };
  const cad = await cadastroDoFreelancer(ctx, f);
  const html = montarExtratoHtml({
    empresa: empresaDosSettings(ctx.settings), freelancer: cad, conta: conta as unknown as ContaDoExtrato, geradoEm: new Date(),
  });
  const saldo = Number(conta.saldo_final) || 0;
  return {
    html,
    arquivo: limitarNomeDoArquivo(nomeDoArquivo("extrato-diarias", f.nome, conta as ContaDoExtrato, "pdf")),
    legenda: `📄 Extrato de diárias — ${f.nome}\nPeríodo: ${periodoResolvido(conta)}\nSaldo: ${brl.format(Math.abs(saldo))} (${ESTADO[String(conta.estado)] ?? conta.estado})`,
    chave: chaveDeEnvio("agente-extrato-diarias", f.id, periodoResolvido(conta), saldo, Number(conta.pago)),
  };
}

/**
 * A foto do acerto. `reembolsos` (F2b, 11/10/2026): as despesas da empresa que ele pagou do bolso,
 * com o comprovante (CMP), que entram no acerto a favor dele.
 */
type Acerto = { id: string; numero: number; de: string; ate: string; saldo_anterior: number; dias: number; trabalhado: number;
  pago_no_periodo: number; valor_do_acerto: number; status: string; reembolsos?: number;
  /** F2: o dia do Pix de quitação e a foto congelada do recibo (nula no acerto do modelo antigo). */
  pagos_ate?: string | null; documento?: DocumentoDoRecibo | null };

/**
 * " · reembolso de despesas pagas pelo técnico R$ 62,00" quando há (F2b; o rótulo inequívoco é a
 * resposta 9 do dono, 11/10/2026); vazio sem reembolso (o texto de antes).
 */
function reembolsosNoTexto(valor: unknown, separador = " · "): string {
  const n = Number(valor);
  return Number.isFinite(n) && n > 0 ? `${separador}${ROTULO_REEMBOLSOS.toLowerCase()} ${brl.format(n)}` : "";
}

/** O acerto pedido (pelo número) ou o último fechado da pessoa. */
async function acertoDe(ctx: ToolCtx, f: Freelancer, numero?: unknown): Promise<Acerto | { error: string }> {
  let q = ctx.admin.from("acertos_diarias")
    .select("id, numero, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo, valor_do_acerto, status, reembolsos, pagos_ate, documento")
    .eq("favorecido_id", f.id);
  const n = numero == null || numero === "" ? null : Number(String(numero).replace(/\D/g, ""));
  q = n ? q.eq("numero", n) : q.eq("status", "fechado").order("ate", { ascending: false }).limit(1);
  const { data, error } = await q;
  if (error) return { error: `Falha ao ler os acertos: ${error.message}` };
  const a = (data ?? [])[0] as any;
  if (!a) return { error: n ? `Não achei o acerto nº ${n} de ${f.nome}.` : `${f.nome} ainda não tem acerto fechado. Feche com fechar_acerto_freelancer.` };
  return { ...a, saldo_anterior: Number(a.saldo_anterior), dias: Number(a.dias), trabalhado: Number(a.trabalhado),
    pago_no_periodo: Number(a.pago_no_periodo), valor_do_acerto: Number(a.valor_do_acerto), reembolsos: Number(a.reembolsos ?? 0) || 0 };
}

/**
 * O recibo. De serviços (F2, 27/10/2026): só da foto congelada no banco — o papel é sempre o mesmo, com
 * o aviso de conferência até o dono liberar (app_settings diarias_recibo_liberado). Acerto do modelo
 * antigo: totais da foto; linhas (dias e vales) da conta corrente do mesmo período.
 */
async function documentoDoRecibo(ctx: ToolCtx, f: Freelancer, a: Acerto): Promise<DocumentoPronto | { error: string }> {
  const n0 = numeroDoRecibo(a.numero);
  if (a.documento) {
    return {
      html: montarReciboDeServicosHtml({ numero: a.numero, documento: a.documento, liberado: String(ctx.settings.diarias_recibo_liberado ?? "") === "true", geradoEm: new Date() }),
      arquivo: limitarNomeDoArquivo(nomeDoArquivo(`recibo-servicos-${n0}`, f.nome, { de: a.de, ate: a.ate }, "pdf")),
      legenda: `🧾 Recibo de serviços nº ${n0} — ${f.nome}\nServiços de ${ddmm(a.de)} a ${ddmm(a.ate)} · Pix de ${brl.format(a.valor_do_acerto)}` +
        (a.pagos_ate ? ` em ${ddmm(a.pagos_ate)}` : "") + " quitou o total" +
        (a.status !== "fechado" ? "\n⚠️ Este recibo foi REABERTO." : ""),
      chave: chaveDeEnvio("agente-recibo-servicos", f.id, a.numero, a.status),
    };
  }
  const conta = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, p_de: a.de, p_ate: a.ate }) as Record<string, any>;
  if (conta && "error" in conta) return { error: String(conta.error) };
  const cad = await cadastroDoFreelancer(ctx, f);
  const n = numeroDoRecibo(a.numero);
  return {
    html: montarReciboHtml({ empresa: empresaDosSettings(ctx.settings), freelancer: cad, acerto: a, linhas: conta.linhas ?? [], geradoEm: new Date() }),
    arquivo: limitarNomeDoArquivo(nomeDoArquivo(`recibo-diarias-${n}`, f.nome, { de: a.de, ate: a.ate }, "pdf")),
    legenda: `🧾 Recibo de diárias nº ${n} — ${f.nome}\nPeríodo: ${ddmm(a.de)} a ${ddmm(a.ate)}\n` +
      `Trabalhado ${brl.format(a.trabalhado)}${reembolsosNoTexto(a.reembolsos)} · vales ${brl.format(a.pago_no_periodo)} · a pagar ${brl.format(a.valor_do_acerto)}` +
      (a.status !== "fechado" ? "\n⚠️ Este acerto foi REABERTO." : ""),
    chave: chaveDeEnvio("agente-recibo-diarias", f.id, a.numero, a.status),
  };
}

/** Renderiza com token de uso único, guarda por minutos, manda pela Evolution e apaga. */
async function mandarPdf(ctx: ToolCtx, telefone: string, doc: DocumentoPronto, contexto: string, rotulo: string) {
  const { data: token, error: tErr } = await ctx.admin.rpc("emitir_token_de_pdf", { p_finalidade: rotulo });
  if (tErr || !token) return { ok: false as const, motivo: `sem credencial para o servidor de PDF (${tErr?.message ?? "token vazio"})` };
  const chave = chaveDeEnvio(doc.chave, telefone, janelaDeDoisMinutos());
  const entrega = await guardarEEntregar({
    admin: ctx.admin,
    doc: { html: doc.html, nomeDoArquivo: doc.arquivo },
    pdfToken: String(token),
    baseUrl: ctx.settings.app_public_url || "",
    rotuloDoLog: rotulo,
    entregar: (url) => enviarDocumentoWhatsapp({ phone: telefone, url, filename: doc.arquivo, caption: doc.legenda, context: contexto, jwt: ctx.jwt, dedupeKey: chave }),
  });
  if (!entrega.ok) return { ok: false as const, motivo: entrega.motivo };
  const envio = entrega.valor;
  if (!envio.ok) {
    // Mesma regra do PDF do orçamento: tool que desistiu sem resposta libera a reserva.
    if (envio.semResposta) await liberarEnvio(ctx.admin, chave).catch(() => {});
    return { ok: false as const, motivo: envio.error };
  }
  return { ok: true as const, deduplicated: !!envio.deduplicated, modoTeste: desviadoPorTeste(ctx.settings) };
}

async function telefoneDeQuemPediu(ctx: ToolCtx): Promise<string | { error: string }> {
  const { data: u, error } = await ctx.admin.from("app_users").select("phone_normalized").eq("id", ctx.userId).maybeSingle();
  if (error) return { error: `Falha ao ler o seu cadastro: ${error.message}` };
  const t = String(u?.phone_normalized ?? "").replace(/\D/g, "");
  return t || { error: "Você não tem um WhatsApp cadastrado para receber o PDF. Cadastre em Configurações → Usuários (aba IA/Zap)." };
}

/** Contexto do envio ao FREELANCER (não é cliente nem o dono; nunca 'quote'). */
const CONTEXTO_AO_FREELANCER = "diarias_ao_freelancer";

/**
 * A confirmação do recibo: a função do banco simulando (F2, 27/10/2026) — serviços, já recebido e o Pix
 * que zera a conta; com trava, as frases do banco (todas) e o aviso de que vai recusar.
 */
export async function resumirAcerto(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const f = await acharFreelancer(ctx, args.freelancer);
  if ("error" in f) return null;
  const ate = args.ate ? dataDoDito(args.ate) : null;
  const { data, error } = await ctx.admin.rpc("fechar_acerto_diarias", { p_favorecido_id: f.id, p_ate: ate, p_simular: true, p_autor: null });
  if (error) return `Recibo de *${f.nome}*\n⚠️ ${semCodigo(error.message)} — o sistema vai recusar.`;
  const s = data as Record<string, any>;
  const travas = Array.isArray(s.travas) ? s.travas.map(String) : [];
  if (s.ok === false || travas.length) {
    return [`Recibo de *${f.nome}*`, "⚠️ Antes do recibo:", ...travas.map((t: string) => `• ${t}`), "— o sistema vai recusar."].join("\n");
  }
  const pix = s.pix ?? {};
  return [`Recibo de *${f.nome}*: serviços de ${ddmm(s.de)} a ${ddmm(s.ate)}`,
    `${String(s.dias).replace(".", ",")} diária(s) = ${brl.format(Number(s.trabalhado))}` +
      (Number(s.saldo_anterior) ? ` · saldo anterior ${brl.format(Number(s.saldo_anterior))}` : "") +
      reembolsosNoTexto(s.reembolsos) +
      ` · já recebido ${brl.format(Number(s.pago_no_periodo))}`,
    `*Pix de ${pix.data ? ddmm(pix.data) : "—"} que quita: ${brl.format(Number(s.valor_do_acerto))}*`,
    `Os dias até ${ddmm(s.ate)} ficam travados (reabrir só pela tela ou pedindo, com motivo).`].join("\n");
}

/** A confirmação do envio ao freelancer: o quê, para que número, e o que acontece com a resposta. */
export async function resumirEnvioAoFreelancer(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const f = await acharFreelancer(ctx, args.freelancer);
  if ("error" in f) return null;
  const a = await acertoDe(ctx, f, args.numero);
  if ("error" in a) return `Mandar ao freelancer\n⚠️ ${a.error}`;
  const cad = await cadastroDoFreelancer(ctx, f);
  return [`Mandar a *${f.nome}* (WhatsApp ${cad.telefone || "SEM TELEFONE NO CADASTRO"}) o recibo nº ${numeroDoRecibo(a.numero)}`,
    `${ddmm(a.de)} a ${ddmm(a.ate)} · a pagar ${brl.format(a.valor_do_acerto)}`,
    "A mensagem pede para ele conferir e responder OK; a resposta fica registrada no acerto."].join("\n");
}

export const diariasTools: ToolDef[] = [
  {
    name: "registrar_diaria",
    description:
      "Registra o DIA de um freelancer de diária já cadastrado: 'Mickael fez meio período ontem', 'Roberto trabalhou dia inteiro " +
      "na OS 1234'. É o dia que já aconteceu; quem VAI vir ('o Roberto não vem amanhã', 'só de manhã na terça') é " +
      "equipe_disponibilidade. Um dia por pessoa: repetir a mesma data CORRIGE o dia, não duplica. Dia que ele NÃO trabalhou não se lança " +
      "(fica sem diária; diga isso ao dono); 'apagar' só para dia lançado por ENGANO. VÁRIOS TRECHOS numa frase ('seg a qui " +
      "inteiro, sex meio, sáb inteiro'): UMA chamada com dias=[{data, data_ate, jornada}, …] — uma confirmação só. Chame direto, " +
      "sem perguntar 'lanço?' antes: o sistema já mostra o resumo e pede o sim. A diária vem do cadastro — não pergunte " +
      "valor nem horário; valor_diaria só quando a pessoa DISSER outro valor para o dia ('na quarta foram 130'). Freelancer que " +
      "ainda não existe: cadastrar_freelancer antes. Não é pagamento (pagamento vem do extrato; em dinheiro é lancar_no_caixa) nem hora de OS " +
      "(log_service_order_hours). Vários dias com a mesma jornada ('a semana toda', 'de segunda até hoje'): data + data_ate; " +
      "só dias úteis, salvo fim_de_semana; dia já lançado no intervalo fica como está. EXTRAS e DESCONTOS do dia, como na tela: " +
      "'diária inteira mais 50 de almoço' (extras=50, observacao='almoço'), 'desconta 30 da diária do Mickael de ontem, chegou " +
      "atrasado' (jornada='manter', descontos=30) — o valor é o TOTAL do dia e substitui o que havia (a confirmação mostra o antes). " +
      "Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou ('Roberto')." },
        data: { type: "string", description: "'hoje' (padrão), 'ontem', dd/mm ou dia da semana ('segunda'). Num intervalo, o primeiro dia." },
        data_ate: { type: "string", description: "Só para vários dias: o último dia ('hoje', dd/mm, 'sexta'). Nunca no futuro." },
        fim_de_semana: { type: "boolean", description: "Num intervalo, incluir sábado e domingo — só se a pessoa disser." },
        jornada: {
          type: "string", enum: [...JORNADAS_DITAS],
          description: "inteiro, meio, apagar (lançado por engano; um dia só) ou manter (o dia já lançado fica como está; só muda extras, descontos, OS ou observação). Sem dias.",
        },
        dias: {
          type: "array",
          description: "Vários trechos de uma vez (uma confirmação só): cada um com data (e data_ate num intervalo) e a jornada; extras, descontos, os, observacao e valor_diaria do trecho se a pessoa disser. Com dias, não mande data/jornada fora.",
          items: {
            type: "object",
            properties: {
              data: { type: "string" }, data_ate: { type: "string" }, jornada: { type: "string", enum: ["inteiro", "meio", "manter"] },
              fim_de_semana: { type: "boolean" }, extras: { type: "number" }, descontos: { type: "number" },
              os: { type: "string" }, observacao: { type: "string" }, valor_diaria: { type: "number" },
            },
            required: ["data", "jornada"],
          },
        },
        os: { type: "string", description: "Número da OS em que trabalhou; duas OS separadas por vírgula (o dia se divide igual)." },
        observacao: { type: "string", description: "Serviço feito, obra, embarcação ou veículo — se a pessoa disser." },
        valor_diaria: { type: "number", description: "Só se a pessoa DISSER o valor do dia, diferente do cadastro (em reais). Sem isso vale a diária do cadastro." },
        extras: { type: "number", description: "Extras do dia em reais (o almoço quando ele traz o próprio, condução, hora a mais) — o total do dia. Só se a pessoa disser." },
        descontos: { type: "number", description: "Descontos do dia em reais (atraso, vale) — o total do dia. Só se a pessoa disser." },
      },
      required: ["freelancer"],
    },
    risk: "medium",
    roles: CARGOS,
    preValidar(args) {
      if (Array.isArray(args?.dias)) {
        if (!args.dias.length) return { error: "Diga os dias: cada dia (ou cada intervalo) com a jornada." };
        if (args.dias.length > MAX_TRECHOS) return { error: `Trechos demais (${args.dias.length}): até ${MAX_TRECHOS} por pedido.` };
        for (const d of args.dias as Array<Record<string, unknown>>) {
          if (d?.jornada === "faltou") return { error: SEM_FALTA };
          if (!["inteiro", "meio", "manter"].includes(String(d?.jornada ?? ""))) {
            return { error: `Jornada "${d?.jornada}" não existe na lista: use inteiro, meio ou manter (apagar é fora da lista).` };
          }
        }
        return null;
      }
      if (args?.jornada === "faltou") return { error: SEM_FALTA };
      if (!JORNADAS_DITAS.includes(String(args?.jornada ?? "") as typeof JORNADAS_DITAS[number])) {
        return { error: `Jornada "${args?.jornada}" não existe: use inteiro, meio, apagar ou manter.` };
      }
      if (args?.jornada === "apagar" && args?.data_ate) return { error: "Apagar é um dia de cada vez: diga qual dia." };
      if (args?.jornada === "manter" && args?.data_ate) return { error: "Mexer só em extras/descontos é um dia de cada vez: diga qual dia." };
      return null;
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      if (Array.isArray(args.dias)) return await registrarLote(ctx, args);
      const p = await resolverDiaria(ctx, args);
      if ("error" in p) return p;
      if (p.intervalo) return await registrarIntervalo(ctx, p);
      if (p.jornada === "apagar") {
        const atual = await diaLancado(ctx, p.freelancer, p.data);
        if (!atual) return { error: `Não há dia lançado para ${p.freelancer.nome} em ${diaCurto(p.data)}.` };
        const r = await chamar(ctx, "apagar_diaria", { p_diaria_id: atual.id }) as Record<string, unknown>;
        if (r && "error" in r) return r;
        return { ok: true, apagado: r?.apagado, aviso: String(r?.message ?? "Dia apagado.") };
      }
      const r = await chamar(ctx, "registrar_diaria", {
        p_favorecido_id: p.freelancer.id,
        p_data: p.data,
        p_jornada: p.jornada,
        p_os_ids: p.os.length ? p.os.map((o) => o.id) : null,
        p_observacao: p.observacao,
        p_extras: p.extras, p_descontos: p.descontos, p_valor_diaria: p.valorDiaria,
        p_origem: "agente",
      }) as Record<string, unknown>;
      if (r && "error" in r) return r;
      // O saldo junto da confirmação: é a pergunta que vem logo depois ("e quanto devo pra ele?").
      return { ...r, aviso: `${String(r?.message ?? "")}${await saldoDito(ctx, p.freelancer)}`.trim() };
    },
  },
  {
    name: "consultar_freelancer",
    description:
      "Quanto se deve a um freelancer de diária e o que ele trabalhou e recebeu: 'quanto devo pro Roberto?', 'quantos dias o Mickael " +
      "fez esse mês?', 'o que falta pagar pro João?' (periodo=em_aberto), 'o que ele fez desde o último pagamento?', 'de 14/09 a 27/09' " +
      "(de/ate), 'quanto o Roberto tem de extra este mês?' (extras_no_periodo e descontos_no_periodo, com o freelancer). " +
      "reembolsos = reembolso de despesas pagas pelo técnico (despesas da empresa que ele pagou, com o comprovante CMP-00124): " +
      "somam a favor dele e entram no próximo acerto (para tirar um, o dono cancela o CMP); a mesma despesa não entra também " +
      "como extra (o extra de almoço é quando ele traz o próprio). Sem nome, mostra todos. Só consulta — não grava nada. Para o " +
      "PDF do extrato, enviar_extrato_freelancer.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome; vazio = todos." },
        periodo: {
          type: "string", enum: [...PERIODOS],
          description: "tudo (padrão: saldo acumulado), em_aberto (o que falta pagar, desde o último acerto), desde_ultimo_pagamento, " +
            "ultimos_15_dias, semana_atual, este_mes, mes_passado. Ignorado se vier de/ate.",
        },
        de: { type: "string", description: "Data inicial dita (dd/mm, 'segunda'), para período livre." },
        ate: { type: "string", description: "Data final dita (dd/mm, 'hoje'), para período livre." },
      },
    },
    risk: "low",
    roles: CARGOS,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const periodo = periodoDito(args);
      if ("error" in periodo) return periodo;
      if (!args.freelancer) {
        const r = await chamar(ctx, "resumo_freelancers", periodo) as Record<string, unknown>;
        if (r && "error" in r) return r;
        const pessoas = ((r?.pessoas ?? []) as any[]).map((x) => ({
          nome: x.nome, periodo: periodoResolvido(x), dias: Number(x.dias), trabalhado: Number(x.trabalhado),
          // F2b: as despesas que ele pagou com comprovante (CMP), a favor dele, à parte dos dias
          ...(Number(x.reembolsos) > 0 ? { reembolsos: Number(x.reembolsos) } : {}),
          pago: Number(x.pago),
          ...(Number(x.pago_aguardando_banco) > 0 ? { pago_lancado_a_mao_aguardando_banco: Number(x.pago_aguardando_banco) } : {}),
          // 27/10/2026: o Pix que já saiu do banco para ele e espera a fila — já está no "pago"
          ...(Number(x.pago_falta_aprovar) > 0 ? { pago_no_banco_falta_aprovar_na_fila: Number(x.pago_falta_aprovar) } : {}),
          saldo: Number(x.saldo_final), situacao: ESTADO[x.estado] ?? x.estado, ultimo_pagamento: x.ultimo_pagamento,
        }));
        return { pessoas };
      }
      const f = await acharFreelancer(ctx, args.freelancer);
      if ("error" in f) return f;
      const c = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, ...periodo }) as Record<string, any>;
      if (c && "error" in c) return c;
      const todas = (c?.linhas ?? []) as any[];
      const linhas = todas.slice(-15).map((l) => {
        if (l.tipo === "dia") {
          return {
            data: l.data, dia: rotuloDaFracao(Number(l.fracao)), valor: Number(l.trabalhado), os: (l.os ?? []).map((o: any) => o.numero),
            // Extras e descontos do dia (07/10/2026): "quanto o Roberto tem de extra este mês?".
            ...(Number(l.extras) > 0 ? { extras: Number(l.extras) } : {}),
            ...(Number(l.descontos) > 0 ? { descontos: Number(l.descontos) } : {}),
            ...(l.observacao ? { observacao: l.observacao } : {}),
          };
        }
        // F2b (11/10/2026): o reembolso de um comprovante é a favor dele, não pagamento; o rótulo
        // inequívoco (resposta 9 do dono) e, se um pagamento dividido já o quitou, quando
        if (l.tipo === "reembolso") {
          return {
            data: l.data, tipo: ROTULO_REEMBOLSO.toLowerCase(), valor: Number(l.trabalhado), codigo: l.conta, descricao: l.descricao,
            ...(l.observacao ? { observacao: l.observacao } : {}),
          };
        }
        return {
          data: l.data, pagamento: Number(l.pago),
          de_onde: l.conta === CONTA_FALTA_APROVAR ? "Pix já no banco, falta aprovar na fila de lançamentos"
            : l.aguardando ? "lançado à mão, aguardando o banco" : l.conta,
        };
      });
      const dias = todas.filter((l) => l.tipo === "dia");
      const soma = (k: string) => Math.round(dias.reduce((s, l) => s + (Number(l[k]) || 0), 0) * 100) / 100;
      return {
        freelancer: f.nome,
        periodo: periodoResolvido(c),
        saldo_antes_do_periodo: Number(c.saldo_anterior),
        dias: Number(c.dias), trabalhado: Number(c.trabalhado),
        // F2b: as despesas da empresa que ele pagou (comprovante), que entram no próximo acerto
        reembolsos: Number(c.reembolsos ?? 0) || 0,
        pago: Number(c.pago),
        ...(Number(c.pago_falta_aprovar) > 0 ? { pago_no_banco_falta_aprovar_na_fila: Number(c.pago_falta_aprovar) } : {}),
        extras_no_periodo: soma("extras"), descontos_no_periodo: soma("descontos"),
        saldo: Number(c.saldo_final), situacao: ESTADO[c.estado] ?? c.estado,
        ultimos_lancamentos: linhas,
      };
    },
  },
  {
    name: "cadastrar_freelancer",
    description:
      "Cadastra um freelancer NOVO de diária: 'cadastre o João Marcelo, diária de 150, Pix e-mail joao@…', 'entrou um ajudante " +
      "novo'. Cria tudo de uma vez: o favorecido (ou usa o que já existe com o mesmo nome/CPF), a diária, a conta corrente desde " +
      "o primeiro dia de trabalho e, com CPF, a regra que lança os Pix dele sozinhos. Precisa do nome e do valor da diária — se " +
      "faltar o valor, PERGUNTE; não invente. Chave Pix, CPF e telefone só se a pessoa disser. desde = primeiro dia trabalhado, " +
      "quando for antes de hoje ('começou terça'). Os dias trabalhados vêm depois, com registrar_diaria. Para freelancer de diária " +
      "não use cadastrar_favorecido (ele não cria a diária). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        nome: { type: "string", description: "Nome como a pessoa disse; o nome completo, se ela der." },
        valor_diaria: { type: "number", description: "Valor do dia inteiro, em reais (meio período = metade)." },
        desde: { type: "string", description: "Primeiro dia de trabalho: 'hoje' (padrão), 'terça', dd/mm. Nunca no futuro." },
        chave_pix: { type: "string", description: "A chave Pix como foi dita." },
        tipo_chave: { type: "string", enum: [...TIPOS_DE_CHAVE], description: "Se a pessoa disser (ou se for óbvio: e-mail tem @). Número de 11 dígitos: pergunte se é CPF ou telefone." },
        cpf: { type: "string", description: "CPF (ou CNPJ), se a pessoa disser." },
        telefone: { type: "string", description: "Telefone/WhatsApp dele, se a pessoa disser." },
        observacao: { type: "string", description: "Ex.: 'entrou no lugar do Mickael'." },
      },
      required: ["nome", "valor_diaria"],
    },
    risk: "medium",
    roles: CARGOS,
    preValidar(args) {
      const p = paramsDoCadastro(args ?? {});
      return "error" in p ? p : null;
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const p = paramsDoCadastro(args);
      if ("error" in p) return p;
      const r = await chamar(ctx, "cadastrar_freelancer", { ...p, p_simular: false }) as Record<string, unknown>;
      if (r && "error" in r) return r;
      return { ...r, aviso: String(r?.message ?? "") };
    },
  },
  {
    name: "registrar_pagamento_freelancer",
    description:
      "Registra o que se PAGOU a um freelancer de diária: 'paguei 100 pro Roberto no Pix', 'dei 50 em dinheiro pro João', " +
      "'paguei o Mickael do meu bolso'. forma: pix (Pix/transferência já feito — fica anotado e casa com a linha do banco; já " +
      "aparece no extrato de diárias), dinheiro (sai do Caixa) ou bolso_do_socio (vira reembolso ao sócio). Com reembolso de " +
      "despesas pagas pelo técnico em aberto (comprovantes CMP), o sistema PROPÕE dividir o pagamento entre Diárias e o " +
      "reembolso (na categoria de cada comprovante) e a confirmação mostra a divisão: o dono confirma, diz 'sem reembolso' " +
      "(reembolsos='nenhum') ou quais CMPs. Não é o dia trabalhado (registrar_diaria). Valor e forma são obrigatórios: se " +
      "faltar, PERGUNTE. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou." },
        valor: { type: "number", description: "Valor pago, em reais." },
        forma: { type: "string", enum: [...FORMAS], description: "pix, dinheiro ou bolso_do_socio." },
        data: { type: "string", description: "Quando pagou: 'hoje' (padrão), 'ontem', dd/mm, dia da semana." },
        socio: { type: "string", description: "Só no bolso_do_socio, se a pessoa disser qual (padrão: quem está falando)." },
        observacao: { type: "string", description: "Ex.: 'adiantamento', 'acerto da quinzena'." },
        reembolsos: {
          type: "string",
          description: "Que reembolsos de despesas pagas pelo técnico este pagamento quita: 'proposta' (padrão: o que o sistema " +
            "propõe), 'nenhum' (a pessoa disse 'sem reembolso': tudo em Diárias) ou os CMPs ditos ('CMP-00124, CMP-00130').",
        },
      },
      required: ["freelancer", "valor", "forma"],
    },
    risk: "medium",
    roles: CARGOS,
    preValidar(args) {
      if (!FORMAS.includes(String(args?.forma ?? "") as Forma)) return { error: "Como foi pago? pix, dinheiro ou bolso_do_socio." };
      const v = numeroDito(args?.valor);
      if (v == null || v <= 0) return { error: "Qual o valor pago? (não invente: pergunte)" };
      const r = reembolsosDitos(args?.reembolsos);
      return "error" in r ? r : null;
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const p = await resolverPagamento(ctx, args);
      if ("error" in p) return p;
      const r = await registrarPagamento(ctx, p);
      if (r && "error" in r) return r;
      if (r && r.ok === false) return { ok: false, aviso: String(r.message ?? "Não lancei.") };
      return { ok: true, aviso: `${String(r?.message ?? "Pagamento lançado.")}${await saldoDito(ctx, p.freelancer)}`.trim() };
    },
  },
  {
    name: "dividir_pagamento_freelancer",
    description:
      "DIVIDE um pagamento de diárias que já veio do banco (o Pix aprovado no Extrato, ou lançado pela regra por CPF) entre " +
      "Diárias e o reembolso de despesas pagas pelo técnico (os comprovantes CMP que ele pagou): 'aquele Pix de 500 pro Roberto " +
      "tinha 92 de reembolso', 'divide o pagamento do João de sexta'. O sistema propõe os reembolsos em aberto (os do acerto " +
      "primeiro, por data, enquanto cabem); a pessoa pode dizer quais CMPs ou 'sem reembolso' (junta de volta o que foi " +
      "dividido). Pagamento em dinheiro ou do bolso do sócio já divide ao registrar (registrar_pagamento_freelancer). O total " +
      "do pagamento e o saldo com ele não mudam: só a categoria das partes. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou." },
        data: { type: "string", description: "O dia do pagamento, se a pessoa disser ('sexta', dd/mm): escolhe entre vários." },
        valor: { type: "number", description: "O valor do pagamento, se a pessoa disser: escolhe entre vários." },
        reembolsos: {
          type: "string",
          description: "'proposta' (padrão), 'nenhum' (juntar de volta: tudo em Diárias) ou os CMPs ditos ('CMP-00124, CMP-00130').",
        },
      },
      required: ["freelancer"],
    },
    risk: "medium",
    roles: CARGOS,
    preValidar(args) {
      const r = reembolsosDitos(args?.reembolsos);
      return "error" in r ? r : null;
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const f = await acharFreelancer(ctx, args.freelancer);
      if ("error" in f) return f;
      const pedido = reembolsosDitos(args.reembolsos);
      if ("error" in pedido) return pedido;
      const pag = await pagamentoParaDividir(ctx, f, args);
      if ("error" in pag) return pag;
      const div = await divisaoPedida(ctx, f, pag.valor, pedido);
      if ("error" in div) return div;
      if (!div.emAberto.length && pedido.modo !== "nenhum" && !pag.dividido) {
        return { ok: false, aviso: `Nada a dividir: ${f.nome} não tem ${ROTULO_REEMBOLSO.toLowerCase()} em aberto.` };
      }
      const r = await chamar(ctx, "dividir_pagamento_do_freelancer", {
        p_payable_id: pag.id, p_reembolsos: div.escolhidos.map((x) => x.id),
      }) as Record<string, unknown>;
      if (r && "error" in r) return r;
      return { ok: true, aviso: `${String(r?.message ?? "Feito.")}${await saldoDito(ctx, f)}`.trim() };
    },
  },
  {
    name: "enviar_extrato_freelancer",
    description:
      "Manda o EXTRATO ou o RECIBO de diárias de um freelancer em PDF para o WhatsApp de QUEM PEDIU (os mesmos PDFs da tela): " +
      "'me manda o extrato do Roberto', 'o PDF do que falta pagar pro João' (periodo=em_aberto), 'extrato do Mickael de 14/09 a " +
      "27/09' (de/ate), 'me manda o recibo do último acerto do João' (documento=recibo; numero se disser). Sem período = o histórico " +
      "inteiro. Para mandar AO FREELANCER, enviar_acerto_ao_freelancer.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou." },
        documento: { type: "string", enum: ["extrato", "recibo"], description: "extrato (padrão) ou recibo de um acerto fechado." },
        periodo: { type: "string", enum: [...PERIODOS], description: "Só no extrato; como em consultar_freelancer; padrão tudo." },
        de: { type: "string", description: "Só no extrato: data inicial dita." },
        ate: { type: "string", description: "Só no extrato: data final dita." },
        numero: { type: "string", description: "Só no recibo: o nº do acerto, se a pessoa disser (padrão: o último)." },
      },
      required: ["freelancer"],
    },
    // Só para quem pede, e o conteúdo é o que ele já vê na tela: nada a confirmar.
    risk: "low",
    roles: CARGOS,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const recibo = args.documento === "recibo";
      const periodo = recibo ? null : periodoDito(args);
      if (periodo && "error" in periodo) return periodo;
      const f = await acharFreelancer(ctx, args.freelancer);
      if ("error" in f) return f;
      const esperando = await lancamentosEsperandoSim(ctx, f);
      if (esperando) return { error: textoDoPdfEsperando(f, esperando) };
      const telefone = await telefoneDeQuemPediu(ctx);
      if (typeof telefone !== "string") return telefone;

      let doc: DocumentoPronto | { error: string };
      if (recibo) {
        const a = await acertoDe(ctx, f, args.numero);
        if ("error" in a) return a;
        doc = await documentoDoRecibo(ctx, f, a);
      } else {
        doc = await documentoDoExtrato(ctx, f, periodo as PeriodoPedido);
      }
      if ("error" in doc) return await falhaDoExtrato(doc.error);

      const envio = await mandarPdf(ctx, telefone, doc, CONTEXTO_DO_ENVIO, `${recibo ? "recibo" : "extrato"} de diárias de ${f.nome}`);
      if (!envio.ok) return await falhaDoExtrato(envio.motivo);
      if (envio.deduplicated) return { ok: true, deduplicated: true, aviso: `Esse mesmo PDF de ${f.nome} já foi mandado há instantes; não reenviei.` };
      return {
        ok: true,
        enviado_para: envio.modoTeste ? "o número de TESTE do WhatsApp (modo de teste ligado)" : "o WhatsApp de quem pediu",
        freelancer: f.nome, documento: recibo ? "recibo" : "extrato", arquivo: doc.arquivo,
        observacao: envio.modoTeste
          ? "O modo de teste do WhatsApp está ligado: o arquivo foi para o número de teste, não para quem pediu. Diga isso."
          : "O arquivo já chegou no WhatsApp de quem pediu.",
      };
    },
  },
  {
    name: "fechar_acerto_freelancer",
    description:
      "EMITE o recibo de serviços de um freelancer DEPOIS de pago: 'fecha o acerto do Roberto', 'faz o recibo do João até sexta'. " +
      "O recibo sai no Pix que ZERA a conta (o sistema acha o Pix; 'ate' = último dia de serviço, padrão o dia do Pix): guarda o " +
      "papel numerado e TRAVA os dias até essa data. Não registra pagamento: se ainda falta pagar, o Pix está na fila ou falta CPF, " +
      "a confirmação diz o que fazer antes. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou." },
        ate: { type: "string", description: "Último dia de serviço do recibo: dd/mm, 'sexta'; padrão o dia do Pix que zera." },
      },
      required: ["freelancer"],
    },
    risk: "medium",
    roles: CARGOS,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const f = await acharFreelancer(ctx, args.freelancer);
      if ("error" in f) return f;
      const ate = args.ate ? dataDoDito(args.ate) : null;
      if (args.ate && !ate) return { error: `Não entendi até quando: "${args.ate}". Use hoje, dd/mm ou o dia da semana.` };
      const r = await chamar(ctx, "fechar_acerto_diarias", { p_favorecido_id: f.id, p_ate: ate, p_simular: false }) as Record<string, unknown>;
      if (r && "error" in r) return r;
      return { ok: true, numero: r?.numero, valor_do_acerto: r?.valor_do_acerto,
        aviso: `${String(r?.message ?? "Recibo fechado.")} O PDF sai com enviar_extrato_freelancer (documento=recibo) ou vai a ele com enviar_acerto_ao_freelancer.` };
    },
  },
  {
    name: "reabrir_acerto_freelancer",
    description:
      "REABRE o último acerto de um freelancer para corrigir um dia travado: 'reabre o acerto do Roberto, o dia 24 estava errado'. " +
      "Só o último acerto, e com o motivo (fica registrado). Depois de corrigir, feche de novo. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou." },
        motivo: { type: "string", description: "Por que reabrir — obrigatório; pergunte se a pessoa não disser." },
      },
      required: ["freelancer", "motivo"],
    },
    risk: "medium",
    roles: CARGOS,
    preValidar(args) {
      return textoOuNulo(args?.motivo) ? null : { error: "Qual o motivo de reabrir o acerto? (fica registrado)" };
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const f = await acharFreelancer(ctx, args.freelancer);
      if ("error" in f) return f;
      const a = await acertoDe(ctx, f);
      if ("error" in a) return a;
      const r = await chamar(ctx, "reabrir_acerto_diarias", { p_acerto_id: a.id, p_motivo: textoOuNulo(args.motivo) }) as Record<string, unknown>;
      if (r && "error" in r) return r;
      return { ok: true, aviso: String(r?.message ?? "Acerto reaberto.") };
    },
  },
  {
    name: "enviar_acerto_ao_freelancer",
    description:
      "Manda AO FREELANCER, no WhatsApp dele (do cadastro), o recibo do acerto em PDF, pedindo que confira e responda OK — a " +
      "resposta fica registrada no acerto: 'manda o recibo pro João conferir'. Precisa de acerto fechado (fechar_acerto_freelancer) " +
      "e do telefone no cadastro. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou." },
        numero: { type: "string", description: "O nº do acerto, se a pessoa disser (padrão: o último)." },
      },
      required: ["freelancer"],
    },
    risk: "medium",
    roles: CARGOS,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const f = await acharFreelancer(ctx, args.freelancer);
      if ("error" in f) return f;
      const a = await acertoDe(ctx, f, args.numero);
      if ("error" in a) return a;
      if (a.status !== "fechado") return { error: `O acerto nº ${numeroDoRecibo(a.numero)} está reaberto: feche de novo antes de mandar.` };
      const esperando = await lancamentosEsperandoSim(ctx, f);
      if (esperando) return { error: textoDoPdfEsperando(f, esperando) };
      const cad = await cadastroDoFreelancer(ctx, f);
      if (!cad.telefone) return { error: `${f.nome} não tem telefone no cadastro. Cadastre o WhatsApp dele em Financeiro › Favorecidos e peça de novo.` };
      const doc = await documentoDoRecibo(ctx, f, a);
      if ("error" in doc) return await falhaDoExtrato(doc.error);
      const primeiro = f.nome.split(" ")[0];
      doc.legenda = a.documento
        ? `Olá, ${primeiro}! Segue o recibo nº ${numeroDoRecibo(a.numero)} dos seus serviços de ${ddmm(a.de)} a ${ddmm(a.ate)}: ` +
          `o Pix de ${brl.format(a.valor_do_acerto)}${a.pagos_ate ? ` em ${ddmm(a.pagos_ate)}` : ""} quitou o total.\nConfere? Se estiver tudo certo, responda *OK*. ` +
          "A via em papel para assinar fica na oficina."
        : `Olá, ${primeiro}! Segue o recibo das suas diárias de ${ddmm(a.de)} a ${ddmm(a.ate)}: ` +
        // a conta fecha (27/10/2026): sem o saldo de antes, "2.660 − 2.673" não dava os 867 da mensagem de 24/10
        (a.saldo_anterior ? `${a.saldo_anterior > 0 ? "saldo de antes" : "adiantamento de antes"} ${brl.format(Math.abs(a.saldo_anterior))}; ` : "") +
        `${String(a.dias).replace(".", ",")} diária(s), ${brl.format(a.trabalhado)}${reembolsosNoTexto(a.reembolsos, "; ")}; vales já pagos ${brl.format(a.pago_no_periodo)}; ` +
        `a receber ${brl.format(a.valor_do_acerto)}.\nConfere? Se estiver tudo certo, responda *OK*.`;
      const envio = await mandarPdf(ctx, cad.telefone, doc, CONTEXTO_AO_FREELANCER, `recibo de diárias ao freelancer ${f.nome}`);
      if (!envio.ok) return await falhaDoExtrato(envio.motivo);
      if (envio.deduplicated) return { ok: true, deduplicated: true, aviso: `Esse recibo já foi mandado a ${f.nome} há instantes; não reenviei.` };
      // Registra o envio: é o que faz o "OK" dele (whatsapp-webhook → registrar_conferencia_do_freelancer) ter a quem se referir.
      await ctx.admin.from("acertos_diarias").update({ enviado_ao_freelancer_em: new Date().toISOString(), telefone_enviado: cad.telefone }).eq("id", a.id);
      return {
        ok: true,
        aviso: envio.modoTeste
          ? `Modo de teste do WhatsApp ligado: o recibo nº ${numeroDoRecibo(a.numero)} foi para o número de TESTE, não para ${f.nome}.`
          : `Recibo nº ${numeroDoRecibo(a.numero)} mandado a ${f.nome}. Quando ele responder OK, fica registrado no acerto e você recebe um aviso.`,
      };
    },
  },
];
