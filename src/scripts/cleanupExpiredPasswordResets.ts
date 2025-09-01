import { cleanupExpiredResets } from "@/lib/services/passwordReset";

(async () => {
  await cleanupExpiredResets();
  console.log("Cleanup complete");
  process.exit(0);
})();