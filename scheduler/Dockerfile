FROM node:20-alpine

# Install native dependencies needed by Prisma
RUN apk add --no-cache libc6-compat openssl

WORKDIR /app

COPY prisma ./prisma
COPY scheduler/package.json scheduler/package-lock.json ./scheduler/

WORKDIR /app/scheduler
# Ignore scripts to prevent prisma generate from running before source code is copied
RUN npm ci --ignore-scripts

COPY scheduler/ ./

# Generate Prisma client, build typescript, and prune dev dependencies
RUN npx prisma generate --schema=../prisma/schema.prisma \
  && npm run build \
  && npm prune --omit=dev

ENV NODE_ENV=production

CMD ["node", "dist/index.js"]
