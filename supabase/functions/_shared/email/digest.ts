// Renderização da seção de e-mail no resumo matinal — lógica pura, sem banco.
//
// É aqui que a pesquisa vira regra de código. Três achados mandam neste arquivo:
//  · digest agrupado rende mais que alerta avulso (+35% engajamento, −28% opt-out);
//  · o teto prático é 3-5 avisos/dia — acima disso o usuário desliga tudo;
//  · notificação dispensada é PIOR que nenhuma, porque ensina a ignorar as próximas.
//
// Consequência: esta seção mostra POUCO de propósito. O que não couber vira contagem,
// não vira linha. E `ignore` nunca aparece individualmente — só no total, para o usuário
// poder auditar quanto foi filtrado sem ter que ler o que foi filtrado.

import type { TriageClass } from "./triage.ts";

export interface EmailDigestItem {
  classe: TriageClass;
  /** Rótulo humano já resolvido no backend: nome do cliente/fornecedor, ou o endereço. */
  remetente: string;
  assunto: string | null;
  recebidoEm: string;
  /** Linha pronta de anexo reconhecido (NF-e/boleto), quando houver. */
  resumoAnexo?: string | null;
  alertaFraude?: boolean;
  /** O mesmo remetente e assunto já foi avisado na hora (email-imap, alerted_at) antes de hoje.
   *  Sai do bloco "Urgente" e vira número no rodapé: aviso repetido ensina a ignorar (15/10/2026:
   *  o mesmo golpe avisado em 13 e 14/10 voltou como "Urgente" nos resumos de 14 e 15/10). */
  jaAvisado?: boolean;
}

export interface DigestOpts {
  /** Teto de itens por categoria dentro do digest. */
  maxPorCategoria?: number;
  /** Teto duro de alertas urgentes. Nunca ultrapassar — é a regra que protege a atenção. */
  maxUrgentes?: number;
}

export const MAX_URGENTES_PADRAO = 3;
const MAX_POR_CATEGORIA_PADRAO = 3;

function linha(item: EmailDigestItem): string {
  const assunto = (item.assunto ?? "").trim();
  const corpo = assunto ? `"${assunto.slice(0, 60)}"` : "(sem assunto)";
  const anexo = item.resumoAnexo ? ` · ${item.resumoAnexo}` : "";
  return `· ${item.remetente}: ${corpo}${anexo}`;
}

/**
 * A chave "mesmo e-mail" para saber se um urgente já foi avisado: endereço em minúsculas + assunto
 * normalizado (minúsculas, sem "re:"/"fwd:" na frente, espaços colapsados).
 */
export function chaveDoAviso(endereco: string | null | undefined, assunto: string | null | undefined): string {
  const de = String(endereco ?? "").trim().toLowerCase();
  let a = String(assunto ?? "").toLowerCase().replace(/\s+/g, " ").trim();
  for (;;) {
    const sem = a.replace(/^(?:re|res|fw|fwd|enc|encaminhad[ao])\s*:\s*/, "");
    if (sem === a) break;
    a = sem;
  }
  return `${de}|${a}`;
}

/** O texto do golpe não afirma o que o e-mail pede: a triagem marca fraude para qualquer golpe. */
const AVISO_DE_GOLPE = "  ⚠️ *possível golpe — não pague nem responda antes de confirmar por telefone*";

/**
 * Urgentes que podem furar o silêncio fora de hora.
 * Ordena colocando suspeita de fraude na frente — é o item de maior dano possível —
 * e depois pelo mais recente. Corta no teto sem dó. O já avisado na hora não volta.
 */
export function selecionarUrgentes(
  itens: EmailDigestItem[],
  teto: number = MAX_URGENTES_PADRAO,
): EmailDigestItem[] {
  return itens
    .filter((i) => i.classe === "urgent" && !i.jaAvisado)
    .sort((a, b) => {
      const fa = a.alertaFraude ? 1 : 0;
      const fb = b.alertaFraude ? 1 : 0;
      if (fa !== fb) return fb - fa;
      return String(b.recebidoEm).localeCompare(String(a.recebidoEm));
    })
    .slice(0, Math.max(0, teto));
}

