# Pixel Pet Café — macOS Menu Bar Idle Game — Design

**Date:** 2026-07-06
**Status:** Approved by Leonard
**Location:** `coding/pixel-pet-cafe/`

## Concept

A cozy pixel-art café run by animal characters, living in the macOS menu bar. The status item shows a tiny animated pet face plus a compact coin counter. Clicking it opens a popover containing an animated SpriteKit café scene and the game UI. The game earns passively while you work and while the Mac sleeps (offline earnings), with light optional interaction (golden tips). Full idle loop in v1: earn → upgrade → hire → unlock recipes → prestige.

## Menu Bar Presence

- **Status item:** 18px pixel pet face (idle animation: blinks, occasional coffee sip) + coin count formatted compactly (`1.2K`, `3.4M`).
- **Left-click:** opens SwiftUI popover, ~360×540pt.
  - Top ~240pt: SpriteKit café scene (pixel art, nearest-neighbor scaling).
  - Below: header with coins + coins/sec, then 4 tabs: **Café** (equipment), **Staff**, **Recipes**, **Renovate** (prestige).
- **Right-click:** context menu — mute sounds, launch at login toggle, quit.

## Game Systems

### Economy
- `coinsPerSec = Σ(staff_i.level × staff_i.baseRate) × Π(equipment multipliers) × Π(recipe bonuses) × (1 + 0.10 × stars)`
- Purchase costs grow geometrically: `cost(level) = baseCost × 1.15^level`.
- Economy ticks on a 1-second timer independent of the scene. Number formatting: K / M / B / T.

### Staff — 6 animal characters
Each has a unique sprite sheet with an idle/work animation, a base income rate, and geometric level costs.

| Character | Role | Note |
|---|---|---|
| Mocha the cat | Barista | Starter, owned at level 1 |
| Biscuit the corgi | Waiter | |
| Poppy the bunny | Pâtissier | |
| Juno the fox | Cashier | |
| Bo the bear | Roaster | |
| Earl the owl | Night shift | Each level extends the offline-earnings cap |

Staff unlock progressively at coin milestones.

### Equipment (Café tab)
Espresso machine, oven, grinder, decor, sound system. Each is a leveled purchase granting an income multiplier; upgrades visibly change the corresponding sprite in the scene.

### Recipes
Unlock automatically at cumulative-coin milestones (e.g., latte art, croissant, matcha, etc.). Each grants a permanent global multiplier for the current run. The newest recipe is shown being served to customers in the scene.

### Golden Tips (light active play)
While the popover is open, every 2–5 minutes (random) a sparkling tip bubble appears in the scene. Clicking it grants a bonus equal to 10 minutes of current income. Never spawns while the popover is closed; no notifications, no pressure.

### Prestige — "Renovate"
- Available past a lifetime-coin threshold. Renovating resets coins, staff levels, equipment, and recipes; grants permanent ⭐ stars (+10% income each), computed as `floor(sqrt(lifetimeCoinsThisRun / threshold))` so deeper runs yield more stars.
- Café decor tier steps up visually with total stars (3 tiers), so prestige progress is visible in the scene.

### Offline Earnings
- On launch and on wake-from-sleep: `elapsed × coinsPerSec`, capped at 8 hours base; Earl the owl's level extends the cap.
- Clock-rollback safe: negative elapsed time earns nothing.
- A "While you were away" toast in the popover shows the haul.

## Architecture

Native Swift, macOS 13+, Xcode project at `coding/pixel-pet-cafe/`.

| Unit | Responsibility |
|---|---|
| `GameState` | Pure `Codable` model: coins, lifetime coins, staff levels, equipment levels, recipes unlocked, stars, last-save timestamp. |
| `EconomyEngine` | Pure functions: rate calc, cost curves, affordability, offline earnings, prestige star formula. No UI imports; fully unit-testable. |
| `CafeScene` (SpriteKit) | Pixel café scene; sprite-sheet animations; golden tip spawning; decor/equipment tier visuals. **Paused entirely when popover closes.** |
| `Persistence` | JSON save in `~/Library/Application Support/PixelPetCafe/`; autosave every 30s, on quit, and on sleep. |
| `StatusItemController` | `NSStatusItem`, animated bar icon, popover lifecycle, right-click menu. |
| SwiftUI views | Header, four tabs, purchase rows, away-toast. |

Performance rule: with the popover closed, the app runs only the 1s economy timer and a slow (~2s) bar-icon frame swap — near-zero CPU.

### Art Pipeline
All pixel art (6 characters, customers, café background, equipment props, decor tiers, bar icon frames) is authored as pixel matrices in a Python script (`tools/generate_sprites.py`) that emits PNG sprite sheets into the asset catalog. Art is deterministic, editable, and regenerable. Rendering uses nearest-neighbor filtering for crisp pixels.

## Error Handling
- Corrupt/missing save → start fresh, back up the corrupt file aside.
- Clock rollback → zero offline earnings, clamp state.
- Save writes are atomic (write temp, rename).

## Testing
- Unit tests (XCTest) for: economy rate math, cost curves, prestige star formula, offline earnings (normal, capped, Earl-extended, clock rollback), save/load round-trip, number formatting.
- Manual/visual verification for scene animation, popover behavior, and CPU usage when closed.

## Out of Scope (v1)
- Sounds beyond simple SFX toggle stub, achievements, Game Center, multiple cafés, seasonal events, in-app purchases (never), iOS port.
