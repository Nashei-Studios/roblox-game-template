--!strict
local CommunityReward = require("../../../src/shared/features/community-reward/CommunityReward")
local CommunityRewardConfig =
    require("../../../src/shared/features/community-reward/CommunityRewardConfig")
local CommunityRewardRequests =
    require("../../../src/shared/features/community-reward/CommunityRewardRequests")
local FallbackMembership =
    require("../../../src/shared/features/community-reward/FallbackMembership")
local MembershipChecker = require("../../../src/shared/ports/MembershipChecker")
local Notifier = require("../../../src/shared/ports/Notifier")
local ProductGrants = require("../../../src/shared/features/monetization/ProductGrants")
local harness = require("../../harness")

type Fixture = {
    service: CommunityReward.CommunityReward,
    profile: CommunityReward.Profile,
    calls: { number },
    clock: { now: number },
    answer: { value: MembershipChecker.CheckResult, saved: boolean },
}

local function enabledConfig(): CommunityRewardConfig.CommunityRewardConfig
    return {
        enabled = true,
        communityId = 77,
        reward = { kind = "coins", amount = 50 },
        recheckCooldownSeconds = 30,
        promptJoin = true,
    }
end

local function newFixture(config: CommunityRewardConfig.CommunityRewardConfig): Fixture
    local profile: CommunityReward.Profile = { coins = 10, communityRewardClaimed = false }
    local calls: { number } = {}
    local clock = { now = 100 }
    local answer =
        { value = { ok = true, value = true } :: MembershipChecker.CheckResult, saved = true }
    local checker: MembershipChecker.MembershipChecker = {
        isMember = function(
            _self: MembershipChecker.MembershipChecker,
            userId: number,
            _id: number
        )
            table.insert(calls, userId)
            return answer.value
        end,
    }
    local service = CommunityReward.new({
        config = config,
        checker = checker,
        now = function(): number
            return clock.now
        end,
        profileFor = function(userId: number): CommunityReward.Profile?
            if userId == 1 then
                return profile
            end
            return nil
        end,
        grants = ProductGrants.new(CommunityReward.grantTable(config)),
        confirmSaved = function(_userId: number): boolean
            return answer.saved
        end,
    })
    return { service = service, profile = profile, calls = calls, clock = clock, answer = answer }
end

