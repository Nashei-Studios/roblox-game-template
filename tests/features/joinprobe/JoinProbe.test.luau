--!strict
local ClientJoinProbe = require("../../../src/shared/features/joinprobe/ClientJoinProbe")
local ProbeLine = require("../../../src/shared/features/joinprobe/ProbeLine")
local ServerJoinProbe = require("../../../src/shared/features/joinprobe/ServerJoinProbe")
local harness = require("../../harness")

local function fakeClock(): ({ now: number }, () -> number)
    local state = { now = 100 }
    return state, function(): number
        return state.now
    end
end

local function validWire(): { [string]: unknown }
    return {
        boot = 12,
        gameTime = 9,
        uiKit = 1.5,
        mining = 2,
        hello = 4,
        swing = -1,
        swingAck = -1,
        root = 0.5,
        paused = 3,
        intro = 0.4,
        firstTap = 1.2,
        provisional = 5,
        waits = { { name = "rig", seconds = 0.2, timedOut = false } },
    }
end

return function(suite: harness.Harness)
    suite:test("ProbeLine sorts keys, trims numbers and escapes strings", function()
        local line = ProbeLine.format({ b = 1.5, a = 'x"y', c = true, d = 2 })
        harness.equal(line, '[JOINPROBE] {"a":"x\\"y","b":1.5,"c":true,"d":2}', "line")
    end)

    suite:test("ProbeLine drops non-finite numbers", function()
        local line = ProbeLine.format({ a = 0 / 0, b = math.huge, c = 1 })
        harness.equal(line, '[JOINPROBE] {"c":1}', "line")
    end)

    suite:test("server probe measures each stage from begin", function()
        local state, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "job-a" })
        probe:begin(7)
        state.now += 45
        probe:mark(7, "join")
        probe:setJoinResult(7, true, false)
        state.now += 1
        probe:mark(7, "passes")
        probe:mark(7, "hello")
        state.now += 0.5
        probe:mark(7, "post")
        probe:setPrior(7, "found", { placeId = 5, jobId = "job-b" }, 0.25)
        local report = probe:finish(7)
        if report == nil then
            error("report expected")
        end
        harness.equal(report.fields.joinS, 45, "joinS")
        harness.equal(report.fields.passesS, 46, "passesS")
        harness.equal(report.fields.helloS, 46, "helloS")
        harness.equal(report.fields.postS, 46.5, "postS")
        harness.equal(report.fields.profileNil, false, "profileNil")
        harness.equal(report.fields.priorJobId, "job-b", "priorJobId")
        harness.equal(report.fields.priorSameJob, false, "priorSameJob")
        harness.equal(report.headlineSeconds, 46, "headline is the hello time")
        harness.isTrue(string.find(report.line, "[JOINPROBE]", 1, true) == 1, "line prefix")
    end)

    suite:test("a stage is recorded once and a missing one is omitted", function()
        local state, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "j" })
        probe:begin(1)
        state.now += 2
        probe:mark(1, "join")
        state.now += 5
        probe:mark(1, "join")
        probe:setJoinResult(1, false, true)
        local report = probe:finish(1)
        if report == nil then
            error("report expected")
        end
        harness.equal(report.fields.joinS, 2, "first mark wins")
        harness.isTrue(report.fields.helloS == nil, "no hello")
        harness.equal(report.fields.priorStatus, "pending", "lookup not back")
        harness.equal(report.headlineSeconds, 2, "falls back to the join time")
    end)

    suite:test("a prior holder with this JobId is flagged as the same job", function()
        local _, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "same" })
        probe:begin(1)
        probe:setPrior(1, "found", { placeId = 1, jobId = "same" }, 0.1)
        local report = probe:finish(1)
        if report == nil then
            error("report expected")
        end
        harness.equal(report.fields.priorSameJob, true, "same job")
    end)

    suite:test("the prior holder metadata adds studio, age and force load fields", function()
        local _, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "live" })
        probe:begin(1)
        probe:setPrior(1, "found", { placeId = 1, jobId = "" }, 0.2, {
            ageS = 12.5,
            forceLoadPending = true,
        })
        local report = probe:finish(1)
        if report == nil then
            error("report expected")
        end
        harness.equal(report.fields.priorStudio, true, "studio")
        harness.equal(report.fields.priorAgeS, 12.5, "age")
        harness.equal(report.fields.priorForceLoad, true, "force load")
        harness.equal(report.fields.priorSameJob, false, "not same job")
    end)

    suite:test("a live-server holder is not studio and no extra means no extra fields", function()
        local _, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "live" })
        probe:begin(1)
        probe:setPrior(1, "found", { placeId = 1, jobId = "other" }, 0.2)
        local report = probe:finish(1)
        if report == nil then
            error("report expected")
        end
        harness.equal(report.fields.priorStudio, false, "studio")
        harness.isTrue(report.fields.priorAgeS == nil, "age")
        harness.isTrue(report.fields.priorForceLoad == nil, "force load")
    end)

    suite:test("marks for an unknown player are ignored and finish is nil", function()
        local _, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "j" })
        probe:mark(9, "join")
        harness.isTrue(probe:finish(9) == nil, "no entry")
        probe:begin(9)
        probe:forget(9)
        harness.isTrue(probe:finish(9) == nil, "forgotten")
    end)

    suite:test("the client report is accepted once per session", function()
        local _, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "j" })
        probe:begin(3)
        probe:begin(4)
        harness.equal(probe:acceptClient(4), 2, "sequence of the second join")
        harness.isTrue(probe:acceptClient(4) == nil, "second report ignored")
        harness.isTrue(probe:acceptClient(99) == nil, "unprobed player ignored")
    end)

    suite:test("client probe marks are relative to start and -1 when missing", function()
        local state, clock = fakeClock()
        local probe = ClientJoinProbe.new({
            clock = clock,
            gameTime = function(): number
                return 8
            end,
        })
        state.now += 2
        probe:mark("uiKit")
        state.now += 3
        probe:mark("uiKit")
        probe:mark("hello")
        local report = probe:report()
        harness.equal(report.uiKit, 2, "first mark wins")
        harness.equal(report.hello, 5, "hello")
        harness.equal(report.swing, -1, "swing not reached")
        harness.equal(report.boot, 100, "boot clock")
        harness.equal(report.gameTime, 8, "game time")
    end)

    suite:test("paused time accumulates and is clipped to the first 60 s", function()
        local state, clock = fakeClock()
        local probe = ClientJoinProbe.new({
            clock = clock,
            gameTime = function(): number
                return 0
            end,
        })
        state.now += 10
        probe:setPaused(true)
        state.now += 5
        probe:setPaused(false)
        state.now += 30
        probe:setPaused(true)
        state.now += 100
        harness.equal(probe:report().paused, 5 + 15, "still paused at the window end")
        probe:setPaused(false)
        harness.equal(probe:report().paused, 20, "closing after the window adds nothing")
    end)

    suite:test("waits keep the first record per name and cap at the maximum", function()
        local _, clock = fakeClock()
        local probe = ClientJoinProbe.new({
            clock = clock,
            gameTime = function(): number
                return 0
            end,
        })
        probe:recordWait("rig", 1, false)
        probe:recordWait("rig", 9, true)
        probe:recordWait("rigFace", 20, true)
        for index = 1, 20 do
            probe:recordWait("w" .. index, 1, false)
        end
        local report = probe:report()
        harness.equal(#report.waits, ClientJoinProbe.MAX_WAITS, "capped")
        harness.equal(report.waits[1].seconds, 1, "first rig wait kept")
        harness.isTrue(report.waits[2].timedOut, "timeout flag kept")
    end)

    suite:test("claimSend is true only once", function()
        local _, clock = fakeClock()
        local probe = ClientJoinProbe.new({
            clock = clock,
            gameTime = function(): number
                return 0
            end,
        })
        harness.isTrue(probe:claimSend(), "first")
        harness.isFalse(probe:claimSend(), "second")
    end)

    suite:test("fields flatten the waits and merge extras", function()
        local extra: ProbeLine.Fields = { jobId = "j" }
        local fields = ClientJoinProbe.fields({
            boot = 1,
            gameTime = 2,
            uiKit = 3,
            mining = 4,
            hello = 5,
            swing = -1,
            swingAck = -1,
            root = 6,
            paused = 7,
            intro = 0.5,
            firstTap = 2,
            provisional = 9,
            waits = { { name = "rig", seconds = 0.5, timedOut = true } },
        }, extra)
        harness.equal(fields.kind, "client", "kind")
        harness.equal(fields.wait_rig, 0.5, "wait seconds")
        harness.equal(fields.timedOut_rig, true, "wait timeout")
        harness.equal(fields.pausedS, 7, "paused")
        harness.equal(fields.introShownS, 0.5, "intro")
        harness.equal(fields.firstTapS, 2, "first tap")
        harness.equal(fields.provisionalTaps, 9, "provisional taps")
        harness.equal(fields.jobId, "j", "extra")
    end)

    suite:test("only the first hello is marked: retries do not overwrite it", function()
        local state, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "j" })
        probe:begin(1)
        state.now += 2
        probe:mark(1, "hello")
        state.now += 20
        probe:mark(1, "hello")
        local report = probe:finish(1)
        harness.isTrue(report ~= nil and report.fields.helloS == 2, "first hello wins")
        local clientClock, readClock = fakeClock()
        local client = ClientJoinProbe.new({ clock = readClock, gameTime = readClock })
        clientClock.now += 3
        client:mark("hello")
        clientClock.now += 30
        client:mark("hello")
        harness.equal(client:report().hello, 3, "client keeps the first hello too")
    end)

    suite:test("every server line carries the boot warm-up time", function()
        local state, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "j" })
        probe:begin(1)
        local before = probe:finish(1)
        harness.isTrue(before ~= nil and before.fields.bootWarmS == -1, "-1 until measured")
        probe:setBootWarm(4.5)
        state.now += 1
        local after = probe:finish(1)
        harness.isTrue(after ~= nil and after.fields.bootWarmS == 4.5, "measured")
    end)

    suite:test("the provisional batch has its own line with claimed and credited taps", function()
        local state, clock = fakeClock()
        local probe = ServerJoinProbe.new({ clock = clock, jobId = "j" })
        harness.isTrue(probe:provisional(1, 5, 5) == nil, "unknown player")
        probe:begin(1)
        state.now += 7
        local report = probe:provisional(1, 90, 84)
        harness.isTrue(report ~= nil, "report")
        if report ~= nil then
            harness.equal(report.fields.kind, "provisional", "kind")
            harness.equal(report.fields.provisionalTaps, 90, "claimed")
            harness.equal(report.fields.provisionalCredited, 84, "credited")
            harness.equal(report.fields.atS, 7, "when")
            harness.isTrue(
                string.find(report.line, "provisionalCredited", 1, true) ~= nil,
                "in the line"
            )
        end
    end)

    suite:test("the client probe takes loader marks and counts provisional taps", function()
        local _state, clock = fakeClock()
        local probe = ClientJoinProbe.new({ clock = clock, gameTime = clock })
        probe:markSeconds("intro", 0.4)
        probe:markSeconds("intro", 9)
        probe:addProvisional(3)
        probe:addProvisional(4)
        probe:mark("firstTap")
        local report = probe:report()
        harness.equal(report.intro, 0.4, "first intro mark wins")
        harness.equal(report.provisional, 7, "taps summed")
        harness.equal(report.firstTap, 0, "first tap marked")
        harness.equal(ClientJoinProbe.validate(validWire()).ok, true, "wire still valid")
    end)

    suite:test("validate refuses a provisional count out of range", function()
        local wire = validWire()
        wire.provisional = 1e9
        harness.isFalse(ClientJoinProbe.validate(wire).ok, "too many")
        wire.provisional = 5
        wire.intro = -5
        harness.isFalse(ClientJoinProbe.validate(wire).ok, "intro below -1")
    end)

    suite:test("validate accepts a well-formed report", function()
        local checked = ClientJoinProbe.validate(validWire())
        harness.isTrue(checked.ok, "accepted")
        if checked.ok then
            harness.equal(checked.value.waits[1].name, "rig", "wait name")
            harness.equal(checked.value.hello, 4, "hello")
        end
    end)

    suite:test("validate rejects bad shapes, bounds, NaN and unknown wait names", function()
        harness.isFalse(ClientJoinProbe.validate(nil).ok, "not a table")
        local cases: { { label: string, change: (wire: { [string]: unknown }) -> () } } = {
            {
                label = "nan",
                change = function(wire)
                    wire.uiKit = 0 / 0
                end,
            },
            {
                label = "missing",
                change = function(wire)
                    wire.hello = nil
                end,
            },
            {
                label = "too big",
                change = function(wire)
                    wire.root = 99999
                end,
            },
            {
                label = "below -1",
                change = function(wire)
                    wire.mining = -2
                end,
            },
            {
                label = "paused over window",
                change = function(wire)
                    wire.paused = 500
                end,
            },
            {
                label = "waits not a table",
                change = function(wire)
                    wire.waits = "x"
                end,
            },
            {
                label = "too many waits",
                change = function(wire)
                    local many: { unknown } = {}
                    for _ = 1, 9 do
                        table.insert(many, { name = "rig", seconds = 1, timedOut = false })
                    end
                    wire.waits = many
                end,
            },
            {
                label = "unknown wait name",
                change = function(wire)
                    wire.waits = { { name = "evil", seconds = 1, timedOut = false } }
                end,
            },
            {
                label = "bad wait seconds",
                change = function(wire)
                    wire.waits = { { name = "rig", seconds = -5, timedOut = false } }
                end,
            },
            {
                label = "bad wait flag",
                change = function(wire)
                    wire.waits = { { name = "rig", seconds = 1, timedOut = "no" } }
                end,
            },
            {
                label = "wait entry not a table",
                change = function(wire)
                    wire.waits = { 5 }
                end,
            },
        }
        for _, case in cases do
            local wire = validWire()
            case.change(wire)
            harness.isFalse(ClientJoinProbe.validate(wire).ok, case.label)
        end
    end)
end
