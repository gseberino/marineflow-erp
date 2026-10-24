// O status da OS só pela PORTA (Agenda de Produção, Fase 2, P4 — 24/10/2026; Fase 3, P3 — 24/10/2026).
//
// Até a Fase 2 sete caminhos escreviam service_orders.status cada um com a sua regra: a tela "Agendar OS" (e o botão da
// R1, que abre a mesma tela), a aprovação com PIN (approve_quote_full), o schedule_service_order e o
// update_service_order_status do assistente, o check-in e as duas OC criadas a partir da OS. Saíam dali a OC que regredia
// a OS EM ANDAMENTO para "aguardando peças" (NOVO-agenda-10) e a OS aguardando peças que virava "agendada" sem a peça.
// Agora todos passam pela porta única do banco (os_transicionar_status), que decide; com a agenda automática ligada, a
// data é da agenda (agenda_marcar_os, ou o rascunho agenda_rascunho_marcar do assistente).
//
// Fase 3 (P3): a porta passou a concluir (a saída e as cobranças da condição na mesma transação), faturar e converter o
// orçamento (o número troca só o prefixo). Entram na cobrança deste teste: concluída e faturada (STATUS_DA_PORTA), a
// conversão (service_order_number / converted_to_os_at num UPDATE de service_orders) e os caminhos que concluíam por
// fora — a mudança genérica de status da tela (useUpdateServiceOrderStatus: StatusQuickChange, kanbans, listas,
// formulário), a assinatura do cliente (submit-signature) e o assistente (a conversão e o faturar).
//
// Este teste lê os arquivos como texto e cobra:
//   1. nos arquivos dos caminhos, nenhum status da porta dentro de um UPDATE de service_orders (nem literal, nem por
//      variável, nem por "update.status = …"), fora da exceção conhecida do próprio arquivo;
//   2. cada caminho chama a porta (ou o marcar da agenda, onde é ela que manda; ou o hook/o módulo que a chama);
//   3. em todo o código (src e supabase/functions, sem os testes), quem escreve service_orders.status por fora da porta
//      — e quem converte o orçamento por fora dela — é só a lista conhecida, e ela é CONGELADA: se um arquivo da lista
//      deixar de escrever, a exceção tem de sair (como em migrations-versao-unica.test.ts);
//   4. a paridade de statusAoAgendar (a leitura da porta que a tela usa) com a porta, status a status: a lista marcada
//      em supabase/tests/agenda_fase2_rascunho.sql é provada contra a porta na bancada; aqui, contra statusAoAgendar.
import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative, sep } from "node:path";
import { STATUS_OS, statusAoAgendar } from "../../supabase/functions/_shared/service-order-status";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const ler = (p: string) => readFileSync(join(RAIZ, p), "utf8").replace(/\r\n/g, "\n");

/** Os status que a porta decide: os de agenda (Fase 2) e, desde a Fase 3, concluir e faturar. Cancelar tem caminho
 *  próprio (cancel_service_order, com o estorno); voltar a orçamento a porta recusa. */
const STATUS_DA_PORTA = ["open", "approved", "scheduled", "in_progress", "awaiting_parts", "awaiting_client", "completed", "invoiced"];

/** Os arquivos dos caminhos (spec-fase2 §10, spec-fase3 §6) e o que cada um tem de chamar. AgendaPage e TaskCard chegam
 *  pelo hook da agenda; os chamadores da mudança genérica de status, pelo useUpdateServiceOrderStatus. */
