--!strict
--[[
    Static remote-bandwidth calculator (ADR 0019). Pure: it takes the text of `net/schema.zap`
    and a `PerfBudget.Budget`, so it loads under Lune and the Luau CLI and is tested without
    the engine. `scripts/perf-budget.luau` is the CLI that reads the files and sets the exit code.

    Model, per remote:
        eventBytes     = payload bytes of the largest message + perEventOverheadBytes
        bytesPerSecond = eventBytes * events in the worst 1 s window
    Client -> server: events in the worst window = capacity + refillPerSecond (a full burst plus
    what refills during that second): the most the RateLimiter lets through.
    Server -> client: the declared `maxPerSecond` (the server decides its own sends).
    A remote with no entry in the budget is a failure: an unbudgeted remote cannot pass.

    Payload sizes follow the Zap wire format for fixed-size types. Unbounded types (a string
    without a length range, arrays, Instance, ...) are rejected: the worst case would be unknown.
]]

local PerfBudget = require("./PerfBudget")

export type Ok<T> = { ok: true, value: T }
export type Err<E> = { ok: false, error: E }
export type Result<T, E> = Ok<T> | Err<E>

export type Direction = "Client" | "Server"

export type EventSpec = {
    name: string,
    from: Direction,
    payloadBytes: number,
}

export type Row = {
    name: string,
    from: Direction,
    payloadBytes: number,
    eventBytes: number,
    eventsPerSecond: number,
    bytesPerSecond: number,
}

export type Report = {
    rows: { Row },
    clientToServerBytesPerSecond: number,
    serverToClientBytesPerSecond: number,
    failures: { string },
}

local FIXED_SIZES: { [string]: number } = {
    u8 = 1,
    i8 = 1,
    bool = 1,
    boolean = 1,
    u16 = 2,
    i16 = 2,
    u32 = 4,
    i32 = 4,
    f32 = 4,
    f64 = 8,
    Vector3 = 12,
}

-- Zap prefixes a string with a u16 length.
local STRING_LENGTH_PREFIX = 2

local RemoteBudget = {}

local function trim(text: string): string
    return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function stripComments(text: string): string
    local lines: { string } = {}
    for line in string.gmatch(text, "[^\r\n]*") do
        table.insert(lines, (string.gsub(line, "%-%-.*$", "")))
    end
    return table.concat(lines, "\n")
end

-- Splits on commas that are not inside parentheses or braces.
local function splitTopLevel(text: string): { string }
    local parts: { string } = {}
    local depth = 0
    local start = 1
    for index = 1, #text do
        local char = string.sub(text, index, index)
        if char == "(" or char == "{" then
            depth += 1
        elseif char == ")" or char == "}" then
            depth -= 1
        elseif char == "," and depth == 0 then
            table.insert(parts, string.sub(text, start, index - 1))
            start = index + 1
        end
    end
    local last = trim(string.sub(text, start))
    if last ~= "" then
        table.insert(parts, last)
    end
    return parts
end

local function enumSize(body: string): Result<number, string>
    local variants = 0
    for _ in string.gmatch(body, '"[^"]*"') do
        variants += 1
    end
    if variants == 0 then
        return { ok = false, error = "enum without string variants" }
    end
    return { ok = true, value = if variants <= 256 then 1 else 2 }
end

local function typeSize(rawType: string, named: { [string]: number }): Result<number, string>
    local typeText = trim(rawType)
    if string.sub(typeText, -1) == "?" then
        local inner = typeSize(string.sub(typeText, 1, -2), named)
        if not inner.ok then
            return inner
        end
        return { ok = true, value = inner.value + 1 }
    end
    local enumBody = string.match(typeText, "^enum%s*{(.*)}$")
    if enumBody ~= nil then
        return enumSize(enumBody)
    end
    local base = string.match(typeText, "^([%w_]+)")
    if base == nil then
        return { ok = false, error = `cannot read type "{typeText}"` }
    end
    if base == "string" then
        local maxLength = string.match(typeText, "%.%.%s*(%d+)%s*%)$")
        if maxLength == nil then
            return { ok = false, error = `unbounded string "{typeText}": add a length range` }
        end
        return { ok = true, value = STRING_LENGTH_PREFIX + (tonumber(maxLength) :: number) }
    end
    local fixed = FIXED_SIZES[base]
    if fixed ~= nil then
        return { ok = true, value = fixed }
    end
    local alias = named[base]
    if alias ~= nil then
        return { ok = true, value = alias }
    end
    return { ok = false, error = `unsupported or unbounded type "{typeText}"` }
end

local function parseNamedTypes(text: string): Result<{ [string]: number }, string>
    local named: { [string]: number } = {}
    for rawName, rawBody in string.gmatch(text, "type%s+([%w_]+)%s*=%s*(enum%s*%b{})") do
        local name, body = rawName :: string, rawBody :: string
        local size = typeSize(body, named)
        if not size.ok then
            return { ok = false, error = `type {name}: {size.error}` }
        end
        named[name] = size.value
    end
    return { ok = true, value = named }
