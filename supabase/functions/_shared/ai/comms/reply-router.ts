// Manejo de Resposta — inbound (módulo G). "Metade da conversa é a resposta que volta."
// Classifica a resposta de cliente/fornecedor para decidir o manejo: de-escalar cobrança em
// disputa, aceitar cotação parcial, responder/escalar pergunta, honrar opt-out.
// Função PURA e testável — dá um sinal determinístico ao agente (que também lê o texto).
// (Fase 5 da Agenda, 27/10/2026: classificarRespostaDoCliente, no fim, usa o extrator de datas da Fase 4.)

import { expressoesDeData, semAsDatasDitas } from "../promessa.ts";

export type IntencaoResposta =
  | "opt_out" // "pare de me mandar"
  | "disputa" // "já paguei", "serviço deu problema", cobrança indevida
  | "acordo" // "pode mandar o pix", "vou pagar", "fechado"
  | "cotacao_parcial" // fornecedor: "só tenho o item 1 e 3"
  | "pergunta" // "qual a bitola?", "vocês têm em estoque?"
  | "outro";

export interface ResultadoResposta {
  intencao: IntencaoResposta;
  manejo: string; // o que o agente deve fazer
  sinais: string[]; // trechos que dispararam
}

function norm(s: string): string {
  return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

// Ordem de precedência (do mais sensível ao menos): opt_out > disputa > acordo > parcial > pergunta.
const REGRAS: Array<{ intencao: IntencaoResposta; re: RegExp; manejo: string }> = [
  {
    intencao: "opt_out",
    re: /\b(para|pare|parar) de (me )?(mandar|enviar)|nao (quero|desejo) (mais )?(receber|mensagens)|nao me mand|descadastr|sair da lista|remover meu (numero|contato)|nunca mais|me tira/,
    manejo: "Marque opt_out_whatsapp=true no cliente/fornecedor (update_client/update_supplier) e NÃO envie mais. Confirme educadamente.",
  },
  {
    intencao: "disputa",
    re: /ja paguei|nao devo|nao reconhe|cobranca indevida|nao concordo|servico (deu problema|nao ficou|incompleto|com defeito|nao foi)|reclama|\berrad[oa]\b|cobranca errada/,
    manejo: "NÃO reenvie cobrança. De-escale e ESCALE ao dono com o contexto (o cliente contesta). Não insista.",
  },
  {
    intencao: "acordo",
    re: /pode (mandar|enviar|passar) (o )?pix|manda o pix|vou pagar|combinado|fechado|fecho|topo|pode fazer|aceito|tá certo|ta certo|de acordo|ok pode/,
    manejo: "Cliente aceitou. Siga o combinado (ex.: enviar Pix/gerar recebível) — passos de dinheiro ainda pedem sua confirmação.",
  },
  {
    intencao: "cotacao_parcial",
    re: /(so|só|apenas) (tenho|trabalho|consigo)|nao (tenho|trabalho) (o |com )|nao temos (o |esse )|item \d+ (nao|indispon)|dos itens|em falta|indisponivel|indisponível/,
    manejo: "Registre a cotação SÓ dos itens respondidos (record_quote_response) — não cobre o resto do fornecedor.",
  },
  {
    intencao: "pergunta",
    re: /\?|^\s*(qual|quanto|como|onde|quando|quais|voces tem|vocês têm|tem em estoque|qual a bitola|voltagem|amperagem|modelo|serve para|é compativel|é compatível)/,
    manejo: "Responda se souber com segurança; se for técnico/comercial que você não domina, ESCALE ao dono. Não invente.",
  },
];

export function classificarResposta(texto: string): ResultadoResposta {
  const n = norm(texto);
  for (const r of REGRAS) {
    const m = n.match(r.re);
    if (m) return { intencao: r.intencao, manejo: r.manejo, sinais: [m[0].slice(0, 40)] };
  }
  return { intencao: "outro", manejo: "Trate normalmente conforme o contexto da conversa.", sinais: [] };
}

// ── A resposta do CLIENTE à mensagem da agenda (Agenda de Produção, Fase 5, P4 — 27/10/2026) ────────────────────
// spec-fase5 §5.4 e d18: função NOVA, ao lado da de cima — classificarResposta fica byte a byte igual (o fornecedor e a
// cobrança usam a de hoje; o teste roda o corpus e compara). Sem IA, por padrão de texto; erra para o lado de NÃO
// detectar: o que não é claro vai ao dono (a agenda não responde nada ao cliente). Quem decide o efeito é o banco
// (agenda_resposta_do_cliente): o "SIM" curto é a regra única de 30/09 (_e_concordancia) e o áudio nunca confirma.
//
// Precedência: opt_out > disputa > negociacao > data > falta > remarcar > acesso > pergunta > acordo > outro.
//   · data = um dia PEDIDO: numa oração sem negação, com o jeito de pedido ("pode ser sexta?", "prefiro quarta", "deixa
//     pra semana que vem", "só quarta") ou só o dia ("Sexta."). A pergunta sobre o dia combinado ("vocês vêm amanhã?",
//     "que horas chegam amanhã?") não é pedido: é pergunta. Com "não posso quinta, pode ser sexta?", o dia é a sexta.
//   · o dia RECUSADO (numa oração com "não", ou com a falta: "vou viajar até sexta") vai em `expressao` no remarcar e na
//     falta ("essa semana" também: o banco lê a semana do dia combinado).
//   · remarcar pelo "não posso"/"não dá" só quando é sobre o dia ("não dá pra amanhã", "infelizmente não vou poder",
//     "não posso nesse dia"); "não dá pra ver o vídeo" não é.
//   · o acesso é afirmação ("a chave fica com o marinheiro"); a pergunta sobre a chave é pergunta.
// A expressão de data vem do extrator da Fase 4 (_shared/ai/promessa.ts, expressoesDeData); nada aqui calcula data.

export type IntencaoDoCliente =
  | "opt_out"
  | "disputa"
  | "negociacao"
  | "data"
  | "falta"
  | "remarcar"
  | "acesso"
  | "pergunta"
  | "acordo"
  | "outro";

export interface RespostaDoCliente {
  intencao: IntencaoDoCliente;
  /** Os trechos que dispararam (até 40 caracteres cada). */
  sinais: string[];
  /** data: o dia pedido; remarcar/falta: o dia recusado (null = o dia da mensagem). Como foi dito; o banco converte. */
  expressao: string | null;
}

/** O tamanho máximo da expressão que o banco guarda (agenda_cliente_respostas.expressao). */
export const EXPRESSAO_MAX = 60;

const OPT_OUT_SOZINHO = /^\s*(?:parar|pare|sair|stop)\s*[.!]*\s*$/;
const DISPUTA_DO_CLIENTE =
  /\bnao (?:funciona|funcionou|esta funcionando|ta funcionando|liga|ligou|carrega|carregou|segura carga)\b|\bapit|\bdesliga(?:ndo)? sozinh|\balarme\b|\bgarantia\b|\bvazando\b|\bpiorou\b|\bdefeito\b/;
const NEGOCIACAO =
  /\bdesconto\b|\babatimento\b|\bmais barato\b|\bparcel|\bpreco\b|\bvalor(?:es)?\b|\borcamento\b|\bquanto (?:fica|custa|vai ficar|sai|vai sair|e|ficou|deu)\b|\bboleto\b|\bpix\b|\bpagamento\b|\bpagar\b|\bcaro\b/;
const FALTA =
  /\bnao vou (?:poder )?estar\b|\bnao estarei\b|\bvou viajar\b|\bviajando\b|\bestarei fora\b|\bvou estar fora\b|\b(?:vai|vao) estar fora\b|\bnao (?:tem|vai ter|tera) ninguem\b/;
/** O "não posso/não dá" — só vale como remarcar quando é sobre o dia (veja `sobreODia`). */
const NAO_POSSO =
  /\bnao (?:posso|podemos|vou poder|vamos poder|consigo|conseguimos|pode ser|pode|da|dara|vai dar|vai rolar|fica bom|e bom|serve|rola)\b/;
const REMARCAR = /\boutro dia\b|\bremarc|\badiar?\b|\bmais (?:pra|para) frente\b|\boutra data\b|\boutro horario\b/;
const ACESSO =
  /\bchaves?\b|\bportaria\b|\bsecretaria\b|\bmarinheiro\b|\bvaga\b|\bno seco\b|\bna agua\b|\bgaragem\b|\btomada\b|\bcaseiro\b|\bsenha\b|\bportao\b/;
const PERGUNTA_DO_CLIENTE = /\?|^\s*(?:qual|quais|quanto|como|onde|quando|que horas|por que|porque|voces tem|tem previsao)\b/;
const ACORDO_DO_CLIENTE =
  /\b(?:sim|ok|okay|beleza|blz|combinado|fechado|certo|perfeito|pode ser|pode vir|podem vir|tudo certo|ta certo|de acordo|confirmo|confirmado|aceito)\b|👍/u;
/** O jeito de pedido de um dia ("pode ser", "prefiro", "deixa pra", "só"…). */
const PEDIDO_DE_DIA =
  /\b(?:pode ser|pode|podem|podemos|poderia|poderiam|podia|da pra|da para|daria pra|daria para|consegue|conseguem|conseguiria|seria possivel|tem como|que tal|prefiro|preferia|prefere|melhor|fica pra|fica para|ficar pra|ficar para|deixa pra|deixa para|deixar pra|deixar para|passa pra|passa para|passar pra|passar para|muda pra|muda para|mudar pra|mudar para|troca pra|troca para|trocar pra|trocar para|remarca pra|remarca para|remarcar pra|remarcar para|adia pra|adia para|adiar pra|adiar para|fica bom|ficaria bom|serve|da certo|so)\b/;
/** As palavras que podem acompanhar o dia sozinho ("Sexta.", "na sexta então", "e sexta?"). */
const SO_O_DIA = /^(?:(?:e|ou|entao|na|no|pra|para|a|o|sim|ok|pode|melhor|de manha|a tarde|cedo)\s*)*$/;
const NEGACAO_DO_CLIENTE = /\b(?:nao|nem|nunca)\b/;

function normalizarCliente(s: string): string {
  return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[ \t]+/g, " ").trim();
}

