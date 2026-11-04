--!strict
local RobuxTransferGateway = require("../../../src/shared/ports/RobuxTransferGateway")
local RobuxTransfers = require("../../../src/shared/features/robuxtransfers/RobuxTransfers")
local harness = require("../../harness")

type Fixture = {
    transfers: RobuxTransfers.RobuxTransfers,
    prompts: { string },
    receipts: { string },
    state: { allowed: boolean, present: boolean, fails: boolean },
}

local function newFixture(enabled: boolean): Fixture
    local prompts: { string } = {}
    local receipts: { string } = {}
    local state = { allowed = true, present = true, fails = false }
    local gateway: RobuxTransferGateway.RobuxTransferGateway = {
        prompt = function(_self, senderId: number, receiverId: number, amount: number)
            if state.fails then
                return { ok = false, error = { kind = "transfer_failed", message = "age" } }
            end
            table.insert(prompts, `{senderId}>{receiverId}:{amount}`)
            return { ok = true, value = "req-1" }
        end,
        bindReceipts = function(_self, _handler)
            return function() end
        end,
    }
    local transfers = RobuxTransfers.new({
        config = { enabled = enabled, minAmount = 10, maxAmount = 500 },
        gateway = gateway,
        allow = function(_userId: number): boolean
            return state.allowed
        end,
        isPlayerPresent = function(_userId: number): boolean
            return state.present
        end,
        onReceipt = function(receipt: RobuxTransferGateway.TransferReceipt)
            table.insert(receipts, `{receipt.side}:{receipt.userId}:{receipt.transferRequestId}`)
        end,
    })
    return { transfers = transfers, prompts = prompts, receipts = receipts, state = state }
end

local function reasonOf(result: RobuxTransfers.HandleResult): string
    if result.ok then
        return "ok"
    end
    return result.reason
end

return function(suite: harness.Harness)
    suite:test("off by config: nothing is prompted", function()
        local fixture = newFixture(false)
        harness.equal(reasonOf(fixture.transfers:handle(1, 2, 50)), "disabled", "reason")
        harness.equal(#fixture.prompts, 0, "no prompt")
    end)

    suite:test("a valid request opens the platform prompt and returns the request id", function()
        local fixture = newFixture(true)
        local result = fixture.transfers:handle(1, 2, 50)
        harness.equal(reasonOf(result), "ok", "ok")
        if result.ok then
            harness.equal(result.transferRequestId, "req-1", "request id")
        end
        harness.equal(fixture.prompts[1], "1>2:50", "arguments")
    end)

    suite:test("amount bounds come from Config and must be whole", function()
        local fixture = newFixture(true)
        harness.equal(reasonOf(fixture.transfers:handle(1, 2, 9)), "out_of_range", "below min")
        harness.equal(reasonOf(fixture.transfers:handle(1, 2, 501)), "out_of_range", "above max")
        harness.equal(reasonOf(fixture.transfers:handle(1, 2, 10.5)), "not_an_integer", "fraction")
        harness.equal(reasonOf(fixture.transfers:handle(1, 2, 0 / 0)), "not_finite", "NaN")
        harness.equal(reasonOf(fixture.transfers:handle(1, 2, "50")), "not_a_number", "string")
        harness.equal(#fixture.prompts, 0, "nothing prompted")
    end)

    suite:test("bad receivers, self transfers and flooding are rejected", function()
        local fixture = newFixture(true)
        harness.equal(reasonOf(fixture.transfers:handle(1, -4, 50)), "out_of_range", "negative")
        harness.equal(reasonOf(fixture.transfers:handle(1, "bob", 50)), "not_a_number", "string")
        harness.equal(reasonOf(fixture.transfers:handle(1, 1, 50)), "self_transfer", "self")
        fixture.state.allowed = false
        harness.equal(reasonOf(fixture.transfers:handle(1, 2, 50)), "rate_limited", "limited")
        harness.equal(#fixture.prompts, 0, "nothing prompted")
    end)

    suite:test("a platform refusal (age, consent) is a typed rejection with its detail", function()
        local fixture = newFixture(true)
        fixture.state.fails = true
        local result = fixture.transfers:handle(1, 2, 50)
        harness.equal(reasonOf(result), "prompt_failed", "reason")
        if not result.ok then
            harness.equal(result.detail, "age", "detail")
        end
    end)

    suite:test("receipts: processed when the player is here, deferred when not", function()
        local fixture = newFixture(true)
        local receipt: RobuxTransferGateway.TransferReceipt =
            { side = "sender", userId = 1, transferRequestId = "req-1" }
        harness.equal(fixture.transfers:decideReceipt(receipt), "processed", "present")
        harness.equal(fixture.receipts[1], "sender:1:req-1", "recorded")
        fixture.state.present = false
        harness.equal(fixture.transfers:decideReceipt(receipt), "notProcessedYet", "absent")
        harness.equal(#fixture.receipts, 1, "not recorded again")
    end)
end
