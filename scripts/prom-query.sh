#!/usr/bin/env bash
# Consulta instantanea a Prometheus dentro del cluster kind.
#
# Esto es lo que puede hacer canary-analyst: LEER. No hay forma de escribir
# nada al cluster desde aca.
#
# Uso:
#   bash scripts/prom-query.sh 'sum(rate(http_requests_total{app="orders"}[1m]))'
set -euo pipefail

QUERY="${1:?uso: $0 '<consulta promql>'}"
CONTEXT="${KUBE_CONTEXT:-kind-harness}"
NAMESPACE="${PROM_NAMESPACE:-monitoring}"

# Corremos la consulta desde un pod efimero: no hace falta port-forward ni
# exponer Prometheus fuera del cluster.
encoded="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$QUERY")"

raw="$(kubectl --context "$CONTEXT" -n "$NAMESPACE" run "promq-$RANDOM" \
  --rm -i --restart=Never --quiet \
  --image=curlimages/curl:8.11.1 -- \
  -sS "http://prometheus.monitoring.svc.cluster.local:9090/api/v1/query?query=${encoded}" 2>/dev/null)"

python3 -c '
import json, sys

query, raw = sys.argv[1], sys.argv[2].strip()
print(f"consulta: {query}")

try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("respuesta no parseable:")
    print(raw[:800])
    sys.exit(1)

if data.get("status") != "success":
    detail = data.get("error") or raw[:400]
    print("error de prometheus: " + str(detail))
    sys.exit(1)

result = data["data"]["result"]
if not result:
    print("sin resultados (ojo: un gate sin datos es un gate ciego)")
    sys.exit(0)

for series in result:
    labels = series.get("metric", {})
    value = series["value"][1]
    label_text = ", ".join(f"{k}={v}" for k, v in sorted(labels.items())) or "(sin labels)"
    print(f"  {value:>14}   {label_text}")
' "$QUERY" "$raw"
