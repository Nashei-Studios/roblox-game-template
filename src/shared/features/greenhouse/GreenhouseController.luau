--!strict
--[[
    Server handler for the greenhouse remotes (ADR 0012, 0020). Pure: the clock, the data, the
    rate limiter, the pass check and the funnel are injected, so every rule runs under Lune.

    Order of checks for each remote: rate limiter first (a flooded client costs one bucket
    lookup), then `Validation` of every argument, then the rule in `Greenhouse` against the
    SERVER clock. The client sends intent only; it never says that a timer finished.

    State goes back through flat events (ADR 0020): the controller keeps a dirty set per player
    and `flush` sends only what changed. The caller flushes every ~0.5 s, which bounds the send
    rate in PerfBudget. A refused action marks its plot dirty so the client resyncs to the
    server state.
]]

local Clock = require("../../ports/Clock")
local Funnel = require("./Funnel")
local Greenhouse = require("./Greenhouse")
local GreenhouseData = require("./GreenhouseData")
local Validation = require("../../net/Validation")

export type Rejection =
    "rate_limited"
    | "no_data"
    | "pass_required"
    | Validation.ValidationError
    | Greenhouse.Reason

export type HandleResult = { ok: true } | { ok: false, reason: Rejection }

export type Deps = {
    clock: Clock.Clock,
    -- The live player data slice, or nil when the profile is not loaded.
    dataFor: (userId: number) -> Greenhouse.Slice?,
    -- Per-remote token bucket (names match PerfBudget.clientRemotes).
    allow: (userId: number, remote: string) -> boolean,
    -- Pass ownership as read from Roblox by the server.
    ownsPass: (userId: number, passName: string) -> boolean,
    funnel: Funnel.Funnel,
}

-- Where flush writes; Main.server binds these to the generated remotes.
export type Sender = {
    plot: (plot: number, cropIndex: number, readyAt: number) -> (),
    stock: (cropIndex: number, seeds: number, produce: number) -> (),
    coins: (coins: number) -> (),
    passes: (extraPlots: boolean, autoHarvest: boolean) -> (),
}

export type GreenhouseController = {
    join: (self: GreenhouseController, userId: number, sessionIndex: number) -> (),
    leave: (self: GreenhouseController, userId: number) -> (),
    plant: (
        self: GreenhouseController,
        userId: number,
        plot: unknown,
        crop: unknown
    ) -> HandleResult,
    harvest: (self: GreenhouseController, userId: number, plot: unknown) -> HandleResult,
    sell: (self: GreenhouseController, userId: number) -> HandleResult,
    buyPlot: (self: GreenhouseController, userId: number) -> HandleResult,
    buySeed: (self: GreenhouseController, userId: number, crop: unknown) -> HandleResult,
    autoHarvest: (self: GreenhouseController, userId: number) -> HandleResult,
    -- Stock and coins changed outside a remote (a product grant).
    markDirty: (self: GreenhouseController, userId: number) -> (),
    -- A pass was bought or its ownership was read.
    passesChanged: (self: GreenhouseController, userId: number) -> (),
    flush: (self: GreenhouseController, userId: number, sender: Sender) -> (),
}

type Dirty = { plots: { [number]: boolean }, stock: boolean, passes: boolean }

local GreenhouseControllerModule = {}

local MAX_U32 = 4294967295

local function reject(reason: Rejection): HandleResult
    return { ok = false, reason = reason }
end

local function clampWire(value: number, max: number): number
    return math.clamp(math.floor(value), 0, max)
end

