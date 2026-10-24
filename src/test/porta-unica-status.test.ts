// O status de agenda da OS só pela PORTA (Agenda de Produção, Fase 2, P4 — 24/10/2026).
//
// Até aqui sete caminhos escreviam service_orders.status cada um com a sua regra: a tela "Agendar OS" (e o botão da
// R1, que abre a mesma tela), a aprovação com PIN (approve_quote_full), o schedule_service_order e o
// update_service_order_status do assistente, o check-in e as duas OC criadas a partir da OS. Saíam dali a OC que regredia
// a OS EM ANDAMENTO para "aguardando peças" (NOVO-agenda-10) e a OS aguardando peças que virava "agendada" sem a peça.
// Agora todos passam pela porta única do banco (os_transicionar_status), que decide; com a agenda automática ligada, a
// data é da agenda (agenda_marcar_os, ou o rascunho agenda_rascunho_marcar do assistente).
//
// Este teste lê os arquivos como texto e cobra:
//   1. nos arquivos dos caminhos, nenhum status de agenda dentro de um UPDATE de service_orders (nem literal, nem por
//      variável, nem por "update.status = …");
//   2. cada caminho chama a porta (ou o marcar da agenda, onde é ela que manda);
//   3. em todo o código (src e supabase/functions, sem os testes), quem escreve service_orders.status por fora da porta
//      é só a lista conhecida — e ela é CONGELADA: se um arquivo da lista deixar de escrever, a exceção tem de sair
//      (como em migrations-versao-unica.test.ts);
//   4. a paridade de statusAoAgendar (a leitura da porta que a tela usa) com a porta, status a status: a lista marcada
//      em supabase/tests/agenda_fase2_rascunho.sql é provada contra a porta na bancada; aqui, contra statusAoAgendar.
import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative, sep } from "node:path";
import { STATUS_OS, statusAoAgendar } from "../../supabase/functions/_shared/service-order-status";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const ler = (p: string) => readFileSync(join(RAIZ, p), "utf8").replace(/\r\n/g, "\n");

/** Os status que são da agenda (a porta decide). Os outros (concluir, faturar, cancelar, voltar a orçamento) têm caminho
 *  próprio — a conclusão vem para a porta na Fase 3. */
const STATUS_DE_AGENDA = ["open", "approved", "scheduled", "in_progress", "awaiting_parts", "awaiting_client"];
const FORA_DA_AGENDA = ["completed", "invoiced", "cancelled", "draft"];

/** Os arquivos dos caminhos (spec-fase2 §10) e o que cada um tem de chamar. AgendaPage e TaskCard chegam pelo hook. */
const CAMINHOS: Record<string, string[]> = {
  "src/hooks/use-agenda.ts": ["os_transicionar_status", "agenda_marcar_os"],
  "src/pages/AgendaPage.tsx": [],
  "src/components/agenda/TaskCard.tsx": [],
  "supabase/functions/_shared/ai/tools/flow-macros.ts": ["os_transicionar_status", "agenda_marcar_os"],
  "supabase/functions/_shared/ai/tools/service-orders.ts": ["os_transicionar_status", "agenda_rascunho_marcar"],
  "supabase/functions/_shared/ai/tools/field-ops.ts": ["os_transicionar_status"],
  "supabase/functions/_shared/ai/tools/purchasing.ts": ["os_transicionar_status"],
  "src/hooks/use-purchase-orders.ts": ["os_transicionar_status"],
};

/**
 * Quem ainda escreve service_orders.status por fora da porta, e por quê. CONGELADA: entra arquivo novo = falha; arquivo
 * que deixou de escrever = falha (a exceção tem de sair).
 */
const LISTA_CONHECIDA: Record<string, string> = {
  // useUpdateServiceOrderStatus (StatusQuickChange, kanban, lista de orçamentos, formulário): também conclui — a
  // conclusão (check_out_at + recebíveis) vem para a porta na Fase 3.
  "src/hooks/use-service-orders.ts": "updates",
  // update_service_order_status: só a conversão do orçamento (draft → OS, com o número novo) e o faturar; os status de
  // agenda já vão pela porta.
  "supabase/functions/_shared/ai/tools/service-orders.ts": "updatePayload",
  // a assinatura do cliente conclui a OS (o status de depois vem de app_settings.signature_status_after) — Fase 3.
  "supabase/functions/submit-signature/index.ts": "newStatus",
  // PLANO B (revisão da Fase 2): só quando os_transicionar_status ainda não existe no banco (o código publicado antes da
  // migration 20261025100100), a tela, a OC e o check-in voltam ao caminho de antes. SAI quando a Fase 2 estiver aplicada.
  "supabase/functions/_shared/porta-ausente.ts": "para",
};

