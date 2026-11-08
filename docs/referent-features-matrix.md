# Referent features matrix (living backlog)

Every feature that makes a referent game attractive, across genres, plus the full feature list of the paid Roblox Essentials packs (which the template provides free and open), plus the social-presence features seen in the referents. Each row maps to the template module that covers it. Rows are genre-agnostic: a feature is listed once, with the games that show it. This is the backlog the next "moldes" (template modules) are picked from. Process rule: no game builds a feature of this table by hand if its row says `missing`; it opens or extends the template module first (ecosystem first, [ADR 0028](adr/0028-external-building-blocks-and-wally.md)).

Update rule: when a module lands, change its `Status` and `Module` in the same PR; when a new referent shows a new attraction, add a row. Companion: [ecosystem-map.md](ecosystem-map.md) (external pieces and modules).

## Method and sources

- Mining and clicker family: vault note `research/2026-11-07-referentes-ronda-3.md` (24 gaps, API reads of 2026-11-07 and 08, two gameplay frame sets).
- Essentials: vault notes `research/2026-11-05-ecosistema-base-paridad-essentials.md` (catalog of the 13 products and parity matrix) and `research/essentials-replacements-2026.md`. Section B lists every function those packs promise.
- Three other genres, read on 2026-11-08 through the public Roblox APIs, anonymous, one request per second plus a 1.1 s pause: `apis.roblox.com/search-api/omni-search` (discovery by genre keyword), `games.roblox.com/v1/games` (players, visits, description, update date) and `apis.roblox.com/game-passes/v1/universes/{id}/game-passes` (pass names and list prices).
  - Tower defense: Anime Adventures (about 115k playing), Cameraman Tower Defense (about 55k), Tower Defense Simulator (about 28k).
  - Tycoon, collection and idle: Steal An Egg (about 1.07M playing), My Small Business (about 26k).
  - Fighting and battlegrounds: Jujutsu Shenanigans (about 119k), The Strongest Battlegrounds (about 74k).
- Labels: **seen** = read from an API or a frame; **[inferred]** = deduced from names, descriptions or the controls text, not observed in play. No game was played. Prices are list prices of the API on the read day.
- Licences read with `gh api repos/<owner>/<repo>/license` on 2026-11-08: Questline MIT, RbxUtil MIT, zap MIT, vide MIT, RoQuest Apache-2.0, ProfileStore Apache-2.0 (ecosystem-map), TopbarPlus and NevermoreEngine report `NOASSERTION` (custom: read before reuse). "None usable" means no maintained open piece with a compatible licence was found; the template writes the module. "Platform" means a native Roblox service, no third-party code.

Status: `have` = a module covers it end to end; `partial` = a module covers a slice (the gap is named); `missing` = nothing yet. Priority: P0 blocks retention or income of most games; P1 next wave; P2 later or genre-specific.

## A. Attractions seen in referents

