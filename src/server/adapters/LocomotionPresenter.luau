--!strict
--[[
    Server presenter of locomotion: reads the Humanoid move direction into the server state
    machine and applies its speed to WalkSpeed, and puts the remembered tool in hand after a
    respawn. It touches Instances, so it is excluded from the line-coverage gate; every decision
    lives in features/locomotion/LocomotionServer.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

type Server = {
    join: (self: Server, playerId: number) -> (),
    leave: (self: Server, playerId: number) -> (),
    setMoving: (self: Server, playerId: number, moving: boolean) -> (),
    onRespawn: (self: Server, playerId: number) -> string?,
    speedOf: (self: Server, playerId: number) -> number?,
}

export type Deps = {
    server: Server,
    -- The Tool instance for a tool id, from the player backpack or the game catalog; nil if none.
    findTool: (player: Player, toolId: string) -> Tool?,
}

local LocomotionPresenter = {}

--- Connects Players and Heartbeat; returns a function that disconnects them.
function LocomotionPresenter.start(deps: Deps): () -> ()
    local connections: { RBXScriptConnection } = {}

    local function watch(player: Player)
        deps.server:join(player.UserId)
        table.insert(
            connections,
            player.CharacterAdded:Connect(function(character: Model)
                local humanoid = character:WaitForChild("Humanoid", 10)
                local toolId = deps.server:onRespawn(player.UserId)
                if toolId ~= nil and humanoid ~= nil and humanoid:IsA("Humanoid") then
                    local tool = deps.findTool(player, toolId)
                    if tool ~= nil then
                        humanoid:EquipTool(tool)
                    end
                end
            end)
        )
    end

    table.insert(connections, Players.PlayerAdded:Connect(watch))
    table.insert(
        connections,
        Players.PlayerRemoving:Connect(function(player: Player)
            deps.server:leave(player.UserId)
        end)
    )
    for _, player in Players:GetPlayers() do
        watch(player)
    end
    table.insert(
        connections,
        RunService.Heartbeat:Connect(function()
            for _, player in Players:GetPlayers() do
                local character = player.Character
                local humanoid = if character ~= nil
                    then character:FindFirstChildOfClass("Humanoid")
                    else nil
                if humanoid ~= nil then
                    deps.server:setMoving(player.UserId, humanoid.MoveDirection.Magnitude > 0)
                    local speed = deps.server:speedOf(player.UserId)
                    if speed ~= nil and humanoid.WalkSpeed ~= speed then
                        humanoid.WalkSpeed = speed
                    end
                end
            end
        end)
    )
    return function()
        for _, connection in connections do
            connection:Disconnect()
        end
    end
end

return LocomotionPresenter
