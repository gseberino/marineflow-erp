// A tool enviar_lembrete_de_vencimento (dono, 26/11/2026: "2. A") — o "sim" do dono no lembrete ANTES do vencimento de
// uma conta a receber ("vence em 3 dias").
//
// Quem cria a pendência: a rotina receivable-reminders (todo dia útil, para as contas que vencem nos próximos dias) e o
// próprio assistente, quando o dono pede ajuste num desses lembretes ("sim, mas tira o emoji") ou o lembrete de uma conta
// que ainda não venceu. A conferência mora em _shared/receivables/lembrete-de-vencimento.ts: o cartão, o retrato e o
// envio perguntam a MESMA coisa. No "sim": as travas de novo com dado fresco, o retrato (mudou até o "sim", não envia), o
// portão de horário e destinatário, a MESMA chave que a rotina usava (o que já saiu não sai de novo) e, enviado, a marca
// reminder_sent_at na conta (o lembrete dela não é pedido de novo). Modo de teste: vai ao número de teste, chave com
// ":teste" e nada marcado na conta.
import { blockTechnician, lerRetrato, type ToolDef } from "./registry.ts";
import { sendWhatsapp } from "./whatsapp.ts";
import { guardaDeEnvio } from "../comms/send-guard.ts";
import { registrarEnvio } from "../comms/send-log.ts";
import { desviadoPorTeste } from "../../whatsapp/marcar-enviado.ts";
import { horaEmBrasilia } from "../../receivables/cobrar-juntas.ts";
import {
  ACAO_DO_LEMBRETE_DE_VENCIMENTO,
  chaveDoLembreteDeVencimento,
  type LembreteDeVencimento,
  lembreteRecusado,
  montarLembreteDeVencimento,
  oQueMudouNoLembreteDeVencimento,
  relogioDoLembreteDeVencimento,
  retratoDaPendenciaDoVencimento,
  SEM_CARGO_DO_LEMBRETE_DE_VENCIMENTO,
  SEM_RETRATO_DO_LEMBRETE_DE_VENCIMENTO,
} from "../../receivables/lembrete-de-vencimento.ts";

export const lembreteDeVencimentoTools: ToolDef[] = [
  {
    name: ACAO_DO_LEMBRETE_DE_VENCIMENTO,
    description:
      "Manda ao cliente o lembrete ANTES do vencimento de UMA conta a receber ('vence em 3 dias'), com o saldo e o vencimento " +
      "da conta (receivable_id). A rotina diária já prepara esses lembretes e pede o 'sim' ao dono; use esta tool quando ele " +
      "pedir ajuste num deles (custom_message = o texto INTEIRO novo) ou pedir o lembrete de uma conta que ainda não venceu. " +
      "A chamada já pede o 'sim' mostrando o número, o valor conferido e a mensagem exata: não pergunte antes. Recusa conta " +
      "paga, sinal, já vencida (aí é cobrança: cobrar_juntas com o cliente), com lembrete já enviado, abaixo do piso, entrada " +
      "do cliente esperando no Extrato, opt-out, cadastro genérico e sem telefone.",
    input_schema: {
      type: "object",
      properties: {
        receivable_id: { type: "string", description: "O id da conta a receber (o que veio na referência do pedido da rotina)." },
        custom_message: { type: "string", description: "Só quando o dono ditar a frase: o texto INTEIRO que vai ao cliente." },
      },
      required: ["receivable_id"],
    },
    // Mensagem a cliente, com valor, em nome da empresa: como o lembrete de cobrança.
    risk: "high",
    // Escrito aqui (não importado): constante importada na carga do módulo já deu TDZ no import circular das tools.
    roles: ["admin", "financial"],
    // O retrato do que o cartão mostrou: a conta, o telefone, o valor, o vencimento e o texto.
    retratoDaPendencia: (args, ctx) => retratoDaPendenciaDoVencimento(ctx.admin, args),
    async execute(args, ctx) {
      const blocked = blockTechnician(ctx);
      if (blocked) return blocked;
      if (ctx.userRole !== "admin" && ctx.userRole !== "financial") return { error: SEM_CARGO_DO_LEMBRETE_DE_VENCIMENTO, nada_enviado: true };
      // O "sim" foi sobre o retrato: sem ele, não envia. Só a pendência chama este execute (risco alto, nunca autônoma).
      const retrato = lerRetrato(args);
      if (!retrato) return { error: SEM_RETRATO_DO_LEMBRETE_DE_VENCIMENTO, nada_enviado: true };
      let l: LembreteDeVencimento | { error: string };
      try {
        l = await montarLembreteDeVencimento(ctx.sb, ctx.admin, args);
      } catch (e) {
        return { error: `Nada foi enviado: não consegui conferir a conta agora (${String((e as Error)?.message ?? e)}). Peça de novo.`, nada_enviado: true };
      }
      if (lembreteRecusado(l)) return { error: `Nada foi enviado: ${l.error}`, nada_enviado: true };
      const mudou = oQueMudouNoLembreteDeVencimento(retrato, l);
      if (mudou) {
        return { error: `Nada foi enviado: ${mudou} depois do pedido. Peça de novo que eu confiro e mostro a mensagem atualizada.`, nada_enviado: true };
      }
      const agora = relogioDoLembreteDeVencimento.agora();
      const base = { tipo: "cobranca" as const, audiencia: "cliente" as const, entityKind: "client" as const, entityId: l.conta.client_id, phone: l.telefone, preview: l.texto };
      // Portão: conformidade (horário, destinatário identificado) bloqueia; estilo avisa.
      const g = guardaDeEnvio(l.texto, {
        tipo: "cobranca", audiencia: "cliente", canal: "whatsapp", destinatarioIdentificado: !!l.conta.client_id, texto: l.texto,
        horaBrasilia: horaEmBrasilia(agora),
      });
      if (g.bloqueado) {
        await registrarEnvio(ctx.admin, { ...base, status: "blocked", blockCode: g.codigoBloqueio });
        return { error: g.motivo, nada_enviado: true };
      }
      const modoTeste = desviadoPorTeste(ctx.settings);
      const r = await sendWhatsapp(l.telefone, l.texto, ctx.jwt, chaveDoLembreteDeVencimento(l.conta.id, l.vencimento, modoTeste), ctx.userId);
      const ok = (r as { ok?: boolean }).ok === true;
      await registrarEnvio(ctx.admin, { ...base, status: ok ? "sent" : "failed" });
      if (ok && modoTeste) {
        const texto = (r as { deduplicated?: boolean }).deduplicated
          ? "Este lembrete já tinha saído para o número de TESTE (modo de teste ligado); não reenviei. Nada foi marcado na conta."
          : "O modo de teste do WhatsApp está ligado: o lembrete foi para o número de TESTE, NÃO para o cliente. Nada foi marcado na conta. Diga isso.";
        return { ...r, enviado_para: "o número de TESTE do WhatsApp (modo de teste ligado), não o cliente", aviso: texto, message: texto };
      }
      if (ok) {
        // A marca da rotina: o lembrete desta conta não é pedido nem enviado de novo. Já saiu antes (deduplicado) também marca.
        const { error } = await ctx.admin.from("receivables").update({ reminder_sent_at: agora.toISOString() })
          .eq("id", l.conta.id).is("reminder_sent_at", null);
        if (error) {
          return { ...r, aviso: `O lembrete saiu, mas não consegui marcar a conta (${error.message}): a rotina pode pedir de novo. Não mande outra vez.` };
        }
      }
      return { ...r, ...(g.avisos.length ? { avisos_estilo: g.avisos } : {}) };
    },
  },
];
