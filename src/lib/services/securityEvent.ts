import { prisma } from "@/lib/prisma";
import { SecurityEventType } from "@prisma/client";

export async function recordSecurityEvent(evt: {
  userId?: string;
  type: SecurityEventType | string;
  meta?: Record<string, unknown>;
}) {
  await prisma.securityEvent
    .create({
      data: {
        userId: evt.userId || null,
        eventType: evt.type as SecurityEventType,
        metadata: evt.meta ? JSON.parse(JSON.stringify(evt.meta)) : {},
      },
    })
    .catch(() => {});
}
