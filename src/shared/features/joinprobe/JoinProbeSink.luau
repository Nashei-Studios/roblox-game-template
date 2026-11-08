--!strict
--[[
    Persists join probe lines to a DataStore so they can be read from Studio.
    Pure: the store is an injected `UpdateAsync`-like port (ADR 0009), so it loads under Lune.

    One key per player per UTC day (`<YYYY-MM-DD>:<userId>`) so concurrent joins never contend on
    one key. Each key holds the last `CAP` entries. Entries are the ProbeLine fields plus `rx` and
    the server `at` timestamp; the profile Data is never part of them. It never throws: a failed
    write is counted and warned once per server.
]]

local ProbeLine = require("./ProbeLine")

export type Entry = ProbeLine.Fields
export type Transform = (old: { Entry }?) -> { Entry }?
export type StoreLike = {
    UpdateAsync: (self: unknown, key: string, transform: Transform) -> unknown,
}

export type Deps = {
    store: StoreLike,
    -- Unix seconds (os.time).
    now: () -> number,
    -- Called once, on the first failed write of this server.
    warn: (message: string) -> (),
}

export type JoinProbeSink = {
    record: (
        self: JoinProbeSink,
        userId: number,
        fields: ProbeLine.Fields,
        rx: "server" | "client"
    ) -> boolean,
    failures: (self: JoinProbeSink) -> number,
}

local JoinProbeSink = {}

JoinProbeSink.CAP = 40
JoinProbeSink.STORE_NAME = "JoinProbeLog"

--- `YYYY-MM-DD:<userId>` with the UTC date of `unixSeconds`.
function JoinProbeSink.key(unixSeconds: number, userId: number): string
    return `{os.date("!%Y-%m-%d", unixSeconds)}:{userId}`
end

--- The compact stored entry: the probe fields plus `rx` and the server `at` timestamp.
function JoinProbeSink.entry(fields: ProbeLine.Fields, rx: string, at: number): Entry
    local out: Entry = table.clone(fields)
    out.rx = rx
    out.at = at
    return out
end

--- Appends `entry` to `old` and keeps the last `CAP`. Returns a new list.
function JoinProbeSink.append(old: { Entry }?, entry: Entry): { Entry }
    local merged: { Entry } = {}
    if old ~= nil then
        for _, existing in old do
            table.insert(merged, existing)
        end
    end
    table.insert(merged, entry)
    while #merged > JoinProbeSink.CAP do
        table.remove(merged, 1)
    end
    return merged
end

--- Wire only on live servers with both flags on.
function JoinProbeSink.shouldWire(probeOn: boolean, sinkOn: boolean, isStudio: boolean): boolean
    return probeOn and sinkOn and not isStudio
end

function JoinProbeSink.new(deps: Deps): JoinProbeSink
    local failed = 0
    return {
        record = function(
            _self: JoinProbeSink,
            userId: number,
            fields: ProbeLine.Fields,
            rx: "server" | "client"
        ): boolean
            local at = deps.now()
            local entry = JoinProbeSink.entry(fields, rx, at)
            local ok, err = pcall(function()
                deps.store:UpdateAsync(
                    JoinProbeSink.key(at, userId),
                    function(old: { Entry }?): { Entry }?
                        return JoinProbeSink.append(old, entry)
                    end
                )
            end)
            if not ok then
                failed += 1
                if failed == 1 then
                    deps.warn(
                        `JoinProbeSink write failed (further failures are only counted): {err}`
                    )
                end
            end
            return ok
        end,
        failures = function(_self: JoinProbeSink): number
            return failed
        end,
    }
end

return JoinProbeSink
