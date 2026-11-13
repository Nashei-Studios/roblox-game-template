--!strict
--[[
    Client join timing collector. Pure: loads under Lune; the clock is injected
    (os.clock in Main.client). Marks are seconds since the client script started, -1 when never
    reached. Also validates the report on the server, because a remote carries data a client
    controls (ADR 0012): every field is bounded.
]]

local ProbeLine = require("./ProbeLine")
local Validation = require("../../net/Validation")

export type Mark =
    "ui"
    | "content"
    | "hello"
    | "action"
    | "actionAck"
    | "root"
    | "intro"
    | "firstTap"

export type WaitEntry = {
    name: string,
    seconds: number,
    timedOut: boolean,
}

export type Report = {
    -- os.clock() when Main.client started: how long the app had been running by then.
    boot: number,
    -- time() when Main.client started: seconds the game had been running.
    gameTime: number,
    ui: number,
    content: number,
    hello: number,
    action: number,
    actionAck: number,
    root: number,
    -- Seconds with Player.GameplayPaused == true in the first PAUSE_WINDOW_SECONDS.
    paused: number,
    -- Seconds from the loader start to the intro overlay showing (ReplicatedFirst), -1 if never.
    intro: number,
    -- Seconds to the first tap, before or after the hello, -1 if never.
    firstTap: number,
    -- Taps made before the hello arrived (the provisional batch).
    provisional: number,
    waits: { WaitEntry },
}

export type Deps = {
    clock: () -> number,
    gameTime: () -> number,
}

export type ClientJoinProbe = {
    mark: (self: ClientJoinProbe, mark: Mark) -> (),
    setPaused: (self: ClientJoinProbe, paused: boolean) -> (),
    recordWait: (self: ClientJoinProbe, name: string, seconds: number, timedOut: boolean) -> (),
    -- A mark measured elsewhere (the loader in ReplicatedFirst): `seconds` as that script saw it.
    markSeconds: (self: ClientJoinProbe, mark: Mark, seconds: number) -> (),
    addProvisional: (self: ClientJoinProbe, count: number) -> (),
    report: (self: ClientJoinProbe) -> Report,
    -- true only the first time: the report is sent once per session.
    claimSend: (self: ClientJoinProbe) -> boolean,
}

local ClientJoinProbeModule = {}

ClientJoinProbeModule.NOT_REACHED = -1
ClientJoinProbeModule.PAUSE_WINDOW_SECONDS = 60
ClientJoinProbeModule.MAX_WAITS = 8
ClientJoinProbeModule.WAIT_NAMES = {
    "world",
    "character",
    "ui",
    "stats",
    "hud",
    "contentRoot",
}

local MAX_SECONDS = 3600
local MAX_CLOCK = 1e8
-- Taps counted before the hello: 12 a second for an hour is far above any real wait.
local MAX_PROVISIONAL = 50000

function ClientJoinProbeModule.new(deps: Deps): ClientJoinProbe
    local startedAt = deps.clock()
    local gameTimeAtStart = deps.gameTime()
    local marks: { [string]: number } = {}
    local waits: { WaitEntry } = {}
    local seenWaits: { [string]: boolean } = {}
    local provisionalTaps = 0
    local pausedTotal = 0
    local pausedSince: number? = nil
    local sent = false

    local function windowEnd(): number
        return startedAt + ClientJoinProbeModule.PAUSE_WINDOW_SECONDS
    end

    local function markOr(name: string): number
        return marks[name] or ClientJoinProbeModule.NOT_REACHED
    end

    local probe: ClientJoinProbe = {
        mark = function(_self: ClientJoinProbe, mark: Mark)
            if marks[mark] == nil then
                marks[mark] = deps.clock() - startedAt
            end
        end,
        markSeconds = function(_self: ClientJoinProbe, mark: Mark, seconds: number)
            if marks[mark] == nil then
                marks[mark] = seconds
            end
        end,
        addProvisional = function(_self: ClientJoinProbe, count: number)
            provisionalTaps += count
        end,
        setPaused = function(_self: ClientJoinProbe, paused: boolean)
            local now = math.min(deps.clock(), windowEnd())
            if paused then
                if pausedSince == nil then
                    pausedSince = now
                end
            elseif pausedSince ~= nil then
                pausedTotal += math.max(0, now - pausedSince)
                pausedSince = nil
            end
        end,
        recordWait = function(
            _self: ClientJoinProbe,
            name: string,
            seconds: number,
            timedOut: boolean
        )
            -- First wait of each name only: a respawn repeats some of them.
            if seenWaits[name] or #waits >= ClientJoinProbeModule.MAX_WAITS then
                return
            end
            seenWaits[name] = true
            table.insert(waits, { name = name, seconds = seconds, timedOut = timedOut })
        end,
        report = function(_self: ClientJoinProbe): Report
            local paused = pausedTotal
            local since = pausedSince
            if since ~= nil then
                paused += math.max(0, math.min(deps.clock(), windowEnd()) - since)
            end
            return {
                boot = startedAt,
                gameTime = gameTimeAtStart,
                ui = markOr("ui"),
                content = markOr("content"),
                hello = markOr("hello"),
                action = markOr("action"),
                actionAck = markOr("actionAck"),
                root = markOr("root"),
                paused = paused,
                intro = markOr("intro"),
                firstTap = markOr("firstTap"),
                provisional = provisionalTaps,
                waits = table.clone(waits),
            }
        end,
        claimSend = function(_self: ClientJoinProbe): boolean
            if sent then
                return false
            end
            sent = true
            return true
        end,
    }
    return probe
