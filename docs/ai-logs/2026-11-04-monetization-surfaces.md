# 2026-11-04 Monetization surfaces

Issues: #31 (subscriptions), #32 (rewarded ads), #33 (private servers). Added at the orchestrator's request in the same PR: Roblox Plus sign-up prompt, in-game Robux transfers and runtime prices.

## Decisions

- One pure feature per surface under `src/shared/features/`, one port each under `src/shared/ports/`, one engine adapter each under `src/server/adapters/`, wired only in `Main.server` (ADR 0022 on the `docs/game-systems-adr` branch, [ADR 0023](../adr/0023-plus-prompt-robux-transfers-and-runtime-prices.md)).
- Four intent-only remotes (`RequestRewardedAd`, `RequestPlusPrompt`, `RequestRobuxTransfer`, `RequestPrivateServerSetting`) in `net/schema.zap` and `PerfBudget`.
- Prices are never literals; `privateServers.expectedMonthlyPrice` is the only price-like number and is checklist-only.

## Verified against the docs (creator-docs, 2026-11-04)

`UserSubscriptionStatusChanged` fires only after the purchase modal closes (so the poll exists); `GetUserSubscriptionStatusAsync` returns `IsSubscribed`; `ShowRewardedVideoAdAsync` is server-only and its result must not grant the reward; `GetAdAvailabilityNowAsync` is client-only; `PromptRobuxTransferAsync` is server-only with amounts 10 to 500; receipt types `RobuxTransferSender` and `RobuxTransferReceiver`; `PromptRobloxSubscriptionPurchase`, `Player.HasRobloxSubscription`; `DataModel.PrivateServerId` and `PrivateServerOwnerId`; `TeleportInitFailed(player, result, message, placeId, options)`; `GetProductInfoAsync` returns `PriceInRobux`, `UserBasePriceInRobux` and `PriceDiscountDetails`.

## Not verified

- Row field names of `GetDeveloperProductsAsync` (the adapter reads `ProductId` and `PriceInRobux` and fails loudly when absent).
- Whether an API exposes age eligibility for Robux transfers (the platform enforces it inside the prompt; the adapter reports a refusal as a typed error).
- Behavior against the real engine: no engine tests exist yet (ADR 0005).
