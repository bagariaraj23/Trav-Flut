import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as {
  prisma: ReturnType<typeof createPrismaWithRetry> | undefined;
};

function isConnectionClosedError(e: unknown): boolean {
  if (!e || typeof e !== "object") return false;
  const msg = (e as Error).message ?? "";
  const code = (e as { code?: string }).code ?? "";
  return (
    msg.includes("Closed") ||
    msg.includes("connection closed") ||
    code === "P1001" ||
    code === "P1017"
  );
}

function createPrismaWithRetry() {
  const base = new PrismaClient({
    log:
      process.env.NODE_ENV === "development"
        ? ["query", "error", "warn"]
        : ["error"],
  });

  const extended = base.$extends({
    name: "reconnect-on-closed",
    query: {
      $allOperations({ operation, model, args, query }) {
        return query(args).catch(async (e: unknown) => {
          if (!isConnectionClosedError(e)) throw e;
          try {
            await base.$connect();
            return query(args);
          } catch (retryErr) {
            throw retryErr;
          }
        });
      },
    },
  });

  return { base, client: extended };
}

let created = globalForPrisma.prisma;
if (!created) {
  created = createPrismaWithRetry();
  if (process.env.NODE_ENV !== "production") {
    globalForPrisma.prisma = created;
  }
}
const prismaBase = created.base;
const prismaClient = created.client;

// Connection will be tested by startup logger
prismaBase
  .$connect()
  .then(() => {})
  .catch((e) => {
    console.error(
      "Database connection error (will be logged by startup logger):",
      e
    );
  });

export const prisma = prismaClient;
