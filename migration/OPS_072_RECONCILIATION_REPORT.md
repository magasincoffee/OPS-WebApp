# OPS-072 — Reconciliation / Opening Balances

**Task:** OPS-072  
**Architecture Generation:** 1  
**Source of Truth:** `SOURCE_OF_TRUTH.md`  
**Snapshot run:** `OPS071-20261001-A`  
**Status:** BLOCKED on Owner payment-history decisions

## Scope executed

OPS-072 was executed against the two immutable XLSX snapshots recorded by `migration/ops_071_snapshot_manifest.json`. The live Google Sheets were not modified and no production database write was performed.

The reconciliation verified snapshot SHA-256 identity, source document money controls, stock/opening-balance logic, the selected legacy receivable checkpoint, the saved period report checkpoint, and payment-history conditions against the current OPS payment workflow.

## Snapshot identity

Both XLSX SHA-256 values match the committed OPS-071 snapshot manifest exactly:

- `thu_chi`: `cd4654a3f73b4948f7ab42200fdd5414e37e910c460a2bf5a7d1fa8b49a3d355`
- `gia_von`: `b7dff499f94cac04984b51b4cd22889dfc6e1e751309ff63728c6331b75c5689`

## Source control reconciliation

| Control | Result |
| --- | ---: |
| Sales-order business rows | 685 |
| Sales-order groups | 303 |
| Sales document total | 466,748,210 VND |
| Sales line ↔ document total mismatches | 0 |
| Purchase-order business rows | 180 |
| Purchase-order groups | 17 |
| Purchase document total | 18,629,000 VND |
| Purchase line ↔ document total mismatches | 0 |
| Goods-receipt business rows | 109 |
| Goods-receipt groups | 14 |
| Goods-receipt document total | 182,775,420 VND |
| Receipt line ↔ document total mismatches | 0 |
| Payment business rows | 340 |
| Source payment total | 423,402,910 VND |

The saved legacy period report reconciles exactly from canonical transaction rows:

- sales: `148,130,850 VND`;
- payments: `141,267,350 VND`;
- debt: `6,863,500 VND`.

The selected `CÔNG NỢ KHÁCH HÀNG` checkpoint (`KH0096`) also reconciles exactly: source/derived orders `6,343,000 VND`, source/derived payments `6,343,000 VND`, balance `0 VND`.

## Inventory and opening balance decision

The `THẺ KHO` current-stock side table contains 69 in-scope SKU rows. All **69/69** reconcile exactly from source transaction evidence using SKU-linked goods receipts minus SKU-linked sales issues.

The only staged `Tồn đầu` candidate is `UKP95-700PP-C-T3 = -46,415`. It is **rejected as redundant**: receipt-minus-sales already equals the source closing quantity (`-65,765`) without applying that candidate. Applying it would double-count the negative opening position.

Therefore OPS-072 accepts **no non-zero opening inventory balance** and no opening inventory movement should be posted for this snapshot.

## Payment reconciliation blockers

The source payment history cannot be loaded losslessly under the current OPS payment invariants without Owner decisions:

1. **149** payment rows have no legacy payment method. Of these, **136** otherwise have a usable date, positive amount, and linked order. They can be represented traceably as `LEGACY_UNSPECIFIED` plus source-row provenance; this does not assert an actual historical method.
2. **13** payment rows have no payment date. The OPS schema requires a payment date, while OPS-070 prohibits silently inventing missing/invalid dates.
3. **1** payment row has no usable amount.
4. **8** sales orders have source payment totals greater than their order totals. The current OPS workflow correctly rejects overpayment, and source evidence is insufficient to decide which payment row is duplicate, superseded, mis-keyed, or belongs elsewhere.

Undated payment order numbers:

- `DH-10092026-004`
- `DH-11092026-001`
- `DH-17092026-001`
- `DH-18082026-006`
- `DH-19082026-001`
- `DH-20082026-005`
- `DH-23082026-001`
- `DH-23082026-002`
- `DH-24082026-004`
- `DH-25082026-001`
- `DH-26082026-001`
- `DH-27082026-002` (also has no usable amount)
- `DH-27082026-003`

Overpayment order groups:

| Order | Order total | Source payment total | Excess |
| --- | ---: | ---: | ---: |
| `DH-23062026-001` | 13,723,000 | 20,143,000 | 6,420,000 |
| `DH-20072026-001` | 2,865,450 | 3,365,450 | 500,000 |
| `DH-06082026-003` | 2,892,000 | 5,584,000 | 2,692,000 |
| `DH-15082026-002` | 844,500 | 855,500 | 11,000 |
| `DH-16082026-001` | 418,000 | 836,000 | 418,000 |
| `DH-03092026-001` | 1,573,500 | 1,648,500 | 75,000 |
| `DH-17092026-001` | 1,013,500 | 1,213,500 | 200,000 |
| `DH-21092026-005` | 1,658,000 | 3,316,000 | 1,658,000 |

Because the source period report validates the raw payment totals, these rows must not simply be dropped or truncated to satisfy the target constraint; doing so would alter authoritative source receivable totals.

## Owner input required to unblock OPS-072

Owner must provide/confirm the authoritative treatment for:

- the 13 undated historical payment rows: actual payment date, or an explicit approved migration-date policy;
- the one payment with no usable amount (`DH-27082026-002`): authoritative amount/treatment; and
- the 8 overpayment order groups: which source payment rows are valid, duplicated/superseded, corrected, or should be reassigned.

No guessed dates, truncated payments, hidden reallocations, synthetic credits, or fabricated historical payment methods were applied.

## Verification

Real-snapshot reconciliation passed every non-ambiguous control above:

- snapshot identity: PASS;
- sales money controls: PASS;
- purchase money controls: PASS;
- receipt money controls: PASS;
- saved period report checkpoint: PASS;
- selected customer receivable checkpoint: PASS;
- inventory: 69/69 SKU closing balances reconciled;
- opening inventory: no non-zero opening movement required.

OPS-072 remains blocked solely on the documented Owner payment-history decisions.