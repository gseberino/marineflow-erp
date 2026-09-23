/**
 * Ler uma nota emitida: NF-e e NFS-e guardam as MESMAS coisas em lugares diferentes.
 *
 * O payload de cada tipo nasce no formato que a API do provedor exige, e os dois formatos
 * não conversam: a NF-e tem `recipient`, `items` e `payments`; a NFS-e tem `taker`,
 * `service` e `amounts`. Quem lê a lista não quer saber disso — quer saber para quem foi a
 * nota e quanto deu. Estas funções são esse tradutor, e ficam juntas de propósito: a
 * próxima diferença entre os padrões tem um lugar óbvio para ser acomodada.
 */

/** O que a tela precisa saber de uma nota para exibi-la numa linha de lista. */
export interface ResumoDaNota {
  tipo: 'NF-e' | 'NFS-e' | 'NFC-e';
  tomador: { nome: string; documento: string };
  total: number;
  itens: number | null;
}

/** Para quem a nota foi emitida. É o dado que faltava para achar uma nota na lista. */
export function tomadorDaNota(doc: unknown): { nome: string; documento: string } {
  const p = (doc as { request_payload?: Record<string, any> })?.request_payload ?? {};
  const lado = p.recipient ?? p.taker ?? {};
  const nome = String(lado?.name ?? '').trim();
  const documento = String(
    lado?.cpf_cnpj ?? lado?.document ?? lado?.cnpj ?? lado?.cpf ?? '',
  ).trim();
  return { nome, documento };
}

/**
 * O valor da nota.
 *
 * A NFS-e não tem `payments` — e a lista lia só de lá, então as cinco notas de serviço
 * apareciam como R$ 0,00 (conferido em 23/09/2026). O líquido vem primeiro porque é o que
 * o tomador deve; `service_amount` cobre a nota sem desconto, onde os dois são iguais.
 */
export function totalDaNota(doc: unknown): number {
  const p = (doc as { request_payload?: Record<string, any> })?.request_payload ?? {};
  const daNfe = Number(p.payments?.[0]?.amount ?? 0);
  if (Number.isFinite(daNfe) && daNfe > 0) return daNfe;
  const daNfse = Number(p.amounts?.net_amount ?? p.amounts?.service_amount ?? 0);
  return Number.isFinite(daNfse) ? daNfse : 0;
}

/**
 * Quantos itens a nota tem.
 *
 * Na NF-e é uma contagem exata. Na NFS-e não existe lista de itens: o que existe é uma
 * descrição única onde os serviços foram unidos por "; " na emissão — então contar os
 * trechos é uma aproximação, e por isso a linha de desconto (que é um aviso, não um
 * serviço) sai da conta. Vale mais que deixar a coluna vazia, mas não é para ser somado.
 */
export function itensDaNota(doc: unknown): number | null {
  const p = (doc as { request_payload?: Record<string, any> })?.request_payload ?? {};
  if (Array.isArray(p.items)) return p.items.length;
  const descricao = String(p.service?.description ?? '').trim();
  if (!descricao) return null;
  return descricao
    .split(';')
    .map((t) => t.trim())
    .filter((t) => t && !/^desconto comercial aplicado/i.test(t)).length;
}

/** NF-e, NFS-e ou NFC-e — a lista mostra os três juntos e não dizia qual era qual. */
export function tipoDaNota(doc: unknown): ResumoDaNota['tipo'] {
  const t = String(
    (doc as { document_type?: string })?.document_type ?? 'nfe',
  ).toLowerCase();
  return t === 'nfse' ? 'NFS-e' : t === 'nfce' ? 'NFC-e' : 'NF-e';
}

/** Tudo de uma vez, para quem monta a linha. */
export function resumirNota(doc: unknown): ResumoDaNota {
  return {
    tipo: tipoDaNota(doc),
    tomador: tomadorDaNota(doc),
    total: totalDaNota(doc),
    itens: itensDaNota(doc),
  };
}
