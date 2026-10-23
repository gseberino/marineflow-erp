// A coleta da manhã nova com um PostgREST de mentira (os filtros rodam de verdade sobre linhas em memória):
// o que cada leitura traz, como vira candidato cru, e o que acontece quando uma leitura falha.
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { candidatosDoDia } from "./secretario-candidatos.ts";
import { coletar } from "./secretario-coleta.ts";
import { CORTE_DA_AGENDA_DE_HOJE } from "./secretario-texto.ts";

type Linha = Record<string, unknown>;
const AGORA = new Date("2026-10-15T10:30:00Z"); // 07:30 de Brasília
const HOJE = "2026-10-15";
const DONO = { id: "u-dono", phone: "5547999990000" };

function valor(l: Linha, c: string): unknown {
  return l[c];
}

/** filtros do supabase-js sobre linhas em memória; `falhar` = tabelas que devolvem erro */
function falsoAdmin(tabelas: Record<string, Linha[]>, falhar: string[] = [], selects: string[] = []) {
  return {
    from(tabela: string) {
      let linhas = [...(tabelas[tabela] ?? [])];
      let soContagem = false;
      const q = {
        select: (c?: string, o?: { head?: boolean }) => (selects.push(`${tabela}: ${c ?? ""}`), (soContagem = !!o?.head), q),
        eq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => valor(l, c) === v)), q),
        neq: (c: string, v: unknown) => ((linhas = linhas.filter((l) => valor(l, c) !== v)), q),
        in: (c: string, vs: unknown[]) => ((linhas = linhas.filter((l) => vs.includes(valor(l, c)))), q),
        is: (c: string, v: unknown) => ((linhas = linhas.filter((l) => (valor(l, c) ?? null) === v)), q),
        lt: (c: string, v: string) => ((linhas = linhas.filter((l) => valor(l, c) != null && Date.parse(String(valor(l, c))) < Date.parse(v))), q),
        lte: (c: string, v: string) => ((linhas = linhas.filter((l) => valor(l, c) != null && Date.parse(String(valor(l, c))) <= Date.parse(v))), q),
        gte: (c: string, v: string) => ((linhas = linhas.filter((l) => valor(l, c) != null && Date.parse(String(valor(l, c))) >= Date.parse(v))), q),
        like: (c: string, p: string) => {
          const re = new RegExp(`^${p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/%/g, ".*")}$`);
          linhas = linhas.filter((l) => re.test(String(valor(l, c) ?? "")));
          return q;
        },
        // só o que a coleta usa: "col.ilike.*x*,col.ilike.*y*"
        // "col.ilike.*x*", "col.like.*x" e "col.in.(a,b)", separados por vírgula (o que a coleta usa)
        // (23/10/2026) + "col.gt.x", "col.gte.x", "col.is.null" e "and(a,b)": o filtroQueCruza da agenda do dia
        or: (expr: string) => {
          const regra = (s: string): (l: Linha) => boolean => {
            const e = /^and\((.*)\)$/.exec(s);
            if (e) {
              const todas = e[1].split(",").map(regra);
              return (l) => todas.every((r) => r(l));
            }
            const em = /^(\w+)\.in\.\((.*)\)$/.exec(s);
            if (em) return (l) => em[2].split(",").includes(String(valor(l, em[1])));
            const nulo = /^(\w+)\.is\.null$/.exec(s);
            if (nulo) return (l) => (valor(l, nulo[1]) ?? null) === null;
            const ge = /^(\w+)\.gte\.(.*)$/.exec(s);
            if (ge) return (l) => valor(l, ge[1]) != null && Date.parse(String(valor(l, ge[1]))) >= Date.parse(ge[2]);
            const gt = /^(\w+)\.gt\.(.*)$/.exec(s);
            if (gt) return (l) => valor(l, gt[1]) != null && Date.parse(String(valor(l, gt[1]))) > Date.parse(gt[2]);
            const m = /^(\w+)\.(i?like)\.(.*)$/.exec(s)!;
            // o % do LIKE casa quebra de linha também
            const re = new RegExp(`^${m[3].replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, "[\\s\\S]*")}$`, m[2] === "ilike" ? "iu" : "u");
            return (l) => re.test(String(valor(l, m[1]) ?? ""));
          };
          const partes = expr.match(/and\([^)]*\)|\w+\.in\.\([^)]*\)|[^,]+/g) ?? [];
          const regras = partes.map(regra);
          linhas = linhas.filter((l) => regras.some((r) => r(l)));
          return q;
        },
        not: (c: string, op: string, v: unknown) => ((linhas = linhas.filter((l) => !(op === "is" && (valor(l, c) ?? null) === v))), q),
        order: () => q,
        limit: () => q,
        then: (ok: (r: unknown) => unknown, erro?: (e: unknown) => unknown) =>
          Promise.resolve(
            falhar.includes(tabela) ? { data: null, error: { code: "XX000" }, count: null }
            : soContagem ? { data: null, error: null, count: linhas.length } : { data: linhas, error: null },
          ).then(ok, erro),
      };
      return q;
    },
  };
}

