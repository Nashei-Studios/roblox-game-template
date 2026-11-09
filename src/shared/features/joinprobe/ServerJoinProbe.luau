--!strict
--[[
    Server join timing collector. Pure: loads under Lune. It only records elapsed
    seconds between named stages of one join and builds the report fields; it never changes the
    join. The clock is injected (os.clock in Main.server). Switch it off with the `joinProbe` flag.

    Stages, all measured from PlayerAdded: `join` (playerData:join returned), `entitlements` (owned
    entitlements read), `hello` (the hello sent), `post` (the rest of the join work done).
]]

local ProbeLine = require("./ProbeLine")

export type Stage = "join" | "entitlements" | "hello" | "post"

export type PriorStatus = "found" | "none" | "error" | "pending"

export type PriorHolder = { placeId: number, jobId: string }

-- Extra metadata of the prior holder's record; both parts optional.
export type PriorExtra = { ageS: number?, forceLoadPending: boolean? }

export type Deps = {
    clock: () -> number,
    -- game.JobId of this server.
    jobId: string,
}

export type Report = {
    fields: ProbeLine.Fields,
    line: string,
    -- Seconds from PlayerAdded to the hello (or to the failed join), for the analytics value.
    headlineSeconds: number,
}

export type ServerJoinProbe = {
    begin: (self: ServerJoinProbe, userId: number) -> (),
    mark: (self: ServerJoinProbe, userId: number, stage: Stage) -> (),
    setJoinResult: (self: ServerJoinProbe, userId: number, ok: boolean, profileNil: boolean) -> (),
    setPrior: (
        self: ServerJoinProbe,
        userId: number,
        status: PriorStatus,
        holder: PriorHolder?,
        lookupSeconds: number,
        extra: PriorExtra?
    ) -> (),
    finish: (self: ServerJoinProbe, userId: number) -> Report?,
    -- The join sequence number the first time a client report arrives, nil afterwards (1 per session).
    acceptClient: (self: ServerJoinProbe, userId: number) -> number?,
    forget: (self: ServerJoinProbe, userId: number) -> (),
    -- Seconds the boot warm-up read took; added to every server line. -1 = not measured.
    setBootWarm: (self: ServerJoinProbe, seconds: number) -> (),
    -- The provisional tap batch of this join: what the client claimed and what was
    -- credited. Reported as its own line because it arrives after the join line.
    provisional: (
        self: ServerJoinProbe,
        userId: number,
        claimed: number,
        credited: number
    ) -> Report?,
}

type Entry = {
    seq: number,
    startedAt: number,
    stages: { [string]: number },
    joinOk: boolean?,
    profileNil: boolean?,
    priorStatus: PriorStatus,
    prior: PriorHolder?,
    lookupSeconds: number?,
    priorExtra: PriorExtra?,
    clientAccepted: boolean,
}

local STAGE_FIELDS: { [string]: string } = {
    join = "joinS",
    entitlements = "entitlementsS",
    hello = "helloS",
    post = "postS",
}

local ServerJoinProbeModule = {}

function ServerJoinProbeModule.new(deps: Deps): ServerJoinProbe
    local entries: { [number]: Entry } = {}
    local sequence = 0
    local bootWarmS = -1

    local probe: ServerJoinProbe = {
        begin = function(_self: ServerJoinProbe, userId: number)
            sequence += 1
            entries[userId] = {
                seq = sequence,
                startedAt = deps.clock(),
                stages = {},
                priorStatus = "pending",
                clientAccepted = false,
            }
        end,
        mark = function(_self: ServerJoinProbe, userId: number, stage: Stage)
            local entry = entries[userId]
            if entry == nil or entry.stages[stage] ~= nil then
                return
            end
            entry.stages[stage] = deps.clock() - entry.startedAt
        end,
        setJoinResult = function(
            _self: ServerJoinProbe,
            userId: number,
            ok: boolean,
            profileNil: boolean
        )
            local entry = entries[userId]
            if entry ~= nil then
                entry.joinOk = ok
                entry.profileNil = profileNil
            end
        end,
        setPrior = function(
            _self: ServerJoinProbe,
            userId: number,
            status: PriorStatus,
            holder: PriorHolder?,
            lookupSeconds: number,
            extra: PriorExtra?
        )
            local entry = entries[userId]
            if entry ~= nil then
                entry.priorStatus = status
                entry.prior = holder
                entry.lookupSeconds = lookupSeconds
                entry.priorExtra = extra
            end
        end,
        finish = function(_self: ServerJoinProbe, userId: number): Report?
            local entry = entries[userId]
            if entry == nil then
                return nil
            end
            local fields: ProbeLine.Fields = {
                kind = "server",
                jobId = deps.jobId,
                seq = entry.seq,
                priorStatus = entry.priorStatus,
                bootWarmS = bootWarmS,
            }
            for stage, seconds in entry.stages do
                fields[STAGE_FIELDS[stage]] = seconds
            end
            if entry.joinOk ~= nil then
                fields.joinOk = entry.joinOk
            end
            if entry.profileNil ~= nil then
                fields.profileNil = entry.profileNil
            end
            if entry.lookupSeconds ~= nil then
                fields.lookupS = entry.lookupSeconds
            end
            local prior = entry.prior
            if prior ~= nil then
                fields.priorPlaceId = prior.placeId
                fields.priorJobId = prior.jobId
                fields.priorSameJob = prior.jobId == deps.jobId
                -- Studio servers have an empty JobId: a lock held by a Studio playtest.
                fields.priorStudio = prior.jobId == ""
            end
            local extra = entry.priorExtra
            if extra ~= nil then
                if extra.ageS ~= nil then
                    fields.priorAgeS = extra.ageS
                end
                if extra.forceLoadPending ~= nil then
                    fields.priorForceLoad = extra.forceLoadPending
                end
            end
            local headline = entry.stages.hello or entry.stages.join or 0
            return {
                fields = fields,
                line = ProbeLine.format(fields),
                headlineSeconds = headline,
            }
        end,
        acceptClient = function(_self: ServerJoinProbe, userId: number): number?
            local entry = entries[userId]
            if entry == nil or entry.clientAccepted then
                return nil
            end
            entry.clientAccepted = true
            return entry.seq
        end,
        setBootWarm = function(_self: ServerJoinProbe, seconds: number)
            bootWarmS = seconds
        end,
        provisional = function(
            _self: ServerJoinProbe,
            userId: number,
            claimed: number,
            credited: number
        ): Report?
            local entry = entries[userId]
            if entry == nil then
                return nil
            end
            local atS = deps.clock() - entry.startedAt
            local fields: ProbeLine.Fields = {
                kind = "provisional",
                jobId = deps.jobId,
                seq = entry.seq,
                provisionalTaps = claimed,
                provisionalCredited = credited,
                atS = atS,
            }
            return {
                fields = fields,
                line = ProbeLine.format(fields),
                headlineSeconds = atS,
            }
        end,
        forget = function(_self: ServerJoinProbe, userId: number)
            entries[userId] = nil
        end,
    }
    return probe
end

return ServerJoinProbeModule
