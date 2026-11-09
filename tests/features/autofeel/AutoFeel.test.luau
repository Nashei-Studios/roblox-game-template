--!strict
local AutoFeel = require("../../../src/shared/features/autofeel/AutoFeel")
local AutoFeelScheduler = require("../../../src/shared/features/autofeel/AutoFeelScheduler")
local harness = require("../../harness")

local CONFIG = AutoFeel.default

local function with(change: (config: AutoFeel.AutoFeelConfig) -> ()): AutoFeel.AutoFeelConfig
    local copy = table.clone(CONFIG)
    copy.sound = table.clone(CONFIG.sound)
    change(copy)
    return copy
end

local AT_ROCK: AutoFeelScheduler.Context = {
    rate = 3,
    moving = false,
    menuOpen = false,
    distance = 8,
}

local function context(change: (c: AutoFeelScheduler.Context) -> ()): AutoFeelScheduler.Context
    local copy = table.clone(AT_ROCK)
    change(copy)
    return copy
end

-- Runs the scheduler once per `dt` from `from` to `to` and returns the swings and popups.
local function run(
    scheduler: AutoFeelScheduler.Scheduler,
    from: number,
    to: number,
    dt: number,
    ctx: AutoFeelScheduler.Context
): (number, { number })
    local swings = 0
    local popups: { number } = {}
    local now = from
    while now <= to + 1e-9 do
        local tick = scheduler:step(now, ctx)
        if tick.swing then
            swings += 1
        end
        if tick.popup ~= nil then
            table.insert(popups, tick.popup)
        end
        now += dt
    end
    return swings, popups
end

