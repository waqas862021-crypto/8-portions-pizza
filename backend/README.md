# backend/

Server-side code for CafeBot. This machine has no Node.js or Python and
no ability to install either (locked-down company machine), so instead
of the FastAPI/Flask/Express stack you'd normally reach for, `server.ps1`
uses .NET's built-in `HttpListener` from PowerShell — the same
zero-install approach the root `serve.ps1` uses to preview the frontend.
If a real runtime is ever approved, this can be replaced with a
Python/Node equivalent.

## server.ps1

One endpoint: `POST /api/chat`.

```powershell
./backend/server.ps1          # listens on http://localhost:8792
```

Request body: `{ "message": "...", "history": [{ "role": "user"|"assistant", "content": "..." }] }`
Response body: `{ "reply": "..." }`

What it does:
- Loads `AI_API_KEY`, `AI_API_BASE_URL`, `AI_MODEL_NAME` from `.env`
  (see `.env.example`) and calls an OpenAI-compatible `/chat/completions`
  endpoint.
- Builds the system message from `prompts/system-prompt.md` plus the
  current contents of `data/menu.json`, so CafeBot only knows about menu
  items that are actually in that file — it's told never to invent
  items or prices.
- Also includes the raw order state and a concise, pre-formatted plain-
  text summary of it (`Format-OrderSummary`: each line's quantity, chosen
  option labels, and price, plus the total), so the model can tell the
  customer what's in their order without reconstructing one from the raw
  JSON itself.
- Computes which `data/promotions.json` entries are both `active` and
  currently eligible for the live order (`Get-EligiblePromotions` /
  `Test-PromotionEligibility`: category rules, `minOrderValue`, `days`,
  `timeWindow`, all checked against the real order/menu/clock) and gives
  the model **only that pre-filtered list** — never the raw promotions
  file — so it can't mention or apply a promotion that isn't real,
  active, or currently eligible.
- Gives the model six tools:
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
  - Either way, the model has to ask the customer for missing/invalid
    info rather than guess. On a tool call, the backend makes a second
    (tool-less) call to the model so it can turn the result into a
    normal reply.
- No checkout yet — see `prompts/system-prompt.md`.

The frontend chat UI (`frontend/chatbot.html`) is not wired up to this
endpoint yet — it still only shows mock messages.
