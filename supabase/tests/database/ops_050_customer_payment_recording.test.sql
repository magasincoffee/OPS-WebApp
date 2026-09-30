begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

select is(has_function_privilege('authenticated','public.record_customer_payment(uuid,numeric,date,text,text,text)','EXECUTE'),true,'record payment RPC available');
select is(has_function_privilege('authenticated','public.void_customer_payment(uuid)','EXECUTE'),true,'void payment RPC available');
select is(has_function_privilege('authenticated','public.create_customer_payment_evidence_attachment(uuid,text,text,text,bigint)','EXECUTE'),true,'payment evidence RPC available');

insert into auth.users(id,email,raw_user_meta_data) values
('f5100000-0000-0000-0000-000000000001','ops-050-owner@example.test','{"display_name":"OPS-050 Owner"}'),
('f5100000-0000-0000-0000-000000000002','ops-050-accounting@example.test','{"display_name":"OPS-050 Accounting"}'),
('f5100000-0000-0000-0000-000000000003','ops-050-sales@example.test','{"display_name":"OPS-050 Sales"}');
insert into public.user_roles(user_id,role_id)
select x.user_id,r.id from (values
('f5100000-0000-0000-0000-000000000001'::uuid,'OWNER_ADMIN'::text),
('f5100000-0000-0000-0000-000000000002'::uuid,'ACCOUNTING'::text),
('f5100000-0000-0000-0000-000000000003'::uuid,'SALES'::text)
)x(user_id,role_code) join public.roles r on r.code=x.role_code;

insert into public.customers(id,customer_code,display_name)
values('f5200000-0000-0000-0000-000000000001','OPS050-CUSTOMER','OPS-050 Customer');
insert into public.products(id,name,product_type)
values('f5300000-0000-0000-0000-000000000001','OPS-050 Product','CUP');
insert into public.product_variants(id,product_id,sku_code,variant_name,base_inventory_unit)
values('f5400000-0000-0000-0000-000000000001','f5300000-0000-0000-0000-000000000001','OPS050-SKU','OPS-050 Variant','piece');

insert into public.sales_orders(
 id,order_number,customer_id,order_status,print_status,warehouse_status,payment_status,delivery_status,currency_code,created_by_user_id
) values
('f5500000-0000-0000-0000-000000000001','SO-OPS050-001','f5200000-0000-0000-0000-000000000001','DRAFT','NOT_REQUIRED','NOT_RESERVED','UNPAID','NOT_READY','VND','f5100000-0000-0000-0000-000000000001'),
('f5500000-0000-0000-0000-000000000002','SO-OPS050-DRAFT','f5200000-0000-0000-0000-000000000001','DRAFT','NOT_REQUIRED','NOT_RESERVED','UNPAID','NOT_READY','VND','f5100000-0000-0000-0000-000000000001');

insert into public.sales_order_items(
 id,sales_order_id,product_variant_id,sale_unit,sale_quantity,units_per_sale_unit,unit_price_per_sale_unit,
 discount_amount,print_mode
) values
('f5600000-0000-0000-0000-000000000001','f5500000-0000-0000-0000-000000000001','f5400000-0000-0000-0000-000000000001','piece',10,1,100000,0,'PLAIN'),
('f5600000-0000-0000-0000-000000000002','f5500000-0000-0000-0000-000000000002','f5400000-0000-0000-0000-000000000001','piece',1,1,100000,0,'PLAIN');

update public.sales_orders set order_status='CONFIRMED'
where id='f5500000-0000-0000-0000-000000000001';

set local role authenticated;
set local request.jwt.claim.sub='f5100000-0000-0000-0000-000000000002';

select throws_ok(
 $$select public.record_customer_payment('f5500000-0000-0000-0000-000000000002',10000,current_date,'BANK_TRANSFER',null,null)$$,
 'P0001','Customer payments may be recorded only against CONFIRMED sales orders',
 'DRAFT order rejects payment'
);

select lives_ok(
 $$select public.record_customer_payment('f5500000-0000-0000-0000-000000000001',300000,current_date,'BANK_TRANSFER','DEP-050','deposit')$$,
 'accounting records first order payment'
);

