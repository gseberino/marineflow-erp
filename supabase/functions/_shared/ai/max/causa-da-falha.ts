// A causa da falha do Claude da assinatura, dita ao dono (pacote 1, C2, 24/11/2026).
//
// ═══ POR QUE EXISTE ═══
//
// Quando o Claude da assinatura (o "Max", que roda no PC da oficina) não atendia, o dono lia um aviso genérico
// ("não consegui concluir agora (erro do sistema, já anotado)") ou o código cru entre parênteses ("(auth_failed)").
// De 08 a 24/11 foram 9 turnos assim, com espera de 82 a 939 segundos, e em nenhum ele soube o que tinha caído: o login
// do Claude, o limite da assinatura ou o PC desligado. Aqui a causa vira uma frase curta, em português, sem termo técnico.
//
// ═══ UMA PEÇA SÓ ═══
//
// Este arquivo é a ÚNICA fonte de duas coisas, para o turno do dono (ai-agent) e para o vigia de queda (V1):
//   · o estado do programa do assistente no PC (lerEstadoDoMax / estadoDoMax), lido de ai_gateway_workers;
//   · a frase de cada causa (FRASE_CURTA_DA_CAUSA e causaDaFalha).
// A mesma queda não pode ter duas frases (regra da voz única): quem precisar dizer por que o assistente caiu importa daqui.
//
// ═══ OS DOIS CORTES DE "SEM SINAL" ═══
//
// O programa do PC avisa o banco a cada ~15 s. "Sem sinal" depende de para que se pergunta, e por isso o corte é
// PARÂMETRO de quem lê, nunca um padrão escondido:
//   · SEM_SINAL_AGORA_S (45 s) = "AGORA": o mesmo corte de ai_claude_max_disponivel, a função do banco que decide se o
//     turno vai ou não para o Claude. É o do turno do dono (C2): explica por que ESTE pedido não foi atendido.
//   · SEM_SINAL_QUEDA_S (180 s) = "QUEDA": o do vigia (V1), que roda de 5 em 5 minutos e não pode abrir uma queda por
//     um soluço de rede de um minuto.
// Com 60 s sem sinal, o turno diz "o PC está sem sinal" (verdade para aquele pedido) e o vigia ainda não abriu queda.
//
// ═══ O QUE NUNCA SAI DAQUI ═══
//
//   · O texto cru do erro (ai_jobs.error): pode trazer caminho de arquivo e detalhe do PC. Ele só é LIDO para escolher
//     a frase (o horário de liberação do limite, "faturamento", "ferramentas"); a frase escolhida é fixa.
//   · O código cru ("auth_failed", "deadline_exceeded"): fica em `cru`, para o log. O dono nunca o lê.
//   · Crédito, recarga ou reserva: decisão do dono de 24/11/2026 (ele não vai pôr crédito na reserva e não quer ser
//     lembrado disso). A frase fala do que caiu (o Claude, o PC da oficina, o login), nunca do saldo de ninguém.
//   · A coluna token_hash de ai_gateway_workers: a leitura pede só id, last_seen_at e estado.
import { agoraEmBrasilia } from "../fuso.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** O Claude da assinatura na fila: ai_jobs.provider e a chave de estado.providers do programa do PC. */
export const PROVEDOR_DO_MAX = "claude-local";

/** "Agora": o corte de ai_claude_max_disponivel. O do turno do dono (C2). */
export const SEM_SINAL_AGORA_S = 45;
/** "Queda": o corte do vigia de queda (V1), que tolera um soluço de rede. */
export const SEM_SINAL_QUEDA_S = 180;

/** Uma linha de ai_gateway_workers, só com o que se lê (nunca o token_hash). */
export interface ProgramaDoPc {
  id: string;
  last_seen_at: string | null;
  estado: unknown;
}

export interface EstadoDoMax {
  /** A última vez que o programa do assistente avisou o banco (relógio do banco). null = nunca avisou ou não existe. */
  ultimoSinal: string | null;
  /** O programa do assistente está calado há mais que o corte recebido. */
  semSinal: boolean;
  /**
   * O programa diz que o Claude não está disponível (login, limite, teto por hora…), com o motivo que ele publica.
   * Com `semSinal`, é o que ele dizia da última vez que avisou: pode estar velho.
   */
  pausa: { motivo: string; ate: string | null } | null;
  /** Todas as vagas do programa estão ocupadas (pedidos em andamento >= o máximo dele). */
  ocupado: boolean;
  /**
   * Algum programa do PC (o do assistente, o leitor de documento, o da impressora) avisou dentro do corte: o PC está
   * ligado e com rede. Com `semSinal` e isto verdadeiro, quem parou foi só o programa do assistente.
   */
  pcComSinal: boolean;
}