function banco(): Record<string, Linha[]> {
  return {
    receivables: [
      { id: "r-marcelo", client_id: "c-marcelo", description: "À vista — OS-00038", due_date: "2026-10-13", amount: 16890, balance_amount: 16890, status: "pending", is_deposit: false,
        service_order_id: "o-38", clients: { name: "Marcelo Marco Bertoldi", display_name: null }, service_orders: { service_order_number: "OS-00038", vessels: { name: "Aria", asset_type: "Lancha" } } },
      { id: "r-pago", client_id: "c-x", description: "pago", due_date: "2026-10-01", amount: 500, balance_amount: 0, status: "paid", is_deposit: false, service_order_id: null, clients: { name: "X" } },
      { id: "r-sinal", client_id: "c-flavio", description: "Sinal — OS-00104", due_date: "2026-10-01", amount: 2070, balance_amount: 0, status: "paid", is_deposit: true, service_order_id: "o-104" },
      { id: "r-apolo", client_id: "c-apolo", description: "NF-e 2/25", due_date: "2026-10-16", amount: 5237.99, balance_amount: 5237.99, status: "pending", is_deposit: false,
        service_order_id: null, clients: { name: "APOLO INDUSTRIA LTDA", display_name: "Apolo" } },
      { id: "r-38", client_id: "c-marcelo", description: "x", due_date: "2026-10-13", amount: 16890, status: "pending", is_deposit: false, service_order_id: "o-38" },
    ],
    service_orders: [
      { id: "q-117", service_order_number: "ORÇ-00117", status: "draft", quote_status: "draft", grand_total: 120020, client_id: "c-everton", created_at: "2026-10-13T12:00:00Z",
        updated_at: "2026-10-14T12:00:00Z", quote_validity_days: 3, quote_validity_date: null, clients: { name: "EVERTON" }, vessels: { name: "Sprinter", asset_type: "Motorhome" } },
      { id: "q-111", service_order_number: "ORÇ-00111", status: "draft", quote_status: "awaiting_approval", grand_total: 4254.69, client_id: "c-final", created_at: "2026-09-30T12:00:00Z",
        updated_at: "2026-10-13T12:00:00Z", quote_validity_days: 3, quote_validity_date: null, clients: { name: "Cliente Final" }, vessels: { name: "Motorhome" } },
      { id: "o-104", service_order_number: "OS-00104", status: "awaiting_parts", grand_total: 2760, client_id: "c-flavio", updated_at: "2026-10-03T12:00:00Z",
        scheduled_start_at: "2026-10-06T09:00:00Z", clients: { name: "Flávio da Igreja" }, vessels: [{ name: "Itapoã", asset_type: "Lancha" }] },
      { id: "o-38", service_order_number: "OS-00038", status: "completed", grand_total: 16890, client_id: "c-marcelo", updated_at: "2026-10-13T12:00:00Z", clients: { name: "Marcelo" } },
      { id: "o-velha", service_order_number: "OS-00010", status: "completed", grand_total: 900, client_id: "c-y", updated_at: "2026-06-01T12:00:00Z", clients: { name: "Y" } },
      { id: "o-hoje", service_order_number: "OS-00120", status: "scheduled", grand_total: 1000, client_id: "c-z", updated_at: "2026-10-14T12:00:00Z",
        scheduled_start_at: "2026-10-15T12:00:00Z", clients: { name: "Z" }, vessels: { name: "Brisa" } },
    ],
    agenda_tasks: [
      { id: "t-r16", title: "Comprar 1 item — OS-00104 (Flávio da Igreja)", created_at: "2026-10-03T12:00:00Z", related_entity_id: "o-104",
        automation_key: "r16:so:o-104", status: "pending", assignee_user_id: DONO.id, due_at: "2026-10-15T11:00:00Z", scheduled_start_at: null, source: "automation" },
      { id: "t-hora", title: "Ligar para o Rafael", created_at: "2026-10-14T12:00:00Z", status: "pending", assignee_user_id: DONO.id,
        scheduled_start_at: "2026-10-15T17:00:00Z", due_at: null, source: "ai", automation_key: null },
      { id: "t-prazo", title: "Mandar a NF da Charline", created_at: "2026-10-14T12:00:00Z", status: "pending", assignee_user_id: DONO.id,
        scheduled_start_at: null, due_at: "2026-10-15T20:00:00Z", source: "ai", automation_key: null },
      { id: "t-ontem", title: "Coisa de ontem", created_at: "2026-10-14T12:00:00Z", status: "pending", assignee_user_id: DONO.id,
        scheduled_start_at: "2026-10-14T17:00:00Z", due_at: null, source: "ai", automation_key: null },
    ],
    clients: [
      { id: "c-flavio", phone: "(47) 99999-0003", whatsapp: null, active: true },
      { id: "c-jorge", phone: null, whatsapp: "+55 47 90000-0001", active: true },
    ],
    whatsapp_messages: [
      ...["2026-10-09", "2026-10-10", "2026-10-11", "2026-10-13", "2026-10-14"].map((d) => ({ phone_normalized: "5547900000001", direction: "outbound", occurred_at: `${d}T15:00:00Z` })),
      { phone_normalized: "5547999990003", direction: "outbound", occurred_at: "2026-10-14T15:00:00Z" },
    ],
    whatsapp_acompanhamentos: [
      { contato: "Eng. Rafael", phone_normalized: "5511", promessa: "retorno sobre o NRX 80", lembrar_em: "2026-10-15T15:00:00Z", status: "ativo", modo: "promessa" },
      { contato: "Depois", phone_normalized: "5512", promessa: "semana que vem", lembrar_em: "2026-10-20T15:00:00Z", status: "ativo", modo: "promessa" },
      { contato: "Acomp", phone_normalized: "5513", promessa: null, lembrar_em: "2026-10-15T15:00:00Z", status: "ativo", modo: "acompanhar" },
    ],
    payables: [
      { amount: 785.07, balance_amount: 785.07, due_date: "2026-10-15", supplier_name: "TSD", description: "parcela", status: "pending" },
      { amount: 100, balance_amount: 100, due_date: "2026-10-30", supplier_name: "Longe", description: "x", status: "pending" },
    ],
    whatsapp_send_queue: [
      { id: "f1", status: "failed", updated_at: "2026-10-15T02:00:00Z" },
      { id: "f2", status: "failed", updated_at: "2026-10-14T12:00:00Z" },
      { id: "s1", status: "sent", updated_at: "2026-10-15T02:00:00Z" },
    ],
    app_error_logs: [
      { id: "e1", source: "edge", level: "error", resolved_at: null, last_seen_at: "2026-10-15T05:00:00Z" },
      { id: "e2", source: "frontend", level: "error", resolved_at: null, last_seen_at: "2026-10-15T05:00:00Z" },
    ],
    resumo_itens: [
      { phone_normalized: DONO.phone, modo: "novo", referencia: "recv:r-marcelo", dia: "2026-10-14", posicao: "manha", fato: "f", acao: null, acao_em: null, adiado_ate: null, voltou_em: null, criado_em: "2026-10-14T10:30:00Z" },
      { phone_normalized: DONO.phone, modo: "sombra", referencia: "recv:r-marcelo", dia: "2026-10-14", posicao: "manha", fato: "f", acao: null, acao_em: null, adiado_ate: null, voltou_em: null, criado_em: "2026-10-14T10:30:00Z" },
      { phone_normalized: DONO.phone, modo: "novo", referencia: "recv:r-marcelo", dia: HOJE, posicao: "manha", fato: "f", acao: null, acao_em: null, adiado_ate: null, voltou_em: null, criado_em: "2026-10-15T10:30:00Z" },
    ],
  };
}

