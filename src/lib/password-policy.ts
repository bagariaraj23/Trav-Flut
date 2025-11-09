import { z } from "zod";

export const passwordPolicy = z
  .string()
  .min(8, "Password must be at least 8 characters")
  .max(128, "Password must be less than 128 characters")
  .regex(
    /^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).*$/,
    "Password must contain at least one lowercase letter, one uppercase letter, and one number"
  );