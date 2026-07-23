#!/usr/bin/env node
// PreToolUse (Bash) — bloqueia comandos que corrompem o trabalho de OUTRA sessão.
// Contrato: exit 2 + motivo no stdout = BLOQUEIA; qualquer outra saída = permite.
// FAIL-OPEN: em dúvida/erro, permite (o wrapper garante que só o 2 bloqueia).
// .cjs (CommonJS) de propósito — o package.json do repo é "type":"module".
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

function allow() { process.exit(0); }
function block(msg) { process.stdout.write(msg + "\n"); process.exit(2); }

let raw = "";
try { raw = fs.readFileSync(0, "utf8"); } catch (e) { allow(); }

let cmd = "";
try {
  const data = JSON.parse(raw);
  cmd = (data && data.tool_input && data.tool_input.command) || "";
} catch (e) { allow(); }
if (typeof cmd !== "string" || !cmd.trim()) allow();

const c = cmd.trim().replace(/\s+/g, " ");

function othersActive() {
  try {
    const g = path.join(__dirname, "..", "guard.sh");
    const out = execFileSync("bash", [g, "others"], { encoding: "utf8", timeout: 8000, env: { ...process.env, MF_STALE_MIN: "10" } });
    return parseInt((out || "0").trim(), 10) || 0;
  } catch (e) { return 0; } // fail-open
}

// 1) git add -A / --all / .  → SEMPRE bloqueia (index compartilhado; regra do repo)
if (/\bgit\s+add\s+(-A\b|--all\b|\.($|\s))/.test(c)) {
  block("BLOQUEADO (multi-session-guard): evite 'git add -A/.' — o index e compartilhado entre sessoes e isso estagia arquivos alheios. Estagie por arquivo: git add <caminho>.");
}

// 2) comandos que apagam a arvore de trabalho → bloqueia SO com outra sessao ativa
if (/\bgit\s+(reset\s+--hard|checkout\s+(--\s+)?\.($|\s)|restore\s+(--staged\s+)?\.($|\s)|clean\s+-\w*f|stash(\s+(push|save))?($|\s))/.test(c)) {
  if (othersActive() > 0) {
    block("BLOQUEADO (multi-session-guard): este comando pode apagar trabalho nao-commitado de OUTRA sessao ativa. Trabalhe no SEU worktree (guard.sh worktree <nome>) ou espere as outras terminarem. (Se a outra ja morreu, o registro some em ~10min.)");
  }
}

// 3) commit direto na 'main' com outra sessao ativa → bloqueia
if (/\bgit\s+commit\b/.test(c)) {
  let br = "";
  try { br = execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf8", timeout: 8000 }).trim(); } catch (e) {}
  if (br === "main" && othersActive() > 0) {
    block("BLOQUEADO (multi-session-guard): nao commite direto na 'main' com outra sessao ativa. Commite no SEU branch/worktree (guard.sh worktree <nome>) e integre na main sob 'guard.sh lock'.");
  }
}

allow();
