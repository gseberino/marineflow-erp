// Quem é a outra ponta de uma linha do extrato — fornecedor, favorecido ou cliente.
//
// Medido em 25/09/2026 na fila do Extrato: das 47 saídas, 3 chegavam com fornecedor e
// NENHUMA com favorecido; das 24 entradas, 1 com cliente — embora quase todas trouxessem
// CPF/CNPJ inteiro. Havia três motivos:
//   * favorecido e cliente só eram procurados pelo documento, e cliente por nome só se o
//     nome fosse idêntico em maiúsculas;
//   * o que o dono JÁ decidiu não era usado: a EQUIT pagou em nome do cliente Acrisio, a
//     TECHVODA em nome do Bruno — e a próxima entrada deles chegava sem cliente de novo;
//   * a identificação só rodava quando a proposta nascia. A MP Motorhomes foi cadastrada
//     depois, com o mesmo CNPJ, e seis entradas dela continuaram sem cliente.
//
// Aqui fica UM identificador para os dois lados, com a evidência escrita. A ordem é a da
// força da prova, e a trava do caso Coremma continua valendo: nome "parecido" nunca decide
// em silêncio — vira sugestão marcada para conferir.
import { normalizeText } from "./matching.ts";

export type TipoDeEvidencia =
  | "documento"        // CPF/CNPJ igual ao do cadastro
  | "conta_bancaria"   // banco, agência e conta iguais aos do favorecido
  | "historico"        // o mesmo documento já foi lançado para este cadastro
  | "nome_identico"    // nome igual, sem acento, caixa e sufixo societário
  | "nome_cortado"     // o nome do extrato é o do cadastro cortado pelo banco (~30 letras)
  | "nome_parecido"    // NÃO É MAIS PRODUZIDO (decisão do dono, 26/09/2026); fica para ler linhas antigas
  | "regra"            // uma regra sua aponta o cadastro
  | "vinculo";         // é o dono da conta/OS que a linha paga

export const ROTULO_DA_EVIDENCIA: Record<TipoDeEvidencia, string> = {
  documento: "CPF/CNPJ",
  conta_bancaria: "conta bancária",
  historico: "lançamentos anteriores",
  nome_identico: "nome idêntico",
  nome_cortado: "nome cortado pelo banco — confira",
  nome_parecido: "nome parecido — confira",
  regra: "regra sua",
  vinculo: "o que ela paga",
};

export type TipoDeCadastro = "fornecedor" | "favorecido" | "cliente";

export interface Reconhecimento {
  id: string;
  nome: string;
  por: TipoDeEvidencia;
  /** Frase para a linha: "CNPJ confere com MP MOTOR HOMES". */
  detalhe: string;
}

export interface Identificacao {
  fornecedor: Reconhecimento | null;
  favorecido: Reconhecimento | null;
  cliente: Reconhecimento | null;
  /** O documento pertence a um cadastro de OUTRO tipo (ex.: CPF de cliente numa saída). */
  outroCadastro: { tipo: TipoDeCadastro; id: string; nome: string } | null;
  /** Nada reconheceu e há o que cadastrar — já com o que o extrato traz. */
  cadastrar: { tipo: TipoDeCadastro; documento: string | null; nome: string | null } | null;
  /** Nome para mostrar quando o banco não mandou nome (sai do cadastro do documento). */
  nomeConhecido: string | null;
}

export interface TxParaIdentificar {
  transaction_type: "credit" | "debit";
  description?: string | null;
  counterparty_name?: string | null;
  counterparty_document?: string | null;
  counterparty_branch?: string | null;
  counterparty_account?: string | null;
}

export interface CadastroParaIdentificar {
  fornecedores: Array<{ id: string; name: string; trade_name?: string | null; cnpj_cpf?: string | null }>;
  favorecidos: Array<{ id: string; name: string; document?: string | null; bank_branch?: string | null; bank_account?: string | null }>;
  clientes: Array<{ id: string; name: string; cpf_cnpj?: string | null }>;
  /** Uma linha por lançamento já feito a partir do extrato (sem cadastro também conta). */
  historico: Array<{
    documento: string | null;
    lado: "saida" | "entrada";
    supplier_id?: string | null; payee_id?: string | null; client_id?: string | null;
  }>;
}

interface Entrada { id: string; nome: string; limpo: string; tokens: string[]; documento?: string }

