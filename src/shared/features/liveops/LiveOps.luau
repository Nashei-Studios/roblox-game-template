--!strict
--[[
    LiveOps-lite: a server-authoritative clock for timed rotations (a new zone every hour, a shop
    restock every few minutes) and recurring event windows (a weekend event). Pure: loads under
    Lune; the clock is injected (`os.time` on the server).

    - Everything is a function of `now`, so every server computes the same answer without a
      store or a message. The client only DISPLAYS the absolute times the server sends; it never
      decides what is active, so a wrong client clock cannot unlock anything.
    - `poll` reports what changed since the last poll (a rotation advanced, an event started or
      ended) so the game can announce it; the first poll only records the baseline.
    - Not here: cross-server events and global events over MessagingService (issue #55 keeps
      those), and any reward. Rewards go through the modules that own them.
]]

export type RotationSlot = {
    -- Stable id, 1 to 32 characters.
    id: string,
    -- Seconds one entry stays active.
    periodSeconds: number,
    -- Unix second at which entry 1 started once; shifts the boundaries (for example to :00).
    anchorSeconds: number,
    -- Ids the game maps to zones, shop stocks, bosses... Cycled in order.
    entries: { string },
}

export type EventWindow = {
    id: string,
    -- Unix second at which the first occurrence starts.
    startsAt: number,
    durationSeconds: number,
    -- nil = happens once; otherwise it starts again every this many seconds.
    repeatEverySeconds: number?,
}

export type LiveOpsConfig = {
    slots: { RotationSlot },
    events: { EventWindow },
}

export type RotationState = {
    slotId: string,
    entry: string,
    -- Absolute period number (monotonic); usable as `rotationIndex` of features/offers.
    periodIndex: number,
    startsAt: number,
    endsAt: number,
    secondsLeft: number,
}

export type EventState = {
    eventId: string,
    startsAt: number,
    endsAt: number,
    secondsLeft: number,
}

export type Change =
    { kind: "rotation", slotId: string, entry: string, periodIndex: number }
    | { kind: "event_started", eventId: string }
    | { kind: "event_ended", eventId: string }

export type Snapshot = { rotations: { RotationState }, activeEvents: { EventState } }

export type LiveOps = {
    rotation: (self: LiveOps, slotId: string) -> RotationState?,
    activeEvents: (self: LiveOps) -> { EventState },
    isActive: (self: LiveOps, eventId: string) -> boolean,
    snapshot: (self: LiveOps) -> Snapshot,
    poll: (self: LiveOps) -> { Change },
}

export type Deps = {
    config: LiveOpsConfig,
    -- Server clock, Unix seconds.
    now: () -> number,
}

local LiveOpsModule = {}

local function isFinite(value: number): boolean
    return value == value and value ~= math.huge and value ~= -math.huge
end

--- One human-readable problem per invalid value (empty when valid).
function LiveOpsModule.validate(config: LiveOpsConfig): { string }
    local problems: { string } = {}
    local seen: { [string]: boolean } = {}
    for _, slot in config.slots do
        local label = `liveops slot "{slot.id}"`
        if slot.id == "" or #slot.id > 32 then
            table.insert(problems, "a liveops slot id must be 1 to 32 characters")
        end
        if seen[slot.id] then
            table.insert(problems, `{label} is declared twice`)
        end
        seen[slot.id] = true
        if not isFinite(slot.periodSeconds) or slot.periodSeconds < 1 then
            table.insert(problems, `{label} periodSeconds must be at least 1`)
        end
        if not isFinite(slot.anchorSeconds) then
            table.insert(problems, `{label} anchorSeconds must be a finite number`)
        end
        if #slot.entries == 0 then
            table.insert(problems, `{label} needs at least one entry`)
        end
    end
    for _, event in config.events do
        local label = `liveops event "{event.id}"`
        if event.id == "" or #event.id > 32 then
            table.insert(problems, "a liveops event id must be 1 to 32 characters")
        end
        if seen[event.id] then
            table.insert(problems, `{label} reuses an id`)
        end
        seen[event.id] = true
        if not isFinite(event.startsAt) then
            table.insert(problems, `{label} startsAt must be a finite number`)
        end
        if not isFinite(event.durationSeconds) or event.durationSeconds < 1 then
            table.insert(problems, `{label} durationSeconds must be at least 1`)
        end
        local every = event.repeatEverySeconds
        if every ~= nil and (not isFinite(every) or every < event.durationSeconds) then
            table.insert(problems, `{label} repeatEverySeconds must be at least its duration`)
        end
    end
    return problems
