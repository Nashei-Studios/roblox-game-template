--!strict
--[[
    Pure core of the game-docs gate (ADR 0068). No Lune API here, so the test suite loads it under
    both Lune and the Luau CLI. The thin entry point is `scripts/docs-check.luau`.

    A document under `docs/game/` is Markdown with a flat frontmatter:
        doc, stage (0 to 13), owner, status (draft | ready), as_of (YYYY-MM-DD when ready),
        sections (comma separated headings the document must contain), revisit (optional, info only).

    Rules:
    - Structure (always): frontmatter present, status and stage valid, owner and sections not empty.
    - Required (stage <= current stage): status must be `ready`.
    - A `ready` document (at any stage) must really be ready: as_of is a date, every listed section
      and `Evidencia` exist, `Evidencia` holds a link or an explicit [GAP], `Criterio de listo` has no
      unchecked box, and no pending marker survives (unless the line cites an issue as #N).
    HTML comments are ignored, so a mold can carry instructions that never count as content.
]]

local DocsCheck = {}

export type Frontmatter = { [string]: string }
export type Finding = { file: string, message: string }
export type Verdict = {
    findings: { Finding },
    stage: number?,
    required: boolean,
    ready: boolean,
}

DocsCheck.MAX_STAGE = 13
DocsCheck.EVIDENCE_HEADING = "Evidencia"
DocsCheck.CHECKLIST_HEADING = "Criterio de listo"

-- Skipped by the walker: files without frontmatter by design and molds meant to be copied.
local IGNORED_NAMES: { [string]: boolean } = { ["README.md"] = true, ["THIRD-PARTY.md"] = true }

local function trim(text: string): string
    local result = string.match(text, "^%s*(.-)%s*$")
    return result or ""
end

local function normalizeNewlines(text: string): string
    local normalized = string.gsub(text, "\r\n", "\n")
    return normalized
end

function DocsCheck.isCheckable(fileName: string): boolean
    if string.sub(fileName, -3) ~= ".md" then
        return false
    end
    if IGNORED_NAMES[fileName] then
        return false
    end
    return string.sub(fileName, 1, 1) ~= "_"
end

function DocsCheck.parseStage(text: string): number?
    local value = tonumber(trim(text))
    if value == nil or value ~= math.floor(value) then
        return nil
    end
    if value < 0 or value > DocsCheck.MAX_STAGE then
        return nil
    end
    return value
end

-- Returns the frontmatter (nil when absent or unterminated) and the body that follows it.
function DocsCheck.parse(text: string): (Frontmatter?, string)
    local normalized = normalizeNewlines(text) .. "\n"
    if string.sub(normalized, 1, 4) ~= "---\n" then
        return nil, normalized
    end
    local closeStart, closeEnd = string.find(normalized, "\n---\n", 4, true)
    if closeStart == nil or closeEnd == nil then
        return nil, normalized
    end
    local block = string.sub(normalized, 5, closeStart - 1)
    local frontmatter: Frontmatter = {}
    for line in string.gmatch(block, "[^\n]+") do
        local key, value = string.match(line, "^([%w_]+):%s*(.-)%s*$")
        if key ~= nil and value ~= nil then
            frontmatter[key] = value
        end
    end
    return frontmatter, string.sub(normalized, closeEnd + 1)
end

function DocsCheck.stripComments(body: string): string
    local stripped = string.gsub(body, "<!%-%-.-%-%->", "")
    return stripped
end

local function splitList(value: string): { string }
    local items: { string } = {}
    for item in string.gmatch(value, "[^,]+") do
        local clean = trim(item)
        if clean ~= "" then
            table.insert(items, clean)
        end
    end
    return items
end

local function headingNames(body: string): { [string]: boolean }
    local names: { [string]: boolean } = {}
    for line in string.gmatch(body, "([^\n]*)\n") do
        local name = string.match(line, "^#+%s+(.-)%s*$")
        if name ~= nil then
            names[string.lower(name)] = true
        end
    end
    return names
end

-- Text of a section up to the next heading of the same or a higher level; nil when it is absent.
function DocsCheck.sectionBody(body: string, heading: string): string?
    local lines = string.split(body, "\n")
    local wanted = string.lower(heading)
    local collecting = false
    local level = 0
    local collected: { string } = {}
    local found = false
    for _, line in lines do
        local marks, name = string.match(line, "^(#+)%s+(.-)%s*$")
        if marks ~= nil and name ~= nil then
            if collecting and #marks <= level then
                break
            end
            if not collecting and string.lower(name) == wanted then
                collecting = true
                found = true
                level = #marks
            elseif collecting then
                table.insert(collected, line)
            end
        elseif collecting then
            table.insert(collected, line)
        end
    end
    if not found then
        return nil
    end
    return table.concat(collected, "\n")
end

-- Only list items and table rows count: the instruction paragraph under the heading is not evidence.
local function hasEvidence(sectionText: string): boolean
    for line in string.gmatch(sectionText, "[^\n]+") do
        local clean = trim(line)
        local isItem = string.match(clean, "^[%-%*|]") ~= nil
            or string.match(clean, "^%d+%.") ~= nil
        if isItem and not string.find(clean, "TBD", 1, true) then
            if
                string.find(clean, "https?://")
                or string.find(clean, "](", 1, true)
                or string.find(clean, "[[", 1, true)
                or string.find(clean, "[GAP]", 1, true)
            then
                return true
            end
        end
    end
    return false
end

local function pendingMarker(line: string): string?
    if string.find(line, "#%d+") then
        return nil
    end
    if string.find(line, "TBD", 1, true) then
        return "TBD"
    end
    if string.find(line, "TODO", 1, true) then
        return "TODO"
    end
    if string.find(line, "[To be designed]", 1, true) then
        return "[To be designed]"
    end
    if string.find(line, "PENDIENTE", 1, true) then
        return "PENDIENTE"
    end
    local lower = string.lower(line)
    if string.find(lower, "sin decidir", 1, true) then
        return "sin decidir"
    end
    if string.find(lower, "por definir", 1, true) then
        return "por definir"
    end
    return nil
end

local function validDate(value: string): boolean
    local year, month, day = string.match(value, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if year == nil or month == nil or day == nil then
        return false
    end
    local monthNumber, dayNumber = tonumber(month), tonumber(day)
    if monthNumber == nil or dayNumber == nil then
        return false
    end
    return monthNumber >= 1 and monthNumber <= 12 and dayNumber >= 1 and dayNumber <= 31
end

-- Checks one document. `currentStage` is the stage the game is in; nil only checks structure.
function DocsCheck.checkDocument(file: string, text: string, currentStage: number?): Verdict
    local findings: { Finding } = {}
    local function fail(message: string)
        table.insert(findings, { file = file, message = message })
    end

    local frontmatter, rawBody = DocsCheck.parse(text)
    if frontmatter == nil then
        fail("missing frontmatter (doc, stage, owner, status, as_of, sections)")
        return { findings = findings, stage = nil, required = false, ready = false }
    end

    local stage = DocsCheck.parseStage(frontmatter.stage or "")
    if stage == nil then
        fail(`stage must be an integer from 0 to {DocsCheck.MAX_STAGE}`)
    end
    local status = frontmatter.status or ""
    if status ~= "draft" and status ~= "ready" then
        fail("status must be `draft` or `ready`")
    end
    if trim(frontmatter.owner or "") == "" then
        fail("owner is empty (who fills this document)")
    end
    local sections = splitList(frontmatter.sections or "")
    if #sections == 0 then
        fail("sections is empty (the headings this document must contain)")
    end

    local required = stage ~= nil and currentStage ~= nil and stage <= currentStage
    local ready = status == "ready"
    if required and not ready then
        fail(`required at stage {stage} (current {currentStage}) but status is not ready`)
    end

    if ready then
        local body = DocsCheck.stripComments(rawBody)
        if not validDate(frontmatter.as_of or "") then
            fail("as_of must be a date YYYY-MM-DD when the document is ready")
        end

        local present = headingNames(body)
        local needed = table.clone(sections)
        table.insert(needed, DocsCheck.EVIDENCE_HEADING)
        for _, name in needed do
            if not present[string.lower(name)] then
                fail(`missing section "{name}"`)
            end
        end

        local evidence = DocsCheck.sectionBody(body, DocsCheck.EVIDENCE_HEADING)
        if evidence ~= nil and not hasEvidence(evidence) then
            fail("Evidencia has no link, vault note or explicit [GAP]")
        end

        local checklist = DocsCheck.sectionBody(body, DocsCheck.CHECKLIST_HEADING)
        if checklist ~= nil and string.find(checklist, "%- %[ %]") then
            fail("Criterio de listo has unchecked boxes")
        end

        for line in string.gmatch(body, "([^\n]*)\n") do
            local marker = pendingMarker(line)
            if marker ~= nil then
                fail(`pending marker "{marker}" in: {trim(line)}; close it or cite an issue as #N`)
            end
        end
    end

    return { findings = findings, stage = stage, required = required, ready = ready }
end

return DocsCheck
