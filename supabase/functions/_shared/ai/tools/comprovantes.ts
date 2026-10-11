/// Comprovantes (CMP-00123) pela conversa do assistente — F2, 11/10/2026.
//
// A foto/PDF de cupom que o dono manda pelo WhatsApp é do fluxo de comprovantes (edge
// comprovantes-whatsapp): ele numera, pergunta pelo menu e grava sozinho depois do "sim". O
// assistente NÃO lança de novo o que tem CMP (regra "registrada ≠ ensinada": a tool existe, o
// prompt ensina, e as travas de caixa.ts/so-ops.ts conferem antes de gravar).
//
// Aqui moram:
// - consultar_comprovantes: só leitura (comprovantes_consultar). Só o administrador vê
//   comprovante (decisão do dono): a função do banco devolve vazio para quem não é admin.
// - conferirComprovantes e os textos das travas: o que caixa.ts e so-ops.ts usam para não
//   lançar em dobro o que um CMP já gravou (ou está para gravar). O admin vê o CMP (código, valor,
//   data); o financeiro só sabe que existe (comprovantes_ja_lancados, sem detalhe nenhum).
//
// Nada aqui grava em log valor, CNPJ, nome ou texto do documento: só códigos e erros do banco.
//
// Sem importar caixa.ts nem financeiro-comum.ts: caixa.ts importa este módulo, e financeiro-comum
// importa caixa.ts — o ciclo deixaria constante em zona morta na carga do módulo.
import type { Role, ToolCtx, ToolDef } from "./registry.ts";
import { conversaDosComprovantesLigada } from "../../comprovantes/modo.ts";

const SO_ADMIN: Role[] = ["admin"];
const brl = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
/** 'AAAA-MM-DD' → 'dd/mm'. */
const ddmm = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

/**
 * As situações de um CMP (CHECK de comprovantes). F3 (11/10/2026): gravado e esperando a linha do
 * banco (aguardando_banco), ligado a ela (conciliado) ou sem linha depois de 30 dias (45 no
 * crédito: abandonado).
 */
export const SITUACOES = [
  "lido", "falhou", "aguardando_vez", "perguntando", "aguardando_sim", "gravado", "aguardando_xml", "cancelado",
  "aguardando_banco", "conciliado", "abandonado",
];

/** Um CMP parecido com o lançamento pedido (comprovantes_parecidos). */
export interface CmpParecido {
  codigo: string;
  numero?: number | null;
  valor?: string | number | null;
  data?: string | null;
  fornecedor?: string | null;
  os_id?: string | null;
  /** Só nos gravados: o que a gravação fez (despesa_os, anotar, caixa, reembolso_socio…). */
  efeitos?: string[] | null;
}

export interface Parecidos {
  abertos: CmpParecido[];
  gravados: CmpParecido[];
}

/** Quem confere: o client service-role e QUEM PEDE (o resumo do "sim" também recebe o usuário). */
export type QuemConfere = Pick<ToolCtx, "admin"> & Partial<Pick<ToolCtx, "userId" | "userRole" | "settings">>;

/**
 * Quem consulta: sempre quem pede (ctx.userId). Sem usuário não há consulta (null) — antes o
 * resumo caía no dono e mostrava o CMP dele a quem não é admin (revisão de 11/10/2026).
 */
export function autorDaConsulta(ctx: Partial<Pick<ToolCtx, "userId">>): string | null {
  return ctx.userId ? String(ctx.userId) : null;
}

/** "AAAA-MM-DD" de hoje em Brasília (a data que o banco usa quando ninguém diz). */
function hojeBrt(agora = new Date()): string {
  return new Date(agora.getTime() - 3 * 3600_000).toISOString().slice(0, 10);
}

function listaDeCmps(v: unknown): CmpParecido[] {
  return Array.isArray(v)
    ? (v as CmpParecido[]).filter((c) => c && typeof c === "object" && typeof c.codigo === "string" && c.codigo)
    : [];
}

/** A data que vai ao banco: só 'AAAA-MM-DD'; o resto vai nulo (o banco olha os últimos 3 dias). */
const dataDoBanco = (d: string | null) => d && /^\d{4}-\d{2}-\d{2}$/.test(d) ? d : null;

