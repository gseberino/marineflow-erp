// Edge lembretes-de-revisao (07/10/2026) — planos de manutenção com lembretes ao cliente.
//
// Chamada pelo pg_cron (x-cron-secret) às 09:05 de Brasília, terça a quinta. O cron NÃO está na
// migration (o dono autoriza e ele é aplicado à parte):
//   select cron.schedule('lembretes-de-revisao', '5 12 * * 2-4', $cron$
//     select net.http_post(
//       url := 'https://okurngvcodmljjicopdp.supabase.co/functions/v1/lembretes-de-revisao',
//       headers := jsonb_build_object('Content-Type', 'application/json',
//         'x-cron-secret', (select value::text from app_settings where key = 'cron_worker_secret' limit 1)),
//       body := '{}'::jsonb, timeout_milliseconds := 60000);
//   $cron$);
//
// O que faz (nada sai para o cliente aqui — decisão do dono: sempre com o "sim" dele antes):
//  1. acha os toques devidos (D-21, D-7 sem resposta, D+14 sem resposta e sem OS) e, de 15/09 a
//     31/10, a campanha de temporada (rodada.ts / texto.ts);
//  2. registra o que foi pulado (opt-out, sem telefone, lembrete desligado, OS agendada);
//  3. cada mensagem vira uma pendência do assistente (action_name enviar_lembrete_de_revisao) na
//     conversa de WhatsApp do dono — o MESMO mecanismo do acompanhar-conversas e do sino: a
//     primeira é perguntada agora; as outras encadeiam no "sim"/"não" (comAProximaPendencia, que
//     junta as pendências criadas no mesmo minuto). "sim, mas troca a data…" vai ao assistente,
//     que refaz o pedido com o texto novo.
// Não atropela o dono: se ele tem uma confirmação aberta, a rodada espera a próxima.
// Interruptores: app_settings.lembretes_revisao_ativo e campanha_temporada_ativa (padrão 'on').
// ?dry=1 devolve o que seria proposto, sem gravar nada (qualquer dia da semana).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { pendenciaQueSegueEsperando, queueWhatsAppReply, resolveOrCreateWhatsAppSession } from "../_shared/ai/whatsapp-channel.ts";
import { numeroDeTesteAtivo } from "../_shared/whatsapp/marcar-enviado.ts";
import { ehTerAQui, hojeEmBrasilia } from "../_shared/revisao/texto.ts";
import {
  ACAO_DE_ENVIO,
  payloadDaProposta,
  perguntaAoDono,
  type Proposta,
  referenciaParaOAssistente,
  resumoDaProposta,
} from "../_shared/revisao/lembretes.ts";
import {
  eventosDaProposta,
  MAX_PROPOSTAS_POR_RODADA,
  proporCampanha,
  proporToques,
  registrarPulados,
} from "../_shared/revisao/rodada.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "content-type, x-cron-secret",
};
const jr = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, "Content-Type": "application/json" } });

// deno-lint-ignore no-explicit-any
type Db = any;

