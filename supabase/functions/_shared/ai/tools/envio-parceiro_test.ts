// Retorno F4 (P12.2): o PDF ao parceiro pelo send_service_order_link, com banco e fetch simulados.
//
// O destino vem SÓ de parceiro_destino_do_pdf (só o dono, regra do documento, número único); nenhum telefone dos
// argumentos nem do cadastro do cliente é lido. Só formato 'pdf', em via reduzida, com o *sim <PIN>* (nunca autônomo).
// Sem destino, o envio ao cliente é o de sempre, byte a byte, com a chave pdf_parceiro_ligado nos dois valores.
// Nomes, CPFs e telefones inventados (4321 e 7391 como finais).
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { oQueMudouDesdeOPedido, resumirEnvioAoCliente, retratoDoEnvio, validarPedidoDeEnvio, whatsappTools } from "./whatsapp.ts";
import { isAutonomyGranted, NEVER_AUTONOMOUS_WHEN } from "../autonomy-policy.ts";
import { hashCurto } from "../../whatsapp/idempotencia.ts";

const tool = whatsappTools.find((t) => t.name === "send_service_order_link")!;

type Linha = Record<string, unknown>;
const CLIENTE = {
  id: "c1", name: "João Pedro Inventado", display_name: null, whatsapp: "5547988887391", phone: "4733337391",
  opt_out_whatsapp: false, generico: false, cpf_cnpj: "123.456.789-09", email: "joao.inventado@exemplo.com", address: "Rua Sintética, 77, Itajaí",
};
const ORC = {
  id: "11111111-1111-4111-8111-111111111111",
  service_order_number: "ORÇ-00123",
  status: "draft",
  quote_status: "draft",
  origem: null,
  share_token: "22222222-2222-4222-8222-222222222222",
  client_id: "c1",
  updated_at: "2026-09-25T12:00:00.000Z",
  created_at: "2026-09-25T02:30:00.000Z",
  quote_validity_days: 3,
  quote_validity_date: null,
  grand_total: 1000,
  labor_cost_total: 0,
  parts_cost_total: 1000,
  travel_cost_total: 0,
  discount_amount: 0,
  tax_amount: 0,
  operational_cost_total: 0,
  problem_description: "Troca de bateria do motorhome",
  clients: { name: CLIENTE.name, phone: "(47) 98888-7391", cpf_cnpj: CLIENTE.cpf_cnpj, email: CLIENTE.email, address_line_1: "Rua Sintética, 77", city: "Itajaí", state: "SC" },
  // revisão de 10/11 (seguranca-pdf): o nome da unidade e a placa sintéticos, que a via reduzida não mostra
  vessels: { name: "Motorhome Azul", asset_type: "Motorhome", hull_id_or_registration: "ABC1D23" },
  marinas: null,
  service_order_services: [],
  service_order_parts: [],
  service_surveys: [],
  service_order_expenses: [],
  service_order_photos: [],
  payment_condition_presets: null,
};
const ONZE_DA_MANHA = new Date("2026-09-26T14:00:00.000Z");
const FONE_MP = "5547999994321";
const DESTINO_OK = {
  ok: true, phone: FONE_MP, chave8: "99994321", rotulo: "MP (comercial, ••4321)", papel: "contratante",
  interessado_id: "oi-1", parceiro_id: "pa-1", reduzir: true,
};

