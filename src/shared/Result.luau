--!strict
--[[
    Typed Result. Errors cross layers as values, never as silent swallows.

    Pure modules that must also load under Lune declare a structurally identical
    local alias instead of requiring this file (see docs/architecture.md, "Pure core").
]]

export type Ok<T> = { ok: true, value: T }
export type Err<E> = { ok: false, error: E }
export type Result<T, E> = Ok<T> | Err<E>

local Result = {}

function Result.ok<T>(value: T): Ok<T>
    return { ok = true, value = value }
end

function Result.err<E>(error: E): Err<E>
    return { ok = false, error = error }
end

return Result
