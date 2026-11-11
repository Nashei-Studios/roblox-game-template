// Run: node --test tests/tools/notion-mirror.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { isConfigured, main, toProperties, toRecord, upsert } from "../../scripts/notion-mirror.mjs";

const issuePayload = {
  issue: {
    number: 12,
    title: "Add the lobby sign",
    state: "open",
    labels: [{ name: "owner:nande" }],
    assignees: [{ login: "someone" }],
    html_url: "https://example.invalid/issues/12",
    updated_at: "2026-11-11T10:00:00Z",
  },
};

test("an issue maps to a flat record", () => {
  const record = toRecord(issuePayload, "org/game");
  assert.equal(record.ref, "org/game#12");
  assert.equal(record.kind, "issue");
  assert.equal(record.state, "open");
  assert.deepEqual(record.labels, ["owner:nande"]);
});

test("a merged PR is merged, a draft PR is draft, a closed one is closed", () => {
  const pr = (extra) => ({ pull_request: { number: 3, title: "x", state: "open", html_url: "u", updated_at: "t", ...extra } });
  assert.equal(toRecord(pr({ state: "closed", merged: true }), "o/g").state, "merged");
  assert.equal(toRecord(pr({ draft: true }), "o/g").state, "draft");
  assert.equal(toRecord(pr({ state: "closed" }), "o/g").state, "closed");
  assert.equal(toRecord(pr({}), "o/g").kind, "pull request");
});

test("an event without issue or PR gives null", () => {
  assert.equal(toRecord({ zen: "x" }, "o/g"), null);
});

test("labels lose commas so Notion accepts them", () => {
  const props = toProperties({ ...toRecord(issuePayload, "o/g"), labels: ["a,b"] });
  assert.equal(props.Labels.multi_select[0].name, "a b");
});

test("inactive without the secret or the database id", async () => {
  assert.equal(isConfigured({}), false);
  assert.equal(isConfigured({ NOTION_TOKEN: "t" }), false);
  assert.equal(isConfigured({ NOTION_TOKEN: " ", NOTION_DATABASE_ID: "d" }), false);
  const lines = [];
  const fetchImpl = async () => assert.fail("must not call the network when inactive");
  const code = await main({}, () => issuePayload, fetchImpl, (line) => lines.push(line));
  assert.equal(code, 0);
  assert.match(lines[0], /inactive/);
});

function fakeNotion(existing) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, method: init.method, auth: init.headers.Authorization });
    const results = url.endsWith("/query") ? (existing ? [{ id: "page-1" }] : []) : [];
    return { ok: true, status: 200, json: async () => ({ results }) };
  };
  return { calls, fetchImpl };
}

test("upsert creates a page when the Ref is not found", async () => {
  const { calls, fetchImpl } = fakeNotion(false);
  const result = await upsert(fetchImpl, { NOTION_TOKEN: "t", NOTION_DATABASE_ID: "d" }, toRecord(issuePayload, "o/g"));
  assert.equal(result, "created");
  assert.deepEqual(calls.map((c) => `${c.method} ${c.url.replace("https://api.notion.com/v1", "")}`), ["POST /databases/d/query", "POST /pages"]);
});

test("upsert patches the page when the Ref exists", async () => {
  const { calls, fetchImpl } = fakeNotion(true);
  const result = await upsert(fetchImpl, { NOTION_TOKEN: "t", NOTION_DATABASE_ID: "d" }, toRecord(issuePayload, "o/g"));
  assert.equal(result, "updated");
  assert.equal(calls[1].method, "PATCH");
  assert.equal(calls[1].auth, "Bearer t");
});

test("a Notion error surfaces with the status and no token", async () => {
  const fetchImpl = async () => ({ ok: false, status: 401, json: async () => ({}) });
  await assert.rejects(
    upsert(fetchImpl, { NOTION_TOKEN: "secret-value", NOTION_DATABASE_ID: "d" }, toRecord(issuePayload, "o/g")),
    (error) => /HTTP 401/.test(error.message) && !error.message.includes("secret-value"),
  );
});
