import { cacheGetJson, cacheSetJson } from "@/lib/cache";

export async function rateLimit(
  key: string,
  limit: number,
  windowSeconds: number
): Promise<{ allowed: boolean; remaining: number; resetAt: number }> {
  const now = Math.floor(Date.now() / 1000);
  const windowKey = `${key}:${Math.floor(now / windowSeconds)}`;
  const current = (await cacheGetJson<number>(windowKey)) ?? 0;
  const next = current + 1;
  const resetAt = (Math.floor(now / windowSeconds) + 1) * windowSeconds;
  await cacheSetJson(windowKey, next, resetAt - now);
  return {
    allowed: next <= limit,
    remaining: Math.max(0, limit - next),
    resetAt,
  };
}

export function rlKeyFromUserOrIp(
  userId?: string,
  ip?: string,
  scope?: string
): string {
  return `rl:${scope ?? "gen"}:${userId ?? ip ?? "anon"}`;
}
