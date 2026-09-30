begin;

create extension if not exists pgtap with schema extensions;

select plan(27);

select is(has_function_privilege('authenticated','public.create_quotation(text,uuid,date,text,text)','EXECUTE'),true,'authenticated can execute quotation creation subject to role checks');
select is(has_function_privilege('authenticated','public.add_quotation_item_priced(uuid,uuid,uuid,numeric,numeric,text,integer,text,text,date,text)','EXECUTE'),true,'authenticated can execute priced line insertion subject to role checks');
select is(has_function_privilege('authenticated','public.remove_quotation_item(uuid)','EXECUTE'),true,'authenticated can execute DRAFT line removal subject to role checks');
select is(has_function_privilege('authenticated','public.set_quotation_status(uuid,text)','EXECUTE'),true,'authenticated can execute quotation status transitions subject to role checks');
select is(has_table_privilege('authenticated','public.quotations','INSERT'),false,'authenticated cannot bypass quotation creation workflow');
select is(has_table_privilege('authenticated','public.quotation_items','INSERT'),false,'authenticated cannot bypass quotation pricing workflow');

select results_eq(
  $$
    select count(*)::bigint
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname='quotation_totals'
      and c.reloptions @> array['security_invoker=true']
  $$,
  array[1::bigint],
  'quotation totals view uses security_invoker and respects underlying RLS'
);

insert into auth.users(id,email)
values
  ('d0100000-0000-0000-0000-000000000001','ops-030-sales@example.test'),
  ('d0100000-0000-0000-0000-000000000002','ops-030-warehouse@example.test');

insert into public.user_roles(user_id,role_id)
select x.user_id,r.id
from (values
  ('d0100000-0000-0000-0000-000000000001'::uuid,'SALES'::text),
  ('d0100000-0000-0000-0000-000000000002'::uuid,'WAREHOUSE'::text)
) x(user_id,role_code)
join public.roles r on r.code=x.role_code;

insert into public.customers(id,customer_code,display_name)
values ('d0200000-0000-0000-0000-000000000001','OPS030-CUSTOMER','OPS-030 Customer');

insert into public.products(id,name,product_type)
values ('d0300000-0000-0000-0000-000000000001','OPS-030 Cup','CUP');

insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit)
values (
  'd0400000-0000-0000-0000-000000000001',
  'd0300000-0000-0000-0000-000000000001',
  'OPS030-SKU','OPS-030 Variant','piece'
);

insert into public.product_packaging(
  id,product_variant_id,package_code,package_name,units_per_package,is_sale_default
)
values (
  'd0500000-0000-0000-0000-000000000001',
  'd0400000-0000-0000-0000-000000000001',
  'CARTON','Carton',1000,true
);

insert into public.purchase_cost_history(
  id,product_variant_id,purchase_unit,units_per_purchase_unit,
  purchase_price_per_purchase_unit,freight_cost_per_purchase_unit,currency_code
)
values (
  'd0600000-0000-0000-0000-000000000001',
  'd0400000-0000-0000-0000-000000000001',
  'carton',1000,1000,200,'VND'
);

insert into public.pricing_rules(
  id,name,product_variant_id,print_mode,min_print_colors,max_print_colors,
  currency_code,priority,effective_from,is_active
)
values
  (
    'd0700000-0000-0000-0000-000000000001',
    'OPS-030 Printed Markup',
    'd0400000-0000-0000-0000-000000000001',
    'PRINTED',1,2,'VND',10,current_date,true
  ),
  (
    'd0700000-0000-0000-0000-000000000002',
    'OPS-030 Plain Fixed',
    'd0400000-0000-0000-0000-000000000001',
    'PLAIN',null,null,'VND',10,current_date,true
  );

insert into public.price_tiers(
  id,pricing_rule_id,min_quantity_base_units,max_quantity_base_units,
  markup_percent,print_cost_per_base_unit
)
values (
  'd0800000-0000-0000-0000-000000000001',
  'd0700000-0000-0000-0000-000000000001',
  1000,null,25,0.3
);

insert into public.price_tiers(
  id,pricing_rule_id,min_quantity_base_units,max_quantity_base_units,
  fixed_selling_price_per_base_unit,print_cost_per_base_unit
)
values (
  'd0800000-0000-0000-0000-000000000002',
  'd0700000-0000-0000-0000-000000000002',
  1,null,2.5,0
);

set local role authenticated;
set local request.jwt.claim.sub='d0100000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.create_quotation('QT-OPS030-001','d0200000-0000-0000-0000-000000000001',current_date+7,'VND','First quotation')$$,
  'SALES can create a DRAFT quotation'
);

reset role;

select results_eq(
  $$
    select status,created_by_user_id
    from public.quotations
    where quotation_number='QT-OPS030-001'
  $$,
  $$values ('DRAFT'::text,'d0100000-0000-0000-0000-000000000001'::uuid)$$,
  'quotation creation is DRAFT and binds authenticated actor'
);

set local role authenticated;
set local request.jwt.claim.sub='d0100000-0000-0000-0000-000000000001';

select lives_ok(
  $$select public.add_quotation_item_priced(
    (select id from public.quotations where quotation_number='QT-OPS030-001'),
    'd0400000-0000-0000-0000-000000000001',
    'd0500000-0000-0000-0000-000000000001',
    2,250,'PRINTED',2,'2-color logo',null,current_date+5,'Primary line'
  )$$,
  'SALES can add a quantity-priced printed quotation line'
);

reset role;

