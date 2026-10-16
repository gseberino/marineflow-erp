// "Me acorde se" (secretário, Passo 4, P4.2, 16/10/2026): o detector e o trabalho completo, puros — sem banco
// e sem IA. Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md §3.
//
// Quem chama (acompanhar-conversas, a cada 15 min — D10) lê o banco, passa as conversas de HOJE de quem espera
// resposta e registra no portão (aviso_registrar). EM SOMBRA NADA É ENVIADO: o portão guarda o texto exato que
// sairia. O acorde de cliente acontece quando:
//   · cliente cadastrado (não genérico) com pressa ("hoje", "urgente"…) ou "quero fechar" → há 30 min ou mais
//     sem resposta da HBR (voz_unica_regras.acorde_espera_min);
//   · contato sem cadastro (lead, ou "Cliente Final"): pressa COM pedido ("?", "consegue", "quanto",
//     "orçamento"…) ou "quero fechar" → idem;
//   · qualquer um que escreveu que fechou com outra empresa ou desistiu → na hora (D2: acorda só com orçamento
//     aberto de R$ 5 mil ou mais; sem ele, vai na próxima mensagem fixa).
// Fica de fora: fornecedor, a equipe, condicional ("se aprovado…"), mensagem de ontem (a manhã das 07:30 já a mostra)
// e, SÓ para a pressa sem "fechar", a conversa de todo dia (o dono escreveu em 4+ dos últimos 7 dias): "hoje" numa
// conversa diária é rotina, mas "quero fechar hoje" e "fechei com outra" numa negociação ativa são justamente o caso
// (ensaio de 16/10: em 07/10 o dono tinha escrito ao Miguel em 4 dos 7 dias; com a exclusão geral, o caso que motivou o
// "me acorde se" não acordaria).
//
// O trabalho completo, montado do banco: o trecho literal (a frase com a palavra, até 160 caracteres; o áudio
// já vem transcrito), há quanto tempo ele espera, o orçamento aberto (número, valor, sinal pela condição do
// orçamento — a mesma conta do PDF — e validade), "Ligue agora: <número>" (D9) e, com o dono livre e depois
// das 09:30, o cartão: *sim* = mando o PDF do orçamento com a legenda pronta; *não* = deixo com você.
// Também aqui: os textos dos acordes de golpe, certificado, NF-e rejeitada e sistema fora do ar.

import { brl, ddmm, umaLinha } from "../secretario/base.ts";
import { COM_PRESSA, CONDICIONAL, PEDE_PRECO, PEDIDO_DE_LEAD, QUER_FECHAR } from "../secretario/palavras.ts";
import { diaBR, horaBR } from "../pdf/datas.ts";
import { contatoEncerrou } from "../whatsapp/contato-encerrou.ts";
import { acordeComCartao } from "./janela.ts";
import type { AvisoDaFonte, RegrasDaVozUnica } from "./portao.ts";