const FROM = String.raw`\.from\(\s*['"]service_orders['"]\s*(?:as\s+\w+\s*)?\)`;
/** Até 400 caracteres depois do .from('service_orders'), sem atravessar outro .from(…). */
const JANELA = String.raw`(?:(?!\.from\()[\s\S]){0,400}?`;

type Escrita = { tipo: "literal" | "variavel" | "atribuicao"; valor: string };

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
    const usa = new RegExp(FROM + JANELA + String.raw`\.update\(\s*` + m[1] + String.raw`\b`);
    if (usa.test(texto)) out.push({ tipo: "variavel", valor: m[1] });
  }
  // const v = …; … .update({ status: v }) já sai acima como variável; e o jeito antigo: update.status = …
  for (const m of texto.matchAll(/\b(update|updates|patch|updatePayload)\.status\s*=/g)) out.push({ tipo: "atribuicao", valor: m[1] });
  return out;
}

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

describe("porta única de status — os caminhos da agenda (Fase 2, P4)", () => {
  it.each(Object.keys(CAMINHOS))("%s: nenhum status de agenda num UPDATE de service_orders", (arquivo) => {
    const ruins = escritasDeStatus(ler(arquivo)).filter((e) =>
      // o literal de fora da agenda (reabrir = concluída) tem caminho próprio; a variável só a da lista conhecida
      !(e.tipo === "literal" && FORA_DA_AGENDA.includes(e.valor))
      && !(e.tipo === "variavel" && LISTA_CONHECIDA[arquivo] === e.valor));
    expect(ruins, "status de agenda só pela porta (os_transicionar_status)").toEqual([]);
    // e nenhum literal de status de agenda num objeto "status: 'scheduled'" do arquivo
    const literais = [...ler(arquivo).matchAll(/\bstatus\s*:\s*['"](scheduled|in_progress|awaiting_parts|awaiting_client)['"]/g)].map((m) => m[0]);
    expect(literais, "status de agenda só pela porta (os_transicionar_status)").toEqual([]);
  });

  it.each(Object.entries(CAMINHOS).filter(([, t]) => t.length))("%s chama a porta (%j)", (arquivo, tokens) => {
    const texto = ler(arquivo);
    for (const t of tokens) expect(texto.includes(t), `${arquivo} devia chamar ${t}`).toBe(true);
  });
});

describe("porta única de status — o resto do código", () => {
  const escritas = new Map<string, Escrita[]>();
  for (const dir of ["src", "supabase/functions"]) {
    for (const arquivo of arquivosDoCodigo(dir)) {
      const e = escritasDeStatus(ler(arquivo)).filter((x) => x.tipo !== "atribuicao");
      if (e.length) escritas.set(arquivo.split(sep).join("/"), e);
    }
  }

  it("nenhum arquivo escreve status de agenda (literal) em service_orders por fora da porta", () => {
    const ruins = [...escritas.entries()]
      .flatMap(([arquivo, es]) => es.filter((e) => e.tipo === "literal" && STATUS_DE_AGENDA.includes(e.valor)).map((e) => `${arquivo}: ${e.valor}`));
    expect(ruins, "status de agenda só pela porta (os_transicionar_status)").toEqual([]);
  });

  it("quem escreve status por variável é só a lista conhecida, e a lista é congelada (exceção que sobra tem de sair)", () => {
    const porVariavel = Object.fromEntries([...escritas.entries()]
      .map(([arquivo, es]) => [arquivo, es.filter((e) => e.tipo === "variavel").map((e) => e.valor)] as const)
      .filter(([, vs]) => vs.length)
      .map(([arquivo, vs]) => [relative(RAIZ, join(RAIZ, arquivo)).split(sep).join("/"), [...new Set(vs)].join(",")]));
    expect(porVariavel, "status de agenda só pela porta (os_transicionar_status)").toEqual(LISTA_CONHECIDA);
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
