import fs from "fs";
import path from "path";
import { describe, expect, it } from "vitest";

const API_ROOT = path.resolve(process.cwd(), "src/app/api");
const HTTP_METHOD_EXPORT = /export\s+(?:async\s+)?function\s+(GET|POST|PUT|PATCH|DELETE)\b|export\s+const\s+(GET|POST|PUT|PATCH|DELETE)\b/;

function collectRouteFiles(dir: string): string[] {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectRouteFiles(fullPath));
    } else if (entry.isFile() && entry.name === "route.ts") {
      files.push(fullPath);
    }
  }

  return files.sort();
}

describe("Next.js API route contracts", () => {
  it("keeps every src/app/api route.ts file backed by at least one HTTP method export", () => {
    const routeFiles = collectRouteFiles(API_ROOT);

    expect(routeFiles.length).toBeGreaterThanOrEqual(70);

    const missingHandlers = routeFiles
      .map((file) => ({
        route: path.relative(API_ROOT, path.dirname(file)),
        source: fs.readFileSync(file, "utf8"),
      }))
      .filter(({ source }) => !HTTP_METHOD_EXPORT.test(source))
      .map(({ route }) => route);

    expect(missingHandlers).toEqual([]);
  });
});
