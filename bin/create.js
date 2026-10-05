#!/usr/bin/env node

/**
 * Argon
 *
 * Usage:
 *   npx @mksd0398/argon my-store-app
 *   argon my-store-app          (once installed)
 */

import { run } from "../lib/index.js";

run(process.argv.slice(2)).catch((err) => {
  console.error("\n\x1b[31mError:\x1b[0m", err.message);
  process.exit(1);
});