interface HistoricoDoDocumento {
  saida: { total: number; fornecedor: Map<string, number>; favorecido: Map<string, number> };
  entrada: { total: number; cliente: Map<string, number> };
}

export interface IndiceDeContrapartes {
  fornecedorPorDoc: Map<string, Entrada>;
  favorecidoPorDoc: Map<string, Entrada>;
  clientePorDoc: Map<string, Entrada>;
  favorecidoPorConta: Map<string, Entrada>;
  fornecedores: Entrada[];
  favorecidos: Entrada[];
  clientes: Entrada[];
  /** documento → quem ele já foi, por sentido, com contagem e total de lançamentos. */
  historico: Map<string, HistoricoDoDocumento>;
  porId: { fornecedor: Map<string, Entrada>; favorecido: Map<string, Entrada>; cliente: Map<string, Entrada> };
}

const digitos = (s: string | null | undefined) => String(s ?? "").replace(/\D/g, "");

/**
 * CPF/CNPJ só com dígitos, com o zero à esquerda que a planilha comeu: CNPJ gravado com 13
 * dígitos ("2559947000324") e CPF com 10 são o mesmo documento com o zero perdido. Sem isto
 * o MESMO documento "contradizia" a si mesmo e o cadastro certo deixava de ser reconhecido.
 */
export function documentoNormalizado(s: string | null | undefined): string {
  const d = digitos(s);
  if (d.length === 13) return d.padStart(14, "0");
  if (d.length === 10) return d.padStart(11, "0");
  return d;
}

/**
 * O extrato e o cadastro têm documento, e eles NÃO são da mesma pessoa ou empresa: o nome
 * igual não vale. CPF contra CNPJ nunca é o mesmo; CNPJ contra CNPJ compara a raiz (matriz e
 * filiais são a mesma empresa); CPF contra CPF, o número inteiro. Sem documento de um dos
 * lados, não há o que contradizer.
 */
export function documentoContradiz(doExtrato: string | null | undefined, doCadastro: string | null | undefined): boolean {
  const a = documentoNormalizado(doExtrato);
  const b = documentoNormalizado(doCadastro);
  if (a.length < 11 || b.length < 11) return false;
  if (a.length !== b.length) return true;
  return a.length === 14 ? a.slice(0, 8) !== b.slice(0, 8) : a !== b;
}

/** Palavras que não identificam ninguém. */
const VAZIAS = new Set(["DE", "DA", "DO", "DAS", "DOS", "E", "LTDA", "ME", "EPP", "EIRELI", "SA", "S", "A", "CIA", "COMERCIO", "SERVICOS"]);

/** Nome sem acento, caixa, pontuação e sufixo societário. */
export function nomeLimpo(s: string | null | undefined): string {
  // "(Lisiane)" em "Thaline Soares Mendonça (Lisiane)" é anotação de quem cadastrou, não nome.
  return normalizeText(String(s ?? "").replace(/\([^)]*\)/g, " "))
    .replace(/\b(LTDA|ME|EPP|EIRELI|SA|S A|CIA)\b/g, " ")
    // "65.010.587 CRISLAINE…" — MEI traz a raiz do CNPJ no começo do nome. Só esse formato:
    // apagar qualquer número tornava "idênticos" nomes diferentes ("2 IRMAOS" e "IRMAOS").
    .replace(/^\d{2} ?\d{3} ?\d{3}(?: ?\d{4} ?\d{2})? +/, "")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * O nome que está DENTRO da descrição, quando o banco não manda o nome à parte.
 * "Pix enviado para JOSE CARLOS ABEL" → "JOSE CARLOS ABEL". Sem isto metade das linhas do
 * Nubank chegava sem nome e não podia ser reconhecida nem cadastrada.
 */
export function nomeDaDescricao(descricao: string | null | undefined): string | null {
  const m = String(descricao ?? "").trim().match(
    /^(?:pix|ted|doc|transf(?:er[eê]ncia)?|transfer[eê]ncia pix)\s+(?:enviad[oa]|recebid[oa]|realizad[oa])\s+(?:para|de|por)\s+(.{3,})$/i,
  );
  return m ? m[1].trim() : null;
}

function palavras(limpo: string): string[] {
  return limpo.split(" ").filter((p) => p.length >= 3 && !VAZIAS.has(p));
}

