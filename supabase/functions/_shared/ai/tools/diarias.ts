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
import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { dataDita, escolherPorNome, normal, osPeloNumero } from "./caixa.ts";

const CARGOS: Role[] = ["admin", "financial"];
const brl = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const DIAS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];
const JORNADAS = ["inteiro", "meio", "faltou", "apagar"] as const;
type Jornada = typeof JORNADAS[number];
const ROTULO: Record<Jornada, string> = { inteiro: "dia inteiro", meio: "meio período", faltou: "faltou", apagar: "apagar" };
const FRACAO: Record<string, number> = { inteiro: 1, meio: 0.5, faltou: 0 };

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
  const { data } = await ctx.admin.from("work_profiles")
    .select("id, payee_id, valor_diaria, vigencia_inicio, vigencia_fim, payees(id, name, active)")
    .eq("modo_pagamento", "diaria");
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
}

/** Até 31 dias por pedido — mais que isso é engano de data, não pedido. */
const MAX_DIAS = 31;

/** Resolve o pedido como a pessoa falou. Devolve a pergunta quando há dúvida — sem gravar nada. */
export async function resolverDiaria(ctx: ToolCtx, args: Record<string, unknown>): Promise<PedidoDeDiaria | { error: string }> {
  const jornada = String(args.jornada ?? "") as Jornada;
  if (!JORNADAS.includes(jornada)) return { error: `Jornada "${args.jornada}" não existe: use inteiro, meio, faltou ou apagar.` };
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
  const observacao = typeof args.observacao === "string" && args.observacao.trim() ? args.observacao.trim() : null;
  return { freelancer: f, data, datas, intervalo, fimDeSemana, jornada, os, observacao };
}

type DiaLancado = { id: string; fracao: number; valorDia: number };

/** Os dias já lançados para a pessoa nessas datas (no máximo um por data, pelo índice do banco). */
async function diasLancados(ctx: ToolCtx, f: Freelancer, datas: string[]): Promise<Map<string, DiaLancado>> {
  const { data: linhas } = await ctx.admin.from("work_shifts")
    .select("id, data, fracao, valor_diaria, valor_dia")
    .in("work_profile_id", f.perfis.map((p) => p.id))
    .in("data", datas)
    .not("fracao", "is", null);
  return new Map(((linhas ?? []) as any[]).map((d) => [String(d.data), { id: d.id as string, fracao: Number(d.fracao), valorDia: Number(d.valor_dia) }]));
}

async function diaLancado(ctx: ToolCtx, f: Freelancer, data: string): Promise<DiaLancado | null> {
  return (await diasLancados(ctx, f, [data])).get(data) ?? null;
}

const ddmm = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

const rotuloDaFracao = (f: number) => (f === 1 ? "dia inteiro" : f === 0.5 ? "meio período" : "faltou");

