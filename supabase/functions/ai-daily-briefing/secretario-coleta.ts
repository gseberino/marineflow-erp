// A coleta da manhã nova (secretário, Passo 2, 15/10/2026): as leituras do banco que viram candidatos.
// Spec: D:/IA-HBR/comprovantes-bancada/spec/spec-secretario-manha.md §3 (de onde vem cada família).
//
// Só roda com resumo_formato = 'sombra' ou 'novo' (com 'antigo' nada daqui é chamado). As consultas
// espelham as do resumo de hoje (index.ts), com as colunas a mais que a seleção precisa (ids, cliente,
// barco, OS). A lista de quem espera resposta é a MESMA do resumo de hoje (já sem "ok/obrigado" e sem
// quem disse que fechou com outra empresa) — chega pronta de quem chama.
//
// Erro na leitura de cobranças, orçamentos, OS ou do histórico LANÇA: sem eles a manhã nova sairia
// errada, e quem chama volta ao resumo de sempre. Agenda, promessas, vencimentos, falhas da noite e os
// dias de conversa são enriquecimento: erro = vazio, com aviso no log (só o código).

import { ultimoDiaDaValidade } from "../_shared/pdf/documento.ts";
import { diaBR, horaBR } from "../_shared/pdf/datas.ts";
import { somarDias } from "../_shared/secretario/base.ts";
import { contatoEncerrou, conversaEncerradaPeloContato, ULTIMAS_RECEBIDAS } from "../_shared/whatsapp/contato-encerrou.ts";
import type { ColetaDoSecretario, ConversaCrua, OrcamentoCru, OsCrua } from "./secretario-candidatos.ts";
import { adiadoPor, type PassagemDoHistorico } from "./secretario-selecao.ts";
import type { DadosDeHoje, NaRua } from "./secretario-texto.ts";

// deno-lint-ignore no-explicit-any
type Admin = any;

const FUSO_BR = "-03:00";

/** O que o resumo de hoje já leu e a coleta reaproveita. */
export interface DoResumoDeHoje {
  /** whatsapp_esperando_resposta já filtrada (index.ts:280-309) */
  // deno-lint-ignore no-explicit-any
  esperando: any[];
  /** as recebidas dos últimos 7 dias desses telefones (index.ts:292-295), ou null se a leitura falhou */
  recebidas: Array<{ phone_normalized: string; body: string | null; occurred_at: string }> | null;
  /** app_settings já lidas (quote_validity_days, para a validade do orçamento) */
  cfg: Record<string, string>;
}

function nomeDe(c: unknown): string | null {
  // deno-lint-ignore no-explicit-any
  const x = (Array.isArray(c) ? c[0] : c) as any;
  const n = x?.display_name || x?.name;
  return typeof n === "string" && n.trim() ? n : null;
}

/** O tipo da unidade (vessels.asset_type): vira o rótulo no *detalhe* ("Motorhome: Overland Vegini"; decisão 6, 22/10/2026). */
function tipoDe(v: unknown): string | null {
  // deno-lint-ignore no-explicit-any
  const x = (Array.isArray(v) ? v[0] : v) as any;
  const t = x?.asset_type;
  return typeof t === "string" && t.trim() ? t : null;
}

function falhou(evento: string, e: unknown): void {
  console.warn(JSON.stringify({ fn: "ai-daily-briefing", secretario: evento, codigo: String((e as { code?: unknown })?.code ?? (e as Error)?.name ?? "erro") }));
}

function ou<T>(r: { data: T | null; error: unknown }, nome: string): T {
  if (r.error) {
    const e = new Error(`secretário: leitura de ${nome} falhou`);
    (e as Error & { code?: unknown }).code = (r.error as { code?: unknown })?.code;
    throw e;
  }
  return (r.data ?? []) as T;
}

