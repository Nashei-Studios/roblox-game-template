# RULES: src/shared

Owner: `owner:victor` and the agents working under him. Maps to `ReplicatedStorage/Shared` through Rojo.

## Who touches what
- Agents and Victor: everything here. This folder is the contract between server and client, so changes to `ports/`, `net/` or types go through the orchestrating agent or Victor.
- Nande and Leon: read only.

## Allowed
- Pure logic that loads under Lune, ports (types), feature modules, remote schema.

## Forbidden
- Engine calls (`game:GetService`) in pure modules.
- Editing files under `net/generated/`: regenerate them from `net/schema.zap`.
- Editing these files from Studio.

## Handoff
Post a comment on the pinned **Agent Board** issue: what is done, what is left, the branch or PR, and an `@mention` of the next owner (`@vruizz22`, `@<nande-gh>`, `@<leon-gh>`, or the agent role). Add the `handoff` label to the issue you pass on. Do not message anyone elsewhere; the board is the record. Method and labels: `docs/team-workflow.md`.
