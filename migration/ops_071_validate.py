#!/usr/bin/env python3
from __future__ import annotations
import argparse, json
from pathlib import Path

ENTITIES=[
 'customers','suppliers','products','product_variants','product_packaging','purchase_cost_history',
 'purchase_orders','purchase_order_items','goods_receipts','goods_receipt_items','sales_orders',
 'sales_order_items','customer_payments','opening_inventory_candidates'
]

def read_jsonl(path):
    if not path.exists(): return []
    return [json.loads(x) for x in path.read_text(encoding='utf-8').splitlines() if x.strip()]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('output_dir');args=ap.parse_args();root=Path(args.output_dir)
    data={e:read_jsonl(root/(e+'.jsonl')) for e in ENTITIES}
    errors=[]
    ids={e:{r['id'] for r in rows if r.get('id')} for e,rows in data.items()}
    for e,rows in data.items():
        if len(ids[e])!=sum(1 for r in rows if r.get('id')):errors.append(f'duplicate id in {e}')
    def req(entity,field,target):
        for r in data[entity]:
            if r.get(field) not in ids[target]:errors.append(f"{entity}.{field} missing target {r.get(field)}")
    req('product_variants','product_id','products')
    req('product_packaging','product_variant_id','product_variants')
    req('purchase_cost_history','product_variant_id','product_variants')
    req('purchase_orders','supplier_id','suppliers')
    req('purchase_order_items','purchase_order_id','purchase_orders');req('purchase_order_items','product_variant_id','product_variants')
    req('goods_receipts','purchase_order_id','purchase_orders');req('goods_receipt_items','goods_receipt_id','goods_receipts');req('goods_receipt_items','purchase_order_item_id','purchase_order_items')
    req('sales_orders','customer_id','customers');req('sales_order_items','sales_order_id','sales_orders');req('sales_order_items','product_variant_id','product_variants')
    req('customer_payments','customer_id','customers');req('customer_payments','sales_order_id','sales_orders')
    for r in data['customer_payments']:
        if float(r['amount'])<=0:errors.append('nonpositive accepted payment')
    for r in data['sales_order_items']:
        if float(r['sale_quantity'])<=0 or float(r['unit_price_per_sale_unit'])<0:errors.append('invalid accepted sales line')
    for r in data['purchase_order_items']:
        if float(r['package_quantity'])<=0 or float(r['unit_cost_per_purchase_unit'])<0:errors.append('invalid accepted PO line')
    q=read_jsonl(root/'quarantine.jsonl')
    if not all(x.get('reason') and x.get('source_row_reference') for x in q):errors.append('quarantine row missing reason/source reference')
    summary=json.loads((root/'reconciliation_inputs.json').read_text(encoding='utf-8'))
    if not all(summary.get('invariants',{}).values()):errors.append('reported invariant is false')
    result={'ok':not errors,'errors':errors,'entity_counts':{e:len(v) for e,v in data.items()},'quarantine_count':len(q)}
    print(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True))
    raise SystemExit(1 if errors else 0)
if __name__=='__main__':main()
