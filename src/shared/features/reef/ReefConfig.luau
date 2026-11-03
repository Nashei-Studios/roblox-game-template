--!strict
--[[
    Zones, fish and rods as data (ADR 0021). Pure: loads under Lune. Prices and values are
    derived from this table on the server; a client never sends one.
]]

export type Fish = {
    id: string,
    -- Relative chance inside its zone (not a percentage).
    weight: number,
    -- Coins paid when sold.
    value: number,
}

export type Zone = {
    index: number,
    fish: { Fish },
    -- Bite delay range in seconds (before bait).
    biteMinSeconds: number,
    biteMaxSeconds: number,
}

export type Rod = {
    level: number,
    -- Coins to buy this rod (level 1 is free).
    price: number,
    -- Deepest zone this rod reaches.
    maxZone: number,
}

export type ReefTable = {
    zones: { Zone },
    rods: { Rod },
}

local ReefConfig = {}

ReefConfig.default = {
    zones = {
        {
            index = 1,
            biteMinSeconds = 2,
            biteMaxSeconds = 5,
            fish = {
                { id = "minnow", weight = 70, value = 6 },
                { id = "sardine", weight = 25, value = 9 },
                { id = "perch", weight = 5, value = 20 },
            },
        },
        {
            index = 2,
            biteMinSeconds = 3,
            biteMaxSeconds = 7,
            fish = {
                { id = "mackerel", weight = 60, value = 18 },
                { id = "snapper", weight = 30, value = 30 },
                { id = "grouper", weight = 10, value = 70 },
            },
        },
        {
            index = 3,
            biteMinSeconds = 4,
            biteMaxSeconds = 9,
            fish = {
                { id = "tuna", weight = 55, value = 60 },
                { id = "swordfish", weight = 35, value = 110 },
                { id = "marlin", weight = 10, value = 300 },
            },
        },
    },
    rods = {
        { level = 1, price = 0, maxZone = 1 },
        { level = 2, price = 12, maxZone = 2 },
        { level = 3, price = 150, maxZone = 3 },
    },
} :: ReefTable

--- One problem per invalid value (empty when valid).
function ReefConfig.validate(table_: ReefTable): { string }
    local problems: { string } = {}
    if #table_.zones == 0 then
        table.insert(problems, "no zones")
    end
    local seenFish: { [string]: boolean } = {}
    for position, zone in table_.zones do
        if zone.index ~= position then
            table.insert(problems, `zone at position {position} has index {zone.index}`)
        end
        if zone.biteMinSeconds <= 0 or zone.biteMaxSeconds < zone.biteMinSeconds then
            table.insert(problems, `zone {zone.index} has an invalid bite range`)
        end
        if #zone.fish == 0 then
            table.insert(problems, `zone {zone.index} has no fish`)
        end
        for _, fish in zone.fish do
            if fish.id == "" or seenFish[fish.id] then
                table.insert(problems, `fish id "{fish.id}" is empty or repeated`)
            end
            seenFish[fish.id] = true
            if fish.weight <= 0 then
                table.insert(problems, `fish "{fish.id}" needs a positive weight`)
            end
            if fish.value <= 0 or fish.value % 1 ~= 0 then
                table.insert(problems, `fish "{fish.id}" needs a positive integer value`)
            end
        end
    end
    for position, rod in table_.rods do
        if rod.level ~= position then
            table.insert(problems, `rod at position {position} has level {rod.level}`)
        end
        if rod.maxZone < 1 or rod.maxZone > #table_.zones then
            table.insert(problems, `rod {rod.level} reaches a zone that does not exist`)
        end
        if rod.price < 0 or rod.price % 1 ~= 0 then
            table.insert(problems, `rod {rod.level} needs a non-negative integer price`)
        end
    end
    if #table_.rods == 0 or table_.rods[1].price ~= 0 then
        table.insert(problems, "the first rod must exist and be free")
    end
    return problems
end

--- The rod of `level`, or nil when out of range.
function ReefConfig.rod(table_: ReefTable, level: number): Rod?
    return table_.rods[level]
end

--- Coin value of a fish id, or nil when the id is not in the table.
function ReefConfig.fishValue(table_: ReefTable, fishId: string): number?
    for _, zone in table_.zones do
        for _, fish in zone.fish do
            if fish.id == fishId then
                return fish.value
            end
        end
    end
    return nil
end

return ReefConfig
