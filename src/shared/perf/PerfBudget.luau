--!strict
--[[
    The performance budget (ADR 0019): ONE config table read by the static calculator
    (`scripts/perf-budget.luau`), the dev probe (`src/server/dev/PerfProbe`) and the composition
    root (the RequestPurchase rate limit). Pure data: no engine services.

    Every number carries its provenance in a trailing comment:
    - "sourced": quoted from Roblox documentation (URLs in docs/performance.md).
    - "chosen, not sourced": a budget picked by this template. The docs publish no figure for it.
      Change it per game; do not read it as a Roblox limit.
]]

export type RemoteLimit = {
    -- Token-bucket burst of the server-side RateLimiter (client -> server remotes).
    capacity: number,
    -- Token-bucket sustained rate (events per second).
    refillPerSecond: number,
}

export type ServerSendRate = {
    -- Worst-case events per second the server sends one player (server -> client remotes).
    maxPerSecond: number,
}

export type Runtime = {
    -- Mean server heartbeat over a sample window, milliseconds.
    maxHeartbeatMs: number,
    -- Fraction of total server memory to stay under.
    maxMemoryFraction: number,
    -- Server memory formula (MiB): base + perPlayer * largest number of connected players.
    memoryBaseMib: number,
    memoryPerPlayerMib: number,
    -- Server-wide Stats.DataSendKbps / DataReceiveKbps allowed per connected player.
    sendKbpsPerPlayer: number,
    receiveKbpsPerPlayer: number,
}

export type Budget = {
    -- Bytes added per remote message on top of the Zap payload.
    perEventOverheadBytes: number,
    -- Worst-case bytes per second, one player, client -> server (all remotes together).
    clientToServerBytesPerSecond: number,
    -- Worst-case bytes per second, one player, server -> client (all remotes together).
    serverToClientBytesPerSecond: number,
    -- Cap for any single remote, either direction.
    perRemoteBytesPerSecond: number,
    -- Rate limits of client -> server remotes, keyed by Zap event name.
    clientRemotes: { [string]: RemoteLimit },
    -- Send rates of server -> client remotes, keyed by Zap event name.
    serverRemotes: { [string]: ServerSendRate },
    -- Runtime figures the dev probe checks.
    runtime: Runtime,
}

local PerfBudget: Budget = {
    perEventOverheadBytes = 8, -- chosen, not sourced: a conservative allowance, not measured
    clientToServerBytesPerSecond = 512, -- chosen, not sourced
    serverToClientBytesPerSecond = 2048, -- chosen, not sourced
    perRemoteBytesPerSecond = 256, -- chosen, not sourced
    clientRemotes = {
        -- The limit Main.server.luau builds the RequestPurchase RateLimiter from.
        RequestPurchase = { capacity = 3, refillPerSecond = 0.5 },
        -- Greenhouse (ADR 0020). A person taps a few plots a second at most; bursts are bounded.
        Plant = { capacity = 6, refillPerSecond = 4 },
        Harvest = { capacity = 6, refillPerSecond = 4 },
        Sell = { capacity = 2, refillPerSecond = 0.5 },
        BuyPlot = { capacity = 2, refillPerSecond = 0.5 },
        BuySeed = { capacity = 6, refillPerSecond = 4 },
        AutoHarvest = { capacity = 2, refillPerSecond = 0.5 },
        RequestPass = { capacity = 2, refillPerSecond = 0.5 },
    },
    serverRemotes = {
        -- At most a couple of grants per second reach one player.
        CoinsChanged = { maxPerSecond = 2 },
        -- Greenhouse: the controller flushes at most every 0.5 s (2 flushes per second). A flush
        -- sends the dirty plots only, so 12 per second covers the join sync of up to 10 plots plus
        -- the plant/harvest rate that the client limiters allow.
        PlotChanged = { maxPerSecond = 12 },
        -- 3 crops per flush, 2 flushes per second.
        StockChanged = { maxPerSecond = 6 },
        PassChanged = { maxPerSecond = 2 },
    },
    runtime = {
        maxHeartbeatMs = 16, -- sourced: server CPU time below 16 ms to hit 60 (production/analytics/performance)
        maxMemoryFraction = 0.5, -- sourced: keep server memory below 50% (performance-optimization/identify)
        memoryBaseMib = 6400, -- sourced: 6.25 GiB base = 6400 MiB (performance-optimization/identify)
        memoryPerPlayerMib = 100, -- sourced: 100 MiB per connected player (performance-optimization/identify)
        sendKbpsPerPlayer = 4, -- chosen, not sourced: the docs give no Kbps figure
        receiveKbpsPerPlayer = 2, -- chosen, not sourced: the docs give no Kbps figure
    },
}

return PerfBudget
