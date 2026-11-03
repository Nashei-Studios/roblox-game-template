--!strict
local ProfileStoreRepository = require("../../src/server/adapters/ProfileStoreRepository")
local harness = require("../harness")

type Data = { coins: number }

type FakeClock = {
    runtime: ProfileStoreRepository.Runtime,
    now: () -> number,
}

-- A clock that only advances when the code under test waits.
local function newClock(): FakeClock
    local current = 0
    return {
        runtime = {
            clock = function(): number
                return current
            end,
            wait = function(seconds: number)
                current += seconds
            end,
        },
        now = function(): number
            return current
        end,
    }
end

type FakeProfile = {
    profile: ProfileStoreRepository.ProfileLike<Data>,
    calls: { string },
    endSession: () -> (),
    -- Stands in for ProfileStore's OnAfterSave: publishes the data as the confirmed snapshot.
    completeSave: () -> (),
}

local function newProfile(data: Data): FakeProfile
    local calls: { string } = {}
    local active = true
    local listeners: { () -> () } = {}
    local function endSession()
        active = false
        for _, listener in listeners do
            listener()
        end
    end
    local profile: ProfileStoreRepository.ProfileLike<Data> = {
        Data = data,
        LastSavedData = { coins = data.coins },
        IsActive = function(_self: unknown): boolean
            return active
        end,
        Reconcile = function(_self: unknown)
            table.insert(calls, "Reconcile")
        end,
        Save = function(_self: unknown)
            table.insert(calls, "Save")
        end,
        EndSession = function(_self: unknown)
            table.insert(calls, "EndSession")
            endSession()
        end,
        OnSessionEnd = {
            Connect = function(_self: unknown, listener: () -> ()): unknown
                table.insert(listeners, listener)
                return nil
            end,
        },
    }
    local function completeSave()
        profile.LastSavedData = { coins = profile.Data.coins }
    end
    return {
        profile = profile,
        calls = calls,
        endSession = endSession,
        completeSave = completeSave,
    }
end

local function newStore(
    profile: ProfileStoreRepository.ProfileLike<Data>?
): (ProfileStoreRepository.StoreLike<Data>, { string })
    local requestedKeys: { string } = {}
    local store: ProfileStoreRepository.StoreLike<Data> = {
        StartSessionAsync = function(
            _self: unknown,
            profileKey: string,
            _params: { Steal: boolean? }?
        ): ProfileStoreRepository.ProfileLike<Data>?
            table.insert(requestedKeys, profileKey)
            return profile
        end,
    }
    return store, requestedKeys
end

