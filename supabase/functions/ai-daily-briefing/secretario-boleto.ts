// Recebimento baixado pelo boleto na manhã nova (24/11/2026, "sim, quero" do dono).
//
// A conta a receber nascida de NF-e com boleto é baixada sozinha quando o banco mostra o 'CREDITO DE BOLETO' de mesmo
// valor no dia do vencimento (baixar_recebido_pelo_boleto, migration 20270228100000). Baixar sozinho só vale porque é
// visível e desfazível — e a manhã que o dono recebe (resumo_formato = 'novo') não tem a linha "Lançados sozinhos": a
// conta sumia do "Na rua" de um dia para o outro sem ninguém dizer por quê. Aqui ficam o texto, puro e testado sem
// rede, e o leitor da manhã, que nunca lança.
//
// A linha NÃO leva letra e não ensina "*desfazer* + letra" (isso é o "volta A" do secretário, _shared/secretario/
// comandos.ts): o dono responde pelo nome ("desfaz a baixa de Apolo"), a frase segue para o assistente e ele usa as
// ferramentas de sempre (listar_lancados_sozinhos → desfazer_aprovacao_de_lancamento), com a confirmação de sempre.
// Nada aqui baixa nem desfaz conta.
//
// Revisão de 24/11/2026 (antes de publicar), o que mudou aqui e por quê:
// - a janela conta desde a última manhã útil ENTREGUE (a fila disse 'sent'), não a do calendário: em 27/10 e 03/11 a
//   fila desistiu da manhã, e a baixa da véspera nunca seria dita;
// - a baixa só é "minha" se o registro da linha do banco (reconciliation_log) disser isso sozinho: depois de um
//   desfazer a proposta fica approved/boleto para sempre, e a conta que o dono casasse à mão com a mesma linha saía
//   como "Baixei sozinho";
// - várias contas do mesmo cliente dizem o valor e o vencimento de cada uma (o dono precisa saber qual desfazer);
// - o nome de chamar não sobra só com o ramo ("Industria") nem termina em "-".
import { brl, ddmm, somarDias, umaLinha } from "../_shared/secretario/base.ts";
import { type TipoDoDia, tipoDoDia } from "../_shared/secretario/feriados.ts";
import { diaBR } from "../_shared/pdf/datas.ts";
import { manhaAnterior } from "./secretario-candidatos.ts";

/** Uma conta a receber que o sistema baixou sozinho pelo boleto e que continua baixada. */
export interface RecebidoPeloBoleto {
  /** o nome de chamar (nomeDeChamar); null = a conta veio sem cliente legível */
  cliente: string | null;
  /** junta as contas do mesmo cliente; null = junta pelo nome */
  clienteId: string | null;
  valor: number;
  /** 'aaaa-mm-dd'; null = a linha sai sem o "(venceu …)" */
  vencimento: string | null;
}

// ─── O nome de chamar ──────────────────────────────────────────────────────────────────────────

const CONECTIVOS = new Set(["de", "da", "do", "das", "dos", "e", "em"]);
/** Onde a razão social deixa de ser o nome de chamar: o ramo e o tipo de sociedade (as mesmas de banking/matching.ts). */
const RAMO_OU_SOCIEDADE = new Set(["industria", "comercio", "comercial", "servico", "servicos", "ltda", "me", "epp", "eireli", "sa", "cia"]);
/** Até quantos caracteres o nome vai, sempre em palavras inteiras (ele entra num comando que o dono digita). */
const MAX_DO_NOME = 24;

const semAcento = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
const soLetras = (s: string) => semAcento(s).replace(/[^a-z0-9]/g, "");

/** Palavra que não diz quem é o cliente: o ramo, o tipo de sociedade, o conectivo ou só um sinal ("-", "&"). */
const generica = (p: string) => {
  const k = soLetras(p);
  return !k || CONECTIVOS.has(k) || RAMO_OU_SOCIEDADE.has(k);
};

