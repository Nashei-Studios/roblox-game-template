--!strict
local PlusPort = require("../../../src/shared/ports/PlusPort")
local PlusPrompt = require("../../../src/shared/features/plus/PlusPrompt")
local harness = require("../../harness")

type Fixture = {
    prompt: PlusPrompt.PlusPrompt,
    prompts: { number },
    thanked: { number },
    state: { now: number, plus: boolean?, allowed: boolean, promptFails: boolean },
}

local function newFixture(enabled: boolean): Fixture
    local prompts: { number } = {}
    local thanked: { number } = {}
    local state = { now = 0, plus = false :: boolean?, allowed = true, promptFails = false }
    local port: PlusPort.PlusPort = {
        hasPlus = function(_self, _userId: number): boolean?
            return state.plus
        end,
        prompt = function(_self, userId: number)
            if state.promptFails then
                return { ok = false, error = { kind = "plus_failed", message = "x" } }
            end
            table.insert(prompts, userId)
            return { ok = true }
        end,
        onPlusChanged = function(_self, _listener)
            return function() end
        end,
    }
    local prompt = PlusPrompt.new({
        config = {
            enabled = enabled,
            placements = { "menu", "levelEnd" },
            cooldownSeconds = 100,
            maxPromptsPerSession = 2,
        },
        port = port,
        allow = function(_userId: number): boolean
            return state.allowed
        end,
        clock = function(): number
            return state.now
        end,
        onSubscribed = function(userId: number)
            table.insert(thanked, userId)
        end,
    })
    return { prompt = prompt, prompts = prompts, thanked = thanked, state = state }
end

local function reasonOf(result: PlusPrompt.HandleResult): string
    if result.ok then
        return "ok"
    end
    return result.reason
end

return function(suite: harness.Harness)
    suite:test("disabled by config: no prompt", function()
        local fixture = newFixture(false)
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "disabled", "reason")
        harness.equal(#fixture.prompts, 0, "no prompt")
    end)

    suite:test("a requested placement opens the prompt", function()
        local fixture = newFixture(true)
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "ok", "ok")
        harness.equal(#fixture.prompts, 1, "prompted")
    end)

    suite:test("unknown placements and flooding never prompt", function()
        local fixture = newFixture(true)
        harness.equal(reasonOf(fixture.prompt:handle(1, "popup")), "not_allowed", "unknown")
        fixture.state.allowed = false
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "rate_limited", "limited")
        harness.equal(#fixture.prompts, 0, "no prompt")
    end)

    suite:test("a player who already has Plus is not prompted", function()
        local fixture = newFixture(true)
        fixture.state.plus = true
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "already_plus", "reason")
        harness.equal(#fixture.prompts, 0, "no prompt")
    end)

    suite:test("an unknown status is a rejection, not a guess", function()
        local fixture = newFixture(true)
        fixture.state.plus = nil
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "status_unknown", "reason")
    end)

    suite:test("frequency: cooldown and the per-session cap come from Config", function()
        local fixture = newFixture(true)
        fixture.prompt:handle(1, "menu")
        fixture.state.now = 50
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "cooldown", "cooldown")
        fixture.state.now = 150
        harness.equal(reasonOf(fixture.prompt:handle(1, "levelEnd")), "ok", "second prompt")
        fixture.state.now = 400
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "session_cap_reached", "cap")
        harness.equal(#fixture.prompts, 2, "two prompts")
    end)

    suite:test("a prompt that fails is typed and does not use up the budget", function()
        local fixture = newFixture(true)
        fixture.state.promptFails = true
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "prompt_failed", "reason")
        fixture.state.promptFails = false
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "ok", "next works")
    end)

    suite:test("onSubscribed fires once, only for a player prompted this session", function()
        local fixture = newFixture(true)
        fixture.prompt:onPlusChanged(1, true)
        harness.equal(#fixture.thanked, 0, "not prompted: no signal")
        fixture.prompt:handle(1, "menu")
        fixture.prompt:onPlusChanged(1, false)
        harness.equal(#fixture.thanked, 0, "still not subscribed")
        fixture.prompt:onPlusChanged(1, true)
        fixture.prompt:onPlusChanged(1, true)
        harness.equal(#fixture.thanked, 1, "exactly once")
    end)

    suite:test("forget clears the session budget", function()
        local fixture = newFixture(true)
        fixture.prompt:handle(1, "menu")
        fixture.prompt:forget(1)
        fixture.state.now = 1
        harness.equal(reasonOf(fixture.prompt:handle(1, "menu")), "ok", "fresh session")
    end)
end