end

--- Flat fields of a client report, as printed in the `[JOINPROBE]` line.
function ClientJoinProbeModule.fields(report: Report, extra: ProbeLine.Fields?): ProbeLine.Fields
    local fields: ProbeLine.Fields = {
        kind = "client",
        boot = report.boot,
        gameTime = report.gameTime,
        uiS = report.ui,
        contentS = report.content,
        helloS = report.hello,
        actionS = report.action,
        actionAckS = report.actionAck,
        rootS = report.root,
        pausedS = report.paused,
        introShownS = report.intro,
        firstTapS = report.firstTap,
        provisionalTaps = report.provisional,
    }
    for _, entry in report.waits do
        fields["wait_" .. entry.name] = entry.seconds
        fields["timedOut_" .. entry.name] = entry.timedOut
    end
    if extra ~= nil then
        for key, value in extra do
            fields[key] = value
        end
    end
    return fields
end

export type ValidationResult = { ok: true, value: Report } | { ok: false, error: string }

local function bounded(value: unknown, min: number, max: number, field: string): (number?, string?)
    local checked = Validation.number(value)
    if not checked.ok then
        return nil, field .. ": " .. checked.error
    end
    if checked.value < min or checked.value > max then
        return nil, field .. ": out_of_range"
    end
    return checked.value, nil
end

local RANGES: { { name: string, min: number, max: number } } = {
    { name = "boot", min = 0, max = MAX_CLOCK },
    { name = "gameTime", min = 0, max = MAX_CLOCK },
    { name = "ui", min = -1, max = MAX_SECONDS },
    { name = "content", min = -1, max = MAX_SECONDS },
    { name = "hello", min = -1, max = MAX_SECONDS },
    { name = "action", min = -1, max = MAX_SECONDS },
    { name = "actionAck", min = -1, max = MAX_SECONDS },
    { name = "root", min = -1, max = MAX_SECONDS },
    { name = "paused", min = 0, max = ClientJoinProbeModule.PAUSE_WINDOW_SECONDS + 1 },
    { name = "intro", min = -1, max = MAX_SECONDS },
    { name = "firstTap", min = -1, max = MAX_SECONDS },
    { name = "provisional", min = 0, max = MAX_PROVISIONAL },
}

--- Validates what a client sent: every number finite and bounded, <= 8 waits, names allow-listed.
function ClientJoinProbeModule.validate(raw: unknown): ValidationResult
    if type(raw) ~= "table" then
        return { ok = false, error = "not_a_table" }
    end
    local input = raw :: { [string]: unknown }
    local numbers: { [string]: number } = {}
    for _, range in RANGES do
        local value, problem = bounded(input[range.name], range.min, range.max, range.name)
        if value == nil then
            return { ok = false, error = problem or range.name }
        end
        numbers[range.name] = value
    end
    local rawWaits = input.waits
    if type(rawWaits) ~= "table" then
        return { ok = false, error = "waits: not_a_table" }
    end
    local list = rawWaits :: { unknown }
    if #list > ClientJoinProbeModule.MAX_WAITS then
        return { ok = false, error = "waits: too_many" }
    end
    local waits: { WaitEntry } = {}
    for _, item in list do
        if type(item) ~= "table" then
            return { ok = false, error = "waits: not_a_table" }
        end
        local entry = item :: { [string]: unknown }
        local name = Validation.oneOf(entry.name, ClientJoinProbeModule.WAIT_NAMES)
        if not name.ok then
            return { ok = false, error = "wait name: " .. name.error }
        end
        local seconds, problem = bounded(entry.seconds, 0, MAX_SECONDS, "wait seconds")
        if seconds == nil then
            return { ok = false, error = problem or "wait seconds" }
        end
        local timedOut = Validation.boolean(entry.timedOut)
        if not timedOut.ok then
            return { ok = false, error = "wait timedOut: " .. timedOut.error }
        end
        table.insert(waits, { name = name.value, seconds = seconds, timedOut = timedOut.value })
    end
    return {
        ok = true,
        value = {
            boot = numbers.boot,
            gameTime = numbers.gameTime,
            ui = numbers.ui,
            content = numbers.content,
            hello = numbers.hello,
            action = numbers.action,
            actionAck = numbers.actionAck,
            root = numbers.root,
            paused = numbers.paused,
            intro = numbers.intro,
            firstTap = numbers.firstTap,
            provisional = numbers.provisional,
            waits = waits,
        },
    }
end

return ClientJoinProbeModule
