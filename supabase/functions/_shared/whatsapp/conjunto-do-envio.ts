/**
 * "Agrupar para o cliente" (migration 20270124100000): o PDF do conjunto leva vários orçamentos num envio só. O
 * whatsapp-send marca como enviado o orçamento do service_order_id e, também, os OUTROS orçamentos que a tela manda em
 * conjunto_orcamento_ids — mas só os que estão, de fato, no mesmo conjunto ATIVO. Id que não está lá é ignorado: o
 * envio já saiu e não falha por isso.
 */

/** Os pedidos que valem: no conjunto, sem repetir e sem o próprio principal. Puro. */
export function orcamentosQueValem(principal: string, pedidos: string[], noConjunto: string[]): string[] {
  const conjunto = new Set(noConjunto);
  return [...new Set(pedidos)].filter((id) => id !== principal && conjunto.has(id));
}

type Leitor = {
  from: (t: string) => any;
};

/** Lê o conjunto ativo do principal e devolve os outros orçamentos pedidos que estão nele. Nunca lança. */
export async function outrosOrcamentosDoConjunto(db: Leitor, principal: string, pedidos?: string[] | null): Promise<string[]> {
  if (!pedidos || pedidos.length === 0) return [];
  try {
    const { data: meu, error: e1 } = await db.from("documento_conjunto_itens")
      .select("conjunto_id").eq("service_order_id", principal).eq("ativo", true).maybeSingle();
    if (e1 || !meu?.conjunto_id) return [];
    const { data: itens, error: e2 } = await db.from("documento_conjunto_itens")
      .select("service_order_id").eq("conjunto_id", meu.conjunto_id).eq("ativo", true);
    if (e2 || !Array.isArray(itens)) return [];
    return orcamentosQueValem(principal, pedidos, itens.map((i: { service_order_id: string }) => i.service_order_id));
  } catch (e) {
    console.warn("[whatsapp-send] conjunto do envio não lido:", e instanceof Error ? e.message : e);
    return [];
  }
}
