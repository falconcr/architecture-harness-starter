import type { Order } from '../domain/order.js';
import type { OrderRepository } from '../domain/order-repository.js';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

export class ListOrdersUseCase {
  constructor(private readonly orders: OrderRepository) {}

  async execute(limit: number = DEFAULT_LIMIT): Promise<readonly Order[]> {
    const safeLimit = Math.min(Math.max(1, Math.trunc(limit)), MAX_LIMIT);
    return this.orders.list(safeLimit);
  }
}
