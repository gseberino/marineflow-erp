// [MF-AUD-020] Guarda estática das políticas do financeiro.
//
// A decisão #3 do dono (09/08/2026) é: o cargo técnico não enxerga NADA financeiro. A
// migration `20260810113036_tecnico_nao_ve_financeiro` cumpriu isso apertando o predicado das
// cinco tabelas do dinheiro com `NOT is_technician(...)`. Em 09/09/2026 a
// `20260909140000_financeiro_rls_admin_ou_financeiro` trocou a barreira negativa pela positiva
// `is_admin_or_financial(auth.uid())` — só admin/financeiro ATIVOS passam; técnico, vendedor
// externo e papel desconhecido ficam de fora sem precisar ser nomeados. As duas formas valem
// aqui; o que não vale é política sem nenhuma das duas.
//
// ═══ POR QUE UMA GUARDA ESTÁTICA, E NÃO SÓ O TESTE DE VERDADE ═══
//
// O teste que realmente prova a RLS precisa de um banco: está em
// `supabase/tests/rls_tecnico_financeiro.sql`, e alguém tem que rodá-lo. O CI deste repo não
// tem banco nem secrets — então, se a proteção dependesse só dele, uma migration futura
// poderia reescrever `authenticated_all_payments` sem o predicado e nada acusaria.
//
// É um risco concreto, não hipotético: `ALTER POLICY` substitui o predicado inteiro. Quem
// mexer nessas políticas por outro motivo (acrescentar uma regra de vendedor, por exemplo) e
// escrever o USING do zero apaga a barreira do técnico sem perceber. Este teste lê as
// migrations e falha nesse caso.
//
// ═══ ESTADO ACUMULADO, NÃO "O ÚLTIMO ARQUIVO" ═══
//
// Uma política vive do CREATE até um DROP posterior. Olhar só o último arquivo que tocou na
// tabela deixava passar dois erros: uma política allow-all antiga que nunca foi derrubada
// (é o que a convergência 20260914110000 fechou) e uma política nova de OUTRO papel (as do
// portal, `to anon` amarradas ao share-token) sendo cobrada pela barreira do técnico. Aqui
// cada política vigente é julgada pelo papel a que se dirige.
//
// O que ele NÃO faz, dito claramente: não conecta em banco nenhum e não prova que a política
// está ATIVA em produção. Prova que o repositório, aplicado do zero, produz a barreira.

import { describe, expect, it } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const raizDoRepo = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const DIR_MIGRATIONS = join(raizDoRepo, "supabase", "migrations");

/** As cinco tabelas do dinheiro, conforme a decisão #3. */
const TABELAS_FINANCEIRAS = [
  "payments",
  "receivables",
  "payables",
  "invoices",
  "bank_transactions",
] as const;

/** Migrations em ordem cronológica — o nome começa com o timestamp. */
function migrationsEmOrdem(): { arquivo: string; sql: string }[] {
  return readdirSync(DIR_MIGRATIONS)
    .filter((f) => f.endsWith(".sql"))
    .sort()
    .map((arquivo) => ({
      arquivo,
      sql: readFileSync(join(DIR_MIGRATIONS, arquivo), "utf8").replace(/--[^\n]*/g, ""),
    }));
}

type Politica = { nome: string; arquivo: string; texto: string };

/**
 * As políticas VIGENTES de uma tabela ao fim de todas as migrations: cada CREATE vale até um
 * DROP posterior (na ordem dos arquivos e, dentro do arquivo, na ordem do texto); ALTER
 * POLICY acrescenta o predicado novo ao texto julgado. Nomes com `%` são format strings de
 * blocos DO e ficam de fora — não são políticas literais.
 */
