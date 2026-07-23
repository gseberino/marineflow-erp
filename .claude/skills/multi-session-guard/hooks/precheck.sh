#!/usr/bin/env bash
# Wrapper FAIL-OPEN do PreToolUse. Só o código 2 (bloqueio intencional do precheck.py)
# bloqueia a tool. Python ausente, erro no script, qualquer outra coisa → exit 0 (permite).
DIR="$(cd "$(dirname "$0")" && pwd)"
reason="$(node "$DIR/precheck.cjs" 2>/dev/null)"; rc=$?
if [ "$rc" = "2" ]; then printf '%s\n' "$reason" >&2; exit 2; fi
exit 0