const CAMINHOS: Record<string, string[]> = {
  "src/hooks/use-agenda.ts": ["os_transicionar_status", "agenda_marcar_os"],
  "src/pages/AgendaPage.tsx": [],
  "src/components/agenda/TaskCard.tsx": [],
  "supabase/functions/_shared/ai/tools/flow-macros.ts": ["os_transicionar_status", "agenda_marcar_os"],
  "supabase/functions/_shared/ai/tools/service-orders.ts": ["os_transicionar_status", "agenda_rascunho_marcar"],
  "supabase/functions/_shared/ai/tools/field-ops.ts": ["os_transicionar_status"],
  "supabase/functions/_shared/ai/tools/purchasing.ts": ["os_transicionar_status"],
  "src/hooks/use-purchase-orders.ts": ["os_transicionar_status"],
  // Fase 3 (P3)
  "src/hooks/use-service-orders.ts": ["os_transicionar_status", "argumentosDaPortaCompleta"],
  "src/components/StatusQuickChange.tsx": ["useUpdateServiceOrderStatus", "avisarSeNaoMudou"],
  "src/pages/CRMKanbanPage.tsx": ["useUpdateServiceOrderStatus", "avisarSeNaoMudou"],
  "src/v2/pages/CRMKanbanV2.tsx": ["useUpdateServiceOrderStatus", "avisarSeNaoMudou"],
  "src/pages/QuoteList.tsx": ["useUpdateServiceOrderStatus", "avisarSeNaoMudou"],
  "src/v2/pages/OrdersListV2.tsx": ["useUpdateServiceOrderStatus", "avisarSeNaoMudou"],
  "supabase/functions/submit-signature/index.ts": ["statusDepoisDaAssinatura"],
  "supabase/functions/submit-signature/status-da-assinatura.ts": ["os_transicionar_status", "argumentosDaPortaCompleta"],
};

/**
 * Quem ainda escreve service_orders.status por fora da porta, e por quê: o literal ('completed') ou o nome da variável.
 * CONGELADA: entra arquivo novo = falha; arquivo que deixou de escrever = falha (a exceção tem de sair).
 */
const LISTA_CONHECIDA: Record<string, string> = {
  // reopenServiceOrder (o "Reabrir" da OS faturada/concluída): o DESFATURAR do financeiro — estorna os pagamentos, reabre
  // as contas e volta a OS a concluída. A porta recusa reabrir a faturada de propósito ("reabrir é pelo financeiro").
  "src/lib/cascade-updates.ts": "'completed'",
  // reopen_service_order do assistente: o mesmo desfaturar (a spec da Fase 3 só listava o da tela; o do assistente faz o
  // mesmo UPDATE desde antes da agenda).
  "supabase/functions/_shared/ai/tools/service-orders.ts": "'completed'",
  // PLANO B (revisões da Fase 2 e Fase 3, P3): só quando a porta ainda não existe no banco (o código publicado antes da
  // migration), a tela, a OC, o check-in, a mudança genérica de status e a assinatura voltam ao caminho de antes. SAI
  // quando as Fases 2 e 3 estiverem aplicadas.
  "supabase/functions/_shared/porta-ausente.ts": "mudanca,para",
};

/** Quem ainda converte o orçamento (número ou converted_to_os_at num UPDATE de service_orders) por fora da porta.
 *  CONGELADA como a de cima. (O sinal pago converte no banco, handle_quote_deposit_payment, com o mesmo prefixo.) */
const CONVERSAO_CONHECIDA: Record<string, string> = {
  // PLANO B: a conversão do caminho de antes (o número troca só o prefixo, como a porta). SAI com a Fase 3 aplicada.
  "supabase/functions/_shared/porta-ausente.ts": "mudanca",
};

const FROM = String.raw`\.from\(\s*['"]service_orders['"]\s*(?:as\s+\w+\s*)?\)`;
/** Até 400 caracteres depois do .from('service_orders'), sem atravessar outro .from(…). */
const JANELA = String.raw`(?:(?!\.from\()[\s\S]){0,400}?`;

type Escrita = { tipo: "literal" | "variavel" | "atribuicao"; valor: string };

/** A variável X vai a um UPDATE de service_orders (.from('service_orders')….update(X)? */
const vaiAoUpdate = (texto: string, x: string) =>
  new RegExp(FROM + JANELA + String.raw`\.update\(\s*` + x + String.raw`\b`).test(texto);

