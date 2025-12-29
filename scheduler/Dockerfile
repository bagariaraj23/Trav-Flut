FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY scheduler/package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY scheduler/ .
COPY scheduler/tsconfig.json ./ 
COPY prisma/ ./prisma/

# Generate Prisma client
RUN npx prisma generate --schema=./prisma/schema.prisma

# Build TypeScript
RUN npm run build

# Verify build output exists
RUN ls -la dist/ || (echo "Build failed - dist directory not found" && exit 1)

# Start the scheduler
CMD ["npm", "start"]