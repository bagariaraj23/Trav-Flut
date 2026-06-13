/**
 * Guards tooling (Vitest, seed script, setup scripts) so Postgres targets only
 * databases intentionally named as test databases — never production.
 */

/** PostgreSQL database segment from `postgresql://…/dbname` or `postgres://…/dbname`. */
export function extractPostgresDatabaseName(databaseUrl: string): string | null {
  const trimmed = databaseUrl.trim();
  if (!trimmed) return null;
  if (!/^postgres(ql)?:\/\//i.test(trimmed)) return null;
  try {
    const parsed = new URL(trimmed.replace(/^postgres(ql)?:/i, "http:"));
    const db = parsed.pathname.replace(/^\//, "").split("?")[0]?.trim();
    return db || null;
  } catch {
    return null;
  }
}

/** Allowed only when the logical DB name ends with `_test` (e.g. `tripthread_test`). */
export function isAllowedTestDatabaseName(dbName: string): boolean {
  return dbName.toLowerCase().endsWith("_test");
}

export function assertTestDatabaseUrl(
  url: string | undefined,
  label: string
): asserts url is string {
  if (!url?.trim()) {
    throw new Error(
      `${label}: TEST_DATABASE_URL is missing. Configure .env.test with a Postgres URL whose database name ends with "_test" (e.g. tripthread_test).`
    );
  }
  const name = extractPostgresDatabaseName(url);
  if (!name) {
    throw new Error(
      `${label}: could not parse database name from the connection URL (expected postgres:// or postgresql://).`
    );
  }
  if (!isAllowedTestDatabaseName(name)) {
    throw new Error(
      `${label}: refusing "${name}" — database name must end with "_test" so production is never targeted.`
    );
  }
}
