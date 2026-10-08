// Favorecido pela conversa (07/10/2026): editar, desativar e reativar — e a conta a pagar para ele.
//
// "troca o Pix da Eliane para o telefone 11 9…", "desativa o favorecido Alex", "lança uma conta a
// pagar de 300 para a Eliane, vence dia 10, alimentação". A tela é Favorecidos (src/pages/PayeesPage.tsx
// e src/components/PayeeFormDialog.tsx → useSalvarPayee): grava direto em `payees`, documento só com
// dígitos. Aqui são os mesmos campos.
//
// Desativar, por regra do dono ("Desativar cadastro: pausar as regras dele", 28/09/2026) — e desde
// 07/10/2026 a tela faz igual, pelo mesmo _shared/banking/pausa-do-favorecido.ts: desativar o cadastro não desliga quem aponta para ele, e o próximo Pix voltaria a
// entrar classificado no favorecido desativado. As regras do extrato que apontam para ele — pelo
// CPF/CNPJ dele, ou pelo nome COMPLETO dele no extrato — são pausadas junto, com uma marca na nota;
// reativar o favorecido reativa as que foram pausadas por isso. A confirmação lista quais.
import { lerRetrato, type ToolCtx, type ToolDef } from "./registry.ts";
import { categoriaValida, dataDita, ehErro, escolherPorNome, normal } from "./caixa.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import {
  alvoDoRetrato, brl, CARGOS_DO_FINANCEIRO, dataFuturaDita, ehUuid, ordemDita, semAcessoDoFinanceiro, valorDito,
} from "./financeiro-comum.ts";
import { hojeEmBrasilia } from "../../banking/fluxo-de-caixa.ts";
import {
  marcarPausa, mudancaDaRegra, regrasDaMudanca as escolherRegrasDaMudanca, regrasQueApontam, SITUACOES_DA_MUDANCA, tirarPausa,
  type RegraDoExtrato,
} from "../../banking/pausa-do-favorecido.ts";

const TIPOS = ["socio", "funcionario", "diarista", "prestador", "comissionado"];
const TIPOS_DE_CHAVE = ["cpf", "cnpj", "email", "telefone", "aleatoria"];
const TIPOS_DE_CONTA = ["corrente", "poupanca", "pagamento"];
const CAMPOS = "id, name, kind, document, phone, email, pix_key, pix_key_type, bank_name, bank_branch, bank_account, account_type, default_category, active, notes";

export interface FavorecidoLido {
  id: string; name: string; kind: string; document: string | null; phone: string | null; email: string | null;
  pix_key: string | null; pix_key_type: string | null; bank_name: string | null; bank_branch: string | null;
  bank_account: string | null; account_type: string | null; default_category: string | null; active: boolean; notes: string | null;
}

/** O favorecido dito — ativos E inativos (reativar é achar um inativo). Dúvida é pergunta, numa linha. */
export async function acharFavorecido(cliente: ToolCtx["sb"], args: Record<string, unknown>): Promise<{ favorecido: FavorecidoLido } | { error: string }> {
  const id = alvoDoRetrato(lerRetrato(args), "favorecido_id") ?? (ehUuid(args.favorecido_id) ? String(args.favorecido_id).trim() : null);
  const { data, error } = id
    ? await cliente.from("payees").select(CAMPOS).eq("id", id).limit(1)
    : await cliente.from("payees").select(CAMPOS).order("name").limit(1000);
  if (error) return { error: `Não consegui ler os favorecidos (${mensagemDoBanco(error)}).` };
  const lista = (data ?? []) as FavorecidoLido[];
  if (id) return lista[0] ? { favorecido: lista[0] } : { error: "Favorecido não encontrado." };
  const dito = typeof args.favorecido === "string" ? args.favorecido.trim() : "";
  if (!dito) return { error: "Qual favorecido? Diga o nome." };
  const r = escolherPorNome(dito, lista.map((f) => ({ ...f, nome: f.name })));
  if ("achado" in r) return { favorecido: r.achado };
  if ("ambiguo" in r) return { error: `Qual deles: ${r.ambiguo.map((f) => `${f.name}${f.active ? "" : " (inativo)"}`).join(" ou ")}?` };
  return { error: `Não achei o favorecido "${dito}". Para cadastrar, use cadastrar_favorecido.` };
}

