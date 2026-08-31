# syntax=docker/dockerfile:1

FROM node:24.14.1-bookworm-slim AS base
WORKDIR /app
RUN corepack enable pnpm

FROM base AS deps
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile

FROM base AS build
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm build

FROM node:24.14.1-bookworm-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8000

RUN groupadd --system --gid 1001 nodejs && \
    useradd --system --uid 1001 --gid nodejs appuser

COPY --from=deps --chown=appuser:nodejs /app/node_modules ./node_modules
COPY --from=build --chown=appuser:nodejs /app/dist ./dist
COPY --from=build --chown=appuser:nodejs /app/package.json ./

USER appuser
EXPOSE 8000
CMD ["node", "dist/index.js"]
