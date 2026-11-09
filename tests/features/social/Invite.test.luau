--!strict
local HashMapLedger = require("../../../src/shared/features/social/HashMapLedger")
local InviteBoost = require("../../../src/shared/features/social/InviteBoost")
local InviteReward = require("../../../src/shared/features/social/InviteReward")
local PairKey = require("../../../src/shared/features/social/PairKey")
local Referral = require("../../../src/shared/features/social/Referral")
local SocialConfig = require("../../../src/shared/features/social/SocialConfig")
local SocialPerks = require("../../../src/shared/features/social/SocialPerks")
local harness = require("../../harness")

local function decode(text: string): unknown
    if text == "bad" then
        error("not json")
    end
    local inviter = tonumber(string.match(text, "inviter=(%d+)"))
    return { inviter = inviter }
end

local function join(inviter: number?, launch: string?): { [string]: unknown }
    return { ReferredByPlayerId = inviter, LaunchData = launch }
end

type Store = {
    values: { [string]: unknown },
    expirations: { [string]: number },
    failing: boolean,
}

local function newStore(): (HashMapLedger.HashMapLike, Store)
    local store: Store = { values = {}, expirations = {}, failing = false }
    local map: HashMapLedger.HashMapLike = {
        UpdateAsync = function(
            _self: HashMapLedger.HashMapLike,
            key: string,
            transform: (old: unknown) -> unknown,
            expirationSeconds: number
        ): unknown
            if store.failing then
                error("MemoryStore throttled")
            end
            local updated = transform(store.values[key])
            if updated == nil then
                return nil
            end
            store.values[key] = updated
            store.expirations[key] = expirationSeconds
            return updated
        end,
    }
    return map, store
end

