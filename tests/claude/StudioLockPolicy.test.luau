--!strict
local StudioLockPolicy = require("../../.claude/hooks/StudioLockPolicy")
local harness = require("../harness")

local THIS = "D:\\Victor\\Repositorios\\roblox\\game-agent-a"
local OTHER = "D:/Victor/Repositorios/roblox/game-agent-b"

return function(suite: harness.Harness)
    suite:test("a tool that is not Studio or rojo serve is allowed without a lock", function()
        local decision = StudioLockPolicy.decide({ toolName = "Read", command = nil }, nil, THIS)
        harness.isTrue(decision.allow)
    end)

    suite:test("a Studio tool without the lock is blocked with a reason", function()
        local decision = StudioLockPolicy.decide(
            { toolName = "mcp__Roblox_Studio__execute_luau", command = nil },
            nil,
            THIS
        )
        harness.isTrue(not decision.allow)
        harness.isTrue(decision.reason ~= nil and #decision.reason > 0)
    end)

    suite:test("a lock held by another worktree blocks", function()
        local decision = StudioLockPolicy.decide(
            { toolName = "mcp__Roblox_Studio__list_roblox_studios", command = nil },
            OTHER,
            THIS
        )
        harness.isTrue(not decision.allow)
    end)

    suite:test("a lock held by this worktree allows", function()
        local decision = StudioLockPolicy.decide(
            { toolName = "mcp__Roblox_Studio__list_roblox_studios", command = nil },
            THIS,
            THIS
        )
        harness.isTrue(decision.allow)
    end)

    suite:test("paths compare case-insensitively and slash-normalized", function()
        harness.equal(
            StudioLockPolicy.normalizePath("D:\\Victor\\Repo\\"),
            StudioLockPolicy.normalizePath("d:/victor/repo")
        )
        local decision = StudioLockPolicy.decide(
            { toolName = "mcp__Roblox_Studio__x", command = nil },
            "d:/victor/repositorios/roblox/GAME-AGENT-A/",
            THIS
        )
        harness.isTrue(decision.allow)
    end)

    suite:test("rojo serve is blocked without the lock", function()
        for _, tool in { "Bash", "PowerShell" } do
            local decision = StudioLockPolicy.decide(
                { toolName = tool, command = "rojo serve --port 34873" },
                nil,
                THIS
            )
            harness.isTrue(not decision.allow, tool)
        end
        local chained = StudioLockPolicy.decide(
            { toolName = "Bash", command = "cd x && rojo serve" },
            nil,
            THIS
        )
        harness.isTrue(not chained.allow)
    end)

    suite:test("rojo build and other shell commands are allowed", function()
        local build = StudioLockPolicy.decide(
            { toolName = "Bash", command = "rojo build default.project.json -o places/dev.rbxl" },
            nil,
            THIS
        )
        harness.isTrue(build.allow)
        local other =
            StudioLockPolicy.decide({ toolName = "Bash", command = "echo rojo servers" }, nil, THIS)
        harness.isTrue(other.allow)
    end)

    suite:test("parseLockWorktree reads the worktree key", function()
        local body = "agent=a1\r\nworktree=D:\\x\\y\nbranch=b\n"
        harness.equal(StudioLockPolicy.parseLockWorktree(body), "D:\\x\\y")
        harness.equal(StudioLockPolicy.parseLockWorktree("agent=a1\n"), nil)
    end)
end
