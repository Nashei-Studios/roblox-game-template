--!strict
--[[
    InspectView mold: the pure state of a viewer that shows ONE catalog item in 3D and lets the
    player rotate and zoom it. It owns no instance. It decides what the viewer is doing (closed,
    or open on an item with a yaw, a pitch and a zoom), turns every input into a state change
    (mouse or touch drag, wheel, pinch, right stick, triggers), clamps rotation and zoom, says which
    keys close it and how many WorldModels the engine side may hold (0 closed, 1 open). The engine
    side (the game UI) builds the model, paints and listens. Loads under Lune.

    Rotate or orbit: the MODEL turns and the camera stays still (ADR 0060), so the light on the
    model and the framing never change. Every function returns a new state; none mutates its input.
    Decision: docs/adr/0060-inspect-view-mold.md. Issue #125.
]]

local ControlRegistry = require("../ui/ControlRegistry")
local InputScheme = require("../ui/InputScheme")

export type Config = {
    -- Degrees of yaw per pixel of horizontal drag, and of pitch per pixel of vertical drag.
    yawDegreesPerPixel: number,
    pitchDegreesPerPixel: number,
    -- Pitch limits in degrees. The model never turns upside down.
    pitchMin: number,
    pitchMax: number,
    -- Right stick: degrees per second at full deflection, and the deadzone (0..1).
    stickDegreesPerSecond: number,
    stickDeadzone: number,
    -- Zoom is a multiplier of the framing distance: 1 is the default, 2 is twice as close.
    zoomDefault: number,
    zoomMin: number,
    zoomMax: number,
    -- Zoom added per wheel notch (a notch is 1), and zoom per second at full trigger.
    wheelStep: number,
    triggerZoomPerSecond: number,
    triggerDeadzone: number,
    -- Enum.KeyCode names that close the viewer (Escape on keyboard, ButtonB on the pad).
    closeKeys: { string },
    -- Enum.KeyCode names that open the viewer of the focused card (gamepad).
    openKeys: { string },
}

export type State = {
    open: boolean,
    -- Id of the item shown; nil while closed.
    itemId: string?,
    -- Degrees, wrapped to [0, 360).
    yaw: number,
    -- Degrees, clamped to [pitchMin, pitchMax].
    pitch: number,
    zoom: number,
}

-- What the viewer may cost (see PerfBudget.inspect).
export type Budget = {
    maxParts: number,
    maxWorldModels: number,
    maxOpenMs: number,
}

-- A panel rectangle { x, y, width, height } in the same pixel space as a tap point.
export type Rect = { x: number, y: number, width: number, height: number }

local InspectView = {}

InspectView.CLOSE_ID = "InspectClose"
InspectView.OPEN_ID = "InspectOpen"
-- Yaw and pitch a model starts with: a three-quarter view reads better than a flat profile.
InspectView.START_YAW = 25
InspectView.START_PITCH = 12

InspectView.default = {
    yawDegreesPerPixel = 0.5,
    pitchDegreesPerPixel = 0.35,
    pitchMin = -50,
    pitchMax = 60,
    stickDegreesPerSecond = 160,
    stickDeadzone = 0.2,
    zoomDefault = 1,
    zoomMin = 0.7,
    zoomMax = 2.2,
    wheelStep = 0.12,
    triggerZoomPerSecond = 1.2,
    triggerDeadzone = 0.1,
    closeKeys = { "Escape", "ButtonB" },
    openKeys = { "ButtonY" },
} :: Config

