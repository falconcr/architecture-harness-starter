import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { loadConfig } from '../src/infrastructure/config.js';
import { buildServer } from '../src/http/server.js';

let app: FastifyInstance | undefined;

afterEach(async () => {
  await app?.close();
  app = undefined;
});

/**
 * Estas metricas son el contrato con el AnalysisTemplate "error-rate".
 * Si este test se rompe, el gate del canary queda ciego: tratalo como un fallo
 * de arquitectura, no como un test molesto.
 */
describe('/metrics', () => {
  it('expone http_requests_total con label status', async () => {
    app = await buildServer(loadConfig({ LOG_LEVEL: 'silent' }));
    await app.inject({ method: 'GET', url: '/orders' });

    const res = await app.inject({ method: 'GET', url: '/metrics' });
    expect(res.statusCode).toBe(200);
    expect(res.body).toContain('http_requests_total');
    expect(res.body).toMatch(/http_requests_total\{[^}]*status="200"[^}]*\}/);
    expect(res.body).toMatch(/route="\/orders"/);
  });

  it('expone el histograma de latencia con buckets para p95', async () => {
    app = await buildServer(loadConfig({ LOG_LEVEL: 'silent' }));
    await app.inject({ method: 'GET', url: '/orders' });

    const body = (await app.inject({ method: 'GET', url: '/metrics' })).body;
    expect(body).toContain('http_request_duration_seconds_bucket');
    expect(body).toContain('le="0.3"');
  });

  it('cuenta los 500 inyectados con status="500"', async () => {
    app = await buildServer(loadConfig({ LOG_LEVEL: 'silent', FAULT_RATE: '0.5', ALLOW_FAULT_INJECTION: 'true' }));
    for (let i = 0; i < 10; i += 1) {
      await app.inject({ method: 'GET', url: '/orders' });
    }

    const body = (await app.inject({ method: 'GET', url: '/metrics' })).body;
    expect(body).toMatch(/http_requests_total\{[^}]*status="500"[^}]*\} 5\b/);
  });
});
