# Expenses and settlements

Trip money is an in-app ledger. A member adds an expense, the server splits it into integer minor units, and anyone can mark a suggested transfer as paid. No card is charged. There is no Stripe, PayPal, Razorpay, or other payment provider in this repository. `context.json` lists "payment logging" as future scope. What shipped is the ledger described here.

Primary files:

- `src/lib/services/expense/expenseService.ts`
- `src/lib/services/expense/splitShares.ts`
- `src/lib/services/expense/netBalances.ts`
- `src/lib/services/expense/simplifyDebts.ts`
- `src/lib/services/expense/pairwise.ts`
- `src/lib/services/expense/assertZeroNet.ts`
- `src/lib/services/expense/constants.ts`
- Routes under `src/app/api/trips/[id]/expenses`, `settlements`, `expense-settings`
- Mobile: `expense_provider.dart`, `trip_money_pane.dart`, `add_expense_sheet.dart`

The Money pane is page 1 of a `PageView`. Page 0 is the thread (`trip_thread_screen.dart`).

## Amounts

Every amount is an integer in minor units. For `INR`, that is paise. `1.50` rupees is `150`. Floats are not stored.

| Bound | Value |
| --- | --- |
| `MIN_AMOUNT_MINOR` | 1 |
| `MAX_AMOUNT_MINOR` | 1,000,000,000 |
| Default currency | `INR` on `Trip.expenseCurrency` |
| Allowed currencies | `INR`, `USD`, `EUR`, `AED`, `GBP`, `SGD`, `AUD`, `CAD` (`EXPENSE_CURRENCIES`) |

`PATCH /api/trips/:id/expense-settings` is owner-only. It can set `expenseCurrency` until the first live expense exists, then the currency is frozen. It can set `spendVisibleOnDiscover` at any time.

`Trip.totalSpendMinor` is incremented when an expense is created and decremented when it is soft-deleted. Discover and the home feed do not re-sum the ledger to draw a total.

## Who is in the split

`tripMemberUserIds` is the owner (`Trip.userId`) plus every `TripParticipant.userId`. The owner is billed even though they have no `trip_participants` row. The participants API synthesizes that owner row for the client. The expense service uses the same set so the two stay aligned.

## Tables

`trip_expenses`: `payerId`, `createdById`, `title`, `category`, `amountMinor`, `currency`, `splitMethod`, `note`, `deletedAt`. Soft delete. Indexes `(tripId, createdAt)`, `(tripId, deletedAt)`, `(payerId)`.

`trip_expense_shares`: `shareMinor`, optional `weight`. Unique `(expenseId, userId)`.

`trip_settlements`: `fromUserId` (debtor), `toUserId` (creditor), `amountMinor`, `currency`, `status`, `recordedById`, `createdAt`. No `updatedAt`. The row is append-only. Index `(tripId, createdAt)` plus the two user ids.

`ExpenseCategory`: `FOOD`, `STAY`, `TRANSPORT`, `ACTIVITIES`, `SHOPPING`, `OTHER`.

`ExpenseSplitMethod`: `EQUAL`, `EXACT`, `PERCENT`, `SHARES`.

`TripSettlementStatus`: `PAID`, `PENDING`, `COMPLETED`, `FAILED`, `CANCELLED`, `DISPUTED`. The v1 write path inserts `PAID` only. Net math counts `PAID` and `COMPLETED` (`NET_COUNTING_STATUSES`). The other statuses exist so a later payment integration can record a failure without a migration. Nothing in the API writes them today.

## Splits

`splitShares.ts`.

| Method | Rule |
| --- | --- |
| `EQUAL` | `floor(total / n)` and the remainder is given one minor unit at a time to the lowest `userId`s, after sorting ids ascending. The same members always get the extra paise |
| `EXACT` | Caller supplies each share. The sum must equal `amountMinor` exactly |
| `PERCENT` | Basis points must sum to **10,000**. Then the same largest-remainder algorithm as shares |
| `SHARES` | Integer weights. Largest remainder. Tie on the remainder goes to the lower `userId` |

Example. `100` minor units, three people, ids sorting as A, B, C. Equal split is `34`, `33`, `33`. A is first in sorted order and receives the remainder. Re-running the split does not depend on map iteration order.

