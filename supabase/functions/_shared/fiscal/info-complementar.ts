// [NOVO-fiscal-03/04] O vínculo legível entre a nota e a ordem de serviço.
//
// As duas notas da OS-00075 saíram sem nada que as ligasse ao trabalho: o quadro
// "INFORMAÇÕES COMPLEMENTARES" veio vazio nas duas. Sem isso a nota chega ao
// cliente e à contabilidade sem referência ao serviço que a originou, e
// conciliar passa a depender de alguém lembrar.
//
// ═══ OS DOIS DOCUMENTOS, AGORA COM CAMPO PRÓPRIO ═══
//
// NF-e: `additionalInfo` → `additional_info` → `infCpl`. O construtor já
// suportava, testado; a ponte da OS é que nunca preenchia.
//
// NFS-e: `service.additional_info` → `serv/infoCompl/xInfComp`. Este campo NÃO
// EXISTIA na API da Contora: foi criado por eles em 06/09/2026 a pedido nosso,
// junto com os de desconto. Até lá a referência era empurrada para dentro da
// discriminação dos serviços, disputando os 500 caracteres com a lista de
// serviços. Limite de 2000 caracteres, e o excesso é RECUSADO, não truncado.
//
// ═══ O QUE NÃO ENTRA ═══
//
// Nada de garantia, prazo ou condição de pagamento. O que a nota afirma vincula
// a empresa, e inventar cláusula fiscal em nome do dono não é decisão de código.
// Quando ele quiser texto fixo próprio, isto vira campo em `app_settings` e a
// função ganha um parâmetro.
//
// O desconto TAMBÉM não entra mais aqui. Ele tem campo próprio nos dois
// documentos — `vDesc` por item na NF-e, `vDescIncond` na NFS-e — e sai
// discriminado no DANFE e no DANFSe. Repetir por extenso faria o tomador ler o
// mesmo abatimento duas vezes e suspeitar de desconto em dobro.

export interface InfoComplementarInput {
  /** `service_orders.service_order_number` — o vínculo com o trabalho. */
  osNumero?: string | null;
  /** Pedido de compra do cliente, quando informado. */
  pedidoCliente?: string | null;
}

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

  if (partes.length === 0) return null;
  return partes.join(" ");
}