function montarAmbiente(opcoes: {
  pdfParceiroLigado?: boolean;
  destino?: unknown;
  destinoErro?: { code?: string; message?: string };
  cliente?: Linha;
  ordem?: Linha;
} = {}) {
  const sequencia: string[] = [];
  const rpcs: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const inserts: Array<{ tabela: string; linha: Linha }> = [];
  const htmls: string[] = [];
  const tabelas: Record<string, Linha[]> = {
    service_orders: [opcoes.ordem ?? ORC],
    clients: [opcoes.cliente ?? CLIENTE],
    app_settings: [{ key: "company_name", value: "HBR" }],
    app_users: [{ id: "u1", full_name: "Gustavo Dono", role: "admin" }],
    receivables: [],
    payments: [],
    retorno_config: [{ validade_orcamento_dias: 7, pdf_parceiro_ligado: opcoes.pdfParceiroLigado ?? true }],
  };
  const consulta = (nome: string) => {
    let resultado = [...(tabelas[nome] ?? [])];
    let unico = false;
    // deno-lint-ignore no-explicit-any
    const q: any = {
      select: (colunas?: string) => {
        sequencia.push(`select:${nome}:${colunas ?? ""}`);
        return q;
      },
      eq: (c: string, v: unknown) => {
        resultado = resultado.filter((l) => l[c] === v);
        return q;
      },
      neq: () => q,
      in: () => q,
      not: () => q,
      order: () => q,
      limit: () => q,
      single: () => {
        unico = true;
        return q;
      },
      maybeSingle: () => {
        unico = true;
        return q;
      },
      insert: (linha: Linha) => {
        inserts.push({ tabela: nome, linha });
        return { select: () => ({ single: () => Promise.resolve({ data: { id: "novo" }, error: null }) }), then: (ok: (v: unknown) => void) => ok({ data: null, error: null }) };
      },
      delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
      update: () => ({ eq: () => Promise.resolve({ error: null }) }),
      then: (ok: (v: unknown) => void) => ok({ data: unico ? (resultado[0] ?? null) : resultado, error: null }),
    };
    return q;
  };
  const admin = {
    from: (t: string) => consulta(t),
    rpc: (fn: string, args: Record<string, unknown>) => {
      rpcs.push({ fn, args });
      if (fn === "parceiro_destino_do_pdf") {
        return Promise.resolve(opcoes.destinoErro ? { data: null, error: opcoes.destinoErro } : { data: opcoes.destino ?? DESTINO_OK, error: null });
      }
      // Retorno F5 (P11.4): a validade do envio ao cliente, com a chave desligada (o padrão: nada muda)
      if (fn === "orcamento_validade_do_envio") return Promise.resolve({ data: { ok: true, fixou: false, motivo: "desligada" }, error: null });
      return Promise.resolve({ data: null, error: null });
    },
    storage: {
      from: (_bucket: string) => ({
        upload: () => Promise.resolve({ data: {}, error: null }),
        createSignedUrl: (caminho: string) => Promise.resolve({ data: { signedUrl: `https://sb.example/${caminho}` }, error: null }),
        remove: () => Promise.resolve({ data: [], error: null }),
      }),
    },
  };
  // deno-lint-ignore no-explicit-any
  const envios: any[] = [];
  const pdfValido = () => new Response(new Uint8Array([...new TextEncoder().encode("%PDF-1.7\n"), ...new Uint8Array(3000)]), { headers: { "content-type": "application/pdf" } });
  const fetchFalso = async (entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada instanceof Request ? entrada.url : entrada);
    if (url.endsWith("/api/pdf")) {
      htmls.push(String(JSON.parse(String(init?.body)).html));
      return pdfValido();
    }
    if (url.endsWith("/functions/v1/whatsapp-send")) {
      sequencia.push("whatsapp-send");
      envios.push(JSON.parse(String(init?.body)));
      return new Response(JSON.stringify({ success: true, messageId: "m1" }));
    }
    throw new Error(`fetch inesperado: ${url}`);
  };
  const ctx = {
    sb: admin, admin, userId: "u1", userRole: "admin" as const, jwt: "", appOrigin: "",
    settings: { app_public_url: "https://erp.example", quote_validity_days: "3" },
  };
  return { sequencia, rpcs, inserts, htmls, envios, fetchFalso, ctx, admin };
}

// deno-lint-ignore no-explicit-any
async function executar(amb: ReturnType<typeof montarAmbiente>, args: Record<string, unknown>): Promise<any> {
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://sb.example");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
  globalThis.fetch = amb.fetchFalso as typeof fetch;
  const relogio = new FakeTime(ONZE_DA_MANHA);
  try {
    // deno-lint-ignore no-explicit-any
    return await tool.execute(args, amb.ctx as any);
  } finally {
    relogio.restore();
    globalThis.fetch = original;
  }
}

const PEDIDO = { service_order_id: ORC.id, formato: "pdf", destino: "parceiro" };

Deno.test("input_schema: destino só cliente ou parceiro, e nenhum campo de telefone", () => {
  const props = tool.input_schema.properties as Record<string, { enum?: string[] }>;
  assertEquals(props.destino?.enum, ["cliente", "parceiro"]);
  assert(!Object.keys(props).some((k) => /phone|fone|telefone/.test(k)));
});

