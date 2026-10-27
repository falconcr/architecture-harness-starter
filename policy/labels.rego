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

# managed-by tiene que decir la VERDAD sobre quien aplica el recurso.
#
# Solo dos sujetos pueden aplicar algo en este repo:
#   - "argocd":         todo lo que es la aplicacion (deploy/k8s). Llega por commit.
#   - "make-bootstrap": la infra que `make up` instala UNA vez antes de que Argo CD
#                       exista (Prometheus). No es parte del ciclo de entrega.
#
# Lo que NO puede aparecer nunca: una persona o un agente (ADR-003). Si un recurso
# dice "kubectl" o un nombre propio, alguien esta aplicando a mano.
valid_managers := {"argocd", "make-bootstrap"}

deny contains msg if {
	labelled_kinds[input.kind]
	value := input.metadata.labels["app.kubernetes.io/managed-by"]
	not valid_managers[value]
	msg := sprintf(
		"%s/%s: app.kubernetes.io/managed-by es '%s'; solo valen 'argocd' (llega por commit) o 'make-bootstrap' (infra inicial de make up). Ningun agente ni persona aplica nada a mano (ADR-003).",
		[input.kind, resource_name, value],
	)
}

# Y lo que esta en deploy/k8s, que es lo que Argo CD sincroniza, tiene que decir argocd.
deny contains msg if {
	labelled_kinds[input.kind]
	input.kind == "Rollout"
	input.metadata.labels["app.kubernetes.io/managed-by"] != "argocd"
	msg := sprintf(
		"%s/%s: un Rollout lo despliega Argo CD por definicion; managed-by tiene que ser 'argocd'.",
		[input.kind, resource_name],
	)
}