/**
 * Tira do fim o conectivo e (24/11/2026, revisão) a palavra sem letra nem número: "LUIS MARCONDES MORAES - EPP" saía
 * "Luis Marcondes Moraes -", e o traço ia para dentro do "desfaz a baixa de …" (9 dos 566 cadastros).
 */
function semConectivoNoFim(palavras: string[]): string[] {
  const p = [...palavras];
  while (p.length > 1 && (CONECTIVOS.has(soLetras(p[p.length - 1])) || !soLetras(p[p.length - 1]))) p.pop();
  return p;
}

/** "APOLO" → "Apolo"; "DE" no meio → "de"; sigla sem vogal ("MP", "TSD") e palavra com número ("C6") ficam como estão. */
function capitalizada(palavra: string, primeira: boolean): string {
  const chave = soLetras(palavra);
  if (!primeira && CONECTIVOS.has(chave)) return palavra.toLowerCase();
  if (/\d/.test(palavra) || !/[aeiouy]/.test(chave)) return palavra;
  return palavra.charAt(0).toUpperCase() + palavra.slice(1).toLowerCase();
}

/**
 * O nome do cliente como o dono fala e digita. O apelido do cadastro (display_name) vale inteiro, como no resto da manhã
 * (secretario-coleta.ts usa display_name || name). Sem apelido, a razão social para no ramo ou no tipo de sociedade:
 * "APOLO INDUSTRIA E COMERCIO DE VEICULOS DE RECREACAO LTDA" → "Apolo". O corte por tamanho que a manhã usa nas outras
 * linhas (umaLinha) daria "APOLO INDUSTRIA E COMER…", que não serve dentro de "desfaz a baixa de …" (24/11/2026).
 * Razão social que COMEÇA pelo ramo (24/11/2026, revisão): o corte é o primeiro ramo depois da primeira palavra que
 * identifica, e o ramo da frente só fica se o nome couber inteiro — "INDUSTRIA E COMERCIO SUL PRAIANA LTDA - EPP" saía
 * "Industria" (dois cadastros diferentes com o mesmo nome de chamar) e agora sai "Sul Praiana"; "COMERCIAL SILVA LTDA"
 * continua "Comercial Silva".
 * Nome todo em maiúsculas ganha maiúscula só no começo das palavras. Sem nome = null.
 */
export function nomeDeChamar(cliente: { name?: string | null; display_name?: string | null } | null | undefined): string | null {
  const apelido = umaLinha(cliente?.display_name, 200);
  const bruto = apelido || umaLinha(cliente?.name, 200);
  if (!bruto) return null;
  let palavras = bruto.split(" ");
  if (!apelido) {
    // a 1ª palavra nunca é o corte ("COMERCIAL SILVA LTDA" → "Comercial Silva"), nem o ramo que vem antes da 1ª palavra
    // que identifica; sem palavra que identifique (proprio = -1) o corte é o de antes
    const proprio = palavras.findIndex((p) => !generica(p));
    const corte = palavras.findIndex((p, i) => i > Math.max(0, proprio) && RAMO_OU_SOCIEDADE.has(soLetras(p)));
    if (corte > 0) palavras = palavras.slice(0, corte);
    // o ramo na frente só fica se o nome couber inteiro; senão o nome começa na palavra que identifica
    if (proprio > 0 && semConectivoNoFim(palavras).join(" ").length > MAX_DO_NOME) palavras = palavras.slice(proprio);
  }
  palavras = semConectivoNoFim(palavras);
  const cabem = [palavras[0]];
  for (const p of palavras.slice(1)) {
    if ([...cabem, p].join(" ").length > MAX_DO_NOME) break;
    cabem.push(p);
  }
  const usadas = semConectivoNoFim(cabem);
  const tudoMaiusculo = !/\p{Ll}/u.test(bruto);
  const nome = usadas.map((p, i) => (tudoMaiusculo ? capitalizada(p, i === 0) : p)).join(" ");
  return umaLinha(nome, MAX_DO_NOME) || null;
}

