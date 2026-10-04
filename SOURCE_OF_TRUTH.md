# OPS WebApp — SOURCE OF TRUTH

> **Project ID:** OPS-WEBAPP  
> **Repository:** `magasincoffee/OPS-WebApp`  
> **Architecture Generation:** 4  
> **SOT Version:** 1.0  
> **Status:** ARCHITECTURE_LOCKED / IMPLEMENTATION_IN_PROGRESS  
> **Last authoritative update:** 2026-10-04  
> **Default branch:** `main`

---

## 0. Authority Rules

This file is the **single authoritative Source of Truth (SOT)** for the OPS WebApp project.

For every new ChatGPT conversation, agent session, implementation task, review, or handoff:

1. Read this file **from the beginning** before deciding or implementing anything.
2. Treat this SOT as the sole authority for:
   - project scope;
   - architecture;
   - business rules;
   - module boundaries;
   - implementation state;
   - task status;
   - dependencies;
   - migration rules.
3. Ignore stale chat history, memory, README files, old plans, screenshots, or historical assumptions when they conflict with this SOT.
4. Do not silently change architecture. Any material architectural or business-rule change must first be reflected in this file and must increment **Architecture Generation**.
5. After completing a material implementation task, update the corresponding task status in this SOT.
6. If repository code conflicts with the SOT, stop and reconcile the conflict before continuing.
7. The project is **independent from MAGASIN Coffee**. Do not couple authentication, database, roles, data, deployment, or business logic to MAGASIN Coffee unless a future SOT generation explicitly changes this rule.

---

# 1. Product Definition

OPS WebApp replaces the current spreadsheet-based operating system used for:

- supplier purchasing;
- goods receiving;
- product master data;
- customer master data;
- cost calculation;
- sales pricing;
- quotations;
- customer orders;
- print-production jobs;
- warehouse reservation and stock movements;
- delivery preparation;
- customer payments;
- customer receivables;
- operational task assignment;
- management reporting.

The current spreadsheets are migration sources only. They must not remain the long-term operational database after production cutover.

## 1.1 Existing Migration Sources

Current source workbooks:

- `*SỔ THU - CHI.xlsx`
- `*BẢNG GIÁ VỐN.xlsx`

Observed workbook responsibilities include products, customers, suppliers, purchase orders, goods receipts, sales orders, receipts/payments, customer debt, inventory cards, pricing, print cost and product cost.

The existing spreadsheets currently contain cross-workbook dependencies such as `IMPORTRANGE`. The WebApp must eliminate these dependencies by using **one shared transactional database**.

---

# 2. Locked Business Decisions

The following decisions are confirmed and locked for Architecture Generation 1.

## 2.1 Warehouse

- The business currently operates **one warehouse only**.
- V1 will implement a single warehouse.
- Data structures should avoid unnecessary multi-warehouse complexity.
- A future multi-warehouse extension may be added only through a later SOT generation.

## 2.2 Units and Packaging

- Products are purchased according to supplier packaging / quy cách.
- Current selling is primarily according to packaging / business quantity rules.
- Retail selling by individual unit will be implemented later.
- Inventory must therefore use the **smallest practical base unit** (normally `piece / cái`) internally.
- Packaging must be represented as conversion rules.

Example:

`1 carton = 1,000 pieces`

Receiving 5 cartons creates `+5,000 pieces` inventory.

Selling 2 cartons creates `-2,000 pieces` inventory.

A future retail sale of 150 pieces must use the same stock ledger without migration.

## 2.3 Printing

Orders may be either:

- **PRINTED** — requires print production;
- **PLAIN / NO PRINT** — does not require print production.

Print jobs must at minimum capture:

- cup/product type;
- print color / number of colors;
- quantity;
- artwork/logo attachment;
- due date;
- assignee;
- print status.

## 2.4 Supplier Payment

- Supplier purchases are paid immediately.
- V1 does **not** require supplier accounts payable / supplier debt management.
- Purchase records must still store payment and document evidence where relevant.

## 2.5 Customer Receivables

- Customer receivables are required.
- A sales order may have multiple customer payments.
- The system must calculate:

`receivable = order total - sum(valid customer payments)`

## 2.6 Project Independence

OPS WebApp is a **standalone system**.

It must remain separate from MAGASIN Coffee:

- separate repository;
- separate database;
- separate authentication;
- separate role model;
- separate deployment;
- separate operational data.

## 2.7 Migration exception handling — Architecture Generation 2

Owner decision recorded 2026-10-01 for unresolved legacy customer-payment history:

- historical payment rows whose date, amount, or allocation cannot be established without guessing must remain in the migration exception/quarantine evidence and must not be inserted into the authoritative `customer_payments` ledger;
- no missing date may be invented, no payment may be truncated to fit an order total, and no payment may be silently reassigned to another order;
- the preserved migration exception and source-row provenance are the authority for later Owner resolution;
- after production deployment, the Owner may resolve an exception by entering a valid payment through the normal WebApp payment workflow once the correct facts are known;
- receivable/payment reporting for affected orders/customers is non-authoritative until the corresponding exceptions are resolved;
- these documented exceptions do not block UAT or production deployment, but their unresolved status must remain explicit during cutover and must not be represented as reconciled historical payment data.

This Generation 2 decision changes only the migration/release treatment of ambiguous legacy payment history. The Generation 1 technical architecture and transactional payment invariants remain unchanged.

## 2.8 Production hosting — Architecture Generation 3

Owner decision recorded 2026-10-01:

- OPS-WebApp production frontend will run on **GitHub Pages**; a separate paid/third-party Next.js server host is not part of the target architecture.
- Supabase remains the standalone backend authority for database, Auth, Storage, RLS, RPC/business invariants, and audit controls.
- GitHub Pages is a static host. The current Next.js server-runtime dependency, including `proxy.ts` session refresh and HttpOnly-cookie route gating, must therefore be removed/replaced before production cutover.
- The frontend must be made static-export compatible (Next.js static export or an equivalent static build) and deployed by GitHub Actions.
- Browser-side authentication may hold/refresh the Supabase user session, but client-side route hiding is not an authorization boundary. All data access and business mutations remain protected by Supabase RLS/RPC/database rules.
- Only the Supabase project URL and publishable key may be exposed to the browser. A `service_role` key or any secret key must never be included in Pages assets, repository code, or client environment variables.
- Supabase Auth redirect/callback URLs must be updated to the final GitHub Pages production origin/path.
- The existing private repository remains the implementation source. If the GitHub account plan cannot publish Pages directly from a private repository, the permitted GitHub-only fallback is a separate deploy-only Pages repository containing only the generated static artifact and no database secrets, migration evidence, or private source material.
- The remaining Supabase security-advisor ERROR for `public.production_print_job_queue` must still be resolved or explicitly replaced with a security-invoker/RPC boundary before OPS-074 can complete.

Compatibility impact: Generation 3 changes only the frontend runtime/deployment/auth-session architecture. It does not change the locked business workflows, Supabase project/database, role model, RLS policy authority, migration policy, or transactional invariants.

## 2.9 Public GitHub Pages repository — Architecture Generation 4

Owner decision recorded 2026-10-01:

- The canonical repository `magasincoffee/OPS-WebApp` is **public** as of 2026-10-01 (GitHub repository metadata verified `visibility=public`, `private=false`). GitHub Pages will publish directly from this same repository under the Owner's GitHub Free-compatible path.
- A second deploy-only repository is no longer the target architecture. The canonical public repository is both the implementation source and GitHub Pages deployment source.
- **Public visibility must not be enabled until a repository scrub is complete.** The scrub must verify that no secret credentials, private keys, service-role keys, passwords, production-only secrets, raw customer/supplier records, migration staging output, quarantine JSONL/CSV/XLSX, or other confidential operational data remain in the public Git history or tracked files.
- The existing `.gitignore` policy for `.env`, generated migration data, XLSX/XLS/CSV/JSONL staging, and build outputs remains mandatory.
- Public browser configuration may contain only the Supabase project URL and publishable key. Supabase RLS/RPC/database authorization remains the security boundary; repository visibility must never grant data access.
- Committed migration reports/manifests that contain internal financial controls, order identifiers, Drive file/folder IDs, or other business-sensitive evidence must be redacted, replaced with public-safe summaries, or moved out of the public repository before the visibility change.
- After the scrub, the Owner may change repository visibility to Public in GitHub Settings. GitHub Pages deployment then proceeds from the canonical repository using GitHub Actions.
- Any future file added to this public repository must be treated as internet-visible by default.

Compatibility impact: Generation 4 changes repository exposure/governance and removes the private-repository fallback from the GitHub Pages plan. It does not change the Generation 3 static frontend runtime, Supabase backend, business workflows, role model, RLS/RPC authority, or transactional invariants.

## 2.10 UI/UX design system — Owner decision

Owner decision recorded 2026-10-01:

- **Tabler is the authoritative visual/UI reference for OPS-WebApp V1.**
- This is a presentation and interaction-system decision only; it does **not** change Architecture Generation 4, the GitHub Pages runtime, Supabase backend, role model, RLS/RPC authorization, database schema, or business workflows.
- The frontend must converge on a consistent Tabler-style operational admin shell:
  - persistent left navigation on desktop with clear module grouping;
  - collapsible/mobile navigation for narrow screens;
  - compact top/header area;
  - page title + breadcrumb/action region;
  - information-dense but readable cards, tables, filters, forms, tabs, badges, alerts, empty states, loading states, and modals;
  - consistent spacing, typography, border radius, status colors, form sizing, and table density;
  - responsive layouts that remain usable on manager/warehouse/production mobile screens;
  - role-aware navigation must remain driven by existing authorization surfaces and must not expose inaccessible modules;
  - financial/cost data visibility remains governed solely by the existing role/RLS rules, not by visual hiding.
- Tabler is a **design-system/reference direction**, not authority over OPS business semantics. Existing OPS terminology, workflow states, fields, permissions, validation, and domain rules must be preserved.
- Do not copy demo content, fake business data, unrelated Tabler modules, or third-party backend assumptions into OPS.
- Reuse existing OPS routes and business components where practical; refactor presentation/layout without rewriting verified business logic unnecessarily.
- Tabler-compatible icons/components may be introduced where they improve consistency, but dependencies must remain compatible with static GitHub Pages export.
- The V1 visual target is a professional internal operations system optimized for fast scanning and repeated daily use rather than marketing-style presentation.
- The Tabler unification is executed as part of the current OPS-074 frontend/static-runtime conversion so the production GitHub Pages release does not ship the obsolete mixed UI shell first.

Minimum visual acceptance for the OPS-074 production frontend:
1. one consistent application shell across all V1 modules;
2. no squeezed/overflowing desktop content area;
3. responsive navigation and primary workflows on mobile;
4. standardized data-table, filter, form, action-button, status-badge, card, modal, alert, loading, and empty-state patterns;
5. role-aware dashboard and navigation remain functionally equivalent to the verified RBAC implementation;
6. no regression to V1 workflows or Supabase authorization boundaries;
7. Scaffold/build/static-export checks pass before Pages deployment.

---

# 3. Core Architecture Principles

## 3.1 One Database

The system must use one transactional database as the operational source.

There must be one authoritative record for:

- customer;
- supplier;
- product;
- SKU;
- product packaging;
- cost;
- inventory;
- sales order;
- print job;
- payment;
- customer receivable.

No duplicated operational masters across modules.

## 3.2 One Product Master

The WebApp must replace the current cross-spreadsheet product synchronization with a central product master.

A product/SKU must support at least:

- SKU code;
- product name;
- category;
- cup/product type;
- capacity/size where applicable;
- purchase unit;
- base inventory unit;
- packaging conversion;
- preferred supplier;
- latest purchase cost;
- logistics/freight allocation;
- calculated cost per base unit;
- calculated cost per package;
- sale pricing rules;
- current stock;
- reserved stock;
- available stock;
- minimum stock level;
- active/inactive state.

## 3.3 Inventory Truth

Inventory is ledger-driven.

Do not directly edit a product's stock balance as normal business behavior.

Stock must be derived from inventory movements such as:

- GOODS_RECEIPT;
- SALES_RESERVATION;
- RESERVATION_RELEASE;
- SALES_ISSUE;
- ADJUSTMENT_IN;
- ADJUSTMENT_OUT;
- STOCKTAKE_ADJUSTMENT.

Required stock concepts:

- **On hand** = physically recorded stock.
- **Reserved** = stock allocated to confirmed sales orders.
- **Available** = on hand - reserved.

Negative available stock should be prevented by default unless an explicitly authorized override is added in a future SOT generation.

## 3.4 Separate Operational Status Dimensions

Do not overload one field with unrelated statuses.

A sales order must have separate dimensions for:

### Order lifecycle

- DRAFT
- CONFIRMED
- COMPLETED
- CANCELLED

### Print lifecycle

- NOT_REQUIRED
- WAITING
- IN_PROGRESS
- WAITING_QC
- COMPLETED

### Warehouse lifecycle

- NOT_RESERVED
- RESERVED
- ISSUED

### Payment lifecycle

- UNPAID
- PARTIALLY_PAID
- RECEIVABLE
- PAID

This separation is mandatory.

---

# 4. V1 Modules

## 4.1 Dashboard

Role-aware operational dashboard.

Owner/Admin indicators should include:

- sales;
- outstanding customer receivables;
- orders in production;
- overdue orders/jobs;
- low-stock products;
- inventory status;
- gross margin / profitability where reliable cost data exists.

## 4.2 Customers

Required capabilities:

- customer profile;
- brand/company name;
- contact name;
- phone;
- address;
- notes;
- purchase history;
- order history;
- payment history;
- outstanding receivable;
- activity history.

## 4.3 Suppliers

Required capabilities:

- supplier profile;
- contact information;
- supplied products;
- purchase history;
- latest purchase prices;
- notes.

Supplier debt management is out of scope for V1.
## 4.4 Products and Costing

Required capabilities:

- central SKU master;
- category;
- cup/product type;
- size/capacity;
- package conversion;
- supplier;
- purchase price;
- freight/logistics;
- latest purchase cost;
- base-unit cost;
- package cost;
- pricing rules;
- stock snapshot;
- historical cost traceability.

## 4.5 Pricing and Quotations

The system must support quantity-based pricing.

Current spreadsheet-style quantity tiers should be converted to data-driven pricing rules rather than hard-coded spreadsheet columns.

Pricing rules should be able to use:

- product;
- product type;
- quantity tier;
- print/no-print;
- number of print colors;
- print cost;
- freight/cost inputs;
- margin/markup rules.

A quotation should be convertible into a sales order without re-entering line items.

## 4.6 Sales Orders

A sales order must support:

- customer;
- salesperson/creator;
- order lines;
- quantities;
- unit prices;
- discount if allowed;
- print/no-print per relevant line;
- print specification;
- artwork attachment;
- requested/due date;
- notes;
- total;
- deposits/payments;
- receivable;
- order status;
- print status;
- warehouse status;
- delivery status/history;
- activity log.

## 4.7 Print Production

Printed order items generate production jobs.

A print job must support:

- unique job number;
- linked sales order;
- linked sales-order item;
- customer;
- product;
- cup/product type;
- quantity;
- print color / number of colors;
- artwork/logo attachment;
- due date;
- assignee;
- status;
- QC state;
- completion evidence / optional photo attachment;
- timestamps;
- activity log.

Minimum print-job flow:

`WAITING → ACCEPTED/IN_PROGRESS → WAITING_QC → COMPLETED`

A plain/no-print order must bypass this module.

## 4.8 Warehouse

Required capabilities:

- goods receipt;
- order reservation;
- reservation release;
- sales issue;
- adjustment;
- stocktake;
- low-stock view;
- inventory movement history;
- on-hand / reserved / available quantities.

## 4.9 Purchasing

V1 purchase flow:

`Purchase requirement → Purchase order → Supplier payment recorded → Goods received → Inventory increased`

Purchase order data:

- supplier;
- products;
- package quantity;
- base-unit conversion;
- unit cost;
- freight/logistics;
- total;
- order date;
- expected/actual receipt date;
- payment information;
- document attachment;
- responsible user.

## 4.10 Delivery

Required V1 capabilities:

