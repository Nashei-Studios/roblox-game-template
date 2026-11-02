# types/

Roblox engine type definitions used by `luau-lsp analyze` (CI and `scripts/analyze.ps1`). This is DATA, not code: never edit it by hand and never run it.

| Field | Value |
|---|---|
| File | `globalTypes.None.d.luau` (public, no extra security level) |
| Source | https://github.com/JohnnyMorganz/luau-lsp/blob/1.70.1/scripts/globalTypes.None.d.luau |
| Pinned to | luau-lsp tag `1.70.1` (commit `0382dc76ca9b73df3c8e7c9cd85a8dd493cbd0ae`), the version pinned in `rokit.toml` |
| Downloaded | 2026-11-02 with `gh api repos/JohnnyMorganz/luau-lsp/contents/scripts/globalTypes.None.d.luau?ref=1.70.1` |
| License | MIT (luau-lsp repository) |

Why vendored: `luau-lsp analyze` does not download definitions, and without them every Roblox global is an unknown global ([ADR 0007](../docs/adr/0007-luau-lsp-analyze-in-ci.md)).

To update: bump `luau-lsp` in `rokit.toml`, download the file at the matching tag, replace it, update the table above, run `pwsh scripts/analyze.ps1`. Excluded from StyLua (`.styluaignore`) and Selene (`selene.toml`).
