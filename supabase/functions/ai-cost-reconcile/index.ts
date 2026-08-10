// Edge Function: ai-cost-reconcile
//
// Troca ESTIMATIVA por FATO no custo de IA. A view v_ai_custo_diario calculava o gasto
// multiplicando tokens por preços de tabela — o que ignora markup do OpenRouter, promoção
// vigente e o desconto de cache que ele aplica. O OpenRouter expõe, por chamada, o valor
// efetivamente cobrado em `GET /api/v1/generation?id=`.
//
// O id da geração já vinha na resposta de toda chamada e era descartado; agora `ai-agent` o
// grava em ai_operator_messages.openrouter_generation_id, e esta função o troca por dinheiro.
//
// Roda de HORA EM HORA de propósito: o OpenRouter não guarda geração indefinidamente, então
// perguntar perto do fato é o que garante resposta. Linhas que falham 5 vezes são abandonadas
// para a fila não crescer para sempre.
//
// Idempotente: só toca linhas com custo_reconciliado_em nulo.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { verificarCronSecret } from "../_shared/cron-auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Teto por execução. Com cron horário e ~60 chamadas/dia no pico, 200 cobre com folga
 *  e ainda protege contra uma fila represada virar centenas de requisições de uma vez. */
const MAX_POR_RODADA = 200;
const MAX_TENTATIVAS = 5;

type LinhaPendente = {
  id: string;
  openrouter_generation_id: string;
  reconcile_tentativas: number;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  // Era fail-OPEN (`if (cronSecret) { ... }`): sem o env var, a função ficava aberta.
  const recusa = verificarCronSecret(req, corsHeaders, "ai-cost-reconcile");
  if (recusa) return recusa;

  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) return jr({ error: "OPENROUTER_API_KEY não configurada" }, 500);

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: pendentes, error: erroBusca } = await admin
      .from("ai_operator_messages")
      .select("id, openrouter_generation_id, reconcile_tentativas")
      .not("openrouter_generation_id", "is", null)
      .is("custo_reconciliado_em", null)
      .lt("reconcile_tentativas", MAX_TENTATIVAS)
      .order("created_at", { ascending: false })
      .limit(MAX_POR_RODADA);

    if (erroBusca) throw erroBusca;

    const linhas = (pendentes || []) as LinhaPendente[];
    if (linhas.length === 0) return jr({ ok: true, pendentes: 0, reconciliadas: 0 });

    let reconciliadas = 0;
    let aindaIndisponiveis = 0;
    let comErro = 0;
    let somaUsd = 0;

    for (const linha of linhas) {
      try {
        const res = await fetch(
          `https://openrouter.ai/api/v1/generation?id=${encodeURIComponent(linha.openrouter_generation_id)}`,
          { headers: { Authorization: `Bearer ${apiKey}` } },
        );

        if (!res.ok) {
          // 404 = geração ainda não indexada (ou já expirada). Conta a tentativa e segue: a
          // próxima rodada tenta de novo, até o teto. Não é erro que mereça derrubar o lote.
          aindaIndisponiveis++;
          await admin
            .from("ai_operator_messages")
            .update({ reconcile_tentativas: linha.reconcile_tentativas + 1 })
            .eq("id", linha.id);
          continue;
        }

        const json = await res.json();
        const g = json?.data ?? json;

        const totalCost = Number(g?.total_cost);
        if (!Number.isFinite(totalCost)) {
          aindaIndisponiveis++;
          await admin
            .from("ai_operator_messages")
            .update({ reconcile_tentativas: linha.reconcile_tentativas + 1 })
            .eq("id", linha.id);
          continue;
        }

        const cacheDiscount = Number(g?.cache_discount);

        const { error: erroUpdate } = await admin
          .from("ai_operator_messages")
          .update({
            usd_real: totalCost,
            usd_cache_discount: Number.isFinite(cacheDiscount) ? cacheDiscount : null,
            custo_reconciliado_em: new Date().toISOString(),
            reconcile_tentativas: linha.reconcile_tentativas + 1,
          })
          .eq("id", linha.id);

        if (erroUpdate) throw erroUpdate;

        reconciliadas++;
        somaUsd += totalCost;
      } catch (e) {
        // Falha numa linha não pode derrubar o lote inteiro.
        comErro++;
        console.error(`[ai-cost-reconcile] falha na linha ${linha.id}:`, e);
      }
    }

    console.log(
      `[ai-cost-reconcile] lote=${linhas.length} reconciliadas=${reconciliadas} ` +
        `indisponiveis=${aindaIndisponiveis} erros=${comErro} usd=${somaUsd.toFixed(4)}`,
    );

    return jr({
      ok: true,
      pendentes: linhas.length,
      reconciliadas,
      ainda_indisponiveis: aindaIndisponiveis,
      com_erro: comErro,
      usd_reconciliado_nesta_rodada: Number(somaUsd.toFixed(6)),
    });
  } catch (e: any) {
    console.error("ai-cost-reconcile error", e);
    return jr({ error: e?.message || "internal error" }, 500);
  }
});
