// Uma voz só (secretário, Passo 4, 15/10/2026): as chaves do portão e as regras do dono, puras.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-uma-voz.md
//
// app_settings.voz_unica:
//   desligado → as fontes avisam o dono como sempre e NÃO registram nada (é o valor com que nasce);
//   sombra    → avisam como sempre E registram em avisos_do_dono o que o portão faria;
//   ligado    → (P4.5, 20/10/2026) o portão decide quem fala: a fonte pergunta ANTES de mandar ao DONO
//               ('acordar' manda, 'guardar' fica para a próxima mensagem fixa, 'acabar' não manda; portão
//               ilegível = manda como sempre). A equipe continua recebendo o de sempre.
//               TRAVA: 'ligado' só vale com quem ENTREGA o guardado no ar — resumo_formato = 'novo' E
//               fechamento_formato = 'ligado' (vozEfetiva). Sem os dois, 'ligado' age como 'sombra': um
//               guardado que nenhuma mensagem fixa lê seria um aviso descartado.
// Valor desconhecido, chave ausente ou erro de leitura = desligado. Três fontes do mesmo padrão: este
// "desligado", a linha da migration 20261016101000 e a ausência da chave.
//
// app_settings.voz_unica_regras (JSON): as respostas-padrão das decisões abertas do dono (D1–D10).
// Campo ausente ou inválido = o padrão daquele campo (as outras respostas continuam valendo).
//
// app_settings.acompanhar_freio: ligado | desligado (P4.3). AUSENTE = desligado — o código publicado
// antes da migration não muda nada; a migration cria a chave 'ligado'.

import { CHAVE_DO_FORMATO, lerFormatoDoResumo } from "../secretario/formato.ts";
import { CHAVE_DO_FECHAMENTO, lerFormatoDoFechamento } from "../secretario/turno.ts";

export const CHAVE_VOZ_UNICA = "voz_unica";
export const CHAVE_REGRAS = "voz_unica_regras";
export const CHAVE_FREIO = "acompanhar_freio";
/** (20/10/2026, P4.5) As chaves de quem entrega o guardado: a trava do 'ligado' (vozEfetiva). */
export const CHAVES_DOS_CONSUMIDORES = [CHAVE_DO_FORMATO, CHAVE_DO_FECHAMENTO] as const;

export type VozUnica = "desligado" | "sombra" | "ligado";
/** O modo gravado nas linhas do portão. */
export type ModoDoPortao = "sombra" | "ligado";

export type Destino = "acorde" | "proxima_fixa" | "hoje" | "escritorio" | "deixar" | "acaba";
export type Decisao = "acordar" | "guardar" | "deixar" | "acabar" | "repetido";

function limpo(v: unknown): string {
  return typeof v === "string" ? v.trim().replace(/^"(.*)"$/, "$1").trim().toLowerCase() : "";
}

/** "sombra", " Ligado ", "\"sombra\"" → o valor; qualquer outra coisa → "desligado". */
export function lerVozUnica(v: unknown): VozUnica {
  const s = limpo(v);
  return s === "sombra" || s === "ligado" ? s : "desligado";
}

/**
 * (20/10/2026, P4.5) A voz que vale de verdade: 'ligado' só com a manhã nova (resumo_formato = 'novo') E o fechamento
 * ligado (fechamento_formato = 'ligado') — são eles que entregam o guardado. Sem os dois, 'ligado' age como 'sombra'
 * (as fontes mandam como sempre e registram). 'sombra' e 'desligado' passam como estão.
 */
export function vozEfetiva(voz: VozUnica, consumidores: { manha: unknown; fechamento: unknown }): VozUnica {
  if (voz !== "ligado") return voz;
  return lerFormatoDoResumo(consumidores.manha) === "novo" && lerFormatoDoFechamento(consumidores.fechamento) === "ligado"
    ? "ligado"
    : "sombra";
}

/**
 * O modo em que as fontes registram: null = não registram (desligado); 'sombra' = registram DEPOIS de mandar (o
 * que sai não muda); 'ligado' = perguntam ANTES de mandar ao dono. Recebe a voz JÁ efetiva (vozEfetiva).
 */
export function modoDoRegistro(v: VozUnica): ModoDoPortao | null {
  return v === "desligado" ? null : v;
}

/** "ligado"/"on"/"true" → true; ausente ou qualquer outra coisa → false. */
export function lerFreio(v: unknown): boolean {
  const s = limpo(v);
  return s === "ligado" || s === "on" || s === "true";
}