/** Chave Pix dita → o tipo. 11 dígitos sem tipo é pergunta (CPF ou telefone). */
export function tipoDaChave(chave: string, dito?: unknown): string | { error: string } {
  if (dito != null && dito !== "") {
    // normal() tira acento e pontuação: "e-mail" vira "email", "chave aleatória" vira "chavealeatoria".
    const t = normal(dito).replace(/ /g, "");
    const tipo = t === "celular" || t === "fone" ? "telefone" : t === "chavealeatoria" ? "aleatoria" : t;
    return TIPOS_DE_CHAVE.includes(tipo) ? tipo : { error: `Tipo de chave Pix "${String(dito)}" não existe: cpf, cnpj, email, telefone ou aleatoria.` };
  }
  if (chave.includes("@")) return "email";
  if (/^[0-9a-f]{8}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{4}-?[0-9a-f]{12}$/i.test(chave.trim())) return "aleatoria";
  const d = chave.replace(/\D/g, "");
  if (chave.trim().startsWith("+") || d.length === 10 || d.length === 12 || d.length === 13) return "telefone";
  if (d.length === 14) return "cnpj";
  if (d.length === 11) return { error: `A chave ${chave} tem 11 dígitos: é CPF ou telefone? Pergunte e passe tipo_chave_pix.` };
  return { error: `Não reconheci o tipo da chave Pix "${chave}": diga se é cpf, cnpj, email, telefone ou aleatoria.` };
}

type Regra = RegraDoExtrato;
// A marca na nota, quem aponta e o que muda em cada regra moram em _shared/banking/pausa-do-favorecido.ts
// (07/10/2026): a tela de Favorecidos (use-payees.ts) faz a MESMA coisa, com a mesma marca.
export { marcarPausa, regrasQueApontam, tirarPausa };

async function lerRegras(cliente: ToolCtx["sb"], status: string[]): Promise<Regra[] | { error: string }> {
  const { data, error } = await cliente.from("finance_rules").select("id, match_type, match_value, set_category, status, note")
    .in("status", status).limit(1000);
  if (error) return { error: `Não consegui ler as regras do extrato (${mensagemDoBanco(error)}).` };
  return (data ?? []) as Regra[];
}

/** Desativar: as que apontam e estão valendo. Reativar: as que foram pausadas por esta desativação. */
async function regrasDaMudanca(cliente: ToolCtx["sb"], f: FavorecidoLido, ativar: boolean): Promise<Regra[] | { error: string }> {
  const lidas = await lerRegras(cliente, SITUACOES_DA_MUDANCA(ativar));
  return ehErro(lidas) ? lidas : escolherRegrasDaMudanca(f, lidas, ativar);
}

const rotuloDaRegra = (r: Regra) =>
  `${r.match_type === "document" ? `CPF/CNPJ ${r.match_value}` : `nome "${r.match_value}"`} → ${r.set_category ?? "sem categoria"}`;

interface Mudancas { patch: Record<string, unknown>; linhas: string[]; ativar: boolean | null }

