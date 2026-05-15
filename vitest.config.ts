import { defineConfig } from "vitest/config";
import path from "path";

// Set NODE_ENV=test BEFORE any imports to ensure test mode is active
// This prevents env.ts from loading production environment
if (!process.env.NODE_ENV) {
  (process.env as any).NODE_ENV = 'test';
}

export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    include: [
      "tests/**/*.test.ts",
      "scheduler/tests/**/*.test.ts",
      "src/app/test/**/*.test.ts",
    ],
    setupFiles: ["./tests/setupTests.ts"],
    // Run test files serially to avoid transaction isolation issues
    fileParallelism: false, // Disable parallel file execution
    maxConcurrency: 1,       // Only one test file at a time
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
    },
  },
});
