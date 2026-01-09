import { cacheGetJson, cacheSetJson } from "@/lib/cache";
import { redis, memoryCache } from "@/lib/redis";
import { NextRequest, NextResponse } from "next/server";
import { ApiResponse } from "@/types/api";
import { RateLimitError } from "./errors";

/**
 * Rate limit configuration
 */
export interface RateLimitConfig {
  /** Maximum number of requests allowed */
  maxRequests: number;
  /** Time window in milliseconds */
  windowMs: number;
  /** Optional prefix for the rate limit key */
  keyPrefix?: string;
  /** Whether to log security events when rate limit is hit */
  logEvent?: boolean;
}

/**
 * Rate limit check result
 */
export interface RateLimitResult {
  /** Whether the request is allowed */
  allowed: boolean;
  /** Number of requests remaining in the current window */
  remaining: number;
  /** Timestamp when the rate limit window resets (in milliseconds) */
  resetAt: number;
  /** Current count of requests in the window */
  count: number;
}

/**
 * Predefined rate limit configurations for common use cases
 */
export const RATE_LIMIT_PRESETS: Record<string, RateLimitConfig> = {
  // Engagement actions
  comment: {
    maxRequests: 10,
    windowMs: 60 * 60 * 1000, // 1 hour
    keyPrefix: "rl:comment",
    logEvent: true,
  },
  share: {
    maxRequests: 100,
    windowMs: 24 * 60 * 60 * 1000, // 24 hours
    keyPrefix: "rl:share",
    logEvent: true,
  },
  like: {
    maxRequests: 200,
    windowMs: 60 * 60 * 1000, // 1 hour
    keyPrefix: "rl:like",
    logEvent: true,
  },
  // General API endpoints
  general: {
    maxRequests: 100,
    windowMs: 60 * 1000, // 1 minute
    keyPrefix: "rl:general",
    logEvent: false,
  },
  // Authentication endpoints
  auth: {
    maxRequests: 5,
    windowMs: 15 * 60 * 1000, // 15 minutes
    keyPrefix: "rl:auth",
    logEvent: true,
  },
  // Search endpoints
  search: {
    maxRequests: 30,
    windowMs: 60 * 1000, // 1 minute
    keyPrefix: "rl:search",
    logEvent: false,
  },
};

/**
 * Get a rate limit key for a user or IP address
 */
export function getRateLimitKey(
  config: RateLimitConfig,
  identifier: string,
  windowStart: number
): string {
  const prefix = config.keyPrefix || "rl:default";
  // Ensure windowStart is a valid number
  const validWindowStart = isNaN(windowStart) || windowStart <= 0 ? 0 : windowStart;
  const validWindowMs = config.windowMs && config.windowMs > 0 ? config.windowMs : 60000; // Default 1 minute
  const windowKey = Math.floor(validWindowStart / validWindowMs);
  return `${prefix}:${identifier}:${windowKey}`;
}

/**
 * Check rate limit for a given identifier (userId or IP)
 * Uses Redis if available, falls back to memory cache
 */
export async function checkRateLimit(
  config: RateLimitConfig,
  identifier: string
): Promise<RateLimitResult> {
  // Validate config
  if (!config || !config.windowMs || config.windowMs <= 0) {
    throw new Error(`Invalid rate limit config: windowMs must be > 0, got ${config?.windowMs}`);
  }
  if (!config.maxRequests || config.maxRequests <= 0) {
    throw new Error(`Invalid rate limit config: maxRequests must be > 0, got ${config?.maxRequests}`);
  }

  const now = Date.now();
  const windowStart = Math.floor(now / config.windowMs) * config.windowMs;
  const resetAt = windowStart + config.windowMs;
  const key = getRateLimitKey(config, identifier, windowStart);

  let count: number;

  if (redis) {
    // Use Redis for distributed rate limiting
    try {
      const result = await redis.incr(key);
      if (result === 1) {
        // First request in this window, set expiration
        await redis.pexpire(key, config.windowMs);
      }
      count = result;
    } catch (error) {
      // Fallback to memory cache if Redis fails
      console.warn("[RateLimit] Redis error, falling back to memory cache:", error);
      const cached = memoryCache.get<{ count: number; resetTime: number }>(key);
      if (cached && cached.resetTime > now) {
        count = cached.count + 1;
        memoryCache.set(key, { count, resetTime }, config.windowMs);
      } else {
        count = 1;
        memoryCache.set(key, { count, resetTime: resetAt }, config.windowMs);
      }
    }
  } else {
    // Use memory cache as fallback
    const cached = memoryCache.get<{ count: number; resetTime: number }>(key);
    if (cached && cached.resetTime > now) {
      count = cached.count + 1;
      memoryCache.set(key, { count, resetTime: cached.resetTime }, config.windowMs);
    } else {
      count = 1;
      memoryCache.set(key, { count, resetTime: resetAt }, config.windowMs);
    }
  }

  const remaining = Math.max(0, config.maxRequests - count);
  const allowed = count <= config.maxRequests;

  return { allowed, remaining, resetAt, count };
}

