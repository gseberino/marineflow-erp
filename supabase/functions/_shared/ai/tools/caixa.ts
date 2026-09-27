// O assessor financeiro pela conversa: gasto em dinheiro, saque, contagem do caixa,
// anotação antecipada e "quanto gastei com…".
//
// "gastei 50 reais em dinheiro com almoço", "paguei 100 em dinheiro pro Roberto", "fiz um
// Pix de 1.500 pro CNPJ X, classifica como fornecedor TSD". Princípio do dono: a IA pensa e
// chama a função; quem preenche é o sistema. Por isso os argumentos aqui são como a pessoa
// fala — nomes, número da OS, "dinheiro" ou "do meu bolso" — e este módulo resolve cada um
// para o cadastro (ou devolve a pergunta certa quando há dúvida). Data, status, saldo, linha
// do Caixa e trilha ficam com as funções do banco.
//
// Tudo que grava pede confirmação (decisão do dono: no começo, sempre). A confirmação mostra
// o pedido JÁ RESOLVIDO — categoria, quem, conta — para o "sim" ser sobre o que vai
// acontecer de fato (resumirPedido, usado pelo agente).
import { blockTechnician, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { categoriaPeloTexto, type RegraFinanceira } from "../../banking/proposals.ts";

const CARGOS_FINANCEIRO: Role[] = ["admin", "financial"];
const brl = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

function semAcesso(ctx: ToolCtx): { error: string } | null {
  const b = blockTechnician(ctx);
  if (b) return b;
  if (!CARGOS_FINANCEIRO.includes(ctx.userRole as Role)) return { error: "Apenas administrador ou financeiro." };
  return null;
}

/** Sem acento, minúsculo, sem pontuação — como se compara nome dito com nome cadastrado. */
export function normal(s: unknown): string {
  return String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
    .replace(/[^a-z0-9 ]/g, " ").replace(/\s+/g, " ").trim();
}

/**
 * O cadastro que o nome dito aponta: igual primeiro; senão, todas as palavras ditas no
 * nome cadastrado ("roberto" acha "Roberto Carlos da Silva"). Mais de um = pergunta.
 */
export function escolherPorNome<T extends { id: string; nome: string }>(
  dito: string, lista: T[],
): { achado: T } | { ambiguo: T[] } | { nenhum: true } {
  const d = normal(dito);
  if (!d) return { nenhum: true };
  const iguais = lista.filter((x) => normal(x.nome) === d);
  if (iguais.length === 1) return { achado: iguais[0] };
  if (iguais.length > 1) return { ambiguo: iguais };
  const palavras = d.split(" ").filter((p) => p.length >= 2);
  const contem = lista.filter((x) => {
    const n = ` ${normal(x.nome)} `;
    return palavras.every((p) => n.includes(` ${p} `) || n.includes(` ${p}`));
  });
  if (contem.length === 1) return { achado: contem[0] };
  if (contem.length > 1) return { ambiguo: contem.slice(0, 5) };
  return { nenhum: true };
}

type Pessoa = {
  id: string; nome: string; tipo: "favorecido" | "fornecedor" | "cliente"; categoria?: string | null; kind?: string;
  /** CPF/CNPJ do cadastro, se houver. */
  documento?: string | null;
};

async function listaDePessoas(ctx: ToolCtx): Promise<Pessoa[]> {
  const [fav, forn, cli] = await Promise.all([
    ctx.admin.from("payees").select("id, name, default_category, kind, document").eq("active", true).limit(1000),
    ctx.admin.from("suppliers").select("id, name, trade_name, cnpj_cpf").limit(3000),
    ctx.admin.from("clients").select("id, name, cpf_cnpj").limit(3000),
  ]);
  return [
    ...((fav.data ?? []) as any[]).map((p) => ({
      id: p.id, nome: p.name, tipo: "favorecido" as const, categoria: p.default_category, kind: p.kind, documento: p.document ?? null,
    })),
    ...((forn.data ?? []) as any[]).flatMap((s) => [
      { id: s.id, nome: s.name, tipo: "fornecedor" as const, documento: s.cnpj_cpf ?? null },
      ...(s.trade_name ? [{ id: s.id, nome: s.trade_name, tipo: "fornecedor" as const, documento: s.cnpj_cpf ?? null }] : []),
    ]),
    ...((cli.data ?? []) as any[]).map((c) => ({ id: c.id, nome: c.name, tipo: "cliente" as const, documento: c.cpf_cnpj ?? null })),
  ];
}

/** Só os dígitos, com o zero à esquerda que planilha costuma comer (como _doc_normalizado). */
function docNormalizado(p: unknown): string {
  const d = String(p ?? "").replace(/\D/g, "");
  return d.length === 13 ? d.padStart(14, "0") : d.length === 10 ? d.padStart(11, "0") : d;
}

/**
 * Os dois documentos existem e NÃO são da mesma pessoa/empresa: CPF diferente, ou CNPJ de outra
 * raiz (filial é a mesma empresa). O mesmo que _documento_contradiz no banco.
 */
export function documentoContradiz(a: unknown, b: unknown): boolean {
  const x = docNormalizado(a);
  const y = docNormalizado(b);
  if (x.length < 11 || y.length < 11) return false;
  if (x.length !== y.length) return true;
  if (x.length === 14) return x.slice(0, 8) !== y.slice(0, 8);
  return x !== y;
}

const docFormatado = (d: unknown) => {
  const x = docNormalizado(d);
  return x.length === 14 ? x.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5")
    : x.length === 11 ? x.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4") : String(d ?? "");
};

/**
 * Nome e CPF/CNPJ ditos juntos têm de ser da mesma pessoa. O documento dito vale no lugar do
 * cadastro na identidade da anotação — com o nome de um e o documento de outro, o Pix da loja
 * entraria como do Roberto: nome e documento diferentes (regra P1 do dono; revisão de 27/09/2026).
 * Contradiz → pergunta. Cadastro sem documento → não dá para conferir: a confirmação diz.
 */
function conferirDocumentoDoCadastro(pessoa: Pessoa, documento: unknown): { error: string } | { semDocumentoNoCadastro: boolean } {
  if (!documento) return { semDocumentoNoCadastro: false };
  if (documentoContradiz(documento, pessoa.documento)) {
    return {
      error: `O documento ${docFormatado(documento)} não é o de ${pessoa.nome} (no cadastro: ${docFormatado(pessoa.documento)}). ` +
        `Qual dos dois vale? Para ${pessoa.nome}, anote sem o documento; para o documento, sem o nome.`,
    };
  }
  return { semDocumentoNoCadastro: docNormalizado(pessoa.documento).length < 11 };
}

/** CPF/CNPJ dito → as duas formas que os cadastros guardam: só os dígitos e a máscara padrão. */
export function formasDoDocumento(documento: unknown): string[] | null {
  const d = String(documento ?? "").replace(/\D/g, "");
  if (d.length === 14) return [d, d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5")];
  if (d.length === 11) return [d, d.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4")];
  return null;
}

/**
 * O cadastro deste CPF/CNPJ, quando ninguém disse o nome: documento igual identifica (regra do
 * dono). É o que faz o comprovante de Pix ou boleto mandado por foto achar o fornecedor sem
 * depender de o nome do comprovante bater com o do cadastro. Saída procura fornecedor e
 * favorecido; entrada, cliente. Mais de um é pergunta.
 */
async function pessoaPeloDocumento(ctx: ToolCtx, documento: unknown, sentido: "saida" | "entrada"):
  Promise<{ achado: Pessoa } | { ambiguo: Pessoa[] } | { nenhum: true } | { error: string } | null> {
  const formas = formasDoDocumento(documento);
  if (!formas) return null;
  const falhou = { error: "Não consegui consultar os cadastros agora. Tente de novo em instantes." };
  if (sentido === "entrada") {
    const { data, error } = await ctx.admin.from("clients").select("id, name").in("cpf_cnpj", formas).limit(5);
    if (error) return falhou;
    const achados = ((data ?? []) as any[]).map((c) => ({ id: c.id, nome: c.name, tipo: "cliente" as const }));
    return achados.length === 1 ? { achado: achados[0] } : achados.length ? { ambiguo: achados } : { nenhum: true };
  }
  const [forn, fav] = await Promise.all([
    ctx.admin.from("suppliers").select("id, name").in("cnpj_cpf", formas).limit(5),
    ctx.admin.from("payees").select("id, name, default_category, kind").eq("active", true).in("document", formas).limit(5),
  ]);
  if (forn.error || fav.error) return falhou;
  const achados: Pessoa[] = [
    ...((forn.data ?? []) as any[]).map((s) => ({ id: s.id, nome: s.name, tipo: "fornecedor" as const })),
    ...((fav.data ?? []) as any[]).map((p) => ({ id: p.id, nome: p.name, tipo: "favorecido" as const, categoria: p.default_category, kind: p.kind })),
  ];
  return achados.length === 1 ? { achado: achados[0] } : achados.length ? { ambiguo: achados } : { nenhum: true };
}

const listaDeCadastros = (ps: Pessoa[]) => ps.map((x) => `${x.nome} (${x.tipo})`).join("; ");

async function categoriaValida(ctx: ToolCtx, dita: unknown, tipo: "payable" | "receivable"): Promise<{ nome: string } | { error: string } | null> {
  if (dita == null || dita === "") return null;
  const { data } = await ctx.admin.from("financial_categories").select("name").eq("type", tipo).eq("active", true);
  const nomes = ((data ?? []) as { name: string }[]).map((c) => c.name);
  const d = normal(dita);
  const exata = nomes.find((n) => normal(n) === d);
  if (exata) return { nome: exata };
  const parciais = nomes.filter((n) => normal(n).includes(d) || d.includes(normal(n)));
  if (parciais.length === 1) return { nome: parciais[0] };
  return { error: `Categoria "${dita}" não existe${parciais.length ? `; parecidas: ${parciais.join(", ")}` : ""}. Veja listar_categorias_financeiras.` };
}

/**
 * Categoria que o texto indica ("almoço" → Alimentação de campo): as regras de texto do dono e
 * a lista do Extrato — a mesma leitura que a tela do Caixa faz. Só devolve categoria que
 * existe no plano de contas.
 */
async function categoriaDoTexto(ctx: ToolCtx, texto: string, valor: number): Promise<{ nome: string; motivo: string } | null> {
  const { data } = await ctx.admin.from("finance_rules")
    .select("id, match_type, match_value, direction, set_category, set_dre_group, autonomy, status, min_amount, max_amount")
    .eq("status", "active").eq("match_type", "text").limit(500);
  const d = categoriaPeloTexto(texto, (data ?? []) as unknown as RegraFinanceira[], valor);
  if (!d) return null;
  const valida = await categoriaValida(ctx, d.categoria, "payable");
  return valida && "nome" in valida ? { nome: valida.nome, motivo: d.motivo } : null;
}

async function osPeloNumero(ctx: ToolCtx, numero: unknown): Promise<{ id: string; numero: string } | { error: string } | null> {
  if (!numero) return null;
  const n = String(numero).replace(/\D/g, "");
  if (!n) return { error: `Não entendi a OS "${numero}".` };
  const { data } = await ctx.admin.from("service_orders").select("id, service_order_number")
    .ilike("service_order_number", `%${n.padStart(5, "0")}%`).limit(3);
  const lista = (data ?? []) as { id: string; service_order_number: string }[];
  if (lista.length === 1) return { id: lista[0].id, numero: lista[0].service_order_number };
  return { error: lista.length ? `Mais de uma OS com ${numero}: ${lista.map((o) => o.service_order_number).join(", ")}` : `OS ${numero} não encontrada.` };
}

/** "hoje", "ontem", "25/09", "2026-09-25" → ISO; vazio = hoje (o banco decide o fuso). */
export function dataDita(d: unknown, hoje = new Date()): string | null {
  if (d == null || d === "") return null;
  const s = normal(d);
  const base = new Date(hoje.getTime() - 3 * 3600_000); // Brasília
  const iso = (x: Date) => x.toISOString().slice(0, 10);
  if (s === "hoje") return iso(base);
  if (s === "ontem") return iso(new Date(base.getTime() - 86_400_000));
  if (s === "anteontem") return iso(new Date(base.getTime() - 2 * 86_400_000));
  const br = String(d).match(/^(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?$/);
  if (br) {
    const ano = br[3] ? (br[3].length === 2 ? 2000 + Number(br[3]) : Number(br[3])) : base.getUTCFullYear();
    return `${ano}-${br[2].padStart(2, "0")}-${br[1].padStart(2, "0")}`;
  }
  if (/^\d{4}-\d{2}-\d{2}$/.test(String(d))) return String(d);
  return null;
}

export interface PedidoResolvido {
  sentido: "gasto" | "recebimento" | "saque" | "deposito";
  valor: number;
  descricao: string;
  data: string | null;
  categoria: string | null;
  /** De onde veio a categoria, quando ninguém a disse ("padrão de Fulano", "“almoço” no texto"). */
  origemDaCategoria: string | null;
  pessoa: Pessoa | null;
  os: { id: string; numero: string } | null;
  pagoPor: "caixa" | "socio";
  socio: Pessoa | null;
}

/** Resolve o pedido de caixa como a pessoa falou. Devolve a pergunta quando há dúvida. */
export async function resolverPedidoDeCaixa(ctx: ToolCtx, args: Record<string, unknown>): Promise<PedidoResolvido | { error: string }> {
  const sentido = String(args.sentido ?? "gasto") as PedidoResolvido["sentido"];
  if (!["gasto", "recebimento", "saque", "deposito"].includes(sentido)) return { error: "Sentido: gasto, recebimento, saque ou deposito." };
  const valor = Number(String(args.valor ?? "").replace(",", "."));
  if (!(valor > 0)) return { error: "Qual o valor?" };
  const data = dataDita(args.data);
  if (args.data && !data) return { error: `Não entendi a data "${args.data}". Use dd/mm ou 'ontem'.` };

  if (sentido === "saque" || sentido === "deposito") {
    return { sentido, valor, descricao: sentido === "saque" ? "Saque do banco para o Caixa" : "Depósito do Caixa no banco",
      data, categoria: null, origemDaCategoria: null, pessoa: null, os: null, pagoPor: "caixa", socio: null };
  }

  const descricao = String(args.descricao ?? "").trim();
  if (!descricao) return { error: "O que foi? (ex.: almoço da equipe)" };

  const pessoas = args.quem || args.socio ? await listaDePessoas(ctx) : [];
  let pessoa: Pessoa | null = null;
  if (args.quem) {
    const alvo = sentido === "recebimento" ? pessoas.filter((p) => p.tipo === "cliente") : pessoas.filter((p) => p.tipo !== "cliente");
    const r = escolherPorNome(String(args.quem), alvo);
    if ("ambiguo" in r) return { error: `Qual "${args.quem}"? ${r.ambiguo.map((p) => `${p.nome} (${p.tipo})`).join("; ")}` };
    if ("nenhum" in r) {
      return { error: sentido === "recebimento"
        ? `Não achei o cliente "${args.quem}". Cadastre o cliente ou diga o nome como está no cadastro.`
        : `Não achei "${args.quem}" entre favorecidos e fornecedores. Posso lançar sem ninguém, ou cadastre antes (cadastrar_favorecido).` };
    }
    pessoa = r.achado;
  }
  if (sentido === "recebimento" && !pessoa) return { error: "Dinheiro que entra precisa de cliente: de quem veio?" };

  const pagoPor = args.pago_por === "bolso_do_socio" ? "socio" : "caixa";
  let socio: Pessoa | null = null;
  if (pagoPor === "socio") {
    const socios = pessoas.length ? pessoas : await listaDePessoas(ctx);
    const soSocios = socios.filter((p) => p.tipo === "favorecido" && p.kind === "socio");
    if (args.socio) {
      const r = escolherPorNome(String(args.socio), soSocios);
      if (!("achado" in r)) return { error: `Qual sócio? ${soSocios.map((s) => s.nome).join(", ") || "nenhum sócio cadastrado como favorecido"}` };
      socio = r.achado;
    } else if (soSocios.length === 1) socio = soSocios[0];
    else return { error: `Qual sócio pagou? ${soSocios.map((s) => s.nome).join(", ") || "Cadastre o sócio como favorecido (tipo sócio)."}` };
  }

  const cat = await categoriaValida(ctx, args.categoria, sentido === "recebimento" ? "receivable" : "payable");
  if (cat && "error" in cat) return cat;
  const os = await osPeloNumero(ctx, args.os);
  if (os && "error" in os) return os;

  // Ninguém disse a categoria: a padrão de quem recebeu; sem ela, o que o texto indica
  // ("almoço" → Alimentação de campo). Antes caía direto em "Outras despesas" (teste do
  // dono, 25/09/2026).
  let categoria = cat?.nome ?? null;
  let origemDaCategoria: string | null = null;
  if (!categoria && pessoa?.tipo === "favorecido" && pessoa.categoria) {
    categoria = pessoa.categoria;
    origemDaCategoria = `padrão de ${pessoa.nome}`;
  }
  if (!categoria && sentido === "gasto") {
    const pelo = await categoriaDoTexto(ctx, descricao, valor);
    if (pelo) { categoria = pelo.nome; origemDaCategoria = `pelo texto: ${pelo.motivo}`; }
  }

  return { sentido, valor, descricao, data, categoria, origemDaCategoria, pessoa, os, pagoPor, socio };
}

/** O texto da confirmação: o que vai acontecer, com tudo resolvido. */
export async function resumirPedido(ctx: ToolCtx, nome: string, args: Record<string, unknown>): Promise<string | null> {
  if (nome === "lancar_no_caixa") {
    const p = await resolverPedidoDeCaixa(ctx, args);
    if ("error" in p) return `⚠️ ${p.error}`;
    const quando = p.data ? p.data.split("-").reverse().join("/") : "hoje";
    if (p.sentido === "saque" || p.sentido === "deposito") return `- ${p.descricao}: *${brl.format(p.valor)}* · ${quando}`;
    return [
      `- ${p.sentido === "gasto" ? "Gasto" : "Recebimento"} de *${brl.format(p.valor)}* · ${p.descricao} · ${quando}`,
      p.categoria
        ? `- Categoria: *${p.categoria}*${p.origemDaCategoria ? ` (${p.origemDaCategoria})` : ""}`
        : `- Categoria: *${p.sentido === "gasto" ? "Outras despesas" : "Serviços prestados"}* (não reconheci pelo texto — diga a categoria se quiser outra)`,
      p.pessoa ? `- ${p.pessoa.tipo === "cliente" ? "Cliente" : p.pessoa.tipo === "favorecido" ? "Para (favorecido)" : "Fornecedor"}: ${p.pessoa.nome}` : null,
      p.os ? `- OS: ${p.os.numero}` : null,
      p.pagoPor === "socio"
        ? `- Pago do bolso de *${p.socio?.nome}*: fica como reembolso a pagar a ele (o Caixa não mexe)`
        : `- ${p.sentido === "gasto" ? "Sai" : "Entra"} do *Caixa (dinheiro)*`,
    ].filter(Boolean).join("\n");
  }
  if (nome === "anotar_transacao_do_banco") {
    const quando = dataDita(args.data) ?? "hoje";
    const pelo = !args.categoria && !args.quem && args.sentido !== "entrada" && args.descricao
      ? await categoriaDoTexto(ctx, String(args.descricao), Number(args.valor) || 0)
      : null;
    // O "sim" é sobre o CADASTRO que vai ser usado, não sobre o nome dito: "fernando" pode
    // ser o Fernando Nunes Fachini EPP. Mostrar o resolvido é o que torna a escolha manual.
    let quem: string | null = null;
    let pessoa: Pessoa | null = null;
    let documentoSemCadastro = false;
    let cadastroSemDocumento = false;
    if (args.quem) {
      const todas = await listaDePessoas(ctx);
      const alvo = args.sentido === "entrada" ? todas.filter((x) => x.tipo === "cliente") : todas.filter((x) => x.tipo !== "cliente");
      const r = escolherPorNome(String(args.quem), alvo);
      if ("ambiguo" in r) return `⚠️ Qual "${args.quem}"? ${r.ambiguo.map((x) => `${x.nome} (${x.tipo})`).join("; ")}`;
      if ("nenhum" in r) return `⚠️ Não achei "${args.quem}". Cadastre antes ou diga como está no cadastro.`;
      const conferido = conferirDocumentoDoCadastro(r.achado, args.documento);
      if ("error" in conferido) return `⚠️ ${conferido.error}`;
      cadastroSemDocumento = conferido.semDocumentoNoCadastro;
      pessoa = r.achado;
      quem = `${r.achado.nome} (${r.achado.tipo})`;
    } else if (args.documento) {
      const r = await pessoaPeloDocumento(ctx, args.documento, args.sentido === "entrada" ? "entrada" : "saida");
      if (r && "error" in r) return `⚠️ ${r.error}`;
      if (r && "ambiguo" in r) return `⚠️ Mais de um cadastro com o documento ${String(args.documento)}: ${listaDeCadastros(r.ambiguo)}. Diga qual.`;
      if (r && "achado" in r) {
        pessoa = r.achado;
        quem = `${r.achado.nome} (${r.achado.tipo}), pelo CPF/CNPJ`;
      }
      documentoSemCadastro = !!r && "nenhum" in r;
    }
    const os = await osPeloNumero(ctx, args.os);
    if (os && "error" in os) return `⚠️ ${os.error}`;
    // A categoria que o execute VAI gravar: a dita (resolvida no plano de contas), senão a
    // padrão do favorecido, senão a do texto — o "sim" é sobre ela.
    const cat = await categoriaValida(ctx, args.categoria, args.sentido === "entrada" ? "receivable" : "payable");
    if (cat && "error" in cat) return `⚠️ ${cat.error}`;
    const padrao = !cat && pessoa?.tipo === "favorecido" && pessoa.categoria ? pessoa.categoria : null;
    return [
      `- Quando chegar do banco: ${args.sentido === "entrada" ? "entrada" : "saída"} de *${brl.format(Number(args.valor) || 0)}* (${quando})`,
      args.documento ? `- Para o documento ${String(args.documento)}` : null,
      quem ? `- Classificar como: *${quem}*` : null,
      cadastroSemDocumento
        ? `- ⚠️ ${pessoa!.nome} não tem CPF/CNPJ no cadastro: não dá para conferir que ${docFormatado(args.documento)} é dele. Confira antes do "sim".`
        : null,
      cat ? `- Categoria: *${cat.nome}*` : null,
      padrao ? `- Categoria: *${padrao}* (padrão de ${pessoa!.nome})` : null,
      !cat && !padrao && pelo ? `- Categoria: *${pelo.nome}* (pelo texto: ${pelo.motivo})` : null,
      os ? `- OS: ${os.numero}` : null,
      documentoSemCadastro
        ? "- Nenhum cadastro com esse CPF/CNPJ: se a transação chegar com o nome de quem recebeu, ela não entra classificada (cadastre antes para entrar)."
        : !quem ? "- Sem dizer para quem foi: só vale para compra no débito ou transferência SEM nome no extrato." : null,
      "- Se houver mais de uma transação desse valor nesses dias, ou se a que chegou for de outro nome, nada é aplicado: eu pergunto.",
    ].filter(Boolean).join("\n");
  }
  return null;
}

async function chamar(ctx: ToolCtx, fn: string, params: Record<string, unknown>) {
  const { data, error } = await ctx.sb.rpc(fn, { ...params, p_autor: ctx.userId || null });
  if (error) return { error: error.message.replace(/^(P0001|42501|23514):\s*/, "") };
  return data;
}

export const caixaTools: ToolDef[] = [
  {
    name: "lancar_no_caixa",
    description:
      "Lança dinheiro vivo e o que saiu do bolso do sócio: 'gastei 50 em dinheiro com almoço', 'paguei 100 em dinheiro pro Roberto', " +
      "'recebi 300 em dinheiro do cliente X', 'saquei 500 pro caixa', 'paguei 80 de peça do meu bolso'. Passe como a pessoa falou " +
      "(nomes, número da OS); o sistema acha os cadastros, a categoria e o Caixa. Pix e cartão NÃO: chegam pelo banco (use " +
      "anotar_transacao_do_banco para classificar antes). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        sentido: { type: "string", enum: ["gasto", "recebimento", "saque", "deposito"], description: "gasto (padrão), recebimento, saque (banco→caixa), deposito (caixa→banco)." },
        valor: { type: "number" },
        descricao: { type: "string", description: "O que foi, com as palavras da pessoa." },
        data: { type: "string", description: "'hoje' (padrão), 'ontem', dd/mm." },
        categoria: { type: "string", description: "Se a pessoa disser. Sem ela, o sistema usa a padrão de quem recebeu ou deduz pelo texto (almoço → Alimentação de campo); a confirmação mostra qual." },
        quem: { type: "string", description: "Favorecido/fornecedor (gasto) ou cliente (recebimento), pelo nome." },
        os: { type: "string", description: "Número da OS, se o gasto foi para um serviço." },
        pago_por: { type: "string", enum: ["caixa", "bolso_do_socio"], description: "bolso_do_socio = saiu do dinheiro pessoal: vira reembolso." },
        socio: { type: "string", description: "Qual sócio pagou, se pago_por = bolso_do_socio." },
      },
      required: ["valor"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const p = await resolverPedidoDeCaixa(ctx, args);
      if ("error" in p) return p;
      if (p.sentido === "saque" || p.sentido === "deposito") {
        return await chamar(ctx, "mover_caixa", { p_sentido: p.sentido, p_valor: p.valor, p_data: p.data, p_transacao_banco: null });
      }
      return await chamar(ctx, "lancar_no_caixa", {
        p_sentido: p.sentido === "gasto" ? "saida" : "entrada",
        p_valor: p.valor, p_descricao: p.descricao, p_data: p.data, p_categoria: p.categoria,
        p_fornecedor_id: p.pessoa?.tipo === "fornecedor" ? p.pessoa.id : null,
        p_favorecido_id: p.pessoa?.tipo === "favorecido" ? p.pessoa.id : null,
        p_cliente_id: p.pessoa?.tipo === "cliente" ? p.pessoa.id : null,
        p_os_id: p.os?.id ?? null,
        p_pago_por: p.pagoPor, p_socio_id: p.socio?.id ?? null,
      });
    },
  },
  {
    name: "ajustar_saldo_do_caixa",
    description:
      "Acerta o Caixa pela contagem do dinheiro: 'contei, tem 640 no caixa'. O sistema registra a diferença (sobra ou falta) " +
      "com o motivo. Use também para o saldo inicial do Caixa. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        saldo_contado: { type: "number", description: "Quanto dinheiro há agora." },
        motivo: { type: "string", description: "Ex.: contagem de sexta; saldo inicial." },
      },
      required: ["saldo_contado", "motivo"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      return await chamar(ctx, "ajustar_caixa", { p_saldo_contado: Number(args.saldo_contado), p_motivo: String(args.motivo ?? "") });
    },
  },
  {
    name: "anotar_transacao_do_banco",
    description:
      "Classifica AGORA uma transação que o banco ainda vai trazer (Pix/transferência/boleto): 'fiz um Pix de 1.500 pro CNPJ X, " +
      "classifica como fornecedor TSD', 'o Pix de 800 do Fulano de hoje é da OS-60'. Quando a linha chegar, ela entra na fila já " +
      "classificada; se já chegou, classifica na hora. Passe SEMPRE 'quem' quando a pessoa disser (e o documento, se disser): " +
      "sem dizer para quem foi, só vale para transação sem nome no extrato (débito no cartão, transferência sem nome) — " +
      "Pix com nome exige o nome (decisão do dono). Só o CPF/CNPJ, sem o nome, também serve: o sistema acha o cadastro " +
      "por ele. Débito no cartão NÃO leva documento (a linha chega sem CNPJ e não casaria). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        sentido: { type: "string", enum: ["saida", "entrada"], description: "Padrão: saida." },
        valor: { type: "number" },
        data: { type: "string", description: "'hoje' (padrão), 'ontem', dd/mm." },
        documento: { type: "string", description: "CPF/CNPJ de quem recebeu/pagou (dito ou do comprovante de Pix/boleto). Sem 'quem', acha o cadastro por ele. Nunca em débito no cartão." },
        quem: { type: "string", description: "Fornecedor/favorecido (saída) ou cliente (entrada), pelo nome." },
        categoria: { type: "string" },
        os: { type: "string" },
        descricao: { type: "string" },
      },
      required: ["valor"],
    },
    risk: "medium",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const sentido = args.sentido === "entrada" ? "entrada" : "saida";
      const valor = Number(String(args.valor ?? "").replace(",", "."));
      if (!(valor > 0)) return { error: "Qual o valor?" };
      const data = dataDita(args.data);
      let pessoa: Pessoa | null = null;
      if (args.quem) {
        const todas = await listaDePessoas(ctx);
        const alvo = sentido === "entrada" ? todas.filter((p) => p.tipo === "cliente") : todas.filter((p) => p.tipo !== "cliente");
        const r = escolherPorNome(String(args.quem), alvo);
        if ("ambiguo" in r) return { error: `Qual "${args.quem}"? ${r.ambiguo.map((p) => `${p.nome} (${p.tipo})`).join("; ")}` };
        if ("nenhum" in r) return { error: `Não achei "${args.quem}". Cadastre antes ou diga como está no cadastro.` };
        const conferido = conferirDocumentoDoCadastro(r.achado, args.documento);
        if ("error" in conferido) return conferido;
        pessoa = r.achado;
      } else if (args.documento) {
        // Sem nome dito, o CPF/CNPJ acha o cadastro (a confirmação mostrou qual).
        const r = await pessoaPeloDocumento(ctx, args.documento, sentido);
        if (r && "error" in r) return r;
        if (r && "ambiguo" in r) return { error: `Mais de um cadastro com o documento ${String(args.documento)}: ${listaDeCadastros(r.ambiguo)}. Diga qual.` };
        if (r && "achado" in r) pessoa = r.achado;
      }
      const cat = await categoriaValida(ctx, args.categoria, sentido === "entrada" ? "receivable" : "payable");
      if (cat && "error" in cat) return cat;
      const os = await osPeloNumero(ctx, args.os);
      if (os && "error" in os) return os;
      let categoria = cat?.nome ?? (pessoa?.tipo === "favorecido" ? pessoa.categoria ?? null : null);
      // Sem categoria e sem ninguém dito: o texto decide (a confirmação mostrou a mesma coisa).
      if (!categoria && !args.quem && sentido === "saida" && args.descricao) {
        categoria = (await categoriaDoTexto(ctx, String(args.descricao), valor))?.nome ?? null;
      }
      return await chamar(ctx, "anotar_transacao", {
        p_sentido: sentido, p_valor: valor, p_data: data,
        p_documento: args.documento ? String(args.documento) : null, p_nome: pessoa?.nome ?? (args.quem ? String(args.quem) : null),
        p_fornecedor_id: pessoa?.tipo === "fornecedor" ? pessoa.id : null,
        p_favorecido_id: pessoa?.tipo === "favorecido" ? pessoa.id : null,
        p_cliente_id: pessoa?.tipo === "cliente" ? pessoa.id : null,
        p_categoria: categoria,
        p_os_id: os?.id ?? null,
        p_descricao: args.descricao ? String(args.descricao) : null,
      });
    },
  },
  {
    name: "gastos_por_categoria",
    description:
      "Quanto se gastou (ou recebeu) por categoria num mês, comparado ao mês anterior, com quem mais recebeu: 'quanto gastei com " +
      "combustível em setembro?', 'onde foi o dinheiro este mês?'. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        categoria: { type: "string", description: "Parte do nome da categoria; omitir = todas." },
        mes: { type: "number" }, ano: { type: "number" },
        tipo: { type: "string", enum: ["despesa", "receita"], description: "Padrão: despesa." },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const hoje = new Date();
      const ano = Number(args.ano ?? hoje.getUTCFullYear());
      const mes = Number(args.mes ?? hoje.getUTCMonth() + 1);
      const intervalo = (a: number, m: number) => {
        const ult = new Date(Date.UTC(a, m, 0)).getUTCDate();
        return [`${a}-${String(m).padStart(2, "0")}-01`, `${a}-${String(m).padStart(2, "0")}-${ult}`];
      };
      const [aAnt, mAnt] = mes === 1 ? [ano - 1, 12] : [ano, mes - 1];
      const receita = args.tipo === "receita";
      const tabela = receita ? "receivables" : "payables";
      const colCat = receita ? "category" : "expense_category";
      const ler = async (a: number, m: number) => {
        const [de, ate] = intervalo(a, m);
        const { data } = await ctx.sb.from(tabela)
          .select(receita ? "amount, category, clients(name)" : "amount, expense_category, supplier_name, suppliers(name), payees(name)")
          .neq("status", "cancelled").gte("issue_date", de).lte("issue_date", ate).limit(5000);
        return (data ?? []) as any[];
      };
      const [atual, anterior, cats] = await Promise.all([
        ler(ano, mes), ler(aAnt, mAnt),
        ctx.sb.from("financial_categories").select("name, dre_group"),
      ]);
      // Fatura do cartão, empréstimo, aplicação e transferência ficam FORA do resultado: a
      // compra no cartão já foi contada quando aconteceu, e somar a fatura contava duas vezes
      // (R$ 70,9 mil de fatura em 2026). Só entram se a pessoa perguntar por uma delas.
      const foraDoResultado = new Set(((cats.data ?? []) as { name: string; dre_group: string | null }[])
        .filter((c) => c.dre_group === "nao_operacional").map((c) => c.name));
      const filtro = args.categoria ? normal(args.categoria) : null;
      const passa = (r: any) => filtro ? normal(r[colCat]).includes(filtro) : !foraDoResultado.has(r[colCat]);
      const fora = new Map<string, number>();
      if (!filtro) {
        for (const r of atual) if (foraDoResultado.has(r[colCat])) fora.set(r[colCat], (fora.get(r[colCat]) ?? 0) + Number(r.amount));
      }
      const somaPorCat = (rs: any[]) => {
        const m = new Map<string, number>();
        for (const r of rs.filter(passa)) m.set(r[colCat] ?? "(sem categoria)", (m.get(r[colCat] ?? "(sem categoria)") ?? 0) + Number(r.amount));
        return m;
      };
      const agora = somaPorCat(atual);
      const antes = somaPorCat(anterior);
      const quem = new Map<string, number>();
      for (const r of atual.filter(passa)) {
        const n = receita ? r.clients?.name : (r.suppliers?.name ?? r.payees?.name ?? r.supplier_name);
        if (n) quem.set(n, (quem.get(n) ?? 0) + Number(r.amount));
      }
      const total = [...agora.values()].reduce((s, v) => s + v, 0);
      const totalAntes = [...antes.values()].reduce((s, v) => s + v, 0);
      return {
        mes: `${String(mes).padStart(2, "0")}/${ano}`,
        total, total_mes_anterior: totalAntes,
        variacao_pct: totalAntes > 0 ? Math.round(((total - totalAntes) / totalAntes) * 100) : null,
        por_categoria: [...agora.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12)
          .map(([categoria, valor]) => ({ categoria, valor, mes_anterior: antes.get(categoria) ?? 0 })),
        quem_mais_recebeu: [...quem.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([nome, valor]) => ({ nome, valor })),
        fora_do_resultado: [...fora.entries()].map(([categoria, valor]) => ({ categoria, valor })),
        observacao: fora.size
          ? "O total não inclui o que fica fora do resultado (pagamento de fatura, empréstimo, aplicação, transferência entre contas): a compra no cartão já foi contada quando aconteceu."
          : undefined,
      };
    },
  },
];
