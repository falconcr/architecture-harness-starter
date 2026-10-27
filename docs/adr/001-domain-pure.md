# ADR-001: El dominio es puro

- **Estado:** aceptado
- **Fecha:** 2026-10-27
- **Decisores:** equipo de plataforma
- **Etiquetas:** arquitectura, verificable-en-ci

## Contexto y planteamiento del problema

El servicio `orders` va a ser modificado con frecuencia por personas **y por agentes de IA**.
Un agente optimiza para "que el test pase" o "que el endpoint responda", no para preservar la
forma del sistema. El atajo más barato y más común es importar el cliente de base de datos (o el
objeto `request` de HTTP) directo desde la lógica de negocio: funciona, pasa los tests, y a los
seis meses el dominio no se puede testear ni cambiar sin levantar media infraestructura.

Necesitamos una regla que no dependa de que alguien se acuerde de revisarla en code review.

## Decisión

**`src/domain` no depende de nada que no sea `src/domain`.**

Concretamente:

1. Ningún módulo de `src/domain` importa de `src/infrastructure` ni de `src/http`.
2. Ningún módulo de `src/domain` importa paquetes de npm ni módulos `node:*` (ni `fastify`, ni
   `prom-client`, ni un cliente de base de datos, ni `fs`). La única excepción permitida es
   `node:assert`.
3. Lo que el dominio necesita del mundo exterior se declara como **puerto** (una `interface` en
   `src/domain`) e lo implementa un adaptador en `src/infrastructure` (ver [ADR-002](002-ports-adapters.md)).
4. Esto incluye lo que parece inocente pero es infraestructura disfrazada: `Date.now()`,
   `crypto.randomUUID()`, `process.env`. Por eso existen los puertos `Clock` e `IdGenerator`.

## Consecuencias

**Bien:**
- El dominio se testea en milisegundos, sin red, sin base de datos y sin cluster
  (ver `test/order.test.ts`).
- Cambiar de almacenamiento no toca una línea de lógica de negocio.
- Un agente que tome el atajo fácil **falla en segundos**, con un mensaje que nombra el ADR.

**Costo aceptado:**
- Hay que escribir el puerto y el adaptador: más archivos para un caso trivial.
- Pasar `Clock` e `IdGenerator` por constructor se siente ceremonioso hasta la primera vez que
  tenés que testear un vencimiento.

## Verificación

Regla **`adr-001-domain-is-pure`** (y su complemento `adr-001-domain-no-external-io`) en
[`.dependency-cruiser.js`](../../.dependency-cruiser.js), `severity: error`.

```bash
npm run arch:check
```

Salida esperada cuando se viola (es exactamente lo que se ve en el Acto 1 de la demo):

```
  error adr-001-domain-is-pure: src/domain/order.ts → src/infrastructure/db.ts

x 1 dependency violations (1 errors, 0 warnings). 15 modules, 27 dependencies cruised.
```

Corre en tres lugares, siempre con el mismo resultado:

| Dónde | Cómo |
|---|---|
| Laptop | `npm run arch:check` |
| CI | job `arch-check` de [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) (gate determinista, bloqueante) |
| Agente | `CLAUDE.md` obliga a correr `npm run verify` antes de proponer un cambio |
