// A queda do assistente vista pelo vigia (pacote 1, V1, 25/11/2026).
//
// ═══ POR QUE EXISTE ═══
//
// Ninguém vigiava o Claude da assinatura: em 90 dias ele caiu sete vezes com o WhatsApp de pé (login, limite da semana,
// rede, o programa do PC parado de 07 a 08/11) e o dono só soube reclamando. E não havia histórico de queda nenhuma.
// Aqui moram as regras PURAS do vigia novo, que roda dentro do vigia da conexão (whatsapp-conexao, a cada 5 minutos):
// o que conta como queda, quando ela fecha, e o que o dono leria. Quem lê e grava é whatsapp-conexao/vigia-do-assistente.ts.
//
// ═══ UMA PEÇA SÓ COM O TURNO DO DONO (C2) ═══
//
// O estado do programa do PC e a frase de cada causa vêm de causa-da-falha.ts, que é a única fonte das duas coisas:
//   · o estado: lerEstadoDoMax com o corte de QUEDA (SEM_SINAL_QUEDA_S, 180 s). Não há outro leitor.
//   · a frase: FRASE_CURTA_DA_CAUSA. O histórico guarda uma causa mais fina que a do turno (CAUSAS_DO_ASSISTENTE, que
//     separa "o programa parou" de "o PC ficou sem rede"), e CODIGO_DA_FRASE diz qual frase do C2 cada uma usa. Não há
//     outro mapa de frases: a mesma queda não pode ser dita de dois jeitos (regra da voz única).
//
// ═══ A CHAVE ═══
//
// app_settings.vigia_assistente: ausente, ilegível ou 'desligado' = o vigia da conexão roda exatamente como antes;
// 'sombra' = grava o histórico (assistente_quedas) e NÃO manda nada, nem muda texto nenhum; 'ligado' = grava e avisa o
// dono pelo portão da voz única. Nasce 'sombra' (migration 20270301110000). Ligar é do dono.
//
// ═══ A JANELA DE HORÁRIO ═══
//
// Não há janela própria: o aviso passa pelo portão (aviso_registrar), que acorda das 08:00 às 19:59 e guarda o resto
// para a manhã ou o fechamento. O dono pediu 7h–21h; abrir a janela do portão só para este aviso é pergunta para ele.
//
// ═══ O QUE FICOU DE FORA, DE PROPÓSITO ═══
//
//   · O "teste de volta" (um pedido mínimo ao Claude para provar que voltou): o programa do PC recusa pedido sem autor,
//     e com o autor seria um uso automático da assinatura. A queda do tipo claude fecha pelo próximo pedido bom de
//     verdade, ou sozinha depois de 24 h sem o problema à vista (sem aviso de volta).
//   · Aviso por fora do WhatsApp (e-mail, push): decisão do dono de 24/11/2026. O aviso só sai com o WhatsApp de pé.
import { diaBR, horaBR } from "../../pdf/datas.ts";
import { ddmm } from "../../secretario/base.ts";
import {
  type CodigoDaCausa, type EstadoDoMax, FRASE_CURTA_DA_CAUSA, fraseDeQuandoLibera, trechoDeDesdeQuando,
  TURNO_SEM_RESPOSTA_COM_CAUSA,
} from "./causa-da-falha.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

// ═══ A CHAVE ═══

export const CHAVE_DO_VIGIA_DO_ASSISTENTE = "vigia_assistente";
export type ModoDoVigia = "desligado" | "sombra" | "ligado";

