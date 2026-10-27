# Políticas (OPA / Rego) para los manifiestos de Kubernetes

Estas políticas son **gates deterministas**: no opinan, no negocian y fallan igual en la laptop
que en CI. Las corre [`scripts/conftest.sh`](../scripts/conftest.sh) vía `npm run policy`.

| Archivo | Qué exige |
|---|---|
| `kubernetes.rego` | Sin tag `latest` (ni tag implícito) · `resources.limits` y `requests` de CPU y memoria · nada `privileged` · sin `allowPrivilegeEscalation` · `runAsNonRoot` · sin `hostNetwork`/`hostPID`. Advierte si falta `readOnlyRootFilesystem` o `readinessProbe`. |
| `labels.rego` | Labels obligatorios `app.kubernetes.io/{name,part-of,managed-by}` y que `managed-by` sea `argocd` (ADR-003: ningún agente ni persona hace `kubectl apply`). |

Cubren `Deployment`, `StatefulSet`, `DaemonSet`, `Job`, `CronJob` **y el `Rollout` de Argo**, que
es el que importa en este repo.

## Correrlas

```bash
npm run policy                      # deploy/k8s (lo que Argo CD sincroniza)
bash scripts/conftest.sh deploy     # todo deploy/, incluido monitoring
```

No hace falta instalar `conftest`: el wrapper usa el binario local si existe y si no cae a
`docker run --rm openpolicyagent/conftest`.

## Agregar una política

1. Escribí la regla `deny contains msg if { … }` con un mensaje que diga **qué hacer**, no solo
   qué está mal.
2. Probá que falla: rompé el manifiesto a propósito y corré `npm run policy`.
3. Probá que pasa: arreglalo y volvé a correr.
4. Si la regla viene de un ADR, citá el ADR en el mensaje y agregá el comando a la sección
   "Verificación" de ese ADR.

Este es exactamente el movimiento del Acto 1 de la demo: **el error de un agente se convierte en
una regla**.
