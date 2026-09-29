begin;

create extension if not exists pgtap with schema extensions;

select plan(19);

-- Representative users are test-only fixtures. public.users has a foreign key to
-- auth.users; for this local pgTAP transaction we disable FK triggers only while
-- seeding deterministic identities, then restore normal trigger behavior before
-- exercising RLS as the authenticated role.
set local session_replication_role = replica;

insert into public.users (id, display_name)
values
  ('00000000-0000-0000-0000-000000000001', 'RBAC Owner'),
  ('00000000-0000-0000-0000-000000000002', 'RBAC Sales'),
  ('00000000-0000-0000-0000-000000000003', 'RBAC Accounting'),
  ('00000000-0000-0000-0000-000000000004', 'RBAC Warehouse'),
  ('00000000-0000-0000-0000-000000000005', 'RBAC Production');

set local session_replication_role = origin;

insert into public.user_roles (user_id, role_id)
select fixture.user_id, r.id
from (
  values
    ('00000000-0000-0000-0000-000000000001'::uuid, 'OWNER_ADMIN'::text),
    ('00000000-0000-0000-0000-000000000002'::uuid, 'SALES'::text),
    ('00000000-0000-0000-0000-000000000003'::uuid, 'ACCOUNTING'::text),
    ('00000000-0000-0000-0000-000000000004'::uuid, 'WAREHOUSE'::text),
    ('00000000-0000-0000-0000-000000000005'::uuid, 'PRINTER_PRODUCTION'::text)
) as fixture(user_id, role_code)
join public.roles r on r.code = fixture.role_code;

insert into public.customers (id, customer_code, display_name)
values (
  '10000000-0000-0000-0000-000000000001',
  'RBAC-CUSTOMER',
  'RBAC Representative Customer'
);

insert into public.products (id, name, product_type)
values (
  '20000000-0000-0000-0000-000000000001',
  'RBAC Representative Product',
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
  '21000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'RBAC-SKU',
  'RBAC Variant',
  'piece'
);

insert into public.purchase_cost_history (
  id,
  product_variant_id,
  purchase_unit,
  units_per_purchase_unit,
  purchase_price_per_purchase_unit
)
values (
  '22000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001',
  'carton',
  1000,
  100000
);

select results_eq(
  $$ select count(*)::bigint from public.roles
     where code in ('OWNER_ADMIN','SALES','ACCOUNTING','WAREHOUSE','PRINTER_PRODUCTION') $$,
  array[5::bigint],
  'OPS-003 seeds all five locked V1 roles'
);

-- OWNER / ADMIN representative.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  public.current_user_has_role('OWNER_ADMIN'),
  'OWNER_ADMIN representative resolves its role membership'
);

select results_eq(
  $$ select count(*)::bigint from public.customers where customer_code = 'RBAC-CUSTOMER' $$,
  array[1::bigint],
  'OWNER_ADMIN can read customer master data'
);

select results_eq(
  $$ select count(*)::bigint
     from public.purchase_cost_history
     where id = '22000000-0000-0000-0000-000000000001'::uuid $$,
  array[1::bigint],
  'OWNER_ADMIN can read restricted purchase-cost history'
);

select results_eq(
  $$ with changed as (
       update public.products
          set description = 'owner-authorized-update'
        where id = '20000000-0000-0000-0000-000000000001'::uuid
        returning id
     )
     select count(*)::bigint from changed $$,
  array[1::bigint],
  'OWNER_ADMIN can mutate product configuration'
);

reset role;

-- SALES representative.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  public.current_user_has_role('SALES'),
  'SALES representative resolves its role membership'
);

select results_eq(
  $$ select count(*)::bigint from public.customers where customer_code = 'RBAC-CUSTOMER' $$,
  array[1::bigint],
  'SALES can read customer master data'
);

select results_eq(
  $$ select count(*)::bigint
     from public.purchase_cost_history
     where id = '22000000-0000-0000-0000-000000000001'::uuid $$,
  array[0::bigint],
  'SALES cannot read restricted purchase-cost history'
);

select results_eq(
  $$ select count(*)::bigint from public.products
     where id = '20000000-0000-0000-0000-000000000001'::uuid $$,
  array[1::bigint],
  'SALES can read product reference data'
);

select results_eq(
  $$ with changed as (
       update public.products
          set description = 'sales-must-not-write'
        where id = '20000000-0000-0000-0000-000000000001'::uuid
        returning id
     )
     select count(*)::bigint from changed $$,
  array[0::bigint],
  'SALES cannot mutate product configuration'
);

reset role;

-- ACCOUNTING representative.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select results_eq(
  $$ select count(*)::bigint from public.customers where customer_code = 'RBAC-CUSTOMER' $$,
  array[1::bigint],
  'ACCOUNTING can read customer master data'
);

select results_eq(
  $$ select count(*)::bigint
     from public.purchase_cost_history
     where id = '22000000-0000-0000-0000-000000000001'::uuid $$,
  array[1::bigint],
  'ACCOUNTING can read restricted purchase-cost history'
);

select results_eq(
  $$ select count(*)::bigint from public.products
     where id = '20000000-0000-0000-0000-000000000001'::uuid $$,
  array[1::bigint],
  'ACCOUNTING can read product reference data'
);

reset role;

-- WAREHOUSE representative.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000004', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select results_eq(
  $$ select count(*)::bigint from public.customers where customer_code = 'RBAC-CUSTOMER' $$,
  array[0::bigint],
  'WAREHOUSE cannot read customer master data'
);

select results_eq(
  $$ select count(*)::bigint
     from public.purchase_cost_history
     where id = '22000000-0000-0000-0000-000000000001'::uuid $$,
  array[0::bigint],
  'WAREHOUSE cannot read restricted purchase-cost history'
);

select results_eq(
  $$ select count(*)::bigint from public.products
     where id = '20000000-0000-0000-0000-000000000001'::uuid $$,
  array[1::bigint],
  'WAREHOUSE can read product reference data'
);

reset role;

-- PRINTER / PRODUCTION representative.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000005', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select results_eq(
  $$ select count(*)::bigint from public.customers where customer_code = 'RBAC-CUSTOMER' $$,
  array[0::bigint],
  'PRINTER_PRODUCTION cannot read customer master data directly'
);

select results_eq(
  $$ select count(*)::bigint
     from public.purchase_cost_history
     where id = '22000000-0000-0000-0000-000000000001'::uuid $$,
  array[0::bigint],
  'PRINTER_PRODUCTION cannot read restricted purchase-cost history'
);

select results_eq(
  $$ select count(*)::bigint from public.products
     where id = '20000000-0000-0000-0000-000000000001'::uuid $$,
  array[1::bigint],
  'PRINTER_PRODUCTION can read product identity required for production'
);

reset role;

select * from finish();
rollback;
