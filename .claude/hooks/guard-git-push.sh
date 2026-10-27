#!/usr/bin/env bash
# PreToolUse hook: bloquea cualquier `git push` cuyo destino sea main/master.
#
# Un agente trabaja en ramas y abre PRs. El merge a main es de los humanos
# (ADR-003). Tambien bloquea los atajos: --force sobre la rama protegida,
# refspecs tipo HEAD:main, y el push sin refspec cuando estas parado en main.
#
# Probalo:
#   echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
#     | bash .claude/hooks/guard-git-push.sh; echo $?
set -uo pipefail

PROTECTED_REGEX="${HARNESS_PROTECTED_BRANCHES:-^(main|master|production|release/.*)$}"

payload="$(cat)"
command_line="$(printf '%s' "$payload" | python3 -c '
import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print((data.get("tool_input") or {}).get("command") or "")
' 2>/dev/null || true)"

[[ -z "$command_line" ]] && exit 0
grep -Eq '(^|[[:space:];&|(])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)' <<<"$command_line" || exit 0

deny() {
  cat >&2 <<MSG
BLOQUEADO por .claude/hooks/guard-git-push.sh

  Comando: $command_line
  Motivo:  el destino es una rama protegida (${1})

Por que: ADR-003 (docs/adr/003-no-agent-prod-creds.md). Los agentes proponen; el
merge a main lo aprueba una persona. Ademas Argo CD despliega desde main: pushear
ahi es desplegar.

Que hacer en su lugar:
  git switch -c fix/descripcion-corta
  git push -u origin fix/descripcion-corta
  gh pr create --fill
MSG
  exit 2
}

# Normalizamos: sacamos el 'git push' y las flags.
args="$(sed -E 's/.*git([[:space:]]+-[^[:space:]]+)*[[:space:]]+push//' <<<"$command_line")"
# Cortamos en el primer separador de comandos para no analizar lo que viene despues.
args="$(sed -E 's/[;&|].*$//' <<<"$args")"

tokens=()
while read -r token; do
  [[ -z "$token" ]] && continue
  tokens+=("$token")
done < <(tr ' \t' '\n\n' <<<"$args")

refspecs=()
for token in "${tokens[@]:-}"; do
  [[ "$token" == -* ]] && continue
  refspecs+=("$token")
done

# El primer no-flag es el remoto; el resto son refspecs.
if [[ ${#refspecs[@]} -ge 2 ]]; then
  for ref in "${refspecs[@]:1}"; do
    destination="${ref##*:}"          # HEAD:main -> main
    destination="${destination#+}"    # +main     -> main
    destination="${destination#refs/heads/}"
    if [[ "$destination" =~ $PROTECTED_REGEX ]]; then
      deny "$destination"
    fi
  done
  exit 0
fi

# Push sin refspec: el destino es la rama actual (o su upstream).
current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
if [[ -n "$current_branch" && "$current_branch" =~ $PROTECTED_REGEX ]]; then
  deny "$current_branch (rama actual, push sin refspec)"
fi

upstream="$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo '')"
upstream="${upstream#*/}"
if [[ -n "$upstream" && "$upstream" =~ $PROTECTED_REGEX ]]; then
  deny "$upstream (upstream de la rama actual)"
fi

exit 0