Deno.test("pdf_parceiro_ligado falso: recusa antes de qualquer outra leitura, nada sai", async () => {
  const amb = montarAmbiente({ pdfParceiroLigado: false });
  const r = await executar(amb, PEDIDO);
  assertEquals(r.nada_enviado, true);
  assertStringIncludes(r.error, "desligado");
  assertEquals(amb.rpcs.length, 0);
  assertEquals(amb.sequencia.filter((s) => !s.startsWith("select:retorno_config")), []);
  assertEquals(amb.envios.length, 0);
});

Deno.test("recusas do destino: sem vínculo, indicou, anfitriã, ambíguo, veto, opt-out, sem aviso — frase do banco, nada sai, cadastro do cliente nem lido", async () => {
  const frases: Array<[string, string]> = [
    ["sem_vinculo", "Esta OS não tem vínculo com o parceiro; nada saiu."],
    ["papel", "A MP só indicou este cliente: o PDF com valor não vai a ela. Nada saiu."],
    ["destino_ambiguo", "Não sei qual número da MP recebe este PDF; nada saiu."],
    ["veto", "O cliente pediu que a MP não acompanhe. Nada saiu."],
    ["opt_out", "O cliente pediu para não receber mensagens. Nada saiu."],
    ["sem_aviso", "O PDF à MP só sai depois do aviso ao cliente e de 24 h. Nada saiu."],
    ["antes_de_24h", "O PDF à MP só sai depois do aviso ao cliente e de 24 h. Nada saiu."],
  ];
  for (const [motivo, frase] of frases) {
    const amb = montarAmbiente({ destino: { ok: false, motivo, frase } });
    const r = await executar(amb, { ...PEDIDO, phone: "5547911112222", to_phone: "5547911112222" });
    assertEquals(r, { error: frase, nada_enviado: true }, motivo);
    assertEquals(amb.envios.length, 0, motivo);
    assertEquals(amb.sequencia.some((s) => s.startsWith("select:clients")), false, `${motivo}: leu o cliente`);
  }
});

Deno.test("o banco responde com a regra do documento: autor dono, OS e o parceiro só do retrato", async () => {
  const amb = montarAmbiente();
  await executar(amb, { ...PEDIDO, parceiro_id: "pa-do-modelo", _retrato: { destino: "parceiro", parceiro_id: "pa-1", telefone: hashCurto("5547999994321"), total: 1000 } });
  assertEquals(amb.rpcs[0].fn, "parceiro_destino_do_pdf");
  assertEquals(amb.rpcs[0].args, { p_os: ORC.id, p_autor: "u1", p_parceiro: "pa-1" });
});

Deno.test("erro do banco no destino: nada sai (falha fecha)", async () => {
  const amb = montarAmbiente({ destinoErro: { code: "42501", message: "só o dono" } });
  const r = await executar(amb, PEDIDO);
  assertEquals(r.nada_enviado, true);
  assertEquals(amb.envios.length, 0);
});

Deno.test("contratante e pagador: o PDF vai ao número do banco, nunca ao do cliente nem ao dos argumentos", async () => {
  for (const [papel, fone] of [["contratante", FONE_MP], ["pagador", "5547966662233"]] as const) {
    const amb = montarAmbiente({ destino: { ...DESTINO_OK, papel, phone: fone, chave8: fone.slice(-8), rotulo: `MP (financeiro, ••${fone.slice(-4)})` } });
    const r = await executar(amb, { ...PEDIDO, phone: "5547911112222" });
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(amb.envios.length, 1);
    assertEquals(amb.envios[0].phone, fone, papel);
    assertEquals(amb.envios[0].kind, "document");
    // não marca 'sent' (marcar-enviado.ts): o contexto é service_order
    assertEquals(amb.envios[0].context, "service_order");
    // a chave anti-duplicado inclui o número do parceiro
    assertStringIncludes(amb.envios[0].dedupe_key, fone);
    assertStringIncludes(r.enviado_para, `••${fone.slice(-4)}`);
    assertEquals(r.destino_chave8, fone.slice(-8));
    // o registro: audiência parceiro, sem nome, com o papel
    const log = amb.inserts.filter((i) => i.tabela === "ai_comms_log").map((i) => i.linha);
    assertEquals(log.length, 1);
    assertEquals(log[0].audiencia, "parceiro");
    assertEquals(log[0].entity_kind, "service_order");
    assertEquals(log[0].message_preview, `[pdf parceiro] papel=${papel}`);
    assertEquals(log[0].status, "sent");
  }
});

