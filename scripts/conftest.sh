#!/usr/bin/env bash
# Wrapper de conftest: usa el binario local si existe, si no cae a Docker.
#
# Por que: queremos que `npm run policy` funcione en cualquier laptop sin pedirle
# a nadie instalar nada mas que Docker. El gate tiene que ser el mismo en los dos
# caminos, asi que la version de la imagen esta pinneada.
set -euo pipefail

CONFTEST_VERSION="${CONFTEST_VERSION:-v0.56.0}"
# OJO: TARGET tiene que estar DENTRO del repo. Cuando no hay conftest local, esto
# corre en un contenedor que solo monta el repo, asi que una ruta de /tmp no existe
# ahi adentro. Para probar un manifiesto temporal, usa .harness-tmp/ (ignorado por git).
TARGET="${1:-deploy/k8s}"
POLICY_DIR="${POLICY_DIR:-policy}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -d "$TARGET" && ! -f "$TARGET" ]]; then
  echo "error: no existe '$TARGET'" >&2
  exit 1
fi

echo "==> Politicas OPA/Conftest sobre '$TARGET' (gate determinista)"

if command -v conftest >/dev/null 2>&1; then
  echo "    usando conftest local: $(conftest --version | head -1)"
  exec conftest test --policy "$POLICY_DIR" --all-namespaces "$TARGET"
fi

if ! command -v docker >/dev/null 2>&1; then
  cat >&2 <<'MSG'
error: no encontre ni `conftest` ni `docker`.

Instala una de las dos cosas:
  - conftest: https://www.conftest.dev/install/
  - Docker:   https://docs.docker.com/get-docker/
MSG
  exit 1
fi

echo "    conftest no esta instalado: usando docker (openpolicyagent/conftest:${CONFTEST_VERSION})"
exec docker run --rm \
  --user "$(id -u):$(id -g)" \
  --network none \
  -v "$REPO_ROOT:/project:ro" \
  -w /project \
  "openpolicyagent/conftest:${CONFTEST_VERSION}" \
  test --policy "$POLICY_DIR" --all-namespaces "$TARGET"
