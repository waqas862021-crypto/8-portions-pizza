# backend/

Server-side code will go here — the part that:

- Receives a message from the frontend
- Sends it (with the system prompt from `prompts/`) to the AI model
- Applies any order logic (reading `data/menu.json`, etc.)
- Sends a reply back to the frontend

Suggested starting point: a single small file such as `main.py`
(FastAPI/Flask) or `server.js` (Express) with one endpoint, e.g.
`POST /chat`. Keep it to one file for as long as possible — split it up
only once it actually gets hard to follow.

No backend code has been written yet.
