// Edge Function: banking-sync
//
// Puxa o extrato das conexões cadastradas (Open Finance via Pluggy/Meu Pluggy) e grava em
// bank_transactions. Não concilia nada — só traz o dado; casar com o financeiro é trabalho
// da banking-reconcile.
//
// Chamadores: o painel (botão "Sincronizar agora", com JWT) e o cron diário (x-cron-secret).
// Por isso verify_jwt=false no config.toml, com a checagem feita aqui dentro.
//
// A janela de busca é deliberadamente sobreposta ao que já foi importado: banco às vezes
// disponibiliza lançamento com atraso, e perder transação é muito pior que reprocessar —
// o id do provedor em bank_ref_id impede duplicata.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import {
  pluggyAuth, fetchItem, fetchAccounts, fetchTransactions, listItems,
  mapTransaction, accountSourceType,
} from "../_shared/banking/pluggy.ts";

type DbClient = SupabaseClient<any, "public", any>;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jr(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Quantos dias para trás buscar quando a conexão nunca sincronizou. */
const JANELA_INICIAL_DIAS = 365;
/** Sobreposição em cima da última transação conhecida, para pegar lançamento atrasado. */
const SOBREPOSICAO_DIAS = 7;

function diasAtras(dias: number): string {
  return new Date(Date.now() - dias * 86_400_000).toISOString().slice(0, 10);
}

interface SyncBody {
  /** Sincroniza só esta conexão; sem isso, todas as ativas. */
  connection_id?: string;
  /** Ignora a janela incremental e varre o período inteiro. */
  full?: boolean;
  /** `list_items` não sincroniza nada: só mostra o que as credenciais enxergam. */
  action?: "sync" | "list_items";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return jr({ error: "method_not_allowed" }, 405);

  const admin: DbClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const cronSecret = req.headers.get("x-cron-secret");
  const isCron = !!cronSecret && cronSecret === Deno.env.get("CRON_SECRET");
  if (!isCron) {
    const token = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    if (!token) return jr({ error: "unauthorized" }, 401);
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data?.user) return jr({ error: "unauthorized" }, 401);
  }

  const clientId = Deno.env.get("PLUGGY_CLIENT_ID");
  const clientSecret = Deno.env.get("PLUGGY_CLIENT_SECRET");
  if (!clientId || !clientSecret) {
    return jr({ error: "provider_not_configured", detail: "PLUGGY_CLIENT_ID/SECRET ausentes nos secrets." }, 500);
  }

  const body: SyncBody = await req.json().catch(() => ({}));

  try {
    // Descobrir o Item ID sem sair do sistema: o código não existe em lugar nenhum do
    // banco, só dentro do painel do provedor, e errar a aplicação de origem é o tropeço
    // mais comum. Aqui a própria integração diz o que ela consegue ver.
    if (body.action === "list_items") {
      const apiKey = await pluggyAuth(clientId, clientSecret);
      const itens = await listItems(apiKey);
      const { data: jaCadastrados } = await admin
        .from("bank_connections")
        .select("external_id");
      const cadastrados = new Set((jaCadastrados || []).map((c: any) => c.external_id));
      return jr({
        ok: true,
        itens: itens.map((i) => ({ ...i, ja_cadastrado: cadastrados.has(i.id) })),
      });
    }

    let q = admin.from("bank_connections").select("*").eq("active", true).eq("provider", "pluggy");
    if (body.connection_id) q = q.eq("id", body.connection_id);
    const { data: conexoes, error: connErr } = await q;
    if (connErr) throw connErr;

    if (!conexoes || conexoes.length === 0) {
      return jr({
        ok: true,
        message: "Nenhuma conexão bancária cadastrada.",
        resultados: [],
      });
    }

    const apiKey = await pluggyAuth(clientId, clientSecret);
    const resultados: Array<Record<string, unknown>> = [];

    for (const conexao of conexoes) {
      const resultado = await sincronizarConexao(admin, apiKey, conexao, !!body.full);
      resultados.push(resultado);
    }

    const importadas = resultados.reduce((s, r) => s + Number(r.importadas ?? 0), 0);
    const comErro = resultados.filter((r) => r.status === "error").length;

    return jr({
      ok: comErro === 0,
      message: `${importadas} transação(ões) nova(s)` + (comErro ? ` · ${comErro} conexão(ões) com erro` : ""),
      resultados,
    });
  } catch (e) {
    console.error("[banking-sync] erro:", e);
    return jr({ error: "unexpected_error", detail: String((e as Error)?.message ?? e) }, 500);
  }
});