end

--- The rotation state of `slot` at `now`.
function LiveOpsModule.rotationAt(slot: RotationSlot, now: number): RotationState
    local periodIndex = math.floor((now - slot.anchorSeconds) / slot.periodSeconds)
    local startsAt = slot.anchorSeconds + periodIndex * slot.periodSeconds
    local endsAt = startsAt + slot.periodSeconds
    -- Luau `%` takes the sign of the divisor, so negative periods (before the anchor) still map in range.
    local entry = slot.entries[periodIndex % #slot.entries + 1]
    return {
        slotId = slot.id,
        entry = entry,
        periodIndex = periodIndex,
        startsAt = startsAt,
        endsAt = endsAt,
        secondsLeft = endsAt - now,
    }
end

--- The active occurrence of `event` at `now`, or nil.
function LiveOpsModule.occurrenceAt(event: EventWindow, now: number): EventState?
    if now < event.startsAt then
        return nil
    end
    local every = event.repeatEverySeconds
    local startsAt = event.startsAt
    if every ~= nil then
        startsAt = event.startsAt + math.floor((now - event.startsAt) / every) * every
    end
    local endsAt = startsAt + event.durationSeconds
    if now >= endsAt then
        return nil
    end
    return { eventId = event.id, startsAt = startsAt, endsAt = endsAt, secondsLeft = endsAt - now }
end

function LiveOpsModule.new(deps: Deps): LiveOps
    local config = deps.config
    local lastIndex: { [string]: number } = {}
    local lastActive: { [string]: boolean } = {}
    local baselined = false

    local function activeNow(now: number): { EventState }
        local active: { EventState } = {}
        for _, event in config.events do
            local state = LiveOpsModule.occurrenceAt(event, now)
            if state ~= nil then
                table.insert(active, state)
            end
        end
        return active
    end

    local service: LiveOps
    service = {
        rotation = function(_self: LiveOps, slotId: string): RotationState?
            for _, slot in config.slots do
                if slot.id == slotId then
                    return LiveOpsModule.rotationAt(slot, deps.now())
                end
            end
            return nil
        end,
        activeEvents = function(_self: LiveOps): { EventState }
            return activeNow(deps.now())
        end,
        isActive = function(_self: LiveOps, eventId: string): boolean
            for _, event in config.events do
                if event.id == eventId then
                    return LiveOpsModule.occurrenceAt(event, deps.now()) ~= nil
                end
            end
            return false
        end,
        snapshot = function(_self: LiveOps): Snapshot
            local now = deps.now()
            local rotations: { RotationState } = {}
            for _, slot in config.slots do
                table.insert(rotations, LiveOpsModule.rotationAt(slot, now))
            end
            return { rotations = rotations, activeEvents = activeNow(now) }
        end,
        poll = function(_self: LiveOps): { Change }
            local now = deps.now()
            local changes: { Change } = {}
            local active: { [string]: boolean } = {}
            for _, state in activeNow(now) do
                active[state.eventId] = true
            end
            for _, slot in config.slots do
                local state = LiveOpsModule.rotationAt(slot, now)
                local previous = lastIndex[slot.id]
                if baselined and previous ~= state.periodIndex then
                    table.insert(changes, {
                        kind = "rotation",
                        slotId = slot.id,
                        entry = state.entry,
                        periodIndex = state.periodIndex,
                    })
                end
                lastIndex[slot.id] = state.periodIndex
            end
            if baselined then
                for _, event in config.events do
                    if active[event.id] and not lastActive[event.id] then
                        table.insert(changes, { kind = "event_started", eventId = event.id })
                    elseif lastActive[event.id] and not active[event.id] then
                        table.insert(changes, { kind = "event_ended", eventId = event.id })
                    end
                end
            end
            lastActive = active
            baselined = true
            return changes
        end,
    }
    return service
end

return LiveOpsModule
