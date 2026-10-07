// Cobrança formal pela conversa (07/10/2026): criar, registrar contato, mudar situação e contato.
//
// "cria uma cobrança de 2.900 da OS-00112 com vencimento dia 20", "liguei para o Flávio, ele prometeu
// pagar sexta", "quem prometeu pagar esta semana e não pagou?". A tela é Cobranças
// (src/v2/pages/CollectionsV2.tsx e src/components/collections/*): CreateCollectionDialog,
// AddContactDialog (tipo + "prometeu pagar em"), EditContactDialog, o seletor de situação do
// CollectionDetailSheet e o cancelar — todos gravam direto em `collections` e `collection_contacts`
// (use-collections.ts). Aqui são os MESMOS campos, com uma diferença de propósito: a cobrança da OS
// nasce LIGADA à conta a receber em aberto (receivable_id). A tela lê a conta para sugerir valor e
// vencimento, mas não grava o vínculo — e sem ele o gatilho que marca a cobrança como paga quando a
// conta é paga (sync_collection_from_receivable) não tem o que marcar.
//
// Pagar NÃO é daqui: pagamento é register_payment na conta (a cobrança ligada fica paga sozinha).
import { blockTechnician, lerRetrato, type Role, type ToolCtx, type ToolDef } from "./registry.ts";
import { ehErro, escolherPorNome } from "./caixa.ts";
import { mensagemDoBanco } from "./lancamentos.ts";
import { alvoDoRetrato, brl, casaNome, ddmm, dataFuturaDita, ehUuid, mesmoValor, ordemDita, valorDito } from "./financeiro-comum.ts";

/** Quem mexe em cobrança: a RLS de collections deixa todos menos o vendedor externo; o técnico
 * fica fora pela regra do dono (09/08/2026: técnico não enxerga financeiro). */
const CARGOS_DA_COBRANCA: Role[] = ["admin", "financial", "seller"];

function semAcesso(ctx: ToolCtx): { error: string } | null {
  const b = blockTechnician(ctx);
  if (b) return b;
  if (!CARGOS_DA_COBRANCA.includes(ctx.userRole as Role)) return { error: "Cargo não autorizado para cobrança." };
  return null;
}

/** Situações abertas: as que ainda esperam pagamento. */
export const SITUACOES_ABERTAS = ["pending", "sent", "viewed", "overdue", "disputed"];

const ROTULO_DA_SITUACAO: Record<string, string> = {
  pending: "Pendente", sent: "Enviada", viewed: "Visualizada", paid: "Paga", overdue: "Vencida", disputed: "Em disputa", cancelled: "Cancelada",
};
/** Como a pessoa diz → a situação do banco (a mesma lista do seletor da tela, menos "paga"). */
const SITUACAO_DITA: Record<string, string> = {
  pendente: "pending", enviada: "sent", visualizada: "viewed", vencida: "overdue", em_disputa: "disputed", cancelada: "cancelled",
};

/** Os tipos de contato da tela (AddContactDialog), menos "pagamento confirmado" — pagar é register_payment. */
const TIPO_DE_CONTATO: Record<string, string> = {
  ligou_atendeu: "call_answered", ligou_nao_atendeu: "call_no_answer", whatsapp: "whatsapp_sent",
  anotacao: "manual_note", prometeu_pagar: "payment_promised",
};
const ROTULO_DO_CONTATO: Record<string, string> = {
  call_answered: "Ligou — atendeu", call_no_answer: "Ligou — não atendeu", whatsapp_sent: "WhatsApp enviado",
  manual_note: "Anotação", payment_promised: "Prometeu pagar",
};

const CAMPOS = "id, client_id, service_order_id, receivable_id, description, amount, due_date, status, contact_name, phone, contact_whatsapp, notes, " +
  "clients!collections_client_id_fkey(name, phone, whatsapp), service_orders!collections_service_order_id_fkey(service_order_number)";

export interface CobrancaLida {
  id: string; client_id: string | null; service_order_id: string | null; receivable_id: string | null; description: string | null;
  amount: number | string; due_date: string; status: string; contact_name: string | null; phone: string | null;
  contact_whatsapp: string | null; notes: string | null;
  clients: { name: string; phone: string | null; whatsapp: string | null } | null;
  service_orders: { service_order_number: string } | null;
}

