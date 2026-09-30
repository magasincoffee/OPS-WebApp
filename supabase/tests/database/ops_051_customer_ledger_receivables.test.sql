begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

select is(has_table_privilege('authenticated','public.customer_ledger_balances_by_currency','SELECT'),true,'currency-safe ledger balance view is API-readable');
select is(has_table_privilege('authenticated','public.customer_ledger_history','SELECT'),true,'ledger history view is API-readable');
select is(has_table_privilege('authenticated','public.customer_ledger_balances','SELECT'),false,'legacy cross-currency aggregate is not exposed to authenticated API users');

insert into auth.users(id,email,raw_user_meta_data) values
('f6100000-0000-0000-0000-000000000001','ops-051-owner@example.test','{"display_name":"OPS-051 Owner"}'),
('f6100000-0000-0000-0000-000000000002','ops-051-accounting@example.test','{"display_name":"OPS-051 Accounting"}'),
('f6100000-0000-0000-0000-000000000003','ops-051-sales@example.test','{"display_name":"OPS-051 Sales"}');

insert into public.user_roles(user_id,role_id)
select x.user_id,r.id from (values
('f6100000-0000-0000-0000-000000000001'::uuid,'OWNER_ADMIN'::text),
('f6100000-0000-0000-0000-000000000002'::uuid,'ACCOUNTING'::text),
('f6100000-0000-0000-0000-000000000003'::uuid,'SALES'::text)
)x(user_id,role_code) join public.roles r on r.code=x.role_code;

insert into public.customers(id,customer_code,display_name)
values('f6200000-0000-0000-0000-000000000001','OPS051-CUSTOMER','OPS-051 Customer');

insert into public.products(id,name,product_type)
values('f6300000-0000-0000-0000-000000000001','OPS-051 Product','CUP');

insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit)
values('f6400000-0000-0000-0000-000000000001','f6300000-0000-0000-0000-000000000001','OPS051-SKU','OPS-051 Variant','piece');

insert into public.sales_orders(
 id,order_number,customer_id,order_status,print_status,warehouse_status,payment_status,delivery_status,
 currency_code,created_by_user_id,salesperson_user_id
) values(
 'f6500000-0000-0000-0000-000000000001','SO-OPS051-001','f6200000-0000-0000-0000-000000000001',
 'DRAFT','NOT_REQUIRED','NOT_RESERVED','UNPAID','NOT_READY','VND',
 'f6100000-0000-0000-0000-000000000001','f6100000-0000-0000-0000-000000000003'
);

insert into public.sales_order_items(
 id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,
 unit_price_per_sale_unit,discount_amount,print_mode
) values(
 'f6600000-0000-0000-0000-000000000001','f6500000-0000-0000-0000-000000000001',
 'f6400000-0000-0000-0000-000000000001','piece',10,1,100000,0,'PLAIN'
);

set local role authenticated;
set local request.jwt.claim.sub='f6100000-0000-0000-0000-000000000001';

select lives_ok(
 $$select public.set_sales_order_status('f6500000-0000-0000-0000-000000000001','CONFIRMED')$$,
 'owner confirms order and opens receivable ledger'
);

select results_eq(
 $$select entry_type,amount,sales_order_id,created_by_user_id
   from public.customer_ledger_entries
   where sales_order_id='f6500000-0000-0000-0000-000000000001'$$,
 $$select * from (values(
   'ORDER_DEBIT'::text,1000000::numeric,
   'f6500000-0000-0000-0000-000000000001'::uuid,
   'f6100000-0000-0000-0000-000000000001'::uuid
 )) as expected(entry_type,amount,sales_order_id,created_by_user_id)$$,
 'confirmation appends one source-backed order debit at locked total'
);

select is(
 (select count(*) from public.activity_logs al
  join public.customer_ledger_entries cle on cle.id=al.linked_entity_id
  where al.linked_entity_type='CUSTOMER_LEDGER_ENTRY'
    and cle.sales_order_id='f6500000-0000-0000-0000-000000000001'),
 1::bigint,
 'automatic order debit is captured by existing ledger activity audit'
);

select results_eq(
 $$select currency_code,balance_amount
   from public.customer_ledger_balances_by_currency
   where customer_id='f6200000-0000-0000-0000-000000000001'$$,
 $$select * from (values('VND'::text,1000000::numeric)) as expected(currency_code,balance_amount)$$,
 'current balance starts at full order debit in the correct currency'
);

