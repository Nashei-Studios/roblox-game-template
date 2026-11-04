--!strict
local AnalyticsQuery = require("../../src/shared/ops/AnalyticsQuery")
local harness = require("../harness")

return function(suite: harness.Harness)
    suite:test("addDays crosses month, year and leap boundaries", function()
        harness.equal(AnalyticsQuery.addDays("2026-03-01", -1), "2026-02-28")
        harness.equal(AnalyticsQuery.addDays("2028-03-01", -1), "2028-02-29")
        harness.equal(AnalyticsQuery.addDays("2026-01-01", -1), "2025-12-31")
        harness.equal(AnalyticsQuery.addDays("2026-12-31", 1), "2027-01-01")
        harness.equal(AnalyticsQuery.addDays("2026-11-04", -30), "2026-10-05")
        harness.isTrue(AnalyticsQuery.addDays("2026-02-30", 1) == nil, "not a real date")
        harness.isTrue(AnalyticsQuery.addDays("nope", 1) == nil, "not a date")
    end)

    suite:test("validateConfig skips on missing values and rejects a path-injecting id", function()
        local missing = AnalyticsQuery.validateConfig(nil, "k")
        harness.isTrue(not missing.ok and missing.error == "missing", "no universe")
        local noKey = AnalyticsQuery.validateConfig("123", "")
        harness.isTrue(not noKey.ok and noKey.error == "missing", "no key")
        local bad = AnalyticsQuery.validateConfig("1/../2", "k")
        harness.isTrue(not bad.ok and bad.error ~= "missing", "bad id")
        harness.isTrue(AnalyticsQuery.validateConfig("123", "k").ok, "good")
    end)

    suite:test("buildRequest makes a daily window ending today (exclusive)", function()
        local request = AnalyticsQuery.buildRequest("ForwardD1Retention", "2026-11-04", 30)
        harness.isTrue(request.ok, "ok")
        if request.ok then
            harness.equal(request.value.granularity, "OneDay")
            harness.equal(request.value.startTime, "2026-10-05T00:00:00Z")
            harness.equal(request.value.endTime, "2026-11-04T00:00:00Z")
        end
        harness.isFalse(AnalyticsQuery.buildRequest("bad name", "2026-11-04", 30).ok, "metric")
        harness.isFalse(AnalyticsQuery.buildRequest("DailyRevenue", "2026-11-04", 0).ok, "days")
        harness.isFalse(AnalyticsQuery.buildRequest("DailyRevenue", "2026-13-04", 5).ok, "date")
    end)

    suite:test("every configured metric builds a request", function()
        for _, metric in AnalyticsQuery.metrics do
            harness.isTrue(AnalyticsQuery.buildRequest(metric, "2026-11-04", 7).ok, metric)
        end
    end)

    suite:test("urls: metrics url and a poll url that cannot leave the API host", function()
        harness.equal(
            AnalyticsQuery.metricsUrl("42"),
            "https://apis.roblox.com/analytics-query-api/v1/universes/42/metrics"
        )
        harness.isTrue(
            AnalyticsQuery.pollUrl("v1/universes/42/operations/metrics/abc-123").ok,
            "documented shape"
        )
        harness.isFalse(AnalyticsQuery.pollUrl("https://evil.example/x").ok, "absolute url")
        harness.isFalse(AnalyticsQuery.pollUrl("v1/universes/42/operations/../../x").ok, "dotdot")
        harness.isFalse(AnalyticsQuery.pollUrl("//evil.example/v1").ok, "scheme-relative")
    end)

    suite:test("parseResponse reads points and reports api errors by code only", function()
        local done = AnalyticsQuery.parseResponse({
            done = true,
            response = {
                values = {
                    {
                        breakdowns = {},
                        dataPoints = {
                            { time = "2026-11-01T00:00:00Z", value = 10 },
                            { time = "2026-11-02T00:00:00Z", value = 14 },
                        },
                    },
                },
            },
        })
        harness.isTrue(done.ok and #done.value == 2, "two valid points")
        local partial = AnalyticsQuery.parseResponse({
            done = true,
            response = { values = { { dataPoints = { { time = "2026-11-03T00:00:00Z" } } } } },
        })
        harness.isTrue(partial.ok and #partial.value == 0, "points without a value are dropped")
        local failed = AnalyticsQuery.parseResponse({
            done = true,
            error = { code = 2001, message = "secret" },
        })
        harness.isTrue(not failed.ok and failed.error == "api error 2001", "code only")
        harness.isFalse(AnalyticsQuery.parseResponse({ done = false }).ok, "pending")
        harness.isFalse(AnalyticsQuery.parseResponse("text").ok, "not an object")
        harness.isFalse(AnalyticsQuery.parseResponse({ done = true }).ok, "no response")
        local empty = AnalyticsQuery.parseResponse({ done = true, response = { values = {} } })
        harness.isTrue(empty.ok and #empty.value == 0, "empty series is valid")
        harness.isFalse(
            AnalyticsQuery.parseResponse({ done = true, response = { values = { 1 } } }).ok,
            "bad series"
        )
        harness.isFalse(
            AnalyticsQuery.parseResponse({ done = true, response = { values = { {} } } }).ok,
            "no points"
        )
    end)

    suite:test("errorCode never returns message text", function()
        harness.equal(AnalyticsQuery.errorCode({ error = { code = 3000, message = "x" } }), "3000")
        harness.equal(AnalyticsQuery.errorCode({ error = { code = "oops" } }), "none")
        harness.equal(AnalyticsQuery.errorCode({ error = "text" }), "none")
        harness.equal(AnalyticsQuery.errorCode("text"), "none")
    end)

    suite:test("summarize and statusLine", function()
        local summary = AnalyticsQuery.summarize({
            { time = "2026-11-01T00:00:00Z", value = 2 },
            { time = "2026-11-03T00:00:00Z", value = 6 },
            { time = "2026-11-02T00:00:00Z", value = 4 },
        }, "DailyActiveUsers")
        harness.equal(summary.points, 3)
        harness.equal(summary.mean, 4)
        local latest = summary.latest
        harness.isTrue(latest ~= nil and latest.value == 6, "latest by time")
        harness.equal(AnalyticsQuery.summarize({}, "m").points, 0)
        local line = AnalyticsQuery.statusLine({
            { metric = "A", result = { ok = true, value = {} } },
            { metric = "B", result = { ok = false, error = "HTTP 503, api code 2002" } },
        })
        harness.equal(line, "own-analytics: 1/2 metrics ok; failed: B: HTTP 503, api code 2002")
    end)
end
