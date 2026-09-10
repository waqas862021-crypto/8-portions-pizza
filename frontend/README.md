# frontend/

The full 8 Portions site: `index.html` (home) and `menu.html` (full
menu), plus `privacy.html`/`terms.html` stubs. Static HTML/CSS/vanilla
JS — no build step.

- `chatbot.html` / `js/chatbot.js` — CafeBot chat UI, calls
  `backend/server.ps1`'s `POST /api/chat` directly from the browser (see
  `backend/README.md`). Linked from the header (chat icon, next to cart)
  and footer on every page via `shared-ui.js`. Needs `backend/server.ps1`
  running with a configured `.env` to get real replies.

- `css/styles.css` — the whole design system (colors, type, spacing,
  every component) as one hand-written stylesheet.
- `js/config.js`, `js/menu-data.js`, `js/branch-data.js` — the data.
  Read the comments at the top of each before editing values; most menu
  data is verified against the client's real ordering platform, some
  fields (contact info, addresses) are still marked TBD.
- `js/shared-ui.js` — header/footer/cart-drawer markup + the small inline
  SVG icon set, injected into every page via JS.
- `js/cart.js` — cart state (localStorage), the cart drawer, and the
  checkout flow (delivery/pickup, WhatsApp/call handoff — no backend or
  payment processing yet).
- `js/product-ui.js` — the product card markup and the customization
  modal (pizza size, half-and-half, quantity, notes). Shared by the
  homepage's "Signature Pizzas" section and the full menu grid.
- `js/menu-page.js` — menu.html's search box, category tabs, and grid.
- `js/main.js` — index.html's section rendering (signature grid, branch
  list, category tiles, Instagram section).
- `img/` — the real 8 Portions logo (`logo-wordmark.png`, cropped from
  their official ordering-platform asset; `logo-mark.jpeg`, their icon
  mark, also used as the favicon).

No framework, no CDN framework, no bundler. Keep it that way in this
phase — see the root [CLAUDE.md](../CLAUDE.md) for why and what "Phase B"
would change.