/**
 * Mensagem de SAÍDA que é o orçamento indo para alguém (o que o banco tinha em 15/10/2026): a legenda do PDF
 * encaminhado ("📄 Orçamento ORÇ-00116 — …"), o arquivo ("Orçamento ORÇ-00098.pdf",
 * "Orcamento_ORC-00104_….pdf") e o texto do envio pelo sistema ("*Orçamento ORÇ-00109* — …"). Só no começo
 * da mensagem: citar o número no meio de uma conversa não é mandar o orçamento.
 */
export const ENVIO_DE_ORCAMENTO = /^\s*(?:📄\s*)?\*?or[çc]amento[\s_]+\*?or[çc]-0*(\d{1,6})/iu;

/** últimos 8 dígitos (a mesma regra da whatsapp_esperando_resposta para achar o cliente pelo telefone) */
function final8(s: string | null | undefined): string | null {
  const d = String(s ?? "").replace(/\D/g, "");
  return d.length >= 8 ? d.slice(-8) : null;
}

export async function coletar(admin: Admin, p: {
  agora: Date;
  hoje: string;
  dono: { id: string; phone: string };
  modo: "sombra" | "novo";
  doResumo: DoResumoDeHoje;
}): Promise<{ coleta: ColetaDoSecretario; naRua: NaRua; deHoje: DadosDeHoje; historico: PassagemDoHistorico[] }> {
  const { agora, hoje, dono } = p;
  const amanha = somarDias(hoje, 1);
  const inicioDoDia = new Date(`${hoje}T00:00:00${FUSO_BR}`).toISOString();
  const fimDoDia = new Date(new Date(inicioDoDia).getTime() + 86_400_000).toISOString();
  const desdeAs20 = new Date(new Date(inicioDoDia).getTime() - 4 * 3_600_000).toISOString();
  const seteDias = new Date(agora.getTime() - 7 * 86_400_000).toISOString();

  // ── cobranças vencidas (as de index.ts:109-116, com cliente, OS e barco) ──
  const cobrancasLidas = ou(await admin.from("receivables")
    .select("id, client_id, description, due_date, amount, balance_amount, clients(name, display_name), service_orders!receivables_service_order_id_fkey(service_order_number, vessels(name, asset_type))")
    .in("status", ["pending", "partially_paid"]).eq("is_deposit", false).lt("due_date", hoje)
    .order("due_date", { ascending: true }).limit(500), "cobranças") as Array<Record<string, unknown>>;
  const cobrancas = cobrancasLidas.map((r) => {
    // deno-lint-ignore no-explicit-any
    const so = (Array.isArray(r.service_orders) ? r.service_orders[0] : r.service_orders) as any;
    return {
      id: String(r.id),
      client_id: (r.client_id as string | null) ?? null,
      cliente: nomeDe(r.clients),
      descricao: (r.description as string | null) ?? null,
      vencimento: String(r.due_date).slice(0, 10),
      saldo: Number(r.balance_amount ?? r.amount ?? 0),
      os_numero: so?.service_order_number ?? null,
      barco: nomeDe(so?.vessels),
      tipo_unidade: tipoDe(so?.vessels),
    };
  }).filter((c) => c.saldo > 0);
  const naRua: NaRua = { total: cobrancas.reduce((s, c) => s + c.saldo, 0), n: cobrancas.length };

  // ── orçamentos enviados/aguardando (index.ts:655-661) e rascunhos (novo: o "montado e não enviado") ──
  const orcs = ou(await admin.from("service_orders")
    .select("id, service_order_number, quote_status, grand_total, client_id, created_at, updated_at, quote_validity_days, quote_validity_date, clients(name, display_name), vessels(name, asset_type)")
    .eq("status", "draft").in("quote_status", ["sent", "awaiting_approval", "awaiting_deposit", "draft"])
    // do mais novo para o mais velho: se um dia passar do limite, o corte leva os rascunhos abandonados
    .order("updated_at", { ascending: false }).limit(300), "orçamentos") as Array<Record<string, unknown>>;
  const validade = (q: Record<string, unknown>) =>
    ultimoDiaDaValidade(q as { created_at?: string | null; quote_validity_date?: string | null; quote_validity_days?: unknown }, p.doResumo.cfg);
  const orcamentos: OrcamentoCru[] = orcs.map((q) => ({
    id: String(q.id),
    numero: String(q.service_order_number || "Orçamento"),
    quote_status: String(q.quote_status),
    valor: Number(q.grand_total || 0),
    client_id: (q.client_id as string | null) ?? null,
    cliente: nomeDe(q.clients),
    barco: nomeDe(q.vessels),
    tipo_unidade: tipoDe(q.vessels),
    criado_em: String(q.created_at),
    mexido_em: String(q.updated_at),
    // o mesmo "até" do PDF, da R19 e do resumo de hoje (index.ts:671); aguardando sinal e rascunho não vencem
    fim_validade: q.quote_status === "awaiting_deposit" || q.quote_status === "draft" ? null : validade(q),
    enviado_em: null,
    cliente_encerrou_em: null,
  }));

  // ── o "ainda é verdade" dos orçamentos (ensaio de 15/10/2026: dois fatos errados sem isto) ──
  // (a) rascunho que JÁ foi mandado ao cliente: o status continua "rascunho" quando o dono encaminha o PDF
  //     do celular ("📄 Orçamento ORÇ-00116 — …", 09/10) ou manda o link pelo sistema (ORÇ-00109). Mandado =
  //     "enviado" (com a data do envio); a manhã nunca diz "não enviado" de um orçamento que saiu.
  const rascunhos = orcamentos.filter((q) => q.quote_status === "draft");
  if (rascunhos.length) {
    const desde45 = new Date(agora.getTime() - 45 * 86_400_000).toISOString();
    const [pelaApi, pelaConversa, daEquipe] = await Promise.all([
      admin.from("audit_log").select("record_id, changed_at, new_value, reason")
        .eq("table_name", "service_orders").eq("action", "whatsapp_send_api").in("record_id", rascunhos.map((q) => q.id)).limit(1000),
      admin.from("whatsapp_messages").select("phone_normalized, body, occurred_at")
        .eq("direction", "outbound").gte("occurred_at", desde45).or("body.ilike.*ORÇ-*,body.ilike.*ORC-*").limit(2000),
      admin.from("app_users").select("phone_normalized").not("phone_normalized", "is", null).limit(200),
    ]);
    const envios = new Map<string, string>(); // id do orçamento → último envio
    const marcar = (id: string, em: string) => {
      if (!envios.has(id) || envios.get(id)! < em) envios.set(id, em);
    };
    for (const a of ou(pelaApi, "envios dos orçamentos") as Array<Record<string, unknown>>) {
      // deno-lint-ignore no-explicit-any
      const nv = (a.new_value ?? {}) as any;
      // só o que saiu de verdade, e não para o número de teste (whatsapp-send/index.ts:203-224)
      if (nv?.provider_result?.ok === true && !String(a.reason ?? "").includes("TEST MODE")) {
        marcar(String(a.record_id), new Date(String(a.changed_at)).toISOString());
      }
    }
    const equipe = new Set((ou(daEquipe, "telefones da equipe") as Array<Record<string, unknown>>).map((u) => String(u.phone_normalized)));
    const porNumero = new Map(rascunhos.map((q) => [Number(q.numero.replace(/\D/g, "")), q]));
    for (const m of ou(pelaConversa, "orçamentos mandados pelo WhatsApp") as Array<Record<string, unknown>>) {
      if (equipe.has(String(m.phone_normalized))) continue; // o PDF que o dono pediu para si não é envio ao cliente
      const n = ENVIO_DE_ORCAMENTO.exec(String(m.body ?? ""));
      const q = n ? porNumero.get(Number(n[1])) : undefined;
      const em = new Date(String(m.occurred_at)).toISOString();
      if (q && em >= new Date(q.criado_em).toISOString()) marcar(q.id, em);
    }
    for (const q of rascunhos) {
      const em = envios.get(q.id);
      if (!em) continue;
      q.enviado_em = em;
      q.quote_status = "sent";
      if (em > new Date(q.mexido_em).toISOString()) q.mexido_em = em;
      q.fim_validade = validade(orcs.find((o) => String(o.id) === q.id)!);
    }
  }
  // (b) cliente que escreveu "fechei com outra empresa"/"desisti" DEPOIS do orçamento (as 5 últimas recebidas
  //     em 30 dias, a mesma regra do "esperando resposta"): o orçamento não sobe com "recomendo um follow-up"
  //     (o ORÇ-00113 e o ORÇ-00103 do Miguel, 07/10). Só os de R$ 5 mil+ (os que podem subir).
  const clientesGrandes = [...new Set(orcamentos.filter((q) => q.valor >= 5000 && q.client_id).map((q) => q.client_id!))];
  if (clientesGrandes.length) {
    // a conversa é do cliente pelo vínculo da mensagem OU pelo telefone do cadastro (8 últimos dígitos, a regra
    // da whatsapp_esperando_resposta): em 15/10 só as mensagens do Miguel tinham client_id preenchido
    // (os telefones são reforço: se a leitura falhar, vale só o vínculo da mensagem)
    const clienteDoFinal = new Map<string, string>();
    try {
      const telefones = ou(await admin.from("clients").select("id, phone, whatsapp").in("id", clientesGrandes).limit(500),
        "telefones dos clientes") as Array<Record<string, unknown>>;
      for (const c of telefones) {
        for (const f of [final8(c.whatsapp as string), final8(c.phone as string)]) if (f && !clienteDoFinal.has(f)) clienteDoFinal.set(f, String(c.id));
      }
    } catch (e) {
      falhou("telefones_dos_clientes", e);
    }
    const filtros = [`client_id.in.(${clientesGrandes.join(",")})`, ...[...clienteDoFinal.keys()].map((f) => `phone_normalized.like.*${f}`)];
    const recebidas = ou(await admin.from("whatsapp_messages").select("client_id, phone_normalized, body, occurred_at")
      .eq("direction", "inbound").or(filtros.join(",")).gte("occurred_at", new Date(agora.getTime() - 30 * 86_400_000).toISOString())
      .lt("occurred_at", agora.toISOString())
      .order("occurred_at", { ascending: false }).limit(2000), "recebidas dos clientes") as Array<Record<string, unknown>>;
    const porCliente = new Map<string, Array<{ body: string | null; em: string }>>();
    for (const m of recebidas) {
      const doVinculo = m.client_id && clientesGrandes.includes(String(m.client_id)) ? String(m.client_id) : null;
      const cliente = doVinculo ?? clienteDoFinal.get(final8(m.phone_normalized as string) ?? "");
      if (!cliente) continue;
      const l = porCliente.get(cliente) ?? [];
      l.push({ body: (m.body as string | null) ?? null, em: new Date(String(m.occurred_at)).toISOString() });
      porCliente.set(cliente, l);
    }
    for (const q of orcamentos) {
      const l = (porCliente.get(String(q.client_id)) ?? []).sort((a, b) => b.em.localeCompare(a.em)).slice(0, ULTIMAS_RECEBIDAS);
      if (!conversaEncerradaPeloContato(l.map((x) => x.body))) continue;
      const quando = l.find((x) => contatoEncerrou(x.body))!.em;
      if (quando > new Date(q.criado_em).toISOString()) q.cliente_encerrou_em = quando;
    }
  }

  // ── OS: ativas (index.ts:133-139, sem o corte de 10 dias) e concluídas nos últimos 60 dias (a "concluída
  //    sem cobrança" é coisa recente; sem o corte, a lista de ids do .in() abaixo cresceria sem fim) ──
  const colunasDaOs = "id, service_order_number, status, grand_total, client_id, updated_at, scheduled_start_at, clients(name, display_name), vessels(name, asset_type)";
  const [ativasLidas, concluidasLidas] = await Promise.all([
    admin.from("service_orders").select(colunasDaOs)
      .in("status", ["approved", "scheduled", "in_progress", "awaiting_parts", "open"])
      .order("updated_at", { ascending: false }).limit(200),
    admin.from("service_orders").select(colunasDaOs)
      .eq("status", "completed").gte("updated_at", new Date(agora.getTime() - 60 * 86_400_000).toISOString())
      .order("updated_at", { ascending: false }).limit(100),
  ]);
  const osLidas = [
    ...ou(ativasLidas, "OS ativas") as Array<Record<string, unknown>>,
    ...ou(concluidasLidas, "OS concluídas") as Array<Record<string, unknown>>,
  ];
  const idsDasOs = osLidas.map((o) => String(o.id));
  const recDasOs = idsDasOs.length
    ? ou(await admin.from("receivables").select("service_order_id, status, is_deposit, amount").in("service_order_id", idsDasOs).limit(3000),
      "recebíveis das OS") as Array<Record<string, unknown>>
    : [];
  // a tarefa de compra da R16 (task-automations/rules.ts:644-690): "Comprar N itens — OS-…"
  const compras = ou(await admin.from("agenda_tasks").select("title, created_at, related_entity_id")
    .like("automation_key", "r16:so:%").in("status", ["pending", "in_progress"]).limit(200), "tarefas de compra") as Array<Record<string, unknown>>;
  const compraPorOs = new Map<string, { titulo: string; criada_em: string }>();
  for (const t of compras) {
    if (t.related_entity_id) compraPorOs.set(String(t.related_entity_id), { titulo: String(t.title), criada_em: String(t.created_at) });
  }
  const oss: OsCrua[] = osLidas.map((o) => {
    const recs = recDasOs.filter((r) => r.service_order_id === o.id);
    return {
      id: String(o.id),
      numero: String(o.service_order_number),
      status: String(o.status),
      valor: Number(o.grand_total || 0),
      client_id: (o.client_id as string | null) ?? null,
      cliente: nomeDe(o.clients),
      barco: nomeDe(o.vessels),
      tipo_unidade: tipoDe(o.vessels),
      mexido_em: String(o.updated_at),
      agendada_em: (o.scheduled_start_at as string | null) ?? null,
      sinal_pago: recs.filter((r) => r.is_deposit === true && r.status === "paid").reduce((s, r) => s + Number(r.amount || 0), 0),
      tarefa_compra: compraPorOs.get(String(o.id)) ?? null,
      cobrancas_vivas: recs.filter((r) => r.status !== "cancelled").length,
    };
  });

  // ── quem espera resposta (a lista do resumo de hoje) + cliente pelo telefone + dias de conversa ──
  const esperando = p.doResumo.esperando;
  const fones = esperando.map((w) => String(w.phone ?? "")).filter(Boolean);
  const clientePorFinal = new Map<string, string>();
  if (fones.length) {
    try {
      const cls = ou(await admin.from("clients").select("id, phone, whatsapp").eq("active", true).limit(3000), "clientes") as Array<Record<string, unknown>>;
      for (const c of cls) {
        for (const f of [final8(c.whatsapp as string), final8(c.phone as string)]) if (f && !clientePorFinal.has(f)) clientePorFinal.set(f, String(c.id));
      }
    } catch (e) {
      falhou("clientes_pelo_telefone", e);
    }
  }
  const diasSeus = new Map<string, Set<string>>();
  if (fones.length) {
    try {
      const env = ou(await admin.from("whatsapp_messages").select("phone_normalized, occurred_at")
        .eq("direction", "outbound").in("phone_normalized", fones).gte("occurred_at", seteDias).limit(3000), "enviadas") as Array<Record<string, unknown>>;
      for (const m of env) {
        const s = diasSeus.get(String(m.phone_normalized)) ?? new Set<string>();
        s.add(diaBR(new Date(String(m.occurred_at))));
        diasSeus.set(String(m.phone_normalized), s);
      }
    } catch (e) {
      falhou("dias_de_conversa", e);
    }
  }
  const recebidasPorFone = new Map<string, Array<{ body: string | null; em: string }>>();
  for (const m of p.doResumo.recebidas ?? []) {
    const l = recebidasPorFone.get(m.phone_normalized) ?? [];
    l.push({ body: m.body, em: m.occurred_at });
    recebidasPorFone.set(m.phone_normalized, l);
  }
  const conversas: ConversaCrua[] = esperando.map((w) => {
    const phone = String(w.phone);
    const categoria = w.categoria === "cliente" || w.categoria === "fornecedor" ? w.categoria : "contato";
    const fin = final8(phone);
    return {
      phone,
      contato: String(w.contato ?? phone),
      categoria,
      last_inbound_at: String(w.last_inbound_at),
      last_body: (w.last_body as string | null) ?? null,
      last_outbound_at: (w.last_outbound_at as string | null) ?? null,
      client_id: fin ? clientePorFinal.get(fin) ?? null : null,
      recebidas: recebidasPorFone.get(phone) ?? (w.last_body ? [{ body: w.last_body, em: String(w.last_inbound_at) }] : []),
      diasComMensagemSua: diasSeus.get(phone)?.size ?? 0,
    };
  });

  // ── o histórico do mesmo modo (30 dias, sem hoje) ──
  // (16/10/2026) + o histórico do item: o "como" do adiamento ('semana' da revisão volta antes com fato novo — F7)
  const historico = (ou(await admin.from("resumo_itens")
    .select("referencia, dia, posicao, fato, acao, acao_em, adiado_ate, voltou_em, criado_em, historico")
    .eq("phone_normalized", dono.phone).eq("modo", p.modo)
    .gte("dia", somarDias(hoje, -30)).lt("dia", hoje).limit(5000), "histórico do resumo") as Array<PassagemDoHistorico & { historico?: unknown }>)
    .map(({ historico: h, ...passagem }) => ({ ...passagem, adiado_por: passagem.acao === "adiado" ? adiadoPor(h) : null }));

  // ── a linha "Hoje" (enriquecimento: erro = vazio) ──
  const deHoje: DadosDeHoje = { agenda: [], promessas: [], vencimentos: [], falhasDeEnvio: 0, errosDaNoite: 0 };
  try {
    // duas leituras (com hora hoje; com prazo hoje) em vez de um .or() com datas no filtro
    const [comHoraHoje, comPrazoHoje, agendadas] = await Promise.all([
      admin.from("agenda_tasks").select("id, title, scheduled_start_at, due_at, source")
        .eq("assignee_user_id", dono.id).in("status", ["pending", "in_progress"])
        .gte("scheduled_start_at", inicioDoDia).lt("scheduled_start_at", fimDoDia).limit(50),
      admin.from("agenda_tasks").select("id, title, scheduled_start_at, due_at, source")
        .eq("assignee_user_id", dono.id).in("status", ["pending", "in_progress"])
        .gte("due_at", inicioDoDia).lt("due_at", fimDoDia).limit(50),
      admin.from("service_orders").select("service_order_number, scheduled_start_at, vessels(name)")
        .gte("scheduled_start_at", inicioDoDia).lt("scheduled_start_at", fimDoDia).neq("status", "cancelled").limit(20),
    ]);
    const tarefas = new Map<string, Record<string, unknown>>();
    for (const t of [...ou(comHoraHoje, "agenda") as Array<Record<string, unknown>>, ...ou(comPrazoHoje, "agenda") as Array<Record<string, unknown>>]) {
      tarefas.set(String(t.id), t);
    }
    const itens: Array<{ hora: string | null; titulo: string; ord: string }> = [];
    const ehHoje = (iso: unknown) => {
      const ms = typeof iso === "string" ? Date.parse(iso) : NaN;
      return !Number.isNaN(ms) && ms >= Date.parse(inicioDoDia) && ms < Date.parse(fimDoDia);
    };
    for (const t of tarefas.values()) {
      const comHora = ehHoje(t.scheduled_start_at) ? String(t.scheduled_start_at) : null;
      // a tarefa da automação com prazo hoje (a R16 recriada, a cobrança) não é "agenda": já vira item
      if (!comHora && t.source === "automation") continue;
      itens.push({ hora: comHora ? horaBR(new Date(comHora)) : null, titulo: String(t.title), ord: comHora ?? String(t.due_at ?? "") });
    }
    for (const o of ou(agendadas, "OS agendadas") as Array<Record<string, unknown>>) {
      const barco = nomeDe(o.vessels);
      itens.push({ hora: horaBR(new Date(String(o.scheduled_start_at))), titulo: `${o.service_order_number}${barco ? ` (${barco})` : ""}`, ord: String(o.scheduled_start_at) });
    }
    deHoje.agenda = itens.sort((a, b) => a.ord.localeCompare(b.ord)).map(({ hora, titulo }) => ({ hora, titulo }));
  } catch (e) {
    falhou("agenda", e);
  }
  try {
    const acomp = ou(await admin.from("whatsapp_acompanhamentos").select("contato, phone_normalized, promessa, lembrar_em")
      .eq("status", "ativo").eq("modo", "promessa").lt("lembrar_em", fimDoDia).limit(20), "promessas") as Array<Record<string, unknown>>;
    deHoje.promessas = acomp.map((a) => ({ contato: String(a.contato || a.phone_normalized), promessa: (a.promessa as string | null) ?? null }));
  } catch (e) {
    falhou("promessas", e);
  }
  try {
    const [rec, pag] = await Promise.all([
      admin.from("receivables").select("balance_amount, amount, due_date, clients(name, display_name)")
        .in("status", ["pending", "partially_paid"]).eq("is_deposit", false).gte("due_date", hoje).lte("due_date", amanha).limit(50),
      admin.from("payables").select("balance_amount, amount, due_date, supplier_name, description")
        .in("status", ["pending", "partially_paid", "overdue"]).gte("due_date", hoje).lte("due_date", amanha).limit(50),
    ]);
    // tudo ou nada: a linha "Hoje" não sai com o a receber e sem o a pagar
    const aReceber = ou(rec, "a receber") as Array<Record<string, unknown>>;
    const aPagar = ou(pag, "a pagar") as Array<Record<string, unknown>>;
    deHoje.vencimentos = [
      ...aReceber.map((r) => ({ lado: "receber" as const, quando: String(r.due_date).slice(0, 10) === hoje ? "hoje" as const : "amanha" as const,
        valor: Number(r.balance_amount ?? r.amount ?? 0), nome: nomeDe(r.clients) ?? "sem cliente" })),
      ...aPagar.map((r) => ({ lado: "pagar" as const, quando: String(r.due_date).slice(0, 10) === hoje ? "hoje" as const : "amanha" as const,
        valor: Number(r.balance_amount ?? r.amount ?? 0), nome: String(r.supplier_name || r.description || "conta") })),
    ].filter((v) => v.valor > 0);
  } catch (e) {
    falhou("vencimentos", e);
  }
  try {
    const [fila, erros] = await Promise.all([
      admin.from("whatsapp_send_queue").select("id", { count: "exact", head: true }).eq("status", "failed").gte("updated_at", desdeAs20),
      admin.from("app_error_logs").select("id", { count: "exact", head: true })
        .eq("source", "edge").eq("level", "error").is("resolved_at", null).gte("last_seen_at", desdeAs20),
    ]);
    if (fila.error) throw fila.error;
    if (erros.error) throw erros.error;
    deHoje.falhasDeEnvio = fila.count ?? 0;
    deHoje.errosDaNoite = erros.count ?? 0;
  } catch (e) {
    falhou("falhas_da_noite", e);
  }

  return { coleta: { cobrancas, conversas, orcamentos, oss }, naRua, deHoje, historico };
}