/** O que vai mudar, campo a campo, com o antes — o mesmo para a confirmação e para a execução. */
export async function mudancasDoFavorecido(ctx: ToolCtx, f: FavorecidoLido, args: Record<string, unknown>): Promise<Mudancas | { error: string }> {
  const patch: Record<string, unknown> = {};
  const linhas: string[] = [];
  const texto = (k: string) => (typeof args[k] === "string" && String(args[k]).trim() ? String(args[k]).trim() : null);
  const mudar = (coluna: keyof FavorecidoLido, valor: unknown, rotulo: string) => {
    patch[coluna] = valor;
    linhas.push(`${rotulo}: ${f[coluna] ?? "—"} → *${valor ?? "—"}*`);
  };
  if (texto("novo_nome")) mudar("name", texto("novo_nome"), "Nome");
  if (texto("tipo")) {
    if (!TIPOS.includes(texto("tipo")!)) return { error: `Tipo "${texto("tipo")}" não existe: ${TIPOS.join(", ")}.` };
    mudar("kind", texto("tipo"), "Tipo");
  }
  if (texto("documento")) {
    const d = texto("documento")!.replace(/\D/g, "");
    if (d.length !== 11 && d.length !== 14) return { error: "CPF tem 11 dígitos e CNPJ tem 14." };
    mudar("document", d, "CPF/CNPJ");
  }
  if (texto("telefone")) mudar("phone", texto("telefone"), "Telefone");
  if (texto("email")) mudar("email", texto("email"), "E-mail");
  if (texto("chave_pix")) {
    const tipo = tipoDaChave(texto("chave_pix")!, args.tipo_chave_pix);
    if (ehErro(tipo)) return tipo;
    mudar("pix_key", texto("chave_pix"), "Chave Pix");
    mudar("pix_key_type", tipo, "Tipo da chave");
  } else if (texto("tipo_chave_pix")) {
    return { error: "Diga a chave Pix junto do tipo." };
  }
  if (texto("banco")) mudar("bank_name", texto("banco"), "Banco");
  if (texto("agencia")) mudar("bank_branch", texto("agencia"), "Agência");
  if (texto("conta")) mudar("bank_account", texto("conta"), "Conta");
  if (texto("tipo_conta")) {
    const t = normal(texto("tipo_conta"));
    if (!TIPOS_DE_CONTA.includes(t)) return { error: "Tipo de conta: corrente, poupanca ou pagamento." };
    mudar("account_type", t, "Tipo de conta");
  }
  if (texto("categoria_padrao")) {
    const cat = await categoriaValida(ctx, texto("categoria_padrao"), "payable");
    if (ehErro(cat)) return cat;
    if (cat) mudar("default_category", cat.nome, "Categoria padrão");
  }
  let ativar: boolean | null = null;
  if (typeof args.ativo === "boolean" && args.ativo !== f.active) {
    ativar = args.ativo;
    patch.active = args.ativo;
    linhas.push(args.ativo ? "*Reativar* (volta às listas)" : "*Desativar* (some das listas; o histórico fica)");
  } else if (typeof args.ativo === "boolean") {
    linhas.push(`Já está ${f.active ? "ativo" : "inativo"}.`);
  }
  if (!Object.keys(patch).length) {
    return { error: linhas.length ? `${f.name} já está ${f.active ? "ativo" : "inativo"}: nada a mudar.` : "Diga o que mudar no favorecido." };
  }
  return { patch, linhas, ativar };
}

export async function resumirFavorecido(ctx: ToolCtx, args: Record<string, unknown>): Promise<string | null> {
  const r = await acharFavorecido(ctx.admin, args);
  if (ehErro(r)) return `⚠️ ${r.error}`;
  const f = r.favorecido;
  const m = await mudancasDoFavorecido(ctx, f, args);
  if (ehErro(m)) return `⚠️ ${m.error}`;
  const linhas = [`Alterar o favorecido *${f.name}*${f.active ? "" : " (inativo)"}:`, ...m.linhas.map((l) => `- ${l}`)];
  if (m.ativar !== null) {
    const regras = await regrasDaMudanca(ctx.admin, f, m.ativar);
    if (ehErro(regras)) linhas.push(`- ⚠️ ${regras.error}`);
    else if (regras.length) {
      linhas.push(m.ativar
        ? `- Voltam a valer ${regras.length} regra(s) do extrato pausada(s) quando ele foi desativado: ${regras.map(rotuloDaRegra).join("; ")}`
        : `- Pausa ${regras.length} regra(s) do extrato que apontam para ele (senão o próximo Pix entra nele de novo): ${regras.map(rotuloDaRegra).join("; ")}`);
    } else if (!m.ativar) linhas.push("- Nenhuma regra do extrato aponta para ele.");
  }
  return linhas.join("\n");
}

