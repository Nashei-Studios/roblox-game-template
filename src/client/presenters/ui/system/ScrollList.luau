--!strict
--[[
    ScrollList and Grid: the two scrolling containers. By construction a ScrollList has an
    automatic canvas (no hand-sized CanvasSize that clips the last row), a UIPadding (rows never
    touch the edges) and a list gap from a token. A Grid is a ScrollList whose cells are computed
    from the available width (CardGrid.columnsFor: never 0 columns) with a cell padding token on
    both axes, and every cell is at least the touch floor wide and tall.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CardGrid = require(Shared.features.ui.CardGrid)
local Tokens = require(Shared.features.uisystem.Tokens)
local Atoms = require(script.Parent.Atoms)
local DevGuard = require(script.Parent.DevGuard)
local UiEnv = require(script.Parent.UiEnv)

export type Options = {
    name: string,
    gap: Tokens.SpacingKey?,
    pad: Tokens.SpacingKey?,
}

export type GridOptions = {
    name: string,
    gap: Tokens.SpacingKey?,
    pad: Tokens.SpacingKey?,
    -- Smallest card width and fixed card height in px (both raised to the touch floor).
    minCardWidth: number,
    cardHeight: number,
}

local ScrollList = {}

local function scroller(env: UiEnv.UiEnv, parent: Instance, name: string, pad: Tokens.SpacingKey?)
    local tokens = env.tokens
    local frame = Instance.new("ScrollingFrame")
    frame.Name = name
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Size = UDim2.fromScale(1, 1)
    frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.CanvasSize = UDim2.new()
    frame.ScrollingDirection = Enum.ScrollingDirection.Y
    frame.ScrollBarThickness = tokens.spacing.xs
    Atoms.pad(frame, tokens, pad or tokens.defaults.pad)
    frame.Parent = parent
    return frame
end

--- A vertical scrolling list. Add rows as children of the returned frame.
function ScrollList.new(env: UiEnv.UiEnv, parent: Instance, options: Options): ScrollingFrame
    local tokens = env.tokens
    local frame = scroller(env, parent, options.name, options.pad)
    Atoms.list(frame, tokens, options.gap or tokens.defaults.gap, false)
    DevGuard.verify(frame, `ScrollList {options.name}`)
    return frame
end

--- A scrolling grid of equal cells. Cell width follows the container; add cards as children.
function ScrollList.grid(env: UiEnv.UiEnv, parent: Instance, options: GridOptions): ScrollingFrame
    local tokens = env.tokens
    local gap = Tokens.space(tokens, options.gap or tokens.defaults.gap)
    local minWidth = math.max(options.minCardWidth, tokens.touchMin)
    local height = math.max(options.cardHeight, tokens.touchMin)
    local frame = scroller(env, parent, options.name, options.pad)
    local grid = Instance.new("UIGridLayout")
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.CellPadding = UDim2.fromOffset(gap, gap)
    grid.CellSize = UDim2.fromOffset(minWidth, height)
    grid.Parent = frame

    local function relayout()
        local padding = frame:FindFirstChildOfClass("UIPadding")
        local inset = if padding ~= nil
            then padding.PaddingLeft.Offset + padding.PaddingRight.Offset
            else 0
        local width = frame.AbsoluteSize.X / env.scale - frame.ScrollBarThickness - inset
        local _, cell = CardGrid.columnsFor(width, minWidth, gap)
        grid.CellSize = UDim2.fromOffset(math.max(math.floor(cell), minWidth), height)
    end
    frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
    relayout()
    DevGuard.verify(frame, `Grid {options.name}`)
    return frame
end

--- One row of a list or grid: a surface panel with the card padding token on every side, so text
--- never touches the row edge (rule UI-CARD-INSET). Put the row content inside the returned frame.
function ScrollList.item(env: UiEnv.UiEnv, parent: Instance, name: string): Frame
    local tokens = env.tokens
    local row = Atoms.panel(parent, tokens, name, "surface", "md")
    Atoms.pad(row, tokens, tokens.defaults.cardPad)
    return row
end

return ScrollList
