import { beforeEach, describe, expect, it } from 'vitest';
import { CreateOrderUseCase } from '../src/application/create-order.js';
import { ListOrdersUseCase } from '../src/application/list-orders.js';
import type { Clock, IdGenerator, OrderRepository } from '../src/domain/order-repository.js';
import type { Order } from '../src/domain/order.js';

// Los casos de uso se testean con dobles de los PUERTOS, no con la infraestructura real.
// Si esto necesitara una base de datos para correr, el ADR-002 estaria roto.
class FakeRepository implements OrderRepository {
  readonly saved: Order[] = [];
  async save(order: Order): Promise<void> {
    this.saved.push(order);
  }
  async findById(id: string): Promise<Order | undefined> {
    return this.saved.find((order) => order.id === id);
  }
  async list(limit: number): Promise<readonly Order[]> {
    return this.saved.slice(-limit).reverse();
  }
}

const fixedClock: Clock = { nowIso: () => '2026-01-01T00:00:00.000Z' };

class SequentialIds implements IdGenerator {
  private n = 0;
  next(): string {
    this.n += 1;
    return `ord_${this.n}`;
  }
}

describe('CreateOrderUseCase', () => {
  let repository: FakeRepository;
  let useCase: CreateOrderUseCase;

  beforeEach(() => {
    repository = new FakeRepository();
    useCase = new CreateOrderUseCase(repository, new SequentialIds(), fixedClock);
  });

  it('persiste el pedido a traves del puerto', async () => {
    const order = await useCase.execute({
      customerId: 'cust_1',
      lines: [{ sku: 'SKU-001', quantity: 3, unitPriceCents: 1000 }],
    });

    expect(order.id).toBe('ord_1');
    expect(order.createdAt).toBe('2026-01-01T00:00:00.000Z');
    expect(order.totalCents).toBe(3000);
    expect(repository.saved).toHaveLength(1);
  });

  it('no guarda nada si el dominio rechaza el pedido', async () => {
    await expect(useCase.execute({ customerId: '', lines: [] })).rejects.toThrow();
    expect(repository.saved).toHaveLength(0);
  });
});

describe('ListOrdersUseCase', () => {
  it('acota el limite al rango permitido', async () => {
    const repository = new FakeRepository();
    const create = new CreateOrderUseCase(repository, new SequentialIds(), fixedClock);
    for (let i = 0; i < 3; i += 1) {
      await create.execute({
        customerId: 'cust_1',
        lines: [{ sku: 'SKU-001', quantity: 1, unitPriceCents: 100 }],
      });
    }

    const list = new ListOrdersUseCase(repository);
    expect(await list.execute(-5)).toHaveLength(1);
    expect(await list.execute(9999)).toHaveLength(3);
  });
});