end

local function payloadSize(dataText: string, named: { [string]: number }): Result<number, string>
    local inner = string.match(trim(dataText), "^%((.*)%)$")
    local fields: { string }
    if inner ~= nil then
        fields = splitTopLevel(inner)
    else
        fields = { dataText }
    end
    local total = 0
    for _, field in fields do
        local typeText = string.match(field, "^%s*[%w_]+%s*:%s*(.+)$") or field
        local size = typeSize(typeText, named)
        if not size.ok then
            return size
        end
        total += size.value
    end
    return { ok = true, value = total }
end

--- Reads every `event` of a Zap schema and computes its largest payload in bytes.
function RemoteBudget.parseSchema(schemaText: string): Result<{ EventSpec }, string>
    local text = stripComments(schemaText)
    local named = parseNamedTypes(text)
    if not named.ok then
        return named
    end
    local events: { EventSpec } = {}
    for rawName, rawBody in string.gmatch(text, "event%s+([%w_]+)%s*=%s*(%b{})") do
        local name, body = rawName :: string, rawBody :: string
        local from = string.match(body, "from%s*:%s*(%a+)")
        if from ~= "Client" and from ~= "Server" then
            return { ok = false, error = `event {name}: "from" must be Client or Server` }
        end
        local dataText = string.match(body, "data%s*:%s*(.-)%s*,?%s*}$")
        if dataText == nil then
            return { ok = false, error = `event {name}: no data field` }
        end
        local size = payloadSize(dataText, named.value)
        if not size.ok then
            return { ok = false, error = `event {name}: {size.error}` }
        end
        table.insert(events, {
            name = name,
            from = from,
            payloadBytes = size.value,
        })
    end
    return { ok = true, value = events }
end

local function eventsPerSecondFor(event: EventSpec, budget: PerfBudget.Budget): number?
    if event.from == "Client" then
        local limit = budget.clientRemotes[event.name]
        if limit ~= nil then
            return limit.capacity + limit.refillPerSecond
        end
        return nil
    end
    local rate = budget.serverRemotes[event.name]
    if rate ~= nil then
        return rate.maxPerSecond
    end
    return nil
end

--- Computes the worst case per remote and in total, and lists every budget violation.
function RemoteBudget.evaluate(events: { EventSpec }, budget: PerfBudget.Budget): Report
    local report: Report = {
        rows = {},
        clientToServerBytesPerSecond = 0,
        serverToClientBytesPerSecond = 0,
        failures = {},
    }
    local known: { [string]: boolean } = {}
    for _, event in events do
        known[event.name] = true
        local eventsPerSecond = eventsPerSecondFor(event, budget)
        if eventsPerSecond == nil then
            table.insert(
                report.failures,
                `{event.name}: no rate declared in the budget ({event.from} remote)`
            )
            continue
        end
        local eventBytes = event.payloadBytes + budget.perEventOverheadBytes
        local bytesPerSecond = eventBytes * eventsPerSecond
        table.insert(report.rows, {
            name = event.name,
            from = event.from,
            payloadBytes = event.payloadBytes,
            eventBytes = eventBytes,
            eventsPerSecond = eventsPerSecond,
            bytesPerSecond = bytesPerSecond,
        })
        if event.from == "Client" then
            report.clientToServerBytesPerSecond += bytesPerSecond
        else
            report.serverToClientBytesPerSecond += bytesPerSecond
        end
        if bytesPerSecond > budget.perRemoteBytesPerSecond then
            table.insert(
                report.failures,
                `{event.name}: {bytesPerSecond} B/s exceeds the per-remote budget of {budget.perRemoteBytesPerSecond} B/s`
            )
        end
    end
    if report.clientToServerBytesPerSecond > budget.clientToServerBytesPerSecond then
        table.insert(
            report.failures,
            `client -> server total {report.clientToServerBytesPerSecond} B/s exceeds {budget.clientToServerBytesPerSecond} B/s`
        )
    end
    if report.serverToClientBytesPerSecond > budget.serverToClientBytesPerSecond then
        table.insert(
            report.failures,
            `server -> client total {report.serverToClientBytesPerSecond} B/s exceeds {budget.serverToClientBytesPerSecond} B/s`
        )
    end
    -- Budget entries for remotes the schema no longer has are stale config: report them.
    for name in budget.clientRemotes do
        if not known[name] then
            table.insert(report.failures, `{name}: budgeted client remote is not in the schema`)
        end
    end
    for name in budget.serverRemotes do
        if not known[name] then
            table.insert(report.failures, `{name}: budgeted server remote is not in the schema`)
        end
    end
    table.sort(report.failures)
    return report
end

return RemoteBudget