return function(suite: harness.Harness)
    suite:test("the default config is valid", function()
        harness.equal(#AutoFeel.validate(CONFIG), 0, table.concat(AutoFeel.validate(CONFIG), "; "))
    end)

    suite:test("invalid configs are reported one problem each", function()
        harness.equal(#AutoFeel.validate(with(function(c)
            c.cadenceSeconds = 0.2
        end)), 1, "cadence too fast")
        harness.equal(#AutoFeel.validate(with(function(c)
            c.cadenceSeconds = 1.5
        end)), 1, "cadence too slow")
        harness.equal(#AutoFeel.validate(with(function(c)
            c.aggregateWindowSeconds = 0.1
        end)), 1, "window too short")
        harness.equal(#AutoFeel.validate(with(function(c)
            c.swingWeight = 0
        end)), 1, "weight")
        harness.equal(#AutoFeel.validate(with(function(c)
            c.popupColorHex = "blue"
        end)), 1, "color")
        harness.equal(#AutoFeel.validate(with(function(c)
            c.sound.volumeScale = 2
        end)), 1, "volume")
        harness.equal(#AutoFeel.validate(with(function(c)
            c.radiusStuds = 0 / 0
        end)), 1, "nan radius")
    end)

    suite:test("manual is the full feel and ignores the config", function()
        local manual = AutoFeel.profile(CONFIG, "manual")
        harness.isTrue(manual.hitStop and manual.fovKick, "hit-stop and FOV kick")
        harness.equal(manual.popup, "perHit", "per-hit popup")
        harness.equal(manual.rockScale, 1, "full rock reaction")
        harness.equal(manual.swingWeight, 1, "full weight")
    end)

    suite:test("auto keeps the grammar, lowers the voice and drops hit-stop and FOV", function()
        local auto = AutoFeel.profile(CONFIG, "auto")
        harness.isTrue(auto.swing, "swings")
        harness.isFalse(auto.hitStop, "no hit-stop")
        harness.isFalse(auto.fovKick, "no FOV kick")
        harness.equal(auto.popup, "aggregated", "aggregated popup")
        harness.isTrue(auto.soundEnabled, "sound on")
        harness.isTrue(auto.soundVolumeScale < 1, "quieter")
        harness.isTrue(auto.soundPitchShift ~= 1, "pitch shifted")
        harness.isTrue(auto.rockScale > 0 and auto.rockScale < 1, "small rock reaction")
        harness.isTrue(auto.swingWeight < 1, "lighter swing")
    end)

    suite:test("observers swing and nothing else (LOD for other players)", function()
        local observer = AutoFeel.profile(CONFIG, "observer")
        harness.isTrue(observer.swing, "the swing is the social proof")
        harness.equal(observer.popup, "none", "no popup")
        harness.isFalse(observer.soundEnabled, "no sound")
        harness.isFalse(observer.hitStop or observer.fovKick, "no camera or time effects")
        harness.equal(observer.rockScale + observer.chipScale, 0, "no rock work")
    end)

    suite:test("swings keep the cadence whatever the paid rate is", function()
        for _, rate in { 1, 3, 12 } do
            local scheduler = AutoFeelScheduler.new(CONFIG)
            local swings = run(
                scheduler,
                100,
                110,
                1 / 60,
                context(function(c)
                    c.rate = rate
                end)
            )
            -- 10 s at 0.65 s per swing = 15.4: the first swing is immediate.
            harness.isTrue(swings >= 15 and swings <= 17, `rate {rate} gave {swings} swings`)
        end
    end)

    suite:test("popups aggregate the server deltas once per window and sum them", function()
        local scheduler = AutoFeelScheduler.new(CONFIG)
        local popups: { number } = {}
        local now = 100
        for step = 0, 300 do
            now = 100 + step / 60
            if step % 30 == 15 then
                scheduler:noteDelta(2)
            end
            local tick = scheduler:step(now, AT_ROCK)
            if tick.popup ~= nil then
                table.insert(popups, tick.popup)
            end
        end
        -- 5 s, one popup per second after the first window, each the sum of the deltas inside it.
        harness.isTrue(#popups >= 3 and #popups <= 5, `popups {#popups}`)
        for _, amount in popups do
            harness.isTrue(amount >= 2 and amount <= 4, `amount {amount}`)
        end
    end)

    suite:test("no popup without a server delta, and bad deltas are ignored", function()
        local scheduler = AutoFeelScheduler.new(CONFIG)
        scheduler:step(99, AT_ROCK)
        scheduler:noteDelta(-5)
        scheduler:noteDelta(0 / 0)
        scheduler:noteDelta(math.huge)
        local _swings, popups = run(scheduler, 100, 110, 1 / 30, AT_ROCK)
        harness.equal(#popups, 0, "nothing invented")
    end)

    suite:test("a manual tap pauses the auto visuals and they return after the override", function()
        local scheduler = AutoFeelScheduler.new(CONFIG)
        scheduler:step(100, AT_ROCK)
        scheduler:noteManual(101)
        local during = scheduler:step(101 + CONFIG.overrideSeconds - 0.1, AT_ROCK)
        harness.isFalse(during.active, "still overridden")
        harness.equal(during.paused, "manual", "reason")
        harness.isFalse(during.swing, "no swing while overridden")
        local after = scheduler:step(101 + CONFIG.overrideSeconds + 0.01, AT_ROCK)
        harness.isTrue(after.active, "back after the delay")
    end)

    suite:test("the first auto swing after a manual one waits a full cadence", function()
        local scheduler = AutoFeelScheduler.new(CONFIG)
        scheduler:noteManual(100)
        local resume = 100 + CONFIG.overrideSeconds + 0.01
        harness.isTrue(scheduler:step(resume, AT_ROCK).swing, "cadence long gone: swings at once")
        scheduler:noteManual(200)
        harness.isFalse(scheduler:step(200.01, AT_ROCK).swing, "manual swing just played")
    end)

    suite:test("moving, a menu, distance and no drill each pause with their reason", function()
        local scheduler = AutoFeelScheduler.new(CONFIG)
        local cases: { { reason: AutoFeelScheduler.PauseReason, ctx: AutoFeelScheduler.Context } } =
            {
                {
                    reason = "moving",
                    ctx = context(function(c)
                        c.moving = true
                    end),
                },
                {
                    reason = "menu",
                    ctx = context(function(c)
                        c.menuOpen = true
                    end),
                },
                {
                    reason = "far",
                    ctx = context(function(c)
                        c.distance = CONFIG.radiusStuds + 1
                    end),
                },
                {
                    reason = "noAuto",
                    ctx = context(function(c)
                        c.rate = 0
                    end),
                },
            }
        for index, case in cases do
            local tick = scheduler:step(100 + index, case.ctx)
            harness.isFalse(tick.active, case.reason)
            harness.equal(tick.paused, case.reason, "reason")
            harness.isFalse(tick.swing, `{case.reason} does not swing`)
            harness.isTrue(tick.popup == nil, `{case.reason} does not pop`)
        end
    end)

    suite:test("the radius is inclusive", function()
        local edge = AutoFeelScheduler.pauseReason(
            CONFIG,
            context(function(c)
                c.distance = CONFIG.radiusStuds
            end),
            math.huge
        )
        harness.isTrue(edge == nil, "exactly at the radius still plays")
    end)

    suite:test("pause reasons rank no drill, manual, menu, moving, far", function()
        local all = context(function(c)
            c.moving = true
            c.menuOpen = true
            c.distance = 999
        end)
        harness.equal(AutoFeelScheduler.pauseReason(CONFIG, all, 0), "manual", "manual first")
        harness.equal(AutoFeelScheduler.pauseReason(CONFIG, all, math.huge), "menu", "then menu")
        all.menuOpen = false
        harness.equal(
            AutoFeelScheduler.pauseReason(CONFIG, all, math.huge),
            "moving",
            "then moving"
        )
        all.moving = false
        harness.equal(AutoFeelScheduler.pauseReason(CONFIG, all, math.huge), "far", "then far")
        all.rate = 0
        harness.equal(AutoFeelScheduler.pauseReason(CONFIG, all, 0), "noAuto", "no drill beats all")
    end)

    suite:test("a pause drops the pending delta and a resume waits a full window", function()
        local scheduler = AutoFeelScheduler.new(CONFIG)
        scheduler:step(100, AT_ROCK)
        scheduler:noteDelta(50)
        local moving = context(function(c)
            c.moving = true
        end)
        scheduler:step(100.5, moving)
        scheduler:noteDelta(7)
        local back = scheduler:step(101, AT_ROCK)
        harness.isTrue(back.popup == nil, "no popup at the resume")
        local later = scheduler:step(101 + CONFIG.aggregateWindowSeconds + 0.01, AT_ROCK)
        harness.isTrue(later.popup == nil, "the 50 and the 7 paid while paused are not shown")
    end)

    suite:test("a popup never lands while overridden or paused", function()
        local scheduler = AutoFeelScheduler.new(CONFIG)
        scheduler:step(100, AT_ROCK)
        scheduler:noteManual(100.2)
        scheduler:noteDelta(9)
        local tick = scheduler:step(
            103.5,
            context(function(c)
                c.menuOpen = true
            end)
        )
        harness.isTrue(tick.popup == nil, "menu open")
    end)

    suite:test("the budget helpers follow the config", function()
        harness.equal(AutoFeel.popupsPerSecond(CONFIG), 1, "one popup per 1 s window")
        harness.isTrue(math.abs(AutoFeel.swingsPerSecond(CONFIG) - 1 / 0.65) < 1e-9, "swings")
    end)
end
