# Guardrail nacido del incidente del 2026-10-27 (Acto 3 de la demo).
#
# El canary atrapo un FAULT_RATE=0.3 en el deploy y lo revirtio solo. Esto hace
# que ese manifiesto ni siquiera pueda llegar a mergearse: el error de ayer es la
# regla de hoy.
package main

import rego.v1

workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "Rollout", "Job"}

fi_containers contains c if {
	workload_kinds[input.kind]
	some c in input.spec.template.spec.containers
}

deny contains msg if {
	some c in fi_containers
	some e in c.env
	e.name == "FAULT_RATE"
	to_number(e.value) > 0
	msg := sprintf(
		"%s/%s: el contenedor '%s' declara FAULT_RATE=%s. La inyeccion de fallos no se despliega: es una herramienta local. Incidente del 2026-10-27.",
		[input.kind, input.metadata.name, c.name, e.value],
	)
}

deny contains msg if {
	some c in fi_containers
	some e in c.env
	e.name == "ALLOW_FAULT_INJECTION"
	e.value == "true"
	msg := sprintf(
		"%s/%s: el contenedor '%s' habilita ALLOW_FAULT_INJECTION. Prohibido en cualquier manifiesto desplegable.",
		[input.kind, input.metadata.name, c.name],
	)
}
