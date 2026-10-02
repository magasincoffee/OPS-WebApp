# OPS-070 — Spreadsheet Mapping and Cleaning Rules

**Task:** OPS-070 — Spreadsheet mapping and cleaning rules  
**Architecture Generation:** 1  
**Source of Truth:** `SOURCE_OF_TRUTH.md`  
**Status:** LOCKED for OPS-071 implementation  
**Captured:** 2026-10-01

> **Public repository copy:** exact Drive/source identifiers are intentionally redacted. Private migration evidence remains outside the public Git tree.

This document is the durable migration contract for the two spreadsheet sources named by the SOT. It defines what is authoritative, how legacy rows map into the OPS schema, which rows require review or quarantine, and which derived/template sheets must not be imported as runtime truth.

It does **not** execute data migration. SQL/ETL/load implementation belongs to OPS-071. Opening-balance reconciliation belongs to OPS-072. Final production cutover belongs to OPS-075.

## 1. Resolved source workbooks

The SOT names the migration inputs as `*SỔ THU - CHI.xlsx` and `*BẢNG GIÁ VỐN.xlsx`. The current accessible source-of-record equivalents are native Google Sheets with the exact SOT titles:

| SOT source | Resolved live source | Drive ID | Last modified (Drive) | Migration use |
| --- | --- | --- | --- | --- |
| `*SỔ THU - CHI.xlsx` | `*SỔ THU - CHI` | `<PRIVATE_SOURCE_REF_THU_CHI>` | 2026-09-30T09:15:20.915Z | customers, sales orders, receipts/payments, purchasing/receipts, inventory events, delivery-related legacy context |
| `*BẢNG GIÁ VỐN.xlsx` | `*BẢNG GIÁ VỐN` | `<PRIVATE_SOURCE_REF_GIA_VON>` | 2026-09-30T08:48:18.726Z | product/SKU master, package conversion, cost history inputs, selling-price tiers |

A second older Drive file with the same `*BẢNG GIÁ VỐN` title exists, but it was last modified in 2025. It is **not** selected for V1 migration because the current `SẢN PHẨM` tab in `*SỔ THU - CHI` explicitly imports from Drive ID `<PRIVATE_SOURCE_REF_GIA_VON>`, establishing the current cross-workbook dependency.

### Read-only source rule

The migration process must never rewrite these two source workbooks. Before OPS-071 first extraction and again immediately before OPS-075 cutover:

1. export complete immutable snapshots;
2. record Drive ID, Drive modified timestamp, exported file size, and SHA-256;
3. store snapshot identity in migration execution metadata;
4. abort load/reconciliation if source identity changed unexpectedly between extraction and validation.

## 2. Source precedence

Where duplicate or derived data exists, use this order:

1. **Dedicated transaction/master sheet with direct entered rows**
2. **Explicit current cross-workbook master source**
3. **Secondary/historical/reference sheet**
4. **Derived report/template/helper sheet — reconciliation only, never runtime truth**

Specific precedence:

- Customer master: `KHÁCH HÀNG`.
- Sales order history: `ĐƠN HÀNG`; printable `ĐƠN HÀNG KHÁCH` is derived only.
- Customer payments: columns A:I of `THU TIỀN`; `CÔNG NỢ KHÁCH HÀNG` is derived reconciliation evidence only.
- Purchasing: `LÊN ĐƠN NCC`; printable `ĐƠN ĐẶT HÀNG NCC` is derived only.
- Goods receipts: `NHẬP KHO`.
- Inventory event candidates: `NHẬP KHO`, `ĐIỀU CHỈNH KHO`, and reliable sales-order issue evidence; `THẺ KHO` is derived reconciliation evidence, not an event source when the source transaction is already migrated.
- Product/cost/pricing master: current `BẢNG BÁO GIÁ` in `*BẢNG GIÁ VỐN`, because `SẢN PHẨM` imports from it.
- `BẢNG BÁO GIÁ MỚI`, `COST NẮP`, `COST PHỤ KIỆN`, `Trang tính5`, and `Ý Nam`: secondary/conflict-resolution evidence only unless a row is explicitly promoted by a deterministic OPS-071 rule.
- Hidden `DATA`, report tabs, lookups, print templates, and broken `BÁO GIÁ` are never migration truth.

