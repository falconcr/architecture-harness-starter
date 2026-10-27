#!/usr/bin/env bash
# =============================================================================
# ACTO 3 — "Se cierra el ciclo"
#
# Que se demuestra: el incidente del Acto 2 no termina en un rollback. Vuelve a
# entrar al ciclo como PR, pasa por el pipeline completo, y lo aprueba una
# persona. El aprendizaje queda en el repo como guardrail, no en la cabeza de
# quien estuvo de guardia.
#
# Duracion: ~5 minutos.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BRANCH="${ACT3_BRANCH:-fix/fault-rate-guard}"

banner "ACTO 3 — Se cierra el ciclo"

say "1. El incidente: lo que ve quien recibe la alerta"
if $KUBECTL cluster-info >/dev/null 2>&1; then
  run rollout_view
  run make --no-print-directory analysis
else
  warn "Sin cluster: usando la salida guardada (plan B)."
  run cat demo/act2-output.txt
fi
pause_demo

say "2. El agente hace el triage (solo lectura en 'produccion')"
cat <<'MSG'

  En Claude Code:

    > Usa el subagente incident-triage: el canary del Rollout orders se revirtio.
    > Analizá metricas y logs, encontrá la causa raiz y propone el fix como rama y PR.

  incident-triage puede: leer logs, leer metricas, leer la historia de Git,
  escribir codigo y tests en una rama, correr npm run verify y abrir un PR.

  NO puede: tocar el cluster, pushear a main, mergear ni aprobar.
  Su salida es un PR. Siempre.

MSG
pause_demo

say "3. El fix que propone (y que vamos a aplicar en la rama)"
require_clean_tree
git switch -c "$BRANCH" 2>/dev/null || git switch "$BRANCH"

note "Causa raiz: FAULT_RATE es una variable de demo, pero nada impide que un"
note "valor > 0 llegue a un entorno que no sea de desarrollo. El fix minimo no es"
note "'poner 0 otra vez': es hacer que ese estado sea imposible."

python3 - <<'PY'
from pathlib import Path

# --- 1) El fix: FAULT_RATE solo tiene efecto si se habilita explicitamente.
config = Path("src/infrastructure/config.ts")
source = config.read_text()

source = source.replace(
    """  return {
    port: numberFromEnv(env.PORT, 3000, 1, 65535),
    host: env.HOST ?? '0.0.0.0',
    // FAULT_RATE=0 por defecto: una build sana nunca inyecta fallos.
    faultRate: numberFromEnv(env.FAULT_RATE, 0, 0, 1),""",
    """  // FAULT_RATE solo tiene efecto si ALGUIEN lo habilita explicitamente con
  // ALLOW_FAULT_INJECTION=true. Sin ese interruptor, un FAULT_RATE heredado de
  // una rama de demo no puede degradar el servicio.
  // Causa raiz del incidente del 2026-10-27: un FAULT_RATE=0.3 llego al deploy.
  const faultInjectionAllowed = env.ALLOW_FAULT_INJECTION === 'true';

  return {
    port: numberFromEnv(env.PORT, 3000, 1, 65535),
    host: env.HOST ?? '0.0.0.0',
    // FAULT_RATE=0 por defecto: una build sana nunca inyecta fallos.
    faultRate: faultInjectionAllowed ? numberFromEnv(env.FAULT_RATE, 0, 0, 1) : 0,""",
)

source = source.replace(
    """  /** Porcentaje de requests de negocio que devuelven 500. Solo para la demo del canary. */
  readonly faultRate: number;""",
    """  /**
   * Porcentaje de requests de negocio que devuelven 500. Solo para la demo del canary.
   * Vale 0 salvo que ALLOW_FAULT_INJECTION sea exactamente 'true'.
   */
  readonly faultRate: number;""",
)
config.write_text(source)
print("  src/infrastructure/config.ts  (el fix)")

