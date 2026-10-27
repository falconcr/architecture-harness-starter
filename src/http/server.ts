import Fastify, { type FastifyInstance } from 'fastify';
import { CreateOrderUseCase } from '../application/create-order.js';
import { ListOrdersUseCase } from '../application/list-orders.js';
import type { AppConfig } from '../infrastructure/config.js';
import {
  InMemoryOrderRepository,
  RandomIdGenerator,
  SystemClock,
} from '../infrastructure/in-memory-order-repository.js';
import { createMetrics } from '../infrastructure/metrics.js';
import { createFaultInjector } from './fault-injection.js';
import { registerRoutes } from './routes.js';

/**
 * Composition root: el unico lugar del repo donde se eligen implementaciones
 * concretas para los puertos del dominio.
 */
export async function buildServer(config: AppConfig): Promise<FastifyInstance> {
  const app = Fastify({ logger: { level: config.logLevel } });

  const repository = new InMemoryOrderRepository();
  const metrics = createMetrics(config.version);

  await registerRoutes(app, {
    createOrder: new CreateOrderUseCase(repository, new RandomIdGenerator(), new SystemClock()),
    listOrders: new ListOrdersUseCase(repository),
    metrics,
    faults: createFaultInjector(config.faultRate),
    version: config.version,
  });

  // Instrumentacion transversal: un unico punto que alimenta http_requests_total
  // y http_request_duration_seconds para todas las rutas.
  app.addHook('onRequest', async (request) => {
    (request as { startedAt?: bigint }).startedAt = process.hrtime.bigint();
  });

  app.addHook('onResponse', async (request, reply) => {
    const startedAt = (request as { startedAt?: bigint }).startedAt;
    const durationSeconds =
      startedAt === undefined ? 0 : Number(process.hrtime.bigint() - startedAt) / 1e9;

    metrics.observe({
      method: request.method,
      // routeOptions.url mantiene la cardinalidad baja (/orders, no /orders/123).
      route: request.routeOptions?.url ?? 'unknown',
      status: reply.statusCode,
      durationSeconds,
    });
  });

  return app;
}