function comoObjeto(v: unknown): Record<string, unknown> | null {
  return v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : null;
}

/** O que o programa publica sobre o Claude (estado.providers["claude-local"]), ou null se ele não atende o Claude. */
function claudeNoEstado(estado: unknown): Record<string, unknown> | null {
  const providers = comoObjeto(comoObjeto(estado)?.providers);
  return providers && Object.hasOwn(providers, PROVEDOR_DO_MAX) ? comoObjeto(providers[PROVEDOR_DO_MAX]) ?? {} : null;
}

function instante(iso: unknown): number | null {
  if (typeof iso !== "string" || !iso.trim()) return null;
  const t = Date.parse(iso);
  return Number.isFinite(t) ? t : null;
}

/**
 * O estado do programa do assistente, a partir das linhas lidas (puro).
 *
 * O programa do assistente é o que publica o Claude no próprio estado (estado.providers["claude-local"]): é o mesmo
 * critério de ai_claude_max_disponivel, que é quem decide se o turno vai ou não para o Claude. Havendo mais de um, vale o
 * que avisou por último. Nenhum = "sem sinal" sem horário.
 */
export function estadoDoMax(
  programas: ReadonlyArray<ProgramaDoPc> | null | undefined,
  corteSegundos: number,
  agora: Date,
): EstadoDoMax {
  const corteMs = Math.max(0, Number(corteSegundos) || 0) * 1000;
  const calado = (p: ProgramaDoPc): boolean => {
    const t = instante(p?.last_seen_at);
    return t === null || agora.getTime() - t >= corteMs;
  };
  const lista = (programas ?? []).filter((p) => !!p);
  const pcComSinal = lista.some((p) => !calado(p));
  const doAssistente = lista
    .filter((p) => claudeNoEstado(p.estado) !== null)
    .sort((a, b) => (instante(b.last_seen_at) ?? 0) - (instante(a.last_seen_at) ?? 0))[0];
  if (!doAssistente) return { ultimoSinal: null, semSinal: true, pausa: null, ocupado: false, pcComSinal };

  const estado = comoObjeto(doAssistente.estado) ?? {};
  const claude = claudeNoEstado(doAssistente.estado) ?? {};
  // ai_claude_max_disponivel só aceita available = true: qualquer outra coisa é "não disponível".
  const pausa = claude.available === true ? null : {
    motivo: typeof claude.reason === "string" ? claude.reason.trim().toLowerCase() : "",
    ate: instante(claude.until) === null ? null : String(claude.until),
  };
  const ativos = Number(estado.ativos);
  const maximo = Number(estado.max);
  return {
    ultimoSinal: instante(doAssistente.last_seen_at) === null ? null : doAssistente.last_seen_at,
    semSinal: calado(doAssistente),
    pausa,
    ocupado: Number.isFinite(ativos) && Number.isFinite(maximo) && maximo > 0 && ativos >= maximo,
    pcComSinal,
  };
}

/**
 * Lê o estado do programa do assistente. `corteSegundos` é obrigatório: SEM_SINAL_AGORA_S no turno do dono,
 * SEM_SINAL_QUEDA_S no vigia (ver o cabeçalho). Nunca lança: leitura que falhou = null, e null não é "está tudo bem"
 * nem "está fora" — quem chama cai na frase do código do pedido.
 */
export async function lerEstadoDoMax(admin: Db, corteSegundos: number, agora: Date = new Date()): Promise<EstadoDoMax | null> {
  try {
    const { data, error } = await admin.from("ai_gateway_workers").select("id, last_seen_at, estado").eq("enabled", true);
    if (error || !Array.isArray(data)) return null;
    return estadoDoMax(data as ProgramaDoPc[], corteSegundos, agora);
  } catch {
    return null;
  }
}

// ═══ A CAUSA ═══

export const CODIGOS_DA_CAUSA = [
  "login", "limite", "faturamento", "ferramentas", "pc_fora", "pc_ocupado", "prazo", "tempo", "sobrecarga", "teto_do_pc",
  "enfileirar", "nao_assinante", "erro",
] as const;
export type CodigoDaCausa = typeof CODIGOS_DA_CAUSA[number];

