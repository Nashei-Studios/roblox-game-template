--!strict
local Flags = require("../../../src/shared/features/flags/Flags")
local harness = require("../../harness")

local defaults: Flags.Defaults = {
    booleans = { purchasesEnabled = true },
    numbers = { maxPlayers = 10 },
}

local function sourceOf(values: { [string]: Flags.FlagValue }): Flags.FlagSource
    return {
        get = function(_self: Flags.FlagSource, name: string): Flags.FlagValue?
            return values[name]
        end,
    }
end

return function(suite: harness.Harness)
    suite:test("without a source the in-repo defaults are used", function()
        local flags = Flags.new(nil, defaults)
        harness.isTrue(flags:getBoolean("purchasesEnabled"), "boolean default")
        harness.equal(flags:getNumber("maxPlayers"), 10, "number default")
    end)

    suite:test("a live value overrides the default", function()
        local flags = Flags.new(sourceOf({ purchasesEnabled = false, maxPlayers = 20 }), defaults)
        harness.isFalse(flags:getBoolean("purchasesEnabled"), "boolean override")
        harness.equal(flags:getNumber("maxPlayers"), 20, "number override")
    end)

    suite:test("a live value of the wrong type is ignored", function()
        local flags =
            Flags.new(sourceOf({ purchasesEnabled = "yes", maxPlayers = "many" }), defaults)
        harness.isTrue(flags:getBoolean("purchasesEnabled"), "boolean fallback")
        harness.equal(flags:getNumber("maxPlayers"), 10, "number fallback")
    end)

    suite:test("a flag without a default is a programming error", function()
        local flags = Flags.new(nil, defaults)
        local ok = pcall(function()
            flags:getBoolean("neverDeclared")
        end)
        harness.isFalse(ok, "unknown flag must raise")
    end)
end
