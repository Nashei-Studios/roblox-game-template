--!strict
--[[
    Adapter: delivers a player's volumes over the typed SoundSettings remote (server -> client).
    Engine pieces are injected (ADR 0009); tested with fakes under Lune.
]]

export type Volumes = { music: number, sfx: number }

export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
}

export type Deps<P> = {
    players: PlayersLike<P>,
    -- Sends the remote; both values are percentages 0..100 (u8 on the wire).
    fire: (player: P, music: number, sfx: number) -> (),
}

export type RemoteSoundPush = {
    push: (self: RemoteSoundPush, userId: number, volumes: Volumes) -> (),
}

local RemoteSoundPushModule = {}

function RemoteSoundPushModule.new<P>(deps: Deps<P>): RemoteSoundPush
    local pusher: RemoteSoundPush = {
        push = function(_self: RemoteSoundPush, userId: number, volumes: Volumes)
            local player = deps.players:GetPlayerByUserId(userId)
            if player == nil then
                return -- The player left; there is no client to tell.
            end
            deps.fire(
                player,
                math.clamp(math.floor(volumes.music), 0, 100),
                math.clamp(math.floor(volumes.sfx), 0, 100)
            )
        end,
    }
    return pusher
end

return RemoteSoundPushModule
