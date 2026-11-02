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

# 1) Un kubeconfig alternativo es, por definicion, un cluster no auditado.
#
#    ESTE CHEQUEO VA PRIMERO, y el orden es la parte importante. Cuando estaba
#    despues del chequeo de contexto, bastaba agregar `--context kind-harness`
#    para colarse:
#
#      kubectl --kubeconfig /tmp/mio.yaml --context kind-harness delete rollout orders
#
#    El nombre del contexto no prueba nada: en un kubeconfig que yo escribo,
#    "kind-harness" puede apuntar al cluster que quiera. Lo que hay que verificar
#    es de DONDE sale la credencial, no como se llama.
if grep -qE -- '--kubeconfig[= ]' <<<"$command_line" || grep -qE '(^|[[:space:];&|(])KUBECONFIG=' <<<"$command_line"; then
  deny "kubeconfig alternativo (no verificable, aunque el contexto se llame $ALLOWED_CONTEXT)"
fi

# 2) Contexto explicito en el comando.
#    kubectl y argocd usan --context; helm usa --kube-context. Hay que mirar los dos:
#    si solo mirabamos --context, `helm --kube-context prod upgrade` se colaba cuando
#    el contexto activo resultaba ser el permitido.
explicit_context="$(grep -oE -- '--(kube-)?context[= ]+[^[:space:]]+' <<<"$command_line" | head -1 | sed -E 's/--(kube-)?context[= ]+//')"
if [[ -n "$explicit_context" ]]; then
  [[ "$explicit_context" == "$ALLOWED_CONTEXT" ]] && exit 0
  deny "$explicit_context (explicito en el comando)"
fi

# 3) Contexto activo.
current_context="$(kubectl config current-context 2>/dev/null || echo '<ninguno>')"
[[ "$current_context" == "$ALLOWED_CONTEXT" ]] && exit 0
deny "$current_context (contexto activo)"
