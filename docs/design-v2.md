# Pixel Pet Café v2 — Living Café Update — Design

**Date:** 2026-07-06 · extends v1 spec. Requested by Leonard: deeper sim (ingredients,
custom menu, preferences, dirt/closed decay), richer animations, customizable owner,
choosable + reactive menu bar character.

## 1. Sales simulation (replaces pure cps)

Income is now customer-driven. Every tick:

- **Customer rate** (customers/sec) = `0.05 × (1 + 0.15×Σ staff levels) × equipMult × (0.3 + 0.7×cleanliness/100) × (1 + 0.1×stars)`.
- Fractional progress accumulates in `customerProgress`; each whole customer:
  - Picks a servable menu item, weighted by price and **preference** (each customer
    species prefers a category — drinks / pastries / specials — at 2× weight).
  - **Serve**: consume the item's ingredients from stock, earn `price × equipMult ×
    recipeMult... × (1+0.1×stars)`, cleanliness −0.4, sale event emitted.
  - **No servable item** (stock out): lost sale, angry event.
- `coinsPerSecond` becomes an *estimate* (rate × avg servable price) for display.
- Offline earnings run the same sim in bulk: customers served round-robin across
  servable items until stock runs out or time cap hit. **No stock ⇒ no offline income.**

## 2. Ingredients & stock

8 ingredients (beans, milk, flour, sugar, matcha, cocoa, berry, honey) with unit
costs. Bought in packs of 25 or 100 (100-pack 10% cheaper). New **Stock** tab with
levels, low-stock warnings. Header shows a stock warning icon when any enabled menu
item is unservable.

## 3. Menu & custom items

- Built-in menu items unlock at lifetime milestones (espresso shot, latte, croissant,
  matcha latte, hot cocoa, berry tart, honey cake…), each with an ingredient recipe,
  category, and price. Items can be toggled on/off the menu.
- **Custom items**: player composes name + icon + 1–4 ingredients; price is derived
  from ingredient cost (×6 margin) so custom items are always viable. Persisted;
  survive renovation.
- v1 "recipes" multipliers are retired; migration converts nothing (v1 saves keep
  coins/staff/equipment/stars; stock and menu start at defaults).

## 4. Cleanliness, dirt, closed state

- Cleanliness 0–100. Falls with each sale; below thresholds, dirt sprites appear in
  the scene one by one (stains, dirty cups) — **click a dirt spot to clean it**
  (+15 cleanliness, sparkle animation). A "Sweep Up" button in the Café tab cleans all
  for coins. Low cleanliness reduces customer rate (factor above).
- **Closed**: when no menu item is servable for >5 minutes, the café closes — dimmed
  scene, CLOSED sign on the door, cobwebs fade in, no customers. Restocking reopens.

## 5. Scene animation upgrades

Customers now walk in through the door, queue to the counter, show an order bubble
(item icon; red angry bubble if they can't be served), get served, sit at a table
while "eating" (item sprite at table), then leave through the door. Owner character
wanders the floor. Dirt spots accumulate visually. Existing staff/tip animations stay.

## 6. Owner customization + menu bar character

- **Owner**: species (cat, corgi, bunny, fox, bear, owl) × fur palette (brown, cream,
  orange, gray) × accessory (none, bow, cap, glasses, scarf) + editable café name.
  New **Style** tab with live sprite preview. Owner appears in the scene.
- **Menu bar character**: choose the owner or any hired staff. Icon is generated per
  species+palette with 5 frames and becomes **state-reactive**: normal/blink cycle,
  sip, **happy bounce** on golden tip, **sleeping (zzz)** while closed, **alert (!)**
  when stock has run out. Priority: alert > sleep > interaction > idle.

## 7. Model & persistence

`GameState` gains: `stock`, `menuEnabled`, `customItems`, `cleanliness`,
`customerProgress`, `owner: OwnerConfig`, `barCharacter`, `lastSaleAt`,
`dirtSpots: Int`. Backward-compatible decoding (`decodeIfPresent` + defaults) so v1
saves load cleanly. Renovate resets stock/menu-enabled/cleanliness but keeps custom
items, owner, style choices.

## 8. Testing

Unit tests: sim tick math (rate, preference weighting determinism via seeded pick,
stock consumption, lost sales), bulk offline sim (stock exhaustion mid-window),
cleanliness bounds, closed detection, custom item pricing, v1→v2 save migration.
