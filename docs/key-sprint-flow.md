# Key sprint: flow of the core loop

Game: speed multiplier obby (design: `roblox-vault-games/games/2026-11-key-sprint/index.md`, a draft that nobody approved). This file is the diagram that precedes the code. Decisions and alternatives: [ADR 0020](adr/0020-key-sprint-server-authoritative-loop.md).

## Rule of the game

The client sends INTENT only. The server owns the multiplier, the walk speed, the stage progress, the coins and every price. A client that sends a bigger number than the server allows gets the server's number.

## Press, run, bank, upgrade

```mermaid
sequenceDiagram
  participant C as Client (UI, key input)
  participant Z as Zap layer (generated)
  participant H as Server handlers (Main.server)
  participant CH as ChargeMeter (pure)
  participant RS as StageRuns (pure)
  participant PD as PlayerData (profile)
  C->>Z: PressBatch(presses: u8) every ~0.25 s
  Z->>H: decoded, typed
  H->>H: batch RateLimiter (remote spam)
  H->>CH: press(userId, presses)
  CH->>CH: Validation.integerInRange, press RateLimiter (cost = presses)
  CH->>CH: multiplier = min(cap, 1 + charge) after decay
  CH-->>H: multiplier (server value)
  H->>H: Humanoid.WalkSpeed = 16 x multiplier
  H-->>C: MultiplierChanged(multiplier, cap) at most 4/s
  C->>Z: Finish(stage: u8) on touching the finish line
  Z->>H: decoded
  H->>RS: finish(userId, stage, cap)
  alt stage is not the active run, or elapsed < minimum plausible time
    RS-->>H: rejected (typed reason), nothing changes
  else accepted
    RS-->>H: reward, nextStage
    H->>PD: coins += reward, highestStage = max(...)
    H-->>C: CoinsChanged, ProgressChanged
  end
  C->>Z: BuyCap()
  Z->>H: decoded
  H->>PD: CapUpgrades.buy(data): price derived on the server
  H-->>C: ProgressChanged, CoinsChanged
```

## Funnel in the first 60 seconds

```mermaid
flowchart TD
  J[PlayerAdded, profile loaded] --> S[session_start]
  S --> N{highestStage = 0 ?}
  N -- yes --> T[tutorial_start, key prompt shown]
  N -- no --> W[returning player: no tutorial events]
  T --> P[first accepted PressBatch]
  P --> F[first_action]
  F --> R[run stage 1]
  R --> D[Finish stage 1 accepted: highestStage 0 to 1]
  D --> TC[tutorial_complete, stage 2 gate opens]
```

Each event is sent once per session (`Funnel` remembers what it sent).

## Purchases

```mermaid
flowchart TD
  P1[Pass Faster charge] --> O[ownsPass at join and on purchase finished]
  O --> CR[ChargeMeter charge per press x 1.5, still clipped by the player cap]
  P2[Pass Trail] --> TR[cosmetic flag only]
  D1[Product SkipStage] --> RG[ProductGrants: highestStage + 1, clamped to the last stage]
  D2[Product Coins100] --> RC[ProductGrants: coins, existing grant]
  RG --> L[Monetization.processReceipt: record, confirm save, then PurchaseGranted - ADR 0016]
  RC --> L
```

## Stage layout

Stages are DATA (`StageSpecs`): a list of segments (platform, gap, mover). `StageLayout` is a pure function from a spec to boxes in stage space; `StageBuilder` (engine adapter, no logic) turns the boxes into Parts at runtime. The world is not built by hand in Studio.