## 3. Workbook inventory and classification

### 3.1 `*SỔ THU - CHI` — 17 sheets

| Sheet | Classification | Canonical for migration? | Target / use |
| --- | --- | ---: | --- |
| `SẢN PHẨM` | cross-workbook derived product cache | No | validation only; current rows import from `*BẢNG GIÁ VỐN` |
| `KHÁCH HÀNG` | master data | **Yes** | `customers` |
| `CHÀNH XE` | carrier reference | Conditional | delivery notes/reference only when linked to an order; otherwise snapshot |
| `ĐIỀU CHỈNH KHO` | inventory adjustment/opening candidates | **Yes, staged** | OPS-072 opening/adjustment candidates; never load negative/ambiguous rows blindly |
| `NHẬP KHO` | goods receipt history | **Yes** | `goods_receipts`, `goods_receipt_items`; purchase linkage when resolvable |
| `ĐƠN HÀNG` | sales order history | **Yes** | `sales_orders`, `sales_order_items`; downstream delivery/payment/print derivation |
| `ĐƠN HÀNG KHÁCH` | printable invoice template | No | exclude |
| `LÊN ĐƠN NCC` | purchase order history | **Yes** | `purchase_orders`, `purchase_order_items` |
| `ĐƠN ĐẶT HÀNG NCC` | printable PO template | No | exclude |
| `MẪU IN` | shipping/label template | No | exclude |
| `THU TIỀN` | customer payment history + helper columns | **Yes, A:I only** | `customer_payments` |
| `BÁO CÁO` | derived report | No | reconciliation only |
| `THẺ KHO` | derived inventory card/current balance | No | OPS-072 reconciliation only |
| `TRA CỨU` | derived lookup | No | exclude |
| `CÔNG NỢ KHÁCH HÀNG` | derived receivable report | No | OPS-072 reconciliation only |
| `THAM SỐ` | legacy configuration hints | Conditional | only explicitly mapped safe values |
| `DATA` | hidden helper/cache | No | exclude; contains `#N/A` / `#REF!` evidence |

### 3.2 `*BẢNG GIÁ VỐN` — 7 sheets

| Sheet | Classification | Canonical for migration? | Target / use |
| --- | --- | ---: | --- |
| `COST NẮP` | secondary accessory cost/price reference | Conditional | conflict fill/review; duplicate/non-unique codes require generated SKU |
| `BẢNG BÁO GIÁ` | current operational product/cost/pricing master | **Yes** | products, variants, packaging, cost history, pricing tiers |
| `BẢNG BÁO GIÁ MỚI` | newer/work-in-progress price model | Secondary | compare/conflict report; do not override canonical automatically |
| `COST PHỤ KIỆN` | secondary accessory cost/price reference | Conditional | conflict fill/review; repeated `Mã SP` values are non-unique |
| `Trang tính5` | ad-hoc legacy cost sheet | Secondary | reference/review only |
| `BÁO GIÁ` | broken legacy derived quote | No | exclude; current source has `#REF!` to a missing sheet |
| `Ý Nam` | historical supplier quote | Secondary | historical evidence only unless supplier/source identity is resolved |

## 4. Source-row traceability

Every staged row must carry a stable source reference:

`gdrive:<file_id>/<sheet>/R<1-based-row-number>`

Examples:

- `gdrive:<PRIVATE_SOURCE_REF_THU_CHI>/ĐƠN HÀNG/R2`
- `gdrive:<PRIVATE_SOURCE_REF_GIA_VON>/BẢNG BÁO GIÁ/R10`

When one source row creates multiple target rows, all target/staging records retain the same source reference plus a deterministic component suffix such as `#order`, `#item`, `#packaging`, `#cost`, or `#tier-1000`.

No source-row identity may depend only on the displayed legacy document number, because duplicates exist in real data.

## 5. Global cleaning rules

### 5.1 Text

For matching only:

1. Unicode NFC normalize.
2. Trim leading/trailing whitespace.
3. Collapse repeated internal whitespace to one space.
4. Normalize line breaks to `\n`.
5. Compare case-insensitively using Vietnamese-aware Unicode text.

For stored human-facing fields, preserve cleaned original casing where practical.

### 5.2 Placeholder/null values

Treat the following as missing/error tokens when a field is not explicitly textual:

