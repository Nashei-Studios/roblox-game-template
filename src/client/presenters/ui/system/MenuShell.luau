--!strict
--[[
    MenuShell: the modal window every menu uses. It is a kit "menu.shell" piece (Studded native
    first) or a plain panel with the same parts, wrapped by what a menu always needs and always
    forgets:
    - a full-screen backdrop that dims the world, SWALLOWS input (Active) and closes on tap,
    - a size from the breakpoint policy (screen fractions capped by an aspect ratio, so it never
      covers a whole phone and never stretches on a wide window),
    - a close button of at least 44 px inside the safe frame,
    - gamepad focus: selection moves to the close button when it opens and returns to the previous
      object when it closes,
    - open/close that animates GroupTransparency and a UIScale only (reduced motion skips both).
    A menu binds its rows to `body` and never builds its own chrome.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Breakpoints = require(Shared.features.uisystem.Breakpoints)
local Atoms = require(script.Parent.Atoms)
local DevGuard = require(script.Parent.DevGuard)
local UiEnv = require(script.Parent.UiEnv)

export type Options = {
    id: string,
    title: string,
    kind: Breakpoints.MenuKind,
    onClose: () -> (),
    reducedMotion: (() -> boolean)?,
}

export type Shell = {
    id: string,
    -- The backdrop plus window; parent it under SafeAreaRoot.content.
    root: Frame,
    window: GuiObject,
    title: TextLabel,
    close: TextButton,
    -- Where the menu puts its rows.
    body: GuiObject,
    setVisible: (self: Shell, visible: boolean) -> (),
    -- Re-sizes the window for a new environment.
    resize: (self: Shell, env: UiEnv.UiEnv) -> (),
}

local OPEN_FROM_SCALE = 0.94

local MenuShell = {}

local function plainWindow(
    env: UiEnv.UiEnv,
    options: Options,
    parent: Instance
): (CanvasGroup, TextLabel, TextButton, Frame)
    local tokens = env.tokens
    local window = Instance.new("CanvasGroup")
    window.Name = "Window"
    window.BackgroundColor3 = Atoms.color(tokens.palette.surface)
    window.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, tokens.radius.lg)
    corner.Parent = window
    window.Parent = parent

    local header = Instance.new("Frame")
    header.Name = "Top"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, 0, 0, tokens.touchMin + 2 * tokens.spacing.sm)
    header.Parent = window
    Atoms.pad(header, tokens, "sm")

    local close = Instance.new("TextButton")
    close.Name = "CloseButton"
    close.Text = "X"
    close.Font = Atoms.font(tokens.font)
    close.TextColor3 = Atoms.color(tokens.palette.textPrimary)
    close.BackgroundColor3 = Atoms.color(tokens.palette.danger)
    close.AnchorPoint = Vector2.new(1, 0.5)
    close.Position = UDim2.fromScale(1, 0.5)
    close.Size = UDim2.fromOffset(tokens.touchMin, tokens.touchMin)
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, tokens.radius.md)
    closeCorner.Parent = close
    Atoms.fitText(close, tokens, tokens.type.title)
    close.Parent = header

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.BackgroundTransparency = 1
    title.Font = Atoms.font(tokens.font)
    title.Text = options.title
    title.TextColor3 = Atoms.color(tokens.palette.textPrimary)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Size = UDim2.new(1, -(tokens.touchMin + tokens.spacing.sm), 1, 0)
    Atoms.fitText(title, tokens, tokens.type.title)
    title.Parent = header

    local body = Instance.new("Frame")
    body.Name = "Container"
    body.BackgroundTransparency = 1
    body.Position = UDim2.fromOffset(0, header.Size.Y.Offset)
    body.Size = UDim2.new(1, 0, 1, -header.Size.Y.Offset)
    body.Parent = window
    return window, title, close, body
end

--- Builds a menu shell under `parent` (usually SafeAreaRoot.content). Hidden until shown.
function MenuShell.new(env: UiEnv.UiEnv, parent: Instance, options: Options): Shell
    local tokens = env.tokens
    local root = Instance.new("Frame")
    root.Name = `Menu_{options.id}`
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Visible = false
    root.Parent = parent

    -- The backdrop is a button so it takes input; tapping outside the window closes the menu.
    local backdrop = Instance.new("TextButton")
    backdrop.Name = "Backdrop"
    backdrop.Text = ""
    backdrop.AutoButtonColor = false
    backdrop.Active = true
    backdrop.BackgroundColor3 = Atoms.color(tokens.palette.scrim)
    backdrop.BackgroundTransparency = 0.45
    backdrop.BorderSizePixel = 0
    backdrop.Size = UDim2.fromScale(1, 1)
    backdrop.ZIndex = 1
    backdrop.Selectable = false
    Atoms.touchFloor(backdrop, tokens)
    backdrop.Parent = root
    backdrop.Activated:Connect(options.onClose)

    local window: GuiObject
    local title: TextLabel
    local close: TextButton
    local body: GuiObject
    local piece = env.skin:cloneSlot("menu.shell")
    if piece ~= nil and piece:IsA("GuiObject") then
        window = piece
        title = env.skin:part(piece, "menu.shell", "title") :: TextLabel
        close = env.skin:part(piece, "menu.shell", "close") :: TextButton
        body = env.skin:part(piece, "menu.shell", "body") :: GuiObject
        title.Text = options.title
        piece.Visible = true
        piece.Parent = root
    else
        local plainWindowFrame, plainTitle, plainClose, plainBody = plainWindow(env, options, root)
        window, title, close, body = plainWindowFrame, plainTitle, plainClose, plainBody
    end
    window.Name = "Window"
    window.ZIndex = 2
    window.AnchorPoint = Vector2.new(0.5, 0.5)
    window.Position = UDim2.fromScale(0.5, 0.5)
    window.Active = true
    close.Activated:Connect(options.onClose)

    local scale = Instance.new("UIScale")
    scale.Parent = window

    local self = {} :: Shell
    self.id = options.id
    self.root = root
    self.window = window
    self.title = title
    self.close = close
    self.body = body

    local previousSelection: GuiObject? = nil

    function self.resize(_self: Shell, newEnv: UiEnv.UiEnv)
        local box = Breakpoints.menuBox(options.kind, newEnv.deviceClass, newEnv.viewport)
        window.Size = UDim2.fromScale(box.widthScale, box.heightScale)
        local aspect: UIAspectRatioConstraint = window:FindFirstChildOfClass(
            "UIAspectRatioConstraint"
        ) or Instance.new("UIAspectRatioConstraint")
        aspect.AspectType = Enum.AspectType.FitWithinMaxSize
        aspect.DominantAxis = Enum.DominantAxis.Width
        aspect.AspectRatio = box.aspect
        aspect.Parent = window
    end

    function self.setVisible(_self: Shell, visible: boolean)
        local reduced = options.reducedMotion ~= nil and options.reducedMotion()
        if visible then
            previousSelection = GuiService.SelectedObject
            root.Visible = true
            if not reduced then
                scale.Scale = OPEN_FROM_SCALE
                TweenService:Create(
                    scale,
                    TweenInfo.new(tokens.motionSeconds, Enum.EasingStyle.Quad),
                    { Scale = 1 }
                ):Play()
            else
                scale.Scale = 1
            end
            GuiService.SelectedObject = close
        else
            root.Visible = false
            if GuiService.SelectedObject == close or GuiService.SelectedObject == nil then
                GuiService.SelectedObject = previousSelection
            end
        end
    end

    self:resize(env)
    DevGuard.verify(root, `MenuShell {options.id}`)
    return self
end

return MenuShell
