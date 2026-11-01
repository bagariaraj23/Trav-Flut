import { NextRequest, NextResponse } from "next/server";
import { TripStatus } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { updateTripDatesSchema } from "@/lib/validation";
import {
  withAuth,
  AuthenticatedRequest,
  handleApiError,
} from "@/lib/middleware";
import { ApiResponse } from "@/types/api";
import { NotFoundError, ValidationError } from "@/lib/errors";
import { scheduledEndInstant } from "@/lib/tripSchedule";

async function handler(
  request: AuthenticatedRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: tripId } = await params;
    const userId = request.user!.userId;
    const body = updateTripDatesSchema.parse(await request.json());

    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      select: {
        id: true,
        userId: true,
        status: true,
        startDate: true,
        endDate: true,
        scheduleTimezone: true,
      },
    });

    if (!trip) throw new NotFoundError("Trip not found");
    if (trip.userId !== userId) {
      throw new ValidationError("Only the trip owner can change the schedule");
    }
    if (trip.status === TripStatus.ENDED) {
      throw new ValidationError("An ended trip cannot be rescheduled");
    }

    const now = new Date();
    let startDate = trip.startDate;
    if (body.startDate !== undefined) {
      if (trip.status !== TripStatus.UPCOMING) {
        throw new ValidationError("Start time can only change before the trip starts");
      }
      const parsed = new Date(body.startDate);
      if (isNaN(parsed.getTime())) {
        throw new ValidationError("Start time must be a valid date");
      }
      if (parsed.getTime() < now.getTime() - 2 * 60 * 1000) {
        throw new ValidationError("Start time cannot be in the past");
      }
      startDate = parsed;
    }

    const zone = body.scheduleTimezone ?? trip.scheduleTimezone;
    let endDate = trip.endDate;
    if (body.endDate !== undefined) {
      if (body.endDate === null) {
        endDate = null;
      } else {
        const parsed = new Date(body.endDate);
        if (isNaN(parsed.getTime())) {
          throw new ValidationError("End time must be a valid date");
        }
        endDate = scheduledEndInstant(parsed, zone);
        if (endDate.getTime() <= now.getTime()) {
          throw new ValidationError("End time must be in the future");
        }
      }
    } else if (body.scheduleTimezone && trip.endDate) {
      endDate = scheduledEndInstant(trip.endDate, zone);
    }

    if (endDate && endDate.getTime() <= startDate.getTime()) {
      throw new ValidationError("End time must be after the start time");
    }

    const status =
      startDate.getTime() > now.getTime() ? TripStatus.UPCOMING : TripStatus.ONGOING;

    const updated = await prisma.trip.update({
      where: { id: tripId },
      data: {
        startDate,
        endDate,
        status,
        ...(body.scheduleTimezone
          ? { scheduleTimezone: body.scheduleTimezone }
          : {}),
        updatedAt: now,
      },
      select: {
        id: true,
        startDate: true,
        endDate: true,
        status: true,
        scheduleTimezone: true,
      },
    });

    return NextResponse.json<ApiResponse>({
      success: true,
      data: {
        ...updated,
        startDate: updated.startDate.toISOString(),
        endDate: updated.endDate ? updated.endDate.toISOString() : null,
      },
      message: "Trip schedule updated",
    });
  } catch (error) {
    return handleApiError(error);
  }
}

export async function PATCH(
  request: NextRequest,
  context: { params: Promise<{ id: string }> }
) {
  return withAuth(request, (authRequest) => handler(authRequest, context));
}