async function sincronizarConexao(
  admin: DbClient,
  apiKey: string,
  conexao: any,
  full: boolean,
): Promise<Record<string, unknown>> {
  const rotulo = conexao.label as string;
  try {
    // O estado do item revela consentimento expirado ou login quebrado — casos em que a
    // coleta pararia em silêncio se ninguém olhasse.
    const item = await fetchItem(apiKey, conexao.external_id);
    const statusItem = String(item?.status ?? "").toUpperCase();
    if (statusItem === "LOGIN_ERROR" || statusItem === "WAITING_USER_INPUT") {
      const msg = statusItem === "LOGIN_ERROR"
        ? "A conexão com o banco caiu. Reconecte esta conta no meu.pluggy.ai."
        : "O banco está pedindo confirmação. Abra o meu.pluggy.ai e conclua a autorização.";
      await registrarResultado(admin, conexao.id, "error", msg, 0, null);
      return { conexao: rotulo, status: "error", mensagem: msg, importadas: 0 };
    }

    const desde = full
      ? diasAtras(JANELA_INICIAL_DIAS)
      : conexao.last_transaction_date
        ? new Date(new Date(`${conexao.last_transaction_date}T12:00:00Z`).getTime() - SOBREPOSICAO_DIAS * 86_400_000)
            .toISOString().slice(0, 10)
        : diasAtras(JANELA_INICIAL_DIAS);

    const contas = await fetchAccounts(apiKey, conexao.external_id);
    if (contas.length === 0) {
      const msg = "Nenhuma conta encontrada nesta conexão.";
      await registrarResultado(admin, conexao.id, "error", msg, 0, null);
      return { conexao: rotulo, status: "error", mensagem: msg, importadas: 0 };
    }

    let importadas = 0;
    let jaExistiam = 0;
    let dataMaisRecente: string | null = conexao.last_transaction_date ?? null;

    for (const conta of contas) {
      const origem = accountSourceType(conta);
      const transacoes = await fetchTransactions(apiKey, conta.id, desde);
      if (transacoes.length === 0) continue;

      const linhas = transacoes.map((t) => ({
        ...mapTransaction(t, origem),
        bank_connection_id: conexao.id,
        reconciled: false,
      }));

      for (const linha of linhas) {
        if (!dataMaisRecente || linha.transaction_date > dataMaisRecente) {
          dataMaisRecente = linha.transaction_date;
        }
      }

      // Descarta o que já está no banco antes de inserir. O índice único por
      // (bank_ref_id, source_type) é a rede de segurança; esta consulta evita depender
      // dela e permite contar quantas eram realmente novas.
      const refs = linhas.map((l) => l.bank_ref_id);
      const existentes = new Set<string>();
      for (let i = 0; i < refs.length; i += 200) {
        const { data } = await admin
          .from("bank_transactions")
          .select("bank_ref_id")
          .in("bank_ref_id", refs.slice(i, i + 200));
        for (const r of data || []) if (r.bank_ref_id) existentes.add(r.bank_ref_id);
      }

      const novas = linhas.filter((l) => !existentes.has(l.bank_ref_id));
      jaExistiam += linhas.length - novas.length;
      if (novas.length === 0) continue;

      for (let i = 0; i < novas.length; i += 200) {
        const lote = novas.slice(i, i + 200);
        const { error } = await admin.from("bank_transactions").insert(lote);
        if (error) throw error;
        importadas += lote.length;
      }
    }

    const mensagem = importadas > 0
      ? `${importadas} transação(ões) nova(s)`
      : jaExistiam > 0 ? "Nada novo — tudo já estava importado" : "Sem movimentação no período";

    await registrarResultado(admin, conexao.id, "ok", mensagem, importadas, dataMaisRecente);
    return { conexao: rotulo, status: "ok", mensagem, importadas, ja_existiam: jaExistiam };
  } catch (e) {
    let msg = String((e as Error)?.message ?? e).slice(0, 300);

    // "item not found" é o erro mais enganoso desta integração: o código está certo no
    // painel, mas pertence a OUTRA aplicação — e as credenciais aqui são de uma só. Sem
    // dizer isso, a pessoa fica reconferindo o código à toa. Então mostramos exatamente
    // quais itens estas credenciais enxergam.
    if (msg.includes("404") || msg.toUpperCase().includes("ITEM_NOT_FOUND")) {
      const visiveis = await listItems(apiKey);
      msg = visiveis.length === 0
        ? "As credenciais configuradas não enxergam nenhuma conexão. Confira se o CLIENT_ID/CLIENT_SECRET são da MESMA aplicação onde você autorizou o conector MeuPluggy."
        : `Este Item ID não pertence à aplicação configurada. As conexões visíveis com estas credenciais são: ${
            visiveis.map((i) => `${i.connector} (${i.id})`).join(" · ")
          }. Cadastre um destes, ou troque as credenciais para as da aplicação onde este item foi criado.`;
    }

    console.error(`[banking-sync] falha em ${rotulo}:`, e);
    await registrarResultado(admin, conexao.id, "error", msg, 0, null);
    return { conexao: rotulo, status: "error", mensagem: msg, importadas: 0 };
  }
}

async function registrarResultado(
  admin: DbClient,
  connectionId: string,
  status: "ok" | "error",
  mensagem: string,
  importadas: number,
  dataMaisRecente: string | null,
) {
  const patch: Record<string, unknown> = {
    last_sync_status: status,
    last_sync_message: mensagem,
    last_sync_imported: importadas,
  };
  // `last_synced_at` só avança quando deu certo: é o marcador de "até quando eu confio
  // neste extrato", e mexer nele num erro esconderia justamente a falha.
  if (status === "ok") {
    patch.last_synced_at = new Date().toISOString();
    if (dataMaisRecente) patch.last_transaction_date = dataMaisRecente;
  }
  await admin.from("bank_connections").update(patch).eq("id", connectionId);
}
