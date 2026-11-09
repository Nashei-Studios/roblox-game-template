--!strict
--[[
    Client presenter of the ItemSlots mold (ADR 0055): a row of slot buttons on the bottom HUD rail.
    Each slot is one tap target (a TextButton named "Slot<N>", registered in the ControlRegistry)
    that holds an ItemIconView (image, rarity frame, level or count badge) and a key hint label.
    Positions come from HudRails.plan (pure): the row never overlaps the other rails, the lower
    sides stay free for the Roblox thumbstick and jump button, and slots keep the token gap.
    The hint follows the input scheme live: number key on keyboard, pad glyph on gamepad, none on
    touch. A tap, or the bound key, opens the item panel through the ItemPanel port.
    Engine code, excluded from the line-coverage gate and kept thin. UNVERIFIED until a person
    checks it in Studio at 1920x1080, 844x390, 667x375 and 568x320.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local HudRails = require(Shared.features.uisystem.HudRails)
local ItemPanel = require(Shared.ports.ItemPanel)
local ItemSlots = require(Shared.features.itemslots.ItemSlots)
local Tokens = require(Shared.features.uisystem.Tokens)
local UiConfig = require(Shared.features.ui.UiConfig)
local Atoms = require(script.Parent.system.Atoms)
local DevGuard = require(script.Parent.system.DevGuard)
local UiEnv = require(script.Parent.system.UiEnv)
local InputSchemeWatcher = require(script.Parent.InputSchemeWatcher)
local ItemIconView = require(script.Parent.ItemIconView)

export type Deps = {
    config: ItemSlots.Config,
    -- Theme of the ItemIconView (Config.default.ui.theme).
    theme: UiConfig.Theme,
    watcher: InputSchemeWatcher.Watcher,
    -- Tapping or pressing a slot key calls `open` of this port with the item id.
    panel: ItemPanel.ItemPanel,
    -- Text of the lock tag of the icon (never shown for equipped items, required by the view).
    lockedText: string,
    -- Share of the height the lower sides keep free for the Roblox thumbstick and jump button
    -- on touch devices (HudRailsView uses 0.42).
    touchReserve: number,
}

export type SideRails = { left: number, right: number }

export type View = {
    root: Frame,
    -- Repaints the slots from `ItemSlots.view`.
    render: (self: View, slots: { ItemSlots.SlotView }) -> (),
    -- Places the slots for a (new) environment. `sideRails` is how many tiles the left and right
    -- rails hold, so the row never runs into them. Returns the plan problems.
    layout: (self: View, env: UiEnv.UiEnv, sideRails: SideRails) -> { string },
    destroy: (self: View) -> (),
}

local ItemSlotsView = {}

function ItemSlotsView.new(env: UiEnv.UiEnv, parent: Instance, deps: Deps): View
    local tokens = env.tokens
    local root = Instance.new("Frame")
    root.Name = "ItemSlots"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = parent

    local buttons: { TextButton } = {}
    local icons: { ItemIconView.ItemIconView } = {}
    local hintLabels: { TextLabel } = {}
    local rings: { UIStroke } = {}
    local current: { ItemSlots.SlotView } = {}
    local scheme = deps.watcher.get()
    local pad = Tokens.space(tokens, "xs")

    for index = 1, deps.config.count do
        local button = Instance.new("TextButton")
        button.Name = ItemSlots.slotId(index)
        button.Text = ""
        button.AutoButtonColor = false
        button.BackgroundTransparency = 1
        button.Visible = false
        Atoms.touchFloor(button, tokens)
        button.Parent = root

        local icon = ItemIconView.new({
            theme = deps.theme,
            parent = button,
            name = "Icon",
            lockedText = deps.lockedText,
        })
        icon.root.Size = UDim2.fromScale(1, 1)
        icon.root.Active = false

        -- Selection ring: its own stroke on the button, so the rarity frame is never touched.
        local ring = Instance.new("UIStroke")
        ring.Name = "Selected"
        ring.Thickness = deps.theme.strokeThickness * 3
        ring.Color = Atoms.color(tokens.palette.textPrimary)
        ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        ring.Enabled = false
        ring.Parent = button

        local hint =
            Atoms.label(button, tokens, "Hint", "", "caption", tokens.palette.textPrimary, 1)
        hint.AnchorPoint = Vector2.new(0, 1)
        hint.Position = UDim2.new(0, pad, 1, -pad)
        hint.Size = UDim2.new(0.6, 0, 0, math.ceil(Tokens.typeSize(tokens, "caption") * 1.4))
        hint.ZIndex = 5
        hint.Visible = false

        button.Activated:Connect(function()
            ItemSlots.tap(current, index, deps.panel)
        end)
        buttons[index] = button
        icons[index] = icon
        hintLabels[index] = hint
        rings[index] = ring
    end

    local function showHints()
        for index, hint in hintLabels do
            local text = ItemSlots.hintFor(deps.config, index, scheme)
            hint.Text = text or ""
            hint.Visible = text ~= nil and buttons[index].Visible
        end
    end

    local unsubscribe = deps.watcher.subscribe(function(next: string)
        scheme = next
        showHints()
    end)
    local keyConnection = UserInputService.InputBegan:Connect(
        function(input: InputObject, processed: boolean)
            if processed then
                return
            end
            local index = ItemSlots.indexForKey(deps.config, input.KeyCode.Name)
            if index ~= nil then
                ItemSlots.tap(current, index, deps.panel)
            end
        end
    )

    local view = {} :: View
    view.root = root

    function view.render(_self: View, slots: { ItemSlots.SlotView })
        current = slots
        for index, slot in slots do
            if index <= #buttons then
                if slot.spec ~= nil then
                    icons[index].apply(slot.spec)
                end
                -- An empty slot stays as a dim frame so the row does not jump.
                icons[index].root.BackgroundTransparency = if slot.spec ~= nil then 0 else 0.6
                rings[index].Enabled = slot.selected
            end
        end
        showHints()
    end

    function view.layout(_self: View, newEnv: UiEnv.UiEnv, sideRails: SideRails): { string }
        local plan = HudRails.plan(
            newEnv.usable,
            { left = sideRails.left, right = sideRails.right, bottom = deps.config.count },
            deps.touchReserve,
            newEnv.tokens
        )
        local placedCount = 0
        for _, placed in plan.tiles do
            if placed.rail == "bottom" then
                local button = buttons[placed.index]
                placedCount += 1
                button.Position = UDim2.fromOffset(
                    placed.rect.x - newEnv.usable.x,
                    placed.rect.y - newEnv.usable.y
                )
                button.Size = UDim2.fromOffset(placed.rect.width, placed.rect.height)
                button.Visible = true
            end
        end
        for index = placedCount + 1, #buttons do
            buttons[index].Visible = false
        end
        showHints()
        DevGuard.requireAll(plan.problems)
        return plan.problems
    end

    function view.destroy(_self: View)
        unsubscribe()
        keyConnection:Disconnect()
        for _, icon in icons do
            icon.destroy()
        end
        root:Destroy()
    end

    return view
end

return ItemSlotsView
