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
  mapTransaction, accountSourceType, motivoDeCreditoEmCartao,
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
  /**
   * `list_items` não sincroniza nada: só mostra o que as credenciais enxergam.
   * `backfill` rebusca o período e ATUALIZA o que já está gravado, em vez de só inserir o
   * que falta — é o único jeito de preencher campos que passaram a ser lidos depois.
   */
  action?: "sync" | "list_items" | "backfill";
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
      const { itens, erro: erroLista } = await listItems(apiKey);
      const { data: jaCadastrados } = await admin
        .from("bank_connections")
        .select("external_id");
      const cadastrados = new Set((jaCadastrados || []).map((c: any) => c.external_id));
      return jr({
        ok: true,
        itens: itens.map((i) => ({ ...i, ja_cadastrado: cadastrados.has(i.id) })),
        erro_listagem: erroLista,
        // Prefixo do CLIENT_ID em uso, para comparar com a aplicação aberta no painel do
        // provedor. É identificador, não segredo — e sem ele não há como saber a QUAL
        // aplicação o sistema está conectado quando a lista volta vazia.
        client_id_prefixo: clientId.slice(0, 8),
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
      const resultado = body.action === "backfill"
        ? await preencherIdentificacao(admin, apiKey, conexao)
        : await sincronizarConexao(admin, apiKey, conexao, !!body.full);
      resultados.push(resultado);
    }

    if (body.action === "backfill") {
      const atualizadas = resultados.reduce((s, r) => s + Number(r.atualizadas ?? 0), 0);
      const jaCompletas = resultados.reduce((s, r) => s + Number(r.ja_completas ?? 0), 0);
      const comErro = resultados.filter((r) => r.status === "error").length;

      // "0 preenchidas" é ambíguo: pode ser que já estivesse tudo certo, ou que nada tenha
      // funcionado. Quem lê precisa saber qual dos dois, senão clica de novo achando que
      // falhou — ou desiste achando que o recurso não serve.
      const message = comErro > 0
        ? `${atualizadas} preenchida(s) · ${comErro} conexão(ões) com erro`
        : atualizadas > 0
          ? `${atualizadas} transação(ões) ganharam identificação nova`
          : jaCompletas > 0
            ? `Nada a preencher: as ${jaCompletas} transações verificadas já tinham tudo que o banco informa`
            : "O provedor não devolveu identificação para nenhuma transação deste período";

      return jr({ ok: comErro === 0, message, atualizadas, ja_completas: jaCompletas, resultados });
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

/**
 * Rebusca o extrato e preenche os campos de identificação no que JÁ está gravado.
 *
 * A sincronização normal só INSERE: o dedupe por `bank_ref_id` barra tudo que já existe,
 * então transação importada antes de um campo passar a ser lido fica sem ele para sempre.
 * Foi o que aconteceu com banco, agência, conta, meio de pagamento e estabelecimento —
 * 1.971 lançamentos vazios porque a leitura só começou depois deles.
 *
 * Só toca em coluna que está NULA. Nada que o gestor tenha corrigido à mão é sobrescrito,
 * e rodar duas vezes não desfaz nada.
 */
/**
 * Colunas que o backfill pode preencher — todas de IDENTIFICAÇÃO.
 *
 * Valor, data e sentido ficam fora de propósito: corrigi-los aqui reescreveria em silêncio
 * lançamento que o gestor já conferiu. A lista virou constante porque ela cresce a cada
 * campo novo que passamos a ler, e o `if` por campo já tinha deixado quatro de fora.
 */
const PREENCHIVEIS = [
  "counterparty_bank", "counterparty_branch", "counterparty_account",
  "payment_method", "payment_reason", "merchant_name", "merchant_document",
  "installment_label", "counterparty_name", "counterparty_document",
  "payee_mcc", "card_last_digits", "bill_id", "provider_category",
  "merchant_category", "tx_status", "authentication_code",
  "receiver_reference_id", "provider_account_id", "pix_end_to_end_id",
] as const;

/**
 * Confere o saldo do provedor contra o que as transações explicam.
 *
 * É o controle que os ERPs chamam de *proof of completeness*, e ele responde a pergunta
 * que nenhuma outra verificação responde: **falta alguma transação?** Um lançamento
 * perdido na sincronização não deixa buraco visível — ele simplesmente não existe para o
 * sistema, e o sistema não tem como saber o que não recebeu. O saldo é a única testemunha
 * externa: se o banco diz que sobrou X e a soma das transações explica Y, a diferença é
 * exatamente o que falta.
 *
 * Grava sempre, feche ou não. A série de conferências é o que mostra se a integração
 * degradou — uma que fecha hoje e não fecha amanhã diz mais que qualquer alerta isolado.
 */
async function conferirSaldo(
  admin: DbClient,
  conexaoId: string,
  conta: any,
  transacoes: any[],
): Promise<void> {
  try {
    const saldoProvedor = Number(conta?.balance);
    if (!Number.isFinite(saldoProvedor)) return;

    // A transação mais recente traz o saldo APÓS ela — é o ponto de comparação honesto.
    const comSaldo = transacoes
      .filter((t) => Number.isFinite(Number(t?.balance)))
      .sort((a, b) => String(b.date).localeCompare(String(a.date)))[0];
    if (!comSaldo) return;

    const saldoCalculado = Number(comSaldo.balance);
    const diferenca = Number((saldoProvedor - saldoCalculado).toFixed(2));
    // Um centavo de arredondamento não é falta de transação.
    const fecha = Math.abs(diferenca) < 0.05;

    await admin.from("bank_balance_checks").insert({
      bank_connection_id: conexaoId,
      saldo_do_provedor: saldoProvedor,
      saldo_calculado: saldoCalculado,
      diferenca,
      transacoes_no_periodo: transacoes.length,
      fecha,
      observacao: fecha
        ? null
        : "Saldo da conta não bate com o saldo após a última transação — pode faltar lançamento na janela sincronizada",
    });
  } catch { /* conferência é diagnóstico: nunca derruba a sincronização */ }
}

/**
 * Guarda o payload cru de algumas transações, para descobrir onde está o EndToEndId.
 *
 * O motor casa transação com cobrança pelo EndToEndId — único no SPI, prova irrefutável —
 * e o campo está vazio em 2.141 linhas, o que deixa INERTE a camada de certeza da
 * conciliação. Sem ver o payload real não dá para saber se o provedor manda em outro
 * campo, se aquela instituição não manda, ou se o método não vem escrito "PIX". Quarenta
 * amostras respondem isso; adivinhar, não.
 *
 * Falha em silêncio de propósito: isto é diagnóstico, não pode derrubar a sincronização.
 */
async function guardarAmostra(admin: DbClient, tx: any, origem: string): Promise<void> {
  try {
    const temSinalDePix = !!tx?.paymentData
      && /PIX/i.test(JSON.stringify(tx.paymentData ?? {}) + String(tx.description ?? ""));
    if (!temSinalDePix) return;

    const { count } = await admin
      .from("pluggy_amostra_payload")
      .select("id", { count: "exact", head: true });
    if ((count ?? 0) >= 40) return;

    await admin.from("pluggy_amostra_payload")
      .upsert({ bank_ref_id: tx.id, source_type: origem, payload: tx }, { onConflict: "bank_ref_id" });
  } catch { /* diagnóstico nunca derruba a sincronização */ }
}

async function preencherIdentificacao(
  admin: DbClient,
  apiKey: string,
  conexao: any,
): Promise<Record<string, unknown>> {
  const rotulo = conexao.label as string;
  try {
    const contas = await fetchAccounts(apiKey, conexao.external_id);
    let atualizadas = 0;
    let semNovidade = 0;

    for (const conta of contas) {
      const origem = accountSourceType(conta);
      const transacoes = await fetchTransactions(apiKey, conta.id, diasAtras(JANELA_INICIAL_DIAS));

      for (const t of transacoes) {
        const linha = mapTransaction(t, origem);
        await guardarAmostra(admin, t, origem);

        // Só o que é identificação. Valor, data e sentido ficam de fora de propósito:
        // corrigi-los aqui reescreveria silenciosamente lançamento já conferido.
        const campos: Record<string, unknown> = {};
        for (const k of PREENCHIVEIS) {
          const v = (linha as any)[k];
          if (v !== null && v !== undefined && v !== "") campos[k] = v;
        }

        if (Object.keys(campos).length === 0) { semNovidade++; continue; }

        // `is null` em cada coluna seria uma consulta por campo; mais simples e seguro é
        // ler o que existe e mandar só o que está vazio.
        const { data: atual } = await admin
          .from("bank_transactions")
          .select(`id, ${PREENCHIVEIS.join(", ")}`)
          .eq("bank_ref_id", linha.bank_ref_id)
          .maybeSingle();
        if (!atual) continue;

        const paraGravar: Record<string, unknown> = {};
        for (const [k, v] of Object.entries(campos)) {
          if ((atual as any)[k] == null) paraGravar[k] = v;
        }
        if (Object.keys(paraGravar).length === 0) { semNovidade++; continue; }

        const { error } = await admin
          .from("bank_transactions").update(paraGravar).eq("id", (atual as any).id);
        if (!error) atualizadas++;
      }
    }

    return {
      conexao: rotulo,
      status: "ok",
      atualizadas,
      ja_completas: semNovidade,
      mensagem: atualizadas > 0
        ? `${atualizadas} lançamento(s) ganharam banco, conta ou meio de pagamento`
        : "Nada a preencher — o provedor não devolveu identificação nova",
    };
  } catch (e) {
    return {
      conexao: rotulo,
      status: "error",
      atualizadas: 0,
      mensagem: String((e as Error)?.message ?? e),
    };
  }
}

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

    // Saúde da conexão, gravada a cada sincronização: consentimento de Open Finance vence
    // em 12 meses e o item cai por MFA ou troca de senha. Sem isso a conexão morre calada
    // e o gestor descobre no fechamento, com o período já perdido.
    await admin.from("bank_connections").update({
      provider_status: statusItem || null,
      consent_expires_at: (item as any)?.consentExpiresAt
        ?? (item as any)?.consent?.expiresAt ?? null,
    }).eq("id", conexao.id);

    for (const conta of contas) {
      const origem = accountSourceType(conta);
      const transacoes = await fetchTransactions(apiKey, conta.id, desde);
      await conferirSaldo(admin, conexao.id, conta, transacoes);
      if (transacoes.length === 0) continue;

      const linhas = transacoes.map((t) => {
        const linha = mapTransaction(t, origem);
        // Crédito em fatura de cartão já entra resolvido: nunca é receita e só polui a
        // fila. Ver `motivoDeCreditoEmCartao` para o porquê de ser uma regra estrutural,
        // e não uma lista de exceções.
        const ignorar = motivoDeCreditoEmCartao(linha.source_type, linha.transaction_type, linha.description);
        return {
          ...linha,
          bank_connection_id: conexao.id,
          reconciled: !!ignorar,
          dismissed_reason: ignorar,
          // Sair da fila na importação também deixa rastro: sem tipo, essas linhas não
          // apareceriam no livro das ignoradas nem teriam como voltar.
          dismissed_kind: ignorar ? "mecanica_cartao" : null,
          dismissed_at: ignorar ? new Date().toISOString() : null,
        };
      });

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
      const { itens: visiveis, erro: erroVisiveis } = await listItems(apiKey);
      msg = erroVisiveis
        ? `Nao consegui listar as conexoes para comparar (${erroVisiveis}). O Item ID informado nao foi encontrado nesta aplicacao.`
        : visiveis.length === 0
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
