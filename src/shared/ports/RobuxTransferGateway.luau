--!strict
--[[
    Port: in-game Robux transfers between players (ADR 0022). Wraps
    MarketplaceService:PromptRobuxTransferAsync and BindReceiptHandler for the transfer receipt
    types. Age restrictions and parental consent are enforced by the platform inside the prompt:
    a refusal comes back as a typed error, never as a granted transfer.
    A pack adapter can implement this type later without changing callers.
]]

export type TransferError = { kind: "transfer_failed", message: string }

export type ReceiptSide = "sender" | "receiver"

export type TransferReceipt = {
    side: ReceiptSide,
    userId: number,
    transferRequestId: string,
}

export type ReceiptDecision = "processed" | "notProcessedYet"

export type RobuxTransferGateway = {
    -- Opens the platform prompt; returns the transfer request id.
    prompt: (
        self: RobuxTransferGateway,
        senderId: number,
        receiverId: number,
        amount: number
    ) -> { ok: true, value: string } | { ok: false, error: TransferError },
    -- Binds the receipt handlers for both sides; returns a function that unbinds them.
    bindReceipts: (
        self: RobuxTransferGateway,
        handler: (receipt: TransferReceipt) -> ReceiptDecision
    ) -> () -> (),
}

return {}
