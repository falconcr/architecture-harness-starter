# Checklist de madurez de harness engineering

> **Los agentes proponen, los gates deterministas deciden, los humanos son dueños de lo irreversible.**

Para qué sirve esto: medir **en qué nivel está tu equipo hoy**, por etapa del ciclo y por eje
transversal, y saber cuál es el siguiente paso concreto.

Dos reglas para que el ejercicio sirva:

1. **Respondé por lo que pasa, no por lo que está escrito.** Si existe la política pero nadie la
   corre, la respuesta es no.
2. **Tu nivel es el del eslabón más flojo, no el promedio.** Un equipo con Deploy en nivel 3 y
   credenciales en nivel 0 está en nivel 0: el agente con el token permanente puede pasar por al
   lado de todo lo demás.

---

## Los cuatro niveles

| Nivel | Nombre | En una frase | Cómo se siente |
|---|---|---|---|
| **0** | **Ad hoc** | Los agentes se usan, nadie definió cómo. | "Funciona, pero no revisaría un PR de agente sin leerlo línea por línea." |
| **1** | **Contexto** | El agente sabe dónde está parado: hay reglas escritas y comandos para verificar. | "El agente acierta más, pero las reglas se cumplen porque alguien las revisa." |
| **2** | **Guardrails** | Las reglas son ejecutables y bloquean. Los agentes tienen permisos mínimos. | "Si el agente se equivoca, falla un comando. No depende de que yo esté atento." |
| **3** | **Ciclo cerrado** | El deploy se verifica y revierte solo; los incidentes vuelven como PRs y dejan guardrails nuevos. | "El harness mejora solo cada vez que algo sale mal." |

---

## Evaluación por etapa del ciclo

Para cada etapa, marcá el nivel más alto cuya descripción sea **completamente** cierta.

### Plan

| Nivel | Descripción |
|---|---|
| 0 | El agente recibe el issue y arranca a codear. No hay plan previo que nadie mire. |
| 1 | Hay un `CLAUDE.md` (o equivalente) con reglas del proyecto, y el agente produce un plan antes de tocar código. |
| 2 | El plan se valida explícitamente contra los ADRs, y el agente corre en **solo lectura** mientras planifica. |
| 3 | El plan se aprueba antes de implementar, y un plan que contradice un ADR se rechaza citando el ADR. |

### Code

| Nivel | Descripción |
|---|---|
| 0 | El agente escribe código con acceso a tu máquina, tus credenciales y tu red. |
| 1 | Hay convenciones escritas y el agente las sigue; los tests existen y se corren a mano. |
| 2 | El agente corre en un **sandbox efímero sin secretos**; tests y fitness functions corren en CI y bloquean. |
| 3 | Un comando (`npm run verify` o equivalente) corre igual en la laptop, en CI y en la sesión del agente, y nadie mergea sin que pase. |

### Review

| Nivel | Descripción |
|---|---|
| 0 | Review humano a ojo, sin checklist. Lo que se atrapa depende de quién revisó y de qué día era. |
| 1 | Hay checklist de review y los ADRs están escritos en algún lado. |
| 2 | Los ADRs se verifican **en CI** (fitness functions) y los manifiestos pasan **policy-as-code**. El review de IA comenta, no bloquea. |
| 3 | Los gates deterministas corren antes del review de IA; una persona aprueba el merge; y lo que las herramientas no ven, el agente lo marca como regla propuesta. |

### Release

| Nivel | Descripción |
|---|---|
| 0 | El changelog se escribe a mano o no se escribe. Las imágenes no se firman. |
| 1 | Commits convencionales y changelog generado (aunque sea a mano con ayuda del agente). |
| 2 | El pipeline genera **SBOM** y **firma** el artefacto; el agente redacta el changelog pero **no publica**. |
| 3 | La firma se **verifica** antes de desplegar (no solo se produce), con credenciales efímeras y sin llaves permanentes (keyless). |

### Deploy

| Nivel | Descripción |
|---|---|
| 0 | Alguien corre `kubectl apply` o un script desde su máquina. El cluster y Git no coinciden. |
| 1 | El deploy está automatizado en el pipeline, pero el pipeline tiene credenciales de producción. |
| 2 | **GitOps**: el único que escribe en el cluster es el controlador (Argo CD / Flux), y solo desde Git. Ningún agente tiene camino al cluster. |
| 3 | Despliegue progresivo (canary / blue-green) con política declarativa; `selfHeal` revierte los cambios manuales; promover es de una persona o de un gate, nunca de un agente. |