const ligado = (v: string | undefined) => (v ?? "on").trim().toLowerCase().replace(/"/g, "") !== "off";

/** Cria as pendências (na ordem), grava os eventos "proposto" e pergunta a primeira ao dono. */
async function proporAoDono(
  admin: Db,
  dono: { id: string; phone: string },
  sessao: string,
  metadata: Record<string, unknown>,
  propostas: Proposta[],
  teste: boolean,
): Promise<string[]> {
  const ids: string[] = [];
  const expira = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  for (const p of propostas) {
    const { data, error } = await admin.from("ai_operator_pending_actions").insert({
      session_id: sessao,
      requested_by_user_id: dono.id,
      action_name: ACAO_DE_ENVIO,
      risk_level: "medium",
      risk_reason: "Mensagem a cliente em nome da empresa (lembrete de revisão).",
      title: p.titulo,
      summary: resumoDaProposta(p, teste),
      payload: payloadDaProposta(p),
      status: "pending",
      expires_at: expira,
    }).select("id").single();
    if (error || !data) throw new Error(`Falha ao criar a pendência do lembrete: ${error?.message ?? "sem id"}`);
    ids.push(data.id);
    const { error: eEv } = await admin.from("maintenance_plan_events").insert(eventosDaProposta(p, data.id));
    if (eEv) console.error("[lembretes-de-revisao] evento 'proposto' não gravado", data.id, eEv.message);
  }

  const primeira = propostas[0];
  const pergunta = perguntaAoDono(primeira, teste, propostas.length);
  await admin.from("ai_operator_sessions").update({
    metadata: { ...metadata, pending_confirm_action_id: ids[0], pin_attempts: 0, pendencia_herdada: false },
    last_activity_at: new Date().toISOString(),
  }).eq("id", sessao);
  // No histórico da conversa, com os ids: se o dono pedir ajuste, o assistente refaz o pedido. Vai
  // em par (a janela do histórico começa numa fala "user"): a marca 🤖 diz que não foi o dono que
  // escreveu, como no acompanhar-conversas. Horários explícitos para a ordem não empatar.
  const t0 = Date.now();
  const { error: eH } = await admin.from("ai_operator_messages").insert([
    {
      session_id: sessao, role: "user", source: "whatsapp", created_at: new Date(t0).toISOString(),
      content: `🤖 Lembretes de revisão de hoje (aviso automático da rotina lembretes-de-revisao): ${propostas.length} para aprovar.`,
    },
    {
      session_id: sessao, role: "assistant", source: "whatsapp", created_at: new Date(t0 + 1).toISOString(),
      content: `${pergunta}\n\n${propostas.map(referenciaParaOAssistente).join("\n")}`,
    },
  ]);
  if (eH) console.error("[lembretes-de-revisao] histórico não gravado", eH.message);
  await queueWhatsAppReply(admin, dono.phone, pergunta);
  await admin.from("ai_operator_audit").insert({
    session_id: sessao, actor_user_id: dono.id, actor_kind: "system", event_type: "lembretes_de_revisao:propostos",
    event_category: "data", payload: { pendencias: ids, clientes: propostas.map((p) => p.cliente) },
  });
  return ids;
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const negado = verificarCronSecret(req, corsHeaders, "lembretes-de-revisao");
  if (negado) return negado;

  const dry = new URL(req.url).searchParams.get("dry") === "1";
  const agora = new Date();
  const hoje = hojeEmBrasilia(agora);
  if (!dry && !ehTerAQui(hoje)) return jr({ ok: true, fora_do_dia: true });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    const { data: linhas, error: eS } = await admin.from("app_settings").select("key, value");
    if (eS) throw new Error(`Falha ao ler as configurações: ${eS.message}`);
    const settings: Record<string, string> = {};
    for (const r of (linhas ?? []) as Array<{ key: string; value: unknown }>) settings[r.key] = String(r.value ?? "");
    const lembretes = ligado(settings.lembretes_revisao_ativo);
    const campanha = ligado(settings.campanha_temporada_ativa);
    if (!lembretes && !campanha) return jr({ ok: true, desligado: true });

    const { propostas: toques, pulados, planos } = lembretes ? await proporToques(admin, hoje) : { propostas: [], pulados: [], planos: [] };
    const daCampanha = campanha ? await proporCampanha(admin, hoje, planos) : [];
    const propostas = [...toques, ...daCampanha].slice(0, MAX_PROPOSTAS_POR_RODADA);
    const teste = numeroDeTesteAtivo(settings) !== null;

    if (dry) {
      return jr({
        ok: true, dry: true, hoje,
        propostas: propostas.map((p) => ({ titulo: p.titulo, toque: p.toque, texto: p.texto, payload: payloadDaProposta(p) })),
        pulados: pulados.map((p) => ({ plano: p.plano.plan_name, embarcacao: p.plano.vessel_name, toque: p.toque, motivo: p.motivo })),
      });
    }

    await registrarPulados(admin, pulados);
    if (!propostas.length) return jr({ ok: true, propostas: 0, pulados: pulados.length });

    // Quem aprova: o primeiro admin ativo com o assistente no WhatsApp (o dono). Um só, de propósito:
    // a mesma mensagem em duas conversas seria aprovada duas vezes.
    const { data: donos, error: eD } = await admin.from("app_users").select("id, phone_normalized")
      .eq("role", "admin").eq("active", true).eq("ai_whatsapp_enabled", true).not("phone_normalized", "is", null)
      .order("created_at", { ascending: true }).limit(1);
    if (eD) throw new Error(`Falha ao ler o dono: ${eD.message}`);
    const dono = donos?.[0] ? { id: donos[0].id as string, phone: donos[0].phone_normalized as string } : null;
    if (!dono) return jr({ ok: true, sem_dono: true, propostas: propostas.length });

    const sessao = await resolveOrCreateWhatsAppSession(admin, dono.phone, dono.id);
    const { data: s } = await admin.from("ai_operator_sessions").select("metadata").eq("id", sessao).maybeSingle();
    const metadata = (s?.metadata ?? {}) as Record<string, unknown>;
    if (await pendenciaQueSegueEsperando(admin, metadata, agora)) {
      return jr({ ok: true, adiado_por_pendencia: true, propostas: propostas.length, pulados: pulados.length });
    }

    const ids = await proporAoDono(admin, dono, sessao, metadata, propostas, teste);
    return jr({ ok: true, propostas: ids.length, pulados: pulados.length });
  } catch (e) {
    console.error("[lembretes-de-revisao] erro", e);
    return jr({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