/** As escritas de status em service_orders de um texto: o valor de cada uma (o literal, ou o nome da variável). */
function escritasDeStatus(texto: string): Escrita[] {
  const out: Escrita[] = [];
  // .from('service_orders')….update({ … status: X … })
  const direto = new RegExp(FROM + JANELA + String.raw`\.update\(\s*\{([^}]*)\}`, "g");
  for (const m of texto.matchAll(direto)) {
    const s = /\bstatus\s*:\s*([^,\n}]+)/.exec(m[1]);
    if (!s) continue;
    const valor = s[1].trim();
    const literal = /^['"](\w+)['"]$/.exec(valor);
    out.push(literal ? { tipo: "literal", valor: literal[1] } : { tipo: "variavel", valor });
  }
  // const X = { status, … } (ou status: …) … .from('service_orders')….update(X
  for (const m of texto.matchAll(/\b(?:const|let)\s+(\w+)\b[^=;\n]*=\s*\{[^}]*\bstatus\b[^}]*\}/g)) {
    if (vaiAoUpdate(texto, m[1])) out.push({ tipo: "variavel", valor: m[1] });
  }
  // const v = …; … .update({ status: v }) já sai acima como variável; e o jeito antigo: update.status = …
  for (const m of texto.matchAll(/\b(update|updates|patch|updatePayload)\.status\s*=/g)) out.push({ tipo: "atribuicao", valor: m[1] });
  return out;
}

/** (Fase 3) Quem converte num UPDATE de service_orders: "objeto" (o literal do .update({…})) ou o nome da variável. */
function conversoes(texto: string): string[] {
  const out: string[] = [];
  const CAMPO = /\b(?:service_order_number|converted_to_os_at)\b/;
  const direto = new RegExp(FROM + JANELA + String.raw`\.update\(\s*\{([^}]*)\}`, "g");
  for (const m of texto.matchAll(direto)) if (CAMPO.test(m[1])) out.push("objeto");
  for (const m of texto.matchAll(/\b(?:const|let)\s+(\w+)\b[^=;\n]*=\s*\{([^}]*)\}/g)) {
    if (CAMPO.test(m[2]) && vaiAoUpdate(texto, m[1])) out.push(m[1]);
  }
  for (const m of texto.matchAll(/\b(\w+)\.(?:service_order_number|converted_to_os_at)\s*=(?!=)/g)) {
    if (vaiAoUpdate(texto, m[1])) out.push(m[1]);
  }
  return [...new Set(out)].sort();
}

/** As escritas que ficam fora da porta: o literal de um status da porta ('completed') e toda variável. */
const foraDaPorta = (es: Escrita[]) => [...new Set(es
  .filter((e) => e.tipo === "variavel" || (e.tipo === "literal" && STATUS_DA_PORTA.includes(e.valor)))
  .map((e) => (e.tipo === "literal" ? `'${e.valor}'` : e.valor)))].sort();

function* arquivosDoCodigo(dir: string): Generator<string> {
  for (const nome of readdirSync(join(RAIZ, dir))) {
    if (nome === "node_modules" || nome.startsWith(".")) continue;
    const rel = `${dir}/${nome}`;
    if (statSync(join(RAIZ, rel)).isDirectory()) {
      yield* arquivosDoCodigo(rel);
    } else if (/\.(ts|tsx)$/.test(nome) && !/(\.test\.|_test\.ts$|\.smoke\.)/.test(nome)) {
      yield rel;
    }
  }
}

