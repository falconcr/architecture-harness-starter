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

# Todo acto arranca desde main. Si no, el Acto 3 se construye sobre la rama del
# Acto 2 (que lleva FAULT_RATE=0.3 commiteado), el guardrail nuevo rechaza su
# propio manifiesto y el acto aborta. Pasó verificando este repo.
ensure_on_main() {
  local current
  current="$(git branch --show-current)"
  [[ "$current" == "main" ]] && return 0
  note "Volviendo a main (estabas en '$current')."
  git switch -q main
}

require_clean_tree() {
  local dirty unexpected=()
  dirty="$(git status --porcelain)"
  if [[ -z "$dirty" ]]; then
    ensure_on_main
    return 0
  fi

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
  ensure_on_main

  if [[ -n "$(git status --porcelain)" ]]; then
    bad "No pude dejar el arbol limpio. Corré: bash demo/reset.sh"
    git status --short
    exit 1
  fi
  ok "Arbol limpio, en main."
}

# Distingue los tres casos, porque el consejo correcto es distinto en cada uno.
# El que mas duele en escena es el tercero: despues de reiniciar o suspender la
# laptop el cluster existe y esta sano, pero el API server tarda ~1 minuto en
# volver. Mandarte a `make up` ahi es perder 6 minutos por nada.
# Antes de culpar al cluster, hay que descartar lo mas comun: que la herramienta
# no este en el PATH de ESTA terminal.
#
# El caso real que motivo esto: kubectl instalado por snap vive en /snap/bin, que
# algunos ~/.bashrc no incluyen. kind y docker (en /usr/local/bin) si se
# encontraban, asi que el script veia "el cluster existe" + "kubectl falla" y
# concluia "el API no responde", y esperaba dos minutos por nada. El mensaje tiene
# que decir que falta y donde esta.
TOOL_SEARCH_DIRS=(/snap/bin /usr/local/bin /usr/bin /bin "$HOME/.local/bin" "$HOME/bin")

require_tools() {
  local missing=() tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0

  bad "Falta en el PATH de esta terminal: ${missing[*]}"
  echo ""
  for tool in "${missing[@]}"; do
    local found="" dir
    for dir in "${TOOL_SEARCH_DIRS[@]}"; do
      [[ -x "$dir/$tool" ]] && { found="$dir/$tool"; break; }
    done
    if [[ -n "$found" ]]; then
      note "'$tool' SI esta instalado, en $found"
      note "    pero $(dirname "$found") no esta en tu PATH. Arreglalo asi:"
      printf '\n      export PATH="%s:$PATH"\n\n' "$(dirname "$found")"
      note "    y para que quede: agregá esa linea a ~/.bashrc"
    else
      note "'$tool' no esta instalado. Ver 'Requisitos' en README.md"
    fi
  done
  exit 1
}