/**
 * Os CMPs com o mesmo valor (±0,01) e a mesma data (±1 dia), e da mesma OS quando ela vem — com
 * código, valor e data: SÓ para o admin (a função do banco devolve vazio para os outros). Data
 * não dita vai nula: a função do banco olha então os CMPs recebidos nos últimos 3 dias ("gastei 62
 * no posto" sem dizer quando pode ser o cupom de anteontem). Os abertos só vêm com a conversa
 * ligada (no banco).
 * Melhor esforço: erro do banco (função ainda não aplicada, rede) devolve null e quem chama segue
 * como antes da F2 — a trava protege contra o dobro, não pode parar o lançamento por falha dela.
 */
export async function comprovantesParecidos(
  ctx: QuemConfere,
  p: { valor: number; data: string | null; osId: string | null },
): Promise<Parecidos | null> {
  if (!(p.valor > 0)) return null;
  const autor = autorDaConsulta(ctx);
  if (!autor) return null;
  try {
    const { data, error } = await ctx.admin.rpc("comprovantes_parecidos", {
      p_valor: Math.round(p.valor * 100) / 100,
      p_data: dataDoBanco(p.data),
      p_os: p.osId,
      p_autor: autor,
    });
    if (error) {
      console.warn(`[comprovantes] parecidos indisponível: ${String(error.code ?? error.message ?? "erro")}`);
      return null;
    }
    const d = (data ?? {}) as Record<string, unknown>;
    return { abertos: listaDeCmps(d.abertos), gravados: listaDeCmps(d.gravados) };
  } catch (e) {
    console.warn(`[comprovantes] parecidos falhou: ${e instanceof Error ? e.name : "erro"}`);
    return null;
  }
}

/**
 * A trava de quem NÃO é admin (financeiro): comprovantes_ja_lancados devolve só dois booleanos —
 * um CMP gravado com um destes efeitos, um CMP aberto do mesmo valor (só com a conversa ligada) —
 * e nunca código, valor nem fornecedor. Mesmo melhor esforço: erro = null.
 */
export async function comprovantesJaLancados(
  ctx: QuemConfere,
  p: { valor: number; data: string | null; osId: string | null; efeitos: readonly string[] },
): Promise<{ ja_lancado: boolean; aberto: boolean } | null> {
  if (!(p.valor > 0)) return null;
  const autor = autorDaConsulta(ctx);
  if (!autor) return null;
  try {
    const { data, error } = await ctx.admin.rpc("comprovantes_ja_lancados", {
      p_valor: Math.round(p.valor * 100) / 100,
      p_data: dataDoBanco(p.data),
      p_os: p.osId,
      p_efeitos: [...p.efeitos],
      p_autor: autor,
    });
    if (error) {
      console.warn(`[comprovantes] ja_lancados indisponível: ${String(error.code ?? error.message ?? "erro")}`);
      return null;
    }
    const d = (data ?? {}) as Record<string, unknown>;
    return { ja_lancado: d.ja_lancado === true, aberto: d.aberto === true };
  } catch (e) {
    console.warn(`[comprovantes] ja_lancados falhou: ${e instanceof Error ? e.name : "erro"}`);
    return null;
  }
}

/** O CMP gravado que já fez ESTE tipo de lançamento (ex.: "caixa" para lancar_no_caixa). */
export function gravadoComEfeito(p: Parecidos | null, efeitos: readonly string[]): CmpParecido | null {
  return p?.gravados.find((c) => (c.efeitos ?? []).some((e) => efeitos.includes(e))) ?? null;
}

/** O primeiro CMP ainda aberto (na fila, na pergunta ou esperando o "sim"). */
export function primeiroAberto(p: Parecidos | null): CmpParecido | null {
  return p?.abertos[0] ?? null;
}

/**
 * O que a trava viu. Gravado: para o admin vem o CMP (código, valor e data entram no texto); para
 * os outros cargos, `true` — só se sabe que existe ("só o dono vê comprovante"). Aberto: só para
 * o admin, que é quem completa o CMP (*cmp N*); ao financeiro ele não diz nada que ele possa fazer
 * e mostraria o comprovante do dono — quando o dono responder, o plano do CMP procura o
 * lançamento igual antes de criar.
 */