describe("porta única de status — os caminhos (Fase 2, P4; Fase 3, P3)", () => {
  it.each(Object.keys(CAMINHOS))("%s: nenhum status da porta num UPDATE de service_orders (fora da exceção conhecida)", (arquivo) => {
    const texto = ler(arquivo);
    const conhecidas = (LISTA_CONHECIDA[arquivo] ?? "").split(",").filter(Boolean);
    const ruins = foraDaPorta(escritasDeStatus(texto)).filter((v) => !conhecidas.includes(v));
    expect(ruins, "status só pela porta (os_transicionar_status)").toEqual([]);
    expect(escritasDeStatus(texto).filter((e) => e.tipo === "atribuicao"), "status só pela porta (update.status = …)").toEqual([]);
    // e nenhum literal de status de agenda num objeto "status: 'scheduled'" do arquivo
    const literais = [...texto.matchAll(/\bstatus\s*:\s*['"](scheduled|in_progress|awaiting_parts|awaiting_client)['"]/g)].map((m) => m[0]);
    expect(literais, "status de agenda só pela porta (os_transicionar_status)").toEqual([]);
    // (Fase 3) e nenhuma conversão do orçamento por fora da porta
    expect(conversoes(texto), "a conversão ORÇ → OS só pela porta").toEqual((CONVERSAO_CONHECIDA[arquivo] ?? "").split(",").filter(Boolean));
  });

  it.each(Object.entries(CAMINHOS).filter(([, t]) => t.length))("%s chama a porta (%j)", (arquivo, tokens) => {
    const texto = ler(arquivo);
    for (const t of tokens) expect(texto.includes(t), `${arquivo} devia chamar ${t}`).toBe(true);
  });
});

describe("porta única de status — o resto do código", () => {
  const escritas = new Map<string, Escrita[]>();
  const conversoesPorArquivo: Record<string, string> = {};
  for (const dir of ["src", "supabase/functions"]) {
    for (const arquivo of arquivosDoCodigo(dir)) {
      const nome = relative(RAIZ, join(RAIZ, arquivo)).split(sep).join("/");
      const texto = ler(arquivo);
      const e = escritasDeStatus(texto).filter((x) => x.tipo !== "atribuicao");
      if (e.length) escritas.set(nome, e);
      const c = conversoes(texto);
      if (c.length) conversoesPorArquivo[nome] = c.join(",");
    }
  }

  it("ninguém escreve status de agenda (literal) em service_orders por fora da porta", () => {
    const ruins = [...escritas.entries()].flatMap(([arquivo, es]) => es
      .filter((e) => e.tipo === "literal" && STATUS_DA_PORTA.includes(e.valor) && e.valor !== "completed")
      .map((e) => `${arquivo}: ${e.valor}`));
    expect(ruins, "status da porta só por ela (os_transicionar_status)").toEqual([]);
  });

  it("quem escreve status por fora da porta (literal da porta ou variável) é só a lista conhecida, e ela é congelada", () => {
    const fora = Object.fromEntries([...escritas.entries()]
      .map(([arquivo, es]) => [arquivo, foraDaPorta(es).join(",")] as const)
      .filter(([, v]) => v));
    expect(fora, "status só pela porta (os_transicionar_status)").toEqual(LISTA_CONHECIDA);
  });

  it("(Fase 3) quem converte o orçamento por fora da porta é só a lista conhecida, e ela é congelada", () => {
    expect(conversoesPorArquivo, "a conversão ORÇ → OS só pela porta").toEqual(CONVERSAO_CONHECIDA);
  });

  it("(Fase 3) a lista conhecida só tem a volta a concluída (o desfaturar do financeiro) e o plano B", () => {
    for (const [arquivo, valores] of Object.entries(LISTA_CONHECIDA)) {
      if (arquivo.endsWith("porta-ausente.ts")) continue;
      expect(valores, `${arquivo}: só o desfaturar (volta a concluída) fica fora da porta`).toBe("'completed'");
      expect(ler(arquivo), `${arquivo}: o UPDATE de volta a concluída é o da reabertura (reopen_reason)`).toMatch(/reopen_reason/);
    }
  });
});

describe("paridade de statusAoAgendar com a porta (via tela_agendar, fora da agenda automática)", () => {
  // A lista que a bancada prova contra a porta (supabase/tests/agenda_fase2_rascunho.sql, teste T1).
  const sql = ler("supabase/tests/agenda_fase2_rascunho.sql");
  const bloco = /-- PARIDADE statusAoAgendar \(início\)([\s\S]*?)-- PARIDADE statusAoAgendar \(fim\)/.exec(sql)?.[1] ?? "";
  const tabela = Object.fromEntries([...bloco.matchAll(/\('(\w+)',\s*'(\w+)'\)/g)].map((m) => [m[1], m[2]]));

  it("a lista marcada cobre todo status do CHECK, uma vez cada", () => {
    expect(Object.keys(tabela).sort()).toEqual([...STATUS_OS].sort());
  });

  it.each([...STATUS_OS])("%s: statusAoAgendar diz o mesmo que a porta", (status) => {
    let lido: string;
    try {
      lido = statusAoAgendar(status) ?? status;
    } catch {
      lido = "recusa";
    }
    expect(lido).toBe(tabela[status]);
  });
});

