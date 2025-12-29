/**
 * Next.js Instrumentation Hook
 * Runs on server startup to log comprehensive configuration and service status
 * 
 * This hook is called automatically by Next.js when the server starts.
 * It runs in both development and production modes.
 */

export async function register() {
  // Log that instrumentation hook is being called
  console.log('[Instrumentation] Register function called');
  console.log(`[Instrumentation] NEXT_RUNTIME: ${process.env.NEXT_RUNTIME || 'not set'}`);
  console.log(`[Instrumentation] NODE_ENV: ${process.env.NODE_ENV || 'not set'}`);
  
  // Only run startup logging in Node.js runtime, not in Edge runtime
  // Prisma and other Node.js-only libraries can't run in Edge runtime
  if (process.env.NEXT_RUNTIME === 'edge') {
    console.log('[Instrumentation] Skipping startup logging in Edge runtime');
    return;
  }
  
  try {
    // Import and run startup logger
    const { logStartupInfo } = await import('./lib/startup-logger');
    console.log('[Instrumentation] Starting comprehensive startup logging...');
    await logStartupInfo();
    console.log('[Instrumentation] Startup logging completed');
  } catch (error) {
    console.error('[Instrumentation] Error during startup logging:', error);
    // Don't throw - allow server to start even if logging fails
  }
}

