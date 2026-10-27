import { describe, expect, it } from 'vitest';
import { InvalidOrderError } from '../src/domain/errors.js';
import { createOrder, totalOf } from '../src/domain/order.js';

// El dominio se testea sin servidor, sin red y sin cluster. Eso ES el ADR-001.
const lines = [
  { sku: 'SKU-001', quantity: 2, unitPriceCents: 1500 },
  { sku: 'SKU-002', quantity: 1, unitPriceCents: 999 },
];

const base = {
  id: 'ord_1',
  customerId: 'cust_42',
  lines,
  createdAt: '2026-01-01T00:00:00.000Z',
};

describe('createOrder', () => {
  it('calcula el total a partir de las lineas', () => {
    const order = createOrder(base);
    expect(order.totalCents).toBe(2 * 1500 + 999);
  });

  it('es puro: dos llamadas con la misma entrada dan el mismo resultado', () => {
    expect(createOrder(base)).toEqual(createOrder(base));
  });

  it('rechaza pedidos sin cliente', () => {
    expect(() => createOrder({ ...base, customerId: '  ' })).toThrow(InvalidOrderError);
  });

  it('rechaza pedidos sin lineas', () => {
    expect(() => createOrder({ ...base, lines: [] })).toThrow(/al menos una linea/);
  });

  it('rechaza skus con formato invalido', () => {
    expect(() =>
      createOrder({ ...base, lines: [{ sku: 'sku minuscula', quantity: 1, unitPriceCents: 10 }] }),
    ).toThrow(/sku invalido/);
  });

  it('rechaza cantidades no positivas o fraccionarias', () => {
    expect(() =>
      createOrder({ ...base, lines: [{ sku: 'SKU-001', quantity: 0, unitPriceCents: 10 }] }),
    ).toThrow(/cantidad invalida/);
    expect(() =>
      createOrder({ ...base, lines: [{ sku: 'SKU-001', quantity: 1.5, unitPriceCents: 10 }] }),
    ).toThrow(/cantidad invalida/);
  });

  it('rechaza precios negativos', () => {
    expect(() =>
      createOrder({ ...base, lines: [{ sku: 'SKU-001', quantity: 1, unitPriceCents: -1 }] }),
    ).toThrow(/precio invalido/);
  });
});

describe('totalOf', () => {
  it('devuelve 0 para una lista vacia', () => {
    expect(totalOf([])).toBe(0);
  });
});