/**
 * Get identifier from request (userId if authenticated, otherwise IP)
 */
export function getRequestIdentifier(
  request: NextRequest,
  userId?: string
): string {
  if (userId) {
    return userId;
  }
  return (
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    request.headers.get("x-real-ip") ||
    "unknown"
  );
}

/**
 * Create rate limit response with proper headers
 */
export function createRateLimitResponse(
  config: RateLimitConfig,
  result: RateLimitResult
): NextResponse<ApiResponse> {
  const retryAfter = Math.ceil((result.resetAt - Date.now()) / 1000);
  const windowDescription =
    config.windowMs >= 24 * 60 * 60 * 1000
      ? "day"
      : config.windowMs >= 60 * 60 * 1000
      ? "hour"
      : "minute";

  const response = NextResponse.json<ApiResponse>(
    {
      success: false,
      error: `Rate limit exceeded. Maximum ${config.maxRequests} requests per ${windowDescription}.`,
    },
    { status: 429 }
  );

  response.headers.set("Retry-After", retryAfter.toString());
  response.headers.set("X-RateLimit-Limit", config.maxRequests.toString());
  response.headers.set("X-RateLimit-Remaining", "0");
  response.headers.set("X-RateLimit-Reset", result.resetAt.toString());

  return response;
}

/**
 * Add rate limit headers to a successful response
 */
export function addRateLimitHeaders(
  response: NextResponse,
  config: RateLimitConfig,
  result: RateLimitResult
): void {
  response.headers.set("X-RateLimit-Limit", config.maxRequests.toString());
  response.headers.set("X-RateLimit-Remaining", result.remaining.toString());
  response.headers.set("X-RateLimit-Reset", result.resetAt.toString());
}

/**
 * Generic rate limiting middleware
 * Can be used with a preset name or custom configuration
 * 
 * Usage with just handler (uses 'general' preset):
 * ```ts
 * return withRateLimit(request, async (req) => {
 *   // handler code
 * });
 * ```
 * 
 * Usage with preset:
 * ```ts
 * return withRateLimit(request, 'general', async (req) => {
 *   // handler code
 * });
 * ```
 * 
 * Usage with custom config:
 * ```ts
 * return withRateLimit(request, {
 *   maxRequests: 50,
 *   windowMs: 60000,
 *   keyPrefix: 'custom'
 * }, async (req) => {
 *   // handler code
 * });
 * ```
 */