export interface RegrasDaVozUnica {
  /** Acordes por dia (o SQL lê o mesmo campo). 0–5. */
  acordes_por_dia: number;
  /** D1: e-mail urgente que não é golpe. */
  email_sem_golpe: "proxima_fixa" | "acorde";
  /** D2: cliente que desistiu acorda só com orçamento aberto de pelo menos R$ X (P4.2, o detector). */
  desistencia_acorda_com_orcamento_de: number;
  /** D3: o acompanhamento pedido pelo dono conta no limite de acordes ("me lembra às 15h" fica fora). */
  acompanhar_conta_no_limite: boolean;
  /** D5: promessa detectada nas mensagens do dono. */
  promessa: "proxima_fixa" | "acorde";
  /** D6: lead do site (salvo se pedir hoje/urgente, que acorda). */
  lead_site: "proxima_fixa" | "acorde";
  /** D7: excesso de sábado (o SQL lê o mesmo campo). */
  sabado: "domingo" | "segunda";
  /** D8: guardado que se resolveu antes da mensagem fixa (o consumidor aplica). */
  guardado_resolvido: "some" | "aparece";
  /** D9: o telefone no próprio aviso ("ligue agora"; P4.2). */
  telefone_no_aviso: boolean;
  /** D10: minutos entre as verificações do acorde de cliente (só documenta: o cron roda a cada 15 min). */
  verificacao_min: number;
  /** P4.3: avisos de acompanhamento sobre a mesma mensagem do contato antes do freio. */
  freio_avisos: number;
  // ── (16/10/2026) padrões recomendados, aguardam o dono. Ausente no JSON = este padrão ──
  /** P4.2: minutos sem resposta para a pressa/o "quero fechar" de um cliente acordar o dono (10–240). */
  acorde_espera_min: number;
  /** F1: o fechamento cita o cliente que escreveu hoje e está sem resposta há N horas ou mais (0 = não cita). */
  sem_resposta_hoje_horas: number;
  /** F1: quantos nomes a linha "Sem resposta desde hoje" cita (o resto vira "e mais N"). */
  sem_resposta_hoje_max: number;
  /** F3: o "Amanhã" do fechamento traz as contas a pagar que vencem até a próxima manhã. */
  amanha_a_pagar: boolean;
  /** F5: a linha do vigia na revisão de segunda só sai se o último mês "pronto" for o mês passado (ou mais novo). */
  vigia_so_mes_recente: boolean;
  /** F7: "X semana" (adiado até segunda) volta antes se houver fato novo (mensagem nova, pagamento, vencimento). */
  semana_volta_com_fato_novo: boolean;
  /** D11: o primeiro aviso sobre uma mensagem NOVA do contato conta como fato novo (pode acordar de novo no dia). */
  mensagem_nova_e_fato_novo: boolean;
}

export const REGRAS_PADRAO: Readonly<RegrasDaVozUnica> = Object.freeze({
  acordes_por_dia: 2,
  email_sem_golpe: "proxima_fixa",
  desistencia_acorda_com_orcamento_de: 5000,
  acompanhar_conta_no_limite: true,
  promessa: "proxima_fixa",
  lead_site: "proxima_fixa",
  sabado: "domingo",
  guardado_resolvido: "some",
  telefone_no_aviso: true,
  verificacao_min: 15,
  freio_avisos: 2,
  acorde_espera_min: 30,
  sem_resposta_hoje_horas: 4,
  sem_resposta_hoje_max: 2,
  amanha_a_pagar: true,
  vigia_so_mes_recente: true,
  semana_volta_com_fato_novo: true,
  mensagem_nova_e_fato_novo: true,
});

function inteiro(v: unknown, min: number, max: number): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  if (!Number.isFinite(n)) return null;
  return Math.min(max, Math.max(min, Math.round(n)));
}

function umDe<T extends string>(v: unknown, opcoes: readonly T[]): T | null {
  return typeof v === "string" && (opcoes as readonly string[]).includes(v) ? (v as T) : null;
}

function booleano(v: unknown): boolean | null {
  return typeof v === "boolean" ? v : v === "true" ? true : v === "false" ? false : null;
}

