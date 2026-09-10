# 8 Portions — Website

The marketing + ordering website for **8 Portions**, a speciality pizza
restaurant in Saudi Arabia (Riyadh &amp; Dhahran, @8portionspizza on
Instagram).

See [CLAUDE.md](CLAUDE.md) for full project context, current phase, and
what's real vs. placeholder data.

## Quick start

This is a static site — no build step, no install required. Two ways to
view it:

1. **Just open it** — double-click `frontend/index.html`.
2. **Or serve it locally** (recommended — avoids any `file://` quirks):
   ```powershell
   powershell -ExecutionPolicy Bypass -File serve.ps1
   ```
   then open http://localhost:8791/index.html. `serve.ps1` is a small
   zero-install static file server (uses .NET's built-in `HttpListener`
   — no Node.js/Python needed) **for local preview only** — don't use it
   to serve the site in production.

**Deploying the site itself** just means uploading the contents of
`frontend/` to any static host (it's plain HTML/CSS/JS, no build output
to generate) — `frontend/index.html` as the entry point. The checkout
flow (`frontend/js/cart.js`) works standalone via a WhatsApp/call
handoff and needs nothing else running.

## Folder structure

```
frontend/            the actual site (see frontend/README.md)
backend/, data/,      CafeBot: an AI chat-ordering backend + staff
prompts/              dashboard, built separately from the site above
                      and not linked from it yet - see backend/README.md
                      before deploying it (no auth, localhost-only by
                      default)
serve.ps1             local preview server for frontend/
```
