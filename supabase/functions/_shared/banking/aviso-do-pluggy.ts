// O aviso do Pluggy (webhook) que faz o extrato entrar sozinho (06/10/2026).
//
// O MeuPluggy vai ao banco uma vez por dia e NÃO aceita pedido de "ir agora" (PATCH /items
// responde 400 para item do MeuPluggy — docs.pluggy.ai, Meu Pluggy). O que dá para fazer é o
// contrário: quando ELE termina de ir ao banco, avisa (evento item/updated) e o ERP lê na hora,
// em vez de esperar as buscas das 06h e 15h. O receptor (pluggy-webhook) existia desde julho, mas
// o aviso nunca tinha sido cadastrado no Pluggy: nenhuma chamada nos registros.

/** Só item/updated: ele vem depois de toda ida ao banco, com ou sem transação nova. */
export const EVENTOS_DO_AVISO = ["item/updated"] as const;

export interface WebhookDoPluggy {
  id: string;
  event: string;
  url: string;
}

/** O endereço sem o token: é o que se compara e o que se mostra (o token é segredo). */
export function semToken(url: string): string {
  try {
    const u = new URL(url);
    u.search = "";
    return u.toString();
  } catch {
    return url.split("?")[0];
  }
}

/** Quais eventos ainda faltam cadastrar para este endereço. */
export function eventosQueFaltam(existentes: WebhookDoPluggy[], endereco: string): string[] {
  const alvo = semToken(endereco);
  return EVENTOS_DO_AVISO.filter((ev) => !existentes.some((w) => (w.event === ev || w.event === "all") && semToken(w.url) === alvo));
}

/**
 * Do evento recebido, o item a ler agora — ou null. item/updated de qualquer origem (o ciclo
 * diário, um pedido no meu.pluggy.ai); item/error e o resto só ficam no log.
 */
export function itemParaLer(evento: { event?: unknown; itemId?: unknown }): string | null {
  if (evento.event !== "item/updated") return null;
  const id = String(evento.itemId ?? "").trim();
  return /^[0-9a-f-]{36}$/i.test(id) ? id : null;
}
