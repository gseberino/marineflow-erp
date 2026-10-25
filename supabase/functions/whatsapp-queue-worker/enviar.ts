// O envio de um lote da fila (whatsapp_send_queue), item por item — o laço que morava no index.ts, sem mudar o que ele
// faz com as origens de sempre: manda pelo provedor, marca 'sent' (com o id do provedor e a tentativa) ou devolve a
// 'pending' para daqui a 5 min (até max_attempts, depois 'failed'), com a pausa entre um envio e outro.
//
// Agenda de Produção, Fase 3 (P7b — NOVO-agenda-26): ANTES de mandar uma linha de origem da agenda (hoje só
// 'agenda-equipe'; as de cliente da Fase 5 entram pelo mesmo helper, _shared/agenda/janela-da-fila.ts), confere a janela da
// agenda NA HORA: fora dela a linha vira 'failed' com o motivo, o registro da mensagem fica recusado e nada sai. A
// configuração da agenda só é lida se o lote tiver alguma linha dessas (uma vez por lote); as outras origens não mudam.
//
// Revisão da Fase 3 (C1): a resposta direta à equipe tem a janela dela (R7, NOVO-agenda-28: o helper reconhece a linha pela
// chave) e o lote só leva as linhas que ESTE disparo travou em 'sending' (item 10, travarLote): dois disparos do cron
// juntos não mandam a mesma ficha duas vezes ao Roberto.

import {
  type JanelasDaAgenda,
  lerJanelasDaAgenda,
  origemComJanelaDaAgenda,
  recusaNaHoraDeEnviar,
  recusarNaFila,
} from "../_shared/agenda/janela-da-fila.ts";

// O tipo de createClient sem o esquema gerado não casa com o cliente criado no index.ts (TS2345).
// deno-lint-ignore no-explicit-any
type DbClient = any;

/** O que o provedor do WhatsApp devolve (createWhatsAppProvider().sendText). */
export interface ProvedorDoEnvio {
  sendText(phone: string, text: string): Promise<{ ok: boolean; providerMessageId?: string | null; error?: string | null }>;
}

/** Uma linha da fila como o worker a lê (select *). */
export interface ItemDaFila {
  id: string;
  phone_normalized: string;
  message: string;
  source?: string | null;
  scheduled_for?: string | null;
  attempts?: number | null;
  max_attempts?: number | null;
  /** (C1) a chave: a resposta direta da agenda é reconhecida por ela */
  dedupe_key?: string | null;
  /** (C1) quando a linha entrou na fila (o prazo da resposta direta conta daqui) */
  created_at?: string | null;
}

export interface ResultadoDoItem {
  id: string;
  ok: boolean;
  error?: string;
  give_up?: boolean;
  /** a janela da agenda segurou a linha (o motivo: janela, domingo, modo) */
  janela_da_agenda?: string;
}

export interface OpcoesDoLote {
  /** a pausa entre um envio e o seguinte (app_settings.whatsapp_queue_delay_ms) */
  delayMs: number;
  /** o relógio (os testes passam o deles) */
  agora?: () => Date;
  /** a pausa (os testes passam a deles) */
  dormir?: (ms: number) => Promise<void>;
}

const dormirDeVerdade = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/**
 * (Revisão C1, item 10) A trava do lote: UPDATE de 'pending' para 'sending' só das linhas que AINDA estão pendentes,
 * devolvendo quais este disparo travou (.select('id')). Só elas vão ao enviarLote: a linha que outro disparo pegou no meio
 * tempo não sai duas vezes. Erro na trava = nada sai (as linhas seguem pendentes para o próximo minuto).
 */
export async function travarLote(
  admin: DbClient,
  batch: ItemDaFila[],
  agoraIso: string,
): Promise<{ lote: ItemDaFila[]; erro?: string }> {
  if (batch.length === 0) return { lote: [] };
  const { data, error } = await admin.from("whatsapp_send_queue")
    .update({ status: "sending", processing_started_at: agoraIso })
    .in("id", batch.map((b) => b.id))
    .eq("status", "pending")
    .select("id");
  if (error) return { lote: [], erro: String(error.message ?? error.code ?? error) };
  const travadas = new Set(((data ?? []) as Array<{ id: unknown }>).map((r) => String(r.id)));
  return { lote: batch.filter((b) => travadas.has(String(b.id))) };
}