/**
 * A frase curta de cada causa: meia frase, sem ponto, que cabe entre parênteses ("O assistente parou no meio desta
 * resposta (passou do tempo máximo)"). EXPORTADA: o vigia de queda (V1) importa daqui, para a mesma queda não ter duas
 * frases. Mexer numa frase muda o que o dono lê em todos os lugares de uma vez.
 */
export const FRASE_CURTA_DA_CAUSA: Readonly<Record<CodigoDaCausa, string>> = {
  login: "o login do Claude caiu",
  limite: "acabou o limite da assinatura",
  faturamento: "a assinatura recusou por faturamento",
  ferramentas: "o Claude não alcançou o sistema",
  pc_fora: "o PC da oficina está sem sinal",
  pc_ocupado: "o PC estava ocupado",
  prazo: "o PC não começou a tempo",
  tempo: "passou do tempo máximo",
  sobrecarga: "o Claude estava sobrecarregado",
  teto_do_pc: "o PC atingiu o teto por hora",
  enfileirar: "o pedido não entrou na fila",
  nao_assinante: "a assinatura atende só o titular",
  erro: "deu um erro no assistente do PC",
};

/**
 * O texto para quem não é o titular da assinatura (código nao_assinante). É a frase inteira: não leva o
 * "Não consegui responder" na frente. Quem decide que a pessoa não é o titular é o S5; aqui mora só a frase.
 */
export const TEXTO_PARA_QUEM_NAO_E_O_TITULAR =
  "Este assistente funciona pela assinatura Claude do dono e atende só o titular. Fale com o administrador.";

export interface CausaDaFalha {
  codigo: CodigoDaCausa;
  /** FRASE_CURTA_DA_CAUSA[codigo]. */
  curta: string;
  /** O que o dono lê (depois de "⚠️ Não consegui responder: ", ver textoDaFalhaParaODono). */
  texto: string;
  /** O código cru de onde a causa saiu (do pedido ou da pausa do programa). Só para o log: o dono nunca o lê. */
  cru: string | null;
}

/** O pedido que falhou, como está em ai_jobs. `error` só é lido para escolher a frase; nunca é copiado. */
export interface PedidoQueFalhou {
  error_code?: string | null;
  error?: string | null;
  timeout_seconds?: number | null;
}

/** Falha que não vem do pedido nem do estado do PC: o pedido não entrou na fila, ou quem pede não é o titular (S5). */
export type MotivoSemPedido = "enfileirar" | "nao_assinante";

const DIAS_DA_SEMANA = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];
const doisDigitos = (n: number) => String(n).padStart(2, "0");

/** O instante no relógio de Brasília: a hora ("02:00"), o dia ("qui 26/11") e se é hoje. null = não é data. */
function emBrasilia(iso: unknown, agora: Date): { hora: string; dia: string; hoje: boolean } | null {
  const t = instante(iso);
  if (t === null) return null;
  // -03:00 fixo, a mesma premissa de fuso.ts (Brasília não tem horário de verão)
  const local = new Date(t - 3 * 3_600_000);
  return {
    hora: `${doisDigitos(local.getUTCHours())}:${doisDigitos(local.getUTCMinutes())}`,
    dia: `${DIAS_DA_SEMANA[local.getUTCDay()]} ${doisDigitos(local.getUTCDate())}/${doisDigitos(local.getUTCMonth() + 1)}`,
    hoje: local.toISOString().slice(0, 10) === agoraEmBrasilia(agora).dia,
  };
}

/**
 * "Libera às 18:30." / "Libera qui 26/11 às 02:00." / "Ainda não sei quando libera." (horário ausente ou já passado).
 * EXPORTADA para o vigia de queda (V1): o horário de liberação do limite é dito do mesmo jeito no turno e no aviso.
 */
export function fraseDeQuandoLibera(iso: unknown, agora: Date): string {
  const q = emBrasilia(iso, agora);
  if (!q || (instante(iso) ?? 0) <= agora.getTime()) return "Ainda não sei quando libera.";
  return q.hoje ? `Libera às ${q.hora}.` : `Libera ${q.dia} às ${q.hora}.`;
}

/** " desde as 17:27" / " desde seg 23/11 às 17:27" / "" (sem horário). EXPORTADA para o vigia de queda (V1). */
export function trechoDeDesdeQuando(iso: unknown, agora: Date): string {
  const q = emBrasilia(iso, agora);
  if (!q) return "";
  return q.hoje ? ` desde as ${q.hora}` : ` desde ${q.dia} às ${q.hora}`;
}

