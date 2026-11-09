--!strict
--[[
    The bookkeeping of a pool of parts, pure so the "no garbage on a tier swap" promise is a test
    and not a hope (ADR 0057). The pool is sized once from the largest demand of any tier, by part
    shape (a WedgePart is another class than a Part, so shapes cannot share a slot). `assign` says,
    per shape, how many pooled parts to show and how many of the previously shown ones to hide; it
    never asks for more than the capacity, and `created` never grows after construction.
]]

export type Demand = { [string]: number }

export type Assignment = {
    -- Parts to pose and show, by shape.
    show: Demand,
    -- Parts shown before that are now unused and must be hidden, by shape.
    hide: Demand,
    -- Demand above the capacity, by shape. The rig skips those parts and reports it.
    overflow: Demand,
}

export type TierPool = {
    -- Total parts built at construction. Constant for the life of the pool.
    created: (self: TierPool) -> number,
    -- Capacity by shape.
    capacity: (self: TierPool) -> Demand,
    assign: (self: TierPool, demand: Demand) -> Assignment,
    -- Number of `assign` calls so far (a swap counter for the report and the tests).
    swaps: (self: TierPool) -> number,
}

local TierPoolModule = {}

--- The capacity that fits every demand: for each shape, the largest count any one demand asks.
function TierPoolModule.capacityFor(demands: { Demand }): Demand
    local capacity: Demand = {}
    for _, demand in demands do
        for shape, count in demand do
            capacity[shape] = math.max(capacity[shape] or 0, count)
        end
    end
    return capacity
end

function TierPoolModule.new(capacity: Demand): TierPool
    local fixed: Demand = table.clone(capacity)
    local total = 0
    for _, count in fixed do
        total += count
    end
    local shown: Demand = {}
    local swapCount = 0
    local pool: TierPool
    pool = {
        created = function(_self: TierPool): number
            return total
        end,
        capacity = function(_self: TierPool): Demand
            return table.clone(fixed)
        end,
        assign = function(_self: TierPool, demand: Demand): Assignment
            swapCount += 1
            local show: Demand = {}
            local hide: Demand = {}
            local overflow: Demand = {}
            local shapes: { [string]: boolean } = {}
            for shape in demand do
                shapes[shape] = true
            end
            for shape in shown do
                shapes[shape] = true
            end
            for shape in shapes do
                local wanted = demand[shape] or 0
                local room = fixed[shape] or 0
                local used = math.min(wanted, room)
                if used > 0 then
                    show[shape] = used
                end
                if wanted > room then
                    overflow[shape] = wanted - room
                end
                local before = shown[shape] or 0
                if before > used then
                    hide[shape] = before - used
                end
                shown[shape] = used
            end
            return { show = show, hide = hide, overflow = overflow }
        end,
        swaps = function(_self: TierPool): number
            return swapCount
        end,
    }
    return pool
end

return TierPoolModule
