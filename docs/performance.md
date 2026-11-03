# Performance budget and manual procedure

Decision and alternatives: [ADR 0019](adr/0019-performance-budget.md). The numbers live in `src/shared/perf/PerfBudget.luau`; this page explains where each comes from and how to check a build by hand.

## Budgets and their sources

| Budget | Value | Source |
|---|---|---|
| Server frame (Heartbeat) | below 16 ms of CPU time per frame to hold 60; frame budget 16.67 ms | sourced: https://create.roblox.com/docs/production/analytics/performance (Server CPU time), https://create.roblox.com/docs/performance-optimization/identify (Server compute) |
| Server Heartbeat cap | 60 FPS | sourced: https://create.roblox.com/docs/performance-optimization/identify |
| Server memory | stay below 50 % of total; total = 6.25 GiB + 100 MiB x largest number of connected players | sourced: https://create.roblox.com/docs/performance-optimization/identify (Server memory). The analytics page also suggests a 3 GB guideline: https://create.roblox.com/docs/production/analytics/performance |
| RemoteEvent throttle (client to server) | about 500 requests per second per client, shared by all RemoteEvents (and UnreliableRemoteEvents) | sourced: https://create.roblox.com/docs/reference/engine/classes/RemoteEvent (Throttling) |
| UnreliableRemoteEvent payload | messages over 1,000 bytes may be dropped | sourced: https://create.roblox.com/docs/scripting/events/remote |
| Per-player network budget (`DataSendKbps` / `DataReceiveKbps`) | 2 KB/s receive, 4 KB/s send per player (runtime); 512 B/s client to server and 2048 B/s server to client in the static calculator; 256 B/s per remote | **budget chosen, not sourced**: the docs describe the Stats properties (roughly kilobytes per second, https://create.roblox.com/docs/reference/engine/classes/Stats) but publish no recommended figure |
| Per-message overhead | 8 bytes | **budget chosen, not sourced** |
| Window of the probe | 10 samples, 1 per second | chosen by this template |

Tools and attributes (no number to set):

- MicroProfiler: Ctrl Alt F6; profile a block with `debug.profilebegin` / `debug.profileend`. https://create.roblox.com/docs/performance-optimization/microprofiler
- Script Profiler (Developer Console): records CPU time per function and marks natively compiled functions with `<native>`. https://create.roblox.com/docs/studio/optimization/scriptprofiler
- `--!native` / `@native`: use for compute-heavy functions only; costs compile time, memory and counts toward a total native-code limit; measure with the Script Profiler before and after. https://create.roblox.com/docs/luau/native-code-gen. The template does not use `--!native` anywhere: no measurement justifies it.
- Parallel Luau (Actors): for expensive work that does not touch the data model; use several Actors; long computations still block. https://create.roblox.com/docs/scripting/multithreading. Not used by the template.

## Static check (CI, no Studio)

```powershell
lune run scripts/perf-budget      # prints bytes/s per remote and per direction; exit 1 over budget
```

Acceptance: output ends with `perf-budget: OK`. If it fails: read the `FAIL` line. Over budget: lower the remote's rate limit or shrink its payload in `net/schema.zap`, or raise the budget in `PerfBudget.luau` with a reason in the PR. "No rate declared": add the remote to `clientRemotes` (with the limiter you build in `Main.server`) or `serverRemotes`. "Unbounded type": give the field a length or range in the schema. Recorded: CI job `test` log.

## Manual procedure in Studio (anyone, from zero)

Prerequisites: Roblox Studio installed, the repo set up per README, a dev place (never production). Record results in the PR description under "Performance" and in the ai-log of the session.

1. **Start a local server with 2 players.** `rojo serve`, connect from Studio, then Test > Clients and Servers > 2 Players > Start. Acceptance: one Server window and two Client windows open, no red errors in Output. If not: fix the script errors first; the numbers mean nothing otherwise.
2. **Enable the probe (optional).** Set `perfProbeEnabled = true` in `src/shared/Config.luau` locally (do not commit it). Acceptance: after about 10 s the server Output shows no `[PerfProbe]` warning in an idle game. If a warning appears, note the metric and go to step 3 or 5.
3. **Server Heartbeat.** In the Server window press F9, tab Server Jobs, expand Heartbeat. Acceptance: Steps Per Sec reads 60 (or within 1 of it) while you play for 60 s. If lower: go to step 4.
4. **Server MicroProfiler.** In the Server window press Ctrl Alt F6, then use the pause control shown in the MicroProfiler to freeze a slow frame (see its docs page above). Acceptance: no frame bar longer than 16.67 ms during normal play; spikes over it are listed with their label. If a spike: find the label (add `debug.profilebegin("name")` around suspect code), fix it, repeat step 3. Use the Developer Console Script Profiler to rank functions by CPU time.
5. **Network.** In a Client window press Ctrl Alt F7 (Performance Stats) and read the data sent and received. In the Server window, `Stats.DataSendKbps` / `DataReceiveKbps` are what the probe warns on. Acceptance: with 2 players and normal play, send stays at or below 8 KB/s and receive at or below 4 KB/s (the per-player budgets times two). If higher: find the remote or replicated property responsible (the Debug Stats overlays, Shift Ctrl F1 to F5, include network traffic) and rate-limit or shrink it.
6. **Memory.** F9, tab Memory. Acceptance: total server memory below 50 % of 6.25 GiB + 100 MiB x players (3,300 MiB for 2 players) and not growing across a 10-minute idle run. If it grows: the categories with the most growth point to scripts, physics or rendering (https://create.roblox.com/docs/performance-optimization/improve).
7. **Record.** Write the numbers (Heartbeat steps per second, worst frame in ms, send/receive KB/s, memory) in the PR. Acceptance: all four are present. Do not paste guessed values; write "not measured" instead.
8. **Revert** `perfProbeEnabled` to `false`. Acceptance: `git diff src/shared/Config.luau` is empty.

Live games: the Performance Dashboard (https://create.roblox.com/docs/production/analytics/performance) shows server CPU time, frame rate and memory; read it by hand in Creator Hub. This template does not call any Roblox data API.
