# Build from repository root (parent of scheduler/):
#   docker build -f scheduler/Dockerfile .
#
# Requires DATABASE_URL (or direct env used by scheduler) at runtime, e.g.:
#   docker run --env-file .env tripthread-scheduler

FROM node:20-alpine

WORKDIR /app

COPY prisma ./prisma
COPY scheduler/package.json scheduler/package-lock.json ./scheduler/

WORKDIR /app/scheduler
RUN npm ci

COPY scheduler/ ./

RUN npx prisma generate --schema=../prisma/schema.prisma \
  && npm run build \
  && npm prune --omit=dev

ENV NODE_ENV=production

CMD ["node", "dist/index.js"]
