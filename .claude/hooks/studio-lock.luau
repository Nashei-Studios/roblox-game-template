--!strict
--[[
    Claude Code PreToolUse hook: `lune run .claude/hooks/studio-lock` (see .claude/settings.json).
    Reads the hook JSON from stdin. Exit 0 = allow, exit 2 = block with the reason on stderr.
    The decision lives in StudioLockPolicy.luau; this file only does the I/O.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local StudioLockPolicy = require("./StudioLockPolicy")

local function git(args: { string }): string?
    local result = process.exec("git", args)
    if not result.ok then
        return nil
    end
    return (string.gsub(result.stdout, "%s+$", ""))
end

local function parseInput(raw: string): StudioLockPolicy.HookInput?
    local ok, decoded = pcall(function(): unknown
        return serde.decode("json", raw)
    end)
    if not ok or typeof(decoded) ~= "table" then
        return nil
    end
    local payload = decoded :: { [string]: unknown }
    local toolName = payload.tool_name
    if typeof(toolName) ~= "string" then
        return nil
    end
    local command: string? = nil
    local toolInput = payload.tool_input
    if typeof(toolInput) == "table" then
        local candidate = (toolInput :: { [string]: unknown }).command
        if typeof(candidate) == "string" then
            command = candidate
        end
    end
    return { toolName = toolName, command = command }
end

local input = parseInput(stdio.readToEnd())
if input == nil then
    -- Unparseable payload: not this hook's call to block.
    process.exit(0)
end
local hookInput = input :: StudioLockPolicy.HookInput

if not StudioLockPolicy.needsLock(hookInput) then
    process.exit(0)
end

local commonDir = git({ "rev-parse", "--path-format=absolute", "--git-common-dir" })
local currentWorktree = git({ "rev-parse", "--show-toplevel" })
if commonDir == nil or currentWorktree == nil then
    stdio.ewrite("studio-lock: not inside a git repository, cannot verify the Studio lock\n")
    process.exit(2)
end

local mainRoot = string.gsub(commonDir :: string, "[/\\]%.git[/\\]?$", "")
local lockPath = `{mainRoot}/.studio.lock`
local lockWorktree: string? = nil
if fs.isFile(lockPath) then
    lockWorktree = StudioLockPolicy.parseLockWorktree(fs.readFile(lockPath))
end

local decision = StudioLockPolicy.decide(hookInput, lockWorktree, currentWorktree :: string)
if decision.allow then
    process.exit(0)
end
stdio.ewrite(`{decision.reason or "Studio lock check failed"}\n`)
process.exit(2)