- empty string
- whitespace-only
- `-`
- `--`
- `???`
- `#N/A`
- `#REF!`
- spreadsheet error cells

Never coerce these to numeric zero, false, or a valid identifier.

### 5.3 Numbers

Use the Sheet **effective numeric value**, not the formatted display string. Vietnamese formatted values such as `1.000` are ambiguous as text but unambiguous as spreadsheet numeric values.

Rules:

- reject NaN/error;
- preserve up to schema precision;
- quantities must respect target positivity/non-zero rules;
- monetary fields must be non-negative unless the target explicitly models a signed movement;
- negative stock is an exception to reconcile, not a value to silently clamp to zero.

### 5.4 Dates and time zone

Source locale is `vi_VN`, source time zone is `Asia/Saigon`.

- Parse date strings as day/month/year when not represented by a native date serial.
- Persist target date-only fields as ISO `YYYY-MM-DD`.
- For legacy date-only values that must become `timestamptz`, use an explicit Asia/Ho_Chi_Minh local timestamp chosen by the loader and record the conversion policy. Prefer local noon when only the calendar date matters, avoiding UTC day rollover.
- Invalid or impossible dates go to review/quarantine.

### 5.5 Currency

V1 source rows are assumed `VND` only when no explicit contradictory currency exists and the source context is one of the two locked workbooks. Persist `currency_code='VND'` on those accepted rows.

Never aggregate or reconcile different currencies into one number.

## 6. Customer mapping

Source: `KHÁCH HÀNG`

| Legacy column | Target |
| --- | --- |
| `Mã KH` | `customers.customer_code` |
| `Tên THƯƠNG HIỆU` | `customers.brand_name`; preferred display label |
| `Người liên hệ` | `customers.contact_name` |
| display-name rule | `customers.display_name = brand_name` when present; otherwise cleaned contact name |
| `Số điện thoại` | `customers.phone` |
| `Địa chỉ` | `customers.address` |
| `Ghi chú` | `customers.notes` |
| `Mã số thuế` | no dedicated V1 column; preserve in tagged migration note/source snapshot |
| `Hạn mức công nợ` | no dedicated V1 field; preserve only as tagged legacy metadata; **never** use as receivable balance |
| `GIAO DỊCH GẦN NHẤT` | derived; do not import |

Customer deduplication precedence:

1. exact non-placeholder `customer_code`;
2. normalized phone when unique;
3. normalized brand name + normalized address;
4. otherwise create a distinct customer and emit a review record.

Name-only fuzzy matching must never automatically merge customers.

Conflicting customer codes or a single normalized phone mapped to materially different names/addresses are hard review exceptions.

## 7. Product, SKU, packaging, cost, and pricing mapping

### 7.1 Canonical product source

Primary source: `*BẢNG GIÁ VỐN / BẢNG BÁO GIÁ`.

The current operational `SẢN PHẨM` sheet imports directly from this tab, therefore `SẢN PHẨM` is a cache/derived presentation, not the canonical product source.

Canonical visible fields include:

- product name
- `MÃ SP`
- `NHÓM SP`
- quantity-based supplier price columns
- `QUY CÁCH`
- `GIÁ NHẬP`
- `VẬN CHUYỂN`
- `GIÁ VỐN`
- quantity-tier selling-price blocks
- material/category-like labels
- legacy availability status

### 7.2 Product / variant target

| Source | Target |
| --- | --- |
| product name | `products.name` / `product_variants.variant_name` as appropriate |
| `NHÓM SP` | `products.product_type` when semantically a type; otherwise review/tagged metadata |
| `MÃ SP` | `product_variants.sku_code` |
| `ĐVT` | base/sale/purchase unit context; do not blindly store package unit as base unit |
| material labels | tagged product description/normalization input when useful |
| status such as `SẴN KHO`, `CHỜ NHẬP HÀNG` | legacy availability metadata only; not `is_active` unless explicitly resolved |
| `TỒN TỐI THIỂU` from SỔ source when valid | `product_variants.minimum_stock_quantity` |

Do not collapse cup/lid/accessory variants that differ by material, diameter, capacity, color, packaging, or vendor formulation merely because their names are similar.

### 7.3 SKU repair/generation

An existing source SKU is accepted only when it is:

- non-placeholder;
- normalized/trimmed;
- unique for one normalized product variant;
- not a generic repeated category token such as the observed accessory code `Muỗng` used by multiple different products.

Normalize accepted SKU text to a stable uppercase form without changing semantic punctuation.

For missing, invalid, or non-unique SKUs, generate deterministically:

`MIG-<ASCII-SLUG>-<HASH8>`

where `HASH8` is the first 8 lowercase hex characters of SHA-256 over:

`<source_file_id>|<sheet>|<row>|<clean_product_name>|<clean_package_text>`

Store the original raw SKU and generated-SKU reason in migration staging metadata.

Never use a random UUID-derived visible SKU and never use fuzzy matching to assign an existing SKU.

### 7.4 Packaging

Parse simple explicit patterns such as:

- `1.000 cái/ Thùng`
- `2.000 cái/ Thùng`
- `1.000 cái/ Bao`
- `5000 cái/ Thùng`

into:

- `product_packaging.package_name`
- deterministic `package_code`
- `units_per_package`
- purchase/sale default flags only where source semantics are explicit

If a package string contains multiple nested units, weights, free text, or cannot be parsed deterministically, mark `REVIEW_PACKAGING`. Do not guess conversion factors.

### 7.5 Cost history

For an accepted canonical `BẢNG BÁO GIÁ` row, let:

- `U = units_per_purchase_unit` parsed from `QUY CÁCH`
- `P = GIÁ NHẬP` (per base unit in current sheet semantics)
- `F = VẬN CHUYỂN` (per base unit)
- `C = GIÁ VỐN` (explicit legacy cost per base unit)

Map only when values are numeric/non-negative and packaging is deterministic:

- `purchase_cost_history.purchase_unit = parsed package unit`
- `units_per_purchase_unit = U`
- `purchase_price_per_purchase_unit = P * U`
- `freight_cost_per_purchase_unit = F * U`
- `inventory_cost_basis_per_base_unit = C` only when `C > 0` and the legacy `GIÁ VỐN` field is explicit
- `source_reference = gdrive:.../R...`

For `other_allocated_cost_per_purchase_unit`:

- if `C >= P + F` and the relationship reconciles arithmetically, candidate other allocated cost is `(C-P-F)*U`;
- if `C < P+F`, columns are ambiguous, or an unlabeled fee is required to reconcile, do **not** infer a negative/hidden allocation — emit a review exception.

Observed shorthand columns such as `ROS TM`, `VC`, duplicate `LÃI`, or unlabeled price blocks must be retained as raw staging metadata unless their meaning is explicitly resolved before OPS-071 load.

Supplier quantity-quote fields such as `GIÁ >15 THÙNG` / `GIÁ <15 THÙNG` do not map cleanly to the V1 purchase-cost history model. Preserve them in staging/snapshot metadata; do not flatten them into one authoritative purchase cost automatically.

### 7.6 Selling-price tiers

Legacy fixed columns such as `1000`, `3000`, `5000`, `10.000` are converted to data-driven `pricing_rules` + `price_tiers` only when:

- the surrounding block heading identifies the selling context;
- the quantity header is numeric and increasing;
- each cell is a valid non-negative selling price;
- currency/context is unambiguous.

Each explicit pricing context becomes a separate `pricing_rules` row. Quantity headers become tier minimums; the next threshold minus one may define an inclusive maximum when appropriate, while the last tier is open-ended.

Unlabeled or duplicated pricing blocks must be reported as `REVIEW_PRICE_BLOCK`, not silently merged.

## 8. Supplier and purchasing mapping

### 8.1 Supplier master

No reliable dedicated supplier master exists in the selected source pair. Supplier names are free text in `LÊN ĐƠN NCC` and `NHẬP KHO`.

Create `suppliers` from the union of accepted supplier strings.

Normalization:

1. NFC + trim/collapse whitespace;
2. case-insensitive exact normalized-name key;
3. strip placeholder-only values;
4. never fuzzy-auto-merge different names.

If two spellings appear similar but not exact after normalization, create separate staging candidates and emit `REVIEW_SUPPLIER_DUPLICATE`.

Generate deterministic supplier codes as `MIG-SUP-<HASH8>` only when no reliable legacy code exists.

### 8.2 Purchase orders

