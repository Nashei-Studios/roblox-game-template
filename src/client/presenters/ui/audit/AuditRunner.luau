--!strict
--[[
    Generic scenarios of the runtime UI audit (docs/ui-audit.md): every ScreenGui of the PlayerGui
    is one scenario, cloned into a root Frame of each viewport. Call it from execute_luau (datamodel
    Client) during a playtest:

        local Runner = require(game.Players.LocalPlayer.PlayerScripts.Client.presenters.ui.audit.AuditRunner)
        return Runner.summary(Runner.run())

    A game replaces `scenarios` with its own: force each menu open (`prepare`), and measure a HUD
    that lays itself out from its frame size live (`live`, `setViewport`, `restore`), see +1 Mining
    Power. Excluded from line coverage (engine code).
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Finding = require(Shared.features.ui.audit.Finding)
local RuntimeAudit = require(script.Parent.RuntimeAudit)

local AuditRunner = {}

--- One scenario per ScreenGui (the audit host itself excluded).
function AuditRunner.scenarios(): { RuntimeAudit.Scenario }
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
    local scenarios: { RuntimeAudit.Scenario } = {}
    for _, gui in playerGui:GetChildren() do
        if gui:IsA("ScreenGui") and gui.Name ~= "UiAuditHost" then
            table.insert(scenarios, { name = gui.Name, sources = { gui } })
        end
    end
    return scenarios
end

--- Runs the audit on the four viewports and on a notched landscape phone.
function AuditRunner.run(): RuntimeAudit.Report
    local scenarios = AuditRunner.scenarios()
    local plain = RuntimeAudit.run({ viewports = RuntimeAudit.VIEWPORTS, scenarios = scenarios })
    local notch = RuntimeAudit.run({
        viewports = { Vector2.new(844, 390), Vector2.new(667, 375) },
        scenarios = scenarios,
        insets = { left = 47, right = 47, bottom = 21 },
        label = "notch",
    })
    for _, finding in notch.findings do
        table.insert(plain.findings, finding)
    end
    for _, name in notch.viewports do
        table.insert(plain.viewports, name)
    end
    plain.total += notch.total
    plain.byRule = Finding.countByRule(plain.findings)
    return plain
end

--- The report as JSON text.
function AuditRunner.toJson(report: RuntimeAudit.Report): string
    return HttpService:JSONEncode(report)
end

--- A readable digest: counts per rule, then each unique rule, scenario and path.
function AuditRunner.summary(report: RuntimeAudit.Report, limitPerRule: number?): string
    local limit = limitPerRule or 8
    local groups: { [string]: { count: number, message: string } } = {}
    local order: { string } = {}
    for _, finding in report.findings do
        local scenario = string.match(finding.scope, "^(.-)@") or finding.scope
        local path = string.gsub(finding.path, "Layer_[%w_]+%.", "")
        local key = `{finding.rule} | {scenario} | {path}`
        local group = groups[key]
        if group == nil then
            groups[key] = { count = 1, message = finding.message }
            table.insert(order, key)
        else
            group.count += 1
        end
    end
    local perRule: { [string]: number } = {}
    local lines: { string } = {}
    for _, key in order do
        local rule = string.match(key, "^(%S+)") or key
        local seen = (perRule[rule] or 0) + 1
        perRule[rule] = seen
        if seen <= limit then
            local group = groups[key]
            table.insert(lines, `{key} x{group.count} :: {group.message}`)
        end
    end
    local head = { `total={report.total} unique={#order}` }
    for rule, count in report.byRule do
        table.insert(head, `{rule}={count}/{perRule[rule] or 0}`)
    end
    return table.concat(head, " ") .. "\n" .. table.concat(lines, "\n")
end

return AuditRunner
