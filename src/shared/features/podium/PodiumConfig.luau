--!strict
--[[
    Typed config of the 3D podium and its validation (ADR 0056). Pure: loads under Lune. Words,
    unit, medal tiers, refresh and geometry live here; the engine pieces live in
    server/adapters/PodiumStage. Numbers carry their provenance: "chosen, not sourced".
]]

local RarityConfig = require("../rarity/RarityConfig")

export type Layout = {
    -- Width and depth of every step, studs.
    stepWidth: number,
    stepDepth: number,
    -- Gap between two steps, studs.
    stepGap: number,
    -- Height of the step of place 1, 2 and 3 (studs). Place 1 is the tallest.
    stepHeights: { number },
    -- Uniform scale of every avatar statue (Model:ScaleTo). 1 is a normal avatar.
    statueScale: number,
}

export type PodiumConfig = {
    -- The LeaderboardsConfig board this podium shows (the game wires the source for it).
    boardId: string,
    -- Heading above the podium.
    title: string,
    -- Seconds between two reads of the source. At least PerfBudget.podium.minRefreshSeconds.
    refreshSeconds: number,
    -- Rarity tier ids whose colors dress places 1, 2 and 3 (medal colors, ADR 0048).
    placeTierIds: { string },
    -- Plate line of an empty pedestal ("Be the first").
    emptyLabel: string,
    -- Name shown when a name cannot be fetched or filtered. A raw name is never shown.
    unknownName: string,
    -- Unit printed after the value ("m", "coins"); "" for none.
    valueUnit: string,
    -- Names longer than this are cut with an ellipsis.
    nameMaxLength: number,
    -- Short looping idle animation asset id ("rbxassetid://..."); nil keeps a static pose.
    idleAnimationId: string?,
    layout: Layout,
}

local PodiumConfigModule = {}

PodiumConfigModule.PLACES = 3 -- the mold is a 3-step podium
PodiumConfigModule.MIN_NAME_LENGTH = 6 -- chosen, not sourced: shorter cuts every name
PodiumConfigModule.MAX_NAME_LENGTH = 40 -- chosen, not sourced: a plate line, Roblox names are at most 20

PodiumConfigModule.default = {
    boardId = "Coins", -- TODO(game): the board this podium shows
    title = "Top miners",
    refreshSeconds = 60, -- chosen, not sourced: same floor as the boards it reads
    placeTierIds = { "legendary", "epic", "rare" }, -- ember, violet, blue
    emptyLabel = "Be the first",
    unknownName = "Player",
    valueUnit = "",
    nameMaxLength = 16, -- chosen, not sourced
    idleAnimationId = nil, -- TODO(game): an allowed idle animation id; nil is a static pose
    layout = {
        stepWidth = 6, -- chosen, not measured: wide enough for a 1.6x statue and a readable tag
        stepDepth = 6, -- chosen, not measured
        stepGap = 0.6, -- chosen, not measured
        stepHeights = { 3.6, 2.8, 2 }, -- chosen, not measured: low, so a 1.6x statue stays under the spawn camera height
        statueScale = 1.6, -- chosen, not measured: statues about 1.6x an avatar
    },
} :: PodiumConfig

local function isFiniteNumber(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

--- One human-readable problem per invalid value (empty when valid). `minRefreshSeconds` is
--- PerfBudget.podium.minRefreshSeconds; `rarity` is the ladder the medal tiers must exist in.
function PodiumConfigModule.problems(
    config: PodiumConfig,
    rarity: RarityConfig.Config,
    minRefreshSeconds: number
): { string }
    local found: { string } = {}
    if config.boardId == "" then
        table.insert(found, "podium.boardId is empty")
    end
    if config.title == "" then
        table.insert(found, "podium.title is empty")
    end
    if not isFiniteNumber(config.refreshSeconds) or config.refreshSeconds < minRefreshSeconds then
        table.insert(found, `podium.refreshSeconds must be at least {minRefreshSeconds}`)
    end
    if #config.placeTierIds ~= PodiumConfigModule.PLACES then
        table.insert(found, `podium.placeTierIds needs exactly {PodiumConfigModule.PLACES} ids`)
    end
    for _, id in config.placeTierIds do
        if RarityConfig.rank(rarity, id) == nil then
            table.insert(found, `podium.placeTierIds has unknown rarity "{id}"`)
        end
    end
    if config.emptyLabel == "" then
        table.insert(found, "podium.emptyLabel is empty")
    end
    if config.unknownName == "" then
        table.insert(found, "podium.unknownName is empty")
    end
    if
        not isFiniteNumber(config.nameMaxLength)
        or config.nameMaxLength < PodiumConfigModule.MIN_NAME_LENGTH
        or config.nameMaxLength > PodiumConfigModule.MAX_NAME_LENGTH
    then
        table.insert(
            found,
            `podium.nameMaxLength must be {PodiumConfigModule.MIN_NAME_LENGTH} to {PodiumConfigModule.MAX_NAME_LENGTH}`
        )
    end
    local animation = config.idleAnimationId
    if animation ~= nil and string.match(animation, "^rbxassetid://%d+$") == nil then
        table.insert(found, 'podium.idleAnimationId must look like "rbxassetid://123"')
    end
    local layout = config.layout
    if not isFiniteNumber(layout.stepWidth) or layout.stepWidth <= 0 then
        table.insert(found, "podium.layout.stepWidth must be positive")
    end
    if not isFiniteNumber(layout.stepDepth) or layout.stepDepth <= 0 then
        table.insert(found, "podium.layout.stepDepth must be positive")
    end
    if not isFiniteNumber(layout.stepGap) or layout.stepGap < 0 then
        table.insert(found, "podium.layout.stepGap must be 0 or more")
    end
    if
        not isFiniteNumber(layout.statueScale)
        or layout.statueScale < 0.5
        or layout.statueScale > 3
    then
        table.insert(found, "podium.layout.statueScale must be 0.5 to 3")
    end
    if #layout.stepHeights ~= PodiumConfigModule.PLACES then
        table.insert(found, "podium.layout.stepHeights needs exactly 3 heights")
    else
        local first, second, third =
            layout.stepHeights[1], layout.stepHeights[2], layout.stepHeights[3]
        if not (first > second and second > third and third > 0) then
            table.insert(
                found,
                "podium.layout.stepHeights must fall from place 1 to 3 and stay positive"
            )
        end
    end
    return found
end

return PodiumConfigModule
