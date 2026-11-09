--!strict
local CollectionIndex = require("../../../src/shared/features/collectionindex/CollectionIndex")
local CollectionService = require("../../../src/shared/features/collectionindex/CollectionService")
local harness = require("../../harness")

local function catalog(count: number): { CollectionIndex.Entry }
    local entries: { CollectionIndex.Entry } = {}
    for index = 1, count do
        table.insert(entries, {
            id = `e{index}`,
            name = `Entry {index}`,
            group = if index % 2 == 0 then "rare" else "common",
            iconRef = `rbxassetid://{index}`,
        })
    end
    return entries
end

local function config(): CollectionIndex.Config
    return {
        tabs = { { id = "common", label = "Common" }, { id = "rare", label = "Rare" } },
        tabsAboveEntries = 20,
        claimMode = "claim",
        milestones = {
            { id = "m1", atFound = 2, amount = 10 },
            { id = "m2", atFound = 4, amount = 25 },
        },
    }
end

local function has(list: { string }, needle: string): boolean
    return string.find(table.concat(list, "|"), needle, 1, true) ~= nil
end

type State = {
    discovered: { string },
    claimed: { string },
    granted: { number },
    failGrant: boolean,
    failMark: boolean,
}

type World = { service: CollectionService.CollectionService, state: State }

local function world(): World
    local state: State = {
        discovered = {},
        claimed = {},
        granted = {},
        failGrant = false,
        failMark = false,
    }
    local service = CollectionService.new({
        catalog = catalog(6),
        config = config(),
        discovery = {
            discoveredIds = function(_userId: number)
                return state.discovered
            end,
        },
        ledger = {
            claimedIds = function(_userId: number)
                return state.claimed
            end,
            markClaimed = function(_userId: number, milestoneId: string)
                if state.failMark then
                    return { ok = false, error = "save_failed" }
                end
                table.insert(state.claimed, milestoneId)
                return { ok = true, value = true }
            end,
            release = function(_userId: number, milestoneId: string)
                local index = table.find(state.claimed, milestoneId)
                if index ~= nil then
                    table.remove(state.claimed, index)
                end
            end,
        },
        reward = {
            grant = function(_userId: number, _milestoneId: string, amount: number)
                if state.failGrant then
                    return { ok = false, error = "no_room" }
                end
                table.insert(state.granted, amount)
                return { ok = true, value = true }
            end,
        },
    })
    return { service = service, state = state }
end

