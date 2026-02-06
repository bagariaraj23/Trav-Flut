import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { ApiResponse, TripFinalPostResponse, TripResponse } from "@/types/api";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
  AuthenticatedRequest,
} from "@/lib/middleware";
import { PerformanceMonitor, ErrorTracker } from "@/lib/monitoring";
import { NotFoundError, ConflictError, ValidationError } from "@/lib/errors";
import { TripStatus } from "@prisma/client";

// End a trip
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        const endTimer =
          PerformanceMonitor.getInstance().startTimer("end_trip");

        try {
          const { id } = await params;
          const tripId = id;
          const userId = authenticatedReq.user!.userId;

          // Check if trip exists and user is owner
          const trip = await prisma.trip.findUnique({
            where: { id: tripId },
            select: {
              id: true,
              userId: true,
              status: true,
            },
          });

          if (!trip) {
            throw new NotFoundError("Trip not found");
          }

          if (trip.userId !== userId) {
            throw new ValidationError("Only trip owner can end the trip");
          }

          if (trip.status !== TripStatus.ONGOING) {
            throw new ConflictError("Trip is not ongoing");
          }

          // Update trip status and generate final post atomically in a transaction
          const [updatedTrip, finalPost] = await prisma.$transaction(
            async (tx) => {
              // Update trip status
              const updated = await tx.trip.update({
                where: { id: tripId },
                data: {
                  status: TripStatus.ENDED,
                  endDate: new Date(),
                  updatedAt: new Date(),
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
                  _count: {
                    select: {
                      threadEntries: true,
                      media: true,
                      participants: true,
                    },
                  },
                  participants: {
                    include: {
                      user: true,
                    },
                  },
                  threadEntries: {
                    include: {
                      media: true,
                      taggedUsers: true,
                      author: true,
                    },
                    orderBy: { createdAt: "asc" },
                  },
                },
              });

              // Generate final post inside the same transaction
              // This ensures atomicity and prevents race conditions
              const generatedFinalPost =
                await TripFinalizerService.generateFinalPost(
                  tripId,
                  userId,
                  tx
                );

              return [updated, generatedFinalPost];
            }
          );

          const finalPostResponse: TripFinalPostResponse = {
            ...finalPost,
            caption: finalPost.caption ?? undefined,
            coverMediaUrl: finalPost.coverMediaUrl ?? undefined,
            generationStatus: finalPost.generationStatus,
            publishedAt: finalPost.publishedAt
              ? finalPost.publishedAt.toISOString()
              : undefined,
            createdAt: finalPost.createdAt.toISOString(),
            updatedAt: finalPost.updatedAt.toISOString(),
          };

          const tripResponse: TripResponse = {
            ...updatedTrip,
            startDate: updatedTrip.startDate?.toISOString() || undefined,
            endDate: updatedTrip.endDate?.toISOString() || undefined,
            createdAt: updatedTrip.createdAt.toISOString(),
            updatedAt: updatedTrip.updatedAt.toISOString(),
            user: updatedTrip.user
              ? {
                  ...updatedTrip.user,
                  username: updatedTrip.user.username ?? undefined,
                  name: updatedTrip.user.name ?? undefined,
                  avatarUrl: updatedTrip.user.avatarUrl ?? undefined,
                  bio: updatedTrip.user.bio ?? undefined,
                  createdAt: updatedTrip.user.createdAt.toISOString(),
                  updatedAt: updatedTrip.user.updatedAt.toISOString(),
                }
              : undefined,
            finalPost: finalPostResponse,
            description: updatedTrip.description ?? undefined,
            mood: updatedTrip.mood ?? undefined,
            type: updatedTrip.type ?? undefined,
            coverMediaId: updatedTrip.coverMediaId ?? undefined,
            status: updatedTrip.status,
            participants: updatedTrip.participants.map((p: any) => ({
              ...p,
              joinedAt: p.joinedAt.toISOString(),
              user: {
                ...p.user,
                username: p.user.username ?? undefined,
                name: p.user.name ?? undefined,
                avatarUrl: p.user.avatarUrl ?? undefined,
                bio: p.user.bio ?? undefined,
                createdAt: p.user.createdAt.toISOString(),
                updatedAt: p.user.updatedAt.toISOString(),
              },
            })),
            threadEntries: updatedTrip.threadEntries.map((entry: any) => ({
              ...entry,
              createdAt: entry.createdAt.toISOString(),
              author: {
                ...entry.author,
                createdAt: entry.author.createdAt.toISOString(),
                updatedAt: entry.author.updatedAt.toISOString(),
              },
              taggedUsers: entry.taggedUsers.map((tag: any) => ({
                ...tag.taggedUser,
                createdAt: tag.taggedUser.createdAt.toISOString(),
                updatedAt: tag.taggedUser.updatedAt.toISOString(),
              })),
              media: entry.media
                ? {
                    ...entry.media,
                    createdAt: entry.media.createdAt.toISOString(),
                  }
                : undefined,
            })),
            _count: {
              threadEntries: updatedTrip._count.threadEntries,
              media: updatedTrip._count.media,
              participants: updatedTrip._count.participants,
            },
          };

          endTimer();

          return NextResponse.json<ApiResponse<TripResponse>>({
            success: true,
            data: tripResponse,
            message: "Trip ended successfully and final post generated",
          });
        } catch (error) {
          endTimer();
          if (error instanceof Error) {
            ErrorTracker.getInstance().trackError(error, {
              operation: "end_trip",
            });
          }
          return handleApiError(error);
        }
      });
    });
  });

  return await loggedHandler(request);
}
