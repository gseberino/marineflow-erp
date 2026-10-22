// O que a tarde mostra (secretário, Passo 3, 15/10/2026) — regras puras, sem banco e sem IA.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-fechamento.md §4 e §5.
//
// A tarde NUNCA cria letra: tudo o que ela mostra com letra é um item que a manhã do mesmo dia gravou
// (resumo_itens), com a letra que ele teve de manhã. "Ainda é verdade" vem dos candidatos montados de novo às
// 17:30 com a mesma coleta da manhã: o item só volta se o candidato da mesma referência ainda existe e ainda
// passa na regra da família (`elegivel`) — cobrança paga, cliente respondido, orçamento enviado ou recusado,
// compra feita: some sozinho.
//
//   · ficaramDeHoje   (fechamento)      — os itens de MANHÃ sem ação do dono hoje e ainda verdade;
//   · paradosDaSemana (revisão da semana) — até 5 assuntos parados, das letras de hoje;
//   · cobrancasAntigas (revisão do mês) — cobranças vencidas há 30 dias ou mais, agrupadas pela letra de hoje.

import { brl, brlCurto, ddmm, diasEntre, somarDias, umaLinha } from "../_shared/secretario/base.ts";
import type { ItemGravado } from "../_shared/secretario/respostas.ts";
import { diaBR, horaBR } from "../_shared/pdf/datas.ts";
import { ehClienteGenerico, pareceSoAgradecimento } from "../_shared/secretario/palavras.ts";
import { type Candidato, type CobrancaCrua, REGRAS } from "./secretario-candidatos.ts";
import { estadoPeloHistorico, type OpcoesDoHistorico, OPCOES_PADRAO, type PassagemDoHistorico } from "./secretario-selecao.ts";

/** Um item gravado pela manhã de hoje (resumo_itens), com o fato e o valor. */
export interface ItemDaManha extends ItemGravado {
  fato: string;
  valor: number | null;
}

/** Uma linha com letra da tarde. `texto` sem a letra e sem as respostas. */
export interface LinhaComLetra {
  letra: string;
  parte: "ficou" | "parado" | "antiga";
  referencia: string;
  tipo: string;
  texto: string;
  /** "*B* = <faco>" (null = sem cartão) */
  faco: string | null;
  /** "*B <comandoAlternativo>* = <alternativa>" */
  alternativa: string | null;
  comandoAlternativo: string;
  valor: number;
  /** dia (aaaa-mm-dd) desde quando o assunto está assim */
  desde: string;
}

/** O dia de um `desde` de candidato (dia de calendário ou instante ISO). */
export function diaDoDesde(desde: string): string {
  return /^\d{4}-\d{2}-\d{2}$/.test(desde) ? desde : diaBR(new Date(desde));
}

function porLetra(itens: ItemDaManha[]): Map<string, ItemDaManha[]> {
  const m = new Map<string, ItemDaManha[]>();
  for (const i of itens) {
    const l = m.get(i.letra) ?? [];
    l.push(i);
    m.set(i.letra, l);
  }
  for (const l of m.values()) l.sort((a, b) => Number(b.principal) - Number(a.principal) || a.ordem - b.ordem);
  return m;
}

/** Os orçamentos montados e não enviados de uma letra (o pacote da manhã). */
function ehPacoteDaManha(daLetra: ItemDaManha[]): boolean {
  return daLetra.length > 1 && daLetra.every((i) => i.tipo === "orcamento_nao_enviado");
}

/** A linha do pacote com os que AINDA não foram enviados (null = todos saíram). */
function linhaDoPacote(daLetra: ItemDaManha[], candidatos: Map<string, Candidato>): {
  texto: string; valor: number; desde: string; vivos: Candidato[];
} | null {
  const vivos = daLetra.map((i) => candidatos.get(i.referencia))
    .filter((c): c is Candidato => !!c && c.elegivel && c.tipo === "orcamento_nao_enviado");
  if (!vivos.length) return null;
  const valor = vivos.reduce((s, c) => s + c.valor, 0);
  const desde = vivos.map((c) => diaDoDesde(c.desde)).sort()[0];
  if (vivos.length === 1) return { texto: vivos[0].curto, valor, desde, vivos };
  const numeros = vivos.map((c) => c.nome.split(" ")[0]);
  return {
    texto: `${vivos.length} orçamentos montados, não enviados (${brlCurto(valor)}): ${numeros.slice(0, 4).join(", ")}${numeros.length > 4 ? ` e mais ${numeros.length - 4}` : ""}`,
    valor, desde, vivos,
  };
}

