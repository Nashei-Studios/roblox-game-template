--!strict
--[[
    Client entry point. UI is built in Studio (partially managed Rojo); this script
    only binds behavior to it. Never trust client input on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local net = require(ReplicatedStorage.Shared.net.generated.client)

print(`{Config.default.gameName} client started`)

-- Server to client: the balance after a grant. Bind it to the UI built in Studio.
net.CoinsChanged.setCallback(function(coins)
    print(`Coins: {coins}`)
end)