Source: `LÊN ĐƠN NCC`.

| Legacy | Target |
| --- | --- |
| `Mã phiếu đặt hàng` | `purchase_orders.po_number` |
| `Ngày ngày đặt` | `purchase_orders.order_date` |
| `Nhà cung cấp` | normalized supplier -> `supplier_id` |
| `Mã SP` | product variant lookup |
| `ĐVT` | `purchase_order_items.purchase_unit` |
| `Số lượng` | package quantity |
| `Đơn giá nhập` | `unit_cost_per_purchase_unit` |
| `Vận chuyển` | order/item legacy metadata; allocate only under explicit OPS-071 rule |
| `Ghi chú` | notes |
| `Thành tiền` / `Tổng Tiền Đơn` | reconciliation checks, not authoritative generated target fields |

Group rows by normalized PO number. All rows in a PO group must agree on supplier and order date or the whole group is quarantined.

### 8.3 Goods receipts

Source: `NHẬP KHO`.

| Legacy | Target |
| --- | --- |
| `Mã phiếu nhập` | `goods_receipts.goods_receipt_number` |
| `Ngày nhập` | `goods_receipts.received_at` |
| `Nhà cung cấp` | supplier consistency check |
| `Mã SP` | product variant lookup |
| `Số lượng` | receipt package/base quantity according to source unit semantics |
| `Đơn giá nhập` | purchase/cost reconciliation |
| `Vận chuyển` | cost reconciliation |
| `Giá Vốn` | cost reconciliation |
| `Thành tiền` / `Tổng Tiền Đơn` | reconciliation |
| `Ghi chú` | notes |

Link a receipt line to a migrated purchase-order item only when PO/supplier/SKU/quantity context resolves deterministically.

An unmatched receipt becomes `REVIEW_ORPHAN_RECEIPT`. OPS-071 may create a clearly tagged synthetic legacy PO only if that behavior is implemented explicitly and the reconciliation report exposes it; no silent synthetic purchasing history.

## 9. Sales-order mapping

Source: `ĐƠN HÀNG`.

| Legacy | Target |
| --- | --- |
| `Mã đơn hàng` | `sales_orders.order_number` |
| `Ngày đặt` | `sales_orders.order_date` |
| `Ngày giao` | requested due / delivery context when valid |
| `Mã KH` | customer lookup |
| customer/brand/phone/address columns | customer consistency + delivery snapshot context |
| `Tên sản phẩm`, `Mã SP` | product variant lookup |
| `ĐVT` | `sales_order_items.sale_unit` |
| `Số lượng` | `sale_quantity` and base quantity through resolved conversion |
| `Đơn giá bán` | `unit_price_per_sale_unit` |
| `Thành tiền` | reconciliation against generated line total |
| `TỔNG ĐƠN HÀNG` | order-level reconciliation only |
| `GHI CHÚ` | notes / print-context review |
| `Trạng thái giao` | **not mapped directly to a single target status** |

Group by normalized order number. Within one group, order date, customer, and order-level total must be consistent.

Observed legacy values such as `ĐÃ THU` and `CHỜ IN` occur in a field named `Trạng thái giao`. They mix payment/production/delivery semantics and must be classified through an explicit status map before load.

No single legacy status may overwrite multiple independent target dimensions.

### Missing SKU in sales orders

A real `ĐƠN HÀNG` row has a blank `Mã SP`. Resolution order:

1. exact cleaned product-name match to one canonical variant;
2. exact name + package/unit context;
3. if still unresolved, quarantine as `REVIEW_MISSING_SKU_ORDER_LINE`.

Do not generate a new SKU from a transaction row when a canonical master product likely exists; generated SKUs are for master-source repair, not transaction-side guesses.

## 10. Payment and receivable mapping

### 10.1 Customer payments

Only columns A:I of `THU TIỀN` are canonical:

`Mã phiếu thu | Ngày thu | Mã đơn hàng | Mã KH | Tên khách hàng | Số tiền thu | Tổng đơn hàng | Hình thức thanh toán | Người thu`

Ignore helper/side-table columns to the right.

