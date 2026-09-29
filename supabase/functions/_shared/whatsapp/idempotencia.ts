// Idempotência de envio de WhatsApp (caminho direto, edge whatsapp-send).
//
// Quem envia monta uma chave estável para "esta mensagem, para este destinatário, nesta
// ocasião" e a edge reserva a chave antes de chamar o provedor. Reserva repetida e CONCLUÍDA
// = já enviada = não envia de novo; repetida sem desfecho = em andamento (reservarOuAguardar).
// Falha no provedor libera a reserva para a tentativa seguinte.
//
// A fila (whatsapp_send_queue) tem a própria proteção, por gatilho no banco; ver a migration
// 20260919120000_whatsapp_idempotencia_de_envio.sql.

// deno-lint-ignore no-explicit-any
type DbClient = any;

/** Hash curto e determinístico (djb2 em base 36). Serve para chave, não para segurança. */
export function hashCurto(texto: string): string {
  let h = 5381;
  for (let i = 0; i < texto.length; i++) {
    h = ((h << 5) + h + texto.charCodeAt(i)) | 0;
  }
  return (h >>> 0).toString(36);
}

/** Dia local (America/Sao_Paulo) no formato YYYY-MM-DD; escopo natural das chaves diárias. */
export function diaLocal(d: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

/** Junta partes com ':' descartando vazias; espaços viram '_' para a chave não ter surpresa. */
export function chaveDeEnvio(...partes: Array<string | number | null | undefined>): string {
  return partes
    .filter((p) => p !== null && p !== undefined && String(p).trim() !== "")
    .map((p) => String(p).trim().replace(/\s+/g, "_"))
    .join(":")
    .slice(0, 200);
}

export type ResultadoReserva = "nova" | "repetida" | "erro";

/**
 * Reserva a chave. "nova" = pode enviar; "repetida" = outra tentativa já reservou (enviada ou
 * ainda em andamento: quem precisa saber qual usa reservarOuAguardar);
 * "erro" = banco indisponível — quem chama decide (a edge segue e envia: melhor um
 * duplicado raro do que uma cobrança que nunca sai).
 */
export async function reservarEnvio(
  admin: DbClient,
  chave: string,
  meta: { phone?: string; contexto?: string } = {},
): Promise<ResultadoReserva> {
  const { error } = await admin.from("whatsapp_send_idempotencia").insert({
    chave,
    phone_normalized: meta.phone ?? null,
    contexto: meta.contexto ?? null,
  });
  if (!error) return "nova";
  if (error.code === "23505") return "repetida";
  console.warn("[idempotencia] reserva falhou, seguindo sem proteção:", error.message);
  return "erro";
}

/** Libera a reserva quando o envio falhou, para a próxima tentativa passar. */
export async function liberarEnvio(admin: DbClient, chave: string): Promise<void> {
  await admin.from("whatsapp_send_idempotencia").delete().eq("chave", chave);
}

/**
 * Marca a reserva como concluída (o provedor confirmou), com o id dele quando houver, e apaga
 * reservas com mais de 30 dias. `concluido_em` é o que autoriza a resposta "já enviado".
 */
export async function concluirEnvio(admin: DbClient, chave: string, providerMessageId?: string | null): Promise<void> {
  await admin.from("whatsapp_send_idempotencia")
    .update({ concluido_em: new Date().toISOString(), ...(providerMessageId ? { provider_message_id: providerMessageId } : {}) })
    .eq("chave", chave);
  const limite = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
  await admin.from("whatsapp_send_idempotencia").delete().lt("criado_em", limite);
}

export type SituacaoDaReserva = "concluida" | "em_andamento" | "livre" | "erro";

/** Em que pé está a chave: envio concluído, ainda sem desfecho, ou já liberada por falha. */
export async function situacaoDaReserva(admin: DbClient, chave: string): Promise<SituacaoDaReserva> {
  const { data, error } = await admin.from("whatsapp_send_idempotencia")
    .select("concluido_em").eq("chave", chave).maybeSingle();
  if (error) return "erro";
  if (!data) return "livre";
  return data.concluido_em ? "concluida" : "em_andamento";
}

export type ResultadoDaReservaComEspera = "nova" | "erro" | "ja_enviada" | "em_andamento";

/**
 * Reserva a chave e, se ela já estiver reservada, espera o desfecho da outra tentativa.
 *
 * Chave reservada NÃO quer dizer "já enviado". Até 29/09/2026 era lida assim, e a tela
 * mostrava "Enviado" num reenvio depois de erro de rede enquanto a primeira tentativa ainda
 * esperava a Evolution — e que depois falhava. Agora:
 *  - a outra tentativa concluiu → "ja_enviada" (verdade: saiu);
 *  - falhou e liberou a chave → reserva de novo → "nova" (esta envia);
 *  - continua sem desfecho depois da espera, ou o banco não respondeu → "em_andamento": quem
 *    chama diz que NÃO confirmou, sem enviar de novo (a outra pode ainda sair) e sem afirmar
 *    que saiu.
 * "erro" (banco indisponível na reserva) segue a regra de reservarEnvio: envia mesmo assim.
 */
export async function reservarOuAguardar(
  admin: DbClient,
  chave: string,
  meta: { phone?: string; contexto?: string } = {},
  opcoes: { consultas?: number; intervaloMs?: number; dormir?: (ms: number) => Promise<void> } = {},
): Promise<ResultadoDaReservaComEspera> {
  const intervaloMs = opcoes.intervaloMs ?? 1_000;
  const dormir = opcoes.dormir ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  // Orçamento total de esperas: ~10 s cobre a Evolution respondendo normalmente (digitação de
  // até 3 s e o download do PDF), sem prender a função quando a outra tentativa morreu.
  let restantes = opcoes.consultas ?? 10;
  while (true) {
    const reserva = await reservarEnvio(admin, chave, meta);
    if (reserva !== "repetida") return reserva;
    let situacao = await situacaoDaReserva(admin, chave);
    while (situacao === "em_andamento" && restantes > 0) {
      restantes--;
      await dormir(intervaloMs);
      situacao = await situacaoDaReserva(admin, chave);
    }
    if (situacao === "concluida") return "ja_enviada";
    // Liberada no meio da espera (a outra falhou): tenta reservar para esta enviar.
    if (situacao === "livre" && restantes-- > 0) continue;
    return "em_andamento";
  }
}
