import { TripStatus } from '@prisma/client';
import { prisma } from "@/lib/prisma";

export interface TripConflictInfo {
    hasOngoingTrip: boolean;
    hasFutureTrip: boolean;
    ongoingTrip?: {
        id: string;
        title: string;
        startDate: Date;
        endDate: Date | null;
        status: TripStatus;
    };
    futureTrip?: {
        id: string;
        title: string;
        startDate: Date;
        endDate: Date | null;
        status: TripStatus;
    };
}

export async function validateTripStatus(userId: string): Promise<TripConflictInfo> {
    const now = new Date();
    
    // Check for ongoing trip
    const ongoingTrip = await prisma.trip.findFirst({
        where: {
            userId,
            status: TripStatus.ONGOING,
        },
        select: {
            id: true,
            title: true,
            startDate: true,
            endDate: true,
            status: true,
        },
    });

    // Check for future trips (UPCOMING status OR startDate in the future)
    const futureTrip = await prisma.trip.findFirst({
        where: {
            userId,
            OR: [
                { status: TripStatus.UPCOMING },
                {
                    status: { in: [TripStatus.ONGOING, TripStatus.UPCOMING] },
                    startDate: { gt: now },
                },
            ],
        },
        select: {
            id: true,
            title: true,
            startDate: true,
            endDate: true,
            status: true,
        },
        orderBy: {
            startDate: 'asc', // Get the earliest future trip
        },
    });

    return {
        hasOngoingTrip: !!ongoingTrip,
        hasFutureTrip: !!futureTrip,
        ongoingTrip: ongoingTrip ? {
            id: ongoingTrip.id,
            title: ongoingTrip.title,
            startDate: ongoingTrip.startDate,
            endDate: ongoingTrip.endDate,
            status: ongoingTrip.status,
        } : undefined,
        futureTrip: futureTrip ? {
            id: futureTrip.id,
            title: futureTrip.title,
            startDate: futureTrip.startDate,
            endDate: futureTrip.endDate,
            status: futureTrip.status,
        } : undefined,
    };
}