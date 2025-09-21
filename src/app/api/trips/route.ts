import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { createTripSchema } from "@/lib/validation";
import { ApiResponse, TripResponse } from "@/types/api";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { PerformanceMonitor, ErrorTracker } from "@/lib/monitoring";
import { NotFoundError, ConflictError, ValidationError } from "@/lib/errors";

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
              "[DEBUG] coverMediaUrl after validation:",
              validatedData.coverMediaUrl
            );
            console.log(
              "[DEBUG] description after validation:",
              validatedData.description
            );
            console.log("[DEBUG] mood after validation:", validatedData.mood);
            console.log("[DEBUG] type after validation:", validatedData.type);

            const userId = authenticatedReq.user!.userId;
            console.log("[DEBUG] User ID:", userId);

            // Check if user has an ongoing trip
            const ongoingTrip = await prisma.trip.findFirst({
              where: {
                userId,
                status: "ONGOING",
              },
            });

            if (ongoingTrip) {
              throw new ConflictError(
                "You already have an ongoing trip. Please end it before starting a new one."
              );
            }

            // Create trip with transaction for data consistency
            const trip = await prisma.$transaction(async (tx) => {
              const tripData = {
                ...validatedData,
                userId,
                startDate: validatedData.startDate
                  ? new Date(validatedData.startDate)
                  : null,
                endDate: validatedData.endDate
                  ? new Date(validatedData.endDate)
                  : null,
                status: "ONGOING" as const,
              };

              console.log(
                "[DEBUG] Trip data for database:",
                JSON.stringify(tripData, null, 2)
              );
              console.log(
                "[DEBUG] coverMediaUrl in tripData:",
                tripData.coverMediaUrl
              );
              console.log(
                "[DEBUG] description in tripData:",
                tripData.description
              );
              console.log("[DEBUG] mood in tripData:", tripData.mood);
              console.log("[DEBUG] type in tripData:", tripData.type);

              const newTrip = await tx.trip.create({
                data: tripData,
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
                  _count: {
                    select: {
                      threadEntries: true,
                      media: true,
                      participants: true,
                    },
                  },
                },
              });

              // Log trip creation for analytics
              console.log(
                `[DEBUG] Trip created successfully: ${newTrip.id} by user ${userId}`
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
              coverMediaUrl: trip.coverMediaUrl ?? undefined,
              type: trip.type ?? undefined,
              mood: trip.mood ?? undefined,
              createdAt: trip.createdAt.toISOString(),
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
            };

            console.log(
              "[DEBUG] Final trip response:",
              JSON.stringify(tripResponse, null, 2)
            );
            console.log(
              "[DEBUG] coverMediaUrl in response:",
              tripResponse.coverMediaUrl
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
                    `Start date validation failed: ${
                      firstError.message
                    }. Received: ${body?.startDate || "undefined"}`
                  );
                } else if (firstError.path.includes("endDate")) {
                  throw new ValidationError(
                    `End date validation failed: ${
                      firstError.message
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
      { maxRequests: 10, windowMs: 60000 } // 10 trips per minute max
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
          const status = searchParams.get("status") as
            | "UPCOMING"
            | "ONGOING"
            | "ENDED"
            | null;

          // Include trips where user is owner OR participant
          const whereClause: any = {
            OR: [
              { userId }, // Trips owned by user
              {
                participants: {
                  some: { userId }, // Trips where user is a participant
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
              _count: {
                select: {
                  threadEntries: true,
                  media: true,
                  participants: true,
                },
              },
            },
            orderBy: { createdAt: "desc" },
            take: 50, // Limit results for performance
          });

          const tripsResponse: TripResponse[] = trips.map((trip) => ({
            ...trip,
            startDate: trip.startDate
              ? trip.startDate.toISOString()
              : undefined,
            endDate: trip.endDate ? trip.endDate.toISOString() : undefined,
            createdAt: trip.createdAt.toISOString(),
            coverMediaUrl: trip.coverMediaUrl ?? undefined, // Fix: convert null to undefined for coverMediaUrl
            type: trip.type ?? undefined, // Fix: convert null to undefined for type
            // Fix for mood: convert null to undefined to match TripResponse type
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
