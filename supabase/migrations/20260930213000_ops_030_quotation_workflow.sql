-- OPS-030: quotation workflow
-- Architecture Generation 1
-- Source of Truth: SOURCE_OF_TRUTH.md
--
-- Quotation prices are snapshots. Active pricing rules/tiers are evaluated when
-- a DRAFT line is added; later pricing configuration changes do not rewrite the
-- accepted quotation price.

begin;

alter table public.quotations
  drop constraint if exists quotations_status_not_blank;

alter table public.quotations
  add constraint quotations_status_valid
  check (status in ('DRAFT','SENT','ACCEPTED','REJECTED','EXPIRED','CONVERTED'));

alter table public.quotations
  add column if not exists sent_at timestamptz,
  add column if not exists accepted_at timestamptz,
  add column if not exists rejected_at timestamptz,
  add column if not exists expired_at timestamptz;

alter table public.quotation_items
  add column if not exists pricing_rule_id uuid
    references public.pricing_rules(id) on delete restrict,
  add column if not exists price_tier_id uuid
    references public.price_tiers(id) on delete restrict;

alter view public.quotation_totals set (security_invoker = true);

-- Production quotation mutation is routed through bounded RPCs. SELECT remains
-- governed by the existing SALES/OWNER RLS policies.
revoke insert, update, delete on public.quotations from authenticated;
revoke insert, update, delete on public.quotation_items from authenticated;
grant select on public.quotations, public.quotation_items to authenticated;

create or replace function private.resolve_quotation_price(
  p_product_variant_id uuid,
  p_base_quantity numeric,
  p_print_mode text,
  p_print_color_count integer,
  p_currency_code text,
  p_pricing_date date
)
returns table (
  pricing_rule_id uuid,
  price_tier_id uuid,
  selling_price_per_base_unit numeric
)
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_fixed numeric(18,6);
  v_markup numeric(9,4);
  v_margin numeric(9,4);
  v_print_cost numeric(18,6);
  v_landed_cost numeric(18,6);
  v_price numeric;
begin
  if p_base_quantity is null or p_base_quantity <= 0 then
    raise exception 'Pricing quantity must be positive';
  end if;

  if p_print_mode not in ('PLAIN','PRINTED') then
    raise exception 'Quotation print mode must be PLAIN or PRINTED';
  end if;

  if p_print_mode = 'PRINTED' and coalesce(p_print_color_count,0) <= 0 then
    raise exception 'Printed quotation items require a positive print color count';
  end if;

  if p_print_mode = 'PLAIN' and p_print_color_count is not null then
    raise exception 'Plain quotation items cannot have a print color count';
  end if;

  select
    pr.id,
    pt.id,
    pt.fixed_selling_price_per_base_unit,
    pt.markup_percent,
    pt.margin_percent,
    pt.print_cost_per_base_unit
  into
    pricing_rule_id,
    price_tier_id,
    v_fixed,
    v_markup,
    v_margin,
    v_print_cost
  from public.pricing_rules pr
  join public.price_tiers pt on pt.pricing_rule_id = pr.id
  join public.product_variants pv on pv.id = p_product_variant_id
  join public.products p on p.id = pv.product_id
  where pv.is_active = true
    and pr.is_active = true
    and pr.currency_code = upper(p_currency_code)
    and pr.effective_from <= p_pricing_date
    and (pr.effective_to is null or pr.effective_to >= p_pricing_date)
    and (pr.product_variant_id is null or pr.product_variant_id = p_product_variant_id)
    and (pr.product_type is null or pr.product_type = p.product_type)
    and pr.print_mode in ('ANY', p_print_mode)
    and (
      pr.min_print_colors is null
      or coalesce(p_print_color_count,0) >= pr.min_print_colors
    )
    and (
      pr.max_print_colors is null
      or coalesce(p_print_color_count,0) <= pr.max_print_colors
    )
    and pt.min_quantity_base_units <= p_base_quantity
    and (pt.max_quantity_base_units is null or pt.max_quantity_base_units >= p_base_quantity)
  order by
    case when pr.product_variant_id = p_product_variant_id then 0
         when pr.product_type is not null then 1
         else 2 end,
    case when pr.print_mode = p_print_mode then 0 else 1 end,
    pr.priority asc,
    pt.min_quantity_base_units desc,
    pr.created_at asc
  limit 1;

  if pricing_rule_id is null or price_tier_id is null then
    raise exception 'No active pricing rule matches this quotation item';
  end if;

  if v_fixed is not null then
    v_price := v_fixed + v_print_cost;
  else
    select pch.landed_cost_per_base_unit
    into v_landed_cost
    from public.purchase_cost_history pch
    where pch.product_variant_id = p_product_variant_id
      and pch.currency_code = upper(p_currency_code)
      and pch.effective_at::date <= p_pricing_date
    order by pch.effective_at desc, pch.created_at desc
    limit 1;

    if v_landed_cost is null then
      raise exception 'No landed cost is available for this dynamic pricing rule';
    end if;

    if v_markup is not null then
      v_price := (v_landed_cost + v_print_cost) * (1 + (v_markup / 100));
    elsif v_margin is not null then
      v_price := (v_landed_cost + v_print_cost) / (1 - (v_margin / 100));
    else
      raise exception 'Pricing tier has no supported pricing basis';
    end if;
  end if;

  selling_price_per_base_unit := round(v_price, 6);
  return next;
