--!strict
--[[
    Minimal test harness for Lune. Assertions raise errors; the runner catches them.
]]

export type TestFn = () -> ()

export type Harness = {
    test: (self: Harness, name: string, fn: TestFn) -> (),
    run: (self: Harness) -> (number, number),
}

type TestCase = { name: string, fn: TestFn }

local harness = {}

function harness.equal<T>(actual: T, expected: T, label: string?)
    if actual ~= expected then
        error(`{label or "values"} differ: expected {tostring(expected)}, got {tostring(actual)}`, 2)
    end
end

function harness.isTrue(condition: boolean, label: string?)
    if not condition then
        error(`{label or "condition"} expected to be true`, 2)
    end
end

function harness.isFalse(condition: boolean, label: string?)
    if condition then
        error(`{label or "condition"} expected to be false`, 2)
    end
end

function harness.new(): Harness
    local cases: { TestCase } = {}
    local self: Harness
    self = {
        test = function(_self: Harness, name: string, fn: TestFn)
            table.insert(cases, { name = name, fn = fn })
        end,
        run = function(_self: Harness): (number, number)
            local passed, failed = 0, 0
            for _, case in cases do
                local ok, message = pcall(case.fn)
                if ok then
                    passed += 1
                    print(`  PASS  {case.name}`)
                else
                    failed += 1
                    print(`  FAIL  {case.name}\n        {tostring(message)}`)
                end
            end
            return passed, failed
        end,
    }
    return self
end

return harness
