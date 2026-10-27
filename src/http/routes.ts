import type { FastifyInstance } from 'fastify';
import type { CreateOrderUseCase } from '../application/create-order.js';
import type { ListOrdersUseCase } from '../application/list-orders.js';
import { DomainError } from '../domain/errors.js';
import type { OrderLine } from '../domain/order.js';
import type { Metrics } from '../infrastructure/metrics.js';
import type { FaultInjector } from './fault-injection.js';

export interface RouteDeps {
  readonly createOrder: CreateOrderUseCase;
  readonly listOrders: ListOrdersUseCase;
  readonly metrics: Metrics;
  readonly faults: FaultInjector;
  readonly version: string;
}

interface CreateOrderBody {
  customerId?: unknown;
  lines?: unknown;
}

function parseLines(raw: unknown): readonly OrderLine[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((item) => {
    const line = item as Record<string, unknown>;
    return {
      sku: String(line.sku ?? ''),
      quantity: Number(line.quantity ?? 0),
      unitPriceCents: Number(line.unitPriceCents ?? 0),
    };
  });
}

export async function registerRoutes(app: FastifyInstance, deps: RouteDeps): Promise<void> {
  // --- Salud: nunca inyecta fallos. Si /healthz fallara, el canary moriria por
  // --- readiness y no por el analisis de metricas, que es lo que queremos mostrar.
  app.get('/healthz', async () => ({ status: 'ok', version: deps.version }));
  app.get('/readyz', async () => ({ status: 'ready', version: deps.version }));

  // --- Metricas que consume Prometheus y, a traves de el, el AnalysisTemplate "error-rate".
  app.get('/metrics', async (_request, reply) => {
    reply.header('content-type', deps.metrics.registry.contentType);
    return deps.metrics.registry.metrics();
  });

  // --- Endpoint de negocio: crear pedido.
  app.post('/orders', async (request, reply) => {
    if (deps.faults.shouldFail()) {
      return reply.code(500).send({ error: 'INTERNAL', message: 'fallo inyectado (FAULT_RATE)' });
    }

    const body = (request.body ?? {}) as CreateOrderBody;
    try {
      const order = await deps.createOrder.execute({
        customerId: String(body.customerId ?? ''),
        lines: parseLines(body.lines),
      });
      return reply.code(201).send(order);
    } catch (error) {
      // El adaptador es el unico que traduce dominio -> HTTP (ADR-002).
      if (error instanceof DomainError) {
        return reply.code(400).send({ error: error.code, message: error.message });
      }
      throw error;
    }
  });

  app.get('/orders', async (request, reply) => {
    if (deps.faults.shouldFail()) {
      return reply.code(500).send({ error: 'INTERNAL', message: 'fallo inyectado (FAULT_RATE)' });
    }
    const limit = Number((request.query as Record<string, unknown> | undefined)?.limit ?? 20);
    const orders = await deps.listOrders.execute(Number.isFinite(limit) ? limit : 20);
    return reply.code(200).send({ items: orders, count: orders.length });
  });
}