const ESPERANDO = [
  { phone: "5547900000001", contato: "Jorge Girardon", categoria: "cliente", last_inbound_at: "2026-10-14T20:10:00Z", last_body: "🎤 Oi" },
  { phone: "5547999990003", contato: "Flávio da Igreja", categoria: "cliente", last_inbound_at: "2026-10-08T15:00:00Z", last_body: "E o compressor?" },
  { phone: "5500000000009", contato: "Alguém", categoria: "lead", last_inbound_at: "2026-10-14T13:00:00Z", last_body: null },
];
const RECEBIDAS = [{ phone_normalized: "5547900000001", body: "🎤 Oi", occurred_at: "2026-10-14T20:10:00Z" }];

function rodar(tabelas = banco(), falhar: string[] = [], selects: string[] = []) {
  return coletar(falsoAdmin(tabelas, falhar, selects), {
    agora: AGORA, hoje: HOJE, dono: DONO, modo: "novo",
    doResumo: { esperando: ESPERANDO, recebidas: RECEBIDAS, cfg: { quote_validity_days: "3" } },
  });
}

Deno.test("cobranças: só as vencidas pendentes que não são sinal, com cliente, OS e barco; o 'Na rua' soma elas", async () => {
  const { coleta, naRua } = await rodar();
  assertEquals(coleta.cobrancas.map((c) => c.id), ["r-marcelo", "r-38"]);
  assertEquals(coleta.cobrancas[0], {
    id: "r-marcelo", client_id: "c-marcelo", cliente: "Marcelo Marco Bertoldi", descricao: "À vista — OS-00038",
    vencimento: "2026-10-13", saldo: 16890, os_numero: "OS-00038", barco: "Aria", tipo_unidade: "Lancha",
  });
  // sem OS, sem unidade: nem nome nem tipo
  assertEquals([coleta.cobrancas[1].barco, coleta.cobrancas[1].tipo_unidade], [null, null]);
  assertEquals(naRua, { total: 33780, n: 2 });
});

