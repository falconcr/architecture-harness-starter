/**
 * Inyector de fallos determinista para la demo del canary (Acto 2).
 *
 * Por que determinista y no Math.random(): en escena necesitamos que con
 * FAULT_RATE=0.3 exactamente 3 de cada 10 requests fallen. Con aleatoriedad,
 * una racha de suerte puede dejar el canary por debajo del umbral y la demo
 * no demuestra nada.
 */
export interface FaultInjector {
  shouldFail(): boolean;
}

export function createFaultInjector(faultRate: number): FaultInjector {
  let seen = 0;
  let failed = 0;

  return {
    shouldFail(): boolean {
      if (faultRate <= 0) return false;
      seen += 1;
      // Mantiene la proporcion acumulada lo mas cerca posible de faultRate.
      if (failed < Math.round(seen * faultRate)) {
        failed += 1;
        return true;
      }
      return false;
    },
  };
}
