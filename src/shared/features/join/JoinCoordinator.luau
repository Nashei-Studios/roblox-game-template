--!strict
--[[
    JoinCoordinator (ADR 0032, from plus-one-mining ADR 0039 and 0044). Pure: loads under Lune;
    everything that touches the engine is injected (ADR 0009). It orchestrates what happens around
    the profile session of one joining player, so the player never waits for data:

    - the "entitlement" reads (game passes, memberships, anything the game must look up outside the
      profile), started at PlayerAdded and running in the background;
    - the moment the hello goes out (`helloSent`), which freezes the provisional window;
    - entitlements that arrive before the hello (they ride on it) or after it (applied as a late
      change), and one that answers after the read deadline (`onLate`), applied instead of dropped;
    - the provisional batch: actions the client took before the hello (taps, clicks), one batch per
      session, claim then commit (ProvisionalCredit);
    - the `leaving` flag: once PlayerRemoving marks a player, no branch of the join writes or
      credits for them any more (the race between a slow join and the profile release).
]]

local ProvisionalCredit = require("./ProvisionalCredit")

export type Deps = {
    clock: () -> number,
    -- The most provisional actions a real player can take per second (frozen into the cap).
    maxPerSecond: number,
    spawn: (fn: () -> ()) -> (),
    -- Reads every entitlement at once (yields). `onLate` receives the names that answer after the
    -- deadline.
    readEntitlements: (userId: number, onLate: (names: { string }) -> ()) -> { string },
    -- Merges `names` into the player's entitlements. late = true: the hello is already out, so the
    -- game settles anything paid at the old rate, changes its perks and tells the client.
    applyEntitlements: (userId: number, names: { string }, late: boolean) -> (),
    -- Optional: called once the entitlements are known AND the hello is out, so a game can pay
    -- what a newly known entitlement adds (must be idempotent in the game's service).
    onEntitlementsSettled: ((userId: number) -> ())?,
    -- Credits `count` provisional actions through the swing path and returns how many were really credited.
    creditProvisional: (userId: number, count: number) -> number,
    -- The first entitlement read finished (the join probe's "entitlements" stage). Optional.
    onEntitlementsRead: ((userId: number) -> ())?,
    -- Crediting the provisional batch threw: the reservation was given back. Never swallowed.
    onCreditError: ((userId: number, message: string) -> ())?,
}

export type ProvisionalResult = { claimed: number, credited: number }

export type JoinCoordinator = {
    -- PlayerAdded, before the profile: stamps the server clock and starts the entitlement reads.
    begin: (self: JoinCoordinator, userId: number) -> (),
    -- The profile exists and the hello is out. false when the player is already leaving (nothing
    -- else should be done for them).
    helloSent: (self: JoinCoordinator, userId: number) -> boolean,
    -- PlayerRemoving: from now on nothing writes or credits for this player.
    leaving: (self: JoinCoordinator, userId: number) -> (),
    isLeaving: (self: JoinCoordinator, userId: number) -> boolean,
    -- The one provisional batch. nil when refused (no hello yet, consumed, leaving, junk) or when
    -- crediting failed outright (the reservation is given back).
    provisional: (
        self: JoinCoordinator,
        userId: number,
        claimed: number
    ) -> ProvisionalResult?,
    forget: (self: JoinCoordinator, userId: number) -> (),
}

type State = { joined: boolean, entitlementsDone: boolean, leaving: boolean }

local JoinCoordinatorModule = {}

function JoinCoordinatorModule.new(deps: Deps): JoinCoordinator
    local states: { [number]: State } = {}
    local credit = ProvisionalCredit.new({ clock = deps.clock, maxPerSecond = deps.maxPerSecond })

    local function settle(userId: number)
        local settled = deps.onEntitlementsSettled
        if settled ~= nil then
            settled(userId)
        end
    end

    local function deliver(userId: number, state: State, names: { string })
        if states[userId] ~= state or state.leaving then
            return
        end
        if #names == 0 then
            return
        end
        deps.applyEntitlements(userId, names, state.joined)
        if state.joined then
            settle(userId)
        end
    end

    local coordinator: JoinCoordinator = {
        begin = function(_self: JoinCoordinator, userId: number)
            local state: State = { joined = false, entitlementsDone = false, leaving = false }
            states[userId] = state
            credit:begin(userId)
            deps.spawn(function()
                local owned = deps.readEntitlements(userId, function(names: { string })
                    deliver(userId, state, names)
                end)
                if states[userId] ~= state or state.leaving then
                    return
                end
                state.entitlementsDone = true
                if deps.onEntitlementsRead ~= nil then
                    deps.onEntitlementsRead(userId)
                end
                deliver(userId, state, owned)
            end)
        end,
        helloSent = function(_self: JoinCoordinator, userId: number): boolean
            local state = states[userId]
            if state == nil then
                -- Not begun (a join path without entitlements): the hello still counts.
                credit:begin(userId)
                credit:markHello(userId)
                return true
            end
            if state.leaving then
                return false
            end
            state.joined = true
            credit:markHello(userId)
            if state.entitlementsDone then
                settle(userId)
            end
            return true
        end,
        leaving = function(_self: JoinCoordinator, userId: number)
            local state = states[userId]
            if state ~= nil then
                state.leaving = true
            end
        end,
        isLeaving = function(_self: JoinCoordinator, userId: number): boolean
            local state = states[userId]
            return state ~= nil and state.leaving
        end,
        provisional = function(
            _self: JoinCoordinator,
            userId: number,
            claimed: number
        ): ProvisionalResult?
            local state = states[userId]
            if state == nil or state.leaving or not state.joined then
                return nil
            end
            local allowed = credit:claim(userId, claimed)
            if allowed == nil then
                return nil
            end
            local applied = 0
            local failure = ""
            local ok = xpcall(function()
                applied = deps.creditProvisional(userId, allowed)
            end, function(err: unknown): ()
                failure = tostring(err)
            end)
            if not ok then
                credit:abort(userId)
                if deps.onCreditError ~= nil then
                    deps.onCreditError(userId, failure)
                end
                return nil
            end
            credit:commit(userId, applied)
            return { claimed = math.floor(claimed), credited = applied }
        end,
        forget = function(_self: JoinCoordinator, userId: number)
            states[userId] = nil
            credit:forget(userId)
        end,
    }
    return coordinator
end

return JoinCoordinatorModule
