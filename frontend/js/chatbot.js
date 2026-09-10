// CafeBot chat interface — wired up to backend/server.ps1's POST /api/chat.
// Order state itself lives on the backend, keyed by sessionId; this page
// only persists sessionId + the message history in localStorage so a page
// reload doesn't lose the conversation. Requires backend/server.ps1 to be
// running (see backend/README.md) with a configured .env - if it isn't,
// sending a message shows a friendly error instead of a reply.

const CAFEBOT_API_URL = "http://localhost:8792/api/chat";
const SESSION_STORAGE_KEY = "cafebot_session_id";
const HISTORY_STORAGE_KEY = "cafebot_history";
const GREETING = "Hi! I'm CafeBot 👋 I can help you browse the menu, check today's promotions, or start an order. What can I get you?";

function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value;
  return div.innerHTML;
}

function formatTime(date) {
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function bubbleHtml(from, text, time) {
  return `
    <div class="chat-bubble-row from-${from}">
      <div class="chat-bubble">
        ${escapeHtml(text)}
        <span class="chat-bubble-time">${time}</span>
      </div>
    </div>
  `;
}

function appendBubble(from, text) {
  const log = document.getElementById("chat-log");
  log.insertAdjacentHTML("beforeend", bubbleHtml(from, text, formatTime(new Date())));
  log.scrollTop = log.scrollHeight;
}

function showTypingIndicator() {
  const log = document.getElementById("chat-log");
  log.insertAdjacentHTML(
    "beforeend",
    `<div class="chat-bubble-row from-bot" id="chat-typing-row">
      <div class="chat-bubble chat-typing"><span></span><span></span><span></span></div>
    </div>`
  );
  log.scrollTop = log.scrollHeight;
}

function hideTypingIndicator() {
  document.getElementById("chat-typing-row")?.remove();
}

function getSessionId() {
  return localStorage.getItem(SESSION_STORAGE_KEY) || "";
}

function setSessionId(id) {
  if (id) localStorage.setItem(SESSION_STORAGE_KEY, id);
}

function getHistory() {
  try {
    const raw = localStorage.getItem(HISTORY_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveHistory(history) {
  // Cap so localStorage doesn't grow unbounded over a long conversation.
  localStorage.setItem(HISTORY_STORAGE_KEY, JSON.stringify(history.slice(-40)));
}

function loadConversation() {
  const history = getHistory();
  if (history.length === 0) {
    appendBubble("bot", GREETING);
    return;
  }
  history.forEach((turn) => appendBubble(turn.role === "user" ? "customer" : "bot", turn.content));
}

async function sendToCafeBot(message) {
  const history = getHistory();
  const response = await fetch(CAFEBOT_API_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ message, history, sessionId: getSessionId() }),
  });

  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `CafeBot request failed (${response.status}).`);
  }

  const data = await response.json();
  setSessionId(data.sessionId);
  saveHistory(history.concat({ role: "user", content: message }, { role: "assistant", content: data.reply }));
  return data.reply;
}

function initChatForm() {
  const form = document.getElementById("chat-form");
  const input = document.getElementById("chat-input");
  const sendBtn = form.querySelector(".chat-send-btn");

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    appendBubble("customer", text);
    input.value = "";

    // Disable the composer while a reply is pending so a second send can't
    // fire while a typing indicator is already showing (that produced two
    // overlapping "typing" bubbles with a duplicate element id).
    input.disabled = true;
    sendBtn.disabled = true;
    showTypingIndicator();

    try {
      const reply = await sendToCafeBot(text);
      hideTypingIndicator();
      appendBubble("bot", reply);
    } catch (err) {
      hideTypingIndicator();
      appendBubble("bot", "Sorry, I couldn't reach CafeBot right now - please try again in a moment.");
    } finally {
      input.disabled = false;
      sendBtn.disabled = false;
      input.focus();
    }
  });
}

function initChatbotPage() {
  loadConversation();
  initChatForm();
}

initChatbotPage();