function entrada(id: string, nome: string, documento?: string | null): Entrada {
  const limpo = nomeLimpo(nome);
  const d = documentoNormalizado(documento);
  return { id, nome, limpo, tokens: palavras(limpo), documento: d.length >= 11 ? d : undefined };
}

/** Chave da conta: agência + conta só com dígitos. Conta curta demais não identifica. */
function chaveDaConta(agencia: string | null | undefined, conta: string | null | undefined): string | null {
  const c = digitos(conta);
  if (c.length < 4) return null;
  // Zero à esquerda some: um banco manda "0001", outro manda "1" para a mesma agência.
  return `${digitos(agencia).replace(/^0+/, "")}|${c.replace(/^0+/, "")}`;
}

export function indexarContrapartes(c: CadastroParaIdentificar): IndiceDeContrapartes {
  const idx: IndiceDeContrapartes = {
    fornecedorPorDoc: new Map(), favorecidoPorDoc: new Map(), clientePorDoc: new Map(),
    favorecidoPorConta: new Map(),
    fornecedores: [], favorecidos: [], clientes: [],
    historico: new Map(),
    porId: { fornecedor: new Map(), favorecido: new Map(), cliente: new Map() },
  };
  for (const f of c.fornecedores) {
    const e = entrada(f.id, f.name, f.cnpj_cpf);
    idx.fornecedores.push(e);
    if (f.trade_name) idx.fornecedores.push({ ...entrada(f.id, f.trade_name, f.cnpj_cpf), nome: f.name });
    idx.porId.fornecedor.set(f.id, e);
    const d = documentoNormalizado(f.cnpj_cpf);
    // Primeiro cadastro vence: dois cadastros com o mesmo documento é erro de cadastro, e
    // trocar qual deles ganha mudaria a identificação sem aviso.
    if (d.length >= 11 && !idx.fornecedorPorDoc.has(d)) idx.fornecedorPorDoc.set(d, e);
  }
  for (const f of c.favorecidos) {
    const e = entrada(f.id, f.name, f.document);
    idx.favorecidos.push(e);
    idx.porId.favorecido.set(f.id, e);
    const d = documentoNormalizado(f.document);
    if (d.length >= 11 && !idx.favorecidoPorDoc.has(d)) idx.favorecidoPorDoc.set(d, e);
    const k = chaveDaConta(f.bank_branch, f.bank_account);
    if (k && !idx.favorecidoPorConta.has(k)) idx.favorecidoPorConta.set(k, e);
  }
  for (const cl of c.clientes) {
    const e = entrada(cl.id, cl.name, cl.cpf_cnpj);
    idx.clientes.push(e);
    idx.porId.cliente.set(cl.id, e);
    const d = documentoNormalizado(cl.cpf_cnpj);
    if (d.length >= 11 && !idx.clientePorDoc.has(d)) idx.clientePorDoc.set(d, e);
  }
  const soma = (m: Map<string, number>, id: string) => m.set(id, (m.get(id) ?? 0) + 1);
  for (const h of c.historico) {
    const d = documentoNormalizado(h.documento);
    if (d.length < 11) continue;
    const reg: HistoricoDoDocumento = idx.historico.get(d) ?? {
      saida: { total: 0, fornecedor: new Map(), favorecido: new Map() },
      entrada: { total: 0, cliente: new Map() },
    };
    if (h.lado === "saida") {
      reg.saida.total += 1;
      if (h.supplier_id) soma(reg.saida.fornecedor, h.supplier_id);
      if (h.payee_id) soma(reg.saida.favorecido, h.payee_id);
    } else {
      reg.entrada.total += 1;
      if (h.client_id) soma(reg.entrada.cliente, h.client_id);
    }
    idx.historico.set(d, reg);
  }
  return idx;
}

/**
 * Histórico só decide quando é UNÂNIME: TODO lançamento deste documento, neste sentido, foi
 * para o mesmo cadastro — contando os que ficaram sem cadastro.
 *
 * Contar só os preenchidos propagaria erro antigo: o CPF do Felipe foi lançado duas vezes
 * com o fornecedor "VIA S.A." (casamento errado de nome, de antes da trava) e duas sem
 * ninguém. Metade não é prática da casa; é acidente.
 */
function unanime(m: Map<string, number>, total: number): { id: string; vezes: number } | null {
  if (m.size !== 1 || total === 0) return null;
  const [[id, vezes]] = [...m.entries()];
  return vezes === total ? { id, vezes } : null;
}

