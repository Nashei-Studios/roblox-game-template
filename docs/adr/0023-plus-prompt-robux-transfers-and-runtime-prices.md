# ADR 0023: Plus sign-up prompt, Robux transfers and runtime prices

- Status: accepted 2026-11-04, revisable
- Date: 2026-11-04
- Refs: ADR 0022 (game systems as modules behind ports, on the `docs/game-systems-adr` branch, PR #22), ADR 0012 (remote validation), ADR 0016 (confirmed save before grant), vault decision 0024 (full monetization from game 1)
- Sources: creator-docs `production/monetization/roblox-plus.md`, `robux-transfers.md`, `subscriptions.md`, `private-servers.md`, `production/promotion/rewarded-video-ads.md`

## Context

Besides subscriptions, rewarded ads and private servers (ADR 0022), Roblox Plus opens two more revenue surfaces: a sign-up prompt (`MarketplaceService:PromptRobloxSubscriptionPurchase`, 250 Robux per month for the first three months per new subscriber, up to 750) and in-game Robux transfers (`MarketplaceService:PromptRobuxTransferAsync`, the game earns 10 percent of a transfer by a Plus subscriber). Plus subscribers also pay 10 to 20 percent less for every item, and the docs warn that a hardcoded price in the UI shows them the wrong number.

NFRs: no price literal in the repo (a wrong price is a trust and policy problem), nothing interrupts gameplay, minors are protected by the platform, every sale path keeps ADR 0016, and a pack can replace any engine call without changing callers.

## Options considered

| NFR | A. Literal prices in Config, shown in the UI | B. Read prices at runtime through a port (chosen) | C. Do not show prices, rely on the platform prompt |
|---|---|---|---|
| Correct for Plus discounts | no | yes (`PriceInRobux`, `PriceDiscountDetails`) | yes |
| Testable under Lune | yes | yes (fake `PriceLookup`) | n/a |
| Useful for a shop UI | yes | yes | no |
| Enforceable in CI | no | yes: a test fails on any price-like numeric key in `Config.default` | no |
| Cost | wrong UI for subscribers | one extra platform call per quote | none, weaker UX |

For the Plus prompt: **opt-in button (chosen)** versus a server-timed prompt. A timed prompt can fire mid-round; a button cannot. For Robux transfers: **off by default (chosen)** versus on, because the surface moves real money between players and the platform restricts it by age and consent.

## Decision

- `PriceLookup` port (`GetProductInfoAsync`, `GetDeveloperProductsAsync`) and `PriceLabel.format(quote)`: the only way to build a price string. `Config` keeps no display price. The single allowed price-like number is `privateServers.expectedMonthlyPrice`, which feeds the release checklist and is never shown, because code cannot set or read the private server price.
- `PlusPort` and `PlusPrompt`: opens only on a player request (`RequestPlusPrompt`, an enum of Config placements), skips subscribers, enforces a cooldown and a per-session cap from Config. "Became a subscriber" is the server seeing `HasRobloxSubscription` change after we prompted that player, never a client signal. No payout code: the platform credits the bonus.
- `RobuxTransferGateway` and `RobuxTransfers`: `RequestRobuxTransfer` carries receiver and amount only; amount bounds come from Config and must sit in the platform range 10 to 500; `enabled = false` by default. Age and consent are enforced by the platform inside the prompt; a refusal is a typed rejection. Receipts (sender and receiver) are acknowledged when the player is on the server and deferred otherwise. Nothing is granted from a transfer; a future reward must go through the Monetization ledger (ADR 0016).

## Consequences

- Positive: Plus discounts display correctly; the no-literal rule is a failing test; both new surfaces are off or opt-in; adapters are swappable at the composition root.
- Negative: a price quote costs a platform call (callers should cache it per session); `GetDeveloperProductsAsync` rows are not documented field by field, so the adapter reads `ProductId` and `PriceInRobux` and fails loudly when they are missing (unverified, to confirm in Studio); the private server price cannot be shown because no API exposes it.
- Not decided here: whether a transfer-based reward exists (none is built).

## What would change this decision

- Roblox publishes an age-eligibility check for transfers: add it to the gateway so the button hides before the prompt.
- Roblox documents the row shape of `GetDeveloperProductsAsync`: replace the defensive reads with a typed shape.
