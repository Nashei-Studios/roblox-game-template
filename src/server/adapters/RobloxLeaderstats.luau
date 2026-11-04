--!strict
--[[
    Adapter: the leaderboards StatView over a player's `leaderstats` folder. The engine pieces are
    injected (ADR 0009): `setValue` creates the folder and the value object on first use and writes
    it. Leaderstats replicate to every client by themselves, so no remote is involved and the
    client has no write path (the server owns these instances).
]]

-- Structurally identical to ports/Leaderboards.luau StatView (local so this file loads under Lune).
type StatView = {
    set: (self: StatView, userId: number, stat: string, value: number) -> (),
    remove: (self: StatView, userId: number) -> (),
}

export type PlayersLike<P> = {
    GetPlayerByUserId: (self: unknown, userId: number) -> P?,
}

export type Deps<P> = {
    players: PlayersLike<P>,
    -- Creates leaderstats/<stat> for the player if missing and sets it. Display names are the
    -- stat keys of Config, so a game renames them there.
    setValue: (player: P, stat: string, value: number) -> (),
}

local RobloxLeaderstats = {}

function RobloxLeaderstats.new<P>(deps: Deps<P>): StatView
    local view: StatView = {
        set = function(_self: StatView, userId: number, stat: string, value: number)
            local player = deps.players:GetPlayerByUserId(userId)
            if player ~= nil then
                deps.setValue(player, stat, value)
            end
        end,
        remove = function(_self: StatView, _userId: number)
            -- The folder is a child of the leaving player and goes away with them.
        end,
    }
    return view
end

return RobloxLeaderstats
