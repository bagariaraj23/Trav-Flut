import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined
}

const prismaClient = globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
  });

// Test the connection on startup
prismaClient.$connect()
  .then(() => {
    console.log('Successfully connected to the database');
  })
  .catch((e) => {
    console.error('Failed to connect to the database:', e);
    process.exit(1);
  });

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prismaClient;

export const prisma = prismaClient;