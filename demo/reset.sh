#!/usr/bin/env bash
# Deja el repo y el cluster listos para repetir la demo desde cero.
#
# No borra el cluster (eso es `make down`): solo deshace lo que hacen los actos.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Ramas EFIMERAS: las crean los actos en vivo y se borran en cada reset,
# local y en origin (si no, el siguiente push falla por non-fast-forward).
EPHEMERAL_BRANCHES=(
  "demo/acto-1-violacion"
  "demo/acto-2-canary"
  "fix/fault-rate-guard"
)

# Ramas PERMANENTES de plan B: NO se tocan nunca. Son las que sostienen la demo
# si algo falla en escena (el run fallido grabado del Acto 1 y el PR del Acto 3).
#   demo/acto-1-violacion  en origin  -> PR con el run de CI fallido
#   demo/acto-3-fix        en origin  -> el fix listo para abrir el PR
PRESERVE_ON_ORIGIN=(
  "demo/acto-1-violacion"
  "demo/acto-3-fix"
)

preserved_on_origin() {
  local branch="$1"
  for keep in "${PRESERVE_ON_ORIGIN[@]}"; do
    [[ "$branch" == "$keep" ]] && return 0
  done
  return 1
}

banner "RESET de la demo"

say "1. Volver a main y descartar los cambios de los actos"
git switch main 2>/dev/null || git switch -c main
run git reset --hard HEAD
run git clean -fd src/infrastructure/db.ts test/fault-rate-guard.test.ts policy/fault-injection.rego 2>/dev/null || true
# Por si quedaron archivos creados por los actos y ya estaban trackeados en otra rama.
rm -f src/infrastructure/db.ts test/fault-rate-guard.test.ts policy/fault-injection.rego
git checkout -- . 2>/dev/null || true

say "2. Borrar las ramas efimeras de la demo"
for branch in "${EPHEMERAL_BRANCHES[@]}"; do
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git branch -D "$branch" >/dev/null && note "borrada local: $branch"
  fi

  if preserved_on_origin "$branch"; then
    note "conservada en origin: $branch (es plan B: sostiene el run fallido grabado)"
    continue
  fi

  if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    if git push origin --delete "$branch" >/dev/null 2>&1; then
      note "borrada en origin: $branch"
    else
      warn "no pude borrar $branch en origin (borrala a mano antes de repetir el acto)"
    fi
  fi
done

say "3. Verificar que main esta verde"
run npm run verify

if $KUBECTL cluster-info >/dev/null 2>&1; then
  say "4. Volver el cluster a la version estable"
  note "Argo CD vuelve a apuntar a main; eso revierte el manifiesto del Acto 2."
  run make --no-print-directory argocd-app GIT_BRANCH=main
  run make --no-print-directory sync

  # Un Rollout abortado se queda en Degraded hasta que cambia el pod template o
  # se reinicia. Como el manifiesto ya es el sano, alcanza con reiniciarlo.
  if command -v kubectl-argo-rollouts >/dev/null 2>&1; then
    run kubectl argo rollouts restart orders -n "$APP_NAMESPACE" --context "$KUBE_CONTEXT" || true
  else
    run $KUBECTL -n "$APP_NAMESPACE" delete pods -l app.kubernetes.io/name=orders --wait=false || true
  fi

  note "Esperando que el Rollout vuelva a estar sano..."
  for _ in $(seq 1 40); do
    phase="$($KUBECTL -n "$APP_NAMESPACE" get rollout orders -o jsonpath='{.status.phase}' 2>/dev/null || echo '')"
    [[ "$phase" == "Healthy" ]] && break
    sleep 5
  done
  run rollout_view
else
  say "4. Sin cluster: nada que resetear ahi"
  note "Para levantarlo: make up"
fi

echo ""
ok "Todo listo para repetir la demo. Empezá con: bash demo/act1-arch-violation.sh"
