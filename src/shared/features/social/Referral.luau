--!strict
--[[
    Invite referral (ADR 0030). Pure: loads under Lune.

    Follows the official referral pattern: the client prompts `SocialService:PromptGameInvite`
    with `ExperienceInviteOptions.LaunchData` (a JSON payload, at most 200 characters), and the
    server reads `Player:GetJoinData()`, where `ReferredByPlayerId` is filled by Roblox for every
    kind of invitation. Sources:
    - https://create.roblox.com/docs/production/promotion/invite-prompts
    - https://create.roblox.com/docs/production/promotion/referral-system
    Nothing in the join data is trusted beyond a positive integer id: it is a claim, validated by
    InviteReward (not self, inviter present, once per pair per day).
]]

export type Payload = { v: number, kind: "referral", inviter: number }

-- ExperienceInviteOptions.LaunchData limit.
local MAX_LAUNCH_DATA_LENGTH = 200

local ReferralModule = {}

ReferralModule.MAX_LAUNCH_DATA_LENGTH = MAX_LAUNCH_DATA_LENGTH

--- What the client puts in LaunchData (the caller JSON-encodes it).
function ReferralModule.payload(inviterUserId: number): Payload
    return { v = 1, kind = "referral", inviter = inviterUserId }
end

local function isUserId(value: unknown): boolean
    return type(value) == "number" and value == value and value >= 1 and value % 1 == 0
end

--- The inviter claimed by a join, or nil when the join was not a valid referral.
--- `ReferredByPlayerId` is the platform's own field; when LaunchData also names an inviter the two
--- must agree, otherwise the join is refused.
--- `decode` is HttpService:JSONDecode (injected); it may throw.
function ReferralModule.inviterOf(joinData: unknown, decode: (text: string) -> unknown): number?
    if type(joinData) ~= "table" then
        return nil
    end
    local record = joinData :: { [string]: unknown }
    local referred = record.ReferredByPlayerId
    if not isUserId(referred) then
        return nil
    end
    local launch = record.LaunchData
    if type(launch) == "string" and launch ~= "" then
        if #launch > MAX_LAUNCH_DATA_LENGTH then
            return nil
        end
        local decoded, body = pcall(decode, launch)
        if decoded and type(body) == "table" then
            local claimed = (body :: { [string]: unknown }).inviter
            if claimed ~= nil and claimed ~= referred then
                return nil
            end
        end
    end
    return referred :: number
end

return ReferralModule
