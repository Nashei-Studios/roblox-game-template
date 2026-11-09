--!strict
--[[
    UiMotionPlayer: plays the presets of UiMotion (docs/adr/0063) on real instances with
    TweenService. One tween per (instance, property) at a time: a new one cancels the old and
    continues from the CURRENT value, so a menu reopened mid-close or a button released mid-press
    never jumps. Only UIScale.Scale and transparency properties are tweened, never Size, so no
    layout is disturbed (R3 of the UI spec). Reduced motion is resolved by UiMotion.resolve.
]]

local TweenService = game:GetService("TweenService")

local UiMotion = require(game:GetService("ReplicatedStorage").Shared.features.ui.UiMotion)

local UiMotionPlayer = {}

-- Active tween per instance and property; weak keys so a destroyed instance is collected.
local active: { [Instance]: { [string]: Tween } } = setmetatable({}, { __mode = "k" }) :: any

local function tweenInfo(preset: UiMotion.Preset): TweenInfo
    return TweenInfo.new(
        preset.seconds,
        (Enum.EasingStyle :: any)[preset.style],
        (Enum.EasingDirection :: any)[preset.direction]
    )
end

--- Tweens one property to `target`, cancelling the tween already running on it. When `from` is
--- given the property snaps there first (a menu that starts from hidden); otherwise the tween
--- continues from the current value. Returns the tween so a caller can wait on Completed.
function UiMotionPlayer.tween(
    instance: Instance,
    property: string,
    target: number,
    preset: UiMotion.Preset,
    from: number?
): Tween
    local perInstance = active[instance]
    if perInstance == nil then
        perInstance = {}
        active[instance] = perInstance
    end
    local running = (perInstance :: { [string]: Tween })[property]
    if running ~= nil then
        running:Cancel()
    end
    if from ~= nil then
        (instance :: any)[property] = from
    end
    local tween = TweenService:Create(instance, tweenInfo(preset), { [property] = target })
    ;(perInstance :: { [string]: Tween })[property] = tween
    tween:Play()
    return tween
end

--- Plays a preset on a UIScale and, when given, a transparency property of `fadeTarget`
--- ("GroupTransparency", "BackgroundTransparency"...). `snapFrom` starts from the preset's own
--- start values (opening from hidden); false continues from where the instance is now. Returns
--- the longest tween, or nil when reduced motion leaves nothing to play.
function UiMotionPlayer.play(
    name: string,
    reducedMotion: boolean,
    scale: UIScale?,
    fadeTarget: Instance?,
    fadeProperty: string?,
    snapFrom: boolean
): Tween?
    local preset = UiMotion.resolve(name, reducedMotion)
    if preset == nil then
        return nil
    end
    local last: Tween? = nil
    if scale ~= nil and preset.scaleTo ~= nil then
        last = UiMotionPlayer.tween(
            scale,
            "Scale",
            preset.scaleTo,
            preset,
            if snapFrom then preset.scaleFrom else nil
        )
    end
    if fadeTarget ~= nil and fadeProperty ~= nil and preset.fadeTo ~= nil then
        last = UiMotionPlayer.tween(
            fadeTarget,
            fadeProperty,
            preset.fadeTo,
            preset,
            if snapFrom then preset.fadeFrom else nil
        )
    end
    return last
end

--- Gives a button hover (pointer only) and press feedback through a UIScale, per the spec table.
--- `reducedMotion` is read on every event so the setting can change while the button lives.
function UiMotionPlayer.bindButton(
    button: GuiButton,
    reducedMotion: (() -> boolean)?,
    hoverEnabled: boolean
)
    local scale = Instance.new("UIScale")
    scale.Name = "MotionScale"
    scale.Parent = button
    local function reduced(): boolean
        return reducedMotion ~= nil and reducedMotion()
    end
    local pressed = false
    local hovering = false
    local function settle()
        local name = if pressed then "pressDown" elseif hovering then "hoverIn" else "hoverOut"
        UiMotionPlayer.play(name, reduced(), scale, nil, nil, false)
    end
    button.MouseButton1Down:Connect(function()
        pressed = true
        settle()
    end)
    button.MouseButton1Up:Connect(function()
        pressed = false
        if hovering then
            settle()
        else
            UiMotionPlayer.play("pressUp", reduced(), scale, nil, nil, false)
        end
    end)
    if hoverEnabled then
        button.MouseEnter:Connect(function()
            hovering = true
            if not pressed then
                settle()
            end
        end)
    end
    button.MouseLeave:Connect(function()
        hovering = false
        if pressed then
            pressed = false
        end
        UiMotionPlayer.play("pressUp", reduced(), scale, nil, nil, false)
    end)
end

--- Counts a TextLabel from its shown number to `target` over the counter preset. A new call
--- while counting restarts from the number currently shown, so rapid changes coalesce into one
--- smooth count. Returns a cancel function.
function UiMotionPlayer.count(
    label: TextLabel,
    from: number,
    target: number,
    reducedMotion: boolean,
    format: ((value: number) -> string)?
): () -> ()
    local preset = UiMotion.preset("counter")
    local render = format or function(value: number): string
        return tostring(value)
    end
    if reducedMotion then
        label.Text = render(target)
        return function() end
    end
    local elapsed = 0
    local connection: RBXScriptConnection
    connection = game:GetService("RunService").Heartbeat:Connect(function(dt: number)
        elapsed += dt
        label.Text = render(UiMotion.countValue(from, target, elapsed, preset.seconds, false))
        if elapsed >= preset.seconds then
            connection:Disconnect()
        end
    end)
    return function()
        connection:Disconnect()
    end
end

return UiMotionPlayer
