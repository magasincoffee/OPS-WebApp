begin;

create extension if not exists pgtap with schema extensions;

select plan(20);

select is(
  has_function_privilege('authenticated','public.messenger_catalog_stock_search(text,integer)','EXECUTE'),
  false,
  'authenticated cannot execute Messenger catalog boundary'
);

select is(
  has_function_privilege('service_role','public.messenger_catalog_stock_search(text,integer)','EXECUTE'),
  true,
  'service_role can execute Messenger catalog boundary'
);

select is(
  has_function_privilege('authenticated','public.messenger_confirm_order(text,text,text,text,text,text,date,text,jsonb)','EXECUTE'),
  false,
  'authenticated cannot create Messenger orders'
);

select is(
  has_table_privilege('authenticated','public.messenger_messages','SELECT'),
  false,
  'authenticated cannot read Messenger conversation storage directly'
);

insert into public.products(id,name,product_type)
values(
  'c1000000-0000-0000-0000-000000000001',
  'Ly PET 700ml',
  'CUP'
);

insert into public.product_variants(
  id,product_id,sku_code,variant_name,capacity_value,capacity_unit,base_inventory_unit
)
values(
  'c2000000-0000-0000-0000-000000000001',
  'c1000000-0000-0000-0000-000000000001',
  'MSG-PET-700',
  'PET 700ml',
  700,
  'ml',
  'piece'
);

insert into public.product_packaging(
  id,product_variant_id,package_code,package_name,units_per_package,is_sale_default
)
values(
  'c3000000-0000-0000-0000-000000000001',
  'c2000000-0000-0000-0000-000000000001',
  'CTN1000',
  'Thùng 1000 cái',
  1000,
  true
);

insert into public.pricing_rules(
  id,name,product_variant_id,print_mode,currency_code,priority,effective_from,is_active
)
values(
  'c4000000-0000-0000-0000-000000000001',
  'Messenger fixture plain',
  'c2000000-0000-0000-0000-000000000001',
  'PLAIN',
  'VND',
  1,
  current_date,
  true
);

insert into public.price_tiers(
  id,pricing_rule_id,min_quantity_base_units,fixed_selling_price_per_base_unit
)
values(
  'c5000000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000001',
  1,
  2
);

insert into public.inventory_movements(
  product_variant_id,movement_type,quantity_delta_base_units,reason
)
values(
  'c2000000-0000-0000-0000-000000000001',
  'ADJUSTMENT_IN',
  5000,
  'OPS-080 Messenger fixture stock'
);

set local request.jwt.claim.role='service_role';
set local role service_role;

select is(
  public.messenger_record_inbound_event(
    'PAGE-1','PSID-1','MID-1','MESSAGE','{"text":"xin giá"}'::jsonb
  ),
  true,
  'first inbound Meta event is accepted'
);

select is(
  public.messenger_record_inbound_event(
    'PAGE-1','PSID-1','MID-1','MESSAGE','{"text":"duplicate"}'::jsonb
  ),
  false,
  'duplicate inbound Meta event is idempotently ignored'
);

select isnt(
  public.messenger_append_message(
    'PAGE-1','PSID-1','MID-1','INBOUND','xin giá','[]'::jsonb,'{}'::jsonb
  ),
  null::uuid,
  'inbound message is stored'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.messenger_get_conversation_context('PAGE-1','PSID-1',20)
  $$,
  array[1::bigint],
  'conversation context returns stored message'
);

select results_eq(
  $$
    select available_quantity
    from public.messenger_catalog_stock_search('700ml',8)
    where sku_code='MSG-PET-700'
  $$,
  $$ values (5000::numeric) $$,
  'catalog search exposes canonical available stock'
);

select is(
  (public.messenger_quote_line(
    'c2000000-0000-0000-0000-000000000001',
    'c3000000-0000-0000-0000-000000000001',
    2,
    'PLAIN',
    null
  )->>'line_total')::numeric,
  4000::numeric,
  'Messenger quote uses canonical OPS pricing'
);

