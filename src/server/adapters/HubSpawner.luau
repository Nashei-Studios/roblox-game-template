--!strict
--[[
    Server presenter of the hub: seats each player on their registry slot when their character
    spawns and applies the name-tag policy. It touches Instances, so it is excluded from the
    line-coverage gate; the slot rules live in features/hub. The game builds the hub place by
    hand (stations, prompts) and passes the CFrame of its center.
]]

local Players = game:GetService("Players")

type SpawnPoint = { position: { x: number, z: number }, facing: { x: number, z: number } }

export type Deps = {
    -- The registry join / leave (features/hub/HubRegistry).
    join: (playerId: number) -> SpawnPoint?,
    leave: (playerId: number) -> (),
    -- Center of the hub in the world.
    origin: CFrame,
    -- nil hides name tags (HubConfig.nameTags.enabled = false).
    nameTagDistance: number?,
}

local HubSpawner = {}

--- Connects the Players events; returns a function that disconnects them.
function HubSpawner.start(deps: Deps): () -> ()
    local function place(player: Player, character: Model)
        local point = deps.join(player.UserId)
        if point == nil then
            return
        end
        local at = deps.origin:PointToWorldSpace(Vector3.new(point.position.x, 3, point.position.z))
        local lookAt = deps.origin:PointToWorldSpace(Vector3.new(0, 3, 0))
        character:PivotTo(CFrame.lookAt(at, lookAt))
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid ~= nil then
            local distance = deps.nameTagDistance
            if distance == nil then
                humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            else
                humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
                humanoid.NameDisplayDistance = distance
            end
        end
    end

    local function watch(player: Player): RBXScriptConnection
        local existing = player.Character
        if existing ~= nil then
            place(player, existing)
        end
        return player.CharacterAdded:Connect(function(character: Model)
            place(player, character)
        end)
    end

    local connections: { RBXScriptConnection } = {}
    table.insert(
        connections,
        Players.PlayerAdded:Connect(function(player: Player)
            table.insert(connections, watch(player))
        end)
    )
    table.insert(
        connections,
        Players.PlayerRemoving:Connect(function(player: Player)
            deps.leave(player.UserId)
        end)
    )
    for _, player in Players:GetPlayers() do
        table.insert(connections, watch(player))
    end
    return function()
        for _, connection in connections do
            connection:Disconnect()
        end
    end
end

return HubSpawner
