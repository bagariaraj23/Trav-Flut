export const CHIP_IN_PRESETS = [50, 100, 200] as const;
export const CHIP_IN_MIN_RUPEES = 10;
export const CHIP_IN_MAX_RUPEES = 10000;
export const CHIP_IN_CURRENCY = "INR";

export type ParsedChipIn =
  | { ok: true; rupees: number; amountMinor: number }
  | { ok: false; error: string };

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
