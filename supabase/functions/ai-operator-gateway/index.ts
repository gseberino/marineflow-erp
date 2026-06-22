// Edge Function: ai-operator-core (NOVA — não substitui ai-agent nem nada)
//
// Handler HTTP FINO. Toda a lógica vive no orquestrador (testado). Esta função
// apenas: autentica → lê config (app_settings, read-only) → chama o orquestrador
// → devolve o PLANO. NÃO executa escrita nem envio (invariante de segurança).
// O funcionamento manual do ERP não é afetado: nenhuma função existente muda.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { handleOperatorTurn } from "./orchestrator.ts";
import {
  DEFAULT_POLICY_CONFIG,
  type PolicyConfig,
} from "../_shared/outbound-policy/index.ts";
import { buildLLMConfig, createLLMProvider } from "../_shared/llm/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Monta a config do motor a partir de app_settings (read-only), sobre defaults. */
function buildPolicyConfig(sm: Record<string, string>): PolicyConfig {
  const cfg: PolicyConfig = { ...DEFAULT_POLICY_CONFIG };
  // Shadow só desliga com opt-in explícito — segurança por padrão.
  if (sm["ai_operator_shadow_mode"] === "false") cfg.shadowMode = false;
  if (sm["ai_operator_approval_whatsapp"]) {
    cfg.approvalManager = {
      whatsapp: sm["ai_operator_approval_whatsapp"].replace(/\D/g, ""),
    };
  }
  if (sm["ai_operator_client_sends_require_confirmation"] === "false") {
    cfg.clientSendsRequireManagerConfirmation = false;
  }
  const maxV = Number(sm["ai_operator_auto_send_max_value"]);
  if (Number.isFinite(maxV) && maxV >= 0) cfg.autoSendMaxValue = maxV;
  return cfg;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
    const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Auth do chamador (exige sessão de usuário — sem service-role aqui).
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jr({ error: "Unauthorized" }, 401);
    const userClient = createClient(SUPABASE_URL, ANON, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData.user) return jr({ error: "Invalid session" }, 401);

    // Config via app_settings (READ-ONLY).
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: settings } = await admin.from("app_settings").select("key, value");
    const sm = Object.fromEntries(
      (settings || []).map((s: any) => [s.key, s.value]),
    );
    const policy = buildPolicyConfig(sm);

    // LLM como fallback (só chamado em intenção "unknown"). Chave vem de secret
    // (Deno.env); provider/modelo de app_settings. Ausência de chave = sem LLM.
    const llmConfig = buildLLMConfig(sm, (k) => Deno.env.get(k));
    const llm = llmConfig
      ? (text: string) =>
          createLLMProvider(llmConfig).complete([{ role: "user", content: text }])
      : undefined;

    const body = await req.json().catch(() => null);
    if (!body || typeof body.text !== "string") {
      return jr({ error: "Campo 'text' é obrigatório." }, 400);
    }

    // Orquestrador puro — NÃO escreve, NÃO envia. Só devolve o plano.
    const result = await handleOperatorTurn(
      {
        text: body.text,
        outboundAction: body.outboundAction,
        outboundContext: body.outboundContext
          ? { ...body.outboundContext, now: new Date(body.outboundContext.now ?? Date.now()) }
          : undefined,
      },
      { policy, llm },
    );

    return jr({ ok: true, result });
  } catch (err) {
    console.error("ai-operator-core error", err);
    return jr({ error: err instanceof Error ? err.message : "Unknown error" }, 500);
  }
});
