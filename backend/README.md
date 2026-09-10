# backend/

Server-side code for CafeBot. This machine has no Node.js or Python and
no ability to install either (locked-down company machine), so instead
of the FastAPI/Flask/Express stack you'd normally reach for, `server.ps1`
uses .NET's built-in `HttpListener` from PowerShell — the same
zero-install approach the root `serve.ps1` uses to preview the frontend.
If a real runtime is ever approved, this can be replaced with a
Python/Node equivalent.

## Setup

```powershell
copy .env.example .env
# then fill in AI_API_KEY, AI_API_BASE_URL, AI_MODEL_NAME (required for
# POST /api/chat - see .env.example), and optionally TAX_RATE/DELIVERY_FEE
powershell -ExecutionPolicy Bypass -File backend/server.ps1
```

## server.ps1

Four endpoints: `POST /api/chat` (CafeBot), `GET /dashboard` (staff order
dashboard, serves `dashboard.html`), `GET /api/orders` (list saved
orders) and `POST /api/orders/status` (change one order's status) - see
"Staff dashboard" below.

```powershell
./backend/server.ps1          # listens on http://localhost:8792
```

Request body: `{ "message": "...", "history": [{ "role": "user"|"assistant", "content": "..." }], "sessionId": "..." (optional) }`
Response body: `{ "reply": "...", "sessionId": "...", "order": { ... } }`

What it does:
- Loads `AI_API_KEY`, `AI_API_BASE_URL`, `AI_MODEL_NAME`, `TAX_RATE`,
  `DELIVERY_FEE` from `.env` (see `.env.example`) and calls an
  OpenAI-compatible `/chat/completions` endpoint.
- Computes every order's `subtotal`/`tax`/`deliveryFee`/`total` itself
  (`Update-OrderTotal`, run after every change to the order) from menu
  prices, quantities, and the applied promotion's discount, plus the
  flat `TAX_RATE` percentage and a `DELIVERY_FEE` that only applies once
  `orderType` is `"delivery"`; both default to 0 if unset. The model
  never calculates a price - it only relays whatever `order.total` (and
  the breakdown in the concise order summary) already say.
- Builds the system message from `prompts/system-prompt.md` plus the
  current contents of `data/menu.json`, so CafeBot only knows about menu
  items that are actually in that file — it's told never to invent
  items or prices.
- Also includes the raw order state and a concise, pre-formatted plain-
  text summary of it (`Format-OrderSummary`: each line's quantity, chosen
  option labels, and price, plus the full subtotal/discount/tax/delivery
  fee/total breakdown), so the model can tell the customer what's in
  their order without reconstructing one from the raw JSON itself.
- Also includes a complete "checkout summary" (`Format-CheckoutSummary`)
  for the model to present right before checkout or whenever the
  customer wants to review everything: items/customizations/breakdown
  (reuses `Format-OrderSummary`), fulfillment details for whichever
  order type is selected, the applied promotion or currently valid ones
  if none is applied yet, and whether the order is already confirmed.
- Computes which `data/promotions.json` entries are both `active` and
  currently eligible for the live order (`Get-EligiblePromotions` /
  `Test-PromotionEligibility`: category rules, `minOrderValue`, `days`,
  `timeWindow`, all checked against the real order/menu/clock) and gives
  the model **only that pre-filtered list** — never the raw promotions
  file — so it can't mention or apply a promotion that isn't real,
  active, or currently eligible.
- Gives the model eight tools:
  - `add_item_to_order` — `Add-ItemToOrder` validates `menuItemId`,
    `quantity`, and any `selectedOptionIds` against `data/menu.json`
    before touching the session's order: unknown or unavailable items
    are rejected, and an item with `optionsRequired: true` is rejected
    until a valid option id is given. Each added line gets a unique
    `lineItemId`.
  - `modify_order_item` — `Update-OrderItem` changes an existing line's
    `quantity` and/or `selectedOptionIds` (looked up by `lineItemId`),
    re-validating against the live menu the same way; `selectedOptionIds`
    fully replaces the line's previous options, and a required option
    can't be cleared.
  - `remove_order_item` — `Remove-OrderItem` removes a line (looked up
    by `lineItemId`) in full, or by a given `quantity` if it's less than
    what's ordered (the line's quantity is reduced instead of dropped).
  - `apply_promotion` — `Apply-Promotion` re-checks eligibility (never
    just trusts the earlier snapshot) before applying a promotion by
    `promotionId`; only one may be applied per order. The discount is
    locked in at that amount on `order.promotion` and `Update-OrderTotal`
    subtracts it from the items total (floored at 0) on every later
    change.
  - `set_pickup_order` — `Set-PickupOrder` sets `order.orderType` to
    `"pickup"` and stores `order.customer.name` (required) and an
    optional `order.pickupTime`. Safe to call more than once - each call
    only touches the fields it was actually given, so the model can set
    the name now and add a pickup time later.
  - `set_delivery_order` — `Set-DeliveryOrder` sets `order.orderType` to
    `"delivery"` once `order.customer.name`, `.phone` and `.address` are
    all known (checked cumulatively across calls, not just the current
    one), plus optional `.apartmentUnit` and `.notes` (delivery
    instructions). Like pickup, it's safe to call incrementally - a
    partial call returns which required fields are still `missing`
    instead of guessing them, and doesn't set `orderType` until all
    three are present.
  - `confirm_delivery_address` — `Confirm-DeliveryAddress` sets
    `order.customer.addressConfirmed` to `true`; only valid once the
    order is a delivery order with an address on file. `Set-DeliveryOrder`
    resets this back to `false` whenever the address actually changes
    (not on a no-op resend of the same address), so a correction always
    requires re-confirmation. The system prompt requires the model to
    read the address back to the customer and get an explicit yes before
    calling this and before checkout.
  - `confirm_order` — `Confirm-Order` is the save/finalize gate: it sets
    `order.confirmation` to `true` and `order.status` to `"confirmed"`,
    and it's the only place either ever becomes true. It first checks
    the order actually has items, a selected order type, the required
    customer details for that type, and (for delivery)
    `addressConfirmed`, rejecting with exactly what's missing otherwise.
    It does **not** judge whether the customer's reply was an
    unambiguous yes - that's a language judgment the system prompt makes
    the model responsible for before ever calling this tool; a vague or
    hedging reply must not trigger it. `Update-OrderTotal` resets
    `confirmation`/`status` back to `false`/`"draft"` on any later
    change to the order (it's called by every order-mutating function),
    so a stale confirmation can never survive an edit - the customer has
    to re-confirm the updated summary. On success, it also generates a
    unique `orderId` and `confirmedAt` (UTC) timestamp and calls
    `Save-ConfirmedOrder` to append the order to `data/orders.json` -
    the only persistence in this backend, and the only function that
    ever writes to that file, so a draft can never end up saved as a
    confirmed order. Calling `confirm_order` again with nothing changed
    in between is a no-op (returns the existing `orderId` instead of
    saving a duplicate record).
  - Either way, the model has to ask the customer for missing/invalid
    info rather than guess. On a tool call, the backend makes a second
    (tool-less) call to the model so it can turn the result into a
    normal reply.
- Confirming an order saves it to `data/orders.json`, but there's no
  payment or fulfillment handoff beyond that yet — see
  `prompts/system-prompt.md`.

The frontend chat UI (`frontend/chatbot.html`) is not wired up to this
endpoint yet — it still only shows mock messages.

## Staff dashboard

`dashboard.html` is a minimal, self-contained page (own inline CSS/JS,
doesn't share `frontend/`'s design system) for staff to see and update
confirmed orders. It's served by `server.ps1` itself, not `serve.ps1`,
so its `fetch()` calls to `/api/orders` and `/api/orders/status` are
same-origin — no CORS needed.

```
http://localhost:8792/dashboard
```

- `GET /api/orders` — returns the full contents of `data/orders.json`
  (`Get-SavedOrders`) as a JSON array (always an array, even when
  empty — see the code comment on the `@()`-wrapped call for the
  PowerShell gotcha that requires it).
- `POST /api/orders/status` — body `{ "orderId": "...", "status": "..." }`.
  `Update-SavedOrderStatus` validates the order exists and the status is
  one of `$script:OrderStatuses` (`confirmed`, `preparing`, `ready`,
  `completed`, `cancelled` — no enforced order between them, kept
  deliberately simple), then rewrites `data/orders.json` in place.
- The dashboard shows order ID, items (with customizations), fulfillment
  type, customer info, total, current status, and a dropdown to change
  status (auto-submits on change, then refreshes).
- Order data is customer-supplied (names, addresses, notes, item
  choices), so the dashboard escapes everything before inserting it into
  the page.
- **No authentication.** Same zero-install, local/trusted-machine
  assumption as the rest of this backend — don't expose this beyond
  that without adding one first.

## Deployment considerations

This backend was built for local/trusted use on one machine, not for
public hosting as-is:

- **Binds to `localhost` only** (`$listener.Prefixes.Add("http://localhost:$Port/")`
  in both `server.ps1` and the root `serve.ps1`). It will not accept
  connections from other machines even on the same network - by
  design, not an oversight. Making it reachable beyond localhost needs
  a different `HttpListener` prefix (typically `+`, which needs an
  admin-run `netsh http add urlacl` reservation on Windows) plus
  authentication first - neither is done here.
- **No authentication on any endpoint** - `/api/chat`, `/api/orders`,
  and `/api/orders/status` (which lets anyone with network access read
  or edit every saved order's status) are all open. Do not put this
  behind a public hostname/IP without adding auth.
- **State is process-local.** Order-in-progress sessions
  (`$script:Sessions`) live only in memory - restarting `server.ps1`
  loses every in-progress (unconfirmed) order. Only confirmed orders
  survive, in `data/orders.json`.
- **`data/orders.json` is the only persistence** - a flat file, not a
  database, gitignored (see root `.gitignore`) because it holds
  customer PII once orders come in. Back it up like any other
  production data file; there's no replication or transaction safety
  beyond a single process writing to a single file.
- The frontend's own checkout flow (`frontend/js/cart.js`, WhatsApp/call
  handoff) doesn't call this backend at all and works completely
  independently — deploying the static site does not require this
  backend to be running anywhere.
