import type { Order } from '../domain/order.js';
import type { Clock, IdGenerator, OrderRepository } from '../domain/order-repository.js';

/**
 * ADAPTADOR del puerto OrderRepository. Para la demo alcanza memoria;
 * cambiarlo por Postgres no toca ni el dominio ni la aplicacion (ADR-002).
 */
export class InMemoryOrderRepository implements OrderRepository {
  private readonly byId = new Map<string, Order>();

  async save(order: Order): Promise<void> {
    this.byId.set(order.id, order);
  }

  async findById(id: string): Promise<Order | undefined> {
    return this.byId.get(id);
  }

  async list(limit: number): Promise<readonly Order[]> {
    return [...this.byId.values()].slice(-limit).reverse();
  }
}

export class SystemClock implements Clock {
  nowIso(): string {
    return new Date().toISOString();
  }
}

export class RandomIdGenerator implements IdGenerator {
  next(): string {
    return `ord_${crypto.randomUUID()}`;
  }
}
