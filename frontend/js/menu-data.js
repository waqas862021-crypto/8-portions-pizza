// REAL menu data, pulled directly from 8 Portions' own official QR-ordering
// platform (8-portions.yallaqrcodes.com, Dhahran branch) on 2026-09-10 —
// names, descriptions, prices (SAR) and calories are verified, not invented.
// Some descriptions are truncated in the source system's own item list
// (ends in "…"); they're kept as-is rather than guessed/completed.
//
// "signature: true" is only set on the pizzas/dishes the client themselves
// called out as noteworthy when scoping this project (Isfahani, Naimi Lamb,
// Alfredo Chicken, South African, Quinoa Salad, Pink Pasta, Arancini,
// Tiramisu) — not a restaurant-verified bestseller list. "popular" is left
// false everywhere; there's no real sales data to base that on yet, so it's
// wired up in the UI but unused until the client provides it.
//
// Half-and-half: the source menu explicitly notes "Half-and-half pizzas
// will be priced based on the higher of the two prices" — implemented in
// the product modal (menu-page.js) rather than invented as a flat topping
// fee like a typical build-your-own pizza place (8 Portions doesn't appear
// to offer topping customization on a fixed specialty menu).

const CATEGORIES = [
  { id: "pizza", label: "Pizza" },
  { id: "soup", label: "Soup" },
  { id: "salads", label: "Salads" },
  { id: "sides", label: "Sides" },
  { id: "pasta", label: "Pasta" },
  { id: "sweets", label: "Sweets" },
  { id: "drinks", label: "Drinks" },
  { id: "sauces", label: "Sauces" },
];

function pizza(id, name, description, kcalMedium, priceMedium, kcalSmall, priceSmall, signature = false) {
  return {
    id,
    name,
    category: "pizza",
    description,
    kcal: kcalMedium,
    basePrice: priceSmall,
    sizes: [
      { id: "small", label: "Small", price: priceSmall, kcal: kcalSmall },
      { id: "medium", label: "Medium", price: priceMedium, kcal: kcalMedium },
    ],
    icon: "pizza",
    signature,
    popular: false,
    verified: true,
  };
}

function dish(id, name, category, description, kcal, price, icon, signature = false) {
  return {
    id,
    name,
    category,
    description,
    kcal: kcal ?? null,
    basePrice: price,
    icon,
    signature,
    popular: false,
    verified: true,
  };
}

