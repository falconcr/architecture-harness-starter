# ADR-002: Todo acceso externo pasa por un puerto y su adaptador

- **Estado:** aceptado
- **Fecha:** 2026-10-27
- **Decisores:** equipo de plataforma
- **Etiquetas:** arquitectura, verificable-en-ci

## Contexto y planteamiento del problema

[ADR-001](001-domain-pure.md) protege el dominio, pero no dice nada de la capa de aplicación.
Sin una regla explícita, los casos de uso terminan importando `InMemoryOrderRepository`,
`fetch`, el SDK del proveedor de pagos o el logger concreto. El resultado es el mismo que
queríamos evitar: para testear "crear pedido" hay que levantar el mundo.

Con agentes en el ciclo el problema se amplifica: el agente ve que
`new InMemoryOrderRepository()` compila y lo usa dentro del caso de uso. No está siendo
descuidado, está siendo literal.

## Decisión

**Todo acceso al exterior del proceso se declara como puerto en `src/domain` y se implementa como
adaptador en `src/infrastructure`.**

1. Un **puerto** es una `interface` en `src/domain` (`OrderRepository`, `Clock`, `IdGenerator`).
2. Un **adaptador** es una clase en `src/infrastructure` que implementa ese puerto
   (`InMemoryOrderRepository`, `SystemClock`, `RandomIdGenerator`).
3. `src/application` solo conoce puertos y los recibe por constructor. Nunca importa de
   `src/infrastructure` ni de `src/http`.
4. `src/infrastructure` implementa puertos; no orquesta casos de uso. El flujo es siempre
   `http → application → domain`, nunca al revés.
5. Hay **un único composition root**, `src/http/server.ts`: el único lugar del repo donde se elige
   una implementación concreta.

```
            ┌───────────── src/http ─────────────┐   adaptador de entrada
            │  routes.ts   server.ts (composition root)
            └───────┬────────────────────────────┘
                    │ usa casos de uso
            ┌───────▼──── src/application ───────┐
            │  CreateOrderUseCase, ListOrders…   │  solo conoce puertos
            └───────┬────────────────────────────┘
                    │ usa puertos (interfaces)
            ┌───────▼──── src/domain ────────────┐
            │  Order  OrderRepository  Clock     │  puro (ADR-001)
            └───────▲────────────────────────────┘
                    │ implementa
            ┌───────┴──── src/infrastructure ────┐   adaptadores de salida
            │  InMemoryOrderRepository, metrics  │
            └────────────────────────────────────┘
```

## Consecuencias

**Bien:**
- Los casos de uso se testean con dobles de los puertos (ver `test/create-order.test.ts`): sin
  base de datos y sin mocks del framework.
- Reemplazar memoria por Postgres es escribir una clase nueva y cambiar una línea del
  composition root.
- El límite es explícito, así que se puede verificar con una herramienta en vez de con una opinión.

**Costo aceptado:**
- Indirección: para seguir una llamada hay que saltar del puerto al adaptador.
- Para un CRUD de un solo endpoint es sobre-ingeniería. Lo asumimos porque el repo existe para
  mostrar cómo se verifica un límite, y porque el servicio real va a crecer.

## Verificación

Reglas **`adr-002-ports-and-adapters`** y **`adr-002-adapters-do-not-call-use-cases`** en
[`.dependency-cruiser.js`](../../.dependency-cruiser.js), `severity: error`.

```bash
npm run arch:check
```

Verificación complementaria, humana pero acotada: el subagente
[`architect-reviewer`](../../.claude/agents/architect-reviewer.md) revisa cada PR y marca el caso
que la herramienta no ve, por ejemplo un puerto nuevo declarado en `src/infrastructure` en lugar
de `src/domain`. **Comenta; no aprueba.**

| Dónde | Cómo |
|---|---|
| Laptop | `npm run arch:check` |
| CI | job `arch-check` (determinista) + job `ai-review` (asistido, no bloqueante) |
| Grafo visual | `npm run arch:graph \| dot -T svg > arch.svg` |