export const favorecidoTools: ToolDef[] = [
  {
    name: "alterar_favorecido",
    description:
      "Edita um FAVORECIDO (sócio, funcionário, diarista, prestador, comissionado) — o mesmo formulário da tela Favorecidos: nome, " +
      "tipo, CPF/CNPJ, telefone, e-mail, chave Pix (e o tipo), banco/agência/conta, categoria padrão; e desativa (ativo=false) ou " +
      "reativa (ativo=true). 'troca o Pix da Eliane para o telefone 11 9…' (chave_pix, tipo_chave_pix=telefone), 'desativa o favorecido " +
      "Alex' (ativo=false). Desativar pausa junto as regras do extrato que apontam para ele; reativar as devolve. Só o que a pessoa " +
      "disser muda. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        favorecido: { type: "string", description: "Nome como a pessoa falou ('Eliane'). Acha também os inativos." },
        favorecido_id: { type: "string" },
        novo_nome: { type: "string" },
        tipo: { type: "string", enum: TIPOS },
        documento: { type: "string", description: "CPF ou CNPJ." },
        telefone: { type: "string" },
        email: { type: "string" },
        chave_pix: { type: "string" },
        tipo_chave_pix: { type: "string", enum: TIPOS_DE_CHAVE, description: "Se a pessoa disser; 11 dígitos sem tipo → pergunte se é CPF ou telefone." },
        banco: { type: "string" },
        agencia: { type: "string" },
        conta: { type: "string" },
        tipo_conta: { type: "string", enum: TIPOS_DE_CONTA },
        categoria_padrao: { type: "string", description: "Categoria em que TODO pagamento a ele entra." },
        ativo: { type: "boolean", description: "false = desativar; true = reativar." },
      },
    },
    risk: "medium",
    roles: CARGOS_DO_FINANCEIRO,
    preValidar(args) {
      if (!args?.favorecido && !args?.favorecido_id) return { error: "Qual favorecido? Diga o nome." };
      return null;
    },
    retratoDaPendencia: async (args, ctx) => {
      const r = await acharFavorecido(ctx.admin, args);
      return ehErro(r) ? null : { favorecido_id: r.favorecido.id };
    },
    async execute(args, ctx) {
      const b = semAcessoDoFinanceiro(ctx);
      if (b) return b;
      const r = await acharFavorecido(ctx.sb, args);
      if (ehErro(r)) return r;
      const f = r.favorecido;
      const m = await mudancasDoFavorecido(ctx, f, args);
      if (ehErro(m)) return m;
      // As regras são lidas ANTES de mudar o cadastro (o nome e o documento de agora são os que apontam).
      const regras = m.ativar === null ? [] : await regrasDaMudanca(ctx.sb, f, m.ativar);
      if (ehErro(regras)) return regras;
      const { error } = await ctx.sb.from("payees").update(m.patch).eq("id", f.id);
      if (error) {
        if (/documento_unico|duplicate key/i.test(error.message)) return { error: "Já existe um favorecido com este CPF/CNPJ." };
        return { error: `Não consegui alterar o favorecido: ${mensagemDoBanco(error)}` };
      }
      let regrasMudadas = 0;
      let aviso: string | null = null;
      const hoje = hojeEmBrasilia().split("-").reverse().join("/");
      for (const regra of regras) {
        const patch = mudancaDaRegra(regra, f, !!m.ativar, hoje);
        const { error: e } = await ctx.sb.from("finance_rules").update(patch).eq("id", regra.id);
        if (e) aviso = `O favorecido foi ${m.ativar ? "reativado" : "desativado"}, mas não consegui ${m.ativar ? "reativar" : "pausar"} todas as regras do extrato dele (${mensagemDoBanco(e)}): confira em Regras do extrato.`;
        else regrasMudadas++;
      }
      return {
        ok: true, favorecido_id: f.id,
        message: `${f.name}: ${m.linhas.join("; ").replace(/\*/g, "")}.` +
          (regrasMudadas ? ` ${regrasMudadas} regra(s) do extrato ${m.ativar ? "voltaram a valer" : "pausada(s)"}.` : ""),
        ...(aviso ? { aviso } : {}),
      };
    },
  },
];

