# La demo, paso a paso

Tres actos, ~15 minutos en total. Cada acto tiene **lo que hacés**, **lo que decís** y un
**plan B** por si algo falla en vivo.

> **Antes de subir al escenario**, leé "Checklist de 10 minutos antes" al final de este archivo.

---

## Preparación

```bash
# Una sola vez
npm ci
make install-rollouts-plugin         # el Acto 2 se ve MUCHO mejor con el plugin

# Antes de la charla (tarda 6-8 min la primera vez)
make up
make rollout-status                  # tiene que decir Healthy, 5/5

# Entre ensayos
bash demo/reset.sh
```

**La demo necesita red.** Argo CD sincroniza desde tu repo en GitHub (eso es el punto del ADR-003:
el único camino al cluster es un commit). Si te quedás sin red, los tres planes B funcionan offline.

Dos terminales en pantalla:

- **Terminal A** (grande): los scripts de los actos.
- **Terminal B**: una sesión de `claude` en la raíz del repo, para invocar los subagentes.

---

## Acto 1 — "El agente viola la arquitectura"

**Tiempo:** ~4 min · **Comando:** `bash demo/act1-arch-violation.sh`

### Lo que pasa

1. `main` está verde: `npm run arch:check` → sin violaciones.
2. El script crea la rama `demo/acto-1-violacion` y simula lo que hizo el agente: `src/domain/order.ts`
   importa `src/infrastructure/db.ts` y agrega una función `persistOrder` con un INSERT.
3. **Los tests pasan. El typecheck pasa. El lint pasa.**
4. `npm run arch:check` **falla**:

   ```
     error adr-001-domain-is-pure: src/domain/order.ts → src/infrastructure/db.ts

   x 1 dependency violations (1 errors, 0 warnings). 15 modules, 27 dependencies cruised.
   ```

5. En la Terminal B, `architect-reviewer` explica qué ADR se violó.
6. Cierre: cómo convertir un error nuevo en una regla.

### Lo que decís

> Le pedí a un agente: "guardá los pedidos en la base de datos". Hizo lo más directo que compila:
> importó el cliente de base de datos desde el dominio. No fue descuidado. Fue **literal**.
>
> *(mostrar el diff)*
>
> Miren esto: los tests pasan. Los tipos pasan. El lint pasa. Y el diff se ve razonable: son
> quince líneas, hay un INSERT, está al lado de la entidad `Order`. **Esto pasa code review
> humano un viernes a las seis de la tarde.** Y en seis meses no podés testear tu lógica de
> negocio sin levantar una base de datos.
>
> *(correr arch:check)*
>
> Y acá está la diferencia. No dice "error de arquitectura". Dice **qué decisión se violó**, con
> nombre y apellido: `adr-001-domain-is-pure`. Dice de dónde a dónde. Y podés leer el ADR
> completo, con el contexto de por qué lo decidimos, en `docs/adr/001-domain-pure.md`.
>
> Esto tardó dos segundos. En mi laptop y en CI, con el mismo mensaje. **El ADR dejó de ser un
> documento y pasó a ser una restricción.**
>
> *(Terminal B: architect-reviewer)*
>
> Ahora el agente explica. Fíjense en el orden: la herramienta **decidió**, el agente **explica**.
> Y `architect-reviewer` solo tiene `Read` y `Grep`: no puede editar el código para arreglarlo, no
> puede aprobar el PR, y no puede desactivar la regla que lo delató.
>
> *(cierre)*
>
> Pero el caso interesante es el otro: cuando un agente encuentra un hueco que **ninguna regla
> atrapa**. Y ahí está la regla de oro de todo esto:
>
> **cada error de un agente que no está cubierto, se convierte en una regla antes de mergear el
> fix.** Un error explicado se repite. Un error convertido en regla, no.

### Plan B del Acto 1

**Si `arch:check` no corre** (npm roto, node de otra versión, lo que sea): mostrá el **run fallido
de GitHub Actions ya grabado**.

Link del run fallido (real, grabado el 2026-10-27):
**https://github.com/falconcr/architecture-harness-starter/actions/runs/40566426718**

PR que lo produjo: **https://github.com/falconcr/architecture-harness-starter/pull/1**

Lo que se ve ahi, y que vale la pena senalar en escena:

