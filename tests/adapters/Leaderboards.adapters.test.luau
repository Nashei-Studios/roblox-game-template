--!strict
local BoardKey = require("../../src/shared/features/leaderboards/BoardKey")
local OrderedDataStoreBoards = require("../../src/server/adapters/OrderedDataStoreBoards")
local ReplicatedBoardPublisher = require("../../src/server/adapters/ReplicatedBoardPublisher")
local RobloxLeaderstats = require("../../src/server/adapters/RobloxLeaderstats")
local harness = require("../harness")

type FakePlayer = { UserId: number }

return function(suite: harness.Harness)
    suite:test("the store writes floored non-negative integers under Board_<key>", function()
        local opened: { string } = {}
        local written: { string } = {}
        local store = OrderedDataStoreBoards.new({
            openStore = function(name: string): OrderedDataStoreBoards.StoreHandle
                table.insert(opened, name)
                return {
                    write = function(key: string, value: number)
                        table.insert(written, `{key}={value}`)
                    end,
                    read = function(_size: number)
                        return {}
                    end,
                }
            end,
        })
        harness.isTrue(store:setScore("Coins", 7, 12.9).ok, "stored")
        harness.isTrue(store:setScore("Coins", 8, -3).ok, "stored")
        harness.equal(written[1], "7=12")
        harness.equal(written[2], "8=0")
        harness.equal(#opened, 1, "store opened once per key")
        harness.equal(opened[1], "Board_Coins")
    end)

    suite:test("top maps rows to entries, skips bad keys and passes the size", function()
        local seenSize = 0
        local store = OrderedDataStoreBoards.new({
            openStore = function(_name: string): OrderedDataStoreBoards.StoreHandle
                return {
                    write = function(_key: string, _value: number) end,
                    read = function(size: number)
                        seenSize = size
                        return { { key = "5", value = 90 }, { key = "oops", value = 1 } }
                    end,
                }
            end,
        })
        local result = store:top("Coins", 10)
        harness.isTrue(result.ok, "ok")
        if result.ok then
            harness.equal(#result.value, 1, "bad key skipped")
            harness.equal(result.value[1].userId, 5)
        end
        harness.equal(seenSize, 10)
    end)

    suite:test("store failures become typed errors with the message", function()
        local store = OrderedDataStoreBoards.new({
            openStore = function(_name: string): OrderedDataStoreBoards.StoreHandle
                return {
                    write = function(_key: string, _value: number)
                        error("budget exhausted")
                    end,
                    read = function(_size: number)
                        error("503")
                    end,
                }
            end,
        })
        local wrote = store:setScore("Coins", 1, 1)
        harness.isTrue(not wrote.ok and string.find(wrote.error.message, "budget") ~= nil, "write")
        local read = store:top("Coins", 3)
        harness.isTrue(not read.ok and string.find(read.error.message, "503") ~= nil, "read")
    end)

    suite:test("leaderstats are set for online players only", function()
        local set: { string } = {}
        local view = RobloxLeaderstats.new({
            players = {
                GetPlayerByUserId = function(_self: unknown, userId: number): FakePlayer?
                    if userId == 1 then
                        return { UserId = 1 }
                    end
                    return nil
                end,
            },
            setValue = function(player: FakePlayer, stat: string, value: number)
                table.insert(set, `{player.UserId}:{stat}={value}`)
            end,
        })
        view:set(1, "coins", 5)
        view:set(2, "coins", 6)
        view:remove(1)
        harness.equal(#set, 1)
        harness.equal(set[1], "1:coins=5")
    end)

    suite:test("the publisher writes the encoded top and the update time", function()
        local seen: { string } = {}
        local publisher = ReplicatedBoardPublisher.new({
            encode = BoardKey.encode,
            write = function(boardId: string, text: string)
                table.insert(seen, `{boardId}={text}`)
            end,
        })
        publisher:publish("Coins", { { userId = 3, value = 40 } }, 1234.9)
        harness.equal(seen[1], "Coins=3:40|1234")
    end)
end
