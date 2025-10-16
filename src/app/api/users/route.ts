import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse } from "@/types/api";

export interface DiscoverUserDto {
  id: string;
  username?: string;
  name?: string;
  avatarUrl?: string;
  bio?: string;
  isPrivate: boolean;
  isFollowing: boolean;
  isFollowedBy: boolean;
}

export interface PaginatedResponse<T> {
  items: T[];
  page: number;
  limit: number;
  total: number;
  hasNext: boolean;
}

export async function GET(request: NextRequest) {
  try {
    // Verify authentication
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Authorization token required",
        },
        { status: 401 }
      );
    }

    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);

    if (!payload) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Invalid token",
        },
        { status: 401 }
      );
    }

    const currentUserId = payload.userId;

    // Parse query parameters
    const searchParams = request.nextUrl.searchParams;
    const search = searchParams.get("search")?.trim();
    const page = parseInt(searchParams.get("page") || "1");
    const limit = Math.min(parseInt(searchParams.get("limit") || "20"), 50);
    const prioritizeFollowed =
      searchParams.get("prioritizeFollowed") === "true";

    // Validate parameters
    if (page < 1) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Page must be greater than 0",
        },
        { status: 400 }
      );
    }

    if (limit < 1 || limit > 50) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Limit must be between 1 and 50",
        },
        { status: 400 }
      );
    }

    if (search && search.length < 1) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Search query must be at least 1 character",
        },
        { status: 400 }
      );
    }

    const offset = (page - 1) * limit;

    let users: any[] = [];
    let total = 0;

    if (prioritizeFollowed && search) {
      // 1. Search followed users first
      const followedUsers = await prisma.user.findMany({
        where: {
          id: { not: currentUserId },
          followers: {
            some: {
              followerId: currentUserId,
            },
          },
          OR: [
            { username: { contains: search, mode: "insensitive" } },
            { name: { contains: search, mode: "insensitive" } },
          ],
        },
        select: {
          id: true,
          username: true,
          name: true,
          avatarUrl: true,
          bio: true,
          isPrivate: true,
          createdAt: true,
          followers: {
            where: { followerId: currentUserId },
            select: { id: true },
          },
          following: {
            where: { followeeId: currentUserId },
            select: { id: true },
          },
        },
        orderBy: { createdAt: "desc" },
        take: limit,
      });

      users.push(...followedUsers);

      // 2. If limit not reached, search other users
      if (users.length < limit) {
        const remainingLimit = limit - users.length;
        const otherUsers = await prisma.user.findMany({
          where: {
            id: { not: currentUserId },
            NOT: {
              followers: {
                some: {
                  followerId: currentUserId,
                },
              },
            },
            OR: [
              { username: { contains: search, mode: "insensitive" } },
              { name: { contains: search, mode: "insensitive" } },
            ],
          },
          select: {
            id: true,
            username: true,
            name: true,
            avatarUrl: true,
            bio: true,
            isPrivate: true,
            createdAt: true,
            followers: {
              where: { followerId: currentUserId },
              select: { id: true },
            },
            following: {
              where: { followeeId: currentUserId },
              select: { id: true },
            },
          },
          orderBy: { createdAt: "desc" },
          skip: offset > 0 ? Math.max(0, offset - followedUsers.length) : 0,
          take: remainingLimit,
        });
        users.push(...otherUsers);
      }

      // Calculate total count for pagination
      const totalFollowed = await prisma.user.count({
        where: {
          id: { not: currentUserId },
          followers: { some: { followerId: currentUserId } },
          OR: [
            { username: { contains: search, mode: "insensitive" } },
            { name: { contains: search, mode: "insensitive" } },
          ],
        },
      });
      const totalOthers = await prisma.user.count({
        where: {
          id: { not: currentUserId },
          NOT: { followers: { some: { followerId: currentUserId } } },
          OR: [
            { username: { contains: search, mode: "insensitive" } },
            { name: { contains: search, mode: "insensitive" } },
          ],
        },
      });
      total = totalFollowed + totalOthers;
    } else {
      // Existing logic for general search or no search
      const whereClause: any = {
        id: { not: currentUserId },
      };
      if (search) {
        whereClause.OR = [
          { username: { contains: search, mode: "insensitive" } },
          { name: { contains: search, mode: "insensitive" } },
        ];
      }
      total = await prisma.user.count({ where: whereClause });
      users = await prisma.user.findMany({
        where: whereClause,
        select: {
          id: true,
          username: true,
          name: true,
          avatarUrl: true,
          bio: true,
          isPrivate: true,
          createdAt: true,
          followers: {
            where: { followerId: currentUserId },
            select: { id: true },
          },
          following: {
            where: { followeeId: currentUserId },
            select: { id: true },
          },
        },
        orderBy: { createdAt: "desc" },
        skip: offset,
        take: limit,
      });
    }

    // Transform to DTO
    const discoverUsers: DiscoverUserDto[] = users.map((user) => ({
      id: user.id,
      username: user.username || null,
      name: user.name || null,
      avatarUrl: user.avatarUrl || null,
      bio: user.bio || null,
      isPrivate: user.isPrivate,
      isFollowing: user.followers.length > 0,
      isFollowedBy: user.following.length > 0,
    }));

    const hasNext = offset + limit < total;

    const response: PaginatedResponse<DiscoverUserDto> = {
      items: discoverUsers,
      page,
      limit,
      total,
      hasNext,
    };

    return NextResponse.json<ApiResponse<PaginatedResponse<DiscoverUserDto>>>({
      success: true,
      data: response,
    });
  } catch (error: any) {
    console.error("Discover users error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
