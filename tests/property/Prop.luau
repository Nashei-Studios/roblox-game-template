--!strict
--[[
    Minimal property-based testing in pure Luau (ADR 0062). No Lune API, so it loads under
    Lune and the Luau CLI (coverage runner). A property is a function that raises when the
    invariant breaks; `Prop.check` feeds it many generated inputs, and on the first failure
    shrinks the input and raises an error that prints the seed to replay it.

    Reproducible: every case has its own seed, derived from a per-property base seed. A failure
    prints `seed=N`; run `Prop.check(name, gen, prop, { seed = N })` to replay exactly that case.

    No external dependency: no maintained open source property-testing library targets Lune
    (checked 2026-11-09), and this fits in one file.
]]

export type Rng = { state: number }

export type Gen<T> = {
    -- `size` grows from 0 to 100 over a run: small inputs first, larger later.
    generate: (rng: Rng, size: number) -> T,
    -- Strictly simpler candidates for `value` (never `value` itself, never NaN).
    shrink: (value: T) -> { T },
}

export type Options = {
    -- Target number of cases (default 300, never below the floor of 200).
    cases: number?,
    -- Cases beyond the floor of 200 stop when this many seconds passed (default 2).
    maxSeconds: number?,
    -- Replays exactly one case with this seed (the one a failure printed).
    seed: number?,
}

local Prop = {}

local MODULUS = 4294967296
local MIN_CASES = 200
local DEFAULT_CASES = 300
local DEFAULT_MAX_SECONDS = 2
local MAX_SHRINK_STEPS = 400

-- Largest integer a Luau number holds exactly.
Prop.MAX_SAFE = 2 ^ 53

-- Rng ----------------------------------------------------------------------------------------

function Prop.newRng(seed: number): Rng
    return { state = seed % MODULUS }
end

--- Uniform float in [0, 1). A 32-bit LCG: state * 1664525 stays below 2^53, so it is exact.
function Prop.float(rng: Rng): number
    rng.state = (rng.state * 1664525 + 1013904223) % MODULUS
    return rng.state / MODULUS
end

--- Uniform integer in [low, high] (inclusive).
function Prop.intBetween(rng: Rng, low: number, high: number): number
    return low + math.floor(Prop.float(rng) * (high - low + 1))
end

function Prop.chance(rng: Rng, probability: number): boolean
    return Prop.float(rng) < probability
end

