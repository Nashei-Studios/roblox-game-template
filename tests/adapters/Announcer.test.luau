--!strict
local Announcer = require("../../src/server/adapters/Announcer")
local AnnouncementPresenter = require("../../src/client/presenters/AnnouncementPresenter")
local harness = require("../harness")

return function(suite: harness.Harness)
    suite:test("announce sends the name and value to every client", function()
        local sent: { { name: string, value: number } } = {}
        local announcer = Announcer.new({
            fireAll = function(name: string, value: number)
                table.insert(sent, { name = name, value = value })
            end,
        })
        announcer:announce("Ana", 150)
        harness.equal(#sent, 1)
        harness.equal(sent[1].name, "Ana")
        harness.equal(sent[1].value, 150)
    end)

    suite:test("a long name is cut to the wire limit on a character boundary", function()
        local sent: { string } = {}
        local announcer = Announcer.new({
            fireAll = function(name: string, _value: number)
                table.insert(sent, name)
            end,
        })
        announcer:announce(string.rep("\u{00E9}", 30), 50)
        harness.isTrue(#sent[1] <= 40, "within 40 bytes")
        harness.isTrue(utf8.len(sent[1]) ~= nil, "still valid utf8")
    end)

    suite:test("an empty name falls back and value is clamped", function()
        local sent: { { name: string, value: number } } = {}
        local announcer = Announcer.new({
            fireAll = function(name: string, value: number)
                table.insert(sent, { name = name, value = value })
            end,
        })
        announcer:announce("", -5)
        harness.equal(sent[1].name, "Miner")
        harness.equal(sent[1].value, 0)
    end)

    suite:test("the client presenter builds the line and shows it", function()
        local shown: { string } = {}
        local presenter = AnnouncementPresenter.new({
            line = function(name: string, value: number): string
                return `{name} reached {value}!`
            end,
            display = function(text: string)
                table.insert(shown, text)
            end,
        })
        presenter:receive("Ana", 150)
        harness.equal(shown[1], "Ana reached 150!")
    end)
end
