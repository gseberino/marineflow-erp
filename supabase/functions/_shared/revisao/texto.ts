// Lembretes de revisão (07/10/2026) — as regras PURAS: qual toque cabe a cada plano, como agrupar
// os planos de um cliente e o texto de cada mensagem. Sem banco, para testar.
//
// Decisões do dono (07/10/2026): lembrete ao cliente SEMPRE com o "sim" dele antes; no máximo 3
// mensagens por vencimento — D-21 (toque 1), D-7 sem resposta (toque 2), D+14 sem resposta e sem
// OS agendada (toque 3); campanha de temporada (15/09–31/10) uma vez por cliente por ano.
// Pesquisa: mensagem com o nome da embarcação, o último serviço com data, DUAS datas concretas e a
// FAIXA de valor; terça a quinta; um cliente com dois planos vencendo perto (≤ 30 dias) recebe UMA
// mensagem; termina com a saída fácil ("responda PARAR", LGPD).

const DIA_MS = 86_400_000;
const BRASILIA_MS = 3 * 60 * 60 * 1000;
const DIAS_CURTOS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];
const MESES = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];

export const SAIDA_FACIL = "Se preferir não receber esses lembretes, responda PARAR.";
/** Planos de um mesmo cliente com vencimentos até 30 dias um do outro vão numa mensagem só. */
export const JANELA_DE_AGRUPAR_DIAS = 30;
/** O RPC enviar_lembrete_de_revisao aceita até 5 planos por mensagem. */
export const MAX_PLANOS_POR_MENSAGEM = 5;

export type Toque = 0 | 1 | 2 | 3;

/** Uma linha de v_maintenance_plans_due (só o que as regras usam). */
export interface PlanoDue {
  plan_id: string;
  vessel_id: string;
  vessel_name: string | null;
  client_id: string | null;
  client_name: string | null;
  client_phone: string | null;
  opt_out: boolean;
  plan_name: string;
  scope?: string | null;
  estimated_value: number | string | null;
  last_service_at: string | null;
  last_service_order_id: string | null;
  next_due_on: string;
  snoozed_until: string | null;
  dias_para_vencer: number;
  situacao: "em_dia" | "na_janela" | "vencida" | "adiada";
  tem_os_agendada: boolean;
  respondeu_no_ciclo: boolean;
  client_reminder_enabled: boolean;
}

export interface EventoDoPlano {
  plan_id: string | null;
  client_id?: string | null;
  due_on: string | null;
  tipo: string;
  toque: number | null;
}

export type Barreira = "opt_out" | "sem_telefone" | "lembrete_desligado" | "os_agendada";
export type ToqueDevido = { toque: 1 | 2 | 3; pular?: Barreira };

// ─── Datas ──────────────────────────────────────────────────────────────────────────────────

/** "AAAA-MM-DD" de hoje em Brasília (sem horário de verão desde 2019: -3h fixo). */
export function hojeEmBrasilia(agora: Date = new Date()): string {
  return new Date(agora.getTime() - BRASILIA_MS).toISOString().slice(0, 10);
}

const emData = (iso: string) => new Date(`${iso.slice(0, 10)}T12:00:00Z`);
const paraIso = (d: Date) => d.toISOString().slice(0, 10);
export const somarDias = (iso: string, n: number) => paraIso(new Date(emData(iso).getTime() + n * DIA_MS));
export const diasEntre = (de: string, ate: string) => Math.round((emData(ate).getTime() - emData(de).getTime()) / DIA_MS);
const diaDaSemana = (iso: string) => emData(iso).getUTCDay();

/** "05/11"; com o ano quando não é o ano de referência ("12/10/2025"). */
export function diaMes(iso: string, anoDeReferencia?: string): string {
  const [a, m, d] = iso.slice(0, 10).split("-");
  return anoDeReferencia && anoDeReferencia.slice(0, 4) !== a ? `${d}/${m}/${a}` : `${d}/${m}`;
}

/** Terça a quinta (os dias de mandar lembrete e de oferecer o serviço). */
export const ehTerAQui = (iso: string) => [2, 3, 4].includes(diaDaSemana(iso));

/**
 * As duas datas oferecidas: os 2 primeiros dias de terça a quinta da semana do vencimento. Se a
 * semana do vencimento já está em cima (ou passou), a partir de hoje + 2 dias — nunca uma data
 * para amanhã nem no passado. Devolve AAAA-MM-DD.
 */
export function diasSugeridos(vence: string, hoje: string): [string, string] {
  const dow = diaDaSemana(vence);
  const segunda = somarDias(vence, -((dow + 6) % 7));
  let d = diasEntre(segunda, somarDias(hoje, 2)) > 0 ? somarDias(hoje, 2) : segunda;
  const achados: string[] = [];
  for (let i = 0; i < 21 && achados.length < 2; i++, d = somarDias(d, 1)) {
    if (ehTerAQui(d)) achados.push(d);
  }
  return [achados[0], achados[1]];
}

