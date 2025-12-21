import { describe, it, expect, beforeEach } from "vitest";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser, createTrip } from "../testUtils";
import { runConcurrentCalls } from "./concurrencyHelper";
import { TripInvitationService } from "../../src/lib/tripInvitation";

// Stress tests: run many parallel requests and assert DB invariants (<=1 per unique key)

describe("Stress tests - concurrency", () => {
    beforeEach(async () => {
        await cleanDb();
    });

    it("stress: 100x parallel follow requests (3 rounds)", { timeout: 120_000 }, async () => {
        const a = await createUser();
        const b = await createUser();

        async function attemptFollow() {
            try {
                const result = await prisma.$transaction(async (tx) => {
                    const [follower, followee] = await Promise.all([
                        tx.user.findUnique({ where: { id: a.id } }),
                        tx.user.findUnique({ where: { id: b.id } }),
                    ]);
                    if (!follower || !followee) return { code: "NOT_FOUND" };
                    if (a.id === b.id) return { code: "SELF_FOLLOW" };

                    const existingFollow = await tx.follow.findFirst({ where: { followerId: a.id, followeeId: b.id } });
                    if (existingFollow) return { code: "ALREADY_FOLLOW" };

                    const existingRequest = await tx.followRequest.findFirst({ where: { followerId: a.id, followeeId: b.id, status: "PENDING" } });
                    if (existingRequest) return { code: "PENDING", request: existingRequest };

                    const request = await tx.followRequest.create({ data: { followerId: a.id, followeeId: b.id, status: "PENDING" } });
                    return { code: "CREATED", request };
                });
                return { ok: true, result };
            } catch (error: any) {
                // Return error metadata so the caller can inspect without failing the whole batch
                return { ok: false, code: error?.code ?? null, error };
            }
        }

        const rounds = 3;
        const concurrency = 100;
        const results = await runConcurrentCalls(() => attemptFollow(), concurrency, rounds);
        const flat = results.flat();

        // DB invariant: at most one followRequest for the pair
        const count = await prisma.followRequest.count({ where: { followerId: a.id, followeeId: b.id } });
        expect(count).toBeLessThanOrEqual(1);

        // No unexpected errors: only allow P2002 unique constraint (race) or expected codes
        const unexpected = flat.filter((r: any) => !r.ok && r.code !== "P2002");
        expect(unexpected.length).toBe(0);
    });

    it("stress: 100x parallel trip invites (3 rounds)", { timeout: 120_000 }, async () => {
        const owner = await createUser();
        const receiver = await createUser();
        const trip = await createTrip({ userId: owner.id });

        async function attemptInvite() {
            try {
                const res = await TripInvitationService.sendInvitation(trip.id, owner.id, receiver.id);
                return { ok: true, res };
            } catch (error: any) {
                return { ok: false, code: error?.code ?? null, error };
            }
        }

        const rounds = 3;
        const concurrency = 100;
        const results = await runConcurrentCalls(() => attemptInvite(), concurrency, rounds);
        const flat = results.flat();

        // DB invariant: at most one tripJoinRequest for the pair
        const count = await prisma.tripJoinRequest.count({ where: { tripId: trip.id, receiverId: receiver.id } });
        expect(count).toBeLessThanOrEqual(1);

        // No unexpected errors: TripInvitationService handles P2002 internally, but tolerate it if thrown
        const unexpected = flat.filter((r: any) => !r.ok && r.code !== "P2002");
        expect(unexpected.length).toBe(0);
    });
});