| Job | Resultado |
|---|---|
| `1 · lint [determinista]` | pass |
| `2 · tests [determinista]` | pass |
| **`3 · arch:check [determinista]`** | **fail** — `error adr-001-domain-is-pure: src/domain/order.ts → src/infrastructure/db.ts` |
| `4 · conftest` … `7 · firma` | skipped (no se gastan recursos si la arquitectura ya falla) |
| `8 · review de arquitectura por IA` | skipped — **a proposito**: si la herramienta ya dijo exactamente que esta mal, no gastamos tokens en repetirlo con menos precision |
| `9 · aprobacion humana` | fail — el merge queda bloqueado |

Cómo regenerarlo (hacelo **antes** de la charla, no en vivo):

```bash
bash demo/act1-arch-violation.sh         # deja la rama con la violación
git push -u origin demo/acto-1-violacion
gh pr create --title "feat: persistir pedidos" --body "Guarda los pedidos en la base de datos" \
  --base main --head demo/acto-1-violacion
gh run list --branch demo/acto-1-violacion --limit 1      # copiá el link acá arriba
```

Abrilo en una pestaña del navegador **antes de empezar**. El job `3 · arch:check [determinista]`
en rojo, con el mismo mensaje de error, es tan convincente como la terminal. Y el comentario del
PR que dejó `architect-reviewer` es la frutilla: podés mostrar los dos lados del mismo hallazgo.

---

## Acto 2 — "El canary atrapa el bug"

**Tiempo:** ~6 min (el análisis tarda ~1,5 min por diseño) · **Comando:** `bash demo/act2-canary-catches-bug.sh`

### Lo que pasa

1. El Rollout `orders` está sano (5/5 réplicas, revisión estable).
2. Se construye `orders:v2-bug` y se carga en kind.
3. El script commitea en `deploy/k8s/rollout.yaml`: imagen `orders:v2-bug` y `FAULT_RATE: "0.3"`.
   **Las policies siguen pasando**: el manifiesto es válido, el bug no es de forma.
4. Push + `make argocd-app GIT_BRANCH=demo/acto-2-canary` + `make sync`: Argo CD sincroniza.
5. Argo Rollouts manda **20 %** del tráfico (1 de 5 réplicas) a la versión nueva.
6. El `AnalysisTemplate` **error-rate** espera 30 s, mide, y con **una** medición fallida aborta.
7. **Rollback automático** a la revisión estable. Nadie aprobó nada.
8. En la Terminal B, `canary-analyst` explica el veredicto.

### Lo que decís

> Este bug no lo atrapa ningún test unitario. No porque seamos malos escribiendo tests: porque
> depende de correr con tráfico real, con esta config, en este entorno. Hay una clase de bugs que
> **solo existe en producción**. La pregunta no es cómo evitarlos: es **quién los atrapa**.
>
> *(mostrar el diff del manifiesto)*
>
> Dos líneas. Imagen nueva, `FAULT_RATE` en `0.3`: tres de cada diez requests van a devolver 500.
> Y fíjense: `npm run policy` **pasa**. El manifiesto es perfectamente válido. Tiene su tag
> inmutable, sus resource limits, no es privilegiado, tiene los labels. **El bug no es de forma.**
>
> *(push)*
>
> Y acá hay algo importante: para desplegar esto **tuve que commitear**. No hay un botón de
> deploy. No hay un `kubectl apply`. El único que escribe en este cluster es Argo CD, y Argo CD
> solo lee de Git. Eso es el ADR-003, y es lo que hace que un agente no pueda desplegar: **no
> existe el camino**.
>
> *(el watch del rollout)*
>
> Ahora miren. 20 % del tráfico a la versión nueva: una réplica de cinco. El generador de carga
> le está pegando al Service. El análisis espera 30 segundos para que el pod acumule muestras, y
> después mide la tasa de error del canary **filtrando por el hash del pod template** — porque si
> midiera el promedio de las cinco réplicas, un 30 % de errores en una se diluiría a 6 % y casi
> no cruzaría el umbral.
>
> *(cuando aparece Degraded)*
>
> Ahí está. Análisis fallido, rollout abortado, de vuelta a la versión estable. **Nadie aprobó ese
> rollback. Nadie estaba mirando un dashboard.** Esto hubiera pasado igual a las tres de la mañana
> de un domingo.
>
> El valor no está en el dashboard. Está en que **nadie necesite mirar el dashboard** para que el
> rollback ocurra.
>
> *(mostrar `make analysis`)*
>
> Y acá está el mensaje exacto, para que no parezca magia:
> `RolloutAborted: Metric "error-rate" assessed Failed due to failed (2) > failureLimit (1)`.
> Dos mediciones por encima del umbral, y el límite era una.
>
> *(Terminal B: canary-analyst)*
>
> Ahora sí, el agente. Error rate del canary: **0,263** contra un umbral de 0,05. Latencia normal
> (4,8 ms), así que no era performance. Veredicto: el gate decidió bien.
>
> Y un detalle honesto: `FAULT_RATE` es 0,3 pero el gate midió 0,263, porque `/healthz` y
> `/readyz` del canary **nunca** fallan y diluyen un poco el promedio. Está bien que sea así: si
> la salud también fallara, el pod moriría por readiness y el canary se caería por otra razón, no
> por el análisis de métricas, que es lo que queremos mostrar.
>
> Y `canary-analyst` **no puede promover ni abortar**. Llega después del rollback, no en lugar del
> rollback. Su trabajo es que yo entienda en treinta segundos lo que pasó, no decidir.

