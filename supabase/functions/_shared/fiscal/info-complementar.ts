// [NOVO-fiscal-03] O vínculo legível entre a nota e a ordem de serviço.
//
// As duas notas da OS-00075 saíram sem nada que as ligasse ao trabalho: o quadro
// "INFORMAÇÕES COMPLEMENTARES" veio vazio nas duas. Sem isso a nota chega ao
// cliente e à contabilidade sem referência ao serviço que a originou, e conciliar
// passa a depender de alguém lembrar.
//
// ═══ POR QUE OS DOIS DOCUMENTOS USAM CAMPOS DIFERENTES ═══
//
// NF-e: `additionalInfo` → `additional_info` → `infCpl`. O construtor já
// suportava, testado; a ponte da OS é que nunca preenchia.
//
// NFS-e: o padrão nacional tem `xInfComp` (`docs/nfse-nacional/rn_dps.tsv:384`),
// mas o nome dele no JSON da Contora não está documentado no repositório —
// e nome errado o provedor ignora em silêncio, o que daria um campo que parece
// preenchido e não está. Lá o texto entra na DISCRIMINAÇÃO DOS SERVIÇOS, que
// comprovadamente imprime no DANFSe. Ver NOVO-fiscal-04.
//
// ═══ O QUE NÃO ENTRA ═══
//
// Nada de garantia, prazo ou condição de pagamento. O que a nota afirma vincula
// a empresa, e inventar cláusula fiscal em nome do dono não é decisão de código.
// Quando ele quiser texto fixo próprio, isto vira campo em `app_settings` e a
// função ganha um parâmetro.
//
// O rateio do desconto NÃO mora aqui: é `rateio-desconto.ts`. Na NFS-e a linha
// "Desconto comercial aplicado" já é montada pela própria ponte; na NF-e o
// desconto vive no `vDesc` de cada item, e a menção em texto só existe para
// explicar por que o total difere do orçamento.

export interface InfoComplementarInput {
  /** `service_orders.service_order_number` — o vínculo com o trabalho. */
  osNumero?: string | null;
  /** Pedido de compra do cliente, quando informado. */
  pedidoCliente?: string | null;
  /** Desconto abatido NESTE documento, quando houver. */
  descontoAplicado?: number | null;
}

const brl = (n: number) =>
  n.toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/**
 * Monta o texto, ou devolve `null` quando não há nada de útil a dizer.
 *
 * Devolver `null` importa: os construtores só incluem o campo quando ele tem
 * conteúdo, e um quadro com texto vazio é pior que quadro ausente.
 */
export function montarInfoComplementar(input: InfoComplementarInput): string | null {
  const partes: string[] = [];

  const os = String(input.osNumero ?? "").trim();
  if (os) partes.push(`Ref. Ordem de Serviço ${os}.`);

  const pedido = String(input.pedidoCliente ?? "").trim();
  if (pedido) partes.push(`Pedido do cliente: ${pedido}.`);

  const desconto = Number(input.descontoAplicado) || 0;
  if (desconto > 0) {
    // Responde à pergunta que a contabilidade faria ao conciliar: por que esta
    // nota é menor que o orçamento.
    partes.push(`Desconto comercial de R$ ${brl(desconto)} já abatido nos valores desta nota.`);
  }

  if (partes.length === 0) return null;
  return partes.join(" ");
}

/**
 * A referência curta que vai na DISCRIMINAÇÃO DOS SERVIÇOS da NFS-e.
 *
 * Separada da versão da NF-e porque ali o espaço é disputado: a discriminação
 * tem 500 caracteres e já carrega a lista de serviços, deslocamento, custos e
 * desconto. Só o essencial cabe.
 */
export function referenciaCurtaDaOs(osNumero?: string | null): string | null {
  const os = String(osNumero ?? "").trim();
  return os ? `Ref. OS ${os}` : null;
}
