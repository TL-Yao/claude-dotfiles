import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm"],
  target: "node18",
  outDir: "dist",
  clean: true,
  // Don't bundle dependencies - they'll be in node_modules
  noExternal: [],
  banner: {
    js: '#!/usr/bin/env node',
  },
});