Deno.test("via reduzida: o HTML não traz CPF, fone, e-mail nem endereço sintéticos; o arquivo só tipo e número", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, PEDIDO);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.htmls.length, 1);
  const html = amb.htmls[0];
  // revisão de 10/11 (seguranca-pdf): nem o nome da unidade ("Azul") nem a placa
  for (const dado of ["123.456.789-09", "98888-7391", "joao.inventado@exemplo.com", "Rua Sintética", "João Pedro Inventado", "Azul", "ABC1D23"]) {
    assertEquals(html.includes(dado), false, dado);
  }
  assertStringIncludes(html, "João I.");
  assertEquals(amb.envios[0].document_filename, "Orcamento_ORC-00123.pdf");
  assertEquals(r.arquivo, "Orcamento_ORC-00123.pdf");
  assert(!JSON.stringify(r).includes("João Pedro"));
});

Deno.test("na OS da própria parceira (reduzir falso), o PDF sai inteiro", async () => {
  const amb = montarAmbiente({ destino: { ...DESTINO_OK, reduzir: false } });
  await executar(amb, PEDIDO);
  assertStringIncludes(amb.htmls[0], "123.456.789-09");
  // revisão de 10/11 (seguranca-pdf): inteiro, com o nome da unidade e a placa
  assertStringIncludes(amb.htmls[0], "Azul");
  assertStringIncludes(amb.htmls[0], "ABC1D23");
});

Deno.test("cliente sem telefone chega ao envio: o parceiro não depende do número do cliente", async () => {
  const amb = montarAmbiente({ cliente: { ...CLIENTE, whatsapp: null, phone: null } });
  const r = await executar(amb, PEDIDO);
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.envios[0].phone, FONE_MP);
});

Deno.test("papel indicou que escapasse do banco: valor_a_parceiro bloqueia, nada sai", async () => {
  const amb = montarAmbiente({ destino: { ...DESTINO_OK, papel: "indicou" } });
  const r = await executar(amb, PEDIDO);
  assert(r.error, JSON.stringify(r));
  assertEquals(amb.envios.length, 0);
  const log = amb.inserts.filter((i) => i.tabela === "ai_comms_log").map((i) => i.linha);
  assertEquals(log[0]?.status, "blocked");
  assertEquals(log[0]?.block_code, "valor_a_parceiro");
});

Deno.test("o número da MP mudou desde o pedido: nada sai", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { ...PEDIDO, _retrato: { destino: "parceiro", parceiro_id: "pa-1", telefone: hashCurto("5547900001111"), total: 1000 } });
  assertEquals(r.nada_enviado, true);
  assertStringIncludes(r.error, "o número do parceiro que recebe o PDF mudou");
  assertEquals(amb.envios.length, 0);
});

Deno.test("link, pdf_e_link e resumo são recusados antes da pendência, com destino parceiro", () => {
  for (const formato of ["link", "pdf_e_link", "resumo"]) {
    const r = validarPedidoDeEnvio({ service_order_id: ORC.id, formato, destino: "parceiro" }, { userRole: "admin", userId: "u1" });
    assertEquals(r?.nada_enviado, true, formato);
    assertStringIncludes(String(r?.error), "só o PDF", formato);
  }
  assertEquals(validarPedidoDeEnvio({ service_order_id: ORC.id, formato: "pdf", destino: "parceiro" }, { userRole: "admin", userId: "u1" }), null);
  assertEquals(validarPedidoDeEnvio({ service_order_id: ORC.id, destino: "parceiro" }, { userRole: "admin", userId: "u1" }), null);
  // o vendedor externo não manda PDF a ninguém
  assert(validarPedidoDeEnvio({ service_order_id: ORC.id, formato: "pdf", destino: "parceiro" }, { userRole: "seller_external" as never, userId: "u2" }));
});

Deno.test("NEVER_AUTONOMOUS_WHEN trava destino parceiro em qualquer formato, inclusive link", () => {
  const trava = NEVER_AUTONOMOUS_WHEN.send_service_order_link;
  assertEquals(trava({ formato: "link", destino: "parceiro" }), true);
  assertEquals(trava({ formato: "pdf", destino: "parceiro" }), true);
  assertEquals(trava({ formato: "link" }), false);
  assertEquals(trava({ formato: "link", destino: "cliente" }), false);
  assertEquals(isAutonomyGranted("send_service_order_link", "high", { ai_autonomy_send_service_order_link: "auto" }, { formato: "link", destino: "parceiro" }), false);
});

