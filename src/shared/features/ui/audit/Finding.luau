--!strict
--[[
    A UI audit finding: one broken rule on one instance. Shared by the static audit (Lune, over the
    committed .rbxm pieces) and the runtime audit (execute_luau in a playtest), so both reports have
    the same shape and the same rule ids (docs/ui-audit.md).
]]

export type Severity = "error" | "warn"

export type Finding = {
    rule: string,
    severity: Severity,
    -- Where it was measured: a piece file for the static audit, "<viewport>" for the runtime one.
    scope: string,
    -- Dotted path of the instance inside its root.
    path: string,
    message: string,
}

local FindingModule = {}

--- Builds a finding.
function FindingModule.new(
    rule: string,
    severity: Severity,
    scope: string,
    path: string,
    message: string
): Finding
    return { rule = rule, severity = severity, scope = scope, path = path, message = message }
end

--- One line per finding: `file path rule message`, the shape the gate prints.
function FindingModule.format(finding: Finding): string
    return `[{finding.severity}] {finding.rule} {finding.scope} {finding.path}: {finding.message}`
end

--- Counts findings per rule id.
function FindingModule.countByRule(findings: { Finding }): { [string]: number }
    local counts: { [string]: number } = {}
    for _, finding in findings do
        counts[finding.rule] = (counts[finding.rule] or 0) + 1
    end
    return counts
end

return FindingModule
