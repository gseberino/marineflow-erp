// [F-DESC-03] O texto das INFORMAÇÕES COMPLEMENTARES das notas.
//
// As duas notas da OS-00075 saíram com esse quadro em branco. Do lado da NF-e o
// campo já existia e era testado (`additionalInfo` → `additional_info` →
// `infCpl`): a ponte da OS só nunca passava valor. Do lado da NFS-e o padrão
// nacional tem `xInfComp` (rn_dps.tsv:384), mas o nome do campo no JSON da
// Contora não está documentado no repositório — mandar um nome adivinhado seria
// o provedor ignorar em silêncio. Lá o texto entra na DISCRIMINAÇÃO DOS
// SERVIÇOS, que comprovadamente imprime no DANFSe.
//
// O CONTEÚDO é deliberadamente mínimo e factual: número da OS, pedido do cliente
// e a existência do desconto. Nada de garantia, prazo ou condição de pagamento —
// o que a nota afirma vincula a empresa, e inventar cláusula fiscal em nome do
// dono não é decisão de código. Quando ele quiser texto fixo próprio, isto vira
// um campo em `app_settings` e esta função ganha um parâmetro.

export interface InfoComplementarInput {
  /** `service_orders.service_order_number` — o vínculo legível com o trabalho. */
  osNumero?: string | null;
  /** Pedido de compra do cliente, quando informado. */
  pedidoCliente?: string | null;
  /** Fatia do desconto da ordem que este documento abateu. */
  descontoDaOrdem?: number | null;
  /** "peças" ou "serviços" — o que o desconto abateu nesta nota. */
  rotuloDesconto?: string;
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

  const desconto = Number(input.descontoDaOrdem) || 0;
  if (desconto > 0) {
    const rotulo = input.rotuloDesconto ? ` sobre ${input.rotuloDesconto}` : "";
    // Explica por que a nota é menor que o orçamento — a pergunta que a
    // contabilidade faria ao conciliar.
    partes.push(`Desconto de R$ ${brl(desconto)}${rotulo} já abatido nos valores desta nota.`);
  }

  if (partes.length === 0) return null;
  return partes.join(" ");
}