select is((select payment_status from public.sales_orders where id='f5500000-0000-0000-0000-000000000001'),'PARTIALLY_PAID','first payment synchronizes PARTIALLY_PAID');

select results_eq(
 $$select amount,payment_method,reference,created_by_user_id,status
   from public.customer_payments where reference='DEP-050'$$,
 $$select * from (values(
   300000::numeric,'BANK_TRANSFER'::text,'DEP-050'::text,
   'f5100000-0000-0000-0000-000000000002'::uuid,'POSTED'::text
 )) as expected(amount,payment_method,reference,created_by_user_id,status)$$,
 'payment stores amount/method/reference and authenticated creator'
);

select throws_ok(
 $$select public.record_customer_payment('f5500000-0000-0000-0000-000000000001',700001,current_date,'CASH',null,null)$$,
 'P0001','Customer payment exceeds outstanding sales-order amount',
 'overpayment is rejected transactionally'
);

select lives_ok(
 $$select public.record_customer_payment('f5500000-0000-0000-0000-000000000001',700000,current_date,'CASH','BAL-050','balance')$$,
 'accounting records remaining payment'
);

select is((select payment_status from public.sales_orders where id='f5500000-0000-0000-0000-000000000001'),'PAID','full posted payment synchronizes PAID');

select is(
 (select count(*) from public.customer_ledger_entries where customer_id='f5200000-0000-0000-0000-000000000001'),
 3::bigint,
 'OPS-051 automatically materializes one order debit and two source-backed payment credits'
);

select lives_ok(
 $$select public.create_customer_payment_evidence_attachment(
   (select id from public.customer_payments where reference='DEP-050'),
   'customer-payments/'||(select id::text from public.customer_payments where reference='DEP-050')||'/deposit.pdf',
   'deposit.pdf','application/pdf',1234
 )$$,
 'accounting creates private payment evidence metadata'
);

select results_eq(
 $$select attachment_kind,storage_bucket,uploaded_by_user_id
   from public.attachments where original_file_name='deposit.pdf'$$,
 $$select * from (values(
   'PAYMENT_EVIDENCE'::text,'ops-attachments'::text,
   'f5100000-0000-0000-0000-000000000002'::uuid
 )) as expected(attachment_kind,storage_bucket,uploaded_by_user_id)$$,
 'payment evidence is self-attributed in private bucket'
);

select lives_ok(
 $$select public.void_customer_payment((select id from public.customer_payments where reference='BAL-050'))$$,
 'accounting voids posted payment'
);

select results_eq(
 $$select status,(voided_at is not null),voided_by_user_id
   from public.customer_payments where reference='BAL-050'$$,
 $$select * from (values(
   'VOIDED'::text,true,'f5100000-0000-0000-0000-000000000002'::uuid
 )) as expected(status,has_voided_at,voided_by_user_id)$$,
 'void preserves payment and records authenticated actor/time'
);

select is((select payment_status from public.sales_orders where id='f5500000-0000-0000-0000-000000000001'),'PARTIALLY_PAID','void recalculates order payment status');

select throws_ok(
 $$select public.void_customer_payment((select id from public.customer_payments where reference='BAL-050'))$$,
 'P0001','Only POSTED customer payments may be voided',
 'already voided payment cannot be voided again'
);

select results_eq(
 $$select valid_payment_amount,receivable_amount
   from public.sales_receivable_followup where sales_order_id='f5500000-0000-0000-0000-000000000001'$$,
 $$select * from (values(300000::numeric,700000::numeric)) as expected(valid_payment_amount,receivable_amount)$$,
 'existing sanitized receivable follow-up reflects valid posted payments'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub='f5100000-0000-0000-0000-000000000003';

select throws_ok(
 $$select public.record_customer_payment('f5500000-0000-0000-0000-000000000001',10000,current_date,'CASH',null,null)$$,
 '42501','Customer payment recording requires OWNER_ADMIN or ACCOUNTING role',
 'SALES cannot record customer payments'
);

select is((select count(*) from public.customer_payments),0::bigint,'SALES has no direct customer-payment row visibility');
select is((select count(*) from public.sales_receivable_followup where sales_order_id='f5500000-0000-0000-0000-000000000001'),1::bigint,'SALES retains sanitized receivable follow-up visibility');

reset role;
select * from finish();
rollback;