// ─── O texto ───────────────────────────────────────────────────────────────────────────────────

const centavos = (v: number) => Math.round(v * 100) / 100;
/** Quantos clientes a linha nomeia quando são vários (o resto vira "e mais N"). */
const MAX_DE_CLIENTES = 3;
/** Quantas contas do mesmo cliente a linha diz uma a uma (o resto vira "e mais N", com a soma de todas). */
const MAX_DE_CONTAS = 3;

/** " (vence hoje)", " (venceu 16/10)", " (vence 30/11)"; sem vencimento = nada. */
const quandoVence = (vencimento: string | null, hoje: string): string =>
  !vencimento ? "" : vencimento === hoje ? " (vence hoje)" : ` (${vencimento > hoje ? "vence" : "venceu"} ${ddmm(vencimento)})`;

/**
 * A linha da manhã. Uma conta: o cliente, o valor e o vencimento; várias do mesmo cliente: quantas e o valor e o
 * vencimento de cada uma, até 3 (24/11/2026, revisão: só "2 recebimentos de Apolo (R$ 10.476,01)" não dizia quais — o
 * cliente tinha outra conta paga do mesmo valor, e nem a soma separava a baixada sozinha da casada à mão); clientes
 * diferentes: quantas, a soma e os nomes. Sem artigo antes do nome ("de Apolo"): o cadastro não diz se é "a" ou "o".
 * Nada baixado (ou lista ausente) = null: a manhã sai como antes.
 */
export function linhaDosRecebidosPeloBoleto(itens: RecebidoPeloBoleto[] | null | undefined, hoje: string): string | null {
  const lista = (itens ?? []).filter((i) => Number.isFinite(i.valor) && i.valor > 0);
  if (!lista.length) return null;
  const total = centavos(lista.reduce((s, i) => s + i.valor, 0));
  const nomes = new Map<string, string | null>();
  for (const i of lista) {
    const chave = i.clienteId ?? `nome:${i.cliente ?? ""}`;
    if (!nomes.has(chave)) nomes.set(chave, i.cliente);
  }
  const unico = nomes.size === 1 ? lista[0].cliente : null;
  // sem o nome não há o que digitar depois de "desfaz a baixa": o dono diz o valor e o assistente acha a conta
  const comoDesfazer = (nome: string | null) => (nome ? `Não era? Diga *desfaz a baixa de ${nome}*.` : "Não era? Diga *desfaz a baixa* e o valor.");
  if (lista.length === 1) {
    const i = lista[0];
    return `Baixei sozinho pelo boleto: ${i.cliente ?? "cliente sem nome"}, ${brl(i.valor)}${quandoVence(i.vencimento, hoje)} — ` +
      `o banco mostrou o crédito no dia do vencimento. ${comoDesfazer(i.cliente)}`;
  }
  if (unico) {
    const cada = lista.slice(0, MAX_DE_CONTAS).map((i) => `${brl(i.valor)}${quandoVence(i.vencimento, hoje)}`);
    // todas ditas: a soma não acrescenta nada; passou de 3: a soma de todas e quantas ficaram sem dizer
    const quais = lista.length > MAX_DE_CONTAS
      ? ` (${brl(total)}): ${cada.join(", ")} e mais ${lista.length - MAX_DE_CONTAS}`
      : `: ${cada.slice(0, -1).join(", ")} e ${cada[cada.length - 1]}`;
    return `Baixei sozinho pelo boleto ${lista.length} recebimentos de ${unico}${quais} — ` +
      `o banco mostrou o crédito no dia do vencimento de cada um. ${comoDesfazer(unico)}`;
  }
  const todos = [...nomes.values()].map((n) => n ?? "cliente sem nome");
  const quem = todos.slice(0, MAX_DE_CLIENTES).join(", ") + (todos.length > MAX_DE_CLIENTES ? ` e mais ${todos.length - MAX_DE_CLIENTES}` : "");
  const comNome = [...nomes.values()].every((n) => !!n);
  return `Baixei sozinho pelo boleto ${lista.length} recebimentos (${brl(total)}): ${quem}. ` +
    (comNome ? "Não era? Diga *desfaz a baixa* e o nome." : "Não era? Diga *desfaz a baixa* e o nome ou o valor.");
}

