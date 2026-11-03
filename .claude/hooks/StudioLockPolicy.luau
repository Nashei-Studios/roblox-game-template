--!strict
--[[
    Pure decision for the Studio lock (docs/multi-agent.md, ADR 0013). No Lune API and no I/O, so
    it loads under Lune and the Luau CLI and is unit tested. `studio-lock.luau` does the I/O.
]]

export type HookInput = {
    toolName: string,
    command: string?,
}

export type Decision = {
    allow: boolean,
    reason: string?,
}

local STUDIO_TOOL_PREFIX = "mcp__Roblox_Studio__"
local SHELL_TOOLS: { [string]: boolean } = { Bash = true, PowerShell = true }

local StudioLockPolicy = {}

--- Lowercases and converts backslashes so Windows paths compare equal.
function StudioLockPolicy.normalizePath(path: string): string
    local lowered = string.lower((string.gsub(path, "\\", "/")))
    return (string.gsub(lowered, "/+$", ""))
end

--- Reads the `worktree=` line of a `.studio.lock` body; nil when absent.
function StudioLockPolicy.parseLockWorktree(body: string): string?
    for line in string.gmatch(body, "[^\r\n]+") do
        local value = string.match(line, "^%s*worktree%s*=%s*(.-)%s*$")
        if value ~= nil and value ~= "" then
            return value
        end
    end
    return nil
end

--- True when the shell command runs `rojo serve` (at the start or after ; && | ).
function StudioLockPolicy.isRojoServe(command: string): boolean
    local padded = ";" .. command
    return string.find(padded, "[;&|]%s*rojo%s+serve") ~= nil
end

--- True when this call needs the lock: a Studio MCP tool or `rojo serve`.
function StudioLockPolicy.needsLock(input: HookInput): boolean
    if string.sub(input.toolName, 1, #STUDIO_TOOL_PREFIX) == STUDIO_TOOL_PREFIX then
        return true
    end
    if SHELL_TOOLS[input.toolName] == true and input.command ~= nil then
        return StudioLockPolicy.isRojoServe(input.command)
    end
    return false
end

--- `lockWorktree` is the `worktree=` value of the lock (nil when there is no lock).
function StudioLockPolicy.decide(
    input: HookInput,
    lockWorktree: string?,
    currentWorktree: string
): Decision
    if not StudioLockPolicy.needsLock(input) then
        return { allow = true, reason = nil }
    end
    if lockWorktree == nil then
        return {
            allow = false,
            reason = "Studio lock not held: pass the headless gate, then create .studio.lock at the main checkout root (docs/multi-agent.md, Studio lock > Acquire).",
        }
    end
    if
        StudioLockPolicy.normalizePath(lockWorktree)
        ~= StudioLockPolicy.normalizePath(currentWorktree)
    then
        return {
            allow = false,
            reason = "Studio lock is held by another worktree: keep working headless and retry later, never delete it (docs/multi-agent.md, Studio lock > Stale locks).",
        }
    end
    return { allow = true, reason = nil }
end

return StudioLockPolicy
