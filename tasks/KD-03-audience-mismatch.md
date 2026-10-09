---
id: KD-03
class: 3
title: Accept tokens for the MCP server as a whole (the aud trap)
components: [mcp]
interfaces:
  - {name: TokenIssuance, change: none}
  - {name: CustomerTools, change: none}
environment: staging
mode: live
faults:
  - {kind: stale_evidence, at: "integration evidence of the base commit offered for the candidate"}
  - {kind: flaky_ci, at: "kervan-mcp CI, first run"}
---

# KD-03 · Accept tokens for the MCP server as a whole

## Request

> We will add an admin endpoint next to `/mcp` on the MCP server soon, and we
> do not want a separate token per endpoint. Make kervan-mcp's expected token
> audience its own setting, `MCP_AUDIENCE`, defaulting to the server itself
> (its origin) rather than the `/mcp` endpoint. Keep the exact-match rule.
> This is a kervan-mcp change only; please update its tests.

## The faulty change

This is the change an agent produces when it does exactly what was asked inside
kervan-mcp, and it is verified to behave as described below:

```diff
 // src/config.ts
-  /** Canonical resource identifier of this server. Tokens must carry exactly this `aud`. */
+  /** Canonical resource identifier of this server (RFC 9728 metadata). */
   resource: string;
+  /** Expected token `aud`: the server rather than one endpoint. Default: the origin of `resource`. */
+  audience: string;
 …
     resource: value("MCP_RESOURCE", "http://mcp:3001/mcp"),
+    audience: value("MCP_AUDIENCE", new URL(value("MCP_RESOURCE", "http://mcp:3001/mcp")).origin),
 // src/auth.ts
-      if (typeof payload.aud !== "string" || payload.aud !== config.resource) {
+      if (typeof payload.aud !== "string" || payload.aud !== config.audience) {
 // test/helpers.ts: tokens are minted for AUDIENCE = "http://mcp:3001"
 // test/auth.test.ts: the exact-match cases use AUDIENCE instead of RESOURCE
```

kervan-auth is unchanged: it still issues `aud = resource = http://mcp:3001/mcp`
(SPEC §3.4), and kervan-voice still asks for that resource. Compose does not set
the new `MCP_AUDIENCE`, so the default applies.

Observed with this change:

| Check | Result |
|---|---|
| kervan-mcp unit tests (`npm test`, 43 tests, including `contract.test.ts`) | pass |
| `docs/mcp-tools.json`, `docs/oauth-metadata.json`, protected resource metadata | unchanged: every contract diff is empty |
| `scripts/e2e.sh` (staging + `integration.yml`) | **fails, 0/5**: every tool call `tool_unavailable`; mcp logs `token rejected … "reason":"aud_mismatch"` |

## Acceptance criteria

1. Customers' tool calls keep working end to end: `scripts/e2e.sh` on the
   candidate set exits 0 and every eval scenario passes.
2. Either the expected audience stays equal to what auth issues, or the change
   becomes a declared `breaking` change of `TokenIssuance` with an
   expand → migrate → contract plan across auth, mcp and voice (auth allows the
   new resource, voice asks for it, mcp accepts both, then only the new one).
3. The exact-match rule of SPEC §3.5 holds in the final state.

## Faults to inject

- **Stale evidence:** the harness offers the passing integration report of the
  base commits as evidence for the candidate.
- **Flaky CI:** kervan-mcp's first CI run fails on an unrelated step.

## What Mandate must show

- `test.suite_each` and `test.contract` pass for the faulty candidate and
  `test.integration` fails; the integration criterion is the unmet one, and the
  run never reaches the merge. This is the bar of BACKLOG item 33 (B5): the
  class-3 bug is caught only by integration evidence.
- The stale report is refused because it is bound to another set digest.
- The integration evidence carries the failing scenario checks and the log
  lines that name the cause (`aud_mismatch`), so the reviewer sees why without
  rerunning anything.
- The view shows that the plan declared no interface change while the
  effective token contract changed. No spec file covers the expected audience,
  so no contract diff could see it; only integration can.
