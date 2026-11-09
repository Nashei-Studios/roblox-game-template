--!strict
local Prop = require("./Prop")
local harness = require("../harness")

local function messageOf(fn: () -> ()): string?
    local message: string? = nil
    xpcall(fn, function(err: unknown): ()
        message = tostring(err)
    end)
    return message
end

return function(suite: harness.Harness)
    suite:test("a true property runs at least 200 cases", function()
        local runs = 0
        Prop.check("always true", Prop.number(), function(_value: number)
            runs += 1
        end)
        harness.isTrue(runs >= 200, `ran {runs} cases`)
    end)

    suite:test("a false property fails, prints its seed and shrinks the input", function()
        local message = messageOf(function()
            Prop.check("below ten", Prop.integer(0, 1000), function(value: number)
                harness.isTrue(value < 10, "value below ten")
            end)
        end)
        harness.isTrue(message ~= nil, "must fail")
        local text = message or ""
        harness.isTrue(string.find(text, "seed=%d+") ~= nil, "prints the seed")
        -- Shrinking walks toward 0 by halves, so the smallest failing value it reaches is 10.
        harness.isTrue(string.find(text, "input 10\n", 1, true) ~= nil, "shrunk to 10: " .. text)
    end)

    suite:test("the same seed replays the same case", function()
        local first = Prop.integer(0, 1000000).generate(Prop.newRng(42), 50)
        local second = Prop.integer(0, 1000000).generate(Prop.newRng(42), 50)
        harness.equal(first, second, "same seed, same value")
    end)

    suite:test("replaying a printed seed reproduces the failure", function()
        local function property(value: number)
            harness.isTrue(value < 500, "below 500")
        end
        local message = messageOf(function()
            Prop.check("replay", Prop.integer(0, 1000), property)
        end)
        local seed = string.match(message or "", "seed=(%d+)")
        harness.isTrue(seed ~= nil, "seed printed")
        local replayed = messageOf(function()
            Prop.check("replay", Prop.integer(0, 1000), property, { seed = tonumber(seed) })
        end)
        harness.isTrue(replayed ~= nil, "same seed fails again")
    end)

    suite:test("a property that raises counts as a failure", function()
        local message = messageOf(function()
            Prop.check("raises", Prop.string(), function(_value: string)
                error("boom")
            end)
        end)
        harness.isTrue(string.find(message or "", "boom", 1, true) ~= nil, "keeps the message")
    end)

    suite:test("the number generator produces NaN, infinity and huge values", function()
        local rng = Prop.newRng(7)
        local gen = Prop.number()
        local sawNaN, sawInf, sawHuge = false, false, false
        for _ = 1, 400 do
            local value = gen.generate(rng, 50)
            sawNaN = sawNaN or value ~= value
            sawInf = sawInf or value == math.huge or value == -math.huge
            sawHuge = sawHuge or math.abs(value) > 2 ^ 53
        end
        harness.isTrue(sawNaN and sawInf and sawHuge, "hostile numbers present")
    end)

    suite:test("the string generator produces empty, unicode and big strings", function()
        local rng = Prop.newRng(9)
        local gen = Prop.string()
        local sawEmpty, sawMultibyte, sawBig = false, false, false
        for _ = 1, 400 do
            local value = gen.generate(rng, 50)
            sawEmpty = sawEmpty or value == ""
            sawMultibyte = sawMultibyte or string.find(value, "[\128-\255]") ~= nil
            sawBig = sawBig or #value > 1000
        end
        harness.isTrue(sawEmpty and sawMultibyte and sawBig, "hostile strings present")
    end)

    suite:test("the anything generator covers nil, tables, functions and threads", function()
        local rng = Prop.newRng(11)
        local gen = Prop.anything()
        local kinds: { [string]: boolean } = {}
        for _ = 1, 600 do
            kinds[type(gen.generate(rng, 60))] = true
        end
        for _, kind in { "nil", "boolean", "number", "string", "table", "function", "thread" } do
            harness.isTrue(kinds[kind] == true, `kind {kind} generated`)
        end
    end)

    suite:test("a list shrinks by dropping elements", function()
        local message = messageOf(function()
            Prop.check(
                "no seven",
                Prop.listOf(Prop.integer(0, 9), 30),
                function(list: { number })
                    harness.isFalse(table.find(list, 7) ~= nil, "contains 7")
                end
            )
        end)
        harness.isTrue(
            string.find(message or "", "[1]=7}", 1, true) ~= nil,
            "shrunk to {7}: " .. (message or "")
        )
    end)
end
