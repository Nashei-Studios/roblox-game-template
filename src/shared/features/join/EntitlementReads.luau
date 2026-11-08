--!strict
--[[
    EntitlementReads (ADR 0032, from plus-one-mining ADR 0039 and 0044): reads every entitlement a
    player may hold (game passes, memberships, anything looked up outside the profile) at the same
    time. Pure: loads under Lune; time and task spawning are injected. The slowest read sets the
    time and a deadline bounds the whole thing. An entitlement whose read did not finish by the
    deadline counts as not owned (and is reported), exactly like a failed read. If it answers LATER
    and the player owns it, `onLate` is called so the perk is applied instead of dropped.
]]

export type Entitlement = { name: string, id: number? }

export type Runtime = {
    clock: () -> number,
    wait: (seconds: number) -> (),
    spawn: (fn: () -> ()) -> (),
}

-- Returns whether the player owns it, or nil when the read failed after its retries.
export type ReadOne = (entitlement: Entitlement) -> boolean?

export type Outcome = {
    owned: { string },
    -- Names whose read failed or did not finish by the deadline.
    unread: { string },
}

local POLL_SECONDS = 0.05

local EntitlementReads = {}

function EntitlementReads.readAll(
    entitlements: { Entitlement },
    readOne: ReadOne,
    runtime: Runtime,
    timeoutSeconds: number,
    -- A read that finished after the deadline and says the player owns it.
    onLate: ((entitlement: Entitlement) -> ())?
): Outcome
    local results: { [number]: boolean? } = {}
    local finished: { [number]: boolean } = {}
    local pending = 0
    local closed = false
    for index, entitlement in entitlements do
        if entitlement.id ~= nil then
            pending += 1
            runtime.spawn(function()
                results[index] = readOne(entitlement)
                finished[index] = true
                pending -= 1
                if closed and results[index] == true and onLate ~= nil then
                    onLate(entitlement)
                end
            end)
        end
    end
    local deadline = runtime.clock() + timeoutSeconds
    while pending > 0 and runtime.clock() < deadline do
        runtime.wait(POLL_SECONDS)
    end
    closed = true
    local outcome: Outcome = { owned = {}, unread = {} }
    for index, entitlement in entitlements do
        if entitlement.id ~= nil then
            if finished[index] == true and results[index] ~= nil then
                if results[index] == true then
                    table.insert(outcome.owned, entitlement.name)
                end
            else
                table.insert(outcome.unread, entitlement.name)
            end
        end
    end
    return outcome
end

return EntitlementReads
