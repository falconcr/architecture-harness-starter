# architecture-harness-starter
#
# "Los agentes proponen, los gates deterministas deciden,
#  los humanos son duenos de lo irreversible."
#
# Todo lo que hace falta para la demo cabe en `make up` y `make down`.
# No hay cuenta de nube: kind + Argo CD + Argo Rollouts + Prometheus en tu laptop.

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Parametros (todos sobreescribibles: make up KIND_NODE_IMAGE=...)
# ---------------------------------------------------------------------------
CLUSTER            ?= harness
KUBE_CONTEXT       ?= kind-$(CLUSTER)
KIND_NODE_IMAGE    ?= kindest/node:v1.27.3
ARGOCD_VERSION     ?= v2.13.3
ROLLOUTS_VERSION   ?= v1.7.2
IMAGE              ?= orders
TAG                ?= v1
APP_NAMESPACE      ?= orders

# Argo CD lee del remoto de Git: detectamos tu fork y tu rama para que esto
# funcione sin editar YAML (ver deploy/argocd/README.md).
GIT_REPO_URL ?= $(shell git remote get-url origin 2>/dev/null)
GIT_BRANCH   ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)

KUBECTL := kubectl --context $(KUBE_CONTEXT)

# ---------------------------------------------------------------------------
help: ## Muestra esta ayuda
	@echo ""
	@echo "  architecture-harness-starter"
	@echo "  Los agentes proponen, los gates deterministas deciden,"
	@echo "  los humanos son duenos de lo irreversible."
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ===========================================================================
# GATES DETERMINISTAS (lo mismo que corre CI)
# ===========================================================================
.PHONY: verify lint test arch policy
verify: ## Corre TODOS los gates deterministas (lo mismo que CI)
	npm run verify

lint: ## Lint
	npm run lint

test: ## Tests unitarios
	npm test

arch: ## Fitness functions de arquitectura (ADR-001, ADR-002)
	npm run arch:check

policy: ## Politicas OPA/Conftest sobre deploy/k8s
	npm run policy

# ===========================================================================
# CD LOCAL
# ===========================================================================
.PHONY: up
up: preflight cluster argocd rollouts prometheus build load argocd-app wait ## Levanta TODO desde cero (~6-8 min la primera vez)
	@echo ""
	@echo "=========================================================="
	@echo " Listo. El cluster '$(CLUSTER)' esta corriendo."
	@echo ""
	@echo "   make rollout-status     ver el Rollout 'orders'"
	@echo "   make argocd-ui          UI de Argo CD (https://localhost:8080)"
	@echo "   make argocd-password    password de admin"
	@echo "   make prom-ui            Prometheus (http://localhost:9090)"
	@echo "   make smoke              pegarle al servicio"
	@echo ""
	@echo "   Demo:  bash demo/act1-arch-violation.sh"
	@echo "=========================================================="