// ── Conta a pagar com o favorecido dito (create_payable, financial.ts) ──────────────────────────

/**
 * A conta a pagar como a pessoa falou: favorecido (ou fornecedor) pelo nome, categoria e vencimento
 * ditos, OS pelo número. A mesma resolução do lançamento do Caixa: nome igual ou cortado identifica;
 * dúvida é pergunta; quem não está no cadastro vai com o nome (supplier_name, a contraparte sem
 * cadastro das contas a pagar).
 */
export async function contaAPagarDita(ctx: ToolCtx, args: Record<string, unknown>): Promise<{ linha: Record<string, unknown>; aviso: string | null } | { error: string }> {
  const valor = valorDito(args.amount);
  if (valor == null) return { error: "Qual o valor da conta a pagar?" };
  const descricao = typeof args.description === "string" ? args.description.trim() : "";
  if (!descricao) return { error: "O que é a conta a pagar? (descrição)" };
  const emissao = args.issue_date ? dataDita(args.issue_date) : hojeEmBrasilia();
  if (!emissao) return { error: `Não entendi a data "${String(args.issue_date)}".` };
  const vencimento = dataFuturaDita(args.due_date);
  if (!vencimento) return { error: `Não entendi o vencimento "${String(args.due_date ?? "")}". Use dd/mm, 'dia 10' ou a data.` };

  let payeeId: string | null = null;
  let supplierId: string | null = ehUuid(args.supplier_id) ? String(args.supplier_id) : null;
  let nomeLivre: string | null = null;
  let categoriaDoFavorecido: string | null = null;
  const dito = typeof args.favorecido === "string" ? args.favorecido.trim() : "";
  if (dito && !supplierId) {
    const [fav, forn] = await Promise.all([
      ctx.admin.from("payees").select("id, name, default_category").eq("active", true).limit(1000),
      ctx.admin.from("suppliers").select("id, name, trade_name").limit(3000),
    ]);
    if (fav.error || forn.error) return { error: `Não consegui consultar os cadastros (${mensagemDoBanco(fav.error ?? forn.error)}).` };
    const pessoas = [
      ...((fav.data ?? []) as any[]).map((p) => ({ id: p.id as string, nome: p.name as string, tipo: "favorecido", categoria: p.default_category as string | null })),
      ...((forn.data ?? []) as any[]).flatMap((s) => [
        { id: s.id as string, nome: s.name as string, tipo: "fornecedor", categoria: null },
        ...(s.trade_name ? [{ id: s.id as string, nome: s.trade_name as string, tipo: "fornecedor", categoria: null }] : []),
      ]),
    ];
    const r = escolherPorNome(dito, pessoas);
    if ("ambiguo" in r) return { error: `Qual "${dito}"? ${r.ambiguo.map((p) => `${p.nome} (${p.tipo})`).join("; ")}` };
    if ("achado" in r) {
      if (r.achado.tipo === "favorecido") { payeeId = r.achado.id; categoriaDoFavorecido = r.achado.categoria; }
      else supplierId = r.achado.id;
    } else nomeLivre = dito;
  }
  const cat = await categoriaValida(ctx, args.expense_category, "payable");
  if (ehErro(cat)) return cat;
  let osId: string | null = null;
  if (args.linked_service_order_id) {
    const o = await ordemDita(ctx.admin, args.linked_service_order_id);
    if (ehErro(o)) return o;
    osId = o.ordem.id;
  }
  return {
    linha: {
      description: descricao, issue_date: emissao, due_date: vencimento, amount: valor,
      expense_category: cat?.nome ?? categoriaDoFavorecido ?? null,
      supplier_id: supplierId, payee_id: payeeId, ...(nomeLivre ? { supplier_name: nomeLivre } : {}),
      linked_service_order_id: osId, notes: typeof args.notes === "string" && args.notes.trim() ? args.notes.trim() : null,
      balance_amount: valor, paid_amount: 0, status: "pending",
    },
    aviso: nomeLivre ? `"${nomeLivre}" não está no cadastro: a conta de ${brl.format(valor)} foi lançada com o nome, sem favorecido.` : null,
  };
}
