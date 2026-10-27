import { Counter, Histogram, Registry, collectDefaultMetrics } from 'prom-client';

/**
 * Adaptador de observabilidad. Los nombres de estas metricas son contrato
 * publico: el AnalysisTemplate "error-rate" de Argo Rollouts los consulta.
 * Cambiarlos rompe el gate del canary.
 */
export interface Metrics {
  readonly registry: Registry;
  observe(params: { method: string; route: string; status: number; durationSeconds: number }): void;
}

export function createMetrics(version: string): Metrics {
  const registry = new Registry();
  registry.setDefaultLabels({ app: 'orders', version });
  collectDefaultMetrics({ register: registry });

  const httpRequestsTotal = new Counter({
    name: 'http_requests_total',
    help: 'Total de requests HTTP atendidos por el servicio orders',
    labelNames: ['method', 'route', 'status'] as const,
    registers: [registry],
  });

  const httpRequestDuration = new Histogram({
    name: 'http_request_duration_seconds',
    help: 'Latencia de los requests HTTP en segundos',
    labelNames: ['method', 'route', 'status'] as const,
    // Buckets pensados para que el p95 del gate (300 ms) caiga en un borde util.
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2.5],
    registers: [registry],
  });

  return {
    registry,
    observe({ method, route, status, durationSeconds }) {
      const labels = { method, route, status: String(status) };
      httpRequestsTotal.inc(labels);
      httpRequestDuration.observe(labels, durationSeconds);
    },
  };
}