- ready-to-ship state;
- package/parcel information;
- transport/carrier/chành xe note;
- consignee;
- dispatch date;
- delivery note/reference;
- delivery completion state.

A full transport-management system is not required in V1.

## 4.11 Customer Payments and Receivables

A sales order may have multiple payments.

Each payment must record at least:

- customer;
- linked order where applicable;
- amount;
- payment date;
- payment method;
- reference/note;
- created by;
- evidence attachment where applicable.

Customer ledger must support:

- order debit;
- payment credit;
- current balance;
- history by customer.

## 4.12 Tasks / Operational Assignment

Operational work must be assignable.

Initial task use cases:

- print job;
- warehouse preparation;
- warehouse issue;
- accounting follow-up;
- other order-related operational tasks.

Task data:

- type;
- linked entity;
- assignee;
- due date;
- status;
- notes;
- completion timestamp.

## 4.13 Reports

V1 reports should include:

- sales by period;
- sales by customer;
- sales by product;
- gross margin where cost data is valid;
- customer receivables;
- payments;
- inventory on hand;
- reserved stock;
- available stock;
- low stock;
- inventory movements;
- purchase history;
- production workload/status.

---

# 5. Roles and Authorization

Initial roles:

1. **OWNER / ADMIN**
2. **SALES**
3. **ACCOUNTING**
4. **WAREHOUSE**
5. **PRINTER / PRODUCTION**

A user may hold more than one role.

## 5.1 OWNER / ADMIN

Access:

- full system;
- users/roles;
- products/cost;
- pricing;
- customers;
- suppliers;
- purchases;
- sales;
- production;
- warehouse;
- finance;
- reports;
- configuration;
- audit logs.

## 5.2 SALES

Primary access:

- customers;
- quotations;
- sales orders;
- order status;
- permitted selling prices;
- customer receivable visibility as required for sales follow-up.

Sales must not automatically receive unrestricted cost/profit configuration access.

## 5.3 ACCOUNTING

Primary access:

- customer payments;
- customer receivables;
- order financial state;
- cost data;
- pricing/cost reports;
- financial operational reports.

## 5.4 WAREHOUSE

Primary access:

- goods receipt;
- inventory;
- reservations;
- picking/preparation;
- issues;
- stocktake;
- adjustments when authorized.

Warehouse users should not require unrestricted profitability data.

## 5.5 PRINTER / PRODUCTION

Primary access:

- assigned print jobs;
- order/product identity needed to perform production;
- cup/product type;
- quantity;
- color specification;
- artwork;
- due date;
- production status;
- completion/QC evidence.

Production users must not see:

- cost price;
- gross margin;
- customer debt;
- accounting reports;
- unrelated financial data.

---

# 6. Primary Workflows
## 6.1 Printed Sales Order

`Customer → Quotation → Sales Order Confirmed → Payment/Deposit → Stock Reserved → Print Job → QC → Warehouse Issue → Delivery → Remaining Payment → Completed`

Rules:

- stock reservation and production status are independent;
- payments do not overwrite production state;
- print jobs originate from order items that require printing;
- inventory is reduced by stock issue, not by merely creating the order.

## 6.2 Plain / No-Print Sales Order

`Customer → Quotation/Order → Confirmed → Payment/Deposit → Stock Reserved → Warehouse Issue → Delivery → Remaining Payment → Completed`

No print job is created.

## 6.3 Purchase and Receipt

`Purchase requirement → Purchase Order → Immediate Supplier Payment → Goods Receipt → Inventory Movement → Cost History Updated`

## 6.4 Customer Receivable

`Order Confirmed/Invoiced → Debit Customer Ledger → One or More Payments → Credit Customer Ledger → Balance Recalculated`

---

# 7. Costing and Pricing Rules

The system must distinguish at least:

- latest purchase cost;
- calculated landed/latest cost;
- inventory costing basis used for reporting;
- selling price.

Existing spreadsheet logic indicates cost may be derived from:

`purchase price / packaging conversion + freight/logistics + relevant print cost`

The implementation must not collapse all of these into one opaque price field.

For V1:

- preserve source cost history during migration;
- make pricing tiers data-driven;
- support print cost differences by quantity and color count;
- keep cost configuration access restricted by role.

Before production financial reporting is declared authoritative, the exact inventory-costing method (e.g. weighted average vs another method) must be explicitly selected and recorded in a later SOT update if not already determined during implementation.

---

# 8. Proposed Data Model

The implementation should center on the following logical entities. Exact SQL schema may refine names but must preserve these domain boundaries.

## Identity / Access

- `users`
- `roles`
- `user_roles`

  - Verified 2026-09-29: added bounded purchase-order automatic activity capture migration at `supabase/migrations/20260929155000_ops_004_purchase_order_activity_capture.sql` covering CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and source metadata. Added pgTAP coverage at `supabase/tests/database/ops_004_purchase_order_activity.test.sql`; Database Migrations CI run `36545631241` passed the complete fresh migration chain and all database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.

## Master Data

- `customers`
- `suppliers`
- `product_categories`
- `products`
- `product_variants`
- `product_packaging`
- `supplier_products`

## Cost / Price

- `purchase_cost_history`
- `pricing_rules`
- `price_tiers`

## Purchasing

- `purchase_orders`
- `purchase_order_items`
- `purchase_payments`
- `goods_receipts`
- `goods_receipt_items`

## Sales

- `quotations`
- `quotation_items`
- `sales_orders`
- `sales_order_items`

## Production

- `print_jobs`
- `print_job_events`

## Inventory

- `inventory_movements`
- `inventory_reservations`
- `stocktakes`
- `stocktake_items`

## Finance

- `customer_payments`
- `customer_ledger_entries`

## Delivery

- `deliveries`
- `delivery_items`

## Work / Audit

- `tasks`
- `attachments`
- `activity_logs`

---

# 9. Technical Architecture

Architecture Generation 1 baseline:

- **Frontend / Web application:** Next.js
- **Primary database:** PostgreSQL
- **Backend platform:** Supabase
- **Authentication:** Supabase Auth
- **Authorization:** application RBAC + database policies where appropriate
- **File storage:** Supabase Storage
- **Form factor:** responsive WebApp / PWA-friendly
- **Primary usage:** desktop for office/admin work, mobile-friendly for warehouse and print-production work

Rules:

- production credentials must never be committed to Git;
- secrets must be environment variables / deployment secrets;
- migrations must be version-controlled;
- database changes must use migrations;
- critical business mutations should be auditable;
- role authorization must be enforced server-side/database-side, not only hidden in UI.

A technical stack change is an architecture change and requires SOT update.

---

# 10. V1 Scope Boundary

## IN SCOPE

- authentication;
- RBAC;
- users;
- customers;
- suppliers;
- products/SKUs;
- packaging conversion;
- product cost;
- pricing rules;
- quotation;
- sales orders;
- printed and no-print order paths;
- print jobs;
- single-warehouse inventory;
- reservation;
- goods receipt;
- stock issue;
- stock adjustments;
- customer payments;
- customer receivables;
- purchasing;
- delivery tracking at operational level;
- tasks;
- attachments;
- audit/activity log;
- management reports;
- migration from the two existing workbooks.

## OUT OF SCOPE FOR V1

- retail POS;
- consumer ecommerce;
- multiple warehouses;
- supplier accounts payable;
- full accounting/general ledger;
- electronic invoice integration;
- native iOS app;
- native Android app;
- MAGASIN Coffee integration;
- MAGASIN Coffee shared auth/database;
- advanced transport management.

Do not implement out-of-scope items merely because they appear useful. Add them only through a future SOT change.

---

# 11. Migration Rules

Migration source:

- `*SỔ THU - CHI.xlsx`
- `*BẢNG GIÁ VỐN.xlsx`

Migration must be treated as an explicit engineering phase, not manual copy/paste.

Required migration activities:

1. inventory all sheets and business columns;
2. map legacy columns to target entities;
3. normalize customer names and identifiers;
4. normalize supplier names;
5. generate/repair missing SKU identifiers;
6. normalize package conversion;
7. deduplicate products;
8. preserve historical order/payment data where reliable;
9. preserve source-row references for traceability;
10. detect invalid/negative stock conditions;
11. detect mixed status values;
12. reconcile opening inventory;
13. reconcile opening customer receivables;
14. validate totals before cutover;
15. retain an immutable migration snapshot/backup.

Known spreadsheet problems must not simply be copied into the database.

Examples already identified:

- missing product codes in some rows;
- suppliers represented as free text;
- mixed meanings in status columns;
- negative inventory values;
- sale-price tiers represented as fixed spreadsheet columns;
- cross-workbook dependencies.

Migration scripts must produce a reconciliation report.

---

# 12. Non-Negotiable Business Invariants

1. Inventory cannot be changed without a recorded movement.
2. Order payment status and production status are independent.
3. Plain/no-print orders must not generate print jobs.
4. Printed order items must preserve their production specification.
5. Customer debt must be derived from ledger/order/payment records, not a manually edited balance.
6. Product package conversion must be explicit and version-safe.
7. Financial/cost information must be protected from production/warehouse roles unless explicitly authorized.
8. Every material business mutation should record actor and timestamp.
9. The system must remain standalone from MAGASIN Coffee.
10. The spreadsheets are migration inputs, not the runtime database.

---

# 13. Implementation Plan and Authoritative Task State

Task status vocabulary:

- `TODO`
- `IN_PROGRESS`
- `BLOCKED`
- `DONE`

## Foundation

- **OPS-000 — SOT / architecture lock** — **DONE**
- **OPS-001 — Repository/app scaffold** — **DONE**
  - Completed 2026-09-29: scaffold validation CI at `.github/workflows/scaffold-ci.yml` passed dependency install, lint, and build in workflow run `36522422820`.
- **OPS-002 — Database schema and migrations** — **DONE**
  - Started 2026-09-29: added bounded master-data foundation migration at `supabase/migrations/20260929050100_ops_002_master_data_foundation.sql` covering customers, suppliers, product categories, products/SKUs, packaging conversion, and supplier-product mapping.
  - Continued 2026-09-29: added bounded cost/pricing foundation migration at `supabase/migrations/20260929050500_ops_002_cost_pricing_foundation.sql` covering purchase-cost history, landed/base-unit cost traceability, data-driven pricing rules, quantity tiers, print-cost inputs, and fixed/markup/margin pricing bases.
  - Continued 2026-09-29: added bounded purchasing/goods-receipt foundation migration at `supabase/migrations/20260929051000_ops_002_purchasing_receipt_foundation.sql` covering purchase orders/items, immediate supplier payments, goods receipts/items, packaging-to-base-unit receipt conversion, and derived purchase-order totals.
  - Continued 2026-09-29: added bounded quotation/sales-order foundation migration at `supabase/migrations/20260929051500_ops_002_sales_order_foundation.sql` covering quotations/items, sales orders/items, packaging conversion snapshots, printed-vs-plain line specifications, derived totals, and separate order/print/warehouse/payment status dimensions.
  - Continued 2026-09-29: added bounded inventory-ledger/reservation foundation migration at `supabase/migrations/20260929052000_ops_002_inventory_foundation.sql` covering immutable inventory movements, reservation linkage, ledger-derived on-hand/reserved/available stock snapshots, single-post goods-receipt protection, and prevention of negative available stock.
  - Continued 2026-09-29: added bounded stocktake/adjustment foundation migration at `supabase/migrations/20260929052500_ops_002_stocktake_foundation.sql` covering stocktake headers/items, system-vs-counted variance, authoritative linkage of stocktake adjustments into the immutable inventory ledger, one-post-per-stocktake-line protection, and required reasons for adjustment movements.
  - Continued 2026-09-29: added bounded print-production foundation migration at `supabase/migrations/20260929053000_ops_002_print_production_foundation.sql` covering print jobs/events, printed-order source validation, production/QC status dimensions, immutable production-spec snapshots, and a production queue view.\n  - Continued 2026-09-29: added bounded customer-finance foundation migration at `supabase/migrations/20260929053500_ops_002_customer_finance_foundation.sql` covering customer payments, source integrity, immutable customer-ledger entries, order-level receivable derivation from valid payments, and customer ledger balance views.
  - Continued 2026-09-29: added bounded delivery foundation migration at `supabase/migrations/20260929054000_ops_002_delivery_foundation.sql` covering delivery headers/items, operational delivery states, parcel/carrier/consignee details, sales-order source integrity, and a derived delivery-status view.
  - Continued 2026-09-29: added bounded operational-task foundation migration at `supabase/migrations/20260929054500_ops_002_operational_tasks_foundation.sql` covering shared task records, linked-entity references, assignment/due/status/priority state, completion consistency, and an overdue-aware operational queue view.
  - Blocked 2026-09-29: the current execution environment has no accessible standalone OPS Supabase project for applying and verifying the migration chain. The only accessible Supabase project is `MAGASIN-NOIBO`, which must not be used because Section 2.6 requires a separate OPS database/auth/deployment. Do not mark OPS-002 DONE until the migrations are applied and verified against an OPS-specific Supabase project.
  - Continued 2026-09-29: added bounded migration-validation CI at `.github/workflows/database-migrations-ci.yml` using the official Supabase CLI to initialize an ephemeral local configuration and apply all version-controlled migrations to a fresh local database for migration-affecting pushes and pull requests.
  - Continued 2026-09-29: added `supabase/migrations/20260929063000_ops_002_security_hardening.sql` to explicitly enable RLS on all 30 OPS public tables and set all 10 public derived views to `security_invoker=true`, keeping local/CI security behavior consistent with hosted Supabase.
  - Verified 2026-09-29: added pgTAP smoke coverage at `supabase/tests/database/ops_002_schema_smoke.test.sql`; GitHub Actions run `36532007015` passed the complete fresh migration chain and verified 30 authoritative tables, 10 authoritative views, RLS on all 30 tables, and security-invoker mode on all 10 views.
  - Continued 2026-09-29: added `supabase/migrations/20260929074000_ops_002_production_hardening.sql` to pin helper-function search paths, revoke public/Data API execution of the internal RLS helper, and add remaining foreign-key indexes identified by hosted Supabase advisors.
  - Verified 2026-09-29 against the standalone Supabase project `OPS-WebApp` (`foclxkjnypjolcwqekku`): hosted migration history contains all 12 repository migrations through `20260929074000`; direct database verification confirmed 30 authoritative tables, 10 authoritative views, RLS enabled on all 30 tables, and `security_invoker=true` on all 10 views. Remaining security-advisor findings are INFO-only `RLS Enabled No Policy` findings intentionally deferred to OPS-003; performance-advisor findings are INFO-only unused-index notices on the newly initialized database.
  - Reconciled 2026-09-29: made `20260929074000_ops_002_production_hardening.sql` replayable on a fresh/local database when the hosted-only `public.rls_auto_enable()` helper is absent. GitHub Actions run `36542929152` subsequently passed the complete fresh migration chain.
