// Retorno F3 (P9): a validade de 7 dias contados do ENVIO, escrita no PDF e na legenda (K6, rr-k6.json).
// A data fica em quote_validity_date, que o PDF e a R19 já leem, e é refeita a cada tentativa enquanto o orçamento está em
// rascunho: PDF que falha não congela a data. Depois de 'sent' não renova. Nomes e telefones inventados.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import {
  fixarValidadeDoEnvio,
  legendaDoPdf,
  opcoesDoResumo,
  resumirEnvioAoCliente,
  retratoDoEnvio,
  type ValidadeDoEnvio,
  validadeDoEnvio,
  whatsappTools,
} from "./whatsapp.ts";
import { montarResumoDeValores } from "../../pdf/gerar-e-guardar.ts";

const tool = whatsappTools.find((t) => t.name === "send_service_order_link")!;

// ─── Banco de mentira só para fixarValidadeDoEnvio ──────────────────────────────────────────
function adminFalso(opcoes: { dias?: unknown; erroUpdate?: string; erroConfig?: string } = {}) {
  const updates: { tabela: string; campos: Record<string, unknown>; coluna: string; valor: unknown }[] = [];
  const leituras: string[] = [];
  const admin = {
    from(tabela: string) {
      if (tabela === "retorno_config") {
        return {
          select: (colunas: string) => {
            leituras.push(colunas);
            return {
              maybeSingle: () =>
                Promise.resolve(
                  opcoes.erroConfig
                    ? { data: null, error: { message: opcoes.erroConfig } }
                    : { data: { validade_orcamento_dias: "dias" in opcoes ? opcoes.dias : 7 }, error: null },
                ),
            };
          },
        };
      }
      if (tabela === "service_orders") {
        return {
          update: (campos: Record<string, unknown>) => ({
            eq: (coluna: string, valor: unknown) => {
              updates.push({ tabela, campos, coluna, valor });
              return Promise.resolve(opcoes.erroUpdate ? { error: { message: opcoes.erroUpdate } } : { error: null });
            },
          }),
        };
      }
      throw new Error(`tabela inesperada: ${tabela}`);
    },
  };
  return { admin, updates, leituras };
}

const SO_RASCUNHO = { id: "os-1", quote_status: "draft", origem: "retorno_previa", quote_validity_date: null };
const AS_23H30_BRT = new Date("2026-12-08T02:30:00.000Z");   // 23:30 de 07/12 em Brasília

Deno.test("com origem e sem data: 7 dias pelo calendário de Brasília, relógio às 23:30 BRT", async () => {
  const { admin, updates } = adminFalso();
  const r = await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
  assertEquals(r, {});
  assertEquals(updates.length, 1);
  assertEquals(updates[0].campos, { quote_validity_days: 7, quote_validity_date: "2026-12-14" });
  assertEquals(updates[0].coluna, "id");
  assertEquals(updates[0].valor, "os-1");
});

Deno.test("com dataDoCartao e sem origem: grava essa data, com os dias da config", async () => {
  const { admin, updates } = adminFalso({ dias: 10 });
  const r = await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, origem: null }, "2026-12-20", AS_23H30_BRT);
  assertEquals(r, {});
  assertEquals(updates[0].campos, { quote_validity_days: 10, quote_validity_date: "2026-12-20" });
});

Deno.test("sem origem e sem dataDoCartao: nenhum update, nem leitura de config (tela e assistente livre até a F5)", async () => {
  const { admin, updates, leituras } = adminFalso();
  const r = await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, origem: null }, undefined, AS_23H30_BRT);
  assertEquals(r, {});
  assertEquals(updates.length, 0);
  assertEquals(leituras.length, 0);
});

Deno.test("orçamento já enviado (sent): não renova, mesmo com origem ou data do cartão (D13)", async () => {
  const { admin, updates } = adminFalso();
  await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, quote_status: "sent" }, "2026-12-20", AS_23H30_BRT);
  await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, quote_status: "sent" }, undefined, AS_23H30_BRT);
  assertEquals(updates.length, 0);
});

Deno.test("rascunho com data de tentativa anterior: refaz a partir de agora", async () => {
  const { admin, updates } = adminFalso();
  await fixarValidadeDoEnvio(admin, { ...SO_RASCUNHO, quote_validity_date: "2026-12-10" }, undefined, AS_23H30_BRT);
  assertEquals(updates[0].campos.quote_validity_date, "2026-12-14");
});

Deno.test("validade_orcamento_dias que não serve (0, nulo, texto) cai nos 7 dias", async () => {
  for (const dias of [0, null, "abc", -1]) {
    const { admin, updates } = adminFalso({ dias });
    await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
    assertEquals(updates[0].campos.quote_validity_days, 7, `dias = ${dias}`);
    assertEquals(updates[0].campos.quote_validity_date, "2026-12-14");
  }
});