/** "; ainda não entrou" para cobrança (o curto já diz o resto). */
function comSituacao(c: Candidato): string {
  return c.familia === "cobranca" ? `${c.curto}; ainda não entrou` : c.curto;
}

/**
 * Fechamento: o que ficou de hoje — cada item de MANHÃ (principal) sem ação do dono hoje (o cartão aberto,
 * "abriu", não é ação) e ainda verdade às 17:30. Na ordem da manhã, com a mesma letra.
 */
export function ficaramDeHoje(itens: ItemDaManha[], candidatos: Map<string, Candidato>): LinhaComLetra[] {
  const linhas: LinhaComLetra[] = [];
  const letras = porLetra(itens);
  const daManha = itens.filter((i) => i.principal && i.posicao === "manha").sort((a, b) => a.ordem - b.ordem);
  for (const p of daManha) {
    if (p.acao) continue;
    const daLetra = letras.get(p.letra) ?? [p];
    if (ehPacoteDaManha(daLetra)) {
      const pac = linhaDoPacote(daLetra, candidatos);
      if (!pac) continue;
      linhas.push({
        letra: p.letra, parte: "ficou", referencia: p.referencia, tipo: p.tipo, texto: pac.texto,
        // a letra sozinha abre o pacote da MANHÃ (a lista dele, sem modelo), mesmo que agora sobre um só
        faco: "te mostro a lista", alternativa: "até segunda", comandoAlternativo: "espera",
        valor: pac.valor, desde: pac.desde,
      });
      continue;
    }
    const c = candidatos.get(p.referencia);
    if (!c || !c.elegivel) continue;
    linhas.push({
      letra: p.letra, parte: "ficou", referencia: p.referencia, tipo: c.tipo, texto: comSituacao(c),
      faco: c.faco, alternativa: c.alternativa, comandoAlternativo: c.comandoAlternativo,
      valor: c.valor, desde: diaDoDesde(c.desde),
    });
  }
  return linhas;
}

const ACOES_DO_DONO = new Set(["feito", "adiado", "nao", "tirado"]);

function ms(iso: string | null | undefined): number {
  const t = iso ? Date.parse(iso) : NaN;
  return Number.isNaN(t) ? -Infinity : t;
}

/**
 * Apareceu DE MANHÃ num dia anterior e o dono não respondeu desde então (nem antes de voltar a aparecer):
 * o "sem fato novo, desce para a lista e para a revisão de segunda" do desenho. O marco ("volta" ou adiamento
 * vencido) zera o que veio antes, como na seleção da manhã. Devolve o dia da última manhã sem resposta.
 */
export function manhaSemResposta(referencia: string, historico: PassagemDoHistorico[], hoje: string): string | null {
  let passagens = historico.filter((h) => h.referencia === referencia && h.dia < hoje);
  let marco = -Infinity;
  for (const h of passagens) {
    marco = Math.max(marco, ms(h.voltou_em));
    if (h.acao === "adiado" && h.adiado_ate && h.adiado_ate <= hoje) marco = Math.max(marco, ms(h.acao_em));
  }
  passagens = passagens.filter((h) => ms(h.criado_em) > marco);
  const ultimaAcao = Math.max(-Infinity, ...passagens.filter((h) => h.acao && ACOES_DO_DONO.has(h.acao)).map((h) => ms(h.acao_em)));
  const manhas = passagens
    .filter((h) => h.posicao === "manha" && (!h.acao || h.acao === "ignorado") && ms(h.criado_em) > ultimaAcao)
    .map((h) => h.dia).sort();
  return manhas.length ? manhas[manhas.length - 1] : null;
}

/**
 * A linha curta de um parado (ensaio de 19/10: com a linha da *lista* os 5 parados e o panorama passavam de 1.000
 * caracteres e o vigia saía): o rótulo (quem, valor) e desde quando está assim. Orçamento: "sem aprovação desde",
 * "sinal não veio desde" ou "montado e não enviado"; o resto já diz a data no rótulo.
 */
