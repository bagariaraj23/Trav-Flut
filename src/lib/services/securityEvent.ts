import { prisma } from "@/lib/prisma";

export async function recordSecurityEvent(evt: { userId?: string; type: string; meta?: Record<string, unknown> }) {
  try {
    await prisma.securityEvent.create({
      data: {
        userId: evt.userId ?? undefined,
        type: evt.type,
        meta: evt.meta === undefined ? undefined : (evt.meta as any),
      },
    });
  } catch (e) {
    // Optionally log or handle the error
  }
}