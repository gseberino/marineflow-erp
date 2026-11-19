import { blockTechnician, NON_TECHNICIAN_ROLES, type ToolDef } from "./registry.ts";
import { ESQUEMA_DA_FORMA, formaDePagamento, validarForma } from "./forma-de-pagamento.ts";
import { horariosDeBrasilia } from "../fuso.ts";
import { sendWhatsapp } from "./whatsapp.ts";
import { descreverSaldo, parcelasDoSaldo } from "./saldo-do-sinal.ts";
import { registrarEnvioDaCobranca, SITUACOES_ABERTAS } from "./cobrancas.ts";
import { vincularTecnico } from "./service-orders.ts";
import { statusAoAgendar } from "../../service-order-status.ts";
import { diaBR } from "../../agenda-dia.ts";
import { favorecidoDoLogin, modoDaPropostaNoBanco } from "../../agenda-modo.ts";

// Macros de FLUXO (Onda 2b) — "o LLM orquestra, o código executa".
// Cada uma colapsa um procedimento de vários passos numa única tool de risco alto:
// é interceptada por runAgentLoop → UMA confirmação (+ PIN) → executa tudo server-side.
// A confirmação mostra a lista/resumo real via buildPendingSummary (ver agent.ts).

const fmtBRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const hojeISODate = () => new Date().toISOString().slice(0, 10);

const CAMPOS_DA_COBRANCA = "id, amount, due_date, contact_whatsapp, phone, contact_name, client_id, last_auto_sent_at, status, receivable_id";

export type ItemDoLote = { pedido: string; cobranca?: { id: string; [campo: string]: any }; motivo?: string; repetida?: boolean };

/**
 * Os ids do lote → a cobrança de cada um (19/11/2026). O prompt manda levantar a lista com get_delinquency_plan, que
 * devolve `receivable_id` (a conta a receber), mas o lote só procurava em collections.id: tudo virava "cobrança não
 * encontrada" e a tool respondia ok com 0 enviados. Agora aceita os dois: id da cobrança, ou id da conta a receber
 * (a cobrança ABERTA mais recente dela). Conta sem cobrança aberta diz isso. Leitura com erro lança.
 */
export async function resolverCobrancasDoLote(sb: any, ids: readonly string[]): Promise<ItemDoLote[]> {
  const unicos = [...new Set(ids.map(String).filter(Boolean))];
  if (!unicos.length) return [];
  const { data: porId, error: erroPorId } = await sb.from("collections").select(CAMPOS_DA_COBRANCA).in("id", unicos);
  if (erroPorId) throw new Error(`Não consegui ler as cobranças: ${erroPorId.message}`);
  const diretas = new Map<string, any>(((porId ?? []) as any[]).map((c) => [String(c.id), c]));
  const faltam = unicos.filter((id) => !diretas.has(id));

  const daConta = new Map<string, any>();
  const contasSemCobranca = new Set<string>();
  if (faltam.length) {
    const { data: porConta, error: erroPorConta } = await sb
      .from("collections").select(`${CAMPOS_DA_COBRANCA}, created_at`)
      .in("receivable_id", faltam).in("status", SITUACOES_ABERTAS)
      .order("created_at", { ascending: false });
    if (erroPorConta) throw new Error(`Não consegui ler as cobranças das contas a receber: ${erroPorConta.message}`);
    for (const c of (porConta ?? []) as any[]) if (!daConta.has(String(c.receivable_id))) daConta.set(String(c.receivable_id), c);
    const semNada = faltam.filter((id) => !daConta.has(id));
    if (semNada.length) {
      const { data: contas, error: erroContas } = await sb.from("receivables").select("id").in("id", semNada);
      if (erroContas) throw new Error(`Não consegui ler as contas a receber: ${erroContas.message}`);
      for (const r of (contas ?? []) as any[]) contasSemCobranca.add(String(r.id));
    }
  }

  const vistas = new Set<string>();
  return unicos.map((pedido) => {
    const cobranca = diretas.get(pedido) ?? daConta.get(pedido);
    if (!cobranca) {
      return {
        pedido,
        motivo: contasSemCobranca.has(pedido)
          ? "conta a receber sem cobrança aberta (crie com criar_cobranca antes de mandar o lembrete)"
          : "cobrança não encontrada",
      };
    }
    if (vistas.has(String(cobranca.id))) return { pedido, motivo: "mesma cobrança repetida no lote", repetida: true };
    vistas.add(String(cobranca.id));
    return { pedido, cobranca };
  });
}