export function textoDoParado(c: Candidato, desde: string): string {
  if (c.familia !== "orcamento") return c.rotulo;
  const status = c.fato.split("|")[0];
  const estado = status === "draft" ? "montado e não enviado"
    : status === "awaiting_deposit" ? `sinal não veio desde ${ddmm(desde)}`
    : `sem aprovação desde ${ddmm(desde)}`;
  return `${c.rotulo}: ${estado}`;
}

/** O que veio junto, curto: "OS-00104" / "ORÇ-00095", "cobrança de R$ 1.650,00" ou "conversa sem resposta". */
function nomeCurto(i: ItemDaManha): string {
  const primeiro = i.nome.split(" ")[0];
  if (/^(OS|ORÇ)-\d+$/.test(primeiro)) return primeiro;
  if (i.familia === "cobranca") return `cobrança de ${brl(i.valor ?? 0)}`;
  if (i.familia === "cliente" || i.familia === "contato") return "conversa sem resposta";
  return umaLinha(i.nome, 24);
}

/** O dono decidiu o assunto e a decisão ainda vale (tirado/feito sem fato novo, adiado, "não"). */
function decididoPeloDono(c: Candidato, historico: PassagemDoHistorico[], hoje: string, opcoes: OpcoesDoHistorico = OPCOES_PADRAO): boolean {
  const e = estadoPeloHistorico(c, historico, hoje, opcoes);
  if (e.lugar === "fora" || e.adiadoAte) return true;
  return e.lugar === "lista" && /você respondeu "não"/.test(e.motivo ?? "");
}

/**
 * Revisão da semana: os assuntos parados das letras de HOJE (principais), sem ação hoje e ainda verdade, que
 * não são contato nem fornecedor nem cobrança de 30+ dias (essa é do dia 1), não foram decididos pelo dono, e
 * estão parados — (a) apareceram de manhã antes e ficaram sem resposta, ou (b) o fato tem 7+ dias. Ordem: maior
 * valor (o pacote vale a soma) → mais antigo. Devolve TODOS (o texto mostra até 5 e conta o resto — ensaio de
 * 19/10: 7 parados, e a conversa do Jorge, que vale 0, ficaria escondida sem a contagem).
 */
export function paradosDaSemana(
  itens: ItemDaManha[],
  candidatos: Map<string, Candidato>,
  historico: PassagemDoHistorico[],
  hoje: string,
  /** (16/10/2026) as regras do histórico do dono (F7): as mesmas da manhã */
  opcoes: OpcoesDoHistorico = OPCOES_PADRAO,
): LinhaComLetra[] {
  const letras = porLetra(itens);
  const corte = somarDias(hoje, -7);
  const achados: LinhaComLetra[] = [];
  for (const p of itens.filter((i) => i.principal).sort((a, b) => a.ordem - b.ordem)) {
    if (p.acao || p.secao === "contatos" || p.tipo === "fornecedor") continue;
    const daLetra = letras.get(p.letra) ?? [p];
    const tambem = daLetra.filter((i) => !i.principal);
    if (ehPacoteDaManha(daLetra)) {
      const pac = linhaDoPacote(daLetra, candidatos);
      if (!pac) continue;
      const vivos = pac.vivos.filter((c) => !decididoPeloDono(c, historico, hoje, opcoes));
      if (!vivos.length) continue;
      const parado = vivos.some((c) => manhaSemResposta(c.referencia, historico, hoje)) || pac.desde <= corte;
      if (!parado) continue;
      achados.push({
        letra: p.letra, parte: "parado", referencia: p.referencia, tipo: p.tipo, texto: pac.texto,
        faco: null, alternativa: null, comandoAlternativo: "espera", valor: pac.valor, desde: pac.desde,
      });
      continue;
    }
    const c = candidatos.get(p.referencia);
    if (!c || c.tipo === "cobranca_antiga" || c.tipo === "fornecedor" || c.secao === "contatos") continue;
    if (decididoPeloDono(c, historico, hoje, opcoes)) continue;
    const desde = diaDoDesde(c.desde);
    if (!manhaSemResposta(c.referencia, historico, hoje) && desde > corte) continue;
    // o que veio junto, só pelo nome curto (ensaio de 13/10: o rótulo inteiro cortava a linha no meio da palavra)
    const juntos = tambem.length === 1 ? ` · também: ${nomeCurto(tambem[0])}`
      : tambem.length > 1 ? ` · e mais ${tambem.length} do cliente`
      : "";
    achados.push({
      letra: p.letra, parte: "parado", referencia: p.referencia, tipo: c.tipo, texto: `${textoDoParado(c, desde)}${juntos}`,
      faco: null, alternativa: null, comandoAlternativo: "espera", valor: c.valor, desde,
    });
  }
  return achados.sort((a, b) => b.valor - a.valor || a.desde.localeCompare(b.desde) || a.letra.localeCompare(b.letra));
}

