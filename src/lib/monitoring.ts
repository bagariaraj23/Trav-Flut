import { prisma } from "./prisma";

// Performance monitoring and logging
export class PerformanceMonitor {
  private static instance: PerformanceMonitor;
  private metrics: Map<string, number[]> = new Map();

  static getInstance(): PerformanceMonitor {
    if (!PerformanceMonitor.instance) {
      PerformanceMonitor.instance = new PerformanceMonitor();
    }
    return PerformanceMonitor.instance;
  }

  startTimer(operation: string): () => void {
    const start = Date.now();

    return () => {
      const duration = Date.now() - start;
      this.recordMetric(operation, duration);
    };
  }

  recordMetric(operation: string, duration: number): void {
    if (!this.metrics.has(operation)) {
      this.metrics.set(operation, []);
    }

    const operationMetrics = this.metrics.get(operation)!;
    operationMetrics.push(duration);

    // Keep only last 100 measurements
    if (operationMetrics.length > 100) {
      operationMetrics.shift();
    }

    // Log slow operations
    if (duration > 1000) {
      // 1 second
      console.warn(`Slow operation detected: ${operation} took ${duration}ms`);
    }
  }

  getMetrics(operation: string): {
    avg: number;
    min: number;
    max: number;
    count: number;
  } | null {
    const metrics = this.metrics.get(operation);
    if (!metrics || metrics.length === 0) return null;

    return {
      avg: metrics.reduce((a, b) => a + b, 0) / metrics.length,
      min: Math.min(...metrics),
      max: Math.max(...metrics),
      count: metrics.length,
    };
  }

  getAllMetrics(): Record<string, any> {
    const result: Record<string, any> = {};

    // Use Array.from to ensure compatibility with older targets
    for (const entry of Array.from(this.metrics.entries())) {
      const operation = entry[0];
      result[operation] = this.getMetrics(operation);
    }

    return result;
  }
}

// Error tracking and reporting
export class ErrorTracker {
  private static instance: ErrorTracker;
  private errors: Array<{
    timestamp: Date;
    error: Error;
    context: Record<string, any>;
    userId?: string;
  }> = [];

  static getInstance(): ErrorTracker {
    if (!ErrorTracker.instance) {
      ErrorTracker.instance = new ErrorTracker();
    }
    return ErrorTracker.instance;
  }

  trackError(
    error: Error,
    context: Record<string, any> = {},
    userId?: string
  ): void {
    this.errors.push({
      timestamp: new Date(),
      error,
      context,
      userId,
    });

    // Keep only last 1000 errors
    if (this.errors.length > 1000) {
      this.errors.shift();
    }

    // Log critical errors immediately
    if (this.isCriticalError(error)) {
      console.error("CRITICAL ERROR:", {
        message: error.message,
        stack: error.stack,
        context,
        userId,
      });
    }
  }

  private isCriticalError(error: Error): boolean {
    const criticalPatterns = [
      /database/i,
      /connection/i,
      /timeout/i,
      /memory/i,
      /security/i,
    ];

    return criticalPatterns.some(
      (pattern) => pattern.test(error.message) || pattern.test(error.name)
    );
  }

  getErrorStats(): {
    totalErrors: number;
    criticalErrors: number;
    recentErrors: number;
    topErrors: Array<{ message: string; count: number }>;
  } {
    const now = new Date();
    const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);

    const recentErrors = this.errors.filter((e) => e.timestamp > oneHourAgo);
    const criticalErrors = this.errors.filter((e) =>
      this.isCriticalError(e.error)
    );

    // Count error types
    const errorCounts = new Map<string, number>();
    this.errors.forEach((e) => {
      const key = e.error.message;
      errorCounts.set(key, (errorCounts.get(key) || 0) + 1);
    });

    const topErrors = Array.from(errorCounts.entries())
      .sort(([, a], [, b]) => b - a)
      .slice(0, 10)
      .map(([message, count]) => ({ message, count }));

    return {
      totalErrors: this.errors.length,
      criticalErrors: criticalErrors.length,
      recentErrors: recentErrors.length,
      topErrors,
    };
  }
}

// Health check utilities
export async function checkDatabaseHealth(): Promise<{
  healthy: boolean;
  latency?: number;
  error?: string;
}> {
  try {
    const start = Date.now();
    await prisma.$queryRaw`SELECT 1`;
    const latency = Date.now() - start;

    return { healthy: true, latency };
  } catch (error) {
    return {
      healthy: false,
      error: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

export async function checkExternalServices(): Promise<
  Record<string, { healthy: boolean; latency?: number; error?: string }>
> {
  const services: Record<string, string> = {
    // Add external service URLs here
    // 'cloudinary': 'https://api.cloudinary.com/v1_1/health',
    // 'maps': 'https://maps.googleapis.com/maps/api/js'
  };

  const results: Record<string, any> = {};

  for (const [name, url] of Object.entries(services)) {
    try {
      const start = Date.now();
      const response = await fetch(url, {
        method: "HEAD",
        signal: AbortSignal.timeout(5000), // 5 second timeout
      });
      const latency = Date.now() - start;

      results[name] = {
        healthy: response.ok,
        latency,
      };
    } catch (error) {
      results[name] = {
        healthy: false,
        error: error instanceof Error ? error.message : "Unknown error",
      };
    }
  }

  return results;
}

// System metrics
export function getSystemMetrics(): {
  memory: NodeJS.MemoryUsage;
  uptime: number;
  timestamp: Date;
} {
  return {
    memory: process.memoryUsage(),
    uptime: process.uptime(),
    timestamp: new Date(),
  };
}
