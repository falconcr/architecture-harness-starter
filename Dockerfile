# Imagen del servicio orders.
#
# Decisiones que importan para el harness:
#  - multi-stage: la imagen final no tiene npm, ni toolchain, ni codigo fuente.
#  - distroless nonroot (uid 65532): sin shell. Un atacante (o un agente confundido)
#    no tiene donde pararse. Coincide con el securityContext del Rollout.
#  - sin secretos en build args: si esto necesitara un token, estariamos violando ADR-003.

# ---------- build ----------
FROM node:22.12.0-bookworm-slim AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# Dependencias de produccion unicamente.
RUN npm ci --omit=dev

# ---------- runtime ----------
FROM gcr.io/distroless/nodejs22-debian12:nonroot AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0 \
    FAULT_RATE=0

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/package.json ./package.json

USER 65532:65532
EXPOSE 3000

CMD ["dist/http/index.js"]
