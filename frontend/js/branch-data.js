// REAL branch names, cities and posted hours — transcribed from the
// client's own Instagram "Branches" story highlight on 2026-09-10.
// Street addresses and phone numbers were NOT shown there and are still
// unverified (TBD). The Dhahran branch's Sat–Wed/Thu opening time is shown
// as "11:00 PM" on the source graphic, which is unusual for a lunch/dinner
// pizzeria (their Riyadh branches open at noon) — kept exactly as posted
// rather than silently "corrected"; worth confirming with the client.
const BRANCHES = [
  {
    id: "riyadh-river-walk",
    name: "River Walk",
    city: "Riyadh",
    address: "River Walk — exact street address to be confirmed",
    phone: "+000 0000 0000",
    hours: [
      { days: "Sat – Wed", time: "12:00 PM – 1:00 AM" },
      { days: "Thu", time: "12:00 PM – 2:00 AM" },
      { days: "Fri", time: "1:00 PM – 2:00 AM" },
    ],
    verified: "partial",
  },
  {
    id: "riyadh-park-avenue",
    name: "Park Avenue",
    city: "Riyadh",
    address: "Park Avenue — exact street address to be confirmed",
    phone: "+000 0000 0000",
    hours: [
      { days: "Sat – Wed", time: "12:00 PM – 1:00 AM" },
      { days: "Thu", time: "12:00 PM – 2:00 AM" },
      { days: "Fri", time: "1:00 PM – 2:00 AM" },
    ],
    verified: "partial",
  },
  {
    id: "dhahran-dawan-complex",
    name: "Dawan Complex",
    city: "Dhahran",
    address: "Dawan Complex — exact street address to be confirmed",
    phone: "+000 0000 0000",
    hours: [
      { days: "Sat – Wed", time: "11:00 PM – 1:00 AM" },
      { days: "Thu", time: "11:00 PM – 2:00 AM" },
      { days: "Fri", time: "12:30 PM – 2:00 AM" },
    ],
    verified: "partial",
  },
];

function googleMapsDirectionsUrl(branch) {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`8 Portions Pizza ${branch.name} ${branch.city}`)}`;
}
