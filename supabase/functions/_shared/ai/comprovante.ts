// Foto do cupom ou do comprovante vira lançamento (item 4.5 do plano "Financeiro Confiável",
// 27/09/2026).
//
// O C6 manda a compra no débito só como "DEBITO DE CARTAO", sem a loja; a loja tem de vir de
// quem pagou. Até aqui era por texto ("paguei 64,80 no débito no posto"). Agora a foto do cupom
// basta: o webhook lê a imagem (whatsapp-read-media, finalidade "auto"), e quando é comprovante
// a primeira linha sai num formato fixo — loja, CNPJ, data, total e forma de pagamento. O
// assistente mostra o que entendeu e, com o "sim", anota (casa com a linha do banco quando ela
// chegar) ou lança no Caixa. Nada é lançado sem o "sim" (decisão do plano: sempre confirmar).

/** O que o modelo de leitura extrai do cupom ou comprovante. */
export interface Comprovante {
  loja: string | null;
  /** CNPJ (14 dígitos) ou CPF (11) de quem RECEBEU — só os dígitos. */
  cnpj: string | null;
  /** 'AAAA-MM-DD' */
  data: string | null;
  total: number | null;
  pagamento: 'debito' | 'credito' | 'pix' | 'dinheiro' | 'boleto' | null;
  /** As linhas de itens que vieram depois da linha do comprovante. */
  itens: string[];
}

/**
 * A foto só é lida quando vem de quem usa o financeiro. Foto de técnico é do serviço (vai para a
 * OS por attach_photo_to_service_order) e não precisa passar pela leitura — nem gastar com ela.
 */
export function fotoDeQuemUsaOFinanceiro(cargo?: string | null): boolean {
  return cargo === "admin" || cargo === "financial";
}

/** O pedido ao modelo de leitura quando a imagem vem de quem usa o financeiro. */
export const PEDIDO_DE_LEITURA_AUTO = `Você recebeu uma imagem ou PDF enviado pelo WhatsApp por alguém da empresa.

1) Se for CUPOM FISCAL, NOTA FISCAL, RECIBO ou COMPROVANTE DE PAGAMENTO (cartão, Pix, boleto ou dinheiro), responda na PRIMEIRA linha exatamente neste formato, sem nada antes:
COMPROVANTE | loja: <nome do estabelecimento ou de quem recebeu> | cnpj: <os dígitos do CNPJ ou CPF de quem RECEBEU, ou não informado> | data: <dd/mm/aaaa, ou não informada> | total: <valor total pago, com vírgula nos centavos, ex. 64,80> | pagamento: <débito, crédito, pix, dinheiro, boleto ou não informado>
Depois, em até 5 linhas, os itens principais no formato "- <item> | R$ <valor>".
Regras: NÃO invente. O que não estiver legível no documento é "não informado". O total é o valor PAGO (com desconto), não a soma dos itens se houver diferença. "Cartão de débito"/"débito" é débito; "cartão de crédito"/"crédito" é crédito; Pix pago com cartão de crédito ("Pix no crédito") é crédito.
O CNPJ/CPF é o de quem RECEBEU o dinheiro (a loja, o recebedor do Pix, o beneficiário do boleto) — nunca o de quem pagou.
Nota fiscal (NF-e/DANFE) só prova pagamento se disser que foi paga à vista: com duplicatas ou vencimentos (compra a prazo), escreva "pagamento: não informado" e, na linha dos itens, "- compra a prazo | vencimentos: <datas>".

2) Se NÃO for comprovante (por exemplo, cotação de fornecedor ou foto de equipamento), extraia o conteúdo em português, de forma compacta e fiel. Se houver itens com preços, liste um por linha: "- <descrição> | unitário: R$ <valor> | prazo: <prazo se houver>". Se não for cotação, resuma em até 5 linhas.

Responda só com o conteúdo, sem preâmbulo.`;

const PAGAMENTOS: Record<string, Comprovante['pagamento']> = {
  'debito': 'debito', 'débito': 'debito',
  'credito': 'credito', 'crédito': 'credito',
  'pix': 'pix', 'dinheiro': 'dinheiro', 'boleto': 'boleto',
};

const naoInformado = (v: string) => /^n[ãa]o\s+informad[oa]$/i.test(v.trim()) || v.trim() === '';

/** 'dd/mm/aaaa' → 'AAAA-MM-DD'; null quando não é uma data válida. */
function dataDoCupom(v: string): string | null {
  const m = v.trim().match(/^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})$/);
  if (!m) return null;
  const ano = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
  const mes = Number(m[2]);
  const dia = Number(m[1]);
  const d = new Date(Date.UTC(ano, mes - 1, dia));
  if (d.getUTCFullYear() !== ano || d.getUTCMonth() !== mes - 1 || d.getUTCDate() !== dia) return null;
  return `${ano}-${String(mes).padStart(2, '0')}-${String(dia).padStart(2, '0')}`;
}

