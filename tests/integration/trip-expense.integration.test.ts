import { beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { TripStatus } from "@prisma/client";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createTrip, createUser, getAuthToken } from "../testUtils";
import {
  GET as getExpensesRoute,
  POST as createExpenseRoute,
} from "../../src/app/api/trips/[id]/expenses/route";
import { GET as getSummaryRoute } from "../../src/app/api/trips/[id]/expenses/summary/route";
import { DELETE as deleteExpenseRoute } from "../../src/app/api/trips/[id]/expenses/[expenseId]/route";
import { POST as createSettlementRoute } from "../../src/app/api/trips/[id]/settlements/route";
import { DELETE as deleteSettlementRoute } from "../../src/app/api/trips/[id]/settlements/[settlementId]/route";
import { PATCH as patchSettingsRoute } from "../../src/app/api/trips/[id]/expense-settings/route";
import { POST as leaveTripRoute } from "../../src/app/api/trips/[id]/leave/route";
import { DELETE as removeParticipantRoute } from "../../src/app/api/trips/[id]/participants/route";
import { DELETE as deleteMeRoute } from "../../src/app/api/users/me/route";

function authRequest(
  url: string,
  method: string,
  token?: string,
  body?: unknown
): NextRequest {
  const headers = new Headers();
  headers.set("Content-Type", "application/json");
  if (token) headers.set("authorization", `Bearer ${token}`);
  return new NextRequest(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function json(response: Response) {
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

async function addParticipant(tripId: string, userId: string) {
  await prisma.tripParticipant.create({
    data: { tripId, userId },
  });
  await prisma.trip.update({
    where: { id: tripId },
    data: { participantCount: { increment: 1 } },
  });
}

describe("Trip expense ledger", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("creates, lists, and summarizes an equal split among a subset of members", async () => {
    const owner = await createUser({ email: "exp-owner@test.com", name: "Owner" });
    const a = await createUser({ email: "exp-a@test.com", name: "Alice" });
    const b = await createUser({ email: "exp-b@test.com", name: "Bob" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    await addParticipant(trip.id, a.id);
    await addParticipant(trip.id, b.id);
    const token = await getAuthToken(a);

    const createRes = await createExpenseRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", token, {
        title: "Car Rental",
        category: "TRANSPORT",
        amountMinor: 30000,
        payerId: a.id,
        splitMethod: "EQUAL",
        memberIds: [a.id, owner.id],
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const created = await json(createRes);
    expect(createRes.status).toBe(201);
    expect(created.data.shares).toHaveLength(2);
    expect(created.data.shares.every((s: { shareMinor: number }) => s.shareMinor === 15000)).toBe(
      true
    );

    const listRes = await getExpensesRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "GET", token),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const list = await json(listRes);
    expect(listRes.status).toBe(200);
    expect(list.data.items).toHaveLength(1);

    const summaryRes = await getSummaryRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses/summary`, "GET", token),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const summary = await json(summaryRes);
    expect(summaryRes.status).toBe(200);
    expect(summary.data.totalSpendMinor).toBe(30000);
    expect(summary.data.myNetMinor).toBe(15000);
    const ownerNet = summary.data.members.find((m: { userId: string }) => m.userId === owner.id);
    expect(ownerNet.netMinor).toBe(-15000);
    expect(summary.data.openTransfers).toEqual([
      expect.objectContaining({
        fromUserId: owner.id,
        toUserId: a.id,
        amountMinor: 15000,
        canMarkPaid: true,
      }),
    ]);
  });

  it("rejects non-members and still allows expenses after the trip has ended", async () => {
    const owner = await createUser({ email: "ended-owner@test.com" });
    const stranger = await createUser({ email: "ended-stranger@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ENDED });
    const ownerToken = await getAuthToken(owner);
    const strangerToken = await getAuthToken(stranger);

    const denied = await createExpenseRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", strangerToken, {
        title: "Snacks",
        category: "FOOD",
        amountMinor: 1000,
        payerId: stranger.id,
        splitMethod: "EQUAL",
        memberIds: [stranger.id],
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(denied.status).toBe(403);

    const allowed = await createExpenseRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", ownerToken, {
        title: "Snacks",
        category: "FOOD",
        amountMinor: 1000,
        payerId: owner.id,
        splitMethod: "EQUAL",
        memberIds: [owner.id],
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(allowed.status).toBe(201);
  });

  it("lets only the payee mark a simplified transfer paid, rejects the payer, and supports undo", async () => {
    const owner = await createUser({ email: "payee-owner@test.com" });
    const member = await createUser({ email: "payee-member@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    await addParticipant(trip.id, member.id);
    const ownerToken = await getAuthToken(owner);
    const memberToken = await getAuthToken(member);

    await createExpenseRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", memberToken, {
        title: "Dinner",
        category: "FOOD",
        amountMinor: 20000,
        payerId: member.id,
        splitMethod: "EQUAL",
        memberIds: [member.id, owner.id],
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );

    const payerTry = await createSettlementRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/settlements`, "POST", ownerToken, {
        fromUserId: owner.id,
        toUserId: member.id,
        amountMinor: 10000,
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(payerTry.status).toBe(403);

    const paid = await createSettlementRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/settlements`, "POST", memberToken, {
        fromUserId: owner.id,
        toUserId: member.id,
        amountMinor: 10000,
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const paidBody = await json(paid);
    expect(paid.status).toBe(201);

    const stale = await createSettlementRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/settlements`, "POST", memberToken, {
        fromUserId: owner.id,
        toUserId: member.id,
        amountMinor: 10000,
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(stale.status).toBe(409);

    const summaryPaid = await json(
      await getSummaryRoute(
        authRequest(`http://localhost/api/trips/${trip.id}/expenses/summary`, "GET", memberToken),
        { params: Promise.resolve({ id: trip.id }) }
      )
    );
    expect(summaryPaid.data.openTransfers).toEqual([]);
    expect(summaryPaid.data.myNetMinor).toBe(0);

    const undoBlocked = await deleteSettlementRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/settlements/${paidBody.data.id}`,
        "DELETE",
        memberToken
      ),
      { params: Promise.resolve({ id: trip.id, settlementId: paidBody.data.id }) }
    );
    expect(undoBlocked.status).toBe(409);
  });

  it("records only one settlement when mark-paid is submitted twice at once", async () => {
    const owner = await createUser({ email: "race-owner@test.com" });
    const member = await createUser({ email: "race-member@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    await addParticipant(trip.id, member.id);
    const memberToken = await getAuthToken(member);

    await createExpenseRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", memberToken, {
        title: "Dinner",
        category: "FOOD",
        amountMinor: 20000,
        payerId: member.id,
        splitMethod: "EQUAL",
        memberIds: [member.id, owner.id],
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );

    const body = {
      fromUserId: owner.id,
      toUserId: member.id,
      amountMinor: 10000,
    };
    const [first, second] = await Promise.all([
      createSettlementRoute(
        authRequest(`http://localhost/api/trips/${trip.id}/settlements`, "POST", memberToken, body),
        { params: Promise.resolve({ id: trip.id }) }
      ),
      createSettlementRoute(
        authRequest(`http://localhost/api/trips/${trip.id}/settlements`, "POST", memberToken, body),
        { params: Promise.resolve({ id: trip.id }) }
      ),
    ]);

    expect([first.status, second.status].sort()).toEqual([201, 409]);
    expect(await prisma.tripSettlement.count({ where: { tripId: trip.id } })).toBe(1);
  });

  it("blocks leave and kick while net is non-zero, then allows leave after delete", async () => {
    const owner = await createUser({ email: "leave-exp-owner@test.com" });
    const member = await createUser({ email: "leave-exp-member@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    await addParticipant(trip.id, member.id);
    const ownerToken = await getAuthToken(owner);
    const memberToken = await getAuthToken(member);

    const created = await json(
      await createExpenseRoute(
        authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", memberToken, {
          title: "Stay",
          category: "STAY",
          amountMinor: 40000,
          payerId: member.id,
          splitMethod: "EQUAL",
          memberIds: [member.id, owner.id],
        }),
        { params: Promise.resolve({ id: trip.id }) }
      )
    );

    const leaveBlocked = await leaveTripRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/leave`, "POST", memberToken, {
        removeMyData: false,
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(leaveBlocked.status).toBe(409);

    const kickBlocked = await removeParticipantRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/participants?userId=${member.id}`,
        "DELETE",
        ownerToken
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(kickBlocked.status).toBe(409);

    const deleted = await deleteExpenseRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/expenses/${created.data.id}`,
        "DELETE",
        memberToken
      ),
      { params: Promise.resolve({ id: trip.id, expenseId: created.data.id }) }
    );
    expect(deleted.status).toBe(200);

    const leaveOk = await leaveTripRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/leave`, "POST", memberToken, {
        removeMyData: false,
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(leaveOk.status).toBe(200);
  });

  it("decrements trip spend once when the same expense is deleted twice", async () => {
    const owner = await createUser({ email: "del-twice-owner@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    const token = await getAuthToken(owner);

    const created = await json(
      await createExpenseRoute(
        authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", token, {
          title: "Dinner",
          category: "FOOD",
          amountMinor: 8000,
          payerId: owner.id,
          splitMethod: "EQUAL",
          memberIds: [owner.id],
        }),
        { params: Promise.resolve({ id: trip.id }) }
      )
    );
    const expenseId = created.data.id as string;
    const deleteOnce = () =>
      deleteExpenseRoute(
        authRequest(
          `http://localhost/api/trips/${trip.id}/expenses/${expenseId}`,
          "DELETE",
          token
        ),
        { params: Promise.resolve({ id: trip.id, expenseId }) }
      );

    const [first, second] = await Promise.all([deleteOnce(), deleteOnce()]);
    expect([first.status, second.status].sort()).toEqual([200, 404]);

    const again = await deleteOnce();
    expect(again.status).toBe(404);

    const stored = await prisma.trip.findUnique({
      where: { id: trip.id },
      select: { totalSpendMinor: true },
    });
    expect(stored?.totalSpendMinor).toBe(0);
    expect(
      await prisma.tripExpense.count({
        where: { id: expenseId, deletedAt: null },
      })
    ).toBe(0);
  });

  it("freezes currency after the first live expense", async () => {
    const owner = await createUser({ email: "fx-owner@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.UPCOMING });
    const token = await getAuthToken(owner);

    const setUsd = await patchSettingsRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expense-settings`, "PATCH", token, {
        expenseCurrency: "USD",
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(setUsd.status).toBe(200);

    await createExpenseRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", token, {
        title: "Tickets",
        category: "ACTIVITIES",
        amountMinor: 5000,
        payerId: owner.id,
        splitMethod: "EQUAL",
        memberIds: [owner.id],
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );

    const locked = await patchSettingsRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expense-settings`, "PATCH", token, {
        expenseCurrency: "INR",
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(locked.status).toBe(409);
  });

  it("blocks account delete while the user has an unpaid trip net", async () => {
    const owner = await createUser({ email: "del-exp-owner@test.com" });
    const member = await createUser({ email: "del-exp-member@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    await addParticipant(trip.id, member.id);
    const memberToken = await getAuthToken(member);

    await createExpenseRoute(
      authRequest(`http://localhost/api/trips/${trip.id}/expenses`, "POST", memberToken, {
        title: "Fuel",
        category: "TRANSPORT",
        amountMinor: 20000,
        payerId: owner.id,
        splitMethod: "EQUAL",
        memberIds: [member.id, owner.id],
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );

    const blocked = await deleteMeRoute(
      authRequest("http://localhost/api/users/me", "DELETE", memberToken)
    );
    expect(blocked.status).toBe(409);
    const body = await json(blocked);
    expect(body.code ?? body.meta?.code).toBe("UNSETTLED_BALANCE");
  }, 15_000);
});
