// Edge Function: comprovantes-whatsapp (F1, 11/10/2026 — spec-f1-final.md)
//
// Recebe, guarda e entrega a leitura dos comprovantes que o dono manda ao WhatsApp do sistema:
//   receber  ← whatsapp-webhook (chamadaInterna), quando app_settings.comprovante_fluxo ≠ off;
//   entrega  ← gatilho _ai_jobs_comprovante_lido, quando o HBR Doc Worker termina a leitura;
//   vigiar   ← pg_cron comprovantes-vigia (*/2, só quando há trabalho);
//   repescar ← manual, com OK do dono.
// Quem decide é o banco (RPCs comprovante_*); esta função baixa, guarda, sobe no Dropbox e fala no
// WhatsApp quando o banco manda. Portas e ações em handler.ts; a orquestração em
// _shared/comprovantes/fluxo.ts.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { servirComCors } from "../_shared/cors.ts";
import { createWhatsAppProvider } from "../_shared/whatsapp/factory.ts";
import type { WhatsAppProvider } from "../_shared/whatsapp/types.ts";
import { abrirDropbox } from "../_shared/dropbox/cliente.ts";
import { type DependenciasDoFluxo, logDoFluxo } from "../_shared/comprovantes/fluxo.ts";
import { criarHandler } from "./handler.ts";

function montarDeps(): DependenciasDoFluxo {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const chave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, chave, { auth: { persistSession: false, autoRefreshToken: false } });
  // Sem credencial da Evolution, o fluxo segue sem reação (o aviso vai pelo whatsapp-send).
  let whatsapp: WhatsAppProvider | null = null;
  try {
    whatsapp = createWhatsAppProvider();
  } catch {
    whatsapp = null;
  }
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  return {
    admin,
    whatsapp,
    dropbox: () => abrirDropbox(admin),
    fetch: (entrada, init) => fetch(entrada, init),
    agora: () => new Date(),
    log: logDoFluxo,
    supabaseUrl: url,
    serviceRoleKey: chave,
    internalSecret: Deno.env.get("AI_INTERNAL_SECRET") ?? "",
    waitUntil: typeof runtime?.waitUntil === "function" ? (p) => runtime.waitUntil(p) : undefined,
  };
}

servirComCors(criarHandler(montarDeps));
