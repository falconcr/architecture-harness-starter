# Application de Argo CD. El Makefile reemplaza __GIT_REPO_URL__ y __GIT_BRANCH__
# con tu remoto y tu rama actual (make up / make argocd-app), asi que el fork de
# cada asistente funciona sin editar YAML.
#
# Esto es el corazon del ADR-003: el UNICO sujeto que aplica cambios al cluster es
# Argo CD, y solo aplica lo que esta en Git. No hay camino desde un agente al cluster.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: orders
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: __GIT_REPO_URL__
    targetRevision: __GIT_BRANCH__
    path: deploy/k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: orders
  syncPolicy:
    automated:
      # Si alguien toca el cluster a mano, Argo CD lo revierte. Git es la verdad.
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
    retry:
      limit: 3
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 1m
