/**
 * Toda la configuracion entra por variables de entorno y se valida aca.
 * El dominio nunca lee process.env (ADR-001).
 */
export interface AppConfig {
  readonly port: number;
  readonly host: string;
  /** Porcentaje de requests de negocio que devuelven 500. Solo para la demo del canary. */
  readonly faultRate: number;
  readonly version: string;
  readonly logLevel: string;
}

function numberFromEnv(raw: string | undefined, fallback: number, min: number, max: number): number {
  if (raw === undefined || raw.trim() === '') return fallback;
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(parsed, min), max);
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  return {
    port: numberFromEnv(env.PORT, 3000, 1, 65535),
    host: env.HOST ?? '0.0.0.0',
    // FAULT_RATE=0 por defecto: una build sana nunca inyecta fallos.
    faultRate: numberFromEnv(env.FAULT_RATE, 0, 0, 1),
    version: env.APP_VERSION ?? 'dev',
    logLevel: env.LOG_LEVEL ?? 'info',
  };
}
