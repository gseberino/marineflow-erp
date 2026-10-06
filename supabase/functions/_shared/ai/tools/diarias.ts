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
import { montarExtratoHtml, montarReciboHtml, nomeDoArquivo, numeroDoRecibo, type ContaDoExtrato } from "../../diarias/extrato.ts";

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
  // Valor do dia só vale para quem trabalhou; numa falta (ou ao apagar) não há o que valer.
  let valorDiaria: number | null = null;
  if (args.valor_diaria != null && args.valor_diaria !== "" && jornada !== "faltou" && jornada !== "apagar") {
    valorDiaria = numeroDito(args.valor_diaria);
    if (valorDiaria == null || valorDiaria <= 0) return { error: `Não entendi o valor do dia: "${args.valor_diaria}".` };
  }
  return { freelancer: f, data, datas, intervalo, fimDeSemana, jornada, os, observacao, valorDiaria };
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

/** Valor dito diferente do cadastro: a confirmação deixa claro que não é a diária de sempre. */
function linhaDoValorDito(p: PedidoDeDiaria, perfil: Perfil | undefined): string[] {
  if (p.valorDiaria == null || !perfil || perfil.valor_diaria === p.valorDiaria) return [];
  return [`Diária ${p.intervalo ? "desses dias" : "desse dia"}: ${brl.format(p.valorDiaria)} (a do cadastro é ${brl.format(perfil.valor_diaria ?? 0)}).`];
}

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
  const valor = p.jornada === "faltou" ? 0 : (p.valorDiaria ?? perfil?.valor_diaria ?? 0) * FRACAO[p.jornada];
  const linhas = [`Registrar diária: ${quem} · *${ROTULO[p.jornada]}*${p.jornada === "faltou" ? " (sem diária)" : ` · ${brl.format(valor)}`}` +
    (p.os.length ? ` · OS ${p.os.map((o) => o.numero).join(", ")}` : "")];
  linhas.push(...linhaDoValorDito(p, perfil));
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
  const valor = p.jornada === "faltou" ? 0 : (p.valorDiaria ?? perfil?.valor_diaria ?? 0) * FRACAO[p.jornada];
  const linhas = [
    `Registrar diária: *${p.freelancer.nome}* · *${ROTULO[p.jornada]}* · ${novos.length} dia(s) de ${diaCurto(primeiro)} a ${diaCurto(ultimo)}` +
      (p.fimDeSemana ? "" : " (só dias úteis)") +
      (p.jornada === "faltou" ? " (sem diária)" : ` · ${brl.format(valor)} cada, ${brl.format(valor * novos.length)} no total`) +
      (p.os.length ? ` · OS ${p.os.map((o) => o.numero).join(", ")}` : ""),
    ...linhaDoValorDito(p, perfil),
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
      p_extras: null, p_descontos: null, p_valor_diaria: p.valorDiaria, p_origem: "agente",
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
const ROTULO_DA_FORMA: Record<Forma, string> = { pix: "Pix", dinheiro: "dinheiro do Caixa", bolso_do_socio: "do bolso do sócio" };
const CATEGORIA_DIARIAS = "Diárias de freelancers";

export interface PedidoDePagamento {
  freelancer: Freelancer;
  valor: number;
  forma: Forma;
  /** A data dita; nula = hoje (no Pix, sem data exata a anotação espera alguns dias de folga). */
  data: string | null;
  socio: { id: string; nome: string } | null;
  observacao: string | null;
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
  return { freelancer: f, valor: Math.round(valor * 100) / 100, forma, data, socio, observacao };
}

const descricaoDoPagamento = (p: PedidoDePagamento) =>
  p.observacao ?? `Pagamento de diárias — ${p.freelancer.nome.split(" ")[0]}`;

/** A confirmação: quem, quanto, como, quando — e o saldo com ele antes e depois. */
export async function resumirPagamento(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const p = await resolverPagamento(ctx, args);
  if ("error" in p) return null;
  const quando = diaCurto(p.data ?? dataDita("hoje")!);
  const linhas = [`Pagamento a *${p.freelancer.nome}*: *${brl.format(p.valor)}* ${p.forma === "pix" ? "por Pix" : `em ${ROTULO_DA_FORMA[p.forma]}`} · ${quando}` +
    (p.socio ? ` · pago por ${p.socio.nome} (fica como reembolso a ele)` : "")];
  linhas.push(`Descrição: ${descricaoDoPagamento(p)} · ${CATEGORIA_DIARIAS}`);
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

async function registrarPagamento(ctx: ToolCtx, p: PedidoDePagamento) {
  const desc = descricaoDoPagamento(p);
  if (p.forma === "pix") {
    return await chamar(ctx, "anotar_transacao", {
      p_sentido: "saida", p_valor: p.valor, p_data: p.data, p_documento: null, p_nome: null,
      p_fornecedor_id: null, p_favorecido_id: p.freelancer.id, p_cliente_id: null,
      p_categoria: CATEGORIA_DIARIAS, p_os_id: null, p_descricao: desc,
    }) as Record<string, unknown>;
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

type Acerto = { id: string; numero: number; de: string; ate: string; saldo_anterior: number; dias: number; trabalhado: number;
  pago_no_periodo: number; valor_do_acerto: number; status: string };

/** O acerto pedido (pelo número) ou o último fechado da pessoa. */
async function acertoDe(ctx: ToolCtx, f: Freelancer, numero?: unknown): Promise<Acerto | { error: string }> {
  let q = ctx.admin.from("acertos_diarias")
    .select("id, numero, de, ate, saldo_anterior, dias, trabalhado, pago_no_periodo, valor_do_acerto, status")
    .eq("favorecido_id", f.id);
  const n = numero == null || numero === "" ? null : Number(String(numero).replace(/\D/g, ""));
  q = n ? q.eq("numero", n) : q.eq("status", "fechado").order("ate", { ascending: false }).limit(1);
  const { data, error } = await q;
  if (error) return { error: `Falha ao ler os acertos: ${error.message}` };
  const a = (data ?? [])[0] as any;
  if (!a) return { error: n ? `Não achei o acerto nº ${n} de ${f.nome}.` : `${f.nome} ainda não tem acerto fechado. Feche com fechar_acerto_freelancer.` };
  return { ...a, saldo_anterior: Number(a.saldo_anterior), dias: Number(a.dias), trabalhado: Number(a.trabalhado),
    pago_no_periodo: Number(a.pago_no_periodo), valor_do_acerto: Number(a.valor_do_acerto) };
}

/** O recibo do acerto: totais da foto; linhas (dias e vales) da conta corrente do mesmo período. */
async function documentoDoRecibo(ctx: ToolCtx, f: Freelancer, a: Acerto): Promise<DocumentoPronto | { error: string }> {
  const conta = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, p_de: a.de, p_ate: a.ate }) as Record<string, any>;
  if (conta && "error" in conta) return { error: String(conta.error) };
  const cad = await cadastroDoFreelancer(ctx, f);
  const n = numeroDoRecibo(a.numero);
  return {
    html: montarReciboHtml({ empresa: empresaDosSettings(ctx.settings), freelancer: cad, acerto: a, linhas: conta.linhas ?? [], geradoEm: new Date() }),
    arquivo: limitarNomeDoArquivo(nomeDoArquivo(`recibo-diarias-${n}`, f.nome, { de: a.de, ate: a.ate }, "pdf")),
    legenda: `🧾 Recibo de diárias nº ${n} — ${f.nome}\nPeríodo: ${ddmm(a.de)} a ${ddmm(a.ate)}\n` +
      `Trabalhado ${brl.format(a.trabalhado)} · vales ${brl.format(a.pago_no_periodo)} · a pagar ${brl.format(a.valor_do_acerto)}` +
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

/** A confirmação do acerto: a função do banco simulando — período, dias, vales, a pagar. */
export async function resumirAcerto(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const f = await acharFreelancer(ctx, args.freelancer);
  if ("error" in f) return null;
  const ate = args.ate ? dataDoDito(args.ate) : null;
  const { data, error } = await ctx.admin.rpc("fechar_acerto_diarias", { p_favorecido_id: f.id, p_ate: ate, p_simular: true, p_autor: null });
  if (error) return `Fechar acerto de *${f.nome}*\n⚠️ ${semCodigo(error.message)} — o sistema vai recusar.`;
  const s = data as Record<string, any>;
  const linhas = [`Fechar acerto de *${f.nome}*: ${ddmm(s.de)} a ${ddmm(s.ate)}`,
    `${String(s.dias).replace(".", ",")} diária(s) = ${brl.format(Number(s.trabalhado))}` +
      (Number(s.saldo_anterior) ? ` · saldo anterior ${brl.format(Number(s.saldo_anterior))}` : "") +
      ` · vales já pagos ${brl.format(Number(s.pago_no_periodo))}`,
    `*A pagar neste acerto: ${brl.format(Number(s.valor_do_acerto))}*`,
    `Os dias até ${ddmm(s.ate)} ficam travados (reabrir só pela tela ou pedindo, com motivo).`];
  if (Number(s.pago_aguardando_banco) > 0) linhas.push(`⚠️ ${brl.format(Number(s.pago_aguardando_banco))} dos vales são Pix lançados à mão que o banco ainda não confirmou.`);
  return linhas.join("\n");
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
      "Registra o DIA de um freelancer de diária já cadastrado: 'o Roberto não veio hoje' (faltou), 'Mickael fez meio período " +
      "ontem', 'Roberto trabalhou dia inteiro na OS 1234'. Um dia por pessoa: repetir a mesma data CORRIGE o dia, não duplica. " +
      "'faltou' grava a ausência (valor zero); 'apagar' só para dia lançado por ENGANO. A diária vem do cadastro — não pergunte " +
      "valor nem horário; valor_diaria só quando a pessoa DISSER outro valor para o dia ('na quarta foram 130'). Freelancer que " +
      "ainda não existe: cadastrar_freelancer antes. Não é pagamento (pagamento vem do extrato; em dinheiro é lancar_no_caixa) nem hora de OS " +
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
        valor_diaria: { type: "number", description: "Só se a pessoa DISSER o valor do dia, diferente do cadastro (em reais). Sem isso vale a diária do cadastro." },
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
        p_extras: null, p_descontos: null, p_valor_diaria: p.valorDiaria,
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
      "(de/ate). Sem nome, mostra todos. Só consulta — não grava nada. Para o PDF do extrato, enviar_extrato_freelancer.",
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
          nome: x.nome, periodo: periodoResolvido(x), dias: Number(x.dias), trabalhado: Number(x.trabalhado), pago: Number(x.pago),
          ...(Number(x.pago_aguardando_banco) > 0 ? { pago_lancado_a_mao_aguardando_banco: Number(x.pago_aguardando_banco) } : {}),
          saldo: Number(x.saldo_final), situacao: ESTADO[x.estado] ?? x.estado, ultimo_pagamento: x.ultimo_pagamento,
        }));
        return { pessoas };
      }
      const f = await acharFreelancer(ctx, args.freelancer);
      if ("error" in f) return f;
      const c = await chamar(ctx, "conta_corrente_freelancer", { p_favorecido_id: f.id, ...periodo }) as Record<string, any>;
      if (c && "error" in c) return c;
      const linhas = ((c?.linhas ?? []) as any[]).slice(-15).map((l) => l.tipo === "dia"
        ? { data: l.data, dia: rotuloDaFracao(Number(l.fracao)), valor: Number(l.trabalhado), os: (l.os ?? []).map((o: any) => o.numero) }
        : { data: l.data, pagamento: Number(l.pago), de_onde: l.aguardando ? "lançado à mão, aguardando o banco" : l.conta });
      return {
        freelancer: f.nome,
        periodo: periodoResolvido(c),
        saldo_antes_do_periodo: Number(c.saldo_anterior),
        dias: Number(c.dias), trabalhado: Number(c.trabalhado), pago: Number(c.pago),
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
      "aparece no extrato de diárias), dinheiro (sai do Caixa) ou bolso_do_socio (vira reembolso ao sócio). Não é o dia trabalhado " +
      "(registrar_diaria). Valor e forma são obrigatórios: se faltar, PERGUNTE. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou." },
        valor: { type: "number", description: "Valor pago, em reais." },
        forma: { type: "string", enum: [...FORMAS], description: "pix, dinheiro ou bolso_do_socio." },
        data: { type: "string", description: "Quando pagou: 'hoje' (padrão), 'ontem', dd/mm, dia da semana." },
        socio: { type: "string", description: "Só no bolso_do_socio, se a pessoa disser qual (padrão: quem está falando)." },
        observacao: { type: "string", description: "Ex.: 'adiantamento', 'acerto da quinzena'." },
      },
      required: ["freelancer", "valor", "forma"],
    },
    risk: "medium",
    roles: CARGOS,
    preValidar(args) {
      if (!FORMAS.includes(String(args?.forma ?? "") as Forma)) return { error: "Como foi pago? pix, dinheiro ou bolso_do_socio." };
      const v = numeroDito(args?.valor);
      if (v == null || v <= 0) return { error: "Qual o valor pago? (não invente: pergunte)" };
      return null;
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
      "FECHA o acerto de um freelancer ao pagar: 'fecha o acerto do Roberto', 'acerta a quinzena do João até sexta'. Do dia seguinte " +
      "ao último acerto até 'ate' (padrão hoje): guarda a foto (dias, vales já pagos, a pagar), gera o recibo numerado e TRAVA os dias " +
      "até essa data. Não registra o pagamento do acerto (isso é registrar_pagamento_freelancer, ou vem do banco). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        freelancer: { type: "string", description: "Nome como a pessoa falou." },
        ate: { type: "string", description: "Até que dia fechar: 'hoje' (padrão), 'sexta', dd/mm." },
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
        aviso: `${String(r?.message ?? "Acerto fechado.")} O recibo sai com enviar_extrato_freelancer (documento=recibo) ou vai a ele com enviar_acerto_ao_freelancer.` };
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
      const cad = await cadastroDoFreelancer(ctx, f);
      if (!cad.telefone) return { error: `${f.nome} não tem telefone no cadastro. Cadastre o WhatsApp dele em Financeiro › Favorecidos e peça de novo.` };
      const doc = await documentoDoRecibo(ctx, f, a);
      if ("error" in doc) return await falhaDoExtrato(doc.error);
      const primeiro = f.nome.split(" ")[0];
      doc.legenda = `Olá, ${primeiro}! Segue o recibo das suas diárias de ${ddmm(a.de)} a ${ddmm(a.ate)}: ` +
        `${String(a.dias).replace(".", ",")} diária(s), ${brl.format(a.trabalhado)}; vales já pagos ${brl.format(a.pago_no_periodo)}; ` +
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
