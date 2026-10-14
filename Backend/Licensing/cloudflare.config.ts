import { readFileSync } from "node:fs";
import { join } from "node:path";
import { bindings, defineConfig, triggers } from "cf/config";

// The D1 ID lives in package.json so the migration scripts and local dev share one database.
// Replace the placeholder with the real ID when provisioning (Docs/Payments/Licensing.md).
const packageJson = JSON.parse(readFileSync(join(import.meta.dirname, "package.json"), "utf8"));
const d1DatabaseId: string = packageJson.config.d1DatabaseId;

export default defineConfig({
  worker: {
    name: "primary-paste-licensing",
    entrypoint: "src/index.ts",
    compatibilityDate: "2026-08-13",
    compatibilityFlags: ["nodejs_compat"],
    observability: { enabled: true },
    triggers: [triggers.scheduled({ schedule: "0 * * * *" })],
    // Plain string types, not literals, so code can compare against values set at deploy time.
    env: {
      DB: bindings.d1({ id: d1DatabaseId, name: "primary-paste-licensing" }),
      APP_ORIGIN: bindings.text<string>("https://primarypaste.example"),
      STRIPE_PRICE_ID: bindings.text<string>("REPLACE_WITH_STRIPE_PRICE_ID"),
      STRIPE_AUTOMATIC_TAX_ENABLED: bindings.text<string>("false"),
      TAX_REGISTRATION_CONFIRMED: bindings.text<string>("false"),
      MAX_ACTIVATIONS: bindings.text<string>("3"),
    },
  },
});
