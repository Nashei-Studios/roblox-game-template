--!strict
local RemoteNotifier = require("../../src/server/adapters/RemoteNotifier")
local RemoteSoundPush = require("../../src/server/adapters/RemoteSoundPush")
local harness = require("../harness")

type FakePlayer = { UserId: number }

local function playersOf(online: { [number]: FakePlayer }): RemoteNotifier.PlayersLike<FakePlayer>
    return {
        GetPlayerByUserId = function(_self: unknown, userId: number): FakePlayer?
            return online[userId]
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("notify fires the remote for an online player and a declared kind", function()
        local player: FakePlayer = { UserId = 7 }
        local fired: { { kind: string, amount: number } } = {}
        local notifier = RemoteNotifier.new({
            players = playersOf({ [7] = player }),
            kinds = { win = true },
            fire = function(_player: FakePlayer, kind: string, amount: number)
                table.insert(fired, { kind = kind, amount = amount })
            end,
        })
        harness.isTrue(notifier:notify(7, "win", 12) == nil, "sent")
        harness.equal(fired[1].kind, "win")
        harness.equal(fired[1].amount, 12)
    end)

    suite:test("an undeclared kind is refused before the wire", function()
        local fired = 0
        local notifier = RemoteNotifier.new({
            players = playersOf({ [7] = { UserId = 7 } }),
            kinds = { win = true },
            fire = function(_player: FakePlayer, _kind: string, _amount: number)
                fired += 1
            end,
        })
        harness.equal(notifier:notify(7, "hack", 1), "unknown_kind")
        harness.equal(fired, 0)
    end)

    suite:test("a player who left is reported", function()
        local notifier = RemoteNotifier.new({
            players = playersOf({}),
            kinds = { win = true },
            fire = function(_player: FakePlayer, _kind: string, _amount: number) end,
        })
        harness.equal(notifier:notify(7, "win", 1), "player_gone")
    end)

    suite:test("the amount is clamped to the wire range", function()
        local sent: { number } = {}
        local notifier = RemoteNotifier.new({
            players = playersOf({ [7] = { UserId = 7 } }),
            kinds = { win = true },
            fire = function(_player: FakePlayer, _kind: string, amount: number)
                table.insert(sent, amount)
            end,
        })
        notifier:notify(7, "win", -5)
        notifier:notify(7, "win", 2 ^ 40)
        notifier:notify(7, "win", 3.9)
        harness.equal(sent[1], 0)
        harness.equal(sent[2], 4294967295)
        harness.equal(sent[3], 3)
    end)

    suite:test("sound push clamps to percent and drops for a missing player", function()
        local sent: { { music: number, sfx: number } } = {}
        local pusher = RemoteSoundPush.new({
            players = playersOf({ [7] = { UserId = 7 } }),
            fire = function(_player: FakePlayer, music: number, sfx: number)
                table.insert(sent, { music = music, sfx = sfx })
            end,
        })
        pusher:push(7, { music = 140, sfx = 33.7 })
        pusher:push(8, { music = 10, sfx = 10 })
        harness.equal(#sent, 1, "only the online player")
        harness.equal(sent[1].music, 100)
        harness.equal(sent[1].sfx, 33)
    end)
end
