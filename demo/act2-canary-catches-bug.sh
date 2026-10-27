#!/usr/bin/env bash
# =============================================================================
# ACTO 2 — "El canary atrapa el bug"
#
# Que se demuestra: un bug que ningun test unitario puede ver (porque depende de
# produccion real) lo atrapa un gate determinista en el deploy, y el rollback
# ocurre sin que nadie apruebe nada.
#
# El bug: FAULT_RATE=0.3, o sea 3 de cada 10 requests devuelven 500.
# El gate: AnalysisTemplate "error-rate" (umbral 5 %) contra Prometheus.
#
# Duracion: ~6 minutos (el analisis tarda ~1,5 min por diseno).
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BRANCH="${ACT2_BRANCH:-demo/acto-2-canary}"
BUG_TAG="v2-bug"

banner "ACTO 2 — El canary atrapa el bug"

require_cluster

say "0. Punto de partida: el Rollout 'orders' esta sano en la revision estable"
run rollout_view
pause_demo

say "1. Construimos la version con el bug y la cargamos en el cluster"
note "orders:${BUG_TAG} es el mismo codigo; el bug se activa con FAULT_RATE=0.3."
note "(En un repo real seria un bug de verdad; aca necesitamos que sea reproducible)."
run docker build -t "orders:${BUG_TAG}" .
run kind load docker-image "orders:${BUG_TAG}" --name harness
pause_demo

say "2. Desplegar = commitear. No hay otra via al cluster (ADR-003)"
require_clean_tree
git switch -c "$BRANCH" 2>/dev/null || git switch "$BRANCH"

python3 - "$BUG_TAG" <<'PY'
import sys
from pathlib import Path

tag = sys.argv[1]
path = Path("deploy/k8s/rollout.yaml")
manifest = path.read_text()

manifest = manifest.replace("image: orders:v1", f"image: orders:{tag}")
manifest = manifest.replace('''            - name: APP_VERSION
              value: v1''', f'''            - name: APP_VERSION
              value: {tag}''')
manifest = manifest.replace('''            - name: FAULT_RATE
              value: "0"''', '''            - name: FAULT_RATE
              value: "0.3"''')

path.write_text(manifest)
print("  deploy/k8s/rollout.yaml:  image -> orders:" + tag + ",  FAULT_RATE -> 0.3")
PY

run git --no-pager diff -- deploy/k8s/rollout.yaml

note "Las policies siguen pasando: el manifiesto es VALIDO. El bug no es de forma."
run npm run policy
pause_demo

say "3. Commit + push: a partir de aca, Argo CD manda"
run git add deploy/k8s/rollout.yaml
run git commit -q -m "feat: nueva version de orders (orders:${BUG_TAG})"
run git push -u origin "$BRANCH"

note "Apuntamos Argo CD a esta rama para no necesitar un merge en vivo."
run make --no-print-directory argocd-app GIT_BRANCH="$BRANCH"
run make --no-print-directory sync
pause_demo

say "4. Argo Rollouts manda 20 % del trafico a la version nueva"
note "1 de 5 replicas = 20 %. El generador de carga ya esta pegandole al Service."
note "El AnalysisTemplate espera 30 s, mide 3 veces cada 20 s, y con UNA medicion"
note "fallida aborta. Mirá la columna de los AnalysisRun."
echo ""

# Espera el veredicto del gate.
#
# Por que no alcanza mirar status.phase: "Progressing" significa lo mismo para un
# canary en vuelo y para el restart de pods que hace demo/reset.sh, y despues de
# que Argo CD cambia el spec la fase sigue diciendo "Healthy" de la revision
# anterior por unos segundos. Apoyarse en la fase daba un falso "el canary paso".
# Las senales inequivocas del Rollout son:
#
#   spec image      != el tag nuevo        -> Argo CD todavia no sincronizo
#   currentPodHash  != stableRS            -> hay un canary EN VUELO
#   status.abort == true  /  Degraded      -> el gate dijo NO y revirtio
#   currentPodHash  == stableRS + Healthy  -> promovido
rollout_field() {
  $KUBECTL -n "$APP_NAMESPACE" get rollout orders -o jsonpath="{$1}" 2>/dev/null || echo ''
}

analysis_summary() {
  $KUBECTL -n "$APP_NAMESPACE" get analysisrun \
    -o jsonpath='{range .items[*]}{.metadata.name}={.status.phase} {end}' 2>/dev/null || echo ''
}

