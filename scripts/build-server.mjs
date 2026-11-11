import * as esbuild from "esbuild";
import { mkdirSync, existsSync } from "fs";
import { dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outDir = "dist";
if (!existsSync(outDir)) mkdirSync(outDir, { recursive: true });

// Bundle only chat-ws and its deps; main server runs from server.js (plain Node)
await esbuild.build({
  entryPoints: ["src/lib/chat-ws.ts"],
  bundle: true,
  platform: "node",
  format: "cjs",
  outfile: `${outDir}/chat-ws.cjs`,
  external: ["next", "ws"],
  plugins: [
    {
      name: "external-next-subpaths",
      setup(build) {
        build.onResolve({ filter: /^next\// }, (args) => ({ path: args.path, external: true }));
      },
    },
  ],
  alias: { "@": "./src" },
  sourcemap: true,
  target: "node18",
});

console.log("> Chat WS built to dist/chat-ws.cjs");