.PHONY: preflight
preflight: ## Verifica que tengas las herramientas necesarias
	@missing=0
	for bin in docker kind kubectl node npm git; do
	  if ! command -v $$bin >/dev/null 2>&1; then
	    missing=1
	    # Lo mas comun no es que falte, es que su directorio no este en el PATH
	    # de esta terminal (kubectl por snap vive en /snap/bin, que algunos
	    # ~/.bashrc no incluyen). Decimos donde esta, no solo que falta.
	    found=""
	    for dir in /snap/bin /usr/local/bin /usr/bin /bin "$$HOME/.local/bin" "$$HOME/bin"; do
	      if [ -x "$$dir/$$bin" ]; then found="$$dir/$$bin"; break; fi
	    done
	    if [ -n "$$found" ]; then
	      echo "FALTA EN EL PATH: $$bin  (esta instalado en $$found)"
	      echo "    export PATH=\"$$(dirname $$found):\$$PATH\"      # y agregalo a ~/.bashrc"
	    else
	      echo "NO INSTALADO: $$bin"
	    fi
	  fi
	done
	if [ "$$missing" = "1" ]; then
	  echo ""
	  echo "Requisitos: Docker, kind, kubectl, Node 22, git. Ver README.md"
	  exit 1
	fi
	if ! docker info >/dev/null 2>&1; then
	  echo "Docker no esta corriendo."; exit 1
	fi
	node_major=$$(node -v | sed 's/^v\([0-9]*\).*/\1/')
	if [ "$$node_major" -lt 22 ]; then
	  echo "Node 22+ requerido (tenes $$(node -v))."; exit 1
	fi
	# Un KUBECONFIG apuntando a otro cluster hace que kubectl diga
	# 'context "kind-harness" does not exist' y parezca que el cluster esta roto.
	# Es el tropiezo mas comun en una laptop con varios clusters.
	if [ -n "$${KUBECONFIG:-}" ]; then
	  echo "AVISO: tenes KUBECONFIG exportado -> $${KUBECONFIG:-}"
	  if ! kubectl config get-contexts -o name 2>/dev/null | grep -qx "$(KUBE_CONTEXT)"; then
	    echo "       y ese kubeconfig NO tiene el contexto '$(KUBE_CONTEXT)'."
	    echo "       Arreglalo con:   unset KUBECONFIG"
	    exit 1
	  fi
	  echo "       (tiene el contexto $(KUBE_CONTEXT), seguimos)"
	fi
	if [ -z "$(GIT_REPO_URL)" ]; then
	  echo ""
	  echo "No hay remoto 'origin' configurado."
	  echo "Argo CD lee los manifiestos desde GitHub, asi que necesita un repo remoto:"
	  echo "    gh repo create architecture-harness-starter --public --source=. --push"
	  echo "O pasale uno:  make up GIT_REPO_URL=https://github.com/tu-usuario/tu-fork.git"
	  exit 1
	fi
	if ! command -v kubectl-argo-rollouts >/dev/null 2>&1; then
	  echo "AVISO: falta el plugin 'kubectl argo rollouts' (opcional, pero la demo se ve mucho mejor con el)."
	  echo "       make install-rollouts-plugin"
	fi
	echo "==> preflight ok"

.PHONY: cluster
cluster: ## Crea el cluster kind 'harness'
	@if kind get clusters 2>/dev/null | grep -qx "$(CLUSTER)"; then
	  echo "==> el cluster '$(CLUSTER)' ya existe"
	else
	  echo "==> creando cluster kind '$(CLUSTER)' ($(KIND_NODE_IMAGE))"
	  kind create cluster --name $(CLUSTER) --image $(KIND_NODE_IMAGE) --wait 120s
	fi
	$(KUBECTL) cluster-info >/dev/null

.PHONY: argocd
argocd: ## Instala Argo CD
	@echo "==> instalando Argo CD $(ARGOCD_VERSION)"
	$(KUBECTL) create namespace argocd --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) apply -n argocd -f \
	  https://raw.githubusercontent.com/argoproj/argo-cd/$(ARGOCD_VERSION)/manifests/install.yaml
	echo "==> esperando a Argo CD (puede tardar un par de minutos)"
	$(KUBECTL) -n argocd rollout status deploy/argocd-repo-server --timeout=300s
	$(KUBECTL) -n argocd rollout status deploy/argocd-server --timeout=300s
	$(KUBECTL) -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

.PHONY: rollouts
rollouts: ## Instala Argo Rollouts
	@echo "==> instalando Argo Rollouts $(ROLLOUTS_VERSION)"
	$(KUBECTL) create namespace argo-rollouts --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) apply -n argo-rollouts -f \
	  https://github.com/argoproj/argo-rollouts/releases/download/$(ROLLOUTS_VERSION)/install.yaml
	$(KUBECTL) -n argo-rollouts rollout status deploy/argo-rollouts --timeout=300s

.PHONY: prometheus
prometheus: ## Instala el Prometheus minimo que alimenta el gate del canary
	@echo "==> instalando Prometheus (1 pod, sin operador)"
	$(KUBECTL) apply -f deploy/monitoring/prometheus.yaml
	$(KUBECTL) -n monitoring rollout status deploy/prometheus --timeout=180s

