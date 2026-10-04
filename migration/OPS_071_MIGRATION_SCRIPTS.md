# OPS-071 — Migration Scripts

This directory implements the locked `OPS-070` spreadsheet migration contract.

## Inputs

Use the immutable XLSX snapshots recorded in `ops_071_snapshot_manifest.json`. The live Google Sheets are read-only sources and are never modified by these scripts.

## Stage

```bash
python migration/ops_071_stage.py \
  --thu-chi /path/to/OPS-071_2026-10-01_SO-THU-CHI.xlsx \
  --gia-von /path/to/OPS-071_2026-10-01_BANG-GIA-VON.xlsx \
  --output-dir /tmp/ops071_run \
  --source-modified-thu 2026-09-30T09:15:20.915Z \
  --source-modified-gia 2026-09-30T08:48:18.726Z
```

The stage command uses only the Python standard library. It reads effective XLSX cell values, normalizes canonical sheets according to OPS-070, generates deterministic UUID/SKU identifiers, and writes target-shaped JSONL entities plus:

- `quarantine.jsonl` — every review record has a reason code and `source_row_reference`;
- `status_values.json` — the exact legacy mixed-status inventory;
- `reconciliation_inputs.json` — entity counts, source controls, quarantine counts, snapshot identity and invariants for OPS-072.

Raw outputs can contain operational/customer data and must not be committed to Git.

## Validate

```bash
python migration/ops_071_validate.py /tmp/ops071_run
```

Validation fails on duplicate target IDs, broken staged foreign keys, invalid accepted positive-value constraints, missing quarantine source references, or false run invariants.

## Current migration boundaries

- Source precedence is canonical-first. Secondary `COST NẮP` rows that resolve to a canonical SKU are treated as deduplicated evidence rather than duplicate variants.
- Missing/non-unique master SKUs are repaired deterministically with the locked `MIG-<slug>-<hash8>` rule.
- Purchase/sales/payment/receipt rows that cannot resolve deterministically are quarantined, never guessed.
- Legacy `Trạng thái giao` is converted only into dimension-specific hints; it is not copied into one target status field.
- Unlabeled/duplicated pricing blocks are `REVIEW_PRICE_BLOCK`, not auto-loaded.
- Opening inventory/negative adjustments are staged only; OPS-072 owns their acceptance/reconciliation.
- The scripts produce deterministic migration staging. They do not write to the live OPS database and do not perform final cutover; production loading remains gated by OPS-072 reconciliation and later release/cutover tasks.

## Real-source dry run

See `OPS_071_DRY_RUN_REPORT.md`. The report is aggregate-only; raw staging data is intentionally excluded from Git history.
