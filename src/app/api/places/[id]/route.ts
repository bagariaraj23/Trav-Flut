import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { ApiResponse } from "@/types/api";

export async function GET(
  _req: NextRequest,
  { params }: { params: { id: string } }
) {
  const place = await prisma.place.findUnique({ where: { id: params.id } });
  if (!place)
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Not found" },
      { status: 404 }
    );
  return NextResponse.json<ApiResponse>({ success: true, data: place });
}