.PHONY: build
build: ## Construye la imagen del servicio
	@echo "==> docker build $(IMAGE):$(TAG)"
	docker build -t $(IMAGE):$(TAG) .

.PHONY: load
load: ## Carga la imagen en el cluster kind (no hay registry)
	@echo "==> kind load $(IMAGE):$(TAG) -> cluster $(CLUSTER)"
	kind load docker-image $(IMAGE):$(TAG) --name $(CLUSTER)

.PHONY: argocd-app
argocd-app: ## Registra/actualiza la Application de Argo CD apuntando a deploy/k8s
	@echo "==> Argo CD Application -> $(GIT_REPO_URL) @ $(GIT_BRANCH) (path deploy/k8s)"
	sed -e 's|__GIT_REPO_URL__|$(GIT_REPO_URL)|' \
	    -e 's|__GIT_BRANCH__|$(GIT_BRANCH)|' \
	    deploy/argocd/application.yaml.tpl > deploy/argocd/application.yaml
	$(KUBECTL) apply -f deploy/argocd/application.yaml

.PHONY: wait
wait: ## Espera a que el Rollout 'orders' este sano
	@echo "==> esperando el primer sync de Argo CD"
	$(MAKE) --no-print-directory sync
	for i in $$(seq 1 60); do
	  if $(KUBECTL) -n $(APP_NAMESPACE) get rollout orders >/dev/null 2>&1; then break; fi
	  sleep 5
	done
	$(KUBECTL) -n $(APP_NAMESPACE) wait --for=condition=available rollout/orders --timeout=300s 2>/dev/null \
	  || $(KUBECTL) -n $(APP_NAMESPACE) get rollout orders -o wide
	$(KUBECTL) -n $(APP_NAMESPACE) get pods -o wide

.PHONY: sync
sync: ## Fuerza a Argo CD a releer Git (no evita el gate: solo acelera el poll)
	@$(KUBECTL) -n argocd annotate application orders \
	  argocd.argoproj.io/refresh=hard --overwrite >/dev/null
	echo "==> refresh solicitado a Argo CD"

.PHONY: down
down: ## Destruye el cluster y todo lo que creamos
	@echo "==> borrando cluster kind '$(CLUSTER)'"
	kind delete cluster --name $(CLUSTER) || true
	rm -f deploy/argocd/application.yaml
	echo "==> listo. No queda nada corriendo."

# ===========================================================================
# OBSERVAR (todo solo-lectura: esto es lo que puede hacer canary-analyst)
# ===========================================================================
.PHONY: rollout-status
rollout-status: ## Estado del Rollout 'orders'
	@if command -v kubectl-argo-rollouts >/dev/null 2>&1; then
	  # Ojo: el plugin exige que --context vaya DESPUES de 'argo rollouts'.
	  kubectl argo rollouts get rollout orders -n $(APP_NAMESPACE) --context $(KUBE_CONTEXT)
	else
	  echo "(sin plugin argo rollouts: mostrando el recurso crudo)"
	  $(KUBECTL) -n $(APP_NAMESPACE) get rollout orders -o yaml | head -60
	fi

.PHONY: rollout-watch
rollout-watch: ## Sigue el Rollout en vivo (lo que se proyecta en el Acto 2)
	@kubectl argo rollouts get rollout orders -n $(APP_NAMESPACE) --context $(KUBE_CONTEXT) --watch

.PHONY: analysis
analysis: ## Muestra los AnalysisRun y por que pasaron o fallaron
	@$(KUBECTL) -n $(APP_NAMESPACE) get analysisrun -o wide || true
	for ar in $$($(KUBECTL) -n $(APP_NAMESPACE) get analysisrun -o name 2>/dev/null); do
	  echo ""
	  echo "--- $$ar ---"
	  $(KUBECTL) -n $(APP_NAMESPACE) get $$ar \
	    -o jsonpath='{range .status.metricResults[*]}{.name}{": phase="}{.phase}{" exitosas="}{.successful}{" fallidas="}{.failed}{"\n"}{range .measurements[*]}{"    valor="}{.value}{" fase="}{.phase}{"\n"}{end}{end}'
	done