/**
 * Nome idêntico, e só um cadastro com esse nome — se dois têm, escolher seria sorteio. Nome
 * igual com documento diferente é homônimo, não a mesma pessoa.
 */
function porNomeIdentico(lista: Entrada[], limpo: string, doc: string): Entrada | null {
  if (!limpo) return null;
  // Por EMPRESA: matriz e filial (mesma raiz de CNPJ) são uma só; entre elas, sempre a de
  // menor documento. Duas empresas com o mesmo nome é empate.
  const empresa = (e: Entrada) => (e.documento?.length === 14 ? `raiz:${e.documento.slice(0, 8)}` : `id:${e.id}`);
  const porEmpresa = new Map<string, Entrada>();
  for (const e of lista) {
    if (e.limpo !== limpo || documentoContradiz(doc, e.documento)) continue;
    const k = empresa(e);
    const atual = porEmpresa.get(k);
    if (!atual || (e.documento ?? "").localeCompare(atual.documento ?? "") < 0) porEmpresa.set(k, e);
  }
  return porEmpresa.size === 1 ? [...porEmpresa.values()][0] : null;
}

function reconhecer(e: Entrada, por: TipoDeEvidencia, detalhe: string): Reconhecimento {
  return { id: e.id, nome: e.nome, por, detalhe };
}

