// CafeBot chat interface — UI prototype only. Conversation starts with a
// scripted mock exchange, and sending a message triggers a canned reply
// after a short "typing" delay. No AI API, backend, or auth is wired up.

const MOCK_CONVERSATION = [
  { from: "bot", text: "Hi! I'm CafeBot 👋 I can help you browse the menu, check today's promotions, or start an order. What can I get you?" },
  { from: "customer", text: "Hi, what pizzas do you have?" },
  { from: "bot", text: "We've got a few favorites — Naimi Lamb, Isfahani, and the classics. Want me to walk you through the full menu?" },
];

const MOCK_REPLIES = [
  "Got it, noting that down. (This is a UI prototype, so I can't place real orders yet.)",
  "Thanks for the message! A real CafeBot response will go here once it's connected.",
  "Sounds good. Anything else you'd like to add?",
  "I hear you — for now this chat is just a visual mockup, no live answers yet.",
];

let mockReplyIndex = 0;

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

function loadMockConversation() {
  MOCK_CONVERSATION.forEach((message) => appendBubble(message.from, message.text));
}

function sendMockReply(onDone) {
  showTypingIndicator();
  setTimeout(() => {
    hideTypingIndicator();
    appendBubble("bot", MOCK_REPLIES[mockReplyIndex % MOCK_REPLIES.length]);
    mockReplyIndex += 1;
    onDone();
  }, 900);
}

function initChatForm() {
  const form = document.getElementById("chat-form");
  const input = document.getElementById("chat-input");
  const sendBtn = form.querySelector(".chat-send-btn");

  form.addEventListener("submit", (e) => {
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
    sendMockReply(() => {
      input.disabled = false;
      sendBtn.disabled = false;
      input.focus();
    });
  });
}

function initChatbotPage() {
  loadMockConversation();
  initChatForm();
}

initChatbotPage();