function Prop.pick<T>(rng: Rng, list: { T }): T
    return list[Prop.intBetween(rng, 1, #list)]
end

-- Generators -----------------------------------------------------------------------------------

function Prop.make<T>(generate: (rng: Rng, size: number) -> T, shrink: (value: T) -> { T }): Gen<T>
    return { generate = generate, shrink = shrink }
end

local function noShrink<T>(_value: T): { T }
    return {}
end

--- Always the same value.
function Prop.constant<T>(value: T): Gen<T>
    return Prop.make(function(): T
        return value
    end, noShrink)
end

function Prop.boolean(): Gen<boolean>
    return Prop.make(function(rng: Rng): boolean
        return Prop.chance(rng, 0.5)
    end, function(value: boolean): { boolean }
        return if value then { false } else {}
    end)
end

--- Integer in [low, high]; the bounds themselves come up often (edges break code first).
function Prop.integer(low: number, high: number): Gen<number>
    local anchor = math.min(math.max(0, low), high)
    return Prop.make(function(rng: Rng): number
        local roll = Prop.float(rng)
        if roll < 0.1 then
            return low
        elseif roll < 0.2 then
            return high
        end
        return Prop.intBetween(rng, low, high)
    end, function(value: number): { number }
        local candidates: { number } = {}
        if value ~= anchor then
            table.insert(candidates, anchor)
            local middle = anchor + (value - anchor) // 2
            if middle ~= anchor and middle ~= value then
                table.insert(candidates, middle)
            end
        end
        return candidates
    end)
end

local NUMBER_EDGES: { number } = {
    0,
    -0,
    1,
    -1,
    0.5,
    -0.5,
    1.5,
    100,
    255,
    256,
    2 ^ 31,
    2 ^ 32,
    2 ^ 53 - 1,
    2 ^ 53,
    2 ^ 53 + 2,
    -(2 ^ 53),
    1e300,
    -1e300,
    1e-300,
    math.huge,
    -math.huge,
    0 / 0,
}

--- Any number, with the hostile ones (NaN, +-inf, -0, 2^53 boundary, huge) over-represented.
function Prop.number(): Gen<number>
    return Prop.make(function(rng: Rng): number
        local roll = Prop.float(rng)
        if roll < 0.4 then
            return Prop.pick(rng, NUMBER_EDGES)
        elseif roll < 0.7 then
            return Prop.intBetween(rng, -1000, 1000)
        end
        return (Prop.float(rng) - 0.5) * 2e6
    end, function(value: number): { number }
        if value ~= value or value == math.huge or value == -math.huge then
            return { 0 }
        end
        local candidates: { number } = {}
        for _, candidate in { 0, math.floor(value), value / 2 } do
            if candidate ~= value and candidate == candidate then
                table.insert(candidates, candidate)
            end
        end
        return candidates
    end)
end

local STRING_PIECES: { string } = {
    "a",
    "Z",
    "0",
    " ",
    "_",
    "-",
    "'",
    '"',
    "\\",
    "\n",
    "\0",
    "\u{e9}",
    "\u{65e5}\u{672c}",
    "\u{1f600}",
    "\u{1f468}\u{200d}\u{1f469}",
    "\u{202e}",
    "\u{ffff}",
}

--- Strings: empty, short ASCII, unicode, emoji, control bytes, and now and then a big one.
function Prop.string(): Gen<string>
    return Prop.make(function(rng: Rng, size: number): string
        local roll = Prop.float(rng)
        if roll < 0.1 then
            return ""
        elseif roll < 0.15 then
            return string.rep(Prop.pick(rng, STRING_PIECES), Prop.intBetween(rng, 1000, 20000))
        end
        local pieces: { string } = {}
        for index = 1, Prop.intBetween(rng, 1, 3 + size // 4) do
            pieces[index] = Prop.pick(rng, STRING_PIECES)
        end
        return table.concat(pieces)
    end, function(value: string): { string }
        local candidates: { string } = {}
        if value ~= "" then
            table.insert(candidates, "")
            if #value > 1 then
                table.insert(candidates, string.sub(value, 1, #value // 2))
                table.insert(candidates, string.sub(value, 1, #value - 1))
            end
        end
        return candidates
    end)
end

--- A list of 0..maxLength elements; shrinks by dropping elements, then by shrinking one.
function Prop.listOf<T>(element: Gen<T>, maxLength: number): Gen<{ T }>
    return Prop.make(function(rng: Rng, size: number): { T }
        local list: { T } = {}
        for index = 1, Prop.intBetween(rng, 0, math.min(maxLength, 1 + size // 5)) do
            list[index] = element.generate(rng, size)
        end
        return list
    end, function(value: { T }): { { T } }
        local candidates: { { T } } = {}
        if #value == 0 then
            return candidates
        end
        table.insert(candidates, {})
        for dropped = 1, #value do
            local copy: { T } = {}
            for index, item in value do
                if index ~= dropped then
                    table.insert(copy, item)
                end
            end
            table.insert(candidates, copy)
        end
        for index, item in value do
            for _, simpler in element.shrink(item) do
                local copy = table.clone(value)
                copy[index] = simpler
                table.insert(candidates, copy)
            end
        end
        return candidates
    end)
end

--- Two generators, one tuple.
function Prop.pair<A, B>(first: Gen<A>, second: Gen<B>): Gen<{ a: A, b: B }>
    return Prop.make(function(rng: Rng, size: number): { a: A, b: B }
        return { a = first.generate(rng, size), b = second.generate(rng, size) }
    end, function(value: { a: A, b: B }): { { a: A, b: B } }
        local candidates: { { a: A, b: B } } = {}
        for _, simpler in first.shrink(value.a) do
            table.insert(candidates, { a = simpler, b = value.b })
        end
        for _, simpler in second.shrink(value.b) do
            table.insert(candidates, { a = value.a, b = simpler })
        end
        return candidates
    end)
end

local function generateAnything(rng: Rng, size: number, depth: number): unknown
    local roll = Prop.float(rng)
    if roll < 0.08 then
        return nil
    elseif roll < 0.18 then
        return Prop.chance(rng, 0.5)
    elseif roll < 0.4 then
        return Prop.number().generate(rng, size)
    elseif roll < 0.62 then
        return Prop.string().generate(rng, size)
    elseif roll < 0.68 then
        return function() end
    elseif roll < 0.72 then
        return coroutine.create(function() end)
    elseif depth >= 3 then
        return {}
    end
    local nested: { [unknown]: unknown } = {}
    for index = 1, Prop.intBetween(rng, 0, 4) do
        local key: unknown = if Prop.chance(rng, 0.5)
            then index
            else Prop.string().generate(rng, size)
        nested[key] = generateAnything(rng, size, depth + 1)
    end
    return nested
end

--- Any Luau value a remote could carry or a hostile client could fake: nil, booleans,
--- numbers (NaN, +-inf), strings, nested tables, functions, threads.
function Prop.anything(): Gen<unknown>
    return Prop.make(function(rng: Rng, size: number): unknown
        return generateAnything(rng, size, 0)
    end, function(value: unknown): { unknown }
        local candidates: { unknown } = {}
        if type(value) == "table" then
            table.insert(candidates, {})
            table.insert(candidates, "")
        elseif type(value) == "string" then
            for _, simpler in Prop.string().shrink(value) do
                table.insert(candidates, simpler)
            end
        elseif type(value) == "number" then
            for _, simpler in Prop.number().shrink(value) do
                table.insert(candidates, simpler)
            end
        end
        return candidates
    end)
end

-- Description of a failing input -----------------------------------------------------------------

local function describe(value: unknown, depth: number): string
    local kind = type(value)
    if kind == "string" then
        local text = value :: string
        if #text > 40 then
            return `<string of {#text} bytes>`
        end
        return string.format("%q", text)
    elseif kind == "table" then
        if depth >= 3 then
            return "{...}"
        end
        local parts: { string } = {}
        local shown = 0
        for key, item in value :: { [unknown]: unknown } do
            shown += 1
            if shown > 8 then
                table.insert(parts, "...")
                break
            end
            table.insert(parts, `[{describe(key, depth + 1)}]={describe(item, depth + 1)}`)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(value)
end

-- Runner ---------------------------------------------------------------------------------------------

local function attempt<T>(property: (value: T) -> (), value: T): (boolean, string?)
    local failure: string? = nil
    local ok = xpcall(property, function(err: unknown): ()
        failure = tostring(err)
    end, value)
    return ok, failure
end

local function hashName(name: string): number
    local hash = 5381
    for index = 1, #name do
        hash = (hash * 33 + string.byte(name, index)) % MODULUS
    end
    return hash
end

local function shrinkInput<T>(gen: Gen<T>, property: (value: T) -> (), start: T): (T, number)
    local current = start
    local steps = 0
    local progressed = true
    while progressed and steps < MAX_SHRINK_STEPS do
        progressed = false
        for _, candidate in gen.shrink(current) do
            steps += 1
            if not (attempt(property, candidate)) then
                current = candidate
                progressed = true
                break
            end
            if steps >= MAX_SHRINK_STEPS then
                break
            end
        end
    end
    return current, steps
end

--- Runs `property` on at least 200 generated inputs (bounded in time). Raises on the first
--- failure with the shrunk input, the seed and the original message.
function Prop.check<T>(name: string, gen: Gen<T>, property: (value: T) -> (), options: Options?)
    local settings: Options = options or {}
    local deadline = os.clock() + (settings.maxSeconds or DEFAULT_MAX_SECONDS)
    local baseSeed = hashName(name)
    local replay = settings.seed

    local total = if replay ~= nil then 1 else math.max(settings.cases or DEFAULT_CASES, MIN_CASES)
    for index = 1, total do
        local seed = if replay ~= nil then replay else (baseSeed + index * 2654435761) % MODULUS
        local size = math.min(100, (index * 100) // total)
        local value = gen.generate(Prop.newRng(seed), size)
        local ok, message = attempt(property, value)
        if not ok then
            local shrunk, steps = shrinkInput(gen, property, value)
            local _, shrunkMessage = attempt(property, shrunk)
            error(
                `property "{name}" failed at case {index}: seed={seed} (replay with \{ seed = {seed} \}), `
                    .. `shrunk in {steps} steps to input {describe(shrunk, 0)}\n`
                    .. `{shrunkMessage or message or "no message"}`,
                0
            )
        end
        -- The floor of cases always runs; only the optional extra cases honor the clock.
        if os.clock() > deadline and index >= MIN_CASES then
            break
        end
    end
end

Prop.describe = describe

return Prop
