#!/usr/bin/env bash
# Utilidades compartidas por los tres actos.
set -uo pipefail

BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

KUBE_CONTEXT="${KUBE_CONTEXT:-kind-harness}"
APP_NAMESPACE="${APP_NAMESPACE:-orders}"
KUBECTL="kubectl --context ${KUBE_CONTEXT}"

# Modo no interactivo: DEMO_AUTO=1 (para verificar los actos sin estar presente).
pause_demo() {
  if [[ "${DEMO_AUTO:-0}" == "1" ]]; then
    echo ""
    return 0
  fi
  echo ""
  read -rp "${DIM}  [Enter para continuar]${RESET} " _ || true
  echo ""
}

say() { printf '\n%s%s%s\n' "$BOLD$CYAN" "$1" "$RESET"; }
note() { printf '%s  %s%s\n' "$DIM" "$1" "$RESET"; }
ok() { printf '%s  OK  %s%s\n' "$GREEN" "$1" "$RESET"; }
bad() { printf '%s  !!  %s%s\n' "$RED" "$1" "$RESET"; }
warn() { printf '%s  ->  %s%s\n' "$YELLOW" "$1" "$RESET"; }

run() {
  printf '\n%s$ %s%s\n' "$BOLD" "$*" "$RESET"
  "$@"
}

banner() {
  printf '\n%s%s%s\n' "$BOLD$CYAN" "============================================================" "$RESET"
  printf '%s  %s%s\n' "$BOLD$CYAN" "$1" "$RESET"
  printf '%s%s%s\n\n' "$BOLD$CYAN" "============================================================" "$RESET"
}

require_clean_tree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    bad "El arbol de trabajo tiene cambios sin commitear."
    note "Corré 'bash demo/reset.sh' antes de empezar el acto."
    git status --short
    exit 1
  fi
}

require_cluster() {
  if ! $KUBECTL cluster-info >/dev/null 2>&1; then
    bad "No encuentro el cluster '${KUBE_CONTEXT}'."
    note "Levantalo con: make up"
    exit 1
  fi
}

rollout_view() {
  if command -v kubectl-argo-rollouts >/dev/null 2>&1; then
    $KUBECTL argo rollouts get rollout orders -n "$APP_NAMESPACE" "$@"
  else
    $KUBECTL -n "$APP_NAMESPACE" get rollout orders -o wide
    $KUBECTL -n "$APP_NAMESPACE" get pods -l app.kubernetes.io/name=orders --show-labels
  fi
}
