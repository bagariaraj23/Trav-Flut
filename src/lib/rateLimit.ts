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
  // Engagement actions - Per-user limits
  comment: {
    maxRequests: 15, // 15 comments per 15 minutes (60/hour effective)
    windowMs: 15 * 60 * 1000, // 15 minutes
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

  // Authentication endpoints - Strict limits to prevent brute force
  auth_login: {
    maxRequests: 100,
    windowMs: 15 * 60 * 1000, // 15 minutes (3 attempts, then 15min cool-down)
    keyPrefix: "rl:auth:login",
    logEvent: true,
  },
  auth_signup: {
    maxRequests: 100,
    windowMs: 60 * 60 * 1000, // 1 hour (50 sign-ups per hour per IP)
    keyPrefix: "rl:auth:signup",
    logEvent: true,
  },
  auth_forgot: {
    maxRequests: 2,
    windowMs: 60 * 60 * 1000, // 1 hour (2 requests/hour prevents email bombing)
    keyPrefix: "rl:auth:forgot",
    logEvent: true,
  },
  auth_reset: {
    maxRequests: 2,
    windowMs: 60 * 60 * 1000, // 1 hour (2 resets/hour)
    keyPrefix: "rl:auth:reset",
    logEvent: true,
  },
  auth_refresh: {
    maxRequests: 10,
    windowMs: 60 * 60 * 1000, // 1 hour (10 refreshes/hour for normal usage)
    keyPrefix: "rl:auth:refresh",
    logEvent: true,
  },
  auth_validate: {
    maxRequests: 20,
    windowMs: 60 * 60 * 1000, // 1 hour (20 validations/hour)
    keyPrefix: "rl:auth:validate",
    logEvent: false, // Less critical, no need to log
  },
  auth_google: {
    maxRequests: 30,
    windowMs: 15 * 60 * 1000,
    keyPrefix: "rl:auth:google",
    logEvent: true,
  },
  auth_complete_profile: {
    maxRequests: 20,
    windowMs: 15 * 60 * 1000,
    keyPrefix: "rl:auth:complete_profile",
    logEvent: true,
  },
  auth_link_google: {
    maxRequests: 10,
    windowMs: 15 * 60 * 1000,
    keyPrefix: "rl:auth:link_google",
    logEvent: true,
  },

  // General API endpoints
  general: {
    maxRequests: 100,
    windowMs: 60 * 1000, // 1 minute
    keyPrefix: "rl:general",
    logEvent: false,
  },

  // Search endpoints
  search: {
    maxRequests: 30,
    windowMs: 60 * 1000, // 1 minute
    keyPrefix: "rl:search",
    logEvent: false,
  },

  // Places endpoints
  places: {
    maxRequests: 100,
    windowMs: 60 * 1000, // 1 minute
    keyPrefix: "rl:places",
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
  const validWindowStart =
    isNaN(windowStart) || windowStart <= 0 ? 0 : windowStart;
  const validWindowMs =
    config.windowMs && config.windowMs > 0 ? config.windowMs : 60000; // Default 1 minute
  const windowKey = Math.floor(validWindowStart / validWindowMs);
  return `${prefix}:${identifier}:${windowKey}`;
}

/**
 * Check rate limit using sliding window algorithm
 * This prevents burst behavior by tracking individual request timestamps
 *
 * @param config - Rate limit configuration
 * @param identifier - User identifier (userId or IP)
 * @returns Rate limit result with allowed status
 */
export async function checkSlidingWindowRateLimit(
  config: RateLimitConfig,
  identifier: string
): Promise<RateLimitResult> {
  // Validate config
  if (!config || !config.windowMs || config.windowMs <= 0) {
    throw new Error(
      `Invalid rate limit config: windowMs must be > 0, got ${config?.windowMs}`
    );
  }
  if (!config.maxRequests || config.maxRequests <= 0) {
    throw new Error(
      `Invalid rate limit config: maxRequests must be > 0, got ${config?.maxRequests}`
    );
  }

  const now = Date.now();
  const windowStart = now - config.windowMs;
  const key = `${config.keyPrefix || "rl:sw"}:${identifier}`;

  let timestamps: number[] = [];
  let count: number;

  if (redis) {
    // Use Redis Sorted Set for distributed sliding window
    try {
      // Remove old timestamps outside the window
      await redis.zremrangebyscore(key, 0, windowStart);

      // Get count of requests in current window
      count = await redis.zcard(key);

      // Get all timestamps for calculating reset time
      const members = await redis.zrange<string[]>(key, 0, -1);
      timestamps = members.map((m: string) => parseFloat(m));

      // If allowed, add current timestamp
      if (count < config.maxRequests) {
        // Upstash Redis zadd signature: zadd(key, { score: number, member: string })
        await redis.zadd(key, { score: now, member: now.toString() });
        // Set expiration on the key (cleanup old keys)
        await redis.pexpire(key, config.windowMs + 60000); // Extra minute for safety
        count++;
        timestamps.push(now);
      }
    } catch (error) {
      // Fallback to memory cache if Redis fails
      console.warn(
        "[RateLimit] Redis error, falling back to memory cache:",
        error
      );
      timestamps = await getSlidingWindowFromMemory(
        key,
        windowStart,
        config.windowMs,
        now,
        config.maxRequests
      );
      count = timestamps.length;
    }
  } else {
    // Use memory cache for sliding window
    timestamps = await getSlidingWindowFromMemory(
      key,
      windowStart,
      config.windowMs,
      now,
      config.maxRequests
    );
    count = timestamps.length;
  }

  // Calculate reset time (when oldest request will expire)
  let resetAt: number;
  if (count >= config.maxRequests && timestamps.length > 0) {
    // Reset when the oldest request expires from the window
    const oldestTimestamp = Math.min(...timestamps);
    resetAt = oldestTimestamp + config.windowMs;
  } else {
    // If under limit, window resets at now + windowMs
    resetAt = now + config.windowMs;
  }

  const remaining = Math.max(0, config.maxRequests - count);
  const allowed = count <= config.maxRequests;

  return { allowed, remaining, resetAt, count };
}

/**
 * Helper function to manage sliding window in memory cache
 */
async function getSlidingWindowFromMemory(
  key: string,
  windowStart: number,
  windowMs: number,
  now: number,
  maxRequests: number
): Promise<number[]> {
  const cached = memoryCache.get(key) as { timestamps: number[] } | null;

  // Filter timestamps within the current window
  let timestamps =
    cached?.timestamps?.filter((ts: number) => ts > windowStart) || [];

  // If allowed, add current timestamp
  if (timestamps.length < maxRequests) {
    timestamps.push(now);
  }

  // Update cache
  memoryCache.set(key, { timestamps }, windowMs + 60000); // Extra minute for safety

  return timestamps;
}

/**
 * Check rate limit for a given identifier (userId or IP)
 * Uses fixed window approach (legacy, but still used for non-comment endpoints)
 * Uses Redis if available, falls back to memory cache
 */
export async function checkRateLimit(
  config: RateLimitConfig,
  identifier: string
): Promise<RateLimitResult> {
  // Validate config
  if (!config || !config.windowMs || config.windowMs <= 0) {
    throw new Error(
      `Invalid rate limit config: windowMs must be > 0, got ${config?.windowMs}`
    );
  }
  if (!config.maxRequests || config.maxRequests <= 0) {
    throw new Error(
      `Invalid rate limit config: maxRequests must be > 0, got ${config?.maxRequests}`
    );
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
      console.warn(
        "[RateLimit] Redis error, falling back to memory cache:",
        error
      );
      const cached = memoryCache.get(key) as {
        count: number;
        resetTime: number;
      } | null;
      if (cached && cached.resetTime > now) {
        count = cached.count + 1;
        memoryCache.set(
          key,
          { count, resetTime: cached.resetTime },
          config.windowMs
        );
      } else {
        count = 1;
        memoryCache.set(key, { count, resetTime: resetAt }, config.windowMs);
      }
    }
  } else {
    // Use memory cache as fallback
    const cached = memoryCache.get(key) as {
      count: number;
      resetTime: number;
    } | null;
    if (cached && cached.resetTime > now) {
      count = cached.count + 1;
      memoryCache.set(
        key,
        { count, resetTime: cached.resetTime },
        config.windowMs
      );
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
  configOrPresetOrHandler:
    | RateLimitConfig
    | string
    | ((req: NextRequest) => Promise<NextResponse>),
  handlerOrOptions?:
    | ((req: NextRequest) => Promise<NextResponse>)
    | {
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
  let handler: ((req: NextRequest) => Promise<NextResponse>) | undefined;
  let opts: { userId?: string; skipIfNoIdentifier?: boolean } | undefined;

  try {
    // Case 1: withRateLimit(request, handler) - use 'general' preset
    if (typeof configOrPresetOrHandler === "function") {
      config = RATE_LIMIT_PRESETS.general;
      handler = configOrPresetOrHandler;
      opts = handlerOrOptions as
        | { userId?: string; skipIfNoIdentifier?: boolean }
        | undefined;
    }
    // Case 2: withRateLimit(request, config/preset, handler, options?)
    else {
      config =
        typeof configOrPresetOrHandler === "string"
          ? RATE_LIMIT_PRESETS[configOrPresetOrHandler] ||
            RATE_LIMIT_PRESETS.general
          : configOrPresetOrHandler;

      if (typeof handlerOrOptions === "function") {
        handler = handlerOrOptions;
        opts = options;
      } else {
        // Invalid signature - handler must be a function
        throw new Error(
          "Invalid withRateLimit signature: handler must be a function"
        );
      }
    }

    // Validate config and handler are set
    if (!config || !config.windowMs || !config.maxRequests) {
      throw new Error(`Invalid rate limit config: ${JSON.stringify(config)}`);
    }
    if (typeof handler !== "function") {
      throw new Error("Handler must be a function");
    }
    const identifier = getRequestIdentifier(request, opts?.userId);

    if (identifier === "unknown" && opts?.skipIfNoIdentifier) {
      // Skip rate limiting if no identifier and option is set
      return handler(request);
    }

    // Sliding window rate limiting available but disabled for now
    // TODO: Enable for critical endpoints when needed
    // const isCommentEndpoint = config.keyPrefix === "rl:comment";
    // const result = isCommentEndpoint
    //   ? await checkSlidingWindowRateLimit(config, identifier)
    //   : await checkRateLimit(config, identifier);

    // Using fixed window for all endpoints
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
    if (typeof handler === "function") {
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