const MENU_ITEMS = [
  // ---- Pizza (Small / Medium) ----
  pizza("naimi-lamb-meat", "Naimi Lamb Meat", "Tomato sauce, mozzarella cheese and lamb meat marinated for 24 hours and slowly cooked for 3 hours.", 327, 86.0, 216, 56.0, true),
  pizza("isfahani", "Isfahani", "Tomato sauce, mozzarella cheese with Persian spiced chicken, sprinkled Iranian zereshk, and covered…", 323, 73.0, 214, 43.0, true),
  pizza("chicken-shish-tawook", "Chicken Shish Tawook", "Tomato sauce, mozzarella cheese, smoked shish tawook chicken and red onion with sumac spice, garnished…", 320, 73.0, 213, 43.0),
  pizza("roma", "Roma", "Tomato sauce, mozzarella cheese, caramelized onions, pepperoni, fresh white mushrooms, covered with…", 296, 73.0, 197, 43.0),
  pizza("vegetables", "Vegetables", "Tomato sauce, mozzarella cheese, Fetta Cheese, Grilled eggplants, capsicum mix, white onion, fresh basil…", 202, 71.0, 140, 43.0),
  pizza("pepperoni", "Pepperoni", "Tomato sauce, mozzarella cheese and Italian beef pepperoni slices with oregano sprinkle.", 278, 71.0, 188, 43.0),
  pizza("eggplant-pine-nuts", "Eggplant & Pine Nuts", "Tomato sauce, mozzarella cheese, Feta cheese, and slices of grilled eggplant, covered with roasted pine nuts…", 252, 71.0, 184, 43.0),
  pizza("goat-cheese", "Goat Cheese", "Tomato sauce, mozzarella cheese and Spanish goat cheese, covered with rosemary, basil leaves and olive oil…", 236, 71.0, 160, 43.0),
  pizza("margarita", "Margarita", "Tomato sauce, mozzarella cheese, Romano cheese covered with Italian seasoning and Parmigiano reggiano…", 245, 49.0, 165, 29.0),
  pizza("mushroom-pizza", "Mushroom Pizza", "Marinara sauce with mozzarella, fresh mushrooms, sundried tomato and Klamath olives served with pesto sauce…", 340, 79.0, 170, 47.0),
  pizza("truffle", "Truffle", "A mix of buffalo mozzarella & fontina cheese, topped with black truffle slices and truffle sauce.", 340, 99.0, 170, 66.0),
  pizza("south-african", "South African", "White sauce and mozzarella cheese, South African spicy chicken covered with fresh red chilli, spring onion…", 357, 77.0, 262, 47.0, true),
  pizza("alfredo-chicken", "Alfredo Chicken", "White sauce with parmigiano reggiano, mozzarella cheese, grilled chicken, garlic slices and rosemary.", 325, 71.0, 220, 43.0, true),
  pizza("butter-chicken", "Butter Chicken", "White sauce with mozzarella cheese, Indian spiced chicken, butter chicken and mint sauce.", 357, 71.0, 262, 43.0),
  pizza("mexican-chicken", "Mexican Chicken", "Char pepper sauce, cheddar & mozzarella cheese, Mexican smokey chicken, sprinkled with corn & pico de gallo…", 364, 77.0, 274, 47.0),

  // ---- Soup ----
  dish("oats-soup", "Oats Soup", "soup", "Oatmeal soup with fresh Naimi meat and bone in broth.", 220, 28.0, "sides"),

  // ---- Salads ----
  dish("burrata-cheese-salad", "Burrata Cheese Salad", "salads", "Burrata salad with pesto cherry tomatoes and baby rocca, with aged balsamic, spinach and asparagus.", 423, 88.0, "salad"),
  dish("quinoa-salad", "Quinoa Salad", "salads", "Red & white quinoa mixed with mango & avocado, feta cheese, and colorful vegetables, topped with baby…", 260, 48.0, "salad", true),

  // ---- Sides ----
  dish("arancini", "Arancini", "sides", "Wild mushroom risotto balls fried in canola oil, served with lime pesto sauce and Parmesan fondue sauce…", 625, 37.0, "sides", true),
  dish("dolma-risotto", "Dolma Risotto", "sides", "Slow cooked rice with vegetables and sour molasses.", 315, 37.0, "sides"),
  dish("chicken-fillets", "Chicken Fillets", "sides", "Six chicken fillets fried in canola oil, covered with breadcrumbs, crispy and juicy, served with honey…", 250, 49.0, "sides"),
  dish("chili-lime-chicken-wings", "Chili Lime Chicken Wings", "sides", "Six chicken wings fried in canola oil, coated with chili lime sauce and served with blue cheese dip.", null, 39.0, "sides"),
  dish("chipotle-chicken-wings", "Chipotle Chicken Wings", "sides", "Six chicken wings fried in canola oil, coated with chipotle sauce, served with blue cheese dip.", 275, 39.0, "sides"),
  dish("bbq-chicken-wings", "BBQ Chicken Wings", "sides", "Six chicken wings fried in canola oil, coated with BBQ sauce.", 265, 39.0, "sides"),
  dish("french-fries", "French Fries", "sides", "Fresh potato, prepared daily and fried in canola oil.", 229, 19.0, "sides"),

  // ---- Pasta ----
  dish("baked-bechamel-pasta", "Baked Bechamel Pasta", "pasta", "Conchiglie pasta baked in creamy béchamel with slow-cooked beef ragù, topped with Parmesan cheese and…", 780, 75.0, "pasta"),
  dish("pink-pasta", "Pink Pasta", "pasta", "Spaghetti with creamy tomato pink sauce served with rosemary chicken, topped with Parmesan and pecorino…", 540, 66.0, "pasta", true),
  dish("truffle-pasta", "Truffle Pasta", "pasta", "Spaghetti with creamy white truffle sauce served with chicken, topped with fresh baby arugula leaves.", 635, 77.0, "pasta"),
  dish("specialty-lasagna", "Specialty Lasagna", "pasta", "Oven-baked lasagna layered with premium pulled Angus beef, Bolognese, and creamy bechamel sauce…", 589, 79.0, "pasta"),
  dish("lemon-risotto-shrimp", "Lemon Risotto with Shrimp", "pasta", "Arborio risotto cooked to perfection in a lemon butter creamy sauce, served with sautéed fresh shrimp.", 465, 79.0, "pasta"),

  // ---- Sweets ----
  dish("tiramisu", "Tiramisu", "sweets", "Classic layered coffee dessert.", 390, 49.0, "dessert", true),

  // ---- Drinks ----
  dish("rosemary-pineapple-mix", "Rosemary Pineapple Mix", "drinks", "A mixture of pineapple juice and rosemary with our special blend of tropical flavors.", 134, 35.0, "drink"),
  dish("peach-habaq", "Peach Habaq", "drinks", "Spicy fresh habaq syrup served with peach sparkling juice.", 165, 35.0, "drink"),
  dish("passion-ginger-ale", "Passion Ginger Ale", "drinks", "Passion fruit mixed with orange and lemon juice and ginger ale.", 165, 35.0, "drink"),
  dish("fresh-orange-juice", "Fresh Orange Juice", "drinks", "Freshly squeezed orange juice.", 165, 18.0, "drink"),
  dish("water-pellegrino", "Water (S. Pellegrino)", "drinks", "Sparkling mineral water.", 0, 17.0, "drink"),
  dish("water", "Water", "drinks", "Still water.", 0, 3.0, "drink"),
  dish("soft-drinks", "Soft Drinks", "drinks", "Cola, Light Cola, Sprite, Fanta.", null, 9.0, "drink"),
  dish("basil-lemonade", "Basil Lemonade", "drinks", "House-made basil lemonade.", 320, 18.0, "drink"),

  // ---- Sauces (add-ons) ----
  dish("tabasco-chili-oil", "Tabasco Chili Oil Bottle", "sauces", "Extra virgin olive oil infused with the best chili by Tabasco brand, especially for 8 Portions restaurant.", null, 55.0, "sides"),
  dish("8portions-chili-sauce", "8Portions Chili Sauce Bottle", "sauces", "The house chili sauce, bottled.", null, 25.0, "sides"),
  dish("honey-mustard", "Honey Mustard", "sauces", "Dipping sauce.", 173, 6.0, "sides"),
  dish("blue-cheese-sauce", "Blue Cheese", "sauces", "Dipping sauce.", 161, 6.0, "sides"),
  dish("spicy-sauce", "Spicy Sauce", "sauces", "Dipping sauce.", 220, 6.0, "sides"),
  dish("chili-flakes", "Chili Flakes", "sauces", "Dry topping.", 7, 6.0, "sides"),
  dish("marinara-sauce", "Marinara", "sauces", "Dipping sauce.", 20, 6.0, "sides"),
  dish("bbq-sauce", "BBQ", "sauces", "Dipping sauce.", 70, 6.0, "sides"),
  dish("chili-lime-sauce", "Chili Lime", "sauces", "Dipping sauce.", 88, 6.0, "sides"),
  dish("ranch-sauce", "Ranch", "sauces", "Dipping sauce.", 189, 6.0, "sides"),
  dish("chipotle-sauce", "Chipotle", "sauces", "Dipping sauce.", 189, 6.0, "sides"),
  dish("spicy-honey", "Spicy Honey", "sauces", "Dipping sauce.", null, 6.0, "sides"),
  dish("pesto-sauce", "Pesto", "sauces", "Dipping sauce.", null, 6.0, "sides"),
];

