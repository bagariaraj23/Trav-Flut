export const CHIP_IN_PRESETS = [50, 100, 200] as const;
export const CHIP_IN_MIN_RUPEES = 10;
export const CHIP_IN_MAX_RUPEES = 10000;
export const CHIP_IN_CURRENCY = "INR";

export type ParsedChipIn =
  | { ok: true; rupees: number; amountMinor: number }
  | { ok: false; error: string };

const NAME_MAX = 40;

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
  const raw = body.amountRupees;
  const rupees = typeof raw === "number" ? raw : typeof raw === "string" ? Number(raw) : NaN;
  if (!Number.isInteger(rupees)) {
    return { ok: false, error: "Choose a whole rupee amount." };
  }
  if (rupees < CHIP_IN_MIN_RUPEES || rupees > CHIP_IN_MAX_RUPEES) {
    return {
      ok: false,
      error: `Chip in between ₹${CHIP_IN_MIN_RUPEES} and ₹${CHIP_IN_MAX_RUPEES.toLocaleString("en-IN")}.`,
    };
  }
  return { ok: true, rupees, amountMinor: rupees * 100 };
}
