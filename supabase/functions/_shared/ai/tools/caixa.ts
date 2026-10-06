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
import {
  categoriaDaLinha, centavos, doMesmoRamoEmOutraCategoria, intervaloDoMes, linhaCasa, normal as normalG, resolverCategorias, somar,
  type LancamentoLido, type LinhaSemLancamento,
} from "../gastos.ts";

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
    // Outra pessoa pagando (ou recebendo) em nome de alguém — cônjuge, empresa — é caso de tela:
    // anotar só com o nome nunca casaria com a linha, que chega com o nome de quem pagou.
    return {
      error: `O documento ${docFormatado(documento)} não é o de ${pessoa.nome} (no cadastro: ${docFormatado(pessoa.documento)}): ` +
        `o sistema não junta nome e documento diferentes. Se é outra pessoa pagando ou recebendo em nome de ${pessoa.nome}, ` +
        `classifique pela tela do Extrato quando a transação chegar; se o nome estava errado, anote só com o documento.`,
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
 * dono). "O Pix de 800 pro CNPJ X é da OS-60" acha o fornecedor sem depender de o nome dito
 * bater com o do cadastro. Saída procura fornecedor e favorecido; entrada, cliente. Mais de um
 * é pergunta.
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

export async function categoriaValida(ctx: ToolCtx, dita: unknown, tipo: "payable" | "receivable"): Promise<{ nome: string } | { error: string } | null> {
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

export async function osPeloNumero(ctx: ToolCtx, numero: unknown): Promise<{ id: string; numero: string } | { error: string } | null> {
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
  /**
   * Para quem foi, quando não está no cadastro (06/10/2026): gasto do dia a dia ("493 pra Eliane,
   * alimentação") não precisa de cadastro — o nome vai junto da descrição e a categoria classifica.
   */
  nomeLivre?: string | null;
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
  let nomeLivre: string | null = null;
  if (args.quem) {
    const alvo = sentido === "recebimento" ? pessoas.filter((p) => p.tipo === "cliente") : pessoas.filter((p) => p.tipo !== "cliente");
    const r = escolherPorNome(String(args.quem), alvo);
    if ("ambiguo" in r) return { error: `Qual "${args.quem}"? ${r.ambiguo.map((p) => `${p.nome} (${p.tipo})`).join("; ")}` };
    if ("nenhum" in r) {
      if (sentido === "recebimento") {
        return { error: `Não achei o cliente "${args.quem}". Cadastre o cliente ou diga o nome como está no cadastro.` };
      }
      // Gasto para quem não está no cadastro: lança com o nome na descrição (06/10/2026).
      nomeLivre = String(args.quem).trim();
    } else {
      pessoa = r.achado;
    }
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

  return {
    sentido, valor, descricao: nomeLivre ? `${nomeLivre} — ${descricao}` : descricao,
    data, categoria, origemDaCategoria, pessoa, nomeLivre, os, pagoPor, socio,
  };
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
      p.nomeLivre ? `- Para: *${p.nomeLivre}* (sem cadastro — o nome fica na descrição)` : null,
      p.os ? `- OS: ${p.os.numero}` : null,
      p.pagoPor === "socio"
        ? `- Pago do bolso de *${p.socio?.nome}*: fica como reembolso a pagar a ele (o Caixa não mexe)`
        : `- ${p.sentido === "gasto" ? "Sai" : "Entra"} do *Caixa (dinheiro)*`,
    ].filter(Boolean).join("\n");
  }
  if (nome === "anotar_transacao_do_banco") {
    const quando = dataDita(args.data) ?? "hoje";
    // A categoria pelo texto vale sem ninguém dito OU com nome sem cadastro (não há padrão de favorecido).
    const pelo = !args.categoria && args.sentido !== "entrada" && args.descricao
      ? await categoriaDoTexto(ctx, String(args.descricao), Number(args.valor) || 0)
      : null;
    // O "sim" é sobre o CADASTRO que vai ser usado, não sobre o nome dito: "fernando" pode
    // ser o Fernando Nunes Fachini EPP. Mostrar o resolvido é o que torna a escolha manual.
    let quem: string | null = null;
    let pessoa: Pessoa | null = null;
    let nomeLivre: string | null = null;
    let documentoSemCadastro = false;
    let cadastroSemDocumento = false;
    if (args.quem) {
      const todas = await listaDePessoas(ctx);
      const alvo = args.sentido === "entrada" ? todas.filter((x) => x.tipo === "cliente") : todas.filter((x) => x.tipo !== "cliente");
      const r = escolherPorNome(String(args.quem), alvo);
      if ("ambiguo" in r) return `⚠️ Qual "${args.quem}"? ${r.ambiguo.map((x) => `${x.nome} (${x.tipo})`).join("; ")}`;
      if ("nenhum" in r) {
        // Sem cadastro (06/10/2026): vale o nome dito + a categoria. Casa com a transação que chegar
        // com ESSE nome no extrato (nome igual — regra do dono de 26/09).
        nomeLivre = String(args.quem).trim();
      } else {
        const conferido = conferirDocumentoDoCadastro(r.achado, args.documento);
        if ("error" in conferido) return `⚠️ ${conferido.error}`;
        cadastroSemDocumento = conferido.semDocumentoNoCadastro;
        pessoa = r.achado;
        quem = `${r.achado.nome} (${r.achado.tipo})`;
      }
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
    if (nomeLivre && !cat && !pelo && !os) {
      return `⚠️ "${nomeLivre}" não está no cadastro: diga a categoria (ex.: Alimentação de campo) para eu anotar só com o nome.`;
    }
    const pelaFrase = !cat && !padrao && pelo && (!args.quem || nomeLivre);
    return [
      `- Quando chegar do banco: ${args.sentido === "entrada" ? "entrada" : "saída"} de *${brl.format(Number(args.valor) || 0)}* (${quando})`,
      args.documento ? `- Para o documento ${String(args.documento)}` : null,
      quem ? `- Classificar como: *${quem}*` : null,
      nomeLivre ? `- Para: *${nomeLivre}* (sem cadastro — entra classificada quando chegar do banco com esse mesmo nome)` : null,
      cadastroSemDocumento
        ? `- ⚠️ ${pessoa!.nome} não tem CPF/CNPJ no cadastro: não dá para conferir que ${docFormatado(args.documento)} é dele. Confira antes do "sim".`
        : null,
      cat ? `- Categoria: *${cat.nome}*` : null,
      padrao ? `- Categoria: *${padrao}* (padrão de ${pessoa!.nome})` : null,
      pelaFrase ? `- Categoria: *${pelo!.nome}* (pelo texto: ${pelo!.motivo})` : null,
      os ? `- OS: ${os.numero}` : null,
      documentoSemCadastro
        ? "- Nenhum cadastro com esse CPF/CNPJ: se a transação chegar com o nome de quem recebeu, ela não entra classificada (cadastre antes para entrar)."
        : !quem && !nomeLivre ? "- Sem dizer para quem foi: só vale para compra no débito ou transferência SEM nome no extrato." : null,
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
        quem: { type: "string", description: "Favorecido/fornecedor (gasto) ou cliente (recebimento), pelo nome. Gasto para quem não está no cadastro: o nome vai na descrição." },
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
      "Pix com nome exige o nome (decisão do dono). Quem NÃO está no cadastro também serve: passe o nome e a categoria (gasto do dia a dia " +
      "não precisa de cadastro). Só o CPF/CNPJ, sem o nome, também serve: o sistema acha o cadastro " +
      "por ele. Débito no cartão NÃO leva documento (a linha chega sem CNPJ e não casaria). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        sentido: { type: "string", enum: ["saida", "entrada"], description: "Padrão: saida." },
        valor: { type: "number" },
        data: { type: "string", description: "'hoje' (padrão), 'ontem', dd/mm." },
        documento: { type: "string", description: "CPF/CNPJ de quem recebeu/pagou, se a pessoa disse. Sem 'quem', acha o cadastro por ele. Nunca em débito no cartão." },
        quem: { type: "string", description: "Para quem foi (saída) ou de quem veio (entrada), pelo nome. NÃO precisa estar cadastrado: sem cadastro, vale o nome + a categoria." },
        categoria: { type: "string", description: "Categoria de despesa/receita. Obrigatória quando 'quem' não está no cadastro (ou deduzida do texto)." },
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
      let semCadastro = false;
      if (args.quem) {
        const todas = await listaDePessoas(ctx);
        const alvo = sentido === "entrada" ? todas.filter((p) => p.tipo === "cliente") : todas.filter((p) => p.tipo !== "cliente");
        const r = escolherPorNome(String(args.quem), alvo);
        if ("ambiguo" in r) return { error: `Qual "${args.quem}"? ${r.ambiguo.map((p) => `${p.nome} (${p.tipo})`).join("; ")}` };
        if ("nenhum" in r) {
          semCadastro = true; // vale o nome dito (p_nome) + a categoria
        } else {
          const conferido = conferirDocumentoDoCadastro(r.achado, args.documento);
          if ("error" in conferido) return conferido;
          pessoa = r.achado;
        }
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
      // Sem categoria e sem ninguém do cadastro: o texto decide (a confirmação mostrou a mesma coisa).
      if (!categoria && (!args.quem || semCadastro) && sentido === "saida" && args.descricao) {
        categoria = (await categoriaDoTexto(ctx, String(args.descricao), valor))?.nome ?? null;
      }
      if (semCadastro && !categoria && !os) {
        return { error: `"${String(args.quem)}" não está no cadastro: diga a categoria para eu anotar só com o nome.` };
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
      "Quanto se gastou (ou recebeu) num mês ou período, com a resposta INTEIRA: 'quanto gastei com combustível em setembro?', " +
      "'gasolina no mês passado', 'quanto foi no Posto Paulinho?', 'onde foi o dinheiro este mês?'. Em `categoria` passe o que a " +
      "pessoa disse (nome de categoria ou palavra do dia a dia: gasolina, posto, almoço, peças); em `busca`, parte do nome do " +
      "fornecedor ou estabelecimento. A resposta separa: `lancado` (o que já está nos lançamentos), `nao_lancado` (compras no " +
      "cartão ainda pendentes e linhas do Extrato sem lançamento, reconhecidas pelo ramo do cartão e pelo texto) e " +
      "`em_outra_categoria` (mesmo tipo de estabelecimento lançado em outra categoria, fora do total). Responda com as partes, " +
      "não só o lançado. Se vier `error`, diga que não conseguiu consultar — NUNCA diga que não houve gasto. Só leitura.",
    input_schema: {
      type: "object",
      properties: {
        categoria: { type: "string", description: "O que a pessoa disse: 'combustível', 'gasolina', 'posto', 'peças', 'almoço'… Omitir = todas." },
        busca: { type: "string", description: "Parte do nome do fornecedor, favorecido ou estabelecimento ('Posto Paulinho', 'Uber')." },
        mes: { type: "number" }, ano: { type: "number" },
        de: { type: "string", description: "Início do período (AAAA-MM-DD), no lugar de mes/ano." },
        ate: { type: "string", description: "Fim do período (AAAA-MM-DD)." },
        tipo: { type: "string", enum: ["despesa", "receita"], description: "Padrão: despesa." },
      },
    },
    risk: "low",
    roles: CARGOS_FINANCEIRO,
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const receita = args.tipo === "receita";
      const falhou = (o: string, e: { message?: string } | null) => ({
        error: `Não consegui ler ${o} (${e?.message ?? "erro do banco"}). Diga ao dono que a consulta falhou — não que não houve ${receita ? "recebimento" : "gasto"}.`,
      });

      // ── Período ──────────────────────────────────────────────────────────────────────────
      const hoje = new Date(Date.now() - 3 * 3600_000); // Brasília
      let de: string, ate: string, rotulo: string;
      let anterior: [string, string] | null = null;
      if (args.de || args.ate) {
        de = String(args.de ?? args.ate);
        ate = String(args.ate ?? args.de);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(de) || !/^\d{4}-\d{2}-\d{2}$/.test(ate)) return { error: "Use de/ate no formato AAAA-MM-DD." };
        rotulo = `${de.split("-").reverse().join("/")} a ${ate.split("-").reverse().join("/")}`;
      } else {
        const ano = Number(args.ano ?? hoje.getUTCFullYear());
        const mes = Number(args.mes ?? hoje.getUTCMonth() + 1);
        if (!(mes >= 1 && mes <= 12) || !(ano > 2000)) return { error: "Mês ou ano inválido." };
        [de, ate] = intervaloDoMes(ano, mes);
        rotulo = `${String(mes).padStart(2, "0")}/${ano}`;
        anterior = mes === 1 ? intervaloDoMes(ano - 1, 12) : intervaloDoMes(ano, mes - 1);
      }

      // ── Plano de contas e regras de texto do dono ────────────────────────────────────────
      const [catsRes, regrasRes] = await Promise.all([
        ctx.sb.from("financial_categories").select("name, type, dre_group, active"),
        ctx.admin.from("finance_rules")
          .select("id, match_type, match_value, direction, set_category, set_dre_group, autonomy, status, min_amount, max_amount")
          .eq("status", "active").eq("match_type", "text").limit(500),
      ]);
      if (catsRes.error) return falhou("o plano de contas", catsRes.error);
      const regras = (regrasRes.data ?? []) as unknown as RegraFinanceira[];
      const cats = (catsRes.data ?? []) as { name: string; type: string; dre_group: string | null; active: boolean | null }[];
      const doLado = cats.filter((c) => c.type === (receita ? "receivable" : "payable"));
      // Fatura do cartão, empréstimo, aplicação e transferência ficam FORA do resultado: a compra
      // no cartão já foi contada quando aconteceu (somar a fatura contava duas vezes). Só entram
      // se a pessoa perguntar por uma delas.
      const foraDoResultado = new Set(doLado.filter((c) => c.dre_group === "nao_operacional").map((c) => c.name));

      let categorias: string[] | null = null;
      let busca: string | null = args.busca ? String(args.busca) : null;
      let comoEntendi = "todas as categorias";
      if (args.categoria) {
        const r = resolverCategorias(String(args.categoria), doLado.map((c) => c.name), regras);
        if ("categorias" in r) {
          categorias = r.categorias;
          comoEntendi = `${r.categorias.join(", ")} (${r.como})`;
        } else if (!busca) {
          // Não é categoria: talvez seja um nome ("quanto gastei com o Roberto").
          busca = String(args.categoria);
          comoEntendi = `nenhuma categoria com "${args.categoria}"; procurei pelo nome no fornecedor, favorecido e descrição`
            + (r.parecidas.length ? ` (categorias parecidas: ${r.parecidas.join(", ")})` : "");
        } else {
          return { error: `Nenhuma categoria com "${args.categoria}". Categorias de ${receita ? "receita" : "despesa"}: ${doLado.map((c) => c.name).join(", ")}.` };
        }
      }
      const passaCategoria = (c: string | null) =>
        categorias ? categorias.some((x) => normalG(x) === normalG(c)) : !foraDoResultado.has(c ?? "");
      const passaBusca = (texto: string) => !busca || normalG(texto).includes(normalG(busca));

      // ── Lançamentos ──────────────────────────────────────────────────────────────────────
      type Lido = LancamentoLido & { id: string };
      const lerLancamentos = async (ini: string, fim: string): Promise<Lido[] | { error: string }> => {
        const lidos: Lido[] = [];
        for (let de0 = 0; de0 < 20000; de0 += 1000) {
          const q = receita
            ? ctx.sb.from("receivables")
              .select("id, issue_date, amount, category, description, clients!receivables_client_id_fkey(name)")
            : ctx.sb.from("payables")
              .select("id, issue_date, amount, expense_category, description, supplier_name, suppliers!payables_supplier_id_fkey(name), payees!payables_payee_id_fkey(name), bank_transactions!payables_bank_transaction_id_fkey(payee_mcc, merchant_name)");
          const { data, error } = await q.neq("status", "cancelled").gte("issue_date", ini).lte("issue_date", fim)
            .order("id").range(de0, de0 + 999);
          if (error) return falhou(receita ? "as contas a receber" : "as contas a pagar", error);
          for (const r of (data ?? []) as any[]) {
            const quem = receita ? r.clients?.name ?? null
              : r.suppliers?.name ?? r.payees?.name ?? r.supplier_name ?? r.bank_transactions?.merchant_name ?? null;
            lidos.push({
              id: r.id, data: r.issue_date, valor: Number(r.amount), categoria: receita ? r.category : r.expense_category,
              descricao: r.description ?? "", quem, mcc: receita ? null : r.bank_transactions?.payee_mcc ?? null,
            });
          }
          if ((data ?? []).length < 1000) break;
        }
        return lidos;
      };
      const atual = await lerLancamentos(de, ate);
      if ("error" in atual) return atual;
      const doPedido = atual.filter((l) => passaCategoria(l.categoria) && passaBusca(`${l.quem ?? ""} ${l.descricao}`));
      const total = somar(doPedido, (l) => l.valor);

      let totalAnterior: number | null = null;
      if (anterior) {
        const ant = await lerLancamentos(anterior[0], anterior[1]);
        if ("error" in ant) return ant;
        totalAnterior = somar(ant.filter((l) => passaCategoria(l.categoria) && passaBusca(`${l.quem ?? ""} ${l.descricao}`)), (l) => l.valor);
      }

      const porCategoria = new Map<string, number>();
      for (const l of doPedido) porCategoria.set(l.categoria ?? "(sem categoria)", (porCategoria.get(l.categoria ?? "(sem categoria)") ?? 0) + l.valor);
      const quemMais = new Map<string, number>();
      for (const l of doPedido) if (l.quem) quemMais.set(l.quem, (quemMais.get(l.quem) ?? 0) + l.valor);

      // ── O que ainda não foi lançado (só despesa) ─────────────────────────────────────────
      let naoLancado: Record<string, unknown> | undefined;
      let emOutraCategoria: Record<string, unknown> | undefined;
      if (!receita) {
        const linhas: LinhaSemLancamento[] = [];
        for (let de0 = 0; de0 < 20000; de0 += 1000) {
          const { data, error } = await ctx.sb.from("bank_transactions")
            .select("id, transaction_date, amount, merchant_name, counterparty_name, description, payee_mcc, tx_status")
            .eq("transaction_type", "debit").is("dismissed_kind", null).eq("reconciled", false)
            .gte("transaction_date", de).lte("transaction_date", ate).order("id").range(de0, de0 + 999);
          if (error) return falhou("o extrato", error);
          for (const t of (data ?? []) as any[]) {
            linhas.push({
              id: t.id, data: t.transaction_date, valor: Math.abs(Number(t.amount)),
              quem: t.merchant_name ?? t.counterparty_name ?? t.description ?? "", mcc: t.payee_mcc ?? null,
              pendente: String(t.tx_status ?? "").toUpperCase() === "PENDING", categoriaSugerida: null,
            });
          }
          if ((data ?? []).length < 1000) break;
        }
        // Linha já lançada (conta a pagar ligada) ou transferência entre contas não entra.
        const ids = linhas.map((l) => l.id);
        const lancadas = new Set<string>();
        const transferencias = new Set<string>();
        const sugestao = new Map<string, string>();
        for (let i = 0; i < ids.length; i += 200) {
          const fatia = ids.slice(i, i + 200);
          const [pg, fila] = await Promise.all([
            ctx.sb.from("payables").select("bank_transaction_id").in("bank_transaction_id", fatia).neq("status", "cancelled"),
            ctx.sb.from("finance_review_queue").select("bank_transaction_id, kind, suggested_category").in("bank_transaction_id", fatia).eq("status", "pending"),
          ]);
          if (pg.error) return falhou("as contas a pagar ligadas ao extrato", pg.error);
          if (fila.error) return falhou("a fila do Extrato", fila.error);
          for (const p of (pg.data ?? []) as any[]) lancadas.add(p.bank_transaction_id);
          for (const q of (fila.data ?? []) as any[]) {
            if (q.kind === "internal_transfer") transferencias.add(q.bank_transaction_id);
            if (q.suggested_category) sugestao.set(q.bank_transaction_id, q.suggested_category);
          }
        }
        // A mesma compra pendente que o banco depois fechou e já foi lançada: não conta de novo.
        const jaLancadas = atual.map((l) => ({ k: `${normalG(l.quem)}|${centavos(l.valor)}`, d: Date.parse(l.data) }));
        const repetida = (l: LinhaSemLancamento) => l.pendente && jaLancadas.some((x) =>
          x.k === `${normalG(l.quem)}|${centavos(l.valor)}` && Math.abs(x.d - Date.parse(l.data)) <= 5 * 86_400_000);
        const semLancamento = linhas
          .filter((l) => !lancadas.has(l.id) && !transferencias.has(l.id) && !repetida(l))
          .map((l) => ({ ...l, categoriaSugerida: sugestao.get(l.id) ?? null }))
          .filter((l) => {
            if (!linhaCasa(l, categorias, busca, regras)) return false;
            if (categorias) return true;
            const c = categoriaDaLinha(l, regras);
            return !c || !foraDoResultado.has(c.categoria);
          });
        if (semLancamento.length) {
          // Por categoria indicada: no mês inteiro a lista de itens mostra só as maiores, e o
          // assistente somou só o que viu ("R$ 70,98 no posto" em vez de R$ 356,51, 02/10/2026).
          const porCategoriaNao = new Map<string, { valor: number; quantidade: number }>();
          for (const l of semLancamento) {
            const c = categoriaDaLinha(l, regras)?.categoria ?? "(sem categoria indicada)";
            const atual = porCategoriaNao.get(c) ?? { valor: 0, quantidade: 0 };
            atual.valor += l.valor;
            atual.quantidade += 1;
            porCategoriaNao.set(c, atual);
          }
          naoLancado = {
            total: somar(semLancamento, (l) => l.valor),
            quantidade: semLancamento.length,
            pendentes_no_cartao: semLancamento.filter((l) => l.pendente).length,
            por_categoria: [...porCategoriaNao.entries()].sort((a, b) => b[1].valor - a[1].valor)
              .map(([categoria, v]) => ({ categoria, valor: centavos(v.valor), quantidade: v.quantidade })),
            observacao: "Categoria indicada pela sugestão do Extrato, pelo ramo do cartão ou pelo nome do estabelecimento — ainda não confirmada por ninguém.",
            itens: [...semLancamento].sort((a, b) => b.valor - a.valor).slice(0, 15).map((l) => {
              const c = categoriaDaLinha(l, regras);
              return {
                data: l.data, quem: l.quem, valor: l.valor,
                situacao: l.pendente ? "compra pendente no cartão (o banco ainda não fechou)"
                  : sugestao.has(l.id) ? "na fila do Extrato" : "no extrato, sem lançamento",
                categoria_indicada: c ? `${c.categoria} (${c.por})` : null,
              };
            }),
          };
        }
        if (categorias) {
          const outros = atual.filter((l) => doMesmoRamoEmOutraCategoria(l, categorias!) && passaBusca(`${l.quem ?? ""} ${l.descricao}`));
          if (outros.length) {
            emOutraCategoria = {
              total: somar(outros, (l) => l.valor),
              itens: outros.slice(0, 10).map((l) => ({ data: l.data, quem: l.quem ?? l.descricao, valor: l.valor, lancado_como: l.categoria })),
              observacao: "Mesmo tipo de estabelecimento (pelo ramo do cartão), mas lançado em outra categoria: não entra no total. Pode ser certo (ex.: lanche no posto) ou um lançamento a corrigir.",
            };
          }
        }
      }

      const totalNaoLancado = Number((naoLancado as { total?: number } | undefined)?.total ?? 0);
      const fora = !categorias ? somar(atual.filter((l) => foraDoResultado.has(l.categoria ?? "")), (l) => l.valor) : 0;
      return {
        periodo: rotulo,
        tipo: receita ? "receita" : "despesa",
        como_entendi: comoEntendi + (busca && args.busca ? `; nome contém "${busca}"` : ""),
        lancado: {
          total,
          quantidade: doPedido.length,
          por_categoria: [...porCategoria.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12)
            .map(([categoria, valor]) => ({ categoria, valor: centavos(valor) })),
          itens: [...doPedido].sort((a, b) => b.valor - a.valor).slice(0, 12)
            .map((l) => ({ data: l.data, quem: l.quem ?? l.descricao, valor: l.valor, categoria: l.categoria })),
        },
        ...(naoLancado ? { nao_lancado: naoLancado, total_com_nao_lancado: centavos(total + totalNaoLancado) } : {}),
        ...(emOutraCategoria ? { em_outra_categoria: emOutraCategoria } : {}),
        ...(totalAnterior != null ? {
          mes_anterior_lancado: totalAnterior,
          variacao_pct: totalAnterior > 0 ? Math.round(((total - totalAnterior) / totalAnterior) * 100) : null,
        } : {}),
        quem_mais_recebeu: [...quemMais.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5).map(([nome, valor]) => ({ nome, valor: centavos(valor) })),
        ...(fora > 0 ? {
          fora_do_resultado: fora,
          observacao: "O total não inclui o que fica fora do resultado (pagamento de fatura, empréstimo, aplicação, transferência entre contas): a compra no cartão já foi contada quando aconteceu.",
        } : {}),
      };
    },
  },
];