/** "qua 05/11 de manhã" / "qui 06/11 à tarde". */
export function diaOferecido(iso: string, periodo: "manhã" | "tarde"): string {
  return `${DIAS_CURTOS[diaDaSemana(iso)]} ${diaMes(iso)} ${periodo === "manhã" ? "de manhã" : "à tarde"}`;
}

// ─── Valor ──────────────────────────────────────────────────────────────────────────────────

const inteiroBR = (n: number) => new Intl.NumberFormat("pt-BR", { maximumFractionDigits: 0 }).format(n);

/** Faixa de ±15% arredondada à dezena: "R$ 1.270 a R$ 1.730". null = sem valor (omite a frase). */
export function faixaDeValor(valor: number | string | null | undefined): string | null {
  const v = Number(valor);
  if (!Number.isFinite(v) || v <= 0) return null;
  // Em inteiros: 1500 × 1,15 em ponto flutuante dá 1724,999… e arredondaria para baixo.
  const de = Math.round((v * 85) / 1000) * 10;
  const ate = Math.round((v * 115) / 1000) * 10;
  return de === ate ? `R$ ${inteiroBR(de)}` : `R$ ${inteiroBR(de)} a R$ ${inteiroBR(ate)}`;
}

// ─── Nomes ──────────────────────────────────────────────────────────────────────────────────

const semAcento = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

/** Primeiro nome para a saudação; empresa (type 'company') não tem — vai "Oi!" sem nome. */
export function primeiroNome(cliente: { name?: string | null; display_name?: string | null; type?: string | null } | null): string | null {
  if (!cliente || cliente.type === "company") return null;
  const base = String(cliente.display_name || cliente.name || "").trim().split(/\s+/)[0] ?? "";
  if (!base || /\d/.test(base)) return null;
  return base.charAt(0).toUpperCase() + base.slice(1).toLowerCase();
}

/**
 * O plano como entra na frase, sem artigo e no feminino ("revisão das baterias", "troca de óleo").
 * Nome que já é um serviço (revisão, troca, manutenção…) vai como está, com a 1ª letra minúscula
 * (sigla fica); nome que é só o equipamento ("Baterias", "Gerador") vira "revisão de …".
 */
export function planoNaFrase(nome: string): string {
  const n = String(nome || "").trim() || "revisão";
  const minusculo = /^[A-ZÀ-Ú][A-ZÀ-Ú]/.test(n) ? n : n.charAt(0).toLowerCase() + n.slice(1);
  if (/^(revis|troca|manuten|limpeza|inspe|verifica|confer|lavagem|pintura|substitui|recarga|calibra|higieniza|vistoria|checagem|teste|equaliza)/.test(semAcento(n))) {
    return minusculo;
  }
  return `revisão de ${minusculo}`;
}

const maiuscula = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

function juntar(itens: string[]): string {
  if (itens.length <= 1) return itens[0] ?? "";
  return `${itens.slice(0, -1).join(", ")} e ${itens[itens.length - 1]}`;
}

// ─── Qual toque cabe ────────────────────────────────────────────────────────────────────────

/**
 * O toque devido hoje para o plano, ou null. Regras:
 *  · adiado ou cliente já respondeu neste ciclo → nada;
 *  · 8 a 21 dias para vencer → toque 1; 0 a 7 → toque 2 se o 1 FOI ENVIADO, senão o 1 (o primeiro
 *    contato nunca é o "só lembrando"); vencido há 14+ dias → toque 3; vencido há 1–13 → espera;
 *  · nunca propõe de novo o mesmo toque do mesmo ciclo (proposto, enviado ou já pulado);
 *  · opt-out, sem telefone, lembrete desligado ou OS agendada → o toque vem com `pular` (a edge
 *    registra reminder_skipped uma vez e não pergunta nada ao dono).
 */
