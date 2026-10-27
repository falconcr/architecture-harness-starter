import { afterEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { loadConfig } from '../src/infrastructure/config.js';
import { buildServer } from '../src/http/server.js';

let app: FastifyInstance | undefined;

async function startApp(env: Record<string, string> = {}): Promise<FastifyInstance> {
  app = await buildServer(loadConfig({ LOG_LEVEL: 'silent', ...env }));
  return app;
}

afterEach(async () => {
  await app?.close();
  app = undefined;
});

const validOrder = {
  customerId: 'cust_1',
  lines: [{ sku: 'SKU-001', quantity: 2, unitPriceCents: 500 }],
};

describe('endpoints de salud', () => {
  it('GET /healthz responde ok', async () => {
    const server = await startApp();
    const res = await server.inject({ method: 'GET', url: '/healthz' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'ok' });
  });

  it('GET /readyz responde ready', async () => {
    const server = await startApp();
    const res = await server.inject({ method: 'GET', url: '/readyz' });
    expect(res.statusCode).toBe(200);
  });
});

describe('endpoint de negocio', () => {
  it('POST /orders crea el pedido', async () => {
    const server = await startApp();
    const res = await server.inject({ method: 'POST', url: '/orders', payload: validOrder });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({ customerId: 'cust_1', totalCents: 1000 });
  });

  it('POST /orders traduce el error de dominio a 400', async () => {
    const server = await startApp();
    const res = await server.inject({ method: 'POST', url: '/orders', payload: { customerId: '' } });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toMatchObject({ error: 'INVALID_ORDER' });
  });

  it('GET /orders devuelve lo creado', async () => {
    const server = await startApp();
    await server.inject({ method: 'POST', url: '/orders', payload: validOrder });
    const res = await server.inject({ method: 'GET', url: '/orders' });
    expect(res.statusCode).toBe(200);
    expect(res.json().count).toBe(1);
  });
});

describe('FAULT_RATE', () => {
  it('con FAULT_RATE=0 (default) nunca falla', async () => {
    const server = await startApp();
    for (let i = 0; i < 20; i += 1) {
      const res = await server.inject({ method: 'GET', url: '/orders' });
      expect(res.statusCode).toBe(200);
    }
  });

  it('con FAULT_RATE=0.3 falla aproximadamente el 30% de los requests', async () => {
    const server = await startApp({ FAULT_RATE: '0.3' });
    let failures = 0;
    const total = 100;
    for (let i = 0; i < total; i += 1) {
      const res = await server.inject({ method: 'GET', url: '/orders' });
      if (res.statusCode === 500) failures += 1;
    }
    // Determinista: el inyector mantiene la proporcion acumulada.
    expect(failures).toBe(30);
  });

  it('con FAULT_RATE=0.3 la salud sigue sana (el canary debe morir por analisis, no por readiness)', async () => {
    const server = await startApp({ FAULT_RATE: '0.3' });
    for (let i = 0; i < 20; i += 1) {
      expect((await server.inject({ method: 'GET', url: '/healthz' })).statusCode).toBe(200);
      expect((await server.inject({ method: 'GET', url: '/readyz' })).statusCode).toBe(200);
    }
  });
});
