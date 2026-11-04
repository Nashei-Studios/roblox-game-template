--!strict
--[[
    Pure half of the own-game analytics job (ADR 0023): builds Open Cloud Analytics Query
    requests, parses the responses and reduces them to a short summary. The Lune half
    (`scripts/own-analytics`) only reads the environment, makes the HTTP calls and writes the file.
    Endpoint and metric names: https://create.roblox.com/docs/cloud/guides/analytics
    (Roblox/creator-docs, content/en-us/cloud/guides/analytics/index.md and metrics.md, read 2026-11-04).

    Nothing here touches the engine or the network, and nothing prints metric values: they are
    Creator Analytics data and must stay private (Roblox Terms of Use, Creator Analytics clause).
]]

type Ok<T> = { ok: true, value: T }
type Err<E> = { ok: false, error: E }
export type Result<T, E> = Ok<T> | Err<E>

export type Request = {
    metric: string,
    granularity: string,
    startTime: string,
    endTime: string,
}

export type Point = { time: string, value: number }

export type Summary = {
    metric: string,
    points: number,
    latest: Point?,
    mean: number?,
}

export type Outcome = { metric: string, result: Result<{ Point }, string> }

local AnalyticsQuery = {}

AnalyticsQuery.baseUrl = "https://apis.roblox.com/analytics-query-api"

--- Metrics fetched every day. Names are from the official metrics page; all support `OneDay`.
AnalyticsQuery.metrics = {
    "DailyActiveUsers",
    "ForwardD1Retention",
    "ForwardD7Retention",
    "ForwardD30Retention",
    "AverageSessionLengthMinutes",
    "DailyRevenue",
    "PayingUsers",
    "RFYPlayThroughRate",
    "RFYDuration0To60",
    "RFYDuration61To180",
    "RFYD1Playtime",
} :: { string }

local METRIC_NAME = "^%a[%w]*$"
local UNIVERSE_ID = "^%d+$"
local ISO_DAY = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"

--- Days in each month of a non-leap year; February is patched for leap years below.
local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function isLeap(year: number): boolean
    return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

type Day = { year: number, month: number, day: number }

local function parseDay(day: string): Day?
    local y, m, d = string.match(day, ISO_DAY)
    if y == nil or m == nil or d == nil then
        return nil
    end
    local year, month, dayNumber =
        tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number
    if month < 1 or month > 12 then
        return nil
    end
    local limit = MONTH_DAYS[month] + (if month == 2 and isLeap(year) then 1 else 0)
    if dayNumber < 1 or dayNumber > limit then
        return nil
    end
    return { year = year, month = month, day = dayNumber }
end