Deno.test("config que falha ao ler cai nos 7 dias, sem derrubar", async () => {
  const { admin, updates } = adminFalso({ erroConfig: "tabela fora" });
  await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
  assertEquals(updates[0].campos.quote_validity_days, 7);
});

Deno.test("erro no update não lança e devolve aviso_validade", async () => {
  const { admin } = adminFalso({ erroUpdate: "update recusado" });
  const r = await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
  assertEquals(r, { aviso_validade: "Não consegui gravar a validade; o PDF saiu com a validade antiga, confira na tela." });
});

Deno.test("exceção de verdade (cliente quebrado): nunca lança", async () => {
  const admin = { from() { throw new Error("cliente quebrado"); } };
  const r = await fixarValidadeDoEnvio(admin, SO_RASCUNHO, undefined, AS_23H30_BRT);
  assertEquals(typeof r.aviso_validade, "string");
});

// ─── O envio inteiro, com banco e fetch simulados ──────────────────────────────────────────
type Linha = Record<string, unknown>;
const CLIENTE = { id: "c1", name: "Cliente Validade Silva", display_name: null, whatsapp: "5547999990123", phone: "4733331234", opt_out_whatsapp: false, generico: false };
const ORC = {
  id: "11111111-1111-4111-8111-111111111111",
  service_order_number: "ORÇ-00123",
  status: "draft",
  quote_status: "draft",
  origem: "retorno_previa",
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
  problem_description: "Serviço de teste",
  clients: { name: "Cliente Validade Silva", phone: "4733331234" },
  vessels: { name: "Barco Azul" },
  marinas: null,
  service_order_services: [],
  service_order_parts: [],
  service_surveys: [],
  service_order_expenses: [],
  service_order_photos: [],
  payment_condition_presets: null,
};
const ONZE_DA_MANHA = new Date("2026-09-26T14:00:00.000Z");

type RespostaDaRpc = { data: unknown; error: unknown };
/** (F5) orcamento_validade_do_envio com a chave desligada: o que o banco devolve no padrão (nada muda). */
const DESLIGADA: RespostaDaRpc = { data: { ok: true, fixou: false, motivo: "desligada" }, error: null };

function montarAmbiente(opcoes: {
  erroUpdate?: string;
  respostaEnvio?: () => Response;
  ordem?: Linha;
  rpc?: (fn: string, args: Record<string, unknown>) => RespostaDaRpc | undefined;
  settings?: Record<string, string>;
} = {}) {
  const rpcs: Array<{ fn: string; args: Record<string, unknown> }> = [];
  const sequencia: string[] = [];
  const updates: { tabela: string; campos: Record<string, unknown> }[] = [];
  const tabelas: Record<string, Linha[]> = {
    service_orders: [opcoes.ordem ?? ORC],
    clients: [CLIENTE],
    app_settings: [{ key: "company_name", value: "HBR" }],
    app_users: [{ id: "u1", full_name: "Gustavo Dono", role: "admin" }],
    receivables: [],
    payments: [],
    retorno_config: [{ validade_orcamento_dias: 7 }],
  };
  const consulta = (nome: string) => {
    let resultado = [...(tabelas[nome] ?? [])];
    let unico = false;
    const q: any = {
      select: (colunas?: string) => { sequencia.push(`select:${nome}:${colunas ?? ""}`); return q; },
      eq: (c: string, v: unknown) => { resultado = resultado.filter((l) => l[c] === v); return q; },
      neq: () => q,
      in: () => q,
      not: () => q,
      order: () => q,
      limit: () => q,
      single: () => { unico = true; return q; },
      maybeSingle: () => { unico = true; return q; },
      insert: () => ({ select: () => ({ single: () => Promise.resolve({ data: { id: "novo" }, error: null }) }), then: (ok: (v: unknown) => void) => ok({ data: null, error: null }) }),
      delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
      update: (campos: Record<string, unknown>) => ({
        eq: (_c: string, _v: unknown) => {
          sequencia.push(`update:${nome}`);
          updates.push({ tabela: nome, campos });
          return Promise.resolve(opcoes.erroUpdate ? { error: { message: opcoes.erroUpdate } } : { error: null });
        },
      }),
      then: (ok: (v: unknown) => void) => ok({ data: unico ? (resultado[0] ?? null) : resultado, error: null }),
    };
    return q;
  };
  const admin = {
    from: (t: string) => consulta(t),
    // (F5) a validade do envio pelo banco; sem resposta do teste, a chave desligada (o padrão)
    rpc: (fn: string, args: Record<string, unknown>) => {
      rpcs.push({ fn, args });
      sequencia.push(`rpc:${fn}`);
      return Promise.resolve(opcoes.rpc?.(fn, args) ?? DESLIGADA);
    },
    storage: {
      from: (_bucket: string) => ({
        upload: () => Promise.resolve({ data: {}, error: null }),
        createSignedUrl: (caminho: string) => Promise.resolve({ data: { signedUrl: `https://sb.example/${caminho}` }, error: null }),
        remove: () => Promise.resolve({ data: [], error: null }),
      }),
    },
  };
  const envios: any[] = [];
  const pdfValido = () => new Response(new Uint8Array([...new TextEncoder().encode("%PDF-1.7\n"), ...new Uint8Array(3000)]), { headers: { "content-type": "application/pdf" } });
  const fetchFalso = async (entrada: string | URL | Request, init?: RequestInit) => {
    const url = String(entrada instanceof Request ? entrada.url : entrada);
    if (url.endsWith("/api/pdf")) return pdfValido();
    if (url.endsWith("/functions/v1/whatsapp-send")) {
      sequencia.push("whatsapp-send");
      envios.push(JSON.parse(String(init?.body)));
      return (opcoes.respostaEnvio ?? (() => new Response(JSON.stringify({ success: true, messageId: "m1" }))))();
    }
    throw new Error(`fetch inesperado: ${url}`);
  };
  const ctx = {
    sb: admin, admin, userId: "u1", userRole: "admin" as const, jwt: "", appOrigin: "",
    settings: { app_public_url: "https://erp.example", quote_validity_days: "3", ...(opcoes.settings ?? {}) },
  };
  return { sequencia, updates, envios, fetchFalso, ctx, rpcs, admin };
}

