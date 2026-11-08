--!strict
--[[
    The movement state machine of one character: idle, walking, running, plus the equipped flag.
    Pure. Inputs are intent (moving, sprint key began or ended, equipped); the output is the state
    and the WalkSpeed to apply. The server owns it (LocomotionServer), so a client can only ask.

    Rules:
    - running needs movement and an active sprint; sprint without movement stays idle.
    - hold mode: began sets the sprint, ended clears it. Toggle mode: began flips it, ended is
      ignored; with cancelSprintOnStop, stopping clears it.
    - the equipped multiplier scales both speeds while a tool is in hand.
]]

local LocomotionConfig = require("./LocomotionConfig")

export type State = string -- "idle" | "walking" | "running" (plain string: the stable solver widens unions)

export type Snapshot = { state: State, equipped: boolean, sprinting: boolean, speed: number }

export type Machine = {
    setMoving: (self: Machine, moving: boolean) -> (),
    sprintInput: (self: Machine, began: boolean) -> (),
    setEquipped: (self: Machine, equipped: boolean) -> (),
    state: (self: Machine) -> State,
    speed: (self: Machine) -> number,
    snapshot: (self: Machine) -> Snapshot,
}

local LocomotionMachine = {}

function LocomotionMachine.new(config: LocomotionConfig.LocomotionConfig): Machine
    local moving = false
    local sprinting = false
    local equipped = false

    local function state(): State
        if not moving then
            return "idle"
        end
        return if sprinting then "running" else "walking"
    end

    local function speed(): number
        local base = if state() == "running" then config.runSpeed else config.walkSpeed
        return if equipped then base * config.equippedSpeedMultiplier else base
    end

    local machine: Machine
    machine = {
        setMoving = function(_self: Machine, value: boolean)
            moving = value
            if not value and config.sprintMode == "toggle" and config.cancelSprintOnStop then
                sprinting = false
            end
        end,
        sprintInput = function(_self: Machine, began: boolean)
            if config.sprintMode == "hold" then
                sprinting = began
            elseif began then
                sprinting = not sprinting
            end
        end,
        setEquipped = function(_self: Machine, value: boolean)
            equipped = value
        end,
        state = function(_self: Machine): State
            return state()
        end,
        speed = function(_self: Machine): number
            return speed()
        end,
        snapshot = function(_self: Machine): Snapshot
            return { state = state(), equipped = equipped, sprinting = sprinting, speed = speed() }
        end,
    }
    return machine
end

return LocomotionMachine
