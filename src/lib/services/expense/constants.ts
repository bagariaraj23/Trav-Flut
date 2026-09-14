export const EXPENSE_CURRENCIES = [
  "INR",
  "USD",
  "EUR",
  "AED",
  "GBP",
  "SGD",
  "AUD",
  "CAD",
] as const;

export type ExpenseCurrency = (typeof EXPENSE_CURRENCIES)[number];

export const DEFAULT_EXPENSE_CURRENCY: ExpenseCurrency = "INR";

/** ₹1 crore in paise (fits Prisma Int). */
export const MAX_AMOUNT_MINOR = 1_000_000_000;

export const MIN_AMOUNT_MINOR = 1;

export const TITLE_MAX_LENGTH = 80;

export const NOTE_MAX_LENGTH = 500;

export const NET_COUNTING_STATUSES = ["PAID", "COMPLETED"] as const;

export function isExpenseCurrency(value: string): value is ExpenseCurrency {
  return (EXPENSE_CURRENCIES as readonly string[]).includes(value);
}