/** O texto da confirmação: o pedido resolvido, e como o dia está hoje quando já existe. */
export async function resumirDiaria(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const p = await resolverDiaria(ctx, args);
  if ("error" in p) return null;
  if (p.intervalo) return await resumirIntervalo(ctx, p);
  const atual = await diaLancado(ctx, p.freelancer, p.data);
  const quem = `*${p.freelancer.nome}* · ${diaCurto(p.data)}`;
  if (p.jornada === "apagar") {
    return atual
      ? `Apagar o dia de ${quem} (${rotuloDaFracao(atual.fracao)}, ${brl.format(atual.valorDia)}). Some do saldo dele — diferente de "faltou", que registra a ausência.`
      : `Apagar o dia de ${quem} — não há dia lançado nessa data; nada vai mudar.`;
  }
  const perfil = p.freelancer.perfis.find((x) => x.vigencia_inicio <= p.data && (!x.vigencia_fim || x.vigencia_fim >= p.data));
  const valor = p.jornada === "faltou" ? 0 : (perfil?.valor_diaria ?? 0) * FRACAO[p.jornada];
  const linhas = [`Registrar diária: ${quem} · *${ROTULO[p.jornada]}*${p.jornada === "faltou" ? " (sem diária)" : ` · ${brl.format(valor)}`}` +
    (p.os.length ? ` · OS ${p.os.map((o) => o.numero).join(", ")}` : "")];
  if (p.os.length > 1) linhas.push("O valor do dia se divide em partes iguais entre as OS.");
  if (p.observacao) linhas.push(`Observação: ${p.observacao}`);
  if (atual) linhas.push(`Hoje está lançado: ${rotuloDaFracao(atual.fracao)} (${brl.format(atual.valorDia)}) — vai ser corrigido, não duplicado.`);
  else if (!perfil) linhas.push("⚠️ Sem diária cadastrada nessa data: o sistema vai recusar.");
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
  const valor = p.jornada === "faltou" ? 0 : (perfil?.valor_diaria ?? 0) * FRACAO[p.jornada];
  const linhas = [
    `Registrar diária: *${p.freelancer.nome}* · *${ROTULO[p.jornada]}* · ${novos.length} dia(s) de ${diaCurto(primeiro)} a ${diaCurto(ultimo)}` +
      (p.fimDeSemana ? "" : " (só dias úteis)") +
      (p.jornada === "faltou" ? " (sem diária)" : ` · ${brl.format(valor)} cada, ${brl.format(valor * novos.length)} no total`) +
      (p.os.length ? ` · OS ${p.os.map((o) => o.numero).join(", ")}` : ""),
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

const PERIODOS = ["tudo", "este_mes", "mes_passado"] as const;

/** De/até do período dito, em Brasília. "tudo" = desde o início da conta corrente. */
export function intervaloDito(periodo: unknown, hoje = new Date()): { de: string | null; ate: string | null } {
  const base = new Date(hoje.getTime() - 3 * 3600_000);
  const ano = base.getUTCFullYear();
  const mes = base.getUTCMonth();
  const doMes = (a: number, m: number) => {
    const ini = new Date(Date.UTC(a, m, 1));
    const fim = new Date(Date.UTC(a, m + 1, 0));
    return { de: ini.toISOString().slice(0, 10), ate: fim.toISOString().slice(0, 10) };
  };
  if (periodo === "este_mes") return doMes(ano, mes);
  if (periodo === "mes_passado") return doMes(mes === 0 ? ano - 1 : ano, mes === 0 ? 11 : mes - 1);
  return { de: null, ate: null };
}

const ESTADO: Record<string, string> = {
  deve: "você deve a ele", adiantado: "pago adiantado (ele deve dias)", quitado: "quitado", semdias: "há pagamento sem dia lançado",
};

async function saldoDito(ctx: ToolCtx, f: Freelancer): Promise<string> {
  const c = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, p_de: null, p_ate: null }) as Record<string, unknown>;
  return c && !("error" in c) ? ` Saldo com ${f.nome}: ${brl.format(Math.abs(Number(c.saldo_final) || 0))} (${ESTADO[String(c.estado)] ?? c.estado}).` : "";
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
      p_extras: null, p_descontos: null, p_valor_diaria: null, p_origem: "agente",
    }) as Record<string, unknown>;
    if (r && "error" in r) falhas.push(`${ddmm(d)}: ${r.error}`);
    else feitos.push(d);
  }
  const partes = [`${p.freelancer.nome} · ${ROTULO[p.jornada]} · ${feitos.length} dia(s) registrado(s)${feitos.length ? `: ${feitos.map(ddmm).join(", ")}` : ""}.`];
  if (mantidos.length) partes.push(`Já lançados, mantidos: ${mantidos.join(", ")}.`);
  if (falhas.length) partes.push(`Não entraram: ${falhas.join("; ")}.`);
  return { ok: falhas.length === 0, registrados: feitos, mantidos, falhas, aviso: `${partes.join(" ")}${await saldoDito(ctx, p.freelancer)}`.trim() };
}