function politicasVigentes(tabela: string): Politica[] {
  const vivas = new Map<string, Politica>();
  const t = `(?:public\\.)?${tabela}\\b`;
  const reCreate = new RegExp(`create\\s+policy\\s+"([^"]+)"\\s+on\\s+${t}[\\s\\S]*?;`, "gi");
  const reDrop = new RegExp(`drop\\s+policy\\s+(?:if\\s+exists\\s+)?"([^"]+)"\\s+on\\s+${t}`, "gi");
  const reAlter = new RegExp(`alter\\s+policy\\s+"([^"]+)"\\s+on\\s+${t}[\\s\\S]*?;`, "gi");

  for (const { arquivo, sql } of migrationsEmOrdem()) {
    const eventos: { i: number; tipo: "c" | "d" | "a"; nome: string; texto: string }[] = [];
    for (const m of sql.matchAll(reCreate)) eventos.push({ i: m.index!, tipo: "c", nome: m[1], texto: m[0] });
    for (const m of sql.matchAll(reDrop)) eventos.push({ i: m.index!, tipo: "d", nome: m[1], texto: m[0] });
    for (const m of sql.matchAll(reAlter)) eventos.push({ i: m.index!, tipo: "a", nome: m[1], texto: m[0] });
    for (const e of eventos.sort((x, y) => x.i - y.i)) {
      if (e.nome.includes("%")) continue;
      if (e.tipo === "c") vivas.set(e.nome, { nome: e.nome, arquivo, texto: e.texto });
      else if (e.tipo === "d") vivas.delete(e.nome);
      else if (vivas.has(e.nome)) vivas.get(e.nome)!.texto += `\n${e.texto}`;
    }
  }
  return [...vivas.values()];
}

/**
 * Políticas allow-all da era Lovable que os arquivos do repo criavam e a PRODUÇÃO já não tinha
 * (derrubadas pela migration perdida 20260706165104, MF-AUD-058). A convergência
 * `20260914110000_convergencia_politicas_orfas` as derruba no repo desde 14/09/2026, então a
 * lista está vazia — e o teste abaixo garante que ela só volte a ter nome se a convergência
 * sumir.
 */
const ORFAS_CONHECIDAS = new Set<string>([]);