/** 150 → "2 min e 30 s"; 300 → "5 min"; 45 → "45 s". null = sem número que preste. */
export function duracaoPorExtenso(segundos: unknown): string | null {
  // null e "" virariam 0 pelo Number(): sem número, não há duração a dizer
  if (segundos === null || segundos === undefined || segundos === "") return null;
  const s = Math.round(Number(segundos));
  if (!Number.isFinite(s) || s <= 0) return null;
  const min = Math.floor(s / 60);
  const resto = s % 60;
  if (!min) return `${resto} s`;
  return resto ? `${min} min e ${resto} s` : `${min} min`;
}

/** O horário que o programa escreve no erro do limite ("…; libera em 2026-11-26T05:00:00.000Z."). */
function liberaEmNoErro(erro: string): string | null {
  const m = /libera em (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})?)/i.exec(erro);
  return m ? m[1] : null;
}

function montar(codigo: CodigoDaCausa, texto: string, cru: string | null): CausaDaFalha {
  return { codigo, curta: FRASE_CURTA_DA_CAUSA[codigo], texto, cru };
}

const login = (cru: string | null) =>
  montar("login", "o login do Claude no PC da oficina caiu. É preciso entrar de novo no Claude, no PC. Depois, mande a mensagem de novo.", cru);
const limite = (libera: unknown, agora: Date, cru: string | null) =>
  montar("limite", `acabou o limite de uso da assinatura Claude. ${fraseDeQuandoLibera(libera, agora)} Até lá eu não consigo responder.`, cru);
const ferramentas = (cru: string | null) =>
  montar("ferramentas", "o Claude no PC não conseguiu se ligar às ferramentas do sistema. Tente de novo em 1 minuto.", cru);
const tetoDoPc = (libera: unknown, agora: Date, cru: string | null) =>
  montar("teto_do_pc", `o PC atingiu o teto de pedidos por hora. ${fraseDeQuandoLibera(libera, agora)}`, cru);
const pcFora = (ultimoSinal: unknown, agora: Date, cru: string | null) =>
  montar(
    "pc_fora",
    `o PC da oficina está sem sinal${trechoDeDesdeQuando(ultimoSinal, agora)} (desligado, sem internet ou com o assistente parado). Confira o PC e mande de novo.`,
    cru,
  );
/** A causa que não se sabe dizer melhor. Sem o código na frase: "worker_shutdown" não é palavra para o dono ler. */
const erroComum = (cru: string | null) =>
  montar("erro", "deu um erro no assistente do PC. Já ficou anotado; tente de novo em instantes.", cru);

/**
 * A causa da falha, em frase (pura). Em ordem:
 *
 *  1. O motivo dado por quem chama: o pedido não entrou na fila (`enfileirar`) ou quem pede não é o titular (`nao_assinante`).
 *  2. O que o pedido disse ao falhar: login, limite (com o horário de liberação), faturamento, ferramentas, tempo máximo,
 *     sobrecarga, teto por hora.
 *  3. Ninguém pegou o pedido (não houve pedido, porque o Claude estava indisponível, ou o prazo venceu na fila): a causa
 *     está no estado do programa do PC. Sem sinal vem primeiro: de quem está calado, a pausa publicada é notícia velha.
 *     Depois a pausa (login, limite, ferramentas, teto por hora), depois o PC ocupado.
 *  4. Prazo vencido sem nada disso: "o PC não começou a tempo".
 *  5. Todo o resto: "deu um erro no assistente do PC", sem o código (ele fica em `cru`, para o log).
 *
 * `estado` nulo (a leitura falhou) = só o código do pedido decide.
 */
