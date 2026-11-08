--!strict
--[[
    Quests engine: daily and weekly rotating quests plus ordered chains, driven by generic
    counters the game feeds from its own events. Pure: loads under Lune; the clock, the profile
    and the save confirmation are injected.

    Rules:
    - The server is the only source of progress: `record` is called by game code, never by a
      remote. A remote may only ask to `claim` (see QuestRequests).
    - Daily and weekly picks are a deterministic function of the UTC day or week, so every
      server shows the same quests; progress resets when the period key changes.
    - A chain exposes only its current step; claiming it advances the chain.
    - A claim is kept only after the save is confirmed (ADR 0016); otherwise the grant and the
      claimed flag are rolled back so the player can try again.
]]

local ProductGrants = require("../monetization/ProductGrants")
local QuestsConfig = require("./QuestsConfig")
local StreakClock = require("../timerewards/StreakClock")

export type Group = "daily" | "weekly" | "chain"

export type QuestState = {
    dailyKey: number,
    weeklyKey: number,
    progress: { [string]: number },
    claimed: { [string]: boolean },
    -- 1-based index of the current step of each chain (absent means 1).
    chainStep: { [string]: number },
}

-- The slice of PlayerData this module reads and writes. `quests` is created on first use.
export type Profile = { coins: number, quests: QuestState? }

export type QuestStatus = "active" | "complete" | "claimed"

export type QuestView = {
    id: string,
    title: string,
    group: Group,
    chainId: string?,
    counter: string,
    progress: number,
    target: number,
    status: QuestStatus,
}

export type ClaimError =
    "disabled"
    | "no_data"
    | "unknown_quest"
    | "not_active"
    | "not_complete"
    | "already_claimed"
    | "grant_failed"
    | "save_failed"

export type ClaimResult = { ok: true, amount: number } | { ok: false, error: ClaimError }

export type RecordError = "disabled" | "no_data" | "invalid_counter" | "invalid_amount"

export type RecordResult = { ok: true, affected: number } | { ok: false, error: RecordError }

export type Quests = {
    record: (self: Quests, userId: number, counter: string, amount: number) -> RecordResult,
    claim: (self: Quests, userId: number, questId: string) -> ClaimResult,
    view: (self: Quests, userId: number) -> { QuestView },
}

export type Deps = {
    config: QuestsConfig.QuestsConfig,
    -- Server clock, Unix seconds (os.time).
    now: () -> number,
    profileFor: (userId: number) -> Profile?,
    -- Built from `QuestsModule.grantTable(config)`.
    grants: ProductGrants.ProductGrants,
    confirmSaved: (userId: number) -> boolean,
}

local DAYS_PER_WEEK = 7
local MINSTD_MODULUS = 2147483647
local MINSTD_MULTIPLIER = 48271

local QuestsModule = {}

--- Grant declarations for ProductGrants.new, one per quest id.
function QuestsModule.grantTable(
    config: QuestsConfig.QuestsConfig
): { [string]: ProductGrants.ProductGrant }
    local grants: { [string]: ProductGrants.ProductGrant } = {}
    for _, quest in QuestsConfig.allQuests(config) do
        grants[quest.id] = quest.reward
    end
    return grants
end

--- UTC week number (7 UTC days counted from the Unix epoch day), starting at 1.
function QuestsModule.weekKey(now: number): number
    return math.floor((StreakClock.dayIndex(now) - 1) / DAYS_PER_WEEK) + 1
end

--- Deterministic pick of `count` distinct indices out of 1..size for a period key. Same input,
--- same output on every server (MINSTD generator; products stay below 2^53).
function QuestsModule.pickIndices(size: number, count: number, key: number): { number }
    local order: { number } = {}
    for index = 1, size do
        order[index] = index
    end
    local seed = (key * MINSTD_MULTIPLIER) % MINSTD_MODULUS + 1
    for index = size, 2, -1 do
        seed = (seed * MINSTD_MULTIPLIER) % MINSTD_MODULUS
        local other = seed % index + 1
        order[index], order[other] = order[other], order[index]
    end
    local picked: { number } = {}
    for offset = 1, math.min(count, size) do
        table.insert(picked, order[size - offset + 1])
    end
    return picked
end

local function freshState(now: number): QuestState
    return {
        dailyKey = StreakClock.dayIndex(now),
        weeklyKey = QuestsModule.weekKey(now),
        progress = {},
        claimed = {},
        chainStep = {},
    }
end

local function clearPool(state: QuestState, pool: { QuestsConfig.QuestDef })
    for _, quest in pool do
        state.progress[quest.id] = nil
        state.claimed[quest.id] = nil
    end
end

-- Creates the state if missing and resets expired periods.
local function syncState(
    config: QuestsConfig.QuestsConfig,
    profile: Profile,
    now: number
): QuestState
    local state = profile.quests
    if state == nil then
        local created = freshState(now)
        profile.quests = created
        return created
    end
    local dayKey = StreakClock.dayIndex(now)
    if state.dailyKey ~= dayKey then
        clearPool(state, config.daily.pool)
        state.dailyKey = dayKey
    end
    local weekKey = QuestsModule.weekKey(now)
    if state.weeklyKey ~= weekKey then
        clearPool(state, config.weekly.pool)
        state.weeklyKey = weekKey
    end
    return state
