// Vigia acompanhar-conversas (06/10/2026) — plans/marineflow-acompanhar-conversa.md
//
// Chamado pelo pg_cron a cada 15 min (x-cron-secret). Só age entre 8h e 20h de Brasília, seg–sáb:
//  1. PROMESSAS: lê o que o dono mandou desde a última rodada e, achando "te mando amanhã" e afins,
//     cria um lembrete (whatsapp_acompanhamentos, modo 'promessa'). Sem IA.
//  2. AVISOS: para cada acompanhamento devido, pede ao assistente — pelo MESMO caminho de uma
//     mensagem do dono (ai-agent, x-internal-secret) — que leia a conversa e sugira a resposta. O dono
//     recebe a confirmação de sempre (sim / "não, muda…"). Nada sai para o contato sem esse sim.
// Não atropela o dono: se ele tem uma confirmação aberta, o aviso espera a próxima rodada. Com a
// conversa dos comprovantes ligada (F2, 11/10/2026), "aberta" é o registro único de pergunta ativa:
// a pergunta de um comprovante ou um "posso mandar?" dos lembretes também faz esperar. A pendência
// que o assistente criar com o aviso entra no registro pelo próprio ai-agent.
// Contato que disse que fechou com outra empresa ou desistiu (15/10/2026): o acompanhamento se
// encerra sozinho, sem aviso (regra de palavras, _shared/whatsapp/contato-encerrou.ts).
// Secretário, Passo 4 (15/10/2026, spec-secretario-uma-voz.md):
//  * janela da manhã: o aviso de acompanhamento e o de promessa só a partir das 09:30 (o lembrete
//    pedido com hora segue das 8h); a detecção de promessas segue das 8h;
//  * freio (app_settings.acompanhar_freio): no máximo 2 avisos sobre a mesma mensagem do contato; o
//    aviso volta quando ele escreve de novo. Conta pelo portão (avisos_do_dono, referência
//    acomp:<id>:<última recebida>): com o freio ligado, cada aviso que SAIU é registrado lá;
//  * voz única em sombra (app_settings.voz_unica): os avisos que saíram são registrados no portão com o
//    que ele faria (acordar, guardar, deixar). O que sai para o dono não muda.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { detectarPromessa } from "../_shared/ai/promessa.ts";
import {
  type Acompanhamento, aplicarFreio, decidir, diaEmBrasilia, type EstadoDaConversa, horaDeAvisar, janelaDoEncerramento,
  MOTIVO_FREIO, podeAvisarNoModo, textoDoAviso,
} from "../_shared/ai/acompanhar.ts";
import { avisoDoAcompanhamento, referenciaDoAcompanhamento } from "../_shared/uma-voz/fontes.ts";
import {
  avisosDestaMensagem, modoDoRegistroDoAcompanhamento, type PortaoDaRodada, portaoDasConfiguracoes, registrarNoPortao,
} from "../_shared/uma-voz/registrar.ts";
import { conversaEncerradaPeloContato, ULTIMAS_RECEBIDAS } from "../_shared/whatsapp/contato-encerrou.ts";
import {
  conversaDosComprovantesLigada,
  donoOcupadoParaPerguntar,
  resolveOrCreateWhatsAppSession,
} from "../_shared/ai/whatsapp-channel.ts";
import { telefoneLegivel } from "../_shared/ai/tools/agendamento.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "content-type, x-cron-secret",
};
const jr = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, "Content-Type": "application/json" } });

/** Avisos por rodada: cada um é um turno do assistente (até ~1 min no OpenRouter). */
const AVISOS_POR_RODADA = 2;

// deno-lint-ignore no-explicit-any
type Db = any;

async function estadoDaConversa(admin: Db, a: Pick<Acompanhamento, "phone_normalized" | "created_at">, agora: Date): Promise<EstadoDaConversa> {
  const phone = a.phone_normalized;
  const [{ data: rec }, { data: env }] = await Promise.all([
    // As 5 últimas recebidas: a 1ª é a "última recebida"; as que caem na janela (7 dias, e só
    // depois de o acompanhamento nascer) dizem se o contato fechou com outra empresa ou desistiu.
    // A última sozinha não basta: o Miguel disse "fechando com outra empresa" e depois "Sim, já fechei".
    admin.from("whatsapp_messages").select("body, occurred_at").eq("phone_normalized", phone).eq("direction", "inbound")
      .order("occurred_at", { ascending: false }).limit(ULTIMAS_RECEBIDAS),
    admin.from("whatsapp_messages").select("occurred_at").eq("phone_normalized", phone).eq("direction", "outbound")
      .order("occurred_at", { ascending: false }).limit(1),
  ]);
  const recebidas = (rec ?? []) as Array<{ body: string | null; occurred_at: string }>;
  const r = recebidas[0];
  const desde = Date.parse(janelaDoEncerramento(a, agora));
  return {
    ultimaRecebida: r ? { em: r.occurred_at, texto: String(r.body ?? "") } : null,
    ultimaEnviadaEm: env?.[0]?.occurred_at ?? null,
    encerrouPeloContato: conversaEncerradaPeloContato(
      recebidas.filter((m) => Date.parse(m.occurred_at) >= desde).map((m) => m.body),
    ),
  };
}

