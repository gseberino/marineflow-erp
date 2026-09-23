/**
 * Ler uma nota emitida: NF-e e NFS-e guardam as MESMAS coisas em lugares diferentes.
 *
 * O payload de cada tipo nasce no formato que a API do provedor exige, e os dois formatos
 * não conversam: a NF-e tem `recipient`, `items` e `payments`; a NFS-e tem `taker`,
 * `service` e `amounts`. Quem lê a lista não quer saber disso — quer saber para quem foi a
 * nota, de quando ela é e quanto deu. Estas funções são esse tradutor, e ficam juntas de
 * propósito: a próxima diferença entre os padrões tem um lugar óbvio para ser acomodada.
 *
 * Nota já emitida não admite aproximação: o número na tela tem que ser o mesmo do DANFE,
 * no centavo. Por isso `totalDaNota` reproduz a conta do vNF e o teste confere contra os
 * XMLs realmente autorizados pela SEFAZ.
 */

/** O que a tela precisa saber de uma nota para exibi-la numa linha de lista. */
export interface ResumoDaNota {
  tipo: 'NF-e' | 'NFS-e' | 'NFC-e';
  tomador: { nome: string; documento: string };
  total: number;
  itens: number | null;
  natureza: string;
  data: string | null;
}

type Payload = Record<string, any>;

function payloadDe(doc: unknown): Payload {
  return ((doc as { request_payload?: Payload })?.request_payload ?? {}) as Payload;
}

/** Duas casas, sem o erro de ponto flutuante que faz 1,005 virar 1,00. */
function duasCasas(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function numero(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** Para quem a nota foi emitida. É o dado que faltava para achar uma nota na lista. */
export function tomadorDaNota(doc: unknown): { nome: string; documento: string } {
  const p = payloadDe(doc);
  const lado = p.recipient ?? p.taker ?? {};
  const nome = String(lado?.name ?? '').trim();
  const documento = String(
    lado?.cpf_cnpj ?? lado?.document ?? lado?.cnpj ?? lado?.cpf ?? '',
  ).trim();
  return { nome, documento };
}

/**
 * O valor total da nota — o mesmo número que está no DANFE.
 *
 * A versão anterior lia `payments[0].amount`, que é a forma de pagamento declarada. Para
 * venda isso coincide com o total, mas **devolução não tem pagamento**: as notas 2/22,
 * 2/23 e 2/24 apareciam como R$ 0,00 na lista, sendo que valem R$ 2.357,14, R$ 1.146,32 e
 * R$ 1.862,55. E a NFS-e nem tem `payments`, então as cinco notas de serviço também
 * apareciam zeradas.
 *
 * Agora a conta é a da própria NF-e:
 *
 *     vNF = Σ (quantidade × preço unitário) − desconto + outras despesas + IPI devolvido
 *
 * Cada linha é arredondada antes de somar, que é o que o XML faz — somar tudo e arredondar
 * no fim pode dar um centavo de diferença quando a nota tem muitos itens.
 *
 * Conferido contra os XMLs autorizados pela SEFAZ (ver o teste): 2/24 → 1.862,55 e
 * 2/29 → 17.568,17, batendo no centavo com a tag `vNF`.
 */
export function totalDaNota(doc: unknown): number {
  const p = payloadDe(doc);

  if (Array.isArray(p.items) && p.items.length > 0) {
    let total = 0;
    for (const item of p.items as Payload[]) {
      const bruto = duasCasas(numero(item?.quantity) * numero(item?.unit_price));
      total += bruto
        - numero(item?.discount)
        + numero(item?.other_expenses)
        + numero(item?.returned_ipi?.value);
    }
    return duasCasas(total);
  }

  // NFS-e: o líquido é o que o tomador deve; `service_amount` cobre a nota sem desconto,
  // onde os dois são iguais.
  const daNfse = numero(p.amounts?.net_amount ?? p.amounts?.service_amount);
  if (daNfse > 0) return duasCasas(daNfse);

  // Último recurso: a forma de pagamento declarada. Só sobra para nota sem item nenhum.
  return duasCasas(numero(p.payments?.[0]?.amount));
}

/**
 * A data da nota — a que está impressa no documento, não a da linha no banco.
 *
 * `created_at` é quando a LINHA nasceu, e o banco a guarda em UTC. Para uma nota emitida
 * às 22h22 de 27/08 isso vira "28/08 01:22", e a tela passava a discordar do documento
 * por um dia inteiro. Foi o caso real das NFS-e 1/3 e 1/4.
 *
 * A ordem abaixo é de confiabilidade decrescente:
 *
 *  1. `provider_status.sefaz.authorized_at` — o carimbo da SEFAZ na NF-e, já com fuso
 *     ("-03:00"), então não há conversão para errar;
 *  2. `provider_status.latest_event.created_at` do evento de autorização — o equivalente
 *     na NFS-e, que não preenche a coluna `authorized_at`;
 *  3. a coluna `authorized_at`;
 *  4. `created_at`, que sobra para rascunho, rejeitada e fila — e aí é honesta: é a data
 *     da tentativa, porque nota não autorizada não tem data de autorização.
 */
export function dataDaNota(doc: unknown): string | null {
  const d = doc as {
    authorized_at?: string | null;
    created_at?: string | null;
    provider_status?: Payload | null;
  };
  const provedor = (d?.provider_status ?? {}) as Payload;

  const daSefaz = provedor?.sefaz?.authorized_at;
  if (typeof daSefaz === 'string' && daSefaz) return daSefaz;

  const evento = provedor?.latest_event;
  if (evento?.status === 'authorized' && typeof evento?.created_at === 'string' && evento.created_at) {
    return evento.created_at;
  }

  return d?.authorized_at || d?.created_at || null;
}

/**
 * A natureza da operação — venda, devolução, remessa.
 *
 * Duas notas do mesmo cliente e do mesmo valor podem ser coisas opostas: uma cobra, a
 * outra estorna. Sem esta coluna a lista não deixava distinguir, e a devolução ainda por
 * cima aparecia zerada.
 */
export function naturezaDaNota(doc: unknown): string {
  const p = payloadDe(doc);
  const declarada = String(p.nature_operation ?? '').trim();
  if (declarada) return declarada;
  // NFS-e não declara natureza: é sempre prestação de serviço.
  if (p.service || p.taker) return 'Prestação de serviço';
  return '';
}

/** Devolução muda o sinal do dinheiro; vale destacar na lista. */
export function ehDevolucao(doc: unknown): boolean {
  const p = payloadDe(doc);
  return Number(p.purpose) === 4;
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
  const p = payloadDe(doc);
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
    natureza: naturezaDaNota(doc),
    data: dataDaNota(doc),
  };
}

/**
 * Tudo que se pode digitar para achar uma nota, num texto só.
 *
 * Busca por número, por tomador, por documento, por natureza e pela chave de acesso — que
 * é como a contadora costuma pedir a nota.
 */
export function textoBuscavelDaNota(doc: unknown): string {
  const d = doc as Record<string, any>;
  const { nome, documento } = tomadorDaNota(doc);
  return [
    `${d?.series ?? ''}/${d?.number ?? ''}`,
    d?.number,
    nome,
    documento,
    documento.replace(/\D/g, ''),
    naturezaDaNota(doc),
    tipoDaNota(doc),
    d?.access_key,
    d?.status_message,
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
}
