--!strict
--[[
    Value text of a podium plate. Pure. Compact so a long number fits a plate: 999, 1.2K, 12K,
    3.4M, 5.6B. Values are floored; a negative or non-finite value reads as 0.
]]

local UNITS: { { limit: number, divisor: number, suffix: string } } = {
    { limit = 1e3, divisor = 1, suffix = "" },
    { limit = 1e6, divisor = 1e3, suffix = "K" },
    { limit = 1e9, divisor = 1e6, suffix = "M" },
    { limit = 1e12, divisor = 1e9, suffix = "B" },
}

local PodiumFormat = {}

--- 0 to 999 as is; above that one decimal under 10 of the unit, none from 10 up.
function PodiumFormat.compact(value: number): string
    if value ~= value or value == math.huge or value < 0 then
        return "0"
    end
    local whole = math.floor(value)
    for _, unit in UNITS do
        if whole < unit.limit then
            if unit.divisor == 1 then
                return tostring(whole)
            end
            local scaled = whole / unit.divisor
            if scaled < 10 then
                -- Truncate (not round) to one decimal so 9.99K never prints as 10.0K.
                local tenths = math.floor(scaled * 10) / 10
                return `{string.format("%.1f", tenths)}{unit.suffix}`
            end
            return `{math.floor(scaled)}{unit.suffix}`
        end
    end
    return `{math.floor(whole / 1e12)}T`
end

--- The plate line for a value: the compact number plus the game's unit, e.g. "1.2K m".
function PodiumFormat.value(value: number, unit: string): string
    local text = PodiumFormat.compact(value)
    if unit == "" then
        return text
    end
    return `{text} {unit}`
end

return PodiumFormat