async function executar(amb: ReturnType<typeof montarAmbiente>, args: Record<string, unknown>, ctxExtra: Record<string, unknown> = {}) {
  const original = globalThis.fetch;
  Deno.env.set("SUPABASE_URL", "https://sb.example");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "chave-de-servico");
  globalThis.fetch = amb.fetchFalso as typeof fetch;
  const relogio = new FakeTime(ONZE_DA_MANHA);
  try {
    return await tool.execute(args, { ...amb.ctx, ...ctxExtra } as any) as any;
  } finally {
    relogio.restore();
    globalThis.fetch = original;
  }
}

Deno.test("execute: o update roda antes de montarDocumentoDaOrdem, e so não é relido", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.updates.length, 1);
  assertEquals(amb.updates[0].campos.quote_validity_days, 7);
  const posUpdate = amb.sequencia.indexOf("update:service_orders");
  const posMontar = amb.sequencia.findIndex((s) => s.startsWith("select:service_orders:") && s.includes("clients(*)"));
  assert(posUpdate >= 0, "sem update");
  assert(posMontar > posUpdate, `montar veio antes do update: ${amb.sequencia.join(" > ")}`);
  const relidas = amb.sequencia.filter((s) => s.startsWith("select:service_orders:") && s.includes("cancellation_reason"));
  assertEquals(relidas.length, 1, "o so do envio não é relido");
});

Deno.test("execute: com dataDoCartao no contexto, grava essa data mesmo sem origem", async () => {
  const amb = montarAmbiente({ ordem: { ...ORC, origem: null } });
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" }, { validadeDoCartao: "2026-10-03" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.updates[0].campos.quote_validity_date, "2026-10-03");
});

Deno.test("execute: sem origem e sem data do cartão não mexe na validade", async () => {
  const amb = montarAmbiente({ ordem: { ...ORC, origem: null } });
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.updates.length, 0);
  assertEquals(r.aviso_validade, undefined);
});

