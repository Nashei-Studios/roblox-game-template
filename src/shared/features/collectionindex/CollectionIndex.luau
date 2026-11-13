--!strict
--[[
    Pure model of a collection index (an ore index, a pet index, a pickaxe index): which entries
    the player has found, the found/total counter, the progress toward a small finite reward and
    the claim rule. Loads under Lune. The game UI paints it;
    the server side is `CollectionService`, which feeds this model from persisted data through
    ports (ADR 0046).

    Invariant the model enforces: an entry the player has not found carries NO name in the
    snapshot. The client cannot leak what the server never sent; it draws a black silhouette of
    the entry icon reference instead.
]]

export type Ok<T> = { ok: true, value: T }
export type Err<E> = { ok: false, error: E }
export type Result<T, E> = Ok<T> | Err<E>

export type Entry = {
    id: string,
    name: string,
    -- Id of the tab this entry belongs to (a rarity, a biome, a page).
    group: string,
    -- Opaque reference the icon slot draws (an asset id, a model name). nil = the slot draws a
    -- plain block; the model never interprets it.
    iconRef: string?,
}

export type Tab = { id: string, label: string }

-- One finite reward step: reached when `atFound` entries are found. `amount` is the value the
-- reward port of the game grants (its meaning is the game's; the mold never names a currency).
export type Milestone = { id: string, atFound: number, amount: number }

export type Config = {
    tabs: { Tab },
    -- Tabs are shown only above this many entries (a short index stays one page).
    tabsAboveEntries: number,
    -- "claim": the player presses a button per milestone. "auto": reaching it applies it, no
    -- button and no remote (the game reads `appliedAmount` itself).
    claimMode: string,
    milestones: { Milestone },
}

export type ViewEntry = {
    id: string,
    found: boolean,
    -- nil while not found: the name never leaves the server.
    name: string?,
    group: string,
    iconRef: string?,
}

export type ViewTab = { id: string, label: string, found: number, total: number }

export type ViewMilestone = {
    id: string,
    atFound: number,
    amount: number,
    reached: boolean,
    claimed: boolean,
    claimable: boolean,
}

export type Snapshot = {
    found: number,
    total: number,
    entries: { ViewEntry },
    showTabs: boolean,
    tabs: { ViewTab },
    milestones: { ViewMilestone },
    -- The first milestone not reached yet; nil when every one is reached.
    nextMilestoneId: string?,
    -- Progress toward the next milestone (found / atFound), 0..1; 1 when none is left.
    barFraction: number,
    -- Sum of `amount` over reached milestones (the figure an "auto" game applies).
    appliedAmount: number,
    -- Sum of `amount` over every milestone (the finite ceiling a bar can lead to).
    maxAmount: number,
}

-- One of: unknown_milestone, not_reached, already_claimed, auto_mode.
export type ClaimError = string

local CollectionIndex = {}

CollectionIndex.CLAIM = "claim"
CollectionIndex.AUTO = "auto"

local function toSet(ids: { string }): { [string]: boolean }
    local set: { [string]: boolean } = {}
    for _, id in ids do
        set[id] = true
    end
    return set
end

--- One problem per invalid catalog and config (empty when valid). Run it at boot and in a test.
function CollectionIndex.validate(catalog: { Entry }, config: Config): { string }
    local problems: { string } = {}
    local tabIds: { [string]: boolean } = {}
    for _, tab in config.tabs do
        if tab.id == "" then
            table.insert(problems, "a tab has no id")
        elseif tabIds[tab.id] then
            table.insert(problems, `tab id "{tab.id}" is repeated`)
        end
        tabIds[tab.id] = true
    end
    local seen: { [string]: boolean } = {}
    for index, entry in catalog do
        if entry.id == "" then
            table.insert(problems, `entry {index} has no id`)
        elseif seen[entry.id] then
            table.insert(problems, `entry id "{entry.id}" is repeated`)
        end
        seen[entry.id] = true
        if entry.name == "" then
            table.insert(problems, `entry "{entry.id}" has no name`)
        end
        if not tabIds[entry.group] then
            table.insert(problems, `entry "{entry.id}" points at unknown tab "{entry.group}"`)
        end
    end
    if config.claimMode ~= CollectionIndex.CLAIM and config.claimMode ~= CollectionIndex.AUTO then
        table.insert(problems, `claimMode must be "claim" or "auto", got "{config.claimMode}"`)
    end
    if #config.milestones == 0 then
        table.insert(problems, "at least one milestone is required (the bar leads somewhere)")
    end
    local previous = 0
    local milestoneIds: { [string]: boolean } = {}
    for _, milestone in config.milestones do
        if milestone.id == "" then
            table.insert(problems, "a milestone has no id")
        elseif milestoneIds[milestone.id] then
            table.insert(problems, `milestone id "{milestone.id}" is repeated`)
        end
        milestoneIds[milestone.id] = true
        if milestone.atFound <= previous then
            table.insert(
                problems,
                `milestone "{milestone.id}" must be above the previous one (strictly growing)`
            )
        end
        if milestone.atFound > #catalog then
            table.insert(
                problems,
                `milestone "{milestone.id}" needs {milestone.atFound} of {#catalog} entries`
            )
        end
        local amount = milestone.amount
        if amount ~= amount or amount <= 0 or amount == math.huge then
            table.insert(problems, `milestone "{milestone.id}" amount must be finite and above 0`)
        end
        previous = milestone.atFound
    end
    return problems
end

--- The discovered ids that exist in the catalog, without duplicates, in catalog order. An id the
--- catalog does not know (a removed entry still in a save) is dropped, never counted.
function CollectionIndex.discoveredIn(catalog: { Entry }, ids: { string }): { string }
    local set = toSet(ids)
    local kept: { string } = {}
    for _, entry in catalog do
        if set[entry.id] then
            table.insert(kept, entry.id)
        end
    end
    return kept
end

--- The snapshot the server sends and the panel draws. `claimedIds` holds milestone ids already
--- claimed (ignored in "auto" mode, where reaching a milestone applies it).
function CollectionIndex.snapshot(
    catalog: { Entry },
    config: Config,
    discoveredIds: { string },
    claimedIds: { string }
): Snapshot
    local discovered = toSet(CollectionIndex.discoveredIn(catalog, discoveredIds))
    local claimed = toSet(claimedIds)
    local isAuto = config.claimMode == CollectionIndex.AUTO

    local entries: { ViewEntry } = {}
    local found = 0
    local perTab: { [string]: { found: number, total: number } } = {}
    for _, tab in config.tabs do
        perTab[tab.id] = { found = 0, total = 0 }
    end
    for _, entry in catalog do
        local isFound = discovered[entry.id] == true
        if isFound then
            found += 1
        end
        local bucket = perTab[entry.group]
        if bucket ~= nil then
            bucket.total += 1
            if isFound then
                bucket.found += 1
            end
        end
        table.insert(entries, {
            id = entry.id,
            found = isFound,
            name = if isFound then entry.name else nil,
            group = entry.group,
            iconRef = entry.iconRef,
        })
    end

    local tabs: { ViewTab } = {}
    for _, tab in config.tabs do
        local bucket = perTab[tab.id]
        table.insert(
            tabs,
            { id = tab.id, label = tab.label, found = bucket.found, total = bucket.total }
        )
    end

    local milestones: { ViewMilestone } = {}
    local nextId: string? = nil
    local nextAt = 0
    local applied = 0
    local maxAmount = 0
    for _, milestone in config.milestones do
        local reached = found >= milestone.atFound
        local isClaimed = if isAuto then reached else claimed[milestone.id] == true
        table.insert(milestones, {
            id = milestone.id,
            atFound = milestone.atFound,
            amount = milestone.amount,
            reached = reached,
            claimed = isClaimed,
            claimable = reached and not isClaimed and not isAuto,
        })
        maxAmount += milestone.amount
        if reached then
            applied += milestone.amount
        elseif nextId == nil then
            nextId = milestone.id
            nextAt = milestone.atFound
        end
    end

    local barFraction = 1
    if nextId ~= nil and nextAt > 0 then
        barFraction = math.clamp(found / nextAt, 0, 1)
    end

    return {
        found = found,
        total = #catalog,
        entries = entries,
        showTabs = #catalog > config.tabsAboveEntries and #config.tabs > 1,
        tabs = tabs,
        milestones = milestones,
        nextMilestoneId = nextId,
        barFraction = barFraction,
        appliedAmount = applied,
        maxAmount = maxAmount,
    }
end

--- Decides a claim from the facts the server holds. Returns the milestone amount to grant.
function CollectionIndex.claim(
    catalog: { Entry },
    config: Config,
    discoveredIds: { string },
    claimedIds: { string },
    milestoneId: string
): Result<number, ClaimError>
    if config.claimMode == CollectionIndex.AUTO then
        return { ok = false, error = "auto_mode" }
    end
    local snapshot = CollectionIndex.snapshot(catalog, config, discoveredIds, claimedIds)
    for _, milestone in snapshot.milestones do
        if milestone.id == milestoneId then
            if milestone.claimed then
                return { ok = false, error = "already_claimed" }
            end
            if not milestone.reached then
                return { ok = false, error = "not_reached" }
            end
            return { ok = true, value = milestone.amount }
        end
    end
    return { ok = false, error = "unknown_milestone" }
end

return CollectionIndex