export const diariasTools: ToolDef[] = [
  {
    name: "registrar_diaria",
    description:
      "Registra o DIA de um freelancer de diária (Roberto, Mickael): 'o Roberto não veio hoje' (faltou), 'Mickael fez meio período " +
      "ontem', 'Roberto trabalhou dia inteiro na OS 1234'. Um dia por pessoa: repetir a mesma data CORRIGE o dia, não duplica. " +
      "'faltou' grava a ausência (valor zero); 'apagar' só para dia lançado por ENGANO. A diária vem do cadastro — não pergunte " +
      "valor nem horário. Não é pagamento (pagamento vem do extrato; em dinheiro é lancar_no_caixa) nem hora de OS " +
      "(log_service_order_hours). Vários dias ('faltou desde 19/09', 'a semana toda', 'de segunda até hoje'): data + data_ate; " +
      "só dias úteis, salvo fim_de_semana; dia já lançado no intervalo fica como está. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou ('Roberto')." },
        data: { type: "string", description: "'hoje' (padrão), 'ontem', dd/mm ou dia da semana ('segunda'). Num intervalo, o primeiro dia." },
        data_ate: { type: "string", description: "Só para vários dias: o último dia ('hoje', dd/mm, 'sexta'). Nunca no futuro." },
        fim_de_semana: { type: "boolean", description: "Num intervalo, incluir sábado e domingo — só se a pessoa disser." },
        jornada: { type: "string", enum: [...JORNADAS], description: "inteiro, meio, faltou (não veio) ou apagar (lançado por engano; um dia só)." },
        os: { type: "string", description: "Número da OS em que trabalhou; duas OS separadas por vírgula (o dia se divide igual)." },
        observacao: { type: "string", description: "Serviço feito, obra, barco — se a pessoa disser." },
      },
      required: ["freelancer", "jornada"],
    },
    risk: "medium",
    roles: CARGOS,
    preValidar(args) {
      if (!JORNADAS.includes(String(args?.jornada ?? "") as Jornada)) {
        return { error: `Jornada "${args?.jornada}" não existe: use inteiro, meio, faltou ou apagar.` };
      }
      if (args?.jornada === "apagar" && args?.data_ate) return { error: "Apagar é um dia de cada vez: diga qual dia." };
      return null;
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
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
        p_extras: null, p_descontos: null, p_valor_diaria: null,
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
      "fez esse mês?', 'como está o saldo dos freelancers?'. Sem nome, mostra todos. Só consulta — não grava nada.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome; vazio = todos." },
        periodo: { type: "string", enum: [...PERIODOS], description: "tudo (padrão: saldo acumulado), este_mes, mes_passado." },
      },
    },
    risk: "low",
    roles: CARGOS,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const { de, ate } = intervaloDito(args.periodo);
      if (!args.freelancer) {
        const r = await chamar(ctx, "resumo_freelancers", { p_de: de, p_ate: ate }) as Record<string, unknown>;
        if (r && "error" in r) return r;
        const pessoas = ((r?.pessoas ?? []) as any[]).map((x) => ({
          nome: x.nome, dias: Number(x.dias), trabalhado: Number(x.trabalhado), pago: Number(x.pago),
          saldo: Number(x.saldo_final), situacao: ESTADO[x.estado] ?? x.estado, ultimo_pagamento: x.ultimo_pagamento,
        }));
        return { periodo: de ? `${de} a ${ate}` : "desde o início da conta corrente", pessoas };
      }
      const f = await acharFreelancer(ctx, args.freelancer);
      if ("error" in f) return f;
      const c = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, p_de: de, p_ate: ate }) as Record<string, any>;
      if (c && "error" in c) return c;
      const linhas = ((c?.linhas ?? []) as any[]).slice(-15).map((l) => l.tipo === "dia"
        ? { data: l.data, dia: rotuloDaFracao(Number(l.fracao)), valor: Number(l.trabalhado), os: (l.os ?? []).map((o: any) => o.numero) }
        : { data: l.data, pagamento: Number(l.pago), de_onde: l.conta });
      return {
        freelancer: f.nome,
        periodo: c.de ? `${c.de} a ${c.ate ?? "hoje"}` : "desde o início da conta corrente",
        dias: Number(c.dias), trabalhado: Number(c.trabalhado), pago: Number(c.pago),
        saldo: Number(c.saldo_final), situacao: ESTADO[c.estado] ?? c.estado,
        ultimos_lancamentos: linhas,
      };
    },
  },
];