# --- 2) El test de regresion: falla sin el fix, pasa con el fix.
Path("test/fault-rate-guard.test.ts").write_text('''import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/infrastructure/config.js';

/**
 * Test de regresion del incidente del 2026-10-27.
 *
 * El canary de orders:v2-bug se revirtio porque un FAULT_RATE=0.3 llego al
 * manifiesto de deploy. El rollback automatico funciono; este test existe para
 * que la causa no pueda volver.
 *
 * Sin el fix en src/infrastructure/config.ts, el primer caso falla.
 */
describe('FAULT_RATE necesita habilitacion explicita', () => {
  it('ignora FAULT_RATE si ALLOW_FAULT_INJECTION no esta en true', () => {
    expect(loadConfig({ FAULT_RATE: '0.3' }).faultRate).toBe(0);
  });

  it('ignora FAULT_RATE si ALLOW_FAULT_INJECTION tiene cualquier otro valor', () => {
    for (const value of ['1', 'yes', 'TRUE', 'si', '']) {
      expect(loadConfig({ FAULT_RATE: '0.9', ALLOW_FAULT_INJECTION: value }).faultRate).toBe(0);
    }
  });

  it('respeta FAULT_RATE cuando se habilita a proposito (la demo sigue funcionando)', () => {
    const config = loadConfig({ FAULT_RATE: '0.3', ALLOW_FAULT_INJECTION: 'true' });
    expect(config.faultRate).toBeCloseTo(0.3);
  });

  it('sigue acotando el valor al rango 0..1', () => {
    expect(loadConfig({ FAULT_RATE: '5', ALLOW_FAULT_INJECTION: 'true' }).faultRate).toBe(1);
    expect(loadConfig({ FAULT_RATE: '-2', ALLOW_FAULT_INJECTION: 'true' }).faultRate).toBe(0);
  });
});
''')
print("  test/fault-rate-guard.test.ts  (el test de regresion)")

# --- 3) El fix cambia el contrato de FAULT_RATE: los tests que dependian del
#        comportamiento anterior se actualizan EN EL MISMO PR, a la vista.
routes = Path("test/routes.test.ts")
source = routes.read_text()
source = source.replace(
    "const server = await startApp({ FAULT_RATE: '0.3' });",
    "const server = await startApp({ FAULT_RATE: '0.3', ALLOW_FAULT_INJECTION: 'true' });",
)
routes.write_text(source)
print("  test/routes.test.ts            (actualizado al contrato nuevo)")

metrics = Path("test/metrics.test.ts")
source = metrics.read_text()
source = source.replace(
    "loadConfig({ LOG_LEVEL: 'silent', FAULT_RATE: '0.5' })",
    "loadConfig({ LOG_LEVEL: 'silent', FAULT_RATE: '0.5', ALLOW_FAULT_INJECTION: 'true' })",
)
metrics.write_text(source)
print("  test/metrics.test.ts           (actualizado al contrato nuevo)")
PY

run git --no-pager diff --stat
pause_demo

say "4. El guardrail: para que esta clase de error no vuelva nunca"
note "Un fix sin guardrail es un fix que depende de que alguien se acuerde."
note "Agregamos una policy que PROHIBE que un manifiesto declare FAULT_RATE > 0."

cat > policy/fault-injection.rego <<'REGO'
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
REGO
echo ""
note "Prueba del guardrail nuevo: tiene que RECHAZAR el manifiesto del Acto 2."
# El directorio de prueba va DENTRO del repo: conftest puede correr en un contenedor
# que solo monta el repo, asi que una ruta de /tmp no existiria ahi adentro.
GUARDRAIL_CHECK_DIR=".harness-tmp/guardrail-check"
mkdir -p "$GUARDRAIL_CHECK_DIR"
sed -e 's/value: "0"/value: "0.3"/' deploy/k8s/rollout.yaml > "$GUARDRAIL_CHECK_DIR/rollout.yaml"
# Capturamos la salida en una variable ANTES de buscar: con `pipefail` activo, el
# `if` de un pipe lee el exit code de conftest (1 porque la policy FALLA, que es
# justo lo que queremos comprobar) en vez del de grep.
guardrail_output="$(bash scripts/conftest.sh "$GUARDRAIL_CHECK_DIR" 2>&1 || true)"
if grep -q 'FAULT_RATE' <<<"$guardrail_output"; then
  ok "El guardrail rechaza el manifiesto que causo el incidente:"
  grep -E 'FAIL' <<<"$guardrail_output" | sed 's/^/    /'
else
  bad "El guardrail NO atrapo el manifiesto. Revisá policy/fault-injection.rego"
  tail -5 <<<"$guardrail_output"
fi
rm -rf .harness-tmp
echo ""
note "Y acepta el manifiesto sano de main:"
run npm run policy
pause_demo

say "5. Los gates deterministas, antes de abrir el PR"
note "incident-triage no abre un PR que no pase 'npm run verify'. Ni deberia."
echo ""
printf '%s$ npm run verify%s\n' "$BOLD" "$RESET"
if ! npm run verify; then
  echo ""
  bad "npm run verify FALLO: no se abre el PR."
  note "Esto no es un bug de la demo: es el gate funcionando. Un agente que abre"
  note "un PR que no pasa los gates le pasa el problema al revisor humano."
  note "Arreglá lo que falla y volvé a correr el acto."
  exit 1
fi
echo ""
ok "Todos los gates pasan. Ahora si se puede abrir el PR."
pause_demo

say "6. El PR"
run git add src/infrastructure/config.ts test/fault-rate-guard.test.ts \
  test/routes.test.ts test/metrics.test.ts policy/fault-injection.rego

