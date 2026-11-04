--!strict
--[[
    Lune entry point: `lune run scripts/own-analytics [outputPath] [days]`
    (default `logs/own-analytics.json`, 30 days). Queries the Open Cloud Analytics Query API for
    this game's own universe and writes one private JSON file (ADR 0023). The pure logic is in
    src/shared/ops/AnalyticsQuery (tested); this file only reads the environment, calls the API
    and writes the file.

    Reads ROBLOX_UNIVERSE_ID and ROBLOX_ANALYTICS_KEY from the environment. When either is
    missing it prints one line and exits 0, so a fresh template or a game without a key stays
    green. The key is sent only in the `x-api-key` header to apis.roblox.com and is never
    printed or written. Metric values are never printed either: they are Creator Analytics data.
    This script is for the game repository's CI only; the vault never runs it.
]]

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local AnalyticsQuery = require("../src/shared/ops/AnalyticsQuery")

local MAX_POLLS = 6
local POLL_SECONDS = 5
local PAUSE_SECONDS = 1

local outputPath = process.args[1] or "logs/own-analytics.json"
local days = tonumber(process.args[2] or "30") or 30

local universeId = process.env.ROBLOX_UNIVERSE_ID
local apiKey = process.env.ROBLOX_ANALYTICS_KEY
local config = AnalyticsQuery.validateConfig(universeId, apiKey)
if not config.ok then
    if config.error == "missing" then
        print("own-analytics: ROBLOX_UNIVERSE_ID or ROBLOX_ANALYTICS_KEY is not set, skipping")
        process.exit(0)
    end
    print(`own-analytics: {config.error}`)
    process.exit(1)
end
local universe = if config.ok then config.value else ""
local key = apiKey :: string

local today = os.date("!%Y-%m-%d")

local function decode(body: string): unknown
    local ok, parsed = pcall(serde.decode, "json" :: "json", body)
    if ok then
        return parsed
    end
    return nil
end

--- One metric: POST, then poll while the API answers 202. Returns the parsed points or an error.
local function fetchMetric(metric: string): AnalyticsQuery.Result<{ AnalyticsQuery.Point }, string>
    local request = AnalyticsQuery.buildRequest(metric, today, days)
    if not request.ok then
        return request
    end
    local postHeaders: { [string]: string } =
        { ["x-api-key"] = key, ["Content-Type"] = "application/json" }
    local postParams: net.FetchParams = {
        url = AnalyticsQuery.metricsUrl(universe),
        method = "POST",
        headers = postHeaders,
        body = serde.encode("json", request.value),
    }
    local response = net.request(postParams)
    for _ = 1, MAX_POLLS do
        if response.statusCode ~= 202 then
            break
        end
        local pending = decode(response.body)
        local path = if type(pending) == "table"
            then (pending :: { [string]: unknown }).path
            else nil
        local poll = if type(path) == "string" then AnalyticsQuery.pollUrl(path) else nil
        if poll == nil or not poll.ok then
            return { ok = false, error = "pending without a usable path" }
        end
        task.wait(POLL_SECONDS)
        local getHeaders: { [string]: string } = { ["x-api-key"] = key }
        local getParams: net.FetchParams =
            { url = poll.value, method = "GET", headers = getHeaders }
        response = net.request(getParams)
    end
    if not response.ok and response.statusCode ~= 202 then
        -- API error bodies carry a numeric code; the key is never part of them.
        local code = AnalyticsQuery.errorCode(decode(response.body))
        return { ok = false, error = `HTTP {response.statusCode}, api code {code}` }
    end
    if response.statusCode == 202 then
        return { ok = false, error = "still pending after polling" }
    end
    return AnalyticsQuery.parseResponse(decode(response.body))
end

local outcomes: { AnalyticsQuery.Outcome } = {}
local summaries: { AnalyticsQuery.Summary } = {}
local series: { [string]: { AnalyticsQuery.Point } } = {}
for index, metric in AnalyticsQuery.metrics do
    if index > 1 then
        task.wait(PAUSE_SECONDS)
    end
    local result = fetchMetric(metric)
    table.insert(outcomes, { metric = metric, result = result })
    if result.ok then
        series[metric] = result.value
        table.insert(summaries, AnalyticsQuery.summarize(result.value, metric))
    end
end

local directory = string.match(outputPath, "^(.*)[/\\][^/\\]+$")
if directory ~= nil and directory ~= "" and not fs.isDir(directory) then
    fs.writeDir(directory)
end
fs.writeFile(
    outputPath,
    serde.encode("json", {
        generatedOn = today,
        windowDays = days,
        summaries = summaries,
        series = series,
    }, true)
)

print(AnalyticsQuery.statusLine(outcomes))
-- A game with no data yet returns empty series, which is fine. Failing every metric is not.
local okCount = 0
for _, outcome in outcomes do
    if outcome.result.ok then
        okCount += 1
    end
end
process.exit(if okCount == 0 then 1 else 0)
