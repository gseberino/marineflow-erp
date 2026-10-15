// O contato disse que fechou com outra empresa ou que não quer mais — regra de palavras, sem IA.
//
// ═══ POR QUE EXISTE ═══
//
// O "esperando resposta" do resumo e o acompanhamento de conversa só sabiam que uma conversa
// acabou quando a ÚLTIMA mensagem era "ok/obrigado". Caso de 07/10/2026 (Miguel): às 14:15 ele
// escreveu "André você demora muito pra responder e por isso acabei fechando com outra empresa.
// Obrigado", às 14:58 "Sim, já fechei" — e o sistema seguiu cobrando resposta e avisando o dono
// por mais três dias. A última mensagem sozinha ("Sim, já fechei") é ambígua; por isso a conversa
// é julgada pelas 5 últimas recebidas (quem lê decide a janela de dias — o resumo usa 7).
//
// Usado pelo resumo da manhã (ai-daily-briefing) e pelo vigia de conversas (acompanhar-conversas).
// A regra erra para o lado de NÃO encerrar: frase ambígua continua na lista.

// Regra de palavras (sem IA): o contato disse que fechou com outra empresa ou que não quer mais.
//
// Revisão de 15/10/2026 — dois erros que tiravam da lista justamente quem mais pede resposta:
//  · o verbo valia em qualquer tempo: "vou fechar com outra empresa se não me responderem" (a
//    AMEAÇA de ir embora, o Miguel antes de sair) encerrava. Agora só o que já aconteceu: passado
//    ou "acabei fechando".
//  · "não quero/preciso mais" valia seguido de qualquer coisa: "não quero mais esperar" (cliente
//    impaciente) e "não preciso mais de peixe" (mensagem real de 25/07) encerravam. Agora só quando
//    a frase acaba ali ou fala do serviço/orçamento.
// E "com outro" precisa ser alguém ("outra empresa/oficina/pessoa…", "com outro." no fim): "resolvi
// o problema com outro cabo" não é ter fechado com outra empresa.
const JA_DECIDIU = String.raw`(?:fech(?:ei|amos|ou|aram|ando)|contrat(?:ei|amos|ou|aram|ando)|opt(?:ei|amos|ou|aram|ando)|escolh(?:i|emos|eu|eram|endo)|compr(?:ei|amos|ou)|resolv(?:i|emos|eu)|fiz(?:emos)?|fez)`;
const OUTRO = String.raw`(?:outr[oa]s?(?:\s+(?:empresa|oficina|pessoa|t[eé]cnico|profissional|fornecedor|firma|loja|marina|estaleiro|equipe|cara|rapaz|mo[cç]o)s?\b|(?=\s*(?:$|[.!?,;)]|e\b|mas\b|obrigad)))|concorr[eê]n(?:te|cia))`;
const COM_OUTRO = new RegExp(String.raw`\b${JA_DECIDIU}\s+[^.!?\n]{0,25}?\bcom\s+(?:o\s+|a\s+|uma?\s+)?${OUTRO}`, "i");
const ALVO = String.raw`(?:servi[cç]o|or[cç]amento|conserto|reparo|instala[cç][aã]o|proposta|trabalho)`;
const SEM_INTERESSE = new RegExp(
  String.raw`\bn[aã]o\s+(?:tenho|temos)\s+mais\s+interesse\b` +
    String.raw`|\bn[aã]o\s+(?:quero|queremos|vou\s+querer|preciso|precisamos)\s+mais(?=\s*(?:$|[.!?,;)]|obrigad|valeu|n[aã]o\b|(?:d?[oa]s?|esse|essa|este|esta)\s+${ALVO}))` +
    String.raw`|\bdesisti(?:mos)?\s+d[oa]\s+${ALVO}\b`,
  "i",
);
// "desisti" sozinho fica de fora de propósito ("desisti de ir hoje" não é desistência do serviço).

/** Quantas mensagens recebidas (as mais recentes) a regra olha. */
export const ULTIMAS_RECEBIDAS = 5;

/** O motivo gravado quando a regra encerra um acompanhamento. */
export const MOTIVO_CONTATO_ENCERROU = "contato encerrou (fechou com outra empresa ou desistiu)";

/**
 * A mensagem diz que o contato fechou com outra empresa ou desistiu do serviço. Pergunta DEPOIS da
 * frase, na mesma mensagem, é pedido (revisão de 15/10/2026): "Comprei a peça com outro fornecedor,
 * vocês instalam?" espera resposta — comprou só a peça e quer o serviço.
 */
export function contatoEncerrou(texto: string | null | undefined): boolean {
  const t = String(texto ?? "").trim();
  if (!t) return false;
  for (const regra of [COM_OUTRO, SEM_INTERESSE]) {
    const m = regra.exec(t);
    if (m && !t.slice(m.index + m[0].length).includes("?")) return true;
  }
  return false;
}

/**
 * recebidas em ordem da MAIS RECENTE; olha as 5 primeiras. Pergunta DEPOIS da desistência reabre
 * (revisão de 15/10/2026): "não quero mais o orçamento" seguido de "pensando bem, quando vocês
 * podem vir?" é alguém esperando resposta. O "Sim, já fechei" do Miguel não pergunta nada.
 */
export function conversaEncerradaPeloContato(recebidas: Array<string | null | undefined>): boolean {
  const ultimas = (Array.isArray(recebidas) ? recebidas : []).slice(0, ULTIMAS_RECEBIDAS);
  const i = ultimas.findIndex(contatoEncerrou);
  if (i < 0) return false;
  return !ultimas.slice(0, i).some((t) => String(t ?? "").includes("?"));
}