/** 1. Promessas do dono desde o cursor. */
async function detectarPromessas(admin: Db, dono: { id: string }, internos: Set<string>, settings: Record<string, string>, agora: Date) {
  if ((settings.acompanhar_promessas || "on").trim().toLowerCase() === "off") return { lidas: 0, criadas: 0 };
  const cursor = settings.acompanhar_cursor && !Number.isNaN(Date.parse(settings.acompanhar_cursor))
    ? settings.acompanhar_cursor
    : new Date(agora.getTime() - 30 * 60_000).toISOString();
  const { data: msgs, error } = await admin.from("whatsapp_messages")
    .select("id, phone_normalized, body, occurred_at")
    .eq("direction", "outbound").gt("occurred_at", cursor).order("occurred_at", { ascending: true }).limit(200);
  if (error) throw error;
  let criadas = 0;
  let ate = cursor;
  for (const m of (msgs ?? []) as Array<{ id: string; phone_normalized: string; body: string | null; occurred_at: string }>) {
    ate = m.occurred_at;
    if (!m.phone_normalized || internos.has(m.phone_normalized)) continue;
    const p = detectarPromessa(m.body, new Date(m.occurred_at));
    if (!p) continue;
    const { data: lead } = await admin.from("whatsapp_leads").select("name").eq("phone_normalized", m.phone_normalized).maybeSingle();
    const { error: insErr } = await admin.from("whatsapp_acompanhamentos").insert({
      phone_normalized: m.phone_normalized, contato: lead?.name ?? null, modo: "promessa",
      lembrar_em: p.quando.toISOString(), promessa: p.trecho, origem_mensagem: m.id, criado_por: dono.id,
    });
    if (!insErr) criadas++;
    else if (insErr.code !== "23505") throw insErr; // 23505 = a mesma mensagem já virou promessa
  }
  if (ate !== cursor) await admin.from("app_settings").update({ value: ate }).eq("key", "acompanhar_cursor");
  return { lidas: (msgs ?? []).length, criadas };
}

