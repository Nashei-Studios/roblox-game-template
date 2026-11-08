--!strict
--[[
    Client presenter of locomotion input: binds the configured sprint and equip keys (keyboard
    and gamepad) with ContextActionService and reports intent through callbacks. The game sends
    the callbacks over a validated remote; the server decides (features/locomotion). Touch uses
    the UI system buttons of LocomotionHud, not the ContextActionService touch button, so the
    buttons follow the safe area and the tokens (ADR 0035). Excluded from the coverage gate.
]]

local ContextActionService = game:GetService("ContextActionService")

export type Callbacks = {
    onSprint: (began: boolean) -> (),
    onEquipToggle: () -> (),
}

local SPRINT_ACTION = "LocomotionSprint"
local EQUIP_ACTION = "LocomotionEquip"

local LocomotionInput = {}

local function resolve(names: { string }): { Enum.KeyCode }
    local codes: { Enum.KeyCode } = {}
    for _, name in names do
        local ok, code = pcall(function()
            return (Enum.KeyCode :: any)[name] :: Enum.KeyCode
        end)
        if ok and code ~= nil then
            table.insert(codes, code)
        else
            warn(`Locomotion: unknown key "{name}" in config`)
        end
    end
    return codes
end

--- Binds both actions; returns a function that unbinds them.
function LocomotionInput.bind(
    sprintKeys: { string },
    equipKeys: { string },
    callbacks: Callbacks
): () -> ()
    ContextActionService:BindAction(
        SPRINT_ACTION,
        function(_name: string, state: Enum.UserInputState)
            if state == Enum.UserInputState.Begin then
                callbacks.onSprint(true)
            elseif state == Enum.UserInputState.End then
                callbacks.onSprint(false)
            end
            return Enum.ContextActionResult.Pass
        end,
        false,
        table.unpack(resolve(sprintKeys))
    )
    ContextActionService:BindAction(
        EQUIP_ACTION,
        function(_name: string, state: Enum.UserInputState)
            if state == Enum.UserInputState.Begin then
                callbacks.onEquipToggle()
            end
            return Enum.ContextActionResult.Pass
        end,
        false,
        table.unpack(resolve(equipKeys))
    )
    return function()
        ContextActionService:UnbindAction(SPRINT_ACTION)
        ContextActionService:UnbindAction(EQUIP_ACTION)
    end
end

return LocomotionInput
