--!strict
--[[
    Server-side validators for remote arguments (ADR 0012). Pure: loads under Lune.
    A remote carries INTENT only ("buy item X"); the server re-derives everything else.
    Each validator takes `unknown` (what a client really sent) and returns a typed Result,
    so a handler cannot use an argument it did not validate.
]]

export type ValidationError =
    "not_a_number"
    | "not_finite"
    | "not_an_integer"
    | "out_of_range"
    | "not_a_string"
    | "bad_length"
    | "not_allowed"
    | "not_a_boolean"

export type Result<T> = { ok: true, value: T } | { ok: false, error: ValidationError }

local Validation = {}

--- A finite number (rejects NaN and +-inf, which survive remote serialization).
function Validation.number(value: unknown): Result<number>
    if type(value) ~= "number" then
        return { ok = false, error = "not_a_number" }
    end
    -- NaN is the only value not equal to itself.
    if value ~= value or value == math.huge or value == -math.huge then
        return { ok = false, error = "not_finite" }
    end
    return { ok = true, value = value }
end

--- An integer within [min, max] inclusive.
function Validation.integerInRange(value: unknown, min: number, max: number): Result<number>
    local numeric = Validation.number(value)
    if not numeric.ok then
        return numeric
    end
    if numeric.value % 1 ~= 0 then
        return { ok = false, error = "not_an_integer" }
    end
    if numeric.value < min or numeric.value > max then
        return { ok = false, error = "out_of_range" }
    end
    return numeric
end

--- A string whose length (in bytes) is within [minLength, maxLength].
function Validation.string(value: unknown, minLength: number, maxLength: number): Result<string>
    if type(value) ~= "string" then
        return { ok = false, error = "not_a_string" }
    end
    if #value < minLength or #value > maxLength then
        return { ok = false, error = "bad_length" }
    end
    return { ok = true, value = value }
end

--- A string that is one of `allowed` (an allow-list, never a deny-list).
function Validation.oneOf(value: unknown, allowed: { string }): Result<string>
    if type(value) ~= "string" then
        return { ok = false, error = "not_a_string" }
    end
    if table.find(allowed, value) == nil then
        return { ok = false, error = "not_allowed" }
    end
    return { ok = true, value = value }
end

function Validation.boolean(value: unknown): Result<boolean>
    if type(value) ~= "boolean" then
        return { ok = false, error = "not_a_boolean" }
    end
    return { ok = true, value = value }
end

return Validation
