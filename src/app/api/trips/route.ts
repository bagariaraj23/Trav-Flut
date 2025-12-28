import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createTripSchema } from "@/lib/validation";
import { validateTripStatus } from "@/lib/tripValidation";
import { ApiResponse, TripResponse } from "@/types/api";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { PerformanceMonitor, ErrorTracker } from "@/lib/monitoring";
import { NotFoundError, ConflictError, ValidationError } from "@/lib/errors";
import { TripStatus } from "@prisma/client";

// Create a new trip
export async function POST(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(
      req,
      async (rateLimitedReq) => {
        return withAuth(rateLimitedReq, async (authenticatedReq) => {
          const endTimer =
            PerformanceMonitor.getInstance().startTimer("create_trip");

          let body: any;
          try {
            body = await authenticatedReq.json();

            // Add comprehensive debugging
            console.log("[DEBUG] Create trip request received");
            console.log("[DEBUG] Request body:", JSON.stringify(body, null, 2));
            console.log("[DEBUG] startDate type:", typeof body.startDate);
            console.log("[DEBUG] startDate value:", body.startDate);
            console.log("[DEBUG] endDate type:", typeof body.endDate);
            console.log("[DEBUG] endDate value:", body.endDate);

            if (body.startDate) {
              const parsedStartDate = new Date(body.startDate);
              console.log("[DEBUG] startDate parsed:", parsedStartDate);
              console.log(
                "[DEBUG] startDate isValid:",
                !isNaN(parsedStartDate.getTime())
              );
              console.log(
                "[DEBUG] startDate toISOString:",
                parsedStartDate.toISOString()
              );
              console.log(
                "[DEBUG] startDate timezone offset:",
                parsedStartDate.getTimezoneOffset()
              );
              console.log("[DEBUG] Current server time:", new Date());
              console.log(
                "[DEBUG] Server timezone offset:",
                new Date().getTimezoneOffset()
              );
            }

            if (body.endDate) {
              const parsedEndDate = new Date(body.endDate);
              console.log("[DEBUG] endDate parsed:", parsedEndDate);
              console.log(
                "[DEBUG] endDate isValid:",
                !isNaN(parsedEndDate.getTime())
              );
              console.log(
                "[DEBUG] endDate toISOString:",
                parsedEndDate.toISOString()
              );
              console.log(
                "[DEBUG] endDate timezone offset:",
                parsedEndDate.getTimezoneOffset()
              );
            }

            const validatedData = createTripSchema.parse(body);
            console.log(
              "[DEBUG] Validation passed, validated data:",
              JSON.stringify(validatedData, null, 2)
            );
            console.log(
              "[DEBUG] coverMediaId after validation:",
              validatedData.coverMediaId
            );
            console.log(
              "[DEBUG] description after validation:",
              validatedData.description
            );
            console.log("[DEBUG] mood after validation:", validatedData.mood);
            console.log("[DEBUG] type after validation:", validatedData.type);

            const userId = authenticatedReq.user!.userId;
            console.log("[DEBUG] User ID:", userId);

            // Check if user wants to replace existing trip
            const replaceExisting = body.replaceExisting === true;
            
            // Validate trip status
            const tripConflict = await validateTripStatus(userId);

            // If user hasn't explicitly chosen to replace, block creation
            if (!replaceExisting && (tripConflict.hasOngoingTrip || tripConflict.hasFutureTrip)) {
              const conflictType = tripConflict.hasOngoingTrip ? 'ongoing' : 'future';
              const tripInfo = tripConflict.hasOngoingTrip 
                ? tripConflict.ongoingTrip 
                : tripConflict.futureTrip;
              
              throw new ConflictError(
                `You already have an ${conflictType} trip${tripInfo ? `: "${tripInfo.title}"` : ''}. Please end it before starting a new one, or set replaceExisting=true to replace it.`
              );
            }

            // If user chose to replace, end the existing trip(s)
            if (replaceExisting) {
              const tripsToEnd: string[] = [];
              if (tripConflict.ongoingTrip) {
                tripsToEnd.push(tripConflict.ongoingTrip.id);
              }
              if (tripConflict.futureTrip && tripConflict.futureTrip.id !== tripConflict.ongoingTrip?.id) {
                tripsToEnd.push(tripConflict.futureTrip.id);
              }

              // End all conflicting trips
              if (tripsToEnd.length > 0) {
                await prisma.trip.updateMany({
                  where: {
                    id: { in: tripsToEnd },
                    userId,
                  },
                  data: {
                    status: TripStatus.ENDED,
                    updatedAt: new Date(),
                  },
                });
                console.log(`[DEBUG] Ended ${tripsToEnd.length} existing trip(s) to allow new trip creation`);
              }
            }

            // Extract destinationPlaceIds from validated data
            const { destinationPlaceIds, ...tripData } = validatedData;

            let startLocationId: string | undefined;
            let endLocationId: string | undefined;

            if (destinationPlaceIds && destinationPlaceIds.length > 0) {
              startLocationId = destinationPlaceIds[0];
              endLocationId =
                destinationPlaceIds.length > 1
                  ? destinationPlaceIds[destinationPlaceIds.length - 1]
                  : destinationPlaceIds[0];
            }

            const coverMediaId = tripData.coverMediaId ?? null;

            // Validate cover media ownership if provided
            if (coverMediaId) {
              const mediaRecord = await prisma.media.findUnique({
                where: { id: coverMediaId },
                select: { id: true, uploadedById: true, tripId: true },
              });

              if (!mediaRecord) {
                throw new ValidationError("Cover media not found");
              }

              if (mediaRecord.uploadedById !== userId) {
                throw new ValidationError("You do not have permission to use this media");
              }
            }

            // Create trip with transaction for data consistency
            const trip = await prisma.$transaction(async (tx) => {
              // Normalize dates to UTC midnight to avoid timezone issues
              // Parse the date string and extract only date components
              const parsedStartDate = new Date(validatedData.startDate);
              const parsedEndDate = tripData.endDate ? new Date(tripData.endDate) : parsedStartDate;
              
              // Create UTC dates at midnight (00:00:00 UTC) using only date components
              const normalizedStartDate = new Date(Date.UTC(
                parsedStartDate.getUTCFullYear(),
                parsedStartDate.getUTCMonth(),
                parsedStartDate.getUTCDate(),
                0, 0, 0, 0
              ));
              
              const normalizedEndDate = new Date(Date.UTC(
                parsedEndDate.getUTCFullYear(),
                parsedEndDate.getUTCMonth(),
                parsedEndDate.getUTCDate(),
                0, 0, 0, 0
              ));

              // Calculate trip status based on start date
              const now = new Date();
              const today = new Date(Date.UTC(
                now.getUTCFullYear(),
                now.getUTCMonth(),
                now.getUTCDate(),
                0, 0, 0, 0
              ));

              const status = normalizedStartDate > today ? TripStatus.UPCOMING : TripStatus.ONGOING;

              // Create trip with required fields
              const newTrip = await tx.trip.create({
                data: {
                  title: tripData.title,
                  userId,
                  status,
                  startDate: normalizedStartDate,
                  endDate: normalizedEndDate,
                  description: tripData.description ?? null,
                  type: tripData.type ?? null,
                  mood: tripData.mood ?? null,
                  coverMediaId,
                  startLocationId: startLocationId ?? null,
                  endLocationId: endLocationId ?? null,
                },
                include: {
                  user: {
                    select: {
                      id: true,
                      email: true,
                      username: true,
                      name: true,
                      avatarUrl: true,
                      bio: true,
                      isPrivate: true,
                      createdAt: true,
                      updatedAt: true,
                    },
                  },
                  coverMedia: true,
                  _count: {
                    select: {
                      threadEntries: true,
                      media: true,
                      participants: true,
                    },
                  },
                },
              }) as any; // Type assertion needed due to complex response type

              if (coverMediaId) {
                await tx.media.update({
                  where: { id: coverMediaId },
                  data: { tripId: newTrip.id },
                });
              }

              // Create place associations if destinationPlaceIds are provided
              if (destinationPlaceIds && destinationPlaceIds.length > 0) {
                await tx.placeOnTrip.createMany({
                  data: destinationPlaceIds.map(
                    (placeId: string, index: number) => ({
                      tripId: newTrip.id,
                      placeId,
                      order: index,
                      dayIndex: null,
                    })
                  ),
                  skipDuplicates: true,
                });
              }

              console.log(
                `[INFO] Trip created: ${newTrip.id} by user ${userId} with ${destinationPlaceIds?.length || 0
                } destination(s)`
              );

              return newTrip;
            });

            const tripResponse: TripResponse = {
              ...trip,
              startDate: trip.startDate
                ? trip.startDate.toISOString()
                : undefined,
              endDate: trip.endDate ? trip.endDate.toISOString() : undefined,
              description: trip.description ?? undefined,
              coverMediaId: trip.coverMediaId ?? undefined,
              type: trip.type ?? undefined,
              mood: trip.mood ?? undefined,
              createdAt: trip.createdAt.toISOString(),
              updatedAt: trip.updatedAt.toISOString(),
              coverMedia: trip.coverMedia
                ? {
                    ...trip.coverMedia,
                    filename: trip.coverMedia.filename ?? undefined,
                    size: trip.coverMedia.size ?? undefined,
                    tripId: trip.coverMedia.tripId ?? undefined,
                    createdAt: trip.coverMedia.createdAt.toISOString(),
                  }
                : undefined,
              user: trip.user
                ? {
                  ...trip.user,
                  username: trip.user.username ?? undefined,
                  name: trip.user.name ?? undefined,
                  avatarUrl: trip.user.avatarUrl ?? undefined,
                  bio: trip.user.bio ?? undefined,
                  createdAt: trip.user.createdAt.toISOString(),
                  updatedAt: trip.user.updatedAt.toISOString(),
                }
                : undefined,
            };

            console.log(
              "[DEBUG] Final trip response:",
              JSON.stringify(tripResponse, null, 2)
            );
            console.log(
              "[DEBUG] coverMediaId in response:",
              tripResponse.coverMediaId
            );
            console.log(
              "[DEBUG] description in response:",
              tripResponse.description
            );
            console.log("[DEBUG] mood in response:", tripResponse.mood);
            console.log("[DEBUG] type in response:", tripResponse.type);

            return NextResponse.json<ApiResponse<TripResponse>>(
              {
                success: true,
                data: tripResponse,
              },
              { status: 201 }
            );
          } catch (error: any) {
            ErrorTracker.getInstance().trackError(
              error,
              { operation: "create_trip" },
              authenticatedReq.user?.userId
            );

            console.log("[DEBUG] Error in create trip:", error);
            console.log("[DEBUG] Error name:", error.name);
            console.log("[DEBUG] Error message:", error.message);
            console.log("[DEBUG] Error stack:", error.stack);

            if (error.name === "ZodError") {
              const validationErrors = error.errors;
              console.log(
                "[DEBUG] Validation errors:",
                JSON.stringify(validationErrors, null, 2)
              );

              // Find the first validation error
              const firstError = validationErrors[0];
              if (firstError) {
                console.log("[DEBUG] First validation error:", firstError);
                console.log("[DEBUG] Error path:", firstError.path);
                console.log("[DEBUG] Error message:", firstError.message);

                // Provide more specific error messages for date issues
                if (firstError.path.includes("startDate")) {
                  throw new ValidationError(
                    `Start date validation failed: ${firstError.message
                    }. Received: ${body?.startDate || "undefined"}`
                  );
                } else if (firstError.path.includes("endDate")) {
                  throw new ValidationError(
                    `End date validation failed: ${firstError.message
                    }. Received: ${body?.endDate || "undefined"}`
                  );
                } else {
                  throw new ValidationError(
                    firstError.message || "Validation error"
                  );
                }
              } else {
                throw new ValidationError("Validation error");
              }
            }

            throw error;
          } finally {
            endTimer();
          }
        });
      },
      { maxRequests: 5, windowMs: 60000 }
    );
  })(request);
}

