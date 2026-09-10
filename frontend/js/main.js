// Homepage: signature pizzas grid, "more than pizza" category tiles, and
// the branches list — all rendered from the shared data files so there's
// one source of truth with the menu page.

function renderSignatureGrid() {
  const grid = document.getElementById("signature-grid");
  const items = MENU_ITEMS.filter((i) => i.signature);
  grid.innerHTML = items.map(foodCardHtml).join("");
  wireFoodCardButtons(grid);
}

const MORE_THAN_PIZZA = ["soup", "salads", "pasta", "sides", "sweets", "drinks", "sauces"];

function renderMoreThanPizza() {
  const row = document.getElementById("more-than-pizza-row");
  row.innerHTML = MORE_THAN_PIZZA.map((catId) => {
    const cat = CATEGORIES.find((c) => c.id === catId);
    const count = MENU_ITEMS.filter((i) => i.category === catId).length;
    const sampleIcon = MENU_ITEMS.find((i) => i.category === catId)?.icon || "sides";
    return `
      <a class="more-tile" href="menu.html#${catId}" data-reveal>
        <span class="more-tile-icon">${icon(sampleIcon)}</span>
        <span class="more-tile-label">${cat.label}</span>
        <span class="more-tile-count">${count} item${count === 1 ? "" : "s"}</span>
      </a>
    `;
  }).join("");
}

function renderBranches() {
  const grid = document.getElementById("branches-grid");
  grid.innerHTML = BRANCHES.map(
    (b) => `
    <div class="branch-card" data-reveal>
      <h3>${escapeHtml(b.name)} <span style="color:var(--color-text-muted);font-weight:500">— ${escapeHtml(b.city)}</span></h3>
      <div class="branch-meta">
        ${icon("mapPin")}
        <span>${escapeHtml(b.address)}</span>
      </div>
      <div class="branch-meta">
        ${icon("clock")}
        <span>${b.hours.map((h) => `${escapeHtml(h.days)}: ${escapeHtml(h.time)}`).join("<br>")}</span>
      </div>
      <div class="branch-meta">
        ${icon("phone")}
        <span>${escapeHtml(b.phone)} <em style="opacity:.6">(TBD)</em></span>
      </div>
      <div class="branch-actions">
        <a class="btn btn-primary btn-sm" href="${googleMapsDirectionsUrl(b)}" target="_blank" rel="noopener">Get Directions</a>
      </div>
    </div>
  `
  ).join("");
}

function renderDeliveryPartners() {
  const el = document.getElementById("delivery-partners");
  if (el) el.textContent = SITE.deliveryPartners.join(" · ");
  const count = document.getElementById("delivery-partners-count");
  if (count) count.textContent = String(SITE.deliveryPartners.length);
}

function renderInstagramGrid() {
  const grid = document.getElementById("ig-grid");
  if (!grid) return;
  const photoTiles = [
    { src: "img/brand/plaque.jpg", alt: "8 Portions logo plaque" },
    { src: "img/brand/dish-napkin.jpg", alt: "A dish at 8 Portions" },
  ]
    .map((p) => `<div class="ig-tile" data-reveal><img src="${p.src}" alt="${p.alt}" loading="lazy" /></div>`)
    .join("");
  grid.innerHTML = `
    <div class="ig-tile" data-reveal>${icon("instagram")}</div>
    ${photoTiles}
    <a class="ig-tile ig-cta" href="${SITE.instagramUrl}" target="_blank" rel="noopener" data-reveal>
      ${icon("instagram")}
      Follow Us
    </a>
  `;
}

function initHomePage() {
  mountLayout("home");
  renderSignatureGrid();
  renderMoreThanPizza();
  renderBranches();
  renderDeliveryPartners();
  renderInstagramGrid();
  observeReveals();
}

initHomePage();
