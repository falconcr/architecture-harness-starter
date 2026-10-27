#!/usr/bin/env bash
# PreToolUse hook: bloquea la lectura de archivos con credenciales.
#
# Cubre las herramientas de lectura (Read, Grep, Glob, Edit) y los comandos de
# shell que sirven para leer (cat, less, head, tail, strings, base64, grep, cp,
# scp, curl -T...). No pretende ser inviolable: pretende que el camino facil
# este cerrado y que el intento quede registrado.
#
# Probalo:
#   echo '{"tool_name":"Read","tool_input":{"file_path":".env"}}' \
#     | bash .claude/hooks/guard-secret-read.sh; echo $?
set -uo pipefail

payload="$(cat)"

read -r tool_name target <<<"$(printf '%s' "$payload" | python3 -c '
import json,sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
ti = data.get("tool_input") or {}
target = (
    ti.get("file_path")
    or ti.get("path")
    or ti.get("pattern")
    or ti.get("command")
    or ""
)
print((data.get("tool_name") or "?"), target.replace("\n", " "))
' 2>/dev/null || true)"

[[ -z "${target:-}" ]] && exit 0

# Patrones de cosas que son secretos o los contienen.
SECRET_REGEX='(^|/|[[:space:]=:"'"'"'])(\.env(\.[A-Za-z0-9_-]+)*([^/A-Za-z0-9_.-]|$)|secrets?\.(ya?ml|json|tfvars|enc)|[^[:space:]]*\.(pem|key|p12|pfx|jks|keystore)|id_(rsa|ed25519|ecdsa)|\.kube/config|kubeconfig([^/[:space:]]*)?|\.aws/credentials|\.docker/config\.json|\.npmrc|\.netrc|\.ssh/|credentials\.json|service-?account.*\.json|\.git-credentials|gh/hosts\.yml)'

# .env.example SI se puede leer: existe justamente para documentar sin secretos.
if grep -Eq '\.env\.example|\.env\.sample|\.env\.template' <<<"$target"; then
  exit 0
fi

grep -Eiq "$SECRET_REGEX" <<<"$target" || exit 0

# Para comandos de Bash, solo bloqueamos si el comando efectivamente lee/copia/manda.
if [[ "$tool_name" == "Bash" ]]; then
  grep -Eq '(^|[[:space:];&|(])(cat|bat|less|more|head|tail|strings|xxd|od|base64|grep|rg|awk|sed|sort|cut|cp|mv|scp|rsync|tar|zip|curl|wget|openssl|dotenv|export|source|\.)([[:space:]]|$)' <<<"$target" || exit 0
fi

cat >&2 <<MSG
BLOQUEADO por .claude/hooks/guard-secret-read.sh

  Herramienta: $tool_name
  Objetivo:    $target

Por que: ADR-003 (docs/adr/003-no-agent-prod-creds.md). Ningun agente lee
credenciales. Un secreto leido por un agente es un secreto que puede terminar en
un log, en un comentario de PR o en un prompt.

Que hacer en su lugar:
  - Para saber QUE configuracion existe: lee .env.example o deploy/k8s/configmap.yaml.
  - Si el cambio necesita un secreto nuevo: documentalo en el PR y que lo cree una
    persona. Las credenciales de CI son efimeras (OIDC), no van al repo.
MSG
exit 2
