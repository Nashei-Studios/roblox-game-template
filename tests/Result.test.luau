--!strict
local Result = require("../src/shared/Result")
local harness = require("./harness")

return function(suite: harness.Harness)
    suite:test("ok wraps a value", function()
        local result = Result.ok(42)
        harness.isTrue(result.ok, "ok flag")
        harness.equal(result.value, 42, "value")
    end)

    suite:test("err wraps an error and is not ok", function()
        local result = Result.err("boom")
        harness.isFalse(result.ok, "ok flag")
        harness.equal(result.error, "boom", "error")
    end)

    suite:test("ok and err narrow through the Result union", function()
        local function parse(input: number): Result.Result<number, string>
            if input < 0 then
                return Result.err("negative")
            end
            return Result.ok(input)
        end
        local good = parse(3)
        local bad = parse(-1)
        harness.isTrue(good.ok and good.value == 3, "good")
        harness.isTrue(not bad.ok and bad.error == "negative", "bad")
    end)
end
