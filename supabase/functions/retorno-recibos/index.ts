// Edge Function: retorno-recibos (Retorno rápido ao cliente, F1, parte P11; sobe em sombra em 16/11/2026).
//
// Quem chama é só o cron 'retorno-minuto' (P9), a cada minuto, e só quando o banco diz que há texto
// vencido (retorno_tem_vencido): o SQL decide antes de chamar a edge, para nada ficar batendo à toa
// (incidente de 17/08). Aqui a rodada (./rodada.ts) pega as saídas vencidas uma a uma no banco
// (retorno_pegar), confere cada texto no validador que falha fechado e registra o desfecho: na sombra,
// "eu teria mandado"; ligada, envia pelo whatsapp-send com a origem retorno_* e a chave do banco.
// No máximo 45 s e 20 itens por chamada: o que sobrar fica para o minuto seguinte.
//
// A porta é só o x-cron-secret (verify_jwt = false no config.toml, como acompanhar-conversas), conferido
// ANTES de qualquer I/O e falhando fechado (CRON_SECRET ausente = recusa tudo). Só POST, o método do
// net.http_post do cron.
//
// Resposta: o resumo da rodada. Quando a rodada parou por erro (retorno_pegar falhou, item ilegível ou
// repetido), o status é 500, para o servirComCors gravar em app_error_logs: com 200, o erro do banco
// ficaria só no net._http_response, que ninguém lê (desvio registrado na entrega da P11).
//
// Imports só de supabase-js, _shared/cors.ts, _shared/cron-auth.ts e ./rodada.ts (que importa só o
// validador): nada de _shared/ai/ nem _shared/agenda/ (isolamento_test.ts, J.1).
//
// Reverter: primeiro desligar o cron 'retorno-minuto' (P9), depois apagar esta pasta e o bloco
// [functions.retorno-recibos] do supabase/config.toml.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";
import { verificarCronSecret } from "../_shared/cron-auth.ts";
import { envioPeloWhatsappSend, rodada } from "./rodada.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "content-type, x-cron-secret",
};
const jr = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...corsHeaders, "Content-Type": "application/json" } });

servirComCors(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });

  const recusa = verificarCronSecret(req, corsHeaders, "retorno-recibos");
  if (recusa) return recusa;
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SERVICE_ROLE) return jr({ error: "not_configured" }, 500);

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
  const enviarPeloWhatsappSend = envioPeloWhatsappSend(SUPABASE_URL, SERVICE_ROLE);
  const resumo = await rodada(admin, {
    agora: () => new Date(),
    enviar: enviarPeloWhatsappSend,
    limiteMs: 45_000,
    maxItens: 20,
  });
  return jr(resumo, resumo.erro ? 500 : 200);
});