// Decisão 6 do dono (22/10/2026): o *detalhe* mostra o tipo ("Motorhome: Overland Vegini"); a coleta traz o
// vessels.asset_type junto do nome nas leituras que viram cobrança, orçamento e OS.
Deno.test("o tipo da unidade vem junto do nome (cobrança, orçamento e OS); sem tipo, null", async () => {
  const selects: string[] = [];
  const { coleta } = await rodar(banco(), [], selects);
  const porNumero = Object.fromEntries(coleta.orcamentos.map((q) => [q.numero, q]));
  assertEquals([porNumero["ORÇ-00117"].barco, porNumero["ORÇ-00117"].tipo_unidade], ["Sprinter", "Motorhome"]);
  assertEquals([porNumero["ORÇ-00111"].barco, porNumero["ORÇ-00111"].tipo_unidade], ["Motorhome", null]);
  const os = Object.fromEntries(coleta.oss.map((o) => [o.numero, o]));
  assertEquals([os["OS-00104"].barco, os["OS-00104"].tipo_unidade], ["Itapoã", "Lancha"], "o embed em lista também vale");
  assertEquals([os["OS-00120"].barco, os["OS-00120"].tipo_unidade], ["Brisa", null]);
  assertEquals([os["OS-00038"].barco, os["OS-00038"].tipo_unidade], [null, null]);
  // o PostgREST de mentira devolve tudo: confere que a leitura de verdade PEDE o tipo
  const pedemUnidade = selects.filter((s) => s.includes("vessels("));
  const pedemTipo = pedemUnidade.filter((s) => s.includes("vessels(name, asset_type)"));
  assert(pedemTipo.some((s) => s.startsWith("receivables:")), "cobranças pedem o tipo");
  assertEquals(pedemTipo.filter((s) => s.startsWith("service_orders:") && s.includes("quote_status")).length, 1, "orçamentos pedem o tipo");
  assertEquals(pedemTipo.filter((s) => s.startsWith("service_orders:") && s.includes("scheduled_end_at, clients")).length, 2, "OS ativas e concluídas pedem o tipo");
});

