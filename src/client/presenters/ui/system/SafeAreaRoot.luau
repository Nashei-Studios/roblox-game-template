--!strict
--[[
    SafeAreaRoot: the ScreenGui every game UI goes under. By construction it
    - uses ScreenInsets = CoreUISafeInsets (clear of the notch, rounded corners and the top bar),
    - applies the root UIScale from the breakpoint policy (never below 1, 1 on phones),
    - insets a `content` frame by the design margin, so a child laid out at scale 0..1 can never
      touch an edge or sit under the thumbstick-free border,
    - never resets on spawn, and keeps a stable DisplayOrder per layer.
    Children go in `content` (HUD, menus) or `overlay` (toasts, tooltips: same safe frame, above).
]]

local UiEnv = require(script.Parent.UiEnv)

export type Root = {
    -- nil when built with `layers` (a story frame).
    gui: ScreenGui?,
    -- Full safe frame, inset by the design margin: lay HUD and menus here.
    content: Frame,
    -- Same rectangle, drawn above content: toasts and tooltips.
    overlay: Frame,
    scaler: UIScale,
    -- Re-applies scale and margin for a new environment (viewport change).
    apply: (self: Root, env: UiEnv.UiEnv) -> (),
    destroy: (self: Root) -> (),
}

local SafeAreaRoot = {}

local function layer(parent: Instance, name: string, order: number): Frame
    local frame = Instance.new("Frame")
    frame.Name = name
    frame.BackgroundTransparency = 1
    frame.Size = UDim2.fromScale(1, 1)
    frame.ZIndex = order
    frame.Parent = parent
    return frame
end

--- The scaled frame with its content and overlay layers, inside any parent. Stories use this
--- directly on a fixed-size frame; `new` wraps it in the ScreenGui.
function SafeAreaRoot.layers(parent: Instance, env: UiEnv.UiEnv): Root
    -- A UIScale on the ScreenGui itself would make scale-sized children overflow the screen. The
    -- scaled frame is 1/scale of the screen and the UIScale grows it back to exactly the screen.
    local scaled = Instance.new("Frame")
    scaled.Name = "Scaled"
    scaled.BackgroundTransparency = 1
    scaled.Parent = parent
    local scaler = Instance.new("UIScale")
    scaler.Name = "RootScale"
    scaler.Parent = scaled

    local content = layer(scaled, "Content", 1)
    local overlay = layer(scaled, "Overlay", 2)
    local contentPadding = Instance.new("UIPadding")
    contentPadding.Parent = content
    local overlayPadding = Instance.new("UIPadding")
    overlayPadding.Parent = overlay

    local self = {} :: Root
    self.content = content
    self.overlay = overlay
    self.scaler = scaler

    function self.apply(_self: Root, newEnv: UiEnv.UiEnv)
        scaler.Scale = newEnv.scale
        scaled.Size = UDim2.fromScale(1 / newEnv.scale, 1 / newEnv.scale)
        local margin = UDim.new(0, newEnv.margin)
        for _, padding in { contentPadding, overlayPadding } do
            padding.PaddingTop = margin
            padding.PaddingBottom = margin
            padding.PaddingLeft = margin
            padding.PaddingRight = margin
        end
    end

    function self.destroy(_self: Root)
        scaled:Destroy()
    end

    self:apply(env)
    return self
end

--- `parent` is PlayerGui. `displayOrder` separates ScreenGuis (HUD below modals below toasts).
function SafeAreaRoot.new(
    parent: Instance,
    name: string,
    displayOrder: number,
    env: UiEnv.UiEnv
): Root
    local gui = Instance.new("ScreenGui")
    gui.Name = name
    gui.ResetOnSpawn = false
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = displayOrder
    local root = SafeAreaRoot.layers(gui, env)
    root.gui = gui
    local innerDestroy = root.destroy
    function root.destroy(self: Root)
        innerDestroy(self)
        gui:Destroy()
    end
    gui.Parent = parent
    return root
end

return SafeAreaRoot