export function toqueDevido(p: PlanoDue, eventos: EventoDoPlano[]): ToqueDevido | null {
  if (p.situacao === "adiada") return null;
  const ciclo = eventos.filter((e) => e.plan_id === p.plan_id && e.due_on === p.next_due_on);
  if (p.respondeu_no_ciclo || ciclo.some((e) => e.tipo === "client_replied")) return null;
  const enviados = new Set(ciclo.filter((e) => e.tipo === "reminder_sent").map((e) => e.toque));
  const jaTratados = new Set(ciclo.filter((e) => ["reminder_proposed", "reminder_sent", "reminder_skipped"].includes(e.tipo)).map((e) => e.toque));
  const d = Number(p.dias_para_vencer);
  let toque: 1 | 2 | 3 | null = null;
  if (d <= -14) toque = 3;
  else if (d < 0) toque = null;
  else if (d <= 7) toque = enviados.has(1) ? 2 : 1;
  else if (d <= 21) toque = 1;
  if (!toque || jaTratados.has(toque)) return null;
  const pular: Barreira | undefined = p.opt_out ? "opt_out"
    : !p.client_phone || String(p.client_phone).replace(/\D/g, "").length < 10 ? "sem_telefone"
    : p.client_reminder_enabled === false ? "lembrete_desligado"
    : p.tem_os_agendada ? "os_agendada"
    : undefined;
  return pular ? { toque, pular } : { toque };
}

export interface Grupo {
  client_id: string;
  toque: 1 | 2 | 3;
  planos: PlanoDue[];
}

/**
 * Uma mensagem por cliente: os planos devidos do mesmo cliente e do mesmo toque, com vencimentos
 * até 30 dias um do outro, vão juntos. No toque 1 entram também os planos do cliente que vencem até
 * 30 dias depois e ainda não tiveram toque nenhum (antecipar 1 mensagem é melhor que mandar 2).
 */
export function agruparPorCliente(
  devidos: Array<{ plano: PlanoDue; toque: 1 | 2 | 3 }>,
  todos: PlanoDue[],
  eventos: EventoDoPlano[],
): Grupo[] {
  const grupos: Grupo[] = [];
  const usados = new Set<string>();
  const ordenados = [...devidos].sort((a, b) =>
    String(a.plano.client_id).localeCompare(String(b.plano.client_id)) || a.toque - b.toque ||
    a.plano.next_due_on.localeCompare(b.plano.next_due_on)
  );
  for (const d of ordenados) {
    if (usados.has(d.plano.plan_id) || !d.plano.client_id) continue;
    const ancora = d.plano;
    const grupo: Grupo = { client_id: ancora.client_id!, toque: d.toque, planos: [ancora] };
    usados.add(ancora.plan_id);
    const perto = (p: PlanoDue) => diasEntre(ancora.next_due_on, p.next_due_on) <= JANELA_DE_AGRUPAR_DIAS;
    for (const outro of ordenados) {
      if (grupo.planos.length >= MAX_PLANOS_POR_MENSAGEM) break;
      if (usados.has(outro.plano.plan_id) || outro.toque !== d.toque || outro.plano.client_id !== ancora.client_id) continue;
      if (!perto(outro.plano)) continue;
      grupo.planos.push(outro.plano);
      usados.add(outro.plano.plan_id);
    }
    if (d.toque === 1) {
      for (const p of todos) {
        if (grupo.planos.length >= MAX_PLANOS_POR_MENSAGEM) break;
        if (usados.has(p.plan_id) || p.client_id !== ancora.client_id || p.situacao !== "em_dia") continue;
        if (!perto(p) || p.client_reminder_enabled === false) continue;
        if (eventos.some((e) => e.plan_id === p.plan_id && e.due_on === p.next_due_on && e.tipo !== "serviced")) continue;
        grupo.planos.push(p);
        usados.add(p.plan_id);
      }
    }
    grupo.planos.sort((a, b) => a.next_due_on.localeCompare(b.next_due_on));
    grupos.push(grupo);
  }
  return grupos;
}

// ─── Campanha ───────────────────────────────────────────────────────────────────────────────

/** 15/09 a 31/10 (a decisão do dono: antes do verão, quando a agenda ainda tem espaço). */
export function dentroDaCampanha(hoje: string): boolean {
  const md = hoje.slice(5, 10);
  return md >= "09-15" && md <= "10-31";
}

/** O mês oferecido na campanha: este, até o dia 20; depois, o próximo. */
export function mesDaCampanha(hoje: string): string {
  const mes = Number(hoje.slice(5, 7)) - 1;
  const dia = Number(hoje.slice(8, 10));
  return MESES[dia <= 20 ? mes : (mes + 1) % 12];
}

// ─── Texto ──────────────────────────────────────────────────────────────────────────────────

export interface ItemDoTexto {
  plano: string;
  embarcacao: string;
  vence: string;
  ultimoServicoEm?: string | null;
  resumoUltimo?: string | null;
  valor?: number | string | null;
}

export interface PedidoDeTexto {
  toque: Toque;
  /** Primeiro nome (primeiroNome); null = sem nome na saudação. */
  nome: string | null;
  itens: ItemDoTexto[];
  /** AAAA-MM-DD em Brasília. */
  hoje: string;
  /** Campanha: as embarcações (sem plano, quase sempre). */
  embarcacoes?: string[];
}

