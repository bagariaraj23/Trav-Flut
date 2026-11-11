import { UnsettledBalanceError } from "@/lib/errors";
import { prisma, PrismaTransactionClient } from "@/lib/prisma";
import { computeMemberNets } from "./netBalances";

export { UnsettledBalanceError };

type DbClient = PrismaTransactionClient | typeof prisma;

export async function getUserNetOnTrip(
  tripId: string,
  userId: string,
  memberIds: string[],
  client: DbClient = prisma
): Promise<number> {
  const nets = await computeMemberNets(tripId, memberIds, client);
  return nets.get(userId)?.netMinor ?? 0;
}

export async function assertZeroNet(
  tripId: string,
  userId: string,
  memberIds: string[],
  client: DbClient = prisma
): Promise<void> {
  const net = await getUserNetOnTrip(tripId, userId, memberIds, client);
  if (net !== 0) {
    throw new UnsettledBalanceError(net);
  }
}