export function identificarContraparte(tx: TxParaIdentificar, idx: IndiceDeContrapartes): Identificacao {
  const doc = documentoNormalizado(tx.counterparty_document);
  const temDoc = doc.length >= 11;
  const tipoDoc = doc.length === 14 ? "CNPJ" : "CPF";
  const nomeDoExtrato = (tx.counterparty_name ?? "").trim() || nomeDaDescricao(tx.description);
  const limpo = nomeLimpo(nomeDoExtrato);
  const historico = temDoc ? idx.historico.get(doc) : undefined;
  const saida = tx.transaction_type === "debit";

  const r: Identificacao = {
    fornecedor: null, favorecido: null, cliente: null,
    outroCadastro: null, cadastrar: null, nomeConhecido: null,
  };

  // O nome que o banco não mandou, pelo cadastro do documento (qualquer tipo).
  if (temDoc && !nomeDoExtrato) {
    r.nomeConhecido = (idx.favorecidoPorDoc.get(doc) ?? idx.fornecedorPorDoc.get(doc) ?? idx.clientePorDoc.get(doc))?.nome ?? null;
  }

  if (saida) {
    // 1. Documento.
    if (temDoc) {
      const fav = idx.favorecidoPorDoc.get(doc);
      if (fav) r.favorecido = reconhecer(fav, "documento", `${tipoDoc} confere com o favorecido ${fav.nome}`);
      const forn = idx.fornecedorPorDoc.get(doc);
      if (forn) r.fornecedor = reconhecer(forn, "documento", `${tipoDoc} confere com o fornecedor ${forn.nome}`);
    }
    // 2. Conta bancária do favorecido.
    if (!r.favorecido) {
      const k = chaveDaConta(tx.counterparty_branch, tx.counterparty_account);
      const fav = k ? idx.favorecidoPorConta.get(k) : undefined;
      // Mesma agência e conta, mas CPF de outra pessoa: é conta de outro banco com o mesmo número.
      if (fav && !documentoContradiz(doc, fav.documento)) r.favorecido = reconhecer(fav, "conta_bancaria", `Conta bancária igual à do favorecido ${fav.nome}`);
    }
    // 3. O que já se lançou para este documento — só se sempre foi o mesmo, e só se o
    //    cadastro não tem documento de OUTRO tipo. Um Pix ao CPF do Ricardo foi lançado uma
    //    vez com o fornecedor "VIA S.A." (Casas Bahia, CNPJ): repetir isso seria propagar
    //    erro antigo com cara de prática da casa.
    if (!r.favorecido && !r.fornecedor && historico) {
      const fav = unanime(historico.saida.favorecido, historico.saida.total);
      const forn = unanime(historico.saida.fornecedor, historico.saida.total);
      const compativel = (e: Entrada | undefined) => !!e && !documentoContradiz(doc, e.documento);
      const e0 = fav ? idx.porId.favorecido.get(fav.id) : undefined;
      const f0 = forn ? idx.porId.fornecedor.get(forn.id) : undefined;
      const e = compativel(e0) ? e0 : undefined;
      const f = compativel(f0) ? f0 : undefined;
      if (e && fav) r.favorecido = reconhecer(e, "historico", `Este ${tipoDoc} já foi lançado ${fav.vezes}× para ${e.nome}`);
      else if (f && forn) r.fornecedor = reconhecer(f, "historico", `Este ${tipoDoc} já foi lançado ${forn.vezes}× para ${f.nome}`);
    }
    // 4. Nome idêntico. Documento de pessoa (CPF) procura favorecido antes de fornecedor.
    if (!r.favorecido && !r.fornecedor && limpo) {
      const fav = porNomeIdentico(idx.favorecidos, limpo, doc);
      const forn = fav ? null : porNomeIdentico(idx.fornecedores, limpo, doc);
      if (fav) r.favorecido = reconhecer(fav, "nome_identico", `Nome idêntico ao do favorecido ${fav.nome}`);
      else if (forn) r.fornecedor = reconhecer(forn, "nome_identico", `Nome idêntico ao do fornecedor ${forn.nome}`);
    }
    // Nome PARECIDO não identifica ninguém (decisão do dono, 26/09/2026: "o sistema nunca pode
    // sugerir ou lançar alguma transação com nomes diferentes"). Sem documento, conta, histórico
    // do mesmo documento ou nome igual, quem decide é a pessoa.
    if (!r.favorecido && !r.fornecedor) {
      const cli = temDoc ? idx.clientePorDoc.get(doc) : undefined;
      if (cli) r.outroCadastro = { tipo: "cliente", id: cli.id, nome: cli.nome };
      // Cadastrar só quando há documento: estabelecimento de maquininha sem CNPJ não vira
      // fornecedor, e propor isso em cada cafezinho seria ruído.
      if (temDoc) {
        r.cadastrar = {
          tipo: doc.length === 14 ? "fornecedor" : "favorecido",
          documento: doc,
          nome: nomeDoExtrato ?? cli?.nome ?? null,
        };
      }
    }
    return r;
  }

  // ── Entrada: de qual cliente veio ──
  if (temDoc) {
    const cli = idx.clientePorDoc.get(doc);
    if (cli) r.cliente = reconhecer(cli, "documento", `${tipoDoc} confere com o cliente ${cli.nome}`);
  }
  if (!r.cliente && historico) {
    const u = unanime(historico.entrada.cliente, historico.entrada.total);
    const cli = u ? idx.porId.cliente.get(u.id) : undefined;
    if (cli && u) {
      r.cliente = reconhecer(cli, "historico",
        `Este ${tipoDoc} já pagou ${u.vezes}× em nome de ${cli.nome}`);
    }
  }
  if (!r.cliente && limpo) {
    const cli = porNomeIdentico(idx.clientes, limpo, doc);
    if (cli) r.cliente = reconhecer(cli, "nome_identico", `Nome idêntico ao do cliente ${cli.nome}`);
  }
  if (!r.cliente) {
    const outro = temDoc ? (idx.favorecidoPorDoc.get(doc) ?? idx.fornecedorPorDoc.get(doc)) : undefined;
    if (outro) {
      r.outroCadastro = {
        tipo: idx.favorecidoPorDoc.get(doc) ? "favorecido" : "fornecedor",
        id: outro.id, nome: outro.nome,
      };
    }
    if (temDoc || nomeDoExtrato) {
      r.cadastrar = { tipo: "cliente", documento: temDoc ? doc : null, nome: nomeDoExtrato ?? outro?.nome ?? null };
    }
  }
  return r;
}

/** As frases de evidência, para o "por que o sistema propôs isto". */
export function frasesDaIdentificacao(i: Identificacao): string[] {
  const f: string[] = [];
  for (const rec of [i.fornecedor, i.favorecido, i.cliente]) if (rec) f.push(rec.detalhe);
  if (i.outroCadastro) {
    const tipo = { fornecedor: "fornecedor", favorecido: "favorecido", cliente: "cliente" }[i.outroCadastro.tipo];
    f.push(`O documento é do ${tipo} ${i.outroCadastro.nome}`);
  }
  if (i.nomeConhecido) f.push(`O banco não mandou o nome; pelo documento é ${i.nomeConhecido}`);
  return f;
}
