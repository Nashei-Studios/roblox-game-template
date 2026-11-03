--!strict
--[[
    Port: finds the purchase ledger of a player (stored inside the player's saved data).
    nil when the player's data is not loaded: the purchase stays unprocessed and Roblox retries.
]]

export type ReceiptLedger = {
    has: (self: ReceiptLedger, purchaseId: string) -> boolean,
    record: (self: ReceiptLedger, purchaseId: string) -> (),
}

export type LedgerProvider = {
    ledgerFor: (self: LedgerProvider, userId: number) -> ReceiptLedger?,
}

return {}