`createExpense` copies `trip.expenseCurrency` onto the row (the client does not pick a second currency), writes the shares, and adds `amountMinor` to `totalSpendMinor`.

## Nets

For each member, `netBalances.ts`:

```text
paidMinor    = sum of amountMinor where this user is the payer, expense not deleted
owedMinor    = sum of shareMinor for this user
settOutMinor = sum of PAID or COMPLETED settlements where this user is fromUserId
settInMinor  = sum of those settlements where this user is toUserId

netMinor     = paidMinor - owedMinor + settOutMinor - settInMinor
```

A positive net means the trip owes this person money. A negative net means this person owes the trip. `settOut` increases the debtor's net (they paid the debt down). `settIn` decreases the creditor's net (they received it).

The sum of `netMinor` across members is expected to be 0. The summary logs a mismatch rather than hiding it. A non-zero sum means a share or a settlement was written that does not balance, which the create path is supposed to make impossible.

## Simplify

`simplifyDebts.ts` greedily pairs the largest creditor with the largest debtor. Ties break on `userId` ascending, so the suggested transfer list is stable across requests. Each item is `{ fromUserId, toUserId, amountMinor }`. This is a minimized cash-flow, not the raw list of "A paid the hotel, B's share is X". Pairwise detail is still returned by the summary for the breakdown UI (`pairwise.ts`).

## Recording a payment

`POST /api/trips/:id/settlements`. **201**.

Only the payee (`toUserId`) may record it. Anyone else gets **403**. The product rule is "the person who was paid taps Mark as paid". The debtor does not get to clear their own debt in the app.

Inside a transaction the trip row is locked with `SELECT ... FOR UPDATE`. The amount must be at most `min(-fromNet, toNet)`, and it must equal one current edge from `simplifyDebts`. If the client submits a stale edge, the response is **409** telling them to refresh settle-up. That closes the race where two creditors mark overlapping transfers from the same snapshot.

`DELETE /api/trips/:id/settlements/:settlementId` exists and calls `undoSettlement`, which always throws `ConflictError`. Settlements are immutable. The summary returns `canUndo: false`. The mobile client still has an undo method so the UI can show the error rather than pretending the delete worked.

Once any `PAID` settlement exists on the trip, deleting an expense returns **409**. Shares are frozen because changing history would make the recorded payments not match the debts they settled.

## Guards that use the net

`assertZeroNet` throws `UnsettledBalanceError` (**409**, `code: UNSETTLED_BALANCE`, `meta.netMinor`) when `netMinor !== 0`.

Call sites:

- `POST /trips/:id/leave`
- `DELETE /trips/:id/participants`
- `DELETE /users/me`

You cannot walk away from a trip, be removed, or delete your account while your net is non-zero. Settle or be settled first.

## Visibility

`omitHiddenTripSpend` (`src/lib/tripSpendVisibility.ts`) removes `totalSpendMinor` from a trip payload unless the viewer is a member or `spendVisibleOnDiscover` is true.

Discover always passes `viewerIsMember: false`, so a discover card shows spend only when the owner opted in. Home feed and live trips compute membership and pass the real flag. The Money pane itself is members-only because the expense routes require membership.

## HTTP

| Method | Path | Notes |
| --- | --- | --- |
| `GET`, `POST` | `/api/trips/:id/expenses` | List is paginated. Create returns the expense and its shares |
| `DELETE` | `/api/trips/:id/expenses/:expenseId` | Soft delete. 409 after any paid settlement |
| `GET` | `/api/trips/:id/expenses/summary` | Nets, open transfers, pairwise, recorded settlements |
| `POST` | `/api/trips/:id/settlements` | Payee only |
| `DELETE` | `/api/trips/:id/settlements/:id` | Always 409 |
| `PATCH` | `/api/trips/:id/expense-settings` | Owner. Currency lock, discover flag |

## Mobile

`ExpenseProvider` loads the summary and the expense page in parallel. `markPaid` posts a settlement. `TripMoneyPane` shows `myNetMinor` as the headline and one row per open transfer, with Mark as paid only when `canMarkPaid` is true (the viewer is the payee).

`expense_summary_test.dart` and `trip_money_pane_test.dart` cover the net sign and the payee-only button.
