import { describe, it, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

// Testes estáticos do hardening de search_path nas duas trigger functions
// do caminho da foundation do AI Operator:
//   * public.ai_op_protect_pending_action()  — server-only.
//   * public.set_updated_at_now()            — helper compartilhado.

const ROOT = resolve(__dirname, "../../");

function read(rel: string): string {
  const p = resolve(ROOT, rel);
  if (!existsSync(p)) throw new Error(`Arquivo esperado não existe: ${rel}`);
  return readFileSync(p, "utf8");
}

const FOUNDATION = "supabase/migrations/20260522190000_ai_operator_foundation.sql";
const HARDENING = "supabase/migrations/20260523010000_ai_operator_harden_pending_trigger_search_path.sql";
const DEFERRED_BRIDGE = "supabase/deferred-migrations/20260522190100_ai_operator_whatsapp_bridge.sql";
const PIPELINE_BRIDGE = "supabase/migrations/20260522190100_ai_operator_whatsapp_bridge.sql";

function extractBlock(sql: string, fnName: string): string {
  // Captura o bloco `(create [or replace]) function ... fnName ... $body|$$  ... $body|$$;`
  const re = new RegExp(
    `create(\\s+or\\s+replace)?\\s+function\\s+public\\.${fnName}[\\s\\S]*?\\$(body)?\\$[\\s\\S]*?\\$(body)?\\$\\s*;`,
    "i"
  );
  const m = sql.match(re);
  if (!m) throw new Error(`Bloco da função public.${fnName} não encontrado`);
  return m[0];
}

describe("AI Operator — trigger function hardening (search_path)", () => {
  // ---------- ai_op_protect_pending_action ----------
  describe("public.ai_op_protect_pending_action()", () => {
    it("foundation: declara `set search_path = ''`", () => {
      const sql = read(FOUNDATION);
      const block = extractBlock(sql, "ai_op_protect_pending_action");
      expect(block).toMatch(/set\s+search_path\s*=\s*''/i);
    });

    it("foundation: mantém REVOKE/GRANT corretos", () => {
      const sql = read(FOUNDATION);
      expect(sql).toMatch(
        /revoke\s+execute\s+on\s+function\s+public\.ai_op_protect_pending_action\(\)\s+from\s+public/i
      );
      expect(sql).toMatch(
        /revoke\s+execute\s+on\s+function\s+public\.ai_op_protect_pending_action\(\)\s+from\s+anon,\s*authenticated/i
      );
      expect(sql).toMatch(
        /grant\s+execute\s+on\s+function\s+public\.ai_op_protect_pending_action\(\)\s+to\s+service_role/i
      );
    });

    it("migration aditiva: replace declara `set search_path = ''`", () => {
      const sql = read(HARDENING);
      const block = extractBlock(sql, "ai_op_protect_pending_action");
      expect(block).toMatch(/set\s+search_path\s*=\s*''/i);
    });

    it("migration aditiva: reafirma REVOKE/GRANT corretos", () => {
      const sql = read(HARDENING);
      expect(sql).toMatch(
        /revoke\s+execute\s+on\s+function\s+public\.ai_op_protect_pending_action\(\)\s+from\s+public/i
      );
      expect(sql).toMatch(
        /revoke\s+execute\s+on\s+function\s+public\.ai_op_protect_pending_action\(\)\s+from\s+anon,\s*authenticated/i
      );
      expect(sql).toMatch(
        /grant\s+execute\s+on\s+function\s+public\.ai_op_protect_pending_action\(\)\s+to\s+service_role/i
      );
    });

    it("foundation mantém o trigger trg_ai_op_pending_guard anexado", () => {
      const sql = read(FOUNDATION);
      expect(sql).toMatch(
        /create\s+trigger\s+trg_ai_op_pending_guard[\s\S]*?on\s+public\.ai_operator_pending_actions/i
      );
    });
  });

  // ---------- set_updated_at_now ----------
  describe("public.set_updated_at_now()", () => {
    it("foundation: criação condicional declara `set search_path = ''`", () => {
      const sql = read(FOUNDATION);
      const block = extractBlock(sql, "set_updated_at_now");
      expect(block).toMatch(/set\s+search_path\s*=\s*''/i);
    });

    it("foundation: usa pg_catalog.now() (qualificado)", () => {
      const sql = read(FOUNDATION);
      const block = extractBlock(sql, "set_updated_at_now");
      expect(block).toMatch(/pg_catalog\.now\(\)/i);
      // Não deve usar `now()` desqualificado dentro do corpo.
      const body = block.replace(/pg_catalog\.now\(\)/gi, "");
      expect(body).not.toMatch(/\bnow\s*\(\)/i);
    });

    it("foundation: criação permanece condicional via IF NOT EXISTS", () => {
      const sql = read(FOUNDATION);
      // Procuramos o bloco do `do $$ ... if not exists (...) set_updated_at_now`
      expect(sql).toMatch(
        /if\s+not\s+exists\s*\(\s*select\s+1\s+from\s+pg_proc\s+where\s+proname\s*=\s*'set_updated_at_now'\s*\)/i
      );
    });

    it("foundation: triggers de updated_at do AI Operator continuam vinculados", () => {
      const sql = read(FOUNDATION);
      for (const trg of [
        "trg_ai_op_sessions_updated",
        "trg_ai_op_drafts_updated",
        "trg_ai_op_memory_updated",
      ]) {
        expect(sql).toMatch(
          new RegExp(
            `create\\s+trigger\\s+${trg}[\\s\\S]*?execute\\s+function\\s+public\\.set_updated_at_now\\(\\)`,
            "i"
          )
        );
      }
    });

    it("migration aditiva: replace declara `set search_path = ''` e usa pg_catalog.now()", () => {
      const sql = read(HARDENING);
      const block = extractBlock(sql, "set_updated_at_now");
      expect(block).toMatch(/set\s+search_path\s*=\s*''/i);
      expect(block).toMatch(/pg_catalog\.now\(\)/i);
    });

    it("migration aditiva NÃO altera permissões de set_updated_at_now", () => {
      const sql = read(HARDENING);
      // Não há REVOKE/GRANT desta função na migration aditiva — ela é
      // compartilhada com outros módulos e nada pode ser quebrado.
      expect(sql).not.toMatch(/(revoke|grant)\s+execute\s+on\s+function\s+public\.set_updated_at_now/i);
    });
  });

  // ---------- escopo geral da migration aditiva ----------
  describe("escopo da migration aditiva", () => {
    it("existe no caminho esperado", () => {
      expect(existsSync(resolve(ROOT, HARDENING))).toBe(true);
    });

    it("altera exclusivamente as duas funções justificadas", () => {
      const sql = read(HARDENING);
      const fnMatches = sql.match(/create\s+or\s+replace\s+function\s+\w+\.\w+/gi) || [];
      // Exatamente duas: ai_op_protect_pending_action e set_updated_at_now.
      expect(fnMatches.length).toBe(2);
      const names = fnMatches.map((s) => s.toLowerCase());
      expect(names.some((n) => n.includes("public.ai_op_protect_pending_action"))).toBe(true);
      expect(names.some((n) => n.includes("public.set_updated_at_now"))).toBe(true);
    });

    it("não cria/dropa tabelas nem policies", () => {
      const sql = read(HARDENING);
      expect(sql).not.toMatch(/create\s+table/i);
      expect(sql).not.toMatch(/drop\s+table/i);
      expect(sql).not.toMatch(/create\s+policy/i);
      expect(sql).not.toMatch(/drop\s+policy/i);
      expect(sql).not.toMatch(/alter\s+table/i);
    });

    it("não cria nenhum objeto SQL relacionado a WhatsApp", () => {
      const sql = read(HARDENING);
      // Comentário pode mencionar 'WhatsApp' (descreve escopo intocado);
      // DDL/DML real não pode citar whatsapp ou ai_operator_channel_events.
      const ddlLines = sql
        .split("\n")
        .filter((line) => !line.trim().startsWith("--"))
        .join("\n")
        .toLowerCase();
      expect(ddlLines).not.toContain("whatsapp");
      expect(ddlLines).not.toContain("ai_operator_channel_events");
      expect(ddlLines).not.toMatch(/create\s+trigger.*whatsapp/i);
    });

    it("bridge WhatsApp permanece em deferred-migrations/ (fora do pipeline)", () => {
      expect(existsSync(resolve(ROOT, DEFERRED_BRIDGE))).toBe(true);
      expect(existsSync(resolve(ROOT, PIPELINE_BRIDGE))).toBe(false);
    });
  });
});
