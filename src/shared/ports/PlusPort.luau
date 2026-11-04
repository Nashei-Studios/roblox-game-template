--!strict
--[[
    Port: the Roblox Plus sign-up prompt (ADR 0022). Wraps Player.HasRobloxSubscription and
    MarketplaceService:PromptRobloxSubscriptionPurchase. A pack adapter can implement this type
    later without changing callers.
]]

export type PlusError = { kind: "plus_failed", message: string }

export type PlusPort = {
    -- Whether the player has an active Roblox Plus subscription right now (server side).
    hasPlus: (self: PlusPort, userId: number) -> boolean?,
    -- Opens the engine prompt; the player may decline.
    prompt: (self: PlusPort, userId: number) -> { ok: true } | { ok: false, error: PlusError },
    -- Fires when the server sees HasRobloxSubscription change; returns a disconnect function.
    onPlusChanged: (
        self: PlusPort,
        listener: (userId: number, hasPlus: boolean) -> ()
    ) -> () -> (),
}

return {}
