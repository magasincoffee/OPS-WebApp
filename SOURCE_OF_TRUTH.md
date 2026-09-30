# OPS WebApp — SOURCE OF TRUTH

> **Project ID:** OPS-WEBAPP  
> **Repository:** `magasincoffee/OPS-WebApp`  
> **Architecture Generation:** 1  
> **SOT Version:** 1.0  
> **Status:** ARCHITECTURE_LOCKED / IMPLEMENTATION_IN_PROGRESS  
> **Last authoritative update:** 2026-09-30  
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
- **OPS-012 — Product/SKU/packaging module** — **IN_PROGRESS**
  - Started 2026-09-30: implementing the centralized product master UI/API for category, product, SKU/variant, and packaging conversion using the existing authenticated Supabase Data API and locked RLS. OWNER_ADMIN owns master-data mutations; all V1 roles retain product-reference reads. Cost/pricing configuration remains in OPS-013 and inventory ledger mutations remain in later inventory tasks. Scaffold and database CI verification are pending.
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
- Done: **7**
- In progress: **1**
- Blocked: **0**
- Todo: **22**

**OPS-002 — Database schema and migrations** is **DONE** after migration application and verification against the standalone OPS Supabase project. **OPS-003 — Authentication and RBAC** is **DONE** after representative permission verification passed in GitHub Actions run `36542929152`. The completed authoritative foundation task is **OPS-004 — Audit/activity/attachment foundation — DONE**. The completed authoritative customer task is **OPS-010 — Customer module — DONE**. The completed authoritative supplier task is **OPS-011 — Supplier module — DONE**. The current authoritative task is **OPS-012 — Product/SKU/packaging module — IN_PROGRESS**. The attachment-metadata and shared activity-log foundation bounded units are implemented; sales-order, customer-payment, print-job, purchase-order, goods-receipt, delivery, operational-task, quotation, quotation-item, and sales-order-item automatic activity capture are implemented and verified; purchase-payment automatic activity capture is implemented and verified in Database Migrations CI run `36550188216`; purchase-order-item automatic activity capture is implemented and verified in Database Migrations CI run `36550817582`; goods-receipt-item automatic activity capture is implemented and verified in Database Migrations CI run `36551394333`; inventory-reservation automatic activity capture is implemented and verified in Database Migrations CI run `36552051051`; inventory-movement automatic activity capture is implemented and verified in Database Migrations CI run `36552732457`; stocktake automatic activity capture is implemented and verified in Database Migrations CI run `36553541607`; stocktake-item automatic activity capture is implemented and verified in Database Migrations CI run `36554188072`; delivery-item automatic activity capture is implemented and verified in Database Migrations CI run `36555375096`; customer automatic activity capture is implemented and verified in Database Migrations CI run `36555973300`; supplier automatic activity capture is implemented and verified in Database Migrations CI run `36556575111`; product automatic activity capture is implemented and verified in Database Migrations CI run `36557165706`; product-variant automatic activity capture is implemented and verified in Database Migrations CI run `36558132582`; product-packaging automatic activity capture is implemented and verified in Database Migrations CI run `36561395045`; supplier-product automatic activity capture is implemented and verified in Database Migrations CI run `36561967418`; product-category automatic activity capture is implemented and verified in Database Migrations CI run `36562492660`; purchase-cost-history automatic activity capture is implemented and verified in Database Migrations CI run `36563386529`; pricing-rule automatic activity capture is implemented and verified in Database Migrations CI run `36564135950`; price-tier automatic activity capture is implemented and verified in Database Migrations CI run `36564703893`; print-job-event automatic activity capture is implemented and verified in Database Migrations CI run `36565316708`; customer-ledger-entry automatic activity capture is implemented and verified in Database Migrations CI run `36566042780`; the 30 material business-table activity-capture bounded units are verified. Print-job attachment metadata access is implemented and verified in Database Migrations CI run `36567074068`; bounded print-job Supabase Storage object access is implemented and verified in Database Migrations CI run `36570360301`; customer-payment attachment metadata access is implemented and verified in Database Migrations CI run `36571242145`; customer-payment Supabase Storage object access is implemented and verified in Database Migrations CI run `36571718123`; sales-order-item artwork attachment metadata access is implemented and verified in Database Migrations CI run `36572620619`; sales-order-item Supabase Storage object access is implemented and verified in Database Migrations CI run `36573457417`; purchase-order document/payment-evidence attachment metadata access is implemented and verified in Database Migrations CI run `36574314272`; purchase-order Supabase Storage object access is implemented and verified in Database Migrations CI run `36575419264`; goods-receipt attachment metadata access is implemented and verified in Database Migrations CI run `36576458191`; goods-receipt Supabase Storage object access is implemented and verified in Database Migrations CI run `36577263639`; delivery attachment metadata access is implemented and verified in Database Migrations CI run `36578189919`; delivery Supabase Storage object access is implemented and verified in Database Migrations CI run `36578782192`; customer attachment metadata access is implemented and verified in Database Migrations CI run `36579810723`; customer Supabase Storage object access is implemented and verified in Database Migrations CI run `36581132483`; supplier attachment metadata access is implemented and verified in Database Migrations CI run `36582503912` after commit `360493385ef5dd9d49f00b65278fb3a642eda9d4` corrected the pgTAP plan from 10 assertions to 9; the `migration-smoke` job applied the complete fresh migration chain and all OPS database smoke tests passed. The final remaining attachment/storage access is implemented and verified; OPS-004 is complete.

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

As of **2026-09-30**:

- Architecture Generation: **1**
- Business architecture: **LOCKED**
- Repository: **created**
- Source of Truth: **established**
- Application scaffold: **completed**
- Database schema: **completed and verified on standalone OPS Supabase**
- UI implementation: **in progress — OPS-010 customer module completed; OPS-011 supplier module completed; OPS-012 product/SKU/packaging underway**
- Migration implementation: **not started**
- Production deployment: **not started**
- Authentication/RBAC: **completed; representative permissions verified**
- Current authoritative task: **OPS-012 — Product/SKU/packaging module — IN_PROGRESS**

Any later state must be read from this file, not inferred from this paragraph if this file has subsequently been updated.