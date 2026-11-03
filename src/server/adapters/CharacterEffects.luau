--!strict
--[[
    Adapter: the engine side effects the KeySprintController asks for on a player's character:
    walk speed, teleport to a stage start gate, and the cosmetic Trail. No rules live here. It
    touches the engine, so the coverage gate excludes it (ADR 0017); a Studio playtest checks it.
]]

local Players = game:GetService("Players")

export type CharacterEffects = {
    setWalkSpeed: (self: CharacterEffects, userId: number, speed: number) -> (),
    teleportTo: (self: CharacterEffects, userId: number, position: Vector3) -> (),
    -- Adds the Trail pass cosmetic to the player's current character (no gameplay effect).
    applyTrail: (self: CharacterEffects, userId: number) -> (),
}

local CharacterEffectsModule = {}

local function characterOf(userId: number): Model?
    local player = Players:GetPlayerByUserId(userId)
    if player == nil then
        return nil
    end
    return player.Character
end

function CharacterEffectsModule.new(): CharacterEffects
    local effects: CharacterEffects = {
        setWalkSpeed = function(_self: CharacterEffects, userId: number, speed: number)
            local character = characterOf(userId)
            if character == nil then
                return
            end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if humanoid ~= nil then
                humanoid.WalkSpeed = speed
            end
        end,
        teleportTo = function(_self: CharacterEffects, userId: number, position: Vector3)
            local character = characterOf(userId)
            if character ~= nil then
                character:PivotTo(CFrame.new(position))
            end
        end,
        applyTrail = function(_self: CharacterEffects, userId: number)
            local character = characterOf(userId)
            if character == nil then
                return
            end
            local root = character:FindFirstChild("HumanoidRootPart")
            if root == nil or not root:IsA("BasePart") or root:FindFirstChild("KeySprintTrail") then
                return
            end
            local top = Instance.new("Attachment")
            top.Position = Vector3.new(0, 1, 0)
            top.Parent = root
            local bottom = Instance.new("Attachment")
            bottom.Position = Vector3.new(0, -1, 0)
            bottom.Parent = root
            local trail = Instance.new("Trail")
            trail.Name = "KeySprintTrail"
            trail.Attachment0 = top
            trail.Attachment1 = bottom
            trail.Lifetime = 0.6
            trail.Color =
                ColorSequence.new(Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 80, 120))
            trail.Parent = root
        end,
    }
    return effects
end

return CharacterEffectsModule