return function(suite: harness.Harness)
    suite:test("a valid catalog and config have no problems", function()
        harness.equal(#CollectionIndex.validate(catalog(6), config()), 0)
    end)

    suite:test(
        "validate reports repeated ids, unknown tabs, bad milestones and bad mode",
        function()
            local entries = catalog(3)
            entries[2].id = "e1"
            entries[3].group = "missing"
            entries[1].name = ""
            local bad = config()
            bad.claimMode = "maybe"
            bad.milestones = {
                { id = "a", atFound = 2, amount = 0 },
                { id = "a", atFound = 2, amount = 5 },
                { id = "", atFound = 9, amount = math.huge },
            }
            local problems = CollectionIndex.validate(entries, bad)
            harness.isTrue(has(problems, 'entry id "e1" is repeated'))
            harness.isTrue(has(problems, 'unknown tab "missing"'))
            harness.isTrue(has(problems, "has no name"))
            harness.isTrue(has(problems, "claimMode must be"))
            harness.isTrue(has(problems, "amount must be finite and above 0"))
            harness.isTrue(has(problems, 'milestone id "a" is repeated'))
            harness.isTrue(has(problems, "strictly growing"))
            harness.isTrue(has(problems, "needs 9 of 3 entries"))
            harness.isTrue(has(problems, "a milestone has no id"))
        end
    )

    suite:test("validate rejects an empty milestone list, empty ids and a repeated tab", function()
        local bad = config()
        bad.milestones = {}
        bad.tabs = {
            { id = "common", label = "A" },
            { id = "common", label = "B" },
            { id = "", label = "C" },
        }
        local entries = catalog(1)
        entries[1].id = ""
        local problems = CollectionIndex.validate(entries, bad)
        harness.isTrue(has(problems, "at least one milestone"))
        harness.isTrue(has(problems, 'tab id "common" is repeated'))
        harness.isTrue(has(problems, "a tab has no id"))
        harness.isTrue(has(problems, "entry 1 has no id"))
    end)

    suite:test("an undiscovered entry carries no name; a found one does", function()
        local snapshot = CollectionIndex.snapshot(catalog(6), config(), { "e2" }, {})
        harness.equal(snapshot.entries[1].found, false)
        harness.equal(snapshot.entries[1].name, nil)
        harness.equal(snapshot.entries[1].iconRef, "rbxassetid://1")
        harness.equal(snapshot.entries[2].found, true)
        harness.equal(snapshot.entries[2].name, "Entry 2")
    end)

    suite:test("found, total and per-tab counters", function()
        local snapshot = CollectionIndex.snapshot(catalog(6), config(), { "e1", "e2", "e4" }, {})
        harness.equal(snapshot.found, 3)
        harness.equal(snapshot.total, 6)
        harness.equal(snapshot.tabs[1].found, 1)
        harness.equal(snapshot.tabs[1].total, 3)
        harness.equal(snapshot.tabs[2].found, 2)
        harness.equal(snapshot.tabs[2].total, 3)
    end)

    suite:test("duplicates and ids the catalog dropped are not counted", function()
        local snapshot = CollectionIndex.snapshot(catalog(6), config(), { "e1", "e1", "gone" }, {})
        harness.equal(snapshot.found, 1)
        harness.equal(#CollectionIndex.discoveredIn(catalog(6), { "e3", "e3", "x", "e1" }), 2)
    end)

    suite:test("the bar leads to the next milestone and clamps", function()
        local none = CollectionIndex.snapshot(catalog(6), config(), {}, {})
        harness.equal(none.barFraction, 0)
        harness.equal(none.nextMilestoneId, "m1")
        local one = CollectionIndex.snapshot(catalog(6), config(), { "e1" }, {})
        harness.equal(one.barFraction, 0.5)
        local three = CollectionIndex.snapshot(catalog(6), config(), { "e1", "e2", "e3" }, {})
        harness.equal(three.nextMilestoneId, "m2")
        harness.equal(three.barFraction, 0.75)
        local all = CollectionIndex.snapshot(catalog(6), config(), { "e1", "e2", "e3", "e4" }, {})
        harness.equal(all.nextMilestoneId, nil)
        harness.equal(all.barFraction, 1)
        harness.equal(all.maxAmount, 35)
    end)

    suite:test("claim mode: reached and unclaimed is claimable; claimed is not", function()
        local snapshot = CollectionIndex.snapshot(catalog(6), config(), { "e1", "e2" }, { "m1" })
        harness.equal(snapshot.milestones[1].reached, true)
        harness.equal(snapshot.milestones[1].claimed, true)
        harness.equal(snapshot.milestones[1].claimable, false)
        harness.equal(snapshot.milestones[2].claimable, false)
        local fresh = CollectionIndex.snapshot(catalog(6), config(), { "e1", "e2" }, {})
        harness.equal(fresh.milestones[1].claimable, true)
        harness.equal(fresh.appliedAmount, 10)
    end)

    suite:test("auto mode applies reached milestones and never offers a claim", function()
        local auto = config()
        auto.claimMode = "auto"
        local snapshot = CollectionIndex.snapshot(catalog(6), auto, { "e1", "e2", "e3" }, {})
        harness.equal(snapshot.appliedAmount, 10)
        harness.equal(snapshot.milestones[1].claimed, true)
        harness.equal(snapshot.milestones[1].claimable, false)
        local decision = CollectionIndex.claim(catalog(6), auto, { "e1", "e2" }, {}, "m1")
        harness.equal(decision.ok, false)
        if not decision.ok then
            harness.equal(decision.error, "auto_mode")
        end
    end)

    suite:test(
        "tabs show only above the configured entry count and with more than one tab",
        function()
            harness.equal(CollectionIndex.snapshot(catalog(20), config(), {}, {}).showTabs, false)
            harness.equal(CollectionIndex.snapshot(catalog(21), config(), {}, {}).showTabs, true)
            local wide = config()
            wide.milestones = { { id = "m1", atFound = 2, amount = 10 } }
            harness.equal(CollectionIndex.snapshot(catalog(21), wide, {}, {}).showTabs, true)
            harness.equal(CollectionIndex.snapshot(catalog(20), wide, {}, {}).showTabs, false)
            local single = config()
            single.tabs = { { id = "common", label = "All" } }
            harness.equal(CollectionIndex.snapshot(catalog(30), single, {}, {}).showTabs, false)
        end
    )

    suite:test("claim decisions: unknown, not reached, already claimed, ok", function()
        local function code(
            milestoneId: string,
            discovered: { string },
            claimed: { string }
        ): string
            local decision =
                CollectionIndex.claim(catalog(6), config(), discovered, claimed, milestoneId)
            if decision.ok then
                return `ok:{decision.value}`
            end
            return decision.error
        end
        harness.equal(code("zzz", { "e1", "e2" }, {}), "unknown_milestone")
        harness.equal(code("m1", { "e1" }, {}), "not_reached")
        harness.equal(code("m1", { "e1", "e2" }, { "m1" }), "already_claimed")
        harness.equal(code("m1", { "e1", "e2" }, {}), "ok:10")
    end)

    suite:test("the service refuses a config that cannot work", function()
        local bad = config()
        bad.milestones = {}
        local ok = pcall(function()
            CollectionService.new({
                catalog = catalog(6),
                config = bad,
                discovery = {
                    discoveredIds = function(_u: number)
                        return {}
                    end,
                },
                ledger = {
                    claimedIds = function(_u: number)
                        return {}
                    end,
                    markClaimed = function(_u: number, _m: string)
                        return { ok = true, value = true }
                    end,
                    release = function(_u: number, _m: string) end,
                },
                reward = {
                    grant = function(_u: number, _m: string, _a: number)
                        return { ok = true, value = true }
                    end,
                },
            })
        end)
        harness.equal(ok, false)
    end)

    suite:test("the service derives discovery from the port on every call", function()
        local w = world()
        local state = w.state
        harness.equal(w.service:view(1).found, 0)
        state.discovered = { "e1", "e2" }
        harness.equal(w.service:view(1).found, 2)
    end)

    suite:test("a claim for an entry set the port does not report is refused", function()
        local w = world()
        local state = w.state
        local result = w.service:claim(1, "m1")
        harness.equal(result.ok, false)
        harness.equal(#state.granted, 0)
    end)

    suite:test("a claim marks the ledger, grants once and cannot be repeated", function()
        local w = world()
        local state = w.state
        state.discovered = { "e1", "e2" }
        local first = w.service:claim(1, "m1")
        harness.equal(first.ok, true)
        harness.equal(state.granted[1], 10)
        harness.equal(state.claimed[1], "m1")
        local again = w.service:claim(1, "m1")
        harness.equal(again.ok, false)
        harness.equal(#state.granted, 1)
    end)

    suite:test("a failed grant releases the ledger so the player can retry", function()
        local w = world()
        local state = w.state
        state.discovered = { "e1", "e2" }
        state.failGrant = true
        local failed = w.service:claim(1, "m1")
        harness.equal(failed.ok, false)
        if not failed.ok then
            harness.isTrue(has({ failed.error }, "reward: no_room"))
        end
        harness.equal(#state.claimed, 0)
        state.failGrant = false
        harness.equal(w.service:claim(1, "m1").ok, true)
    end)

    suite:test("a failed ledger write grants nothing", function()
        local w = world()
        local state = w.state
        state.discovered = { "e1", "e2" }
        state.failMark = true
        local failed = w.service:claim(1, "m1")
        harness.equal(failed.ok, false)
        if not failed.ok then
            harness.isTrue(has({ failed.error }, "ledger: save_failed"))
        end
        harness.equal(#state.granted, 0)
    end)
end
