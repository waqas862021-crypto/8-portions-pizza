# CLAUDE.md

Guidance for any AI coding assistant (including Claude) working in this
repository.

## Project purpose

This is the marketing + ordering website for **8 Portions**, a real
speciality pizza restaurant in Saudi Arabia (branches in Riyadh and
Dhahran, Instagram @8portionspizza). A customer browses the menu, adds
items to a cart, customizes pizzas (size, half-and-half), and checks out
— the checkout hands off a formatted order summary via WhatsApp/phone
rather than processing payment directly (see "Current phase" below).

This project's scope changed from an earlier "simple chat-ordering bot"
concept to a full browse-and-order website, at the client's request.

## Current phase: Phase A — static site, no backend

**The machine this is developed on has no Node.js, no Python, and no
ability to install software** (locked-down company machine). That is a
hard constraint, not a preference — it rules out Next.js/React/any build
tooling or server-side language until that changes.

Phase A is a fully static site: plain HTML/CSS/vanilla JS, no framework,
no bundler, no package manager. It works opened directly via `file://`
or served by any static file server (see `serve.ps1`, a zero-install
`HttpListener`-based preview server used for local testing — no Node/
Python required).

**Phase B (not built yet)**: a real backend, database, order storage, an
admin dashboard for managing menu/branches/orders, real payment gateway
integration, and a live Instagram feed. These all need a server runtime.
Don't add fake/mocked versions of these — wait until a runtime is
available (Node install approved, or a hosting platform that builds
server-side for you), then revisit the architecture rather than bolting
a backend onto the static site ad hoc.

## Architecture

```
frontend/
├── index.html, menu.html, privacy.html, terms.html
├── css/styles.css       — hand-written design system (CSS custom
│                          properties for color/type/spacing), no
│                          Tailwind/framework
├── js/
│   ├── config.js          site constants (brand info, currency, TBD
│   │                      contact fields)
│   ├── menu-data.js        the menu (see "Real data" below)
│   ├── branch-data.js      branches
│   ├── shared-ui.js        header/footer/cart-drawer markup + icons,
│   │                       injected via JS (not fetch()-based partials
│   │                       — keeps file:// working, no CORS issues)
│   ├── cart.js              cart state (localStorage), drawer, checkout
│   │                       flow (WhatsApp/call handoff, no payment)
│   ├── product-ui.js        product card + customization modal (size,
│   │                       half-and-half, qty, notes) — shared by the
│   │                       homepage and the menu page
│   ├── menu-page.js          menu.html search/filter/grid
│   └── main.js                index.html section rendering
├── img/                    real logo assets (see below)
├── robots.txt, sitemap.xml
serve.ps1                   local preview server (no install needed)
backend/, data/, prompts/   left over from the original chat-bot scaffold;
                             unused in Phase A, candidates to repurpose in
                             Phase B (real order storage, menu API)
```

Keep this shape in Phase A. Don't reach for a framework, bundler, or
backend to solve something plain HTML/CSS/JS can already do.

## Real data — what's verified vs. placeholder

Most of the menu and brand data is **real**, pulled directly from 8
Portions' own official QR-ordering platform (8-portions.yallaqrcodes.com)
and their Instagram. Don't casually "fix" or "simplify" values in
`menu-data.js` / `branch-data.js` — check the comments at the top of
those files before changing prices, descriptions, or branch details.

Still unverified / TBD (don't invent values for these):
- Branch street addresses and phone numbers (`branch-data.js`)
- WhatsApp Business number, contact phone/email (`config.js`)
- Customer reviews (the homepage has an explicit empty state — don't add
  fabricated testimonials)

The real logo files are in `frontend/img/` (`logo-wordmark.png`,
`logo-mark.jpeg`) — use these instead of inventing new brand marks.

## Coding rules

- Keep it beginner-friendly: prefer plain, readable code over clever
  abstractions.
- Keep each part in as few files as reasonably possible — don't split
  code into many small modules until a file actually becomes hard to
  follow.
- No new dependencies/frameworks unless the task requires them and
  there isn't a simpler way with what's already in the project. Google
  Fonts (via `<link>`) is the one external dependency already in use;
  don't add a CDN framework (Tailwind, Bootstrap, jQuery, etc.) on top
  of the hand-written CSS system.
- Match the existing style and structure of the file you're editing
  rather than introducing a new pattern.
- Don't add features, endpoints, or files that weren't asked for.
- Leave a short comment explaining anything non-obvious (e.g. why a
  particular data shape or pricing rule was chosen).

## Security rules

- Never hardcode API keys, passwords, or other secrets in code — they
  belong in `.env` (and `.env` must stay out of version control; see
  `.gitignore`). Phase A doesn't call any paid API, so there's currently
  nothing that needs a key — don't add one speculatively.
- Never commit or print the contents of `.env` or any real secret value.
- Treat all customer input (checkout form fields) as untrusted: this
  site renders it via `innerHTML` in a couple of places (cart summary,
  confirmation screen) — always go through the existing `escapeHtml()`
  helper in `cart.js`, never interpolate raw user input into HTML.
- Don't send more customer data anywhere than the task actually needs —
  checkout data only ever goes into a WhatsApp link or is shown back to
  the same customer, never to a third party.
- Don't disable or bypass any validation or error handling to "just make
  it work" — fix the underlying issue instead.

## Working on this project

- Modify only the files needed for the current task. Don't refactor,
  rename, reorganize, or "clean up" unrelated files or folders while
  doing so.
- If a task seems to require touching many unrelated files, stop and
  confirm that's really needed before proceeding.
- Before starting a Phase B (backend/admin/payments) task, confirm a
  runtime is actually available on the dev machine now — don't assume
  the Node.js constraint above has been lifted.
