# Argo CD

`application.yaml.tpl` es una plantilla: `make up` (o `make argocd-app`) la renderiza a
`deploy/argocd/application.yaml` sustituyendo tu remoto y tu rama.

```bash
make argocd-app                                   # usa `git remote get-url origin` y la rama actual
make argocd-app GIT_BRANCH=demo/acto-2            # apuntar Argo CD a otra rama
make argocd-app GIT_REPO_URL=https://github.com/otro/repo.git
```

El archivo renderizado está en `.gitignore` a propósito: es local y depende de tu fork.

## Por qué Argo CD y no `kubectl apply`

Porque `kubectl apply` no deja rastro revisable y cualquiera con un kubeconfig lo puede correr,
incluido un agente. Con Argo CD, para que algo llegue al cluster tiene que existir un **commit en
la rama observada**, y por lo tanto un PR, un pipeline y un aprobador humano (ADR-003).

`selfHeal: true` cierra la puerta de atrás: si alguien edita el cluster a mano, Argo CD lo
revierte.

## Entrar a la UI

```bash
make argocd-ui          # port-forward a https://localhost:8080
make argocd-password    # usuario: admin
```
