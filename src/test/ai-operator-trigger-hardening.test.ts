import { describe, it, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

// Teste estático: garante que `public.ai_op_protect_pending_action` seja
// criada com search_path fixo e vazio, e que os GRANT/REVOKE permaneçam,
// tanto na foundation (para novos ambientes) quanto na migration aditiva
// (para o staging já migrado).

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

// Extrai o bloco `create or replace function ... ai_op_protect_pending_action ... $$ ... $$;`
function extractFunctionBlock(sql: string): string {
  const re =
    /create\s+or\s+replace\s+function\s+public\.ai_op_protect_pending_action[\s\S]*?\$\$\s*;/i;
  const m = sql.match(re);
  if (!m) throw new Error("Bloco da função ai_op_protect_pending_action não encontrado");
  return m[0];
}

describe("AI Operator — trigger function hardening (search_path)", () => {
  it("foundation: ai_op_protect_pending_action declara `set search_path = ''`", () => {
    const sql = read(FOUNDATION);
    const block = extractFunctionBlock(sql);
    expect(block).toMatch(/set\s+search_path\s*=\s*''/i);
  });

  it("foundation: mantém REVOKE/GRANT corretos da trigger function", () => {
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

  it("migration aditiva existe com o nome esperado", () => {
    expect(existsSync(resolve(ROOT, HARDENING))).toBe(true);
  });

  it("migration aditiva: replace da função declara `set search_path = ''`", () => {
    const sql = read(HARDENING);
    const block = extractFunctionBlock(sql);
    expect(block).toMatch(/set\s+search_path\s*=\s*''/i);
  });

  it("migration aditiva: reafirma REVOKE de public/anon/authenticated e GRANT a service_role", () => {
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

  it("migration aditiva NÃO altera tabelas, policies ou outras funções do AI Operator", () => {
    const sql = read(HARDENING);
    // Não cria nem dropa tabelas/policies/outras funções.
    expect(sql).not.toMatch(/create\s+table/i);
    expect(sql).not.toMatch(/drop\s+table/i);
    expect(sql).not.toMatch(/create\s+policy/i);
    expect(sql).not.toMatch(/drop\s+policy/i);
    // Nenhuma outra função criada/alterada — apenas ai_op_protect_pending_action.
    const fnMatches = sql.match(/create\s+or\s+replace\s+function\s+\w+\.\w+/gi) || [];
    expect(fnMatches.length).toBe(1);
    expect(fnMatches[0]).toMatch(/public\.ai_op_protect_pending_action/i);
  });

  it("migration aditiva não cria nenhum objeto SQL relacionado a WhatsApp", () => {
    const sql = read(HARDENING);
    // Comentário mencionando 'WhatsApp' é permitido (escopo); o que não pode
    // existir é qualquer DDL/DML real (create/alter/drop/insert/update/delete)
    // que cite whatsapp ou ai_operator_channel_events.
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

  it("foundation mantém o trigger anexado ao ai_operator_pending_actions", () => {
    const sql = read(FOUNDATION);
    expect(sql).toMatch(
      /create\s+trigger\s+trg_ai_op_pending_guard[\s\S]*?on\s+public\.ai_operator_pending_actions/i
    );
  });
});
