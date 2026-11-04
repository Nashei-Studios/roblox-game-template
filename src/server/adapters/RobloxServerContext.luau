--!strict
--[[
    Adapter: ServerContext over DataModel.PrivateServerId, DataModel.PrivateServerOwnerId and
    TeleportService.TeleportInitFailed. Engine pieces are injected (ADR 0009). The retry closure
    re-runs the same TeleportAsync call, so the destination and options of the failed teleport
    are kept (docs: TeleportInitFailed provides what is needed to retry).
]]

-- Structurally identical to ports/ServerContext.luau (local so this file loads under Lune).
type TeleportFailure = {
    userId: number,
    result: string,
    message: string,
    retry: () -> (),
}
type ServerContext = {
    privateServerId: (self: ServerContext) -> string,
    ownerId: (self: ServerContext) -> number,
    onTeleportFailed: (self: ServerContext, listener: (failure: TeleportFailure) -> ()) -> () -> (),
}

export type GameLike = {
    PrivateServerId: string,
    PrivateServerOwnerId: number,
}

-- `P` is the engine Player type, `O` its TeleportOptions type.
export type TeleportLike<P, O> = {
    -- Connects TeleportInitFailed; the returned function disconnects it.
    ConnectInitFailed: (
        self: unknown,
        listener: (
            player: P,
            resultName: string,
            message: string,
            targetPlaceId: number,
            options: O
        ) -> ()
    ) -> () -> (),
    TeleportAsync: (self: unknown, placeId: number, players: { P }, options: O) -> (),
    UserIdOf: (self: unknown, player: P) -> number,
}

export type Deps<P, O> = {
    game: GameLike,
    teleport: TeleportLike<P, O>,
    -- Logs a retry that itself failed (never swallowed silently).
    log: (message: string) -> (),
}

local RobloxServerContext = {}

function RobloxServerContext.new<P, O>(deps: Deps<P, O>): ServerContext
    local context: ServerContext = {
        privateServerId = function(_self: ServerContext): string
            return deps.game.PrivateServerId
        end,
        ownerId = function(_self: ServerContext): number
            return deps.game.PrivateServerOwnerId
        end,
        onTeleportFailed = function(
            _self: ServerContext,
            listener: (failure: TeleportFailure) -> ()
        ): () -> ()
            return deps.teleport:ConnectInitFailed(
                function(
                    player: P,
                    resultName: string,
                    message: string,
                    targetPlaceId: number,
                    options: O
                )
                    listener({
                        userId = deps.teleport:UserIdOf(player),
                        result = resultName,
                        message = message,
                        retry = function()
                            local retried, failure = pcall(function()
                                deps.teleport:TeleportAsync(targetPlaceId, { player }, options)
                            end)
                            if not retried then
                                deps.log(`Teleport retry failed: {tostring(failure)}`)
                            end
                        end,
                    })
                end
            )
        end,
    }
    return context
end

return RobloxServerContext