/**
 * A linha no fim da manhã (depois dos pagamentos, antes da sugestão de imprimir). Só em dia útil: domingo e feriado a
 * manhã é uma linha só, e o que foi baixado neles sai na manhã útil seguinte (a janela do leitor cobre). Sem linha = o
 * texto de antes, byte a byte.
 */
export function comRecebidosPeloBoleto(texto: string, tipo: TipoDoDia, linha: string | null | undefined): string {
  return tipo === "util" && linha ? `${texto}\n\n${linha}` : texto;
}

// ─── O leitor ──────────────────────────────────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
type Admin = any;

/**
 * Desde quando a manhã de `hoje` conta as baixas: as 07:30 da última manhã com itens (a mesma janela do "pedido que
 * chegou depois da última manhã", secretario-candidatos.ts). Com 24h fixas, a baixa de sábado à tarde ou de domingo
 * cairia fora da manhã de segunda e nunca seria contada.
 */
export function desdeAUltimaManha(hoje: string): string {
  return new Date(`${manhaAnterior(hoje)}T07:30:00-03:00`).toISOString();
}

/** Até quantos dias para trás a janela vai atrás da última manhã entregue. */
const MAX_DE_DIAS_DA_JANELA = 7;

/**
 * (24/11/2026, revisão) Desde quando contar, pela última manhã útil ENTREGUE ao dono: a linha da manhã na fila do
 * WhatsApp (source 'ai_briefing') com status 'sent' — o mesmo "entregue só quando a fila disser 'sent'" do guardado e
 * das aprovações (index.ts). Pelo calendário a baixa era dita uma única vez: em 27/10 e 03/11 a fila desistiu da manhã
 * (que ficou gravada com enviado = true), e a baixa da véspera nunca mais apareceria. Domingo e feriado não contam (a
 * manhã deles é uma linha só, sem esta). Nunca depois da janela do calendário, nunca antes de 7 dias; em dia normal sai
 * idêntica a desdeAUltimaManha. Sem telefone ou com erro na leitura = a do calendário; leitura boa sem nenhuma manhã
 * útil entregue nos 7 dias = o piso de 7 dias (nunca lança;
 * o erro vai para o log, com o código). Lê só a data da linha da fila, nunca o texto.
 */
export async function desdeAUltimaManhaEntregue(admin: Admin, hoje: string, phoneDoDono?: string | null): Promise<string> {
  const peloCalendario = desdeAUltimaManha(hoje);
  if (!phoneDoDono) return peloCalendario;
  try {
    const { data, error } = await admin.from("whatsapp_send_queue")
      .select("created_at")
      .eq("source", "ai_briefing").eq("phone_normalized", phoneDoDono).eq("status", "sent")
      .gte("created_at", new Date(`${somarDias(hoje, -MAX_DE_DIAS_DA_JANELA)}T00:00:00-03:00`).toISOString())
      .lt("created_at", new Date(`${hoje}T00:00:00-03:00`).toISOString())
      .order("created_at", { ascending: false }).limit(10);
    if (error) throw error;
    let ultima: string | null = null;
    // deno-lint-ignore no-explicit-any
    for (const l of (data ?? []) as any[]) {
      const quando = new Date(String(l?.created_at ?? ""));
      if (Number.isNaN(quando.getTime())) continue;
      const dia = diaBR(quando);
      if (dia < hoje && tipoDoDia(dia) === "util" && (!ultima || dia > ultima)) ultima = dia;
    }
    // Nenhuma manhã útil entregue em 7 dias (WhatsApp fora do ar): nada foi dito nesse tempo, então a janela fica no
    // piso de 7 dias em vez de encolher para "desde ontem" — senão a baixa do intervalo nunca seria contada.
    if (!ultima) {
      const piso = new Date(`${somarDias(hoje, -MAX_DE_DIAS_DA_JANELA)}T07:30:00-03:00`).toISOString();
      return piso < peloCalendario ? piso : peloCalendario;
    }
    const entregue = new Date(`${ultima}T07:30:00-03:00`).toISOString();
    return entregue < peloCalendario ? entregue : peloCalendario;
  } catch (e) {
    console.warn(JSON.stringify({
      fn: "ai-daily-briefing", secretario: "ultima_manha_entregue_falhou", codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro"),
    }));
    return peloCalendario;
  }
}