/** O texto da mensagem ao cliente, pelo modelo de cada toque. Sem emoji, assinado pela empresa. */
export function montarTexto(p: PedidoDeTexto): string {
  const oi = p.nome ? `Oi, ${p.nome}!` : "Oi!";
  if (p.toque === 0) {
    const barcos = juntar((p.embarcacoes?.length ? p.embarcacoes : p.itens.map((i) => i.embarcacao)).map((b) => `da ${b}`));
    return `${oi} Aqui é da HBR Marine. Antes do verão a agenda lota. Quer deixar a parte elétrica ${barcos} conferida ainda em ${mesDaCampanha(p.hoje)} (baterias, carregador e inversor)? Me diz uma semana que eu encaixo. ${SAIDA_FACIL}`;
  }
  const itens = [...p.itens].sort((a, b) => a.vence.localeCompare(b.vence));
  const um = itens.length === 1;
  const primeiro = itens[0];
  const [d1, d2] = diasSugeridos(primeiro.vence, p.hoje);

  if (p.toque === 1) {
    const valores = itens.map((i) => Number(i.valor));
    const faixa = valores.every((v) => Number.isFinite(v) && v > 0) ? faixaDeValor(valores.reduce((a, b) => a + b, 0)) : null;
    const emTorno = faixa ? `, em torno de ${faixa}` : "";
    const datas = `Tenho ${diaOferecido(d1, "manhã")} ou ${diaOferecido(d2, "tarde")}`;
    if (um) {
      const ultima = primeiro.ultimoServicoEm
        ? ` (a última foi em ${diaMes(primeiro.ultimoServicoEm, p.hoje)}${primeiro.resumoUltimo ? `: ${primeiro.resumoUltimo}` : ""})`
        : "";
      return `${oi} Aqui é da HBR Marine. A ${planoNaFrase(primeiro.plano)} da ${primeiro.embarcacao} vence dia ${diaMes(primeiro.vence)}${ultima}. ${datas}${emTorno}. Qual fica melhor? ${SAIDA_FACIL}`;
    }
    const lista = juntar(itens.map((i) => `a ${planoNaFrase(i.plano)} da ${i.embarcacao} (vence ${diaMes(i.vence)})`));
    const quantas = itens.length === 2 ? "duas revisões" : `${itens.length} revisões`;
    const todas = itens.length === 2 ? "as duas" : "todas";
    return `${oi} Aqui é da HBR Marine. Estão chegando ${quantas}: ${lista}. ${datas} para fazer ${todas} juntas${emTorno}. Qual fica melhor? ${SAIDA_FACIL}`;
  }

  const abre = (resto: string) => (p.nome ? `${p.nome}, ${resto}` : maiuscula(resto));
  if (p.toque === 2) {
    const lista = juntar(itens.map((i) => `da ${planoNaFrase(i.plano)} da ${i.embarcacao} (vence ${diaMes(i.vence)})`));
    return `${abre(`só lembrando ${lista}.`)} Quer que eu reserve ${diaOferecido(d1, "manhã")}? Responda SIM ou sugira outro dia.`;
  }
  // toque 3
  if (um) {
    return `${abre(`a ${planoNaFrase(primeiro.plano)} da ${primeiro.embarcacao} venceu em ${diaMes(primeiro.vence)}.`)} Ainda faz sentido agendar ou prefere que eu tire do calendário?`;
  }
  const lista = juntar(itens.map((i) => `a ${planoNaFrase(i.plano)} da ${i.embarcacao} (venceu em ${diaMes(i.vence)})`));
  return `${abre(`estas revisões venceram: ${lista}.`)} Ainda faz sentido agendar ou prefere que eu tire do calendário?`;
}

/** Como o toque aparece para o dono na confirmação. */
export function rotuloDoToque(toque: Toque): string {
  return toque === 1 ? "1º lembrete (21 dias antes)"
    : toque === 2 ? "2º lembrete (7 dias antes, sem resposta)"
    : toque === 3 ? "último lembrete (14 dias depois de vencer)"
    : "campanha de temporada";
}

/** O resumo do último serviço, a partir dos nomes dos serviços da OS: curto, sem maiúscula inicial. */
export function resumoDoServico(nomes: string[]): string | null {
  const limpos = nomes.map((n) => String(n || "").trim()).filter(Boolean);
  if (!limpos.length) return null;
  const txt = juntar(limpos.slice(0, 2).map((n) => (/^[A-ZÀ-Ú][A-ZÀ-Ú]/.test(n) ? n : n.charAt(0).toLowerCase() + n.slice(1))));
  return txt.length > 80 ? `${txt.slice(0, 77).trimEnd()}…` : txt;
}
