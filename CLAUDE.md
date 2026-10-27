# CLAUDE.md — contexto del proyecto `orders`

> **Los agentes proponen, los gates deterministas deciden, los humanos son dueños de lo irreversible.**

Este archivo es la **capa de contexto** del harness. Si algo acá contradice al código, gana el
código y hay que corregir este archivo en el mismo PR.

---

## Qué es este repo

Servicio `orders` (TypeScript, Node 22, Fastify) con arquitectura en capas, usado como demo de
*harness engineering*: cómo poner agentes de IA en todo el ciclo CI/CD sin perder el control de lo
que llega a producción.

```
src/domain/          reglas de negocio puras + PUERTOS (interfaces)
src/application/     casos de uso; solo conocen puertos
src/infrastructure/  ADAPTADORES de los puertos (repos, métricas, config)
src/http/            adaptador de entrada (Fastify) + composition root
test/                vitest
deploy/k8s/          lo que Argo CD sincroniza. Cambiar algo acá ES desplegar.
policy/              políticas OPA/Conftest para los manifiestos
docs/adr/            las decisiones de arquitectura, cada una con su verificación
.claude/             subagentes y hooks (los guardrails)
```

---

## Verificá antes de proponer

**Corré esto antes de decir que terminaste.** Es exactamente lo que corre CI:

```bash
npm run verify     # lint + typecheck + test + arch:check + policy
```

Por separado, cuando necesites iterar rápido:

| Comando | Qué verifica | Qué pasa si falla |
|---|---|---|
| `npm run lint` | estilo y errores obvios | bloquea el PR |
| `npm run typecheck` | tipos (`tsc --noEmit`) | bloquea el PR |
| `npm test` | comportamiento (vitest) | bloquea el PR |
| `npm run arch:check` | **ADR-001 y ADR-002** (dependency-cruiser) | bloquea el PR |
| `npm run policy` | manifiestos de k8s (OPA/Conftest) | bloquea el PR |
| `make test-hooks` | que los guardrails de `.claude/hooks/` bloqueen de verdad | bloquea el PR |

Si un gate falla, **el gate tiene razón hasta que un PR demuestre lo contrario**. No desactives una
regla, no agregues un `eslint-disable`, no borres un test y no aflojes un umbral para que pase.
Si crees que la regla está mal: decilo, explicá por qué, y que lo decida una persona.

---

## Las decisiones de arquitectura (y cómo se verifican)

| ADR | Decisión | Verificación |
|---|---|---|
| [ADR-001](docs/adr/001-domain-pure.md) | `src/domain` no depende de infraestructura, de HTTP ni de npm | `npm run arch:check` → `adr-001-domain-is-pure` |
| [ADR-002](docs/adr/002-ports-adapters.md) | Todo acceso externo pasa por puerto + adaptador; un solo composition root (`src/http/server.ts`) | `npm run arch:check` → `adr-002-ports-and-adapters` |
| [ADR-003](docs/adr/003-no-agent-prod-creds.md) | Ningún agente tiene credenciales de producción ni despliega | hooks de `.claude/hooks/`, `npm run policy`, `permissions` del workflow |

**Un ADR sin sección "Verificación" no es un ADR: es una opinión.** Si agregás uno, agregá la
regla que lo verifica en el mismo PR.

---

## Reglas duras

1. **Nunca `git push` a `main`.** Trabajá en una rama y abrí un PR.
   El hook `.claude/hooks/guard-git-push.sh` lo bloquea.
2. **Nunca modifiques manifiestos de producción sin PR.** `deploy/k8s/` es lo que Argo CD aplica:
   un commit ahí es un deploy. Siempre rama + PR + aprobación humana.
3. **Nunca `kubectl apply`, `delete`, `patch`, `scale`, `promote` ni `abort`.** El único que
   escribe en el cluster es Argo CD. Si querés cambiar el cluster, cambiá Git.
4. **Nunca hables con un cluster que no sea `kind-harness`.** El hook
   `.claude/hooks/guard-kubectl.sh` lo bloquea.
5. **Nunca leas secretos.** No `.env`, no `*.pem`, no `*.key`, no `~/.kube/config`, no `~/.aws`.
   Para saber qué configuración existe: `.env.example` y `deploy/k8s/configmap.yaml`.
   El hook `.claude/hooks/guard-secret-read.sh` lo bloquea.
6. **El dominio se mantiene puro.** Si necesitás el reloj, un ID, la red o la base de datos desde
   `src/domain` o `src/application`: declarás un **puerto** y lo implementás en
   `src/infrastructure`.
7. **Todo cambio de comportamiento viene con test.** Un fix sin test que falle antes y pase
   después no está terminado.
8. **Commits convencionales**: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `ci:`.
   El agente `release-notes` depende de eso.
9. **No instales dependencias nuevas sin justificarlo** en el PR. Cada dependencia es superficie
   de ataque y peso en la imagen.
10. **Si tocás `.claude/`, `policy/` o `.github/workflows/`, decilo en el título del PR.** Son
    cambios al harness: los revisa una persona con atención especial, porque aflojar un guardrail
    es el cambio más peligroso que existe en este repo.

---

## Convenciones de código

- TypeScript estricto, ESM, imports con extensión `.js` (requisito de `NodeNext`).
- `import type { … }` para tipos (lo exige el lint).
- Inyección por constructor; nada de singletons ni de estado global, salvo el registry de métricas.
- Errores de dominio: subclases de `DomainError`. **El dominio no conoce códigos HTTP**; la
  traducción vive en `src/http/routes.ts`.
- Nombres de métricas (`http_requests_total`, `http_request_duration_seconds`) son **contrato
  público**: los consulta el `AnalysisTemplate` `error-rate`. Cambiarlos deja ciego al gate del
  canary. `test/metrics.test.ts` los protege.
- Documentación y comentarios en español.

---

## Subagentes disponibles

| Agente | Para qué | Nunca |
|---|---|---|
| `architect-reviewer` | revisar un diff contra los ADRs | editar código, aprobar PRs |
| `test-writer` | escribir tests en `/test` | tocar `src/` |
| `release-notes` | changelog desde commits convencionales | publicar releases |
| `canary-analyst` | explicar por qué un canary pasó o falló | promover, abortar |
| `incident-triage` | analizar un incidente y proponer el fix como PR | tocar el cluster |

Detalle y permisos exactos: [`.claude/agents/README.md`](.claude/agents/README.md).

---

## Cómo se despliega (y por qué no podés desplegar)

```
PR → CI (lint, tests, arch:check, conftest, build, SBOM, firma, review IA) → aprobación humana
   → merge a main → Argo CD sincroniza deploy/k8s → Rollout canary 20 %
   → AnalysisTemplate "error-rate" contra Prometheus → 50 % → 100 %  (o rollback automático)
```

No hay ningún paso de esa cadena que un agente pueda saltear. Eso es el punto.