/** "MP Motor Homes · OS-00112 · R$ 2.900,00 · vence 20/10 · Pendente" — numa linha. */
export function rotuloDaCobranca(c: CobrancaLida): string {
  return [
    c.clients?.name ?? c.contact_name ?? "cliente",
    c.service_orders?.service_order_number ?? c.description ?? "avulsa",
    brl.format(Number(c.amount)),
    `vence ${ddmm(c.due_date)}`,
    ROTULO_DA_SITUACAO[c.status] ?? c.status,
  ].join(" · ");
}

/**
 * A cobrança do pedido: pelo id (retrato da pendência ou cobranca_id), ou pelo cliente, OS e valor
 * ditos — só entre as abertas. Mais de uma → as opções numa linha (no resumo vira recusa).
 */
export async function acharCobranca(
  cliente: ToolCtx["sb"], args: Record<string, unknown>,
): Promise<{ cobranca: CobrancaLida } | { error: string }> {
  const id = alvoDoRetrato(lerRetrato(args), "cobranca_id") ?? (ehUuid(args.cobranca_id) ? String(args.cobranca_id).trim() : null);
  if (id) {
    const { data, error } = await cliente.from("collections").select(CAMPOS).eq("id", id).maybeSingle();
    if (error) return { error: `Não consegui ler a cobrança (${mensagemDoBanco(error)}).` };
    return data ? { cobranca: data as CobrancaLida } : { error: "Cobrança não encontrada." };
  }
  const quem = typeof args.cliente === "string" && args.cliente.trim() ? args.cliente.trim() : null;
  const valor = args.valor != null && args.valor !== "" ? valorDito(args.valor) : null;
  let osId: string | null = null;
  let osRotulo: string | null = null;
  if (args.os) {
    const o = await ordemDita(cliente, args.os);
    if (ehErro(o)) return o;
    osId = o.ordem.id;
    osRotulo = o.ordem.service_order_number;
  }
  if (!quem && !osId && valor == null) return { error: "Diga de qual cobrança: o cliente, a OS ou o valor." };
  let q = cliente.from("collections").select(CAMPOS).in("status", SITUACOES_ABERTAS);
  if (osId) q = q.eq("service_order_id", osId);
  const { data, error } = await q.order("due_date", { ascending: true }).limit(300);
  if (error) return { error: `Não consegui ler as cobranças (${mensagemDoBanco(error)}). Diga que a consulta falhou.` };
  const achadas = ((data ?? []) as CobrancaLida[]).filter((c) =>
    (!quem || casaNome(quem, c.clients?.name) || casaNome(quem, c.contact_name)) &&
    (valor == null || mesmoValor(c.amount, valor))
  );
  const dito = [quem, osRotulo, valor != null ? brl.format(valor) : null].filter(Boolean).join(", ");
  if (achadas.length === 1) return { cobranca: achadas[0] };
  if (achadas.length > 1) {
    return { error: `Há ${achadas.length} cobranças abertas com ${dito}: ${achadas.slice(0, 6).map((c) => `${rotuloDaCobranca(c)} [cobranca_id ${c.id}]`).join("; ")}. Pergunte qual.` };
  }
  return { error: `Nenhuma cobrança aberta com ${dito}. Para criar uma, use criar_cobranca.` };
}

// ── Criar ─────────────────────────────────────────────────────────────────────────────────────────

type Recebivel = { id: string; description: string | null; amount: number | string; balance_amount: number | string | null; due_date: string | null; status: string };
const saldoDe = (r: Recebivel) => Number(r.balance_amount ?? r.amount);

export interface NovaCobranca {
  linha: Record<string, unknown>;
  cliente: string;
  os: string | null;
  recebivel: Recebivel | null;
  contato: string;
}