--- Problems that make a config invalid; empty when fine.
function InspectView.validate(config: Config): { string }
    local problems: { string } = {}
    if config.yawDegreesPerPixel <= 0 or config.pitchDegreesPerPixel <= 0 then
        table.insert(problems, "inspect: degrees per pixel must be above 0")
    end
    if config.pitchMin >= config.pitchMax or config.pitchMin < -89 or config.pitchMax > 89 then
        table.insert(problems, "inspect: pitchMin < pitchMax, both within -89..89")
    end
    if config.zoomMin <= 0 or config.zoomMin >= config.zoomMax then
        table.insert(problems, "inspect: 0 < zoomMin < zoomMax")
    end
    if config.zoomDefault < config.zoomMin or config.zoomDefault > config.zoomMax then
        table.insert(problems, "inspect: zoomDefault must lie inside zoomMin..zoomMax")
    end
    if
        config.wheelStep <= 0
        or config.triggerZoomPerSecond <= 0
        or config.stickDegreesPerSecond <= 0
    then
        table.insert(
            problems,
            "inspect: wheelStep, triggerZoomPerSecond and stick speed must be above 0"
        )
    end
    if
        config.stickDeadzone < 0
        or config.stickDeadzone >= 1
        or config.triggerDeadzone < 0
        or config.triggerDeadzone >= 1
    then
        table.insert(problems, "inspect: deadzones must be in 0..1 (1 excluded)")
    end
    if #config.closeKeys == 0 then
        table.insert(problems, "inspect: at least one close key (a modal needs a way out)")
    end
    return problems
end

--- Problems of a model and a count against the budget; empty when it fits.
function InspectView.budgetProblems(parts: number, worldModels: number, budget: Budget): { string }
    local problems: { string } = {}
    if parts > budget.maxParts then
        table.insert(problems, `inspect model has {parts} parts, budget is {budget.maxParts}`)
    end
    if worldModels > budget.maxWorldModels then
        table.insert(
            problems,
            `inspect holds {worldModels} WorldModels, budget is {budget.maxWorldModels}`
        )
    end
    return problems
end

local function clamp(value: number, low: number, high: number): number
    return math.max(low, math.min(high, value))
end

-- Stick or trigger value with its deadzone removed and the rest rescaled to 0..1 (sign kept).
local function shaped(value: number, deadzone: number): number
    local magnitude = math.abs(value)
    if magnitude <= deadzone then
        return 0
    end
    local scaled = (math.min(magnitude, 1) - deadzone) / (1 - deadzone)
    return if value < 0 then -scaled else scaled
end

local function with(state: State, yaw: number, pitch: number, zoom: number): State
    return { open = state.open, itemId = state.itemId, yaw = yaw, pitch = pitch, zoom = zoom }
end

--- The closed state: nothing shown, no WorldModel allowed.
function InspectView.closed(config: Config): State
    return {
        open = false,
        itemId = nil,
        yaw = InspectView.START_YAW,
        pitch = InspectView.START_PITCH,
        zoom = config.zoomDefault,
    }
end

--- Opens the viewer on `itemId` with the start framing. Opening while open swaps the item and
--- resets the framing, so a second card never inherits the last rotation.
function InspectView.open(config: Config, itemId: string): State
    local state = InspectView.closed(config)
    state.open = true
    state.itemId = itemId
    return state
end

--- Closes the viewer. Closing a closed viewer is a no-op.
function InspectView.close(config: Config, _state: State): State
    return InspectView.closed(config)
end

--- Back to the start framing, keeping the item open.
function InspectView.reset(config: Config, state: State): State
    if not state.open or state.itemId == nil then
        return state
    end
    return InspectView.open(config, state.itemId)
end

--- Mouse or touch drag of `dx`, `dy` pixels. Drag right turns the model right; drag down tips
--- the top toward the viewer. Ignored while closed.
function InspectView.drag(config: Config, state: State, dx: number, dy: number): State
    if not state.open then
        return state
    end
    local yaw = (state.yaw + dx * config.yawDegreesPerPixel) % 360
    local pitch =
        clamp(state.pitch + dy * config.pitchDegreesPerPixel, config.pitchMin, config.pitchMax)
    return with(state, yaw, pitch, state.zoom)
end

--- Right stick held for `dt` seconds at (x, y), each in -1..1. Stick up tips the top away.
function InspectView.stick(config: Config, state: State, x: number, y: number, dt: number): State
    if not state.open or dt <= 0 then
        return state
    end
    local step = config.stickDegreesPerSecond * dt
    local yaw = (state.yaw + shaped(x, config.stickDeadzone) * step) % 360
    local pitch = clamp(
        state.pitch - shaped(y, config.stickDeadzone) * step,
        config.pitchMin,
        config.pitchMax
    )
    return with(state, yaw, pitch, state.zoom)
end

