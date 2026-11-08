--!strict
--[[
    The environment every component is built against: tokens, skin, device class, root scale and
    usable rectangle. Built once per ScreenGui by SafeAreaRoot and refreshed when the viewport
    changes. Components read it, never GuiService or the camera, so a story can hand them any
    fake viewport (844x390, 667x375, 1327x496, 1920x1080) and get the real layout.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage.Shared
local Breakpoints = require(Shared.features.uisystem.Breakpoints)
local SafeArea = require(Shared.features.uisystem.SafeArea)
local Tokens = require(Shared.features.uisystem.Tokens)
local Skin = require(script.Parent.Skin)

export type UiEnv = {
    tokens: Tokens.Tokens,
    skin: Skin.Skin,
    viewport: Breakpoints.Viewport,
    deviceClass: Tokens.DeviceClass,
    -- Root UIScale: >= 1, 1 on phones.
    scale: number,
    -- Margin from the safe area in design px.
    margin: number,
    -- Usable rectangle in DESIGN px (viewport / scale minus margin).
    usable: SafeArea.Rect,
    -- Closes the open menu: wired by the menu controller, used by the modal backdrop.
    onBack: (() -> ())?,
}

local UiEnvModule = {}

--- Builds the environment for a viewport. `isConsole` defaults to GuiService:IsTenFootInterface.
function UiEnvModule.new(
    tokens: Tokens.Tokens,
    skin: Skin.Skin,
    viewport: Breakpoints.Viewport,
    isConsole: boolean?
): UiEnv
    local problems = Tokens.validate(tokens)
    if #problems > 0 then
        error(`UI tokens are invalid:\n{table.concat(problems, "\n")}`, 2)
    end
    local console = if isConsole == nil then GuiService:IsTenFootInterface() else isConsole
    local deviceClass: Tokens.DeviceClass = Breakpoints.classify(viewport, console)
    local scale = Breakpoints.uiScale(deviceClass, viewport)
    local margin = Breakpoints.safeMargin(deviceClass, viewport, tokens)
    local usable = SafeArea.usable(
        viewport.width / scale,
        viewport.height / scale,
        { top = 0, left = 0, bottom = 0, right = 0 },
        margin
    )
    return {
        tokens = tokens,
        skin = skin,
        viewport = viewport,
        deviceClass = deviceClass,
        scale = scale,
        margin = margin,
        usable = usable,
        onBack = nil,
    }
end

return UiEnvModule
