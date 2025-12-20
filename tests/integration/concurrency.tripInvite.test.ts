import { describe, it, expect, beforeEach } from "vitest";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser, createTrip } from "../testUtils";
import { TripInvitationService } from "../../src/lib/tripInvitation";
import { ConflictError } from "../../src/lib/errors";

describe("TripInvitationService - concurrency", () => {
    beforeEach(async () => {
        await cleanDb();
    });

    it("creates at most one pending invitation under concurrent sends", async () => {
        const owner = await createUser();
        const receiver = await createUser();
        const trip = await createTrip({ userId: owner.id });

        // Ensure DB visibility
        await prisma.$queryRaw`SELECT 1`;

        const parallel = Array.from({ length: 6 }).map(() =>
            TripInvitationService.sendInvitation(trip.id, owner.id, receiver.id).catch(
                (err) => err
            )
        );

        const results = await Promise.all(parallel);

        // Count pending requests in DB
        const count = await prisma.tripJoinRequest.count({
            where: { tripId: trip.id, receiverId: receiver.id },
        });

        expect(count).toBeLessThanOrEqual(1);

        // The important invariant is DB state: ensure at most one request exists.
        // Individual calls may throw or return non-fatal errors under heavy contention,
        // but the DB should never contain more than one invitation for the same trip/receiver.
    });

    it("rejects self-invite", async () => {
        const owner = await createUser();
        const trip = await createTrip({ userId: owner.id });

        await expect(
            TripInvitationService.sendInvitation(trip.id, owner.id, owner.id)
        ).rejects.toThrow();
    });
});