/** O JSON de voz_unica_regras (texto ou objeto) sobre os padrões, campo a campo. Nunca lança. */
export function lerRegras(v: unknown): RegrasDaVozUnica {
  let o: Record<string, unknown> = {};
  try {
    const bruto = typeof v === "string" ? JSON.parse(v) : v;
    if (bruto && typeof bruto === "object" && !Array.isArray(bruto)) o = bruto as Record<string, unknown>;
  } catch {
    o = {};
  }
  const p = REGRAS_PADRAO;
  return {
    acordes_por_dia: inteiro(o.acordes_por_dia, 0, 5) ?? p.acordes_por_dia,
    email_sem_golpe: umDe(o.email_sem_golpe, ["proxima_fixa", "acorde"] as const) ?? p.email_sem_golpe,
    desistencia_acorda_com_orcamento_de: inteiro(o.desistencia_acorda_com_orcamento_de, 0, 10_000_000) ?? p.desistencia_acorda_com_orcamento_de,
    acompanhar_conta_no_limite: booleano(o.acompanhar_conta_no_limite) ?? p.acompanhar_conta_no_limite,
    promessa: umDe(o.promessa, ["proxima_fixa", "acorde"] as const) ?? p.promessa,
    lead_site: umDe(o.lead_site, ["proxima_fixa", "acorde"] as const) ?? p.lead_site,
    sabado: umDe(o.sabado, ["domingo", "segunda"] as const) ?? p.sabado,
    guardado_resolvido: umDe(o.guardado_resolvido, ["some", "aparece"] as const) ?? p.guardado_resolvido,
    telefone_no_aviso: booleano(o.telefone_no_aviso) ?? p.telefone_no_aviso,
    verificacao_min: inteiro(o.verificacao_min, 5, 60) ?? p.verificacao_min,
    freio_avisos: inteiro(o.freio_avisos, 1, 10) ?? p.freio_avisos,
    acorde_espera_min: inteiro(o.acorde_espera_min, 10, 240) ?? p.acorde_espera_min,
    sem_resposta_hoje_horas: inteiro(o.sem_resposta_hoje_horas, 0, 24) ?? p.sem_resposta_hoje_horas,
    sem_resposta_hoje_max: inteiro(o.sem_resposta_hoje_max, 1, 5) ?? p.sem_resposta_hoje_max,
    amanha_a_pagar: booleano(o.amanha_a_pagar) ?? p.amanha_a_pagar,
    vigia_so_mes_recente: booleano(o.vigia_so_mes_recente) ?? p.vigia_so_mes_recente,
    semana_volta_com_fato_novo: booleano(o.semana_volta_com_fato_novo) ?? p.semana_volta_com_fato_novo,
    mensagem_nova_e_fato_novo: booleano(o.mensagem_nova_e_fato_novo) ?? p.mensagem_nova_e_fato_novo,
  };
}

/** O que uma fonte quer dizer ao dono (sem o telefone: a fonte sabe para quem manda). */
export interface AvisoDaFonte {
  fonte: string;
  chave: string;
  assunto: string;
  destino: Destino;
  referencia?: string | null;
  /** O texto que saiu (ou sairia) — fica no registro para a comparação. */
  texto?: string | null;
  dados?: Record<string, unknown>;
  /** Fato novo do mesmo assunto no mesmo dia: pode acordar de novo (D2). */
  novo_fato?: boolean;
}

/** O pedido completo ao portão (o corpo de aviso_registrar). */
export function pedidoAoPortao(phone: string, modo: ModoDoPortao, aviso: AvisoDaFonte, agora?: Date): Record<string, unknown> {
  return {
    phone,
    modo,
    fonte: aviso.fonte,
    chave: aviso.chave.slice(0, 200),
    assunto: aviso.assunto.slice(0, 200),
    destino: aviso.destino,
    referencia: aviso.referencia ? aviso.referencia.slice(0, 200) : null,
    texto: aviso.texto ? aviso.texto.slice(0, 4000) : null,
    dados: aviso.dados ?? {},
    novo_fato: aviso.novo_fato ?? false,
    ...(agora ? { agora: agora.toISOString() } : {}),
  };
}

export interface RespostaDoPortao {
  ok: boolean;
  decisao?: Decisao;
  situacao?: string;
  motivo?: string | null;
  cartao?: boolean;
  id?: string;
  mensagem?: string | null;
  entregar_a_partir_de?: string | null;
  /** no 'repetido': a decisão da primeira vez */
  antes?: string | null;
  erro?: string;
}
