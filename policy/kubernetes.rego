# Politicas deterministas para los manifiestos de deploy/k8s.
#
# Este es el gate que decide: no opina, no negocia, y falla igual en la laptop
# y en CI. Corre con `npm run policy` (wrapper de conftest, ver scripts/conftest.sh).
#
# Cubre Deployment, StatefulSet, DaemonSet, Job, CronJob y el Rollout de Argo.
package main

import rego.v1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Rollout", "Job"}

is_workload if workload_kinds[input.kind]

name := n if {
	n := input.metadata.name
} else := "<sin-nombre>"

# Pod spec segun el tipo de recurso.
pod_spec := input.spec.template.spec if is_workload

pod_spec := input.spec.jobTemplate.spec.template.spec if input.kind == "CronJob"

containers contains c if some c in pod_spec.containers

containers contains c if some c in pod_spec.initContainers

# ---------------------------------------------------------------------------
# Imagenes: sin :latest y sin tag implicito
# ---------------------------------------------------------------------------

deny contains msg if {
	some c in containers
	endswith(c.image, ":latest")
	msg := sprintf(
		"%s/%s: el contenedor '%s' usa el tag ':latest'. Un deploy tiene que ser reproducible: usa un tag inmutable o un digest.",
		[input.kind, name, c.name],
	)
}

deny contains msg if {
	some c in containers
	not contains(c.image, ":")
	not contains(c.image, "@sha256:")
	msg := sprintf(
		"%s/%s: el contenedor '%s' no declara tag ni digest ('%s'), lo que equivale a ':latest'.",
		[input.kind, name, c.name, c.image],
	)
}

# ---------------------------------------------------------------------------
# Resource limits y requests
# ---------------------------------------------------------------------------

deny contains msg if {
	some c in containers
	not c.resources.limits.cpu
	msg := sprintf("%s/%s: el contenedor '%s' no declara resources.limits.cpu.", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	not c.resources.limits.memory
	msg := sprintf("%s/%s: el contenedor '%s' no declara resources.limits.memory.", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	not c.resources.requests.cpu
	msg := sprintf("%s/%s: el contenedor '%s' no declara resources.requests.cpu.", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	not c.resources.requests.memory
	msg := sprintf("%s/%s: el contenedor '%s' no declara resources.requests.memory.", [input.kind, name, c.name])
}

# ---------------------------------------------------------------------------
# Seguridad del contenedor (ADR-003: nada privilegiado, nada como root)
# ---------------------------------------------------------------------------

deny contains msg if {
	some c in containers
	c.securityContext.privileged == true
	msg := sprintf("%s/%s: el contenedor '%s' pide privileged: true. Prohibido (ADR-003).", [input.kind, name, c.name])
}

deny contains msg if {
	some c in containers
	c.securityContext.allowPrivilegeEscalation == true
	msg := sprintf(
		"%s/%s: el contenedor '%s' permite allowPrivilegeEscalation. Prohibido (ADR-003).",
		[input.kind, name, c.name],
	)
}

deny contains msg if {
	some c in containers
	not has_non_root(c)
	msg := sprintf(
		"%s/%s: el contenedor '%s' no garantiza runAsNonRoot: true (ni en el pod ni en el contenedor).",
		[input.kind, name, c.name],
	)
}

has_non_root(c) if c.securityContext.runAsNonRoot == true

has_non_root(_) if pod_spec.securityContext.runAsNonRoot == true

deny contains msg if {
	is_workload
	pod_spec.hostNetwork == true
	msg := sprintf("%s/%s: hostNetwork: true esta prohibido.", [input.kind, name])
}

deny contains msg if {
	is_workload
	pod_spec.hostPID == true
	msg := sprintf("%s/%s: hostPID: true esta prohibido.", [input.kind, name])
}

# ---------------------------------------------------------------------------
# Advertencias (no bloquean, pero se ven)
# ---------------------------------------------------------------------------

warn contains msg if {
	some c in containers
	not c.securityContext.readOnlyRootFilesystem
	msg := sprintf(
		"%s/%s: el contenedor '%s' no declara readOnlyRootFilesystem: true.",
		[input.kind, name, c.name],
	)
}

# Solo le exigimos readinessProbe a lo que expone un puerto: un generador de carga
# no "atiende" nada, asi que no tiene sentido sondearlo.
warn contains msg if {
	some c in containers
	count(object.get(c, "ports", [])) > 0
	not c.readinessProbe
	msg := sprintf(
		"%s/%s: el contenedor '%s' expone un puerto pero no declara readinessProbe; sin eso el canary no distingue 'arrancando' de 'roto'.",
		[input.kind, name, c.name],
	)
}