function GreenhouseControllerModule.new(deps: Deps): GreenhouseController
    local dirtyByUser: { [number]: Dirty } = {}

    local function dirtyOf(userId: number): Dirty
        local dirty = dirtyByUser[userId]
        if dirty == nil then
            dirty = { plots = {}, stock = false, passes = false }
            dirtyByUser[userId] = dirty
        end
        return dirty
    end

    -- Common prelude: rate limit, then data. Returns the data or the rejection.
    local function enter(userId: number, remote: string): (Greenhouse.Slice?, HandleResult?)
        if not deps.allow(userId, remote) then
            return nil, reject("rate_limited")
        end
        local data = deps.dataFor(userId)
        if data == nil then
            return nil, reject("no_data")
        end
        return data, nil
    end

    local function plotIndex(value: unknown): (number?, HandleResult?)
        local checked = Validation.integerInRange(value, 1, GreenhouseData.ABSOLUTE_MAX_PLOTS)
        if not checked.ok then
            return nil, reject(checked.error)
        end
        return checked.value, nil
    end

    local function settle(
        userId: number,
        outcome: Greenhouse.Outcome<unknown>,
        plots: { number }
    ): HandleResult
        local dirty = dirtyOf(userId)
        for _, plot in plots do
            dirty.plots[plot] = true
        end
        dirty.stock = true
        if outcome.ok then
            return { ok = true }
        end
        return reject(outcome.reason)
    end

    local controller: GreenhouseController
    controller = {
        join = function(_self: GreenhouseController, userId: number, sessionIndex: number)
            local data = deps.dataFor(userId)
            local dirty = dirtyOf(userId)
            dirty.stock = true
            dirty.passes = true
            if data ~= nil then
                for index in data.plots do
                    dirty.plots[index] = true
                end
                deps.funnel:onJoin(userId, sessionIndex, data.totalHarvests)
            end
        end,
        leave = function(_self: GreenhouseController, userId: number)
            dirtyByUser[userId] = nil
            deps.funnel:forget(userId)
        end,
        plant = function(
            _self: GreenhouseController,
            userId: number,
            plot: unknown,
            crop: unknown
        ): HandleResult
            local data, denied = enter(userId, "Plant")
            if data == nil then
                return denied :: HandleResult
            end
            local index, badPlot = plotIndex(plot)
            if index == nil then
                return badPlot :: HandleResult
            end
            local cropId = Validation.oneOf(crop, GreenhouseData.cropIds())
            if not cropId.ok then
                return reject(cropId.error)
            end
            local outcome = Greenhouse.plant(data, deps.clock:now(), index, cropId.value)
            if outcome.ok then
                deps.funnel:onPlantAccepted(userId)
            end
            return settle(userId, outcome, { index })
        end,
        harvest = function(
            _self: GreenhouseController,
            userId: number,
            plot: unknown
        ): HandleResult
            local data, denied = enter(userId, "Harvest")
            if data == nil then
                return denied :: HandleResult
            end
            local index, badPlot = plotIndex(plot)
            if index == nil then
                return badPlot :: HandleResult
            end
            return settle(userId, Greenhouse.harvest(data, deps.clock:now(), index), { index })
        end,
        sell = function(_self: GreenhouseController, userId: number): HandleResult
            local data, denied = enter(userId, "Sell")
            if data == nil then
                return denied :: HandleResult
            end
            local outcome = Greenhouse.sell(data)
            if outcome.ok then
                deps.funnel:onSellAccepted(userId)
            end
            return settle(userId, outcome, {})
        end,
        buyPlot = function(_self: GreenhouseController, userId: number): HandleResult
            local data, denied = enter(userId, "BuyPlot")
            if data == nil then
                return denied :: HandleResult
            end
            local cap =
                GreenhouseData.maxPlots(deps.ownsPass(userId, GreenhouseData.PASS_EXTRA_PLOTS))
            local outcome = Greenhouse.buyPlot(data, cap)
            local added = if outcome.ok then { outcome.value } else {}
            return settle(userId, outcome, added)
        end,
        buySeed = function(
            _self: GreenhouseController,
            userId: number,
            crop: unknown
        ): HandleResult
            local data, denied = enter(userId, "BuySeed")
            if data == nil then
                return denied :: HandleResult
            end
            local cropId = Validation.oneOf(crop, GreenhouseData.cropIds())
            if not cropId.ok then
                return reject(cropId.error)
            end
            return settle(userId, Greenhouse.buySeed(data, cropId.value), {})
        end,
        autoHarvest = function(_self: GreenhouseController, userId: number): HandleResult
            local data, denied = enter(userId, "AutoHarvest")
            if data == nil then
                return denied :: HandleResult
            end
            if not deps.ownsPass(userId, GreenhouseData.PASS_AUTO_HARVEST) then
                return reject("pass_required")
            end
            local outcome = Greenhouse.autoHarvest(data, deps.clock:now())
            return settle(userId, outcome, if outcome.ok then outcome.value else {})
        end,
        markDirty = function(_self: GreenhouseController, userId: number)
            dirtyOf(userId).stock = true
        end,
        passesChanged = function(_self: GreenhouseController, userId: number)
            dirtyOf(userId).passes = true
        end,
        flush = function(_self: GreenhouseController, userId: number, sender: Sender)
            local dirty = dirtyByUser[userId]
            local data = deps.dataFor(userId)
            if dirty == nil or data == nil then
                return
            end
            local indexes: { number } = {}
            for index in dirty.plots do
                table.insert(indexes, index)
            end
            table.sort(indexes)
            for _, index in indexes do
                local plot = data.plots[index]
                if plot ~= nil then
                    local crop = GreenhouseData.cropById(plot.cropId)
                    sender.plot(
                        index,
                        if crop ~= nil then crop.index else 0,
                        clampWire(plot.readyAt, MAX_U32)
                    )
                end
            end
            if dirty.stock then
                for _, crop in GreenhouseData.CROPS do
                    sender.stock(
                        crop.index,
                        clampWire(data.seeds[crop.id] or 0, GreenhouseData.MAX_STOCK),
                        clampWire(data.produce[crop.id] or 0, GreenhouseData.MAX_STOCK)
                    )
                end
                sender.coins(clampWire(data.coins, MAX_U32))
            end
            if dirty.passes then
                sender.passes(
                    deps.ownsPass(userId, GreenhouseData.PASS_EXTRA_PLOTS),
                    deps.ownsPass(userId, GreenhouseData.PASS_AUTO_HARVEST)
                )
            end
            dirtyByUser[userId] = { plots = {}, stock = false, passes = false }
        end,
    }
    return controller
end

return GreenhouseControllerModule
