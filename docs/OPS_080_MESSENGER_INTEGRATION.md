# OPS-080 Messenger integration boundary

This bounded unit is the OPS side of `magasincoffee/magasin-messenger-agent`.

## Contract

- OPS remains canonical for product, pricing, customer, order and inventory.
- Messenger inquiry reads `available_quantity`.
- Messenger final confirmation creates a normal OPS sales order and full inventory reservation.
- Physical stock is not decremented at chat time. Existing warehouse issue remains the only normal path to `SALES_ISSUE`.
- The integration RPCs are executable by `service_role` only.
- The service-role key is permitted only in server-side Supabase Edge Function secrets.
- Every Meta event and order confirmation is idempotent.

## Rollout dependency

Do not apply this production migration until OPS-075 final spreadsheet cutover is complete and exact-main cutover verification is GREEN.
