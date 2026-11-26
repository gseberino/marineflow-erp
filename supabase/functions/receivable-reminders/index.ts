// Edge Function: receivable-reminders — o lembrete ANTES do vencimento de uma conta a receber ("vence em 3 dias").
//
// Dono, 26/11/2026 ("2. A"): o lembrete passa a pedir o "sim" dele. Até aqui a rotina rodava às 08:00 e mandava sozinha ao
// cliente (origem "sistema"). Agora NADA sai para o cliente aqui: a rodada (propor.ts) acha as contas que vencem nos
// próximos dias, confere cada uma (_shared/receivables/lembrete-de-vencimento.ts) e pergunta ao dono no WhatsApp, como os
// lembretes de revisão; o "sim" executa a tool enviar_lembrete_de_vencimento, que confere tudo de novo e manda com a MESMA
// chave de antes (lembrete-recebivel:<conta>:<vencimento>).
//
// Chamada pelo pg_cron (x-cron-secret) às 10:40 e às 15:40 de Brasília (migration 20270302100000_lembrete_de_vencimento_pede_sim;
// antes, 08:00). Antes das 09:30 não pergunta (janela da manhã: só a manhã do secretário pergunta). Só em dia útil
// (agenda_dia_util; sem resposta do banco, nada). Uma pergunta por vez: com o dono ocupado (outra confirmação aberta), a
// rodada espera a próxima — a janela de N dias não perde a conta. Com a voz única, a rodada que perguntou fica registrada
// no portão como "fica como está".
// Interruptor: app_settings.lembrete_vencimento_ativo ('off' desliga; ausente = ligado). ?dry=1 devolve o que seria
// perguntado e o que ficou de fora, sem gravar nada (a qualquer hora e em qualquer dia).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { diaLocal } from "../_shared/whatsapp/idempotencia.ts";
import { modoDeTesteSemNumero, numeroDeTesteAtivo } from "../_shared/whatsapp/marcar-enviado.ts";
import {
  conversaDosComprovantesLigada,
  donoOcupadoParaPerguntar,
  resolveOrCreateWhatsAppSession,
} from "../_shared/ai/whatsapp-channel.ts";
import { cartaoDoLembreteDeVencimento } from "../_shared/receivables/lembrete-de-vencimento.ts";
import { depoisDaJanelaDaManha } from "../_shared/uma-voz/janela.ts";
import { avisoDosLembretesDeVencimento } from "../_shared/uma-voz/fontes.ts";
import { portaoDasConfiguracoes, registrarNoPortao } from "../_shared/uma-voz/registrar.ts";
import { pedirSimAoDono, proporLembretesDeVencimento } from "./propor.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const jr = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, "Content-Type": "application/json" } });

const ligado = (v: string | undefined) => (v ?? "on").trim().toLowerCase().replace(/"/g, "") !== "off";

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  // Era fail-OPEN (`if (cronSecret) { ... }`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "receivable-reminders");
  if (recusa) return recusa;

  const dry = new URL(req.url).searchParams.get("dry") === "1";
  const agora = new Date();
  // Janela da manhã (07:30–09:30): só a manhã pergunta. O ?dry=1 roda a qualquer hora.
  if (!dry && !depoisDaJanelaDaManha(agora)) return jr({ ok: true, fora_da_janela: true });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    const { data: linhas, error: eS } = await admin.from("app_settings").select("key, value");
    if (eS) throw new Error(`Falha ao ler as configurações: ${eS.message}`);
    const settings: Record<string, string> = {};
    for (const r of (linhas ?? []) as Array<{ key: string; value: unknown }>) settings[r.key] = String(r.value ?? "");
    if (!ligado(settings.lembrete_vencimento_ativo)) return jr({ ok: true, desligado: true });
    // Modo de teste sem número: o envio iria ao cliente de verdade — nem pergunta.
    if (modoDeTesteSemNumero(settings)) return jr({ ok: false, reason: "test_mode_no_number" });

    // Dia útil pela agenda. Sem resposta do banco, não pergunta (falha fechada).
    const hoje = diaLocal(agora);
    if (!dry) {
      const { data: util, error: eU } = await admin.rpc("agenda_dia_util", { p_dia: hoje });
      if (eU) throw new Error(`agenda_dia_util(${hoje}): ${eU.message}`);
      if (util !== true) return jr({ ok: true, dia_util: false, hoje });
    }

    const diasAntes = parseInt(settings.receivable_reminder_days_before || "3", 10);
    const rodada = await proporLembretesDeVencimento(admin, { hoje, diasAntes: Number.isFinite(diasAntes) ? diasAntes : 3, agora });
    const teste = numeroDeTesteAtivo(settings) !== null;
    if (dry) {
      return jr({
        ok: true, dry: true, hoje,
        propostas: rodada.propostas.map((l) => ({ conta: l.conta.id, cliente: l.nomeDoCliente, cartao: cartaoDoLembreteDeVencimento(l, { teste }) })),
        pulados: rodada.pulados,
        ja_pedidas: rodada.jaPedidas,
      });
    }
    for (const x of rodada.pulados) console.info(`[receivable-reminders] ${x.conta}: ${x.motivo}`);
    if (!rodada.propostas.length) return jr({ ok: true, propostas: 0, pulados: rodada.pulados.length, ja_pedidas: rodada.jaPedidas });

    // Quem aprova: o primeiro admin ativo com o assistente no WhatsApp (o dono). Um só, de propósito: a mesma mensagem em
    // duas conversas seria aprovada duas vezes.
    const { data: donos, error: eD } = await admin.from("app_users").select("id, phone_normalized")
      .eq("role", "admin").eq("active", true).eq("ai_whatsapp_enabled", true).not("phone_normalized", "is", null)
      .order("created_at", { ascending: true }).limit(1);
    if (eD) throw new Error(`Falha ao ler o dono: ${eD.message}`);
    const dono = donos?.[0] ? { id: donos[0].id as string, phone: donos[0].phone_normalized as string } : null;
    if (!dono) return jr({ ok: true, sem_dono: true, propostas: rodada.propostas.length });

    const sessao = await resolveOrCreateWhatsAppSession(admin, dono.phone, dono.id);
    const { data: s } = await admin.from("ai_operator_sessions").select("metadata").eq("id", sessao).maybeSingle();
    const metadata = (s?.metadata ?? {}) as Record<string, unknown>;
    // Uma pergunta por vez no WhatsApp do dono (erro na leitura = ocupado): a rodada espera a próxima.
    const conversaLigada = conversaDosComprovantesLigada(settings);
    const ocupado = await donoOcupadoParaPerguntar(admin, { phone: dono.phone, metadata, ligada: conversaLigada, agora });
    if (ocupado.ocupado) {
      return jr({ ok: true, adiado_por_pergunta: true, por: ocupado.por, propostas: rodada.propostas.length, pulados: rodada.pulados.length });
    }

    const ids = await pedirSimAoDono(admin, dono, sessao, metadata, rodada.propostas, { teste, conversaLigada, agora });
    // Voz única: a rodada que perguntou fica registrada como "fica como está". Nunca lança.
    await registrarNoPortao(admin, portaoDasConfiguracoes(settings).modo, dono.phone,
      avisoDosLembretesDeVencimento(hoje, agora, ids.length, `Lembretes antes do vencimento para aprovar: ${ids.length}.`), agora);
    return jr({ ok: true, propostas: ids.length, pulados: rodada.pulados.length, ja_pedidas: rodada.jaPedidas });
  } catch (e) {
    console.error("[receivable-reminders] erro", e);
    return jr({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
