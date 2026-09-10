# prompts/

- `system-prompt.md` — CafeBot's real, active system instructions:
  menu grounding, recommendations, adding/changing/removing order
  items, promotions, pickup/delivery, delivery-address confirmation,
  the pre-checkout summary, and the explicit order-confirmation gate.
  Loaded verbatim by `Build-SystemMessage` in `backend/server.ps1` on
  every request, alongside the live menu/order/promotions data - see
  the file's own header comment for what's still draft vs. decided.

Keeping this in its own file (instead of buried in `server.ps1`) makes
it easy to read and edit without touching backend logic.
