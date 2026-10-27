import { loadConfig } from '../infrastructure/config.js';
import { buildServer } from './server.js';

const config = loadConfig();
const app = await buildServer(config);

if (config.faultRate > 0) {
  app.log.warn(
    { faultRate: config.faultRate },
    'FAULT_RATE > 0: esta instancia devuelve errores a proposito (demo del canary)',
  );
}

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    app.log.info({ signal }, 'cerrando');
    void app.close().then(() => process.exit(0));
  });
}

await app.listen({ port: config.port, host: config.host });
