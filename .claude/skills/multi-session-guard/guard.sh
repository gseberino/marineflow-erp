#!/usr/bin/env bash
# Multi-session guard — coordena várias sessões de IA no MESMO repositório sem que uma
# sobrescreva/reverta a outra. Primitivas: registro de sessões ativas (com heartbeat),
# criação de worktree isolado, e um lock global para a seção crítica de integrar+deployar.
#
# Estado fica em "$(git-common-dir)/mf-sessions" — dentro do .git, NUNCA versionado, e
# compartilhado por todos os worktrees do mesmo repo. É um protocolo COOPERATIVO: só protege
# entre sessões que rodam esta skill.
set -euo pipefail

COORD="$(cd "$(git rev-parse --git-common-dir)" && pwd)/mf-sessions"
ACTIVE="$COORD/active"
LOCK="$COORD/integrate.lock"
STALE_MIN=${MF_STALE_MIN:-45}    # sessão sem heartbeat há N min = considerada morta
LOCK_WAIT=${MF_LOCK_WAIT:-180}   # espera até N s pelo lock de integração
mkdir -p "$ACTIVE"

wt()  { git rev-parse --show-toplevel; }
sid() { wt | tr '/:\\ .' '______'; }   # id da sessão = caminho do worktree sanitizado
now() { date +%s; }
mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }

cmd_status() {
  echo "worktree:   $(wt)"
  echo "branch:     $(git rev-parse --abbrev-ref HEAD)"
  echo "git-common: $(git rev-parse --git-common-dir)"
  echo "session-id: $(sid)"
  echo "--- sessões ativas ---"; cmd_active
  echo "--- lock de integração ---"
  if [ -d "$LOCK" ]; then echo "OCUPADO por: $(cat "$LOCK/holder" 2>/dev/null || echo '?')"; else echo "livre"; fi
}

cmd_active() {
  local found=0 f age flag
  for f in "$ACTIVE"/*.json; do
    [ -e "$f" ] || continue
    age=$(( ($(now) - $(mtime "$f")) / 60 ))
    flag=""; [ "$age" -gt "$STALE_MIN" ] && flag="  (STALE ${age}min — provável morta)"
    echo "  - $(basename "$f" .json) · último sinal há ${age}min${flag}"
    found=1
  done
  [ "$found" -eq 0 ] && echo "  (nenhuma)"
}

cmd_register() {
  local f="$ACTIVE/$(sid).json"
  printf '{"worktree":"%s","branch":"%s","pid":%s,"started":%s}\n' \
    "$(wt)" "$(git rev-parse --abbrev-ref HEAD)" "$$" "$(now)" > "$f"
  echo "registrada: $(sid)"
}

cmd_heartbeat() { local f="$ACTIVE/$(sid).json"; [ -e "$f" ] && { touch "$f"; echo "heartbeat ok"; } || echo "não registrada (rode: register)"; }

cmd_done() { rm -f "$ACTIVE/$(sid).json"; echo "sessão encerrada: $(sid)"; }

# Nº de OUTRAS sessões ativas (não-stale) além desta. 0 = você está sozinho.
cmd_others() {
  local me f age n=0; me="$(sid)"
  for f in "$ACTIVE"/*.json; do
    [ -e "$f" ] || continue
    [ "$(basename "$f" .json)" = "$me" ] && continue
    age=$(( ($(now) - $(mtime "$f")) / 60 )); [ "$age" -gt "$STALE_MIN" ] && continue
    n=$((n+1))
  done
  echo "$n"
}

# Cria (ou reaproveita) um worktree isolado. Uso: guard.sh worktree <nome-curto>
cmd_worktree() {
  local name="${1:?uso: guard.sh worktree <nome-curto> (ex.: ai, fiscal)}"
  local branch="session/$name" root path
  root="$(git rev-parse --show-toplevel)"
  path="$(cd "$root/.." && pwd)/$(basename "$root")--$name"
  if git worktree list --porcelain | grep -q "^worktree $path$"; then
    echo "já existe: $path (branch $branch)"
  elif git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$path" "$branch"
  else
    git worktree add -b "$branch" "$path"
  fi
  echo "→ trabalhe SEMPRE dentro de: $path"
}

cmd_lock() {
  local deadline=$(( $(now) + LOCK_WAIT )) ts
  while :; do
    if mkdir "$LOCK" 2>/dev/null; then printf '%s %s\n' "$(sid)" "$(now)" > "$LOCK/holder"; echo "lock adquirido"; return 0; fi
    if [ -f "$LOCK/holder" ]; then
      ts=$(awk '{print $2}' "$LOCK/holder" 2>/dev/null || echo 0)
      if [ $(( $(now) - ts )) -gt $(( STALE_MIN * 60 )) ]; then echo "lock stale — quebrando"; rm -rf "$LOCK"; continue; fi
    fi
    [ "$(now)" -ge "$deadline" ] && { echo "TIMEOUT esperando o lock (ocupado por: $(cat "$LOCK/holder" 2>/dev/null))"; return 1; }
    sleep 3
  done
}

cmd_unlock() {
  [ -d "$LOCK" ] || { echo "sem lock"; return 0; }
  local h; h=$(awk '{print $1}' "$LOCK/holder" 2>/dev/null || echo "")
  if [ "$h" = "$(sid)" ] || [ "${1:-}" = "--force" ]; then rm -rf "$LOCK"; echo "lock liberado"; else echo "lock é de outra sessão ($h) — use --force só se tiver certeza que morreu"; return 1; fi
}

case "${1:-status}" in
  status)    cmd_status;;
  active)    cmd_active;;
  register)  cmd_register;;
  heartbeat) cmd_heartbeat;;
  others)    cmd_others;;
  worktree)  shift; cmd_worktree "${1:-}";;
  lock)      cmd_lock;;
  unlock)    shift || true; cmd_unlock "${1:-}";;
  done)      cmd_done;;
  *) echo "uso: guard.sh {status|active|register|heartbeat|others|worktree <nome>|lock|unlock|done}"; exit 1;;
esac
