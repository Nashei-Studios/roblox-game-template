--!strict
--[[
    HUD rails (left, right, bottom) planned as pure geometry, so overlap and reach are impossible
    by construction and testable under Lune. The caller passes the usable rectangle in DESIGN px
    (already divided by the root UIScale) and the number of tiles per rail; it gets one rectangle
    per tile or the sentence of what does not fit.

    Rules:
    - A tile is a square of `edge` px: never below the touch floor, about 11 % of the short side,
      capped at 88 px.
    - Reflow, never shrink: a rail that runs out of height starts a second column.
    - On touch devices the lower part of the left and right sides belongs to the Roblox thumbstick
      and jump button: rails stay above `reserveBottomShare` of the height (chosen, not sourced:
      verify on a device).
    - The bottom rail lives between the side rails.
]]

local Geometry = require("../ui/audit/Geometry")
local SafeArea = require("./SafeArea")
local Tokens = require("./Tokens")

export type Counts = { left: number, right: number, bottom: number }

export type Tile = { rail: "left" | "right" | "bottom", index: number, rect: Geometry.Rect }

export type Plan = { edge: number, tiles: { Tile }, problems: { string } }

local MIN_SHARE = 0.11
local MAX_EDGE = 88

local HudRails = {}

--- Tile edge in design px.
function HudRails.edgeFor(usable: SafeArea.Rect, tokens: Tokens.Tokens): number
    local short = math.min(usable.width, usable.height)
    return math.clamp(math.round(short * MIN_SHARE), tokens.touchMin, MAX_EDGE)
end

local function column(
    rail: "left" | "right",
    count: number,
    usable: SafeArea.Rect,
    edge: number,
    gap: number,
    height: number,
    tiles: { Tile },
    problems: { string }
): number
    if count <= 0 then
        return 0
    end
    local perColumn = math.max(1, math.floor((height + gap) / (edge + gap)))
    local columns = math.ceil(count / perColumn)
    for index = 0, count - 1 do
        local col = index // perColumn
        local row = index % perColumn
        local offsetX = col * (edge + gap)
        local x = if rail == "left"
            then usable.x + offsetX
            else usable.x + usable.width - edge - offsetX
        local y = usable.y + row * (edge + gap)
        table.insert(
            tiles,
            { rail = rail, index = index + 1, rect = { x = x, y = y, width = edge, height = edge } }
        )
    end
    if edge > height + 0.5 then
        table.insert(problems, `UI-HUD-RAIL {rail}: not even one tile fits in {height} px`)
    end
    return columns * edge + (columns - 1) * gap
end

--- Plans the three rails inside `usable`.
function HudRails.plan(
    usable: SafeArea.Rect,
    counts: Counts,
    reserveBottomShare: number,
    tokens: Tokens.Tokens
): Plan
    local gap = Tokens.space(tokens, tokens.defaults.gap)
    local edge = HudRails.edgeFor(usable, tokens)
    local tiles: { Tile } = {}
    local problems: { string } = {}
    local sideHeight = usable.height * (1 - reserveBottomShare)
    local leftWidth = column("left", counts.left, usable, edge, gap, sideHeight, tiles, problems)
    local rightWidth = column("right", counts.right, usable, edge, gap, sideHeight, tiles, problems)
    if counts.bottom > 0 then
        local free = usable.width
            - leftWidth
            - rightWidth
            - (if leftWidth > 0 then gap else 0)
            - (if rightWidth > 0 then gap else 0)
        local perRow = math.max(1, math.floor((free + gap) / (edge + gap)))
        if counts.bottom > perRow then
            table.insert(
                problems,
                `UI-HUD-RAIL bottom: {counts.bottom} tiles do not fit in {math.floor(free)} px (room for {perRow})`
            )
        end
        local shown = math.min(counts.bottom, perRow)
        local rowWidth = shown * edge + (shown - 1) * gap
        local startX = usable.x + (usable.width - rowWidth) / 2
        local y = usable.y + usable.height - edge
        for index = 0, shown - 1 do
            table.insert(tiles, {
                rail = "bottom",
                index = index + 1,
                rect = { x = startX + index * (edge + gap), y = y, width = edge, height = edge },
            })
        end
    end
    -- Rails must not overlap each other and must stay inside the usable area.
    for first = 1, #tiles do
        local a = tiles[first]
        if not SafeArea.contains(usable, a.rect, 0.5) then
            table.insert(problems, `UI-OFFSCREEN {a.rail} tile {a.index} leaves the usable area`)
        end
        for second = first + 1, #tiles do
            local b = tiles[second]
            if Geometry.overlapArea(a.rect, b.rect) > 0 then
                table.insert(problems, `UI-OVERLAP {a.rail} {a.index} with {b.rail} {b.index}`)
            end
        end
    end
    return { edge = edge, tiles = tiles, problems = problems }
end

return HudRails