// Get user's trips
export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        const endTimer =
          PerformanceMonitor.getInstance().startTimer("get_trips");

        try {
          const userId = authenticatedReq.user!.userId;
          const { searchParams } = new URL(authenticatedReq.url);
          const status = searchParams.get("status") as TripStatus | null;

          // Include trips where user is owner OR participant
          const whereClause: any = {
            OR: [
              { userId },
              {
                participants: {
                  some: { userId },
                },
              },
            ],
          };

          if (status) {
            whereClause.status = status;
          }

          const trips = await prisma.trip.findMany({
            where: whereClause,
            include: {
              user: {
                select: {
                  id: true,
                  email: true,
                  username: true,
                  name: true,
                  avatarUrl: true,
                  bio: true,
                  isPrivate: true,
                  createdAt: true,
                  updatedAt: true,
                },
              },
              coverMedia: true,
              _count: {
                select: {
                  threadEntries: true,
                  media: true,
                  participants: true,
                },
              },
            },
            orderBy: { createdAt: "desc" },
            take: 50,
          });

          // Explicitly type trip as any to avoid TS error for .user property
          const tripsResponse: TripResponse[] = trips.map((trip: any) => ({
            ...trip,
            startDate: trip.startDate
              ? trip.startDate.toISOString()
              : undefined,
            endDate: trip.endDate ? trip.endDate.toISOString() : undefined,
            createdAt: trip.createdAt.toISOString(),
            coverMediaId: trip.coverMediaId ?? undefined,
            type: trip.type ?? undefined,
            mood: trip.mood ?? undefined,
            description: trip.description ?? undefined,
            updatedAt: trip.updatedAt.toISOString(),
            user: trip.user
              ? {
                ...trip.user,
                username: trip.user.username ?? undefined,
                name: trip.user.name ?? undefined,
                avatarUrl: trip.user.avatarUrl ?? undefined,
                bio: trip.user.bio ?? undefined,
                createdAt: trip.user.createdAt.toISOString(),
                updatedAt: trip.user.updatedAt.toISOString(),
              }
              : undefined,
            coverMedia: trip.coverMedia
              ? {
                  ...trip.coverMedia,
                  filename: trip.coverMedia.filename ?? undefined,
                  size: trip.coverMedia.size ?? undefined,
                  tripId: trip.coverMedia.tripId ?? undefined,
                  createdAt: trip.coverMedia.createdAt.toISOString(),
                }
              : undefined,
          }));

          return NextResponse.json<ApiResponse<TripResponse[]>>({
            success: true,
            data: tripsResponse,
          });
        } catch (error: any) {
          ErrorTracker.getInstance().trackError(
            error,
            { operation: "get_trips" },
            authenticatedReq.user?.userId
          );
          throw error;
        } finally {
          endTimer();
        }
      });
    });
  })(request);
}
