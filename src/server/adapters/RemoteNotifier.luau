--!strict
--[[
    Adapter: the Notifier port over the typed Notify remote (server -> client only; the client
    has no way to call it). The engine pieces are injected (ADR 0009) so this file loads under
    Lune and is tested with fakes. An unknown kind is refused here, so the wire enum can never be
    fed a value Config does not declare.
]]

-- Structurally identical to ports/Notifier.luau (kept local so this file loads under Lune).
type NotifyError = "unknown_kind" | "player_gone"

type Notifier = {
    notify: (self: Notifier, userId: number, kind: string, amount: number) -> NotifyError?,
}

export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
}

export type Deps<P> = {
    players: PlayersLike<P>,
    -- Keys of Config.default.notifications.kinds, as a set.
    kinds: { [string]: boolean },
    -- Sends the Notify remote. The amount is clamped to the wire type (u32) here.
    fire: (player: P, kind: string, amount: number) -> (),
}

-- Largest value of the u32 `amount` field in net/schema.zap.
local MAX_WIRE_AMOUNT = 4294967295

local RemoteNotifier = {}

function RemoteNotifier.new<P>(deps: Deps<P>): Notifier
    local notifier: Notifier = {
        notify = function(
            _self: Notifier,
            userId: number,
            kind: string,
            amount: number
        ): NotifyError?
            if not deps.kinds[kind] then
                return "unknown_kind"
            end
            local player = deps.players:GetPlayerByUserId(userId)
            if player == nil then
                return "player_gone"
            end
            deps.fire(player, kind, math.clamp(math.floor(amount), 0, MAX_WIRE_AMOUNT))
            return nil
        end,
    }
    return notifier
end

return RemoteNotifier
