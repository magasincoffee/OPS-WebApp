-- OPS-080: bounded Messenger sales-channel integration
-- Architecture Generation 5
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- This migration exposes a service-role-only boundary for the external
-- MAGASIN Messenger Agent. It preserves canonical OPS pricing/order/inventory
-- invariants and never allows the agent to physically issue stock.

begin;

create sequence if not exists public.messenger_order_number_seq;
revoke all on sequence public.messenger_order_number_seq from public, anon, authenticated;
grant usage, select on sequence public.messenger_order_number_seq to service_role;

create table if not exists public.messenger_customers (
  id uuid primary key default gen_random_uuid(),
  page_id text not null,
  psid text not null,
  customer_id uuid references public.customers(id) on delete restrict,
  display_name text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint messenger_customers_page_psid_unique unique(page_id, psid),
  constraint messenger_customers_page_not_blank check(length(btrim(page_id)) > 0),
  constraint messenger_customers_psid_not_blank check(length(btrim(psid)) > 0)
);

create table if not exists public.messenger_inbound_events (
  id uuid primary key default gen_random_uuid(),
  page_id text not null,
  psid text not null,
  event_id text not null,
  event_type text not null,
  raw_payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default timezone('utc', now()),
  constraint messenger_inbound_events_page_event_unique unique(page_id, event_id),
  constraint messenger_inbound_events_event_id_not_blank check(length(btrim(event_id)) > 0)
);

create table if not exists public.messenger_messages (
  id uuid primary key default gen_random_uuid(),
  page_id text not null,
  psid text not null,
  message_id text not null,
  direction text not null,
  message_text text,
  attachments jsonb not null default '[]'::jsonb,
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  constraint messenger_messages_direction_valid check(direction in ('INBOUND','OUTBOUND')),
  constraint messenger_messages_page_message_direction_unique unique(page_id, message_id, direction)
);

create table if not exists public.messenger_sales_order_links (
  id uuid primary key default gen_random_uuid(),
  external_order_key text not null unique,
  page_id text not null,
  psid text not null,
  sales_order_id uuid not null references public.sales_orders(id) on delete restrict unique,
  created_at timestamptz not null default timezone('utc', now()),
  constraint messenger_sales_order_links_key_not_blank check(length(btrim(external_order_key)) > 0)
);

create index if not exists messenger_messages_conversation_idx
  on public.messenger_messages(page_id, psid, created_at desc);

create index if not exists messenger_inbound_events_conversation_idx
  on public.messenger_inbound_events(page_id, psid, received_at desc);

drop trigger if exists messenger_customers_set_updated_at on public.messenger_customers;
create trigger messenger_customers_set_updated_at
before update on public.messenger_customers
for each row execute function public.set_updated_at();

revoke all on public.messenger_customers from public, anon, authenticated;
revoke all on public.messenger_inbound_events from public, anon, authenticated;
revoke all on public.messenger_messages from public, anon, authenticated;
revoke all on public.messenger_sales_order_links from public, anon, authenticated;

grant select, insert, update on public.messenger_customers to service_role;
grant select, insert on public.messenger_inbound_events to service_role;
grant select, insert on public.messenger_messages to service_role;
grant select, insert on public.messenger_sales_order_links to service_role;

create or replace function private.require_messenger_service_role()
returns void
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Messenger integration requires service_role'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.require_messenger_service_role()
from public, anon, authenticated, service_role;

