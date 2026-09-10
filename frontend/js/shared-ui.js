// Icons, header, footer and cart-drawer markup shared by every page.
// Defined as JS template strings (not fetched partials) so the site keeps
// working when opened directly via file:// as well as from a local server.

const ICONS = {
  pizza: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M12 2 2 20h20L12 2Z"/><circle cx="12" cy="12" r="1.1" fill="currentColor" stroke="none"/><circle cx="9" cy="16" r="1.1" fill="currentColor" stroke="none"/><circle cx="15" cy="15" r="1.1" fill="currentColor" stroke="none"/></svg>',
  salad: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M3 12a9 9 0 0 1 18 0Z"/><path d="M3 12h18"/><path d="M12 3v9M7 5l2 6M17 5l-2 6"/></svg>',
  pasta: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><ellipse cx="12" cy="16" rx="8" ry="4"/><path d="M6 16c1-4 3-9 2-12M12 16c1-5 2-9 1-13M18 16c-1-4-2-9-1-12"/></svg>',
  sides: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="4" y="9" width="16" height="8" rx="2"/><path d="M8 9V6a4 4 0 0 1 8 0v3"/></svg>',
  dessert: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M5 10h14l-1.5 9h-11L5 10Z"/><path d="M9 10a3 3 0 0 1 6 0M12 4v3"/></svg>',
  drink: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M7 3h10l-1.2 16.5A2 2 0 0 1 13.8 21h-3.6a2 2 0 0 1-2-1.5L7 3Z"/><path d="M6 8h12"/></svg>',
  cart: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="9" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.5 3h2l2.7 12.4a2 2 0 0 0 2 1.6h8.2a2 2 0 0 0 2-1.6L21 7H6"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>',
  close: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  instagram: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.2" cy="6.8" r="1" fill="currentColor" stroke="none"/></svg>',
  whatsapp: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M3 21l1.4-4.2A8.5 8.5 0 1 1 8 19.6L3 21Z"/><path d="M8.5 9.5c0 3.5 3 6 6.5 6"/></svg>',
  phone: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M5 4h3l1.5 4.5L7.5 10a11 11 0 0 0 6.5 6.5l1.5-2L20 16v3a2 2 0 0 1-2 2A15 15 0 0 1 3 6a2 2 0 0 1 2-2Z"/></svg>',
  mapPin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M12 21s7-6.5 7-12a7 7 0 1 0-14 0c0 5.5 7 12 7 12Z"/><circle cx="12" cy="9" r="2.4"/></svg>',
  clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6 9 17l-5-5"/></svg>',
  heart: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M12 20s-7-4.4-9.5-8.8C.6 7.6 2.6 4 6.3 4A5 5 0 0 1 12 7.5 5 5 0 0 1 17.7 4c3.7 0 5.7 3.6 3.8 7.2C19 15.6 12 20 12 20Z"/></svg>',
  chat: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M4 5h16v11H8l-4 4V5Z"/></svg>',
};

function icon(name) {
  return ICONS[name] || "";
}

function renderHeader(activePage) {
  const link = (href, label, key) =>
    `<a href="${href}" ${activePage === key ? 'aria-current="page"' : ""}>${label}</a>`;

  return `
    <a class="skip-link" href="#main">Skip to content</a>
    <header class="site-header">
      <div class="container">
        <a class="brand" href="index.html">
          <img class="brand-logo-img" src="img/logo-wordmark.png" alt="8 Portions Pizza" />
        </a>
        <nav class="main-nav" aria-label="Primary">
          ${link("index.html", "Home", "home")}
          ${link("menu.html", "Menu", "menu")}
          ${link("index.html#branches", "Branches", "branches")}
          ${link("index.html#about", "About", "about")}
          ${link("index.html#footer", "Contact", "contact")}
        </nav>
        <div class="header-actions">
          <a class="btn btn-ghost btn-sm" href="menu.html">Order Now</a>
          <a class="icon-btn" href="chatbot.html" aria-label="Chat with CafeBot">
            ${icon("chat")}
          </a>
          <button class="icon-btn" id="cart-toggle" aria-haspopup="dialog" aria-label="Open cart">
            ${icon("cart")}
            <span class="cart-count" id="cart-count" hidden>0</span>
          </button>
          <button class="nav-toggle" id="nav-toggle" aria-expanded="false" aria-controls="primary-nav" aria-label="Toggle menu">
            <span></span>
          </button>
        </div>
      </div>
    </header>
  `;
}

