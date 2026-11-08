--!strict
--[[
    The win condition of a game, declared in config (vault ADR 0032, pipeline stages 1, 7, 8, 12):
    one hypothesis of who sees which moment, through which borrowed channel, and why they join.
    Pure: loads under Lune; `scripts/win-condition.luau` runs it as a gate.

    Two kinds of finding, kept apart on purpose:
    - `missing`: a field still empty. A template or a game at stage 0 has these; they fail only in
      strict mode (stage 1 closes with none).
    - `problems`: a field that is filled but wrong (a hook of 14 words, a moment id declared twice,
      a metric without a source). They always fail.
    Nothing here measures anything: a measurement plan names WHAT will be read and WHERE; the
    values are written in the game win-condition file with an as_of date, never precompleted.
]]

export type Metric = {
    -- What is read (play-through rate, first play bounce, D1, playtime, clips published...).
    name: string,
    -- Where it is read (Creator Dashboard, Creator Analytics, Victor...).
    source: string,
}

export type WinConditionConfig = {
    -- Who sees which moment, through which channel, and why they join. One or two sentences.
    hypothesis: string,
    -- The hook in under 10 words, understandable without playing.
    hookSentence: string,
    -- Ids of the clip moments the game declares (features/clipmoment). At least one unless solo.
    shareableMomentIds: { string },
    -- The borrowed channel: a group with its member count, a creator, the Moments feed.
    borrowedChannel: string,
    -- True when no other player is visible; then the funny element must carry the clip alone.
    solo: boolean,
    -- The funny or odd element that explains the clip with the sound off.
    funnyElement: string,
    -- The 0 to 250 attempt: what is measured and where.
    measurementPlan: { Metric },
    -- Owner and date of the target (ISO date); the number 250 is Victor target, not Roblox.
    targetOwner: string,
    targetDate: string,
}

export type Report = { problems: { string }, missing: { string } }

local WinCondition = {}

WinCondition.MAX_HOOK_WORDS = 9

--- An empty declaration, the honest state of a template or a game before stage 1.
function WinCondition.empty(): WinConditionConfig
    return {
        hypothesis = "",
        hookSentence = "",
        shareableMomentIds = {},
        borrowedChannel = "",
        solo = false,
        funnyElement = "",
        measurementPlan = {},
        targetOwner = "",
        targetDate = "",
    }
end

local function blank(text: string): boolean
    return string.match(text, "^%s*$") ~= nil
end

local function wordCount(text: string): number
    local count = 0
    for _ in string.gmatch(text, "%S+") do
        count += 1
    end
    return count
end

local function isIsoDate(text: string): boolean
    return string.match(text, "^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

--- Compares the declaration with the checklist. `knownMomentIds` (optional) is the set of ids the
--- game clip-moment config really declares; a shareable id outside it is a problem.
function WinCondition.validate(
    declaration: WinConditionConfig,
    knownMomentIds: { [string]: boolean }?
): Report
    local problems: { string } = {}
    local missing: { string } = {}

    if blank(declaration.hypothesis) then
        table.insert(missing, "hypothesis")
    end
    if blank(declaration.hookSentence) then
        table.insert(missing, "hookSentence")
    elseif wordCount(declaration.hookSentence) > WinCondition.MAX_HOOK_WORDS then
        table.insert(
            problems,
            `winCondition.hookSentence has {wordCount(declaration.hookSentence)} words; the limit is {WinCondition.MAX_HOOK_WORDS}`
        )
    end
    if blank(declaration.borrowedChannel) then
        table.insert(missing, "borrowedChannel")
    end
    if blank(declaration.funnyElement) then
        table.insert(missing, "funnyElement")
    end

    if #declaration.shareableMomentIds == 0 then
        if not declaration.solo then
            table.insert(missing, "shareableMomentIds")
        end
    end
    local seen: { [string]: boolean } = {}
    for _, id in declaration.shareableMomentIds do
        if id == "" then
            table.insert(problems, "winCondition.shareableMomentIds has an empty id")
        elseif seen[id] then
            table.insert(problems, `winCondition.shareableMomentIds repeats "{id}"`)
        end
        seen[id] = true
        if knownMomentIds ~= nil and id ~= "" and not knownMomentIds[id] then
            table.insert(
                problems,
                `winCondition.shareableMomentIds "{id}" is not a declared clip moment`
            )
        end
    end

    if #declaration.measurementPlan == 0 then
        table.insert(missing, "measurementPlan")
    end
    local metrics: { [string]: boolean } = {}
    for _, metric in declaration.measurementPlan do
        if blank(metric.name) or blank(metric.source) then
            table.insert(
                problems,
                "winCondition.measurementPlan needs a name and a source per metric"
            )
        elseif metrics[metric.name] then
            table.insert(problems, `winCondition.measurementPlan repeats "{metric.name}"`)
        end
        metrics[metric.name] = true
    end

    if blank(declaration.targetOwner) then
        table.insert(missing, "targetOwner")
    end
    if blank(declaration.targetDate) then
        table.insert(missing, "targetDate")
    elseif not isIsoDate(declaration.targetDate) then
        table.insert(problems, "winCondition.targetDate must be an ISO date (YYYY-MM-DD)")
    end

    return { problems = problems, missing = missing }
end

return WinCondition
