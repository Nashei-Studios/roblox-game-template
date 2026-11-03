--!strict
local Validation = require("../../src/shared/net/Validation")
local harness = require("../harness")

local function errorOf<T>(result: Validation.Result<T>): string
    if result.ok then
        return "ok"
    end
    return result.error
end

return function(suite: harness.Harness)
    suite:test("number accepts finite numbers and rejects NaN, infinity and other types", function()
        harness.isTrue(Validation.number(3.5).ok, "3.5")
        harness.equal(errorOf(Validation.number(0 / 0)), "not_finite", "NaN")
        harness.equal(errorOf(Validation.number(math.huge)), "not_finite", "inf")
        harness.equal(errorOf(Validation.number(-math.huge)), "not_finite", "-inf")
        harness.equal(errorOf(Validation.number("5")), "not_a_number", "string")
        harness.equal(errorOf(Validation.number(nil)), "not_a_number", "nil")
    end)

    suite:test("integerInRange enforces integer-ness and inclusive bounds", function()
        harness.isTrue(Validation.integerInRange(1, 1, 10).ok, "lower bound")
        harness.isTrue(Validation.integerInRange(10, 1, 10).ok, "upper bound")
        harness.equal(errorOf(Validation.integerInRange(0, 1, 10)), "out_of_range", "below")
        harness.equal(errorOf(Validation.integerInRange(11, 1, 10)), "out_of_range", "above")
        harness.equal(errorOf(Validation.integerInRange(2.5, 1, 10)), "not_an_integer", "fraction")
        harness.equal(errorOf(Validation.integerInRange(0 / 0, 1, 10)), "not_finite", "NaN")
    end)

    suite:test("string enforces type and length", function()
        harness.isTrue(Validation.string("abc", 1, 5).ok, "valid")
        harness.equal(errorOf(Validation.string("", 1, 5)), "bad_length", "too short")
        harness.equal(errorOf(Validation.string("abcdef", 1, 5)), "bad_length", "too long")
        harness.equal(errorOf(Validation.string(12, 1, 5)), "not_a_string", "number")
    end)

    suite:test("oneOf is an allow-list", function()
        local allowed = { "sword", "shield" }
        harness.isTrue(Validation.oneOf("sword", allowed).ok, "allowed")
        harness.equal(errorOf(Validation.oneOf("bomb", allowed)), "not_allowed", "not listed")
        harness.equal(errorOf(Validation.oneOf(1, allowed)), "not_a_string", "number")
    end)

    suite:test("boolean accepts only booleans", function()
        harness.isTrue(Validation.boolean(false).ok, "false")
        harness.equal(errorOf(Validation.boolean(0)), "not_a_boolean", "number")
    end)

    suite:test("a validated value carries the value itself", function()
        local result = Validation.integerInRange(7, 1, 10)
        harness.isTrue(result.ok and result.value == 7, "value preserved")
    end)
end