export interface CobrancasAntigas {
  linhas: LinhaComLetra[];
  /** quantas e quanto ao todo (com as sem letra e as que passaram do limite) */
  n: number;
  total: number;
  /** cobranças sem letra hoje (passaram das 21) ou de letras além do limite: só contadas */
  fora: { n: number; total: number };
}

/**
 * Revisão do mês: as cobranças vencidas há 30 dias ou mais (a régua da manhã que as manda "para a revisão do
 * mês"), lidas às 17:30, agrupadas pela letra de HOJE (o mesmo cliente divide a letra). Fica de fora o que o
 * dono decidiu (tirado, adiado, "não"). Até `max` letras, pelo total.
 */
export function cobrancasAntigas(
  itens: ItemDaManha[],
  cobrancas: CobrancaCrua[],
  candidatos: Map<string, Candidato>,
  historico: PassagemDoHistorico[],
  hoje: string,
  max = 5,
  opcoes: OpcoesDoHistorico = OPCOES_PADRAO,
): CobrancasAntigas {
  const letraDe = new Map<string, ItemDaManha>();
  for (const i of itens) letraDe.set(i.referencia, i);
  const acaoDaLetra = new Map<string, string | null>();
  for (const i of itens) if (i.principal) acaoDaLetra.set(i.letra, i.acao);
  const grupos = new Map<string, Array<{ c: Candidato; cr: CobrancaCrua }>>();
  const fora = { n: 0, total: 0 };
  let n = 0;
  let total = 0;
  for (const cr of cobrancas) {
    if (diasEntre(cr.vencimento, hoje) < REGRAS.cobrancaAntigaDias || !(cr.saldo > 0)) continue;
    const c = candidatos.get(`recv:${cr.id}`);
    if (!c || decididoPeloDono(c, historico, hoje, opcoes)) continue;
    const item = letraDe.get(c.referencia);
    if (item && acaoDaLetra.get(item.letra)) continue; // o dono já respondeu a letra hoje
    n++;
    total += cr.saldo;
    if (!item) {
      fora.n++;
      fora.total += cr.saldo;
      continue;
    }
    const l = grupos.get(item.letra) ?? [];
    l.push({ c, cr });
    grupos.set(item.letra, l);
  }
  const ordenados = [...grupos.entries()].map(([letra, gs]) => {
    gs.sort((a, b) => a.cr.vencimento.localeCompare(b.cr.vencimento));
    return { letra, gs, soma: gs.reduce((s, g) => s + g.cr.saldo, 0) };
  }).sort((a, b) => b.soma - a.soma || a.gs[0].cr.vencimento.localeCompare(b.gs[0].cr.vencimento));
  const linhas: LinhaComLetra[] = ordenados.slice(0, max).map(({ letra, gs, soma }) => {
    const antiga = gs[0].cr;
    const dias = diasEntre(antiga.vencimento, hoje);
    const texto = gs.length === 1
      ? gs[0].c.curto
      : `${umaLinha(antiga.cliente || "Sem cliente", 30)}: ${brl(soma)} em ${gs.length} cobranças; a mais antiga venceu ${ddmm(antiga.vencimento)} (${dias} dias)`;
    return {
      letra, parte: "antiga" as const, referencia: gs[0].c.referencia, tipo: gs[0].c.tipo, texto,
      faco: null, alternativa: null, comandoAlternativo: "espera", valor: soma, desde: antiga.vencimento,
    };
  });
  for (const g of ordenados.slice(max)) {
    fora.n += g.gs.length;
    fora.total += g.soma;
  }
  fora.total = Math.round(fora.total * 100) / 100;
  return { linhas, n, total: Math.round(total * 100) / 100, fora };
}

// ─── (16/10/2026) F1: quem escreveu hoje e está sem resposta ────────────────────────────────────

/** Uma linha de whatsapp_esperando_resposta (a lista do resumo, já sem "ok/obrigado" e sem quem desistiu). */
export interface QuemEspera {
  phone: string;
  contato: string | null;
  categoria: string | null;
  last_inbound_at: string;
  last_outbound_at?: string | null;
  /** a última recebida (quando as recebidas da semana não foram lidas) */
  last_body?: string | null;
}