select results_eq(
  $$
    select
      sale_unit,sale_quantity,units_per_sale_unit,base_quantity,
      unit_price_per_sale_unit,discount_amount,line_total,
      pricing_rule_id,price_tier_id
    from public.quotation_items qi
    join public.quotations q on q.id=qi.quotation_id
    where q.quotation_number='QT-OPS030-001'
  $$,
  $$values (
    'CARTON'::text,2::numeric,1000::numeric,2000::numeric,
    1875::numeric,250::numeric,3500::numeric,
    'd0700000-0000-0000-0000-000000000001'::uuid,
    'd0800000-0000-0000-0000-000000000001'::uuid
  )$$,
  'printed line snapshots package conversion and markup-plus-print-cost selling price'
);

select results_eq(
  $$
    select qt.subtotal_amount,qt.discount_amount,qt.total_amount,qt.currency_code
    from public.quotation_totals qt
    join public.quotations q on q.id=qt.quotation_id
    where q.quotation_number='QT-OPS030-001'
  $$,
  $$values (3750::numeric,250::numeric,3500::numeric,'VND'::text)$$,
  'quotation totals are database-derived'
);

set local role authenticated;
set local request.jwt.claim.sub='d0100000-0000-0000-0000-000000000001';

select is((select count(*) from public.purchase_cost_history),0::bigint,'SALES cannot read purchase cost history used by dynamic pricing');

select lives_ok(
  $$select public.set_quotation_status(
    (select id from public.quotations where quotation_number='QT-OPS030-001'),
    'SENT'
  )$$,
  'DRAFT quotation with items can be sent'
);

reset role;

select results_eq(
  $$
    select count(*)::bigint
    from public.quotations
    where quotation_number='QT-OPS030-001'
      and status='SENT'
      and sent_at is not null
  $$,
  array[1::bigint],
  'SENT lifecycle timestamp is recorded'
);

set local role authenticated;
set local request.jwt.claim.sub='d0100000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.add_quotation_item_priced(
    (select id from public.quotations where quotation_number='QT-OPS030-001'),
    'd0400000-0000-0000-0000-000000000001',null,10,0,'PLAIN',null,null,null,null,null
  )$$,
  'P0001','Quotation items are editable only while the quotation is DRAFT',
  'quotation lines are locked after sending'
);

select lives_ok(
  $$select public.set_quotation_status(
    (select id from public.quotations where quotation_number='QT-OPS030-001'),
    'ACCEPTED'
  )$$,
  'SENT quotation can be accepted'
);

reset role;

select results_eq(
  $$
    select count(*)::bigint
    from public.quotations
    where quotation_number='QT-OPS030-001'
      and status='ACCEPTED'
      and accepted_at is not null
  $$,
  array[1::bigint],
  'ACCEPTED lifecycle timestamp is recorded'
);

set local role authenticated;
set local request.jwt.claim.sub='d0100000-0000-0000-0000-000000000001';

select throws_like(
  $$select public.set_quotation_status(
    (select id from public.quotations where quotation_number='QT-OPS030-001'),
    'SENT'
  )$$,
  'Invalid quotation status transition%',
  'accepted quotation cannot move backward to SENT'
);

select lives_ok(
  $$select public.create_quotation('QT-OPS030-002','d0200000-0000-0000-0000-000000000001',current_date+7,'VND','Plain quotation')$$,
  'SALES can create a second quotation'
);

select lives_ok(
  $$select public.add_quotation_item_priced(
    (select id from public.quotations where quotation_number='QT-OPS030-002'),
    'd0400000-0000-0000-0000-000000000001',null,100,0,'PLAIN',null,null,null,null,null
  )$$,
  'plain quotation line resolves fixed pricing rule'
);

reset role;

select results_eq(
  $$
    select sale_unit,units_per_sale_unit,unit_price_per_sale_unit,pricing_rule_id,price_tier_id
    from public.quotation_items qi
    join public.quotations q on q.id=qi.quotation_id
    where q.quotation_number='QT-OPS030-002'
  $$,
  $$values (
    'piece'::text,1::numeric,2.5::numeric,
    'd0700000-0000-0000-0000-000000000002'::uuid,
    'd0800000-0000-0000-0000-000000000002'::uuid
  )$$,
  'plain line snapshots fixed per-base selling price'
);

set local role authenticated;
set local request.jwt.claim.sub='d0100000-0000-0000-0000-000000000001';

select throws_ok(
  $$select public.add_quotation_item_priced(
    (select id from public.quotations where quotation_number='QT-OPS030-002'),
    'd0400000-0000-0000-0000-000000000001',null,100,0,'PRINTED',null,null,null,null,null
  )$$,
  'P0001','Printed quotation items require a positive print color count',
  'printed quotation line requires color count'
);

select lives_ok(
  $select public.create_quotation('QT-OPS030-EMPTY','d0200000-0000-0000-0000-000000000001',current_date+7,'VND',null)$,
  'empty quotation fixture can be created'
);

select throws_ok(
  $$select public.set_quotation_status(
    (select id from public.quotations where quotation_number='QT-OPS030-EMPTY'),
    'SENT'
  )$$,
  'P0001','Quotation must contain at least one item before sending',
  'empty quotation cannot be sent'
);

reset role;

set local role authenticated;
set local request.jwt.claim.sub='d0100000-0000-0000-0000-000000000002';

select is((select count(*) from public.quotations),0::bigint,'WAREHOUSE cannot read quotation headers');
select is((select count(*) from public.quotation_totals),0::bigint,'WAREHOUSE cannot bypass quotation RLS through totals view');

reset role;

select * from finish();
rollback;
