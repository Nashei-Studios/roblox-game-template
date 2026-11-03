--!strict
--[[
    Engine adapter: the sell stand and the proximity check behind the `isNearStand` dep of
    ReefController (ADR 0021). It holds no rules. If the place has no Part named "SellStand",
    a plain placeholder is created so the loop can be tried without building the world; the
    pier, water and real stand are built in Studio. It touches the engine, so the coverage gate
    excludes it (ADR 0017) and it is checked in Studio.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

export type SellStand = {
    isNear: (self: SellStand, userId: number) -> boolean,
}

local SellStandModule = {}

local STAND_NAME = "SellStand"
-- Placeholder position and size, used only when the place has no stand of its own.
local PLACEHOLDER_POSITION = Vector3.new(0, 3, 20)
local PLACEHOLDER_SIZE = Vector3.new(6, 6, 6)

function SellStandModule.new(range: number): SellStand
    local found = Workspace:FindFirstChild(STAND_NAME)
    local stand: BasePart
    if found ~= nil and found:IsA("BasePart") then
        stand = found
    else
        local part = Instance.new("Part")
        part.Name = STAND_NAME
        part.Anchored = true
        part.Size = PLACEHOLDER_SIZE
        part.Position = PLACEHOLDER_POSITION
        part.Parent = Workspace
        stand = part
    end

    local adapter: SellStand = {
        isNear = function(_self: SellStand, userId: number): boolean
            local player = Players:GetPlayerByUserId(userId)
            local character = if player ~= nil then player.Character else nil
            local root = if character ~= nil
                then character:FindFirstChild("HumanoidRootPart")
                else nil
            if root == nil or not root:IsA("BasePart") then
                return false
            end
            return (root.Position - stand.Position).Magnitude <= range
        end,
    }
    return adapter
end

return SellStandModule
