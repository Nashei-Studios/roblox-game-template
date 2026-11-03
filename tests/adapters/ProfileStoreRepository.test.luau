--!strict
local ProfileStoreRepository = require("../../src/server/adapters/ProfileStoreRepository")
local harness = require("../harness")

type Data = { coins: number }

type FakeProfile = {
    profile: ProfileStoreRepository.ProfileLike<Data>,
    calls: { string },
    endSession: () -> (),
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
    return { profile = profile, calls = calls, endSession = endSession }
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
        local loaded = ProfileStoreRepository.new(store):load("42")
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
        local loaded = ProfileStoreRepository.new(store):load("42")
        harness.isFalse(loaded.ok, "must fail")
        if not loaded.ok then
            harness.equal(loaded.error, "session_unavailable", "error")
        end
    end)

    suite:test("save schedules a Save while active and reports not_active after the end", function()
        local fake = newProfile({ coins = 0 })
        local store = newStore(fake.profile)
        local loaded = ProfileStoreRepository.new(store):load("1")
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
        local loaded = ProfileStoreRepository.new(store):load("1")
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
        local loaded = ProfileStoreRepository.new(store):load("1")
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
end