- **OPS-003 — Authentication and RBAC** — **DONE**
  - Started 2026-09-29: added bounded identity/RBAC foundation migration at `supabase/migrations/20260929080000_ops_003_identity_rbac_foundation.sql` covering the `users`, `roles`, and `user_roles` identity model; Supabase Auth user synchronization; the five locked V1 roles; role-membership helpers; and RLS/grants for the RBAC tables themselves. Business-table authorization policies and representative permission verification remain within OPS-003.
  - Continued 2026-09-29: added bounded master-data/cost-pricing authorization migration at `supabase/migrations/20260929090000_ops_003_master_cost_rbac.sql`. It grants SALES customer-management plus product/pricing reads, ACCOUNTING financial/master reads, WAREHOUSE procurement/product reference reads, PRINTER_PRODUCTION product reference reads, restricts purchase-cost history to OWNER_ADMIN/ACCOUNTING, and keeps master/cost/pricing configuration mutations OWNER_ADMIN-only. Authorization for purchase/order/inventory/production/finance/delivery/task tables and representative permission verification remain within OPS-003.
  - Continued 2026-09-29: added bounded purchasing/warehouse authorization migration at `supabase/migrations/20260929093000_ops_003_purchasing_warehouse_rbac.sql`. It keeps direct purchase-order/item/payment cost-bearing records restricted to OWNER_ADMIN/ACCOUNTING reads with OWNER_ADMIN mutations; grants OWNER_ADMIN/WAREHOUSE operational access to goods receipts, inventory reservations/movements, and stocktakes; preserves the append-only inventory ledger by granting only SELECT/INSERT on `inventory_movements`; and intentionally does not expose purchase-item unit costs to WAREHOUSE. Sales, production, customer-finance, delivery, operational-task authorization and representative permission verification remain within OPS-003.
  - Continued 2026-09-29: added bounded quotation/sales-order authorization migration at `supabase/migrations/20260929100000_ops_003_sales_rbac.sql`. It grants OWNER_ADMIN/SALES management of quotations and sales orders, grants ACCOUNTING read-only visibility into sales orders/items and derived order totals, and intentionally withholds direct sales-table access from WAREHOUSE/PRINTER_PRODUCTION to avoid unnecessary exposure of selling-price/order financial data. Production, customer-finance, delivery, operational-task authorization and representative permission verification remain within OPS-003.
  - Continued 2026-09-29: added bounded print-production authorization migration at `supabase/migrations/20260929103000_ops_003_production_rbac.sql`. It limits PRINTER_PRODUCTION to assigned print jobs/events, prevents production users from rewriting source order/customer/product/specification/assignment fields, provides a sanitized non-financial production queue with order/customer/product identity, and keeps SALES/ACCOUNTING/WAREHOUSE out of direct production-table access. Customer-finance, delivery, operational-task authorization and representative permission verification remain within OPS-003.
  - Continued 2026-09-29: added bounded customer-finance authorization migration at `supabase/migrations/20260929110000_ops_003_customer_finance_rbac.sql`. It grants OWNER_ADMIN/ACCOUNTING direct customer-payment and immutable ledger access, withholds payment/ledger records from WAREHOUSE/PRINTER_PRODUCTION, and provides SALES a sanitized receivable follow-up projection without direct access to payment or ledger tables. Delivery, operational-task authorization and representative permission verification remain within OPS-003.
  - Continued 2026-09-29: added bounded delivery authorization migration at `supabase/migrations/20260929111500_ops_003_delivery_rbac.sql`. It grants OWNER_ADMIN/WAREHOUSE operational read/create/update access to deliveries and delivery items, gives SALES read-only delivery visibility for order follow-up, withholds direct delivery-table access from ACCOUNTING/PRINTER_PRODUCTION, and preserves traceability by providing no authenticated DELETE grant. Operational-task authorization and representative permission verification remain within OPS-003.
  - Continued 2026-09-29: added bounded operational-task authorization migration at `supabase/migrations/20260929113000_ops_003_operational_tasks_rbac.sql`. It gives OWNER_ADMIN full task administration, limits SALES/ACCOUNTING/WAREHOUSE/PRINTER_PRODUCTION to reading their own assigned tasks and updating execution-only fields, prevents assignees from changing task identity/linkage/assignment/due date/priority/creator metadata, and exposes the operational task queue through invoker-security RLS.
  - Verified 2026-09-29: added `supabase/tests/database/ops_003_representative_permissions.test.sql` with representative OWNER_ADMIN, SALES, ACCOUNTING, WAREHOUSE, and PRINTER_PRODUCTION identities. GitHub Actions run `36542929152` passed all database tests, including 23 representative RBAC assertions confirming permitted operational visibility and denial of restricted purchase-cost/customer data where required.- **OPS-004 — Audit/activity/attachment foundation** — **DONE**
  - Started 2026-09-29: added bounded attachment-metadata foundation migration at `supabase/migrations/20260929120000_ops_004_attachment_metadata_foundation.sql` covering polymorphic business-entity linkage, Supabase Storage object references, evidence/artwork/document attachment kinds, uploader traceability, indexes, immediate RLS, restrictive OWNER_ADMIN metadata policies, and no direct authenticated update/delete grant. Added pgTAP smoke coverage at `supabase/tests/database/ops_004_attachment_metadata.test.sql`. Module-specific attachment/storage access remains within OPS-004.
  - Continued 2026-09-29: added bounded shared activity-log foundation migration at `supabase/migrations/20260929121500_ops_004_activity_log_foundation.sql` covering polymorphic entity linkage, action/actor/timestamp capture, structured before/after metadata, append-only update/delete guards, OWNER_ADMIN audit visibility, and prevention of direct authenticated audit-log writes. Added pgTAP smoke coverage at `supabase/tests/database/ops_004_activity_log.test.sql`. Module-specific automatic activity capture and attachment/storage access remain within OPS-004.
  - Continued 2026-09-29: added bounded sales-order automatic activity capture migration at `supabase/migrations/20260929123000_ops_004_sales_order_activity_capture.sql` covering CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and source metadata. Added pgTAP coverage at `supabase/tests/database/ops_004_sales_order_activity.test.sql`; Database Migrations CI run `36543934113` passed the fresh migration chain and sales-order activity assertions. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Continued 2026-09-29: added bounded customer-payment automatic activity capture migration at `supabase/migrations/20260929124500_ops_004_customer_payment_activity_capture.sql` covering CREATE/UPDATE audit events (including payment VOID transitions), `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and source metadata. Added pgTAP coverage at `supabase/tests/database/ops_004_customer_payment_activity.test.sql`. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Continued 2026-09-29: added bounded print-job automatic activity capture migration at `supabase/migrations/20260929154358_ops_004_print_job_activity_capture.sql` covering CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and source metadata. Added pgTAP coverage at `supabase/tests/database/ops_004_print_job_activity.test.sql`.
  - Reconciled 2026-09-29: corrected the customer-payment pgTAP plan count from 9 to 8 assertions in `supabase/tests/database/ops_004_customer_payment_activity.test.sql`. Database Migrations CI run `36545021406` then passed the complete fresh migration chain and all database smoke tests, verifying both customer-payment and print-job activity capture. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: goods-receipt automatic activity capture at `supabase/migrations/20260929160000_ops_004_goods_receipt_activity_capture.sql` and pgTAP coverage at `supabase/tests/database/ops_004_goods_receipt_activity.test.sql` passed Database Migrations CI run `36546100434`. The `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests, including the goods-receipt activity assertions. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded delivery automatic activity capture at `supabase/migrations/20260929161000_ops_004_delivery_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution for authenticated mutations, SYSTEM attribution for trusted internal deletion, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and source metadata. pgTAP coverage at `supabase/tests/database/ops_004_delivery_activity.test.sql` passed Database Migrations CI run `36546823873`; the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded operational-task automatic activity capture at `supabase/migrations/20260929162000_ops_004_task_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and source metadata. pgTAP coverage at `supabase/tests/database/ops_004_task_activity.test.sql` passed Database Migrations CI run `36547585186`; the run completed successfully against the fresh migration chain and database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded quotation automatic activity capture at `supabase/migrations/20260929163000_ops_004_quotation_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and source metadata. pgTAP coverage at `supabase/tests/database/ops_004_quotation_activity.test.sql` passed Database Migrations CI run `36548174899`; the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests. Other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded quotation-item automatic activity capture at `supabase/migrations/20260929164000_ops_004_quotation_item_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, parent `quotation_id` source metadata, and pgTAP coverage at `supabase/tests/database/ops_004_quotation_item_activity.test.sql`. Database Migrations CI run `36549042192` completed successfully; the `migration-smoke` job applied the complete fresh migration chain and all database smoke tests passed. Other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded sales-order-item automatic activity capture at `supabase/migrations/20260929165000_ops_004_sales_order_item_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, parent `sales_order_id`/source quotation-item metadata, and pgTAP coverage at `supabase/tests/database/ops_004_sales_order_item_activity.test.sql`. Database Migrations CI run `36549757310` completed successfully; the `migration-smoke` job applied the complete fresh migration chain and all database smoke tests passed. Other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded purchase-payment automatic activity capture at `supabase/migrations/20260929170000_ops_004_purchase_payment_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, parent `purchase_order_id` source metadata, and pgTAP coverage at `supabase/tests/database/ops_004_purchase_payment_activity.test.sql`. Database Migrations CI run `36550188216` completed successfully; the `migration-smoke` job applied the complete fresh migration chain and all database smoke tests passed. Other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded purchase-order-item automatic activity capture at `supabase/migrations/20260929171000_ops_004_purchase_order_item_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, parent `purchase_order_id`/`product_variant_id` source metadata, and pgTAP coverage at `supabase/tests/database/ops_004_purchase_order_item_activity.test.sql`. Database Migrations CI run `36550817582` completed successfully; the `migration-smoke` job applied the complete fresh migration chain and all database smoke tests passed. Other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded goods-receipt-item automatic activity capture at `supabase/migrations/20260929172000_ops_004_goods_receipt_item_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and parent `goods_receipt_id`/`purchase_order_item_id` source metadata. pgTAP coverage at `supabase/tests/database/ops_004_goods_receipt_item_activity.test.sql` passed Database Migrations CI run `36551394333`; the `migration-smoke` job applied the complete fresh migration chain and all database smoke tests passed. Other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded inventory-reservation automatic activity capture at `supabase/migrations/20260929173000_ops_004_inventory_reservation_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and parent `sales_order_item_id`/`product_variant_id` source metadata. pgTAP coverage at `supabase/tests/database/ops_004_inventory_reservation_activity.test.sql` passed Database Migrations CI run `36552051051`; the `migration-smoke` job applied the complete fresh migration chain and all database smoke tests passed. Other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded inventory-movement automatic activity capture at `supabase/migrations/20260929174000_ops_004_inventory_movement_activity_capture.sql` covers CREATE audit events for the append-only inventory ledger, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, post-insert row snapshots, movement/source-link metadata, and pgTAP coverage at `supabase/tests/database/ops_004_inventory_movement_activity.test.sql`. Database Migrations CI run `36552732457` completed successfully; the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests. Other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded stocktake automatic activity capture at `supabase/migrations/20260929175000_ops_004_stocktake_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, stocktake identity/status metadata, and pgTAP coverage at `supabase/tests/database/ops_004_stocktake_activity.test.sql`. Database Migrations CI run `36553541607` completed successfully; the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests. Stocktake-item activity capture, other material modules, and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded stocktake-item automatic activity capture at `supabase/migrations/20260929180000_ops_004_stocktake_item_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots including generated variance, and parent `stocktake_id`/`product_variant_id` source metadata. pgTAP coverage at `supabase/tests/database/ops_004_stocktake_item_activity.test.sql` passed Database Migrations CI run `36554188072`; the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded delivery-item automatic activity capture at `supabase/migrations/20260929181000_ops_004_delivery_item_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and parent `delivery_id`/`sales_order_item_id`/`product_variant_id` source metadata. pgTAP coverage at `supabase/tests/database/ops_004_delivery_item_activity.test.sql` passed Database Migrations CI run `36555375096`; the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests after the delivery-item linkage assertion fix in commit `350a25835f841092deee36da04a2ba1ce694814d`. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded customer automatic activity capture at `supabase/migrations/20260929182000_ops_004_customer_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after customer snapshots, and source metadata. pgTAP coverage at `supabase/tests/database/ops_004_customer_activity.test.sql` passed Database Migrations CI run `36555973300`; the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded supplier automatic activity capture at `supabase/migrations/20260929183000_ops_004_supplier_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after supplier snapshots, and source metadata. pgTAP coverage at `supabase/tests/database/ops_004_supplier_activity.test.sql` passed Database Migrations CI run `36556575111`; the `migration-smoke` job applied the complete fresh migration chain and all database smoke tests passed. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded product automatic activity capture at `supabase/migrations/20260929184000_ops_004_product_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after product snapshots, and category/source metadata. pgTAP coverage at `supabase/tests/database/ops_004_product_activity.test.sql` passed Database Migrations CI run `36557165706`; the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests. Product-variant automatic activity capture at `supabase/migrations/20260929185000_ops_004_product_variant_activity_capture.sql` with pgTAP coverage at `supabase/tests/database/ops_004_product_variant_activity.test.sql` is verified: Database Migrations CI run `36558132582` completed successfully, and the `migration-smoke` job applied the complete fresh migration chain and passed all database smoke tests. Product packaging, other material modules, and attachment/storage access remain within OPS-004.

  - Continued 2026-09-29: added bounded product-packaging automatic activity capture at `supabase/migrations/20260929190000_ops_004_product_packaging_activity_capture.sql` covering CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and parent `product_variant_id`/package-code source metadata. Added pgTAP coverage at `supabase/tests/database/ops_004_product_packaging_activity.test.sql`. Database Migrations CI verification is pending; other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: product-packaging automatic activity capture passed Database Migrations CI run `36561395045`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the product-packaging activity assertions. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded supplier-product automatic activity capture at `supabase/migrations/20260929191000_ops_004_supplier_product_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and supplier/product-variant/packaging source metadata. pgTAP coverage at `supabase/tests/database/ops_004_supplier_product_activity.test.sql` passed Database Migrations CI run `36561967418`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded product-category automatic activity capture at `supabase/migrations/20260929192000_ops_004_product_category_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after row snapshots, and category-code source metadata. pgTAP coverage at `supabase/tests/database/ops_004_product_category_activity.test.sql` passed Database Migrations CI run `36562492660`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Continued 2026-09-29: added bounded purchase-cost-history automatic activity capture at `supabase/migrations/20260929193000_ops_004_purchase_cost_history_activity_capture.sql` covering CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after cost snapshots, and product-variant/supplier/packaging/source-reference metadata. Added pgTAP coverage at `supabase/tests/database/ops_004_purchase_cost_history_activity.test.sql`. Database Migrations CI verification is pending; pricing-rule, price-tier, other material modules, and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: purchase-cost-history automatic activity capture passed Database Migrations CI run `36563386529`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the purchase-cost-history activity assertions. Pricing-rule, price-tier, other material modules, and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded pricing-rule automatic activity capture at `supabase/migrations/20260929194000_ops_004_pricing_rule_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after pricing-rule snapshots, and product-variant/product-type/print-mode/effective-state source metadata. pgTAP coverage at `supabase/tests/database/ops_004_pricing_rule_activity.test.sql` passed Database Migrations CI run `36564135950`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Price-tier, other material modules, and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded price-tier automatic activity capture at `supabase/migrations/20260929195000_ops_004_price_tier_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after tier snapshots, and pricing-rule/quantity/pricing-basis source metadata. pgTAP coverage at `supabase/tests/database/ops_004_price_tier_activity.test.sql` passed Database Migrations CI run `36564703893`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded print-job-event automatic activity capture at `supabase/migrations/20260929200000_ops_004_print_job_event_activity_capture.sql` covers CREATE/UPDATE/DELETE audit events, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, before/after event snapshots, and parent `print_job_id`/event-type source metadata. pgTAP coverage at `supabase/tests/database/ops_004_print_job_event_activity.test.sql` passed Database Migrations CI run `36565316708`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded customer-ledger-entry automatic activity capture at `supabase/migrations/20260929201000_ops_004_customer_ledger_entry_activity_capture.sql` covers CREATE audit events for the immutable customer receivables ledger, `auth.uid()` actor attribution, SECURITY DEFINER-controlled audit insertion, post-insert row snapshots, and customer/order/payment source metadata. pgTAP coverage at `supabase/tests/database/ops_004_customer_ledger_entry_activity.test.sql` passed Database Migrations CI run `36566042780`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the customer-ledger-entry activity assertions. Automatic activity capture for other material modules and attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded print-job attachment metadata access at `supabase/migrations/20260929202000_ops_004_print_job_attachment_metadata_access.sql` allows assigned `PRINTER_PRODUCTION` users to read only `ARTWORK` and `PRODUCTION_EVIDENCE` metadata for their assigned print jobs and insert only self-attributed `PRODUCTION_EVIDENCE`; payment/document evidence and unassigned-job attachments remain hidden. pgTAP coverage at `supabase/tests/database/ops_004_print_job_attachment_metadata_access.test.sql` passed Database Migrations CI run `36567074068`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Supabase Storage object policies and other module-specific attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded print-job Supabase Storage object access at `supabase/migrations/20260929203000_ops_004_print_job_storage_object_access.sql` enforces the `ops-attachments` bucket as private; `storage.objects` SELECT/INSERT policies require an exact pre-authorized `PRINT_JOB` attachment metadata row, keep OWNER_ADMIN access bounded to print-job objects, allow assigned `PRINTER_PRODUCTION` to read only `ARTWORK`/`PRODUCTION_EVIDENCE` and upload only self-attributed `PRODUCTION_EVIDENCE`, and intentionally add no authenticated UPDATE/DELETE policy. pgTAP coverage at `supabase/tests/database/ops_004_print_job_storage_object_access.test.sql` passed Database Migrations CI run `36570360301`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Other module-specific attachment/storage access remains within OPS-004.\n  - Verified 2026-09-29: bounded customer-payment attachment metadata access at `supabase/migrations/20260929204000_ops_004_customer_payment_attachment_metadata_access.sql` allows ACCOUNTING to read only `PAYMENT_EVIDENCE` metadata linked to visible `CUSTOMER_PAYMENT` records and insert only self-attributed evidence in the private `ops-attachments` bucket; SALES, WAREHOUSE, and PRINTER_PRODUCTION gain no customer-payment evidence access, and no authenticated UPDATE/DELETE access is added. pgTAP coverage at `supabase/tests/database/ops_004_customer_payment_attachment_metadata_access.test.sql` passed Database Migrations CI run `36571242145`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Customer-payment Supabase Storage object access and other module-specific attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded customer-payment Supabase Storage object access at `supabase/migrations/20260929205000_ops_004_customer_payment_storage_object_access.sql` keeps the `ops-attachments` bucket private; `storage.objects` SELECT/INSERT policies require an exact pre-authorized `CUSTOMER_PAYMENT` + `PAYMENT_EVIDENCE` metadata row, allow bounded OWNER_ADMIN access, allow ACCOUNTING to read evidence and upload only self-attributed evidence, grant no SALES/WAREHOUSE/PRINTER_PRODUCTION access, and intentionally add no authenticated UPDATE/DELETE policy. pgTAP coverage at `supabase/tests/database/ops_004_customer_payment_storage_object_access.test.sql` passed Database Migrations CI run `36571718123`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the customer-payment Storage object assertions. Other module-specific attachment/storage access remains within OPS-004.
  - Verified 2026-09-29: bounded sales-order-item artwork attachment metadata access at `supabase/migrations/20260929210000_ops_004_sales_order_item_attachment_metadata_access.sql` allows SALES to read only `ARTWORK` metadata linked to existing `SALES_ORDER_ITEM` records and insert only self-attributed artwork metadata in the private `ops-attachments` bucket; ACCOUNTING, WAREHOUSE, and PRINTER_PRODUCTION gain no direct sales-order artwork metadata access, and no authenticated UPDATE/DELETE access is added. pgTAP coverage at `supabase/tests/database/ops_004_sales_order_item_attachment_metadata_access.test.sql` passed Database Migrations CI run `36572620619`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Sales-order-item Supabase Storage object access and other module-specific attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded sales-order-item Supabase Storage object access at `supabase/migrations/20260929211000_ops_004_sales_order_item_storage_object_access.sql` keeps the private `ops-attachments` bucket metadata-first: `storage.objects` SELECT/INSERT policies require an exact pre-authorized `SALES_ORDER_ITEM` + `ARTWORK` attachment metadata row; OWNER_ADMIN has bounded read/upload access; SALES can read artwork and upload only self-attributed artwork; ACCOUNTING, WAREHOUSE, and PRINTER_PRODUCTION gain no direct sales-order-item object access; and no authenticated UPDATE/DELETE policy is added. pgTAP coverage at `supabase/tests/database/ops_004_sales_order_item_storage_object_access.test.sql` passed Database Migrations CI run `36573457417`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Other module-specific attachment/storage access remains within OPS-004.
  - Verified 2026-09-29: bounded purchase-order attachment metadata access at `supabase/migrations/20260929212000_ops_004_purchase_order_attachment_metadata_access.sql` allows ACCOUNTING to read only `DOCUMENT` and `PAYMENT_EVIDENCE` metadata linked to existing `PURCHASE_ORDER` records in the private `ops-attachments` bucket; ACCOUNTING receives no attachment metadata INSERT/UPDATE/DELETE capability because purchase-order mutation remains OWNER_ADMIN-only; SALES, WAREHOUSE, and PRINTER_PRODUCTION gain no purchase-order attachment metadata access. pgTAP coverage at `supabase/tests/database/ops_004_purchase_order_attachment_metadata_access.test.sql` passed Database Migrations CI run `36574314272`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Purchase-order Supabase Storage object access and other module-specific attachment/storage access remain within OPS-004.
  - Continued 2026-09-29: added bounded purchase-order Supabase Storage object access at `supabase/migrations/20260929213000_ops_004_purchase_order_storage_object_access.sql`. The private `ops-attachments` bucket now requires an exact pre-authorized `PURCHASE_ORDER` attachment metadata row for `DOCUMENT`/`PAYMENT_EVIDENCE` object access; OWNER_ADMIN has bounded read/upload access, ACCOUNTING has read-only object access, SALES/WAREHOUSE/PRINTER_PRODUCTION gain no purchase-order object access, and no authenticated UPDATE/DELETE policy is added. Added pgTAP coverage at `supabase/tests/database/ops_004_purchase_order_storage_object_access.test.sql`. Database Migrations CI verification is pending; other module-specific attachment/storage access remains within OPS-004.
  - Verified 2026-09-29: bounded purchase-order Supabase Storage object access passed Database Migrations CI run `36575419264`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the purchase-order Storage object access assertions. Other module-specific attachment/storage access remains within OPS-004.
  - Verified 2026-09-29: bounded goods-receipt attachment metadata access at `supabase/migrations/20260929214000_ops_004_goods_receipt_attachment_metadata_access.sql` allows WAREHOUSE and ACCOUNTING to read only `DOCUMENT` metadata linked to existing `GOODS_RECEIPT` records in the private `ops-attachments` bucket; WAREHOUSE may insert only self-attributed document metadata; ACCOUNTING remains read-only; SALES and PRINTER_PRODUCTION gain no goods-receipt attachment metadata access; and no authenticated UPDATE/DELETE access is added. pgTAP coverage at `supabase/tests/database/ops_004_goods_receipt_attachment_metadata_access.test.sql` passed Database Migrations CI run `36576458191`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the goods-receipt attachment metadata access assertions. Goods-receipt Supabase Storage object access and other module-specific attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded goods-receipt Supabase Storage object access at `supabase/migrations/20260929215000_ops_004_goods_receipt_storage_object_access.sql` keeps the private `ops-attachments` bucket metadata-first: an exact pre-authorized `GOODS_RECEIPT` + `DOCUMENT` attachment metadata row is required for object access; OWNER_ADMIN has bounded read/upload access; WAREHOUSE may read document objects and upload only self-attributed document objects; ACCOUNTING has read-only object access; SALES and PRINTER_PRODUCTION gain no goods-receipt object access; and no authenticated UPDATE/DELETE policy is added. pgTAP coverage at `supabase/tests/database/ops_004_goods_receipt_storage_object_access.test.sql` passed Database Migrations CI run `36577263639`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the goods-receipt Storage object access assertions. Other module-specific attachment/storage access remains within OPS-004.
  - Verified 2026-09-29: bounded delivery attachment metadata access at `supabase/migrations/20260929220000_ops_004_delivery_attachment_metadata_access.sql` allows WAREHOUSE and SALES to read only `DELIVERY_EVIDENCE` metadata linked to existing `DELIVERY` records in the private `ops-attachments` bucket; WAREHOUSE may insert only self-attributed delivery-evidence metadata; SALES remains read-only; ACCOUNTING and PRINTER_PRODUCTION gain no delivery attachment metadata access; and no authenticated UPDATE/DELETE access is added. pgTAP coverage at `supabase/tests/database/ops_004_delivery_attachment_metadata_access.test.sql` passed Database Migrations CI run `36578189919`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the delivery attachment metadata assertions. Delivery Supabase Storage object access and other module-specific attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded delivery Supabase Storage object access at `supabase/migrations/20260929221000_ops_004_delivery_storage_object_access.sql` keeps the private `ops-attachments` bucket metadata-first: an exact pre-authorized `DELIVERY` + `DELIVERY_EVIDENCE` attachment metadata row is required for object access; OWNER_ADMIN has bounded read/upload access; WAREHOUSE may read evidence and upload only self-attributed evidence; SALES has read-only object access; ACCOUNTING and PRINTER_PRODUCTION gain no delivery object access; and no authenticated UPDATE/DELETE policy is added. pgTAP coverage at `supabase/tests/database/ops_004_delivery_storage_object_access.test.sql` passed Database Migrations CI run `36578782192`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the delivery Storage object access assertions. Other module-specific attachment/storage access remains within OPS-004.
  - Verified 2026-09-29: bounded customer attachment metadata access at `supabase/migrations/20260929222000_ops_004_customer_attachment_metadata_access.sql` allows SALES and ACCOUNTING to read only `GENERAL`/`DOCUMENT` metadata linked to existing `CUSTOMER` records in the private `ops-attachments` bucket; SALES may insert only self-attributed customer document metadata; ACCOUNTING remains read-only; WAREHOUSE and PRINTER_PRODUCTION gain no customer attachment metadata access; and no authenticated UPDATE/DELETE access is added. pgTAP coverage at `supabase/tests/database/ops_004_customer_attachment_metadata_access.test.sql` passed Database Migrations CI run `36579810723`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests, including the customer attachment metadata access assertions. Customer Supabase Storage object access and other module-specific attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: bounded customer Supabase Storage object access at `supabase/migrations/20260929223000_ops_004_customer_storage_object_access.sql` keeps the private `ops-attachments` bucket metadata-first: an exact pre-authorized `CUSTOMER` attachment metadata row for `GENERAL`/`DOCUMENT` is required for object access; OWNER_ADMIN has bounded read/upload access; SALES may read customer documents and upload only self-attributed customer document objects; ACCOUNTING has read-only object access; WAREHOUSE and PRINTER_PRODUCTION gain no customer object access; and no authenticated UPDATE/DELETE policy is added. pgTAP coverage at `supabase/tests/database/ops_004_customer_storage_object_access.test.sql` passed Database Migrations CI run `36581132483`; the `migration-smoke` job applied the complete fresh migration chain and passed all OPS database smoke tests. Other module-specific attachment/storage access remains within OPS-004.
  - Continued 2026-09-29: added bounded supplier attachment metadata access at `supabase/migrations/20260929224000_ops_004_supplier_attachment_metadata_access.sql`. ACCOUNTING and WAREHOUSE may read only `GENERAL`/`DOCUMENT` metadata linked to existing `SUPPLIER` records in the private `ops-attachments` bucket; supplier mutation remains OWNER_ADMIN-only, so no business-role attachment metadata INSERT/UPDATE/DELETE capability is added; SALES and PRINTER_PRODUCTION gain no supplier attachment metadata access. Added pgTAP coverage at `supabase/tests/database/ops_004_supplier_attachment_metadata_access.test.sql`. Database Migrations CI run `36582113897` subsequently failed only because the pgTAP file planned 10 assertions while executing 9; the full migration chain itself applied successfully.
  - Reconciled 2026-09-29: corrected `supabase/tests/database/ops_004_supplier_attachment_metadata_access.test.sql` from `plan(10)` to `plan(9)` in commit `360493385ef5dd9d49f00b65278fb3a642eda9d4`. Re-verification in Database Migrations CI is pending; Supplier Supabase Storage object access and other module-specific attachment/storage access remain within OPS-004.
  - Verified 2026-09-29: supplier attachment metadata access passed Database Migrations CI run `36582503912` after the pgTAP plan correction; the `migration-smoke` job applied the complete fresh migration chain and all OPS database smoke tests passed (`50` test files / `495` tests), including `ops_004_supplier_attachment_metadata_access.test.sql`. Supplier Supabase Storage object access and other module-specific attachment/storage access remain within OPS-004.
  - Completed 2026-09-30: added the final bounded attachment/storage access migration at `supabase/migrations/20260930090000_ops_004_remaining_attachment_storage_access.sql` and pgTAP coverage at `supabase/tests/database/ops_004_remaining_attachment_storage_access.test.sql`. This closes Supplier Storage object access plus PRODUCT_VARIANT, QUOTATION, SALES_ORDER, TASK, and STOCKTAKE metadata/object access, completing policy coverage for all 13 attachment entity types supported by the OPS-004 foundation. Database Migrations CI run `36662951581` passed: `migration-smoke` applied the complete fresh migration chain and `Run OPS database smoke tests` completed successfully. Scaffold CI run `36662951607` also passed. OPS-004 is complete.



## Master Data

- **OPS-010 — Customer module** — **DONE**
  - Started 2026-09-30: implementing the first application business module with authenticated customer list/create/update/profile flows; customer order, product-purchase, payment, receivable, and activity history; and a bounded customer-only activity-log read policy for SALES/ACCOUNTING. Build and database CI verification are pending.
  - Completed 2026-09-30: customer module implementation in commit `fe71c3ddccd3e591ca40352a2a3a6277718ecc00` provides authenticated customer list/search/create/update/profile flows, customer order and product-purchase history, role-aware payment/receivable views, customer activity history, Supabase Auth session handling, and bounded SALES/ACCOUNTING customer-only activity-log visibility. Scaffold CI run `36697963926` passed dependency install, lint, and Next.js build. Database Migrations CI run `36697964094` passed the complete fresh migration chain and OPS database smoke tests, including `ops_010_customer_module_access.test.sql`. OPS-010 is complete.
- **OPS-011 — Supplier module** — **DONE**
  - Started 2026-09-30: implementing authenticated supplier list/create/update/profile flows; supplied-product mapping; role-aware purchase history and latest purchase-price visibility; and pgTAP coverage confirming WAREHOUSE operational visibility does not expose purchase-cost/PO financial data. Supplier debt remains intentionally out of scope per SOT. Build and database CI verification are pending.
  - Completed 2026-09-30: supplier module implementation in commit `9c1346fa24702cd6b94191308e1a048fa191176e` provides authenticated supplier list/search/create/update/profile flows, supplied-product mapping, role-aware purchase history and latest purchase-price visibility, and preserves the V1 exclusion of supplier debt. OWNER_ADMIN manages supplier master/linkages; ACCOUNTING receives cost-bearing purchasing visibility; WAREHOUSE remains limited to operational supplier/product context. Scaffold CI run `36703274220` passed dependency install, lint, and Next.js build. Database Migrations CI run `36703274537` passed the complete fresh migration chain and OPS database smoke tests, including `ops_011_supplier_module_access.test.sql` verifying the supplier/RBAC/cost boundary. OPS-011 is complete.
- **OPS-012 — Product/SKU/packaging module** — **DONE**
  - Started 2026-09-30: implementing the centralized product master UI/API for category, product, SKU/variant, and packaging conversion using the existing authenticated Supabase Data API and locked RLS. OWNER_ADMIN owns master-data mutations; all V1 roles retain product-reference reads. Cost/pricing configuration remains in OPS-013 and inventory ledger mutations remain in later inventory tasks. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `e63033f5d6849702c15e53ca23f27e784a06b8f1` delivers category/product/SKU/variant/packaging master-data UI and API using authenticated user JWTs and existing RLS, with OWNER_ADMIN-only mutation and all V1-role product-reference reads. Cost/pricing remains reserved for OPS-013 and inventory ledger mutation remains outside this module. Scaffold CI run `36706769576` passed dependency install, lint, and Next.js build. Database Migrations CI run `36706769608` passed the full fresh migration chain and OPS database smoke tests, including `ops_012_product_master_access.test.sql` coverage for all-role product reads, OWNER_ADMIN-only master mutation, procurement/cost boundaries, and packaging/minimum-stock constraints. OPS-012 is complete.
- **OPS-013 — Cost and pricing-rule module** — **DONE**
  - Started 2026-09-30: implementing the cost/pricing operational UI and API over the existing `purchase_cost_history`, `pricing_rules`, and `price_tiers` foundation. Scope includes historical purchase/freight/allocated cost inputs, generated base/landed cost visibility, package-cost calculations, quantity-tier pricing rules, print/no-print/color criteria, and fixed/markup/margin pricing bases. OWNER_ADMIN owns configuration; ACCOUNTING receives cost/pricing visibility; SALES receives the pricing surface without purchase-cost history. Purchase-order workflow remains OPS-020. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `0cb734353609deb2f1c53ff0971dcc267a0da5ed` delivers the cost/pricing operational UI and API over `purchase_cost_history`, `pricing_rules`, and `price_tiers`, including append-only historical purchase/freight/allocated cost inputs, database-generated purchase/landed base-unit costs, package-cost visibility, quantity-tier pricing, print/no-print/color criteria, and fixed/markup/margin pricing bases. OWNER_ADMIN remains the only configuration writer; ACCOUNTING retains cost/pricing visibility; SALES receives pricing visibility without purchase-cost history; WAREHOUSE and PRINTER_PRODUCTION remain excluded from cost/profitability surfaces. Scaffold CI run `36708236855` passed dependency install, lint, and Next.js build. Database Migrations CI run `36708237105` passed the complete fresh migration chain and OPS database smoke tests, including `ops_013_cost_pricing_module_access.test.sql` coverage for financial/pricing RBAC, database-generated cost columns, one-pricing-basis enforcement, and cost/pricing numeric/range constraints. OPS-013 is complete.

## Purchasing / Warehouse

- **OPS-020 — Purchase order workflow** — **DONE**
  - Started 2026-09-30: implementing the purchase-order operational workflow over the existing purchasing schema and locked RBAC. Scope includes supplier/order header, responsible user, expected receipt date, package/base-unit line conversion, unit cost, freight/logistics, derived totals, immediate supplier-payment recording, document/payment-evidence attachment upload/download, and financial-role visibility. Goods receipt, receipt-driven actual date/inventory posting, and warehouse receipt mutation remain OPS-021 and later inventory tasks. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `ac24b186bdf989c855b8e84ad517367f9db63adb` delivers the purchase-order workflow: supplier/order header, responsible user, expected receipt date, package-to-base line conversion, unit cost, freight/logistics, derived totals, immediate supplier-payment recording, and private DOCUMENT/PAYMENT_EVIDENCE attachment upload/download under existing RLS/storage policies. Financial PO/item/payment data remains limited to OWNER_ADMIN/ACCOUNTING, with OWNER_ADMIN-only mutation; WAREHOUSE remains outside cost-bearing PO data. Goods receipt and inventory posting remain OPS-021/OPS-022. Scaffold CI run `36709580056` passed dependency install, lint, and Next.js build. Database Migrations CI run `36709579734` passed the complete fresh migration chain and OPS database smoke tests, including `ops_020_purchase_order_workflow_access.test.sql` coverage for purchase RBAC, generated base/subtotal columns, purchasing constraints, attachment/storage boundaries, and activity-capture triggers. OPS-020 is complete.
- **OPS-021 — Goods receipt** — **DONE**
  - Started 2026-09-30: implementing the goods-receipt workflow over the existing receipt schema/RBAC. Scope includes WAREHOUSE/OWNER receipt creation and editing, partial receipt lines using PO package-to-base conversion, a sanitized non-cost PO-line projection for receiving, supplier-payment readiness enforcement before receipt, receipt document attachments, received-user attribution, receipt-driven `actual_receipt_date`, and cross-PO/conversion integrity guards. Inventory movements and cost-history posting remain OPS-022 and later workflow work. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `4cc5d3656e9ebcf38d3b2c6a0dd4cc3ff79f272f` delivers the goods-receipt workflow: WAREHOUSE/OWNER receipt creation and editing, partial receiving by PO line with package-to-base conversion, a sanitized no-cost receipt-source projection for warehouse operations, supplier-payment readiness enforcement before receipt, receipt-document attachments, authenticated received-user attribution, receipt-driven PO `actual_receipt_date`, and cross-PO/conversion integrity guards. The initial Database Migrations CI run `36711336767` correctly exposed one legacy OPS-004 fixture that predated the new payment-before-receipt invariant; fix commit `5492803fc912d359be8096c4cac583d228da9e5c` updated that test fixture to seed full supplier payment without weakening the production guard. Scaffold CI run `36711844166` then passed dependency install, lint, and Next.js build. Database Migrations CI run `36711843937` passed the complete fresh migration chain and all OPS database smoke tests, including the updated OPS-004 goods-receipt-item activity test and `ops_021_goods_receipt_workflow_access.test.sql`. Inventory movements and cost-history posting remain OPS-022 and later work. OPS-021 is complete.
- **OPS-022 — Inventory ledger** — **DONE**
  - Started 2026-09-30: implementing the single-warehouse immutable inventory ledger operational surface. Scope includes one-time GOODS_RECEIPT posting from receipt lines, database validation of receipt SKU/base quantity, authenticated actor/time attribution, ledger-derived on-hand/reserved/available snapshot visibility, movement history, and automatic purchase-cost history posting from the received PO line with PO freight allocated pro-rata by merchandise line subtotal. The inventory costing basis remains NULL because SOT Section 7 explicitly defers authoritative costing-method selection. Reservation/release/issue remain OPS-023; stocktake/adjustment/low-stock remain OPS-024. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `740598ada035613ec8938be5349305b89a36ac4f` delivers one-time GOODS_RECEIPT posting into the immutable inventory ledger, database validation of receipt SKU/base quantity, authenticated actor and receipt-time attribution, ledger-derived on-hand/reserved/available stock visibility and movement history, and automatic append-only purchase-cost history with PO freight allocated pro-rata by merchandise line subtotal while leaving `inventory_cost_basis_per_base_unit` NULL per SOT Section 7. Scaffold CI run `36713281913` passed dependency install, lint, and Next.js build. Database Migrations CI run `36713281720` passed the complete fresh migration chain and all OPS database smoke tests, including `ops_022_inventory_ledger_workflow.test.sql` coverage for immutable ledger permissions, one-post-per-receipt-line enforcement, database source validation, actor/reference attribution, stock snapshot derivation, and purchase/landed-cost history posting. Reservation/release/issue remain OPS-023 and stocktake/adjustment/low-stock remain OPS-024. OPS-022 is complete.
- **OPS-023 — Reservation / release / issue workflow** — **DONE**
  - Started 2026-09-30: implementing warehouse reservation/release/issue over the immutable inventory ledger. Scope includes role-bounded reservation work queue without sales financial exposure; partial or full reservation, release, and issue actions; database enforcement that reservation movements match the linked sales-order item/SKU and cannot exceed ordered or currently reserved quantities; automatic warehouse-status synchronization; locking inventory-linked sales-order quantity/SKU source fields; and regression coverage for on-hand/reserved/available reconciliation. Stocktake/adjustments/low-stock remain OPS-024; quotation and sales-order authoring remain OPS-030/OPS-031. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `33133c01c3f6dd47eef40ab8477b5305968ee4f7` delivers the role-bounded non-financial warehouse reservation queue, partial/full reserve-release-issue actions, immutable ledger movements, source/SKU/quantity enforcement, automatic sales-order warehouse-status synchronization, and protection against inventory-linked sales-order SKU/quantity drift. Initial Database Migrations CI run `36723705028` exposed two regression-test mismatches without weakening production guards: the historical OPS-004 inventory-reservation activity fixture required direct table mutation inside its rollback-only test transaction, and the new OPS-023 test declared an incorrect pgTAP plan/expected error message. Fix commit `a8ee1d4797e32026cb444eb210561768d72428be` scoped a temporary GRANT only inside the legacy test transaction and aligned the OPS-023 pgTAP plan/expectation. Scaffold CI run `36724482099` then passed lint and Next.js build. Database Migrations CI run `36724482085` passed the complete fresh migration chain and all OPS database smoke tests: 59 test files / 597 assertions, `Result: PASS`. Reservation → release/issue → on-hand/reserved/available reconciliation is therefore verified. Stocktake/adjustments/low-stock remain OPS-024. OPS-023 is complete.
- **OPS-024 — Stocktake / adjustments / low-stock** — **DONE**
  - Started 2026-09-30: implementing the warehouse stock-control surface over the immutable inventory ledger. Scope includes stocktake creation with ledger-derived on-hand snapshots, counted-quantity capture, COUNTED/POSTED workflow, exactly-once STOCKTAKE_ADJUSTMENT posting with stale-snapshot protection, manual ADJUSTMENT_IN/ADJUSTMENT_OUT with mandatory reason and authenticated actor attribution, low-stock visibility derived from available quantity versus SKU minimum stock, and warehouse/owner operational UI. Existing audit/activity capture remains authoritative. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `38ab6471441de815d32a406eec02a5dba94499f9` delivers ledger-derived stocktake snapshots, bounded count/finalize/post RPCs, DRAFT → COUNTED → POSTED lifecycle, exactly-once STOCKTAKE_ADJUSTMENT posting, stale-snapshot protection when ledger on-hand changes after count creation, authenticated and reason-required ADJUSTMENT_IN/ADJUSTMENT_OUT posting, security-invoker low-stock visibility based on available quantity versus SKU minimum stock, hardened stocktake table mutation boundaries, and warehouse/owner operational UI in `/inventory`. Scaffold CI run `36726799017` passed dependency install, lint, and Next.js build. Database Migrations CI run `36726798953` applied the complete fresh migration chain and passed all OPS database smoke tests: 60 test files / 625 assertions, `Result: PASS`. OPS-024 is complete.

## Sales

- **OPS-030 — Quotation workflow** — **DONE**
  - Started 2026-09-30: implementing SALES/OWNER quotation operations over the existing quotation and pricing foundations. Scope includes DRAFT quotation creation, customer/currency/validity capture, data-driven quantity pricing resolution from active pricing rules/tiers, SKU/package conversion into base quantity, print/no-print/color matching, selling-price snapshotting with pricing-rule/tier traceability, discounts, quotation totals, DRAFT-only line editing/removal, lifecycle transitions through SENT/ACCEPTED/REJECTED/EXPIRED, and a conversion-ready ACCEPTED state for OPS-031 without creating sales orders in this task. Quotation totals must respect underlying RLS. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `afaa740f90d6dd8e9c385b895f31115c9a4189be` delivers SALES/OWNER quotation creation and operational UI/API; data-driven pricing resolution from active pricing rules/tiers; SKU/package conversion into base quantity; PRINTED/PLAIN and print-color matching; selling-price snapshotting with pricing rule/tier traceability; discounts and derived quotation totals; DRAFT-only line mutation; lifecycle transitions through SENT/ACCEPTED/REJECTED/EXPIRED; and an ACCEPTED conversion boundary reserved for OPS-031. The implementation also changes `quotation_totals` to `security_invoker` so totals cannot bypass quotation RLS. Initial CI exposed a React render-purity lint issue and pgTAP fixture/query defects only; fix commits `4c96e29de32a18ccefe8ed1c2e2a3d3a047a9a34` and `66941307804823c5078805dfc55275367e6172b2` corrected those regressions without weakening workflow guards. Scaffold CI run `36730250437` passed dependency install, lint, and Next.js build. Database Migrations CI run `36730250278` applied the complete fresh migration chain and passed all OPS database smoke tests: 61 test files / 652 assertions, `Result: PASS`. OPS-030 is complete.
- **OPS-031 — Sales-order workflow** — **DONE**
  - Started 2026-09-30: implementing SALES/OWNER sales-order operations over the quotation, pricing, inventory-reservation, audit, and attachment foundations. Scope includes converting an ACCEPTED quotation to a DRAFT sales order without re-entering line items; direct DRAFT sales-order creation; pricing-rule-based direct line creation with package/base-unit conversion and selling-price snapshot traceability; DRAFT-only line mutation; CONFIRMED/CANCELLED/COMPLETED lifecycle guards; actor/timestamp capture; protection against cancellation after inventory or downstream operational activity; completion gating on independent warehouse/print/delivery/payment dimensions; RLS-safe sales-order totals; and SALES/OWNER operational UI with ACCOUNTING read-only visibility. Confirmation opens the existing OPS-023 reservation workflow. Print-job creation and detailed printed/no-print branching remain OPS-032/OPS-040; delivery and customer-payment execution remain later tasks. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `86a7d81fe6b4207c30d987417dfd910604df63aa` delivers ACCEPTED quotation → DRAFT sales-order conversion without line re-entry; direct DRAFT order creation; pricing-rule-based direct order lines with package/base-unit conversion and selling-price snapshot traceability; DRAFT-only line mutation; CONFIRMED/CANCELLED/COMPLETED lifecycle guards; actor/timestamp capture; cancellation protection after inventory/downstream activity; completion gating on the independent warehouse/print/delivery/payment dimensions; `sales_order_totals` as `security_invoker`; and SALES/OWNER operational UI with ACCOUNTING read-only visibility. Confirmation integrates with the existing OPS-023 reservation queue while print-job creation remains deferred to OPS-032/OPS-040. CI uncovered only regression-fixture/test-harness issues caused by the stronger lifecycle and inventory-authority guards; fix commits `9ebd228773d18936a985803b5b959f40ed7985f8`, `2740a864ecccd6b753f6c2a8865b7c4f450ff130`, and `03fee14bc920b12b362d36b13d5d12062f58c65f` aligned legacy fixtures with DRAFT → line → CONFIRMED ordering, repaired pgTAP expected-query quoting, updated the inventory immutability expectation to the stronger DRAFT guard, and used the bounded WAREHOUSE `adjust_inventory` RPC for stock setup without weakening production controls. Scaffold CI run `36735151317` passed dependency install, lint, and Next.js build. Database Migrations CI run `36735151209` applied the complete fresh migration chain and passed all OPS database smoke tests: 62 test files / 686 assertions, `Result: PASS`. OPS-031 is complete.
- **OPS-032 — Printed vs no-print branching** — **DONE**
  - Started 2026-09-30: implementing canonical sales-order branching from line-level `print_mode`. Confirmation must derive the order print branch in the database: all-PLAIN orders become `print_status=NOT_REQUIRED` and bypass production; any order containing PRINTED lines becomes `print_status=WAITING`. PRINTED lines require a usable due date from the line or parent order before confirmation. A security-invoker, non-financial print-requirement projection exposes only confirmed PRINTED lines for later OPS-040 job materialization, while plain lines never enter the production requirement path. Print-job source validation is hardened so jobs cannot originate from DRAFT/CANCELLED/plain orders. OPS-032 does not create print jobs or implement production transitions; those remain OPS-040+. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `54ee37b4d9489e86f8743558d18eeef2ba7be4fd` delivers canonical database-level print branching from sales-order line `print_mode`: all-PLAIN orders confirm with `print_status=NOT_REQUIRED` and bypass production; any order containing PRINTED lines confirms with `print_status=WAITING`; PRINTED lines require a usable line-level or parent-order due date before confirmation; mixed orders expose only PRINTED lines through the non-financial `sales_order_print_requirements` security-invoker projection; and print-job source validation rejects DRAFT/CANCELLED/plain sources while leaving actual print-job materialization to OPS-040. Legacy print-job regression fixtures were aligned to the canonical DRAFT → line authoring → CONFIRMED source lifecycle without weakening production guards. Initial CI identified only pgTAP test-contract issues; fix commit `ed60251b5b9164a133b1a1d37bff711561444fa5` corrected the assertion plan and stabilized the plain/no-print rejection message while preserving the same blocking behavior. Scaffold CI run `36737768604` passed dependency install, lint, and Next.js build. Database Migrations CI run `36737768543` applied the complete fresh migration chain and passed all OPS database smoke tests: 63 test files / 715 assertions, `Result: PASS`. OPS-032 is complete.
- **OPS-033 — Delivery workflow** — **DONE**
  - Started 2026-09-30: implementing V1 delivery over the existing delivery, inventory-issue, sales-order, audit, attachment, and storage foundations. Scope includes one active full-order delivery manifest per sales order; operational work queue without selling-price exposure; consignee, parcel/package, carrier/chành xe note, dispatch date, delivery reference, and notes; canonical NOT_READY → READY_TO_SHIP → DISPATCHED → COMPLETED flow with pre-dispatch cancellation; READY_TO_SHIP gating on authoritative warehouse_status=ISSUED and print_status=NOT_REQUIRED/COMPLETED; immutable manifest after readiness; sales-order delivery-status synchronization; and OWNER_ADMIN/WAREHOUSE management with SALES read-only tracking. Full transport-management, routing, fleet management, and customer-payment execution are outside OPS-033. Scaffold and database CI verification are pending.
  - Completed 2026-09-30: implementation commit `92becfc1d01038f397f40e163789b85653afa2f9` delivers the V1 delivery lifecycle and UI: one active full-order delivery manifest per sales order; operational delivery work queue/tracking/manifest RPCs without selling-price or cost exposure; consignee, parcel/package, carrier/chành xe note, dispatch date, delivery reference, and notes; canonical `NOT_READY → READY_TO_SHIP → DISPATCHED → COMPLETED` lifecycle with pre-dispatch cancellation; readiness gating on authoritative `warehouse_status=ISSUED` and `print_status in (NOT_REQUIRED, COMPLETED)`; immutable manifest after readiness; sales-order delivery-status synchronization; and OWNER_ADMIN/WAREHOUSE management with SALES read-only tracking through `/deliveries`. Fix commit `2a5da04140d182c32c455bf2a8b4a368cc02677f` repaired the delivery-tracking SQL function delimiter. Fix commit `68be98cdeff0813d83d5082a7ed6bbb287a428e4` aligned legacy attachment/storage fixtures with the NOT_READY start rule and moved WAREHOUSE state verification behind the non-financial operational tracking RPC while preserving RLS. Fix commit `744f3d7bab6841463dc9f63e3ae125c1254dc0f7` repaired pgTAP dollar-quoted query literals. Scaffold CI run `36750379163` passed dependency install, lint, and Next.js build. Database Migrations CI run `36750379092` applied the complete fresh migration chain and passed all OPS database smoke tests: 64 test files / 754 assertions, `Result: PASS`. OPS-033 is complete.

## Production

- **OPS-040 — Print-job workflow** — **DONE**
  - Started 2026-10-01: implementing print-job materialization and pre-QC production lifecycle over the OPS-032 PRINTED requirements. Scope includes one active print job per PRINTED sales-order line; immutable source/specification snapshots; OWNER_ADMIN materialization from confirmed requirements; WAITING → ACCEPTED → IN_PROGRESS → WAITING_QC transitions with cancellation before QC; production domain events with authenticated actor capture; aggregate sales-order print-status synchronization across all required jobs; and non-financial OWNER_ADMIN/PRINTER_PRODUCTION tracking UI. Assignment/mobile work queue remains OPS-041. QC state, completion evidence, and COMPLETED transition remain locked for OPS-042. Scaffold and database CI verification are pending.
  - Completed 2026-10-01: implementation commit `112572f179a65a3d17b11eb8117e39ef6b6b8693` delivers print-job materialization from confirmed PRINTED requirements, one active print job per PRINTED sales-order line, immutable production snapshots, pre-QC lifecycle `WAITING → ACCEPTED → IN_PROGRESS → WAITING_QC` with pre-QC cancellation, authenticated production domain events, aggregate sales-order `print_status` synchronization, bounded non-financial requirement/tracking RPCs, and `/print-jobs` UI. The task intentionally keeps assignment/mobile work queue locked for OPS-041 and QC/evidence/`COMPLETED` locked for OPS-042. Initial CI exposed integration-only regressions: escaped template literals in the new UI and legacy print attachment/storage/OPS-032 fixtures that no longer matched the strengthened one-active-job/source-snapshot invariants. Fix commit `03f6065c78cd42e7531aa8f84bf723f19c326f42` repaired the UI literals and aligned those fixtures to separate source lines with exact production snapshots, without weakening production guards. Scaffold CI run `36753277041` passed dependency install, lint, and Next.js build. Database Migrations CI run `36753277125` applied the complete fresh migration chain including `20261001002000_ops_040_print_job_workflow.sql`; OPS-004 print attachment/storage regressions, OPS-032 branching, and OPS-040 workflow tests all passed. Final database result: 65 test files / 789 assertions, `Result: PASS`. OPS-040 is complete.
- **OPS-041 — Production assignment / mobile work queue** — **DONE**
  - Started 2026-10-01: implementing bounded print-production assignment and a mobile-first queue over OPS-040. OWNER_ADMIN may assign/reassign/unassign a WAITING print job only to an active user holding PRINTER_PRODUCTION; assignment becomes immutable once the job is accepted. Every assignment change is recorded in print_job_events with authenticated actor attribution. PRINTER_PRODUCTION receives a non-financial mobile queue containing only jobs assigned to auth.uid(), ordered by due date, with the production identity/specification/artwork/status fields required by SOT Section 5.5 and the existing OPS-040 execution actions through WAITING_QC. QC result/evidence/COMPLETED remain reserved for OPS-042. Scaffold and database CI verification are pending.
  - Completed 2026-10-01: implementation commit `4c69c76d2f5ad0dd975ceb679a4e4537a468f84f` delivers OWNER_ADMIN assignment/reassignment/unassignment for WAITING print jobs, active-PRINTER_PRODUCTION assignee validation, authenticated assignment history in `print_job_events`, a non-financial mobile-first `/production` queue scoped to `auth.uid()`, and assigned-worker execution through the existing OPS-040 lifecycle to `WAITING_QC`. Follow-up commit `e343e4995bdc6ecdede155fc92db3011d7369c1a` hardened the assignment path so direct `assignee_user_id` mutation cannot bypass audit history, aligned legacy print activity/attachment/storage fixtures with valid production assignees, and updated OPS-040 regression setup to assign jobs before acceptance. Final fix commit `ef96ba9af205f38a2a227e28652a8b1039ee5251` repaired pgTAP dollar-quoted literals in OPS-040/041 tests only. Scaffold CI run `36756386429` passed dependency install, lint, and Next.js build. Database Migrations CI run `36756386597` applied the complete fresh migration chain including `20261001011000_ops_041_production_assignment_mobile_queue.sql`; OPS-004 print activity/attachment/event/storage regressions, OPS-040 workflow, and OPS-041 assignment/mobile queue tests all passed. Final database result: 66 test files / 818 assertions, `Result: PASS`. QC result, completion evidence, and `COMPLETED` remain reserved for OPS-042. OPS-041 is complete.
- **OPS-042 — QC / production completion evidence** — **DONE**
  - Started 2026-10-01: implementing bounded print QC and production-completion evidence over OPS-040/041. QC submission is limited to OWNER_ADMIN or the assigned PRINTER_PRODUCTION user for a WAITING_QC job and requires a linked PRODUCTION_EVIDENCE attachment in the existing private ops-attachments bucket. PASS records QC/evidence, completes the print job, and allows aggregate sales-order print_status synchronization to COMPLETED when every required job is complete. FAIL records durable QC evidence/event history and returns the job to IN_PROGRESS for rework; the same assignment remains locked. Direct QC/completion mutation remains blocked so evidence-backed completion must pass through the bounded QC RPC. Finance/customer-payment execution remains OPS-050+. Scaffold and database CI verification are pending.
  - Completed 2026-10-01: implementation commit `b257b14fc75e747f65c19f47dfb1cf45152a0e2e` delivers evidence-backed print QC over the existing private `ops-attachments` storage/RLS foundation. `submit_print_job_qc` accepts only WAITING_QC jobs visible to OWNER_ADMIN or the assigned PRINTER_PRODUCTION user; PASS requires a linked PRODUCTION_EVIDENCE attachment, records QC/evidence/timestamps, moves the job to COMPLETED, and allows aggregate sales-order `print_status` to synchronize to COMPLETED when all required print jobs are complete. FAIL records durable evidence/event history and returns the same assigned job to IN_PROGRESS for rework. Direct QC/completion field mutation remains blocked. The UI adds private evidence upload/download plus PASS/FAIL controls on print-job detail, while completed jobs leave the active mobile production queue. Follow-up commit `8e96fc8f283a6faa5f4b7c333a6c3389d8f4f228` aligned regression expectations and RLS-aware test harness behavior without changing production business rules. Final fix commit `0481c64176103410fb95d6ed4bf2fffa27dc70ef` repaired pgTAP dollar-quoted literals in the OPS-042 test only. Scaffold CI run `36759368155` passed dependency install, lint, and Next.js build. Database Migrations CI run `36759368144` applied the complete fresh migration chain including `20261001013000_ops_042_qc_completion_evidence.sql`; OPS-040, OPS-041, and OPS-042 tests all passed. Final database result: 67 test files / 842 assertions, `Result: PASS`. OPS-042 is complete.

## Finance

- **OPS-050 — Customer payment recording** — **DONE**
  - Started 2026-10-01: implementing bounded customer-payment recording over confirmed sales orders using the existing customer-finance, activity-log, and private PAYMENT_EVIDENCE attachment/storage foundations. OWNER_ADMIN/ACCOUNTING may record multiple POSTED payments; authenticated actor attribution is authoritative; linked-order payments cannot exceed the current order total; VOID preserves payment history and recalculates the order payment dimension. Payment status synchronizes to UNPAID/PARTIALLY_PAID/PAID from valid POSTED order payments while RECEIVABLE remains reserved for OPS-051 ledger/receivables policy. The application exposes finance-only payment recording/history, payment voiding, and private evidence upload/download. SALES retains only the existing sanitized receivable follow-up visibility. Customer-ledger entries and receivable ledger posting remain OPS-051. Scaffold and database CI verification are pending.
  - Completed 2026-10-01: implementation commit `861c1b624765b049db3f8e59a2a55b9ecf79692f` delivers bounded customer-payment recording for confirmed sales orders, multiple POSTED payments, overpayment rejection, authenticated creator attribution, payment-history-preserving VOID, automatic sales-order payment-status synchronization across UNPAID/PARTIALLY_PAID/PAID, finance-only payment history/recording UI, and private PAYMENT_EVIDENCE upload/download using the existing attachment/storage RLS foundation. It intentionally creates no customer-ledger entries; ledger debits/credits, RECEIVABLE policy, and customer balance reconciliation remain OPS-051. Initial CI exposed one least-privilege issue: the SECURITY INVOKER recording RPC unnecessarily requested a row lock on sales_orders, which required an UPDATE privilege ACCOUNTING correctly does not have. Fix commit `44f7a1a4ad5fa995c5c9e8e67be6af2ff28e5166` removed that redundant public-RPC row lock while preserving transactional overpayment protection in the privileged BEFORE INSERT guard that locks the authoritative order row before summing POSTED payments. Scaffold CI run `36761646937` passed dependency install, lint, and Next.js build. Database Migrations CI run `36761646656` applied the complete fresh migration chain including `20261001015500_ops_050_customer_payment_recording.sql`; customer-payment activity, attachment-metadata, Storage-object regressions, and OPS-050 payment workflow tests all passed. Final database result: 68 test files / 863 assertions, `Result: PASS`. OPS-050 is complete.
- **OPS-051 — Customer ledger / receivables** — **DONE**
  - Started 2026-10-01: implementing source-backed customer receivables over OPS-050 and the existing immutable ledger foundation. CONFIRMED sales orders automatically append one ORDER_DEBIT at the locked sales-order total; customer payments automatically append one PAYMENT_CREDIT at the immutable payment amount; payment VOID and order cancellation preserve ledger history while becoming ineffective in current-balance calculations. Current balances are exposed per customer **and currency** to avoid invalid cross-currency aggregation. Payment status remains UNPAID/PARTIALLY_PAID before delivery, becomes RECEIVABLE when delivery is COMPLETED with an outstanding amount, and becomes PAID only when valid POSTED payments cover the order total. OWNER_ADMIN/ACCOUNTING receive source-linked ledger/balance history; SALES retains sanitized order-level receivable follow-up without direct payment/ledger access. Existing confirmed orders and payments are backfilled idempotently. Dashboard/report aggregation remains OPS-060/062. Scaffold and database CI verification are pending.
  - Completed 2026-10-01: implementation commit `5731ab1ced9efae1729be5ac8a8b6da21ceac09f` delivers source-backed customer receivables over OPS-050. CONFIRMED sales orders append one immutable ORDER_DEBIT at the locked sales-order total; customer payments append one immutable PAYMENT_CREDIT at the authoritative payment amount. Payment VOID and order cancellation preserve ledger history but become ineffective in current-balance calculations. Current customer balances are exposed per currency so values such as VND and USD are never incorrectly aggregated. Payment status remains UNPAID/PARTIALLY_PAID before delivery, becomes RECEIVABLE when delivery is COMPLETED with an outstanding amount, and returns to PAID only when valid POSTED payments cover the order total. OWNER_ADMIN/ACCOUNTING receive source-linked ledger history and currency-safe balances, while SALES retains only the sanitized order-level receivable follow-up projection. Existing confirmed orders and payments are backfilled idempotently; dashboard/report aggregation remains OPS-060/062. The implementation also updates OPS-050 and OPS-004 ledger-activity regressions to reflect automatic source-backed credits/debits. Initial Database CI exposed only one malformed UUID fixture in the new OPS-051 pgTAP test; fix commit `a2a77de95e7a11092250813b114e02097255aece` corrected that fixture without changing production logic. Scaffold CI run `36764070146` passed dependency install, lint, and Next.js build. Database Migrations CI run `36764070179` applied the complete fresh migration chain including `20261001021000_ops_051_customer_ledger_receivables.sql`; OPS-004 customer-ledger activity, OPS-050 customer-payment recording, and OPS-051 customer-ledger/receivables tests all passed. Final database result: 69 test files / 889 assertions, `Result: PASS`. OPS-051 is complete.

## Operations / Reporting

- **OPS-060 — Role-aware dashboards** — **DONE**
  - Started 2026-10-01: replacing the shared unauthenticated module launcher with an authenticated role-aware operations dashboard. Dashboard data/navigation are derived from the user's existing database roles and current RLS/sanitized projections rather than a new privileged dashboard API. SALES receives customer/quotation/order/delivery/receivable follow-up only; ACCOUNTING receives finance, receivables, order financial state, costing, and receipt visibility; WAREHOUSE receives goods-receipt/inventory/reservation/delivery workload; PRINTER_PRODUCTION receives only its assigned production queue and print-job access; OWNER_ADMIN receives the combined system overview through the existing owner-authorized surfaces. Multi-role users receive the union of their allowed dashboard sections. Production dashboards do not expose cost, margin, customer debt, or unrelated finance. Operational task execution remains OPS-061 and formal reports remain OPS-062. Scaffold and full database regression CI verification are pending.
  - Completed 2026-10-01: implementation commit `f448480335dcd1921da2a3bb909b0411be9b9201` replaces the common unauthenticated home launcher with an authenticated role-aware dashboard and adds the root route to the existing session-refresh proxy. Dashboard sections are composed from the user's current role set, so multi-role users receive the union of allowed surfaces. SALES sees customer/quotation/order/delivery/receivable follow-up metrics and navigation; ACCOUNTING sees payment/receivable/order-financial/costing/receipt surfaces; WAREHOUSE sees receipt/inventory/reservation/low-stock/delivery workload; PRINTER_PRODUCTION queries only its assigned production mobile queue and print-job access and does not query payment, ledger, costing, margin, debt, or unrelated finance; OWNER_ADMIN receives cross-functional overview through existing owner-authorized surfaces. The implementation introduces no privileged dashboard API and no database/schema change, preserving existing RLS and sanitized-view boundaries. Owner-level total production workload uses Print Jobs, while My Production Queue is shown only when the user also holds PRINTER_PRODUCTION. Scaffold CI run `36765245645` passed dependency install, lint, and Next.js build. Because OPS-060 changes only `app/page.tsx`, `proxy.ts`, and the SOT, it does not trigger Database Migrations CI; the unchanged schema baseline remains verified by Database Migrations CI run `36764070179` with 69 test files / 889 assertions and `Result: PASS`. Source review confirms role-gated requests align with the existing authorization surfaces. OPS-060 is complete.
- **OPS-061 — Operational tasks** — **DONE**
  - Started 2026-10-01: implementing the SOT Section 4.12 operational-assignment workflow over the existing `tasks` table, owner/assignee RLS, queue view, and automatic activity capture. OWNER_ADMIN creates, assigns/reassigns, prioritizes, dates, annotates, and cancels tasks; active users holding SALES, ACCOUNTING, WAREHOUSE, or PRINTER_PRODUCTION may be assignees. Assignees see only their own tasks and may update execution status/notes but cannot rewrite task identity, linked entity, assignment, due date, priority, creator, or creation timestamp. Assignee lifecycle is bounded to OPEN → IN_PROGRESS/BLOCKED/DONE, BLOCKED → IN_PROGRESS/DONE, and IN_PROGRESS → BLOCKED/DONE; DONE/CANCELLED tasks are execution-locked. DONE automatically records completion timestamp, while reopening by OWNER_ADMIN clears it. Initial task types cover PRINT_JOB, WAREHOUSE_PREPARATION, WAREHOUSE_ISSUE, ACCOUNTING_FOLLOW_UP, and ORDER_OPERATION with optional linked-entity references. The role-aware dashboard receives an RLS-backed Operational Tasks summary/link. Formal reports remain OPS-062. Scaffold and database CI verification are pending.
  - Completed 2026-10-01: implementation commit `c36f8206a2643b068386c635b49648fb9d8282c5` added the operational-task assignment/execution workflow, task assignee directory, bounded create/manage/execute/cancel RPCs, `/tasks` board, authenticated route coverage, and role-aware dashboard task summary. Follow-up compatibility/test fixes preserved the business contract while aligning the legacy representative-permissions fixture, exposing task creator provenance through the security-invoker queue view, preserving existing view column order, enforcing assignee immutability before owner-only reassignment validation, and correcting pgTAP SQL snippets. Final verification commit `74e23abcab913848774509f0929cda3447995e8c` passed Scaffold CI run `36770491217` (dependency install, lint, and Next.js build all SUCCESS) and Database Migrations CI run `36770491225`. The migration-smoke job applied the complete fresh migration chain including `20261001023000_ops_061_operational_tasks.sql`; representative RBAC, existing task activity capture, and the new OPS-061 29-assertion workflow test all passed. Full database result: `Files=70, Tests=918, Result: PASS`. OPS-061 is complete.
- **OPS-062 — Reports** — **DONE**
  - Started 2026-10-01: implementing formal V1 reports over the existing RLS-protected transactional sources and bounded production RPCs without introducing a privileged reporting API or a second reporting database. OWNER_ADMIN receives all report families. SALES receives sales-by-period/customer/product plus sanitized customer receivable follow-up. ACCOUNTING receives sales, finance, receivables/payments, purchase history, and gross-margin reporting where authoritative cost data is valid. WAREHOUSE receives inventory on-hand/reserved/available/low-stock and movement history without profitability or purchase-cost exposure. PRINTER_PRODUCTION receives only its assigned production workload/status through the existing sanitized production tracking boundary. Multi-role users receive the union of permitted sections. Sales totals exclude DRAFT/CANCELLED orders and remain separated by currency. Gross margin is deliberately bounded to PLAIN sales lines that have a non-null `inventory_cost_basis_per_base_unit` effective on/before the order date in the same currency; PRINTED lines are excluded because the current sales-line model does not snapshot authoritative actual print cost, and rows lacking an explicit inventory cost basis remain non-authoritative under SOT Section 7. Report date filters constrain source dates. Scaffold verification is pending; no database migration is introduced by OPS-062.
  - Completed 2026-10-01: implementation commit `b081c03f5b8cdccd26990cb200c76036914dab87` added the authenticated `/reports` route, role-aware report navigation, period filters, sales-by-period/customer/product aggregation, sanitized receivable reporting, customer-payment and purchase-history reporting for finance roles, ledger-derived inventory on-hand/reserved/available/low-stock and movement reporting for OWNER_ADMIN/WAREHOUSE, and production workload/status reporting through the existing bounded `print_job_tracking` RPC. Monetary aggregation remains separated by currency. Gross margin is reported only for PLAIN sales lines with a non-null authoritative inventory cost basis effective on/before the order date in the same currency; PRINTED lines and rows lacking a reliable cost basis are excluded rather than estimated. Source review confirms PRINTER_PRODUCTION triggers only the sanitized production query and does not query sales finance, payment, purchase cost, receivables, or margin sources; WAREHOUSE does not query profitability or purchase-cost sources. The route is covered by the existing session-refresh proxy. Scaffold CI run `36772376851` passed dependency install, lint, and Next.js build. OPS-062 introduces no database/schema/migration change, so no new Database Migrations CI run is required; the unchanged database baseline remains verified by run `36770491225` with 70 files / 918 tests / `Result: PASS`. Task-summary arithmetic was also reconciled against the enumerated authoritative task IDs: the SOT contains 32 tasks, not the stale summary value 30. OPS-062 is complete.

## Migration / Release

- **OPS-070 — Spreadsheet mapping and cleaning rules** — **DONE**
  - Completed 2026-10-01: resolved the two SOT migration inputs to the current shared Google Sheets `*SỔ THU - CHI` (Drive ID `<PRIVATE_SOURCE_REF_THU_CHI>`, modified 2026-09-30T09:15:20.915Z) and `*BẢNG GIÁ VỐN` (Drive ID `<PRIVATE_SOURCE_REF_GIA_VON>`, modified 2026-09-30T08:48:18.726Z). The mapping audit inventoried all 17 + 7 sheets, classified canonical vs derived/template/secondary sources, and verified real anomalies including the cross-workbook `IMPORTRANGE`, missing sales-order SKU, free-text suppliers, mixed status semantics, negative inventory, spreadsheet errors, broken legacy quote formulas, non-unique accessory codes, duplicate payment references, fixed-column price tiers, and ambiguous shorthand cost columns. The durable migration contract is `migration/OPS_070_SPREADSHEET_MAPPING_AND_CLEANING_RULES.md`; the machine-readable source manifest for OPS-071 is `migration/ops_070_source_manifest.json`. The contract locks source precedence, exact legacy-to-target mappings, deterministic source-row references, text/number/date/currency normalization, customer/supplier/product dedupe rules, deterministic SKU repair, package parsing, cost/pricing conversion, status decomposition, quarantine reason codes, negative/opening-stock handling, receivable derivation, reconciliation requirements, and immutable source snapshot metadata. No migration/load script was executed; that remains OPS-071.
- **OPS-071 — Migration scripts** — **DONE**
  - Started 2026-10-01: implemented deterministic migration extraction/staging against immutable XLSX snapshots of the two OPS-070-locked source workbooks. The live Google Sheets remain read-only. Snapshot identity, original source modified timestamps, Drive snapshot IDs, byte sizes, and SHA-256 hashes are recorded in `migration/ops_071_snapshot_manifest.json`. The staging tool follows OPS-070 source precedence and cleaning rules, emits target-shaped JSONL records with stable `gdrive:<file_id>/<sheet>/R<row>` provenance, deterministic repaired SKU/UUID identifiers, exact mixed-status inventory, quarantine records for rejected/ambiguous rows, and reconciliation inputs for OPS-072. A separate validator rejects duplicate target IDs, broken staged foreign keys, invalid accepted quantities/amounts, missing quarantine provenance, or false run invariants. Opening inventory/negative stock remains staged only for OPS-072; duplicated/unlabeled pricing blocks are quarantined rather than guessed; unmatched receipts/payments/PO lines remain review exceptions; raw staging/quarantine files are reproducible from snapshots and intentionally excluded from Git because they may contain operational/customer data. Real-source dry-run and validation completed successfully; exact source counts and private migration evidence are intentionally excluded from the public repository. Cross-entity validation and 5 helper unit tests passed locally. Migration Tools CI verification is pending.
  - Completed 2026-10-01: implementation commit `6184432acfa4079441722e97d5ce262d3ace419c` added the deterministic migration staging/validation tools and commit `693943f5181490ea0931d7520fb4ea7bcccd058d` repaired the Migration Tools CI workflow definition. Migration Tools CI run `36777975050` completed successfully; its `validate` job passed migration-tool compilation, unit tests, and committed snapshot-manifest validation. Scaffold CI run `36777975112` on the same commit also completed successfully. OPS-071 is complete.
- **OPS-072 — Reconciliation / opening balances** — **DONE**
  - Completed 2026-10-01 against the immutable OPS-071 snapshots. Snapshot identity, sales, purchasing, goods-receipt, saved-period, selected receivable, and in-scope inventory reconciliation controls passed. Exact financial controls, source/snapshot identifiers, hashes, order/customer/SKU identifiers, and row-level exception evidence are intentionally retained outside the public Git tree.
  - Reconciliation determined that no non-zero opening inventory movement was required for the verified snapshot.
  - Owner-approved migration-exception policy remains authoritative: unresolved historical payment facts are preserved as private migration exceptions and are not inserted into `customer_payments` until valid facts are known. No dates, amounts, allocations, methods, synthetic credits, or reallocations are fabricated. Affected historical receivable/payment history remains explicitly non-authoritative until resolved. Public-safe durable evidence is in `migration/OPS_072_RECONCILIATION_REPORT.md`. OPS-072 is complete and does not block OPS-073 UAT.
- **OPS-073 — UAT / permission testing** — **DONE**
  - Started 2026-10-01: executing the release UAT/permission gate against the current authoritative implementation. The acceptance matrix is recorded at `supabase/tests/OPS_073_UAT_PERMISSION_TESTING.md` and maps V1 Definition-of-Done workflow/permission criteria to the existing automated pgTAP scenarios. A fresh Database Migrations CI run on the complete migration chain and full database test suite is required before OPS-073 may be marked DONE.
  - Completed 2026-10-01: UAT/permission verification commit `15e625f61aceb11b794b44902a3dbb84097690e9` passed Database Migrations CI run `36872629187`: the `migration-smoke` job applied the complete migration chain to a fresh local Supabase database and the full pgTAP suite passed with `Files=70, Tests=918, Result: PASS`. The run includes representative V1 RBAC, purchasing/receipt/inventory, reservation/release/issue, quotation/sales-order, printed-vs-plain branching, delivery, production assignment/QC, customer payment/receivable, operational task, audit, attachment, and storage-boundary scenarios defined by the OPS-073 acceptance matrix. Scaffold CI run `36872629141` on the same commit also passed dependency install, lint, and Next.js build. No permission regression was waived. OPS-073 is complete.
- **OPS-074 — Production deployment** — **IN_PROGRESS**
  - Started 2026-10-01: production Supabase project `OPS-WebApp` (`foclxkjnypjolcwqekku`) is ACTIVE_HEALTHY. Production migration history was found to stop at OPS-050 while main/UAT includes OPS-051 and OPS-061. The first OPS-051 apply attempt correctly failed before commit because production schema drift had removed `private.valid_customer_payment_total(uuid)`, a helper originally defined by OPS-003 and required by the OPS-051 sanitized receivable view. No OPS-061 migration was applied after that failure.
  - Backend deployment progress 2026-10-01: commit `5808ee3ad1904e7e1d4587523787d7bdff56637d` added idempotent repair migration `20261001020500_ops_074_restore_receivable_helper.sql`; commit `66349af70de165e385ff2de7d33119c2506d7a8d` added pgTAP regression coverage. Database Migrations CI run `36875054662` passed the full fresh-database chain with `Files=71, Tests=922, Result: PASS`; Scaffold CI run `36875055270` also passed. Current production migration history now contains `20261001020500 ops_074_restore_receivable_helper`, `20261001021000 ops_051_customer_ledger_receivables`, and `20261001023000 ops_061_operational_tasks`; the Supabase project remains ACTIVE_HEALTHY. Production verification confirms `sales_receivable_followup` and `operational_task_queue` are security-invoker views. Supabase security advisor still reports one ERROR for `public.production_print_job_queue` (`security_invoker=false`); it remains part of OPS-074 remediation.
  - Owner decision 2026-10-01 resolved the hosting-target blocker: production frontend target is **GitHub Pages + Supabase**. Architecture Generation 4 locks the canonical `magasincoffee/OPS-WebApp` repository as **public** and removes the separate deploy-repository fallback. Repository metadata was verified on 2026-10-01 as `visibility=public`, `private=false`, while GitHub Pages is still disabled (`has_pages=false`). Because the visibility change occurred before the planned public-repository scrub, the scrub is now the immediate OPS-074 priority: tracked/history-visible secrets and credentials must be absent, raw migration/customer/supplier data must remain excluded, and committed migration reports/manifests containing internal financial controls, order identifiers, or Drive IDs must be redacted/replaced/moved out of the public repository. After the scrub, OPS-074 continues with static Pages-compatible runtime conversion, Supabase browser session, **Tabler-based UI/UX unification per Section 2.10**, GitHub Actions Pages deployment, Auth redirect configuration, remaining production security remediation, and live verification before DONE.
  - Public-repository scrub progress 2026-10-02: the current `main` tree was redacted to remove exact Drive/source identifiers, snapshot identifiers/hashes, financial controls, legacy order/customer/SKU identifiers, and detailed migration volumes from public migration evidence. Root `.gitignore` was strengthened for raw migration/secret file types; the OPS-071 public manifest CI contract was changed so it no longer requires private Drive/hash evidence; and an automated `Public Repository Scrub` workflow now rejects tracked private artifacts, obvious secrets, Drive identifiers, and sensitive migration evidence patterns. Historical commits created before this scrub may still expose superseded private evidence; Git-history exposure verification/remediation remains required before the repository scrub can be declared complete. OPS-074 remains IN_PROGRESS.
  - Security-boundary remediation progress 2026-10-04: Database Migrations CI on the first `security_invoker=true` view-only fix exposed a real OPS-041 regression because PRINTER_PRODUCTION users do not have broad RLS access to every customer/order/product table joined by the sanitized queue. OPS-074 now replaces normal authenticated direct access to `production_print_job_queue` with the existing `production_mobile_work_queue()` RPC implemented as a bounded SECURITY DEFINER projection that explicitly checks PRINTER_PRODUCTION role and filters by `auth.uid()` assignment; the underlying view remains `security_invoker=true` and is revoked from authenticated users. Regression coverage now requires both the advisor-safe view setting and the RPC/view privilege boundary. Fresh Database Migrations CI verification is pending; OPS-074 remains IN_PROGRESS.
  - **Robot execution continuity protocol (authoritative, 2026-10-04):**
    - `OPS-074` remains the single authoritative task ID until production deployment is fully complete. The checkpoint IDs below are internal execution markers only; they are **not** replacement task IDs and must not be emitted as `TASK_ID` or `NEXT_TASK_ID` in `MAGASIN_TASK_CONTROL_V1`.
    - Every execute/check cycle for OPS-074 must work on exactly the first non-DONE checkpoint in the ledger below. Do not restart a DONE checkpoint unless new concrete regression evidence invalidates its completion evidence. Do not skip ahead to a later checkpoint while the current checkpoint still lacks its required evidence.
    - While a bounded external CI/deployment verification is still running, return `STATUS=RUNNING`, keep `TASK_ID=OPS-074`, and use a bounded `CHECK_AFTER_SECONDS`. A pending external run is not a reason to rediscover, re-plan, or redo already committed work.
    - **Terminal-failure rule:** an external CI/deployment run with `status=completed` and a non-success conclusion (for example `failure`, `cancelled`, or `timed_out`) is **not RUNNING**. If Owner input is not required, a CHECK cycle must surface the failed evidence and return the current OPS-074 work for repair/re-execution (use `STATUS=READY` for the same authoritative task rather than another timed RUNNING wait). Repeated `RUNNING` checks are permitted only while the external run itself is genuinely queued/in_progress/pending.
    - When a checkpoint completes, record its concrete evidence in this SOT, mark that checkpoint DONE, advance `CURRENT_CHECKPOINT` to the next non-DONE checkpoint, and continue OPS-074. Only after checkpoint `074-C07` is DONE and all OPS-074 acceptance requirements are satisfied may the parent task become DONE/COMPLETE and advance to OPS-075.
    - If a checkpoint truly requires Owner action that cannot be performed by the robot, record the exact Owner action in this SOT and use `STATUS=BLOCKED`; otherwise continue autonomously.
  - **OPS-074 checkpoint ledger:**
    - `074-C01` — **Production queue security CI + production verification — DONE.**
      - Code repair merged to `main` via PR #1 at commit `90123538a597d76fcaaccbb4cc55886a9e1ccd3f`.
      - Fresh exact-main Database Migrations CI run `37181157340` completed `success`; Scaffold CI `37181157347`, Public Repository Scrub `37181157366`, and OPS Source Export `37181157355` also completed `success` on the same main commit.
      - Production Supabase migration `20261004055544 ops_074_production_queue_boundary_repair` was applied successfully to project `foclxkjnypjolcwqekku` and is recorded in migration history.
      - Production verification confirms `public.production_print_job_queue` has `security_invoker=true`, `authenticated` has no direct SELECT privilege on the view, and both `production_mobile_work_queue()` and `print_job_tracking(uuid)` are bounded SECURITY DEFINER RPCs with explicit role/user filtering and fixed search paths.
      - Production security advisors no longer report the prior `production_print_job_queue` SECURITY DEFINER-view ERROR. The remaining advisor notices are WARN-level SECURITY DEFINER RPC notices and are not the prior blocking view error.
      - No active production user currently holds PRINTER_PRODUCTION, so live impersonation against a real production assignee was not possible without fabricating a production identity. PRINTER_PRODUCTION access/non-regression is instead covered by the fresh full pgTAP Database Migrations CI, including OPS-040/OPS-041/OPS-042 production assignment, tracking, active mobile queue, and completion semantics.
    - `074-C02` — **Historical Git exposure verification/remediation — DONE.**
      - Initial full-history Public Repository Scrub run `37186017708` correctly failed and identified historical exposure categories without printing secret values: Drive IDs/URL in legacy migration manifests, legacy order/VND controls in historical SOT/reconciliation evidence, and historical snapshot SHA-256 evidence.
      - Remediation rewrote the public branch history to clean snapshot commit `115f38b51a79aabca815d7429880b786aae2b0a9`, preserving the current sanitized tree while severing the sensitive ancestry. At verification time, `main` and the remaining OPS-074 branches all pointed to this clean snapshot.
      - Public Repository Scrub run `37186542825` completed `success` with full-history scanning enabled. Exact-main verification on the same clean snapshot also passed: Database Migrations CI `37186542842`, Scaffold CI `37186542823`, Migration Tools CI `37186542843`, and OPS Source Export `37186542826`.
      - The public canonical repository now retains automated full-history exposure scanning as a release gate.
    - `074-C03` — **Static GitHub Pages runtime + browser Supabase session — DONE.**
      - Static/browser-runtime implementation merged through PR #5 to `main` at commit `e9659c25535f4ba68e899b26278c6618a06427d7`.
      - Production frontend now uses Next.js static export with a browser Supabase client/session; legacy server-rendered routes/helpers and the root server proxy were archived outside the production runtime, and production `app/` + `lib/` retain RLS/RPC as the authorization boundary without service-role credentials.
      - The static-export verification gate rejects production route handlers, `/api/` dependencies, `next/headers`, service-role references, root proxy/middleware server runtime, and unexpected Next server bundles.
      - PR-head verification passed: Scaffold CI `37190082327` completed `success` with install, lint, static build, and static-boundary verification all GREEN; Public Repository Scrub `37190082358` also completed `success`.
      - Exact-main verification on commit `e9659c25535f4ba68e899b26278c6618a06427d7` passed: Scaffold CI `37190492508`, Public Repository Scrub `37190492497`, and OPS Source Export `37190492569` all completed `success`.
    - `074-C04` — **Tabler UI/UX unification — DONE.**
      - Implementation merged through PR #7 to `main` at commit `b90ed12222a79613b5d48754d64a6cd9292bd4e7`.
      - Production frontend now uses one consistent Tabler-style shell across V1 modules with grouped role-aware desktop navigation, collapsible mobile navigation, compact topbar, breadcrumb/action headers, standardized cards/tables/filters/buttons/badges/alerts/loading/empty states, responsive overflow handling, and preserved Supabase query/RPC/RBAC boundaries.
      - A durable Tabler UI acceptance contract was added to Scaffold CI so future changes must retain the shell, responsive navigation, standardized table/state patterns, role-aware filtering, and mobile breakpoint requirements.
      - PR-head verification passed: Scaffold CI `37193639863` and Public Repository Scrub `37193639897` completed `success`.
      - Exact-main verification on commit `b90ed12222a79613b5d48754d64a6cd9292bd4e7` passed: Scaffold CI `37197343664` and Public Repository Scrub `37197343658` completed `success`.
    - `074-C05` — **GitHub Actions Pages deployment — TODO.** Enable/configure deployment from the canonical public repository, publish the static artifact, and establish the final production Pages origin with successful deployment evidence.
    - `074-C06` — **Supabase Auth production redirect/callback configuration — TODO.** Configure the final Pages origin/path for sign-in/reset/confirmation flows and verify the browser session flow without exposing service-role or secret credentials.
    - `074-C07` — **Live production verification + OPS-074 closeout — TODO.** Verify production login, representative roles, primary V1 workflows, production queue, Supabase reads/writes, Pages delivery, security boundaries, and release gates; then update this SOT to mark OPS-074 DONE and advance authority to OPS-075.
  - `CURRENT_CHECKPOINT=074-C05`
  - `NEXT_CHECKPOINT=074-C06` (only after `074-C05` is recorded DONE)

- **OPS-075 — Final spreadsheet cutover** — TODO

### Current task summary

- Total authoritative tasks: **32**
- Done: **30**
- In progress: **1**
- Blocked: **0**
- Todo: **1**

**OPS-002 — Database schema and migrations** is **DONE** after migration application and verification against the standalone OPS Supabase project. **OPS-003 — Authentication and RBAC** is **DONE** after representative permission verification passed in GitHub Actions run `36542929152`. The completed authoritative foundation task is **OPS-004 — Audit/activity/attachment foundation — DONE**. The completed authoritative customer task is **OPS-010 — Customer module — DONE**. The completed authoritative supplier task is **OPS-011 — Supplier module — DONE**. The completed authoritative product-master task is **OPS-012 — Product/SKU/packaging module — DONE**. The completed authoritative cost/pricing task is **OPS-013 — Cost and pricing-rule module — DONE**. The completed authoritative purchase-order task is **OPS-020 — Purchase order workflow — DONE**. The completed authoritative goods-receipt task is **OPS-021 — Goods receipt — DONE**. The completed authoritative inventory-ledger task is **OPS-022 — Inventory ledger — DONE**. The completed authoritative reservation/release/issue task is **OPS-023 — Reservation / release / issue workflow — DONE**. The completed authoritative stocktake/adjustments/low-stock task is **OPS-024 — Stocktake / adjustments / low-stock — DONE**. The completed authoritative quotation task is **OPS-030 — Quotation workflow — DONE**. The completed authoritative sales-order task is **OPS-031 — Sales-order workflow — DONE**. The completed authoritative print-branching task is **OPS-032 — Printed vs no-print branching — DONE**. The completed authoritative delivery task is **OPS-033 — Delivery workflow — DONE**. The completed authoritative print-job task is **OPS-040 — Print-job workflow — DONE**. The completed authoritative production-assignment task is **OPS-041 — Production assignment / mobile work queue — DONE**. The completed authoritative production-QC task is **OPS-042 — QC / production completion evidence — DONE**. The completed authoritative customer-payment task is **OPS-050 — Customer payment recording — DONE**. The completed authoritative customer-ledger task is **OPS-051 — Customer ledger / receivables — DONE**. The completed authoritative dashboard task is **OPS-060 — Role-aware dashboards — DONE**. The completed authoritative operational-task task is **OPS-061 — Operational tasks — DONE**. The completed authoritative reporting task is **OPS-062 — Reports — DONE**. The completed authoritative migration-mapping task is **OPS-070 — Spreadsheet mapping and cleaning rules — DONE**. The completed authoritative migration-script task is **OPS-071 — Migration scripts — DONE**. The completed reconciliation task is **OPS-072 — Reconciliation / opening balances — DONE** under the Owner-approved migration-exception policy documented in `migration/OPS_072_RECONCILIATION_REPORT.md`. The completed authoritative UAT task is **OPS-073 — UAT / permission testing — DONE**. The current authoritative task is **OPS-074 — Production deployment — IN_PROGRESS** under Architecture Generation 4 (public canonical GitHub Pages repository + Supabase) with Tabler as the authoritative V1 UI/UX reference; public-repository scrub, frontend static-runtime conversion, Tabler UI unification, Pages deployment, Auth redirect configuration, remaining production security remediation, and live verification remain. The attachment-metadata and shared activity-log foundation bounded units are implemented; sales-order, customer-payment, print-job, purchase-order, goods-receipt, delivery, operational-task, quotation, quotation-item, and sales-order-item automatic activity capture are implemented and verified; purchase-payment automatic activity capture is implemented and verified in Database Migrations CI run `36550188216`; purchase-order-item automatic activity capture is implemented and verified in Database Migrations CI run `36550817582`; goods-receipt-item automatic activity capture is implemented and verified in Database Migrations CI run `36551394333`; inventory-reservation automatic activity capture is implemented and verified in Database Migrations CI run `36552051051`; inventory-movement automatic activity capture is implemented and verified in Database Migrations CI run `36552732457`; stocktake automatic activity capture is implemented and verified in Database Migrations CI run `36553541607`; stocktake-item automatic activity capture is implemented and verified in Database Migrations CI run `36554188072`; delivery-item automatic activity capture is implemented and verified in Database Migrations CI run `36555375096`; customer automatic activity capture is implemented and verified in Database Migrations CI run `36555973300`; supplier automatic activity capture is implemented and verified in Database Migrations CI run `36556575111`; product automatic activity capture is implemented and verified in Database Migrations CI run `36557165706`; product-variant automatic activity capture is implemented and verified in Database Migrations CI run `36558132582`; product-packaging automatic activity capture is implemented and verified in Database Migrations CI run `36561395045`; supplier-product automatic activity capture is implemented and verified in Database Migrations CI run `36561967418`; product-category automatic activity capture is implemented and verified in Database Migrations CI run `36562492660`; purchase-cost-history automatic activity capture is implemented and verified in Database Migrations CI run `36563386529`; pricing-rule automatic activity capture is implemented and verified in Database Migrations CI run `36564135950`; price-tier automatic activity capture is implemented and verified in Database Migrations CI run `36564703893`; print-job-event automatic activity capture is implemented and verified in Database Migrations CI run `36565316708`; customer-ledger-entry automatic activity capture is implemented and verified in Database Migrations CI run `36566042780`; the 30 material business-table activity-capture bounded units are verified. Print-job attachment metadata access is implemented and verified in Database Migrations CI run `36567074068`; bounded print-job Supabase Storage object access is implemented and verified in Database Migrations CI run `36570360301`; customer-payment attachment metadata access is implemented and verified in Database Migrations CI run `36571242145`; customer-payment Supabase Storage object access is implemented and verified in Database Migrations CI run `36571718123`; sales-order-item artwork attachment metadata access is implemented and verified in Database Migrations CI run `36572620619`; sales-order-item Supabase Storage object access is implemented and verified in Database Migrations CI run `36573457417`; purchase-order document/payment-evidence attachment metadata access is implemented and verified in Database Migrations CI run `36574314272`; purchase-order Supabase Storage object access is implemented and verified in Database Migrations CI run `36575419264`; goods-receipt attachment metadata access is implemented and verified in Database Migrations CI run `36576458191`; goods-receipt Supabase Storage object access is implemented and verified in Database Migrations CI run `36577263639`; delivery attachment metadata access is implemented and verified in Database Migrations CI run `36578189919`; delivery Supabase Storage object access is implemented and verified in Database Migrations CI run `36578782192`; customer attachment metadata access is implemented and verified in Database Migrations CI run `36579810723`; customer Supabase Storage object access is implemented and verified in Database Migrations CI run `36581132483`; supplier attachment metadata access is implemented and verified in Database Migrations CI run `36582503912` after commit `360493385ef5dd9d49f00b65278fb3a642eda9d4` corrected the pgTAP plan from 10 assertions to 9; the `migration-smoke` job applied the complete fresh migration chain and all OPS database smoke tests passed. The final remaining attachment/storage access is implemented and verified; OPS-004 is complete.

---

# 14. Definition of Done for V1

V1 is complete only when all of the following are true:

1. All V1 modules in Section 10 are implemented.
2. Role permissions have been tested with representative users.
3. Printed and plain/no-print sales flows both work end-to-end.
4. Purchase → receipt → stock ledger works end-to-end.
5. Reservation → issue → available-stock calculation is reconciled.
6. Customer payments and receivables reconcile.
7. Migrated customers/products/orders/open inventory/open receivables reconcile against agreed source totals.
8. Production users cannot access restricted financial/cost data.
9. Audit trail exists for material operations.
10. Production deployment is working.
11. Migration/cutover is documented.
12. This SOT reports all V1 tasks as DONE.

---

# 15. Rules for Future Changes

## Business-rule change

Update this SOT before implementation.

## Architecture change

1. increment **Architecture Generation**;
2. document the new decision;
3. document migration/compatibility impact;
4. update tasks/dependencies;
5. only then implement.

## Task completion

When a task is completed:

1. change its status to DONE;
2. record any material design decision in the relevant SOT section;
3. update task summary counts;
4. commit the SOT update together with, or immediately after, the implementation.

---

# 16. Bootstrap Protocol for New Conversations

Use this project bootstrap in a new ChatGPT conversation:

```text
OPS_SINGLE_CONVERSATION_BOOTSTRAP_V1
PROJECT=OPS-WEBAPP
SOT=https://github.com/magasincoffee/OPS-WebApp/blob/main/SOURCE_OF_TRUTH.md