/** Resolve a cobrança nova como a pessoa falou. Nada grava; devolve a pergunta quando falta algo. */
export async function resolverNovaCobranca(cliente: ToolCtx["sb"], args: Record<string, unknown>): Promise<NovaCobranca | { error: string }> {
  const valor = args.valor != null && args.valor !== "" ? valorDito(args.valor) : null;
  if (args.valor != null && args.valor !== "" && valor == null) return { error: `Não entendi o valor "${String(args.valor)}".` };
  const vencimento = args.vencimento ? dataFuturaDita(args.vencimento) : null;
  if (args.vencimento && !vencimento) return { error: `Não entendi o vencimento "${String(args.vencimento)}". Use dd/mm, 'dia 20' ou o dia da semana.` };

  let clienteId: string | null = null;
  let os: { id: string; numero: string } | null = null;
  let recebivel: Recebivel | null = null;
  let valorFinal = valor;
  let vencFinal = vencimento;
  let descricao: string | null = null;

  if (args.os) {
    const o = await ordemDita(cliente, args.os);
    if (ehErro(o)) return o;
    if (o.ordem.status === "cancelled") return { error: `A ${o.ordem.service_order_number} está cancelada: não se cobra.` };
    os = { id: o.ordem.id, numero: o.ordem.service_order_number };
    clienteId = o.ordem.client_id;
    const { data, error } = await cliente.from("receivables")
      .select("id, description, amount, balance_amount, due_date, status")
      .eq("service_order_id", o.ordem.id).neq("status", "cancelled").order("due_date", { ascending: true }).limit(50);
    if (error) return { error: `Não consegui ler as contas a receber da ${os.numero} (${mensagemDoBanco(error)}).` };
    const todas = (data ?? []) as Recebivel[];
    const abertas = todas.filter((r) => ["pending", "partially_paid", "overdue"].includes(r.status));
    if (ehUuid(args.receivable_id)) {
      recebivel = abertas.find((r) => r.id === String(args.receivable_id)) ?? null;
      if (!recebivel) return { error: `Essa conta a receber não está em aberto na ${os.numero}.` };
    } else if (abertas.length === 1) {
      recebivel = abertas[0];
    } else if (abertas.length > 1) {
      const doValor = valor != null ? abertas.filter((r) => mesmoValor(saldoDe(r), valor)) : [];
      if (doValor.length === 1) recebivel = doValor[0];
      else {
        return {
          error: `A ${os.numero} tem ${abertas.length} parcelas em aberto: ${abertas.map((r) =>
            `«${r.description ?? "parcela"}» saldo ${brl.format(saldoDe(r))} vence ${ddmm(r.due_date)} [receivable_id ${r.id}]`).join("; ")}. Pergunte qual.`,
        };
      }
    } else if (todas.length) {
      return { error: `As contas a receber da ${os.numero} estão pagas: não há o que cobrar.` };
    }
    if (recebivel) {
      const { data: ja, error: e2 } = await cliente.from("collections").select(CAMPOS)
        .eq("receivable_id", recebivel.id).in("status", SITUACOES_ABERTAS).limit(1);
      if (e2) return { error: `Não consegui conferir as cobranças da ${os.numero} (${mensagemDoBanco(e2)}).` };
      if ((ja ?? []).length) {
        return { error: `Já existe cobrança aberta para essa parcela: ${rotuloDaCobranca((ja as CobrancaLida[])[0])}. Para mudar, use alterar_cobranca.` };
      }
      valorFinal = valor ?? saldoDe(recebivel);
      vencFinal = vencimento ?? recebivel.due_date;
    } else {
      valorFinal = valor ?? (o.ordem.grand_total != null ? Number(o.ordem.grand_total) : null);
    }
  } else {
    descricao = typeof args.descricao === "string" && args.descricao.trim() ? args.descricao.trim() : null;
    if (!descricao) return { error: "Cobrança avulsa precisa da descrição (o que está sendo cobrado)." };
  }

  // Cliente: o da OS; na avulsa, o dito (nome igual ou cortado; dúvida é pergunta).
  type Cli = { id: string; name: string; phone: string | null; whatsapp: string | null };
  let cli: Cli | null = null;
  if (clienteId) {
    const { data, error } = await cliente.from("clients").select("id, name, phone, whatsapp").eq("id", clienteId).maybeSingle();
    if (error) return { error: `Não consegui ler o cliente (${mensagemDoBanco(error)}).` };
    cli = data as Cli | null;
  } else if (!os) {
    const dito = typeof args.cliente === "string" ? args.cliente.trim() : "";
    if (!dito) return { error: "De qual cliente é a cobrança?" };
    const primeira = dito.split(/\s+/).find((p) => p.length >= 2) ?? dito;
    const { data, error } = await cliente.from("clients").select("id, name, phone, whatsapp").ilike("name", `%${primeira}%`).limit(200);
    if (error) return { error: `Não consegui ler os clientes (${mensagemDoBanco(error)}).` };
    const lista = ((data ?? []) as Cli[]).map((c) => ({ ...c, nome: c.name }));
    const r = escolherPorNome(dito, lista);
    if ("ambiguo" in r) return { error: `Qual cliente: ${r.ambiguo.map((c) => c.name).join(" ou ")}?` };
    if ("nenhum" in r) return { error: `Não achei o cliente "${dito}". Diga o nome como está no cadastro.` };
    cli = r.achado;
  }
  if (!cli) return { error: "A OS não tem cliente: não dá para cobrar." };
  if (valorFinal == null || !(valorFinal > 0)) return { error: "Qual o valor da cobrança?" };
  if (!vencFinal) return { error: "Qual o vencimento da cobrança?" };

  // Contato: o do cadastro do cliente, como a tela preenche; o dito vence.
  const contatoNome = typeof args.contato_nome === "string" && args.contato_nome.trim() ? args.contato_nome.trim() : cli.name;
  const telefone = typeof args.telefone === "string" && args.telefone.trim() ? args.telefone.trim() : cli.phone;
  const whatsapp = typeof args.whatsapp === "string" && args.whatsapp.trim() ? args.whatsapp.trim() : (cli.whatsapp || cli.phone);

  // O modelo de mensagem padrão, como a tela escolhe ao abrir (o padrão, senão o primeiro).
  const { data: modelos, error: eMod } = await cliente.from("collection_templates").select("body, send_method, is_default, name")
    .order("is_default", { ascending: false }).order("name").limit(1);
  if (eMod) return { error: `Não consegui ler o modelo de mensagem de cobrança (${mensagemDoBanco(eMod)}).` };
  const modelo = ((modelos ?? []) as { body: string; send_method: string }[])[0] ?? null;

  return {
    linha: {
      client_id: cli.id,
      service_order_id: os?.id ?? null,
      receivable_id: recebivel?.id ?? null,
      description: descricao,
      standalone_amount: os ? null : valorFinal,
      amount: Math.round(valorFinal * 100) / 100,
      due_date: vencFinal,
      contact_name: contatoNome,
      phone: telefone || null,
      contact_whatsapp: whatsapp || null,
      send_method: modelo?.send_method ?? "text_link",
      message_template: modelo?.body ?? null,
      auto_rule_enabled: false,
      status: "pending",
    },
    cliente: cli.name,
    os: os?.numero ?? null,
    recebivel,
    contato: `${contatoNome}${whatsapp ? ` (WhatsApp ${whatsapp})` : " — ⚠️ sem WhatsApp"}`,
  };
}

