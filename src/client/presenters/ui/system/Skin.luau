--!strict
--[[
    The skin: a kit adapter bound to the kit's Instance tree. Components ask for a SLOT, never a
    kit path. `cloneSlot` returns a clone of the kit piece with only structural fixups (touch
    floor, text fit, scroller canvas and padding): it never re-tints, never touches a UIStroke
    Thickness or StrokeSizingMode (kit-native rule). It returns nil when the kit does not cover
    the slot, and the component then draws its plain piece from the tokens.

    `Skin.new` verifies the adapter against the tree and raises with every missing piece, so a
    kit update that moves a part fails at boot with a sentence, not as a nil index in a menu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local KitAdapter = require(Shared.features.uisystem.KitAdapter)
local Tokens = require(Shared.features.uisystem.Tokens)
local Atoms = require(script.Parent.Atoms)

export type Skin = {
    adapter: KitAdapter.KitAdapter,
    tokens: Tokens.Tokens,
    covers: (self: Skin, slot: KitAdapter.Slot) -> boolean,
    -- A clone of the kit piece for a slot, fixed up structurally, or nil when not covered.
    cloneSlot: (self: Skin, slot: KitAdapter.Slot) -> Instance?,
    -- The named part of a cloned piece, by the adapter's part map.
    part: (self: Skin, piece: Instance, slot: KitAdapter.Slot, partName: string) -> Instance,
    -- Like `part`, but nil when the adapter does not map that optional part.
    optionalPart: (
        self: Skin,
        piece: Instance,
        slot: KitAdapter.Slot,
        partName: string
    ) -> Instance?,
}

local SkinModule = {}

local function pathExists(root: Instance, path: string): boolean
    local current: Instance? = root
    for part in string.gmatch(path, "[^/]+") do
        if current == nil then
            return false
        end
        current = current:FindFirstChild(part)
    end
    return current ~= nil
end

local function fixups(piece: Instance, tokens: Tokens.Tokens)
    local all: { Instance } = { piece }
    for _, descendant in piece:GetDescendants() do
        table.insert(all, descendant)
    end
    for _, instance in all do
        if instance:IsA("GuiButton") then
            Atoms.touchFloor(instance, tokens)
        end
        -- Spacing the kit left at 0 is a bug on a phone (rule UI-LIST-PADDING / UI-GRID-PADDING).
        if instance:IsA("UIListLayout") and instance.Padding == UDim.new(0, 0) then
            instance.Padding = UDim.new(0, tokens.spacing.sm)
        elseif instance:IsA("UIGridLayout") then
            local cell = instance.CellPadding
            local gap = tokens.spacing.sm
            instance.CellPadding = UDim2.fromOffset(
                if cell.X.Offset <= 0 and cell.X.Scale <= 0 then gap else cell.X.Offset,
                if cell.Y.Offset <= 0 and cell.Y.Scale <= 0 then gap else cell.Y.Offset
            )
        end
        if instance:IsA("TextLabel") or instance:IsA("TextButton") then
            if instance.Text ~= "" then
                Atoms.fitText(instance, tokens, nil)
            end
        elseif instance:IsA("ScrollingFrame") then
            if instance.AutomaticCanvasSize == Enum.AutomaticSize.None then
                instance.AutomaticCanvasSize = Enum.AutomaticSize.Y
                instance.CanvasSize = UDim2.new()
            end
            if instance:FindFirstChildOfClass("UIPadding") == nil then
                Atoms.pad(instance, tokens, tokens.defaults.cardPad)
            end
        end
    end
end

--- `kitRoot` is the ScreenGui (or Folder) that holds the kit tree, nil for the plain adapter.
function SkinModule.new(
    adapter: KitAdapter.KitAdapter,
    kitRoot: Instance?,
    tokens: Tokens.Tokens
): Skin
    local own = KitAdapter.validate(adapter)
    if #own > 0 then
        error(`UI adapter is invalid:\n{table.concat(own, "\n")}`, 2)
    end
    if kitRoot ~= nil then
        local missing = KitAdapter.verify(adapter, function(path: string): boolean
            return pathExists(kitRoot, path)
        end)
        if #missing > 0 then
            error(`UI kit does not match its adapter:\n{table.concat(missing, "\n")}`, 2)
        end
    elseif next(adapter.slots) ~= nil then
        error(`UI adapter "{adapter.id}" covers slots but no kit tree was given`, 2)
    end

    local self = {} :: Skin
    self.adapter = adapter
    self.tokens = tokens

    function self.covers(_self: Skin, slot: KitAdapter.Slot): boolean
        return adapter.slots[slot] ~= nil and kitRoot ~= nil
    end

    function self.cloneSlot(_self: Skin, slot: KitAdapter.Slot): Instance?
        local binding = adapter.slots[slot]
        if binding == nil or kitRoot == nil then
            return nil
        end
        local source: Instance = kitRoot
        for part in string.gmatch(binding.path, "[^/]+") do
            source = source:FindFirstChild(part) :: Instance
        end
        local clone = source:Clone()
        local clearPaths: { string } = binding.clear or {}
        for _, dotPath in clearPaths do
            local container = Atoms.find(clone, dotPath)
            for _, child in container:GetChildren() do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
        end
        fixups(clone, tokens)
        return clone
    end

    function self.part(
        _self: Skin,
        piece: Instance,
        slot: KitAdapter.Slot,
        partName: string
    ): Instance
        local binding = adapter.slots[slot]
        assert(binding ~= nil, `slot {slot} is not covered by {adapter.id}`)
        local dotPath = binding.parts[partName]
        assert(dotPath ~= nil, `slot {slot} has no part "{partName}"`)
        return Atoms.find(piece, dotPath)
    end

    function self.optionalPart(
        _self: Skin,
        piece: Instance,
        slot: KitAdapter.Slot,
        partName: string
    ): Instance?
        local binding = adapter.slots[slot]
        if binding == nil or binding.parts[partName] == nil then
            return nil
        end
        return Atoms.find(piece, binding.parts[partName])
    end

    return self
end

return SkinModule
