// Edge Function: client-portal — APOSENTADA em 29/09/2026 (decisão do dono).
//
// Buscava o cliente por CPF/CNPJ ou por TRECHO de telefone/WhatsApp (5 dígitos bastavam) e
// devolvia as OS dele com o share_token, que abre a página pública com o cadastro completo.
// Estava quebrada desde maio (colunas renomeadas); consertar só isso teria aberto os dados de
// 533 clientes. O filtro .or() ainda recebia o texto digitado sem escape.
//
// Fica como stub 410 (mesmo caminho das edges órfãs de 19/09): quem ainda chamar recebe
// "não existe mais" em vez de erro, e nada é lido do banco. Apagar a função depois de alguns
// dias sem chamadas.
import { ORIGEM_PADRAO, servirComCors } from "../_shared/cors.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": ORIGEM_PADRAO,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

servirComCors((req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  return new Response(
    JSON.stringify({ error: "O portal do cliente foi desativado. Os documentos são enviados em PDF pelo WhatsApp." }),
    { status: 410, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
