begin;

create extension if not exists pgtap with schema extensions;

select plan(23);

-- Representative V1 users. Inserting into auth.users exercises the OPS auth-user
-- synchronization trigger and produces matching public.users rows.
insert into auth.users (id, email)
values
  ('10000000-0000-0000-0000-000000000001', 'ops-owner@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'ops-sales@example.test'),
  ('10000000-0000-0000-0000-000000000003', 'ops-accounting@example.test'),
  ('10000000-0000-0000-0000-000000000004', 'ops-warehouse@example.test'),
  ('10000000-0000-0000-0000-000000000005', 'ops-production@example.test');

insert into public.user_roles (user_id, role_id, assigned_by)
select x.user_id, r.id, '10000000-0000-0000-0000-000000000001'::uuid
from (
  values
    ('10000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('10000000-0000-0000-0000-000000000002'::uuid, 'SALES'::text),
    ('10000000-0000-0000-0000-000000000003'::uuid, 'ACCOUNTING'::text),
    ('10000000-0000-0000-0000-000000000004'::uuid, 'WAREHOUSE'::text),
    ('10000000-0000-0000-0000-000000000005'::uuid, 'PRINTER_PRODUCTION'::text)
) as x(user_id, role_code)
join public.roles r on r.code = x.role_code;

-- Minimal shared data used to verify positive and negative RLS visibility.
insert into public.customers (id, customer_code, display_name)
values (
  '20000000-0000-0000-0000-000000000001',
  'TEST-CUSTOMER',
  'Representative Customer'
);

insert into public.suppliers (id, supplier_code, supplier_name)
values (
  '30000000-0000-0000-0000-000000000001',
  'TEST-SUPPLIER',
  'Representative Supplier'
);

insert into public.product_categories (id, category_code, name)
values (
  '40000000-0000-0000-0000-000000000001',
  'TEST-CATEGORY',
  'Representative Category'
);

insert into public.products (id, category_id, name, product_type)
values (
  '50000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  'Representative Product',
  'CUP'
);

insert into public.product_variants (
  id,
  product_id,
  sku_code,
  variant_name,
  base_inventory_unit
)
values (
  '60000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  'TEST-SKU',
  'Representative Variant',
  'piece'
);

insert into public.purchase_cost_history (
  id,
  product_variant_id,
  supplier_id,
  purchase_unit,
  units_per_purchase_unit,
  purchase_price_per_purchase_unit,
  freight_cost_per_purchase_unit
)
values (
  '70000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  'carton',
  1000,
  1000000,
  50000
);

insert into public.tasks (
  id,
  task_type,
  assignee_user_id,
  status,
  priority
)
values
  ('80000000-0000-0000-0000-000000000001', 'OWNER_TEST', '10000000-0000-0000-0000-000000000001', 'OPEN', 'NORMAL'),
  ('80000000-0000-0000-0000-000000000002', 'SALES_TEST', '10000000-0000-0000-0000-000000000002', 'OPEN', 'NORMAL'),
  ('80000000-0000-0000-0000-000000000003', 'ACCOUNTING_TEST', '10000000-0000-0000-0000-000000000003', 'OPEN', 'NORMAL'),
  ('80000000-0000-0000-0000-000000000004', 'WAREHOUSE_TEST', '10000000-0000-0000-0000-000000000004', 'OPEN', 'NORMAL'),
  ('80000000-0000-0000-0000-000000000005', 'PRODUCTION_TEST', '10000000-0000-0000-0000-000000000005', 'OPEN', 'NORMAL');

set local role authenticated;

-- SALES representative.
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';

select ok(public.current_user_has_role('SALES'), 'SALES representative resolves its assigned role');
select is((select count(*) from public.customers), 1::bigint, 'SALES can read customer master');
select is((select count(*) from public.suppliers), 0::bigint, 'SALES cannot read supplier master');
select is((select count(*) from public.purchase_cost_history), 0::bigint, 'SALES cannot read purchase cost history');
select is((select count(*) from public.tasks), 1::bigint, 'SALES sees only its assigned operational task');

-- ACCOUNTING representative.
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000003';

select ok(public.current_user_has_role('ACCOUNTING'), 'ACCOUNTING representative resolves its assigned role');
select is((select count(*) from public.customers), 1::bigint, 'ACCOUNTING can read customer master');
select is((select count(*) from public.suppliers), 1::bigint, 'ACCOUNTING can read supplier master');
select is((select count(*) from public.purchase_cost_history), 1::bigint, 'ACCOUNTING can read purchase cost history');
select is((select count(*) from public.tasks), 1::bigint, 'ACCOUNTING sees only its assigned operational task');

-- WAREHOUSE representative.
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000004';

select ok(public.current_user_has_role('WAREHOUSE'), 'WAREHOUSE representative resolves its assigned role');
select is((select count(*) from public.suppliers), 1::bigint, 'WAREHOUSE can read supplier reference data');
select is((select count(*) from public.products), 1::bigint, 'WAREHOUSE can read product reference data');
select is((select count(*) from public.purchase_cost_history), 0::bigint, 'WAREHOUSE cannot read purchase cost history');
select is((select count(*) from public.tasks), 1::bigint, 'WAREHOUSE sees only its assigned operational task');

-- PRINTER / PRODUCTION representative.
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000005';

select ok(public.current_user_has_role('PRINTER_PRODUCTION'), 'PRINTER_PRODUCTION representative resolves its assigned role');
select is((select count(*) from public.products), 1::bigint, 'PRINTER_PRODUCTION can read product identity');
select is((select count(*) from public.purchase_cost_history), 0::bigint, 'PRINTER_PRODUCTION cannot read purchase cost history');
select is((select count(*) from public.customers), 0::bigint, 'PRINTER_PRODUCTION cannot read customer master directly');
select is((select count(*) from public.tasks), 1::bigint, 'PRINTER_PRODUCTION sees only its assigned operational task');

-- OWNER / ADMIN representative.
set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';

select ok(public.current_user_has_role('OWNER_ADMIN'), 'OWNER_ADMIN representative resolves its assigned role');
select is((select count(*) from public.purchase_cost_history), 1::bigint, 'OWNER_ADMIN can read purchase cost history');
select is((select count(*) from public.tasks), 5::bigint, 'OWNER_ADMIN can read all operational tasks');

reset role;

select * from finish();
rollback;