Deno.test("orçamentos: rascunho sem validade; enviado com o 'até' do PDF (criado + dias)", async () => {
  const { coleta } = await rodar();
  const porNumero = Object.fromEntries(coleta.orcamentos.map((q) => [q.numero, q]));
  assertEquals(porNumero["ORÇ-00117"].fim_validade, null);
  assertEquals(porNumero["ORÇ-00111"].fim_validade, "2026-10-03");
  assertEquals(porNumero["ORÇ-00117"].cliente, "EVERTON");
});

Deno.test("rascunho já mandado ao cliente vira 'enviado' (PDF encaminhado ou link pelo sistema); o PDF para si e o teste não contam", async () => {
  const t = banco();
  t.service_orders.push(
    { id: "q-116", service_order_number: "ORÇ-00116", status: "draft", quote_status: "draft", grand_total: 70050, client_id: "c-santo", created_at: "2026-10-09T20:31:00Z",
      updated_at: "2026-10-09T20:46:00Z", quote_validity_days: 3, quote_validity_date: null, clients: { name: "Santo Inacio" }, vessels: { name: "S.I. 7.8 AUTO" } },
    { id: "q-109", service_order_number: "ORÇ-00109", status: "draft", quote_status: "draft", grand_total: 4089.97, client_id: "c-tiago", created_at: "2026-09-24T18:57:00Z",
      updated_at: "2026-09-24T19:00:00Z", quote_validity_days: 3, quote_validity_date: null, clients: { name: "Tiago" }, vessels: { name: "S.I. 8.5" } },
  );
  t.whatsapp_messages.push(
    // encaminhado do celular a quem não é da equipe: enviado
    { phone_normalized: "5547992247477", direction: "outbound", occurred_at: "2026-10-09T20:48:19Z", body: "📄 Orçamento ORÇ-00116 — Santo Inacio · S.I. 7.8 AUTO\nTotal: R$ 70.050,00" },
    // o PDF que o dono pediu para si: não é envio ao cliente
    { phone_normalized: DONO.phone, direction: "outbound", occurred_at: "2026-10-14T22:00:00Z", body: "📄 Orçamento ORÇ-00117 — EVERTON · Sprinter\nTotal: R$ 120.020,00" },
    // o número citado no meio de uma conversa: não é envio
    { phone_normalized: "5547900000001", direction: "outbound", occurred_at: "2026-10-14T22:00:00Z", body: "Vou ver o ORÇ-00117 amanhã" },
  );
  t.app_users = [{ phone_normalized: DONO.phone }];
  t.audit_log = [
    { table_name: "service_orders", action: "whatsapp_send_api", record_id: "q-109", changed_at: "2026-09-24T19:06:50Z",
      new_value: { kind: "link", context: "quote", provider_result: { ok: true } }, reason: "Envio WhatsApp (link) realizado com sucesso" },
    { table_name: "service_orders", action: "whatsapp_send_api", record_id: "q-117", changed_at: "2026-10-14T19:06:50Z",
      new_value: { kind: "document", context: "quote", provider_result: { ok: true } }, reason: "Envio WhatsApp (document) realizado com sucesso [TEST MODE ACTIVE]" },
  ];
  const { coleta } = await rodar(t);
  const porNumero = Object.fromEntries(coleta.orcamentos.map((q) => [q.numero, q]));
  assertEquals([porNumero["ORÇ-00116"].quote_status, porNumero["ORÇ-00116"].enviado_em, porNumero["ORÇ-00116"].mexido_em],
    ["sent", "2026-10-09T20:48:19.000Z", "2026-10-09T20:48:19.000Z"]);
  assertEquals(porNumero["ORÇ-00116"].fim_validade, "2026-10-12", "enviado ganha a validade do PDF");
  assertEquals([porNumero["ORÇ-00109"].quote_status, porNumero["ORÇ-00109"].enviado_em], ["sent", "2026-09-24T19:06:50.000Z"]);
  assertEquals([porNumero["ORÇ-00117"].quote_status, porNumero["ORÇ-00117"].enviado_em], ["draft", null], "para si, citado e teste não são envio");
  // a leitura dos envios é parte dos orçamentos: falhou, a manhã nova não sai (o resumo de sempre vai)
  await assertRejects(() => rodar(t, ["audit_log"]), Error, "secretário: leitura de envios");
});

