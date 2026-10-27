#!/usr/bin/env bash
# PreToolUse hook: bloquea kubectl/argo rollouts contra cualquier contexto que no
# sea el cluster de la demo (kind-harness).
#
# Esto NO es una instruccion al modelo: es un script. Decide con `exit 2` y el
# modelo no puede negociarlo, convencerlo ni ignorarlo.
#
# Entrada:  JSON por stdin con {tool_name, tool_input:{command}}
# Salida:   exit 0 = permitido | exit 2 = BLOQUEADO (stderr vuelve al agente)
#
# Probalo:
#   echo '{"tool_name":"Bash","tool_input":{"command":"kubectl --context prod get pods"}}' \
#     | bash .claude/hooks/guard-kubectl.sh; echo $?
set -uo pipefail

ALLOWED_CONTEXT="${HARNESS_ALLOWED_CONTEXT:-kind-harness}"

payload="$(cat)"

# Extraccion del comando sin depender de jq.
command_line="$(printf '%s' "$payload" | python3 -c '
import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = data.get("tool_input") or {}
print(ti.get("command") or "")
' 2>/dev/null || true)"

[[ -z "$command_line" ]] && exit 0

# Solo nos interesan comandos que hablan con un cluster.
if ! grep -Eq '(^|[[:space:];&|(])(kubectl|oc|kubectl-argo-rollouts|helm|argocd)([[:space:]]|$)' <<<"$command_line"; then
  exit 0
fi

deny() {
  cat >&2 <<MSG
BLOQUEADO por .claude/hooks/guard-kubectl.sh

  Comando:  $command_line
  Contexto: ${1}
  Permitido unicamente: ${ALLOWED_CONTEXT}

Por que: ADR-003 (docs/adr/003-no-agent-prod-creds.md). Ningun agente habla con un
cluster que no sea el de la demo local. Lo irreversible es de los humanos.

Que hacer en su lugar:
  - Si querias el cluster de la demo:  kubectl --context ${ALLOWED_CONTEXT} ...
  - Si querias cambiar algo en el cluster: NO se hace con kubectl. Se commitea en
    deploy/k8s y lo aplica Argo CD (GitOps). Abri un PR.
MSG
  exit 2
}

# 1) Contexto explicito en el comando.
explicit_context="$(grep -oE -- '--context[= ]+[^[:space:]]+' <<<"$command_line" | head -1 | sed -E 's/--context[= ]+//')"
if [[ -n "$explicit_context" ]]; then
  [[ "$explicit_context" == "$ALLOWED_CONTEXT" ]] && exit 0
  deny "$explicit_context (explicito en el comando)"
fi

# 2) Un kubeconfig distinto al del usuario es, por definicion, un cluster no auditado.
if grep -qE -- '--kubeconfig[= ]' <<<"$command_line" || grep -qE 'KUBECONFIG=' <<<"$command_line"; then
  deny "kubeconfig alternativo (no verificable)"
fi

# 3) Contexto activo.
current_context="$(kubectl config current-context 2>/dev/null || echo '<ninguno>')"
[[ "$current_context" == "$ALLOWED_CONTEXT" ]] && exit 0
deny "$current_context (contexto activo)"
