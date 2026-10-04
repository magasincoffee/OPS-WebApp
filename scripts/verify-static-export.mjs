import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const failures = [];

function assert(condition, message) {
  if (!condition) failures.push(message);
}

function walk(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

const appDir = path.join(root, "app");
const outDir = path.join(root, "out");
const appFiles = walk(appDir);
const outFiles = walk(outDir);
const productionSource = appFiles
  .filter((file) => /\.(ts|tsx|js|jsx)$/.test(file))
  .map((file) => fs.readFileSync(file, "utf8"))
  .join("\n");

assert(fs.existsSync(path.join(outDir, "index.html")), "out/index.html is missing");
assert(
  !appFiles.some((file) => file.endsWith("route.ts") || file.endsWith("route.js")),
  "production app still contains Next route handlers",
);
assert(!productionSource.includes("next/headers"), "production app imports next/headers");
assert(!productionSource.includes("/api/"), "production app still depends on /api routes");
assert(!productionSource.includes("SUPABASE_SERVICE_ROLE"), "production app references service-role credentials");
assert(
  !outFiles.some((file) => file.includes(`${path.sep}_next${path.sep}server${path.sep}`)),
  "static artifact unexpectedly contains a Next server bundle",
);

const indexHtml = fs.existsSync(path.join(outDir, "index.html"))
  ? fs.readFileSync(path.join(outDir, "index.html"), "utf8")
  : "";
assert(indexHtml.includes("_next/static"), "index.html does not reference static Next assets");

if (failures.length > 0) {
  console.error("STATIC EXPORT VERIFY: FAIL");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("STATIC EXPORT VERIFY: PASS");
console.log("- client-only production app");
console.log("- no route handlers or /api dependency");
console.log("- no Next server bundle in out/");
