export const CHIP_IN_CURRENCIES = ["INR", "USD"] as const;
export type ChipInCurrency = (typeof CHIP_IN_CURRENCIES)[number];

export const CHIP_IN_PRESETS: Record<ChipInCurrency, readonly number[]> = {
  INR: [50, 100, 200],
  USD: [5, 10, 20],
};

export const CHIP_IN_LIMITS: Record<ChipInCurrency, { min: number; max: number }> = {
  INR: { min: 10, max: 10000 },
  USD: { min: 1, max: 500 },
};

export const CHIP_IN_CURRENCY: ChipInCurrency = "INR";

export type ParsedChipIn =
  | { ok: true; amount: number; currency: ChipInCurrency; amountMinor: number }
  | { ok: false; error: string };

const NAME_MAX = 40;

export function chipInSymbol(currency: ChipInCurrency): string {
  return currency === "USD" ? "$" : "₹";
}

export function parseChipInCurrency(value: unknown): ChipInCurrency | null {
  if (typeof value !== "string") return null;
  const currency = value.trim().toUpperCase();
  return CHIP_IN_CURRENCIES.includes(currency as ChipInCurrency)
    ? (currency as ChipInCurrency)
    : null;
}

export function parseChipInName(input: unknown): string | null {
  const body = input && typeof input === "object" ? (input as Record<string, unknown>) : {};
  const raw = body.name;
  if (typeof raw !== "string") return null;
  const cleaned = raw.replace(/[\u0000-\u001F<>]/g, "").replace(/\s+/g, " ").trim();
  if (!cleaned) return null;
  return cleaned.slice(0, NAME_MAX);
}

export function publicSupporterNames(names: Array<string | null | undefined>, limit = 60): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of names) {
    if (typeof raw !== "string") continue;
    const name = raw.trim();
    if (!name) continue;
    const key = name.toLocaleLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(name);
    if (out.length >= limit) break;
  }
  return out;
}

export function parseChipInAmount(input: unknown): ParsedChipIn {
  const body = input && typeof input === "object" ? (input as Record<string, unknown>) : {};
  const currency = body.currency == null ? CHIP_IN_CURRENCY : parseChipInCurrency(body.currency);
  if (!currency) {
    return { ok: false, error: "Choose rupees or dollars." };
  }

  const raw = body.amount ?? (currency === "INR" ? body.amountRupees : undefined);
  const amount = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
  const symbol = chipInSymbol(currency);
  const { min, max } = CHIP_IN_LIMITS[currency];
  const unit = currency === "USD" ? "dollar" : "rupee";
  if (!Number.isInteger(amount)) {
    return { ok: false, error: `Choose a whole ${unit} amount.` };
  }
  if (amount < min || amount > max) {
    const maxLabel = currency === "INR" ? max.toLocaleString("en-IN") : String(max);
    return {
      ok: false,
      error: `Chip in between ${symbol}${min} and ${symbol}${maxLabel}.`,
    };
  }
  return { ok: true, amount, currency, amountMinor: amount * 100 };
}
