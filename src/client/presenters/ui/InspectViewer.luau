--!strict
--[[
    Client presenter of the InspectView mold (ADR 0060): a modal that shows one item in 3D.
    A dim backdrop (a tap outside the panel closes), a panel with the item name, its level badge and
    a ViewportFrame in the rarity frame color, and a close X. Everything the player can do is a state
    change of the pure `InspectView` module; this file only listens, paints and cleans up.

    The ViewportFrame and its WorldModel exist ONLY while the viewer is open: `close` destroys the
    whole ScreenGui, so the WorldModel count in PlayerGui is 0, 1, 0 (acceptance of #125). The model
    comes from the ModelSource port (the game's own builder), built when the viewer opens and never
    before. Input: drag (mouse or touch), wheel and pinch on the viewport, the right stick and the
    triggers through a Heartbeat poll, Escape and the pad back button through ContextActionService.
    Engine code, excluded from the line-coverage gate and kept thin. UNVERIFIED until a person checks
    it in Studio at 568x320, 844x390 and 1327x472.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local InspectView = require(Shared.features.inspect.InspectView)
local ItemIcon = require(Shared.features.ui.ItemIcon)
local ModelSource = require(Shared.ports.ModelSource)
local Tokens = require(Shared.features.uisystem.Tokens)
local Atoms = require(script.Parent.system.Atoms)
local UiEnv = require(script.Parent.system.UiEnv)
local InputSchemeWatcher = require(script.Parent.InputSchemeWatcher)

export type Deps = {
    config: InspectView.Config,
    env: UiEnv.UiEnv,
    source: ModelSource.ModelSource,
    watcher: InputSchemeWatcher.Watcher,
    -- Studs between the camera and the model centre at zoom 1, for a model of about 4 studs.
    baseDistance: number,
    -- DisplayOrder of the ScreenGui: above the menu that opened it.
    displayOrder: number,
    -- Text of the closed-by-pad hint prefix ("B") is drawn from the registry hint; this is the
    -- accessibility label of the close button.
    closeText: string,
}

export type Viewer = {
    -- Opens the viewer on an item. `spec` supplies the name, rarity frame color and level badge.
    open: (self: Viewer, spec: ItemIcon.Spec) -> boolean,
    close: (self: Viewer) -> (),
    isOpen: (self: Viewer) -> boolean,
    destroy: (self: Viewer) -> (),
}

local ACTION_CLOSE = "InspectViewerClose"
local ACTION_STICK = "InspectViewerStick"

local InspectViewer = {}

function InspectViewer.new(deps: Deps): Viewer
    local config = deps.config
    local tokens = deps.env.tokens
    local state = InspectView.closed(config)
    local gui: ScreenGui? = nil
    local camera: Camera? = nil
    local model: Model? = nil
    local connections: { RBXScriptConnection } = {}
    local unsubscribers: { () -> () } = {}
    local stickX, stickY = 0, 0
    local triggerLeft, triggerRight = 0, 0
    local dragInput: InputObject? = nil
    local pinchStartZoom = 1

    local viewer = {} :: Viewer

    local function paint()
        local currentModel, currentCamera = model, camera
        if currentModel == nil or currentCamera == nil then
            return
        end
        local rotation = CFrame.Angles(0, math.rad(state.yaw), 0)
            * CFrame.Angles(math.rad(state.pitch), 0, 0)
        local pivot = currentModel:GetPivot().Position
        currentModel:PivotTo(CFrame.new(pivot) * rotation)
        local distance = InspectView.cameraDistance(state, deps.baseDistance)
        currentCamera.CFrame = CFrame.lookAt(pivot + Vector3.new(0, 0, distance), pivot)
    end

    local function teardown()
        for _, connection in connections do
            connection:Disconnect()
        end
        table.clear(connections)
        for _, unsubscribe in unsubscribers do
            unsubscribe()
        end
        table.clear(unsubscribers)
        ContextActionService:UnbindAction(ACTION_CLOSE)
        ContextActionService:UnbindAction(ACTION_STICK)
        -- Destroying the ScreenGui destroys the ViewportFrame, the WorldModel and the model.
        if gui ~= nil then
            gui:Destroy()
        end
        gui, camera, model, dragInput = nil, nil, nil, nil
        stickX, stickY, triggerLeft, triggerRight = 0, 0, 0, 0
    end

    function viewer.close(_self: Viewer)
        if not state.open then
            return
        end
        state = InspectView.close(config, state)
        teardown()
    end

    function viewer.isOpen(_self: Viewer): boolean
        return state.open
    end

    local function closeKeyAction(
        _name: string,
        inputState: Enum.UserInputState,
        _input: InputObject
    )
        if inputState == Enum.UserInputState.Begin then
            viewer:close()
        end
        return Enum.ContextActionResult.Sink
    end

    local function stickAction(_name: string, _state: Enum.UserInputState, input: InputObject)
        stickX, stickY = input.Position.X, input.Position.Y
        return Enum.ContextActionResult.Sink
    end

    function viewer.open(_self: Viewer, spec: ItemIcon.Spec): boolean
        if state.open then
            viewer:close()
        end
        -- Lazy: nothing was built before this call. A missing model keeps the viewer closed.
        local built = deps.source:build(spec.id)
        if built == nil then
            return false
        end
        state = InspectView.open(config, spec.id)
        model = built

        local newGui = Instance.new("ScreenGui")
        newGui.Name = "InspectViewer"
        newGui.ResetOnSpawn = false
        -- Inside the core UI safe area like the kit menus: on a phone a panel centred on the full
        -- screen put the close button under the Roblox top bar.
        newGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
        newGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        newGui.DisplayOrder = deps.displayOrder
        local player = Players.LocalPlayer
        newGui.Parent = player:WaitForChild("PlayerGui")
        gui = newGui

        local gap = Tokens.space(tokens, "sm")
        local pad = Tokens.space(tokens, "md")

        -- Backdrop: a tap anywhere outside the panel closes. The panel is its SIBLING, drawn above
        -- it: a click on a descendant of a GuiButton fires that button's Activated, so a panel parented
        -- inside the backdrop closed the viewer on the first drag in the viewport.
        local backdrop = Instance.new("TextButton")
        backdrop.Name = "Backdrop"
        backdrop.Text = ""
        backdrop.AutoButtonColor = false
        backdrop.Size = UDim2.fromScale(1, 1)
        backdrop.BackgroundColor3 = Atoms.color(tokens.palette.background)
        backdrop.BackgroundTransparency = 0.35
        backdrop.BorderSizePixel = 0
        backdrop.ZIndex = 0
        backdrop.Parent = newGui
        table.insert(
            connections,
            backdrop.Activated:Connect(function()
                viewer:close()
            end)
        )

        local panel = Atoms.panel(newGui, tokens, "Panel", tokens.palette.surface, "lg")
        panel.ZIndex = backdrop.ZIndex + 1
        panel.AnchorPoint = Vector2.new(0.5, 0.5)
        panel.Position = UDim2.fromScale(0.5, 0.5)
        -- Wide on a phone in landscape (568x320), capped on a large screen.
        panel.Size = UDim2.fromScale(0.8, 0.86)
        panel.Active = true
        local sizeCap = Instance.new("UISizeConstraint")
        sizeCap.MaxSize = Vector2.new(720, 520)
        sizeCap.Parent = panel
        local stroke = Instance.new("UIStroke")
        stroke.Name = "RarityFrame"
        stroke.Thickness = 3
        stroke.Color = Atoms.color(spec.fx.frameHex)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = panel
        Atoms.pad(panel, tokens, "md")

        -- Header: name and level on the left, the close X on the right.
        local headerHeight =
            math.max(tokens.touchMin, math.ceil(Tokens.typeSize(tokens, "title") * 1.4))
        local header = Instance.new("Frame")
        header.Name = "Header"
        header.BackgroundTransparency = 1
        header.Size = UDim2.new(1, 0, 0, headerHeight)
        header.Parent = panel

        local close = Instance.new("TextButton")
        close.Name = InspectView.CLOSE_ID
        close.Text = deps.closeText
        close.Font = Atoms.font(tokens.font)
        close.AutoButtonColor = true
        close.BackgroundColor3 = Atoms.color(tokens.palette.surfaceRaised)
        close.TextColor3 = Atoms.color(tokens.palette.textPrimary)
        close.BorderSizePixel = 0
        close.AnchorPoint = Vector2.new(1, 0)
        close.Position = UDim2.fromScale(1, 0)
        close.Size = UDim2.fromOffset(tokens.touchMin, tokens.touchMin)
        Atoms.fitText(close, tokens, Tokens.typeSize(tokens, "title"))
        Atoms.touchFloor(close, tokens)
        close.Parent = header
        table.insert(
            connections,
            close.Activated:Connect(function()
                viewer:close()
            end)
        )

        local titleWidth = UDim2.new(1, -(tokens.touchMin + gap), 0, headerHeight)
        local title =
            Atoms.label(header, tokens, "Name", spec.name, "title", tokens.palette.textPrimary, 1)
        title.Size = UDim2.new(
            titleWidth.X.Scale,
            titleWidth.X.Offset,
            0,
            math.ceil(Tokens.typeSize(tokens, "title") * 1.4)
        )
        local level = Atoms.label(
            header,
            tokens,
            "Level",
            spec.badge or "",
            "body",
            tokens.palette.textMuted,
            1
        )
        level.Position = UDim2.fromOffset(0, title.Size.Y.Offset)
        level.Size = UDim2.new(titleWidth.X.Scale, titleWidth.X.Offset, 0, level.Size.Y.Offset)
        level.Visible = spec.badge ~= nil

        -- The viewport fills the rest of the panel below the header.
        local newViewport = Instance.new("ViewportFrame")
        newViewport.Name = "Viewport"
        newViewport.BackgroundColor3 = Atoms.color(spec.fx.backgroundBottomHex)
        newViewport.BorderSizePixel = 0
        newViewport.Active = true
        newViewport.Position = UDim2.fromOffset(0, headerHeight + gap)
        newViewport.Size = UDim2.new(1, 0, 1, -(headerHeight + gap + pad))
        newViewport.Ambient = Color3.fromRGB(150, 150, 150)
        newViewport.LightColor = Color3.fromRGB(255, 255, 255)
        newViewport.Parent = panel
        local viewportCorner = Instance.new("UICorner")
        viewportCorner.CornerRadius = UDim.new(0, Tokens.radius(tokens, "md"))
        viewportCorner.Parent = newViewport

        local worldModel = Instance.new("WorldModel")
        worldModel.Parent = newViewport
        built.Parent = worldModel
        built:PivotTo(CFrame.new(0, 0, 0))
        local newCamera = Instance.new("Camera")
        newCamera.FieldOfView = 40
        newCamera.Parent = newViewport
        newViewport.CurrentCamera = newCamera
        camera = newCamera

        -- Pad hint under the viewport edge when the close button is not the way out.
        local hint = InspectView.hintFor(config.closeKeys, "gamepad")
        if hint ~= nil then
            local hintLabel = Atoms.label(
                newViewport,
                tokens,
                "PadHint",
                hint,
                "caption",
                tokens.palette.textPrimary,
                1
            )
            hintLabel.AnchorPoint = Vector2.new(0, 1)
            hintLabel.Position = UDim2.new(0, gap, 1, -gap)
            hintLabel.Size = UDim2.new(0.4, 0, 0, hintLabel.Size.Y.Offset)
            hintLabel.Visible = deps.watcher.get() == "gamepad"
            table.insert(
                unsubscribers,
                deps.watcher.subscribe(function(scheme: string)
                    hintLabel.Visible = scheme == "gamepad"
                end)
            )
        end

        -- Drag: mouse button 1 or one finger on the viewport.
        table.insert(
            connections,
            newViewport.InputBegan:Connect(function(input: InputObject)
                if
                    input.UserInputType == Enum.UserInputType.MouseButton1
                    or input.UserInputType == Enum.UserInputType.Touch
                then
                    dragInput = input
                end
            end)
        )
        table.insert(
            connections,
            UserInputService.InputChanged:Connect(function(input: InputObject)
                if input == dragInput then
                    state = InspectView.drag(config, state, input.Delta.X, input.Delta.Y)
                    paint()
                elseif input.UserInputType == Enum.UserInputType.MouseWheel then
                    state = InspectView.wheel(config, state, input.Position.Z)
                    paint()
                elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
                    triggerLeft = input.Position.Z
                elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
                    triggerRight = input.Position.Z
                end
            end)
        )
        table.insert(
            connections,
            UserInputService.InputEnded:Connect(function(input: InputObject)
                if input == dragInput then
                    dragInput = nil
                end
            end)
        )
        -- Pinch: the ratio of the gesture scales the zoom the pinch started from.
        table.insert(
            connections,
            newViewport.TouchPinch:Connect(
                function(
                    _points: { Vector2 },
                    scale: number,
                    _velocity: number,
                    pinchState: Enum.UserInputState
                )
                    if pinchState == Enum.UserInputState.Begin then
                        pinchStartZoom = state.zoom
                    else
                        -- The gesture scale is cumulative: apply it to the zoom the pinch began at.
                        local base = table.clone(state)
                        base.zoom = pinchStartZoom
                        state = InspectView.pinch(config, base, 1, scale)
                        paint()
                    end
                end
            )
        )
        -- Stick and triggers are analog: poll them every frame while open.
        table.insert(
            connections,
            RunService.Heartbeat:Connect(function(dt: number)
                if stickX ~= 0 or stickY ~= 0 then
                    state = InspectView.stick(config, state, stickX, stickY, dt)
                end
                if triggerLeft ~= 0 or triggerRight ~= 0 then
                    state = InspectView.triggers(config, state, triggerLeft, triggerRight, dt)
                end
                if stickX ~= 0 or stickY ~= 0 or triggerLeft ~= 0 or triggerRight ~= 0 then
                    paint()
                end
            end)
        )
        -- Escape and the pad back button close; the right stick is sunk so the camera stays put.
        local closeInputs: { Enum.KeyCode } = {}
        for _, keyCode in Enum.KeyCode:GetEnumItems() do
            if table.find(config.closeKeys, keyCode.Name) ~= nil then
                table.insert(closeInputs, keyCode)
            end
        end
        ContextActionService:BindActionAtPriority(
            ACTION_CLOSE,
            closeKeyAction,
            false,
            Enum.ContextActionPriority.High.Value + 1,
            table.unpack(closeInputs)
        )
        ContextActionService:BindActionAtPriority(
            ACTION_STICK,
            stickAction,
            false,
            Enum.ContextActionPriority.High.Value,
            Enum.KeyCode.Thumbstick2
        )

        paint()
        return true
    end

    function viewer.destroy(_self: Viewer)
        viewer:close()
    end

    return viewer
end

return InspectViewer
