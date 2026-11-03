--!strict
--[[
    The server-side rules of the fishing loop (ADR 0021). Pure: clock, RNG, pass checks and
    the stand check are injected, so it loads under Lune.

    The client sends INTENT only. This module owns the catch roll, the bite time, the reel
    window, prices and coins. Every method either mutates the data it is given and returns a
    typed value, or returns a typed error and leaves the data untouched (bait is spent only
    by an accepted cast).
]]

local FishRoll = require("./FishRoll")
local ReefConfig = require("./ReefConfig")
local ReefRules = require("./ReefRules")
local Validation = require("../../net/Validation")

-- The slice of PlayerData this module reads and writes.
export type ReefData = {
    coins: number,
    rodLevel: number,
    bait: number,
    totalCatches: number,
    fishStock: { [string]: number },
}

export type Deps = {
    table: ReefConfig.ReefTable,
    -- Seconds, monotonic (os.clock on the server).
    clock: () -> number,
    -- Random number in [0, 1).
    rng: () -> number,
    ownsPass: (userId: number, passName: string) -> boolean,
    -- Engine check that the player stands near the sell stand.
    isNearStand: (userId: number) -> boolean,
}

export type CastError =
    { kind: "invalid_zone", reason: Validation.ValidationError }
    | { kind: "zone_locked", zone: number, maxZone: number }
    | { kind: "cast_pending" }
    | { kind: "bucket_full", capacity: number }

export type CastStarted = {
    -- Distinguishes casts, so a delayed Bite message can tell it is stale.
    castId: number,
    zone: number,
    biteDelaySeconds: number,
    usedBait: boolean,
}

export type ReelOutcome =
    { caught: true, fishId: string, zone: number }
    | { caught: false, reason: "too_early" | "too_late" }

export type ReelError = { kind: "no_cast" }

export type SellError = { kind: "not_near_stand" } | { kind: "empty_bucket" } | { kind: "overflow" }

export type SellOutcome = { coinsEarned: number, fishSold: number }

export type BuyRodError =
    { kind: "max_rod" }
    | { kind: "not_enough_coins", price: number, coins: number }

export type CastResult = { ok: true, value: CastStarted } | { ok: false, error: CastError }
export type ReelResult = { ok: true, value: ReelOutcome } | { ok: false, error: ReelError }
export type SellResult = { ok: true, value: SellOutcome } | { ok: false, error: SellError }
export type BuyRodResult = { ok: true, value: number } | { ok: false, error: BuyRodError }

export type ReefController = {
    cast: (self: ReefController, userId: number, data: ReefData, zone: unknown) -> CastResult,
    reel: (self: ReefController, userId: number, data: ReefData) -> ReelResult,
    sell: (self: ReefController, userId: number, data: ReefData) -> SellResult,
    buyRod: (self: ReefController, userId: number, data: ReefData) -> BuyRodResult,
    -- True while `castId` is the player's live cast and its reel window has not ended.
    isPending: (self: ReefController, userId: number, castId: number) -> boolean,
    bucketCapacity: (self: ReefController, userId: number) -> number,
    stockCount: (self: ReefController, data: ReefData) -> number,
    forget: (self: ReefController, userId: number) -> (),
}

type Pending = {
    castId: number,
    zone: number,
    fishId: string,
    biteAt: number,
    windowEnd: number,
}

-- Largest integer a Luau number holds exactly.
local MAX_COINS = 2 ^ 53

local ReefControllerModule = {}

local function countStock(data: ReefData): number
    local total = 0
    for _, count in data.fishStock do
        total += count
    end
    return total
end