/** "sombra", " Ligado ", "\"sombra\"" → o valor; ausente ou qualquer outra coisa → "desligado". */
export function modoDoVigia(v: unknown): ModoDoVigia {
  const s = typeof v === "string" ? v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase() : "";
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

/** Lê a chave. Nunca lança: chave ausente, erro do banco ou exceção = "desligado" (o vigia da conexão roda como antes). */
export async function lerModoDoVigia(admin: Db): Promise<ModoDoVigia> {
  try {
    const { data, error } = await admin.from("app_settings").select("value").eq("key", CHAVE_DO_VIGIA_DO_ASSISTENTE).maybeSingle();
    if (error) return "desligado";
    return modoDoVigia(data?.value);
  } catch {
    return "desligado";
  }
}

// ═══ O VOCABULÁRIO DO HISTÓRICO (os CHECKs de assistente_quedas) ═══

export type TipoDeQueda = "claude" | "gateway" | "whatsapp";

/** A queda do assistente: do tipo claude (login, limite, indisponivel, configuracao) ou gateway (programa_parado, sem_rede). */
export const CAUSAS_DO_ASSISTENTE = ["login", "limite", "indisponivel", "configuracao", "programa_parado", "sem_rede", "desconhecida"] as const;
export type CausaDoAssistente = typeof CAUSAS_DO_ASSISTENTE[number];

/** A queda do WhatsApp (a que o vigia da conexão já detecta). */
export const CAUSAS_DO_WHATSAPP = ["pc_fora", "docker_ou_tunel", "desconectado", "travado", "desconhecida"] as const;
export type CausaDoWhatsApp = typeof CAUSAS_DO_WHATSAPP[number];

export type CausaDaQueda = CausaDoAssistente | CausaDoWhatsApp;

/** Minutos de queda do assistente, contados de quando o vigia a viu, antes de avisar (absorve o religamento do programa). */
export const MINUTOS_ATE_AVISAR_ASSISTENTE = 15;
/** Sem prova de volta (nenhum pedido bom), a queda do tipo claude fecha sozinha depois disso, sem aviso de volta. */
export const HORAS_ATE_FECHAR_SEM_PROVA = 24;
/** Mensagens deste vigia ao dono por dia (queda e volta somadas). O portão ainda tem o teto dele, de todas as fontes. */
export const MENSAGENS_DO_VIGIA_POR_DIA = 2;
/**
 * A resposta de falha que o dono recebeu vale desde este tanto ANTES do início gravado da queda: a queda do tipo claude
 * começa quando o vigia a vê (até 5 minutos depois do pedido que falhou), e o registro da falha é desse pedido.
 */
export const MARGEM_DO_JA_SOUBE_MIN = 10;

/**
 * Os registros de falha (app_error_logs.action, gravados por registrarFalhaDoAssistente) em que o dono LEU a causa na
 * resposta do WhatsApp. A falha do painel (turno_painel) e a do tratador (handler) não chegaram ao WhatsApp dele.
 *
 * Revisão da leva B (25/11/2026): o turno que caiu no laço da reserva e falhou só conta quando a causa do Claude foi no
 * topo da resposta (turno_whatsapp_com_causa). O `turno_whatsapp` puro é o turno que o dono leu só como "erro do
 * sistema": contá-lo calava o aviso de queda justamente quando o login do Claude caía com a reserva ligada.
 */
export const FALHAS_QUE_O_DONO_LEU = ["max_sem_reserva", "max_fora_sem_reserva", TURNO_SEM_RESPOSTA_COM_CAUSA] as const;

function ehCausaDoAssistente(v: unknown): v is CausaDoAssistente {
  return typeof v === "string" && (CAUSAS_DO_ASSISTENTE as readonly string[]).includes(v);
}

/**
 * O motivo que o programa do PC publica (estado.providers["claude-local"].reason) → a causa do histórico.
 * null = não é queda: sem motivo, ou o teto de pedidos por hora do próprio PC (local_quota), que passa sozinho.
 * Motivo que este código não conhece = "desconhecida" (o programa diz que não atende e não se sabe por quê).
 */
export function causaDoMotivo(motivo: string | null | undefined): CausaDoAssistente | null {
  switch (String(motivo ?? "").trim().toLowerCase()) {
    case "":
    case "local_quota":
      return null;
    case "auth_failed":
      return "login";
    case "rate_limited":
      return "limite";
    case "provider_unavailable":
      return "indisponivel";
    case "isolation_violation":
      return "configuracao";
    case "worker_shutdown":
      return "programa_parado";
    default:
      return "desconhecida";
  }
}

/**
 * Qual frase do C2 (FRASE_CURTA_DA_CAUSA) cada causa do histórico usa. É um mapa de CÓDIGOS, não de frases: a frase
 * mora só em causa-da-falha.ts. Confere com o que causaDaFalha diz do mesmo estado (queda-do-assistente_test.ts).
 */
export const CODIGO_DA_FRASE: Readonly<Record<CausaDoAssistente, CodigoDaCausa>> = {
  login: "login",
  limite: "limite",
  // a pausa não traz o detalhe: o C2 também a lê como "o Claude não alcançou o sistema"
  indisponivel: "ferramentas",
  configuracao: "erro",
  programa_parado: "pc_fora",
  sem_rede: "pc_fora",
  desconhecida: "erro",
};

/** A frase curta da causa, a mesma do turno do dono. Causa que não é do assistente (ou lixo) = a frase do erro comum. */
export function fraseDaCausaDaQueda(causa: unknown): string {
  return FRASE_CURTA_DA_CAUSA[CODIGO_DA_FRASE[ehCausaDoAssistente(causa) ? causa : "desconhecida"]];
}

// ═══ O QUE ESTÁ ERRADO AGORA ═══

export interface Problema {
  tipo: "claude" | "gateway";
  causa: CausaDoAssistente;
  /** Desde quando, se o estado diz (o último sinal do programa). null = desde agora. */
  desde: string | null;
  /** O motivo publicado e o horário de liberação, como vieram do estado. Nunca texto de mensagem. */
  detalhe: string | null;
  /** O horário de liberação do limite da assinatura (só na causa "limite"). */
  libera: string | null;
}

/**
 * O problema do assistente à vista neste estado, ou null (puro).
 *   · gateway: o programa do assistente está calado há mais que o corte. Com outro programa do PC dando sinal, parou só
 *     ele (programa_parado); sem nenhum, o PC não fala com o banco (sem_rede; o WhatsApp responde pelo túnel).
 *   · claude: o programa está vivo e diz que o Claude não atende, com o motivo.
 * O programa que avisou que estava saindo (worker_shutdown) é do tipo gateway: ele volta sozinho pelo religador, e o
 * vigia vê a volta pelo sinal. Do tipo claude a queda só fecharia com um pedido bom, e o religamento viraria alarme.
 */
export function problemaDoAssistente(estado: EstadoDoMax): Problema | null {
  if (estado.semSinal) {
    return { tipo: "gateway", causa: estado.pcComSinal ? "programa_parado" : "sem_rede", desde: estado.ultimoSinal, detalhe: "sem_sinal", libera: null };
  }
  if (!estado.pausa) return null;
  const causa = causaDoMotivo(estado.pausa.motivo);
  if (!causa) return null;
  const saindo = causa === "programa_parado";
  const detalhe = `${estado.pausa.motivo.slice(0, 60)}${estado.pausa.ate ? ` até ${estado.pausa.ate.slice(0, 40)}` : ""}`;
  return {
    tipo: saindo ? "gateway" : "claude",
    causa,
    desde: saindo ? estado.ultimoSinal : null,
    detalhe,
    libera: causa === "limite" ? estado.pausa.ate : null,
  };
}

// ═══ A DECISÃO ═══

/** A queda do assistente que está aberta (assistente_quedas, tipo claude ou gateway, `ate` nulo). */
export interface QuedaAberta {
  id: string;
  tipo: "claude" | "gateway";
  causa: CausaDoAssistente;
  desde: string;
  /** A última rodada em que o problema estava à vista. */
  visto_em: string;
  /** Quando o vigia gravou a queda (relógio do banco). É daqui que contam os 15 minutos do aviso. */
  criado_em: string;
  dono_soube: "aviso" | "resposta_de_falha" | null;
  avisado_por: "whatsapp" | "guardado" | "sino" | "limite" | null;
  aviso_id: string | null;
}

export type Passo =
  | { acao: "nada" }
  | { acao: "abrir"; tipo: "claude" | "gateway"; causa: CausaDoAssistente; desde: string; detalhe: string | null }
  /** `visto` = o problema está à vista nesta rodada (atualiza visto_em, a causa e o tipo). Sem `visto`, nada se grava. */
  | { acao: "manter"; tipo: "claude" | "gateway"; causa: CausaDoAssistente; visto: boolean; detalhe: string | null }
  | { acao: "fechar"; ate: string; provada: boolean; por: "job_bom" | "batimento" | "sem_prova" };

function instante(iso: unknown): number | null {
  if (typeof iso !== "string" || !iso.trim()) return null;
  const t = Date.parse(iso);
  return Number.isFinite(t) ? t : null;
}

/**
 * O que fazer com a queda do assistente nesta rodada (puro; nenhum modelo decide nada aqui). Em ordem:
 *
 *  1. WhatsApp fora: não abre queda do assistente (a do WhatsApp cobre, e não haveria por onde avisar). Queda já aberta
 *     fica como está, sem marcar que foi vista.
 *  2. Sem queda aberta: com problema à vista, abre (desde o último sinal, no tipo gateway; desde agora, no tipo claude).
 *  3. Queda aberta e um pedido bom ao Claude DEPOIS do início dela: fecha na hora desse pedido, com prova.
 *  4. Queda aberta e problema à vista: mantém, marca que viu e atualiza a causa (o login pode virar limite). O tipo
 *     gateway vira claude quando o programa volta dizendo que o Claude não atende; o tipo claude nunca vira gateway
 *     (quem já precisou de prova continua precisando).
 *  5. Queda do tipo gateway sem problema à vista: o programa voltou a dar sinal e diz que atende. Fecha agora, com prova.
 *  6. Queda do tipo claude sem problema à vista: NÃO fecha. Depois de uma falha de login a pausa do programa vence em
 *     10 minutos e ele volta a se dizer disponível sem testar. Fecha só pelo passo 3, ou sozinha, sem prova e sem aviso
 *     de volta, depois de 24 h sem ver o problema.
 */
export function decidirQuedaDoAssistente(p: {
  aberta: QuedaAberta | null;
  estado: EstadoDoMax;
  /** A conexão do WhatsApp está "open" nesta rodada. */
  whatsappAberto: boolean;
  /** O pedido ao Claude concluído mais recente depois de aberta.desde, ou null. */
  ultimoJobBomEm: string | null;
  agora: Date;
}): Passo {
  const { aberta, agora } = p;
  const semMudar = (q: QuedaAberta): Passo => ({ acao: "manter", tipo: q.tipo, causa: q.causa, visto: false, detalhe: null });

  if (!p.whatsappAberto) return aberta ? semMudar(aberta) : { acao: "nada" };

  const problema = problemaDoAssistente(p.estado);
  if (!aberta) {
    if (!problema) return { acao: "nada" };
    const sinal = problema.tipo === "gateway" ? instante(problema.desde) : null;
    // o último sinal nunca fica no futuro (relógios diferentes): no máximo agora
    const desde = sinal !== null && sinal <= agora.getTime() ? new Date(sinal).toISOString() : agora.toISOString();
    return { acao: "abrir", tipo: problema.tipo, causa: problema.causa, desde, detalhe: problema.detalhe };
  }

  const jobBom = instante(p.ultimoJobBomEm);
  const inicio = instante(aberta.desde);
  if (jobBom !== null && inicio !== null && jobBom > inicio) {
    return { acao: "fechar", ate: new Date(jobBom).toISOString(), provada: true, por: "job_bom" };
  }

  if (problema) {
    return { acao: "manter", tipo: aberta.tipo === "claude" ? "claude" : problema.tipo, causa: problema.causa, visto: true, detalhe: problema.detalhe };
  }

  if (aberta.tipo === "gateway") return { acao: "fechar", ate: agora.toISOString(), provada: true, por: "batimento" };

  const visto = instante(aberta.visto_em);
  if (visto !== null && agora.getTime() - visto >= HORAS_ATE_FECHAR_SEM_PROVA * 3_600_000) {
    return { acao: "fechar", ate: agora.toISOString(), provada: false, por: "sem_prova" };
  }
  return semMudar(aberta);
}

/** Já passaram os 15 minutos desde que o vigia gravou a queda? (data ilegível = ainda não) */
export function jaDaParaAvisar(q: Pick<QuedaAberta, "criado_em">, agora: Date): boolean {
  const gravada = instante(q.criado_em);
  return gravada !== null && agora.getTime() - gravada >= MINUTOS_ATE_AVISAR_ASSISTENTE * 60_000;
}

// ═══ O QUE O DONO LÊ ═══

/** As causas em que o vigia vê a volta sozinho (pelo sinal do programa). Só nelas ele promete avisar. */
const VOLTA_PELO_SINAL: ReadonlySet<CausaDoAssistente> = new Set<CausaDoAssistente>(["programa_parado", "sem_rede"]);

/**
 * O aviso de queda (WhatsApp, sem botão, sem pedir resposta). A frase da causa é a do C2. "Aviso aqui quando ele voltar"
 * só entra quando o vigia vê a volta sozinho; nas outras causas a volta só se prova com um pedido bom, e prometer um
 * aviso faria o dono esperar por uma mensagem que não chega se ele não escrever.
 * `libera` = o horário de liberação do limite da assinatura (só na causa "limite").
 */
export function textoDaQuedaDoAssistente(q: { causa: unknown; desde: string | null; libera?: string | null }, agora: Date): string {
  const causa: CausaDoAssistente = ehCausaDoAssistente(q.causa) ? q.causa : "desconhecida";
  const libera = causa === "limite" ? ` ${fraseDeQuandoLibera(q.libera ?? null, agora)}` : "";
  const fecho = VOLTA_PELO_SINAL.has(causa) ? " Aviso aqui quando ele voltar." : "";
  return `*Seu assistente está fora do ar${trechoDeDesdeQuando(q.desde, agora)}:* ${fraseDaCausaDaQueda(causa)}.${libera} ` +
    `O WhatsApp e o resto do sistema seguem normais; só as mensagens para o assistente ficam sem resposta.${fecho}`;
}

/** "às 10:37" (hoje) / "em 23/11 às 22:10" (outro dia) / "" (sem horário). */
function quandoVoltou(iso: string | null, agora: Date): string {
  const t = instante(iso);
  if (t === null) return "";
  const fim = new Date(t);
  return diaBR(fim) === diaBR(agora) ? ` às ${horaBR(fim)}` : ` em ${ddmm(diaBR(fim))} às ${horaBR(fim)}`;
}

/** O aviso de volta (WhatsApp, sem botão, sem pedir resposta). */
export function textoDaVoltaDoAssistente(q: { desde: string | null; ate: string | null }, agora: Date): string {
  const fora = trechoDeDesdeQuando(q.desde, agora);
  return `*Seu assistente voltou${quandoVoltou(q.ate, agora)}*${fora ? ` (estava fora${fora})` : ""}. Pode mandar de novo o que ficou sem resposta.`;
}

/** O sino dos administradores (app_notifications): o mesmo texto, sem o negrito do WhatsApp. */
export function sinoDoAssistente(momento: "caiu" | "voltou", texto: string): { type: string; title: string; body: string } {
  return {
    type: momento === "caiu" ? "assistente_caiu" : "assistente_voltou",
    title: momento === "caiu" ? "Assistente fora do ar" : "Assistente de volta",
    body: texto.replace(/\*/g, ""),
  };
}
