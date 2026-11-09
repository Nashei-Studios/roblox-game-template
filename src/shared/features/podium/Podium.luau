--!strict
--[[
    The podium service (ADR 0056). Pure: the source, the name resolver and the clock are injected.
    `tick` is cheap and safe to call every second: it reads the source only when `refreshSeconds`
    have passed since the last read, caches the resulting view, and says whether the view
    changed so the stage rebuilds only then.

    Failure policy: a failed read never throws and never reaches a player. With a good view
    cached it keeps showing it; with nothing cached the three pedestals are empty with the
    "Be the first" plate. Either way the next read waits a full interval (no hammering a store
    that is failing) and the failure goes to `onError` with context.
]]

local PodiumConfig = require("./PodiumConfig")
local PodiumModel = require("./PodiumModel")
local PodiumSource = require("../../ports/PodiumSource")
local RarityConfig = require("../rarity/RarityConfig")

export type View = PodiumModel.View

export type Deps = {
    config: PodiumConfig.PodiumConfig,
    rarity: RarityConfig.Config,
    -- Card surface the medal colors sit on ("#RRGGBB"), the same one the UI uses.
    surfaceHex: string,
    source: PodiumSource.PodiumSource,
    -- PodiumNames.new(...): filtered name of a user id; never throws.
    nameOf: (userId: number) -> string,
    -- The game's value formatter (its Format module); nil uses PodiumFormat with config.valueUnit.
    formatValue: ((value: number) -> string)?,
    -- Server clock, Unix seconds (os.time in production).
    now: () -> number,
    onError: (message: string) -> (),
}

export type Podium = {
    -- Refreshes when due. Returns true when the view changed (or this was the first tick).
    tick: (self: Podium) -> boolean,
    -- The current view (three empty pedestals before the first successful read).
    view: (self: Podium) -> View,
}

local PodiumService = {}

function PodiumService.new(deps: Deps): Podium
    local current = PodiumModel.empty(deps.config, deps.rarity, deps.surfaceHex)
    local lastAttempt: number? = nil
    local announced = false

    local function refresh(): boolean
        local read = deps.source:top(PodiumConfig.PLACES)
        if not read.ok then
            deps.onError(`podium "{deps.config.boardId}" read failed: {read.error.message}`)
            return false
        end
        local next = PodiumModel.build(
            deps.config,
            deps.rarity,
            deps.surfaceHex,
            read.value,
            deps.nameOf,
            deps.formatValue
        )
        local changed = next.signature ~= current.signature
        current = next
        return changed
    end

    local service: Podium = {
        tick = function(_self: Podium): boolean
            local now = deps.now()
            local previous = lastAttempt
            if previous ~= nil and now - previous < deps.config.refreshSeconds then
                return false
            end
            lastAttempt = now
            local changed = refresh()
            if not announced then
                announced = true
                return true
            end
            return changed
        end,
        view = function(_self: Podium): View
            return current
        end,
    }
    return service
end

return PodiumService
