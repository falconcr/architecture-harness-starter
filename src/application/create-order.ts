import { createOrder, type NewOrder, type Order, type OrderLine } from '../domain/order.js';
import type { Clock, IdGenerator, OrderRepository } from '../domain/order-repository.js';

export interface CreateOrderCommand {
  readonly customerId: string;
  readonly lines: readonly OrderLine[];
}

/**
 * Caso de uso. Recibe los puertos por constructor: no importa ni un solo
 * modulo de src/infrastructure (lo verifica la regla adr-002-no-bypass-ports).
 */
export class CreateOrderUseCase {
  constructor(
    private readonly orders: OrderRepository,
    private readonly ids: IdGenerator,
    private readonly clock: Clock,
  ) {}

  async execute(command: CreateOrderCommand): Promise<Order> {
    const draft: NewOrder = {
      id: this.ids.next(),
      customerId: command.customerId,
      lines: command.lines,
      createdAt: this.clock.nowIso(),
    };

    const order = createOrder(draft);
    await this.orders.save(order);
    return order;
  }
}
