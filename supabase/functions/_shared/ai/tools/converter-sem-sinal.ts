// converter_sem_sinal — orçamento vira OS SEM sinal, com o valor inteiro na conclusão (27/10/2026).
//
// Paridade com a tela (src/components/ConverterSemSinal.tsx): mesma condição (fonte única em
// _shared/banking/condicao-na-conclusao.ts), mesma ordem — condição + orçamento aprovado, depois a
// conversão — e o MESMO número: ORÇ-00042 vira OS-00042, como faz useUpdateServiceOrderStatus.
//
// Agenda de Produção (merge de 28/10/2026): a conversão vai pela porta única de status (os_transicionar_status, via
// 'assistente'), como a da tela e a de update_service_order_status: a porta troca só o prefixo do número, guarda o valor
// orçado, confere que o número novo não é de outra OS e registra a conversão em agenda_acoes. Sem a porta da Fase 3 no
// banco (PGRST202), o caminho de antes (PLANO B, _shared/porta-ausente.ts), com o mesmo número.
//
// Risco médio: troca a condição de pagamento e compromete o serviço, então pede o "sim". O retrato
// guarda o total que o dono viu; se o orçamento mudar até o "sim", a execução recusa.
//
// JÁ FOI FEITO (18/11/2026, OS-00129): o cartão do "sim" (resumirConversaoSemSinal) mostra a data do orçamento e, com sinal
// de serviço já feito (_shared/sinais-de-ja-feito.ts), avisa antes. Com ja_concluida, a porta vai de orçamento DIRETO a
// concluída numa chamada só (ela já sabia: converte e conclui, e se a conclusão recusar a conversão também não fica): a OS
// nunca entra na carteira da agenda (nenhum dia, nenhuma ficha) e a cobrança nasce na conclusão, como sempre.