function renderFooter() {
  const year = new Date().getFullYear();
  return `
    <footer class="site-footer" id="footer">
      <div class="container">
        <div class="footer-grid">
          <div class="footer-brand">
            <a class="footer-wordmark" href="index.html">
              8PORTIONS.
              <small>SPECIALITY PIZZA</small>
            </a>
            <p>Neapolitan/NY-style dough, cold-fermented, organic mozzarella
            and Italian olive oil. Menu and prices reflect the real 8 Portions
            menu (Dhahran branch); branch contact details are still pending
            confirmation from the client.</p>
            <div class="footer-social">
              <a href="${SITE.instagramUrl}" target="_blank" rel="noopener" aria-label="Instagram">${icon("instagram")}</a>
            </div>
          </div>
          <div class="footer-col">
            <h4>Explore</h4>
            <ul>
              <li><a href="index.html">Home</a></li>
              <li><a href="menu.html">Full Menu</a></li>
              <li><a href="chatbot.html">Chat with CafeBot</a></li>
              <li><a href="index.html#about">Our Story</a></li>
              <li><a href="index.html#branches">Branches</a></li>
            </ul>
          </div>
          <div class="footer-col">
            <h4>Menu</h4>
            <ul>
              <li><a href="menu.html#pizza">Pizza</a></li>
              <li><a href="menu.html#pasta">Pasta</a></li>
              <li><a href="menu.html#salads">Salads</a></li>
              <li><a href="menu.html#desserts">Desserts</a></li>
            </ul>
          </div>
          <div class="footer-col">
            <h4>Contact</h4>
            <ul>
              <li>${SITE.phone} <em style="opacity:.6">(TBD)</em></li>
              <li>${SITE.email} <em style="opacity:.6">(TBD)</em></li>
              <li><a href="${SITE.instagramUrl}" target="_blank" rel="noopener">${SITE.instagramHandle}</a></li>
            </ul>
          </div>
        </div>
        <div class="footer-bottom">
          <span>&copy; ${year} 8 Portions Pizza. All rights reserved.</span>
          <span>
            <a href="privacy.html">Privacy Policy</a> &middot;
            <a href="terms.html">Terms &amp; Conditions</a>
          </span>
        </div>
      </div>
    </footer>
  `;
}

function renderCartDrawerShell() {
  return `
    <div class="drawer-overlay" id="drawer-overlay">
      <aside class="drawer" role="dialog" aria-modal="true" aria-label="Cart" id="cart-drawer">
        <div id="drawer-content"></div>
      </aside>
    </div>
  `;
}

function observeReveals() {
  const targets = document.querySelectorAll("[data-reveal]:not(.is-visible)");
  if (!("IntersectionObserver" in window)) {
    targets.forEach((t) => t.classList.add("is-visible"));
    return;
  }
  const observer = new IntersectionObserver(
    (entries, obs) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          obs.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.15 }
  );
  targets.forEach((t) => observer.observe(t));
}

function mountLayout(activePage) {
  document.body.insertAdjacentHTML("afterbegin", renderHeader(activePage));
  document.body.insertAdjacentHTML("beforeend", renderFooter());
  document.body.insertAdjacentHTML("beforeend", renderCartDrawerShell());

  const navToggle = document.getElementById("nav-toggle");
  navToggle.addEventListener("click", () => {
    const isOpen = document.body.classList.toggle("nav-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
  });

  document.getElementById("cart-toggle").addEventListener("click", () => openCart());
}
