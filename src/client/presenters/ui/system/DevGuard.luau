--!strict
--[[
    Dev-mode assertions of the UI system. Every primitive and component calls `DevGuard.verify`
    on what it just built. In Studio a broken rule raises (the stack trace points at the call
    site that built it); in a live server it only warns once per rule and path, so a player never
    sees a crash for a spacing bug.

    The tree rules are the SAME code as the static audit gate (ui/audit/StaticRules): list gap,
    grid cell padding, scroller canvas and padding, text fit, touch size, kit stroke. The
    construction-time rules (token gap, off-scale padding) are uisystem/Contracts. One rule set.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Finding = require(Shared.features.ui.audit.Finding)
local StaticRules = require(Shared.features.ui.audit.StaticRules)

local DevGuard = {}

DevGuard.enabled = RunService:IsStudio()

local warned: { [string]: boolean } = {}

local function raise(lines: { string })
    local message = `UI system rules broken:\n{table.concat(lines, "\n")}`
    if DevGuard.enabled then
        error(message, 3)
    end
    for _, line in lines do
        if not warned[line] then
            warned[line] = true
            warn(line)
        end
    end
end

--- Reports the sentence of a construction-time rule (a Contracts result), if any.
function DevGuard.require(problem: string?)
    if problem ~= nil then
        raise({ problem })
    end
end

--- Reports every sentence of a list of problems.
function DevGuard.requireAll(problems: { string })
    if #problems > 0 then
        raise(problems)
    end
end

--- Audits a freshly built subtree with the static rules and raises on any finding.
function DevGuard.verify(root: Instance, scope: string)
    local findings = StaticRules.auditRoot(root, scope)
    if #findings == 0 then
        return
    end
    local lines: { string } = {}
    for _, finding in findings do
        table.insert(lines, Finding.format(finding))
    end
    raise(lines)
end

return DevGuard
