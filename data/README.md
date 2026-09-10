# data/

Flat JSON files used by `backend/server.ps1` — no database.

- `menu.json` — the real 8 Portions menu (items, prices, sizes,
  allergens/dietary placeholders, availability). Authoritative source
  CafeBot is grounded in; see the file's own `_note` before editing
  prices or descriptions.
- `promotions.json` — promotion rules (discount type, eligibility:
  category/minimum order value/day/time window, `active` flag). Still
  **sample/placeholder** offers, not real 8 Portions promotions — see
  its own `_note`.
- `orders.json` — confirmed orders, appended by `Save-ConfirmedOrder`
  once a customer explicitly confirms (never before — see
  `Confirm-Order` in `backend/server.ps1`). **Gitignored**: it fills up
  with real customer PII (names, phone numbers, delivery addresses)
  once the backend is used, so it must never be committed. Starts as
  `[]`; the backend creates it automatically if it's missing.

`backend/dashboard.html` (the staff dashboard) reads and updates
`orders.json` through the backend's `/api/orders` endpoints — it never
touches this folder directly.