// ─── A baixa que continua de pé ────────────────────────────────────────────────────────────────

/** Como começa o detalhe que baixar_recebido_pelo_boleto deixa no registro da linha (migration 20270228100000). */
const DETALHE_DA_BAIXA = "Baixa automática pelo boleto";
/** O teto do PostgREST (max-rows): leitura que bate nele pode ter vindo cortada, e aí não dá para contar "um só". */
const TETO_DE_LINHAS = 1000;

/** Uma linha de public.reconciliation_log (a data é ocorrido_em; aqui não é preciso). */
export interface RegistroDaLinha {
  bank_transaction_id?: unknown;
  receivable_id?: unknown;
  acao?: unknown;
  detalhe?: unknown;
}

/**
 * (24/11/2026, revisão — "a marca que revive") Quais linhas do banco têm a baixa automática do RECEBIMENTO de pé, e de
 * qual conta: linha do banco → id da conta a receber. A proposta da fila fica approved + automatica = 'boleto' para
 * sempre; se o dono desfaz e casa à mão a mesma linha com outra conta, "há conta casada com a linha" voltava a dizer
 * "baixado sozinho", com o cliente da conta nova. O critério (o mesmo na tela, na ferramenta do assistente e aqui): o
 * registro da linha tem EXATAMENTE UMA linha, ela é 'conciliou' com o detalhe começando por "Baixa automática pelo
 * boleto", e a conta é a dela. É exato porque a função do banco nunca baixa linha que já tenha qualquer registro: todo
 * registro a mais (desconciliou, conciliou à mão, cancelou…) é obra de gente depois da baixa. Só vale para a conta a
 * RECEBER; a marca da conta a pagar não passa por aqui.
 */
export function baixasDePe(registros: RegistroDaLinha[] | null | undefined): Map<string, string> {
  const daLinha = new Map<string, RegistroDaLinha[]>();
  for (const r of registros ?? []) {
    // a faxina da própria varredura (proposta repetida fechada por outra rodada) não é mão de ninguém: não conta
    if (!r?.bank_transaction_id || r.acao === "tirou_da_fila_ja_lancada") continue;
    const linha = String(r.bank_transaction_id);
    daLinha.set(linha, [...(daLinha.get(linha) ?? []), r]);
  }
  const dePe = new Map<string, string>();
  for (const [linha, rs] of daLinha) {
    const r = rs[0];
    if (rs.length === 1 && r.acao === "conciliou" && String(r.detalhe ?? "").startsWith(DETALHE_DA_BAIXA) && r.receivable_id) {
      dePe.set(linha, String(r.receivable_id));
    }
  }
  return dePe;
}

/**
 * Lê o registro das linhas do banco e devolve as baixas de pé (baixasDePe). LANÇA se a leitura falhar ou puder ter
 * vindo cortada: quem chama decide o que o erro vira (na manhã nova, sem a linha; no resumo antigo, a linha sem o nome).
 */
export async function lerBaixasDePe(admin: Admin, linhas: string[]): Promise<Map<string, string>> {
  const unicas = [...new Set(linhas.filter(Boolean).map(String))];
  if (!unicas.length) return new Map();
  const { data, error } = await admin.from("reconciliation_log")
    .select("bank_transaction_id, receivable_id, acao, detalhe")
    .in("bank_transaction_id", unicas).limit(TETO_DE_LINHAS);
  if (error) throw error;
  const registros = (data ?? []) as RegistroDaLinha[];
  if (registros.length >= TETO_DE_LINHAS) throw new Error("registro_cortado");
  return baixasDePe(registros);
}

