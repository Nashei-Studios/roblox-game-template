--!strict
local CodeRequests = require("../../../src/shared/features/codes/CodeRequests")
local Codes = require("../../../src/shared/ports/Codes")
local Notifier = require("../../../src/shared/ports/Notifier")
local harness = require("../../harness")

type Sent = { kind: string, amount: number }

local function newHandler(
    allowed: boolean,
    outcome: Codes.RedeemResult
): (CodeRequests.CodeRequests, { Sent }, { string })
    local sent: { Sent } = {}
    local redeemed: { string } = {}
    local codes: Codes.Codes = {
        redeem = function(_self: Codes.Codes, _userId: number, text: string): Codes.RedeemResult
            table.insert(redeemed, text)
            return outcome
        end,
        forget = function(_self: Codes.Codes, _userId: number) end,
    }
    local notifier: Notifier.Notifier = {
        notify = function(
            _self: Notifier.Notifier,
            _userId: number,
            kind: string,
            amount: number
        ): Notifier.NotifyError?
            table.insert(sent, { kind = kind, amount = amount })
            return nil
        end,
    }
    local handler = CodeRequests.new({
        codes = codes,
        notifier = notifier,
        allow = function(_userId: number): boolean
            return allowed
        end,
        maxCodeLength = 8,
    })
    return handler, sent, redeemed
end

return function(suite: harness.Harness)
    suite:test("a rate-limited request is dropped silently", function()
        local handler, sent, redeemed = newHandler(false, { ok = false, error = "cooldown" })
        local result = handler:handle(1, "ABC")
        harness.equal(not result.ok and result.reason or "ok", "rate_limited")
        harness.equal(#sent, 0, "no toast")
        harness.equal(#redeemed, 0, "port untouched")
    end)

    suite:test("a non-string, empty or oversized text never reaches the port", function()
        local handler, sent, redeemed = newHandler(true, { ok = false, error = "cooldown" })
        harness.isFalse(handler:handle(1, 42).ok)
        harness.isFalse(handler:handle(1, "123456789").ok)
        harness.isFalse(handler:handle(1, "").ok)
        harness.equal(#redeemed, 0, "port untouched")
        harness.equal(sent[1].kind, "code_invalid")
    end)

    suite:test("a success notifies with the reward amount", function()
        local handler, sent = newHandler(true, { ok = true, value = { code = "ABC", amount = 7 } })
        harness.isTrue(handler:handle(1, "abc").ok, "accepted")
        harness.equal(sent[1].kind, "code_redeemed")
        harness.equal(sent[1].amount, 7)
    end)

    suite:test("each failure maps to its toast kind", function()
        local cases: { { error: Codes.RedeemError, kind: string } } = {
            { error = "cooldown", kind = "code_cooldown" },
            { error = "invalid_code", kind = "code_invalid" },
            { error = "expired", kind = "code_expired" },
            { error = "already_redeemed", kind = "code_used" },
            { error = "no_data", kind = "code_invalid" },
            { error = "grant_failed", kind = "code_invalid" },
        }
        for _, case in cases do
            local handler, sent = newHandler(true, { ok = false, error = case.error })
            local result = handler:handle(1, "abc")
            harness.equal(not result.ok and result.reason or "ok", case.error)
            harness.equal(sent[1].kind, case.kind, case.error)
        end
    end)
end