function ReefControllerModule.new(deps: Deps): ReefController
    local pending: { [number]: Pending } = {}
    local nextCastId = 0

    local function bucketCapacity(userId: number): number
        if deps.ownsPass(userId, ReefRules.BIGGER_BUCKET_PASS) then
            return ReefRules.BASE_BUCKET + ReefRules.BUCKET_PASS_EXTRA
        end
        return ReefRules.BASE_BUCKET
    end

    local controller: ReefController = {
        cast = function(
            _self: ReefController,
            userId: number,
            data: ReefData,
            rawZone: unknown
        ): CastResult
            local validated = Validation.integerInRange(rawZone, 1, #deps.table.zones)
            if not validated.ok then
                return { ok = false, error = { kind = "invalid_zone", reason = validated.error } }
            end
            local zoneIndex = validated.value
            local rod = ReefConfig.rod(deps.table, data.rodLevel)
            local maxZone = if rod == nil then 1 else rod.maxZone
            if zoneIndex > maxZone then
                return {
                    ok = false,
                    error = { kind = "zone_locked", zone = zoneIndex, maxZone = maxZone },
                }
            end
            local now = deps.clock()
            local live = pending[userId]
            if live ~= nil and now <= live.windowEnd then
                return { ok = false, error = { kind = "cast_pending" } }
            end
            local capacity = bucketCapacity(userId)
            if countStock(data) >= capacity then
                return { ok = false, error = { kind = "bucket_full", capacity = capacity } }
            end

            local zone = deps.table.zones[zoneIndex]
            local tutorial = data.totalCatches == 0
            local usedBait = false
            local delay: number
            if tutorial then
                delay = ReefRules.TUTORIAL_BITE_SECONDS
            else
                delay = FishRoll.biteDelay(zone, deps.rng())
                if data.bait > 0 then
                    data.bait -= 1
                    usedBait = true
                    delay *= ReefRules.BAIT_BITE_FACTOR
                end
            end
            nextCastId += 1
            local biteAt = now + delay
            pending[userId] = {
                castId = nextCastId,
                zone = zoneIndex,
                fishId = FishRoll.pickFish(zone, deps.rng()),
                biteAt = biteAt,
                windowEnd = biteAt + ReefRules.REEL_WINDOW_SECONDS,
            }
            return {
                ok = true,
                value = {
                    castId = nextCastId,
                    zone = zoneIndex,
                    biteDelaySeconds = delay,
                    usedBait = usedBait,
                },
            }
        end,

        reel = function(_self: ReefController, userId: number, data: ReefData): ReelResult
            local live = pending[userId]
            if live == nil then
                return { ok = false, error = { kind = "no_cast" } }
            end
            -- A reel always ends the cast, caught or not.
            pending[userId] = nil
            local now = deps.clock()
            if now < live.biteAt then
                return { ok = true, value = { caught = false, reason = "too_early" } }
            end
            if now > live.windowEnd then
                return { ok = true, value = { caught = false, reason = "too_late" } }
            end
            data.fishStock[live.fishId] = (data.fishStock[live.fishId] or 0) + 1
            data.totalCatches += 1
            return { ok = true, value = { caught = true, fishId = live.fishId, zone = live.zone } }
        end,

        sell = function(_self: ReefController, userId: number, data: ReefData): SellResult
            if
                not deps.ownsPass(userId, ReefRules.SELL_ANYWHERE_PASS)
                and not deps.isNearStand(userId)
            then
                return { ok = false, error = { kind = "not_near_stand" } }
            end
            local earned = 0
            local sold = 0
            for fishId, count in data.fishStock do
                sold += count
                earned += count * (ReefConfig.fishValue(deps.table, fishId) or 0)
            end
            if sold == 0 then
                return { ok = false, error = { kind = "empty_bucket" } }
            end
            if data.coins > MAX_COINS - earned then
                return { ok = false, error = { kind = "overflow" } }
            end
            data.coins += earned
            table.clear(data.fishStock)
            return { ok = true, value = { coinsEarned = earned, fishSold = sold } }
        end,

        buyRod = function(_self: ReefController, _userId: number, data: ReefData): BuyRodResult
            local nextRod = ReefConfig.rod(deps.table, data.rodLevel + 1)
            if nextRod == nil then
                return { ok = false, error = { kind = "max_rod" } }
            end
            if data.coins < nextRod.price then
                return {
                    ok = false,
                    error = {
                        kind = "not_enough_coins",
                        price = nextRod.price,
                        coins = data.coins,
                    },
                }
            end
            data.coins -= nextRod.price
            data.rodLevel = nextRod.level
            return { ok = true, value = nextRod.level }
        end,

        isPending = function(_self: ReefController, userId: number, castId: number): boolean
            local live = pending[userId]
            return live ~= nil and live.castId == castId and deps.clock() <= live.windowEnd
        end,

        bucketCapacity = function(_self: ReefController, userId: number): number
            return bucketCapacity(userId)
        end,

        stockCount = function(_self: ReefController, data: ReefData): number
            return countStock(data)
        end,

        forget = function(_self: ReefController, userId: number)
            pending[userId] = nil
        end,
    }
    return controller
end

return ReefControllerModule