### Verify

| Nivel | Descripción |
|---|---|
| 0 | Se despliega y se espera. Si algo rompe, lo descubre un usuario. |
| 1 | Hay dashboards y alertas; alguien los mira después de desplegar. |
| 2 | El deploy se **verifica automáticamente** contra métricas (tasa de error, latencia) con umbrales declarados, y **revierte solo** si no las cumple. |
| 3 | El análisis distingue canary de estable; un agente de solo lectura explica el veredicto; y un gate sin datos se trata como un fallo del harness, no como un pase libre. |

### Operate

| Nivel | Descripción |
|---|---|
| 0 | El incidente se arregla en caliente. El aprendizaje queda en la cabeza de quien estuvo de guardia. |
| 1 | Hay postmortems escritos. A veces generan tareas; a veces las tareas se hacen. |
| 2 | El triage lo asiste un agente con **solo lectura** en producción, y su salida es un **PR**, no un cambio aplicado. |
| 3 | **El ciclo se cierra**: el fix entra como PR con test de regresión **y un guardrail nuevo** que impide esa clase de error. El harness termina mejor que antes del incidente. |

---

## Evaluación por eje transversal

Preguntas de sí/no. **Un "no" en los ejes marcados con ⚠️ te deja en nivel 0 de ese eje, sin
importar qué tan bien estés en todo lo demás.**

### Contexto

- [ ] ¿Existe un `CLAUDE.md` (o equivalente) versionado en el repo, no en la cabeza de alguien?
- [ ] ¿Tenés ADRs escritos para las decisiones de arquitectura que importan?
- [ ] **¿Tus ADRs se verifican en CI?** ⚠️ *(Si la respuesta es no, tus ADRs son documentación
      histórica, no restricciones.)*
- [ ] ¿Cada ADR tiene una sección "Verificación" que nombra el comando que lo comprueba?
- [ ] ¿Está escrito en algún lado qué comando corre todos los gates (`npm run verify` o similar)?
- [ ] ¿Ese contexto se actualiza en el mismo PR que cambia el código, o envejece aparte?

### Guardrails deterministas

- [ ] ¿Hay fitness functions de arquitectura que corren en CI y **bloquean el merge**?
- [ ] ¿Los manifiestos de infraestructura pasan por policy-as-code (OPA, Kyverno, equivalente)?
- [ ] ¿El mismo comando da el mismo resultado en la laptop y en CI?
- [ ] ¿Las policies prohíben lo básico: tags mutables, sin resource limits, privileged, sin labels?
- [ ] **¿Alguien puede desactivar un gate sin que se note?** *(Si sí: `enforce_admins`, CODEOWNERS
      sobre `policy/` y `.github/`.)*
- [ ] ¿Testeás tus guardrails? *(Un guardrail que nadie testea es una decoración.)*

### Aislamiento de agentes

- [ ] ¿Los agentes corren en contenedores **efímeros** (`--rm`), no en tu máquina ni en un pod de larga vida?
- [ ] ¿Con usuario **no root** y filesystem de **solo lectura**?
- [ ] ¿Con la red restringida a lo que realmente necesitan alcanzar?
- [ ] ¿El código se monta de **solo lectura** y la salida del agente es un patch o un PR?
- [ ] ¿Hay límites de CPU, memoria y procesos?
- [ ] ¿Evaluaste si tu caso necesita una frontera de kernel (gVisor, Kata, Firecracker)?

### Credenciales

- [ ] **¿Tus agentes usan credenciales permanentes?** ⚠️ *(La respuesta correcta es **NO**. Si es
      sí, este es el primer item de tu backlog: nada de lo demás te protege de un token que vive
      para siempre.)*
- [ ] ¿Algún agente tiene kubeconfig, token de cloud o credenciales de base de datos de producción?
      *(Debería ser no.)*
- [ ] ¿CI usa OIDC / federación de identidad en vez de llaves estáticas?
- [ ] ¿Los `permissions` de cada job del pipeline son mínimos, declarados job por job?
- [ ] ¿Hay un hook o control técnico que **impida** que un agente lea `.env`, `*.pem`, `~/.kube/config`?
- [ ] ¿Sabés enumerar todos los secretos permanentes de tu repo y justificar cada uno?

### Observabilidad

- [ ] ¿Las métricas que usan tus gates están versionadas como **contrato** (con un test que
      protege sus nombres)?