Deno.test("cliente que escreveu que fechou com outra DEPOIS do orçamento: a data vai para o orçamento", async () => {
  const t = banco();
  t.service_orders.push(
    { id: "q-113", service_order_number: "ORÇ-00113", status: "draft", quote_status: "sent", grand_total: 105603.9, client_id: "c-miguel", created_at: "2026-10-05T00:45:00Z",
      updated_at: "2026-10-05T18:46:00Z", quote_validity_days: 3, quote_validity_date: null, clients: { name: "Miguel" }, vessels: { name: "Above & Beyond" } },
    { id: "q-200", service_order_number: "ORÇ-00200", status: "draft", quote_status: "sent", grand_total: 9000, client_id: "c-miguel", created_at: "2026-10-10T12:00:00Z",
      updated_at: "2026-10-10T12:00:00Z", quote_validity_days: 3, quote_validity_date: null, clients: { name: "Miguel" }, vessels: { name: "Above & Beyond" } },
  );
  t.service_orders.push(
    { id: "q-300", service_order_number: "ORÇ-00300", status: "draft", quote_status: "sent", grand_total: 8000, client_id: "c-santo", created_at: "2026-10-01T12:00:00Z",
      updated_at: "2026-10-01T12:00:00Z", quote_validity_days: 30, quote_validity_date: null, clients: { name: "Santo Inacio" }, vessels: { name: "S.I." } },
  );
  t.clients.push({ id: "c-santo", phone: "(47) 99224-7477", whatsapp: null, active: true });
  t.whatsapp_messages.push(
    { client_id: "c-miguel", direction: "inbound", occurred_at: "2026-10-07T17:15:54Z", body: "André você demora muito pra responder e por isso acabei fechando com outra empresa. Obrigado" },
    { client_id: "c-miguel", direction: "inbound", occurred_at: "2026-10-07T17:58:33Z", body: "Sim, já fechei" },
    // sem client_id na mensagem: o cliente vem pelo telefone do cadastro
    { client_id: null, phone_normalized: "5547992247477", direction: "inbound", occurred_at: "2026-10-10T12:00:00Z", body: "Não tenho mais interesse, obrigado" },
  );
  const { coleta } = await rodar(t);
  const porNumero = Object.fromEntries(coleta.orcamentos.map((q) => [q.numero, q]));
  assertEquals(porNumero["ORÇ-00113"].cliente_encerrou_em, "2026-10-07T17:15:54.000Z");
  assertEquals(porNumero["ORÇ-00200"].cliente_encerrou_em, null, "orçamento feito DEPOIS da desistência não é afetado");
  assertEquals(porNumero["ORÇ-00300"].cliente_encerrou_em, "2026-10-10T12:00:00.000Z", "achado pelo telefone");
});

