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

if command -v kubectl-argo-rollouts >/dev/null 2>&1; then
  warn "Abriendo el watch. Salí con Ctrl+C cuando veas 'Degraded' / el rollback."
  if [[ "${DEMO_AUTO:-0}" == "1" ]]; then
    timeout 300 kubectl --context "$KUBE_CONTEXT" argo rollouts get rollout orders \
      -n "$APP_NAMESPACE" --watch 2>&1 | head -120 || true
  else
    kubectl --context "$KUBE_CONTEXT" argo rollouts get rollout orders -n "$APP_NAMESPACE" --watch || true
  fi
else
  for _ in $(seq 1 30); do
    clear
    rollout_view
    $KUBECTL -n "$APP_NAMESPACE" get analysisrun -o wide 2>/dev/null || true
    sleep 10
  done
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