export interface Conferencia {
  gravado: CmpParecido | true | null;
  aberto: CmpParecido | null;
  /**
   * Só para o admin: o CMP gravado com um dos efeitos de `avisar` (não trava; quem chama diz ao dono o
   * que ele é — ex.: o custo interno da OS, que o cliente não vê).
   */
  avisado?: CmpParecido | null;
}

/**
 * A trava contra o dobro, para caixa.ts e so-ops.ts: sempre com QUEM PEDE. Sem usuário, nada
 * (nenhuma consulta). Admin → comprovantes_parecidos (com detalhe); outro cargo →
 * comprovantes_ja_lancados (só o booleano; o banco confere se é admin ou financeiro). CMP aberto
 * só conta para o admin e com a conversa ligada (conversaDosComprovantesLigada): com ela
 * desligada, ou em sombra, "responda *cmp N*" não faria nada — nada muda para o dono. Falha da
 * consulta = nada.
 */
export async function conferirComprovantes(
  ctx: QuemConfere,
  p: { valor: number; data: string | null; osId: string | null; efeitos: readonly string[]; avisar?: readonly string[] },
): Promise<Conferencia> {
  if (!autorDaConsulta(ctx) || !(p.valor > 0)) return { gravado: null, aberto: null };
  const ligada = conversaDosComprovantesLigada(ctx.settings);
  if (ctx.userRole === "admin") {
    const parecidos = await comprovantesParecidos(ctx, p);
    const gravado = gravadoComEfeito(parecidos, p.efeitos);
    return {
      gravado,
      aberto: ligada ? primeiroAberto(parecidos) : null,
      avisado: !gravado && p.avisar?.length ? gravadoComEfeito(parecidos, p.avisar) : null,
    };
  }
  const r = await comprovantesJaLancados(ctx, p);
  return { gravado: r?.ja_lancado ? true : null, aberto: null };
}

/** "R$ 62,00 em 10/10" — o que o dono reconhece do comprovante. */
function valorEData(c: CmpParecido): string {
  const valor = Number(c.valor);
  return [
    Number.isFinite(valor) && valor > 0 ? brl.format(valor) : null,
    c.data ? `em ${ddmm(c.data)}` : null,
  ].filter(Boolean).join(" ");
}

/** O número curto do comando "cmp 124". */
function numeroDoCmp(c: CmpParecido): string {
  if (c.numero != null && Number(c.numero) > 0) return String(Number(c.numero));
  const m = String(c.codigo).match(/(\d+)\s*$/);
  return m ? String(Number(m[1])) : c.codigo;
}

/**
 * Uma linha só, começando com ⚠️: no resumo do "sim" vira recusa (resumoQueRecusa, agent.ts).
 * `true` (quem pede não é o admin): sem código, valor nem data.
 */
export function textoDoJaLancado(c: CmpParecido | true): string {
  if (c === true) return "⚠️ Esse gasto já foi lançado por um comprovante do dono. Nada foi lançado de novo.";
  return `⚠️ Já lançado pelo ${c.codigo} (${valorEData(c)}). Nada foi lançado de novo.`;
}

/** Linha a mais no resumo do "sim" (só do admin): há um CMP do mesmo valor ainda sem gravar. */
export function textoDoAberto(c: CmpParecido): string {
  return `Atenção: há o ${c.codigo} aberto com ${valorEData(c)}. Se for o mesmo gasto, responda *não* e depois *cmp ${numeroDoCmp(c)}*.`;
}

/** Despesa da OS (add_service_order_expense, que executa sem "sim"): a mesma OS já tem o CMP. */
export function textoDaDespesaJaLancada(c: CmpParecido | true): string {
  if (c === true) return "Esse gasto já foi lançado nesta OS por um comprovante do dono.";
  return `Já lançado pelo ${c.codigo} (${valorEData(c)}) nesta OS.`;
}

/**
 * Despesa da OS POR CONTA DA CASA com um CMP aberto do mesmo valor: o CMP vira esse mesmo custo interno
 * quando o dono o completar — completar em vez de lançar à parte.
 */
