# ADR-003: Ningún agente de IA tiene credenciales de producción ni despliega

- **Estado:** aceptado
- **Fecha:** 2026-10-27
- **Decisores:** equipo de plataforma, seguridad
- **Etiquetas:** seguridad, agentes, verificable-en-ci

## Contexto y planteamiento del problema

Un agente que puede desplegar es un agente que puede causar un incidente a las 3 de la mañana sin
que nadie haya aprobado nada. Y un agente con un token permanente es un token permanente más en
circulación: vive en un `.env`, se filtra en un log, se queda en el historial de una sesión, o se
usa desde un prompt inyectado en un issue de GitHub.

El patrón cómodo —"dale un kubeconfig de prod al agente así arregla el incidente solo"— convierte
cada falla del modelo en una falla de producción. Y las fallas del modelo no son teóricas: alucina
un nombre de recurso, confunde namespaces, o sigue una instrucción que venía dentro del texto que
estaba leyendo.

## Decisión

**Los agentes proponen. Los gates deterministas deciden. Los humanos son dueños de lo irreversible.**

1. **Cero credenciales de producción para agentes.** Ningún agente recibe kubeconfig de prod,
   credenciales de base de datos, tokens de cloud ni llaves de firma. Lo único que este repo
   admite como secreto permanente es `ANTHROPIC_API_KEY` en GitHub Actions, y solo habilita
   *comentar* en un PR.
2. **Ningún agente despliega.** No hay un camino desde un agente hacia el cluster. El único sujeto
   que aplica cambios al cluster es **Argo CD**, y solo desde lo que está mergeado en Git.
   Para que algo llegue al cluster tiene que existir un commit en la rama que Argo CD observa.
3. **Nada de push directo a `main`.** Los agentes trabajan en ramas y abren PRs. `main` está
   protegida y exige revisión humana.
4. **Credenciales de vida corta donde haya que autenticar.** En CI, OIDC + `GITHUB_TOKEN` efímero
   con `permissions` mínimos por job. Cosign firma *keyless*: no existe una llave privada que
   robar.
5. **Lectura de producción acotada y de solo lectura.** `canary-analyst` e `incident-triage` leen
   métricas y logs; no pueden promover, abortar ni tocar el cluster.
6. **Aislamiento.** Los agentes corren en contenedores efímeros, sin secretos montados, usuario
   no root, filesystem de solo lectura y red restringida (ver sección "Agentes en sandbox
   efímeros" del README).

Corolario operativo: **el output de un agente es un PR, nunca un `kubectl apply`.** Un incidente
analizado por un agente vuelve a entrar al ciclo como un PR que pasa por el pipeline completo.

## Consecuencias

**Bien:**
- El peor caso de un agente equivocado es un PR malo, que es exactamente el riesgo que el pipeline
  ya está diseñado para contener.
- No hay secretos de larga vida que rotar, filtrar ni auditar.
- La trazabilidad es gratis: todo cambio que llegó al cluster tiene commit, PR y aprobador.

**Costo aceptado:**
- Un agente no puede "arreglarlo solo" en el minuto 1 de un incidente. Puede analizar y proponer;
  el rollback automático lo hace Argo Rollouts, no el agente.
- Hay que mantener los hooks y los `permissions` del workflow: es trabajo de plataforma real.

## Verificación

Este ADR no se verifica con una sola herramienta: se verifica con **cuatro controles, todos
deterministas**.

| # | Qué verifica | Cómo | Archivo |
|---|---|---|---|
| 1 | Un agente no puede hablarle a un cluster que no sea el de la demo | hook `PreToolUse` que bloquea `kubectl`/`argo rollouts` si el contexto ≠ `kind-harness` | [`.claude/hooks/guard-kubectl.sh`](../../.claude/hooks/guard-kubectl.sh) |
| 2 | Un agente no puede pushear a `main` | hook `PreToolUse` que bloquea `git push` con destino `main`/`master` | [`.claude/hooks/guard-git-push.sh`](../../.claude/hooks/guard-git-push.sh) |
| 3 | Un agente no puede leer secretos | hook `PreToolUse` que bloquea leer `.env*`, `*.pem`, `*.key`, `kubeconfig`, `~/.aws`, … | [`.claude/hooks/guard-secret-read.sh`](../../.claude/hooks/guard-secret-read.sh) |
| 4 | Los manifiestos no corren privilegiados ni como root | políticas OPA/Conftest | [`policy/kubernetes.rego`](../../policy/kubernetes.rego) |

```bash
# Controles 1-3: los hooks son scripts, se ejecutan y se testean a mano.
echo '{"tool_name":"Bash","tool_input":{"command":"kubectl --context prod get pods"}}' \
  | bash .claude/hooks/guard-kubectl.sh; echo "exit=$?"   # exit=2 => bloqueado

echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
  | bash .claude/hooks/guard-git-push.sh; echo "exit=$?"  # exit=2 => bloqueado

echo '{"tool_name":"Read","tool_input":{"file_path":".env"}}' \
  | bash .claude/hooks/guard-secret-read.sh; echo "exit=$?" # exit=2 => bloqueado

# Control 4:
npm run policy
```

Revisión de los permisos declarados (parte del checklist de review de cada PR que toque el
harness):

```bash
# Ningun subagente debe declarar herramientas de escritura sobre el cluster.
grep -n '^tools:' .claude/agents/*.md

# Ningun job debe tener permissions: write-all ni secrets que no sean ANTHROPIC_API_KEY.
grep -n -E 'permissions:|secrets\.' .github/workflows/ci.yml
```
