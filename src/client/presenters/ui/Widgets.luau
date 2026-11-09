--!strict
--[[
    Client presenter helpers: the few instances the UI kit is made of (panel, label, button).
    Every size, color, font and gap comes from the resolved theme tokens; the only numbers here
    are 0 and 1 (scale fractions). It touches the engine, so it is excluded from the line-coverage
    gate and kept thin on purpose.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage.Shared.features.ui.UiConfig)

export type Theme = UiConfig.Theme

local Widgets = {}

--- Color3 from a palette entry.
function Widgets.color(hex: string): Color3
    return Color3.fromHex(hex)
end

--- A Font enum member by its name, falling back to the default UI font when the name is wrong.
function Widgets.font(name: string): Enum.Font
    for _, item in Enum.Font:GetEnumItems() do
        if item.Name == name then
            return item
        end
    end
    warn(`ui.theme.font "{name}" is not an Enum.Font member; using the default font`)
    return Enum.Font.BuilderSans
end

local function decorate(frame: GuiObject, theme: Theme, fill: string)
    frame.BackgroundColor3 = Widgets.color(fill)
    frame.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, theme.radius)
    corner.Parent = frame
    if theme.strokeThickness > 0 then
        local stroke = Instance.new("UIStroke")
        stroke.Thickness = theme.strokeThickness
        stroke.Color = Widgets.color(theme.palette.surfaceRaised)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = frame
    end
end

--- A rounded panel filled with a palette color.
function Widgets.panel(parent: Instance, theme: Theme, name: string, fill: string): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    decorate(frame, theme, fill)
    frame.Parent = parent
    return frame
end

--- Padding from a spacing token.
function Widgets.pad(parent: Instance, points: number)
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, points)
    padding.PaddingBottom = UDim.new(0, points)
    padding.PaddingLeft = UDim.new(0, points)
    padding.PaddingRight = UDim.new(0, points)
    padding.Parent = parent
end

--- A vertical list with a gap token.
function Widgets.stack(parent: Instance, gap: number, horizontal: boolean?)
    assert(gap > 0, "Widgets.stack: the gap must be a spacing token above 0 (items would touch)")
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, gap)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    if horizontal == true then
        list.FillDirection = Enum.FillDirection.Horizontal
    end
    list.Parent = parent
end

--- A grid with a gap token on both axes; the caller sets CellSize.
function Widgets.grid(parent: Instance, gap: number): UIGridLayout
    assert(gap > 0, "Widgets.grid: the gap must be a spacing token above 0 (cells would touch)")
    local grid = Instance.new("UIGridLayout")
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.CellPadding = UDim2.fromOffset(gap, gap)
    grid.Parent = parent
    return grid
end

--- A text label. `sizeKey` is a key of theme.textSize, `colorHex` a palette entry.
function Widgets.label(
    parent: Instance,
    theme: Theme,
    name: string,
    text: string,
    sizeKey: "caption" | "body" | "title",
    colorHex: string
): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Font = Widgets.font(theme.font)
    label.Text = text
    label.TextSize = theme.textSize[sizeKey]
    label.TextColor3 = Widgets.color(colorHex)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Size = UDim2.new(1, 0, 0, theme.textSize[sizeKey])
    label.AutomaticSize = Enum.AutomaticSize.Y
    label.Parent = parent
    return label
end

--- A button at least as tall as the touch floor at the current UIScale. `onActivated` runs on
--- touch, click or gamepad/keyboard activation (Activated covers all of them).
function Widgets.button(
    parent: Instance,
    theme: Theme,
    name: string,
    text: string,
    heightPoints: number,
    onActivated: () -> ()
): TextButton
    local button = Instance.new("TextButton")
    button.Name = name
    button.AutoButtonColor = true
    button.Font = Widgets.font(theme.font)
    button.Text = text
    button.TextSize = theme.textSize.body
    button.TextColor3 = Widgets.color(theme.palette.onAccent)
    button.Size = UDim2.new(1, 0, 0, heightPoints)
    decorate(button, theme, theme.palette.accent)
    button.Activated:Connect(onActivated)
    button.Parent = parent
    return button
end

--- Greys a button out and stops it from reacting.
function Widgets.setEnabled(button: TextButton, theme: Theme, enabled: boolean)
    button.Active = enabled
    button.AutoButtonColor = enabled
    button.BackgroundColor3 =
        Widgets.color(if enabled then theme.palette.accent else theme.palette.surfaceRaised)
    button.TextColor3 =
        Widgets.color(if enabled then theme.palette.onAccent else theme.palette.textMuted)
end

return Widgets
