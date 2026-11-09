--!strict
--[[
    Connects the pure SocialRuntime (shared/features/social) to the engine: Players, HttpService,
    MemoryStoreService and task. No rule lives here (ADR 0009, 0030, 0031).

    - Friend Boost: `Player:IsFriendsWith`, in parallel, retried every 60 s with backoff.
    - Invite reward: `Player:GetJoinData()` on join, behind the `inviteReward` flag, with the
      once-per-pair-per-day record in a MemoryStore hash map shared by every server.
    - `perksFor` is what the game multiplies into its configurable perk.
]]

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Flags = require(Shared.features.flags.Flags)
local HashMapLedger = require(Shared.features.social.HashMapLedger)
local SocialConfig = require(Shared.features.social.SocialConfig)
local SocialPerks = require(Shared.features.social.SocialPerks)
local SocialRuntime = require(Shared.features.social.SocialRuntime)

export type Deps = {
    flags: Flags.Flags,
    -- A player's social multiplier is about to change / changed (settle at the old rate, then re-read).
    beforeChange: (userId: number) -> (),
    onChanged: (userId: number) -> (),
    -- Whole percent of the community perk; 0 while it is off or the player is not a member.
    communityPerkPct: (userId: number) -> number,
}

export type Wiring = {
    perksFor: (userId: number) -> SocialPerks.SocialPerks,
    onJoin: (player: Player) -> (),
    onLeave: (player: Player) -> (),
}

local LEDGER_MAP = "InviteLedger"

local SocialWiring = {}

function SocialWiring.start(deps: Deps): Wiring
    local config = SocialConfig.default
    local map = MemoryStoreService:GetHashMap(LEDGER_MAP)
    local ledger = HashMapLedger.new({
        UpdateAsync = function(
            _self: HashMapLedger.HashMapLike,
            key: string,
            transform: (old: unknown) -> unknown,
            expirationSeconds: number
        ): unknown
            return map:UpdateAsync(key, transform, expirationSeconds)
        end,
    }, config.invite.dailyPaidPerInviter)

    local runtime = SocialRuntime.new({
        config = config,
        inviteRewardEnabled = function(): boolean
            return deps.flags:getBoolean("inviteReward")
        end,
        now = os.time,
        isFriendsWith = function(userId: number, otherUserId: number): boolean
            local player = Players:GetPlayerByUserId(userId)
            if player == nil then
                error("player left before the friendship was read")
            end
            return player:IsFriendsWith(otherUserId)
        end,
        isPresent = function(userId: number): boolean
            return Players:GetPlayerByUserId(userId) ~= nil
        end,
        ledger = ledger,
        decode = function(text: string): unknown
            return HttpService:JSONDecode(text)
        end,
        spawn = function(run: () -> ())
            task.spawn(run)
        end,
        delay = function(seconds: number, run: () -> ())
            task.delay(seconds, run)
        end,
        beforeChange = deps.beforeChange,
        onChanged = deps.onChanged,
        communityPerkPct = deps.communityPerkPct,
        warn = function(message: string)
            warn(message)
        end,
    })
    runtime:start()

    local wiring: Wiring = {
        perksFor = function(userId: number): SocialPerks.SocialPerks
            return runtime:perksFor(userId)
        end,
        onJoin = function(player: Player)
            runtime:onJoin(player.UserId, player:GetJoinData())
        end,
        onLeave = function(player: Player)
            runtime:onLeave(player.UserId)
        end,
    }
    return wiring
end

return SocialWiring
