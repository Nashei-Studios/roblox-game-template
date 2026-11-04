# 2026-11-04 Engagement modules

- Scope: issues #27 (time rewards), #28 (promo codes), #29 (notifications), #30 (sound), one branch `feature/engagement-modules`.
- Read first: ADR 0022 (design), ADRs 0009, 0010, 0012, 0015, 0016, 0017; the vault research on the free RBLX Essentials packs was used as a behaviour reference only (Codes cooldown that doubles after repeated failures); no code was copied.
- Decisions: recorded in ADR 0025 (state in the profile with one v3 to v4 migration, rewards through `ProductGrants`, server clock only, client logic pure behind `ToastRenderer` and `SoundEngine`, toast kinds mirrored in a Zap enum).
- Verification: stylua, selene, analyze, `lune run scripts/test`, `scripts/coverage.ps1`, `scripts/perf-budget`, `rojo build` and `generate-remotes` (no diff). Numbers are in the PR.
- Not verified: the two client presenters against the real engine (Device Emulator on a small phone, a tablet and 1080p is still pending), and the sound ids, which stay `nil`.
- Coordination: another worker builds monetization surfaces; shared files (Config, schema.zap, PerfBudget, Main.server, PlayerData and its migrations) were edited in one grouped section each.
