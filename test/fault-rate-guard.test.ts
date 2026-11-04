import { describe, expect, it } from 'vitest';
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
