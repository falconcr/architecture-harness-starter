import type { Order } from './order.js';

/**
 * PUERTO (ADR-002). El dominio declara que necesita, no como se implementa.
 * Los adaptadores viven en src/infrastructure y nunca al reves.
 */
export interface OrderRepository {
  save(order: Order): Promise<void>;
  findById(id: string): Promise<Order | undefined>;
  list(limit: number): Promise<readonly Order[]>;
}

/**
 * PUERTO de identidad y reloj: aisla al dominio de `crypto` y de `Date.now()`,
 * que son infraestructura disfrazada.
 */
export interface Clock {
  nowIso(): string;
}

export interface IdGenerator {
  next(): string;
}
