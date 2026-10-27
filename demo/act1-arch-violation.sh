#!/usr/bin/env bash
# =============================================================================
# ACTO 1 — "El agente viola la arquitectura"
#
# Que se demuestra: un ADR escrito en un documento no protege nada. El mismo ADR
# convertido en una regla ejecutable falla en 2 segundos, en la laptop y en CI,
# con un mensaje que nombra la decision violada.
#
# Duracion: ~4 minutos.
# =============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BRANCH="demo/acto-1-violacion"

banner "ACTO 1 — El agente viola la arquitectura"

say "0. Punto de partida: main esta verde"
run npm run arch:check
pause_demo

say "1. Creamos la rama donde 'el agente' hizo su cambio"
require_clean_tree
git switch -c "$BRANCH" 2>/dev/null || git switch "$BRANCH"

note "El pedido fue: 'guarda los pedidos en la base de datos'."
note "El agente hizo lo mas directo que compila: importar el cliente de BD"
note "desde el dominio. No fue descuidado: fue literal."

cat > src/infrastructure/db.ts <<'TS'
// Cliente de base de datos (adaptador de infraestructura).
export interface QueryResult {
  readonly rows: readonly unknown[];
}

export const db = {
  async query(sql: string, params: readonly unknown[] = []): Promise<QueryResult> {
    // En la demo no hay BD real: lo que importa es DONDE vive este modulo.
    void sql;
    void params;
    return { rows: [] };
  },
};
TS

python3 - <<'PY'
from pathlib import Path

path = Path("src/domain/order.ts")
source = path.read_text()

source = source.replace(
    "import { InvalidOrderError } from './errors.js';",
    "import { InvalidOrderError } from './errors.js';\n"
    "// El agente agrego esto: el dominio pasa a depender de infraestructura.\n"
    "import { db } from '../infrastructure/db.js';",
)

source += '''
/**
 * El agente agrego esta funcion al dominio porque "ahi estaba la entidad Order".
 * Parece razonable. Rompe el ADR-001.
 */
export async function persistOrder(order: Order): Promise<void> {
  await db.query('INSERT INTO orders (id, customer_id, total_cents) VALUES ($1, $2, $3)', [
    order.id,
    order.customerId,
    order.totalCents,
  ]);
}
'''
path.write_text(source)
print("  modificado: src/domain/order.ts")
print("  creado:     src/infrastructure/db.ts")
PY

run git --no-pager diff --stat
pause_demo

say "2. Los tests pasan. El typecheck pasa. El lint pasa."
note "Por eso el code review humano se lo come: el diff se ve razonable."
run npm test -- --reporter=dot 2>&1 | tail -5 || true
pause_demo

say "3. Y aca el gate determinista dice que no"
echo ""
if npm run arch:check; then
  bad "ESTO NO DEBERIA PASAR: la regla no atrapo la violacion."
  warn "Revisá .dependency-cruiser.js"
  exit 1
fi
echo ""
ok "arch:check fallo, como tiene que ser."
note "El mensaje no dice 'error de arquitectura'. Dice QUE decision se violo,"
note "DONDE, y se puede leer el ADR completo en docs/adr/001-domain-pure.md."
pause_demo

say "4. Ahora el agente explica (no decide)"
cat <<'MSG'

  En Claude Code, en otra terminal:

    > Usa el subagente architect-reviewer para revisar el diff de esta rama
    > contra los ADRs y explicarme que decision se violo y como se arregla.

  architect-reviewer solo tiene Read y Grep. No puede editar el codigo, no puede
  aprobar el PR y no puede desactivar la regla. Explica. La decision ya la tomo
  la herramienta.

  Lo que va a decir, en resumen:
    - Violacion: ADR-001, regla adr-001-domain-is-pure
    - Donde: src/domain/order.ts -> src/infrastructure/db.ts
    - Arreglo: persistOrder no va en el dominio. El dominio ya declara el puerto
      OrderRepository; el INSERT va en un adaptador de src/infrastructure que
      implemente ese puerto, y el caso de uso lo recibe por constructor.

MSG
pause_demo

say "5. El movimiento que cierra el acto: convertir el error en una regla"
cat <<'MSG'

  Esta violacion ya estaba cubierta. La pregunta interesante es la otra:
  cuando un agente encuentra un hueco que NINGUNA regla atrapa.

  Ejemplo real de este repo: nada impide hoy que un caso de uso escriba SQL
  directo en un string. El ADR-002 lo prohibe en espiritu; ninguna regla lo
  verifica. Asi se cierra el hueco (3 lineas en .dependency-cruiser.js):

MSG
cat <<'RULE'
    {
      name: 'adr-002-no-sql-outside-infrastructure',
      comment:
        'ADR-002: el SQL vive en adaptadores de src/infrastructure. ' +
        'Un caso de uso que escribe SQL ya esta acoplado al motor de base de datos.',
      severity: 'error',
      from: { path: '^src/(domain|application)' },
      to: { path: '^src/infrastructure/(db|sql)' },
    },
RULE
cat <<'MSG'

  Y la regla de oro del harness:

    Cada error de un agente que no esta cubierto por una regla
    se convierte en una regla ANTES de mergear el fix.

    Un error explicado se repite. Un error convertido en regla, no.

MSG
pause_demo

say "6. Plan B / reset"
note "Si algo falla en escena: demo/DEMO.md tiene el link al run fallido de CI ya grabado."
note "Para volver a main limpio:  bash demo/reset.sh"
echo ""
ok "Fin del Acto 1."