Deno.test("execute: ok e deduplicated levam destino_chave8 (os 8 últimos dígitos do telefone real)", async () => {
  const amb = montarAmbiente();
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(r.destino_chave8, "99990123");
  const dup = montarAmbiente({ respostaEnvio: () => new Response(JSON.stringify({ success: true, deduplicated: true })) });
  const rDup = await executar(dup, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(rDup.ok, true, JSON.stringify(rDup));
  assertEquals(rDup.deduplicated, true);
  assertEquals(rDup.destino_chave8, "99990123");
});

Deno.test("execute: erro no update não derruba o envio e o aviso_validade vai nos dois resultados ok", async () => {
  const amb = montarAmbiente({ erroUpdate: "fora do ar" });
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertStringIncludes(r.aviso_validade, "Não consegui gravar a validade");
  assertEquals(amb.envios.length, 1, "o PDF saiu mesmo assim");
  const dup = montarAmbiente({ erroUpdate: "fora do ar", respostaEnvio: () => new Response(JSON.stringify({ success: true, deduplicated: true })) });
  const rDup = await executar(dup, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals(rDup.deduplicated, true);
  assertStringIncludes(rDup.aviso_validade, "Não consegui gravar a validade");
});

// ═══ Retorno F5 (P11.4 e P11.8): a validade do envio em todo envio de orçamento ═══════════════════════════════════
// sáb 26/09/2026, 11h em Brasília: hoje + 7 = sáb 03/10. O banco devolve O21 e O22 com o contexto do validador
// (_orcamento_legenda); aqui ele é montado do mesmo jeito que validador_aceite_test.ts o monta.

const O21 = (numero: string, validade: string) => `Segue o ${numero}, conforme solicitado. Ele vale até ${validade}. Qualquer dúvida, estamos à disposição.`;
const O22 = (validade: string) => `Ele vale até ${validade}.`;
function contextoDaLegenda(numero: string, validade: string) {
  return {
    audiencia: "cliente", datas_permitidas: [validade], horas_permitidas: [], nome_permitido: null, nomes_de_outros: [],
    os_permitidas: [numero], textos_do_cliente: [],
    trechos_do_modelo: ["Segue o ", ", conforme solicitado. Ele vale até ", ". Qualquer dúvida, estamos à disposição.", "Ele vale até ", "."],
    marcas: { tem_proposta: false, tem_topo: false, cliente_ouviu: false, conferida: false, aceite_registrado: false },
  };
}
const SABADO = "sábado (03/10)";
const COM_LEGENDA = { legenda: O21("ORÇ-00123", SABADO), linha: O22(SABADO), contexto: contextoDaLegenda("ORÇ-00123", SABADO) };
const PREVIA: RespostaDaRpc = { data: { ok: true, fixou: false, data: "2026-10-03", dias: 7, motivo: "previa", ...COM_LEGENDA }, error: null };
const FIXOU: RespostaDaRpc = { data: { ok: true, fixou: true, data: "2026-10-03", dias: 7, ...COM_LEGENDA }, error: null };
const JA_ENVIADO: RespostaDaRpc = { data: { ok: true, fixou: false, data: "2026-09-29", motivo: "ja_enviado", legenda: O21("ORÇ-00123", "terça (29/09)"), linha: O22("terça (29/09)"), contexto: contextoDaLegenda("ORÇ-00123", "terça (29/09)") }, error: null };
const VENCIDA: RespostaDaRpc = { data: { ok: true, fixou: false, data: "2026-09-20", motivo: "vencida" }, error: null };
const MUDOU: RespostaDaRpc = { data: { ok: true, fixou: false, data: "2026-10-04", antes: "2026-10-03", motivo: "mudou" }, error: null };
const SEM_ORIGEM = { ...ORC, origem: null };
/** As configurações do turno como as do banco (o resumo do *sim* lê app_settings; o envio, ctx.settings, que o turno lê de lá). */
const COMO_NO_BANCO = { company_name: "HBR" };
/** Responde a orcamento_validade_do_envio: a prévia (p_gravar falso) e o envio (p_gravar verdadeiro). */
const pelaGravacao = (previa: RespostaDaRpc, envio: RespostaDaRpc) => (fn: string, a: Record<string, unknown>) =>
  fn === "orcamento_validade_do_envio" ? (a.p_gravar ? envio : previa) : undefined;

Deno.test("F5 validadeDoEnvio: chama a função do banco e passa a legenda e a linha pelo validador", async () => {
  const amb = montarAmbiente({ rpc: pelaGravacao(PREVIA, FIXOU) });
  const v = await validadeDoEnvio(amb.admin, { id: "os-1" }, { agora: ONZE_DA_MANHA, gravar: true, esperada: "2026-10-03" });
  assertEquals(amb.rpcs, [{ fn: "orcamento_validade_do_envio", args: { p_os: "os-1", p_agora: ONZE_DA_MANHA.toISOString(), p_gravar: true, p_esperada: "2026-10-03" } }]);
  assertEquals(v, { data: "2026-10-03", motivo: "fixou", legenda: O21("ORÇ-00123", SABADO), linha: O22(SABADO) });
  const p = await validadeDoEnvio(amb.admin, { id: "os-1" }, { agora: ONZE_DA_MANHA, gravar: false });
  assertEquals(p.motivo, "previa");
  assertEquals(amb.rpcs[1].args.p_esperada, null);
});

Deno.test("F5 validadeDoEnvio: reprovada no validador → sem legenda nem linha, com aviso; erro → a frase do cadastro; ausente → desligada", async () => {
  const reprovada = { data: { ...PREVIA.data as Record<string, unknown>, legenda: "Segue o ORÇ-00999, conforme solicitado. Ele vale até sábado (03/10). Qualquer dúvida, estamos à disposição." }, error: null };
  const amb = montarAmbiente({ rpc: () => reprovada });
  const v = await validadeDoEnvio(amb.admin, { id: "os-1" }, { agora: ONZE_DA_MANHA, gravar: false });
  assertEquals(v, { data: "2026-10-03", motivo: "previa", legenda: null, linha: null, aviso: "A linha da validade não entrou na legenda: confira na tela." });
  for (const resposta of [{ data: null, error: { code: "57014", message: "tempo esgotado" } }, { data: { ok: false, motivo: "erro" }, error: null }]) {
    const e = await validadeDoEnvio(montarAmbiente({ rpc: () => resposta }).admin, { id: "os-1" }, { agora: ONZE_DA_MANHA, gravar: true });
    assertEquals(e, { data: null, motivo: "erro", legenda: null, linha: null, aviso: "Não consegui fixar a validade do envio; o PDF sai com a validade do cadastro." });
  }
  // a exceção também (nunca lança)
  const lanca = await validadeDoEnvio({ rpc: () => Promise.reject(new Error("rede")) }, { id: "os-1" }, { agora: ONZE_DA_MANHA, gravar: true });
  assertEquals(lanca.motivo, "erro");
  // a função ainda não publicada: como a chave desligada, sem aviso
  const ausente = await validadeDoEnvio(montarAmbiente({ rpc: () => ({ data: null, error: { code: "PGRST202" } }) }).admin, { id: "os-1" }, { agora: ONZE_DA_MANHA, gravar: true });
  assertEquals(ausente, { data: null, motivo: "desligada", legenda: null, linha: null });
  // vencida nunca traz legenda nem linha
  const venc = await validadeDoEnvio(montarAmbiente({ rpc: () => VENCIDA }).admin, { id: "os-1" }, { agora: ONZE_DA_MANHA, gravar: true });
  assertEquals(venc, { data: "2026-09-20", motivo: "vencida", legenda: null, linha: null });
});

Deno.test("F5 fixarValidadeDoEnvio: o ramo novo (sem origem e sem data do cartão) só com orçamento; desligada = {} como hoje", async () => {
  const ligada = montarAmbiente({ rpc: pelaGravacao(PREVIA, FIXOU) });
  const r = await fixarValidadeDoEnvio(ligada.admin, { id: "os-1", status: "draft", quote_status: "draft", origem: null }, undefined, ONZE_DA_MANHA, { esperada: "2026-10-03" });
  assertEquals(r, { doEnvio: { data: "2026-10-03", motivo: "fixou", legenda: O21("ORÇ-00123", SABADO), linha: O22(SABADO) } });
  assertEquals(ligada.rpcs[0].args.p_gravar, true);
  assertEquals(ligada.rpcs[0].args.p_esperada, "2026-10-03");
  const desligada = montarAmbiente();
  assertEquals(await fixarValidadeDoEnvio(desligada.admin, { id: "os-1", status: "draft", quote_status: "draft", origem: null }, undefined, ONZE_DA_MANHA), {});
  assertEquals(desligada.updates.length, 0);
  // OS (não orçamento): nem pergunta ao banco — a O21 diria "Segue o OS-…"
  const os = montarAmbiente({ rpc: pelaGravacao(PREVIA, FIXOU) });
  assertEquals(await fixarValidadeDoEnvio(os.admin, { id: "os-1", status: "in_progress", quote_status: null, origem: null }, undefined, ONZE_DA_MANHA), {});
  assertEquals(os.rpcs.length, 0);
  // erro: o aviso sai como aviso_validade
  const erro = montarAmbiente({ rpc: () => ({ data: null, error: { code: "57014" } }) });
  const re = await fixarValidadeDoEnvio(erro.admin, { id: "os-1", status: "draft", quote_status: "draft", origem: null }, undefined, ONZE_DA_MANHA);
  assertEquals(re.aviso_validade, "Não consegui fixar a validade do envio; o PDF sai com a validade do cadastro.");
  assertEquals(re.doEnvio?.motivo, "erro");
});

Deno.test("F5 fixarValidadeDoEnvio: ao parceiro nunca fixa hoje + 7; soRamoNovo não roda o ramo da F3", async () => {
  const parceiro = montarAmbiente({ rpc: pelaGravacao(PREVIA, FIXOU) });
  assertEquals(await fixarValidadeDoEnvio(parceiro.admin, { id: "os-1", status: "draft", quote_status: "draft", origem: null }, undefined, ONZE_DA_MANHA, { aoParceiro: true }), {});
  assertEquals(parceiro.rpcs.length, 0, "não chama orcamento_validade_do_envio");
  assertEquals(parceiro.updates.length, 0, "não muda quote_validity_date");
  // com origem, ao parceiro, o ramo da F3 de sempre
  const f3 = montarAmbiente();
  await fixarValidadeDoEnvio(f3.admin, SO_RASCUNHO, undefined, AS_23H30_BRT, { aoParceiro: true });
  assertEquals(f3.updates[0].campos, { quote_validity_days: 7, quote_validity_date: "2026-12-14" });
  // soRamoNovo com origem: nada (o link e o resumo nunca rodaram o ramo da F3)
  const so = montarAmbiente({ rpc: pelaGravacao(PREVIA, FIXOU) });
  assertEquals(await fixarValidadeDoEnvio(so.admin, SO_RASCUNHO, undefined, AS_23H30_BRT, { soRamoNovo: true }), {});
  assertEquals([so.updates.length, so.rpcs.length], [0, 0]);
});

Deno.test("F5 legendaDoPdf: sem o 3º argumento, byte a byte a de hoje", () => {
  const so = { service_order_number: "ORÇ-00123", status: "draft" };
  assertEquals(legendaDoPdf({}, so), "Segue o ORÇ-00123, conforme solicitado. Qualquer dúvida, estamos à disposição.");
  assertEquals(legendaDoPdf({ custom_message: " Oi, Ana! " }, so), "Oi, Ana!");
  assertEquals(legendaDoPdf({ sem_legenda: true }, so), "");
  assertEquals(legendaDoPdf({}, { service_order_number: "OS-00087", status: "in_progress" }), "Segue a OS-00087. Qualquer dúvida, estamos à disposição.");
  assertEquals(legendaDoPdf({}, so, null), legendaDoPdf({}, so));
  assertEquals(legendaDoPdf({}, so, undefined), legendaDoPdf({}, so));
});

Deno.test("F5 legendaDoPdf: a O21 sem frase; a frase do dono + a O22 numa 2ª linha (sem o dd/mm na frase); sem legenda, nada", () => {
  const so = { service_order_number: "ORÇ-00123", status: "draft" };
  const v: ValidadeDoEnvio = { data: "2026-10-03", motivo: "previa", legenda: O21("ORÇ-00123", SABADO), linha: O22(SABADO) };
  assertEquals(legendaDoPdf({}, so, v), O21("ORÇ-00123", SABADO));
  assertEquals(legendaDoPdf({ custom_message: "Oi, Ana! Segue o orçamento." }, so, v), `Oi, Ana! Segue o orçamento.\n${O22(SABADO)}`);
  assertEquals(legendaDoPdf({ custom_message: "Oi, Ana! Vale até 03/10." }, so, v), "Oi, Ana! Vale até 03/10.");
  assertEquals(legendaDoPdf({ sem_legenda: true }, so, v), "");
  // vencida (sem legenda nem linha) e legenda nula: a de hoje
  assertEquals(legendaDoPdf({}, so, { data: "2026-09-20", motivo: "vencida", legenda: null, linha: null }), legendaDoPdf({}, so));
  assertEquals(legendaDoPdf({}, so, { ...v, legenda: null, linha: null }), legendaDoPdf({}, so));
  assertEquals(legendaDoPdf({ custom_message: "Oi" }, so, { ...v, linha: null }), "Oi");
});

Deno.test("F5 opcoesDoResumo: vencida → sem validade; prévia, fixada e já enviada → a data; o resto → o resumo de hoje", () => {
  const com = (motivo: string, data: string | null = "2026-10-03"): ValidadeDoEnvio => ({ data, motivo, legenda: null, linha: null });
  assertEquals(opcoesDoResumo(com("vencida", "2026-09-20")), { semValidade: true });
  for (const m of ["previa", "fixou", "ja_enviado"]) assertEquals(opcoesDoResumo(com(m)), { validadeAte: "2026-10-03" }, m);
  for (const m of ["desligada", "funil", "cargo", "erro"]) assertEquals(opcoesDoResumo(com(m, null)), undefined, m);
  assertEquals(opcoesDoResumo(null), undefined);
  assertEquals(opcoesDoResumo(undefined), undefined);
});

Deno.test("F5 montarResumoDeValores: validadeAte diz 'válida até' mesmo com dias no cadastro; semValidade tira a linha e vence a data", async () => {
  const amb = montarAmbiente({ ordem: SEM_ORIGEM });
  const hoje = await montarResumoDeValores(amb.admin, SEM_ORIGEM, amb.ctx.settings);
  assert(hoje.ok);
  assertStringIncludes(hoje.texto, "⏳ Proposta válida por 3 dias.");
  const ate = await montarResumoDeValores(amb.admin, SEM_ORIGEM, amb.ctx.settings, { validadeAte: "2026-10-03" });
  assert(ate.ok);
  assertStringIncludes(ate.texto, "⏳ Proposta válida até 03/10/2026.");
  assert(!ate.texto.includes("válida por"));
  assertEquals(ate.texto.replace("⏳ Proposta válida até 03/10/2026.", "⏳ Proposta válida por 3 dias."), hoje.texto, "só a linha muda");
  const sem = await montarResumoDeValores(amb.admin, SEM_ORIGEM, amb.ctx.settings, { semValidade: true, validadeAte: "2026-10-03" });
  assert(sem.ok);
  assert(!sem.texto.includes("⏳ Proposta válida"), sem.texto);
  assertEquals(await montarResumoDeValores(amb.admin, SEM_ORIGEM, amb.ctx.settings, undefined), hoje);
});

Deno.test("F5 execute pdf: a O21 na legenda; a frase do dono + a O22; o resultado nunca leva doEnvio nem o contexto", async () => {
  const amb = montarAmbiente({ ordem: SEM_ORIGEM, rpc: pelaGravacao(PREVIA, FIXOU) });
  const r = await executar(amb, { service_order_id: ORC.id, formato: "pdf", _retrato: { validade: "2026-10-03" } });
  assertEquals(r.ok, true, JSON.stringify(r));
  assertEquals(amb.envios[0].document_caption, O21("ORÇ-00123", SABADO));
  assertEquals(amb.rpcs.map((c) => c.args.p_gravar), [true]);
  assertEquals(amb.rpcs[0].args.p_esperada, "2026-10-03");
  assert(!("doEnvio" in r) && !JSON.stringify(r).includes("trechos_do_modelo"), JSON.stringify(r));
  const frase = montarAmbiente({ ordem: SEM_ORIGEM, rpc: pelaGravacao(PREVIA, FIXOU) });
  await executar(frase, { service_order_id: ORC.id, formato: "pdf", custom_message: "Oi! Segue o orçamento." });
  assertEquals(frase.envios[0].document_caption, `Oi! Segue o orçamento.\n${O22(SABADO)}`);
  // pdf_e_link: a O22 logo depois da abertura
  const link = montarAmbiente({ ordem: SEM_ORIGEM, rpc: pelaGravacao(PREVIA, FIXOU) });
  await executar(link, { service_order_id: ORC.id, formato: "pdf_e_link" });
  const legenda = String(link.envios[0].document_caption);
  assert(legenda.startsWith(`Olá Cliente, segue o orçamento em PDF.\n${O22(SABADO)}\n\nOrçamento ORÇ-00123`), legenda);
});

Deno.test("F5 execute: com a chave desligada, o envio é o de hoje, byte a byte, nos quatro formatos", async () => {
  for (const formato of ["pdf", "pdf_e_link", "link", "resumo"]) {
    const desligada = montarAmbiente({ ordem: SEM_ORIGEM });
    const r = await executar(desligada, { service_order_id: ORC.id, formato });
    assertEquals(r.ok, true, `${formato}: ${JSON.stringify(r)}`);
    assertEquals(r.aviso_validade, undefined, formato);
    const env = desligada.envios[0];
    if (formato === "pdf") assertEquals(env.document_caption, "Segue o ORÇ-00123, conforme solicitado. Qualquer dúvida, estamos à disposição.");
    if (formato === "resumo") assertStringIncludes(env.message, "⏳ Proposta válida por 3 dias.");
    assertEquals("orcamento_via" in env, false, formato);
  }
});

Deno.test("F5 execute: o sim de outro dia — 'mudou' não envia nada, nos três caminhos, e diz de quanto para quanto", async () => {
  for (const formato of ["pdf", "link", "resumo"]) {
    const amb = montarAmbiente({ ordem: SEM_ORIGEM, rpc: pelaGravacao(PREVIA, MUDOU) });
    const r = await executar(amb, { service_order_id: ORC.id, formato, _retrato: { validade: "2026-10-03" } });
    assertEquals(r.error, "Desde o pedido, a validade do envio passou de 03/10 para 04/10 (o dia virou). Nada foi enviado ao cliente — peça de novo para confirmar com a data de agora.", formato);
    assertEquals(r.nada_enviado, true, formato);
    assertEquals(amb.envios.length, 0, formato);
    assertEquals(amb.sequencia.some((s) => s.startsWith("insert")), false, formato);
  }
});

Deno.test("F5 execute: link e resumo fixam a data (só o ramo novo); com origem não chamam a função nem mudam a validade", async () => {
  const link = montarAmbiente({ ordem: SEM_ORIGEM, rpc: pelaGravacao(PREVIA, FIXOU) });
  const rl = await executar(link, { service_order_id: ORC.id, formato: "link" });
  assertEquals(rl.ok, true, JSON.stringify(rl));
  assertEquals(link.rpcs.map((c) => c.args.p_gravar), [true]);
  assert(!String(link.envios[0].message).includes("vale até"), "no link, nenhuma linha (o portal mostra a data)");
  for (const formato of ["link", "resumo"]) {
    const comOrigem = montarAmbiente({ rpc: pelaGravacao(PREVIA, FIXOU) });
    const r = await executar(comOrigem, { service_order_id: ORC.id, formato });
    assertEquals(r.ok, true, JSON.stringify(r));
    assertEquals(comOrigem.rpcs.length, 0, formato);
    assertEquals(comOrigem.updates.length, 0, formato);
  }
});

Deno.test("F5 resumo: o 1º envio com a data do envio, uma validade só; o resumo do sim é, byte a byte, o texto que o envio manda", async () => {
  const amb = montarAmbiente({ ordem: SEM_ORIGEM, rpc: pelaGravacao(PREVIA, FIXOU), settings: COMO_NO_BANCO });
  const doSim = await comRelogio(() => resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id, formato: "resumo" }, ONZE_DA_MANHA));
  const r = await executar(amb, { service_order_id: ORC.id, formato: "resumo" });
  assertEquals(r.ok, true, JSON.stringify(r));
  const enviado = String(amb.envios[0].message);
  assertStringIncludes(enviado, "⏳ Proposta válida até 03/10/2026.");
  assert(!enviado.includes("válida por"), enviado);
  assertEquals(enviado.split("⏳").length, 2, "uma validade só");
  assertStringIncludes(doSim!, `\n${enviado}\n`);
  assert(!doSim!.includes("A validade acabou em"), doSim!);
  // o resumo do sim chama a função sem gravar
  assertEquals(amb.rpcs[0].args.p_gravar, false);
});

