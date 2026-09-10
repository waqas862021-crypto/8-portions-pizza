// Menu page: search + category filtering + grid, on top of the shared
// product card / modal logic in product-ui.js.

const filterState = { query: "", category: "all" };

function matchesFilter(item) {
  const inCategory = filterState.category === "all" || item.category === filterState.category;
  const q = filterState.query.trim().toLowerCase();
  const inQuery = !q || item.name.toLowerCase().includes(q) || item.description.toLowerCase().includes(q);
  return inCategory && inQuery;
}

function renderCategoryTabs() {
  const el = document.getElementById("category-tabs");
  const all = [{ id: "all", label: "All" }, ...CATEGORIES];
  el.innerHTML = all
    .map(
      (c) => `<button data-category="${c.id}" aria-pressed="${filterState.category === c.id}">${c.label}</button>`
    )
    .join("");
  el.querySelectorAll("button").forEach((btn) => {
    btn.addEventListener("click", () => {
      filterState.category = btn.dataset.category;
      renderCategoryTabs();
      renderMenuGrid();
    });
  });
}

function renderMenuGrid() {
  const grid = document.getElementById("menu-grid");
  const countEl = document.getElementById("menu-results-count");
  const items = MENU_ITEMS.filter(matchesFilter);

  countEl.textContent = `${items.length} item${items.length === 1 ? "" : "s"}`;

  if (!items.length) {
    grid.innerHTML = `<div class="menu-empty">No items match your search. Try a different keyword or category.</div>`;
    grid.className = "";
    return;
  }

  grid.className = "grid grid-3";
  grid.innerHTML = items.map(foodCardHtml).join("");
  wireFoodCardButtons(grid);
  observeReveals();
}

function initMenuPage() {
  mountLayout("menu");

  const hash = window.location.hash.replace("#", "");
  if (hash && CATEGORIES.some((c) => c.id === hash)) {
    filterState.category = hash;
  }

  renderCategoryTabs();
  renderMenuGrid();

  const search = document.getElementById("menu-search");
  search.addEventListener("input", (e) => {
    filterState.query = e.target.value;
    renderMenuGrid();
  });
}

// Script tag sits at the end of <body>, so the DOM above it (search input,
// grid container, modal shell) is already parsed and available here.
initMenuPage();