--- Mouse wheel: `delta` notches, positive when the wheel turns away from the user
--- (InputObject.Position.Z). Wheel up zooms in.
function InspectView.wheel(config: Config, state: State, delta: number): State
    if not state.open then
        return state
    end
    local zoom = clamp(state.zoom + delta * config.wheelStep, config.zoomMin, config.zoomMax)
    return with(state, state.yaw, state.pitch, zoom)
end

--- Pinch: the distance between the two fingers went from `previousDistance` to `distance` pixels.
--- Spreading zooms in by the same ratio. A zero or negative distance is ignored.
function InspectView.pinch(
    config: Config,
    state: State,
    previousDistance: number,
    distance: number
): State
    if not state.open or previousDistance <= 0 or distance <= 0 then
        return state
    end
    local zoom = clamp(state.zoom * (distance / previousDistance), config.zoomMin, config.zoomMax)
    return with(state, state.yaw, state.pitch, zoom)
end

--- Triggers held for `dt` seconds: `right` zooms in, `left` zooms out, each in 0..1.
function InspectView.triggers(
    config: Config,
    state: State,
    left: number,
    right: number,
    dt: number
): State
    if not state.open or dt <= 0 then
        return state
    end
    local net = shaped(right, config.triggerDeadzone) - shaped(left, config.triggerDeadzone)
    local zoom =
        clamp(state.zoom + net * config.triggerZoomPerSecond * dt, config.zoomMin, config.zoomMax)
    return with(state, state.yaw, state.pitch, zoom)
end

--- A tap at a point: closes when it lands outside the panel rectangle, keeps it open inside.
function InspectView.tap(config: Config, state: State, x: number, y: number, panel: Rect): State
    if not state.open then
        return state
    end
    local inside = x >= panel.x
        and x <= panel.x + panel.width
        and y >= panel.y
        and y <= panel.y + panel.height
    return if inside then state else InspectView.close(config, state)
end

--- True when the Enum.KeyCode `keyName` closes the viewer.
function InspectView.isCloseKey(config: Config, keyName: string): boolean
    return table.find(config.closeKeys, keyName) ~= nil
end

--- True when the Enum.KeyCode `keyName` opens the viewer of the focused card.
function InspectView.isOpenKey(config: Config, keyName: string): boolean
    return table.find(config.openKeys, keyName) ~= nil
end

--- How many WorldModels the engine side may hold for this state: 1 open, 0 closed.
function InspectView.worldModelCount(state: State): number
    return if state.open then 1 else 0
end

--- Distance of the camera for a framing distance `baseDistance` (studs) at the current zoom.
function InspectView.cameraDistance(state: State, baseDistance: number): number
    return baseDistance / state.zoom
end

--- Hint text for a scheme from the first matching key name ("ButtonB" -> "B").
function InspectView.hintFor(keys: { string }, scheme: InputScheme.Scheme): string?
    local key = InputScheme.firstKeyFor(keys, scheme)
    return if key ~= nil then InputScheme.keyLabel(key) else nil
end

--- Registers the two controls. The close X is a button on touch and keyboard, and the pad shows
--- "B" in its place; the Inspect button of a card is shown on touch and keyboard, the pad shows "Y".
function InspectView.register(registry: ControlRegistry.Registry, config: Config)
    local padClose = InspectView.hintFor(config.closeKeys, InputScheme.GAMEPAD)
    local padOpen = InspectView.hintFor(config.openKeys, InputScheme.GAMEPAD)
    ControlRegistry.register(registry, {
        id = InspectView.CLOSE_ID,
        purpose = "closes the item viewer; Escape or the pad back button do the same",
        schemes = { InputScheme.TOUCH, InputScheme.KEYBOARD },
        screen = "inspect",
        hints = if padClose ~= nil then { [InputScheme.GAMEPAD] = padClose } else nil,
    })
    ControlRegistry.register(registry, {
        id = InspectView.OPEN_ID,
        purpose = "opens the 3D viewer of the item of this card",
        schemes = { InputScheme.TOUCH, InputScheme.KEYBOARD },
        screen = "card",
        hints = if padOpen ~= nil then { [InputScheme.GAMEPAD] = padOpen } else nil,
    })
end

return InspectView