| Legacy | Target |
| --- | --- |
| `Mã đơn hàng` | `customer_payments.sales_order_id` |
| `Mã KH` | customer consistency check |
| `Số tiền thu` | `amount` |
| `Ngày thu` | `payment_date` |
| `Hình thức thanh toán` | `payment_method` plus tagged legacy meaning if needed |
| `Mã phiếu thu` | `reference`, **not unique identity** |
| `Người thu` | migration note/actor reference; do not fabricate auth user |
| `Tổng đơn hàng` | reconciliation only |

Accepted historical payment rows are loaded as source-backed `POSTED` payments unless explicitly rejected/quarantined. Values such as `CHUYỂN CỌC` and `CHUYỂN ĐỦ` describe payment intent/method and do not become the target lifecycle status.

The source contains duplicate displayed receipt references. Therefore payment idempotency must be keyed by source-row reference, not `Mã phiếu thu`.

### 10.2 Receivables

Do **not** import `CÔNG NỢ KHÁCH HÀNG / Tổng phải thu` as an editable customer balance.

OPS target receivables are derived from:

1. migrated sales-order debits;
2. migrated valid customer-payment credits;
3. target order/payment lifecycle.

`CÔNG NỢ KHÁCH HÀNG` is used only as an OPS-072 reconciliation checkpoint.

## 11. Inventory and opening-balance rules

### 11.1 Event precedence

Use source events where reliable:

- accepted goods receipts -> receipt-driven inventory movement;
- accepted sales issue/delivery evidence -> order-linked issue workflow;
- explicit `ĐIỀU CHỈNH KHO` rows -> staged adjustment/opening candidates.

Do not import `THẺ KHO` as a second movement stream when its rows are already derived from those same source transactions.

### 11.2 Negative inventory

Real source `THẺ KHO` rows contain negative current stock values. Real `ĐIỀU CHỈNH KHO` rows can contain negative `Tồn đầu` values.

Rules:

- never clamp to zero silently;
- never invent a receipt to erase a negative value;
- produce per-SKU exception records;
- OPS-072 reconciles source closing/opening quantities against ledger-derived OPS stock;
- cutover cannot proceed with unexplained variance for an in-scope SKU.

### 11.3 Opening inventory

`Tồn đầu` records are opening-balance candidates, not normal manual adjustments.

OPS-071 must stage them separately. OPS-072 decides the accepted opening balance after event-history reconciliation, then creates the proper traceable opening/adjustment movement under target invariants.

## 12. Delivery / carrier mapping

`CHÀNH XE` is a carrier reference table, but V1 has no standalone carrier master.

Do not create a new V1 carrier entity.

When an order can be linked deterministically to a carrier/dispatch context, preserve legacy carrier details in existing delivery fields such as:

- `carrier_note`
- `delivery_reference`
- consignee fields
- parcel/dispatch notes

Unlinked carrier rows remain snapshot/reference data only.

## 13. Legacy parameters

`THAM SỐ` contains examples such as:

- `MIN_STOCK`
- `VAT`
- `WARNING_DEBT`
- `REPORT_YEAR`

Only explicitly safe values may seed target fields:

- `MIN_STOCK` may be used as a fallback for product minimum stock **only when a product-specific minimum is absent**.
- `VAT`, `WARNING_DEBT`, and `REPORT_YEAR` do not automatically create accounting/debt/configuration behavior in V1.

## 14. Status normalization

Normalize raw status text using NFC, trim, whitespace collapse, and uppercase matching.

Build an explicit staging lookup of every distinct raw status before load.

Categories must be target-dimension-specific:

- sales order status
- print status
- warehouse status
- payment status
- delivery status
- purchase-order status
- production status

Unknown or cross-dimensional labels are quarantined as `REVIEW_STATUS`.

Examples already observed:

- `ĐÃ THU` → payment semantic, not delivery semantic
- `CHỜ IN` → production/print semantic, not delivery semantic
- `SẴN KHO`, `CHỜ NHẬP HÀNG` → legacy availability/procurement metadata, not automatically a target product active/inactive state

Payment status after migration must be derived from accepted orders/payments according to the current OPS workflow, not copied from free-text legacy labels.

## 15. Deduplication rules

### Customers
`customer_code > unique normalized phone > brand+address > review`

### Suppliers
Exact normalized supplier name only. Fuzzy merge prohibited.

### Products
Prefer unique accepted SKU. If SKU absent, exact normalized name + product type/material/package context. Never fuzzy-collapse variants.

