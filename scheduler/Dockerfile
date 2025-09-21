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
RUN npx prisma generate

# Build TypeScript
RUN npm run build

# Start the scheduler
CMD ["npm", "start"]