import { blockTechnician, lerRetrato, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { condicaoTudoNaConclusao } from "../../banking/condicao-na-conclusao.ts";
import { fmtCurrency } from "../../pdf/documento.ts";
import { argumentosDaPortaCompleta, ehPortaAusente, ehSemDireitoNaPorta, statusPelaTelaSemAPorta } from "../../porta-ausente.ts";
import { dataComIdade, diaFeitoValido, motivoDoAviso, saidaDoDia, sinaisDeJaFeito } from "../../sinais-de-ja-feito.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const COLUNAS = "id, service_order_number, status, quote_status, converted_to_os_at, grand_total, original_quote_amount, signed_at, payment_conditions";

type Orcamento = {
  id: string;
  service_order_number: string | null;
  status: string;
  quote_status: string | null;
  converted_to_os_at: string | null;
  grand_total: number | null;
  original_quote_amount: number | null;
  signed_at: string | null;
  payment_conditions: string | null;
};

// deno-lint-ignore no-explicit-any
async function lerOrcamento(sb: any, ref: string): Promise<Orcamento | null> {
  let q = sb.from("service_orders").select(COLUNAS);
  q = UUID_RE.test(ref) ? q.eq("id", ref) : q.eq("service_order_number", ref);
  const { data, error } = await q.maybeSingle();
  if (error) throw error;
  return (data as Orcamento | null) ?? null;
}

/** Recusa o que não é orçamento convertível. null = pode converter. */
export function recusaParaConverter(o: Orcamento): { error: string } | null {
  const n = o.service_order_number ?? "O orçamento";
  if (o.converted_to_os_at || o.status !== "draft") return { error: `${n} já é OS — não há o que converter.` };
  if (o.quote_status === "rejected") {
    return { error: `${n} está Reprovado. Volte para "Em elaboração" (update_quote_status → draft) antes de converter.` };
  }
  return null;
}

/** ORÇ-00042 → OS-00042 (sequência única: orçamento e OS dividem o contador). */
export function numeroDaOS(numero: string | null): string | null {
  if (!numero) return numero;
  return numero.startsWith("ORÇ-") ? numero.replace("ORÇ-", "OS-") : numero;
}

/**
 * Retorno F5 (P11.1, C-CONV): as opções do núcleo. `via: "assistente"` é o caminho de sempre (a ferramenta). `via: "dono"` é o
 * *sim <PIN>* do cartão (o aceite por texto, B ou D): a porta recebe p_via = 'dono' e o motivo (até 200 caracteres), e o
 * total que o dono viu no cartão (`totalVisto`) tem de ser o de agora (até R$ 0,01), senão recusa antes de tocar na condição.
 * `retrato` é o do "sim" da ferramenta (o mesmo teste de sempre, com a frase de sempre).
 */
export interface OpcoesDoNucleo {
  via: "assistente" | "dono";
  autor: string | null;
  motivo?: string;
  totalVisto?: number | null;
  retrato?: Record<string, unknown> | null;
  /** (18/11/2026) o serviço JÁ FOI FEITO: a porta converte direto em concluída (não entra na agenda). */
  jaConcluida?: boolean;
  /** O dia em que foi feito (AAAA-MM-DD) — a saída fica às 17:00 desse dia. Sem ele, agora. */
  concluidaEm?: string | null;
}

/** O código da recusa, para quem chama o núcleo (o cartão). A ferramenta devolve só o `error`, como antes. */
export type CodigoDoNucleo = "nao_encontrado" | "ja_os" | "reprovado" | "mudou" | "so_condicao";

type ResultadoDoNucleo = Record<string, unknown> & { error?: string; codigo?: CodigoDoNucleo };

const MOTIVO_MAX = 200;

/** Mais de R$ 0,01 de diferença (em centavos, sem o erro do ponto flutuante). */
function mudouMaisDeUmCentavo(a: number, b: number): boolean {
  return Math.abs(Math.round(a * 100) - Math.round(b * 100)) > 1;
}

/**
 * Retorno F5 (P11.1, C-CONV): o corpo da ferramenta, exportado. O mesmo caminho para o assistente (sem mudança de
 * comportamento) e para o cartão do retorno (via dono). Lança no erro de leitura ou de gravação, como a ferramenta lançava.
 */
// deno-lint-ignore no-explicit-any
export async function converterSemSinalNucleo(sb: any, ref: string, opcoes: OpcoesDoNucleo): Promise<ResultadoDoNucleo> {
  const o = await lerOrcamento(sb, ref);
  if (!o) return { error: `Orçamento não encontrado: "${ref}".`, codigo: "nao_encontrado" };
  const recusa = recusaParaConverter(o);
  if (recusa) return { ...recusa, codigo: o.converted_to_os_at || o.status !== "draft" ? "ja_os" : "reprovado" };

  // O "sim" foi sobre este orçamento com este total.
  const retrato = opcoes.retrato ?? null;
  const total = Number(o.grand_total) || 0;
  if (retrato && (retrato.id !== o.id || Math.abs(Number(retrato.total) - total) > 0.009)) {
    return {
      error: `${o.service_order_number} mudou desde o pedido (total era ${fmtCurrency(Number(retrato.total) || 0)}, agora ${fmtCurrency(total)}). Nada foi convertido — confirme de novo com o valor atual.`,
      codigo: "mudou",
    };
  }
  // (F5) o total que o dono viu no cartão: mudou, nada é tocado
  if (opcoes.totalVisto !== undefined && opcoes.totalVisto !== null && mudouMaisDeUmCentavo(Number(opcoes.totalVisto), total)) {
    return { error: "O orçamento mudou desde o cartão.", codigo: "mudou" };
  }

  const { data: presets, error: pErr } = await sb.from("payment_condition_presets").select("id, label, installments").eq("active", true);
  if (pErr) throw pErr;
  const condicao = condicaoTudoNaConclusao(presets ?? []);

  const { error: cErr } = await sb
    .from("service_orders")
    .update({ ...condicao, quote_status: "approved" })
    .eq("id", o.id);
  if (cErr) throw cErr;

  const soCondicao = (porque: string): ResultadoDoNucleo => ({
    error: `A condição de ${o.service_order_number} foi trocada para "${condicao.payment_conditions}", mas a conversão não aconteceu (${porque}). Confira na tela.`,
    codigo: "so_condicao",
  });
  // (F5) a via do dono leva o motivo (o id da mensagem do cliente); a do assistente, nada a mais
  const extra: Record<string, unknown> = { p_autor: opcoes.autor ?? null };
  if (opcoes.via === "dono" && opcoes.motivo) extra.p_motivo = opcoes.motivo.slice(0, MOTIVO_MAX);
  // (18/11/2026) já feito: orçamento → concluída na mesma chamada da porta, com a saída no dia em que foi feito
  const concluir = opcoes.jaConcluida === true;
  if (concluir && opcoes.concluidaEm) extra.p_check_out = saidaDoDia(opcoes.concluidaEm);
  let documento: string | null;
  let convertido: boolean;
  let concluida = false;
  const { data: porta, error: erroPorta } = await sb.rpc("os_transicionar_status",
    argumentosDaPortaCompleta(o.id, concluir ? "completed" : "approved", opcoes.via, extra));
  if (erroPorta) {
    if (ehSemDireitoNaPorta(erroPorta)) return soCondicao(String(erroPorta.message ?? "você não pode converter este orçamento"));
    if (!ehPortaAusente(erroPorta)) throw erroPorta;
    // sem a porta no banco (caminho de antes): só converte; concluir fica para a tela (o aviso abaixo diz)
    const antes = await statusPelaTelaSemAPorta(sb, o.id, "approved");
    documento = antes.numero ?? numeroDaOS(o.service_order_number);
    convertido = antes.convertido;
  } else {
    if (!porta?.ok) return soCondicao(String(porta?.texto ?? "o sistema recusou"));
    documento = porta.numero ?? numeroDaOS(o.service_order_number);
    convertido = porta.convertido === true;
    concluida = concluir && porta.para === "completed";
  }
  if (!convertido) return soCondicao("alguém converteu ao mesmo tempo?");

  const avisos: string[] = [];
  if (o.signed_at) avisos.push("O orçamento estava ASSINADO com outra condição: o cliente precisa assinar de novo.");
  if (concluir && !concluida) {
    avisos.push(`Converti, mas NÃO concluí: conclua a ${documento} pela tela, senão a agenda vai marcar dia para ela.`);
  }
  if (concluida) {
    return {
      ok: true,
      documento,
      orcamento_era: o.service_order_number,
      concluida: true,
      saida: porta?.check_out_at ?? null,
      agenda: "Nasceu concluída: não entra na agenda (nenhum dia marcado, nenhuma ficha, nenhuma via).",
      condicao: condicao.payment_conditions,
      condicao_anterior: o.payment_conditions || null,
      total: fmtCurrency(total),
      cobranca: String(porta?.cobrancas_texto ?? "").trim() || null,
      quando_paga: "A cobrança nasceu agora, na conclusão. Se o cliente já pagou, ligue o pagamento a ela.",
      ...(avisos.length ? { avisos } : {}),
    };
  }
  return {
    ok: true,
    documento,
    orcamento_era: o.service_order_number,
    condicao: condicao.payment_conditions,
    condicao_anterior: o.payment_conditions || null,
    total: fmtCurrency(total),
    quando_paga: "Valor inteiro na conclusão do serviço (a conta a receber nasce ao concluir).",
    ...(avisos.length ? { avisos } : {}),
  };
}

/** A recusa do ja_concluida/concluida_em, ou null. Sem banco: preValidar e execute usam a mesma. */
export function recusaDoJaFeito(args: Record<string, unknown> | null | undefined, hoje: Date): { error: string } | null {
  const ja = args?.ja_concluida;
  if (ja !== undefined && ja !== null && typeof ja !== "boolean") return { error: "ja_concluida é sim ou não (true/false)." };
  const dia = args?.concluida_em;
  if (ja === true && dia !== undefined && dia !== null && String(dia).trim() !== ""
      && !diaFeitoValido(String(dia).trim(), hoje)) {
    return { error: `Não entendi o dia em que o serviço foi feito ("${String(dia)}"): diga no formato AAAA-MM-DD, até hoje.` };
  }
  return null;
}

// deno-lint-ignore no-explicit-any
async function lerRecebido(sb: any, osId: string): Promise<number | null> {
  const { data, error } = await sb.from("receivables").select("paid_amount, status").eq("service_order_id", osId);
  if (error) return null; // não deu para conferir: o cartão diz, em vez de mostrar R$ 0
  return ((data ?? []) as { paid_amount: number | null; status: string | null }[])
    .filter((r) => r.status !== "cancelled")
    .reduce((s, r) => s + (Number(r.paid_amount) || 0), 0);
}

/**
 * O cartão do "sim" (buildPendingSummary): o orçamento resolvido (número, cliente, total, a data com a idade) e, com sinal de
 * serviço já feito, o aviso ANTES do "sim" — a OS-00129 entrou na agenda porque ninguém perguntou. Com ja_concluida, o cartão
 * diz que ela nasce concluída e não entra na agenda. Não começa com "⚠️" (isso viraria recusa: resumoQueRecusa).
 * null = não achou (o genérico segue; a execução recusa).
 */
// deno-lint-ignore no-explicit-any
export async function resumirConversaoSemSinal(sb: any, args: Record<string, unknown>, hoje: Date = new Date()): Promise<string | null> {
  const ref = String(args?.service_order_id ?? "").trim();
  if (!ref) return null;
  let q = sb.from("service_orders")
    .select(`${COLUNAS}, created_at, technician_notes, diagnosis, check_in_at, check_out_at, clients(name)`);
  q = UUID_RE.test(ref) ? q.eq("id", ref) : q.eq("service_order_number", ref);
  const { data: o, error } = await q.maybeSingle();
  if (error) throw error;
  if (!o) return null;
  const recebido = await lerRecebido(sb, o.id);
  const s = sinaisDeJaFeito({
    criadoEm: o.created_at, technicianNotes: o.technician_notes, diagnosis: o.diagnosis,
    checkInAt: o.check_in_at, checkOutAt: o.check_out_at, recebido,
  }, hoje);
  const ja = args?.ja_concluida === true;
  const dia = ja && args?.concluida_em ? String(args.concluida_em).trim() : null;
  const diaCurto = dia ? `${dia.slice(8, 10)}/${dia.slice(5, 7)}` : null;
  const cliente = (o.clients as { name?: string } | null)?.name?.trim();
  const total = fmtCurrency(Number(o.grand_total) || 0);
  const data = dataComIdade(s);
  const linhas = [
    ja
      ? `Converter ${o.service_order_number} em OS JÁ CONCLUÍDA${diaCurto ? ` (serviço feito em ${diaCurto})` : " (concluída agora)"}`
      : `Converter ${o.service_order_number} em OS sem sinal`,
    ...(cliente ? [`Cliente: ${cliente}`] : []),
    ja
      ? `Total: ${total}, 100% na entrega: a cobrança nasce agora, ao concluir.`
      : `Total: ${total}, 100% na entrega: a cobrança nasce na conclusão.`,
    ...(data ? [`Orçamento de ${data}.`] : []),
  ];
  if (ja) {
    linhas.push("Não entra na agenda: nenhum dia marcado, nenhuma ficha, nenhuma via ao técnico.");
  } else {
    const motivo = motivoDoAviso(s);
    if (motivo) {
      linhas.push(`Atenção: ${motivo}. Se o serviço JÁ FOI FEITO, não responda sim: diga *já foi feito* (e o dia, se lembrar) e eu converto a OS já concluída, sem entrar na agenda.`);
    }
  }
  if (recebido === null) linhas.push("Não consegui conferir se já entrou dinheiro neste orçamento.");
  if (o.signed_at) linhas.push("O orçamento está assinado com outra condição: o cliente vai precisar assinar de novo.");
  return linhas.join("\n");
}

export const converterSemSinalTools: ToolDef[] = [
  {
    name: "converter_sem_sinal",
    description:
      "Converte um ORÇAMENTO em OS SEM sinal: o cliente paga o valor inteiro na CONCLUSÃO do serviço (ex.: orçamento adicional de quem já tem serviço em andamento, 'acerta tudo no final', 'pode tocar sem entrada'). " +
      "Numa ação só: troca a condição de pagamento para '100% na entrega', marca o orçamento como aprovado e converte (ORÇ-00042 vira OS-00042). A conta a receber nasce na conclusão, vencendo no dia. " +
      "Serviço que JÁ FOI FEITO (o dono diz 'já foi feito', 'já fizemos', 'já entregamos'): ja_concluida=true e, se ele disser, concluida_em — a OS nasce concluída e não entra na agenda. " +
      "NÃO use quando houver sinal: sinal já pago → register_deposit_and_convert; sinal a cobrar → siga o playbook de aprovação. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID ou número do orçamento (ORÇ-00112)." },
        ja_concluida: {
          type: "boolean",
          description: "true SÓ quando o dono disser que o serviço JÁ FOI FEITO: converte direto em concluída (a cobrança nasce agora) e a OS não entra na agenda.",
        },
        concluida_em: { type: "string", description: "Com ja_concluida: o dia em que o serviço foi feito (AAAA-MM-DD), se o dono disser. Sem ele, hoje." },
      },
      required: ["service_order_id"],
    },
    risk: "medium",
    roles: NON_TECHNICIAN_ROLES,
    preValidar(args, ctx) {
      if (ctx.userRole === "technician") return { error: "Cargo não autorizado para esta ação." };
      if (!String(args?.service_order_id ?? "").trim()) return { error: "Diga qual orçamento converter (o número ORÇ)." };
      return recusaDoJaFeito(args, new Date());
    },
    async retratoDaPendencia(args, ctx) {
      const o = await lerOrcamento(ctx.sb, String(args.service_order_id ?? "").trim());
      if (!o) return null;
      return { id: o.id, numero: o.service_order_number, total: Number(o.grand_total) || 0 };
    },
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const ref = String(args.service_order_id ?? "").trim();
      const recusa = recusaDoJaFeito(args, new Date());
      if (recusa) return recusa;
      const jaConcluida = args.ja_concluida === true;
      const concluidaEm = jaConcluida && String(args.concluida_em ?? "").trim() ? String(args.concluida_em).trim() : null;
      // (F5, P11.1) o corpo virou o núcleo, sem mudança para o assistente; o código da recusa fica só no núcleo
      const { codigo: _codigo, ...r } = await converterSemSinalNucleo(ctx.sb, ref, {
        via: "assistente", autor: ctx.userId ?? null, retrato: lerRetrato(args),
        ...(jaConcluida ? { jaConcluida, concluidaEm } : {}),
      });
      return r;
    },
  },
];