// ── Resumos da confirmação ────────────────────────────────────────────────────────────────────────

export async function resumirCobranca(ctx: ToolCtx, nome: string, args: Record<string, unknown>): Promise<string | null> {
  if (nome === "criar_cobranca") {
    const r = await resolverNovaCobranca(ctx.admin, args);
    if (ehErro(r)) return `⚠️ ${r.error}`;
    return [
      `Criar cobrança: *${r.cliente}* · ${r.os ?? String(r.linha.description)} · *${brl.format(Number(r.linha.amount))}* · vence *${ddmm(String(r.linha.due_date))}*`,
      r.recebivel ? `- Ligada à conta a receber «${r.recebivel.description ?? "parcela"}» (saldo ${brl.format(saldoDe(r.recebivel))}): quando ela for paga, a cobrança fica paga sozinha.` : null,
      r.os && !r.recebivel ? "- A OS não tem conta a receber em aberto: a cobrança fica sem vínculo (marque como paga pela tela quando receber)." : null,
      `- Contato: ${r.contato}`,
      "- Não manda nada ao cliente: para enviar, peça o envio depois.",
    ].filter(Boolean).join("\n");
  }
  const r = await acharCobranca(ctx.admin, args);
  if (ehErro(r)) return `⚠️ ${r.error}`;
  const c = r.cobranca;
  if (nome === "registrar_contato_de_cobranca") {
    const tipo = TIPO_DE_CONTATO[String(args.tipo)];
    if (!tipo) return "⚠️ Tipo de contato: ligou_atendeu, ligou_nao_atendeu, whatsapp, anotacao ou prometeu_pagar.";
    const promessa = tipo === "payment_promised" ? dataFuturaDita(args.prometeu_em) : null;
    if (tipo === "payment_promised" && !promessa) return "⚠️ Prometeu pagar quando? Diga a data (sexta, dia 20, dd/mm).";
    return [
      `Registrar contato na cobrança: ${rotuloDaCobranca(c)}`,
      `- *${ROTULO_DO_CONTATO[tipo]}*${promessa ? ` para *${ddmm(promessa)}*` : ""}${args.observacao ? ` — ${String(args.observacao)}` : ""}`,
    ].join("\n");
  }
  if (nome === "alterar_cobranca") {
    const m = mudancasDaCobranca(args, c);
    if (ehErro(m)) return `⚠️ ${m.error}`;
    return [`Alterar a cobrança: ${rotuloDaCobranca(c)}`, ...m.linhas.map((l) => `- ${l}`)].join("\n");
  }
  return null;
}

