--!strict
--[[
    Server entry point. Validates config at boot and reports what is still unset.
    Game-specific wiring (data load on PlayerAdded, MonetizationService.start) goes here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local problems = Config.validate(Config.default)
if #problems > 0 then
    warn(`Config is incomplete ({#problems} problem(s)):`)
    for _, problem in problems do
        warn(`  - {problem}`)
    end
end

-- TODO(victor): on PlayerAdded call Session.load via RobloxDataStoreBackend, and on
-- PlayerRemoving call Session.save with release = true. Then call MonetizationService.start.
