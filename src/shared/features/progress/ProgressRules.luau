--!strict
--[[
    Pure rules of visible progression. Loads under Lune. Nothing here knows the game: tiers,
    steps and message templates are data the game passes in.
      - tierFor: the tier (title, color) a counter value has reached.
      - milestoneCrossed: the highest multiple of a step newly reached.
      - format: a message from a template with {name} and {value}.
      - newDailyCounter: a per-UTC-day count derived from a lifetime counter.
]]

export type Tier = { min: number, name: string, colorHex: string }

export type DailyCounter = {
    -- Units counted during the current UTC day, given the lifetime counter `total`.
    observe: (self: DailyCounter, userId: number, total: number, now: number) -> number,
    forget: (self: DailyCounter, userId: number) -> (),
}

local SECONDS_PER_DAY = 86400

local ProgressRules = {}

--- The last tier whose `min` is reached (tiers are ordered by `min`, the first has the lowest).
function ProgressRules.tierFor(value: number, tiers: { Tier }): Tier
    local best = tiers[1]
    for _, tier in tiers do
        if value >= tier.min then
            best = tier
        end
    end
    return best
end

--- One problem per invalid value (empty when valid): not empty, strictly increasing `min`, a
--- name and a "#RRGGBB" color on every tier.
function ProgressRules.validateTiers(tiers: { Tier }): { string }
    local problems: { string } = {}
    if #tiers == 0 then
        table.insert(problems, "there must be at least one tier")
    end
    local previous: number? = nil
    for index, tier in tiers do
        if tier.name == "" then
            table.insert(problems, `tier {index} has no name`)
        end
        if string.match(tier.colorHex, "^#%x%x%x%x%x%x$") == nil then
            table.insert(problems, `tier {index} color must be #RRGGBB`)
        end
        if previous ~= nil and tier.min <= previous then
            table.insert(problems, `tier {index} min must be above the previous tier`)
        end
        previous = tier.min
    end
    return problems
end

--- The highest multiple of `step` reached by `current` that is above `previous` (the best
--- already announced), or nil when none is new or `step` is not positive.
function ProgressRules.milestoneCrossed(previous: number, current: number, step: number): number?
    if step <= 0 then
        return nil
    end
    local reached = math.floor(current / step) * step
    if reached > 0 and reached > previous then
        return reached
    end
    return nil
end

--- Fills {name} and {value} in `template`. Unknown braces stay as written.
function ProgressRules.format(template: string, name: string, value: number): string
    local filled = string.gsub(template, "{name}", function()
        return name
    end)
    filled = string.gsub(filled, "{value}", function()
        return tostring(value)
    end)
    return filled
end

--- Counts units per UTC day from a lifetime counter. In memory: the first sight of the day (a
--- rejoin, another server) is the baseline, so the day's count restarts at 0 there.
function ProgressRules.newDailyCounter(): DailyCounter
    local state: { [number]: { day: number, base: number } } = {}
    local counter: DailyCounter = {
        observe = function(_self: DailyCounter, userId: number, total: number, now: number): number
            local day = math.floor(now / SECONDS_PER_DAY)
            local entry = state[userId]
            if entry == nil or entry.day ~= day then
                entry = { day = day, base = total }
                state[userId] = entry
            end
            return math.max(0, total - entry.base)
        end,
        forget = function(_self: DailyCounter, userId: number)
            state[userId] = nil
        end,
    }
    return counter
end

return ProgressRules