/** O que alterar_cobranca vai gravar — o mesmo para a confirmação e para a execução. */
function mudancasDaCobranca(args: Record<string, unknown>, c: CobrancaLida): { patch: Record<string, unknown>; linhas: string[] } | { error: string } {
  const patch: Record<string, unknown> = {};
  const linhas: string[] = [];
  if (args.situacao != null && args.situacao !== "") {
    const s = SITUACAO_DITA[String(args.situacao)];
    if (!s) return { error: "Situação: pendente, enviada, visualizada, vencida, em_disputa ou cancelada. Paga não: registre o pagamento na conta da OS (register_payment)." };
    if (c.status === "paid") return { error: "Essa cobrança já está paga: a situação não muda por aqui." };
    patch.status = s;
    linhas.push(`Situação: ${ROTULO_DA_SITUACAO[c.status] ?? c.status} → *${ROTULO_DA_SITUACAO[s]}*`);
    const motivo = typeof args.motivo === "string" && args.motivo.trim() ? args.motivo.trim() : null;
    if (motivo) {
      const hoje = new Date(Date.now() - 3 * 3600_000).toISOString().slice(0, 10);
      patch.notes = [c.notes?.trim() || null, `[${ddmm(hoje)}] ${ROTULO_DA_SITUACAO[s]}: ${motivo}`].filter(Boolean).join("\n");
      linhas.push(`Motivo (vai nas observações): ${motivo}`);
    }
  }
  const campos: Array<[string, string, string]> = [["contato_nome", "contact_name", "Nome do contato"], ["telefone", "phone", "Telefone"], ["whatsapp", "contact_whatsapp", "WhatsApp"]];
  for (const [arg, coluna, rotulo] of campos) {
    const v = typeof args[arg] === "string" ? String(args[arg]).trim() : "";
    if (!v) continue;
    patch[coluna] = v;
    linhas.push(`${rotulo}: ${(c as unknown as Record<string, string | null>)[coluna] || "—"} → *${v}*`);
  }
  if (!linhas.length) return { error: "Diga o que mudar na cobrança: a situação ou o contato (nome, telefone, WhatsApp)." };
  return { patch, linhas };
}

/**
 * Depois de um lembrete enviado: o contato 'whatsapp_sent' no histórico da cobrança e a situação
 * 'sent' (paga continua paga) — o que a tela faz em useSendCollectionWhatsApp. Devolve um aviso
 * se não conseguiu registrar (a mensagem já foi; não se desfaz o envio por isso).
 */
export async function registrarEnvioDaCobranca(
  admin: ToolCtx["admin"], cobranca: { id: string; status?: string | null }, quem: string | null, nota: string,
): Promise<string | null> {
  const contato = await admin.from("collection_contacts").insert({
    collection_id: cobranca.id, contact_type: "whatsapp_sent", notes: nota, created_by: quem || null,
  });
  const situacao = await admin.from("collections").update({
    status: cobranca.status === "paid" ? "paid" : "sent", last_auto_sent_at: new Date().toISOString(),
  }).eq("id", cobranca.id);
  const erro = contato?.error ?? situacao?.error;
  return erro ? `A mensagem foi enviada, mas não consegui registrar o envio na cobrança (${mensagemDoBanco(erro)}).` : null;
}