Deno.test("F5 resumo: reenvio com a data do 1º envio; vencida sem a linha nem a frase antiga, e a frase da F5 uma vez só", async () => {
  const re = montarAmbiente({ ordem: { ...SEM_ORIGEM, quote_status: "sent" }, rpc: () => JA_ENVIADO, settings: COMO_NO_BANCO });
  const doSim = await comRelogio(() => resumirEnvioAoCliente(re.admin, { service_order_id: ORC.id, formato: "resumo" }, ONZE_DA_MANHA));
  await executar(re, { service_order_id: ORC.id, formato: "resumo" });
  assertStringIncludes(String(re.envios[0].message), "⏳ Proposta válida até 29/09/2026.");
  assertStringIncludes(doSim!, `\n${re.envios[0].message}\n`);
  assertStringIncludes(doSim!, "a data do 1º envio");
  const venc = montarAmbiente({ ordem: SEM_ORIGEM, rpc: () => VENCIDA, settings: COMO_NO_BANCO });
  const simVenc = await comRelogio(() => resumirEnvioAoCliente(venc.admin, { service_order_id: ORC.id, formato: "resumo" }, ONZE_DA_MANHA));
  await executar(venc, { service_order_id: ORC.id, formato: "resumo" });
  assert(!String(venc.envios[0].message).includes("⏳ Proposta válida"), venc.envios[0].message);
  assert(!simVenc!.includes("⏳ Proposta válida"), simVenc!);
  assert(!simVenc!.includes("A validade acabou em"), simVenc!);
  assertEquals(simVenc!.split("O ORÇ-00123 venceu em 20/09: o PDF sai com essa data. Para renovar, mude a validade na tela antes de mandar.").length, 2);
});

