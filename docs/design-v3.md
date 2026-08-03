# Pixel Pet Café v3 — Cities, Manager & Casino — Design

**Date:** 2026-07-06 · extends v2. Requested: differentiated staff + manager,
multiple cafés/cities with different vibes, casino minigames with real rules.
Mahjong deferred (full ruleset is its own project).

## 1. Staff specialization + Manager

All staff keep +15% customer rate per level. Role bonuses added (per level):
- **Mocha** (barista): +4% drink prices · **Poppy** (pâtissier): +4% pastry prices
- **Juno** (cashier): +2% all prices · **Bo** (roaster): 2% chance/level (cap 50%)
  a sale consumes no ingredients · **Earl**: +1h offline cap (unchanged)
- **NEW — Marble the raccoon, Manager** (unlock 500K lifetime, base cost 1M):
  auto-restock — keeps every ingredient stocked at ≥ 10×level by buying 25-packs
  with your coins, live and during offline sim. The café never starves while
  you can afford supplies.

## 2. Cities (multi-café)

`GameState.cafes: [CafeState]` — each café: city id, staff, equipment, stock,
menu toggles, cleanliness, progress. Global: coins, lifetime, stars, custom
items, owner/style. **Only the active café operates**; switching is free
(other crews rest). Passthrough accessors keep the engines café-agnostic.

| City | Cost | Vibe | Bonus |
|---|---|---|---|
| Home Town | start | warm cream | — |
| Sakura Town | 250K | pink blossoms | ×1.3 customer rate |
| Neon City | 2M | night + neon | ×1.5 prices |

Backgrounds per city × 3 decor tiers, generated. Renovate resets café contents
but keeps city ownership, custom items, style.

## 3. Casino (unlocks at 50K lifetime coins, tab 🎰)

Pure, unit-tested `CasinoEngine`; bets deduct/settle real game coins (never
touches lifetime counters — gambling doesn't advance prestige/unlocks).

- **Slots**: 3 reels, café symbols (bean, croissant, matcha, berry, honey, star),
  weighted; paytable: 3×⭐ 50×, 3×🍯 20×, three-of-a-kind 10×, pair 2×.
- **Blackjack**: single 52-card deck per hand, hit/stand/double, dealer stands
  on all 17, blackjack pays 3:2, push on tie.
- **Roulette**: European single-zero; bets: straight number 35:1, red/black,
  odd/even, low/high 1:1, dozens 2:1.

UI: casino tab with game picker; cards drawn as styled SwiftUI views; slots use
pixel item icons with spin animation; roulette shows wheel result + history.

## 4. Migration

v2 saves: root café fields wrap into `cafes[0]` (home). All engines/tests keep
compiling via passthrough properties. Casino stats not persisted beyond coins.

## 5. Addendum (same session): ads, reputation, work mode

- **Reputation (0–100, starts 50)**: +0.05 per happy sale, −2 per angry lost
  sale, decays while closed. Customer rate × (0.5 + reputation/100). Shown in
  header (💖). Deep cause-and-effect: no stock → angry customers → reputation
  drops → fewer customers even after restocking, until happy sales rebuild it.
- **Ads campaign (toggle in Café tab)**: while active, drains 25% of your
  income estimate per second from coins, boosts customer rate ×1.8 and slowly
  builds reputation. Auto-stops when you can't afford it.
- **Work Mode (opt-in toggle)**: a global keystroke *counter* (counts key-down
  events only — never reads which keys) measures your typing speed; earning
  rate multiplies up to ×2.5 while you actively type, decaying when you stop.
  Menu bar shows ⚡ and the boost; requires macOS input-monitoring permission,
  gracefully off without it. Idle income stays modest — working literally pays.
