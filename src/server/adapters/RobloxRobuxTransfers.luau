--!strict
--[[
    Adapter: RobuxTransferGateway over MarketplaceService:PromptRobuxTransferAsync (server-only)
    and BindReceiptHandler for Enum.ReceiptType.RobuxTransferSender / RobuxTransferReceiver.
    Engine pieces are injected (ADR 0009). `BindReceiptHandler` is wired in Main.server with the
    receipt type NAME ("RobuxTransferSender" / "RobuxTransferReceiver") so this file needs no
    Enum. The platform raises the age and consent checks inside the prompt; a throw becomes a
    typed TransferError that keeps the engine message.
]]

-- Structurally identical to ports/RobuxTransferGateway.luau (local so this file loads under Lune).
type TransferError = { kind: "transfer_failed", message: string }
type ReceiptSide = "sender" | "receiver"
type TransferReceipt = { side: ReceiptSide, userId: number, transferRequestId: string }
type ReceiptDecision = "processed" | "notProcessedYet"
type RobuxTransferGateway = {
    prompt: (
        self: RobuxTransferGateway,
        senderId: number,
        receiverId: number,
        amount: number
    ) -> { ok: true, value: string } | { ok: false, error: TransferError },
    bindReceipts: (
        self: RobuxTransferGateway,
        handler: (receipt: TransferReceipt) -> ReceiptDecision
    ) -> () -> (),
}

export type ReceiptInfoLike = { PlayerId: number, TransferRequestId: string }

export type MarketplaceLike<P> = {
    PromptRobuxTransferAsync: (
        self: unknown,
        sender: P,
        receiverUserId: number,
        amount: number
    ) -> string,
    -- Binds a handler for one receipt type name; returns a function that unbinds it.
    BindTransferReceipt: (
        self: unknown,
        receiptTypeName: string,
        handler: (info: ReceiptInfoLike) -> boolean
    ) -> () -> (),
}

export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
}

export type Deps<P> = {
    marketplace: MarketplaceLike<P>,
    players: PlayersLike<P>,
}

local RobloxRobuxTransfers = {}

function RobloxRobuxTransfers.new<P>(deps: Deps<P>): RobuxTransferGateway
    local gateway: RobuxTransferGateway = {
        prompt = function(
            _self: RobuxTransferGateway,
            senderId: number,
            receiverId: number,
            amount: number
        )
            local sender = deps.players:GetPlayerByUserId(senderId)
            if sender == nil then
                return {
                    ok = false,
                    error = { kind = "transfer_failed", message = "sender is not in the server" },
                }
            end
            local prompted, requestId = pcall(function(): string
                return deps.marketplace:PromptRobuxTransferAsync(sender, receiverId, amount)
            end)
            if not prompted then
                return {
                    ok = false,
                    error = {
                        kind = "transfer_failed",
                        message = `PromptRobuxTransferAsync failed: {tostring(requestId)}`,
                    },
                }
            end
            return { ok = true, value = requestId }
        end,
        bindReceipts = function(
            _self: RobuxTransferGateway,
            handler: (receipt: TransferReceipt) -> ReceiptDecision
        ): () -> ()
            local function bind(typeName: string, side: ReceiptSide): () -> ()
                return deps.marketplace:BindTransferReceipt(
                    typeName,
                    function(info: ReceiptInfoLike): boolean
                        local decision = handler({
                            side = side,
                            userId = info.PlayerId,
                            transferRequestId = info.TransferRequestId,
                        })
                        return decision == "processed"
                    end
                )
            end
            local unbindSender = bind("RobuxTransferSender", "sender")
            local unbindReceiver = bind("RobuxTransferReceiver", "receiver")
            return function()
                unbindSender()
                unbindReceiver()
            end
        end,
    }
    return gateway
end

return RobloxRobuxTransfers
