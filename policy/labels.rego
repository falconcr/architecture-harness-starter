# Labels obligatorios en todos los recursos de deploy/k8s.
#
# Sin labels consistentes no hay forma de correlacionar una metrica, un pod y un
# commit. Y sin esa correlacion, el AnalysisTemplate del canary y el triage de un
# incidente son adivinanza.
package main

import rego.v1

required_labels := {
	"app.kubernetes.io/name",
	"app.kubernetes.io/part-of",
	"app.kubernetes.io/managed-by",
}

# Recursos a los que les exigimos labels (dejamos fuera cosas como Namespace).
labelled_kinds := {
	"Deployment",
	"StatefulSet",
	"DaemonSet",
	"Rollout",
	"Service",
	"ConfigMap",
	"Job",
	"CronJob",
	"AnalysisTemplate",
}

resource_name := n if {
	n := input.metadata.name
} else := "<sin-nombre>"

deny contains msg if {
	labelled_kinds[input.kind]
	some required in required_labels
	not input.metadata.labels[required]
	msg := sprintf(
		"%s/%s: falta el label obligatorio '%s'.",
		[input.kind, resource_name, required],
	)
}

# managed-by tiene que decir la verdad: en este repo despliega Argo CD, no una persona
# y mucho menos un agente (ADR-003).
deny contains msg if {
	labelled_kinds[input.kind]
	value := input.metadata.labels["app.kubernetes.io/managed-by"]
	value != "argocd"
	msg := sprintf(
		"%s/%s: app.kubernetes.io/managed-by es '%s'; en este repo todo lo aplica Argo CD ('argocd'), ningun agente ni persona hace kubectl apply (ADR-003).",
		[input.kind, resource_name, value],
	)
}
