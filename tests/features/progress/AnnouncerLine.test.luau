--!strict
local AnnouncerLine = require("../../../src/shared/features/progress/AnnouncerLine")
local harness = require("../../harness")

return function(suite: harness.Harness)
    suite:test("trims and keeps a normal line", function()
        harness.equal(AnnouncerLine.prepare("  hello  "), "hello")
    end)
    suite:test("empty or blank has nothing to send", function()
        harness.equal(AnnouncerLine.prepare(""), nil)
        harness.equal(AnnouncerLine.prepare("   "), nil)
    end)
    suite:test("a long line is cut at 100 characters", function()
        local cut = AnnouncerLine.prepare(string.rep("a", 300))
        harness.equal(if cut ~= nil then #cut else 0, 100)
    end)
    suite:test("the cut never splits a multi-byte character", function()
        local cut = AnnouncerLine.prepare(string.rep("é", 300))
        harness.isTrue(cut ~= nil)
        if cut ~= nil then
            harness.equal(utf8.len(cut), 100)
        end
    end)
    suite:test("invalid UTF-8 is refused", function()
        harness.equal(AnnouncerLine.prepare("bad\255"), nil)
    end)
end