end

type Active = {
    quest: QuestsConfig.QuestDef,
    group: Group,
    chainId: string?,
    chainIndex: number?,
}

local function activeQuests(
    config: QuestsConfig.QuestsConfig,
    state: QuestState,
    now: number
): { Active }
    local active: { Active } = {}
    local function addRotating(rotating: QuestsConfig.Rotating, group: Group, key: number)
        for _, index in QuestsModule.pickIndices(#rotating.pool, rotating.count, key) do
            table.insert(active, { quest = rotating.pool[index], group = group })
        end
    end
    addRotating(config.daily, "daily", StreakClock.dayIndex(now))
    addRotating(config.weekly, "weekly", QuestsModule.weekKey(now))
    for _, chain in config.chains do
        local step = state.chainStep[chain.id] or 1
        local quest = chain.steps[step]
        if quest ~= nil then
            table.insert(
                active,
                { quest = quest, group = "chain", chainId = chain.id, chainIndex = step }
            )
        end
    end
    return active
end

local function statusOf(state: QuestState, quest: QuestsConfig.QuestDef): QuestStatus
    if state.claimed[quest.id] == true then
        return "claimed"
    end
    if (state.progress[quest.id] or 0) >= quest.target then
        return "complete"
    end
    return "active"
end

local function isDeclared(config: QuestsConfig.QuestsConfig, questId: string): boolean
    for _, quest in QuestsConfig.allQuests(config) do
        if quest.id == questId then
            return true
        end
    end
    return false
end

function QuestsModule.new(deps: Deps): Quests
    local config = deps.config

    local service: Quests = {
        record = function(
            _self: Quests,
            userId: number,
            counter: string,
            amount: number
        ): RecordResult
            if not config.enabled then
                return { ok = false, error = "disabled" }
            end
            if counter == "" or #counter > 32 then
                return { ok = false, error = "invalid_counter" }
            end
            if
                amount ~= amount
                or amount <= 0
                or amount == math.huge
                or amount > config.maxIncrementPerEvent
            then
                return { ok = false, error = "invalid_amount" }
            end
            local profile = deps.profileFor(userId)
            if profile == nil then
                return { ok = false, error = "no_data" }
            end
            local now = deps.now()
            local state = syncState(config, profile, now)
            local affected = 0
            for _, entry in activeQuests(config, state, now) do
                local quest = entry.quest
                if quest.counter == counter and state.claimed[quest.id] ~= true then
                    local current = state.progress[quest.id] or 0
                    if current < quest.target then
                        state.progress[quest.id] = math.min(quest.target, current + amount)
                        affected += 1
                    end
                end
            end
            return { ok = true, affected = affected }
        end,

        claim = function(_self: Quests, userId: number, questId: string): ClaimResult
            if not config.enabled then
                return { ok = false, error = "disabled" }
            end
            local profile = deps.profileFor(userId)
            if profile == nil then
                return { ok = false, error = "no_data" }
            end
            local now = deps.now()
            local state = syncState(config, profile, now)
            local found: Active? = nil
            for _, entry in activeQuests(config, state, now) do
                if entry.quest.id == questId then
                    found = entry
                end
            end
            if found == nil then
                if not isDeclared(config, questId) then
                    return { ok = false, error = "unknown_quest" }
                end
                if state.claimed[questId] == true then
                    return { ok = false, error = "already_claimed" }
                end
                return { ok = false, error = "not_active" }
            end
            local quest = found.quest
            local status = statusOf(state, quest)
            if status == "claimed" then
                return { ok = false, error = "already_claimed" }
            end
            if status ~= "complete" then
                return { ok = false, error = "not_complete" }
            end
            local applied = deps.grants:apply(profile, quest.id)
            if not applied.ok then
                return { ok = false, error = "grant_failed" }
            end
            state.claimed[quest.id] = true
            local chainId = found.chainId
            local chainIndex = found.chainIndex
            if chainId ~= nil and chainIndex ~= nil then
                state.chainStep[chainId] = chainIndex + 1
            end
            if not deps.confirmSaved(userId) then
                profile.coins -= quest.reward.amount
                state.claimed[quest.id] = nil
                if chainId ~= nil and chainIndex ~= nil then
                    -- Step 1 is the default, so it is stored as absent.
                    if chainIndex == 1 then
                        state.chainStep[chainId] = nil
                    else
                        state.chainStep[chainId] = chainIndex
                    end
                end
                return { ok = false, error = "save_failed" }
            end
            return { ok = true, amount = quest.reward.amount }
        end,

        view = function(_self: Quests, userId: number): { QuestView }
            local views: { QuestView } = {}
            if not config.enabled then
                return views
            end
            local profile = deps.profileFor(userId)
            if profile == nil then
                return views
            end
            local now = deps.now()
            local state = syncState(config, profile, now)
            for _, entry in activeQuests(config, state, now) do
                local quest = entry.quest
                table.insert(views, {
                    id = quest.id,
                    title = quest.title,
                    group = entry.group,
                    chainId = entry.chainId,
                    counter = quest.counter,
                    progress = state.progress[quest.id] or 0,
                    target = quest.target,
                    status = statusOf(state, quest),
                })
            end
            return views
        end,
    }
    return service
end

return QuestsModule
