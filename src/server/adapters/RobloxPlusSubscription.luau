--!strict
--[[
    Adapter: PlusPort over Player.HasRobloxSubscription and
    MarketplaceService:PromptRobloxSubscriptionPurchase. Engine pieces are injected (ADR 0009).
    A prompt that throws becomes a typed PlusError with the engine message.
]]

-- Structurally identical to ports/PlusPort.luau (local so this file loads under Lune).
type PlusError = { kind: "plus_failed", message: string }
type PlusPort = {
    hasPlus: (self: PlusPort, userId: number) -> boolean?,
    prompt: (self: PlusPort, userId: number) -> { ok: true } | { ok: false, error: PlusError },
    onPlusChanged: (
        self: PlusPort,
        listener: (userId: number, hasPlus: boolean) -> ()
    ) -> () -> (),
}

export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
    -- Reads Player.HasRobloxSubscription.
    HasPlus: (self: unknown, player: P) -> boolean,
    -- Connects GetPropertyChangedSignal("HasRobloxSubscription") of a player now and of every
    -- player who joins later; returns a function that disconnects everything.
    ConnectPlusChanged: (self: unknown, listener: (player: P) -> ()) -> () -> (),
    UserIdOf: (self: unknown, player: P) -> number,
}

export type MarketplaceLike<P> = {
    PromptRobloxSubscriptionPurchase: (self: unknown, player: P) -> (),
}

export type Deps<P> = {
    players: PlayersLike<P>,
    marketplace: MarketplaceLike<P>,
}

local RobloxPlusSubscription = {}

function RobloxPlusSubscription.new<P>(deps: Deps<P>): PlusPort
    local port: PlusPort = {
        hasPlus = function(_self: PlusPort, userId: number): boolean?
            local player = deps.players:GetPlayerByUserId(userId)
            if player == nil then
                return nil
            end
            return deps.players:HasPlus(player)
        end,
        prompt = function(_self: PlusPort, userId: number)
            local player = deps.players:GetPlayerByUserId(userId)
            if player == nil then
                return {
                    ok = false,
                    error = { kind = "plus_failed", message = "player is not in the server" },
                }
            end
            local opened, failure = pcall(function()
                deps.marketplace:PromptRobloxSubscriptionPurchase(player)
            end)
            if not opened then
                return {
                    ok = false,
                    error = {
                        kind = "plus_failed",
                        message = `PromptRobloxSubscriptionPurchase failed: {tostring(failure)}`,
                    },
                }
            end
            return { ok = true }
        end,
        onPlusChanged = function(
            _self: PlusPort,
            listener: (userId: number, hasPlus: boolean) -> ()
        ): () -> ()
            return deps.players:ConnectPlusChanged(function(player: P)
                listener(deps.players:UserIdOf(player), deps.players:HasPlus(player))
            end)
        end,
    }
    return port
end

return RobloxPlusSubscription
