import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const pagePath = path.join(root, "app", "page.tsx");
const cssPath = path.join(root, "app", "globals.css");
const failures = [];

function expect(source, token, label) {
  if (!source.includes(token)) failures.push(label);
}

const page = fs.readFileSync(pagePath, "utf8");
const css = fs.readFileSync(cssPath, "utf8");

expect(page, 'className="app-shell"', "consistent application shell missing");
expect(page, 'className={mobileNavOpen ? "sidebar sidebar-open" : "sidebar"}', "collapsible mobile navigation missing");
expect(page, 'className="app-topbar"', "compact application topbar missing");
expect(page, 'className="breadcrumbs"', "breadcrumb region missing");
expect(page, 'className="panel-toolbar"', "table/filter toolbar pattern missing");
expect(page, 'className="data-table"', "standard data-table pattern missing");
expect(page, 'className="state-block"', "loading/empty state pattern missing");
expect(page, 'visibleModules = useMemo', "role-aware navigation derivation missing");
expect(page, 'hasAnyRole(roles, module.roles)', "role-aware navigation filter missing");

expect(css, ".app-shell", "application shell styles missing");
expect(css, ".sidebar.sidebar-open", "mobile sidebar open state missing");
expect(css, ".table-wrap", "overflow-safe table wrapper missing");
expect(css, ".status-badge", "standard status badge styles missing");
expect(css, ".alert-danger", "standard alert styles missing");
expect(css, ".state-block", "standard state styles missing");
expect(css, "@media (max-width: 820px)", "mobile responsive breakpoint missing");

if (failures.length > 0) {
  console.error("TABLER UI CONTRACT: FAIL");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("TABLER UI CONTRACT: PASS");
console.log("- consistent desktop shell and compact topbar");
console.log("- grouped role-aware navigation with mobile collapse");
console.log("- breadcrumb/action, table/filter, alert, loading and empty-state patterns");
console.log("- responsive overflow-safe mobile layout");
