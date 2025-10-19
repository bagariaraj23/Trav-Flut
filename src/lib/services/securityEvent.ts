import { prisma } from "@/lib/prisma";

export async function recordSecurityEvent(evt: {
  userId?: string;
  type: string;
  meta?: Record<string, unknown>;
}) {
  await prisma.securityEvent
    .create({
      data: {
        userId: evt.userId || null,
        type: evt.type,
        meta: evt.meta ? JSON.parse(JSON.stringify(evt.meta)) : undefined,
      },
    })
    .catch(() => {});
}
