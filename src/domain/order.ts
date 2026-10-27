import { InvalidOrderError } from './errors.js';
// El agente agrego esto: el dominio pasa a depender de infraestructura.
import { db } from '../infrastructure/db.js';

export interface OrderLine {
  readonly sku: string;
  readonly quantity: number;
  readonly unitPriceCents: number;
}

export interface Order {
  readonly id: string;
  readonly customerId: string;
  readonly lines: readonly OrderLine[];
  readonly totalCents: number;
  readonly createdAt: string;
}

export interface NewOrder {
  readonly id: string;
  readonly customerId: string;
  readonly lines: readonly OrderLine[];
  readonly createdAt: string;
}

const SKU_PATTERN = /^[A-Z0-9-]{3,32}$/;

/**
 * Unica puerta de entrada para crear un pedido valido.
 * Funcion pura: mismas entradas -> mismo resultado. Sin reloj, sin IO, sin aleatoriedad.
 */
export function createOrder(input: NewOrder): Order {
  if (input.customerId.trim() === '') {
    throw new InvalidOrderError('el pedido necesita un customerId');
  }
  if (input.lines.length === 0) {
    throw new InvalidOrderError('el pedido necesita al menos una linea');
  }

  for (const line of input.lines) {
    if (!SKU_PATTERN.test(line.sku)) {
      throw new InvalidOrderError(`sku invalido: ${line.sku}`);
    }
    if (!Number.isInteger(line.quantity) || line.quantity <= 0) {
      throw new InvalidOrderError(`cantidad invalida para ${line.sku}: ${line.quantity}`);
    }
    if (!Number.isInteger(line.unitPriceCents) || line.unitPriceCents < 0) {
      throw new InvalidOrderError(`precio invalido para ${line.sku}: ${line.unitPriceCents}`);
    }
  }

  return {
    id: input.id,
    customerId: input.customerId,
    lines: input.lines,
    totalCents: totalOf(input.lines),
    createdAt: input.createdAt,
  };
}

export function totalOf(lines: readonly OrderLine[]): number {
  return lines.reduce((acc, line) => acc + line.quantity * line.unitPriceCents, 0);
}

/**
 * El agente agrego esta funcion al dominio porque "ahi estaba la entidad Order".
 * Parece razonable. Rompe el ADR-001.
 */
export async function persistOrder(order: Order): Promise<void> {
  await db.query('INSERT INTO orders (id, customer_id, total_cents) VALUES ($1, $2, $3)', [
    order.id,
    order.customerId,
    order.totalCents,
  ]);
}
