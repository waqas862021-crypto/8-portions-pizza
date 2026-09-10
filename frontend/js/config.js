// Site-wide constants. Names, Instagram handle, and currency are verified
// against 8 Portions' own official ordering platform (branch/1, Dhahran)
// and Instagram. Contact phone/WhatsApp are still TBD — not published
// anywhere we could verify; the client's own ordering platform currently
// has online ordering switched off too.
const SITE = {
  brandName: "8 Portions",
  brandTagline: "Speciality Pizza",
  brandNameAr: "ايت بورشنز",
  tagline: "Neapolitan/NY-style pizza, made for sharing.",
  instagramHandle: "@8portionspizza",
  instagramUrl: "https://www.instagram.com/8portionspizza/",
  // TBD: real WhatsApp Business number in international format, no symbols
  // (e.g. "9665XXXXXXXX"). Leave empty to fall back to a "call us" message.
  whatsappNumber: "",
  // TBD: primary contact number and email — not published on their official
  // channels yet.
  phone: "+000 0000 0000",
  email: "hello@example.com",
  currency: "SAR",
  // Third-party delivery apps 8 Portions is shown promoting on Instagram —
  // these are external ordering channels, not part of this site's own cart.
  deliveryPartners: ["Jahez", "Keeta", "HungerStation", "Ninja Food"],
};

// Builds a wa.me link with a pre-filled message. Falls back to null when no
// WhatsApp number is configured so callers can show a phone-call fallback.
function buildWhatsappLink(message) {
  if (!SITE.whatsappNumber) return null;
  const encoded = encodeURIComponent(message);
  return `https://wa.me/${SITE.whatsappNumber}?text=${encoded}`;
}

function formatPrice(amount) {
  return `${SITE.currency} ${amount.toFixed(2)}`;
}