.PHONY: canary-report
canary-report: ctx-check ## TODA la evidencia del canary en un comando (lo que usa canary-analyst)
	@echo "============================================================"
	echo " INFORME DEL CANARY - $$(date '+%Y-%m-%d %H:%M:%S')"
	echo " Solo lectura. Nada de esto modifica el cluster."
	echo "============================================================"
	echo ""
	echo "--- 1. ROLLOUT -------------------------------------------"
	$(KUBECTL) -n $(APP_NAMESPACE) get rollout orders -o jsonpath='fase:            {.status.phase}{"\n"}mensaje:         {.status.message}{"\n"}abortado:        {.status.abort}{"\n"}imagen deseada:  {.spec.template.spec.containers[0].image}{"\n"}revision canary: {.status.currentPodHash}{"\n"}revision estable:{.status.stableRS}{"\n"}replicas listas: {.status.readyReplicas}/{.spec.replicas}{"\n"}'
	echo ""
	echo "--- 2. UMBRALES DECLARADOS (deploy/k8s/analysistemplate.yaml) ---"
	grep -E 'name: (error-rate|latency-p95)|successCondition|interval:|count:|failureLimit' 	  deploy/k8s/analysistemplate.yaml | sed 's/^ */    /'
	echo ""
	echo "--- 3. MEDICIONES REALES ---------------------------------"
	if ! $(KUBECTL) -n $(APP_NAMESPACE) get analysisrun -o name 2>/dev/null | grep -q .; then
	  echo "    NO HAY NINGUN AnalysisRun."
	  echo "    Un gate sin datos es un gate ciego: eso es un hallazgo, no un detalle."
	  echo "    Si acabas de resetear la demo, todavia no corrio ningun analisis."
	else
	  for ar in $$($(KUBECTL) -n $(APP_NAMESPACE) get analysisrun -o name 2>/dev/null); do
	    echo "    $$ar"
	    $(KUBECTL) -n $(APP_NAMESPACE) get $$ar -o jsonpath='{range .status.metricResults[*]}      {.name}: fase={.phase} exitosas={.successful} fallidas={.failed}{"\n"}{range .measurements[*]}          valor={.value} fase={.phase}{"\n"}{end}{end}'
	    echo ""
	  done
	fi
	echo "--- 4. PROMETHEUS, POR VERSION ---------------------------"
	echo "    tasa de error por revision (umbral del gate: < 0.05)"
	bash scripts/prom-query.sh '(sum by (pod_hash) (rate(http_requests_total{app="orders",status=~"5.."}[1m])) or sum by (pod_hash) (rate(http_requests_total{app="orders"}[1m])) * 0) / sum by (pod_hash) (rate(http_requests_total{app="orders"}[1m]))' 2>&1 | tail -n +2 | sed 's/^/    /'
	echo ""
	echo "    p95 de latencia por revision en segundos (umbral: < 0.3)"
	bash scripts/prom-query.sh 'histogram_quantile(0.95, sum by (pod_hash, le) (rate(http_request_duration_seconds_bucket{app="orders"}[1m])))' 2>&1 | tail -n +2 | sed 's/^/    /'
	echo ""
	echo "    trafico por revision (si una da 0, el gate no tenia datos)"
	bash scripts/prom-query.sh 'sum by (pod_hash) (rate(http_requests_total{app="orders"}[1m]))' 2>&1 | tail -n +2 | sed 's/^/    /'
	echo ""
	echo "--- 5. LOGS: SOLO LO QUE IMPORTA -------------------------"
	# 15 lineas por pod de requests exitosos son ruido: esconden la senal y hacen
	# que un agente gaste turnos leyendo nada. Resumimos y mostramos solo errores.
	logs="$$($(KUBECTL) -n $(APP_NAMESPACE) logs -l app.kubernetes.io/name=orders --tail=200 --prefix 2>/dev/null || true)"
	if [ -z "$$logs" ]; then
	  echo "    (sin logs)"
	else
	  echo "    conteo por codigo de estado (ultimas 200 lineas por pod):"
	  printf '%s\n' "$$logs" | grep -oE '"statusCode":[0-9]+' | sort | uniq -c | sed 's/^/        /' || true
	  echo ""
	  echo "    hasta 5 errores 5xx, con el pod que los genero:"
	  errors="$$(printf '%s\n' "$$logs" | grep -E '"statusCode":5[0-9][0-9]' | tail -5 || true)"
	  if [ -z "$$errors" ]; then
	    echo "        ninguno. Si el canary fallo pero aca no hay 5xx, es porque el pod"
	    echo "        canary ya fue escalado a cero y sus logs se fueron con el."
	  else
	    printf '%s\n' "$$errors" | sed 's/^/        /'
	  fi
	fi
	echo ""
	echo "============================================================"