### Orders
Normalized order number is grouping key, but conflicting customer/date/order-level attributes cause quarantine.

### Purchase orders / receipts
Normalized document number is grouping key only after supplier/date consistency validation.

### Payments
Source-row reference is identity; displayed receipt number is non-unique metadata.

## 16. Quarantine / review reason codes

OPS-071 must emit at least:

- `REVIEW_CUSTOMER_CONFLICT`
- `REVIEW_SUPPLIER_DUPLICATE`
- `REVIEW_MISSING_SKU_MASTER`
- `REVIEW_MISSING_SKU_ORDER_LINE`
- `REVIEW_DUPLICATE_SKU`
- `REVIEW_PACKAGING`
- `REVIEW_COST_COMPONENTS`
- `REVIEW_PRICE_BLOCK`
- `REVIEW_STATUS`
- `REVIEW_ORDER_CONFLICT`
- `REVIEW_PO_CONFLICT`
- `REVIEW_ORPHAN_RECEIPT`
- `REVIEW_PAYMENT_LINK`
- `REVIEW_NEGATIVE_STOCK`
- `REVIEW_OPENING_BALANCE`
- `REVIEW_SPREADSHEET_ERROR`

No quarantined row may be silently discarded. Counts and source references must appear in the reconciliation output.

## 17. Reconciliation contract for OPS-072

OPS-071 load output must make the following comparisons possible:

### Row/control counts
For every canonical sheet and entity:

- source rows
- blank/non-business rows
- staged rows
- deduplicated rows
- loaded rows
- rejected/quarantined rows
- synthetic legacy records, if any

The equation `source business rows = loaded logical rows + deduplicated aliases + quarantined rows` must be explainable.

### Money
All totals remain currency-specific:

- sales-order line totals vs source `Thành tiền`
- order totals vs source `TỔNG ĐƠN HÀNG`
- customer payments vs source payment totals
- purchase items vs source `Thành tiền`
- purchase order totals vs source `Tổng Tiền Đơn`
- current receivables vs legacy debt report, with explained exceptions

### Inventory
Per SKU:

- opening candidate
- goods receipts
- sales issues
- explicit adjustments
- target ledger on-hand/reserved/available
- source `THẺ KHO` closing quantity
- variance and reason

### Integrity
- no transaction row linked to a non-existent migrated customer/product;
- no accepted payment exceeds target workflow constraints;
- no package conversion is implicit/unknown;
- all loaded financial rows have a source reference;
- all exceptions have reason codes.

## 18. Immutable source snapshot requirement

Before any production-facing load or final cutover, retain immutable exports of both locked source workbooks. Snapshot metadata must include:

- Drive ID
- source title
- Drive modified timestamp
- export timestamp
- exported file name/format
- byte size
- SHA-256
- task/run identifier

OPS-071 must read from a recorded snapshot or verify that the live source still matches the recorded identity before extraction. OPS-075 must take a final snapshot before cutover.

## 19. Known source anomalies verified during OPS-070

The following are **observed facts**, not hypothetical risks:

1. `SẢN PHẨM` depends on `IMPORTRANGE` from the selected `*BẢNG GIÁ VỐN` workbook.
2. At least one sales-order line has a blank `Mã SP`.
3. Supplier names are free text in purchasing/receipt history.
4. `Trạng thái giao` contains mixed concepts such as `ĐÃ THU` and `CHỜ IN`.
5. `THẺ KHO` contains negative current stock values.
6. `ĐIỀU CHỈNH KHO` contains a negative `Tồn đầu` example.
7. Hidden `DATA` contains spreadsheet errors including `#N/A` and `#REF!`.
8. Legacy `BÁO GIÁ` contains a live `#REF!` caused by a missing source sheet.
9. `COST PHỤ KIỆN` reuses generic values such as `Muỗng` in `MÃ SP` across distinct products.
10. `THU TIỀN` contains duplicate displayed receipt references, so that reference is not a safe migration key.
11. Fixed-column selling-price tiers exist and must be normalized into data rows.
12. Cost/price source contains shorthand/unlabeled columns whose semantics must not be guessed.

These anomalies are inputs to OPS-071 validation, not reasons to copy spreadsheet defects into the OPS runtime database.