Deno.test("OS: ativas e concluídas recentes; sinal pago, a tarefa da R16 e as cobranças vivas", async () => {
  const { coleta } = await rodar();
  assertEquals(coleta.oss.map((o) => o.numero).sort(), ["OS-00038", "OS-00104", "OS-00120"], "a concluída de junho fica de fora");
  const o104 = coleta.oss.find((o) => o.numero === "OS-00104")!;
  assertEquals([o104.sinal_pago, o104.cobrancas_vivas, o104.tarefa_compra?.titulo], [2070, 1, "Comprar 1 item — OS-00104 (Flávio da Igreja)"]);
  assertEquals(coleta.oss.find((o) => o.numero === "OS-00038")!.cobrancas_vivas, 2);
});

Deno.test("conversas: cliente pelo telefone (8 dígitos), dias de conversa sua e as recebidas da semana", async () => {
  const { coleta } = await rodar();
  const jorge = coleta.conversas.find((c) => c.contato === "Jorge Girardon")!;
  assertEquals([jorge.client_id, jorge.diasComMensagemSua, jorge.recebidas.length], ["c-jorge", 5, 1]);
  const flavio = coleta.conversas.find((c) => c.contato === "Flávio da Igreja")!;
  assertEquals([flavio.client_id, flavio.diasComMensagemSua], ["c-flavio", 1]);
  // sem recebidas lidas: a última mensagem da RPC
  assertEquals(flavio.recebidas, [{ body: "E o compressor?", em: "2026-10-08T15:00:00Z" }]);
  assertEquals(coleta.conversas.find((c) => c.contato === "Alguém")!.categoria, "contato");
});

Deno.test("linha Hoje: agenda de Brasília (sem a tarefa da automação nem a de ontem), promessa de hoje, vencimentos, falhas da noite", async () => {
  const { deHoje } = await rodar();
  assertEquals(deHoje.agenda, [
    { hora: "09:00", titulo: "OS-00120 (Brisa)" },
    { hora: "14:00", titulo: "Ligar para o Rafael" },
    { hora: null, titulo: "Mandar a NF da Charline" },
  ]);
  assertEquals(deHoje.promessas, [{ contato: "Eng. Rafael", promessa: "retorno sobre o NRX 80" }]);
  assertEquals(deHoje.vencimentos, [
    { lado: "receber", quando: "amanha", valor: 5237.99, nome: "Apolo" },
    { lado: "pagar", quando: "hoje", valor: 785.07, nome: "TSD" },
  ]);
  assertEquals([deHoje.falhasDeEnvio, deHoje.errosDaNoite], [1, 1]);
});

// ─── (23/10/2026) Agenda de Produção, Fase 0: D11a e D4 no "Hoje" ──────────────────────────────────
Deno.test("D11a: a OS esperando o cliente entra nas ativas (STATUS_OS_ATIVAS) e vira 'esperando o cliente desde' na lista", async () => {
  const t = banco();
  t.service_orders.push(
    { id: "o-76", service_order_number: "OS-00076", status: "awaiting_client", grand_total: 740, client_id: "c-rodrigo", updated_at: "2026-08-08T21:31:38Z",
      scheduled_start_at: null, scheduled_end_at: null, clients: { name: "Rodrigo" }, vessels: { name: "MH Overlander - VW Delivery", asset_type: "Motorhome" } },
  );
  const { coleta } = await rodar(t);
  const o76 = coleta.oss.find((o) => o.numero === "OS-00076");
  assert(o76, "a leitura das ativas traz o awaiting_client");
  assertEquals([o76.status, o76.agendada_em, o76.termina_em], ["awaiting_client", null, null]);
  const c = candidatosDoDia(coleta, AGORA, HOJE).find((x) => x.referencia === "os:o-76")!;
  assertEquals([c.tipo, c.elegivel], ["os_parada", false]);
  assertEquals(c.titulo, "*OS-00076* (Rodrigo, MH Overlander - VW Deli…): esperando o cliente desde 08/08.");
});