### Plan B del Acto 2

Salida real guardada en **[`demo/act2-output.txt`](act2-output.txt)**:

```bash
cat demo/act2-output.txt
```

Tiene el `kubectl argo rollouts get rollout orders` con el análisis fallido y el rollback, más la
salida de `make analysis` con los valores medidos. Si el cluster se te muere en vivo, mostrás eso y
seguís sin perder el hilo: los números son los reales de una corrida de verdad.

Para regenerarlo después de una corrida buena:

```bash
{
  echo "# Salida real del Acto 2 - $(date -I)"; echo
  kubectl argo rollouts get rollout orders -n orders --context kind-harness
  echo; make analysis
} > demo/act2-output.txt
```

---

## Acto 3 — "Se cierra el ciclo"

**Tiempo:** ~5 min · **Comando:** `bash demo/act3-close-the-loop.sh`

### Lo que pasa

1. Se ve el incidente como lo ve quien recibe la alerta.
2. En la Terminal B, `incident-triage` hace el triage con **solo lectura**.
3. El script aplica el fix en la rama `fix/fault-rate-guard`:
   `FAULT_RATE` solo tiene efecto si `ALLOW_FAULT_INJECTION=true`.
4. **El test de regresión**: `test/fault-rate-guard.test.ts`, que falla sin el fix.
5. **El guardrail nuevo**: `policy/fault-injection.rego` prohíbe `FAULT_RATE > 0` en cualquier
   manifiesto desplegable. El script verifica que rechaza el manifiesto del Acto 2.
6. `npm run verify` → todo verde.
7. `gh pr create` → el PR entra al pipeline completo.
8. Falta una sola cosa: **que una persona apruebe**.

### Lo que decís

> El rollback no es el final. Si el ciclo termina en "volvimos a la versión anterior", mañana
> alguien vuelve a hacer lo mismo.
>
> *(Terminal B: incident-triage)*
>
> `incident-triage` puede leer logs, leer métricas, leer la historia de Git, escribir código y
> tests **en una rama**, correr los gates y abrir un PR.
>
> No puede tocar el cluster. No puede pushear a main. No puede mergear. **Su salida es un PR.
> Siempre.** No es el camino rápido: es el camino que deja aprendizaje.
>
> *(el fix)*
>
> Y miren el fix. No es "poné `FAULT_RATE` en cero otra vez" — eso arregla hoy. El fix es que
> `FAULT_RATE` **no tenga efecto** salvo que alguien lo habilite explícitamente. Hace que el
> estado malo sea imposible, no improbable.
>
> *(el test)*
>
> Con su test de regresión, que falla sin el fix. Sin ese test, el incidente vuelve en seis meses
> cuando nadie se acuerde de por qué estaba así.
>
> *(el guardrail)*
>
> Y esto es la parte que me importa más de toda la charla. Una **policy nueva**: ningún manifiesto
> desplegable puede declarar `FAULT_RATE` mayor a cero. Miren: la corremos contra el manifiesto que
> causó el incidente, y lo rechaza.
>
> **El manifiesto que causó el incidente ya no puede ni mergearse.**
>
> Ayer esto era un incidente. Hoy es una regla de CI. Y esa regla va a seguir trabajando dentro de
> un año, cuando ninguno de nosotros se acuerde de esta conversación.
>
> *(el PR)*
>
> El PR pasa por todo: lint, tests, `arch:check`, policies, build, SBOM, firma, y el review de IA
> que **comenta y no aprueba**. Y acá está el último eslabón: alguien tiene que apretar "Approve".
>
> *(cierre)*
>
> Deploy, Verify, Operate, Plan, Code, Review. El ciclo se cerró. Y el harness terminó **más
> fuerte** que antes del incidente.
>
> **Los agentes proponen. Los gates deterministas deciden. Los humanos son dueños de lo
> irreversible.**

