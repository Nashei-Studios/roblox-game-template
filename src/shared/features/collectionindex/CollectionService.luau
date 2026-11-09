--!strict
--[[
    Server-side use case of the collection index. Discovery is NOT a client claim: the service asks
    the `DiscoveryPort` for the ids derived from persisted data (an ore count above 0, a hatched
    pet, an owned pickaxe) every time, so a forged client message cannot unlock an entry. The mold
    defines the ports; each game adapts them over its own profile (ADR 0046).

    Pure: no Roblox API, loads under Lune. A remote handler calls `view` and `claim` and validates
    the payload at the border (ADR 0012); this module trusts only the ports.
]]

local CollectionIndex = require("./CollectionIndex")

export type Ok<T> = { ok: true, value: T }
export type Err<E> = { ok: false, error: E }
export type Result<T, E> = Ok<T> | Err<E>

-- Ids the player has found, derived from persisted data. May contain ids the catalog dropped.
export type DiscoveryPort = {
    discoveredIds: (userId: number) -> { string },
}

-- Milestone ids already claimed, persisted with the player data. `markClaimed` must be durable
-- before the reward is granted (ADR 0016); `release` undoes it when the grant fails.
export type ClaimLedgerPort = {
    claimedIds: (userId: number) -> { string },
    markClaimed: (userId: number, milestoneId: string) -> Result<boolean, string>,
    release: (userId: number, milestoneId: string) -> (),
}

-- Grants the milestone amount (a currency, a multiplier step). The game decides what it is.
export type RewardPort = {
    grant: (userId: number, milestoneId: string, amount: number) -> Result<boolean, string>,
}

export type Deps = {
    catalog: { CollectionIndex.Entry },
    config: CollectionIndex.Config,
    discovery: DiscoveryPort,
    ledger: ClaimLedgerPort,
    reward: RewardPort,
}

export type CollectionService = {
    view: (self: CollectionService, userId: number) -> CollectionIndex.Snapshot,
    claim: (
        self: CollectionService,
        userId: number,
        milestoneId: string
    ) -> Result<CollectionIndex.Snapshot, string>,
}

local Service = {}

--- Builds the service. Raises on an invalid catalog or config: the process must not start with
--- an index that cannot work (the same boot rule as the rest of the template).
function Service.new(deps: Deps): CollectionService
    local problems = CollectionIndex.validate(deps.catalog, deps.config)
    if #problems > 0 then
        error(`collection index config is invalid:\n{table.concat(problems, "\n")}`, 2)
    end

    local self = {} :: CollectionService

    function self.view(_self: CollectionService, userId: number): CollectionIndex.Snapshot
        return CollectionIndex.snapshot(
            deps.catalog,
            deps.config,
            deps.discovery.discoveredIds(userId),
            deps.ledger.claimedIds(userId)
        )
    end

    function self.claim(
        selfArg: CollectionService,
        userId: number,
        milestoneId: string
    ): Result<CollectionIndex.Snapshot, string>
        local decision = CollectionIndex.claim(
            deps.catalog,
            deps.config,
            deps.discovery.discoveredIds(userId),
            deps.ledger.claimedIds(userId),
            milestoneId
        )
        if not decision.ok then
            return { ok = false, error = decision.error }
        end
        local marked = deps.ledger.markClaimed(userId, milestoneId)
        if not marked.ok then
            return { ok = false, error = `ledger: {marked.error}` }
        end
        local granted = deps.reward.grant(userId, milestoneId, decision.value)
        if not granted.ok then
            deps.ledger.release(userId, milestoneId)
            return { ok = false, error = `reward: {granted.error}` }
        end
        return { ok = true, value = selfArg:view(userId) }
    end

    return self
end

return Service