/** Sem acento, minúsculo, sem cortar o tamanho e SEM perder o "?" (o paraBusca corta em 120 e tira o "?"). */
export function normalizar(s: string | null | undefined): string {
  return String(s ?? "")
    .replace(/^\s*🎤\s*/u, "")
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\?/g, " ? ")
    .replace(/[^a-z0-9? ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export type Gatilho = "fechar_hoje" | "fechar" | "pressa" | "desistencia";

/**
 * A palavra que acorda, numa mensagem. `cliente` = cadastrado e não genérico (pressa basta); senão, lead (a pressa
 * precisa de um pedido). null = não acorda.
 */
export function gatilhoDaMensagem(body: string | null | undefined, cliente: boolean): Gatilho | null {
  const bruto = String(body ?? "").trim();
  if (!bruto || /^\[(audio|image|video|document|conteúdo vazio)\]$/.test(bruto)) return null;
  if (contatoEncerrou(bruto)) return "desistencia";
  const t = normalizar(bruto);
  if (CONDICIONAL.test(t)) return null;
  const fechar = QUER_FECHAR.test(t);
  const pressa = COM_PRESSA.test(t);
  if (fechar && pressa) return "fechar_hoje";
  if (fechar) return "fechar";
  if (!pressa) return null;
  if (cliente) return "pressa";
  return PEDIDO_DE_LEAD.test(t) || PEDE_PRECO.test(t) ? "pressa" : null;
}

/** A frase da mensagem que tem a palavra (até 160 caracteres, sem o 🎤 do áudio); sem achar, o começo. */
export function trechoDoGatilho(body: string | null | undefined, gatilho: Gatilho): string {
  const bruto = String(body ?? "").replace(/^\s*🎤\s*/u, "").replace(/\s+/g, " ").trim();
  const frases = bruto.split(/(?<=[.!?])\s+/).filter(Boolean);
  const tem = (f: string) => {
    if (gatilho === "desistencia") return contatoEncerrou(f);
    const t = normalizar(f);
    if (gatilho === "fechar") return QUER_FECHAR.test(t);
    return COM_PRESSA.test(t);
  };
  const achada = frases.find(tem) ?? bruto;
  return umaLinha(achada, 160);
}

export interface Recebida {
  em: string;
  body: string | null;
}

/** A conversa de quem espera resposta, como o detector a vê (montada por quem chama). */
export interface ConversaDoAcorde {
  phone: string;
  nome: string;
  /** cliente cadastrado e não genérico ("Cliente Final" conta como lead) */
  cliente: boolean;
  fornecedor: boolean;
  client_id: string | null;
  /** a última mensagem da HBR para ele (qualquer dia); null = nunca */
  ultimaSaidaEm: string | null;
  /** as recebidas (qualquer ordem; o detector só olha as de hoje que ninguém respondeu) */
  recebidas: Recebida[];
  /** em quantos dos últimos 7 dias o dono mandou mensagem para ele (4+ = conversa de todo dia) */
  diasComMensagemSua: number;
}

export interface Disparo {
  /** pressa/fechar (espera os minutos) ou desistência (na hora) */
  tipo: "pressa" | "desistencia";
  gatilho: Gatilho;
  mensagem: Recebida;
  trecho: string;
  /** há quantos minutos a mensagem espera resposta */
  esperaMin: number;
  audio: boolean;
}

const ms = (iso: string | null | undefined) => (iso ? Date.parse(iso) : NaN);

/**
 * O que acorda nesta conversa agora: no máximo um disparo de pressa (a PRIMEIRA mensagem com a palavra desde a
 * última resposta da HBR — mensagens novas enquanto ele espera não viram um 2º acorde) e um de desistência (a
 * mais recente). Vazio = nada.
 */
export function disparosDaConversa(c: ConversaDoAcorde, agora: Date, esperaMin: number): Disparo[] {
  if (c.fornecedor) return [];
  const todoDia = c.diasComMensagemSua >= 4;
  const hoje = diaBR(agora);
  const saida = ms(c.ultimaSaidaEm);
  const pendentes = c.recebidas
    .filter((r) => !Number.isNaN(ms(r.em)) && ms(r.em) <= agora.getTime() && diaBR(new Date(r.em)) === hoje)
    .filter((r) => Number.isNaN(saida) || ms(r.em) > saida)
    .sort((a, b) => ms(a.em) - ms(b.em));
  const disparos: Disparo[] = [];
  const espera = (r: Recebida) => Math.max(0, Math.floor((agora.getTime() - ms(r.em)) / 60_000));
  const audio = (r: Recebida) => /^\s*(🎤|\[audio\])/u.test(String(r.body ?? ""));
  const pressa = pendentes.map((r) => ({ r, g: gatilhoDaMensagem(r.body, c.cliente) }))
    .find((x) => x.g && x.g !== "desistencia" && !(todoDia && x.g === "pressa"));
  if (pressa && espera(pressa.r) >= esperaMin) {
    disparos.push({
      tipo: "pressa", gatilho: pressa.g!, mensagem: pressa.r, trecho: trechoDoGatilho(pressa.r.body, pressa.g!),
      esperaMin: espera(pressa.r), audio: audio(pressa.r),
    });
  }
  const desistiu = [...pendentes].reverse().find((r) => contatoEncerrou(r.body));
  if (desistiu) {
    disparos.push({
      tipo: "desistencia", gatilho: "desistencia", mensagem: desistiu, trecho: trechoDoGatilho(desistiu.body, "desistencia"),
      esperaMin: espera(desistiu), audio: audio(desistiu),
    });
  }
  return disparos;
}

// ─── O trabalho completo ────────────────────────────────────────────────────────────────────────

/** Um orçamento aberto do cliente, já com o sinal (a conta do PDF) e o último dia da validade. */
export interface OrcamentoAberto {
  id: string;
  numero: string;
  valor: number;
  /** draft | sent | awaiting_approval | awaiting_deposit */
  status: string;
  mexido_em: string;
  sinal: number | null;
  /** o último dia da validade (aaaa-mm-dd); null = não vence (aguardando sinal) ou sem data */
  validade: string | null;
}

/** A proposta "pronta": a enviada/aguardando mexida por último; sem enviada, o rascunho mais novo. */
export function propostaPronta(orcs: OrcamentoAberto[]): OrcamentoAberto | null {
  const enviados = orcs.filter((o) => o.status !== "draft");
  const pool = enviados.length ? enviados : orcs;
  return [...pool].sort((a, b) => ms(b.mexido_em) - ms(a.mexido_em) || b.valor - a.valor)[0] ?? null;
}

function primeiroNome(nome: string): string {
  const n = nome.replace(/\s+/g, " ").trim().split(" ")[0];
  return n || nome;
}

function tempoDeEspera(min: number): string {
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h}h${String(m).padStart(2, "0")}` : `${h}h`;
}

const CABECA: Record<Gatilho, string> = {
  fechar_hoje: "quer fechar hoje",
  fechar: "quer fechar",
  pressa: "pede para hoje",
  desistencia: "disse que fechou com outra empresa ou desistiu",
};

/** A legenda do PDF que o *sim* manda (sem IA; o dono pode trocar respondendo com o texto dele). */
export function legendaDoPdf(nome: string, numero: string): string {
  return `${primeiroNome(nome)}, segue a proposta completa (${numero}). Se estiver de acordo, confirmo o início com o sinal.`;
}

export interface AcordeDeCliente {
  texto: string;
  /** o orçamento que o *sim* manda (null = sem cartão) */
  cartao: { service_order_id: string; numero: string; legenda: string } | null;
}

/**
 * O texto do acorde de cliente (o que sairia). `telefone` já legível (null = sem a linha "Ligue agora": D9
 * desligado ou sem número). `podeCartao` = o dono está livre (sem pergunta nem cartão aberto); o cartão sai só
 * com ele livre, depois das 09:30 (acordeComCartao) e com um orçamento para mandar.
 */
export function textoDoAcordeDeCliente(p: {
  nome: string;
  disparo: Disparo;
  orcamentos: OrcamentoAberto[];
  telefone: string | null;
  podeCartao: boolean;
  agora: Date;
}): AcordeDeCliente {
  const { disparo: d } = p;
  const nome = umaLinha(p.nome, 40);
  const hora = horaBR(new Date(d.mensagem.em));
  const como = d.audio ? `Áudio às ${hora}` : `Mensagem às ${hora}`;
  const espera = d.esperaMin >= 1 ? ` Está há ${tempoDeEspera(d.esperaMin)} sem resposta.` : "";
  const ponto = /[.!?…]$/.test(d.trecho) ? "" : ".";
  const linhas = [`*${nome} ${CABECA[d.gatilho]}.* ${como}: "${d.trecho}"${ponto}${espera}`];
  const pronta = propostaPronta(p.orcamentos);
  if (pronta) {
    const sinal = pronta.sinal && pronta.sinal > 0 ? `sinal de ${brl(pronta.sinal)} na aprovação` : null;
    const hojeBR = diaBR(p.agora);
    const validade = pronta.validade
      ? (pronta.validade < hojeBR ? `validade vencida em ${ddmm(pronta.validade)}` : `validade até ${ddmm(pronta.validade)}`)
      : null;
    const detalhes = [sinal, validade].filter(Boolean).join("; ");
    // depois de "fechei com outra" a proposta não está "pronta": estava em aberto (o acorde é para tentar uma ligação)
    const rotulo = d.tipo === "desistencia" ? "Estava em aberto"
      : pronta.status === "draft" ? "Proposta montada (ainda não enviada)" : "Proposta pronta";
    const outros = p.orcamentos.filter((o) => o.id !== pronta.id).sort((a, b) => b.valor - a.valor);
    const tambem = outros.length
      ? ` Também aberto: ${outros.slice(0, 2).map((o) => `${o.numero}, ${brl(o.valor)}`).join("; ")}${outros.length > 2 ? ` e mais ${outros.length - 2}` : ""}.`
      : "";
    linhas.push(`${rotulo}: *${pronta.numero}*, ${brl(pronta.valor)}${detalhes ? ` (${detalhes})` : ""}.${tambem}`);
  } else {
    linhas.push("Sem orçamento aberto no sistema.");
  }
  if (p.telefone) linhas.push(`Ligue agora: ${p.telefone}`);
  const comCartao = !!pronta && p.podeCartao && acordeComCartao(p.agora) && d.tipo !== "desistencia";
  if (comCartao) {
    const legenda = legendaDoPdf(p.nome, pronta!.numero);
    linhas.push(`*sim* = mando o PDF do ${pronta!.numero} com: "${legenda}" · *não* = deixo com você`);
    return { texto: linhas.join("\n"), cartao: { service_order_id: pronta!.id, numero: pronta!.numero, legenda } };
  }
  return { texto: linhas.join("\n"), cartao: null };
}

/** O maior orçamento aberto (para a D2: a desistência acorda com orçamento de pelo menos R$ X). */
export function maiorOrcamento(orcs: OrcamentoAberto[]): number {
  return orcs.reduce((m, o) => Math.max(m, o.valor), 0);
}

/**
 * D11 (16/10/2026, padrão recomendado): a primeira vez que o portão ouve sobre uma mensagem NOVA do contato conta
 * como fato novo — pode acordar de novo no mesmo dia (dentro do limite de 2). "Nova" = nenhum acorde de hoje do
 * mesmo contato foi sobre ela (a mesma mensagem não acorda duas vezes, venha do detector ou do acompanhamento).
 */
export function mensagemNovaEFatoNovo(
  regras: Pick<RegrasDaVozUnica, "mensagem_nova_e_fato_novo">,
  mensagemEm: string | null,
  acordesDeHoje: Array<{ dados?: Record<string, unknown> | null }>,
): boolean {
  if (!regras.mensagem_nova_e_fato_novo || !mensagemEm) return false;
  const alvo = new Date(mensagemEm).toISOString();
  return !acordesDeHoje.some((a) => {
    const em = a.dados?.mensagem_em;
    return typeof em === "string" && !Number.isNaN(Date.parse(em)) && new Date(em).toISOString() === alvo;
  });
}

/**
 * O pedido ao portão do acorde de cliente. Chave: um por "espera" (a primeira mensagem com a palavra desde a
 * última resposta) — mensagens novas enquanto ele espera dão "repetido". Desistência: chave própria e, pela D2,
 * fato novo (acorda mesmo depois do acorde de pressa do dia) se havia orçamento de R$ X ou mais; sem ele, vai na
 * próxima mensagem fixa.
 */
export function avisoDoCliente(p: {
  conversa: Pick<ConversaDoAcorde, "phone" | "nome" | "cliente" | "client_id">;
  disparo: Disparo;
  orcamentos: OrcamentoAberto[];
  acorde: AcordeDeCliente;
  regras: Pick<RegrasDaVozUnica, "desistencia_acorda_com_orcamento_de">;
  novoFato: boolean;
}): AvisoDaFonte {
  const { conversa: c, disparo: d } = p;
  const em = new Date(d.mensagem.em).toISOString();
  const desistencia = d.tipo === "desistencia";
  const maior = maiorOrcamento(p.orcamentos);
  const acordaPelaD2 = desistencia && maior > 0 && maior >= p.regras.desistencia_acorda_com_orcamento_de;
  return {
    fonte: "cliente",
    chave: `${desistencia ? "desistencia" : "cliente"}:${c.phone}:${em}`,
    assunto: `contato:${c.phone}`,
    destino: desistencia && !acordaPelaD2 ? "proxima_fixa" : "acorde",
    referencia: c.client_id ? `cliente:${c.client_id}` : `fone:${c.phone}`,
    texto: p.acorde.texto,
    novo_fato: desistencia ? acordaPelaD2 : p.novoFato,
    dados: {
      nome: umaLinha(c.nome, 60),
      cliente: c.cliente,
      gatilho: d.gatilho,
      mensagem_em: em,
      trecho: d.trecho,
      espera_min: d.esperaMin,
      orcamentos: p.orcamentos.slice(0, 5).map((o) => ({ numero: o.numero, valor: o.valor })),
      ...(p.acorde.cartao ? { cartao: { acao: "send_service_order_link", formato: "pdf", ...p.acorde.cartao } } : {}),
    },
  };
}

// ─── Os outros acordes (golpe, certificado, NF-e, sistema): o texto que sairia ──────────────────

/** Golpe por e-mail: uma vez por remetente, para sempre. */
export function textoDoGolpe(p: { conta: string; remetente: string; assunto: string | null }): string {
  const assunto = p.assunto ? `, "${umaLinha(p.assunto, 80)}"` : "";
  return `*Parece golpe no e-mail ${umaLinha(p.conta, 40)}:* ${umaLinha(p.remetente, 60)}${assunto}. ` +
    "Não pague nem mude dados bancários sem confirmar por telefone. Não volto a avisar deste remetente.";
}

/** Certificado A1 com 7 dias ou menos. `validade` aaaa-mm-dd. */
export function textoDoCertificado(dias: number, validade: string): string {
  const quando = dias < 0 ? `venceu em ${ddmm(validade)}` : dias === 0 ? "vence hoje" : `vence em ${dias} ${dias === 1 ? "dia" : "dias"} (${ddmm(validade)})`;
  return `*O certificado A1 ${quando}:* sem ele nenhuma NF-e sai. Renove na Contora.`;
}

/** NF-e rejeitada, uma por nota. */
export function textoDaNfe(p: { numero: string | number | null; cliente: string | null; valor: number | null; motivo: string | null; os: string | null }): string {
  const quem = [p.cliente ? umaLinha(p.cliente, 40) : null, p.valor ? brl(p.valor) : null].filter(Boolean).join(", ");
  const motivo = p.motivo ? ` ${umaLinha(p.motivo, 140).replace(/\.?$/, ".")}` : "";
  const reemitir = p.os ? ` Reemita pela ${p.os}.` : " Reemita pela OS.";
  return `*A NF-e${p.numero ? ` nº ${p.numero}` : ""}${quem ? ` (${quem})` : ""} foi rejeitada.*${motivo}${reemitir}`;
}

/** Sistema fora do ar, avisado na volta. `manhaNaoChegou` = a queda derrubou a manhã de hoje. */
export function textoDoSistema(p: { desde: string | null; ate: string | null; manhaNaoChegou: boolean }): string {
  const fora = p.desde && p.ate
    ? `O WhatsApp ficou fora das ${horaBR(new Date(p.desde))} às ${horaBR(new Date(p.ate))}${diaBR(new Date(p.desde)) !== diaBR(new Date(p.ate)) ? ` (desde ${ddmm(diaBR(new Date(p.desde)))})` : ""}.`
    : "O WhatsApp ficou fora do ar.";
  const manha = p.manhaNaoChegou ? " A manhã de hoje não chegou: me peça *como estão as coisas?* se quiser o resumo." : "";
  return `${fora}${manha}`;
}

/**
 * A queda derrubou a manhã de hoje: começou antes das 07:30 e só acabou depois das 09:05 (a fila da manhã tenta até
 * ~09:05 — ai-daily-briefing, tentativasAte("09:00")). Para o texto do acorde de sistema.
 */
export function quedaDerrubouAManha(desde: string, ate: string): boolean {
  const fim = Date.parse(ate);
  const ini = Date.parse(desde);
  if (Number.isNaN(fim) || Number.isNaN(ini)) return false;
  const dia = diaBR(new Date(fim));
  return ini <= Date.parse(`${dia}T07:30:00-03:00`) && fim >= Date.parse(`${dia}T09:05:00-03:00`);
}
