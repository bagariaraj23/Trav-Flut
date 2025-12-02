/**
 * Comprehensive startup logging utility for Scheduler Service
 * Logs all configuration, environment variables, and service connections
 */

import { PrismaClient } from "@prisma/client";

interface ServiceStatus {
  name: string;
  status: 'connected' | 'disconnected' | 'error' | 'not-configured';
  details?: string;
  error?: string;
}

/**
 * Masks sensitive values in environment variables
 */
function maskSensitiveValue(value: string | undefined): string {
  if (!value) return 'NOT SET';
  if (value.length <= 8) return '***';
  return value.substring(0, 4) + '***' + value.substring(value.length - 4);
}

/**
 * Masks URLs but keeps the structure visible
 */
function maskUrl(url: string | undefined): string {
  if (!url) return 'NOT SET';
  try {
    const urlObj = new URL(url);
    const protocol = urlObj.protocol;
    const hostname = urlObj.hostname;
    const pathname = urlObj.pathname;
    const username = urlObj.username ? maskSensitiveValue(urlObj.username) : '';
    const password = urlObj.password ? '***' : '';
    
    let masked = `${protocol}//`;
    if (username || password) {
      masked += `${username}${password ? ':' + password : ''}@`;
    }
    masked += hostname;
    if (urlObj.port) masked += `:${urlObj.port}`;
    masked += pathname;
    if (urlObj.search) masked += urlObj.search;
    return masked;
  } catch {
    return maskSensitiveValue(url);
  }
}

/**
 * Tests database connection
 */
async function testDatabaseConnection(prisma: PrismaClient): Promise<ServiceStatus> {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return {
      name: 'PostgreSQL Database',
      status: 'connected',
      details: 'Connection successful',
    };
  } catch (error) {
    return {
      name: 'PostgreSQL Database',
      status: 'error',
      error: error instanceof Error ? error.message : String(error),
    };
  }
}


/**
 * Collects all configuration information
 */
function collectConfigInfo(): Record<string, Record<string, string | number | boolean | null | undefined>> {
  const configs: Record<string, Record<string, string | number | boolean | null | undefined>> = {};

  // Server Configuration
  configs['Server Configuration'] = {
    NODE_ENV: process.env.NODE_ENV || 'NOT SET',
    PORT: process.env.PORT || 'NOT SET',
    'Working Directory': process.cwd(),
  };

  // Database Configuration
  configs['Database Configuration'] = {
    DATABASE_URL: maskUrl(process.env.DATABASE_URL),
    'Database Connected': 'Testing...',
  };

  // Scheduler Configuration
  configs['Scheduler Configuration'] = {
    'Execution Mode': 'Cron (single execution)',
    'Cron Schedule': process.env.CRON_SCHEDULE || '0 * * * * (every hour)',
    'Retry Attempts': 3,
    'Retry Strategy': 'Exponential backoff',
  };

  return configs;
}

/**
 * Logs startup information comprehensively
 */
export async function logSchedulerStartupInfo(
  prisma: PrismaClient
): Promise<void> {
  const separator = '='.repeat(80);
  const line = '-'.repeat(80);

  console.log('\n' + separator);
  console.log('TRIPTHREAD SCHEDULER - STARTUP LOG');
  console.log(separator + '\n');

  // System Information
  console.log('SYSTEM INFORMATION');
  console.log(line);
  console.log(`Node.js Version: ${process.version}`);
  console.log(`Platform: ${process.platform}`);
  console.log(`Architecture: ${process.arch}`);
  console.log(`Working Directory: ${process.cwd()}`);
  console.log(`Process ID: ${process.pid}`);
  console.log(`Uptime: ${Math.floor(process.uptime())}s\n`);

  // Configuration Information
  console.log('CONFIGURATION');
  console.log(line);
  const configs = collectConfigInfo();
  for (const [category, items] of Object.entries(configs)) {
    console.log(`\n${category}:`);
    for (const [key, value] of Object.entries(items)) {
      if (value === null || value === undefined) {
        console.log(`  ${key}: NOT SET`);
      } else {
        console.log(`  ${key}: ${value}`);
      }
    }
  }

  // Service Connections
  console.log('\n\nSERVICE CONNECTIONS');
  console.log(line);

  const services: ServiceStatus[] = [];

  // Test Database
  console.log('Testing database connection...');
  const dbStatus = await testDatabaseConnection(prisma);
  services.push(dbStatus);

  // Log service statuses
  console.log('\n');
  for (const service of services) {
    const statusIcon =
      service.status === 'connected'
        ? '√'
        : service.status === 'error'
        ? 'X'
        : service.status === 'not-configured'
        ? '!'
        : '?';
    console.log(`${statusIcon} ${service.name}: ${service.status.toUpperCase()}`);
    if (service.details) {
      console.log(`   ${service.details}`);
    }
    if (service.error) {
      console.log(`   Error: ${service.error}`);
    }
  }

  // Prisma Schema Check
  console.log('\n\nPRISMA SCHEMA STATUS');
  console.log(line);
  try {
    const prismaVersion = await prisma.$queryRaw<Array<{ version: string }>>`
      SELECT version()
    `;
    console.log(`Database Version: ${prismaVersion[0]?.version || 'Unknown'}`);
    
    // Check if we can query the Trip model (to detect schema mismatches)
    try {
      await prisma.trip.findFirst({ take: 1 });
      console.log('Prisma schema matches database');
    } catch (error: any) {
      if (error?.code === 'P2022' || error?.message?.includes('does not exist')) {
        console.log('Prisma schema mismatch detected!');
        console.log(`   Error: ${error.message}`);
        console.log('   Action: Run `npx prisma generate --schema=../prisma/schema.prisma`');
      } else {
        throw error;
      }
    }
  } catch (error) {
    console.log(`Failed to check Prisma schema: ${error instanceof Error ? error.message : String(error)}`);
  }

  // Execution Mode Information
  console.log('\n\nEXECUTION MODE');
  console.log(line);
  console.log('Mode: Cron-based (single execution per invocation)');
  console.log('No Redis dependency - runs independently');
  console.log('Retry Logic: 3 attempts with exponential backoff');
  console.log('Recommended Schedule: Every hour (0 * * * *)');

  // Environment Variable Summary
  console.log('\n\nENVIRONMENT VARIABLE SUMMARY');
  console.log(line);
  const allEnvVars = Object.keys(process.env).filter((key) =>
    key.includes('DATABASE') ||
    key.includes('NODE') ||
    key.includes('CRON')
  );
  console.log(`Total relevant environment variables: ${allEnvVars.length}`);
  const missingVars: string[] = [];
  const criticalVars = ['DATABASE_URL'];
  for (const varName of criticalVars) {
    if (!process.env[varName]) {
      missingVars.push(varName);
    }
  }
  if (missingVars.length > 0) {
    console.log(`Missing critical variables: ${missingVars.join(', ')}`);
  } else {
    console.log('All critical variables are set');
  }

  // Final Summary
  console.log('\n' + separator);
  const allConnected = services.every((s) => s.status === 'connected');
  if (allConnected) {
    console.log('STARTUP COMPLETE - All services ready');
  } else {
    console.log('STARTUP FAILED - Service connection errors detected');
    console.log('   Check the service connections above for details');
    throw new Error('Service connection failed');
  }
  console.log(separator + '\n');
}