export interface SemRespostaDeHoje {
  phone: string;
  nome: string;
  /** hh:mm da primeira mensagem de hoje sem resposta */
  desde: string;
  /** hh:mm do acorde de hoje sobre ele (o portão), ou null */
  acordei: string | null;
}

/** O nome curto da linha sem letra: "Giancarlo Ribeiro dos Santos" → "Giancarlo S." (até 18 caracteres fica como está). */
export function nomeSemLetra(nome: string): string {
  const n = nome.replace(/\s+/g, " ").trim();
  if (n.length <= 18) return n;
  const p = n.split(" ");
  return p.length > 1 ? `${p[0]} ${p[p.length - 1][0].toUpperCase()}.` : umaLinha(n, 18);
}

/**
 * F1 (16/10/2026, padrão recomendado, aguarda o dono): o fechamento cita, numa linha SEM letra, o cliente cadastrado
 * (não genérico) que escreveu HOJE e está sem resposta há `horas` horas ou mais — caso real: 13/10, o Giancarlo S.
 * perguntou às 10:31 e só foi respondido em 15/10; o fechamento não o citou. E também quem o portão acordou hoje e
 * continua sem resposta (spec uma voz §6.3-2), de qualquer tipo. Fica de fora quem já está na mensagem com letra e quem
 * só agradeceu. (21/10/2026) A regra do vendedor (pareceVendedor) NÃO se repete aqui: o contato sem cadastro só entra se
 * o "me acorde se" o acordou, e o acorde já a aplica antes de acordar (_shared/uma-voz/acorde.ts, sobre o de hoje sem
 * resposta); refazê-la sobre a semana tirava da linha o lead acordado que falou "consórcio" antes da resposta da HBR.
 * `horas` = 0 desliga a parte dos clientes. Ordem: os acordados primeiro, depois o que espera há mais tempo.
 */
export function semRespostaDesdeHoje(p: {
  esperando: QuemEspera[];
  recebidas: Array<{ phone_normalized: string; occurred_at: string; body?: string | null }> | null;
  agora: Date;
  horas: number;
  comLetra: Set<string>;
  /** telefone → instante (ISO) do acorde de hoje */
  acordados: Map<string, string>;
}): SemRespostaDeHoje[] {
  const hoje = diaBR(p.agora);
  const achados: Array<SemRespostaDeHoje & { ms: number }> = [];
  for (const w of p.esperando) {
    const phone = String(w.phone);
    if (!phone || p.comLetra.has(phone)) continue;
    const saida = w.last_outbound_at ? Date.parse(String(w.last_outbound_at)) : NaN;
    const deHoje = (iso: string) => diaBR(new Date(iso)) === hoje && (Number.isNaN(saida) || Date.parse(iso) > saida);
    const deHojeSemResposta = p.recebidas
      ? p.recebidas.filter((m) => m.phone_normalized === phone && deHoje(m.occurred_at)).map((m) => ({ em: Date.parse(m.occurred_at), body: m.body }))
      : (deHoje(String(w.last_inbound_at)) ? [{ em: Date.parse(String(w.last_inbound_at)), body: w.last_body }] : []);
    if (!deHojeSemResposta.length) continue;
    // (16/10/2026) agradecimento não é "sem resposta": o que ele mandou hoje é só "Bom dia Gustavo! Ótimo 👍", "ok", "👍"
    if (deHojeSemResposta.every((m) => pareceSoAgradecimento(m.body))) continue;
    const primeiras = deHojeSemResposta.map((m) => m.em);
    const primeira = Math.min(...primeiras);
    const acordei = p.acordados.get(phone) ?? null;
    const cliente = w.categoria === "cliente" && !ehClienteGenerico(w.contato);
    const esperou = p.agora.getTime() - primeira >= p.horas * 3_600_000;
    if (!acordei && !(cliente && p.horas > 0 && esperou)) continue;
    achados.push({
      phone, nome: nomeSemLetra(w.contato || phone), desde: horaBR(new Date(primeira)),
      acordei: acordei ? horaBR(new Date(acordei)) : null, ms: primeira,
    });
  }
  return achados.sort((a, b) => Number(!!b.acordei) - Number(!!a.acordei) || a.ms - b.ms).map(({ ms: _ms, ...x }) => x);
}