.PHONY: smoke
smoke: ## Pegale al servicio desde dentro del cluster
	@$(KUBECTL) -n $(APP_NAMESPACE) run smoke-$$RANDOM --rm -i --restart=Never \
	  --image=busybox:1.37.0 --command -- \
	  sh -c 'for i in 1 2 3 4 5; do wget -qO- -T 2 http://orders/healthz; echo; done'

.PHONY: metrics
metrics: ## Query de la tasa de error a Prometheus (lo mismo que mira el gate)
	@bash scripts/prom-query.sh 'sum(rate(http_requests_total{app="orders",status=~"5.."}[1m])) / sum(rate(http_requests_total{app="orders"}[1m]))'

.PHONY: logs
logs: ## Logs del servicio (solo lectura)
	@$(KUBECTL) -n $(APP_NAMESPACE) logs -l app.kubernetes.io/name=orders --tail=80 --prefix

# ===========================================================================
# UIs
# ===========================================================================
.PHONY: ctx-check
ctx-check: ## Verifica que kubectl pueda hablarle al contexto de la demo
	@if $(KUBECTL) cluster-info >/dev/null 2>&1; then exit 0; fi
	err="$$($(KUBECTL) cluster-info 2>&1 >/dev/null || true)"
	echo "ERROR: kubectl no puede hablarle al contexto '$(KUBE_CONTEXT)'."
	echo ""
	echo "  Esto dice kubectl:"
	echo "      $$err"
	echo ""
	if [ -n "$${KUBECONFIG:-}" ]; then
	  echo "  Tenes KUBECONFIG exportado -> $${KUBECONFIG}"
	  echo "  Si es de otro cluster (lo mas probable), arreglalo con:"
	  echo ""
	  echo "      unset KUBECONFIG"
	  echo ""
	else
	  echo "  Para diagnosticar:   make preflight"
	  echo "                       kind get clusters"
	  echo "                       docker ps --filter label=io.x-k8s.kind.cluster=$(CLUSTER)"
	  echo ""
	fi
	exit 1

