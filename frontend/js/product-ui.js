// Product card markup + the customization modal (size / half-and-half /
// quantity / notes / live price). Shared by the homepage (Signature
// Pizzas) and the full menu page so there's one modal implementation.

let modalState = null; // { item, sizeId, qty, notes, halfWithId }

function foodCardHtml(item) {
  const badges = [];
  if (item.signature) badges.push('<span class="badge badge-signature">Signature</span>');
  if (item.popular) badges.push('<span class="badge badge-popular">Popular</span>');

  const priceLabel = item.sizes ? `<span class="price price-from">${formatPrice(item.basePrice)}</span>` : `<span class="price">${formatPrice(item.basePrice)}</span>`;
  const kcalLabel = item.kcal ? `<span class="kcal-tag">${item.kcal} kcal</span>` : "";

  const media = item.image
    ? `<img src="${item.image}" alt="${escapeHtml(item.name)}" loading="lazy" />`
    : icon(item.icon);

  return `
    <article class="food-card" data-reveal>
      <div class="food-card-media">
        <div class="badge-row">${badges.join("")}</div>
        ${media}
      </div>
      <div class="food-card-body">
        <h3>${escapeHtml(item.name)}</h3>
        <p class="food-card-desc">${escapeHtml(item.description)}</p>
        ${kcalLabel}
        <div class="food-card-footer">
          ${priceLabel}
          <button class="btn btn-primary btn-sm food-card-add" data-open-item="${item.id}">Add</button>
        </div>
      </div>
    </article>
  `;
}

function wireFoodCardButtons(container) {
  container.querySelectorAll("[data-open-item]").forEach((btn) => {
    btn.addEventListener("click", () => handleAddClick(btn.dataset.openItem, btn));
  });
}

function handleAddClick(itemId, btn) {
  const item = MENU_ITEMS.find((i) => i.id === itemId);
  if (!item) return;
  if (item.sizes) {
    openProductModal(item);
    return;
  }
  addToCart({
    menuItemId: item.id,
    name: item.name,
    unitPrice: item.basePrice,
    qty: 1,
    sizeLabel: "",
    toppingLabels: [],
    icon: item.icon,
  });
  const original = btn.textContent;
  btn.textContent = "Added ✓";
  btn.disabled = true;
  setTimeout(() => {
    btn.textContent = original;
    btn.disabled = false;
  }, 900);
}

function openProductModal(item) {
  modalState = {
    item,
    sizeId: item.sizes ? item.sizes[0].id : null,
    qty: 1,
    notes: "",
    halfWithId: null,
  };
  renderModal();
  document.getElementById("product-modal").classList.add("open");
  document.addEventListener("keydown", handleModalKeydown);
}

function closeProductModal() {
  document.getElementById("product-modal").classList.remove("open");
  document.removeEventListener("keydown", handleModalKeydown);
}

function handleModalKeydown(e) {
  if (e.key === "Escape") closeProductModal();
}

function otherPizzaOptions(item) {
  return pizzaItems().filter((p) => p.id !== item.id);
}

// Real rule from the source menu: "Half-and-half pizzas will be priced
// based on the higher of the two prices" — not a flat topping fee.
function modalUnitPrice() {
  const { item, sizeId, halfWithId } = modalState;
  const size = item.sizes.find((s) => s.id === sizeId);
  if (!halfWithId) return size.price;
  const other = MENU_ITEMS.find((p) => p.id === halfWithId);
  const otherSize = other.sizes.find((s) => s.id === sizeId);
  return Math.max(size.price, otherSize.price);
}

function modalPrice() {
  return modalUnitPrice() * modalState.qty;
}