### Plan B del Acto 3

Rama ya empujada y lista: **`demo/acto-3-fix`**. Si el script falla en vivo:

```bash
git switch demo/acto-3-fix          # el fix + el test + el guardrail, ya commiteados
npm run verify                      # verde
gh pr create --base main --head demo/acto-3-fix --fill
```

PR de ejemplo ya abierto (real): **https://github.com/falconcr/architecture-harness-starter/pull/5**
(sale de `demo/acto-3-fix`, que es una rama **permanente**: `demo/reset.sh` no la toca).

Ojo con esto si armás tu propio repo: el PR del plan B tiene que salir de una rama permanente.
Si lo abrís desde `fix/fault-rate-guard` —la rama que crea el acto en vivo— el primer
`demo/reset.sh` borra esa rama en `origin` y **cierra tu PR de plan B**. Pasó mientras se
verificaba este repo; de ahí la separación entre ramas efímeras y ramas de plan B en
[`demo/reset.sh`](reset.sh).

Descripción lista para pegar (si `gh` falla y lo tenés que crear desde la web):

```markdown
## Incidente: el canary de `orders` se revirtio solo

### Impacto
La revisión canary devolvía 500 en ~3 de cada 10 requests a `/orders`. Con 20 % del tráfico, el
`AnalysisTemplate` **error-rate** midió 26,3 % contra un umbral de 5 % y **Argo Rollouts abortó el
rollout y volvió a la revisión estable**. Ningún humano intervino.

### Causa raíz
`loadConfig()` lee `FAULT_RATE` directo del entorno sin ningún interruptor. Un valor heredado de
una rama de demo puede degradar el servicio en cualquier entorno.

### Evidencia
- `error-rate` del canary: **0,263** (umbral 0,05) → `Failed`
- `latency-p95`: normal → no era un problema de performance
- Manifiesto: `deploy/k8s/rollout.yaml` con `FAULT_RATE: "0.3"`

### El fix (mínimo)
`FAULT_RATE` solo tiene efecto si `ALLOW_FAULT_INJECTION=true`.

### Test de regresión
`test/fault-rate-guard.test.ts`: falla sin el fix, pasa con el fix.

### Guardrail nuevo
`policy/fault-injection.rego` prohíbe `FAULT_RATE > 0` y `ALLOW_FAULT_INJECTION=true` en cualquier
manifiesto desplegable.

### Verificación
`npm run verify` → OK

### Lo que NO hice
No toqué el cluster. El rollback lo hizo Argo Rollouts. **Este PR necesita aprobación humana.**

---
🤖 Propuesto por el subagente `incident-triage`. Los agentes proponen; los humanos aprueban.
```

---

## Reset: repetir la demo desde cero

```bash
bash demo/reset.sh
```

Hace exactamente esto:

1. `git switch main` + `git reset --hard` y borra los archivos que crean los actos
   (`src/infrastructure/db.ts`, `test/fault-rate-guard.test.ts`, `policy/fault-injection.rego`).
2. Borra las ramas de demo, local y en `origin`
   (`demo/acto-1-violacion`, `demo/acto-2-canary`, `fix/fault-rate-guard`).
3. Corre `npm run verify` para confirmar que `main` quedó verde.
4. Vuelve a apuntar Argo CD a `main` (lo que revierte el manifiesto del Acto 2), reinicia el
   Rollout y espera a que esté `Healthy`.

Si querés empezar de cero de cero:

```bash
make down && make up
```

---

## Checklist de 10 minutos antes

- [ ] `make up` corrió y `make rollout-status` dice **Healthy, 5/5**.
- [ ] `kubectl-argo-rollouts` instalado (`make install-rollouts-plugin`).
- [ ] `bash demo/reset.sh` corrido: `main` limpio, sin ramas de demo colgadas.
- [ ] Terminal B con `claude` abierto en la raíz del repo.
- [ ] Fuente grande en las dos terminales (≥ 16 pt) y fondo claro si la sala es grande.
- [ ] Pestañas del navegador abiertas **antes**:
      el run fallido del Acto 1 · el PR del Acto 3 · la UI de Argo CD (`make argocd-ui`).
- [ ] `demo/act2-output.txt` existe y tiene números reales.
- [ ] `demo/DEMO.md` abierto en otra ventana (este archivo) con los links de los planes B pegados.
- [ ] Wi-Fi probado: el Acto 2 necesita que Argo CD alcance GitHub.
- [ ] Nada de secretos en pantalla: cerrá cualquier terminal con `kubectl config view` o `.env`.