- [ ] ¿Podés medir el canary **separado** de la versión estable?
- [ ] ¿Hay tráfico garantizado durante el análisis, o el gate puede quedarse sin datos?
- [ ] ¿Un gate **sin datos** se trata como fallo? *(Si da luz verde, es un gate ciego.)*
- [ ] ¿Un agente de solo lectura puede explicar un veredicto sin pedir más permisos?
- [ ] ¿Podés correlacionar una métrica con un pod y con un commit?

### Rol humano

- [ ] **¿Quién puede promover a producción?** ⚠️ *(Si la respuesta incluye "un agente" o "el
      pipeline, sin que nadie apruebe el cambio", tenés un problema de diseño, no de herramientas.
      Escribí los nombres: si no podés, nadie es dueño.)*
- [ ] ¿`main` está protegida, con aprobación humana obligatoria y `enforce_admins: true`?
- [ ] ¿El review de IA está **fuera** de los checks requeridos? *(Debería estarlo: un agente no
      bloquea ni habilita un merge.)*
- [ ] ¿Está claro qué decisiones son irreversibles y quién es dueño de cada una?
- [ ] ¿Los force push a `main` están deshabilitados?
- [ ] ¿Alguien revisa con atención especial los PRs que tocan el harness (`policy/`, `.claude/`,
      `.github/`)? *(Aflojar un guardrail es el cambio más peligroso que existe en un repo.)*

---

## Cómo puntuar

1. Anotá tu nivel (0-3) en cada una de las **7 etapas**.
2. Para cada uno de los **6 ejes**, contá los "sí": 0-1 → nivel 0 · 2-3 → nivel 1 · 4-5 → nivel 2
   · 6 → nivel 3.
3. **Tu nivel general es el mínimo de los 13 valores**, no el promedio.
4. Un "no" en cualquier item ⚠️ te pone en nivel 0 de ese eje, sin importar el conteo.

Tabla para llenar:

| Dimensión | Nivel |
|---|---|
| Plan | |
| Code | |
| Review | |
| Release | |
| Deploy | |
| Verify | |
| Operate | |
| Contexto | |
| Guardrails deterministas | |
| Aislamiento de agentes | |
| Credenciales | |
| Observabilidad | |
| Rol humano | |
| **General (el mínimo)** | |

La dimensión más baja **es** tu backlog. En ese orden.

---

## Mañana en tu equipo

Tres cosas. No seis, no un plan trimestral. Tres, y las tres se pueden empezar mañana.

### 1. Escribí un `CLAUDE.md` y un ADR verificable

Un archivo con las reglas del proyecto y los comandos para verificarlas. Y **un** ADR: el límite
que más te duele cuando se rompe, con su sección "Verificación" que nombre un comando concreto.

Si no podés escribir ese comando, el ADR todavía no está terminado. Eso ya es información valiosa.

> Referencia: [`CLAUDE.md`](CLAUDE.md), [`docs/adr/001-domain-pure.md`](docs/adr/001-domain-pure.md)

### 2. Quitale a tus agentes las credenciales permanentes

Buscá hoy qué `.env`, qué kubeconfig y qué token de larga vida tienen acceso tus agentes y tus
runners. Reemplazalos por credenciales efímeras (OIDC, federación de identidad) o quitalos.

Es la acción con mejor relación entre esfuerzo y riesgo evitado de toda la lista. Un agente sin
credenciales de producción tiene como peor caso un PR malo. Con credenciales, su peor caso es un
incidente.

> Referencia: [`docs/adr/003-no-agent-prod-creds.md`](docs/adr/003-no-agent-prod-creds.md),
> [`.claude/hooks/`](.claude/hooks/)

### 3. Convertí el próximo error de un agente en una regla de CI

La próxima vez que un agente haga algo mal —y va a pasar— no te quedes en explicarle por qué
estuvo mal. **Escribí la regla que hace que ese error falle solo**, y mergeala junto con el fix.

Un error explicado se repite. Un error convertido en regla, no.

Esa es la única práctica de esta lista que hace que tu harness **mejore con el tiempo** en vez de
envejecer: cada falla lo deja más fuerte que antes.

> Referencia: el Acto 1 de [`demo/DEMO.md`](demo/DEMO.md) y el guardrail nuevo del Acto 3.

---

```
Los agentes proponen.
Los gates deterministas deciden.
Los humanos son dueños de lo irreversible.
```