return function(suite: harness.Harness)
    suite:test("pair key: order does not matter and the key is canonical", function()
        local forward = PairKey.new(7, 3, 20000)
        local backward = PairKey.new(3, 7, 20000)
        harness.equal(forward.key, backward.key, "same pair")
        harness.equal(forward.key, "invite:20000:3:7", "canonical form")
        harness.equal(forward.low, 3, "low first")
        harness.isTrue(PairKey.new(3, 7, 20001).key ~= forward.key, "another day, another key")
    end)

    suite:test(
        "referral: inviter comes from ReferredByPlayerId and LaunchData must agree",
        function()
            harness.equal(Referral.inviterOf(join(5, nil), decode), 5, "plain")
            harness.equal(Referral.inviterOf(join(5, "inviter=5"), decode), 5, "agrees")
            harness.equal(Referral.inviterOf(join(5, "inviter=6"), decode), nil, "disagrees")
            harness.equal(
                Referral.inviterOf(join(5, "bad"), decode),
                5,
                "unreadable payload ignored"
            )
            harness.equal(
                Referral.inviterOf(join(5, string.rep("x", 201)), decode),
                nil,
                "too long"
            )
            harness.equal(Referral.inviterOf(join(nil, nil), decode), nil, "no referral")
            harness.equal(Referral.inviterOf(join(0, nil), decode), nil, "zero id")
            harness.equal(Referral.inviterOf(join(1.5, nil), decode), nil, "fractional id")
            harness.equal(Referral.inviterOf("x", decode), nil, "not a table")
            harness.equal(Referral.payload(9).inviter, 9, "payload names the inviter")
        end
    )

    suite:test("invite reward: validation, flag off, reversed pair and day change", function()
        local granted: { number } = {}
        local clock = { now = 1000000 }
        local state = { enabled = true }
        local present: { [number]: boolean } = { [10] = true, [20] = true }
        local reward = InviteReward.new({
            enabled = function(): boolean
                return state.enabled
            end,
            now = function(): number
                return clock.now
            end,
            isPresent = function(userId: number): boolean
                return present[userId] == true
            end,
            ledger = InviteReward.memoryLedger(5),
            grant = function(userId: number)
                table.insert(granted, userId)
            end,
            decode = decode,
        })
        state.enabled = false
        harness.equal(reward:onJoin(20, join(10, nil)), "disabled", "flag off")
        harness.equal(#granted, 0, "nothing granted while off")
        state.enabled = true
        harness.equal(reward:onJoin(20, join(nil, nil)), "not_a_referral", "no referral")
        harness.equal(reward:onJoin(10, join(10, nil)), "self_referral", "self")
        harness.equal(reward:onJoin(20, join(77, nil)), "unknown_inviter", "unknown inviter")
        harness.equal(#granted, 0, "rejections grant nothing")
        harness.equal(reward:onJoin(20, join(10, nil)), "granted", "valid")
        harness.equal(#granted, 2, "both get it")
        harness.equal(reward:onJoin(20, join(10, nil)), "already_granted_today", "repeat")
        harness.equal(reward:onJoin(10, join(20, nil)), "already_granted_today", "reversed pair")
        harness.equal(#granted, 2, "idempotent")
        clock.now += 86400
        harness.equal(reward:onJoin(20, join(10, nil)), "granted", "next day pays again")
        harness.equal(#granted, 4, "four grants in two days")
    end)

    suite:test("invite reward: an inviter is paid for at most the daily cap", function()
        local granted: { number } = {}
        local reward = InviteReward.new({
            enabled = function(): boolean
                return true
            end,
            now = function(): number
                return 5 * 86400
            end,
            isPresent = function(_userId: number): boolean
                return true
            end,
            ledger = InviteReward.memoryLedger(2),
            grant = function(userId: number)
                table.insert(granted, userId)
            end,
            decode = decode,
        })
        harness.equal(reward:onJoin(21, join(10, nil)), "granted", "first")
        harness.equal(reward:onJoin(22, join(10, nil)), "granted", "second")
        harness.equal(reward:onJoin(23, join(10, nil)), "inviter_daily_cap", "third is refused")
        harness.equal(#granted, 4, "only two invites paid")
    end)

    suite:test("hash map ledger: atomic claim, unordered key, 24 h expiry", function()
        local map, store = newStore()
        local ledger = HashMapLedger.new(map, 5)
        harness.isTrue(ledger:claimPair(PairKey.new(3, 7, 100)), "first claim wins")
        harness.isFalse(ledger:claimPair(PairKey.new(7, 3, 100)), "reversed pair loses")
        harness.isTrue(ledger:claimPair(PairKey.new(3, 7, 101)), "next day wins")
        harness.equal(store.expirations["invite:100:3:7"], 86400, "expires in 24 h")
        harness.isTrue(store.values["invite:100:7:3"] == nil, "never the directed key")
    end)

    suite:test("hash map ledger: the inviter counter stops at the cap", function()
        local map, store = newStore()
        local ledger = HashMapLedger.new(map, 5)
        for index = 1, 5 do
            harness.isTrue(ledger:takeInviterSlot(10, 100), `slot {index}`)
        end
        harness.isFalse(ledger:takeInviterSlot(10, 100), "sixth refused")
        harness.isTrue(ledger:takeInviterSlot(11, 100), "another inviter")
        harness.isTrue(ledger:takeInviterSlot(10, 101), "another day")
        harness.equal(store.values["invite-count:100:10"], 5, "counter stays at the cap")
    end)

    suite:test("hash map ledger: a failing store means no reward and no error", function()
        local map, store = newStore()
        local ledger = HashMapLedger.new(map, 5)
        store.failing = true
        harness.isFalse(ledger:claimPair(PairKey.new(1, 2, 100)), "claim fails closed")
        harness.isFalse(ledger:takeInviterSlot(1, 100), "slot fails closed")
        store.failing = false
        harness.isTrue(ledger:claimPair(PairKey.new(1, 2, 100)), "recovers afterwards")
    end)

    suite:test("invite boost lasts its window and is not stacked", function()
        local boost = InviteBoost.new()
        harness.equal(boost:multiplier(1, 100), 1, "none before")
        boost:grant(1, 100)
        boost:grant(1, 200)
        harness.equal(boost:multiplier(1, 200), 3, "x3")
        harness.equal(boost:remainingSeconds(1, 200), 900, "one window from the latest grant")
        harness.equal(boost:multiplier(1, 200 + 900), 1, "ended")
        boost:forget(1)
        harness.equal(boost:remainingSeconds(1, 200), 0, "forgotten")
    end)

    suite:test("social perks: product with a ceiling, community at 0, none", function()
        local config = SocialConfig.default
        harness.isTrue(math.abs(SocialPerks.multiplier(config, 50, 10, 1) - 1.65) < 1e-9, "product")
        harness.equal(SocialPerks.multiplier(config, 50, 10, 3), 3, "clipped to the ceiling")
        harness.isTrue(
            math.abs(SocialPerks.multiplier(config, 20, 0, 1) - 1.2) < 1e-9,
            "no community"
        )
        harness.equal(SocialPerks.multiplier(config, 0, 0, 1), 1, "nothing")
        harness.equal(SocialPerks.none().perkMultiplier, 1, "none")
    end)
end
