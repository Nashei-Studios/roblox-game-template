--!strict
--[[
    Client entry point. UI is built in Studio (partially managed Rojo); this script
    only binds behavior to it. Never trust client input on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(`{Config.default.gameName} client started`)