Deno.test("D4: o 'Hoje' traz a OS que começou ontem e termina amanhã (sem hora, 'em curso desde'), não a encerrada nem a que acabou", async () => {
  const t = banco();
  const os = (id: string, numero: string, status: string, ini: string | null, fim: string | null, barco: string) => ({
    id, service_order_number: numero, status, grand_total: 1000, client_id: "c-w", updated_at: "2026-10-14T12:00:00Z",
    scheduled_start_at: ini, scheduled_end_at: fim, clients: { name: "W" }, vessels: { name: barco },
  });
  t.service_orders.push(
    // de ontem 08:00 a amanhã 18:00: é de hoje também
    os("o-121", "OS-00121", "in_progress", "2026-10-14T11:00:00Z", "2026-10-16T21:00:00Z", "Maré"),
    // o barco de nome longo encurta; o "em curso desde" nunca
    os("o-126", "OS-00126", "awaiting_parts", "2026-10-13T12:00:00Z", "2026-10-20T21:00:00Z", "Santo Inácio 7.8"),
    // concluída antes do fim da janela: não está "em curso"
    os("o-122", "OS-00122", "completed", "2026-10-13T11:00:00Z", "2026-10-16T21:00:00Z", "Vento"),
    // orçamento com data: não está "em curso"
    os("q-124", "ORÇ-00124", "draft", "2026-10-14T11:00:00Z", "2026-10-16T21:00:00Z", "Onda"),
    // acabou ontem às 18:00: não é de hoje
    os("o-123", "OS-00123", "scheduled", "2026-10-13T11:00:00Z", "2026-10-14T21:00:00Z", "Rio"),
    // começou antes e não tem fim: vale só o início (ontem), não é de hoje
    os("o-127", "OS-00127", "open", "2026-10-14T11:00:00Z", null, "Lago"),
    // termina à meia-noite exata de hoje: não toca hoje
    os("o-128", "OS-00128", "scheduled", "2026-10-14T11:00:00Z", "2026-10-15T03:00:00Z", "Mar"),
  );
  const selects: string[] = [];
  const { deHoje } = await rodar(t, [], selects);
  assertEquals(deHoje.agenda, [
    { hora: null, titulo: "OS-00126 (Santo…), em curso desde 13/10" },
    { hora: null, titulo: "OS-00121 (Maré), em curso desde 14/10" },
    { hora: "09:00", titulo: "OS-00120 (Brisa)" },
    { hora: "14:00", titulo: "Ligar para o Rafael" },
    { hora: null, titulo: "Mandar a NF da Charline" },
  ]);
  assert(deHoje.agenda.every((a) => a.titulo.length <= CORTE_DA_AGENDA_DE_HOJE), "cabe no corte da linha Hoje");
  assert(selects.some((s) => s.startsWith("service_orders: service_order_number, status, scheduled_start_at, scheduled_end_at")), "a leitura do dia pede o fim da janela");
});

Deno.test("histórico: só o mesmo modo e sem o dia de hoje", async () => {
  const { historico } = await rodar();
  assertEquals(historico.length, 1);
  assertEquals([historico[0].dia, historico[0].referencia], ["2026-10-14", "recv:r-marcelo"]);
});

Deno.test("leitura essencial que falha LANÇA (quem chama volta ao resumo de sempre); enriquecimento vira vazio", async () => {
  for (const t of ["receivables", "service_orders", "resumo_itens"]) {
    await assertRejects(() => rodar(banco(), [t]), Error, "secretário: leitura de");
  }
  const semExtras = await rodar(banco(), ["whatsapp_acompanhamentos", "payables", "app_error_logs", "clients"]);
  assertEquals(semExtras.deHoje.promessas, []);
  assertEquals(semExtras.deHoje.vencimentos, []);
  assertEquals(semExtras.deHoje.errosDaNoite, 0);
  assert(semExtras.coleta.conversas.every((c) => c.client_id === null));
});