/**
 * Monta a seção do resumo matinal.
 * Devolve null quando não há nada que valha a pena dizer — seção vazia é ruído, e o
 * briefing não deve crescer só para provar que rodou.
 */
export function montarSecaoEmail(itens: EmailDigestItem[], opts: DigestOpts = {}): string | null {
  const lista = Array.isArray(itens) ? itens : [];
  if (lista.length === 0) return null;

  const maxCat = opts.maxPorCategoria ?? MAX_POR_CATEGORIA_PADRAO;
  const maxUrg = opts.maxUrgentes ?? MAX_URGENTES_PADRAO;

  const por = (c: TriageClass) => lista.filter((i) => i.classe === c);
  const urgentes = selecionarUrgentes(lista, maxUrg);
  const jaAvisados = lista.filter((i) => i.classe === "urgent" && i.jaAvisado).length;
  const respond = por("respond");
  const document = por("document");
  const notify = por("notify");
  const ignorados = por("ignore").length;

  // Nada além de ruído: uma linha só, para o filtro ficar auditável sem virar relatório.
  if (urgentes.length === 0 && respond.length === 0 && document.length === 0 && notify.length === 0) {
    if (jaAvisados > 0) {
      const r = [`${jaAvisados} ${plural(jaAvisados, "urgente já avisado", "urgentes já avisados")}`];
      if (ignorados > 0) r.push(`${ignorados} filtrado${ignorados > 1 ? "s" : ""}`);
      return `📧 E-mail: ${r.join(" · ")}.`;
    }
    return ignorados > 0 ? `📧 E-mail: ${ignorados} ${plural(ignorados, "mensagem", "mensagens")}, tudo ruído.` : null;
  }

  const partes: string[] = ["📧 *E-mail*"];

  if (urgentes.length > 0) {
    partes.push("");
    partes.push(`🔴 *Urgente* (${urgentes.length}):`);
    for (const u of urgentes) {
      partes.push(linha(u) + (u.alertaFraude ? AVISO_DE_GOLPE : ""));
    }
    const sobra = por("urgent").length - jaAvisados - urgentes.length;
    if (sobra > 0) partes.push(`  (+${sobra} ${plural(sobra, "outro urgente", "outros urgentes")} no sistema)`);
  }

  if (respond.length > 0) {
    partes.push("");
    partes.push(`✍️ *Esperando resposta* (${respond.length}):`);
    for (const r of respond.slice(0, maxCat)) partes.push(linha(r));
    if (respond.length > maxCat) partes.push(`  (+${respond.length - maxCat})`);
  }

  if (document.length > 0) {
    partes.push("");
    partes.push(`📎 *Documentos recebidos* (${document.length}):`);
    for (const d of document.slice(0, maxCat)) partes.push(linha(d));
    if (document.length > maxCat) partes.push(`  (+${document.length - maxCat})`);
  }

  // "notify" não vira lista: vira número. É a categoria mais volumosa e a menos acionável.
  const rodape: string[] = [];
  if (notify.length > 0) rodape.push(`${notify.length} informativo${notify.length > 1 ? "s" : ""}`);
  if (jaAvisados > 0) rodape.push(`${jaAvisados} ${plural(jaAvisados, "urgente já avisado", "urgentes já avisados")}`);
  if (ignorados > 0) rodape.push(`${ignorados} filtrado${ignorados > 1 ? "s" : ""}`);
  if (rodape.length > 0) {
    partes.push("");
    partes.push(`_${rodape.join(" · ")}_`);
  }

  return partes.join("\n");
}

function plural(n: number, um: string, muitos: string): string {
  return n === 1 ? um : muitos;
}

/**
 * Métrica de ruído do dia: quanto do que chegou foi escondido.
 * É o número que decide se o filtro continua ligado (§8 do plano) — sem isso, não há
 * como saber se a triagem está ajudando ou só sumindo com e-mail.
 */
export function taxaDeRuido(itens: EmailDigestItem[]): number {
  const total = itens.length;
  if (total === 0) return 0;
  return itens.filter((i) => i.classe === "ignore").length / total;
}
