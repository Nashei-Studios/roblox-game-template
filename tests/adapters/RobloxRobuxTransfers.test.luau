--!strict
local RobloxRobuxTransfers = require("../../src/server/adapters/RobloxRobuxTransfers")
local RobuxTransferGateway = require("../../src/shared/ports/RobuxTransferGateway")
local harness = require("../harness")

type FakePlayer = { UserId: number }
type ReceiptHandler = (info: RobloxRobuxTransfers.ReceiptInfoLike) -> boolean

local function newGateway(online: boolean, throws: boolean)
    local sender: FakePlayer = { UserId = 1 }
    local calls: { string } = {}
    local handlers: { [string]: ReceiptHandler } = {}
    local unbound: { string } = {}
    local gateway = RobloxRobuxTransfers.new({
        marketplace = {
            PromptRobuxTransferAsync = function(
                _self: unknown,
                who: FakePlayer,
                receiverUserId: number,
                amount: number
            ): string
                if throws then
                    error("under 13")
                end
                table.insert(calls, `{who.UserId}>{receiverUserId}:{amount}`)
                return "req-7"
            end,
            BindTransferReceipt = function(
                _self: unknown,
                typeName: string,
                handler: ReceiptHandler
            ): () -> ()
                handlers[typeName] = handler
                return function()
                    table.insert(unbound, typeName)
                end
            end,
        },
        players = {
            GetPlayerByUserId = function(_self: unknown, userId: number): FakePlayer?
                if online and userId == 1 then
                    return sender
                end
                return nil
            end,
        },
    })
    return gateway, calls, handlers, unbound
end

return function(suite: harness.Harness)
    suite:test("prompt forwards the arguments and returns the request id", function()
        local gateway, calls = newGateway(true, false)
        local result = gateway:prompt(1, 2, 50)
        harness.isTrue(result.ok and result.value == "req-7", "request id")
        harness.equal(calls[1], "1>2:50", "arguments")
    end)

    suite:test("a missing sender and an engine refusal are typed failures", function()
        local gone = newGateway(false, false)
        harness.isFalse(gone:prompt(1, 2, 50).ok, "sender gone")
        local refused = newGateway(true, true)
        local result = refused:prompt(1, 2, 50)
        harness.isFalse(result.ok, "refused")
        if not result.ok then
            harness.isTrue(string.find(result.error.message, "under 13", 1, true) ~= nil, "message")
        end
    end)

    suite:test("receipts bind both sides and map the decision", function()
        local gateway, _calls, handlers, unbound = newGateway(true, false)
        local seen: { string } = {}
        local unbind = gateway:bindReceipts(
            function(
                receipt: RobuxTransferGateway.TransferReceipt
            ): RobuxTransferGateway.ReceiptDecision
                table.insert(seen, `{receipt.side}:{receipt.userId}:{receipt.transferRequestId}`)
                return if receipt.side == "sender" then "processed" else "notProcessedYet"
            end
        )
        harness.isTrue(
            handlers.RobuxTransferSender({ PlayerId = 1, TransferRequestId = "a" }),
            "sender processed"
        )
        harness.isFalse(
            handlers.RobuxTransferReceiver({ PlayerId = 2, TransferRequestId = "a" }),
            "receiver deferred"
        )
        harness.equal(seen[1], "sender:1:a", "sender receipt")
        harness.equal(seen[2], "receiver:2:a", "receiver receipt")
        unbind()
        harness.equal(#unbound, 2, "both unbound")
    end)
end