require_cluster() {
  local cluster="${CLUSTER_NAME:-harness}"

  # Sin esto, un kubectl ausente se confunde con un cluster caido.
  require_tools kubectl kind docker

  $KUBECTL cluster-info >/dev/null 2>&1 && return 0

  # 1) El cluster no existe.
  if ! kind get clusters 2>/dev/null | grep -qx "$cluster"; then
    bad "No existe el cluster kind '${cluster}'."
    note "Crealo con:  make up"
    exit 1
  fi

  # 2) Existe pero sus contenedores estan detenidos (pasa al reiniciar Docker).
  local stopped
  stopped="$(docker ps -a --filter "label=io.x-k8s.kind.cluster=${cluster}" \
    --filter 'status=exited' --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')"
  if [[ -n "${stopped// /}" ]]; then
    warn "El cluster '${cluster}' existe pero sus nodos estan detenidos: ${stopped}"
    note "Arrancalos con:  docker start ${stopped}"
    note "y volvé a correr el acto en un minuto."
    exit 1
  fi

  # 3) Existe y corre, pero el API server no responde. Puede ser que este
  #    arrancando (reinicio/suspension) o que haya un problema de verdad, asi que
  #    mostramos EL ERROR REAL de kubectl en vez de esconderlo: diagnosticar a
  #    ciegas cuesta mas que no diagnosticar.
  local kubectl_error
  kubectl_error="$($KUBECTL cluster-info 2>&1 >/dev/null || true)"

  # Caso aparte, y el mas confuso de todos: el contexto no existe en el
  # kubeconfig que lee ESTA terminal. No es transitorio, asi que esperar no sirve.
  # Pasa cuando hay un KUBECONFIG exportado apuntando a otro cluster, algo
  # normalisimo en una laptop con varios clusters. (Caso real: una terminal con
  # KUBECONFIG de otro proyecto; kind y docker funcionaban, kubectl no.)
  if grep -qiE 'context .* does not exist|no context exists' <<<"$kubectl_error"; then
    local effective_config="${KUBECONFIG:-$HOME/.kube/config}"
    bad "El contexto '${KUBE_CONTEXT}' no existe en el kubeconfig de esta terminal."
    echo ""
    note "kubeconfig en uso:  ${effective_config}"
    if [[ -n "${KUBECONFIG:-}" ]]; then
      note "  (viene de la variable KUBECONFIG exportada en esta terminal)"
    fi
    note "contextos que ve:"
    kubectl config get-contexts -o name 2>/dev/null | sed 's/^/      /' || true
    echo ""

    if [[ -n "${KUBECONFIG:-}" ]] \
      && kubectl --kubeconfig "$HOME/.kube/config" config get-contexts -o name 2>/dev/null \
         | grep -qx "${KUBE_CONTEXT}"; then
      note "El contexto SI existe en ~/.kube/config. Tenes un KUBECONFIG apuntando a otro lado."
      note "Arreglalo en esta terminal con:"
      printf '\n      unset KUBECONFIG\n\n'
      note "(o abrí una terminal nueva)"
    else
      note "Regeneralo desde kind con:"
      printf '\n      kind export kubeconfig --name %s\n\n' "$cluster"
    fi
    exit 1
  fi

  warn "El cluster '${cluster}' corre, pero kubectl no puede hablarle."
  echo ""
  note "Esto es lo que dice kubectl (el dato que importa):"
  printf '%s\n' "${kubectl_error:-(sin mensaje)}" | sed 's/^/      /'
  echo ""
  note "Puede ser que este arrancando (pasa al reiniciar o suspender la laptop)."
  note "Esperando hasta 2 minutos..."
  for _ in $(seq 1 24); do
    sleep 5
    if $KUBECTL cluster-info >/dev/null 2>&1; then
      ok "El cluster respondio. Seguimos."
      return 0
    fi
    printf '  %s. esperando al API server de %s...%s\n' "$DIM" "$cluster" "$RESET"
  done

  bad "El cluster '${cluster}' no respondio en 2 minutos."
  echo ""
  note "Diagnostico, en este orden:"
  note "  1. kubectl que estas usando:   command -v kubectl"
  note "  2. kubeconfig que lee:         echo \"\$KUBECONFIG\"  (vacio = ~/.kube/config)"
  note "  3. a donde apunta:             kubectl config view --minify --context ${KUBE_CONTEXT} -o jsonpath='{.clusters[0].cluster.server}'"
  note "  4. proxy que puede romperlo:   env | grep -i proxy"
  note "     (si hay HTTPS_PROXY sin NO_PROXY=127.0.0.1, kubectl no llega al API local)"
  note "  5. responde el puerto?:        curl -sk -o /dev/null -w '%{http_code}\\n' \\"
  note "                                   \"\$(kubectl config view --minify --context ${KUBE_CONTEXT} -o jsonpath='{.clusters[0].cluster.server}')/livez\""
  note "  6. logs del nodo:              docker logs ${cluster}-control-plane --tail 30"
  echo ""
  note "Si nada de eso explica nada:   make down && make up"
  exit 1
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
