# Subagentes

Cinco agentes, cada uno con el **mínimo** de herramientas para su trabajo. El patrón es siempre el
mismo: **leen mucho, escriben poco, no deciden nada irreversible.**

| Agente | Puede | Nunca | Modelo |
|---|---|---|---|
| [`architect-reviewer`](architect-reviewer.md) | Read, Grep, Glob | editar código, aprobar PRs | opus |
| [`test-writer`](test-writer.md) | Read, Write/Edit **solo en `/test`** | tocar `src/` | sonnet |
| [`release-notes`](release-notes.md) | Read, `git log` | publicar releases, taggear, firmar | sonnet |
| [`canary-analyst`](canary-analyst.md) | lectura de Prometheus y del Rollout | promover, abortar, tocar el cluster | opus |
| [`incident-triage`](incident-triage.md) | leer logs/métricas, crear rama, abrir PR | tocar el cluster, pushear a main, mergear | opus |

## Por qué el scope mínimo no es paranoia

Un agente con más permisos de los que necesita no es "más útil": es más caro de revisar. Si
`test-writer` pudiera tocar `src/`, cada PR suyo tendría que leerse completo porque podría haber
"arreglado" el código para que su test pase. Como no puede, su diff se revisa en 30 segundos.

El límite no se declara acá y se confía: `tools:` acota lo que el agente puede pedir, y los
**hooks** de [`.claude/hooks/`](../hooks/) bloquean lo que no debería poder hacer igual, incluso si
el modelo se confunde o alguien le pega un prompt malicioso en un issue.

Ver [ADR-003](../../docs/adr/003-no-agent-prod-creds.md).