/** Das contas a receber casadas com a linha do banco, as que são a da baixa de pé (a casada à mão depois do desfazer não é). */
export function contasDaBaixaDePe<T extends { id?: unknown; bank_transaction_id?: unknown }>(
  contas: T[] | null | undefined,
  dePe: Map<string, string>,
): T[] {
  return (contas ?? []).filter((c) => !!c?.id && !!c?.bank_transaction_id && dePe.get(String(c.bank_transaction_id)) === String(c.id));
}

/**
 * Lê o que foi baixado sozinho pelo boleto desde a última manhã entregue e CONTINUA baixado: a proposta da fila fica
 * approved/boleto para sempre, então a baixa desfeita se reconhece por não haver mais conta a receber casada com a linha
 * do banco — e a desfeita que o dono casou de novo à mão, pelo registro da linha (baixasDePe). Nunca lança: qualquer
 * erro = null (a manhã sai sem a linha; o erro vai só para o log, com o código). Nada baixado = lista vazia.
 * `phoneDoDono` é o telefone do dono na fila do WhatsApp (o da manhã); sem ele a janela é a do calendário.
 */
export async function lerRecebidosPeloBoleto(admin: Admin, hoje: string, phoneDoDono?: string | null): Promise<RecebidoPeloBoleto[] | null> {
  try {
    const desde = await desdeAUltimaManhaEntregue(admin, hoje, phoneDoDono);
    const { data: fila, error } = await admin.from("finance_review_queue")
      .select("bank_transaction_id, decided_at")
      .eq("automatica", "boleto").eq("kind", "create_receivable").eq("status", "approved")
      .gte("decided_at", desde)
      .order("decided_at", { ascending: true }).limit(200);
    if (error) throw error;
    // deno-lint-ignore no-explicit-any
    const linhas = [...new Set(((fila ?? []) as any[]).map((l) => l?.bank_transaction_id).filter(Boolean).map(String))];
    if (!linhas.length) return [];
    const { data: contas, error: erroContas } = await admin.from("receivables")
      .select("id, client_id, bank_transaction_id, amount, due_date, clients(name, display_name)")
      .in("bank_transaction_id", linhas);
    if (erroContas) throw erroContas;
    // deno-lint-ignore no-explicit-any
    const casadas = ((contas ?? []) as any[]).filter((c) => c?.bank_transaction_id);
    if (!casadas.length) return []; // todas desfeitas: a conta voltou a ficar em aberto e a linha do banco, solta
    const dePe = await lerBaixasDePe(admin, casadas.map((c) => String(c.bank_transaction_id)));
    // deno-lint-ignore no-explicit-any
    const daLinha = new Map<string, any>();
    for (const c of contasDaBaixaDePe(casadas, dePe)) daLinha.set(String(c.bank_transaction_id), c);
    const itens: RecebidoPeloBoleto[] = [];
    for (const linha of linhas) {
      const c = daLinha.get(linha);
      if (!c) continue; // desfeita (sem conta casada) ou desfeita e casada de novo à mão (o registro da linha diz)
      const cadastro = Array.isArray(c.clients) ? c.clients[0] : c.clients;
      const vencimento = /^\d{4}-\d{2}-\d{2}/.test(String(c.due_date ?? "")) ? String(c.due_date).slice(0, 10) : null;
      itens.push({ cliente: nomeDeChamar(cadastro), clienteId: c.client_id ? String(c.client_id) : null, valor: Number(c.amount), vencimento });
    }
    return itens;
  } catch (e) {
    console.warn(JSON.stringify({
      fn: "ai-daily-briefing", secretario: "recebidos_pelo_boleto_falhou", codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro"),
    }));
    return null;
  }
}
