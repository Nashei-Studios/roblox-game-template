--!strict
--[[
    Load and join checks (ADR 0073), the static half of the perf gate. Pure: loads under Lune; the
    clock and the repository are injected. `scripts/perf-budget` reads the files and reports; the
    rules live here so each one has a test.

    Three rules, all driven by `PerfBudget.load`:
    - Instance and part counts per service of the place export stay under their caps.
    - A session-lock wait ends within the cap, however long the lock holder stays silent.
    - A join issues at most N DataStore requests (session start counts as one).
]]

local PerfBudget = require("./PerfBudget")

export type Limits = PerfBudget.LoadLimits

type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

export type ServiceCount = {
    instances: number,
    parts: number?,
}

-- What the place export says per top-level service.
export type PlaceCounts = { [string]: ServiceCount }

export type Wait = {
    cancel: () -> boolean,
}

-- Session wait under a lock holder that never answers. `build` gets the simulated clock.
export type WaitFactory = (clock: () -> number) -> Wait

export type RequestCounter = {
    record: (self: RequestCounter) -> (),
    total: (self: RequestCounter) -> number,
}

type ProfileError = "session_unavailable" | "not_active" | "save_failed"

type SaveConfirmError = "not_active" | "timeout"

type ProfileHandle<T> = {
    key: string,
    data: T,
    isActive: (self: ProfileHandle<T>) -> boolean,
    save: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    release: (self: ProfileHandle<T>) -> Result<nil, ProfileError>,
    onSessionEnd: (self: ProfileHandle<T>, listener: () -> ()) -> (),
    confirmSaved: (
        self: ProfileHandle<T>,
        isSaved: (saved: T) -> boolean,
        timeoutSeconds: number
    ) -> Result<nil, SaveConfirmError>,
}

type ProfileRepository<T> = {
    load: (self: ProfileRepository<T>, key: string) -> Result<ProfileHandle<T>, ProfileError>,
}

local LoadBudget = {}

local function isFiniteNumber(value: unknown): boolean
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

--- Reads the place export: `{ "services": { "Workspace": { "instances": 12, "parts": 7 } } }`.
--- Anything else is a typed failure, never a silently empty table.
function LoadBudget.readPlaceCounts(decoded: unknown): Result<PlaceCounts, string>
    if type(decoded) ~= "table" then
        return { ok = false, error = "export is not an object" }
    end
    local root = decoded :: { [unknown]: unknown }
    local services = root.services
    if type(services) ~= "table" then
        return { ok = false, error = "export has no `services` object" }
    end
    local counts: PlaceCounts = {}
    for name, entry in services :: { [unknown]: unknown } do
        if type(name) ~= "string" or type(entry) ~= "table" then
            return { ok = false, error = "`services` must map names to objects" }
        end
        local fields = entry :: { [unknown]: unknown }
        if not isFiniteNumber(fields.instances) then
            return { ok = false, error = `{name}.instances must be a non-negative number` }
        end
        local parts = fields.parts
        if parts ~= nil and not isFiniteNumber(parts) then
            return { ok = false, error = `{name}.parts must be a non-negative number` }
        end
        counts[name] = {
            instances = fields.instances :: number,
            parts = parts :: number?,
        }
    end
    return { ok = true, value = counts }
end

--- Failures for every service cap the export exceeds or cannot answer. Sorted by name so the
--- report is stable.
function LoadBudget.instanceProblems(counts: PlaceCounts, limits: Limits): { string }
    local names: { string } = {}
    for name in limits.services do
        table.insert(names, name)
    end
    table.sort(names)
    local problems: { string } = {}
    for _, name in names do
        local cap = limits.services[name]
        local count = counts[name]
        if count == nil then
            table.insert(problems, `place export has no entry for {name}`)
            continue
        end
        if cap.maxInstances ~= nil and count.instances > cap.maxInstances then
            table.insert(problems, `{name} has {count.instances} instances, cap {cap.maxInstances}`)
        end
        if cap.maxParts ~= nil then
            if count.parts == nil then
                table.insert(problems, `place export has no part count for {name}`)
            elseif count.parts > cap.maxParts then
                table.insert(problems, `{name} has {count.parts} parts, cap {cap.maxParts}`)
            end
        end
    end
    return problems
end

--- Seconds a wait lasts when the lock holder never answers: the clock moves `pollSeconds` per poll
--- and the wait ends when `cancel` says so. `math.huge` when it is still waiting at `ceilingSeconds`
--- (an unbounded loop), so a missing limit fails instead of hanging the gate.
function LoadBudget.simulateSessionWait(
    build: WaitFactory,
    pollSeconds: number,
    ceilingSeconds: number
): number
    local now = 0
    local wait = build(function(): number
        return now
    end)
    while not wait.cancel() do
        if now >= ceilingSeconds then
            return math.huge
        end
        now += pollSeconds
    end
    return now
end

function LoadBudget.sessionWaitProblems(waitedSeconds: number, limits: Limits): { string }
    if waitedSeconds > limits.session.maxWaitSeconds then
        local shown = if waitedSeconds == math.huge then "never ends" else `{waitedSeconds} s`
        return { `session-lock wait {shown}, cap {limits.session.maxWaitSeconds} s` }
    end
    return {}
end

--- Ceiling for the simulation: past twice the cap the wait is unbounded for our purposes.
function LoadBudget.waitCeilingSeconds(limits: Limits): number
    return limits.session.maxWaitSeconds * 2 + limits.session.pollSeconds
end

function LoadBudget.dataStoreProblems(requests: number, limits: Limits): { string }
    if requests > limits.dataStore.maxRequestsPerJoin then
        return {
            `join issues {requests} DataStore requests, cap {limits.dataStore.maxRequestsPerJoin}`,
        }
    end
    return {}
end

function LoadBudget.newRequestCounter(): RequestCounter
    local count = 0
    local counter: RequestCounter = {
        record = function(_self: RequestCounter)
            count += 1
        end,
        total = function(_self: RequestCounter): number
            return count
        end,
    }
    return counter
end

--- Wraps a repository so each call that reaches the DataStore is counted: session start (`load`),
--- `save` and `release`. `confirmSaved` waits on a write that `save` already counted.
function LoadBudget.countingRepository<T>(
    inner: ProfileRepository<T>,
    counter: RequestCounter
): ProfileRepository<T>
    local repository: ProfileRepository<T> = {
        load = function(
            _self: ProfileRepository<T>,
            key: string
        ): Result<ProfileHandle<T>, ProfileError>
            counter:record()
            local loaded = inner:load(key)
            if not loaded.ok then
                return loaded
            end
            local handle = loaded.value
            local counted: ProfileHandle<T> = {
                key = handle.key,
                data = handle.data,
                isActive = function(_self: ProfileHandle<T>): boolean
                    return handle:isActive()
                end,
                save = function(_self: ProfileHandle<T>): Result<nil, ProfileError>
                    counter:record()
                    return handle:save()
                end,
                release = function(_self: ProfileHandle<T>): Result<nil, ProfileError>
                    counter:record()
                    return handle:release()
                end,
                onSessionEnd = function(_self: ProfileHandle<T>, listener: () -> ())
                    handle:onSessionEnd(listener)
                end,
                confirmSaved = function(
                    _self: ProfileHandle<T>,
                    isSaved: (saved: T) -> boolean,
                    timeoutSeconds: number
                ): Result<nil, SaveConfirmError>
                    return handle:confirmSaved(isSaved, timeoutSeconds)
                end,
            }
            return { ok = true, value = counted }
        end,
    }
    return repository
end

return LoadBudget
