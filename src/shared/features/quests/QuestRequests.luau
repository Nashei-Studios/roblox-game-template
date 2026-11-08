--!strict
--[[
    Server handler for a ClaimQuest remote (ADR 0012). Pure: loads under Lune.
    The remote carries INTENT only (the quest id). Order: rate limiter, then Validation, then the
    Quests engine. Progress never comes from a remote: `record` is called by server game code.
    A rate-limited request gets no answer at all.
]]

local Quests = require("./Quests")
local Validation = require("../../net/Validation")

export type Rejection = "rate_limited" | Validation.ValidationError | Quests.ClaimError

export type HandleResult = { ok: true, amount: number } | { ok: false, reason: Rejection }

export type Deps = {
    quests: Quests.Quests,
    allow: (userId: number) -> boolean,
}

export type QuestRequests = {
    handleClaim: (self: QuestRequests, userId: number, questId: unknown) -> HandleResult,
}

local QuestRequestsModule = {}

function QuestRequestsModule.new(deps: Deps): QuestRequests
    local handler: QuestRequests = {
        handleClaim = function(
            _self: QuestRequests,
            userId: number,
            questId: unknown
        ): HandleResult
            if not deps.allow(userId) then
                return { ok = false, reason = "rate_limited" }
            end
            local checked = Validation.string(questId, 1, 32)
            if not checked.ok then
                return { ok = false, reason = checked.error }
            end
            local result = deps.quests:claim(userId, checked.value)
            if not result.ok then
                return { ok = false, reason = result.error }
            end
            return { ok = true, amount = result.amount }
        end,
    }
    return handler
end

return QuestRequestsModule
