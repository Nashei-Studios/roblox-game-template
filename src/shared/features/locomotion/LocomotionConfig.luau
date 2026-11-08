--!strict
--[[
    Typed config of the locomotion and tool controller, and its validation. Pure: loads under
    Lune. Animation ids are references (ADR 0006): nil means the default Roblox Animate script
    keeps playing its own walk, run and tool poses, so a game works with no ids at all. Never put
    a plausible fake id.
]]

export type Animations = {
    idle: number?,
    walk: number?,
    run: number?,
    equip: number?,
    unequip: number?,
    swing: number?,
}

export type Keys = {
    -- Enum.KeyCode names (keyboard) and gamepad names; the presenter resolves them.
    sprint: { string },
    equip: { string },
}

export type LocomotionConfig = {
    walkSpeed: number,
    runSpeed: number,
    -- "hold" (run while the key is down) or "toggle" (a press flips it).
    sprintMode: string,
    -- Toggle mode: stopping to walk clears the sprint.
    cancelSprintOnStop: boolean,
    -- Multiplies both speeds while a tool is equipped (1 = no change).
    equippedSpeedMultiplier: number,
    keys: Keys,
    -- Draw the sprint and equip buttons with the UI system on touch devices.
    touchButtons: boolean,
    animations: Animations,
    equipCooldownSeconds: number,
    swingCooldownSeconds: number,
}

local LocomotionConfigModule = {}

-- Roblox default WalkSpeed is 16; the engine accepts higher but 100 is far past any sane value.
LocomotionConfigModule.MAX_SPEED = 100
LocomotionConfigModule.SPRINT_MODES = { hold = true, toggle = true }

--- A neutral default: Roblox walk speed 16, a 1.6x run, hold to sprint, default animations.
function LocomotionConfigModule.default(): LocomotionConfig
    return {
        walkSpeed = 16,
        runSpeed = 25,
        sprintMode = "hold",
        cancelSprintOnStop = true,
        equippedSpeedMultiplier = 1,
        keys = { sprint = { "LeftShift", "ButtonL3" }, equip = { "Q", "ButtonY" } },
        touchButtons = true,
        animations = {},
        equipCooldownSeconds = 0.3,
        swingCooldownSeconds = 0.4,
    }
end

local function positiveFinite(value: number): boolean
    return value == value and value > 0 and value <= LocomotionConfigModule.MAX_SPEED
end

local function idOk(value: number?): boolean
    return value == nil or (value > 0 and value % 1 == 0)
end

--- One human-readable problem per invalid value (empty when valid).
function LocomotionConfigModule.validate(config: LocomotionConfig): { string }
    local problems: { string } = {}
    if not positiveFinite(config.walkSpeed) then
        table.insert(problems, "locomotion.walkSpeed must be above 0 and at most 100")
    end
    if not positiveFinite(config.runSpeed) or config.runSpeed <= config.walkSpeed then
        table.insert(problems, "locomotion.runSpeed must be above walkSpeed and at most 100")
    end
    if not LocomotionConfigModule.SPRINT_MODES[config.sprintMode] then
        table.insert(problems, "locomotion.sprintMode must be hold or toggle")
    end
    local multiplier = config.equippedSpeedMultiplier
    if multiplier ~= multiplier or multiplier <= 0 or multiplier > 2 then
        table.insert(problems, "locomotion.equippedSpeedMultiplier must be above 0 up to 2")
    end
    if #config.keys.sprint == 0 or #config.keys.equip == 0 then
        table.insert(problems, "locomotion.keys needs at least one sprint and one equip binding")
    end
    for name, id in config.animations :: { [string]: number? } do
        if not idOk(id) then
            table.insert(problems, `locomotion.animations.{name} must be a positive integer or nil`)
        end
    end
    if
        config.equipCooldownSeconds ~= config.equipCooldownSeconds
        or config.equipCooldownSeconds < 0
    then
        table.insert(problems, "locomotion.equipCooldownSeconds must be zero or positive")
    end
    if
        config.swingCooldownSeconds ~= config.swingCooldownSeconds
        or config.swingCooldownSeconds < 0
    then
        table.insert(problems, "locomotion.swingCooldownSeconds must be zero or positive")
    end
    return problems
end

--- Which animation slots fall back to the default Roblox animation (informational).
function LocomotionConfigModule.defaultedAnimations(config: LocomotionConfig): { string }
    local names = { "idle", "walk", "run", "equip", "unequip", "swing" }
    local missing: { string } = {}
    local animations = config.animations :: { [string]: number? }
    for _, name in names do
        if animations[name] == nil then
            table.insert(missing, name)
        end
    end
    return missing
end

return LocomotionConfigModule
