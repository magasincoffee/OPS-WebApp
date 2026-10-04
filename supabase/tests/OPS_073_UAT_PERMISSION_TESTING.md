# OPS-073 — UAT / Permission Testing

Status: IN_PROGRESS
Date: 2026-10-01
Authority: SOURCE_OF_TRUTH.md, Architecture Generation 2

## Purpose

This file is the durable acceptance matrix for OPS-073. The task is complete only after the current main-branch implementation passes the fresh-database CI gate and the application scaffold/build gate.

The UAT gate deliberately reuses the existing executable acceptance scenarios rather than duplicating business logic in a second test framework. Database Migrations CI applies the complete migration chain to a fresh local Supabase database and then runs every pgTAP test under `supabase/tests/database`.

## V1 acceptance matrix

| Acceptance criterion | Automated evidence |
| --- | --- |
| Representative V1 roles resolve correctly and restricted data stays hidden | `ops_003_representative_permissions.test.sql` |
| Goods receipt is role-bounded and does not expose purchasing cost data to warehouse | `ops_021_goods_receipt_workflow_access.test.sql` |
| Purchase → receipt → immutable stock ledger increases on-hand/available stock and posts traceable cost history | `ops_022_inventory_ledger_workflow.test.sql` |
| Reservation → release / issue reconciles ledger-derived on-hand, reserved and available stock | `ops_023_reservation_release_issue_workflow.test.sql` |
| Quotation workflow remains operational before conversion | `ops_030_quotation_workflow.test.sql` |
| Sales-order lifecycle and locked status dimensions remain operational | `ops_031_sales_order_workflow.test.sql` |
| PLAIN orders bypass print production and PRINTED lines generate production requirements | `ops_032_print_branching.test.sql` |
| Delivery workflow remains role-bounded and operational | `ops_033_delivery_workflow.test.sql` |
| Printed requirements create and progress print jobs through the production workflow | `ops_040_print_job_workflow.test.sql` |
| Production users see only assigned/sanitized mobile work queue data | `ops_041_production_assignment_mobile_queue.test.sql` |
| Production QC/completion evidence remains controlled and auditable | `ops_042_qc_completion_evidence.test.sql` |
| Accounting/Owner can record valid payments; overpayment and unauthorized SALES writes are rejected | `ops_050_customer_payment_recording.test.sql` |
| Customer debit/payment ledger reconciles receivables and preserves immutable history | `ops_051_customer_ledger_receivables.test.sql` |
| Operational task assignment remains role-bounded | `ops_061_operational_tasks.test.sql` |
| Audit/activity and attachment/storage boundaries remain covered | all `ops_004_*.test.sql` scenarios in the same fresh-database run |

## Definition-of-Done mapping

SOT Section 14 criteria exercised by OPS-073:

1. Role permissions tested with representative users.
2. Printed and plain/no-print sales paths verified through executable workflow tests.
3. Purchase → receipt → stock ledger verified end-to-end.
4. Reservation → issue → available-stock reconciliation verified.
5. Customer payments and receivables reconciled.
6. Production users denied restricted financial/cost data.
7. Existing material-operation audit trail and attachment/storage controls re-run in the same CI gate.

Migration reconciliation itself remains authoritative from OPS-072. Production deployment and final spreadsheet cutover remain OPS-074 and OPS-075 respectively.

## Required completion evidence

OPS-073 may be marked DONE only when all of the following are true on a commit containing this matrix:

- Database Migrations CI: SUCCESS.
- The `migration-smoke` job applies the complete migration chain to a fresh database.
- `supabase test db` returns PASS for the full database suite, including all scenarios listed above.
- Scaffold CI: SUCCESS (dependency install, lint, Next.js build).
- No failing permission regression is waived or converted into an undocumented exception.

## Run evidence

Pending current GitHub Actions runs triggered by this file.
