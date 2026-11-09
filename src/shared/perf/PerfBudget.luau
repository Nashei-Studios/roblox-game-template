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

-- Client per-frame work the rarity language may add (ADR 0048). Read by RarityConfig tests and by
-- the shimmer clock; a game lowers these, never raises them without measuring on a phone.
export type ClientFx = {
    -- Shimmer gradients animated at once; the rest render static. One Heartbeat step moves all.
    maxLiveShimmers: number,
    -- World emitters alive at once; the rest keep color and light but no particles.
    maxLiveEmitters: number,
    -- Particles per second one emitter may spawn at the high quality tier.
    maxParticlesPerSecond: number,
    -- Light beams a reveal draws at once (ADR 0054). They rotate as ONE group, so the per-frame cost
    -- is a single Rotation write whatever the count; the cap bounds the instances, not the frames.
    maxRevealBeams: number,
}

-- World podium (ADR 0056). The statues are server-built and anchored, so the cost is parts and
-- web calls, not frames; the only client work is the optional idle animation.
export type PodiumBudget = {
    -- Parts of the whole podium: 3 steps, 3 plates and 3 avatar statues (a statue is ~15 parts
    -- plus accessories). The stage reports when a build goes over.
    maxParts: number,
    -- Floor for PodiumConfig.refreshSeconds: each refresh may cost a GetSortedAsync (5 per
    -- minute per server) and up to three avatar loads.
    minRefreshSeconds: number,
    -- Statues animated at once (idle animation); the rest hold the static pose.
    maxAnimatedStatues: number,
}

-- World nodes with a model per tier (ADR 0057). The parts are built once into a pool and re-posed
-- when the tier changes, so the cost is the standing parts and triangles, not allocations.
export type TierModelBudget = {
    -- Parts one node (rock, ore, slab) may use, whatever its tier.
    maxPartsPerNode: number,
    -- Upper bound of triangles per node (TierModelConfig.TRIANGLES per shape).
    maxTrianglesPerNode: number,
    -- Nodes drawn at once; the total standing cost is this times the per-node figures.
    maxVisibleNodes: number,
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
    -- Per-frame client work of RarityFx; optional so a budget literal without it stays valid.
    clientFx: ClientFx?,
    -- World podium limits; optional so a budget literal without it stays valid.
    podium: PodiumBudget?,
    -- Per-tier world models; optional so a budget literal without it stays valid.
    tierModels: TierModelBudget?,
}

local PerfBudget: Budget = {
    perEventOverheadBytes = 8, -- chosen, not sourced: a conservative allowance, not measured
    clientToServerBytesPerSecond = 512, -- chosen, not sourced
    serverToClientBytesPerSecond = 2048, -- chosen, not sourced
    perRemoteBytesPerSecond = 256, -- chosen, not sourced
    clientRemotes = {
        -- The limit Main.server.luau builds the RequestPurchase RateLimiter from.
        RequestPurchase = { capacity = 3, refillPerSecond = 0.5 },
        -- Engagement modules (ADR 0025); Main.server builds each limiter from these numbers.
        RedeemCode = { capacity = 2, refillPerSecond = 0.2 }, -- chosen, not sourced
        ClaimDailyReward = { capacity = 2, refillPerSecond = 0.2 }, -- chosen, not sourced
        ClaimSessionGift = { capacity = 2, refillPerSecond = 0.1 }, -- chosen, not sourced
        SetVolume = { capacity = 2, refillPerSecond = 1 }, -- chosen, not sourced: the client sends on slider release
        -- The monetization surfaces (ADR 0022). Chosen, not sourced: a player presses a button,
        -- so a small burst and a slow refill are far above any real use.
        RequestRewardedAd = { capacity = 2, refillPerSecond = 0.1 }, -- chosen, not sourced
        RequestPlusPrompt = { capacity = 2, refillPerSecond = 0.05 }, -- chosen, not sourced
        RequestRobuxTransfer = { capacity = 2, refillPerSecond = 0.2 }, -- chosen, not sourced
        RequestPrivateServerSetting = { capacity = 2, refillPerSecond = 0.2 }, -- chosen, not sourced
        -- Community join reward (issue #36): a "Check again" button; the service adds its own cooldown.
        RequestCommunityCheck = { capacity = 1, refillPerSecond = 0.05 }, -- chosen, not sourced
    },
    serverRemotes = {
        -- At most a couple of grants per second reach one player.
        CoinsChanged = { maxPerSecond = 2 },
        -- Engagement modules (ADR 0025).
        Notify = { maxPerSecond = 4 }, -- chosen, not sourced: a few toasts per second at most
        AnnounceMilestone = { maxPerSecond = 1 }, -- chosen, not sourced: milestones are rare
        SoundSettings = { maxPerSecond = 2 }, -- chosen, not sourced
    },
    runtime = {
        maxHeartbeatMs = 16, -- sourced: server CPU time below 16 ms to hit 60 (production/analytics/performance)
        maxMemoryFraction = 0.5, -- sourced: keep server memory below 50% (performance-optimization/identify)
        memoryBaseMib = 6400, -- sourced: 6.25 GiB base = 6400 MiB (performance-optimization/identify)
        memoryPerPlayerMib = 100, -- sourced: 100 MiB per connected player (performance-optimization/identify)
        sendKbpsPerPlayer = 4, -- chosen, not sourced: the docs give no Kbps figure
        receiveKbpsPerPlayer = 2, -- chosen, not sourced: the docs give no Kbps figure
    },
    clientFx = {
        maxLiveShimmers = 8, -- chosen, not measured: a screenful of cards, one property write each per frame
        maxLiveEmitters = 4, -- chosen, not measured: Roblox publishes no emitter count for phones
        maxParticlesPerSecond = 12, -- chosen, not measured: small bursts read as a sparkle, not a cloud
        maxRevealBeams = 8, -- chosen, not measured: eight thin frames in one rotating group
    },
    podium = {
        maxParts = 96, -- chosen, not measured: 3 steps + 3 plates + 3 statues of about 30 parts with accessories
        minRefreshSeconds = 60, -- chosen, not sourced: keeps the GetSortedAsync budget of 5 per minute (docs/performance.md)
        maxAnimatedStatues = 3, -- chosen, not measured: one idle loop per statue
    },
    tierModels = {
        maxPartsPerNode = 24, -- chosen, not measured: a rock reads with a handful of chunky parts
        maxTrianglesPerNode = 600, -- chosen, not measured: Roblox publishes no per-node figure for phones
        maxVisibleNodes = 6, -- chosen, not measured: a slab plus a few ore nodes in view
    },
}

return PerfBudget
