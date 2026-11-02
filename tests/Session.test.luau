--!strict
local Session = require("../src/shared/Session")
local harness = require("./harness")

type Data = { coins: number }

-- In-memory backend that applies the transform against a single stored record.
local function memoryBackend(initial: Session.SessionRecord<Data>?): Session.Backend<Data>
    local stored = initial
    return {
        update = function(_key: string, transform)
            local nextRecord = transform(stored)
            if nextRecord ~= nil then
                stored = nextRecord
            end
            return { ok = true, value = nextRecord }
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("first load creates a record locked by the caller", function()
        local backend = memoryBackend(nil)
        local result = Session.load(backend, "k", { coins = 0 }, "serverA", 100, 1800)
        harness.isTrue(result.ok, "load ok")
        if result.ok then
            harness.equal(result.value.lockOwner, "serverA")
            harness.equal(result.value.version, 1)
        end
    end)

    suite:test("a live lock held by another server blocks the load", function()
        local backend = memoryBackend({
            data = { coins = 5 },
            lockOwner = "serverB",
            lockedAt = 100,
            version = 3,
        })
        local result = Session.load(backend, "k", { coins = 0 }, "serverA", 200, 1800)
        harness.isFalse(result.ok, "load must fail")
        if not result.ok then
            harness.equal(result.error, "locked_by_other_server")
        end
    end)

    suite:test("a stale lock is taken over and data is preserved", function()
        local backend = memoryBackend({
            data = { coins = 5 },
            lockOwner = "serverB",
            lockedAt = 0,
            version = 3,
        })
        local result = Session.load(backend, "k", { coins = 0 }, "serverA", 2000, 1800)
        harness.isTrue(result.ok, "takeover ok")
        if result.ok then
            harness.equal(result.value.data.coins, 5, "coins preserved")
            harness.equal(result.value.lockOwner, "serverA")
            harness.equal(result.value.version, 4)
        end
    end)

    suite:test("save by a non-owner is rejected", function()
        local backend = memoryBackend({
            data = { coins = 5 },
            lockOwner = "serverB",
            lockedAt = 100,
            version = 3,
        })
        local result = Session.save(backend, "k", { coins = 99 }, "serverA", 150, false)
        harness.isFalse(result.ok, "save must fail")
        if not result.ok then
            harness.equal(result.error, "not_lock_owner")
        end
    end)

    suite:test("save with release clears the lock", function()
        local backend = memoryBackend({
            data = { coins = 5 },
            lockOwner = "serverA",
            lockedAt = 100,
            version = 3,
        })
        local result = Session.save(backend, "k", { coins = 9 }, "serverA", 150, true)
        harness.isTrue(result.ok, "save ok")
        if result.ok then
            harness.equal(result.value.lockOwner, nil, "lock released")
            harness.equal(result.value.data.coins, 9)
        end
    end)
end