create or replace function public.messenger_record_inbound_event(
  p_page_id text,
  p_psid text,
  p_event_id text,
  p_event_type text,
  p_payload jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_id uuid;
begin
  perform private.require_messenger_service_role();

  if p_page_id is null or length(btrim(p_page_id)) = 0
     or p_psid is null or length(btrim(p_psid)) = 0
     or p_event_id is null or length(btrim(p_event_id)) = 0 then
    raise exception 'page_id, psid and event_id are required';
  end if;

  insert into public.messenger_customers(page_id, psid)
  values (btrim(p_page_id), btrim(p_psid))
  on conflict (page_id, psid) do update
    set updated_at = timezone('utc', now());

  insert into public.messenger_inbound_events(
    page_id, psid, event_id, event_type, raw_payload
  )
  values (
    btrim(p_page_id),
    btrim(p_psid),
    btrim(p_event_id),
    upper(coalesce(nullif(btrim(p_event_type), ''), 'MESSAGE')),
    coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (page_id, event_id) do nothing
  returning id into v_id;

  return v_id is not null;
end;
$$;

revoke all on function public.messenger_record_inbound_event(text,text,text,text,jsonb)
from public, anon, authenticated;
grant execute on function public.messenger_record_inbound_event(text,text,text,text,jsonb)
to service_role;

create or replace function public.messenger_append_message(
  p_page_id text,
  p_psid text,
  p_message_id text,
  p_direction text,
  p_message_text text default null,
  p_attachments jsonb default '[]'::jsonb,
  p_raw_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_id uuid;
  v_direction text := upper(btrim(coalesce(p_direction, '')));
begin
  perform private.require_messenger_service_role();

  if v_direction not in ('INBOUND','OUTBOUND') then
    raise exception 'Unsupported Messenger message direction %', v_direction;
  end if;

  insert into public.messenger_customers(page_id, psid)
  values (btrim(p_page_id), btrim(p_psid))
  on conflict (page_id, psid) do update
    set updated_at = timezone('utc', now());

  insert into public.messenger_messages(
    page_id, psid, message_id, direction, message_text, attachments, raw_payload
  )
  values (
    btrim(p_page_id),
    btrim(p_psid),
    btrim(p_message_id),
    v_direction,
    nullif(btrim(coalesce(p_message_text, '')), ''),
    coalesce(p_attachments, '[]'::jsonb),
    coalesce(p_raw_payload, '{}'::jsonb)
  )
  on conflict (page_id, message_id, direction) do nothing
  returning id into v_id;

  if v_id is null then
    select mm.id into v_id
    from public.messenger_messages mm
    where mm.page_id = btrim(p_page_id)
      and mm.message_id = btrim(p_message_id)
      and mm.direction = v_direction;
  end if;

  return v_id;
end;
$$;

revoke all on function public.messenger_append_message(text,text,text,text,text,jsonb,jsonb)
from public, anon, authenticated;
grant execute on function public.messenger_append_message(text,text,text,text,text,jsonb,jsonb)
to service_role;

create or replace function public.messenger_get_conversation_context(
  p_page_id text,
  p_psid text,
  p_limit integer default 20
)
returns table(
  direction text,
  message_text text,
  attachments jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
begin
  perform private.require_messenger_service_role();

  return query
  select q.direction, q.message_text, q.attachments, q.created_at
  from (
    select mm.direction, mm.message_text, mm.attachments, mm.created_at
    from public.messenger_messages mm
    where mm.page_id = btrim(p_page_id)
      and mm.psid = btrim(p_psid)
    order by mm.created_at desc, mm.id desc
    limit greatest(1, least(coalesce(p_limit,20),50))
  ) q
  order by q.created_at asc;
end;
$$;

revoke all on function public.messenger_get_conversation_context(text,text,integer)
from public, anon, authenticated;
grant execute on function public.messenger_get_conversation_context(text,text,integer)
to service_role;

create or replace function public.messenger_catalog_stock_search(
  p_query text,
  p_limit integer default 8
)
returns table(
  product_variant_id uuid,
  sku_code text,
  product_name text,
  variant_name text,
  capacity_value numeric,
  capacity_unit text,
  base_inventory_unit text,
  default_packaging_id uuid,
  default_package_code text,
  default_package_name text,
  units_per_package numeric,
  on_hand_quantity numeric,
  reserved_quantity numeric,
  available_quantity numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_query text := '%' || btrim(coalesce(p_query,'')) || '%';
begin
  perform private.require_messenger_service_role();

  return query
  select
    pv.id,
    pv.sku_code,
    p.name,
    pv.variant_name,
    pv.capacity_value,
    pv.capacity_unit,
    pv.base_inventory_unit,
    pkg.id,
    pkg.package_code,
    pkg.package_name,
    pkg.units_per_package,
    coalesce(stock.on_hand_quantity,0::numeric),
    coalesce(stock.reserved_quantity,0::numeric),
    coalesce(stock.available_quantity,0::numeric)
  from public.product_variants pv
  join public.products p on p.id = pv.product_id
  left join lateral (
    select pp.id, pp.package_code, pp.package_name, pp.units_per_package
    from public.product_packaging pp
    where pp.product_variant_id = pv.id
      and pp.is_active = true
      and pp.effective_from <= current_date
      and (pp.effective_to is null or pp.effective_to >= current_date)
    order by pp.is_sale_default desc, pp.effective_from desc, pp.id
    limit 1
  ) pkg on true
  left join public.inventory_stock_snapshot stock
    on stock.product_variant_id = pv.id
  where pv.is_active = true
    and p.is_active = true
    and (
      pv.sku_code ilike v_query
      or coalesce(pv.variant_name,'') ilike v_query
      or p.name ilike v_query
      or coalesce(p.product_type,'') ilike v_query
    )
  order by
    case when lower(pv.sku_code) = lower(btrim(coalesce(p_query,''))) then 0 else 1 end,
    p.name,
    pv.sku_code
  limit greatest(1, least(coalesce(p_limit,8),20));
end;
$$;

revoke all on function public.messenger_catalog_stock_search(text,integer)
from public, anon, authenticated;
grant execute on function public.messenger_catalog_stock_search(text,integer)
to service_role;

create or replace function public.messenger_quote_line(
  p_product_variant_id uuid,
  p_packaging_id uuid,
  p_sale_quantity numeric,
  p_print_mode text default 'PLAIN',
  p_print_color_count integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_sale_unit text;
  v_units numeric(18,6);
  v_packaging_id uuid;
  v_base_quantity numeric(18,6);
  v_rule_id uuid;
  v_tier_id uuid;
  v_price_base numeric(18,6);
  v_unit_price numeric(18,6);
  v_available numeric(18,6);
  v_print_mode text := upper(btrim(coalesce(p_print_mode,'PLAIN')));
begin
  perform private.require_messenger_service_role();

  if p_sale_quantity is null or p_sale_quantity <= 0 then
    raise exception 'Sale quantity must be positive';
  end if;
  if v_print_mode not in ('PLAIN','PRINTED') then
    raise exception 'Unsupported print mode %', v_print_mode;
  end if;

  if p_packaging_id is null then
    select pp.id, pp.package_code, pp.units_per_package
    into v_packaging_id, v_sale_unit, v_units
    from public.product_packaging pp
    where pp.product_variant_id = p_product_variant_id
      and pp.is_active = true
      and pp.effective_from <= current_date
      and (pp.effective_to is null or pp.effective_to >= current_date)
    order by pp.is_sale_default desc, pp.effective_from desc, pp.id
    limit 1;

    if v_packaging_id is null then
      select null::uuid, pv.base_inventory_unit, 1::numeric
      into v_packaging_id, v_sale_unit, v_units
      from public.product_variants pv
      where pv.id = p_product_variant_id and pv.is_active = true;
    end if;
  else
    select pp.id, pp.package_code, pp.units_per_package
    into v_packaging_id, v_sale_unit, v_units
    from public.product_packaging pp
    join public.product_variants pv on pv.id = pp.product_variant_id
    where pp.id = p_packaging_id
      and pp.product_variant_id = p_product_variant_id
      and pp.is_active = true
      and pv.is_active = true
      and pp.effective_from <= current_date
      and (pp.effective_to is null or pp.effective_to >= current_date);
  end if;

  if v_sale_unit is null or v_units is null then
    raise exception 'Active sale unit/package is not valid for this SKU';
  end if;

  v_base_quantity := p_sale_quantity * v_units;

  select pricing_rule_id, price_tier_id, selling_price_per_base_unit
  into v_rule_id, v_tier_id, v_price_base
  from private.resolve_quotation_price(
    p_product_variant_id,
    v_base_quantity,
    v_print_mode,
    p_print_color_count,
    'VND',
    current_date
  );

  v_unit_price := round(v_price_base * v_units, 6);

  select coalesce(s.available_quantity,0::numeric)
  into v_available
  from public.inventory_stock_snapshot s
  where s.product_variant_id = p_product_variant_id;

  return jsonb_build_object(
    'product_variant_id', p_product_variant_id,
    'packaging_id', v_packaging_id,
    'sale_unit', v_sale_unit,
    'sale_quantity', p_sale_quantity,
    'units_per_sale_unit', v_units,
    'base_quantity', v_base_quantity,
    'unit_price_per_sale_unit', v_unit_price,
    'line_total', p_sale_quantity * v_unit_price,
    'currency_code', 'VND',
    'available_quantity', coalesce(v_available,0::numeric),
    'sufficient_stock', coalesce(v_available,0::numeric) >= v_base_quantity,
    'pricing_rule_id', v_rule_id,
    'price_tier_id', v_tier_id
  );
end;
$$;

revoke all on function public.messenger_quote_line(uuid,uuid,numeric,text,integer)
from public, anon, authenticated;
grant execute on function public.messenger_quote_line(uuid,uuid,numeric,text,integer)
to service_role;

create or replace function public.messenger_confirm_order(
  p_external_order_key text,
  p_page_id text,
  p_psid text,
  p_customer_display_name text default null,
  p_customer_phone text default null,
  p_customer_address text default null,
  p_requested_due_date date default null,
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_existing_order_id uuid;
  v_existing_order_number text;
  v_customer_id uuid;
  v_order_id uuid;
  v_order_number text;
  v_total numeric(18,6);
  v_item jsonb;
  v_product_variant_id uuid;
  v_packaging_id uuid;
  v_sale_quantity numeric(18,6);
  v_sale_unit text;
  v_units numeric(18,6);
  v_base_quantity numeric(18,6);
  v_print_mode text;
  v_print_color_count integer;
  v_print_specification text;
  v_artwork_reference text;
  v_line_due date;
  v_rule_id uuid;
  v_tier_id uuid;
  v_price_base numeric(18,6);
  v_unit_price numeric(18,6);
  v_stock record;
  v_available numeric(18,6);
  v_line record;
  v_reservation_id uuid;
begin
  perform private.require_messenger_service_role();

  if p_external_order_key is null or length(btrim(p_external_order_key)) = 0 then
    raise exception 'external_order_key is required';
  end if;
  if p_page_id is null or length(btrim(p_page_id)) = 0
     or p_psid is null or length(btrim(p_psid)) = 0 then
    raise exception 'page_id and psid are required';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Confirmed Messenger order requires at least one item';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(btrim(p_external_order_key), 580));

  select l.sales_order_id, so.order_number
  into v_existing_order_id, v_existing_order_number
  from public.messenger_sales_order_links l
  join public.sales_orders so on so.id = l.sales_order_id
  where l.external_order_key = btrim(p_external_order_key);

  if found then
    return jsonb_build_object(
      'status','EXISTING',
      'sales_order_id',v_existing_order_id,
      'order_number',v_existing_order_number
    );
  end if;

  create temporary table if not exists messenger_order_build (
    seq integer,
    product_variant_id uuid,
    packaging_id uuid,
    sale_unit text,
    sale_quantity numeric(18,6),
    units_per_sale_unit numeric(18,6),
    base_quantity numeric(18,6),
    unit_price_per_sale_unit numeric(18,6),
    print_mode text,
    print_color_count integer,
    print_specification text,
    artwork_reference text,
    requested_due_date date,
    pricing_rule_id uuid,
    price_tier_id uuid
  ) on commit drop;
  truncate messenger_order_build;

  for v_item in
    select value from jsonb_array_elements(p_items)
  loop
    begin
      v_product_variant_id := (v_item->>'product_variant_id')::uuid;
      v_packaging_id := nullif(v_item->>'packaging_id','')::uuid;
      v_sale_quantity := (v_item->>'sale_quantity')::numeric;
      v_print_mode := upper(coalesce(nullif(btrim(v_item->>'print_mode'),''),'PLAIN'));
      v_print_color_count := nullif(v_item->>'print_color_count','')::integer;
      v_print_specification := nullif(btrim(coalesce(v_item->>'print_specification','')),'');
      v_artwork_reference := nullif(btrim(coalesce(v_item->>'artwork_reference','')),'');
      v_line_due := coalesce(nullif(v_item->>'requested_due_date','')::date, p_requested_due_date);
    exception when others then
      raise exception 'Invalid Messenger order item payload';
    end;

    if v_sale_quantity is null or v_sale_quantity <= 0 then
      raise exception 'Sale quantity must be positive';
    end if;
    if v_print_mode not in ('PLAIN','PRINTED') then
      raise exception 'Unsupported print mode %', v_print_mode;
    end if;
    if v_print_mode = 'PLAIN' then
      v_print_color_count := null;
    elsif v_print_color_count is null or v_print_color_count <= 0 then
      raise exception 'Printed Messenger item requires print_color_count';
    elsif v_line_due is null then
      raise exception 'Printed Messenger item requires requested due date';
    end if;

    if v_packaging_id is null then
      select pp.id, pp.package_code, pp.units_per_package
      into v_packaging_id, v_sale_unit, v_units
      from public.product_packaging pp
      where pp.product_variant_id = v_product_variant_id
        and pp.is_active = true
        and pp.effective_from <= current_date
        and (pp.effective_to is null or pp.effective_to >= current_date)
      order by pp.is_sale_default desc, pp.effective_from desc, pp.id
      limit 1;

      if v_packaging_id is null then
        select null::uuid, pv.base_inventory_unit, 1::numeric
        into v_packaging_id, v_sale_unit, v_units
        from public.product_variants pv
        where pv.id = v_product_variant_id and pv.is_active = true;
      end if;
    else
      select pp.id, pp.package_code, pp.units_per_package
      into v_packaging_id, v_sale_unit, v_units
      from public.product_packaging pp
      join public.product_variants pv on pv.id = pp.product_variant_id
      where pp.id = v_packaging_id
        and pp.product_variant_id = v_product_variant_id
        and pp.is_active = true
        and pv.is_active = true
        and pp.effective_from <= current_date
        and (pp.effective_to is null or pp.effective_to >= current_date);
    end if;

    if v_sale_unit is null or v_units is null then
      raise exception 'Active sale unit/package is not valid for Messenger item';
    end if;

    v_base_quantity := v_sale_quantity * v_units;

    select pricing_rule_id, price_tier_id, selling_price_per_base_unit
    into v_rule_id, v_tier_id, v_price_base
    from private.resolve_quotation_price(
      v_product_variant_id,
      v_base_quantity,
      v_print_mode,
      v_print_color_count,
      'VND',
      current_date
    );

    v_unit_price := round(v_price_base * v_units, 6);

    insert into messenger_order_build(
      seq, product_variant_id, packaging_id, sale_unit, sale_quantity,
      units_per_sale_unit, base_quantity, unit_price_per_sale_unit,
      print_mode, print_color_count, print_specification, artwork_reference,
      requested_due_date, pricing_rule_id, price_tier_id
    )
    values(
      (select coalesce(max(seq),0)+1 from messenger_order_build),
      v_product_variant_id, v_packaging_id, v_sale_unit, v_sale_quantity,
      v_units, v_base_quantity, v_unit_price,
      v_print_mode, v_print_color_count, v_print_specification, v_artwork_reference,
      v_line_due, v_rule_id, v_tier_id
    );
  end loop;

  for v_stock in
    select product_variant_id, sum(base_quantity) as required_quantity
    from messenger_order_build
    group by product_variant_id
    order by product_variant_id::text
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_stock.product_variant_id::text, 581));

    select coalesce(s.available_quantity,0::numeric)
    into v_available
    from public.inventory_stock_snapshot s
    where s.product_variant_id = v_stock.product_variant_id;

    if coalesce(v_available,0::numeric) < v_stock.required_quantity then
      return jsonb_build_object(
        'status','INSUFFICIENT_STOCK',
        'product_variant_id',v_stock.product_variant_id,
        'requested_base_quantity',v_stock.required_quantity,
        'available_quantity',coalesce(v_available,0::numeric)
      );
    end if;
  end loop;

  insert into public.messenger_customers(page_id, psid, display_name)
  values (
    btrim(p_page_id),
    btrim(p_psid),
    nullif(btrim(coalesce(p_customer_display_name,'')),'')
  )
  on conflict (page_id, psid) do update
    set display_name = coalesce(excluded.display_name, public.messenger_customers.display_name),
        updated_at = timezone('utc', now())
  returning customer_id into v_customer_id;

  if v_customer_id is null then
    insert into public.customers(
      display_name, contact_name, phone, address, notes
    )
    values(
      coalesce(
        nullif(btrim(coalesce(p_customer_display_name,'')),''),
        'Khách Messenger ' || right(btrim(p_psid), 6)
      ),
      nullif(btrim(coalesce(p_customer_display_name,'')),''),
      nullif(btrim(coalesce(p_customer_phone,'')),''),
      nullif(btrim(coalesce(p_customer_address,'')),''),
      'Tạo tự động từ kênh Facebook Messenger'
    )
    returning id into v_customer_id;

    update public.messenger_customers
    set customer_id = v_customer_id
    where page_id = btrim(p_page_id) and psid = btrim(p_psid);
  else
    update public.customers
    set phone = coalesce(phone, nullif(btrim(coalesce(p_customer_phone,'')),''))
      , address = coalesce(address, nullif(btrim(coalesce(p_customer_address,'')),''))
    where id = v_customer_id;
  end if;

  v_order_number :=
    'MSG-' || to_char(current_date,'YYYYMMDD') || '-' ||
    lpad(nextval('public.messenger_order_number_seq')::text, 6, '0');

  insert into public.sales_orders(
    order_number, customer_id, order_status, print_status, warehouse_status,
    payment_status, delivery_status, order_date, requested_due_date, currency_code,
    created_by_user_id, salesperson_user_id, notes
  )
  values(
    v_order_number, v_customer_id, 'DRAFT', 'NOT_REQUIRED', 'NOT_RESERVED',
    'UNPAID', 'NOT_READY', current_date, p_requested_due_date, 'VND',
    null, null,
    concat_ws(
      E'\n',
      'Nguồn: Facebook Messenger',
      'External order key: ' || btrim(p_external_order_key),
      nullif(btrim(coalesce(p_notes,'')),'')
    )
  )
  returning id into v_order_id;

  insert into public.sales_order_items(
    sales_order_id, product_variant_id, packaging_id, sale_unit, sale_quantity,
    units_per_sale_unit, unit_price_per_sale_unit, discount_amount,
    print_mode, print_color_count, print_specification, artwork_reference,
    requested_due_date, notes, pricing_rule_id, price_tier_id
  )
  select
    v_order_id, b.product_variant_id, b.packaging_id, b.sale_unit, b.sale_quantity,
    b.units_per_sale_unit, b.unit_price_per_sale_unit, 0,
    b.print_mode, b.print_color_count, b.print_specification, b.artwork_reference,
    b.requested_due_date, 'Tạo từ Messenger Agent', b.pricing_rule_id, b.price_tier_id
  from messenger_order_build b
  order by b.seq;

  update public.sales_orders
  set order_status = 'CONFIRMED'
  where id = v_order_id;

  for v_line in
    select soi.id, soi.product_variant_id, soi.base_quantity
    from public.sales_order_items soi
    where soi.sales_order_id = v_order_id
    order by soi.id
  loop
    insert into public.inventory_reservations(
      sales_order_item_id, product_variant_id, requested_base_quantity,
      created_by_user_id, notes
    )
    values(
      v_line.id, v_line.product_variant_id, v_line.base_quantity,
      null, 'Messenger Agent auto reservation'
    )
    returning id into v_reservation_id;

    insert into public.inventory_movements(
      product_variant_id, movement_type, quantity_delta_base_units,
      inventory_reservation_id, sales_order_item_id, created_by_user_id,
      reference, reason
    )
    values(
      v_line.product_variant_id, 'SALES_RESERVATION', v_line.base_quantity,
      v_reservation_id, v_line.id, null,
      'SALES_ORDER:' || v_order_number,
      'Messenger customer confirmed order'
    );
  end loop;

  insert into public.messenger_sales_order_links(
    external_order_key, page_id, psid, sales_order_id
  )
  values(
    btrim(p_external_order_key), btrim(p_page_id), btrim(p_psid), v_order_id
  );

  select total_amount into v_total
  from public.sales_order_totals
  where sales_order_id = v_order_id;

  return jsonb_build_object(
    'status','RESERVED',
    'sales_order_id',v_order_id,
    'order_number',v_order_number,
    'customer_id',v_customer_id,
    'total_amount',coalesce(v_total,0::numeric),
    'currency_code','VND',
    'warehouse_status',(select warehouse_status from public.sales_orders where id=v_order_id)
  );
end;
$$;

revoke all on function public.messenger_confirm_order(
  text,text,text,text,text,text,date,text,jsonb
) from public, anon, authenticated;
grant execute on function public.messenger_confirm_order(
  text,text,text,text,text,text,date,text,jsonb
) to service_role;

commit;
