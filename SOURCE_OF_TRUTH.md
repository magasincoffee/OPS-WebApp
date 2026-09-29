# OPS WebApp — SOURCE OF TRUTH

> **Project ID:** OPS-WEBAPP  
> **Repository:** `magasincoffee/OPS-WebApp`  
> **Architecture Generation:** 1  
> **SOT Version:** 1.0  
> **Status:** ARCHITECTURE_LOCKED / IMPLEMENTATION_IN_PROGRESS  
> **Last authoritative update:** 2026-09-29  
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
- **OPS-002 — Database schema and migrations** — **IN_PROGRESS**
  - Started 2026-09-29: added bounded master-data foundation migration at `supabase/migrations/20260929050100_ops_002_master_data_foundation.sql` covering customers, suppliers, product categories, products/SKUs, packaging conversion, and supplier-product mapping.
  - Continued 2026-09-29: added bounded cost/pricing foundation migration at `supabase/migrations/20260929050500_ops_002_cost_pricing_foundation.sql` covering purchase-cost history, landed/base-unit cost traceability, data-driven pricing rules, quantity tiers, print-cost inputs, and fixed/markup/margin pricing bases.
  - Continued 2026-09-29: added bounded purchasing/goods-receipt foundation migration at `supabase/migrations/20260929051000_ops_002_purchasing_receipt_foundation.sql` covering purchase orders/items, immediate supplier payments, goods receipts/items, packaging-to-base-unit receipt conversion, and derived purchase-order totals.
  - Continued 2026-09-29: added bounded quotation/sales-order foundation migration at `supabase/migrations/20260929051500_ops_002_sales_order_foundation.sql` covering quotations/items, sales orders/items, packaging conversion snapshots, printed-vs-plain line specifications, derived totals, and separate order/print/warehouse/payment status dimensions.
- **OPS-003 — Authentication and RBAC** — TODO
- **OPS-004 — Audit/activity/attachment foundation** — TODO

## Master Data

- **OPS-010 — Customer module** — TODO
- **OPS-011 — Supplier module** — TODO
- **OPS-012 — Product/SKU/packaging module** — TODO
- **OPS-013 — Cost and pricing-rule module** — TODO

## Purchasing / Warehouse

- **OPS-020 — Purchase order workflow** — TODO
- **OPS-021 — Goods receipt** — TODO
- **OPS-022 — Inventory ledger** — TODO
- **OPS-023 — Reservation / release / issue workflow** — TODO
- **OPS-024 — Stocktake / adjustments / low-stock** — TODO

## Sales

- **OPS-030 — Quotation workflow** — TODO
- **OPS-031 — Sales-order workflow** — TODO
- **OPS-032 — Printed vs no-print branching** — TODO
- **OPS-033 — Delivery workflow** — TODO

## Production

- **OPS-040 — Print-job workflow** — TODO
- **OPS-041 — Production assignment / mobile work queue** — TODO
- **OPS-042 — QC / production completion evidence** — TODO

## Finance

- **OPS-050 — Customer payment recording** — TODO
- **OPS-051 — Customer ledger / receivables** — TODO

## Operations / Reporting

- **OPS-060 — Role-aware dashboards** — TODO
- **OPS-061 — Operational tasks** — TODO
- **OPS-062 — Reports** — TODO

## Migration / Release

- **OPS-070 — Spreadsheet mapping and cleaning rules** — TODO
- **OPS-071 — Migration scripts** — TODO
- **OPS-072 — Reconciliation / opening balances** — TODO
- **OPS-073 — UAT / permission testing** — TODO
- **OPS-074 — Production deployment** — TODO
- **OPS-075 — Final spreadsheet cutover** — TODO

### Current task summary

- Total authoritative tasks: **30**
- Done: **2**
- In progress: **1**
- Blocked: **0**
- Todo: **27**

The next task is **OPS-002 — Database schema and migrations**, unless the SOT is updated with a different priority.

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

As of **2026-09-29**:

- Architecture Generation: **1**
- Business architecture: **LOCKED**
- Repository: **created**
- Source of Truth: **established**
- Application scaffold: **completed**
- Database schema: **in progress**
- UI implementation: **not started**
- Migration implementation: **not started**
- Production deployment: **not started**
- Next authoritative task: **OPS-002 — Database schema and migrations**

Any later state must be read from this file, not inferred from this paragraph if this file has subsequently been updated.