# Fase 1: que Argo CD sincronice y que arranque de verdad un canary.
wait_for_canary_start() {
  local expected_image="$1"
  for _ in $(seq 1 48); do
    local image current stable abort phase
    image="$(rollout_field '.spec.template.spec.containers[0].image')"
    current="$(rollout_field .status.currentPodHash)"
    stable="$(rollout_field .status.stableRS)"
    abort="$(rollout_field .status.abort)"
    phase="$(rollout_field .status.phase)"

    if [[ "$abort" == "true" || "$phase" == "Degraded" ]]; then
      return 0
    fi

    if [[ "$image" != "$expected_image" ]]; then
      printf '  %s. esperando el sync de Argo CD (el Rollout todavia dice %s)%s\n' \
        "$DIM" "${image:-?}" "$RESET"
      sleep 5
      continue
    fi

    if [[ -n "$current" && "$current" != "$stable" ]]; then
      ok "Canary en vuelo: revision $current contra estable $stable"
      return 0
    fi

    printf '  %s. esperando que arranque el canary (fase=%s)%s\n' "$DIM" "${phase:-?}" "$RESET"
    sleep 5
  done
  bad "No arranco ningun canary en 4 minutos."
  note "Casi siempre es que Argo CD no sincronizo. Mirá:"
  note "  kubectl --context $KUBE_CONTEXT -n argocd get application orders"
  note "  make rollout-status"
  exit 1
}

# Fase 2: el veredicto.
wait_for_verdict() {
  wait_for_canary_start "$1"
  for _ in $(seq 1 72); do
    local current stable abort phase
    current="$(rollout_field .status.currentPodHash)"
    stable="$(rollout_field .status.stableRS)"
    abort="$(rollout_field .status.abort)"
    phase="$(rollout_field .status.phase)"

    if [[ "$abort" == "true" || "$phase" == "Degraded" ]]; then
      echo ""
      bad "El gate dijo NO: analisis fallido, Argo Rollouts abortó y volvio a la version estable."
      note "Mensaje del Rollout: $(rollout_field .status.message)"
      return 0
    fi
    if [[ "$phase" == "Healthy" && "$current" == "$stable" ]]; then
      echo ""
      ok "El gate dijo SI: el analisis paso y la version se promovio."
      return 0
    fi

    printf '  %s. fase=%s canary=%s estable=%s  analisis: %s%s\n' \
      "$DIM" "${phase:-?}" "${current:-?}" "${stable:-?}" "$(analysis_summary)" "$RESET"
    sleep 10
  done
  warn "El gate no decidio en 12 minutos. Mirá 'make analysis'."
}

if [[ "${DEMO_AUTO:-0}" == "1" ]]; then
  # Modo no interactivo (verificacion): no abrimos el watch, esperamos el veredicto.
  wait_for_verdict "orders:${BUG_TAG}"
  rollout_view
elif command -v kubectl-argo-rollouts >/dev/null 2>&1; then
  warn "Abriendo el watch. Salí con Ctrl+C cuando veas 'Degraded' y el rollback."
  kubectl argo rollouts get rollout orders -n "$APP_NAMESPACE" --context "$KUBE_CONTEXT" --watch || true
else
  warn "Sin el plugin argo rollouts: refresco cada 10 s hasta el veredicto."
  wait_for_verdict "orders:${BUG_TAG}"
  rollout_view
  $KUBECTL -n "$APP_NAMESPACE" get analysisrun -o wide 2>/dev/null || true
fi

say "5. Que vio el gate"
run make --no-print-directory analysis
echo ""
run bash scripts/prom-query.sh 'sum(rate(http_requests_total{app="orders",status=~"5.."}[1m])) / sum(rate(http_requests_total{app="orders"}[1m]))'
pause_demo

say "6. Estado final: volvio solo a la version estable"
run rollout_view
echo ""
ok "Nadie aprobo el rollback. Nadie estaba mirando. El gate decidio."
pause_demo

say "7. Ahora el agente explica (solo lectura)"
cat <<'MSG'

  En Claude Code:

    > Usa el subagente canary-analyst para explicarme por que fallo el canary
    > del Rollout orders.

  canary-analyst puede leer Prometheus, los AnalysisRun y los logs.
  NO puede promover, NO puede abortar, NO puede tocar el cluster.
  Llega despues del rollback, no en lugar del rollback.

  Lo que va a decir:
    - error-rate del canary: ~0,30 (umbral 0,05) -> FALLO
    - latency-p95: normal -> el problema no es de performance
    - veredicto: el gate decidio bien; la version nueva devuelve 500 en ~3 de
      cada 10 requests
    - recomendacion: para una persona, no una accion propia

MSG
pause_demo

say "8. Plan B / reset"
note "Salida real guardada: demo/act2-output.txt"
note "Para dejar todo como estaba:  bash demo/reset.sh"
echo ""
ok "Fin del Acto 2."
