--!strict
--[[
    Port: live subscription and legacy-pass ownership lookups for the subscriptions module
    (ADR 0022). Callers depend on this type only; a paid pack adapter can implement it later
    without changing them. Every lookup is a typed Result: a failure is never read as "not
    subscribed".
]]

export type LookupError = { kind: "lookup_failed", message: string }

export type SubscriptionStatus = { isSubscribed: boolean }

export type SubscriptionPort = {
    -- Live status from the platform (never from saved data).
    statusOf: (
        self: SubscriptionPort,
        userId: number,
        subscriptionId: string
    ) -> { ok: true, value: SubscriptionStatus } | { ok: false, error: LookupError },
    -- Whether the player owns a legacy game pass that the subscription replaces.
    ownsPass: (
        self: SubscriptionPort,
        userId: number,
        passId: number
    ) -> { ok: true, value: boolean } | { ok: false, error: LookupError },
    -- Registers a listener for status changes; returns a function that disconnects it.
    onChanged: (
        self: SubscriptionPort,
        listener: (userId: number, subscriptionId: string) -> ()
    ) -> () -> (),
}

return {}
