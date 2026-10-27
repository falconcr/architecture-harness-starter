/**
 * Fitness functions de arquitectura: convierten los ADRs en gates deterministas.
 *
 * Cada regla cita el ADR que verifica. Si un agente (o una persona) viola la
 * arquitectura, esto falla en la laptop y en CI con el mismo mensaje, sin
 * depender del criterio de nadie.
 *
 * Comando: npm run arch:check
 */
export default {
  forbidden: [
    {
      // ADR-001: el dominio es puro.
      name: 'adr-001-domain-is-pure',
      comment:
        'ADR-001: src/domain no puede depender de infraestructura ni de HTTP. ' +
        'El dominio declara puertos; los adaptadores viven en src/infrastructure. ' +
        'Ver docs/adr/001-domain-pure.md',
      severity: 'error',
      from: { path: '^src/domain' },
      to: { path: '^src/(infrastructure|http)' },
    },
    {
      // ADR-001 (segunda mitad): tampoco dependencias externas de IO en el dominio.
      name: 'adr-001-domain-no-external-io',
      comment:
        'ADR-001: el dominio no puede importar librerias de IO, red, framework web ni ' +
        'clientes de base de datos. Si lo necesita, se declara como puerto. ' +
        'Ver docs/adr/001-domain-pure.md',
      severity: 'error',
      from: { path: '^src/domain' },
      to: {
        dependencyTypes: ['npm', 'npm-dev', 'npm-optional', 'npm-peer', 'core'],
        pathNot: '^(node:assert|assert)$',
      },
    },
    {
      // ADR-002: puertos y adaptadores.
      name: 'adr-002-ports-and-adapters',
      comment:
        'ADR-002: la capa de aplicacion solo conoce los puertos de src/domain. ' +
        'Importar un adaptador concreto de src/infrastructure saltea el puerto. ' +
        'La unica excepcion es el composition root (src/http/server.ts). ' +
        'Ver docs/adr/002-ports-adapters.md',
      severity: 'error',
      from: { path: '^src/application' },
      to: { path: '^src/(infrastructure|http)' },
    },
    {
      // ADR-002: la infraestructura implementa puertos, no llama a la aplicacion.
      name: 'adr-002-adapters-do-not-call-use-cases',
      comment:
        'ADR-002: un adaptador no orquesta casos de uso; el flujo va http -> application -> domain. ' +
        'Ver docs/adr/002-ports-adapters.md',
      severity: 'error',
      from: { path: '^src/infrastructure' },
      to: { path: '^src/(application|http)' },
    },
    {
      name: 'no-circular',
      comment: 'Las dependencias circulares hacen imposible razonar sobre las capas.',
      severity: 'error',
      from: {},
      to: { circular: true },
    },
    {
      name: 'no-orphans',
      comment: 'Modulo sin usar: o se usa, o se borra.',
      severity: 'warn',
      from: { orphan: true, pathNot: '^src/http/index\\.ts$' },
      to: {},
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    tsPreCompilationDeps: true,
    tsConfig: { fileName: 'tsconfig.json' },
    enhancedResolveOptions: {
      exportsFields: ['exports'],
      conditionNames: ['import', 'node', 'default'],
      extensions: ['.ts', '.js'],
    },
    reporterOptions: {
      text: { highlightFocused: true },
    },
  },
};