export function textoDaDespesaComCmpAberto(c: CmpParecido): string {
  return `Há o ${c.codigo} aberto com ${valorEData(c)}; completar o CMP? Responda *cmp ${numeroDoCmp(c)}*. ` +
    "Se for outro gasto, peça de novo dizendo 'mesmo assim'.";
}

/**
 * Despesa COBRADA lançada com um CMP aberto do mesmo valor (ajustes do dono: o comprovante nunca cobra o
 * cliente): quando o dono responder *cmp N*, o CMP acha esta despesa na OS e só a comprova.
 */
export function textoDaDespesaCobradaComCmpAberto(c: CmpParecido): string {
  return `O ${c.codigo} (${valorEData(c)}) ainda está aberto: ele só comprova, não cobra o cliente. Lancei esta despesa ` +
    `para o cliente; quando você responder *cmp ${numeroDoCmp(c)}*, o comprovante comprova esta, sem lançar outra.`;
}

/**
 * Despesa COBRADA lançada numa OS onde um CMP já gravou o mesmo gasto como custo interno: o interno não
 * aparece para o cliente; a cobrada é a que ele vê, e o Lucro por OS conta a compra uma vez só.
 */
export function textoDaDespesaInternaDoCmp(c: CmpParecido): string {
  return `O ${c.codigo} (${valorEData(c)}) é só custo interno desta OS (não aparece para o cliente); lancei a despesa ` +
    "cobrada do cliente. No Lucro por OS a compra conta uma vez só.";
}

/** remove_service_order_expense numa despesa que nasceu de um CMP: só sai cancelando o comprovante. */
export function textoDaDespesaDoCmpNaoSai(codigo: string): string {
  const n = String(codigo).match(/(\d+)\s*$/);
  return `Essa despesa é o custo interno do ${codigo} (comprovante): não apago por aqui. Para tirá-la, cancele o ` +
    `comprovante: *cancelar cmp ${n ? String(Number(n[1])) : codigo} motivo*.`;
}

/** 'CMP-00124', 'cmp 124', '124' → 'CMP-00124'; null se não der para ler. */
export function codigoDoCmp(v: unknown): string | null {
  const m = String(v ?? "").trim().match(/^(?:cmp[\s-]*)?0*(\d{1,6})$/i);
  return m ? `CMP-${m[1].padStart(5, "0")}` : null;
}

/** 'hoje', 'ontem', 'dd/mm', 'dd/mm/aaaa' ou ISO → 'AAAA-MM-DD'; null se não der para ler. */
export function dataDaConsulta(v: unknown, agora = new Date()): string | null {
  const s = String(v ?? "").trim().toLowerCase();
  if (!s) return null;
  const hoje = hojeBrt(agora);
  const menos = (dias: number) => new Date(Date.parse(`${hoje}T12:00:00Z`) - dias * 86_400_000).toISOString().slice(0, 10);
  if (s === "hoje") return hoje;
  if (s === "ontem") return menos(1);
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return s;
  const br = s.match(/^(\d{1,2})\/(\d{1,2})(?:\/(\d{2}|\d{4}))?$/);
  if (!br) return null;
  const ano = br[3] ? (br[3].length === 2 ? 2000 + Number(br[3]) : Number(br[3])) : Number(hoje.slice(0, 4));
  return `${ano}-${br[2].padStart(2, "0")}-${br[1].padStart(2, "0")}`;
}