end;
$$;

revoke all on function private.resolve_quotation_price(uuid,numeric,text,integer,text,date)
from public, anon, authenticated;

create or replace function private.guard_quotation_workflow()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_item_count integer;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'DRAFT' then
      raise exception 'Only DRAFT quotations may be deleted';
    end if;
    return old;
  end if;

  if old.status <> 'DRAFT' and (
    new.customer_id is distinct from old.customer_id
    or new.quotation_date is distinct from old.quotation_date
    or new.valid_until is distinct from old.valid_until
    or new.currency_code is distinct from old.currency_code
    or new.notes is distinct from old.notes
  ) then
    raise exception 'Quotation header is locked after it is sent';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'DRAFT' and new.status = 'SENT')
      or (old.status = 'SENT' and new.status in ('ACCEPTED','REJECTED','EXPIRED'))
      or (old.status = 'ACCEPTED' and new.status = 'CONVERTED')
    ) then
      raise exception 'Invalid quotation status transition from % to %', old.status, new.status;
    end if;

    if new.status = 'SENT' then
      select count(*)::integer into v_item_count
      from public.quotation_items qi
      where qi.quotation_id = new.id;

      if v_item_count = 0 then
        raise exception 'Quotation must contain at least one item before sending';
      end if;

      if new.valid_until is not null and new.valid_until < current_date then
        raise exception 'Expired quotation cannot be sent';
      end if;

      new.sent_at := coalesce(new.sent_at, timezone('utc', now()));
    elsif new.status = 'ACCEPTED' then
      if new.valid_until is not null and new.valid_until < current_date then
        raise exception 'Expired quotation cannot be accepted';
      end if;
      new.accepted_at := coalesce(new.accepted_at, timezone('utc', now()));
    elsif new.status = 'REJECTED' then
      new.rejected_at := coalesce(new.rejected_at, timezone('utc', now()));
    elsif new.status = 'EXPIRED' then
      if new.valid_until is null or new.valid_until >= current_date then
        raise exception 'Quotation may be marked EXPIRED only after valid_until';
      end if;
      new.expired_at := coalesce(new.expired_at, timezone('utc', now()));
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.guard_quotation_workflow()
from public, anon, authenticated;

drop trigger if exists quotations_guard_workflow on public.quotations;
create trigger quotations_guard_workflow
before update or delete on public.quotations
for each row execute function private.guard_quotation_workflow();

create or replace function private.guard_quotation_item_editability()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_quotation_id uuid;
  v_status text;
begin
  v_quotation_id := case when tg_op = 'DELETE' then old.quotation_id else new.quotation_id end;

  select q.status into v_status
  from public.quotations q
  where q.id = v_quotation_id;

  if not found then
    raise exception 'Quotation % does not exist', v_quotation_id;
  end if;

  if v_status <> 'DRAFT' then
    raise exception 'Quotation items are editable only while the quotation is DRAFT';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.guard_quotation_item_editability()
