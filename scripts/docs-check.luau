--!strict
--[[
    Game-docs gate: `lune run scripts/docs-check [stage] [--dir <path>]` (ADR 0068).
    Reads every Markdown document under docs/game/ (default) and reports what is missing for the
    current stage. The stage is the argument, or the integer in docs/game/STAGE (0 when absent).
    - A document whose `stage` is at or below the current stage must be `ready` and really filled.
    - A `ready` document that still holds a TBD, an unchecked box or no evidence always fails.
    - Documents of later stages are listed as pending and never fail the run.
    Exit code 1 on any finding. The rules live in scripts/DocsCheck.luau (pure, unit tested).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local DocsCheck = require("./DocsCheck")

local DEFAULT_DIR = "docs/game"

local function collect(directory: string, out: { string })
    for _, name in fs.readDir(directory) do
        local path = `{directory}/{name}`
        if fs.isDir(path) then
            collect(path, out)
        elseif DocsCheck.isCheckable(name) then
            table.insert(out, path)
        end
    end
end

local directory = DEFAULT_DIR
local stageArgument: string? = nil
local arguments = process.args
local index = 1
while index <= #arguments do
    local argument = arguments[index]
    if argument == "--dir" then
        index += 1
        directory = arguments[index] or DEFAULT_DIR
    else
        stageArgument = argument
    end
    index += 1
end

local stageSource = "argument"
local stage: number? = nil
if stageArgument ~= nil then
    stage = DocsCheck.parseStage(stageArgument)
    if stage == nil then
        print(`FAIL  stage "{stageArgument}" is not an integer from 0 to {DocsCheck.MAX_STAGE}`)
        process.exit(1)
    end
else
    stageSource = `{directory}/STAGE`
    local stagePath = `{directory}/STAGE`
    if fs.isFile(stagePath) then
        stage = DocsCheck.parseStage(fs.readFile(stagePath))
        if stage == nil then
            print(`FAIL  {stagePath} must hold an integer from 0 to {DocsCheck.MAX_STAGE}`)
            process.exit(1)
        end
    else
        stage = 0
    end
end

if not fs.isDir(directory) then
    print(`FAIL  {directory} does not exist`)
    process.exit(1)
end

local files: { string } = {}
collect(directory, files)
table.sort(files)

local problems, requiredCount, readyCount, pendingCount = 0, 0, 0, 0
for _, path in files do
    local verdict = DocsCheck.checkDocument(path, fs.readFile(path), stage)
    if verdict.required then
        requiredCount += 1
    end
    if verdict.ready and #verdict.findings == 0 then
        readyCount += 1
    elseif verdict.stage ~= nil and not verdict.required and #verdict.findings == 0 then
        pendingCount += 1
        print(`PEND  {path} (stage {verdict.stage})`)
    end
    for _, finding in verdict.findings do
        problems += 1
        print(`FAIL  {finding.file}: {finding.message}`)
    end
end

print(
    `docs-check: stage {stage} ({stageSource}), {#files} documents, {requiredCount} required, `
        .. `{readyCount} ready, {pendingCount} pending, {problems} problems`
)
if problems > 0 then
    process.exit(1)
end