| ID | Attraction (seen in) | Template module | Status | Open-source reference (licence) | Priority |
|---|---|---|---|---|---|
| F01 | First reward in under 2 s and a guided first minute (+1 Mining Power ADR 0038; Crypto Empire pays in about 1 min) | `join` (fast entry), `progress` | partial | none usable; guided steps come from `quests` chains (F08) | P0 |
| F02 | Titles and milestones by counter, no spam on join | `progress` | have | none needed | P2 |
| F03 | Daily streak reward with grace | `timerewards` | have | none needed | P2 |
| F04 | Session gifts by time played (Tap Simulator, mining family) | `timerewards` | have | none needed | P2 |
| F05 | Redeem codes (almost every top game) | `codes` | have | none needed | P2 |
| F06 | Offline earnings with a visible estimate (Crypto Empire, My Small Business) | none (lives in one game) | missing | none usable | P1 |
| F07 | Rewarded video ads (clickers) | `rewardedads` | have | none needed | P2 |
| F08 | Daily and weekly quests with chains and generic counters (Rock In My Lawn "new job every few minutes") | `quests` | have | FarFromLittle/Questline (MIT, design read only), prooheckcp/RoQuest (Apache-2.0, not read) | P0 |
| F09 | NPC job giver with dialogue portrait and floor arrows (Rock In My Lawn) | none (needs `quests` + UI) | missing | kit GUI trees from the kit manifest; no code piece | P2 |
| F10 | Shared objective with a common progress bar and a reward for everyone (Rock In My Lawn, up to 6 friends) | none (one game has it as "Shared Vein") | missing | none usable | P0 |
| F11 | Friend boost by friends in the server (Crypto Empire "Friends Bonus") | `social` | have | none needed | P2 |
| F12 | Invite a friend with a reward | `social` | have | platform: SocialService | P2 |
| F13 | Group or community reward with a real perk, not only coins (Mine a Mountain "+1 Digging Luck", Tower Defense Simulator "+$100 starting cash") | `community-reward` (`CommunityReward`, `CommunityPerk`), `social` | have | none usable | P0 |
| F14 | Free private servers announced in the description (VERY LUCKY games) | `privateserver` | have | none needed | P1 |
| F15 | Daily boards and avatar podium | `leaderboards` | partial (#50, #51) | platform: OrderedDataStore | P1 |
| F16 | Pets and eggs with weighted hatching (Tap Simulator REBORN, Steal An Egg, Loot To Forge, Dig For Eggs) | none | missing (#24) | none usable (candidates have 0 to 14 stars, mostly unlicensed) | P0 |
| F17 | Mutations and size variants on collectibles (Steal An Egg "sizes, mutations", My Anime Mine "Mutation Luck") | none (part of pets) | missing | none usable | P1 |
| F18 | Roulette or gacha with weighted slots, odds shown (Tap Simulator, Lift Rock; The Strongest Battlegrounds states equal odds) | none | missing (#26) | marchware/Roblox-Spin-Wheel has no licence: not reusable | P1 |
| F19 | Luck multiplier as a stat or pass (Super Luck 799, Super Drop Luck 1,199, Mutation Luck 99) | none (a Luck stat read by pets and roulette) | missing | none usable | P1 |
| F20 | Long ladder of multiplier passes x2 to x64 with a high ceiling (Lift Rock 17 passes from 9, Money Per Click 36 passes) | `monetization`, `pricing` | partial (ladder in `offers`; wiring per game) | none usable | P0 |
| F21 | Cheap entry pass or starter pack, 9 to 59 (Starter Pack 19 and 59, Mine a Mountain Starter 9) | `monetization` | partial (rail timing in `offers`) | none usable | P1 |
| F22 | Offer rail: rotating offers with a price strip (Crypto Empire shop, Tower Defense Simulator limited-time units) | `offers` | have | none usable | P1 |
| F23 | Coin packs as developer products | `monetization`, `ProductGrants` | have | none needed | P2 |
| F24 | Robux for restock, skip or boost (Crypto Empire "Restock Now") | `robuxtransfers`, `plus` | partial | none needed | P2 |
| F25 | Subscriptions and VIP with benefits (VIP 199 to 375 in most games) | `subscriptions`, `monetization` | partial | none needed | P1 |
| F26 | Cosmetic shop: trails, auras, platforms, outfits, kill sounds, emote slots, unit display (Money Per Click trails 79 to 1,199; Jujutsu Shenanigans outfits and kill sound; Anime Adventures display passes) | none | missing | none usable | P1 |
| F27 | Capacity and slot upgrades as passes (Unit Storage 99, +3 Pet Equip 749, Extra Emote Slots 99, More Build Saves 125) | none | missing | none usable | P1 |
| F28 | Auto features as passes (Auto Collect, Auto Sell, Auto Arrange, Auto Tap) | none (game-level) | missing | none usable | P1 |
| F29 | Skip-animation pass (Skip Forge Animation 29, Skip Card Animations 99) | none | missing | none usable | P2 |
| F30 | Season pass (seasonal updates in Venom Evolution, Tower Defense Simulator limited-time towers) | none | missing (#63) | none usable | P1 |
| F31 | Event calendar and timed rotation: new zone every hour (Mine a Mountain), hourly shop restock (Crypto Empire) | `liveops` | have | none usable | P0 |
| F32 | Server and global events over cross-server messaging (seasonal Halloween updates) | none | missing (#55) | platform: MessagingService | P1 |
| F33 | Limited-time passes and units (Tower Defense Simulator "LIMITED TIME") | needs F20 and F31 | missing | none usable | P1 |
| F34 | Market price board with a good-price selling window (Crypto Empire "Next prices in 0:14") | none | missing | none usable | P2 |
| F35 | Backpack with a cap and a dump point (Rock In My Lawn `0/20`, Mine a Mountain carry) | none | missing | none usable | P1 |
| F36 | Co-op on one objective up to 6 (Rock In My Lawn, My Small Business "invite friends to help") | `social` (boost only) | partial | none usable | P1 |
| F37 | Stealing from or raiding other players (Steal An Egg) | none | missing | none usable; needs its own risk review | P2 |
| F38 | Experience notifications opt-in (return reason) | none | missing (#49) | platform: ExperienceNotificationService | P1 |
| F39 | Hit effect with one reused emitter | `hitfx` | have | none needed | P2 |
| F40 | Tap anywhere input router | `input` | have | none needed | P2 |
| F41 | Standard funnel analytics catalog | `analytics` | partial (#58) | none needed | P1 |
| F42 | Experiments and A/B per player | `flags` | partial (#57) | platform: ConfigService | P2 |
| F43 | Admin console, bans, soft shutdown, privacy erasure | none | missing (#59, #60, #61) | evaera/Cmdr (MIT, per ecosystem-map); CheeseGodRoblox/SoftShutdown is GPL-3.0, do not copy | P1 |
| F44 | Store page kit: name pattern, numbered description with emoji, thumbnail with avatar and big number (VERY LUCKY, 10K Steps) | skills `roblox-naming`, `roblox-thumbnails` | partial | none needed | P0 |
| F45 | Match start from a platform or lobby queue (Cameraman Tower Defense, Anime Adventures) | none | missing | none usable | P2 |
| F46 | Round and wave framework with win and loss (tower defense) | none | missing | none usable | P2 |
| F47 | Ranked mode and rating (Huss Valley "RANKED") | none | missing | none usable | P2 |
| F48 | Unit or hero loadout and summon with duplicates (Anime Adventures) | none (shares weighted pick with pets and roulette) | missing | none usable | P2 |
| F49 | Hire workers and automation (My Small Business) | none (game-level) | missing | none usable | P2 |
| F50 | Persistence that survives rejoin and server shutdown | `playerdata` | have | MadStudioRoblox/ProfileStore (Apache-2.0) | P2 |

## B. Roblox Essentials, full function list (provided free and open)

Source: the 13 products and the parity matrix of the vault. The paid packs are not copied (vault decision 0022); each function is covered by our own module or is a gap. "Reference" for gaps is design reference only unless a licence is stated.

| ID | Essentials function | Template module | Status | Open-source reference (licence) | Priority |
|---|---|---|---|---|---|
| E01 | Single grouped save, on timer, on leave and on shutdown | `playerdata` | have | ProfileStore (Apache-2.0) | P2 |
| E02 | Gamepasses and developer products with receipt grant after save | `monetization` | have | platform: MarketplaceService | P2 |
| E03 | FreeMode (grant products without Robux, Studio only) and Wipe Studio Data | none | missing | none needed; small, write in `monetization` | P2 |
| E04 | Codes: distinct reply for unknown, used, expired; per-code expiry; one redeem per player; any reward | `codes` | have | none needed | P2 |
| E05 | Toasts, stackable templates | `notifications` | have | none needed | P2 |
| E06 | Top banner and coloured chat lines | none | missing | platform: TextChatService | P1 |
| E07 | Triggers: friend joined, joins and leaves, rotating announcements, purchase announced in chat | none | missing | platform: TextChatService, Players | P1 |
| E08 | Sound: mixer, separate music and SFX volume, toggles, levelled effects | `sound` | have | Kenney audio (CC0) | P2 |
| E09 | Music player with named tracks, time, skip, mute, hide | none | missing (#62) | Kenney (CC0) for tracks | P1 |
| E10 | World speakers with ProximityPrompt | none | missing (#62) | platform: ProximityPrompt | P2 |
| E11 | UI: Shop, Settings menus | `ui` | have | none needed | P2 |
| E12 | UI: Teleport, Changelogs menus | `ui` | missing (#53) | none usable | P2 |
| E13 | UI: Pets, Spin, Rebirth, Upgrades, Index menus | `ui` (card grid only) | missing | none usable | P1 |
| E14 | UI: Trade, Trade Inventory, Trade Request, Gift, Gift Received menus | none | missing (#54, #65) | none usable | P2 |
| E15 | Tooltip per button, open and close animation, hover and press sounds | `ui` | partial | none needed | P2 |
| E16 | Plain and Studded themes by tokens | `ui` tokens | have | free Studded UI trees as visual reference (kit manifest) | P2 |
| E17 | Pets: 6 eggs for cash or Robux, odds shown, opening animation | none | missing (#24) | none usable | P0 |
| E18 | Pets: Triple Hatch, Auto Hatch, Extra Pet Space passes | none | missing (#24) | none usable | P1 |
| E19 | Pets: 28 pets in 5 rarities, merge 3 equal, Equip Best, Merge All | none | missing (#24) | none usable | P0 |
| E20 | Pets: index with found and hidden, follow modes (Float, Ground, Follow), rare-hatch chat announcement, pets as prizes | none | missing (#24) | none usable | P1 |
| E21 | Leaderboards: global boards from many stats, daily and weekly cycles | `leaderboards` | have | platform: OrderedDataStore | P2 |
| E22 | Leaderboards: podium of 3 with avatars, board designs, refresh timer | `leaderboards` | partial (#50) | platform: CreateHumanoidModelFromUserId | P1 |
| E23 | Leaderboards: Tab list from leaderstats, raw, comma and abbreviated number formats | `leaderboards` (`Format`) | have | none needed | P2 |
| E24 | Leaderboards: monthly reset | `leaderboards` | partial | none needed | P2 |
| E25 | Roulette: 2 to 12 weighted slots, server-picked prize paid at stop | none | missing (#26) | none usable | P1 |
| E26 | Roulette: free spin on a timer, spin packs of 1, 3, 10, "Spins left" counter, prize any stat or pet | none | missing (#26) | none usable | P1 |
| E27 | Time rewards: 7-day streak with its own reward per day, 24 h or UTC clock | `timerewards` | have | none needed | P2 |
| E28 | Time rewards: a missed day pauses the streak (ours resets after a grace window; choose one) | `timerewards` | partial | none needed | P2 |
| E29 | Time rewards: 6 gifts by minutes played, HUD badge when a reward is ready | `timerewards` | partial (no badge) | none needed | P2 |
| E30 | Datastore pack plugin installer and theme/diagnostic plugin | Rojo and `scripts/new-game.ps1` | have (different shape) | Rojo (MPL-2.0) | P2 |

## C. Social presence seen in the referents

The common thread: players are visible to each other, the world has a place where everybody gathers, and the game gives a reason to be in the same server. Controls text of the fighting games and the descriptions of the group games are the evidence; none was played.

| ID | Social-presence feature (seen in) | Template module | Status | Open-source reference (licence) | Priority |
|---|---|---|---|---|---|
| S01 | Central lobby or hub where every system is reachable and other players are seen (Tower Defense Simulator and Anime Adventures lobbies, Steal An Egg base area) [inferred] | `hub` (`HubLayout`, `HubRegistry`) | partial (layout, slots and cap are code; the place itself is built per game) | none usable; ADR 0039 | P0 |
| S02 | Character locomotion states: walk, run (Double Tap W in The Strongest Battlegrounds, W+W sprint in Jujutsu Shenanigans), dash, block | `locomotion` (`LocomotionMachine`, `LocomotionServer`) | partial (sprint and speeds are code; dash and block are not) | platform: default Animate script and `Humanoid` states; NevermoreEngine (custom licence) has movement modules, read first | P1 |
| S03 | Equip and unequip the tool or weapon with its animation (pickaxe, drill, shovel in the mining family; battleground moves) | `locomotion` (`LocomotionServer` equip, swing gate) | partial (the swing effect is the game; animations are config) | platform: `Tool`, `Humanoid:EquipTool`; animation via `animate-roblox-characters` skill | P1 |
| S04 | Emote wheel and extra emote slots (The Strongest Battlegrounds "B - emote wheel", Extra Emote Slots 99) | `hub` (`HubEmotes`: allow-list and cooldown only) | partial (no wheel UI, no animation) | platform: Emotes API; slots tie to F27 | P2 |
| S05 | Shared spaces that make more players better: shared base area, team objective, co-op bar (Rock In My Lawn, My Small Business, Steal An Egg shared server) | `social` (boost only) | partial | none usable; ties to F10 and F36 | P0 |
| S06 | Server-wide visibility of progress: nameplates with rank or title above the head, Tab list stats | `progress` (titles), `leaderboards` (leaderstats) | partial | platform: BillboardGui, leaderstats | P1 |
| S07 | Community hooks in the description: group join, like and favourite, Discord or socials, update version log (Tower Defense Simulator "Join the group for +$100", Mine a Mountain, VERY LUCKY "Join our Community Server") | `community-reward` + skills `roblox-naming` | partial | none needed | P0 |
| S08 | In-game events with a visible countdown that gather everybody (Halloween updates, hourly mountain) | `liveops` | partial (clock and windows; announcements per game) | none usable | P0 |
| S09 | Friends joining each other, invite prompt, join-by-friend | `social` | have | platform: SocialService | P2 |
| S10 | Chat presence: announcements of rare drops and joins in chat | none | missing | platform: TextChatService | P1 |
| S11 | Spectate or follow a friend, party and group queue (battlegrounds, tower defense matches) | none | missing | none usable | P2 |
| S12 | A clip-worthy moment with timed hype and a skippable share prompt (Roblox Moments clips, 30 s, captured by the player; win-condition criteria 2, 4, 8) | `clipmoment` (`MomentDirector`) | partial (plan, limits and opt-outs are code; hooks and the real capture are per game) | platform: CaptureService `PromptShareCapture`; ADR 0042 | P0 |

## How to read the gaps

- The two P0 mechanisms that appear in every genre we read are **a long pass ladder with a cheap entry and a high ceiling** (F20, F21, F33) and **a reason to return on a clock** (F31, F08, F03, S08). ECO-1 builds both foundations first.
- The collection engine (F16, F17, F18, F19, F48, E17 to E26) is one family: weighted pick plus luck stat plus slots. Design it once, as the `pets` ADR, before three modules grow three pickers.
- The presence layer (S01 to S05) is mostly place construction and platform Humanoid behaviour, not pure Luau: the template ships its contract (README and anchors), the Lune-testable part is small.
- Everything that grants value goes through the server and through the receipt or save-confirmed path (ADR 0016); every price and every odds table is config.

## Next steps

1. ECO-1 modules are open as PRs #80, #83, #85, #92 (quests, pass ladder with offer rail, community perk, timed rotation). When each merges, set its rows to `have` or `partial` and name the module. Each lands with an ADR, a folder README, an ecosystem-map entry and Lune tests.
2. Design ADR for the shared collection engine (pets, roulette, luck) before any code.
3. Hub contract (S01, PR for #87 done), locomotion and tool equip (S02, S03, PR for #88 done), backpack (F35), shared objective (F10) and offline earnings (F06) are the next genre-agnostic moldes.