export const flowMacroTools: ToolDef[] = [
  // ───────────────────────── COBRANÇA EM LOTE ─────────────────────────
  {
    name: "send_bulk_collection_reminders",
    description:
      "Envia lembrete de cobrança por WhatsApp para VÁRIOS clientes de uma vez (ex.: 'cobra todos os vencidos', 'manda a cobrança da lista'). Levante a lista ANTES (get_delinquency_plan / list_pending_collections) e passe os ids escolhidos em collection_ids — vale o id de list_pending_collections ou o receivable_id de get_delinquency_plan (o sistema acha a cobrança aberta da conta) — a confirmação vai mostrar quem, quanto e o atraso, e você aprova o lote de uma vez. Quem já foi cobrado hoje é PULADO automaticamente. Envio externo: pede confirmação. Report-only: se um envio falhar, os outros seguem.",
    input_schema: {
      type: "object",
      properties: {
        collection_ids: {
          type: "array",
          items: { type: "string" },
          description: "UUIDs: o id da cobrança (list_pending_collections) ou o receivable_id (get_delinquency_plan). Passe só os que você escolheu cobrar.",
        },
        custom_message: {
          type: "string",
          description: "Opcional: mensagem única para todos. Se omitido, cada cliente recebe o texto padrão com o próprio valor e vencimento.",
        },
      },
      required: ["collection_ids"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const { sb, admin, jwt } = ctx;
      const ids: string[] = Array.isArray(args.collection_ids) ? (args.collection_ids as string[]).filter(Boolean) : [];
      if (ids.length === 0) return { error: "Nenhuma cobrança informada." };

      const hoje = hojeISODate();
      const enviados: Array<Record<string, unknown>> = [];
      const pulados: Array<Record<string, unknown>> = [];
      const falhas: Array<Record<string, unknown>> = [];

      const lote = await resolverCobrancasDoLote(sb, ids);
      for (const item of lote) {
        if (item.repetida) { pulados.push({ id: item.pedido, motivo: item.motivo }); continue; }
        const col = item.cobranca;
        if (!col) { falhas.push({ id: item.pedido, motivo: item.motivo }); continue; }
        // Paga ou cancelada não se cobra (07/10/2026).
        if (col.status === "paid" || col.status === "cancelled") {
          pulados.push({ cliente: col.contact_name || null, motivo: col.status === "paid" ? "cobrança paga" : "cobrança cancelada" });
          continue;
        }

        // Não recobrar quem já foi cobrado hoje (mesma regra do get_delinquency_plan).
        if (col.last_auto_sent_at && String(col.last_auto_sent_at).slice(0, 10) === hoje) {
          pulados.push({ cliente: col.contact_name || null, motivo: "já cobrado hoje" });
          continue;
        }

        let phone = col.contact_whatsapp || col.phone;
        if (!phone && col.client_id) {
          const { data: c } = await sb.from("clients").select("whatsapp, phone").eq("id", col.client_id).maybeSingle();
          phone = c?.whatsapp || c?.phone;
        }
        if (!phone) { falhas.push({ cliente: col.contact_name || null, motivo: "sem telefone" }); continue; }

        const valor = fmtBRL.format(Number(col.amount) || 0);
        const msg = args.custom_message ||
          `Olá${col.contact_name ? ` ${col.contact_name}` : ""}, lembrete amigável: consta um valor de ${valor} com vencimento em ${col.due_date}. Qualquer dúvida, estamos à disposição.`;

        const r = await sendWhatsapp(phone, msg, jwt);
        if ((r as { ok?: boolean }).ok) {
          // O contato 'whatsapp_sent' e a situação 'enviada', como a tela (07/10/2026).
          const aviso = await registrarEnvioDaCobranca(admin, col, ctx.userId, "Lembrete enviado pelo assistente (lote, WhatsApp)");
          enviados.push({ cliente: col.contact_name || null, valor: Number(col.amount) || 0, ...(aviso ? { aviso } : {}) });
        } else {
          falhas.push({ cliente: col.contact_name || null, motivo: (r as { error?: string }).error || "falha no envio" });
        }
      }

      if (enviados.length === 0) {
        // Nenhum envio não é "feito": antes voltava ok:true com 0 enviados, e o modelo dizia que cobrou.
        const motivos = [...new Set([...falhas, ...pulados].map((f) => String(f.motivo)))];
        return {
          ok: false,
          error: `Nenhum lembrete foi enviado (${ids.length} pedido(s)). Motivo(s): ${motivos.join("; ") || "nenhum envio saiu"}.`,
          total_solicitado: ids.length,
          enviados: 0,
          pulados: pulados.length,
          falhas: falhas.length,
          detalhe: { pulados, falhas },
        };
      }
      return {
        ok: true,
        total_solicitado: ids.length,
        enviados: enviados.length,
        pulados: pulados.length,
        falhas: falhas.length,
        detalhe: { enviados, pulados, falhas },
        ...(pulados.length ? { nota: "Alguns foram pulados (já cobrados hoje, pagos, cancelados ou repetidos): veja detalhe.pulados." } : {}),
        ...(falhas.length ? { atencao: `${falhas.length} lembrete(s) NÃO saíram: diga quais (detalhe.falhas).` } : {}),
      };
    },
  },

  // ──────────────── APROVAR ORÇAMENTO (fluxo completo, sinal já pago) ────────────────
  {
    name: "approve_quote_full",
    description:
      "APROVA um orçamento cujo SINAL JÁ FOI PAGO, em uma ação só: registra o sinal e converte em OS, e (opcional) agenda a OS e cria um lembrete de follow-up. Use quando o cliente aprovou E o dinheiro do sinal já entrou. Se o sinal ainda VAI ser cobrado, NÃO use isto — cobre o sinal primeiro (create_receivable / send_collection_reminder) e converta depois que ele pagar. Ação de dinheiro: confirmação + PIN. Report-only: se um passo falhar, os anteriores NÃO são desfeitos.",
    input_schema: {
      type: "object",
      properties: {
        service_order_id: { type: "string", description: "UUID do orçamento (draft)." },
        deposit_amount: { type: "number", description: "Valor do sinal JÁ PAGO." },
        payment_date: { type: "string", description: "Data do pagamento do sinal (ISO date)." },
        payment_method: { ...ESQUEMA_DA_FORMA, description: `Forma de pagamento do sinal: ${ESQUEMA_DA_FORMA.description}` },
        card_fee_percent: { type: "number", description: "Taxa de cartão em %, se houver." },
        follow_up_in_days: { type: "number", description: "Opcional: agenda um lembrete de follow-up PARA VOCÊ em N dias (às 08:00)." },
        scheduled_start_at: { type: "string", description: "Opcional: agenda a OS para esta data/hora (ISO)." },
        scheduled_end_at: { type: "string", description: "Opcional: fim do agendamento (ISO)." },
        technician_user_id: { type: "string", description: "Opcional: técnico responsável. O status não depende dele: com data, a OS aprovada ou aberta passa a Agendada." },
        notes: { type: "string" },
      },
      required: ["service_order_id", "deposit_amount", "payment_date", "payment_method"],
    },
    risk: "high",
    roles: NON_TECHNICIAN_ROLES,
    preValidar: (args) => validarForma(args),
    async execute(argsCrus, ctx) {
      // Hora sem fuso vira hora de Brasília (fuso.ts): 09:00 não pode virar 06:00.
      const args = horariosDeBrasilia(argsCrus);
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      const forma = validarForma(args);
      if (forma) return forma;
      const { sb, admin, userId } = ctx;
      const passos: Array<Record<string, unknown>> = [];

      // 1) Núcleo: sinal + conversão. Se falhar, para aqui — não dá pra agendar OS que não converteu.
      // O saldo vira conta a receber junto, como no "Receber sinal" da tela (06/10/2026).
      const dataDoSinal = String(args.payment_date).split("T")[0];
      const saldo = await parcelasDoSaldo(ctx, String(args.service_order_id), Number(args.deposit_amount), dataDoSinal);
      if ("error" in saldo) {
        return { ok: false, passos: [{ passo: "sinal+conversão", status: "✖", erro: saldo.error }], nota: "Nada foi feito." };
      }
      const { error: convErr } = await admin.rpc("register_deposit_and_convert", {
        p_service_order_id: args.service_order_id,
        p_amount: args.deposit_amount,
        p_payment_date: dataDoSinal,
        p_payment_method: formaDePagamento(args.payment_method),
        p_card_fee_percent: args.card_fee_percent || 0,
        p_notes: args.notes || null,
        p_balance_installments: saldo.parcelas.length ? saldo.parcelas : null,
        p_create_collections: true,
      });
      if (convErr) {
        return { ok: false, passos: [{ passo: "sinal+conversão", status: "✖", erro: convErr.message }], nota: "Nada foi agendado — a conversão falhou." };
      }
      passos.push({ passo: "sinal+conversão", status: "✔", saldo: descreverSaldo(saldo.parcelas) });

      // nº atual da OS (mesma linha; ganha novo número ao converter)
      // O status vem junto, lido DEPOIS da conversão: é dele que o passo 3 decide se a OS vira agendada.
      // O erro não é engolido (revisão de 23/10/2026): sem o status, statusAoAgendar('') dava null, a
      // data era gravada com a OS 'open' e o passo saía ✔ calado. O follow-up segue sem o número.
      const { data: so, error: soErr } = await sb.from("service_orders").select("service_order_number, client_id, status").eq("id", args.service_order_id).maybeSingle();

      // 2) Follow-up para o próprio dono (opcional) — espelha schedule_self_reminder.
      if (Number(args.follow_up_in_days) > 0) {
        try {
          const datePart = new Date(Date.now() + Number(args.follow_up_in_days) * 86400000).toISOString().slice(0, 10);
          const whenISO = new Date(`${datePart}T08:00:00-03:00`).toISOString(); // 08:00 Brasília
          const { data: u } = await admin.from("app_users").select("phone_normalized, full_name").eq("id", userId).maybeSingle();
          const phone = (u?.phone_normalized || "").replace(/\D/g, "");
          if (!phone) {
            passos.push({ passo: "follow-up", status: "✖", erro: "sem número de WhatsApp cadastrado para lembretes" });
          } else {
            const firstName = String(u?.full_name || "").trim().split(/\s+/)[0] || "";
            const texto = `Follow-up do ${so?.service_order_number || "orçamento aprovado"} — verificar andamento com o cliente.`;
            const { error: remErr } = await admin.from("whatsapp_scheduled_sends").insert({
              phone,
              message: firstName ? `⏰ *Lembrete, ${firstName}!*\n\n${texto}` : `⏰ *Lembrete!*\n\n${texto}`,
              scheduled_at: whenISO,
              next_run_at: whenISO,
              recurrence_type: "once",
              send_mode: "text",
              target_kind: "self_reminder",
              status: "pending",
              created_by: userId,
              auto_retry: true,
              max_attempts: 3,
            });
            passos.push(remErr ? { passo: "follow-up", status: "✖", erro: remErr.message } : { passo: "follow-up", status: "✔", em: whenISO.slice(0, 10) });
          }
        } catch (e) {
          passos.push({ passo: "follow-up", status: "✖", erro: (e as Error).message });
        }
      }

      // 3) Agendamento da OS (opcional) — espelha schedule_service_order.
      // D8/D8b (Agenda de Produção, Fase 0, 23/10/2026): o status não depende do técnico, e o vínculo
      // do técnico não tem .catch() (o builder não tem); erro nele vira aviso no passo, que fica ✔.
      // Fase 2 (P4, 24/10/2026): o status nunca vai no update — quem decide é a porta única do banco
      // (os_transicionar_status, via 'aprovacao'): a conversão costuma deixar a OS 'open', que vira
      // 'scheduled'. Com a agenda automática ligada, a data é da agenda: agenda_marcar_os (via
      // 'aprovacao') a partir do dia de Brasília pedido — o dono confirmou com PIN o resumo que já tinha
      // a data. Este passo nunca sai ✔ calado: leva a frase da porta ou da agenda (✔ ou ✖).
      if (args.scheduled_start_at && (soErr || !so?.status)) {
        // Sem o status relido não há como decidir o status da OS: nada é gravado e o passo diz por quê.
        passos.push({ passo: "agendamento", status: "✖", erro: "não consegui ler o status da OS depois da conversão; a data não foi gravada" });
      } else if (args.scheduled_start_at) {
        try {
          // A encerrada recusa antes de gravar (a leitura da porta); o status quem decide é a porta.
          statusAoAgendar(String(so?.status ?? ""));
          const aoVincular = async () => args.technician_user_id
            ? await vincularTecnico(sb, String(args.service_order_id), String(args.technician_user_id))
            : null;
          if ((await modoDaPropostaNoBanco(admin)) === "ligado") {
            const de = diaBR(String(args.scheduled_start_at));
            const fim = args.scheduled_end_at ? diaBR(String(args.scheduled_end_at)) : de;
            const pessoa = await favorecidoDoLogin(admin, args.technician_user_id ? String(args.technician_user_id) : null);
            const { data: marcado, error: mErr } = await admin.rpc("agenda_marcar_os", {
              p_autor: userId, p_os: args.service_order_id, p_de: de, p_ate: fim < de ? de : fim, p_pessoa: pessoa, p_via: "aprovacao",
            });
            if (mErr) {
              passos.push({ passo: "agendamento", status: "✖", erro: `a agenda não marcou: ${mErr.message}` });
            } else if (!marcado?.ok) {
              passos.push({ passo: "agendamento", status: "✖", erro: String(marcado?.texto ?? "a agenda não marcou") });
            } else {
              const aviso = await aoVincular();
              passos.push({ passo: "agendamento", status: "✔", agenda: String(marcado.texto ?? ""), ...(aviso ? { aviso } : {}) });
            }
          } else {
            const update: Record<string, unknown> = { scheduled_start_at: args.scheduled_start_at };
            if (args.scheduled_end_at) update.scheduled_end_at = args.scheduled_end_at;
            const { error: schErr } = await sb.from("service_orders").update(update).eq("id", args.service_order_id);
            if (schErr) {
              passos.push({ passo: "agendamento", status: "✖", erro: schErr.message });
            } else {
              const aviso = await aoVincular();
              const { data: porta, error: pErr } = await sb.rpc("os_transicionar_status", {
                p_os: args.service_order_id, p_para: "scheduled", p_via: "aprovacao", p_autor: userId,
              });
              if (pErr) {
                passos.push({ passo: "agendamento", status: "✖", erro: `a data foi gravada, mas o status não mudou: ${pErr.message}`, ...(aviso ? { aviso } : {}) });
              } else if (porta?.ok === false) {
                passos.push({ passo: "agendamento", status: "✖", erro: `a data foi gravada, mas o status não mudou: ${porta?.texto ?? "recusado"}`, ...(aviso ? { aviso } : {}) });
              } else {
                passos.push({
                  passo: "agendamento", status: "✔", status_da_os: String(porta?.para ?? so?.status ?? ""),
                  ...(porta?.texto ? { texto: String(porta.texto) } : {}), ...(aviso ? { aviso } : {}),
                });
              }
            }
          }
        } catch (e) {
          passos.push({ passo: "agendamento", status: "✖", erro: (e as Error).message });
        }
      }

      return {
        ok: true,
        os: so?.service_order_number || null,
        passos,
        resumo: passos.map((p) => `${p.status} ${p.passo}`).join(" · "),
      };
    },
  },
];