--- Days since 1970-01-01 (proleptic Gregorian). Howard Hinnant's civil-days algorithm.
local function toDayNumber(year: number, month: number, day: number): number
    local y = if month <= 2 then year - 1 else year
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (month + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + day - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

local function fromDayNumber(days: number): string
    local z = days + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor(
        (doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365
    )
    local year = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local day = doy - math.floor((153 * mp + 2) / 5) + 1
    local month = if mp < 10 then mp + 3 else mp - 9
    if month <= 2 then
        year += 1
    end
    return string.format("%04d-%02d-%02d", year, month, day)
end

--- Adds `delta` days to an ISO day (`YYYY-MM-DD`). Returns nil when the input is not a real date.
function AnalyticsQuery.addDays(day: string, delta: number): string?
    local parsed = parseDay(day)
    if parsed == nil then
        return nil
    end
    return fromDayNumber(toDayNumber(parsed.year, parsed.month, parsed.day) + delta)
end

--- Validates the two values read from the environment. `universeId` must be digits only so it
--- cannot alter the URL path; the key is only checked for being present, never inspected.
function AnalyticsQuery.validateConfig(universeId: string?, apiKey: string?): Result<string, string>
    if universeId == nil or universeId == "" or apiKey == nil or apiKey == "" then
        return { ok = false, error = "missing" }
    end
    if string.match(universeId, UNIVERSE_ID) == nil then
        return { ok = false, error = "ROBLOX_UNIVERSE_ID must contain digits only" }
    end
    return { ok = true, value = universeId }
end

function AnalyticsQuery.metricsUrl(universeId: string): string
    return `{AnalyticsQuery.baseUrl}/v1/universes/{universeId}/metrics`
end

--- Polling URL for a long-running query (`202 Accepted`). Only a relative path of the shape the
--- docs show is accepted, so a hostile response cannot redirect the key to another host.
function AnalyticsQuery.pollUrl(path: string): Result<string, string>
    if
        string.match(path, "^v1/universes/%d+/operations/[%w%-_/%.]+$") == nil
        or string.find(path, "..", 1, true) ~= nil
    then
        return { ok = false, error = "unexpected operation path" }
    end
    return { ok = true, value = `{AnalyticsQuery.baseUrl}/{path}` }
end

--- One daily-bucket request for `days` full days ending the day before `today` (UTC).
--- `endTime` is exclusive in the API, so it is `today` at midnight.
function AnalyticsQuery.buildRequest(
    metric: string,
    today: string,
    days: number
): Result<Request, string>
    if string.match(metric, METRIC_NAME) == nil then
        return { ok = false, error = "invalid metric name" }
    end
    if days < 1 or days > 365 or days ~= math.floor(days) then
        return { ok = false, error = "days must be an integer from 1 to 365" }
    end
    local startDay = AnalyticsQuery.addDays(today, -days)
    if startDay == nil then
        return { ok = false, error = "today must be a real YYYY-MM-DD date" }
    end
    return {
        ok = true,
        value = {
            metric = metric,
            granularity = "OneDay",
            startTime = `{startDay}T00:00:00Z`,
            endTime = `{today}T00:00:00Z`,
        },
    }
end

--- Numeric API error code of a failed response body, or "none". Never returns message text.
function AnalyticsQuery.errorCode(body: unknown): string
    if type(body) ~= "table" then
        return "none"
    end
    local failure = (body :: { [string]: unknown }).error
    if type(failure) ~= "table" then
        return "none"
    end
    local code = (failure :: { [string]: unknown }).code
    return if type(code) == "number" then tostring(code) else "none"
end

--- Reads the `response.values[1].dataPoints` of a finished query. A query that reports `error`
--- or is still pending returns an Err carrying the API code, never the body.
function AnalyticsQuery.parseResponse(body: unknown): Result<{ Point }, string>
    if type(body) ~= "table" then
        return { ok = false, error = "response is not an object" }
    end
    local doc = body :: { [string]: unknown }
    if doc.done ~= true then
        return { ok = false, error = "query not done" }
    end
    local failure = doc.error
    if type(failure) == "table" then
        local code = (failure :: { [string]: unknown }).code
        return { ok = false, error = `api error {tostring(code)}` }
    end
    local response = doc.response
    if type(response) ~= "table" then
        return { ok = false, error = "missing response" }
    end
    local values = (response :: { [string]: unknown }).values
    if type(values) ~= "table" or #(values :: { unknown }) == 0 then
        return { ok = true, value = {} }
    end
    local first = (values :: { unknown })[1]
    if type(first) ~= "table" then
        return { ok = false, error = "series is not an object" }
    end
    local rawPoints = (first :: { [string]: unknown }).dataPoints
    if type(rawPoints) ~= "table" then
        return { ok = false, error = "series has no dataPoints" }
    end
    local points: { Point } = {}
    for _, raw in rawPoints :: { unknown } do
        if type(raw) == "table" then
            local entry = raw :: { [string]: unknown }
            if type(entry.time) == "string" and type(entry.value) == "number" then
                table.insert(points, { time = entry.time :: string, value = entry.value :: number })
            end
        end
    end
    return { ok = true, value = points }
end

--- Counts and the latest point per metric. The summary goes into the private artifact only.
function AnalyticsQuery.summarize(points: { Point }, metric: string): Summary
    if #points == 0 then
        return { metric = metric, points = 0, latest = nil, mean = nil }
    end
    local latest = points[1]
    local sum = 0
    for _, point in points do
        sum += point.value
        if point.time > latest.time then
            latest = point
        end
    end
    return { metric = metric, points = #points, latest = latest, mean = sum / #points }
end

--- One-line, value-free status for the CI log: metric counts and failures only.
function AnalyticsQuery.statusLine(outcomes: { Outcome }): string
    local okCount, failed = 0, {}
    for _, outcome in outcomes do
        if outcome.result.ok then
            okCount += 1
        else
            table.insert(failed, `{outcome.metric}: {outcome.result.error}`)
        end
    end
    local line = `own-analytics: {okCount}/{#outcomes} metrics ok`
    if #failed > 0 then
        line ..= `; failed: {table.concat(failed, ", ")}`
    end
    return line
end

return AnalyticsQuery