/** 2. Avisos devidos. `conversaLigada` = conversa dos comprovantes ligada (conversaDosComprovantesLigada). */
async function avisar(admin: Db, agora: Date, conversaLigada: boolean, portao: PortaoDaRodada) {
  const { data: ativos, error } = await admin.from("whatsapp_acompanhamentos")
    .select("id, phone_normalized, contato, modo, intervalo_min, ate, lembrar_em, promessa, ultimo_aviso_em, avisos_dia, avisos_no_dia, created_at, criado_por")
    .eq("status", "ativo").order("created_at", { ascending: true }).limit(100);
  if (error) throw error;
  const resultado = {
    avaliados: 0, avisados: 0, encerrados: 0, adiados_por_pendencia: 0, na_janela_da_manha: 0, parados_pelo_freio: 0, no_portao: 0,
  };
  const donos = new Map<string, { id: string; phone: string } | null>();

  for (const a of (ativos ?? []) as Array<Acompanhamento & { criado_por: string | null }>) {
    resultado.avaliados++;
    const conversa = await estadoDaConversa(admin, a, agora);
    let d = decidir(a, conversa, agora);
    if (d.acao === "encerrar") {
      await admin.from("whatsapp_acompanhamentos").update({ status: "encerrado", encerrado_motivo: d.motivo, updated_at: agora.toISOString() }).eq("id", a.id);
      resultado.encerrados++;
      continue;
    }
    if (d.acao !== "avisar" || resultado.avisados >= AVISOS_POR_RODADA) continue;

    // Janela da manhã: acompanhamento e promessa esperam as 09:30 (o devido continua devido).
    if (!podeAvisarNoModo(a.modo, agora)) {
      resultado.na_janela_da_manha++;
      continue;
    }

    // Freio: quantos avisos já saíram sobre esta mensagem dele (pelo portão). Só no modo acompanhar.
    const referencia = referenciaDoAcompanhamento(a.id, conversa.ultimaRecebida?.em ?? null);
    const jaAvisados = a.modo === "acompanhar" && (portao.freio || portao.modo) ? await avisosDestaMensagem(admin, referencia) : null;
    if (portao.freio) {
      d = aplicarFreio(d, a, jaAvisados, portao.regras.freio_avisos);
      if (d.acao === "esperar" && d.motivo === MOTIVO_FREIO) {
        resultado.parados_pelo_freio++;
        continue;
      }
    }

    // Quem recebe o aviso: quem pediu, se tem o assistente no WhatsApp ligado.
    if (!a.criado_por) continue;
    if (!donos.has(a.criado_por)) {
      const { data: u } = await admin.from("app_users").select("id, phone_normalized")
        .eq("id", a.criado_por).eq("ai_whatsapp_enabled", true).eq("active", true).maybeSingle();
      donos.set(a.criado_por, u?.phone_normalized ? { id: u.id, phone: u.phone_normalized } : null);
    }
    const dono = donos.get(a.criado_por);
    if (!dono) continue;

    // Não atropela uma pergunta aberta do dono (o aviso traria outra e cancelaria a dele): a
    // confirmação do assistente e, com a conversa dos comprovantes ligada, a pergunta de um
    // comprovante ou um lembrete (registro único; erro na leitura = ocupado, espera a próxima rodada).
    const sessao = await resolveOrCreateWhatsAppSession(admin, dono.phone, dono.id);
    const { data: s } = await admin.from("ai_operator_sessions").select("metadata").eq("id", sessao).maybeSingle();
    const ocupado = await donoOcupadoParaPerguntar(admin, { phone: dono.phone, metadata: s?.metadata ?? {}, ligada: conversaLigada, agora });
    if (ocupado.ocupado) {
      resultado.adiados_por_pendencia++;
      continue;
    }

    const texto = textoDoAviso(a, conversa, agora, telefoneLegivel(a.phone_normalized));
    const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/ai-agent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-internal-secret": Deno.env.get("AI_INTERNAL_SECRET") ?? "" },
      body: JSON.stringify({ channel: "whatsapp", phone_normalized: dono.phone, app_user_id: dono.id, text: texto }),
      signal: AbortSignal.timeout(110_000),
    }).catch((e) => ({ ok: false, status: 0, text: () => Promise.resolve(String(e)) }) as unknown as Response);
    if (!res.ok) {
      console.error("[acompanhar-conversas] ai-agent recusou o aviso", a.id, res.status, await res.text().catch(() => ""));
      continue;
    }
    // O aviso SAIU: registra no portão (a conta do freio e a sombra da voz única). Nunca lança.
    const modoRegistro = modoDoRegistroDoAcompanhamento(portao, a.modo);
    if (modoRegistro) {
      const ordem = jaAvisados === null ? agora.getTime() : jaAvisados + 1;
      const r = await registrarNoPortao(admin, modoRegistro, dono.phone,
        avisoDoAcompanhamento(a, conversa.ultimaRecebida?.em ?? null, ordem, portao.regras, texto), agora);
      if (r) resultado.no_portao++;
    }
    const hoje = diaEmBrasilia(agora);
    const unico = a.modo !== "acompanhar";
    await admin.from("whatsapp_acompanhamentos").update({
      ultimo_aviso_em: agora.toISOString(),
      avisos_dia: hoje,
      avisos_no_dia: a.avisos_dia === hoje ? a.avisos_no_dia + 1 : 1,
      ...(unico ? { status: "encerrado", encerrado_motivo: "avisado" } : {}),
      updated_at: agora.toISOString(),
    }).eq("id", a.id);
    resultado.avisados++;
  }
  return resultado;
}

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const negado = verificarCronSecret(req, corsHeaders, "acompanhar-conversas");
  if (negado) return negado;
  const agora = new Date();
  if (!horaDeAvisar(agora)) return jr({ ok: true, fora_do_horario: true });

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  try {
    const { data: linhas } = await admin.from("app_settings").select("key, value");
    const settings: Record<string, string> = {};
    for (const r of (linhas ?? []) as Array<{ key: string; value: unknown }>) settings[r.key] = String(r.value ?? "");

    // Números internos (a equipe, o próprio dono): mensagem para eles não é promessa a cliente.
    const { data: usuarios } = await admin.from("app_users").select("id, phone_normalized, role, ai_whatsapp_enabled, active");
    const internos = new Set<string>(((usuarios ?? []) as any[]).map((u) => u.phone_normalized).filter(Boolean));
    const dono = ((usuarios ?? []) as any[]).find((u) => u.role === "admin" && u.ai_whatsapp_enabled && u.active && u.phone_normalized);

    const promessas = dono ? await detectarPromessas(admin, dono, internos, settings, agora) : { lidas: 0, criadas: 0, sem_dono: true };
    const avisos = await avisar(admin, agora, conversaDosComprovantesLigada(settings), portaoDasConfiguracoes(settings));
    return jr({ ok: true, promessas, avisos });
  } catch (e) {
    console.error("[acompanhar-conversas] erro", e);
    return jr({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