export async function enviarLote(
  admin: DbClient,
  provider: ProvedorDoEnvio,
  batch: ItemDaFila[],
  opcoes: OpcoesDoLote,
): Promise<ResultadoDoItem[]> {
  const agora = opcoes.agora ?? (() => new Date());
  const dormir = opcoes.dormir ?? dormirDeVerdade;
  const results: ResultadoDoItem[] = [];
  // A janela da agenda: lida só se o lote tiver linha da agenda, uma vez (undefined = ainda não lida; null = falhou).
  let janelas: JanelasDaAgenda | null | undefined;
  let erroDaJanela: string | undefined;

  for (let i = 0; i < batch.length; i++) {
    const item = batch[i];

    // Fase 3 (P7b): a linha da agenda fora da janela, na hora do envio, não sai.
    if (origemComJanelaDaAgenda(item.source)) {
      if (janelas === undefined) {
        try {
          janelas = await lerJanelasDaAgenda(admin);
        } catch (e) {
          janelas = null;
          erroDaJanela = e instanceof Error ? e.message : String(e);
          console.error("whatsapp-queue-worker: a janela da agenda não foi lida", erroDaJanela);
        }
      }
      const recusa = recusaNaHoraDeEnviar(item, agora(), janelas, erroDaJanela);
      if (recusa) {
        const erroAoMarcar = await recusarNaFila(admin, item, recusa);
        if (erroAoMarcar) console.error("whatsapp-queue-worker: a recusa da janela não foi gravada", item.id, erroAoMarcar);
        results.push({ id: item.id, ok: false, error: recusa.texto, give_up: true, janela_da_agenda: recusa.motivo });
        continue;
      }
    }

    try {
      const result = await provider.sendText(item.phone_normalized, item.message);

      if (result.ok) {
        await admin.from("whatsapp_send_queue").update({
          status: "sent",
          sent_at: new Date().toISOString(),
          // Coluna correta é zapi_message_id (não wa_message_id, que não existe na
          // tabela) — com o nome errado o UPDATE inteiro falhava silenciosamente e a
          // linha ficava presa em 'sending' apesar do envio ter dado certo. Bug latente
          // até a fila ser ligada (Fase 4).
          zapi_message_id: result.providerMessageId || null,
          attempts: (item.attempts || 0) + 1,
        }).eq("id", item.id);
        results.push({ id: item.id, ok: true });
      } else {
        const newAttempts = (item.attempts || 0) + 1;
        const giveUp = newAttempts >= (item.max_attempts || 3);
        await admin.from("whatsapp_send_queue").update({
          status: giveUp ? "failed" : "pending",
          attempts: newAttempts,
          failed_reason: result.error || "send failed",
          scheduled_for: giveUp ? item.scheduled_for : new Date(Date.now() + 5 * 60_000).toISOString(),
          processing_started_at: null,
        }).eq("id", item.id);
        results.push({ id: item.id, ok: false, error: result.error ?? undefined, give_up: giveUp });
      }
    } catch (e) {
      const newAttempts = (item.attempts || 0) + 1;
      const giveUp = newAttempts >= (item.max_attempts || 3);
      await admin.from("whatsapp_send_queue").update({
        status: giveUp ? "failed" : "pending",
        attempts: newAttempts,
        failed_reason: e instanceof Error ? e.message : String(e),
        scheduled_for: giveUp ? item.scheduled_for : new Date(Date.now() + 5 * 60_000).toISOString(),
        processing_started_at: null,
      }).eq("id", item.id);
      results.push({ id: item.id, ok: false, error: e instanceof Error ? e.message : String(e), give_up: giveUp });
    }

    if (i < batch.length - 1 && opcoes.delayMs > 0) await dormir(opcoes.delayMs);
  }
  return results;
}