export async function withRateLimit(
  request: NextRequest,
  configOrPresetOrHandler: RateLimitConfig | string | ((req: NextRequest) => Promise<NextResponse>),
  handlerOrOptions?: ((req: NextRequest) => Promise<NextResponse>) | {
    /** Optional userId if already authenticated */
    userId?: string;
    /** Whether to skip rate limiting if no identifier is found */
    skipIfNoIdentifier?: boolean;
  },
  options?: {
    /** Optional userId if already authenticated */
    userId?: string;
    /** Whether to skip rate limiting if no identifier is found */
    skipIfNoIdentifier?: boolean;
  }
): Promise<NextResponse> {
  // Handle overloaded function signatures
  let config: RateLimitConfig;
  let handler: (req: NextRequest) => Promise<NextResponse>;
  let opts: { userId?: string; skipIfNoIdentifier?: boolean } | undefined;

  try {
    // Case 1: withRateLimit(request, handler) - use 'general' preset
    if (typeof configOrPresetOrHandler === 'function') {
      config = RATE_LIMIT_PRESETS.general;
      handler = configOrPresetOrHandler;
      opts = handlerOrOptions as { userId?: string; skipIfNoIdentifier?: boolean } | undefined;
    }
    // Case 2: withRateLimit(request, config/preset, handler, options?)
    else {
      config = typeof configOrPresetOrHandler === "string"
        ? RATE_LIMIT_PRESETS[configOrPresetOrHandler] || RATE_LIMIT_PRESETS.general
        : configOrPresetOrHandler;
      
      if (typeof handlerOrOptions === 'function') {
        handler = handlerOrOptions;
        opts = options;
      } else {
        // Invalid signature - handler must be a function
        throw new Error('Invalid withRateLimit signature: handler must be a function');
      }
    }

    // Validate config and handler are set
    if (!config || !config.windowMs || !config.maxRequests) {
      throw new Error(`Invalid rate limit config: ${JSON.stringify(config)}`);
    }
    if (typeof handler !== 'function') {
      throw new Error('Handler must be a function');
    }
    const identifier = getRequestIdentifier(request, opts?.userId);

    if (identifier === "unknown" && opts?.skipIfNoIdentifier) {
      // Skip rate limiting if no identifier and option is set
      return handler(request);
    }

    const result = await checkRateLimit(config, identifier);

    if (!result.allowed) {
      // Log security event if configured
      if (config.logEvent) {
        try {
          const { logSecurityEvent } = await import("../lib/security/events");
          await logSecurityEvent({
            eventType: "RATE_LIMIT_HIT",
            userId: opts?.userId || null,
            metadata: {
              identifier,
              limit: config.maxRequests,
              windowMs: config.windowMs,
              count: result.count,
              path: request.nextUrl.pathname,
            },
            ipAddress:
              request.headers.get("x-forwarded-for") ||
              request.headers.get("x-real-ip") ||
              null,
          });
        } catch (error) {
          console.error("[RateLimit] Failed to log security event:", error);
        }
      }

      return createRateLimitResponse(config, result);
    }

    // Execute handler and add rate limit headers
    const response = await handler(request);
    addRateLimitHeaders(response, config, result);

    return response;
  } catch (error) {
    // If rate limiting fails, allow the request but log the error
    console.error("[RateLimit] Error in rate limiting:", error);
    // Only call handler if it's actually a function (safety check)
    if (typeof handler === 'function') {
      return handler(request);
    }
    // If handler is not set, return a 500 error
    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error: Rate limiting configuration error",
      },
      { status: 500 }
    );
  }
}

/**
 * Engagement-specific rate limiting middleware
 * Convenience wrapper for engagement actions (likes, comments, shares)
 * 
 * Usage:
 * ```ts
 * return withEngagementRateLimit(req, async (rateLimitedReq) => {
 *   // handler code
 * }, 'like');
 * ```
 */
export async function withEngagementRateLimit(
  request: NextRequest,
  handler: (req: NextRequest) => Promise<NextResponse>,
  actionType: "comment" | "share" | "like"
): Promise<NextResponse> {
  // Extract userId from auth token if present
  let userId: string | undefined;
  const authHeader = request.headers.get("authorization");
  if (authHeader?.startsWith("Bearer ")) {
    try {
      const token = authHeader.substring(7);
      const { AuthService } = await import("./auth");
      const payload = AuthService.verifyAccessToken(token);
      userId = payload?.userId;
    } catch (error) {
      // Token invalid, continue without userId
    }
  }

  return withRateLimit(request, actionType, handler, { userId });
}

/**
 * Legacy function for backward compatibility
 * @deprecated Use withRateLimit with preset or config instead
 */
export async function rateLimit(
  key: string,
  limit: number,
  windowSeconds: number
): Promise<{ allowed: boolean; remaining: number; resetAt: number }> {
  const config: RateLimitConfig = {
    maxRequests: limit,
    windowMs: windowSeconds * 1000,
    keyPrefix: key.split(":")[0] || "rl",
  };

  const identifier = key.split(":").slice(1).join(":") || "unknown";
  const result = await checkRateLimit(config, identifier);

  return {
    allowed: result.allowed,
    remaining: result.remaining,
    resetAt: Math.floor(result.resetAt / 1000), // Convert to seconds
  };
}

/**
 * Legacy function for backward compatibility
 * @deprecated Use getRequestIdentifier instead
 */
export function rlKeyFromUserOrIp(
  userId?: string,
  ip?: string,
  scope?: string
): string {
  const prefix = scope || "gen";
  const identifier = userId || ip || "anon";
  return `rl:${prefix}:${identifier}`;
}
