import { SecurityEventType, EntityType } from '@prisma/client';
import { prisma } from '../prisma';

interface LogSecurityEventParams {
  eventType: SecurityEventType;
  userId?: string | null;
  entityType?: EntityType | null;
  entityId?: string | null;
  ipAddress?: string | null;
  metadata?: Record<string, any>;
}

export async function logSecurityEvent(params: LogSecurityEventParams): Promise<void> {
  try {
    await prisma.securityEvent.create({
      data: {
        eventType: params.eventType,
        userId: params.userId || null,
        entityType: params.entityType || null,
        entityId: params.entityId || null,
        ipAddress: params.ipAddress || null,
        metadata: params.metadata || {},
      },
    });
  } catch (error) {
    console.error('[SecurityEvent] Failed to log event:', error);
  }
}

export async function getAbuseScore(userId: string, hours: number = 24): Promise<number> {
  const since = new Date(Date.now() - hours * 60 * 60 * 1000);

  const events = await prisma.securityEvent.count({
    where: {
      userId,
      createdAt: {
        gte: since,
      },
      eventType: {
        in: ['RATE_LIMIT_HIT', 'PROFANITY_DETECTED', 'ABUSE_DETECTED'],
      },
    },
  });

  return events;
}