git commit -q -F - <<'MSG'
fix: FAULT_RATE requiere habilitacion explicita

Causa raiz: FAULT_RATE se lee directo del entorno, asi que un valor heredado de
una rama de demo puede degradar el servicio en cualquier entorno. El canary lo
atrapo (AnalysisTemplate error-rate, 26,3 % de errores contra un umbral de 5 %)
y Argo Rollouts revirtio solo.

Fix: FAULT_RATE solo tiene efecto si ALLOW_FAULT_INJECTION=true.
Test de regresion: test/fault-rate-guard.test.ts (falla sin el fix).
Los tests que dependian del contrato anterior (routes, metrics) pasan ahora
ALLOW_FAULT_INJECTION=true explicitamente: el cambio de contrato queda a la vista
en el diff, no escondido.
Guardrail nuevo: policy/fault-injection.rego prohibe FAULT_RATE > 0 en cualquier
manifiesto desplegable, asi este manifiesto ya no puede ni mergearse.

Verificado con: npm run verify
MSG
ok "Commit creado (convencional: lo va a tomar release-notes)."

if ! git push -u origin "$BRANCH"; then
  echo ""
  bad "No pude pushear '$BRANCH'."
  note "Si quedo una rama vieja de un ensayo anterior:  bash demo/reset.sh"
  exit 1
fi

PR_BODY="$(mktemp)"
cat > "$PR_BODY" <<'MSG'
## Incidente: el canary de `orders` se revirtio solo

### Impacto
La revision canary devolvia 500 en ~3 de cada 10 requests a `/orders`. Con 20 % del trafico,
el `AnalysisTemplate` **error-rate** midio 26,3 % contra un umbral de 5 % y **Argo Rollouts
abortó el rollout y volvio a la revision estable**. Ningun humano intervino.

### Causa raiz
`loadConfig()` lee `FAULT_RATE` directo del entorno sin ningun interruptor. Un valor heredado de
una rama de demo puede degradar el servicio en cualquier entorno.

### Evidencia
- `error-rate` del canary: **0,263** (umbral 0,05) → `Failed`
- `latency-p95`: normal → no era un problema de performance
- Manifiesto: `deploy/k8s/rollout.yaml` con `FAULT_RATE: "0.3"`

### El fix (minimo)
`FAULT_RATE` solo tiene efecto si `ALLOW_FAULT_INJECTION=true`. Sin ese interruptor explicito,
vale 0 siempre.

### Test de regresion
`test/fault-rate-guard.test.ts`: falla sin el fix, pasa con el fix.

Y los tests que dependian del contrato anterior (`test/routes.test.ts`,
`test/metrics.test.ts`) ahora piden `ALLOW_FAULT_INJECTION=true` explicitamente. El cambio de
contrato esta en el diff, no escondido detras de un test borrado.

### Guardrail nuevo
`policy/fault-injection.rego` **prohibe** `FAULT_RATE > 0` y `ALLOW_FAULT_INJECTION=true` en
cualquier manifiesto desplegable. El manifiesto que causo el incidente ya no puede mergearse.

### Verificacion
```
$ npm run verify     # lint + typecheck + test + arch:check + policy  -> OK
```

### Lo que NO hice
No toqué el cluster. El rollback lo hizo Argo Rollouts. **Este PR necesita aprobacion humana.**

---
🤖 Propuesto por el subagente `incident-triage`. Los agentes proponen; los humanos aprueban.
MSG

if command -v gh >/dev/null 2>&1; then
  run gh pr create \
    --title "fix: FAULT_RATE requiere habilitacion explicita" \
    --body-file "$PR_BODY" \
    --base main --head "$BRANCH" || warn "No se pudo crear el PR (plan B: demo/DEMO.md tiene el PR ya preparado)."
else
  warn "gh no esta instalado. Descripcion del PR guardada en: $PR_BODY"
fi
pause_demo

say "7. El ciclo cerrado"
cat <<'MSG'

  Lo que acaba de pasar, en orden:

    Deploy    el canary recibio 20 % del trafico
    Verify    el gate midio, decidio, y REVIRTIO solo
    Operate   el agente hizo triage (solo lectura)
    Plan      el agente propuso el fix + un guardrail nuevo
    Code      el fix viene con test de regresion
    Review    el pipeline completo: lint, tests, arch, policy, build, SBOM, firma, review IA
    -> Humano aprueba el merge

  Y lo importante: el aprendizaje no quedo en la cabeza de quien estuvo de guardia.
  Quedo en policy/fault-injection.rego, donde va a seguir trabajando dentro de un ano.

  "Los agentes proponen, los gates deterministas deciden,
   los humanos son duenos de lo irreversible."

MSG
ok "Fin del Acto 3. Falta UNA cosa: que una persona apruebe el PR."
