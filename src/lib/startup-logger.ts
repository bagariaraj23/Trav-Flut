/**
 * Comprehensive startup logging utility
 * Logs all configuration, environment variables, and service connections
 */

import { config } from '@/config/env';
import { prisma } from './prisma';
import { redis } from './redis';
import { ENV } from '@/env';

interface ServiceStatus {
  name: string;
  status: 'connected' | 'disconnected' | 'error' | 'not-configured';
  details?: string;
  error?: string;
}

interface ConfigInfo {
  category: string;
  items: Record<string, string | number | boolean | string[] | null | undefined>;
}

/**
 * Masks sensitive values in environment variables
 */
function maskSensitiveValue(value: string | undefined): string {
  if (!value) return 'NOT SET';
  if (value.length <= 8) return '*****';
  return value.substring(0, 4) + '****' + value.substring(value.length - 4);
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
    const password = urlObj.password ? '*****' : '';
    
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
async function testDatabaseConnection(): Promise<ServiceStatus> {
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
 * Tests Redis connection
 */
async function testRedisConnection(): Promise<ServiceStatus> {
  if (!redis) {
    return {
      name: 'Redis Cache',
      status: 'not-configured',
      details: 'REDIS_REST_URL or REDIS_REST_TOKEN not set',
    };
  }

  try {
    await redis.ping();
    return {
      name: 'Redis Cache',
      status: 'connected',
      details: 'Upstash Redis REST API connection successful',
    };
  } catch (error) {
    return {
      name: 'Redis Cache',
      status: 'error',
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Checks Cloudinary configuration
 */
function checkCloudinaryConfig(): ServiceStatus {
  const cloudName = process.env.CLOUDINARY_CLOUD_NAME;
  const apiKey = process.env.CLOUDINARY_API_KEY;
  const apiSecret = process.env.CLOUDINARY_API_SECRET;

  if (!cloudName || !apiKey || !apiSecret) {
    return {
      name: 'Cloudinary',
      status: 'not-configured',
      details: 'Missing required environment variables',
    };
  }

  if (
    cloudName.startsWith('your_') ||
    apiKey.startsWith('your_') ||
    apiSecret.startsWith('your_')
  ) {
    return {
      name: 'Cloudinary',
      status: 'not-configured',
      details: 'Placeholder values detected',
    };
  }

  return {
    name: 'Cloudinary',
    status: 'connected',
    details: `Cloud: ${cloudName}, API Key: ${maskSensitiveValue(apiKey)}`,
  };
}

/**
 * Collects all configuration information
 */
function collectConfigInfo(): ConfigInfo[] {
  const configs: ConfigInfo[] = [];

  // Server Configuration
  configs.push({
    category: 'Server Configuration',
    items: {
      NODE_ENV: process.env.NODE_ENV || 'NOT SET',
      PORT: process.env.PORT || 'NOT SET',
      API_BASE_URL: config.apiBaseUrl,
      NEXT_PUBLIC_API_BASE_URL: config.publicApiBaseUrl,
      APP_NAME: process.env.APP_NAME || 'NOT SET',
      APP_SCHEME: config.appScheme,
      APP_RESET_WEB_URL: config.appResetWebUrl,
    },
  });

  // Database Configuration
  configs.push({
    category: 'Database Configuration',
    items: {
      DATABASE_URL: maskUrl(process.env.DATABASE_URL),
      'Database Connected': 'Testing...',
    },
  });

  // Authentication Configuration
  configs.push({
    category: 'Authentication Configuration',
    items: {
      JWT_SECRET: maskSensitiveValue(process.env.JWT_SECRET),
      JWT_REFRESH_SECRET: maskSensitiveValue(process.env.JWT_REFRESH_SECRET),
      NEXTAUTH_SECRET: maskSensitiveValue(process.env.NEXTAUTH_SECRET),
      NEXTAUTH_URL: process.env.NEXTAUTH_URL || 'NOT SET',
    },
  });

  // Redis Configuration
  configs.push({
    category: 'Redis Configuration',
    items: {
      REDIS_REST_URL: maskSensitiveValue(process.env.REDIS_REST_URL),
      REDIS_REST_TOKEN: maskSensitiveValue(process.env.REDIS_REST_TOKEN),
      REDIS_URL: maskUrl(process.env.REDIS_URL),
    },
  });

  // Cloudinary Configuration
  configs.push({
    category: 'Cloudinary Configuration',
    items: {
      CLOUDINARY_CLOUD_NAME: process.env.CLOUDINARY_CLOUD_NAME || 'NOT SET',
      CLOUDINARY_API_KEY: maskSensitiveValue(process.env.CLOUDINARY_API_KEY),
      CLOUDINARY_API_SECRET: maskSensitiveValue(process.env.CLOUDINARY_API_SECRET),
      CLOUDINARY_UPLOAD_FOLDER: process.env.CLOUDINARY_UPLOAD_FOLDER || 'NOT SET',
    },
  });

  // Email Configuration
  configs.push({
    category: 'Email Configuration',
    items: {
      SENDGRID_API_KEY: maskSensitiveValue(process.env.SENDGRID_API_KEY),
      SENDGRID_DEBUG: process.env.SENDGRID_DEBUG || 'NOT SET',
      MAIL_FROM: process.env.MAIL_FROM || process.env.FROM_EMAIL || 'NOT SET',
    },
  });

  // CORS Configuration
  configs.push({
    category: 'CORS Configuration',
    items: {
      ALLOWED_ORIGINS: config.allowedOrigins,
    },
  });

  // Security Configuration
  configs.push({
    category: 'Security Configuration',
    items: {
      PASSWORD_RESET_TTL_MINUTES: config.passwordResetTtlMinutes,
      RESET_RETENTION_DAYS: process.env.RESET_RETENTION_DAYS || 'NOT SET',
      RESET_TOKEN_TTL_MIN: process.env.RESET_TOKEN_TTL_MIN || 'NOT SET',
      PASSWORD_RESET_DEBUG_ECHO: process.env.PASSWORD_RESET_DEBUG_ECHO || 'NOT SET',
    },
  });

  // Media Configuration
  configs.push({
    category: 'Media Configuration',
    items: {
      MEDIA_TOTAL_STORAGE_LIMIT_BYTES: process.env.MEDIA_TOTAL_STORAGE_LIMIT_BYTES || 'NOT SET',
      MEDIA_PER_TRIP_LIMIT: process.env.MEDIA_PER_TRIP_LIMIT || 'NOT SET',
      MEDIA_DAILY_UPLOAD_LIMIT: process.env.MEDIA_DAILY_UPLOAD_LIMIT || 'NOT SET',
    },
  });

  // Map Configuration
  configs.push({
    category: 'Map Configuration',
    items: {
      MAPBOX_ACCESS_TOKEN: maskSensitiveValue(process.env.MAPBOX_ACCESS_TOKEN),
    },
  });

  // OAuth Configuration
  configs.push({
    category: 'OAuth Configuration',
    items: {
      GOOGLE_CLIENT_ID: maskSensitiveValue(process.env.GOOGLE_CLIENT_ID),
      GOOGLE_CLIENT_SECRET: maskSensitiveValue(process.env.GOOGLE_CLIENT_SECRET),
    },
  });

  // Feature Flags
  configs.push({
    category: 'Feature Flags',
    items: {
      ENABLE_SCHEDULER: process.env.ENABLE_SCHEDULER || 'NOT SET',
    },
  });

  return configs;
}

/**
 * Logs startup information comprehensively
 */
export async function logStartupInfo(): Promise<void> {
  const separator = '='.repeat(80);
  const line = '-'.repeat(80);

  console.log('\n' + separator);
  console.log('TRIPTHREAD BACKEND - STARTUP LOG');
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
  for (const configInfo of configs) {
    console.log(`\n${configInfo.category}:`);
    for (const [key, value] of Object.entries(configInfo.items)) {
      if (value === null || value === undefined) {
        console.log(`  ${key}: NOT SET`);
      } else if (Array.isArray(value)) {
        console.log(`  ${key}: [${value.join(', ')}]`);
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
  const dbStatus = await testDatabaseConnection();
  services.push(dbStatus);

  // Test Redis
  console.log('Testing Redis connection...');
  const redisStatus = await testRedisConnection();
  services.push(redisStatus);

  // Check Cloudinary
  const cloudinaryStatus = checkCloudinaryConfig();
  services.push(cloudinaryStatus);

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

  // Environment Variable Summary
  console.log('\n\nENVIRONMENT VARIABLE SUMMARY');
  console.log(line);
  const allEnvVars = Object.keys(process.env).filter((key) =>
    key.startsWith('NEXT_PUBLIC_') ||
    key.includes('DATABASE') ||
    key.includes('REDIS') ||
    key.includes('JWT') ||
    key.includes('CLOUDINARY') ||
    key.includes('SENDGRID') ||
    key.includes('MAPBOX') ||
    key.includes('GOOGLE') ||
    key.includes('API') ||
    key.includes('APP_')
  );
  console.log(`Total relevant environment variables: ${allEnvVars.length}`);
  const missingVars: string[] = [];
  const criticalVars = [
    'DATABASE_URL',
    'JWT_SECRET',
    'JWT_REFRESH_SECRET',
    'NEXTAUTH_SECRET',
    'NEXTAUTH_URL',
  ];
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

  // Prisma Schema Check
  console.log('\n\nPRISMA SCHEMA STATUS');
  console.log(line);
  try {
    const prismaVersion = await prisma.$queryRaw<Array<{ version: string }>>`
      SELECT version()
    `;
    console.log(`Database Version: ${prismaVersion[0]?.version || 'Unknown'}`);
    
    // Check if we can query the User model (to detect schema mismatches)
    try {
      await prisma.user.findFirst({ 
        take: 1,
        select: { id: true, email: true } // Only select fields that should exist
      });
      console.log('Prisma schema matches database');
    } catch (error: any) {
      if (error?.code === 'P2022' || error?.message?.includes('does not exist')) {
        console.log('Prisma schema mismatch detected!');
        console.log(`   Error Code: ${error?.code || 'Unknown'}`);
        console.log(`   Error Message: ${error?.message || String(error)}`);
        if (error?.meta) {
          console.log(`   Model: ${error.meta.modelName || 'Unknown'}`);
          console.log(`   Column: ${error.meta.column || 'Unknown'}`);
        }
        console.log('   Action Required:');
        console.log('   1. Run `npx prisma generate` to regenerate Prisma Client');
        console.log('   2. Run `npx prisma db push` to sync schema, OR');
        console.log('   3. Run `npx prisma migrate deploy` to apply pending migrations');
        console.log('   4. Restart the application');
      } else {
        throw error;
      }
    }
  } catch (error) {
    console.log(`Failed to check Prisma schema: ${error instanceof Error ? error.message : String(error)}`);
    if (error instanceof Error && error.stack) {
      console.log(`   Stack: ${error.stack.split('\n').slice(0, 3).join('\n')}`);
    }
  }

  // Final Summary
  console.log('\n' + separator);
  const allConnected = services.every(
    (s) => s.status === 'connected' || s.status === 'not-configured'
  );
  if (allConnected) {
    console.log('STARTUP COMPLETE - All services ready');
  } else {
    console.log('STARTUP COMPLETE - Some services have issues');
    console.log('Check the service connections above for details');
  }
  console.log(separator + '\n');
}