interface Oracao {
  texto: string;
  pergunta: boolean;
}

/** As orações do texto (vírgula, ponto, "?", "!", ";", quebra de linha e o "mas"), cada uma com o "?" dela. */
function oracoes(n: string): Oracao[] {
  return n
    .split(/(?<=[,;.!?\n])\s*|\s+(?=mas\b)|\s+(?=porem\b)/)
    .map((o) => o.trim())
    .filter(Boolean)
    .map((o) => ({ texto: o.replace(/[,;.!?\n]+$/g, "").trim(), pergunta: o.endsWith("?") }))
    .filter((o) => o.texto !== "");
}

/** O "não posso/não dá" é sobre o dia? (o que vem depois dele é nada, um dia, ou "nesse dia/essa semana"). */
function sobreODia(o: string, m: RegExpExecArray): boolean {
  const depois = o.slice(m.index + m[0].length).trim();
  if (!depois || /^(?:nao|mesmo|nao mesmo|infelizmente)$/.test(depois)) return true;
  if (/^(?:(?:pra|para|em|no|na) )?(?:esse|essa|este|esta|nesse|nessa|neste|nesta|o|a) (?:dia|data|semana|horario|turno)\b/.test(depois)) {
    return true;
  }
  return expressoesDeData(o, { periodo: true }).length > 0;
}

