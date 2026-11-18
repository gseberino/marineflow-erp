// Sinais de que o serviço de um orçamento JÁ FOI FEITO, lidos na hora de converter em OS (18/11/2026).
//
// Caso real (OS-00129): o orçamento de 28/10 tinha diagnóstico e nota técnica no passado desde 30/10 e o Pix inteiro de 31/10.
// Foi convertido sem sinal em 16/11 e, como toda conversão, entrou na agenda: o técnico recebeu ficha e via de um dia
// inteiro para um serviço já feito. A porta de status já sabia converter direto em concluída; faltava perguntar.
//
// Medido em 18/11 nos 21 orçamentos em aberto: nenhum tinha nota técnica, diagnóstico, check-in/saída ou dinheiro
// recebido (sinais FORTES, raros em orçamento de verdade); todos tinham 14 dias ou mais (a IDADE, que só lembra a data).
// Fonte única: o cartão do assistente (tools/converter-sem-sinal.ts) e a tela (src/components/ConverterSemSinal.tsx, por
// src/lib/sinais-de-ja-feito.ts). Sem banco e sem relógio próprio: quem chama passa os dados e o "hoje".

/** A partir de quantos dias o orçamento é "antigo" (o aviso lembra a data). */
export const IDADE_ANTIGA_DIAS = 14;

export interface DadosDoOrcamento {
  /** created_at do orçamento (ISO). */
  criadoEm?: string | null;
  technicianNotes?: string | null;
  diagnosis?: string | null;
  checkInAt?: string | null;
  checkOutAt?: string | null;
  /** O que já entrou de dinheiro nas contas a receber do orçamento (soma de paid_amount). null = não deu para conferir. */
  recebido?: number | null;
}

export interface SinaisDeJaFeito {
  /** Dias inteiros entre o dia do orçamento e hoje (pelo relógio de Brasília). null sem a data. */
  idadeDias: number | null;
  /** O dia do orçamento, "28/10". */
  dataDoOrcamento: string | null;
  /** Os sinais fortes, em português: "diagnóstico", "nota técnica", "check-in", "saída registrada", "R$ 750,00 já recebido". */
  fortes: string[];
  /** idadeDias >= IDADE_ANTIGA_DIAS. */
  antigo: boolean;
  /** Há o que avisar: algum sinal forte ou o orçamento antigo. */
  avisar: boolean;
}

const FUSO = "America/Sao_Paulo";

/** AAAA-MM-DD do instante no relógio de Brasília. */
export function diaEmBrasilia(d: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: FUSO, year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
}

function diasEntre(deAAAAMMDD: string, ateAAAAMMDD: string): number {
  const [a1, m1, d1] = deAAAAMMDD.split("-").map(Number);
  const [a2, m2, d2] = ateAAAAMMDD.split("-").map(Number);
  return Math.round((Date.UTC(a2, m2 - 1, d2) - Date.UTC(a1, m1 - 1, d1)) / 86_400_000);
}

const brl = (n: number) => new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(n);
const preenchido = (s: string | null | undefined) => typeof s === "string" && s.trim().length > 0;

export function sinaisDeJaFeito(o: DadosDoOrcamento, hoje: Date): SinaisDeJaFeito {
  let idadeDias: number | null = null;
  let dataDoOrcamento: string | null = null;
  const criado = o.criadoEm ? new Date(o.criadoEm) : null;
  if (criado && !Number.isNaN(criado.getTime())) {
    const dia = diaEmBrasilia(criado);
    idadeDias = Math.max(0, diasEntre(dia, diaEmBrasilia(hoje)));
    dataDoOrcamento = `${dia.slice(8, 10)}/${dia.slice(5, 7)}`;
  }
  const fortes: string[] = [];
  if (preenchido(o.diagnosis)) fortes.push("diagnóstico");
  if (preenchido(o.technicianNotes)) fortes.push("nota técnica");
  if (o.checkInAt) fortes.push("check-in");
  if (o.checkOutAt) fortes.push("saída registrada");
  if (typeof o.recebido === "number" && o.recebido > 0.009) fortes.push(`${brl(o.recebido)} já recebido`);
  const antigo = idadeDias !== null && idadeDias >= IDADE_ANTIGA_DIAS;
  return { idadeDias, dataDoOrcamento, fortes, antigo, avisar: fortes.length > 0 || antigo };
}

/** "28/10 (há 19 dias)", "18/11 (de hoje)", "17/11 (há 1 dia)". null sem a data. */
export function dataComIdade(s: SinaisDeJaFeito): string | null {
  if (!s.dataDoOrcamento || s.idadeDias === null) return null;
  const idade = s.idadeDias === 0 ? "de hoje" : `há ${s.idadeDias} ${s.idadeDias === 1 ? "dia" : "dias"}`;
  return `${s.dataDoOrcamento} (${idade})`;
}

function lista(itens: string[]): string {
  return itens.length <= 1 ? (itens[0] ?? "") : `${itens.slice(0, -1).join(", ")} e ${itens[itens.length - 1]}`;
}

/**
 * O porquê do aviso, sem o "o que fazer" (cada canal diz o seu): "orçamento de 28/10 (há 19 dias), já com diagnóstico,
 * nota técnica e R$ 750,00 já recebido". null quando não há o que avisar.
 */
export function motivoDoAviso(s: SinaisDeJaFeito): string | null {
  if (!s.avisar) return null;
  const data = dataComIdade(s);
  const partes: string[] = [];
  if (data) partes.push(`orçamento de ${data}`);
  if (s.fortes.length) partes.push(`já com ${lista(s.fortes)}`);
  return partes.join(", ");
}

/** "2026-10-31" é um dia de verdade, não depois de hoje (Brasília)? A data em que o serviço foi feito. */
export function diaFeitoValido(dia: string, hoje: Date): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) return false;
  const [a, m, d] = dia.split("-").map(Number);
  const t = new Date(Date.UTC(a, m - 1, d));
  if (t.getUTCFullYear() !== a || t.getUTCMonth() !== m - 1 || t.getUTCDate() !== d) return false;
  return dia <= diaEmBrasilia(hoje) && a >= 2020;
}

/** A saída (check_out_at) de um serviço feito no dia: 17:00 de Brasília, o fim do expediente. */
export function saidaDoDia(dia: string): string {
  return `${dia}T17:00:00-03:00`;
}