from public, anon, authenticated;

drop trigger if exists quotation_items_guard_editability on public.quotation_items;
create trigger quotation_items_guard_editability
before insert or update or delete on public.quotation_items
for each row execute function private.guard_quotation_item_editability();

create or replace function public.create_quotation(
  p_quotation_number text,
  p_customer_id uuid,
  p_valid_until date default null,
  p_currency_code text default 'VND',
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_id uuid;
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('SALES')
  ) then
    raise exception 'Create quotation requires OWNER_ADMIN or SALES role'
      using errcode='42501';
  end if;

  if p_quotation_number is null or length(btrim(p_quotation_number)) = 0 then
    raise exception 'Quotation number is required';
  end if;

  if not exists (
    select 1 from public.customers c
    where c.id = p_customer_id and c.is_active = true
  ) then
    raise exception 'Active customer % does not exist', p_customer_id;
  end if;

  insert into public.quotations (
    quotation_number, customer_id, status, quotation_date, valid_until,
    currency_code, created_by_user_id, notes
  )
  values (
    btrim(p_quotation_number), p_customer_id, 'DRAFT', current_date, p_valid_until,
    upper(coalesce(nullif(btrim(p_currency_code),''),'VND')),
    v_user_id, nullif(btrim(coalesce(p_notes,'')),'')
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_quotation(text,uuid,date,text,text)
from public, anon;
grant execute on function public.create_quotation(text,uuid,date,text,text)
to authenticated, service_role;

create or replace function public.add_quotation_item_priced(
  p_quotation_id uuid,
  p_product_variant_id uuid,
  p_packaging_id uuid,
  p_sale_quantity numeric,
  p_discount_amount numeric default 0,
  p_print_mode text default 'PLAIN',
  p_print_color_count integer default null,
  p_print_specification text default null,
  p_artwork_reference text default null,
  p_requested_due_date date default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_status text;
  v_currency text;
  v_quotation_date date;
  v_sale_unit text;
  v_units_per_sale_unit numeric(18,6);
  v_base_quantity numeric(18,6);
  v_price_per_base numeric(18,6);
  v_pricing_rule_id uuid;
  v_price_tier_id uuid;
  v_unit_price numeric(18,6);
  v_subtotal numeric(18,6);
  v_item_id uuid;
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('SALES')
  ) then
    raise exception 'Add quotation item requires OWNER_ADMIN or SALES role'
      using errcode='42501';
  end if;

  if p_sale_quantity is null or p_sale_quantity <= 0 then
    raise exception 'Sale quantity must be positive';
  end if;
  if coalesce(p_discount_amount,0) < 0 then
    raise exception 'Discount amount cannot be negative';
  end if;

  select q.status, q.currency_code, q.quotation_date
  into v_status, v_currency, v_quotation_date
  from public.quotations q
  where q.id = p_quotation_id
  for update;

  if not found then
    raise exception 'Quotation % does not exist', p_quotation_id;
  end if;
  if v_status <> 'DRAFT' then
    raise exception 'Quotation items are editable only while the quotation is DRAFT';
  end if;

  if p_packaging_id is null then
    select pv.base_inventory_unit, 1::numeric
    into v_sale_unit, v_units_per_sale_unit
    from public.product_variants pv
    where pv.id = p_product_variant_id and pv.is_active = true;
  else
    select pp.package_code, pp.units_per_package
    into v_sale_unit, v_units_per_sale_unit
    from public.product_packaging pp
    join public.product_variants pv on pv.id = pp.product_variant_id
    where pp.id = p_packaging_id
      and pp.product_variant_id = p_product_variant_id
      and pp.is_active = true
      and pv.is_active = true
      and pp.effective_from <= v_quotation_date
      and (pp.effective_to is null or pp.effective_to >= v_quotation_date);
  end if;

  if v_sale_unit is null or v_units_per_sale_unit is null then
    raise exception 'Active sale unit/package is not valid for this SKU';
  end if;

  v_base_quantity := p_sale_quantity * v_units_per_sale_unit;

  select r.pricing_rule_id, r.price_tier_id, r.selling_price_per_base_unit
  into v_pricing_rule_id, v_price_tier_id, v_price_per_base
  from private.resolve_quotation_price(
    p_product_variant_id,
    v_base_quantity,
    upper(p_print_mode),
    p_print_color_count,
    v_currency,
    v_quotation_date
  ) r;

  v_unit_price := round(v_price_per_base * v_units_per_sale_unit, 6);
  v_subtotal := p_sale_quantity * v_unit_price;

  if coalesce(p_discount_amount,0) > v_subtotal then
    raise exception 'Discount amount cannot exceed line subtotal';
  end if;

  insert into public.quotation_items (
    quotation_id, product_variant_id, packaging_id,
    sale_unit, sale_quantity, units_per_sale_unit,
    unit_price_per_sale_unit, discount_amount,
    print_mode, print_color_count, print_specification,
    artwork_reference, requested_due_date, notes,
    pricing_rule_id, price_tier_id
  )
  values (
    p_quotation_id, p_product_variant_id, p_packaging_id,
    v_sale_unit, p_sale_quantity, v_units_per_sale_unit,
    v_unit_price, coalesce(p_discount_amount,0),
    upper(p_print_mode), p_print_color_count,
    nullif(btrim(coalesce(p_print_specification,'')),''),
    nullif(btrim(coalesce(p_artwork_reference,'')),''),
    p_requested_due_date,
    nullif(btrim(coalesce(p_notes,'')),''),
    v_pricing_rule_id, v_price_tier_id
  )
  returning id into v_item_id;

  return v_item_id;
end;
$$;

revoke all on function public.add_quotation_item_priced(uuid,uuid,uuid,numeric,numeric,text,integer,text,text,date,text)
from public, anon;
grant execute on function public.add_quotation_item_priced(uuid,uuid,uuid,numeric,numeric,text,integer,text,text,date,text)
to authenticated, service_role;

create or replace function public.remove_quotation_item(p_quotation_item_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_quotation_id uuid;
  v_status text;
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('SALES')
  ) then
    raise exception 'Remove quotation item requires OWNER_ADMIN or SALES role'
      using errcode='42501';
  end if;

  select qi.quotation_id, q.status
  into v_quotation_id, v_status
  from public.quotation_items qi
  join public.quotations q on q.id = qi.quotation_id
  where qi.id = p_quotation_item_id
  for update of qi, q;

  if not found then
    raise exception 'Quotation item % does not exist', p_quotation_item_id;
  end if;
  if v_status <> 'DRAFT' then
    raise exception 'Quotation items are editable only while the quotation is DRAFT';
  end if;

  delete from public.quotation_items where id = p_quotation_item_id;
  return v_quotation_id;
end;
$$;

revoke all on function public.remove_quotation_item(uuid)
from public, anon;
grant execute on function public.remove_quotation_item(uuid)
to authenticated, service_role;

create or replace function public.set_quotation_status(
  p_quotation_id uuid,
  p_status text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_target text := upper(btrim(coalesce(p_status,'')));
begin
  if v_user_id is null or not (
    public.current_user_has_role('OWNER_ADMIN')
    or public.current_user_has_role('SALES')
  ) then
    raise exception 'Quotation status change requires OWNER_ADMIN or SALES role'
      using errcode='42501';
  end if;

  if v_target not in ('SENT','ACCEPTED','REJECTED','EXPIRED') then
    raise exception 'Unsupported quotation status action %', v_target;
  end if;

  update public.quotations
  set status = v_target
  where id = p_quotation_id;

  if not found then
    raise exception 'Quotation % does not exist', p_quotation_id;
  end if;

  return p_quotation_id;
end;
$$;

revoke all on function public.set_quotation_status(uuid,text)
from public, anon;
grant execute on function public.set_quotation_status(uuid,text)
to authenticated, service_role;

commit;
