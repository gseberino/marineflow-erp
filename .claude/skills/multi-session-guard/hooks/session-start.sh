#!/usr/bin/env bash
# SessionStart — registra a sessão e, se houver OUTRA ativa, avisa para isolar antes de editar.
# Sempre exit 0 (nunca derruba a inicialização). O stdout vira contexto para o agente.
DIR="$(cd "$(dirname "$0")/.." && pwd)"
G="$DIR/guard.sh"

bash "$G" register >/dev/null 2>&1 || true
others="$(bash "$G" others 2>/dev/null || echo 0)"

if [ "${others:-0}" -gt 0 ] 2>/dev/null; then
  wt="$(git rev-parse --show-toplevel 2>/dev/null || echo '?')"
  echo "multi-session-guard: ha ${others} OUTRA(S) sessao(oes) ativa(s) neste repo (worktree atual: ${wt})."
  echo "ANTES de editar/commitar, ISOLE-SE:  bash .claude/skills/multi-session-guard/guard.sh worktree <nome>"
  echo "e trabalhe SO na pasta que ele indicar. Nunca 'git add -A' / 'reset --hard' / 'checkout .' no worktree compartilhado."
  echo "Integrar+deployar so sob:  bash .claude/skills/multi-session-guard/guard.sh lock"
fi
exit 0