function pizzaItems() {
  return MENU_ITEMS.filter((i) => i.category === "pizza");
}

// Real product photos, downloaded from 8 Portions' own ordering platform CDN
// (the same images shown on their live menu). Two sauces (Spicy Honey, Pesto)
// have no photo on the source site, so they're left without an `image` field
// and fall back to the category icon.
const MENU_ITEM_IMAGES = {
  "naimi-lamb-meat": "img/menu/naimi-lamb-meat.webp",
  "isfahani": "img/menu/isfahani.webp",
  "chicken-shish-tawook": "img/menu/chicken-shish-tawook.webp",
  "roma": "img/menu/roma.webp",
  "vegetables": "img/menu/vegetables.webp",
  "pepperoni": "img/menu/pepperoni.webp",
  "eggplant-pine-nuts": "img/menu/eggplant-pine-nuts.webp",
  "goat-cheese": "img/menu/goat-cheese.webp",
  "margarita": "img/menu/margarita.webp",
  "mushroom-pizza": "img/menu/mushroom-pizza.webp",
  "truffle": "img/menu/truffle.webp",
  "south-african": "img/menu/south-african.webp",
  "alfredo-chicken": "img/menu/alfredo-chicken.webp",
  "butter-chicken": "img/menu/butter-chicken.webp",
  "mexican-chicken": "img/menu/mexican-chicken.webp",
  "oats-soup": "img/menu/oats-soup.webp",
  "burrata-cheese-salad": "img/menu/burrata-cheese-salad.webp",
  "quinoa-salad": "img/menu/quinoa-salad.webp",
  "arancini": "img/menu/arancini.webp",
  "dolma-risotto": "img/menu/dolma-risotto.webp",
  "chicken-fillets": "img/menu/chicken-fillets.webp",
  "chili-lime-chicken-wings": "img/menu/chili-lime-chicken-wings.webp",
  "chipotle-chicken-wings": "img/menu/chipotle-chicken-wings.webp",
  "bbq-chicken-wings": "img/menu/bbq-chicken-wings.webp",
  "french-fries": "img/menu/french-fries.webp",
  "baked-bechamel-pasta": "img/menu/baked-bechamel-pasta.webp",
  "pink-pasta": "img/menu/pink-pasta.webp",
  "truffle-pasta": "img/menu/truffle-pasta.webp",
  "specialty-lasagna": "img/menu/specialty-lasagna.webp",
  "lemon-risotto-shrimp": "img/menu/lemon-risotto-shrimp.webp",
  "tiramisu": "img/menu/tiramisu.webp",
  "rosemary-pineapple-mix": "img/menu/rosemary-pineapple-mix.webp",
  "peach-habaq": "img/menu/peach-habaq.webp",
  "passion-ginger-ale": "img/menu/passion-ginger-ale.webp",
  "fresh-orange-juice": "img/menu/fresh-orange-juice.webp",
  "water-pellegrino": "img/menu/water-pellegrino.webp",
  "water": "img/menu/water.webp",
  "soft-drinks": "img/menu/soft-drinks.webp",
  "basil-lemonade": "img/menu/basil-lemonade.webp",
  "tabasco-chili-oil": "img/menu/tabasco-chili-oil.webp",
  "8portions-chili-sauce": "img/menu/8portions-chili-sauce.webp",
  "honey-mustard": "img/menu/honey-mustard.webp",
  "blue-cheese-sauce": "img/menu/blue-cheese-sauce.webp",
  "spicy-sauce": "img/menu/spicy-sauce.webp",
  "chili-flakes": "img/menu/chili-flakes.webp",
  "marinara-sauce": "img/menu/marinara-sauce.webp",
  "bbq-sauce": "img/menu/bbq-sauce.webp",
  "chili-lime-sauce": "img/menu/chili-lime-sauce.webp",
  "ranch-sauce": "img/menu/ranch-sauce.webp",
  "chipotle-sauce": "img/menu/chipotle-sauce.webp",
};

MENU_ITEMS.forEach((item) => {
  if (MENU_ITEM_IMAGES[item.id]) item.image = MENU_ITEM_IMAGES[item.id];
});
