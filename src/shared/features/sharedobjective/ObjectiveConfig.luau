--!strict
--[[
    Typed config of the shared objective mold (ADR 0049) and its validation. Pure: loads under
    Lune. Nothing here names a game: "units" are whatever the game counts (swings, kills, orbs),
    and the reward payload is not part of the mold (the game maps a Completion to its rewards).
]]

export type ObjectiveConfig = {
    -- Seconds between the end of one objective and the opening of the next.
    intervalSeconds: number,
    -- Seconds an open objective lasts. Must be shorter than the interval.
    durationSeconds: number,
    -- The first objective opens this many seconds after the first player is present.
    firstOpenSeconds: number,
    -- Units the bar asks for per player in the server (the target scales with the room).
    unitsPerPlayer: number,
    -- Per-player rate cap in units per second (a burst up to one second is allowed).
    maxUnitsPerSecond: number,
    -- Units a player must contribute to be counted in the completion.
    minContribution: number,
    -- Players at the top of the ranking flagged `top` in the completion.
    topCount: number,
    -- Seconds the beat stays "drop" or "fail" after the objective resolves.
    resultHoldSeconds: number,
}

local ObjectiveConfigModule = {}

--- Neutral defaults: a four-minute cycle with a ninety-second window.
ObjectiveConfigModule.default = {
    intervalSeconds = 240,
    durationSeconds = 90,
    firstOpenSeconds = 45,
    unitsPerPlayer = 60,
    maxUnitsPerSecond = 8,
    minContribution = 1,
    topCount = 3,
    resultHoldSeconds = 8,
} :: ObjectiveConfig

local function positive(value: number): boolean
    return value == value and value > 0
end

--- One human-readable problem per invalid value (empty when valid).
function ObjectiveConfigModule.problems(config: ObjectiveConfig): { string }
    local found: { string } = {}
    if not positive(config.intervalSeconds) then
        table.insert(found, "intervalSeconds must be above zero")
    end
    if not positive(config.durationSeconds) then
        table.insert(found, "durationSeconds must be above zero")
    elseif config.durationSeconds >= config.intervalSeconds then
        table.insert(found, "durationSeconds must be shorter than intervalSeconds")
    end
    if config.firstOpenSeconds ~= config.firstOpenSeconds or config.firstOpenSeconds < 0 then
        table.insert(found, "firstOpenSeconds must be zero or positive")
    end
    if not positive(config.unitsPerPlayer) then
        table.insert(found, "unitsPerPlayer must be above zero")
    end
    if not positive(config.maxUnitsPerSecond) then
        table.insert(found, "maxUnitsPerSecond must be above zero")
    end
    if config.minContribution ~= config.minContribution or config.minContribution < 0 then
        table.insert(found, "minContribution must be zero or positive")
    end
    if config.topCount < 0 or config.topCount % 1 ~= 0 then
        table.insert(found, "topCount must be a non-negative integer")
    end
    if config.resultHoldSeconds ~= config.resultHoldSeconds or config.resultHoldSeconds < 0 then
        table.insert(found, "resultHoldSeconds must be zero or positive")
    end
    return found
end

return ObjectiveConfigModule
