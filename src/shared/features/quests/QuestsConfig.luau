--!strict
--[[
    Typed config of the quests (daily, weekly and chains) and its validation. Pure: loads under
    Lune. Counters are free-form strings the GAME feeds from its own events; the template never
    names one. Rewards share the shape of every other reward (`rewards/RewardConfig`) so delivery
    goes through ProductGrants.
]]

local RewardConfig = require("../rewards/RewardConfig")

export type QuestDef = {
    -- Stable id the client sends as intent (never an index). 1 to 32 characters, unique overall.
    id: string,
    -- Text key or plain text the UI shows; the template does not interpret it.
    title: string,
    -- Name of the counter this quest listens to, 1 to 32 characters.
    counter: string,
    -- Units of the counter needed to complete the quest.
    target: number,
    reward: RewardConfig.Reward,
}

export type Chain = {
    id: string,
    -- Steps unlock in order: step N+1 is active only after step N was claimed.
    steps: { QuestDef },
}

export type Rotating = {
    -- How many quests of `pool` are active at a time (same pick on every server for a period).
    count: number,
    pool: { QuestDef },
}

export type QuestsConfig = {
    enabled: boolean,
    -- Largest amount one `record` call may add; a bigger value is refused as a bug or an exploit.
    maxIncrementPerEvent: number,
    daily: Rotating,
    weekly: Rotating,
    chains: { Chain },
}

local MAX_ID_LENGTH = 32

local QuestsConfigModule = {}

--- Every quest of the config, in declaration order (daily pool, weekly pool, chain steps).
function QuestsConfigModule.allQuests(config: QuestsConfig): { QuestDef }
    local all: { QuestDef } = {}
    for _, quest in config.daily.pool do
        table.insert(all, quest)
    end
    for _, quest in config.weekly.pool do
        table.insert(all, quest)
    end
    for _, chain in config.chains do
        for _, quest in chain.steps do
            table.insert(all, quest)
        end
    end
    return all
end

local function validRotating(label: string, rotating: Rotating, problems: { string })
    if rotating.count ~= 0 and not RewardConfig.isPositiveInteger(rotating.count) then
        table.insert(problems, `quests.{label}.count must be zero or a positive integer`)
    elseif rotating.count > #rotating.pool then
        table.insert(problems, `quests.{label}.count is larger than its pool`)
    end
end

--- One human-readable problem per invalid value (empty when valid).
function QuestsConfigModule.validate(config: QuestsConfig): { string }
    local problems: { string } = {}
    if
        not RewardConfig.isFinite(config.maxIncrementPerEvent)
        or config.maxIncrementPerEvent <= 0
    then
        table.insert(problems, "quests.maxIncrementPerEvent must be positive")
    end
    validRotating("daily", config.daily, problems)
    validRotating("weekly", config.weekly, problems)
    local seen: { [string]: boolean } = {}
    for _, quest in QuestsConfigModule.allQuests(config) do
        local label = `quest "{quest.id}"`
        if quest.id == "" or #quest.id > MAX_ID_LENGTH then
            table.insert(problems, `a quest id must be 1 to {MAX_ID_LENGTH} characters`)
        end
        if seen[quest.id] then
            table.insert(problems, `{label} is declared twice`)
        end
        seen[quest.id] = true
        if quest.counter == "" or #quest.counter > MAX_ID_LENGTH then
            table.insert(problems, `{label} counter must be 1 to {MAX_ID_LENGTH} characters`)
        end
        if not RewardConfig.isPositiveInteger(quest.target) then
            table.insert(problems, `{label} target must be a positive integer`)
        end
        for _, problem in RewardConfig.problems(quest.reward, label) do
            table.insert(problems, problem)
        end
    end
    for _, chain in config.chains do
        if #chain.steps == 0 then
            table.insert(problems, `quests chain "{chain.id}" needs at least one step`)
        end
    end
    return problems
end

return QuestsConfigModule