.PHONY: ui
ui: ctx-check ## Abre las UIs (Argo CD + Prometheus) en BACKGROUND, listas para la demo
	@mkdir -p .harness-tmp
	# En escena no sirve un port-forward que te bloquea la terminal.
	# Esto los deja corriendo y te devuelve el prompt con las credenciales.
	for spec in "argocd:svc/argocd-server:8080:443" "monitoring:svc/prometheus:9090:9090"; do
	  ns="$${spec%%:*}"; rest="$${spec#*:}"
	  svc="$${rest%%:*}"; rest="$${rest#*:}"
	  local_port="$${rest%%:*}"; remote_port="$${rest##*:}"
	  pidfile=".harness-tmp/pf-$${ns}.pid"
	  if [ -f "$$pidfile" ] && kill -0 "$$(cat $$pidfile)" 2>/dev/null; then
	    echo "    ya corria: $$ns en localhost:$$local_port"
	    continue
	  fi
	  nohup $(KUBECTL) -n "$$ns" port-forward "$$svc" "$$local_port:$$remote_port" 	    > ".harness-tmp/pf-$$ns.log" 2>&1 &
	  pid=$$!
	  echo $$pid > "$$pidfile"

	  # No cantamos exito sin comprobarlo: un port-forward que murio al
	  # instante dejaba el banner con las URLs igual, y el problema se
	  # descubria en escena.
	  up=0
	  for _ in 1 2 3 4 5 6 7 8 9 10; do
	    sleep 1
	    if ! kill -0 "$$pid" 2>/dev/null; then break; fi
	    if (exec 3<>/dev/tcp/127.0.0.1/$$local_port) 2>/dev/null; then up=1; break; fi
	  done

	  if [ "$$up" = "1" ]; then
	    echo "    OK  $$ns -> localhost:$$local_port"
	  else
	    echo "    FALLO: el port-forward de $$ns murio al instante."
	    echo "    Esto dice kubectl:"
	    sed "s/^/        /" ".harness-tmp/pf-$$ns.log" 2>/dev/null | head -5
	    kill "$$pid" 2>/dev/null || true
	    rm -f "$$pidfile"
	    exit 1
	  fi
	done
	echo ""
	echo "=========================================================="
	echo "  Argo CD     https://localhost:8080"
	echo "    usuario   admin"
	printf "    password  "
	$(KUBECTL) -n argocd get secret argocd-initial-admin-secret 	  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "(no disponible)"
	echo ""
	echo "  Prometheus  http://localhost:9090"
	echo ""
	echo "  Para cerrarlas:  make ui-stop"
	echo "=========================================================="

.PHONY: ui-stop
ui-stop: ## Cierra los port-forward de las UIs
	@for pidfile in .harness-tmp/pf-*.pid; do
	  [ -f "$$pidfile" ] || continue
	  pid="$$(cat $$pidfile)"
	  if kill "$$pid" 2>/dev/null; then echo "    cerrado: pid $$pid"; fi
	  rm -f "$$pidfile"
	done
	echo "==> UIs cerradas."

.PHONY: argocd-ui
argocd-ui: ctx-check ## Port-forward a la UI de Argo CD en primer plano (bloquea; para la demo usa 'make ui')
	@echo "==> https://localhost:8080  (usuario admin, 'make argocd-password')"
	echo "    (bloquea esta terminal; si queres seguir usandola: make ui)"
	$(KUBECTL) -n argocd port-forward svc/argocd-server 8080:443

.PHONY: argocd-password
argocd-password: ## Password inicial de admin en Argo CD
	@$(KUBECTL) -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d; echo

.PHONY: prom-ui
prom-ui: ctx-check ## Port-forward a Prometheus (http://localhost:9090)
	@echo "==> http://localhost:9090"
	$(KUBECTL) -n monitoring port-forward svc/prometheus 9090:9090

.PHONY: install-rollouts-plugin
install-rollouts-plugin: ## Instala el plugin 'kubectl argo rollouts' en ~/.local/bin
	@mkdir -p "$$HOME/.local/bin"
	curl -fsSL -o "$$HOME/.local/bin/kubectl-argo-rollouts" \
	  "https://github.com/argoproj/argo-rollouts/releases/download/$(ROLLOUTS_VERSION)/kubectl-argo-rollouts-linux-amd64"
	chmod +x "$$HOME/.local/bin/kubectl-argo-rollouts"
	echo "==> instalado. Asegurate de tener ~/.local/bin en el PATH."

# ===========================================================================
# DEMO
# ===========================================================================
.PHONY: act1 act2 act3 reset
act1: ## Acto 1: el agente viola la arquitectura
	@bash demo/act1-arch-violation.sh

act2: ## Acto 2: el canary atrapa el bug
	@bash demo/act2-canary-catches-bug.sh

act3: ## Acto 3: se cierra el ciclo
	@bash demo/act3-close-the-loop.sh

reset: ## Deja el repo y el cluster listos para repetir la demo
	@bash demo/reset.sh

# ===========================================================================
# HOOKS (los guardrails que limitan a los agentes, ADR-003)
# ===========================================================================
.PHONY: test-hooks
test-hooks: ## Verifica que los hooks de .claude/ realmente bloquean
	@bash scripts/test-hooks.sh