select is(
  (public.messenger_confirm_order(
    'ORDER-KEY-1',
    'PAGE-1',
    'PSID-1',
    'Khách Test',
    '0900000000',
    'Cần Thơ',
    null,
    'pgTAP',
    jsonb_build_array(jsonb_build_object(
      'product_variant_id','c2000000-0000-0000-0000-000000000001',
      'packaging_id','c3000000-0000-0000-0000-000000000001',
      'sale_quantity',2,
      'print_mode','PLAIN'
    ))
  )->>'status'),
  'RESERVED',
  'explicit Messenger order creates and reserves canonical OPS sales order'
);

select results_eq(
  $$
    select order_status,warehouse_status
    from public.sales_orders so
    join public.messenger_sales_order_links l on l.sales_order_id=so.id
    where l.external_order_key='ORDER-KEY-1'
  $$,
  $$ values ('CONFIRMED'::text,'RESERVED'::text) $$,
  'Messenger order is confirmed and warehouse status is RESERVED'
);

select results_eq(
  $$
    select on_hand_quantity,reserved_quantity,available_quantity
    from public.inventory_stock_snapshot
    where product_variant_id='c2000000-0000-0000-0000-000000000001'
  $$,
  $$ values (5000::numeric,2000::numeric,3000::numeric) $$,
  'order confirmation reserves stock without reducing physical on-hand'
);

select is(
  (public.messenger_confirm_order(
    'ORDER-KEY-1',
    'PAGE-1',
    'PSID-1',
    'Khách Test',
    '0900000000',
    'Cần Thơ',
    null,
    'duplicate replay',
    jsonb_build_array(jsonb_build_object(
      'product_variant_id','c2000000-0000-0000-0000-000000000001',
      'packaging_id','c3000000-0000-0000-0000-000000000001',
      'sale_quantity',2,
      'print_mode','PLAIN'
    ))
  )->>'status'),
  'EXISTING',
  'replayed confirmation returns existing order'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.messenger_sales_order_links
    where external_order_key='ORDER-KEY-1'
  $$,
  array[1::bigint],
  'idempotency creates one Messenger sales-order link'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.inventory_movements im
    join public.sales_order_items soi on soi.id=im.sales_order_item_id
    join public.messenger_sales_order_links l on l.sales_order_id=soi.sales_order_id
    where l.external_order_key='ORDER-KEY-1'
      and im.movement_type='SALES_RESERVATION'
  $$,
  array[1::bigint],
  'replay does not duplicate stock reservation movement'
);

select is(
  (public.messenger_confirm_order(
    'ORDER-KEY-SHORT',
    'PAGE-1',
    'PSID-1',
    'Khách Test',
    null,
    null,
    null,
    null,
    jsonb_build_array(jsonb_build_object(
      'product_variant_id','c2000000-0000-0000-0000-000000000001',
      'packaging_id','c3000000-0000-0000-0000-000000000001',
      'sale_quantity',4,
      'print_mode','PLAIN'
    ))
  )->>'status'),
  'INSUFFICIENT_STOCK',
  'insufficient available stock is reported instead of oversold'
);

select results_eq(
  $$
    select count(*)::bigint from public.messenger_sales_order_links
    where external_order_key='ORDER-KEY-SHORT'
  $$,
  array[0::bigint],
  'insufficient-stock attempt creates no sales order link'
);

select results_eq(
  $$
    select count(*)::bigint
    from public.inventory_movements
    where product_variant_id='c2000000-0000-0000-0000-000000000001'
      and movement_type='SALES_ISSUE'
  $$,
  array[0::bigint],
  'Messenger confirmation never physically issues stock'
);

reset role;
select set_config('request.jwt.claim.role','authenticated',true);

select throws_ok(
  'select public.messenger_catalog_stock_search(''700ml'',8)',
  '42501',
  'Messenger integration requires service_role',
  'database boundary also rejects calls without service-role JWT claim'
);

select * from finish();

rollback;