return function(suite: harness.Harness)
    suite:test("a member is granted once and the flag is saved with the coins", function()
        local fixture = newFixture(enabledConfig())
        local first = fixture.service:check(1)
        harness.isTrue(first.ok and first.outcome == "granted" and first.amount == 50, "granted")
        harness.equal(fixture.profile.coins, 60, "coins")
        harness.isTrue(fixture.profile.communityRewardClaimed, "flag")
        fixture.clock.now += 1000
        local again = fixture.service:check(1)
        harness.isTrue(again.ok and again.outcome == "already_claimed", "idempotent")
        harness.equal(fixture.profile.coins, 60, "no second grant")
        harness.equal(#fixture.calls, 1, "no second membership call")
    end)

    suite:test("a player who left the community keeps the reward", function()
        local fixture = newFixture(enabledConfig())
        fixture.service:check(1)
        fixture.answer.value = { ok = true, value = false }
        fixture.clock.now += 1000
        local later = fixture.service:check(1)
        harness.isTrue(later.ok and later.outcome == "already_claimed", "kept")
        harness.equal(fixture.profile.coins, 60, "coins kept")
    end)

    suite:test("a non-member gets no grant and no error", function()
        local fixture = newFixture(enabledConfig())
        fixture.answer.value = { ok = true, value = false }
        local result = fixture.service:check(1)
        harness.isTrue(result.ok and result.outcome == "not_member", "not a member")
        harness.equal(fixture.profile.coins, 10, "unchanged")
    end)

    suite:test("a stale false only delays the grant", function()
        local fixture = newFixture(enabledConfig())
        fixture.answer.value = { ok = true, value = false }
        fixture.service:check(1)
        fixture.answer.value = { ok = true, value = true }
        local early = fixture.service:check(1)
        harness.isTrue(not early.ok and early.error == "cooldown", "cooldown holds the retry")
        fixture.clock.now += 31
        local late = fixture.service:check(1)
        harness.isTrue(late.ok and late.outcome == "granted", "granted after the cooldown")
    end)

    suite:test("disabled, unknown player and failed checks grant nothing", function()
        local config = enabledConfig()
        config.enabled = false
        local off = newFixture(config)
        local disabled = off.service:check(1)
        harness.isTrue(not disabled.ok and disabled.error == "disabled", "disabled")
        harness.equal(#off.calls, 0, "no call while disabled")

        local on = newFixture(enabledConfig())
        local missing = on.service:check(2)
        harness.isTrue(not missing.ok and missing.error == "no_data", "no data")
        on.answer.value = { ok = false, error = { kind = "check_failed", message = "x" } }
        local failed = on.service:check(1)
        harness.isTrue(not failed.ok and failed.error == "check_failed", "check failed")
        harness.equal(on.profile.coins, 10, "unchanged")
    end)

    suite:test("an enabled module without id or reward refuses to grant", function()
        local config = enabledConfig()
        config.reward = nil
        local fixture = newFixture(config)
        local result = fixture.service:check(1)
        harness.isTrue(not result.ok and result.error == "disabled", "no reward configured")
    end)

    suite:test("a save that is not confirmed rolls the grant back", function()
        local fixture = newFixture(enabledConfig())
        fixture.answer.saved = false
        local result = fixture.service:check(1)
        harness.isTrue(not result.ok and result.error == "save_failed", "save_failed")
        harness.equal(fixture.profile.coins, 10, "coins rolled back")
        harness.isFalse(fixture.profile.communityRewardClaimed, "flag rolled back")
        fixture.answer.saved = true
        fixture.clock.now += 31
        local retry = fixture.service:check(1)
        harness.isTrue(retry.ok and retry.outcome == "granted", "a later check grants")
    end)

    suite:test("a failing grant keeps the flag clear", function()
        local config = enabledConfig()
        local fixture = newFixture(config)
        fixture.profile.coins = ProductGrants.MAX_COINS
        local result = fixture.service:check(1)
        harness.isTrue(not result.ok and result.error == "grant_failed", "overflow refused")
        harness.isFalse(fixture.profile.communityRewardClaimed, "flag clear")
    end)

    suite:test("a check made while another one runs is busy, and forget clears state", function()
        local config = enabledConfig()
        local profile: CommunityReward.Profile = { coins = 0, communityRewardClaimed = false }
        local ref: { service: CommunityReward.CommunityReward? } = {}
        local nested: CommunityReward.CheckResult? = nil
        local checker: MembershipChecker.MembershipChecker = {
            isMember = function(
                _self: MembershipChecker.MembershipChecker,
                _userId: number,
                _id: number
            )
                local inner = ref.service
                if inner ~= nil then
                    nested = inner:check(1)
                end
                return { ok = true, value = false } :: MembershipChecker.CheckResult
            end,
        }
        local service = CommunityReward.new({
            config = config,
            checker = checker,
            now = function(): number
                return 100
            end,
            profileFor = function(_userId: number): CommunityReward.Profile?
                return profile
            end,
            grants = ProductGrants.new(CommunityReward.grantTable(config)),
            confirmSaved = function(_userId: number): boolean
                return true
            end,
        })
        ref.service = service
        service:check(1)
        harness.isTrue(nested ~= nil and not nested.ok and nested.error == "busy", "busy")
        service:forget(1)
        local again = service:check(1)
        harness.isTrue(again.ok, "state cleared")
    end)

    suite:test("config validate reports every problem of an enabled module", function()
        local config = enabledConfig()
        harness.equal(#CommunityRewardConfig.validate(config), 0, "valid")
        config.communityId = nil
        config.reward = nil
        config.recheckCooldownSeconds = 0
        harness.equal(#CommunityRewardConfig.validate(config), 3, "id, reward, cooldown")
        config.communityId = 1.5
        config.reward = { kind = "coins", amount = -1 }
        harness.equal(#CommunityRewardConfig.validate(config), 3, "bad id, bad reward, cooldown")
        config.enabled = false
        harness.equal(
            #CommunityRewardConfig.validate(config),
            1,
            "disabled checks only the cooldown"
        )
    end)

    suite:test("requests: rate limit first, toasts for granted and not member", function()
        local fixture = newFixture(enabledConfig())
        local kinds: { string } = {}
        local notifier: Notifier.Notifier = {
            notify = function(
                _self: Notifier.Notifier,
                _userId: number,
                kind: string,
                _amount: number
            )
                table.insert(kinds, kind)
                return nil
            end,
        }
        local allowed = false
        local requests = CommunityRewardRequests.new({
            reward = fixture.service,
            notifier = notifier,
            allow = function(_userId: number): boolean
                return allowed
            end,
        })
        local limited = requests:handle(1)
        harness.isTrue(not limited.ok and limited.reason == "rate_limited", "limited")
        harness.equal(#fixture.calls, 0, "never reached the checker")
        fixture.answer.value = { ok = true, value = false }
        harness.isTrue(requests:onJoin(1).ok, "join check is not rate limited")
        harness.equal(kinds[1], "community_not_member")
        allowed = true
        fixture.answer.value = { ok = true, value = true }
        fixture.clock.now += 31
        harness.isTrue(requests:handle(1).ok, "client check")
        harness.equal(kinds[2], "community_reward_claimed")
        local quiet = requests:handle(1)
        harness.isTrue(quiet.ok and quiet.outcome == "already_claimed", "already claimed")
        harness.equal(#kinds, 2, "no toast for an already claimed reward")
        local failed = requests:onJoin(2)
        harness.isTrue(not failed.ok and failed.reason == "no_data", "no data")
    end)

    suite:test("fallback asks the second source only when the first says no or fails", function()
        local asked = { first = 0, second = 0 }
        local function checker(counter: string, result: MembershipChecker.CheckResult)
            local built: MembershipChecker.MembershipChecker = {
                isMember = function(
                    _self: MembershipChecker.MembershipChecker,
                    _u: number,
                    _c: number
                )
                    asked[counter] += 1
                    return result
                end,
            }
            return built
        end
        local yes: MembershipChecker.CheckResult = { ok = true, value = true }
        local no: MembershipChecker.CheckResult = { ok = true, value = false }
        local broken: MembershipChecker.CheckResult =
            { ok = false, error = { kind = "check_failed", message = "x" } }

        local chained = FallbackMembership.new(checker("first", yes), checker("second", no))
        local firstAnswer = chained:isMember(1, 2)
        harness.isTrue(firstAnswer.ok and firstAnswer.value, "first wins")
        harness.equal(asked.second, 0, "second untouched")

        local stale = FallbackMembership.new(checker("first", no), checker("second", yes))
        local fixed = stale:isMember(1, 2)
        harness.isTrue(fixed.ok and fixed.value, "second source repairs a stale no")

        local bothBroken =
            FallbackMembership.new(checker("first", broken), checker("second", broken))
        harness.isFalse(bothBroken:isMember(1, 2).ok, "error kept")
        local alone = checker("first", no)
        harness.isTrue(FallbackMembership.new(alone, nil) == alone, "no second source: unchanged")
    end)
end
