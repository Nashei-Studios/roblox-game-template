--!strict
local DocsCheck = require("../../scripts/DocsCheck")
local harness = require("../harness")

local function document(overrides: { [string]: string }, body: string?): string
    local fields: { [string]: string } = {
        doc = "sample",
        stage = "2",
        owner = "agente",
        status = "ready",
        as_of = "2026-11-12",
        sections = "Respuestas, Criterio de listo",
    }
    for key, value in overrides do
        fields[key] = value
    end
    local lines = { "---" }
    for _, key in { "doc", "stage", "owner", "status", "as_of", "sections" } do
        table.insert(lines, `{key}: {fields[key]}`)
    end
    table.insert(lines, "---")
    table.insert(lines, body or table.concat({
        "# Sample",
        "",
        "## Respuestas",
        "",
        "1. Vaciar el lago en cinco verbos.",
        "",
        "## Criterio de listo",
        "",
        "- [x] Hecho.",
        "",
        "## Evidencia",
        "",
        "- [nota](https://example.com/nota)",
        "",
    }, "\n"))
    return table.concat(lines, "\n")
end

local function messages(text: string, stage: number?): string
    local verdict = DocsCheck.checkDocument("sample.md", text, stage)
    local all: { string } = {}
    for _, finding in verdict.findings do
        table.insert(all, finding.message)
    end
    return table.concat(all, " | ")
end

local function contains(haystack: string, needle: string): boolean
    return string.find(haystack, needle, 1, true) ~= nil
end

return function(suite: harness.Harness)
    suite:test("a filled ready document passes", function()
        harness.equal(messages(document({}), 2), "")
    end)

    suite:test("a draft document of a later stage is pending and does not fail", function()
        local text = document({ status = "draft", stage = "5" }, "# Sample\nTBD\n")
        local verdict = DocsCheck.checkDocument("sample.md", text, 2)
        harness.equal(#verdict.findings, 0)
        harness.isFalse(verdict.required)
    end)

    suite:test("a draft document of the current stage fails as required", function()
        local text = document({ status = "draft", stage = "2" }, "# Sample\nTBD\n")
        harness.isTrue(contains(messages(text, 2), "required at stage 2"))
        harness.isTrue(DocsCheck.checkDocument("sample.md", text, 2).required)
    end)

    suite:test("a stage at or below the current one is required, above is not", function()
        local text = document({ status = "draft", stage = "3" }, "# Sample\n")
        harness.isTrue(DocsCheck.checkDocument("sample.md", text, 3).required)
        harness.isFalse(DocsCheck.checkDocument("sample.md", text, 2).required)
    end)

    suite:test("a ready document with a pending marker fails", function()
        local body =
            "## Respuestas\n1. TBD\n## Criterio de listo\n- [x] ok\n## Evidencia\n- [a](https://a.b)\n"
        harness.isTrue(contains(messages(document({}, body), 2), 'pending marker "TBD"'))
    end)

    suite:test("a marker that cites an issue is allowed", function()
        local body =
            "## Respuestas\n1. por definir, ver #12\n## Criterio de listo\n- [x] ok\n## Evidencia\n- [a](https://a.b)\n"
        harness.equal(messages(document({}, body), 2), "")
    end)

    suite:test("a ready document without evidence links fails", function()
        local body =
            "## Respuestas\n1. algo\n## Criterio de listo\n- [x] ok\n## Evidencia\n\nLo vi en un video.\n"
        harness.isTrue(contains(messages(document({}, body), 2), "Evidencia has no link"))
    end)

    suite:test("an explicit GAP counts as evidence, an instruction paragraph does not", function()
        local gap =
            "## Respuestas\n1. algo\n## Criterio de listo\n- [x] ok\n## Evidencia\n- [GAP] no se midió\n"
        harness.equal(messages(document({}, gap), 2), "")
        local paragraph =
            "## Respuestas\n1. algo\n## Criterio de listo\n- [x] ok\n## Evidencia\nUn [GAP] explícito vale.\n"
        harness.isTrue(contains(messages(document({}, paragraph), 2), "Evidencia has no link"))
    end)

    suite:test("unchecked boxes in the checklist fail", function()
        local body =
            "## Respuestas\n1. algo\n## Criterio de listo\n- [ ] falta\n## Evidencia\n- [a](https://a.b)\n"
        harness.isTrue(contains(messages(document({}, body), 2), "unchecked boxes"))
    end)

    suite:test("a missing declared section fails, case insensitive", function()
        local body = "## respuestas\n1. algo\n## Evidencia\n- [a](https://a.b)\n"
        harness.isTrue(
            contains(messages(document({}, body), 2), 'missing section "Criterio de listo"')
        )
    end)

    suite:test("HTML comments never count as content", function()
        local body =
            "## Respuestas\n<!-- TBD instrucciones -->\n1. algo\n## Criterio de listo\n- [x] ok\n## Evidencia\n- [a](https://a.b)\n"
        harness.equal(messages(document({}, body), 2), "")
    end)

    suite:test("frontmatter problems are reported even without a stage", function()
        harness.isTrue(contains(messages("# Sin frontmatter\n", nil), "missing frontmatter"))
        harness.isTrue(
            contains(messages(document({ stage = "14" }), nil), "stage must be an integer")
        )
        harness.isTrue(contains(messages(document({ status = "done" }), nil), "status must be"))
        harness.isTrue(contains(messages(document({ owner = "" }), nil), "owner is empty"))
        harness.isTrue(contains(messages(document({ sections = "" }), nil), "sections is empty"))
        harness.isTrue(
            contains(messages(document({ as_of = "ayer" }), nil), "as_of must be a date")
        )
    end)

    suite:test("CRLF files parse like LF files", function()
        local crlf = string.gsub(document({}), "\n", "\r\n")
        harness.equal(messages(crlf, 2), "")
    end)

    suite:test("parseStage accepts 0 to 13 only", function()
        harness.equal(DocsCheck.parseStage(" 0\n"), 0)
        harness.equal(DocsCheck.parseStage("13"), 13)
        harness.equal(DocsCheck.parseStage("14"), nil)
        harness.equal(DocsCheck.parseStage("-1"), nil)
        harness.equal(DocsCheck.parseStage("2.5"), nil)
        harness.equal(DocsCheck.parseStage("dos"), nil)
    end)

    suite:test("the walker skips READMEs, third-party notices and copy molds", function()
        harness.isTrue(DocsCheck.isCheckable("concept.md"))
        harness.isFalse(DocsCheck.isCheckable("README.md"))
        harness.isFalse(DocsCheck.isCheckable("THIRD-PARTY.md"))
        harness.isFalse(DocsCheck.isCheckable("_sistema.md"))
        harness.isFalse(DocsCheck.isCheckable("STAGE"))
        harness.isFalse(DocsCheck.isCheckable("economy.csv"))
    end)
end
