// STUB DE DESATIVAÇÃO (19/09/2026). A edge `evolution-debug` era um endpoint temporário do
// cutover Z-API → Evolution (maio/2026) que aceitava POST SEM JWT e gravava qualquer payload
// na tabela webhook_debug. Ficou órfã em produção. A exclusão (`functions delete`) está na
// fila do dono; até lá, esta versão substitui a antiga: responde 410 e não grava nada.
// Quando o dono apagar a função, esta pasta pode ser removida do repositório.
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

servirComCors((req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  return new Response(
    JSON.stringify({ error: "evolution-debug foi desativada em 19/09/2026 (endpoint temporário do cutover)." }),
    { status: 410, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
