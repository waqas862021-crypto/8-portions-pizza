// Cart state (persisted to localStorage), cart drawer rendering, and the
// checkout flow. There is no backend in this phase, so "checkout" builds a
// clear order summary and hands off via WhatsApp click-to-chat (or a
// call-us fallback when no WhatsApp number is configured yet).

const CART_STORAGE_KEY = "8pp_cart";

let cart = loadCart();
let drawerView = "cart"; // 'cart' | 'checkout' | 'confirmation'
let lastConfirmation = null;

function loadCart() {
  try {
    const raw = localStorage.getItem(CART_STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch (err) {
    return [];
  }
}

function persistCart() {
  try {
    localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(cart));
  } catch (err) {
    // Storage unavailable (private browsing, quota) — cart just won't persist.
  }
}

function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value;
  return div.innerHTML;
}

function makeId() {
  return window.crypto && crypto.randomUUID
    ? crypto.randomUUID()
    : `id-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function addToCart(entry) {
  cart.push({ id: makeId(), ...entry });
  persistCart();
  renderCartBadge();
  renderDrawer();
}

function removeCartItem(id) {
  cart = cart.filter((item) => item.id !== id);
  persistCart();
  renderCartBadge();
  renderDrawer();
}

function changeCartQty(id, delta) {
  const item = cart.find((i) => i.id === id);
  if (!item) return;
  item.qty = Math.max(1, item.qty + delta);
  persistCart();
  renderCartBadge();
  renderDrawer();
}

function cartCount() {
  return cart.reduce((sum, item) => sum + item.qty, 0);
}

function cartSubtotal() {
  return cart.reduce((sum, item) => sum + item.unitPrice * item.qty, 0);
}

function renderCartBadge() {
  const badge = document.getElementById("cart-count");
  if (!badge) return;
  const count = cartCount();
  badge.textContent = String(count);
  badge.hidden = count === 0;
}

function openCart() {
  drawerView = cart.length ? "cart" : "cart";
  renderDrawer();
  const overlay = document.getElementById("drawer-overlay");
  overlay.classList.add("open");
  document.addEventListener("keydown", handleDrawerKeydown);
}

function closeCart() {
  const overlay = document.getElementById("drawer-overlay");
  overlay.classList.remove("open");
  document.removeEventListener("keydown", handleDrawerKeydown);
}

function handleDrawerKeydown(e) {
  if (e.key === "Escape") closeCart();
}

function cartItemMetaLine(item) {
  const parts = [];
  if (item.sizeLabel) parts.push(item.sizeLabel);
  if (item.toppingLabels && item.toppingLabels.length) parts.push(item.toppingLabels.join(", "));
  return parts.join(" · ");
}

function renderDrawer() {
  const el = document.getElementById("drawer-content");
  if (!el) return;

  if (drawerView === "checkout") {
    el.innerHTML = renderCheckoutView();
    wireCheckoutView();
    return;
  }

  if (drawerView === "confirmation") {
    el.innerHTML = renderConfirmationView();
    wireConfirmationView();
    return;
  }

  el.innerHTML = renderCartView();
  wireCartView();
}

function renderCartView() {
  const header = `
    <div class="drawer-header">
      <h2>Your Cart</h2>
      <button class="icon-btn" id="drawer-close" aria-label="Close cart">${icon("close")}</button>
    </div>
  `;

  if (!cart.length) {
    return `
      ${header}
      <div class="drawer-body">
        <div class="drawer-empty">
          ${icon("cart")}
          <p>Your cart is empty. Add something delicious from the menu.</p>
          <a class="btn btn-primary" href="menu.html" style="margin-top:1rem">Browse Menu</a>
        </div>
      </div>
    `;
  }

  const items = cart
    .map(
      (item) => `
      <div class="cart-item">
        <div class="cart-item-thumb">${icon(item.icon || "pizza")}</div>
        <div>
          <div class="cart-item-name">${escapeHtml(item.name)}</div>
          <div class="cart-item-meta">${escapeHtml(cartItemMetaLine(item))}</div>
          <div class="cart-item-controls">
            <div class="qty-stepper">
              <button data-qty-minus="${item.id}" aria-label="Decrease quantity">&minus;</button>
              <span>${item.qty}</span>
              <button data-qty-plus="${item.id}" aria-label="Increase quantity">+</button>
            </div>
            <button class="cart-item-remove" data-remove="${item.id}">Remove</button>
          </div>
        </div>
        <div class="cart-item-price">${formatPrice(item.unitPrice * item.qty)}</div>
      </div>
    `
    )
    .join("");

  const subtotal = cartSubtotal();

  return `
    ${header}
    <div class="drawer-body">${items}</div>
    <div class="drawer-footer">
      <div class="summary-row total">
        <span>Subtotal</span>
        <span>${formatPrice(subtotal)}</span>
      </div>
      <p style="font-size:.78rem;color:var(--color-text-muted)">Delivery fee (if applicable) is confirmed at checkout.</p>
      <button class="btn btn-primary btn-block" id="go-checkout">Checkout</button>
    </div>
  `;
}

function wireCartView() {
  document.getElementById("drawer-close")?.addEventListener("click", closeCart);
  document.getElementById("go-checkout")?.addEventListener("click", () => {
    drawerView = "checkout";
    renderDrawer();
  });
  cart.forEach((item) => {
    document.querySelector(`[data-qty-plus="${item.id}"]`)?.addEventListener("click", () => changeCartQty(item.id, 1));
    document.querySelector(`[data-qty-minus="${item.id}"]`)?.addEventListener("click", () => changeCartQty(item.id, -1));
    document.querySelector(`[data-remove="${item.id}"]`)?.addEventListener("click", () => removeCartItem(item.id));
  });
}

function renderCheckoutView() {
  const subtotal = cartSubtotal();
  return `
    <div class="drawer-header">
      <h2>Checkout</h2>
      <button class="icon-btn" id="drawer-close" aria-label="Close cart">${icon("close")}</button>
    </div>
    <div class="drawer-body">
      <form id="checkout-form" novalidate>
        <div class="field" style="margin-bottom:1rem">
          <label>Fulfillment</label>
          <div class="fulfillment-toggle" role="radiogroup" aria-label="Delivery or pickup">
            <button type="button" data-fulfillment="delivery" aria-pressed="true">Delivery</button>
            <button type="button" data-fulfillment="pickup" aria-pressed="false">Pickup</button>
          </div>
        </div>
        <div class="field" style="margin-bottom:1rem">
          <label for="cust-name">Full name</label>
          <input id="cust-name" name="name" type="text" autocomplete="name" required />
          <div class="form-error" id="err-name" hidden>Please enter your name.</div>
        </div>
        <div class="field" style="margin-bottom:1rem">
          <label for="cust-phone">Phone number</label>
          <input id="cust-phone" name="phone" type="tel" autocomplete="tel" required />
          <div class="form-error" id="err-phone" hidden>Please enter a phone number.</div>
        </div>
        <div class="field" style="margin-bottom:1rem" id="address-field">
          <label for="cust-address">Delivery address</label>
          <input id="cust-address" name="address" type="text" autocomplete="street-address" />
          <div class="form-error" id="err-address" hidden>Please enter a delivery address.</div>
        </div>
        <div class="field" style="margin-bottom:1rem">
          <label for="cust-notes">Order notes (optional)</label>
          <textarea id="cust-notes" name="notes" rows="3"></textarea>
        </div>
      </form>
    </div>
    <div class="drawer-footer">
      <div class="summary-row total">
        <span>Subtotal</span>
        <span>${formatPrice(subtotal)}</span>
      </div>
      <button class="btn btn-ghost btn-block" id="back-to-cart">Back to Cart</button>
      <button class="btn btn-primary btn-block" id="place-order" form="checkout-form">Place Order</button>
    </div>
  `;
}

function wireCheckoutView() {
  document.getElementById("drawer-close")?.addEventListener("click", closeCart);
  document.getElementById("back-to-cart")?.addEventListener("click", () => {
    drawerView = "cart";
    renderDrawer();
  });

  let fulfillment = "delivery";
  const addressField = document.getElementById("address-field");
  document.querySelectorAll("[data-fulfillment]").forEach((btn) => {
    btn.addEventListener("click", () => {
      fulfillment = btn.dataset.fulfillment;
      document.querySelectorAll("[data-fulfillment]").forEach((b) => b.setAttribute("aria-pressed", String(b === btn)));
      addressField.style.display = fulfillment === "delivery" ? "block" : "none";
    });
  });

  document.getElementById("place-order")?.addEventListener("click", (e) => {
    e.preventDefault();
    const name = document.getElementById("cust-name").value.trim();
    const phone = document.getElementById("cust-phone").value.trim();
    const address = document.getElementById("cust-address").value.trim();
    const notes = document.getElementById("cust-notes").value.trim();

    let valid = true;
    toggleError("err-name", !name);
    toggleError("err-phone", !phone);
    if (!name) valid = false;
    if (!phone) valid = false;
    if (fulfillment === "delivery") {
      toggleError("err-address", !address);
      if (!address) valid = false;
    } else {
      toggleError("err-address", false);
    }
    if (!valid) return;

    submitOrder({ name, phone, address, notes, fulfillment });
  });
}

function toggleError(id, show) {
  const el = document.getElementById(id);
  if (el) el.hidden = !show;
}

function submitOrder({ name, phone, address, notes, fulfillment }) {
  const orderNumber = `8PP-${Date.now().toString(36).toUpperCase()}`;
  const lines = cart.map((item) => `${item.qty}x ${item.name}${cartItemMetaLine(item) ? " (" + cartItemMetaLine(item) + ")" : ""} — ${formatPrice(item.unitPrice * item.qty)}`);
  const subtotal = cartSubtotal();

  const summaryText = [
    `Order ${orderNumber}`,
    `Fulfillment: ${fulfillment === "delivery" ? "Delivery" : "Pickup"}`,
    `Name: ${name}`,
    `Phone: ${phone}`,
    fulfillment === "delivery" ? `Address: ${address}` : null,
    notes ? `Notes: ${notes}` : null,
    "",
    ...lines,
    "",
    `Subtotal: ${formatPrice(subtotal)}`,
  ]
    .filter(Boolean)
    .join("\n");

  lastConfirmation = { orderNumber, summaryText };
  cart = [];
  persistCart();
  renderCartBadge();
  drawerView = "confirmation";
  renderDrawer();
}

function renderConfirmationView() {
  if (!lastConfirmation) {
    drawerView = "cart";
    return renderCartView();
  }
  const link = buildWhatsappLink(lastConfirmation.summaryText);
  const handoff = link
    ? `<a class="btn btn-primary btn-block" href="${link}" target="_blank" rel="noopener">${icon("whatsapp")} Send order via WhatsApp</a>`
    : `<p style="font-size:.85rem;color:var(--color-text-muted)">Online order handoff isn't configured yet — please call ${escapeHtml(SITE.phone)} (TBD) to confirm this order.</p>`;

  return `
    <div class="drawer-header">
      <h2>Order Summary</h2>
      <button class="icon-btn" id="drawer-close" aria-label="Close cart">${icon("close")}</button>
    </div>
    <div class="drawer-body">
      <div class="confirmation">
        ${icon("check")}
        <h3>Thanks, ${escapeHtml(lastConfirmation.orderNumber)}</h3>
        <p style="color:var(--color-text-muted)">Review your order summary below, then confirm with the restaurant.</p>
        <div class="confirmation-summary">${escapeHtml(lastConfirmation.summaryText)}</div>
        ${handoff}
        <button class="btn btn-ghost btn-block" id="continue-shopping" style="margin-top:.75rem">Continue Browsing</button>
      </div>
    </div>
  `;
}

function wireConfirmationView() {
  document.getElementById("drawer-close")?.addEventListener("click", closeCart);
  document.getElementById("continue-shopping")?.addEventListener("click", closeCart);
}

document.addEventListener("DOMContentLoaded", renderCartBadge);