Deno.test("resumo do sim: o literal diz para a MP, o número mascarado e a via reduzida; nunca o nome inteiro do cliente", async () => {
  const amb = montarAmbiente();
  const t = await resumirEnvioAoCliente(amb.admin, PEDIDO, ONZE_DA_MANHA, "u1");
  assert(t);
  assertStringIncludes(t!, "para a MP (comercial, ••4321)");
  assertStringIncludes(t!, "via reduzida");
  assertStringIncludes(t!, "ORÇ-00123");
  assert(!t!.includes("João Pedro Inventado"), t!);
  assert(!t!.includes("7391"), "o número do cliente não aparece");
  // destino recusado: o resumo avisa que nada vai sair
  const recusado = montarAmbiente({ destino: { ok: false, motivo: "papel", frase: "A MP só indicou este cliente: o PDF com valor não vai a ela. Nada saiu." } });
  assertStringIncludes((await resumirEnvioAoCliente(recusado.admin, PEDIDO, ONZE_DA_MANHA, "u1"))!, "⚠️ A MP só indicou");
  const desligado = montarAmbiente({ pdfParceiroLigado: false });
  assertStringIncludes((await resumirEnvioAoCliente(desligado.admin, PEDIDO, ONZE_DA_MANHA, "u1"))!, "⚠️ O PDF ao parceiro está desligado");
});

Deno.test("retrato do envio ao parceiro: hash do número do banco, destino e parceiro; o que mudou fala da MP", async () => {
  const amb = montarAmbiente();
  const r = await retratoDoEnvio(amb.admin, PEDIDO, "u1");
  assertEquals(r, { telefone: hashCurto(FONE_MP), total: 1000, destino: "parceiro", parceiro_id: "pa-1", numero: "••4321" });
  assertEquals(oQueMudouDesdeOPedido(r!, { digitos: "5547900001111", total: 1000 }, "parceiro"), "o número do parceiro que recebe o PDF mudou");
  assertEquals(oQueMudouDesdeOPedido(r!, { digitos: FONE_MP, total: 1000 }, "parceiro"), null);
  assertEquals(await retratoDoEnvio(montarAmbiente({ destino: { ok: false, motivo: "papel", frase: "x" } }).admin, PEDIDO, "u1"), null);
});

// ─── Regressão: sem destino, o envio ao cliente é o de sempre, com a chave nos dois valores ─────────────────────────

Deno.test("destino ausente (ou cliente): igual ao de hoje, byte a byte, e a chave pdf_parceiro_ligado nem é lida", async () => {
  const saidas: string[] = [];
  for (const ligado of [false, true]) {
    for (const extra of [{}, { destino: "cliente" }]) {
      const amb = montarAmbiente({ pdfParceiroLigado: ligado });
      const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf", ...extra });
      assertEquals(r.ok, true, JSON.stringify(r));
      assertEquals(amb.rpcs.filter((x) => x.fn === "parceiro_destino_do_pdf").length, 0);
      assertEquals(amb.sequencia.some((s) => s.includes("pdf_parceiro_ligado")), false, "a chave foi lida");
      assertEquals(amb.envios[0].phone, CLIENTE.whatsapp);
      // o caminho guardado no bucket é aleatório (crypto.randomUUID): sai da comparação
      const { document_url: _url, ...envio } = amb.envios[0];
      saidas.push(JSON.stringify({ envio, html: amb.htmls[0], r, log: amb.inserts.map((i) => i.linha) }));
    }
  }
  assertEquals(new Set(saidas).size, 1, "as quatro execuções saem idênticas");
  // e com o cliente inteiro no PDF
  assertStringIncludes(JSON.parse(saidas[0]).html, "123.456.789-09");
});

Deno.test("resumo sem destino: o de sempre, sem ler o parceiro", async () => {
  const amb = montarAmbiente();
  const t = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id, formato: "pdf" }, ONZE_DA_MANHA, "u1");
  assertStringIncludes(t!, `Cliente: *${CLIENTE.name}*`);
  // (F5) o resumo ao cliente pergunta a validade do envio (orcamento_validade_do_envio); o parceiro continua sem ser lido
  assertEquals(amb.rpcs.filter((x) => x.fn !== "orcamento_validade_do_envio").length, 0);
  const semAutor = await resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id, formato: "pdf" }, ONZE_DA_MANHA);
  assertEquals(semAutor, t);
});
