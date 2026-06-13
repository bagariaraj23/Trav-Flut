FROM node:20-alpine

# Install libc6-compat (required for Prisma query engines) and other utilities
RUN apk add --no-cache libc6-compat openssl bash postgresql-client

WORKDIR /app

# Copy lockfile, package.json, and prisma directory first for caching
COPY package.json package-lock.json ./
COPY prisma ./prisma

# Install dependencies
RUN npm ci

# Copy the rest of the application source code
COPY . .

# Generate Prisma Client
RUN npx prisma generate

# Build Next.js production build with placeholder env variables for build-time validation
ENV DATABASE_URL="postgresql://postgres:postgres@localhost:5432/placeholder"
ENV JWT_SECRET="placeholder"
ENV MAPBOX_ACCESS_TOKEN="placeholder"
RUN npm run build

# Make docker-entrypoint executable
RUN chmod +x ./scripts/docker-entrypoint.sh

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

EXPOSE 3000

# Use startup script to handle db readiness and migration before starting Next.js
ENTRYPOINT ["/bin/bash", "./scripts/docker-entrypoint.sh"]
