--!strict
--[[
    Contract every ProfileRepository implementation must satisfy (ADR 0010). Run it against
    the in-memory fake in Lune; run it against the ProfileStore adapter once the Luau
    Execution API job exists (ADR 0005).
]]

local harness = require("../../harness")

type Data = { coins: number }

type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }
type ProfileError = "session_unavailable" | "not_active" | "save_failed"
type SaveConfirmError = "not_active" | "timeout"
type ProfileHandle = {
    key: string,
    data: Data,
    isActive: (self: ProfileHandle) -> boolean,
    save: (self: ProfileHandle) -> Result<nil, ProfileError>,
    release: (self: ProfileHandle) -> Result<nil, ProfileError>,
    onSessionEnd: (self: ProfileHandle, listener: () -> ()) -> (),
    confirmSaved: (
        self: ProfileHandle,
        isSaved: (saved: Data) -> boolean,
        timeoutSeconds: number
    ) -> Result<nil, SaveConfirmError>,
}
export type Repository = {
    load: (self: Repository, key: string) -> Result<ProfileHandle, ProfileError>,
}

local function loadOrFail(repository: Repository, key: string): ProfileHandle
    local result = repository:load(key)
    if not result.ok then
        error(`load failed: {result.error}`, 2)
    end
    return result.value
end

--- `makeRepository` returns a fresh, empty repository whose default data is { coins = 0 }.
local contract = {}

function contract.run(suite: harness.Harness, makeRepository: () -> Repository)
    suite:test("first load returns the default data and an active handle", function()
        local handle = loadOrFail(makeRepository(), "p1")
        harness.equal(handle.data.coins, 0, "default coins")
        harness.isTrue(handle:isActive(), "active")
    end)

    suite:test("a second load of a held key is refused", function()
        local repository = makeRepository()
        loadOrFail(repository, "p1")
        local second = repository:load("p1")
        harness.isFalse(second.ok, "second load must fail")
        if not second.ok then
            harness.equal(second.error, "session_unavailable")
        end
    end)

    suite:test("saved data survives release and reload", function()
        local repository = makeRepository()
        local handle = loadOrFail(repository, "p1")
        handle.data.coins = 42
        harness.isTrue(handle:release().ok, "release ok")
        harness.isFalse(handle:isActive(), "inactive after release")
        local again = loadOrFail(repository, "p1")
        harness.equal(again.data.coins, 42, "persisted coins")
    end)

    suite:test("an inactive handle cannot save or release", function()
        local handle = loadOrFail(makeRepository(), "p1")
        handle:release()
        local save = handle:save()
        harness.isFalse(save.ok, "save after release")
        if not save.ok then
            harness.equal(save.error, "not_active")
        end
        harness.isFalse(handle:release().ok, "second release")
    end)

    suite:test("release notifies session-end listeners", function()
        local handle = loadOrFail(makeRepository(), "p1")
        local notified = 0
        handle:onSessionEnd(function()
            notified += 1
        end)
        handle:release()
        harness.equal(notified, 1, "listener calls")
    end)

    suite:test("confirmSaved succeeds once the data reached storage", function()
        local handle = loadOrFail(makeRepository(), "p1")
        handle.data.coins = 7
        local confirmed = handle:confirmSaved(function(saved: Data): boolean
            return saved.coins == 7
        end, 1)
        harness.isTrue(confirmed.ok, "confirmed")
    end)

    suite:test("confirmSaved still confirms data saved by the final release", function()
        local handle = loadOrFail(makeRepository(), "p1")
        handle.data.coins = 9
        handle:release()
        local confirmed = handle:confirmSaved(function(saved: Data): boolean
            return saved.coins == 9
        end, 1)
        harness.isTrue(confirmed.ok, "confirmed after release")
    end)

    suite:test("confirmSaved on an ended session without the data reports not_active", function()
        local handle = loadOrFail(makeRepository(), "p1")
        handle:release()
        local confirmed = handle:confirmSaved(function(saved: Data): boolean
            return saved.coins == 123
        end, 0.1)
        harness.isFalse(confirmed.ok, "not confirmed")
        if not confirmed.ok then
            harness.equal(confirmed.error, "not_active")
        end
    end)

    suite:test("confirmSaved reports timeout when the snapshot never matches", function()
        local handle = loadOrFail(makeRepository(), "p1")
        local confirmed = handle:confirmSaved(function(saved: Data): boolean
            return saved.coins == 123
        end, 0.1)
        harness.isFalse(confirmed.ok, "not confirmed")
        if not confirmed.ok then
            harness.equal(confirmed.error, "timeout")
        end
    end)

    suite:test("keys are independent", function()
        local repository = makeRepository()
        local a = loadOrFail(repository, "a")
        local b = loadOrFail(repository, "b")
        a.data.coins = 1
        harness.equal(b.data.coins, 0, "other key untouched")
    end)
end

return contract
