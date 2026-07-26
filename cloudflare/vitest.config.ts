import { defineConfig } from "vitest/config";

// Without an explicit config here vitest walks up and loads the Tauri app's
// React config, which has nothing to do with these pure validator tests.
export default defineConfig({
  test: { environment: "node", include: ["src/**/*.test.ts"] },
});
