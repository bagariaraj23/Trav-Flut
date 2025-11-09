import { prisma } from "@/lib/prisma";

export async function revokeAllRefreshTokens(userId: string) {
  await prisma.jWTRefreshToken.deleteMany({ where: { userId } });
}