select is(
 (select payment_status from public.sales_orders where id='f6500000-0000-0000-0000-000000000001'),
 'UNPAID',
 'confirmed undelivered order remains UNPAID before any payment'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f6100000-0000-0000-0000-000000000002';

select lives_ok(
 $$select public.record_customer_payment(
   'f6500000-0000-0000-0000-000000000001',300000,current_date,'BANK_TRANSFER','OPS051-P1','deposit'
 )$$,
 'accounting posts partial payment'
);

select results_eq(
 $$select cle.entry_type,cle.amount,cle.created_by_user_id
   from public.customer_ledger_entries cle
   join public.customer_payments cp on cp.id=cle.customer_payment_id
   where cp.reference='OPS051-P1'$$,
 $$select * from (values(
   'PAYMENT_CREDIT'::text,300000::numeric,'f6100000-0000-0000-0000-000000000002'::uuid
 )) as expected(entry_type,amount,created_by_user_id)$$,
 'posted payment automatically appends immutable source-backed credit'
);

select results_eq(
 $$select currency_code,balance_amount
   from public.customer_ledger_balances_by_currency
   where customer_id='f6200000-0000-0000-0000-000000000001'$$,
 $$select * from (values('VND'::text,700000::numeric)) as expected(currency_code,balance_amount)$$,
 'partial payment reduces customer balance'
);

select is(
 (select payment_status from public.sales_orders where id='f6500000-0000-0000-0000-000000000001'),
 'PARTIALLY_PAID',
 'partial payment remains PARTIALLY_PAID before delivery completion'
);

select throws_ok(
 $$insert into public.customer_ledger_entries(
   customer_id,sales_order_id,entry_type,amount,created_by_user_id
 ) values(
   'f6200000-0000-0000-0000-000000000001',
   'f6500000-0000-0000-0000-000000000001',
   'ORDER_DEBIT',1,'f6100000-0000-0000-0000-000000000002'
 )$$,
 'P0001','Customer ledger amount must match its authoritative source amount',
 'finance role cannot forge a ledger amount that differs from source'
);

reset role;
update public.sales_orders
set delivery_status='COMPLETED'
where id='f6500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub='f6100000-0000-0000-0000-000000000002';

select is(
 (select payment_status from public.sales_orders where id='f6500000-0000-0000-0000-000000000001'),
 'RECEIVABLE',
 'delivered order with outstanding amount becomes RECEIVABLE'
);

select results_eq(
 $$select valid_payment_amount,receivable_amount,payment_status
   from public.sales_receivable_followup
   where sales_order_id='f6500000-0000-0000-0000-000000000001'$$,
 $$select * from (values(
   300000::numeric,700000::numeric,'RECEIVABLE'::text
 )) as expected(valid_payment_amount,receivable_amount,payment_status)$$,
 'receivable follow-up exposes outstanding amount after delivery'
);

select lives_ok(
 $$select public.record_customer_payment(
   'f6500000-0000-0000-0000-000000000001',700000,current_date,'BANK_TRANSFER','OPS051-P2','remaining'
 )$$,
 'accounting posts remaining payment'
);

select is(
 (select payment_status from public.sales_orders where id='f6500000-0000-0000-0000-000000000001'),
 'PAID',
 'valid payments covering the order total synchronize PAID'
);

select results_eq(
 $$select currency_code,balance_amount
   from public.customer_ledger_balances_by_currency
   where customer_id='f6200000-0000-0000-0000-000000000001'$$,
 $$select * from (values('VND'::text,0::numeric)) as expected(currency_code,balance_amount)$$,
 'fully paid order yields zero customer balance in that currency'
);

select lives_ok(
 $$select public.void_customer_payment(
   (select id from public.customer_payments where reference='OPS051-P2')
 )$$,
 'accounting voids remaining payment without deleting ledger history'
);

select is(
 (select payment_status from public.sales_orders where id='f6500000-0000-0000-0000-000000000001'),
 'RECEIVABLE',
 'voided payment reopens delivered outstanding amount as RECEIVABLE'
);

select results_eq(
 $$select currency_code,balance_amount
   from public.customer_ledger_balances_by_currency
   where customer_id='f6200000-0000-0000-0000-000000000001'$$,
 $$select * from (values('VND'::text,700000::numeric)) as expected(currency_code,balance_amount)$$,
 'voided payment credit becomes ineffective while immutable ledger row remains'
);

select results_eq(
 $$select payment_status,effective_amount
   from public.customer_ledger_history
   where customer_payment_id=(select id from public.customer_payments where reference='OPS051-P2')$$,
 $$select * from (values('VOIDED'::text,0::numeric)) as expected(payment_status,effective_amount)$$,
 'ledger history preserves voided payment credit with zero current-balance effect'
);

select is(
 (select count(*) from public.customer_ledger_history
  where customer_id='f6200000-0000-0000-0000-000000000001'),
 3::bigint,
 'finance ledger history contains one debit and two payment credits'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f6100000-0000-0000-0000-000000000003';

select is(
 (select count(*) from public.customer_ledger_entries),
 0::bigint,
 'SALES has no direct customer-ledger row visibility'
);

select is(
 (select count(*) from public.customer_ledger_history),
 0::bigint,
 'SALES has no detailed ledger-history visibility'
);

select results_eq(
 $$select receivable_amount,payment_status
   from public.sales_receivable_followup
   where sales_order_id='f6500000-0000-0000-0000-000000000001'$$,
 $$select * from (values(700000::numeric,'RECEIVABLE'::text)) as expected(receivable_amount,payment_status)$$,
 'SALES retains sanitized receivable follow-up without payment/ledger detail'
);

reset role;
select * from finish();
rollback;
