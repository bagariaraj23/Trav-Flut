import { TripStatus } from '@prisma/client';
import { prisma } from "@/lib/prisma";

export async function validateTripStatus(userId: string): Promise<{ hasOngoingTrip: boolean }> {
    const ongoingTrip = await prisma.trip.findFirst({
        where: {
            userId,
            status: TripStatus.ONGOING,
        },
    });

    return {
        hasOngoingTrip: !!ongoingTrip
    };
}