return function(suite: harness.Harness)
    suite:test("load reconciles the profile and exposes its live data", function()
        local fake = newProfile({ coins = 9 })
        local store, keys = newStore(fake.profile)
        local loaded = ProfileStoreRepository.new(store, newClock().runtime):load("42")
        harness.isTrue(loaded.ok, "loaded")
        harness.equal(keys[1], "42", "key")
        harness.equal(fake.calls[1], "Reconcile", "reconcile first")
        if loaded.ok then
            harness.equal(loaded.value.key, "42", "handle key")
            harness.isTrue(loaded.value.data == fake.profile.Data, "same data table")
        end
    end)

    suite:test("an unavailable session maps to session_unavailable", function()
        local store = newStore(nil)
        local loaded = ProfileStoreRepository.new(store, newClock().runtime):load("42")
        harness.isFalse(loaded.ok, "must fail")
        if not loaded.ok then
            harness.equal(loaded.error, "session_unavailable", "error")
        end
    end)

    suite:test("save schedules a Save while active and reports not_active after the end", function()
        local fake = newProfile({ coins = 0 })
        local store = newStore(fake.profile)
        local loaded = ProfileStoreRepository.new(store, newClock().runtime):load("1")
        if not loaded.ok then
            error("load failed")
        end
        harness.isTrue(loaded.value:save().ok, "save ok")
        harness.equal(fake.calls[2], "Save", "Save called")
        fake.endSession()
        local after = loaded.value:save()
        harness.isFalse(after.ok, "save after end")
        if not after.ok then
            harness.equal(after.error, "not_active", "error")
        end
    end)

    suite:test("release ends the session once; a second release is not_active", function()
        local fake = newProfile({ coins = 0 })
        local store = newStore(fake.profile)
        local loaded = ProfileStoreRepository.new(store, newClock().runtime):load("1")
        if not loaded.ok then
            error("load failed")
        end
        harness.isTrue(loaded.value:release().ok, "first release")
        harness.isFalse(loaded.value:isActive(), "inactive")
        local second = loaded.value:release()
        harness.isFalse(second.ok, "second release")
        if not second.ok then
            harness.equal(second.error, "not_active", "error")
        end
    end)

    suite:test("onSessionEnd forwards the listener to the ProfileStore signal", function()
        local fake = newProfile({ coins = 0 })
        local store = newStore(fake.profile)
        local loaded = ProfileStoreRepository.new(store, newClock().runtime):load("1")
        if not loaded.ok then
            error("load failed")
        end
        local fired = 0
        loaded.value:onSessionEnd(function()
            fired += 1
        end)
        fake.endSession()
        harness.equal(fired, 1, "listener calls")
    end)

    suite:test(
        "confirmSaved returns ok once ProfileStore publishes matching LastSavedData",
        function()
            local fake = newProfile({ coins = 0 })
            local clock = newClock()
            local loaded = ProfileStoreRepository.new(newStore(fake.profile), clock.runtime)
                :load("1")
            if not loaded.ok then
                error("load failed")
            end
            fake.profile.Data.coins = 50
            -- The save completes 0.3 s after the adapter asks for it.
            local baseWait = clock.runtime.wait
            clock.runtime.wait = function(seconds: number)
                baseWait(seconds)
                if table.find(fake.calls, "Save") ~= nil and clock.now() >= 0.3 then
                    fake.completeSave()
                end
            end
            local confirmed = loaded.value:confirmSaved(function(saved: Data): boolean
                return saved.coins == 50
            end, 30)
            harness.isTrue(confirmed.ok, "confirmed")
            harness.isTrue(table.find(fake.calls, "Save") ~= nil, "asked ProfileStore to save")
        end
    )

    suite:test(
        "confirmSaved times out when the save never lands, and keeps asking to save",
        function()
            local fake = newProfile({ coins = 0 })
            local clock = newClock()
            local loaded = ProfileStoreRepository.new(newStore(fake.profile), clock.runtime)
                :load("1")
            if not loaded.ok then
                error("load failed")
            end
            fake.profile.Data.coins = 50
            local confirmed = loaded.value:confirmSaved(function(saved: Data): boolean
                return saved.coins == 50
            end, 12)
            harness.isFalse(confirmed.ok, "not confirmed")
            if not confirmed.ok then
                harness.equal(confirmed.error, "timeout", "error")
            end
            local saves = 0
            for _, call in fake.calls do
                if call == "Save" then
                    saves += 1
                end
            end
            harness.equal(saves, 3, "saves at t=0, 5 and 10")
        end
    )

    suite:test("confirmSaved reports not_active when the session ends without the data", function()
        local fake = newProfile({ coins = 0 })
        local clock = newClock()
        local loaded = ProfileStoreRepository.new(newStore(fake.profile), clock.runtime):load("1")
        if not loaded.ok then
            error("load failed")
        end
        fake.profile.Data.coins = 50
        fake.endSession()
        local confirmed = loaded.value:confirmSaved(function(saved: Data): boolean
            return saved.coins == 50
        end, 30)
        harness.isFalse(confirmed.ok, "not confirmed")
        if not confirmed.ok then
            harness.equal(confirmed.error, "not_active", "error")
        end
    end)

    suite:test(
        "ten simultaneous receipts share one Save() per interval (DataStore budget)",
        function()
            local fake = newProfile({ coins = 0 })
            -- A tiny cooperative scheduler: wait() yields and the virtual clock jumps to the next wake-up.
            local current = 0
            local sleepers: { { thread: thread, wakeAt: number } } = {}
            local runtime: ProfileStoreRepository.Runtime = {
                clock = function(): number
                    return current
                end,
                wait = function(seconds: number)
                    coroutine.yield(seconds)
                end,
            }
            local loaded = ProfileStoreRepository.new(newStore(fake.profile), runtime):load("1")
            if not loaded.ok then
                error("load failed")
            end
            local handle = loaded.value
            local results: { string } = {}
            local function park(thread: thread, seconds: number)
                table.insert(sleepers, { thread = thread, wakeAt = current + seconds })
            end
            for _ = 1, 10 do
                local thread = coroutine.create(function()
                    local confirmed = handle:confirmSaved(function(): boolean
                        return false -- the save never lands: the worst case for the budget
                    end, 30)
                    table.insert(results, if confirmed.ok then "ok" else confirmed.error)
                end)
                local _, seconds = coroutine.resume(thread)
                if coroutine.status(thread) ~= "dead" then
                    park(thread, seconds :: number)
                end
            end
            while #sleepers > 0 do
                table.sort(sleepers, function(a, b)
                    return a.wakeAt < b.wakeAt
                end)
                local next = table.remove(sleepers, 1) :: { thread: thread, wakeAt: number }
                current = next.wakeAt
                local _, seconds = coroutine.resume(next.thread)
                if coroutine.status(next.thread) ~= "dead" then
                    park(next.thread, seconds :: number)
                end
            end
            harness.equal(#results, 10, "all waiters finished")
            for _, outcome in results do
                harness.equal(outcome, "timeout", "outcome")
            end
            local saves = 0
            for _, call in fake.calls do
                if call == "Save" then
                    saves += 1
                end
            end
            -- One UpdateAsync per 5 s for the profile (t = 0, 5, ... 25), not one per waiter.
            harness.equal(saves, 6, "Save() calls in 30 s")
            -- 6 per 30 s is 12 per minute: inside 60 + 40 x 1 player even for a one-player experience.
            harness.isTrue(saves * 2 <= 60 + 40 * 1, "within the DataStore budget")
        end
    )
end