// ── Ferramentas ───────────────────────────────────────────────────────────────────────────────────

const LOCALIZAR = {
  cobranca_id: { type: "string", description: "A cobrança, quando já se sabe (de list_pending_collections ou das opções)." },
  cliente: { type: "string", description: "Nome do cliente como a pessoa falou ('Flávio')." },
  os: { type: "string", description: "Número da OS da cobrança ('OS-00112')." },
  valor: { type: "number", description: "Valor da cobrança, se ajudar a achar." },
};

export const cobrancaTools: ToolDef[] = [
  {
    name: "criar_cobranca",
    description:
      "Cria uma COBRANÇA formal (a tela Cobranças): 'cria uma cobrança de 2.900 da OS-00112 com vencimento dia 20' (os, valor, " +
      "vencimento) ou avulsa ('cobrança de 500 do Flávio, conserto do guincho, vence sexta': cliente, descricao, valor, vencimento). " +
      "Da OS, ela nasce ligada à conta a receber em aberto (sem valor/vencimento, usa o saldo e o vencimento dela; com várias parcelas, " +
      "o sistema pergunta qual). O contato vem do cadastro do cliente. NÃO envia nada: para mandar, send_collection_reminder depois. " +
      "Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        os: { type: "string", description: "Número da OS ('OS-00112'). Sem OS = avulsa." },
        receivable_id: { type: "string", description: "Só quando a OS tem várias parcelas e a pessoa disse qual (das opções)." },
        cliente: { type: "string", description: "Avulsa: o cliente, pelo nome." },
        descricao: { type: "string", description: "Avulsa: o que está sendo cobrado." },
        valor: { type: "number" },
        vencimento: { type: "string", description: "Como foi dito: 'dia 20', 'sexta', dd/mm. Da OS, pode faltar (vale o da parcela)." },
        contato_nome: { type: "string", description: "Só se a pessoa disser outro contato que não o do cadastro." },
        telefone: { type: "string" },
        whatsapp: { type: "string" },
      },
    },
    risk: "medium",
    roles: CARGOS_DA_COBRANCA,
    preValidar(args) {
      if (!args?.os && !(args?.cliente && args?.descricao)) return { error: "Diga a OS da cobrança, ou o cliente e o que está sendo cobrado (avulsa)." };
      return null;
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const r = await resolverNovaCobranca(ctx.sb, args);
      if (ehErro(r)) return r;
      const { data, error } = await ctx.sb.from("collections")
        .insert({ ...r.linha, created_by: ctx.userId || null }).select("id").single();
      if (error) return { error: `Não consegui criar a cobrança: ${mensagemDoBanco(error)}` };
      return {
        ok: true, cobranca_id: (data as { id: string }).id,
        message: `Cobrança criada: ${r.cliente} · ${r.os ?? String(r.linha.description)} · ${brl.format(Number(r.linha.amount))} · vence ${ddmm(String(r.linha.due_date))}.` +
          (r.recebivel ? " Ligada à conta a receber da OS." : ""),
      };
    },
  },
  {
    name: "registrar_contato_de_cobranca",
    description:
      "Registra um CONTATO no histórico de uma cobrança (o 'Registrar contato' da tela): 'liguei para o Flávio, ele prometeu pagar " +
      "sexta' (tipo=prometeu_pagar, prometeu_em='sexta'), 'liguei e não atendeu', 'mandei mensagem', uma anotação. Ache a cobrança pelo " +
      "cliente/OS/valor ou pelo cobranca_id. Promessas que vencerem sem pagamento aparecem em list_pending_collections(promessas). " +
      "Não registra pagamento (isso é register_payment). Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        ...LOCALIZAR,
        tipo: { type: "string", enum: Object.keys(TIPO_DE_CONTATO) },
        prometeu_em: { type: "string", description: "Para prometeu_pagar: a data prometida como foi dita ('sexta', 'dia 20', dd/mm)." },
        observacao: { type: "string", description: "O que foi conversado." },
      },
      required: ["tipo"],
    },
    risk: "medium",
    roles: CARGOS_DA_COBRANCA,
    preValidar(args) {
      if (!TIPO_DE_CONTATO[String(args?.tipo)]) return { error: "Tipo de contato: ligou_atendeu, ligou_nao_atendeu, whatsapp, anotacao ou prometeu_pagar." };
      if (args.tipo === "prometeu_pagar" && !args.prometeu_em) return { error: "Prometeu pagar quando? Pergunte a data." };
      return null;
    },
    retratoDaPendencia: async (args, ctx) => {
      const r = await acharCobranca(ctx.admin, args);
      return ehErro(r) ? null : { cobranca_id: r.cobranca.id };
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const tipo = TIPO_DE_CONTATO[String(args.tipo)];
      if (!tipo) return { error: "Tipo de contato: ligou_atendeu, ligou_nao_atendeu, whatsapp, anotacao ou prometeu_pagar." };
      const promessa = tipo === "payment_promised" ? dataFuturaDita(args.prometeu_em) : null;
      if (tipo === "payment_promised" && !promessa) return { error: `Não entendi a data prometida "${String(args.prometeu_em ?? "")}". Use sexta, dia 20 ou dd/mm.` };
      const r = await acharCobranca(ctx.sb, args);
      if (ehErro(r)) return r;
      const { error } = await ctx.sb.from("collection_contacts").insert({
        collection_id: r.cobranca.id, contact_type: tipo,
        notes: typeof args.observacao === "string" && args.observacao.trim() ? args.observacao.trim() : null,
        promised_date: promessa, created_by: ctx.userId || null,
      });
      if (error) return { error: `Não consegui registrar o contato: ${mensagemDoBanco(error)}` };
      return {
        ok: true, cobranca_id: r.cobranca.id,
        message: `Registrado na cobrança ${rotuloDaCobranca(r.cobranca)}: ${ROTULO_DO_CONTATO[tipo]}${promessa ? ` para ${ddmm(promessa)}` : ""}.`,
      };
    },
  },
  {
    name: "alterar_cobranca",
    description:
      "Muda a SITUAÇÃO de uma cobrança (pendente, enviada, visualizada, vencida, em_disputa, cancelada — cancelar com motivo) ou o CONTATO " +
      "dela (contato_nome, telefone, whatsapp): 'cancela a cobrança do Flávio, ele já acertou comigo', 'o cliente contestou a cobrança', " +
      "'o WhatsApp de cobrança da MP é 47 9…'. Paga não se marca aqui: registre o pagamento na conta da OS (register_payment), e a " +
      "cobrança ligada fica paga sozinha. Pede confirmação.",
    input_schema: {
      type: "object",
      properties: {
        ...LOCALIZAR,
        situacao: { type: "string", enum: Object.keys(SITUACAO_DITA) },
        motivo: { type: "string", description: "Por que mudar a situação (vai nas observações da cobrança)." },
        contato_nome: { type: "string" },
        telefone: { type: "string" },
        whatsapp: { type: "string" },
      },
    },
    risk: "medium",
    roles: CARGOS_DA_COBRANCA,
    preValidar(args) {
      if (args?.situacao && !SITUACAO_DITA[String(args.situacao)]) return { error: "Situação: pendente, enviada, visualizada, vencida, em_disputa ou cancelada." };
      if (!args?.situacao && !args?.contato_nome && !args?.telefone && !args?.whatsapp) {
        return { error: "Diga o que mudar na cobrança: a situação ou o contato." };
      }
      return null;
    },
    retratoDaPendencia: async (args, ctx) => {
      const r = await acharCobranca(ctx.admin, args);
      return ehErro(r) ? null : { cobranca_id: r.cobranca.id };
    },
    async execute(args, ctx) {
      const b = semAcesso(ctx);
      if (b) return b;
      const r = await acharCobranca(ctx.sb, args);
      if (ehErro(r)) return r;
      const m = mudancasDaCobranca(args, r.cobranca);
      if (ehErro(m)) return m;
      const { error } = await ctx.sb.from("collections").update(m.patch).eq("id", r.cobranca.id);
      if (error) return { error: `Não consegui alterar a cobrança: ${mensagemDoBanco(error)}` };
      return { ok: true, cobranca_id: r.cobranca.id, message: `Cobrança ${rotuloDaCobranca(r.cobranca)}: ${m.linhas.join("; ").replace(/\*/g, "")}.` };
    },
  },
];
