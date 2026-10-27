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
//
// Fase 4 (P5): a mensagem ao fornecedor ('agenda-fornecedor') passa pelo mesmo helper, com a janela dela (segunda a sexta,
// fornecedor_janela_inicio a fornecedor_janela_fim, modo_fornecedor). Cada janela é lida à parte, uma vez por lote e só se
// o lote tiver linha daquela origem: a leitura de uma não segura a outra, e as outras origens continuam sem ler nada.
//
// Fase 5 (P2): a mensagem ao CLIENTE ('agenda-cliente') passa pela janela dela (segunda a sexta e sábado até
// cliente_sabado_fim, nunca domingo nem feriado, modo_cliente) e por mais duas conferências, só dela:
//   · no máximo UMA linha de cliente por lote (o banco já marca 30 a 60 s entre uma e outra; o worker roda a cada minuto e
//     manda o lote com 1,5 s entre as linhas): as outras voltam a 'pending' sem contar tentativa e saem no próximo disparo;
//   · antes de mandar, a pergunta ao banco (agenda_cliente_pode_sair: o modo, o tipo, a validade, a janela e a
//     revalidação — status, data, material, opt-out, o mesmo tipo em 24 h, o texto). Erro na pergunta ou "não pode" = não
//     sai: a linha vira 'failed' e o registro em agenda_cliente_mensagens fica recusado com o motivo.
// As outras origens não chamam a RPC nem mudam (provado em enviar_test.ts).

import {
  ehMensagemAoCliente,
  janelaDaOrigem,
  type JanelasDaAgenda,
  lerJanelasDaAgenda,
  type NomeDaJanela,
  recusaDoBanco,
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
  /** a janela da agenda segurou a linha (o motivo: janela, domingo, modo; no cliente também feriado e os do banco) */
  janela_da_agenda?: string;
  /** (Fase 5, P2) a 2ª linha de cliente do lote: voltou a 'pending' sem contar tentativa (sai no próximo disparo) */
  adiada?: boolean;
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
  // A janela da agenda: cada uma lida só se o lote tiver linha dela, uma vez (sem a chave = ainda não lida; janelas null =
  // falhou, com o erro).
  const lidas = new Map<NomeDaJanela, { janelas: JanelasDaAgenda | null; erro?: string }>();
  // (Fase 5, P2) já foi uma linha de cliente neste lote?
  let clienteNoLote = false;

  for (let i = 0; i < batch.length; i++) {
    const item = batch[i];

    // Fase 3 (P7b): a linha da agenda fora da janela, na hora do envio, não sai. Fase 4 (P5): a do fornecedor também.
    const qual = janelaDaOrigem(item.source);
    if (qual) {
      // Fase 5 (P2): no máximo uma linha de cliente por lote — as outras voltam a 'pending' sem contar tentativa.
      if (ehMensagemAoCliente(item.source)) {
        if (clienteNoLote) {
          const { error: eVolta } = await admin.from("whatsapp_send_queue")
            .update({ status: "pending", processing_started_at: null })
            .eq("id", item.id);
          if (eVolta) console.error("whatsapp-queue-worker: a 2ª linha de cliente não voltou à fila", item.id, eVolta.message ?? eVolta);
          results.push({ id: item.id, ok: false, adiada: true, error: "agenda-cliente: uma mensagem ao cliente por disparo (sai no próximo)" });
          continue;
        }
        clienteNoLote = true;
      }
      let lida = lidas.get(qual);
      if (!lida) {
        try {
          lida = { janelas: await lerJanelasDaAgenda(admin, qual) };
        } catch (e) {
          lida = { janelas: null, erro: e instanceof Error ? e.message : String(e) };
          console.error(`whatsapp-queue-worker: a janela da agenda (${qual}) não foi lida`, lida.erro);
        }
        lidas.set(qual, lida);
      }
      const recusa = recusaNaHoraDeEnviar(item, agora(), lida.janelas, lida.erro);
      if (recusa) {
        const erroAoMarcar = await recusarNaFila(admin, item, recusa);
        if (erroAoMarcar) console.error("whatsapp-queue-worker: a recusa da janela não foi gravada", item.id, erroAoMarcar);
        results.push({ id: item.id, ok: false, error: recusa.texto, give_up: true, janela_da_agenda: recusa.motivo });
        continue;
      }
      // Fase 5 (P2): a revalidação na saída — o banco diz se a mensagem ao cliente ainda vale AGORA.
      if (ehMensagemAoCliente(item.source)) {
        let resposta: { data?: unknown; error?: unknown };
        try {
          resposta = await admin.rpc("agenda_cliente_pode_sair", { p_fila: item.id });
        } catch (e) {
          resposta = { error: { message: e instanceof Error ? e.message : String(e) } };
        }
        const doBanco = recusaDoBanco(resposta ?? {}, String(item.source));
        if (doBanco) {
          const erroAoMarcar = await recusarNaFila(admin, item, doBanco);
          if (erroAoMarcar) console.error("whatsapp-queue-worker: a recusa do banco não foi gravada", item.id, erroAoMarcar);
          results.push({ id: item.id, ok: false, error: doBanco.texto, give_up: true, janela_da_agenda: doBanco.motivo });
          continue;
        }
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