function renderModal() {
  const { item, sizeId, qty, halfWithId } = modalState;
  const root = document.getElementById("product-modal");

  const sizeOptions = `
    <div class="option-group">
      <h4>Size</h4>
      <div class="option-row" role="radiogroup" aria-label="Size">
        ${item.sizes
          .map((s) => `<button type="button" class="option-pill" data-size="${s.id}" aria-pressed="${s.id === sizeId}">${s.label} <small>${formatPrice(s.price)}</small></button>`)
          .join("")}
      </div>
    </div>`;

  const halfOptions = otherPizzaOptions(item)
    .map((p) => `<option value="${p.id}" ${p.id === halfWithId ? "selected" : ""}>${escapeHtml(p.name)}</option>`)
    .join("");

  const halfAndHalf = `
    <div class="option-group">
      <h4>Half &amp; Half</h4>
      <label class="option-pill" style="width:100%;justify-content:space-between">
        <span>Split with another pizza</span>
        <input type="checkbox" id="modal-half-toggle" ${halfWithId ? "checked" : ""} />
      </label>
      ${
        halfWithId !== null
          ? `<div class="field" style="margin-top:.75rem">
               <label for="modal-half-select">Second half</label>
               <select id="modal-half-select">${halfOptions}</select>
             </div>`
          : ""
      }
      <p style="font-size:.78rem;color:var(--color-text-muted);margin-top:.5rem">Half-and-half pizzas are priced at the higher of the two prices.</p>
    </div>`;

  root.innerHTML = `
    <div class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title">
      <div class="modal-media">
        <button class="icon-btn modal-close" id="modal-close" aria-label="Close">${icon("close")}</button>
        ${item.image ? `<img src="${item.image}" alt="${escapeHtml(item.name)}" />` : icon(item.icon)}
      </div>
      <div class="modal-body">
        <div>
          <h2 id="modal-title">${escapeHtml(item.name)}</h2>
          <p class="food-card-desc">${escapeHtml(item.description)}</p>
          ${item.kcal ? `<span class="kcal-tag">${item.kcal} kcal</span>` : ""}
        </div>
        ${sizeOptions}
        ${halfAndHalf}
        <div class="option-group">
          <h4>Quantity</h4>
          <div class="qty-stepper">
            <button type="button" id="modal-qty-minus" aria-label="Decrease quantity">&minus;</button>
            <span id="modal-qty">${qty}</span>
            <button type="button" id="modal-qty-plus" aria-label="Increase quantity">+</button>
          </div>
        </div>
        <div class="field">
          <label for="modal-notes">Special instructions (optional)</label>
          <textarea id="modal-notes" rows="2" placeholder="e.g. no onions">${escapeHtml(modalState.notes)}</textarea>
        </div>
        <div class="modal-footer">
          <span class="price" id="modal-price">${formatPrice(modalPrice())}</span>
          <button class="btn btn-primary" id="modal-add">Add to Cart</button>
        </div>
      </div>
    </div>
  `;

  wireModal();
}

function wireModal() {
  const { item } = modalState;
  document.getElementById("modal-close").addEventListener("click", closeProductModal);
  document.getElementById("product-modal").addEventListener("click", (e) => {
    if (e.target.id === "product-modal") closeProductModal();
  });

  document.querySelectorAll("[data-size]").forEach((btn) => {
    btn.addEventListener("click", () => {
      modalState.sizeId = btn.dataset.size;
      renderModal();
    });
  });

  document.getElementById("modal-half-toggle").addEventListener("change", (e) => {
    modalState.halfWithId = e.target.checked ? otherPizzaOptions(item)[0]?.id ?? null : null;
    renderModal();
  });

  document.getElementById("modal-half-select")?.addEventListener("change", (e) => {
    modalState.halfWithId = e.target.value;
    updateModalPrice();
  });

  document.getElementById("modal-qty-plus").addEventListener("click", () => {
    modalState.qty += 1;
    updateModalPrice();
  });
  document.getElementById("modal-qty-minus").addEventListener("click", () => {
    modalState.qty = Math.max(1, modalState.qty - 1);
    updateModalPrice();
  });
  document.getElementById("modal-notes").addEventListener("input", (e) => {
    modalState.notes = e.target.value;
  });
  document.getElementById("modal-add").addEventListener("click", addFromModal);
}

function updateModalPrice() {
  document.getElementById("modal-qty").textContent = modalState.qty;
  document.getElementById("modal-price").textContent = formatPrice(modalPrice());
}

function addFromModal() {
  const { item, sizeId, qty, notes, halfWithId } = modalState;
  const size = item.sizes.find((s) => s.id === sizeId);
  const other = halfWithId ? MENU_ITEMS.find((p) => p.id === halfWithId) : null;

  addToCart({
    menuItemId: item.id,
    name: other ? `${item.name} / ${other.name} (Half & Half)` : item.name,
    unitPrice: modalUnitPrice(),
    qty,
    sizeLabel: size.label,
    toppingLabels: [],
    notes,
    icon: item.icon,
  });

  closeProductModal();
  openCart();
}
