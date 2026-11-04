--!strict
--[[
    Server handler for the RequestRobuxTransfer remote (ADR 0012, ADR 0022). Pure: loads under Lune.
    Docs: production/monetization/robux-transfers. The game earns a share of each transfer made
    by a Plus subscriber; the platform runs the prompt, the safety and age checks and the
    payment. Off by default (`robuxTransfers.enabled = false`).

    The remote carries INTENT only (receiver and amount). Order of checks: enabled, rate limiter,
    `Validation`, then the gateway prompt. Amount bounds come from Config (inside the platform
    range 10..500). Receipts are acknowledged once the player is on this server; nothing is
    granted from a transfer, so a future reward must go through the Monetization ledger.
]]

local Config = require("../../Config")
local RobuxTransferGateway = require("../../ports/RobuxTransferGateway")
local Validation = require("../../net/Validation")

export type Rejection =
    "disabled"
    | "rate_limited"
    | "self_transfer"
    | "prompt_failed"
    | Validation.ValidationError

export type HandleResult =
    { ok: true, transferRequestId: string }
    | { ok: false, reason: Rejection, detail: string? }

export type Deps = {
    config: Config.RobuxTransfersConfig,
    gateway: RobuxTransferGateway.RobuxTransferGateway,
    allow: (userId: number) -> boolean,
    isPlayerPresent: (userId: number) -> boolean,
    -- Records an acknowledged receipt (logging in production).
    onReceipt: (receipt: RobuxTransferGateway.TransferReceipt) -> (),
}

export type RobuxTransfers = {
    handle: (
        self: RobuxTransfers,
        senderId: number,
        receiverId: unknown,
        amount: unknown
    ) -> HandleResult,
    decideReceipt: (
        self: RobuxTransfers,
        receipt: RobuxTransferGateway.TransferReceipt
    ) -> RobuxTransferGateway.ReceiptDecision,
}

-- Largest integer a double represents exactly.
local MAX_USER_ID = 9007199254740991

local RobuxTransfersModule = {}

function RobuxTransfersModule.new(deps: Deps): RobuxTransfers
    local transfers: RobuxTransfers = {
        handle = function(
            _self: RobuxTransfers,
            senderId: number,
            receiverId: unknown,
            amount: unknown
        ): HandleResult
            if not deps.config.enabled then
                return { ok = false, reason = "disabled" }
            end
            if not deps.allow(senderId) then
                return { ok = false, reason = "rate_limited" }
            end
            local receiver = Validation.integerInRange(receiverId, 1, MAX_USER_ID)
            if not receiver.ok then
                return { ok = false, reason = receiver.error }
            end
            local robux =
                Validation.integerInRange(amount, deps.config.minAmount, deps.config.maxAmount)
            if not robux.ok then
                return { ok = false, reason = robux.error }
            end
            if receiver.value == senderId then
                return { ok = false, reason = "self_transfer" }
            end
            local prompted = deps.gateway:prompt(senderId, receiver.value, robux.value)
            if not prompted.ok then
                return { ok = false, reason = "prompt_failed", detail = prompted.error.message }
            end
            return { ok = true, transferRequestId = prompted.value }
        end,
        decideReceipt = function(
            _self: RobuxTransfers,
            receipt: RobuxTransferGateway.TransferReceipt
        ): RobuxTransferGateway.ReceiptDecision
            if not deps.isPlayerPresent(receipt.userId) then
                return "notProcessedYet"
            end
            deps.onReceipt(receipt)
            return "processed"
        end,
    }
    return transfers
end

return RobuxTransfersModule