/**
 * A intenção da resposta do cliente à mensagem da agenda: {intencao, sinais, expressao}. Pura; o banco decide o efeito.
 */
export function classificarRespostaDoCliente(texto: string | null | undefined): RespostaDoCliente {
  const n = normalizarCliente(String(texto ?? ""));
  if (!n || /^\[(?:audio|image|imagem|video|document|documento|sticker|conteudo vazio)\]$/.test(n)) {
    return { intencao: "outro", sinais: [], expressao: null };
  }
  const achou = (intencao: IntencaoDoCliente, sinal: string, expressao: string | null = null): RespostaDoCliente => ({
    intencao,
    sinais: [sinal.trim().slice(0, 40)],
    expressao: expressao && expressao.length <= EXPRESSAO_MAX ? expressao : null,
  });

  // 1. opt-out: a regra de hoje (a 1ª de REGRAS) e a palavra sozinha ("PARAR", como o pós-serviço ensina)
  const opt = n.match(REGRAS[0].re) ?? n.match(OPT_OUT_SOZINHO);
  if (opt) return achou("opt_out", opt[0]);
  // 2. disputa: a de hoje (a 2ª de REGRAS) e o defeito depois do serviço
  const disp = n.match(REGRAS[1].re) ?? n.match(DISPUTA_DO_CLIENTE);
  if (disp) return achou("disputa", disp[0]);
  // 3. negociação (preço, desconto, parcela, pagamento)
  const neg = n.match(NEGOCIACAO);
  if (neg) return achou("negociacao", neg[0]);

  // 4. as datas: o dia pedido e o dia recusado, oração por oração
  const ditas = oracoes(n);
  let pedido: { expressao: string; sinal: string } | null = null;
  let recusado: string | null = null;
  for (const o of ditas) {
    // a recusa antes do jeito de pedido não nega o pedido ("se não der quinta pode ser sexta" → "pode ser sexta"); o
    // "não" colado no pedido nega ("não dá pra amanhã", "não pode ser terça")
    const p = PEDIDO_DE_DIA.exec(o.texto);
    const antes = p ? o.texto.slice(0, p.index) : "";
    const partes = p && NEGACAO_DO_CLIENTE.test(antes) && !/\b(?:nao|nem|nunca)\s*$/.test(antes)
      ? [antes, o.texto.slice(p.index)]
      : [o.texto];
    for (const parte of partes) {
      const recusa = NEGACAO_DO_CLIENTE.test(parte) || FALTA.test(parte);
      const datas = expressoesDeData(parte, { periodo: recusa });
      if (!datas.length) continue;
      if (recusa) {
        recusado ??= datas[0];
        continue;
      }
      const resto = semAsDatasDitas(parte);
      if (!pedido && (PEDIDO_DE_DIA.test(parte) || SO_O_DIA.test(resto))) pedido = { expressao: datas[0], sinal: parte };
    }
  }
  if (pedido) return achou("data", pedido.sinal, pedido.expressao);

  // 5. falta e remarcar (com o dia recusado, se disse)
  const falta = n.match(FALTA);
  if (falta) return achou("falta", falta[0], recusado);
  for (const o of ditas) {
    const m = NAO_POSSO.exec(o.texto);
    if (m && sobreODia(o.texto, m)) return achou("remarcar", m[0], recusado);
  }
  const rem = n.match(REMARCAR);
  if (rem) return achou("remarcar", rem[0], recusado);

  // 6. acesso: só o que ele AFIRMA (a pergunta sobre a chave é pergunta)
  for (const o of ditas) {
    if (o.pergunta) continue;
    const a = o.texto.match(ACESSO);
    if (a) return achou("acesso", a[0]);
  }
  // 7. pergunta, acordo, outro
  const perg = n.match(PERGUNTA_DO_CLIENTE);
  if (perg) return achou("pergunta", perg[0]);
  const ac = n.match(ACORDO_DO_CLIENTE);
  if (ac) return achou("acordo", ac[0]);
  return { intencao: "outro", sinais: [], expressao: null };
}