/** '1.234,56' ou '64,80' ou 'R$ 64,80' → número; null quando não dá para ler. */
function valorDoCupom(v: string): number | null {
  const limpo = v.replace(/R\$\s*/i, '').trim();
  if (!/^\d{1,3}(\.\d{3})*,\d{2}$|^\d+,\d{2}$|^\d+(\.\d{2})?$/.test(limpo)) return null;
  const n = limpo.includes(',') ? Number(limpo.replace(/\./g, '').replace(',', '.')) : Number(limpo);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/**
 * Lê o texto que o modelo devolveu. Devolve null quando a imagem não é comprovante (a primeira
 * linha não começa com "COMPROVANTE |") — aí nada muda no que o assistente recebe.
 */
export function lerComprovante(texto: string): Comprovante | null {
  const linhas = texto.replace(/^📷\s*/, '').split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (linhas.length === 0 || !/^COMPROVANTE\s*\|/i.test(linhas[0])) return null;
  const campos = new Map<string, string>();
  for (const parte of linhas[0].split('|').slice(1)) {
    const i = parte.indexOf(':');
    if (i < 0) continue;
    campos.set(parte.slice(0, i).trim().toLowerCase(), parte.slice(i + 1).trim());
  }
  const loja = campos.get('loja') ?? '';
  const cnpj = (campos.get('cnpj') ?? '').replace(/\D/g, '');
  const pagamento = (campos.get('pagamento') ?? '').toLowerCase();
  // Nota de compra a prazo não prova pagamento: a linha vem primeiro (não se perde no corte de 5
  // itens) e a forma de pagamento fica em branco, mesmo que o modelo tenha escrito "boleto".
  const todos = linhas.slice(1).filter((l) => l.startsWith('-'));
  const aPrazo = todos.find((l) => /compra a prazo/i.test(l));
  const itens = (aPrazo ? [aPrazo, ...todos.filter((l) => l !== aPrazo)] : todos).slice(0, 5);
  return {
    loja: naoInformado(loja) ? null : loja,
    cnpj: cnpj.length === 14 || cnpj.length === 11 ? cnpj : null,
    data: dataDoCupom(campos.get('data') ?? ''),
    total: valorDoCupom(campos.get('total') ?? ''),
    pagamento: aPrazo ? null : PAGAMENTOS[pagamento] ?? null,
    itens,
  };
}

/**
 * A legenda que a pessoa escreveu na foto ou no PDF. Não é legenda o marcador que o webhook grava
 * quando não há texto ("[image]") nem o nome do arquivo, que o WhatsApp manda no lugar da
 * legenda de um PDF ("comprovante.pdf").
 */
export function legendaDaMidia(texto?: string | null): string | null {
  const t = (texto ?? '').trim();
  if (!t || /^\[(image|document|imagem|documento)\]/i.test(t)) return null;
  if (/^\S+\.(pdf|jpe?g|png|heic|webp)$/i.test(t)) return null;
  return t;
}

/**
 * O documento lido é o da própria empresa (quem PAGOU, num comprovante de Pix): não é de quem
 * recebeu e não identificaria ninguém — sai. `raiz` são os 8 primeiros dígitos do CNPJ da empresa.
 */
export function semODocumentoDaEmpresa(c: Comprovante, raiz: string | null | undefined): Comprovante {
  return c.cnpj && raiz && raiz.length === 8 && c.cnpj.length === 14 && c.cnpj.startsWith(raiz) ? { ...c, cnpj: null } : c;
}

const brl = (v: number) => v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
const cnpjFormatado = (c: string) => c.length === 11
  ? `CPF ${c.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4')}`
  : `CNPJ ${c.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, '$1.$2.$3/$4-$5')}`;
const dataFormatada = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}/${d.slice(0, 4)}`;
const COMO_FOI_PAGO: Record<NonNullable<Comprovante['pagamento']>, string> = {
  debito: 'no débito', credito: 'no crédito', pix: 'por Pix', dinheiro: 'em dinheiro', boleto: 'por boleto',
};

/**
 * A mensagem que o assistente recebe no lugar de "[image]": o que a foto diz, em uma frase, com a
 * legenda que a pessoa escreveu (ela manda sobre a foto — "almoço da equipe", "é da OS-60").
 */
export function mensagemDoComprovante(c: Comprovante, legenda?: string | null): string {
  const valor = c.total != null ? brl(c.total) : 'valor não informado';
  const loja = c.loja ? `em ${c.loja}${c.cnpj ? ` (${cnpjFormatado(c.cnpj)})` : ''}` : 'loja não informada';
  const partes: string[] = [`${valor} ${loja}`];
  partes.push(c.data ? `em ${dataFormatada(c.data)}` : 'data não informada');
  partes.push(c.pagamento ? `pago ${COMO_FOI_PAGO[c.pagamento]}` : 'forma de pagamento não informada');
  const linhas = [`📷 Comprovante enviado por foto: ${partes.join(', ')}.`];
  if (c.itens.length) linhas.push(`Itens: ${c.itens.map((i) => i.replace(/^-\s*/, '')).join('; ')}`);
  const texto = legendaDaMidia(legenda);
  if (texto) linhas.push(`Legenda: ${texto}`);
  return linhas.join('\n');
}