export const comprovanteTools: ToolDef[] = [
  {
    name: "consultar_comprovantes",
    description:
      "Consulta os comprovantes (CMP-00123) que o dono mandou pelo WhatsApp — foto/PDF de cupom, nota ou Pix — e o que o " +
      "sistema de comprovantes fez com cada um: 'o CMP-00124 foi gravado?', 'quais comprovantes estão em aberto?', 'tem " +
      "comprovante de 62 reais de ontem?', 'os comprovantes da OS X'. Traz situação, valor, data, fornecedor, destino (OS, " +
      "estoque, insumo, empresa, pessoal), na OS se foi peça ou despesa (tipo_na_os: a despesa é custo interno, nunca aparece " +
      "para o cliente nem muda o total da OS; a peça só comprova a peça lançada na OS), quem pagou, a forma, as pendências e a " +
      "pasta no Dropbox. PESSOAL pago pela empresa é gasto pessoal do sócio (descontado do pró-labore). Só leitura; não grava " +
      "nem completa comprovante (quem completa é o dono, respondendo *cmp N*). Se vier error, diga que a consulta falhou — não " +
      "que não há comprovante.",
    input_schema: {
      type: "object",
      properties: {
        codigo: { type: "string", description: "Código do comprovante: 'CMP-00124' ou 'cmp 124'." },
        numero: { type: "number", description: "Número do comprovante (124 = CMP-00124)." },
        situacao: {
          type: "string",
          enum: SITUACOES,
          description: "lido/falhou = ainda não conferido; aguardando_vez/perguntando/aguardando_sim = na conversa com o dono; " +
            "gravado; aguardando_xml = esperando a nota entrar; cancelado. Gravados que pagaram pelo banco ou cartão da empresa: " +
            "aguardando_banco = esperando a linha aparecer no extrato (o sistema pergunta ao dono 'apareceu no extrato, ligo?'; " +
            "depois de 5 dias sem aparecer em nenhuma conta da empresa, pergunta 'quem pagou?'); conciliado = ligado à linha do " +
            "extrato e lançado (aprovado no sim do dono); abandonado = a linha não apareceu em 30 dias (45 no crédito): " +
            "classificar no Extrato.",
        },
        desde: { type: "string", description: "Data inicial: 'hoje', 'ontem', dd/mm ou AAAA-MM-DD." },
        ate: { type: "string", description: "Data final: 'hoje', 'ontem', dd/mm ou AAAA-MM-DD." },
        os_id: { type: "string", description: "UUID da OS (os comprovantes ligados a ela)." },
        valor: { type: "number", description: "Valor em reais (acha o comprovante desse valor)." },
      },
    },
    risk: "low",
    roles: SO_ADMIN,
    async execute(args, ctx) {
      if (ctx.userRole !== "admin") return { error: "Comprovantes: só o administrador consulta." };
      const filtros: Record<string, unknown> = { autor: ctx.userId || null };
      if (args.codigo != null && args.codigo !== "") {
        const codigo = codigoDoCmp(args.codigo);
        if (!codigo) return { error: `Não entendi o código "${String(args.codigo)}". Use CMP-00124 ou só o número.` };
        filtros.codigo = codigo;
      }
      if (args.numero != null && args.numero !== "") {
        const numero = Number(args.numero);
        if (!(Number.isInteger(numero) && numero > 0)) return { error: "Número do comprovante inválido." };
        filtros.numero = numero;
      }
      if (args.situacao) {
        if (!SITUACOES.includes(String(args.situacao))) return { error: `Situação desconhecida. Use: ${SITUACOES.join(", ")}.` };
        filtros.situacao = String(args.situacao);
      }
      for (const campo of ["desde", "ate"] as const) {
        if (args[campo] == null || args[campo] === "") continue;
        const d = dataDaConsulta(args[campo]);
        if (!d) return { error: `Não entendi a data "${String(args[campo])}". Use dd/mm, 'ontem' ou AAAA-MM-DD.` };
        filtros[campo] = d;
      }
      if (args.os_id) filtros.os_id = String(args.os_id);
      if (args.valor != null && args.valor !== "") {
        const valor = Number(String(args.valor).replace(",", "."));
        if (!(valor > 0)) return { error: "Valor inválido." };
        filtros.valor = Math.round(valor * 100) / 100;
      }
      // comprovantes_consultar: só leitura; quem não é admin recebe vazio (nunca erro).
      const { data, error } = await ctx.sb.rpc("comprovantes_consultar", { p: filtros });
      // Leitura que falha não vira "nenhum comprovante" (02/10/2026).
      if (error) {
        return { error: `Não consegui consultar os comprovantes (${String(error.message ?? "erro do banco")}). Diga que a consulta falhou — não que não há comprovante.` };
      }
      return data ?? { itens: [], total: 0 };
    },
  },
];
