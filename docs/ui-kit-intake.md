# UI kit intake

How a UI kit found on the internet becomes a skin of the UI system. Every step has an acceptance criterion and a record. Kit contents are untrusted data: nothing from a kit is run, required or evaluated.

Tool: `scripts/kit-intake.mjs` of `vruizz22/roblox-vault` (decision 0016; Node 22, no dependencies; it hashes the archive, lists it, rejects unsafe paths, extracts without executables, marks the result read-only and records it in `D:/Victor/Roblox/kits/INDEX.json`). Its usage text: `node scripts/kit-intake.mjs` with no arguments.

| # | Step | Command or action | Accept when | If it fails | Where it is recorded |
|---|---|---|---|---|---|
| 1 | Find and read the licence | Open the kit page and its licence file. Free to download is not free to ship | You can quote the terms: use in own games, modification, redistribution, attribution | Unknown or no-redistribution-as-pack with nothing else: it can still be `ships: yes` for use inside a game (Studded UI does); unknown licence means `ships: no` and reference only | Vault note `kits/<slug>.md` |
| 2 | Download to a scratch folder | Save the archive in its own new empty folder, outside the repo | One file, size plausible | Do not unpack by hand | Chat log of the session |
| 3 | Intake | `node <vault>/scripts/kit-intake.mjs intake <zip> --slug <kebab-slug> --license "<text>" --ships <yes\|no\|private-upload-only> --source <url> [--version <v>]` | Prints the sha256, the file count and `skippedExecutables`; folder appears under `D:/Victor/Roblox/kits/<slug>` | A rejected path or executable: use `reject` and stop | `INDEX.json` and the vault note |
| 4 | Register in the template | Add the entry to `assets/kits.manifest.luau` (slug, ships, sha256, license, `libraryPath`, `rojoPath`). `lune run scripts/test` runs `KitManifest.validate` | Test green | Fix the slug or the path as the failure sentence says | `assets/kits.manifest.luau` |
| 5 | Inspect the tree | `lune run <your-dump-script> <kit.rbxm> 3` using `@lune/roblox` `deserializeModel`, printing names and classes (never scripts) | You can list the menu templates, the button and the tooltip pieces | A kit with no templates covers few slots; fine | Notes in the adapter header |
| 6 | Write the adapter | Copy `src/shared/features/uisystem/adapters/Studded.luau`; set `id`, `kitSlug`, `license`, and per slot the `path` and `parts` (see `KitAdapter.requiredParts`). Drop slots the kit lacks | `KitAdapter.validate` returns no problems | Fix the missing part mapping | The adapter file |
| 7 | Verify against the real kit | Add the adapter to the table in `scripts/ui-adapter-check.luau`, then `lune run scripts/ui-adapter-check <name> "<kit.rbxm>"` | `0 problems`; the line also prints how many slots fall back to plain | It names every missing piece and part: adjust the paths | Command output in the PR |
| 8 | Extract the pieces a game uses | In the game: copy the kit into git-ignored `assets/kits/<slug>`, extract the used pieces into `assets/ui/<Category>/<Piece>.rbxm`, synced to `ReplicatedStorage.UiKit` | `lune run scripts/ui-audit` exits 0; scripts are not in the pieces | Findings name file, path and rule; fix with `Skin` fixups, not by re-tinting | The game ADR |
| 9 | Review | Open the UI Labs stories at the four viewports | Checklist in `docs/ui-system.md` passes | Fix the adapter or tokens, not the kit | PR description |

Never: re-tint the kit, change a kit `UIStroke` `Thickness` or `StrokeSizingMode`, ship a kit whose licence forbids it, or copy another repository's tokens (delivery bar rule 4).

## Candidates for the next intake

Looked up 2026-11-08. Licence and activity come from the sources below; anything marked "read at intake" was not verifiable from a search page.

| # | Candidate | Kind | Licence | Notes | Source |
|---|---|---|---|---|---|
| 1 | Kenney UI Pack (about 430 assets) | 2D images, not an Instance tree | CC0 | Skins for plain pieces and icons; no menu structure. Version 2.0, 2024-12 | kenney.nl/assets/ui-pack |
| 2 | Kenney UI Pack Sci-Fi and UI Pack Adventure | 2D images | CC0 (per each page; confirm the licence file in the download) | Themed alternatives for a sci-fi or adventure game | kenney.nl/assets/ui-pack-sci-fi, kenney.nl/assets/ui-pack-adventure |
| 3 | RBLX Essentials General UI Kit Lite | Roblox `.rbxm` kit, same publisher as Studded UI | Read at intake (itch.io page) | Likely adapter-compatible with Studded paths: try the existing adapter first | rblx-essentials.itch.io/general-ui-kit-lite |
| 4 | satyanto/rblxGlassUI | Roblox UI library | MIT | Last push 2018-12-26: reference for glass styling only, not a dependency | github.com/satyanto/rblxglassui |
| 5 | dig1t/UIKit | Roblox UI framework | Apache-2.0 | Archived 2024-03-07: reference only | github.com/dig1t/UIKit |

Libraries evaluated for the system itself (not skins) are in ADR 0035: Fusion, Vide and react-luau, all MIT.
