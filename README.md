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
   — no Node.js/Python needed).

## Folder structure

```
frontend/            the actual site (see frontend/README.md)
backend/, data/,      left over from an earlier "chat ordering bot"
prompts/              concept; unused for now, see CLAUDE.md "Phase B"
serve.ps1             local preview server
```