Read SOURCE_OF_TRUTH.md from the beginning before deciding or implementing anything.
SOURCE_OF_TRUTH.md is the sole project authority.
Ignore stale chat, memory, README, and historical state when they conflict with the SOT.
Derive scope, Architecture Generation, current task state, dependencies, and next action only from the SOT.
Continue from the first authoritative TODO/IN_PROGRESS task unless I explicitly assign another task.
After a material implementation or architecture change, update SOURCE_OF_TRUTH.md and its task counts.
Report the Architecture Generation and the task ID being worked on.
```

For continuation cycles in the same or another chat:

```text
OPS_SINGLE_CONVERSATION_NEXT_V1
SOT=https://github.com/magasincoffee/OPS-WebApp/blob/main/SOURCE_OF_TRUTH.md

Re-read the SOT from the beginning.
Continue only from the current authoritative state.
Do not rely on stale conversational state when it conflicts with the SOT.
Report Architecture Generation, completed task IDs, current task ID, and next action.
Update the SOT after material progress.
```

---

# 17. Current Authoritative State

As of **2026-10-01**:

- Architecture Generation: **4**
- Business architecture: **LOCKED**
- Repository: **created**
- Source of Truth: **established**
- Application scaffold: **completed**
- Database schema: **completed and verified on standalone OPS Supabase**
- UI implementation: **in progress — OPS-010 customer module completed; OPS-011 supplier module completed; OPS-012 product/SKU/packaging completed; OPS-013 cost/pricing completed; OPS-020 purchase-order workflow completed; OPS-021 goods receipt completed; OPS-022 inventory ledger completed; OPS-023 reservation/release/issue completed; OPS-024 stocktake/adjustments/low-stock completed**
- Migration implementation: **OPS-070 mapping, OPS-071 migration scripts, and OPS-072 reconciliation/opening balances completed; unresolved legacy payment facts remain preserved as Owner-approved migration exceptions for post-deployment resolution**
- Production deployment: **in progress — public canonical GitHub Pages repository + Supabase authorized under Architecture Generation 4; current-tree public scrub implemented, historical Git exposure verification/remediation plus static-runtime/Pages/security/live verification remain**
- Authentication/RBAC: **completed; representative permissions verified**
- Current authoritative task: **OPS-074 — Production deployment — IN_PROGRESS**

Any later state must be read from this file, not inferred from this paragraph if this file has subsequently been updated.