Deno.test("F5 resumo do sim no pdf: a legenda exata do envio do mesmo dia, e 'a data conta do envio'", async () => {
  const amb = montarAmbiente({ ordem: SEM_ORIGEM, rpc: pelaGravacao(PREVIA, FIXOU) });
  const doSim = await comRelogio(() => resumirEnvioAoCliente(amb.admin, { service_order_id: ORC.id, formato: "pdf" }, ONZE_DA_MANHA));
  await executar(amb, { service_order_id: ORC.id, formato: "pdf" });
  assertStringIncludes(doSim!, `Legenda: "${amb.envios[0].document_caption}"`);
  assertStringIncludes(doSim!, "a data conta do envio: se você confirmar noutro dia, eu peço de novo");
  // com a chave desligada e a validade do cadastro vencida: o aviso de sempre
  const desligada = montarAmbiente({ ordem: { ...SEM_ORIGEM, quote_validity_days: 1, created_at: "2026-09-01T12:00:00.000Z" } });
  const simAntigo = await comRelogio(() => resumirEnvioAoCliente(desligada.admin, { service_order_id: ORC.id, formato: "pdf" }, ONZE_DA_MANHA));
  assertStringIncludes(simAntigo!, "A validade acabou em");
});

Deno.test("F5 retratoDoEnvio: grava a validade da prévia (ou o motivo); com a chave desligada, o retrato de antes", async () => {
  const amb = montarAmbiente({ ordem: SEM_ORIGEM, rpc: pelaGravacao(PREVIA, FIXOU) });
  const r = await retratoDoEnvio(amb.admin, { service_order_id: ORC.id });
  assertEquals(r?.validade, "2026-10-03");
  assertEquals(amb.rpcs[0].args.p_gravar, false);
  const venc = await retratoDoEnvio(montarAmbiente({ ordem: SEM_ORIGEM, rpc: () => ({ data: { ok: true, fixou: false, motivo: "funil" }, error: null }) }).admin, { service_order_id: ORC.id });
  assertEquals([venc?.validade, venc?.validade_motivo], [undefined, "funil"]);
  const desligada = await retratoDoEnvio(montarAmbiente({ ordem: SEM_ORIGEM }).admin, { service_order_id: ORC.id });
  assertEquals(Object.keys(desligada ?? {}).sort(), ["telefone", "total"]);
});

Deno.test("F5 P11.9: o envio pelo cartão leva orcamento_via 'cartao' ao whatsapp-send; o do assistente, não", async () => {
  const cartao = montarAmbiente({ ordem: SEM_ORIGEM });
  await executar(cartao, { service_order_id: ORC.id, formato: "pdf" }, { envioPeloCartao: true });
  assertEquals(cartao.envios[0].orcamento_via, "cartao");
  assertEquals(cartao.envios[0].origem, "assistente");
  const livre = montarAmbiente({ ordem: SEM_ORIGEM });
  await executar(livre, { service_order_id: ORC.id, formato: "pdf" });
  assertEquals("orcamento_via" in livre.envios[0], false);
});

/** O relógio do resumo do sim (11h de sábado em Brasília). */
async function comRelogio<T>(f: () => Promise<T>): Promise<T> {
  const relogio = new FakeTime(ONZE_DA_MANHA);
  try {
    return await f();
  } finally {
    relogio.restore();
  }
}