const barreiraNegativa = (t: string) => /not\s+(?:public\.)?is_technician\s*\(/.test(t);
const barreiraPositiva = (t: string) => /(?:public\.)?is_admin_or_financial\s*\(\s*auth\.uid\(\)\s*\)/.test(t);
/** A quem a política se dirige: `TO anon`, `TO authenticated`, ou nenhum papel (= todos). */
function papeis(texto: string): string[] {
  const m = texto.match(/\bto\s+([a-z_]+(?:\s*,\s*[a-z_]+)*)/i);
  return m ? m[1].toLowerCase().split(/\s*,\s*/) : [];
}

describe("MF-AUD-020 — o técnico não enxerga o financeiro", () => {
  it("a função is_technician existe e está fechada para anon", () => {
    const todas = migrationsEmOrdem().map((m) => m.sql).join("\n");

    expect(todas).toMatch(/create\s+or\s+replace\s+function\s+public\.is_technician\(/i);

    // Função nova nasce com EXECUTE para PUBLIC. Sem o revoke, o predicado continuaria certo
    // e a função viraria superfície de consulta para anônimo (MF-AUD-025).
    expect(todas).toMatch(/revoke\s+execute\s+on\s+function\s+public\.is_technician\(uuid\)\s+from\s+public,\s*anon/i);

    // SECURITY DEFINER com search_path fixo: sem isso, um schema no caminho de busca do
    // chamador poderia sequestrar a resolução de `app_users`.
    const corpo = todas.slice(todas.search(/create\s+or\s+replace\s+function\s+public\.is_technician\(/i));
    expect(corpo.slice(0, 400)).toMatch(/security\s+definer/i);
    expect(corpo.slice(0, 400)).toMatch(/set\s+search_path\s*=\s*public/i);
  });

  it("a função is_admin_or_financial existe, é SECURITY DEFINER e está fechada para anon", () => {
    // É o predicado positivo das políticas de 09/09. Se ela sumir ou abrir para anon, a
    // barreira continua "escrita" e deixa de valer — o mesmo raciocínio da is_technician.
    const todas = migrationsEmOrdem().map((m) => m.sql).join("\n");

    expect(todas).toMatch(/create\s+or\s+replace\s+function\s+public\.is_admin_or_financial\(/i);
    expect(todas).toMatch(/revoke\s+execute\s+on\s+function\s+public\.is_admin_or_financial\(uuid\)\s+from\s+public,\s*anon/i);

    const corpo = todas.slice(todas.search(/create\s+or\s+replace\s+function\s+public\.is_admin_or_financial\(/i));
    expect(corpo.slice(0, 400)).toMatch(/security\s+definer/i);
    expect(corpo.slice(0, 400)).toMatch(/set\s+search_path\s*(?:=|to)\s*'?public'?/i);
  });

  it("a lista de órfãs conhecidas esvazia quando a convergência entra no repositório", () => {
    const convergiu = readdirSync(DIR_MIGRATIONS).some((f) => /convergencia_politicas_orfas/.test(f));
    if (convergiu) expect(ORFAS_CONHECIDAS.size, "a convergência já derruba as órfãs — tire-as da lista").toBe(0);
    for (const nome of ORFAS_CONHECIDAS) expect(nome).toMatch(/^Authenticated users can do everything on /);
  });

  for (const tabela of TABELAS_FINANCEIRAS) {
    it(`toda política vigente de ${tabela} para autenticados carrega a barreira do técnico`, () => {
      const vigentes = politicasVigentes(tabela).filter((p) => !ORFAS_CONHECIDAS.has(p.nome));
      expect(vigentes.length, `nenhuma política vigente para ${tabela}`).toBeGreaterThan(0);

      for (const p of vigentes) {
        const texto = p.texto.toLowerCase();
        const alvo = papeis(texto);

        // Uma política que dissesse `USING (is_technician(...))` mencionaria a função e faria
        // exatamente o oposto.
        expect(texto, `"${p.nome}" (${p.arquivo}) libera pelo is_technician`).not.toMatch(/using\s*\(\s*(?:public\.)?is_technician\s*\(/);

        if (alvo.includes("anon") && !alvo.includes("authenticated")) {
          // Política do portal: o anônimo só entra pela OS do share-token. Sem esse amarre, a
          // política é uma porta aberta.
          expect(texto, `"${p.nome}" (${p.arquivo}) é para anon e não se amarra ao share-token`)
            .toMatch(/share_token_da_requisicao\s*\(/);
          continue;
        }

        // Sem `TO authenticated` a política vale para anon também: com a barreira negativa,
        // `NOT is_technician(null)` é verdadeiro e o anônimo passa (lição de 08/2026).
        expect(alvo, `"${p.nome}" (${p.arquivo}) não nomeia o papel — sem "to authenticated" vale para anon`)
          .toContain("authenticated");

        expect(
          barreiraNegativa(texto) || barreiraPositiva(texto),
          `"${p.nome}" (${p.arquivo}) para autenticados não carrega a barreira do técnico: `
          + `precisa de "is_admin_or_financial(auth.uid())" (ou "NOT public.is_technician(auth.uid())") `
          + `— decisão #3 do dono, 09/08/2026.`,
        ).toBe(true);
      }
    });
  }

  it("payables mantém a regra de categoria sensível junto com a do técnico", () => {
    // A T1.4 (MF-AUD-023) fechou UPDATE/DELETE de payables de categoria sensível. A migration
    // do técnico veio depois e usou ALTER para somar, não substituir; a de 09/09 reescreveu
    // do zero e manteve as duas (estendendo a categoria ao INSERT). Se alguém reescrever uma
    // política de autenticado e uma das duas regras cair, este teste diz qual.
    const paraAutenticados = politicasVigentes("payables")
      .filter((p) => !ORFAS_CONHECIDAS.has(p.nome) && !papeis(p.texto.toLowerCase()).includes("anon"));
    expect(paraAutenticados.length).toBeGreaterThan(0);
    for (const p of paraAutenticados) {
      const texto = p.texto.toLowerCase();
      expect(barreiraNegativa(texto) || barreiraPositiva(texto), `"${p.nome}" (${p.arquivo}) perdeu a barreira do técnico.`).toBe(true);
      expect(
        texto.includes("sensitive") || texto.includes("sensivel") || texto.includes("categoria"),
        `"${p.nome}" (${p.arquivo}) perdeu a referência à categoria sensível (MF-AUD-023). As duas regras precisam coexistir.`,
      ).toBe(true);
    }
  });
});
