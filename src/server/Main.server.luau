--!strict
--[[
    The ONLY server Script: the composition root (ADR 0009). It builds adapters over engine
    services and ProfileStore, injects them into the feature services, and connects engine
    events. Game-specific wiring goes here; logic goes in features.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Analytics = require(Shared.features.analytics.Analytics)
local AnalyticsTracker = require(Shared.features.analytics.AnalyticsTracker)
local Config = require(Shared.Config)
local Flags = require(Shared.features.flags.Flags)
local LedgerProvider = require(Shared.ports.LedgerProvider)
local Monetization = require(Shared.features.monetization.Monetization)
local PlayerData = require(Shared.features.playerdata.PlayerData)
local PlayerDataService = require(Shared.features.playerdata.PlayerDataService)

local ProfileStore = require(ServerScriptService.Vendor.ProfileStore)

local AnalyticsServiceSink = require(script.Parent.adapters.AnalyticsServiceSink)
local ConfigServiceFlags = require(script.Parent.adapters.ConfigServiceFlags)
local MonetizationService = require(script.Parent.features.monetization.MonetizationService)
local ProfileStoreRepository = require(script.Parent.adapters.ProfileStoreRepository)

-- Config is validated at boot; unset ids are reported, not hidden.
local problems = Config.validate(Config.default)
if #problems > 0 then
    warn(`Config is incomplete ({#problems} problem(s)):`)
    for _, problem in problems do
        warn(`  - {problem}`)
    end
end

ProfileStore.SetConstant("AUTO_SAVE_PERIOD", Config.default.autosaveIntervalSeconds)
ProfileStore.SetConstant("ASSUME_DEAD", Config.default.sessionLockTimeoutSeconds)

-- Adapters: the only code that touches engine services or ProfileStore.
local profileStore = ProfileStore.New("PlayerData", PlayerData.default())
local store: ProfileStoreRepository.StoreLike<PlayerData.PlayerData> = {
    StartSessionAsync = function(_self: unknown, profileKey: string, params: { Steal: boolean? }?)
        return profileStore:StartSessionAsync(profileKey, params or {})
    end,
}
local repository = ProfileStoreRepository.new(store)
local flags = Flags.new(ConfigServiceFlags.new(), Config.flagDefaults)

-- Feature services.
local tracker = AnalyticsTracker.new({
    sink = AnalyticsServiceSink.new(),
    clock = function(): number
        return os.time()
    end,
    isValidEvent = Analytics.isFunnelEvent,
})

local playerData = PlayerDataService.new({
    repository = repository,
    onSessionLost = function(key: string)
        local player = Players:GetPlayerByUserId(tonumber(key) or 0)
        if player ~= nil then
            player:Kick("Your data session ended on another server. Please rejoin.")
        end
    end,
})

local ledgers: LedgerProvider.LedgerProvider = {
    ledgerFor = function(
        _self: LedgerProvider.LedgerProvider,
        userId: number
    ): LedgerProvider.ReceiptLedger?
        local data = playerData:get(tostring(userId))
        if data == nil then
            return nil
        end
        return Monetization.newTableLedger(data.purchases)
    end,
}

local monetization = MonetizationService.new({
    ledgers = ledgers,
    -- TODO(victor): grant the product (update the player's data) and return true only on success.
    grant = function(): boolean
        return false
    end,
})

-- Engine events.
Players.PlayerAdded:Connect(function(player: Player)
    local joined = playerData:join(tostring(player.UserId))
    if not joined.ok then
        player:Kick("Could not load your data. Please rejoin.")
        return
    end
    -- TODO(victor): sessionIndex should count this player's sessions (store it in PlayerData).
    tracker:track("session_start", player.UserId, 1)
end)

Players.PlayerRemoving:Connect(function(player: Player)
    playerData:leave(tostring(player.UserId))
end)

if flags:getBoolean("purchasesEnabled") then
    monetization.start()
end
