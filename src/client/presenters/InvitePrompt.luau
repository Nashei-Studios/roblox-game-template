--!strict
--[[
    Asks the player to invite friends (ADR 0030). The prompt carries a referral payload in
    ExperienceInviteOptions.LaunchData; the server reads the result with Player:GetJoinData() and
    decides whether to reward (features/social/InviteReward). Nothing here grants anything.
    Official pattern: CanSendGameInviteAsync in a pcall, then PromptGameInvite
    (https://create.roblox.com/docs/production/promotion/invite-prompts).
    Menus bind to `InvitePrompt.prompt`; this file owns no UI.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Referral = require(ReplicatedStorage.Shared.features.social.Referral)

local InvitePrompt = {}

--- True when the invite prompt was shown. False when the player cannot send invites here or
--- anything failed; the failure never reaches the player as an error.
function InvitePrompt.prompt(): boolean
    local player = Players.LocalPlayer
    local checked, canSend = pcall(function()
        return SocialService:CanSendGameInviteAsync(player)
    end)
    if not (checked and canSend == true) then
        return false
    end
    local options = Instance.new("ExperienceInviteOptions")
    options.PromptMessage = "Invite friends to play together!"
    options.LaunchData = HttpService:JSONEncode(Referral.payload(player.UserId))
    local shown = pcall(function()
        SocialService:PromptGameInvite(player, options)
    end)
    return shown
end

return InvitePrompt