export function causaDaFalha(p: {
  job?: PedidoQueFalhou | null;
  estado: EstadoDoMax | null;
  agora: Date;
  motivo?: MotivoSemPedido;
}): CausaDaFalha {
  const { estado, agora } = p;
  if (p.motivo === "nao_assinante") return montar("nao_assinante", TEXTO_PARA_QUEM_NAO_E_O_TITULAR, null);
  if (p.motivo === "enfileirar") {
    return montar("enfileirar", "o pedido não entrou na fila do PC (erro do sistema, já anotado). Tente de novo em instantes.", null);
  }

  const codigo = String(p.job?.error_code ?? "").trim().toLowerCase();
  const erro = String(p.job?.error ?? "");
  const cruDoPedido = codigo || null;
  const pausa = estado?.pausa ?? null;

  switch (codigo) {
    case "auth_failed":
      return login(codigo);
    case "rate_limited":
      return limite(liberaEmNoErro(erro) ?? (pausa?.motivo === "rate_limited" ? pausa.ate : null), agora, codigo);
    case "provider_unavailable":
      if (/faturamento|cr[eé]dito/i.test(erro)) {
        return montar("faturamento", "a assinatura Claude recusou o pedido por faturamento. Confira a conta da assinatura.", codigo);
      }
      if (/ferramentas/i.test(erro)) return ferramentas(codigo);
      break;
    case "timeout": {
      const tempo = duracaoPorExtenso(p.job?.timeout_seconds);
      return montar(
        "tempo",
        `o pedido passou do tempo máximo${tempo ? ` (${tempo})` : ""} e foi interrompido. Se era um pedido grande, mande em partes.`,
        codigo,
      );
    }
    case "overloaded":
      return montar("sobrecarga", "o Claude está sobrecarregado agora. Tente de novo em 1 minuto.", codigo);
    case "local_quota":
      return tetoDoPc(pausa?.motivo === "local_quota" ? pausa.ate : null, agora, codigo);
  }

  const prazoVencido = codigo === "deadline_exceeded";
  if ((!p.job || prazoVencido) && estado) {
    if (estado.semSinal) return pcFora(estado.ultimoSinal, agora, cruDoPedido);
    switch (pausa?.motivo) {
      case "auth_failed":
        return login(cruDoPedido ?? pausa.motivo);
      case "rate_limited":
        return limite(pausa.ate, agora, cruDoPedido ?? pausa.motivo);
      case "provider_unavailable":
        // a pausa não traz o detalhe: a de ferramentas (1 minuto) é a comum
        return ferramentas(cruDoPedido ?? pausa.motivo);
      case "local_quota":
        return tetoDoPc(pausa.ate, agora, cruDoPedido ?? pausa.motivo);
      case "worker_shutdown":
        // o programa avisou que estava saindo: daqui a instantes ele some do sinal
        return pcFora(estado.ultimoSinal, agora, cruDoPedido ?? pausa.motivo);
    }
    if (prazoVencido && estado.ocupado) {
      return montar("pc_ocupado", "o PC estava ocupado com outros pedidos e não começou o seu a tempo. Mande de novo em instantes.", codigo);
    }
  }
  if (prazoVencido) {
    return montar("prazo", "o PC não começou o pedido a tempo (rede ou relógio do PC). Mande de novo em instantes.", codigo);
  }
  return erroComum(cruDoPedido ?? (pausa?.motivo || null));
}

/** O aviso inteiro que o dono lê quando o Claude não atende e nada mais vai responder. Sem botão, sem pedir resposta. */
export function textoDaFalhaParaODono(c: CausaDaFalha): string {
  return c.codigo === "nao_assinante" ? c.texto : `⚠️ Não consegui responder: ${c.texto}`;
}

/**
 * A linha que vai no TOPO quando o Claude falhou, a reserva tentou e também falhou: o dono lê por que o Claude não
 * respondeu, em cima do erro da reserva. Fala só do Claude; do saldo da reserva, nada (decisão do dono de 24/11/2026).
 */
export function avisoDeQueOClaudeNaoRespondeu(c: CausaDaFalha): string {
  return `⚠️ O Claude não respondeu (${c.curta}).`;
}

/** Como a causa vai para o log: o código da frase e, entre parênteses, o código cru de onde ela saiu. */
export function rotuloDaCausaNoLog(c: CausaDaFalha): string {
  return c.cru && c.cru !== c.codigo ? `${c.codigo} (${c.cru})` : c.codigo;
}

/**
 * A causa de uma falha de AGORA (o turno do dono): lê o estado com o corte de 45 s e monta a frase.
 * Com `motivo`, o estado não é lido (a causa já é conhecida).
 *
 * Nunca lança: é chamada também no caminho em que a reserva ainda vai responder, e dizer a causa não pode derrubar
 * o turno. O que der errado aqui vira o erro comum.
 */
export async function lerCausaDaFalha(
  admin: Db,
  p: { job?: PedidoQueFalhou | null; motivo?: MotivoSemPedido; agora?: Date } = {},
): Promise<CausaDaFalha> {
  try {
    const agora = p.agora ?? new Date();
    const estado = p.motivo ? null : await lerEstadoDoMax(admin, SEM_SINAL_AGORA_S, agora);
    return causaDaFalha({ job: p.job ?? null, estado, agora, motivo: p.motivo });
  } catch {
    return erroComum(null);
  }
}
