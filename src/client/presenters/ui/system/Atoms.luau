--!strict
--[[
    Atoms of the UI system: the few Instance recipes every primitive and component is made of
    (colour, font, padding from a token, a fitted text, a touch-safe size). They take token KEYS,
    never numbers, so a spacing value off the scale cannot be written. Engine code: excluded from
    the line-coverage gate, kept thin. UNVERIFIED in the engine until a person reviews the UI Labs
    stories (docs/ui-system.md).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tokens = require(Shared.features.uisystem.Tokens)

export type Tokens = Tokens.Tokens

local Atoms = {}

--- Color3 from a palette entry.
function Atoms.color(hex: string): Color3
    return Color3.fromHex(hex)
end

--- Hex of a palette key. The single cast lives here so call sites stay checked by key name.
function Atoms.hex(tokens: Tokens, key: string): string
    local hex = Tokens.paletteMap(tokens.palette)[key]
    assert(hex ~= nil, `unknown palette key "{key}"`)
    return hex
end

--- A Font enum member by name, falling back to the default UI font.
function Atoms.font(name: string): Enum.Font
    for _, item in Enum.Font:GetEnumItems() do
        if item.Name == name then
            return item
        end
    end
    warn(`ui tokens font "{name}" is not an Enum.Font member; using the default font`)
    return Enum.Font.BuilderSans
end

--- UIPadding from one token key on all four sides.
function Atoms.pad(parent: Instance, tokens: Tokens, key: Tokens.SpacingKey): UIPadding
    local points = Tokens.space(tokens, key)
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, points)
    padding.PaddingBottom = UDim.new(0, points)
    padding.PaddingLeft = UDim.new(0, points)
    padding.PaddingRight = UDim.new(0, points)
    padding.Parent = parent
    return padding
end

--- A list layout whose gap is a token key (never zero: the scale starts above 0).
function Atoms.list(
    parent: Instance,
    tokens: Tokens,
    key: Tokens.SpacingKey,
    horizontal: boolean
): UIListLayout
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, Tokens.space(tokens, key))
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.FillDirection = if horizontal
        then Enum.FillDirection.Horizontal
        else Enum.FillDirection.Vertical
    list.Parent = parent
    return list
end

--- Guarantees the touch floor on a tappable whatever the kit size: a UISizeConstraint minimum.
function Atoms.touchFloor(target: GuiObject, tokens: Tokens)
    local limit: UISizeConstraint = target:FindFirstChildOfClass("UISizeConstraint")
        or Instance.new("UISizeConstraint")
    limit.MinSize = Vector2.new(
        math.max(limit.MinSize.X, tokens.touchMin),
        math.max(limit.MinSize.Y, tokens.touchMin)
    )
    limit.Parent = target
end

local function sizeBounds(label: Instance, tokens: Tokens, maxPoints: number?)
    local limit: UITextSizeConstraint = label:FindFirstChildOfClass("UITextSizeConstraint")
        or Instance.new("UITextSizeConstraint")
    limit.MinTextSize = tokens.text.min
    limit.MaxTextSize = math.max(maxPoints or tokens.text.max, tokens.text.min)
    limit.Parent = label
end

--- Makes a text fit its box: scaled between the token bounds, wrapped, truncated at the end.
--- Every label whose text can change goes through this (rule UI-TEXT-FIT).
function Atoms.fitText(label: TextLabel | TextButton, tokens: Tokens, maxPoints: number?)
    if label:IsA("TextLabel") then
        label.TextScaled = true
        label.TextTruncate = Enum.TextTruncate.AtEnd
        label.TextWrapped = true
    elseif label:IsA("TextButton") then
        label.TextScaled = true
        label.TextTruncate = Enum.TextTruncate.AtEnd
    end
    sizeBounds(label, tokens, maxPoints)
end

--- A plain text label for a type key. Height is `lines` lines of the type size plus line gap.
function Atoms.label(
    parent: Instance,
    tokens: Tokens,
    name: string,
    text: string,
    typeKey: Tokens.TypeKey,
    colorHex: string,
    lines: number?
): TextLabel
    local size = Tokens.typeSize(tokens, typeKey)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.Font = Atoms.font(tokens.font)
    label.Text = text
    label.TextColor3 = Atoms.color(colorHex)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Size = UDim2.new(1, 0, 0, math.ceil(size * 1.4) * (lines or 1))
    Atoms.fitText(label, tokens, size)
    label.Parent = parent
    return label
end

--- A rounded plain panel. `fill` is a palette key. Used only by pieces a kit does not cover.
function Atoms.panel(
    parent: Instance,
    tokens: Tokens,
    name: string,
    fill: string,
    radiusKey: Tokens.RadiusKey
): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundColor3 = Atoms.color(fill)
    frame.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Tokens.radius(tokens, radiusKey))
    corner.Parent = frame
    frame.Parent = parent
    return frame
end

--- The descendant at a dot path; a missing piece is a loud error that names it.
function Atoms.find(root: Instance, dotPath: string): Instance
    local current: Instance = root
    for part in string.gmatch(dotPath, "[^.]+") do
        local child = current:FindFirstChild(part)
        if child == nil then
            error(`UI piece "{root.Name}" has no "{dotPath}" (missing "{part}")`, 2)
        end
        current = child
    end
    return current
end

return Atoms
