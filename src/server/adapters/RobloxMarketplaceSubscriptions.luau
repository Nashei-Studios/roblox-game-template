--!strict
--[[
    Adapter: SubscriptionPort over MarketplaceService:GetUserSubscriptionStatusAsync,
    MarketplaceService:UserOwnsGamePassAsync and Players.UserSubscriptionStatusChanged.
    Engine pieces are injected (ADR 0009) so this file loads under Lune and is tested with
    fakes; Main.server passes the real ones. A pcall failure becomes a typed LookupError that
    keeps the engine message; nothing is swallowed.
    Note: the engine fires the change event only after the purchase modal closes, so a Store tab
    purchase made mid-session is picked up by the periodic poll in Main.server.
]]

-- Structurally identical to ports/SubscriptionPort.luau (local so this file loads under Lune).
type LookupError = { kind: "lookup_failed", message: string }
type SubscriptionStatus = { isSubscribed: boolean }
type SubscriptionPort = {
    statusOf: (
        self: SubscriptionPort,
        userId: number,
        subscriptionId: string
    ) -> { ok: true, value: SubscriptionStatus } | { ok: false, error: LookupError },
    ownsPass: (
        self: SubscriptionPort,
        userId: number,
        passId: number
    ) -> { ok: true, value: boolean } | { ok: false, error: LookupError },
    onChanged: (
        self: SubscriptionPort,
        listener: (userId: number, subscriptionId: string) -> ()
    ) -> () -> (),
}

export type StatusLike = { IsSubscribed: boolean }

export type MarketplaceLike<P> = {
    GetUserSubscriptionStatusAsync: (
        self: unknown,
        player: P,
        subscriptionId: string
    ) -> StatusLike,
    UserOwnsGamePassAsync: (self: unknown, userId: number, passId: number) -> boolean,
}

export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
    -- Connects the engine event; the returned function disconnects it.
    ConnectStatusChanged: (
        self: unknown,
        listener: (player: P, subscriptionId: string) -> ()
    ) -> () -> (),
    UserIdOf: (self: unknown, player: P) -> number,
}

export type Deps<P> = {
    marketplace: MarketplaceLike<P>,
    players: PlayersLike<P>,
}

local RobloxMarketplaceSubscriptions = {}

function RobloxMarketplaceSubscriptions.new<P>(deps: Deps<P>): SubscriptionPort
    local port: SubscriptionPort = {
        statusOf = function(_self: SubscriptionPort, userId: number, subscriptionId: string)
            local player = deps.players:GetPlayerByUserId(userId)
            if player == nil then
                return {
                    ok = false,
                    error = { kind = "lookup_failed", message = "player is not in the server" },
                }
            end
            local loaded, status = pcall(function(): StatusLike
                return deps.marketplace:GetUserSubscriptionStatusAsync(player, subscriptionId)
            end)
            if not loaded then
                return {
                    ok = false,
                    error = {
                        kind = "lookup_failed",
                        message = `GetUserSubscriptionStatusAsync failed: {tostring(status)}`,
                    },
                }
            end
            return { ok = true, value = { isSubscribed = status.IsSubscribed == true } }
        end,
        ownsPass = function(_self: SubscriptionPort, userId: number, passId: number)
            local loaded, owned = pcall(function(): boolean
                return deps.marketplace:UserOwnsGamePassAsync(userId, passId)
            end)
            if not loaded then
                return {
                    ok = false,
                    error = {
                        kind = "lookup_failed",
                        message = `UserOwnsGamePassAsync failed: {tostring(owned)}`,
                    },
                }
            end
            return { ok = true, value = owned == true }
        end,
        onChanged = function(
            _self: SubscriptionPort,
            listener: (userId: number, subscriptionId: string) -> ()
        ): () -> ()
            return deps.players:ConnectStatusChanged(function(player: P, subscriptionId: string)
                listener(deps.players:UserIdOf(player), subscriptionId)
            end)
        end,
    }
    return port
end

return RobloxMarketplaceSubscriptions
