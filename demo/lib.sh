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

# Archivos que crean o modifican los actos. Si lo unico sucio es esto, lo
# limpiamos solos: en escena no sirve que el Acto 2 se niegue a arrancar porque
# quedaron los restos del Acto 1.
ACT_ARTIFACTS=(
  "src/infrastructure/db.ts"
  "test/fault-rate-guard.test.ts"
  "policy/fault-injection.rego"
)
ACT_TOUCHED_FILES=(
  "src/domain/order.ts"
  "src/infrastructure/config.ts"
  "test/routes.test.ts"
  "test/metrics.test.ts"
  "deploy/k8s/rollout.yaml"
)

is_act_leftover() {
  local path="$1"
  local known
  for known in "${ACT_ARTIFACTS[@]}" "${ACT_TOUCHED_FILES[@]}"; do
    [[ "$path" == "$known" ]] && return 0
  done
  return 1
}

require_clean_tree() {
  local dirty unexpected=()
  dirty="$(git status --porcelain)"
  [[ -z "$dirty" ]] && return 0

  # IFS= es obligatorio: sin eso `read` recorta el espacio inicial de
  # `git status --porcelain` (" M archivo") y el recorte del path se desalinea.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local path="${line:3}"
    is_act_leftover "$path" || unexpected+=("$line")
  done <<<"$dirty"

  if [[ ${#unexpected[@]} -gt 0 ]]; then
    bad "El arbol de trabajo tiene cambios que no son de la demo."
    note "Guardalos o descartalos y volvé a correr el acto."
    printf '%s\n' "${unexpected[@]}"
    exit 1
  fi

  warn "Limpiando los restos del acto anterior (no hace falta reset completo):"
  git status --short | sed 's/^/      /'
  rm -f "${ACT_ARTIFACTS[@]}"
  git checkout -- "${ACT_TOUCHED_FILES[@]}" 2>/dev/null || true
  git switch -q main 2>/dev/null || true

  if [[ -n "$(git status --porcelain)" ]]; then
    bad "No pude dejar el arbol limpio. Corré: bash demo/reset.sh"
    git status --short
    exit 1
  fi
  ok "Arbol limpio, en main."
}

require_cluster() {
  if ! $KUBECTL cluster-info >/dev/null 2>&1; then
    bad "No encuentro el cluster '${KUBE_CONTEXT}'."
    note "Levantalo con: make up"
    exit 1
  fi
}

# El plugin 'kubectl argo rollouts' NO acepta flags antes del nombre del plugin:
# --context tiene que ir al final. Por eso no usa $KUBECTL.
rollout_view() {
  if command -v kubectl-argo-rollouts >/dev/null 2>&1; then
    kubectl argo rollouts get rollout orders -n "$APP_NAMESPACE" --context "$KUBE_CONTEXT" "$@"
  else
    $KUBECTL -n "$APP_NAMESPACE" get rollout orders -o wide
    $KUBECTL -n "$APP_NAMESPACE" get pods -l app.kubernetes.io/name=orders --show-labels
  fi
}
